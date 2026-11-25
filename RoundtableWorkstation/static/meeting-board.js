"use strict";
(() => {
  const fallbackModules = [
    { id: "agenda", kind: "agenda", title: "会议议程" },
    { id: "materials", kind: "materials", title: "会议材料" },
    { id: "positions", kind: "positions", title: "讨论观点与立场" },
  ];
  const stanceLabels = {
    support: "支持",
    oppose: "反对",
    qualified: "有保留",
    undecided: "尚未决定",
  };
  const materialLabels = {
    text: "已提取文字",
    failed: "文字提取失败",
    original_only: "仅原件",
    no_extractable_text: "无可提取文字",
  };
  const {canPreview, originalHref: materialHref, downloadOriginal} = window.RoundtableMaterials;
  const drafting = new Set(["pending", "drafting"]);

  function element(tag, suffix, value) {
    const node = document.createElement(tag);
    if (suffix) node.className = `board-${suffix}`;
    if (value) node.textContent = value;
    return node;
  }

  function anchor(node, key) {
    node.dataset.boardAnchor = key;
    return node;
  }

  function action(label, key, callback, suffix = "action") {
    const button = element("button", suffix, label);
    button.type = "button";
    button.dataset.boardFocus = key;
    button.addEventListener("click", () => callback(button));
    return button;
  }

  function seatName(seat, session) {
    if (seat === "user") return "主持人";
    return window.RoundtableIdentity?.seatName?.(seat, session) ||
      session.members?.find(member => member.id === seat)?.label || seat;
  }

  function historicalName(seat, session, round, source) {
    const identity = window.RoundtableIdentity;
    const saved = identity?.sourceIdentity?.(seat, session, round, source);
    return saved ? identity.modelByline(saved) : seatName(seat, session);
  }

  function editControls(editor, spec, controls, content) {
    if (!editor?.canEdit(spec.key)) return;
    const {trigger, form} = editor.create(spec);
    controls.append(trigger);
    content.append(form);
  }

  function editGroup(...controls) {
    const group = element("div", "edit-actions");
    group.append(...controls.filter(Boolean));
    return group;
  }

  function contextFor(session) {
    const rounds = session.rounds || [];
    const published = session.status === "running" ? rounds.slice(0, -1) : rounds;
    const sources = new Map();
    const points = new Map();
    const positions = [];
    for (const round of published) {
      for (const turn of round.turns || []) {
        if (turn.status !== "done" || !turn.text?.trim()) continue;
        const source = {round: round.number, seat: turn.seat, model: turn.model};
        sources.set(JSON.stringify([round.number, turn.seat]), source);
        for (const point of turn.points || []) {
          if (point.id && point.text?.trim() && !points.has(point.id))
            points.set(point.id, {...point, source, positions: new Map()});
        }
        for (const position of turn.positions || []) {
          if (Object.hasOwn(stanceLabels, position.stance))
            positions.push({...position, source});
        }
      }
    }
    for (const position of positions)
      points.get(position.point_id)?.positions.set(position.source.seat, position);
    const members = session.members?.length ? session.members.map(member => member.id) : session.seats || [];
    return {members, points: [...points.values()], sources};
  }

  function projectPoints({members, points}, session) {
    return points.map(point => {
      const participants = new Set([...members, point.source.seat, ...point.positions.keys()]);
      const seats = [...participants].map(seat => {
        const value = point.positions.get(seat);
        const proposed = seat === point.source.seat;
        const source = value?.source || (proposed ? point.source : null);
        return {
          seat, name: source ? historicalName(seat, session, source.round, source) : seatName(seat, session), proposed,
          stance: value?.stance || (proposed ? "" : "unrecorded"),
          reason: value?.reason,
          source,
        };
      });
      return {id: point.id, text: point.text, seats};
    });
  }

  function formatSize(bytes) {
    if (!Number.isFinite(bytes) || bytes < 0) return "";
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  function truncate(text, length) {
    const characters = Array.from(text);
    return characters.length <= length ? text : characters.slice(0, length).join("").trimEnd() + "…";
  }

  function readText(parent, text, key, max = 420) {
    if (!text) return;
    const short = truncate(text, max);
    if (short === text) {
      parent.append(element("p", "prose", text));
      return;
    }
    const details = element("details", "excerpt");
    details.dataset.boardDetails = key;
    const summary = element("summary", "excerpt-toggle");
    summary.dataset.boardFocus = key;
    summary.append(element("span", "when-closed", "展开全文"), element("span", "when-open", "收起全文"));
    details.append(summary, element("p", "prose", text));
    parent.append(element("p", "prose excerpt-short", short), details);
  }

  function sourceFor(ctx, round, seat, quote) {
    const source = ctx.sources.get(JSON.stringify([Number(round), seat]));
    return source && quote ? {...source, quote} : source;
  }

  function makeSourceButton(source, label, key, onSource) {
    return action(label, key, trigger => onSource(source, trigger), "source");
  }

  function blockHeading(title, key, control) {
    const heading = anchor(element("h2", "section-title", title), `${key}:heading`);
    heading.tabIndex = -1;
    heading.dataset.boardFocus = `${key}:heading`;
    const row = element("div", "section-heading");
    row.append(heading);
    if (control) row.append(control);
    return row;
  }

  function attribution(module, ctx, session, key, onSource) {
    if (!module.source_seat) return null;
    const name = historicalName(module.source_seat, session, module.source_round, module);
    const source = sourceFor(ctx, module.source_round, module.source_seat, module.body);
    const row = element("div", "attribution");
    if (source && onSource) row.append(makeSourceButton(source, `${name} · 第 ${source.round} 轮 ↗`, key, onSource));
    else row.textContent = module.source_round ? `${name} · 第 ${module.source_round} 轮` : `${name} 起草`;
    return row;
  }

  function agendaModule(node, data, onAgenda, onSource, editor) {
    const {items, activeId, completed, key} = data;
    if (!items.length) {
      node.append(element("p", "empty", "议程待补充。"));
      return;
    }
    const list = element("ol", "agenda-list");
    list.setAttribute("aria-label", completed ? `议程，已完成 ${completed} 项` : "议程");
    for (const [index, item] of items.entries()) {
      const rowKey = `${key}:item:${item.id || index}`;
      const row = anchor(element("li", "agenda-item"), rowKey);
      const active = item.id === activeId && item.status !== "done";
      if (active) {
        row.dataset.current = "true";
        row.setAttribute("aria-current", "step");
      }
      if (item.status === "done") row.dataset.done = "true";
      const number = element("span", "agenda-index", item.status === "done" ? "✓" : String(index + 1));
      number.setAttribute("aria-hidden", "true");
      const content = element("div", "agenda-item-main");
      const title = onAgenda && item.id
        ? action(item.title, rowKey, trigger => onAgenda(item.id, trigger), "agenda-link")
        : element("span", "agenda-title", item.title);
      const line = element("div", "agenda-line");
      const controls = editGroup();
      line.append(title, controls);
      content.append(line);
      if (active || item.kind === "implementation") {
        content.append(element("span", "agenda-meta", [active && "当前议题", item.kind === "implementation" && "实施"].filter(Boolean).join(" · ")));
      }
      if (item.sourceLink && onSource) {
        content.append(makeSourceButton(item.sourceLink, "原话 ↗", `${rowKey}:source`, onSource));
      }
      if (item.id) editControls(editor, {
        type: "agenda", id: item.id, key: `agenda:${item.id}`, label: `编辑议题：${item.title}`,
        fields: {title: 240}, labels: {title: "议题"},
      }, controls, content);
      row.append(number, content);
      list.append(row);
    }
    node.append(list);
  }

  function downloadLink(material, key, label, onDownload) {
    const link = element("a", "action", label);
    link.href = materialHref(material.id);
    link.download = material.name || "";
    link.dataset.boardFocus = key;
    link.setAttribute("aria-label", `下载 ${material.name || "会议附件"}`);
    link.addEventListener("click", event => onDownload(event, material));
    return link;
  }

  function materialCard(material, key, onPreview, onDownload, editor, annotation, referenced) {
    const rowKey = `${key}:file:${material.id}`;
    const card = anchor(element("article", "material-card"), rowKey);
    const original = materialHref(material.id);
    if (canPreview(material)) {
      const picture = action("", `${rowKey}:preview`, trigger => onPreview(material, trigger), "material-picture");
      picture.setAttribute("aria-label", `预览 ${material.name}`);
      picture.setAttribute("aria-haspopup", "dialog");
      const image = element("img");
      image.src = original + "?preview=1";
      image.alt = "";
      image.loading = "lazy";
      image.decoding = "async";
      image.addEventListener("error", () => { picture.hidden = true; }, {once: true});
      picture.append(image);
      card.append(picture);
    }
    const header = element("div", "material-heading");
    const name = element("h3", "material-name", material.name || "会议附件");
    const download = downloadLink(material, `${rowKey}:download`, "下载", onDownload);
    const controls = editGroup(download);
    header.append(name, controls);
    card.append(header);
    const meta = [referenced && "已引用", formatSize(material.size), materialLabels[material.read_status]].filter(Boolean).join(" · ");
    if (meta) card.append(element("p", "material-meta", meta));
    if (material.excerpt) {
      const details = element("details", "material-excerpt");
      details.dataset.boardDetails = `${rowKey}:excerpt`;
      const summary = element("summary", "", "查看摘录");
      summary.dataset.boardFocus = details.dataset.boardDetails;
      details.append(summary, element("p", "prose", material.excerpt));
      card.append(details);
    }
    annotationBody(card, annotation, "主持人审阅");
    editControls(editor, {
      type: "material", id: material.id, key: `material:${material.id}`,
      label: `编辑材料审阅：${material.name || "会议附件"}`, action: "编辑审阅",
      fields: {body: 800}, labels: {body: "材料审阅"},
    }, controls, card);
    return card;
  }

  function materialReferences(node, references, key, onDownload) {
    if (!references.length) return;
    const list = element("ul", "material-references");
    list.setAttribute("aria-label", "本节引用的材料");
    for (const material of references) {
      const row = element("li");
      const link = downloadLink(material, `${key}:reference:${material.id}`, material.name || "会议附件", onDownload);
      link.setAttribute("aria-label", `下载引用材料 ${material.name || "会议附件"}`);
      row.append(link);
      list.append(row);
    }
    node.append(list);
  }

  function materialsModule(node, data, onPreview, onDownload, editor) {
    const {materials, key, annotations, references} = data;
    if (!materials.length) {
      node.append(element("p", "empty", "暂无附件。"));
      return;
    }
    const grid = element("div", "material-grid");
    const referenced = new Set(references.map(material => material.id));
    for (const material of materials) {
      grid.append(materialCard(material, key, onPreview, onDownload, editor, annotations[material.id], referenced.has(material.id)));
    }
    node.append(grid);
  }

  function annotationBody(parent, annotation, label) {
    if (!annotation?.body) return;
    const block = element("div", "host-annotation");
    block.append(element("span", "host-label", label));
    readText(block, annotation.body, `${label}:${parent.dataset.boardAnchor}`, 200);
    parent.append(block);
  }

  function positionsModule(node, data, onSource, editor) {
    const {points, key, annotations} = data;
    if (!points.length) {
      node.append(element("p", "empty", "暂无观点。"));
      return;
    }
    const list = element("div", "point-list");
    for (const [index, point] of points.entries()) {
      const rowKey = `${key}:point:${point.id}`;
      const details = anchor(element("details", "point"), rowKey);
      details.dataset.boardDetails = rowKey;
      details.open = index === 0;
      const summary = element("summary", "point-summary");
      summary.dataset.boardFocus = rowKey;
      summary.append(element("span", "point-title", point.text));
      const counts = new Map();
      for (const seat of point.seats) {
        if (Object.hasOwn(stanceLabels, seat.stance))
          counts.set(seat.stance, (counts.get(seat.stance) || 0) + 1);
      }
      const tally = element("span", "point-tally");
      for (const [stance, label] of Object.entries(stanceLabels)) {
        if (!counts.has(stance)) continue;
        const tag = element("span", "stance", `${label} ${counts.get(stance)}`);
        tag.dataset.stance = stance;
        tally.append(tag);
      }
      if (tally.childElementCount) summary.append(tally);
      details.append(summary);
      const members = element("ul", "point-seats");
      members.setAttribute("aria-label", "席位的立场");
      for (const seat of point.seats) {
        const seatKey = `${rowKey}:seat:${seat.seat}`;
        const row = anchor(element("li", "point-seat"), seatKey);
        const identity = element("div", "point-identity");
        identity.append(element("strong", "point-name", seat.name));
        const stance = element("span", "stance",
          stanceLabels[seat.stance] || (seat.proposed ? "提出者" : "未表态"));
        stance.dataset.stance = seat.stance;
        identity.append(stance);
        row.append(identity);
        if (seat.reason) row.append(element("p", "point-reason", seat.reason));
        if (seat.source && onSource) {
          const source = makeSourceButton(seat.source, `第 ${seat.source.round} 轮原话 ↗`, `${seatKey}:source`, onSource);
          source.setAttribute("aria-label", `查看 ${seat.name} 第 ${seat.source.round} 轮原话`);
          row.append(source);
        }
        members.append(row);
      }
      details.append(members);
      const annotation = annotations[point.id];
      annotationBody(details, annotation, "主持人批注");
      const controls = editGroup();
      if (editor) details.append(controls);
      editControls(editor, {
        type: "point", id: point.id, key: `point:${point.id}`,
        label: `编辑观点批注：${truncate(point.text, 48)}`, action: annotation?.body ? "编辑批注" : "添加批注",
        fields: {body: 800}, labels: {body: "主持人批注"},
      }, controls, details);
      list.append(details);
    }
    node.append(list);
  }

  function mount({root, statusRoot, onAgenda, onOpinions, onSource, onChat, onRetry, onError, writeEdit, onEdit}) {
    const frame = element("div", "document");
    const header = anchor(element("header", "header"), "header");
    const status = anchor(element("div", "status"), "status");
    status.hidden = true;
    const live = element("p");
    live.className = "sr-only";
    live.setAttribute("role", "status");
    const downloadStatus = element("p");
    downloadStatus.className = "sr-only";
    downloadStatus.setAttribute("role", "status");
    const modules = element("div", "sections");
    const pendingNotes = element("div", "collab-pending-notes");
    const note = element("div", "edit-note");
    const preview = element("dialog", "preview");
    const previewTitle = element("h2", "preview-title");
    previewTitle.id = `${root.id || "meeting-board"}-preview-title`;
    preview.setAttribute("aria-labelledby", previewTitle.id);
    const previewHeader = element("header", "preview-header");
    const dismiss = action("关闭", "close-preview", () => preview.close());
    dismiss.autofocus = true;
    const previewActions = element("div", "preview-actions");
    previewHeader.append(previewTitle, previewActions);
    const previewImage = element("img", "preview-image");
    preview.append(previewHeader, previewImage);
    frame.append(header);
    (statusRoot || frame).append(status, live);
    frame.append(modules, pendingNotes, note, downloadStatus, preview);
    root.append(frame);

    let sessionId = "";
    let watchedEmpty = false;
    let published = false;
    let reveal = null;
    const suppressReveal = window.matchMedia("(prefers-reduced-motion: reduce), (forced-colors: active)");
    let headerKey = "";
    let statusKey = "";
    let noteKey = "";
    let cards = new Map();
    let previewOpener = null;
    let currentSession = null;
    const editor = writeEdit && window.RoundtableBoardEdit?.mount({
      root, write: writeEdit, onChange: onEdit,
      repaint: () => { if (currentSession) render(currentSession); },
    });
    const collab = window.RoundtableBoardCursors?.mount({root, pending: pendingNotes, seatName});
    suppressReveal.addEventListener("change", () => {
      if (suppressReveal.matches && reveal) finishReveal();
    });

    function downloadMaterial(event, material) {
      const activeSession = sessionId;
      return downloadOriginal(event, material, {
        onStart: () => { downloadStatus.textContent = ""; },
        onSaved: () => {
          if (sessionId === activeSession) downloadStatus.textContent = `已保存 ${material.name || "会议附件"}`;
        },
        onError: message => {
          if (sessionId !== activeSession) return;
          downloadStatus.textContent = message;
          onError?.(new Error(message));
        },
      });
    }

    function openPreview(material, trigger) {
      if (preview.open) return;
      previewOpener = trigger;
      previewTitle.textContent = material.name || "会议图片";
      previewImage.alt = previewTitle.textContent;
      previewImage.src = materialHref(material.id) + "?preview=1";
      previewActions.replaceChildren(downloadLink(material, "download-preview", "下载", downloadMaterial), dismiss);
      preview.showModal();
    }

    preview.addEventListener("click", event => {
      if (event.target === preview) preview.close();
    });
    preview.addEventListener("close", () => {
      if (preview.open) return;
      previewImage.removeAttribute("src");
      if (previewOpener) focusTrigger(previewOpener);
      previewOpener = null;
    });

    function clear() {
      if (reveal) clearTimeout(reveal.timer);
      reveal = null;
      currentSession = null;
      editor?.leave();
      collab?.clear();
      sessionId = "";
      watchedEmpty = false;
      published = false;
      headerKey = "";
      statusKey = "";
      noteKey = "";
      cards = new Map();
      previewOpener = null;
      if (preview.open) preview.close();
      header.replaceChildren();
      stage(header, "visible");
      note.inert = false;
      status.hidden = true;
      status.replaceChildren();
      live.textContent = "";
      downloadStatus.textContent = "";
      modules.replaceChildren();
      note.replaceChildren();
      root.dataset.boardReveal = "waiting";
      delete root.dataset.boardRevealStep;
      root.removeAttribute("aria-labelledby");
      root.scrollTop = 0;
    }

    function fillHeader(data) {
      const key = JSON.stringify(data);
      if (key === headerKey || editor?.isOpen(header)) return;
      headerKey = key;
      const title = element("h1", "title", data.title);
      title.id = `${root.id || "meeting-board"}-title`;
      title.tabIndex = -1;
      title.dataset.boardFocus = "title";
      collab?.register(title, "board", "title", data.title);
      root.setAttribute("aria-labelledby", title.id);
      const heading = element("div", "header-title");
      const controls = editGroup(onChat && action("对话 ↗", "chat", onChat, "header-action"));
      heading.append(title, controls);
      const content = document.createDocumentFragment();
      content.append(heading);
      editControls(editor, {
        type: "title", key: "title", label: "编辑会议标题", fields: {title: 80}, labels: {title: "会议标题"},
      }, controls, content);
      if (data.topic && data.topic.trim() !== data.title.trim()) {
        const disclosure = element("details", "original-topic");
        disclosure.dataset.boardDetails = "topic";
        const summary = element("summary", "", "原始议题");
        summary.dataset.boardFocus = "topic";
        disclosure.append(summary, element("p", "prose", data.topic));
        content.append(disclosure);
      }
      preserveDetails(header, content);
      header.replaceChildren(content);
    }

    function fillStatus(session) {
      const {agenda_draft_status: state, agenda_draft_error: error} = session;
      const closed = session.status === "closed";
      const running = session.status === "running";
      const needsDraft = session.board?.state === "empty" && state === "ready";
      const key = JSON.stringify([state, error, closed, running, needsDraft]);
      if (key === statusKey) return;
      statusKey = key;
      status.hidden = closed || (!needsDraft && !drafting.has(state) && state !== "failed");
      status.dataset.state = state || "";
      if (status.hidden) {
        live.textContent = state === "ready" && live.textContent ? "议题板起草完成" : "";
        status.replaceChildren();
        return;
      }
      const message = element("div", "status-message");
      const heading = state === "drafting" ? "首席正在起草议题板"
        : state === "failed" ? "首席起草未完成" : needsDraft ? "主页尚未起草" : "等待首席起草";
      message.append(element("strong", "", heading));
      if (state === "failed" && error) readText(message, error, "draft-error", 250);
      preserveDetails(status, message);
      status.replaceChildren(message);
      if (live.textContent !== heading) live.textContent = heading;
      if (onRetry && state !== "drafting" && !running) {
        status.append(action(state === "failed" ? "重新起草" : "开始起草", "retry", onRetry));
      }
    }

    function stage(node, value) {
      node.dataset.boardStage = value;
      node.inert = value !== "visible";
    }

    function finishReveal() {
      clearTimeout(reveal.timer);
      for (const section of reveal.sections) stage(section, "visible");
      stage(header, "visible");
      note.inert = false;
      reveal = null;
      root.dataset.boardReveal = "complete";
      delete root.dataset.boardRevealStep;
      if (currentSession) render(currentSession);
    }

    function startReveal(sections) {
      const phases = [
        ["outline", 200],
        ["surface", 145],
        // The body starts 120 ms after the title and takes 620 ms to finish.
        ["content", 770],
      ];
      reveal = {sections, timer: 0};
      root.dataset.boardReveal = "drawing";
      note.inert = true;
      stage(header, "queued");
      sections.forEach(section => stage(section, "queued"));

      function draw(index, phase) {
        if (index === sections.length) return finishReveal();
        const section = sections[index];
        if (phase === phases.length) {
          stage(section, "visible");
          if (!index) stage(header, "visible");
          return draw(index + 1, 0);
        }
        const [value, duration] = phases[phase];
        section.style.setProperty("--board-reveal-duration", `${duration}ms`);
        if (!index && value === "content") {
          header.style.setProperty("--board-reveal-duration", `${duration}ms`);
          stage(header, value);
          collab?.draft("board");
        }
        if (value === "content") collab?.draft(section.dataset.boardModule);
        root.dataset.boardRevealStep = value;
        stage(section, value);
        reveal.timer = setTimeout(() => draw(index, phase + 1), duration);
      }
      // The real board is present but blank before the first outline starts.
      reveal.timer = setTimeout(() => draw(0, 0), 45);
    }

    function preserveDetails(previous, next) {
      const states = new Map([...previous.querySelectorAll("details[data-board-details]")]
        .map(detail => [detail.dataset.boardDetails, detail.open]));
      for (const detail of next.querySelectorAll("details[data-board-details]")) {
        if (states.has(detail.dataset.boardDetails)) detail.open = states.get(detail.dataset.boardDetails);
      }
    }

    function findFocus(key) {
      return key && [...root.querySelectorAll("[data-board-focus]")]
        .find(node => node.dataset.boardFocus === key && node.getClientRects().length);
    }

    function focusTrigger(trigger) {
      const target = findFocus(trigger?.dataset.boardFocus) || root;
      target.focus({preventScroll: true});
      return target !== root;
    }

    function render(session, {animateInitial = false} = {}) {
      if (!session) return clear();
      if (session.id !== sessionId) {
        clear();
        sessionId = session.id;
      }
      if (window.RoundtableBoardEdit?.snapshotIsOlder(currentSession, session)) return;
      currentSession = session;
      editor?.sync(session);
      fillStatus(session);
      if (session.board?.state !== "published") {
        watchedEmpty = true;
        collab?.sync(session);
        return;
      }
      if (reveal) return;
      const animate = !published && (animateInitial || watchedEmpty) && !suppressReveal.matches;
      published = true;
      const editable = Boolean(editor && session.status !== "closed");

      const focused = root.contains(document.activeElement) ? document.activeElement : null;
      const focusKey = focused?.dataset.boardFocus;
      const focusSection = focused?.closest("[data-board-module]")?.dataset.boardModule;
      const rootTop = root.getBoundingClientRect().top;
      const reading = root.scrollTop > 0 && !root.hidden
        ? [...root.querySelectorAll("[data-board-anchor]")].find(node =>
            node.getBoundingClientRect().bottom > rootTop + 4)
        : null;
      const offset = reading ? reading.getBoundingClientRect().top - rootTop : 0;
      const ctx = contextFor(session);
      const board = session.board;
      fillHeader({
        title: board?.title || session.title || truncate(session.topic || "", 80) || "共享议题板",
        topic: session.topic, editable,
      });

      const agenda = (session.agenda || []).map(item => ({
        id: item.id, title: item.title, kind: item.kind, status: item.status,
        sourceLink: sourceFor(ctx, item.source_round, item.source_seat),
      }));
      const materials = (session.materials || []).filter(material => material.id);
      const materialById = new Map(materials.map(material => [material.id, material]));
      const points = projectPoints(ctx, session);
      const configured = board.modules || [];
      const dataset = configured.flatMap(module => {
        const key = module.id || module.kind;
        if (editor?.isCreating(key)) return [];
        const data = {
          key, kind: module.kind, title: module.title, body: module.body, editable,
          materialChoices: ["materials", "note"].includes(module.kind) ? materials.map(({id, name}) => [id, name]) : [],
          references: (module.material_ids || []).map(id => materialById.get(id)).filter(Boolean),
        };
        if (module.kind === "agenda") Object.assign(data, {
          items: agenda, activeId: session.active_agenda_id,
          completed: agenda.filter(item => item.status === "done").length,
        });
        if (module.kind === "materials") Object.assign(data, {materials, annotations: board?.material_annotations || {}});
        if (module.kind === "positions") Object.assign(data, {points, annotations: board?.point_annotations || {}});
        data.mark = module.body && module.source_seat
          ? [module.source_seat, module.source_round, historicalName(module.source_seat, session, module.source_round, module)] : [];
        return [{data, module}];
      });
      const nextCards = new Map();
      for (const {data, module} of dataset) {
        const {key, title, kind, body} = data;
        const signature = JSON.stringify(data);
        const previous = cards.get(key);
        if (editor?.isOpen(previous?.node) || previous?.signature === signature) {
          nextCards.set(key, previous);
          continue;
        }
        const section = element("section", "section");
        section.dataset.boardModule = key;
        stage(section, "visible");
        section.append(element("div", "reveal-surface"), element("div", "reveal-outline"));
        const controls = {
          agenda: onAgenda && action("管理议程 ↗", `${key}:manage`, trigger => onAgenda("", trigger)),
          positions: onOpinions && data.points?.length && action("全部观点 ↗", `${key}:opinions`, onOpinions),
        };
        const sectionControls = editGroup(controls[kind]);
        const label = title || fallbackModules.find(item => item.kind === kind)?.title || "记录";
        const heading = blockHeading(label, key, sectionControls);
        collab?.register(heading.firstElementChild, key, "title", label);
        section.append(heading);
        if (editor && module) {
          const fields = {title: 80};
          if (kind === "materials" || kind === "note") Object.assign(fields, {body: 800, material_ids: 8});
          editControls(editor, {
            type: "module", id: key, key: `module:${key}`, label: `编辑分区：${title}`,
            fields, kind, labels: {body: kind === "materials" ? "审阅内容" : "笔记"},
          }, sectionControls, section);
        }
        if (["materials", "note"].includes(kind) || body || data.references?.length) {
          const text = element("div", "edit-preview");
          const copy = element("div", "collab-body");
          const drawBody = (node, value) => {
            const content = document.createDocumentFragment();
            readText(content, value, `${key}:body`);
            preserveDetails(node, content);
            node.replaceChildren(content);
          };
          drawBody(copy, body);
          collab?.register(copy, key, "body", body || "", drawBody);
          text.append(copy);
          if (kind !== "materials") materialReferences(text, data.references, key, downloadMaterial);
          section.append(text);
        }
        if (kind === "agenda") agendaModule(section, data, onAgenda, onSource, editor);
        if (kind === "materials") materialsModule(section, data, openPreview, downloadMaterial, editor);
        if (kind === "positions") positionsModule(section, data, onSource, editor);
        const authorLine = data.mark?.length && attribution(module, ctx, session, `${key}:source`, onSource);
        if (authorLine) section.append(authorLine);
        if (previous) {
          preserveDetails(previous.node, section);
          previous.node.replaceWith(section);
        }
        nextCards.set(key, {node: section, signature});
      }
      for (const [key, previous] of cards) if (!nextCards.has(key)) previous.node.remove();
      let cursor = modules.firstElementChild;
      for (const {node} of nextCards.values()) {
        if (cursor !== node) modules.insertBefore(node, cursor);
        cursor = node.nextElementSibling;
      }
      cards = nextCards;
      collab?.sync(session);
      if (animate && cards.size) startReveal([...cards.values()].map(({node}) => node));
      else root.dataset.boardReveal = "complete";
      const noteId = editor?.newNoteId(editable && configured.length < 8) || "";
      const nextNoteKey = noteId && JSON.stringify([noteId, materials.map(({id, name}) => [id, name])]);
      if (noteKey !== nextNoteKey && !editor?.isOpen(note)) {
        noteKey = nextNoteKey;
        if (nextNoteKey) {
          const {trigger, form} = editor.newNote(noteId);
          note.replaceChildren(trigger, form);
        } else note.replaceChildren();
      }

      if (reading) {
        const replacement = reading.isConnected ? reading : [...root.querySelectorAll("[data-board-anchor]")]
          .find(node => node.dataset.boardAnchor === reading.dataset.boardAnchor);
        if (replacement) root.scrollTop += replacement.getBoundingClientRect().top - rootTop - offset;
      }
      if (focused && document.activeElement !== focused) {
        const replacement = findFocus(focusKey);
        if (replacement) replacement.focus({preventScroll: true});
        else {
          const fallback = cards.get(focusSection)?.node.querySelector(".board-section-title") || header.querySelector("h1");
          fallback?.focus({preventScroll: true});
        }
      }
    }

    return {
      render, clear, focusTrigger, isDrawing: () => Boolean(reveal),
      setPresence: snapshot => collab?.setPresence(snapshot),
      flush: () => editor?.flush() ?? true, revealDraft: () => editor?.reveal(),
    };
  }

  window.RoundtableBoard = Object.freeze({mount});
})();
