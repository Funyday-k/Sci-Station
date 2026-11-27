"use strict";
(() => {
  const $ = id => document.getElementById(id);
  const activeReportStatuses = new Set(["drafting", "reviewing", "revising"]);
  const reportLabels = {
    drafting: "正在起草",
    reviewing: "正在复核",
    revising: "正在根据复核意见修订",
    ready: "报告已生成",
    failed: "报告生成失败",
  };
  const stances = [
    ["support", "认同"],
    ["oppose", "不认同"],
    ["qualified", "有保留"],
    ["undecided", "尚未决定"],
  ];

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  }

  function name(seat, session) {
    return window.RoundtableIdentity.seatName(seat, session);
  }

  function historicalName(turn, round, session) {
    const identity = window.RoundtableIdentity;
    return identity.modelByline(identity.sourceIdentity(turn.seat, session, round, turn));
  }

  function publishedTurns(session) {
    const rounds = session?.rounds || [];
    const visible = session?.status === "running" ? rounds.slice(0, -1) : rounds;
    return visible.flatMap(round => (round.turns || []).flatMap((turn, index) =>
      turn.status === "done" && turn.text?.trim()
        ? [{ round: round.number, index: index + 1, turn }]
        : [],
    ));
  }

  function messageId(number, seat) {
    return `round-${number}-${seat}`;
  }

  function citation(round, id) {
    return `${round}\u0000${id}`;
  }

  function findTurn(session, number, seat, model) {
    return publishedTurns(session).find(source =>
      source.round === Number(number) &&
      source.turn.seat === seat &&
      (model === undefined || source.turn.model === model),
    );
  }

  function linkSources(root, session, navigate, changes = null) {
    const report = changes !== null;
    const sources = new Map();
    for (const { round, index, turn } of publishedTurns(session)) {
      const id = messageId(round, turn.seat);
      const source = { id, label: `第 ${round} 轮 · ${historicalName(turn, round, session)}` };
      sources.set(citation(round, turn.seat), source);
      if (turn.model) sources.set(citation(round, `${turn.seat}/${turn.model}`), source);
      if (report) sources.set(`R${round}-T${index}`, source);
    }
    if (report) {
      const boardHeading = [...root.children].find(node =>
        node.tagName === "H4" && node.textContent.trim() === "主持人议题板笔记与批注");
      const notes = boardHeading?.nextElementSibling;
      if (notes?.tagName === "UL") {
        for (const item of notes.children) {
          const id = /^\[(B[1-9]\d*)\]/.exec(item.textContent.trim())?.[1];
          if (id) sources.set(id, {boardNote: item, label:"主持人批注"});
        }
      }
      for (const round of session.rounds || []) {
        if (round.note) sources.set(`H${round.number}`, {
          id: `round-${round.number}-host`,
          label: `第 ${round.number} 轮 · 主持人`,
        });
      }
      for (const [index, item] of (session.agenda || []).entries()) sources.set(`A${index + 1}`, {
        agenda: item.id,
        label: item.title,
      });
      for (const [index, change] of changes.entries()) sources.set(`F${index + 1}`, {
        change,
        label: change.path ? `文件修订 ${change.path}` : "文件修订",
      });
    }
    if (!sources.size) return;
    const pattern = /\[(?:R([1-9]\d*)\s*·\s*([^\]\r\n]+)|((?:R[1-9]\d*-T|[ABHF])[1-9]\d*))\]/g;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const parent = node.parentElement;
        if (parent.closest("a, button, code, pre, .katex") || (!report && !parent.closest(".message-body")))
          return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    const replacements = [];
    while (walker.nextNode()) {
      const node = walker.currentNode;
      const value = node.nodeValue;
      let start = 0;
      let fragment;
      for (const match of value.matchAll(pattern)) {
        const source = sources.get(match[3] || citation(match[1], match[2].trim()));
        if (!source || source.boardNote?.contains(node)) continue;
        fragment ||= document.createDocumentFragment();
        fragment.append(value.slice(start, match.index));
        const button = element("button", "meeting-citation", match[0]);
        button.type = "button";
        button.setAttribute("aria-label", `${match[0]} · 查看${source.label}`);
        button.addEventListener("click", () => {
          if (source.boardNote) {
            source.boardNote.tabIndex = -1;
            source.boardNote.focus();
            source.boardNote.scrollIntoView({block:"center"});
          } else navigate(source, session.id, button);
        });
        fragment.append(button);
        start = match.index + match[0].length;
      }
      if (fragment) {
        fragment.append(value.slice(start));
        replacements.push([node, fragment]);
      }
    }
    for (const [node, fragment] of replacements) node.replaceWith(fragment);
  }

  function foldCitationAppendix(content) {
    const heading = [...content.children].find(node =>
      node.tagName === "H4" && node.textContent.trim() === "引用原文",
    );
    if (!heading) return;
    const details = element("details", "meeting-report-citations");
    const summary = element("summary", "", heading.textContent);
    const body = element("div", "meeting-report-citations-body");
    while (heading.nextElementSibling && !/^H[1-4]$/.test(heading.nextElementSibling.tagName))
      body.append(heading.nextElementSibling);
    details.append(summary, body);
    heading.replaceWith(details);
  }

  function collectPoints(published) {
    const points = new Map();
    const affiliations = [];
    for (const source of published) {
      const { turn } = source;
      for (const point of turn.points || []) {
        if (point.id && point.text && !points.has(point.id))
          points.set(point.id, { id: point.id, text: point.text, source, positions: new Map() });
      }
      for (const position of turn.positions || []) {
        if (stances.some(([value]) => value === position.stance))
          affiliations.push({ position, source });
      }
    }
    for (const { position, source } of affiliations)
      points.get(position.point_id)?.positions.set(source.turn.seat, { ...position, source });
    return [...points.values()];
  }

  function renderPoint(point, session, jump, isExpanded) {
    const detail = element("details", "meeting-opinion");
    detail.dataset.point = point.id;
    detail.open = isExpanded;
    const summary = element("summary", "", point.text);
    const counts = new Map();
    for (const position of point.positions.values()) counts.set(position.stance, (counts.get(position.stance) || 0) + 1);
    const tally = stances.filter(([value]) => counts.has(value)).map(([value, label]) => label + " " + counts.get(value));
    if (tally.length) summary.append(element("span", "point-tally", tally.join(" · ")));
    detail.append(summary);
    const entries = element("dl", "meeting-opinion-positions");
    const sourceButton = source => {
      const { round, turn } = source;
      const author = historicalName(turn, round, session);
      const button = element("button", "meeting-citation", `${author} · 第 ${round} 轮 ↗`);
      button.type = "button";
      button.dataset.citation = `${round}:${turn.seat}:${turn.model || ""}`;
      button.setAttribute("aria-label", `查看 ${author} 第 ${round} 轮发言`);
      button.addEventListener("click", () => jump(round, turn.seat, turn.model));
      return button;
    };
    const add = (label, rows) => {
      if (!rows.length) return;
      const normalized = label === "提出人" ? "proposer" : label === "认同" ? "support" : label === "不认同" ? "oppose" : "other";
      const heading = element("dt", `meeting-opinion-group meeting-opinion-group-${normalized}`, label);
      const list = element("ul");
      for (const row of rows) {
        const li = element("li");
        li.append(row);
        list.append(li);
      }
      const value = element("dd");
      value.append(list);
      value.className = `meeting-opinion-group-value meeting-opinion-group-value-${normalized}`;
      entries.append(heading, value);
    };
    add("提出人", [sourceButton(point.source)]);
    for (const [stance, label] of stances) {
      const rows = [];
      for (const position of point.positions.values()) {
        if (position.stance !== stance) continue;
        const row = document.createDocumentFragment();
        row.append(sourceButton(position.source));
        if (position.reason) row.append(element("span", "meeting-opinion-reason", position.reason));
        rows.push(row);
      }
      add(label, rows);
    }
    const members = session.members?.length ? session.members.map(member => member.id) : session.seats || [];
    const unrecorded = members.filter(seat => seat !== point.source.turn.seat && !point.positions.has(seat));
    add("未表态", unrecorded.length ? [element("span", "", unrecorded.map(seat => name(seat, session)).join("、"))] : []);
    detail.append(entries);
    return detail;
  }

  function reviewDescription(report, session) {
    const identity = window.RoundtableIdentity;
    const describe = (seat, model) => seat ? identity.modelByline(identity.sourceIdentity(seat, session, 0, {model})) : model;
    const author = describe(report.author_seat, report.author_model);
    const reviewer = describe(report.reviewer_seat, report.reviewer_model);
    const lines = [];
    if (author) lines.push(`起草 ${author}`);
    if (reviewer) lines.push(`复核 ${reviewer}`);
    if (report.review_mode === "same_model") lines.push("复核席与起草席使用同一模型");
    if (report.review_mode === "self") lines.push("由起草席自检");
    return lines.join(" ｜ ");
  }

  function mount({ fileChanges, openRevision, write, reveal, hasUnsentNote }) {
    const toolbar = $("meeting-report");
    const dialog = $("meeting-report-dialog");
    const title = $("meeting-report-title");
    const status = $("meeting-report-status");
    const confirm = $("meeting-report-confirm");
    const confirmation = $("meeting-report-confirmation");
    const note = $("meeting-report-unsent");
    const retry = $("meeting-report-retry");
    const download = $("meeting-report-download");
    const error = $("meeting-report-error");
    const meta = $("meeting-report-meta");
    const content = $("meeting-report-content");
    const reviewNotes = $("meeting-report-review");
    const reviewNotesBody = $("meeting-report-review-notes");
    const reportScroll = $("meeting-report-scroll");
    const returnToReport = element("button", "button secondary meeting-report-return", "返回报告此处");
    returnToReport.type = "button";
    returnToReport.hidden = true;
    document.body.append(returnToReport);
    const guidance = element("details", "meeting-report-guidance");
    const guidanceList = element("ul", "meeting-report-guidance-list");
    guidance.hidden = true;
    guidance.append(
      element("summary", "", "报告指引来源"),
      element("p", "quiet", "本次报告保存的扩展指引，供起草、复核与修订使用。"),
      guidanceList,
    );
    reviewNotes.after(guidance);
    const opinions = $("meeting-opinions");
    const opinionToggleCount = $("opinions-toggle-count");
    const opinionCount = $("meeting-opinions-count");
    const opinionList = $("meeting-opinions-list");
    const opinionEmpty = $("meeting-opinions-empty");
    let session;
    let busy = false;
    let requestError = "";
    let pointsKey = "";
    let reportKey = "";
    let reportBodyKey = "";
    let guidanceKey = "";
    let hasPublished = false;
    let returnPoint = null;

    function setOpinionsOpen(open, { restoreFocus = false } = {}) {
      if (!opinions || !session) return;
      if (open) {
        if (opinionList.children.length === 1) opinionList.firstElementChild.open = true;
        if (window.RoundtableRoomPanel) window.RoundtableRoomPanel.openTab("opinions", { focus: restoreFocus });
        else opinions.hidden = false;
      } else {
        if (window.RoundtableRoomPanel) window.RoundtableRoomPanel.setTab("chat", { focus: restoreFocus });
        else opinions.hidden = true;
      }
    }

    function clearReturnPoint() {
      returnPoint = null;
      returnToReport.hidden = true;
    }

    function rememberCitation(sessionId, button) {
      if (!button || !dialog.open || !dialog.contains(button)) return;
      returnPoint = { sessionId, button, scrollTop: reportScroll.scrollTop };
      returnToReport.hidden = false;
    }

    function navigate(source, sessionId, citationButton = null) {
      if (session?.id !== sessionId) return false;
      if (source.change) {
        if (!source.change.path) {
          requestError = "这份历史记录缺少文件路径，无法定位修订。";
          draw();
          return false;
        }
        rememberCitation(sessionId, citationButton);
        dialog.close();
        openRevision(source.change);
        return true;
      }
      const target = source.agenda
        ? [...$("meeting-agenda").querySelectorAll("[data-agenda-item]")].find(row => row.dataset.agendaItem === source.agenda)
        : $(source.id);
      if (!target) return false;
      rememberCitation(sessionId, citationButton);
      if (dialog.open) dialog.close();
      reveal(target, Boolean(source.agenda));
      return true;
    }

    returnToReport.addEventListener("click", () => {
      const point = returnPoint;
      if (!point || point.sessionId !== session?.id || !point.button.isConnected) {
        clearReturnPoint();
        return;
      }
      returnPoint = null;
      returnToReport.hidden = true;
      dialog.showModal();
      reportScroll.scrollTop = point.scrollTop;
      requestAnimationFrame(() => {
        if (session?.id !== point.sessionId || !dialog.open || !point.button.isConnected) return;
        point.button.focus({ preventScroll: true });
      });
    });

    function jump(round, seat, model) {
      if (!findTurn(session, round, seat, model)) return false;
      setOpinionsOpen(false, { restoreFocus: false });
      return navigate({ id: messageId(round, seat) }, session.id);
    }

    function drawGuidance(snapshot) {
      const plugins = Array.isArray(snapshot)
        ? snapshot.filter(plugin => typeof plugin?.report_guidance === "string" && plugin.report_guidance.trim())
        : [];
      const key = JSON.stringify(plugins);
      if (key === guidanceKey) return;
      guidanceKey = key;
      guidance.hidden = !plugins.length;
      guidanceList.replaceChildren(...plugins.map(plugin => {
        const item = element("li");
        const title = plugin.name || plugin.id;
        const identity = [plugin.id !== title ? plugin.id : "", plugin.version ? `版本 ${plugin.version}` : ""]
          .filter(Boolean).join(" · ");
        const label = element("div", "meeting-report-guidance-label");
        label.append(element("strong", "", title));
        if (identity) label.append(element("span", "", identity));
        item.append(label, element("p", "meeting-report-guidance-text", plugin.report_guidance));
        return item;
      }));
    }

    function draw() {
      const closed = session?.status === "closed";
      const report = session?.report;
      const eligible = Boolean(session && hasPublished && session.status !== "running" &&
        session.agenda_draft_status !== "drafting");
      toolbar.hidden = !session || (!closed && !hasPublished);
      toolbar.disabled = busy || (!closed && !eligible);
      const label = closed ? "阅读报告" : "完成会议";
      toolbar.textContent = label;
      toolbar.title = closed ? reportLabels[report?.status] || label :
        !eligible ? "本轮公开后可完成会议" : label;
      if (!dialog.open) return;

      title.textContent = closed ? "会议报告" : label;
      confirmation.hidden = closed;
      note.hidden = !hasUnsentNote();
      confirm.hidden = closed;
      confirm.disabled = busy || !eligible;
      const previous = document.activeElement;
      retry.hidden = report?.status !== "failed";
      retry.disabled = busy;
      const available = Boolean(report?.markdown && !activeReportStatuses.has(report.status));
      download.hidden = !available;
      const copy = $("meeting-report-copy");
      copy.hidden = !available;
      download.textContent = report?.status === "failed" ? "下载草稿" : "下载 Markdown";
      if (available) download.href = `/api/studio/sessions/${encodeURIComponent(session.id)}/report.md`;
      status.hidden = !closed;
      status.dataset.reportStatus = report?.status || "";
      const statusText = closed ? reportLabels[report?.status] || "暂无报告" : "";
      if (status.textContent !== statusText) status.textContent = statusText;
      const description = report ? reviewDescription(report, session) : "";
      meta.textContent = description;
      meta.hidden = !description;
      const message = requestError || (report?.status === "failed" ? report.error : "");
      error.textContent = message || "";
      error.hidden = !message;
      content.hidden = !available;
      content.classList.toggle("meeting-report-draft", report?.status === "failed");
      const bodyKey = JSON.stringify([session.id, available ? report.markdown : ""]);
      if (bodyKey !== reportBodyKey) {
        reportBodyKey = bodyKey;
        if (available) {
          window.SciMarkdown.render(content, report.markdown, {headingShift:2});
          window.SciMarkdown.bindCopy(copy, report.markdown);
          foldCitationAppendix(content);
          linkSources(content, session, navigate, fileChanges(session));
        } else {
          content.replaceChildren();
          copy.onclick = null;
        }
        $("meeting-report-scroll").scrollTop = 0;
      }
      const review = report?.review_notes;
      reviewNotes.hidden = !closed || typeof review !== "string" || !review.trim();
      const reviewText = reviewNotes.hidden ? "" : review;
      if (reviewNotesBody.textContent !== reviewText) {
        reviewNotesBody.textContent = reviewText;
        if (reviewText) linkSources(reviewNotesBody, session, navigate, fileChanges(session));
      }
      drawGuidance(closed ? report?.plugin_guidance : null);
      if ((previous === confirm && confirm.hidden) || (previous === retry && retry.hidden))
        $("meeting-report-close").focus({ preventScroll: true });
    }

    function update(next) {
      const sameSession = session?.id === next?.id;
      if (!sameSession) {
        if (dialog.open) dialog.close();
        clearReturnPoint();
        setOpinionsOpen(false, { restoreFocus: false });
        requestError = "";
        reportBodyKey = "";
        pointsKey = "";
        reportKey = "";
        reviewNotes.open = false;
        guidance.open = false;
      }
      session = next;
      const published = publishedTurns(next);
      hasPublished = published.length > 0;
      if (!next) {
        if (opinionToggleCount) opinionToggleCount.textContent = "0";
        if (opinionCount) opinionCount.textContent = "";
      } else {
        const points = collectPoints(published);
        const key = JSON.stringify([next.id, next.members, next.seats, points.map(point => [
          point.id, point.text, point.source.round, point.source.turn.seat, point.source.turn.model,
          [...point.positions].map(([seat, position]) => [seat, position.stance, position.reason, position.source.round, position.source.turn.model]),
        ])]);
        if (key !== pointsKey) {
          pointsKey = key;
          const expanded = sameSession
            ? new Set([...opinionList.querySelectorAll("details[open]")].map(el => el.dataset.point))
            : new Set();
          const focused = opinionList.contains(document.activeElement)
            ? { point: document.activeElement.closest(".meeting-opinion")?.dataset.point,
                citation: document.activeElement.dataset.citation }
            : null;
          if (opinionCount) opinionCount.textContent = `${points.length} 项`;
          if (opinionToggleCount) opinionToggleCount.textContent = String(points.length);
          opinionEmpty.hidden = points.length > 0;
          opinionList.hidden = !points.length;
          opinionList.replaceChildren(...points.map(point => renderPoint(point, next, jump, expanded.has(point.id))));
          if (focused) {
            const point = [...opinionList.querySelectorAll(".meeting-opinion")].find(item => item.dataset.point === focused.point);
            const target = focused.citation
              ? [...(point?.querySelectorAll("[data-citation]") || [])].find(item => item.dataset.citation === focused.citation)
              : point?.querySelector("summary");
            target?.focus({ preventScroll: true });
          }
        }
      }
      const key = JSON.stringify([next?.id, next?.status, next?.agenda_draft_status, next?.report, hasPublished]);
      if (key === reportKey) return;
      reportKey = key;
      draw();
    }

    async function request(action) {
      if (!session || busy) return;
      if (action === "finish" &&
          (!hasPublished || ["running", "closed"].includes(session.status) || session.agenda_draft_status === "drafting")) return;
      if (action === "retry" && session.report?.status !== "failed") return;
      const id = session.id;
      const payload = {
        action,
        expected_round: session.rounds?.length || 0,
        agenda_version: session.agenda_version || 0,
      };
      if (action === "retry") payload.attempt = session.report.attempt;
      requestError = "";
      setBusy(true);
      try {
        await write(id, payload);
      } catch (failure) {
        if (session?.id === id) requestError = failure.message || String(failure);
      } finally {
        setBusy(false);
      }
    }

    function setBusy(value) {
      if (busy === value) return;
      busy = value;
      draw();
    }

    toolbar.addEventListener("click", () => {
      clearReturnPoint();
      requestError = "";
      dialog.showModal();
      draw();
      $("meeting-report-close").focus({ preventScroll: true });
    });
    $("meeting-report-close").addEventListener("click", () => dialog.close());
    confirm.addEventListener("click", () => request("finish"));
    retry.addEventListener("click", () => request("retry"));
    window.RoundtableReferences = Object.freeze({ jump });
    window.RoundtableOpinions = Object.freeze({
      open: options => setOpinionsOpen(true, options),
      close: options => setOpinionsOpen(false, options),
    });
    return {
      update,
      setBusy,
      isOpen: () => dialog.open,
      close: () => {
        clearReturnPoint();
        if (dialog.open) dialog.close();
      },
      linkStatements: (root, current) => linkSources(root, current, navigate),
    };
  }

  window.RoundtableReport = Object.freeze({
    mount,
    isWorking: report => activeReportStatuses.has(report?.status),
  });
})();
