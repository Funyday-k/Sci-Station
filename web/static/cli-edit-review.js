"use strict";
(() => {
  const activeStates = new Set(["starting", "running", "pending", "responded"]);
  const stateLabels = {
    starting: "正在启动 CLI",
    running: "CLI 正在工作",
    pending: "等待审核",
    responded: "已向 CLI 发送答复，等待执行结果",
    completed: "CLI 已结束本次任务",
    failed: "CLI 任务失败",
    cancelled: "CLI 任务已取消"
  };

  function meetingScope(session, projectName) {
    if (!session) return null;
    return {
      meetingId: session.id, projectId: session.project_id || "",
      meeting: session.title || session.topic || session.id,
      project: projectName || session.project_id || "",
      round: session.rounds?.length || 0, closed: session.status === "closed", discussing: session.status === "running"
    };
  }

  function unpack(body, scope) {
    if (!Array.isArray(body?.providers) || !Object.hasOwn(body, "run")) throw Error("无法核对 CLI 的状态。");
    const run = body.run;
    if (run && (!run.id || !Object.hasOwn(stateLabels, run.status) ||
        run.meetingId !== scope.meetingId || run.projectId !== scope.projectId)) {
      throw Error("CLI 状态与当前项目或会议不匹配，请重新读取。");
    }
    return body;
  }

  function pendingDecision(run, scope) {
    const item = run?.pending;
    if (run?.status !== "pending" || !item || run.meetingId !== scope?.meetingId ||
        run.projectId !== scope.projectId || !item.requestId || !item.itemId ||
        !item.threadId || !item.turnId || (run.threadId && item.threadId !== run.threadId) ||
        (run.turnId && item.turnId !== run.turnId)) return null;
    return {
      projectId: scope.projectId, runId: run.id, threadId: item.threadId, turnId: item.turnId,
      requestId: item.requestId, itemId: item.itemId
    };
  }

  function canAccept(run, scope) {
    return Boolean(pendingDecision(run, scope)) && !scope.closed && !scope.discussing && scope.round === run.meetingRound &&
      Array.isArray(run.pending.changes) && run.pending.changes.length > 0 &&
      run.pending.changes.every(change => typeof change?.path === "string" && change.path.length &&
        typeof change.diff === "string" && change.diff.trim().length);
  }

  function parseDiffLines(diffText) {
    const raw = typeof diffText === "string" && diffText.length ? diffText : "CLI 未提供此文件的差异。";
    return raw.split(/\r?\n/).map(line => {
      if (/^(?:diff --git |index |--- |\+\+\+ |@@ |\\ )/.test(line)) {
        return {kind: "header", gutter: "", text: line};
      }
      if (line.startsWith("+")) {
        return {kind: "add", gutter: "+", text: line.slice(1)};
      }
      if (line.startsWith("-")) {
        return {kind: "remove", gutter: "−", text: line.slice(1)};
      }
      if (line.startsWith(" ")) {
        return {kind: "context", gutter: " ", text: line.slice(1)};
      }
      return {kind: "context", gutter: " ", text: line};
    });
  }

  function renderDiffView(diffText, doc) {
    const pre = doc.createElement("pre");
    pre.className = "diff-view";
    const lines = parseDiffLines(diffText);
    for (const entry of lines) {
      const row = doc.createElement("span");
      row.className = "diff-line diff-" + entry.kind;
      const gutter = doc.createElement("span");
      gutter.className = "diff-gutter";
      gutter.setAttribute?.("aria-hidden", "true");
      gutter.textContent = entry.gutter;
      const body = doc.createElement("span");
      body.className = "diff-text";
      body.textContent = entry.text;
      row.append(gutter, body);
      pre.append(row);
    }
    return pre;
  }

  function mount() {
    const el = id => document.getElementById("cli-edit-" + id);
    const dialog = el("dialog");
    let scope = null;
    let envelope = null;
    let error = "";
    let sequence = 0;
    let writing = false;
    let fetching = false;
    let timer = null;
    let lastDecision = "";
    let providerSignature = "";
    let proposalSignature = "";

    function nativeSession() {
      return typeof window.sciStationCLIEditSession === "string" && window.sciStationCLIEditSession.length > 0;
    }
    function schedule() {
      clearTimeout(timer);
      // GET can observe a CLI response. Only an explicit button may send one.
      if (!nativeSession() || !scope?.projectId || document.hidden || writing || fetching) return;
      if (activeStates.has(envelope?.run?.status)) timer = setTimeout(refresh, error ? 3500 : 1200);
    }

    function setSession(session, projectName) {
      const next = meetingScope(session, projectName);
      const changed = scope?.meetingId !== next?.meetingId || scope?.projectId !== next?.projectId;
      scope = next;
      el("open").hidden = !next;
      if (!changed) {
        render();
        return;
      }
      sequence++;
      clearTimeout(timer);
      if (dialog.open) dialog.close();
      el("start").reset();
      envelope = null;
      lastDecision = "";
      proposalSignature = "";
      error = "";
      writing = fetching = false;
      render();
      if (scope?.projectId) refresh();
    }

    function showProviders(providers) {
      const signature = JSON.stringify(providers);
      if (signature === providerSignature) return;
      providerSignature = signature;
      const previous = el("provider").value;
      const options = providers.map(provider => {
        const option = new Option(provider.label || provider.id, provider.id);
        option.disabled = !provider.available;
        return option;
      });
      el("provider").replaceChildren(...options);
      const picked = providers.find(provider => provider.id === previous && provider.available) ||
        providers.find(provider => provider.available);
      el("provider").value = picked?.id || "";
      const reasons = providers.filter(provider => !provider.available).map(provider => {
        const item = document.createElement("li");
        item.textContent = (provider.label || provider.id) + " · " + (provider.reason || "无法提供逐项文件审批");
        return item;
      });
      el("capabilities").replaceChildren(...reasons);
      el("capabilities").hidden = !reasons.length;
    }

    function showProposal(run) {
      const item = run?.status === "pending" ? run.pending : null;
      el("proposal").hidden = !item;
      const decisionActions = el("decision-actions");
      if (decisionActions) decisionActions.hidden = !item;
      const signature = JSON.stringify([run?.id, item]);
      if (proposalSignature !== signature) {
        proposalSignature = signature;
        el("reason").textContent = item?.reason || "";
        const files = Array.isArray(item?.changes) ? item.changes : [];
        el("changes").replaceChildren(...files.map(change => {
          const section = document.createElement("section");
          const name = document.createElement("h4");
          const kind = {add:"新增", update:"修改", delete:"删除", create:"新增", remove:"删除"}[change.kind];
          name.textContent = [change.path, kind || change.kind].filter(Boolean).join(" · ");
          const diff = renderDiffView(change.diff, document);
          section.append(name, diff);
          return section;
        }));
        // Replace the buttons as well as the diff when the CLI asks a new
        // question. A click on an obsolete rendering cannot authorize it.
        for (const action of ["accept", "decline"]) {
          const button = el(action).cloneNode(true);
          el(action).replaceWith(button);
          button.onclick = () => {
            if (signature !== proposalSignature || writing || error) return;
            const current = envelope?.run;
            const decision = pendingDecision(current, scope);
            if (!decision || (action === "accept" && !canAccept(current, scope))) return;
            lastDecision = JSON.stringify(decision);
            send({action, ...decision});
          };
        }
      }
      const decision = pendingDecision(run, scope);
      const sent = decision && JSON.stringify(decision) === lastDecision;
      el("accept").disabled = Boolean(error || writing || sent || !canAccept(run, scope));
      el("decline").disabled = Boolean(error || writing || sent || !decision);
    }

    function render() {
      const run = envelope?.run;
      const active = activeStates.has(run?.status);
      const providers = envelope?.providers || [];
      showProviders(providers);
      const projectLabel = scope?.project && scope.project !== scope.projectId ? scope.project + " (" + scope.projectId + ")" : scope?.project;
      el("scope").textContent = scope ? [projectLabel || "全局圆桌", scope.meeting, scope.round ? "第 " + scope.round + " 轮" : "首轮开始前"].join(" · ") : "";
      el("open").textContent = run?.status === "pending" && !error ? "CLI 编辑待审核" : "CLI 文件编辑";
      el("start").hidden = !nativeSession() || !scope?.projectId || active || scope.closed;
      el("submit").disabled = Boolean(writing || error || !envelope || scope?.discussing || !el("provider").value);
      el("run").hidden = !run;
      const provider = providers.find(provider => provider.id === run?.provider);
      el("run-title").textContent = run ? (error ? "上次读取 · " : "") + (provider?.label || run.provider) + " · " + stateLabels[run.status] : "";
      const task = run?.prompt ? "编辑要求：" + run.prompt : "";
      const paths = run?.paths?.length ? "本次文件范围：" + run.paths.join("、") : "";
      el("run-detail").textContent = [task, paths, run?.detail].filter(Boolean).join("\n");
      showProposal(run);
      el("cancel").hidden = !active;
      el("cancel").disabled = Boolean(writing || error);
      el("refresh").disabled = !nativeSession() || !scope?.projectId || fetching || writing;
      let message = "";
      if (!nativeSession()) message = "请在 Sci-Station 桌面窗口中发起或审核 CLI 文件编辑。";
      else if (!scope?.projectId) message = "请在关联项目的圆桌中编辑项目文件。";
      else if (writing) message = "正在发送，等待 CLI 服务确认…";
      else if (error) message = error;
      else if (!envelope) message = "正在读取 CLI 状态…";
      else if (run?.status === "pending" && !canAccept(run, scope)) message = "当前轮次或文件差异无法核对，请拒绝请求或取消任务。";
      else if (scope?.discussing && !active) message = "当前讨论轮次进行中，结束后可发起编辑请求。";
      else if (!run && scope.closed) message = "这场会议已结束。";
      else if (!run && !providers.some(provider => provider.available)) message = "当前没有可逐项审核文件修改的 CLI。";
      else if (!run) message = "当前没有待审核的 CLI 请求。";
      el("status").textContent = message;
    }

    async function request(payload) {
      if (!nativeSession() || !scope?.projectId) return;
      const ticket = ++sequence;
      clearTimeout(timer);
      const endpoint = "/api/studio/sessions/" + encodeURIComponent(scope.meetingId) + "/cli-edits";
      if (payload) writing = true;
      else fetching = true;
      render();
      try {
        const options = {method:"GET", cache:"no-store", headers:{Accept:"application/json","X-Sci-Station-CLI-Session":window.sciStationCLIEditSession}};
        if (payload) {
          options.method = "POST";
          options.headers["Content-Type"] = "application/json";
          options.headers["X-Roundtable"] = "1";
          options.body = JSON.stringify(payload);
        }
        const response = await fetch(endpoint, options);
        const data = await response.json();
        if (!response.ok) throw Error(data?.error?.message || data?.error || "本机 CLI 服务未能完成请求。");
        if (ticket !== sequence) return;
        envelope = unpack(data, scope);
        error = "";
        if (payload?.action === "start") {
          el("prompt").value = "";
          el("paths").value = "";
        }
      } catch (failure) {
        if (ticket !== sequence) return;
        error = "未能确认当前状态。请刷新后核对。 " + failure.message;
        if (payload?.action === "accept" || payload?.action === "decline") lastDecision = "";
      } finally {
        if (ticket === sequence) {
          writing = fetching = false;
          render();
          schedule();
        }
      }
    }

    function refresh() {
      if (!writing && !fetching) return request();
    }

    function send(payload) {
      if (writing || error) return;
      return request(payload);
    }

    el("start").onsubmit = event => {
      event.preventDefault();
      if (activeStates.has(envelope?.run?.status) || !scope?.projectId || scope.closed || scope.discussing || error || writing) return;
      const provider = envelope?.providers.find(provider => provider.id === el("provider").value && provider.available);
      const paths = el("paths").value.split(/\r?\n/).map(path => path.trim()).filter(Boolean);
      const prompt = el("prompt").value.trim();
      if (!provider || !prompt || !paths.length) return;
      send({action:"start", projectId:scope.projectId, meetingRound:scope.round, provider:provider.id, prompt, paths});
    };
    el("cancel").onclick = () => {
      const run = envelope?.run;
      if (activeStates.has(run?.status) && scope?.projectId === run.projectId) {
        send({action:"cancel", projectId:scope.projectId, runId:run.id});
      }
    };
    // Focus order and Escape contract:
    // - Opening moves focus to Close (never auto-focusing Approve) so keyboard users
    //   inspect the diff before tabbing through Refresh -> Cancel -> Deny -> Approve.
    // - Escape or Close dismisses the modal without issuing any POST decision and
    //   restores focus to #cli-edit-open.
    el("open").onclick = () => {
      dialog.showModal();
      el("close").focus?.();
      refresh();
    };
    el("close").onclick = () => dialog.close();
    dialog.addEventListener?.("close", () => {
      if (!el("open").hidden) el("open").focus?.();
    });
    el("refresh").onclick = refresh;
    el("provider").onchange = render;
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) clearTimeout(timer);
      else if (dialog.open || activeStates.has(envelope?.run?.status)) refresh();
    });
    window.addEventListener("scistation:cli-edit-session", () => {
      // Revalidate the current window's authorization. Never replay an in-flight command.
      sequence++;
      clearTimeout(timer);
      writing = fetching = false;
      envelope = null;
      error = "";
      render();
      refresh();
    });
    window.addEventListener("pageshow", event => { if (event.persisted) refresh(); });
    return {setSession};
  }
  if (typeof module !== "undefined" && module.exports) {
    module.exports = {meetingScope, unpack, pendingDecision, canAccept, parseDiffLines, renderDiffView};
  }
  if (typeof window !== "undefined") window.SciCLIEdit = mount();
})();
