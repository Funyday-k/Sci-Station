"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const paintTextLimit = window.RoundtableInputLimit.paint;
  const legacyNames = { codex: "Codex", cursor: "Cursor" };
  const { icon, sourceMark: assetFor } = window.RoundtableIcons;
  function sessionMembers(session = state.session) {
    if (session?.members?.length) return session.members;
    const resolved = state.legacyRosters.get(session?.id)?.members;
    return (session?.seats || []).map(id => session.seat_overrides?.[id] || resolved?.find(member => member.id === id) || ({
      id, source:id, label:legacyNames[id] || id,
      model:session.rounds?.at(-1)?.settings?.models?.[id] || "", effort:"auto",
    }));
  }
  function seatName(id, session = state.session) {
    if (id === "user") return "主持人";
    const members = sessionMembers(session);
    const member = members.find(item => item.id === id);
    if (!member) return legacyNames[id] || id || "主持人";
    const name = member.label || member.model || member.id;
    if (members.filter(item => (item.label || item.model || item.id) === name).length === 1) return name;
    return name + " · 席位 " + (members.indexOf(member) + 1);
  }
  function memberAsset(id, session = state.session) {
    const member = sessionMembers(session).find(item => item.id === id);
    return assetFor(member?.source || (member?.model || "").split("/")[0] || id);
  }
  function turnIdentity(turn, session = state.session, round) {
    const id = turn.seat;
    if (id === "user") return {label:"主持人", model:"", source:"", effort:""};
    const model = turn.model || round?.settings?.models?.[id] || "";
    const members = sessionMembers(session);
    const index = members.findIndex(member => member.id === id);
    const current = members[index];
    const source = turn.model_source || (model.includes("/") ? model.split("/")[0] :
      (current?.model === model ? current.source : "") || (legacyNames[id] ? id : ""));
    const savedLabel = turn.model_label || model || legacyNames[id] || (index >= 0 ? `席位 ${index + 1}` : id);
    const matchingTurns = (round?.turns || []).filter(item =>
      (item.model_label || item.model || round?.settings?.models?.[item.seat]) === savedLabel);
    const label = matchingTurns.length > 1 && index >= 0 ? `${savedLabel} · 席位 ${index + 1}` : savedLabel;
    return {label, model, source, effort:turn.effort || round?.settings?.efforts?.[id] || "", asset:assetFor(source)};
  }
  function sourceIdentity(id, session, roundNumber, source = {}) {
    const round = session?.rounds?.find(item => item.number === Number(roundNumber));
    const turn = round?.turns?.find(item => item.seat === id && (!source?.model || item.model === source.model));
    return turnIdentity(turn || {...source, seat:id}, session, round);
  }
  const modelByline = ({label, model}) => model && model !== label ? `${label} · ${model}` : label;
  window.RoundtableIdentity = Object.freeze({seatName, memberAsset, turnIdentity, sourceIdentity, modelByline});
  const state = {
    settings: null,
    sessions: [],
    selected: null,
    session: null,
    activeProject: null,
    projectListStatus: "loading",
    draftOpen: false,
    view: "table",
    writing: false,
    poll: null,
    roundsKey: "",
    historyKey: "",
    seatKeys: {},
    legacyRosters: new Map(),
    expandedSeats: new Set(),
    files: [],
    file: null,
    fileText: "",
    fileRawText: "",
    diff: null,
    filesSession: null,
    anchor: "",
    fileRequest: 0,
    fileListRequest: 0,
    fileRefreshRequest: 0,
    fileLoading: false,
    savingFile: false,
    diskChanged: null,
    workspaceKey: "",
    workspaceSyncing: false,
    workspacePending: false,
    settingsDirty: false,
    filePanelOpen: false,
    panelOpener: null,
    reviewCache: new Map(),
    reviewUnit: "lines",
    metricsWorker: null,
    metricRequests: new Map(),
    reviewSummaries: new Map(),
    reviewQueue: [],
    reviewActive: 0,
    reviewEpoch: 0,
    enteredSessions: new Set(),
    titleAttempts: new Set(),
    titleJobs: new Map(),
    titles: new Map(),
    titleErrors: new Map(),
    menuSession: null,
    menuOpener: null,
    dialogOpener: null,
    actionToast: null,
    cancelling: false,
    discussionChoices: new Map(),
    agendaNote: "",
  };
  const escape = (value) =>
    String(value ?? "").replace(
      /[&<>"']/g,
      (char) =>
        ({
          "&": "&amp;",
          "<": "&lt;",
          ">": "&gt;",
          '"': "&quot;",
          "'": "&#39;",
        })[char],
    );
  const detailText = (value) =>
    typeof value === "string" ? value : value ? JSON.stringify(value) : "";
  $("toggle-sidebar").innerHTML = icon("sidebar");
  $("dismiss-notice").innerHTML = icon("close");
  function storageGet(key) {
    try {
      return localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }
  function storageSet(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch (_) {}
  }
  const appearance = window.RoundtableAppearance;
  const colorThemeControl = $("settings-form").elements.namedItem("color_theme");
  function showError(error) {
    $("notice-text").textContent = error.message || String(error);
    $("notice").hidden = false;
  }
  function clearError() {
    $("notice").hidden = true;
  }
  async function api(path, body, poll = null) {
    const response = await fetch(`/api/studio${path}`, {
      cache: "no-store",
      ...(body === undefined
        ? {headers: poll?.etag ? {"If-None-Match": poll.etag} : {}}
        : {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Roundtable": "1",
            },
            body: JSON.stringify(body),
          }),
    });
    if (poll && response.status === 304) return null;
    if (poll && response.ok) poll.etag = response.headers.get("ETag") || "";
    let result;
    try {
      result = await response.json();
    } catch (_) {
      throw new Error("本机服务返回了无法读取的内容。");
    }
    if (!response.ok) {
      const error = new Error(
        typeof result.error === "string"
          ? result.error
          : result.error?.message ||
              result.message ||
              `请求未完成（${response.status}）`,
      );
      error.status = response.status;
      error.unreadableSession = result.unreadable_session;
      error.session = result.session;
      throw error;
    }
    return result;
  }
  const sessionPath = (suffix) =>
    `/sessions/${encodeURIComponent(state.selected)}${suffix || ""}`;
  const latestRound = () => state.session?.rounds?.at(-1);
  function sessionWorking(session = state.session) {
    const continuous = session?.continuous;
    if (session?.status !== "running") return false;
    if (continuous?.manual) return true;
    return !["paused", "completed"].includes(continuous?.status);
  }
  const statusText = (status) =>
    ({
      ready: "等待主持",
      closed: "会议已结束",
      running: "工作进行中",
      partial: "有工作未完成",
      pending: "等待开始",
      done: "已完成",
      error: "未完成",
      cancelled: "已停止",
      canceled: "已停止",
    })[status] ||
    status ||
    "等待开始";
  function activityEvent(event) {
    const owner = event.seat ? (event.round ? sourceIdentity(event.seat, state.session, event.round).label : seatName(event.seat)) : "圆桌";
    const detail = detailText(event.detail);
    const labels = {
      created: "圆桌已建立，等待你发起第一轮。",
      round_started: "新一轮工作已开始。",
      round_finished:
        event.detail === "partial"
          ? "本轮已结束，部分工作未完成。"
          : "本轮工作已完成，等待下一步。",
      cancel_requested: "正在停止本轮工作。",
      recovered: "已恢复上次记录；中断的工作没有自动重启。",
      seat_started: "正在处理任务。",
      seat_done: "已完成本轮工作并记录发言。",
      child_done: "子代理已完成工作，结果已交回所属主 agent。",
      write: "已更新项目文件",
      read: "正在读取项目文件",
      child_read: "子代理正在读取项目文件",
      child_started: "已派出子代理",
      seat_error: "本轮工作未完成",
      child_error: "子代理工作未完成",
      action_error: "操作未完成",
      round_error: "本轮工作遇到问题",
    };
    let text = labels[event.type] || "工作记录已更新。";
    if (
      [
        "write",
        "read",
        "child_read",
        "child_started",
        "seat_error",
        "child_error",
        "action_error",
        "round_error",
      ].includes(event.type) &&
      detail
    )
      text += `：${detail}`;
    if (event.type === "round_started" && detail) text += ` ${detail}`;
    return { owner, text };
  }
  function sidebar(open) {
    const mobile = matchMedia("(max-width: 800px)").matches;
    document.body.classList.toggle(
      mobile ? "sidebar-open" : "sidebar-collapsed",
      mobile ? open : !open,
    );
    $("toggle-sidebar").setAttribute("aria-expanded", String(open));
    if (!mobile) storageSet("studio.sidebar", open ? "open" : "closed");
  }
  function closeMobileSidebar() {
    if (matchMedia("(max-width: 800px)").matches) sidebar(false);
  }
  let restoringRoute = true;
  function syncUrl(id, preserveHash = false, createdProject = "") {
    const url = new URL(location.href);
    url.pathname = "/studio";
    if (id) url.searchParams.set("session", id);
    else url.searchParams.delete("session");
    const project = id ? createdProject || state.sessions.find(item=>item.id===id)?.project_id || state.session?.project_id :
      projects.available().find(item=>item.id===state.activeProject && !item.global)?.id;
    if (project) url.searchParams.set("project",project); else url.searchParams.delete("project");
    if (!preserveHash) url.hash = "";
    if (!restoringRoute) {
      url.searchParams.delete("view");
      window.SciStationNav.commitURL(url,"replace");
    }
  }
  function scrollToMessage(target, block = "start") {
    const scroll = $("table-scroll");
    if (!target || !$("rounds").contains(target)) return;
    if (!target.getBoundingClientRect || !scroll.getBoundingClientRect) {
      scroll.scrollTop = block === "end" ? scroll.scrollHeight : 0;
      return;
    }
    const frame = scroll.getBoundingClientRect(),
      rect = target.getBoundingClientRect();
    const top = scroll.scrollTop + rect.top - frame.top - scroll.clientTop;
    scroll.scrollTop = Math.max(
      0,
      block === "end" ? top + rect.height - scroll.clientHeight : top,
    );
  }
  function scrollAnchor() {
    const target = document.getElementById(location.hash.slice(1));
    if (target && $("rounds").contains(target)) {
      setChatVisible(true);
      scrollToMessage(target);
    }
  }
  const normalizeNewlines = (text) => String(text).replace(/\r\n|\r/g, "\n");
  function restoreNewlines(original, edited) {
    const normalized = normalizeNewlines(original);
    const next = normalizeNewlines(edited);
    if (normalized === next) return original;
    const before = normalized.split("\n"),
      after = next.split("\n");
    const endings = original.match(/\r\n|\r|\n/g) || [];
    let prefix = 0,
      suffix = 0;
    while (
      prefix < before.length &&
      prefix < after.length &&
      before[prefix] === after[prefix]
    )
      prefix++;
    while (
      suffix < before.length - prefix &&
      suffix < after.length - prefix &&
      before[before.length - 1 - suffix] === after[after.length - 1 - suffix]
    )
      suffix++;
    const local = endings.slice(
      Math.max(0, prefix - 1),
      Math.max(prefix + 1, before.length - suffix),
    );
    const counts = new Map();
    for (const ending of local.length ? local : endings)
      counts.set(ending, (counts.get(ending) || 0) + 1);
    const preferred = [...counts].sort((a, b) => b[1] - a[1])[0]?.[0] || "\n";
    // Keep unchanged edge lines' separators; align replacement lines with the old interval.
    return after
      .map((line, index) => {
        if (index === after.length - 1) return line;
        const oldIndex =
          index >= after.length - suffix
            ? before.length - after.length + index
            : index;
        return line + (endings[oldIndex] || preferred);
      })
      .join("");
  }
  function hasFileDraft() {
    return Boolean(state.file && $("file-editor").value !== state.fileText);
  }
  function dirtyFile() {
    return Boolean(
      state.file && (state.file.version === "missing" || hasFileDraft()),
    );
  }
  function fileControls() {
    const reviewing = Boolean(state.diff);
    const closed = state.session?.status === "closed";
    for (const id of ["copy-file", "reload-file"]) $(id).hidden = reviewing;
    $("save-file").hidden = reviewing || closed;
    $("edit-diff").hidden = !reviewing;
    $("edit-diff").textContent = closed ? "查看此文件" : "编辑此文件";
    $("file-dirty").hidden = !dirtyFile();
    $("file-dirty").textContent =
      state.file?.version === "missing" ? "新文件 · 尚未保存" : "有未保存修改";
    $("file-editor").readOnly = closed || state.fileLoading;
    $("save-file").disabled =
      closed ||
      !dirtyFile() ||
      state.writing ||
      state.fileLoading ||
      Boolean(state.diskChanged);
    $("reload-file").disabled =
      !state.file || state.fileLoading || state.savingFile;
    $("copy-file").disabled = !state.file || state.fileLoading;
    $("file-change-notice").hidden = !state.diskChanged;
    if (state.diskChanged)
      $("file-change-text").textContent =
        "磁盘上的文件已变化。你的草稿已保留，请复制草稿，或重新载入后核对。";
  }
  function resetFiles() {
    state.reviewEpoch++;
    state.reviewCache.clear();
    state.reviewSummaries.clear();
    state.reviewQueue = [];
    state.metricRequests.clear();
    state.metricsWorker?.terminate();
    state.metricsWorker = null;
    state.fileRequest++;
    state.fileRefreshRequest++;
    state.fileListRequest++;
    state.fileLoading = false;
    state.diskChanged = null;
    state.workspaceKey = "";
    state.files = [];
    state.fileText = "";
    state.fileRawText = "";
    state.workspacePending = false;
    $("file-change-notice").hidden = true;
    fileControls();
  }
  function canLeaveFile() {
    return (
      !dirtyFile() ||
      window.confirm("当前文件还有未保存的修改。是否放弃这些修改？")
    );
  }
  function chatPosition() {
    const scroll = $("table-scroll"),
      viewport = scroll.getBoundingClientRect?.();
    if (viewport)
      for (const node of $("rounds").querySelectorAll(".message[id]")) {
        const rect = node.getBoundingClientRect();
        if (rect.bottom > viewport.top)
          return {
            node,
            id: node.id,
            offset: rect.top - viewport.top,
            top: scroll.scrollTop,
          };
      }
    return { top: scroll.scrollTop };
  }
  function restoreChatPosition(position) {
    requestAnimationFrame(() => {
      const scroll = $("table-scroll"),
        node = position.node?.isConnected
          ? position.node
          : position.id
            ? document.getElementById(position.id)
            : null;
      if (node?.getBoundingClientRect && scroll.getBoundingClientRect)
        scroll.scrollTop +=
          node.getBoundingClientRect().top -
          scroll.getBoundingClientRect().top -
          position.offset;
      else scroll.scrollTop = position.top;
    });
  }
  function openChanges(change = null, opener = document.activeElement) {
    if (!state.session || !allChanges().length) return;
    if (state.view !== "table") switchView("table");
    window.dispatchEvent(
      new CustomEvent("roundtable:sidepanel-open", { detail: "review" }),
    );
    const position = chatPosition();
    state.filePanelOpen = true;
    state.panelOpener = opener;
    $("files-view").hidden = false;
    $("files-toggle").setAttribute("aria-expanded", "true");
    const selected = change || state.diff || allChanges().at(-1);
    if (selected) showDiff(selected);
    loadFiles().catch(showError);
    restoreChatPosition(position);
    $("close-changes").focus({ preventScroll: true });
  }
  function closeChanges(restoreFocus = true) {
    if (!state.filePanelOpen) {
      $("files-view").hidden = true;
      return;
    }
    const position = chatPosition();
    state.filePanelOpen = false;
    $("files-view").hidden = true;
    $("files-toggle").setAttribute("aria-expanded", "false");
    restoreChatPosition(position);
    if (restoreFocus) {
      const target = state.panelOpener?.getClientRects().length
        ? state.panelOpener
        : $("meeting-actions-toggle");
      target.focus({ preventScroll: true });
    }
  }
  function switchView(view) {
    closeHistoryMenu(false);
    if ($("project-dialog").open) $("project-dialog").close();
    if (view === "files") {
      switchView("table");
      if (allChanges().length) openChanges();
      return;
    }
    if (view !== "table") {
      resetRoomDisclosures();
      createCommands.close();
      reportUI.close();
      pluginsUI.closeTools();
      closeChanges(false);
      window.RoundtableChildren?.close({ restoreFocus: false });
    }
    state.view = view;
    document.body.classList.toggle("settings-mode", ["settings", "plugins"].includes(view));
    const viewURL = new URL(location.href);
    if (view === "table") viewURL.searchParams.delete("view");
    else viewURL.searchParams.set("view", view);
    if (!restoringRoute) window.SciStationNav.commitURL(viewURL,"push");
    $("table-view").hidden = view !== "table";
    syncBoardPresence();
    if (state.session) schedulePoll();
    $("settings-view").hidden = !["settings", "plugins"].includes(view);
    if (view === "table" && !state.selected && !$("create-form").hidden) setup.resume();
    renderHeading();
    $("back-to-table").hidden = view === "table";
    for (const button of document.querySelectorAll(".view-tab")) {
      const selected = button.dataset.view === view;
      button.classList.toggle("selected", selected);
      if (selected) button.setAttribute("aria-current", "page");
      else button.removeAttribute("aria-current");
    }
    if (view === "settings") {
      window.RoundtableSettingsNav?.select("models");
      refreshSettingsOverview();
    }
    if (view === "plugins") {
      window.RoundtableSettingsNav?.select("plugins");
    }
    closeMobileSidebar();
  }
  const cleanTitle = (value) =>
    typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
  const historyId = (kind, id) =>
    `history-${kind}-${encodeURIComponent(id).replace(/%/g, "_")}`;
  function sessionTitle(session) {
    if (session?.board?.source_seat && session.board.title) return session.board.title;
    if (session?.status === "closed" && !cleanTitle(session.title)) {
      const topic = Array.from(cleanTitle(session.topic));
      return topic.slice(0, 54).join("") + (topic.length > 54 ? "…" : "") || "已结束的圆桌";
    }
    return (
      state.titles.get(session?.id) ||
      cleanTitle(session?.title) ||
      (state.titleJobs.get(session?.id)?.pending
        ? "正在命名…"
        : state.titleErrors.has(session?.id)
          ? "标题待重试"
          : cleanTitle(session?.topic).slice(0, 54) || "未命名圆桌")
    );
  }
  function currentSummary() {
    return state.session?.id === state.selected
      ? state.session
      : state.sessions.find((item) => item.id === state.selected);
  }
  function renderHeading() {
    const projectName = state.draftOpen
      ? projects.available().find(project => project.id === state.activeProject)?.name
      : "";
    const text = (zh, en) => window.SciStationI18n?.text(zh, en) ?? zh;
    const viewName = state.view === "settings" ? text("设置", "Settings")
      : state.view === "plugins" ? text("插件市场", "Plugin marketplace") : "";
    const title = viewName || (state.selected
      ? sessionTitle(currentSummary())
      : projectName ? `${projectName} / 新建圆桌` : "新建圆桌");
    $("view-title").textContent = title;
    $("view-title").title =
      state.view === "table" && state.titleErrors.has(state.selected) && !state.titles.has(state.selected)
        ? "标题暂未生成，可在会话更多操作中重试命名。"
        : title;
    $("view-title").setAttribute(
      "aria-busy",
      String(
        state.view === "table" &&
          Boolean(state.titleJobs.get(state.selected)?.pending),
      ),
    );
    const inMeeting = state.view === "table" && state.session && state.session.id === state.selected;
    $("chat-toolbar").hidden = !inMeeting;
    $("meeting-mode-status").hidden = !inMeeting;
    $("session-status").hidden =
      !state.session || state.session.status === "ready";
    document.title = `${title} · ${text("工作圆桌", "Roundtable")}`;
  }
  function requestTitle(id, { force = false } = {}) {
    if (!id || !state.enteredSessions.has(id)) return Promise.resolve(null);
    const active = state.session?.id === id ? state.session : null;
    if (!force && (active?.board?.source_seat || ["pending", "drafting", "failed"].includes(active?.agenda_draft_status)))
      return Promise.resolve(null);
    const current = state.titleJobs.get(id);
    if (current?.pending) return current.promise;
    const known =
      state.sessions.find((item) => item.id === id) ||
      (state.session?.id === id ? state.session : null);
    if (
      known?.status === "closed" ||
      state.titles.has(id) ||
      cleanTitle(known?.title) ||
      (!force && state.titleAttempts.has(id))
    )
      return Promise.resolve(null);
    state.titleAttempts.add(id);
    state.titleErrors.delete(id);
    const job = { pending: true, generation: (current?.generation || 0) + 1 };
    job.promise = new Promise((resolve) => {
      job.timer = setTimeout(async () => {
        let value = null;
        try {
          const result = await api(
            `/sessions/${encodeURIComponent(id)}/title`,
            {},
          );
          value = cleanTitle(result.title);
          if (!value) throw new Error("未返回有效标题。");
          if (state.titleJobs.get(id) !== job) return;
          if (state.session?.id === id && state.session.board?.source_seat)
            value = state.session.board.title;
          state.titles.set(id, value);
          state.titleErrors.delete(id);
          const summary = state.sessions.find((item) => item.id === id);
          if (summary) summary.title = value;
          if (state.session?.id === id) state.session.title = value;
          renderHistory();
        } catch (error) {
          if (state.titleJobs.get(id) === job)
            state.titleErrors.set(id, error.message || "标题生成失败。");
        } finally {
          job.pending = false;
          renderHistory();
          if (state.selected === id) renderHeading();
          updateHistoryMenu();
          resolve(value);
        }
      }, 120);
    });
    state.titleJobs.set(id, job);
    renderHistory();
    if (state.selected === id) renderHeading();
    updateHistoryMenu();
    return job.promise;
  }
  function renderHistory() {
    const key = JSON.stringify([
      state.selected,
      state.activeProject,
      state.sessions,
      [...state.titleJobs].map(([id, job]) => [
        id,
        job.pending,
        state.titleErrors.has(id),
      ]),
    ]);
    if (key === state.historyKey) return;
    state.historyKey = key;
    const rows = new Map();
    for (const session of state.sessions) {
      const row = document.createElement("div");
      row.className = `history-row${session.id === state.selected ? " selected" : ""}`;
      row.dataset.sessionId = session.id;
      const button = document.createElement("button");
      button.className = "history-item";
      button.type = "button";
      button.id = historyId("open", session.id);
      if (session.id === state.selected)
        button.setAttribute("aria-current", "page");
      const title = document.createElement("span");
      title.className = "history-topic";
      title.textContent = sessionTitle(session);
      button.append(title);
      button.addEventListener("click", () => openSession(session.id));
      const more = document.createElement("button");
      more.className = "history-more icon-button";
      more.type = "button";
      more.id = historyId("more", session.id);
      more.setAttribute("aria-label", `${sessionTitle(session)}的更多操作`);
      more.setAttribute("aria-haspopup", "menu");
      more.setAttribute(
        "aria-expanded",
        String(state.menuSession === session.id),
      );
      more.title = "更多操作";
      more.innerHTML = icon("more");
      more.addEventListener("click", (event) => {
        event.stopPropagation();
        openHistoryMenu(session.id, { opener: more });
      });
      const menuKey = (event) => {
        if (
          event.key === "ContextMenu" ||
          (event.shiftKey && event.key === "F10") ||
          (event.target === more && event.key === "ArrowDown")
        ) {
          event.preventDefault();
          event.stopPropagation();
          openHistoryMenu(session.id, { opener: more });
        }
      };
      row.addEventListener("contextmenu", (event) => {
        event.preventDefault();
        event.stopPropagation();
        openHistoryMenu(session.id, {
          x: event.clientX,
          y: event.clientY,
          opener: more,
        });
      });
      row.addEventListener("keydown", menuKey);
      row.append(button, more);
      rows.set(session.id, row);
    }
    projects.render(state.sessions, rows, state.selected, state.activeProject);
  }
  function menuSummary() {
    return (
      state.sessions.find((session) => session.id === state.menuSession) ||
      (state.session?.id === state.menuSession ? state.session : null)
    );
  }
  function updateHistoryMenu() {
    if (!state.menuSession) return;
    const summary = menuSummary(),
      path = summary?.project || "";
    $("menu-project-path").textContent = path || "未记录项目路径";
    $("menu-project-path").title = path;
    $("menu-view-project").disabled = !path;
    $("menu-copy-project").disabled = !path;
    const canRetry =
      summary?.status !== "closed" &&
      state.enteredSessions.has(state.menuSession) &&
      !state.titles.has(state.menuSession) &&
      !cleanTitle(summary?.title);
    $("menu-regenerate-title").hidden = !canRetry;
    $("title-menu-separator").hidden = !canRetry;
    $("menu-regenerate-title").disabled = Boolean(
      state.titleJobs.get(state.menuSession)?.pending,
    );
    $("menu-regenerate-title").textContent = state.titleJobs.get(
      state.menuSession,
    )?.pending
      ? "正在命名…"
      : "重试命名";
    $("menu-regenerate-title").title =
      state.titleErrors.get(state.menuSession) || "";
  }
  function menuItems() {
    return [
      $("menu-view-project"),
      $("menu-copy-project"),
      $("menu-regenerate-title"),
    ].filter((button) => !button.disabled && !button.hidden);
  }
  function openHistoryMenu(id, { x, y, opener } = {}) {
    closeHistoryMenu(false);
    state.menuSession = id;
    state.menuOpener = opener;
    updateHistoryMenu();
    if (opener) opener.setAttribute("aria-expanded", "true");
    const menu = $("history-menu");
    menu.hidden = false;
    const point = opener?.getBoundingClientRect?.() || { left: 8, bottom: 8 };
    const rect = menu.getBoundingClientRect();
    menu.style.left = `${Math.max(8, Math.min(x ?? point.left, innerWidth - rect.width - 8))}px`;
    menu.style.top = `${Math.max(8, Math.min(y ?? point.bottom, innerHeight - rect.height - 8))}px`;
    (menuItems()[0] || menu).focus({ preventScroll: true });
  }
  function closeHistoryMenu(restoreFocus = true) {
    const opener = state.menuOpener,
      id = state.menuSession;
    $("history-menu").hidden = true;
    state.menuSession = null;
    state.menuOpener = null;
    const current = id ? document.getElementById(historyId("more", id)) : null;
    if (current) current.setAttribute("aria-expanded", "false");
    if (restoreFocus)
      (current || (opener?.isConnected ? opener : null))?.focus({
        preventScroll: true,
      });
  }
  function showHistoryFeedback(text) {
    clearTimeout(state.actionToast);
    $("history-action-status").textContent = text;
    $("history-action-status").hidden = false;
    state.actionToast = setTimeout(() => {
      $("history-action-status").hidden = true;
    }, 1800);
  }
  function showProjectPath(summary, opener = state.menuOpener) {
    if (!summary?.project) return;
    state.dialogOpener = opener?.id || historyId("more", summary.id);
    closeHistoryMenu(false);
    $("project-dialog-path").value = summary.project;
    $("project-copy-status").textContent = "";
    if (!$("project-dialog").open) $("project-dialog").showModal();
    $("project-dialog-path").focus({ preventScroll: true });
  }
  async function copyProjectPath(path, summary, opener) {
    if (!path) return;
    try {
      if (!navigator.clipboard?.writeText)
        throw new Error("clipboard unavailable");
      await navigator.clipboard.writeText(path);
      if ($("project-dialog").open)
        $("project-copy-status").textContent = "已复制";
      else showHistoryFeedback("项目路径已复制");
    } catch (_) {
      if (!$("project-dialog").open)
        showProjectPath(summary || { project: path }, opener);
      $("project-dialog-path").focus({ preventScroll: true });
      $("project-dialog-path").select();
      $("project-copy-status").textContent = "路径已选中，请按 ⌘C 复制。";
    }
  }
  async function loadHistory() {
    const result = await api("/sessions");
    state.sessions = result.sessions || [];
    window.RoundtableRecovery.render(result.unreadable_sessions);
    renderHistory();
  }
  function settingsToForm() {
    const settings = state.settings;
    if (!settings) return;
    state.settingsDirty = false;
    $("setting-appearance").value = settings.appearance || "system";
    colorThemeControl.value = settings.color_theme || "iris";
    $("setting-text-size").value = settings.text_size || "standard";
    appearance.setMode($("setting-appearance").value, true);
    appearance.setColorTheme(colorThemeControl.value, true);
    appearance.setTextSize($("setting-text-size").value, true);
    $("setting-allow-edits").checked = Boolean(settings.allow_edits);
    setup.setEditingAllowed(Boolean(settings.allow_edits));
    for (const [id, key] of [
      ["setting-max-children", "max_children"],
      ["setting-max-steps", "max_steps"],
      ["setting-timeout", "timeout"],
    ]) {
      $(id).value = settings[key] ?? "";
    }
    renderSeats();
    updateControls();
  }

  function settingsPatch() {
    return {
      appearance: $("setting-appearance").value,
      color_theme: colorThemeControl.value,
      text_size: $("setting-text-size").value,
      allow_edits: $("setting-allow-edits").checked,
      max_children: Number($("setting-max-children").value),
      max_steps: Number($("setting-max-steps").value),
      timeout: Number($("setting-timeout").value),
    };
  }

  function changedSettings() {
    if (!state.settings) return false;
    const patch = settingsPatch();
    const baseline = {
      ...state.settings,
      appearance: state.settings.appearance || "system",
      color_theme: state.settings.color_theme || "iris",
      text_size: state.settings.text_size || "standard",
    };
    return Object.entries(patch).some(([key, value]) => value !== baseline[key]);
  }

  function updateSettingsNavigation() {
    if (!state.settings) return;
    const patch = settingsPatch();
    const collaborationChanged = ["allow_edits", "max_children", "max_steps", "timeout"]
      .some((key) => patch[key] !== state.settings[key]);
    const appearanceChanged = patch.appearance !== (state.settings.appearance || "system") ||
      patch.color_theme !== (state.settings.color_theme || "iris") ||
      patch.text_size !== (state.settings.text_size || "standard");
    for (const tab of document.querySelectorAll(".settings-nav-item")) {
      const key = tab.dataset.settingsPage;
      tab.dataset.unsaved = String(
        (key === "collaboration" && collaborationChanged) ||
        (key === "appearance" && appearanceChanged),
      );
    }
  }

  function setSettingsSaveState(text) {
    for (const status of document.querySelectorAll(".settings-save-state"))
      status.textContent = text;
  }

  const settingsOverview = {
    checkedAt: 0,
    loading: false,
    modelsKey: null,
    modelRequest: 0,
    agent: null,
    agentAction: false,
    agentRequest: 0,
  };

  function setSettingsStatus(id, label, tone = "") {
    const status = $(id);
    status.textContent = label;
    status.className = `settings-status ${tone}`;
  }

  function setSettingsNote(id, text) {
    const note = $(id);
    note.textContent = text;
    note.hidden = !text;
  }

  async function loadSettingsModels() {
    const request = ++settingsOverview.modelRequest;
    try {
      const result = await api("/models");
      if (request !== settingsOverview.modelRequest) return;
      const models = Array.isArray(result.models) ? result.models : [];
      const list = $("magpie-model-list");
      list.replaceChildren();
      for (const model of models) {
        const row = document.createElement("li");
        row.textContent = model.label || model.id;
        if (model.label && model.label !== model.id) {
          const id = document.createElement("small");
          id.textContent = model.id;
          row.append(id);
        }
        list.append(row);
      }
      if (!models.length) {
        const empty = document.createElement("li");
        empty.textContent = "目录为空";
        list.append(empty);
      }
      setSettingsStatus("magpie-connection", "已连接", "settings-ready");
      setSettingsNote("magpie-connection-detail", "");
      $("magpie-model-count").textContent = `${models.length} 个模型`;
      $("magpie-models").hidden = false;
      const key = JSON.stringify([result.default_model, models]);
      if (settingsOverview.modelsKey !== key) {
        settingsOverview.modelsKey = key;
        window.dispatchEvent(new Event("roundtable:models-changed"));
      }
    } catch (error) {
      if (request !== settingsOverview.modelRequest) return;
      $("magpie-models").hidden = true;
      $("magpie-model-list").replaceChildren();
      setSettingsStatus("magpie-connection", "目录暂不可用", "settings-warning");
      setSettingsNote("magpie-connection-detail", error.message);
      if (settingsOverview.modelsKey !== null) {
        settingsOverview.modelsKey = null;
        window.dispatchEvent(new Event("roundtable:models-changed"));
      }
    }
  }

  function renderMagpieAgent(result, error = "") {
    const open = $("open-magpie");
    const register = $("register-magpie-agent");
    open.disabled = settingsOverview.agentAction || !result?.can_open;
    register.disabled = settingsOverview.agentAction;
    register.hidden = !result?.can_install;
    if (error) {
      setSettingsStatus("magpie-agent-status", "状态暂不可用", "settings-warning");
      setSettingsNote("magpie-agent-detail", error);
      return;
    }
    const label = result.connected
      ? "已连接"
      : result.registered
        ? "已注册，等待连接"
        : result.installed && !result.enabled
          ? "未启用"
          : result.installed
            ? "等待 Magpie 加载"
            : "未注册";
    setSettingsStatus(
      "magpie-agent-status",
      label,
      result.connected || result.registered ? "settings-ready" : "",
    );
    setSettingsNote(
      "magpie-agent-detail",
      !result.connected && (result.installed || !result.can_install)
        ? result.detail || ""
        : "",
    );
  }

  async function loadMagpieAgent() {
    if (settingsOverview.agentAction) return;
    const request = ++settingsOverview.agentRequest;
    try {
      const result = await api("/magpie-agent");
      if (request !== settingsOverview.agentRequest) return;
      settingsOverview.agent = result;
      renderMagpieAgent(result);
    } catch (error) {
      if (request === settingsOverview.agentRequest)
        renderMagpieAgent(settingsOverview.agent, error.message);
    }
  }

  async function magpieAgentAction(action) {
    if (settingsOverview.agentAction) return;
    settingsOverview.agentAction = true;
    settingsOverview.agentRequest++;
    settingsOverview.checkedAt = 0;
    $("open-magpie").disabled = true;
    $("register-magpie-agent").disabled = true;
    let errorMessage = "";
    try {
      settingsOverview.agent = await api("/magpie-agent", action);
    } catch (error) {
      errorMessage = error.message;
    } finally {
      settingsOverview.agentAction = false;
      renderMagpieAgent(settingsOverview.agent, errorMessage);
    }
    if (!errorMessage && !action.action) await loadSettingsModels();
  }

  function renderClients(clients) {
    const list = $("clients-list");
    list.replaceChildren();
    const installed = clients
      .filter((client) => client.installed === true)
      .sort((a, b) => a.name.localeCompare(b.name));
    for (const client of installed) {
      const row = document.createElement("li");
      row.className = "client-row";
      const src = assetFor(client.id);
      if (src) {
        const tile = document.createElement("span");
        tile.className = "client-logo";
        const image = document.createElement("img");
        image.src = src;
        image.alt = "";
        image.width = 24;
        image.height = 24;
        tile.append(image);
        row.append(tile);
      }
      const identity = document.createElement("div");
      identity.className = "client-identity";
      const name = document.createElement("strong");
      name.textContent = client.name;
      identity.append(name);
      if (client.path) {
        const path = document.createElement("small");
        path.textContent = client.path;
        path.title = client.path;
        identity.append(path);
      }
      const status = document.createElement("span");
      status.className = "settings-status";
      if (client.state === "ready") {
        status.classList.add("settings-ready");
        status.textContent = client.version ? `可运行 · ${client.version}` : "可运行";
      } else if (client.state === "check_failed") {
        status.classList.add("settings-warning");
        status.textContent = "已安装 · 检查失败";
      } else {
        status.textContent = "已安装 · 版本未检查";
      }
      row.append(identity, status);
      list.append(row);
    }
    setSettingsNote("clients-state", installed.length ? "" : "未找到已安装的 CLI");
  }

  async function loadClients() {
    try {
      const result = await api("/cli-health");
      renderClients(result.clients || []);
    } catch (error) {
      setSettingsNote("clients-state", error.message);
    }
  }

  async function refreshSettingsOverview() {
    if (
      state.view !== "settings" ||
      document.hidden ||
      settingsOverview.loading ||
      Date.now() - settingsOverview.checkedAt < 30000
    ) return;
    settingsOverview.loading = true;
    try {
      await Promise.allSettled([loadSettingsModels(), loadMagpieAgent(), loadClients()]);
    } finally {
      settingsOverview.loading = false;
      settingsOverview.checkedAt = Date.now();
    }
  }
  const contextDrawers = {
    "participants-toggle": "participants-panel",
    "agenda-toggle": "agenda-drawer",
    "progress-toggle": "progress-drawer",
  };
  function showRoomDrawer(active = "") {
    for (const [toggle, panel] of Object.entries(contextDrawers)) {
      const expanded = toggle === active;
      $(toggle).setAttribute("aria-expanded", String(expanded));
      $(panel).hidden = !expanded;
    }
  }
  function resetRoomDisclosures() {
    showRoomDrawer();
    meetingActions.close();
    runCommands.close();
    window.RoundtableOpinions?.close({restoreFocus:false});
    seatMention.setContext();
  }
  for (const [toggle, panel] of Object.entries(contextDrawers)) {
    $(toggle).addEventListener("click", () => showRoomDrawer($(panel).hidden ? toggle : ""));
  }
  $("chat-header").addEventListener("keydown", event => {
    if (event.key !== "Escape" || event.defaultPrevented) return;
    const active = Object.keys(contextDrawers).find(toggle => !$(contextDrawers[toggle]).hidden);
    if (active) {
      event.preventDefault();
      showRoomDrawer();
      $(active).focus();
    }
  });

  function loadLegacyRoster(session) {
    if (session.members?.length || !session.seats?.length) return;
    const previous = state.legacyRosters.get(session.id);
    const key = JSON.stringify([session.status, session.rounds?.at(-1)?.number,
      session.seat_overrides, state.settings?.models, state.settings?.efforts]);
    if (previous?.key === key) return;
    const request = {key, members:previous?.members || []};
    state.legacyRosters.set(session.id, request);
    api(`/sessions/${encodeURIComponent(session.id)}/members`).then(result => {
      if (state.legacyRosters.get(session.id) !== request) return;
      request.members = Array.isArray(result.members) ? result.members : [];
      if (state.session?.id === session.id) renderSeats();
    }).catch(() => {
      // The saved seat and turn remain readable when the legacy settings lookup is unavailable.
    });
  }

  function paintSeatAvailability() {
    const enabled = !state.writing && window.RoundtableMemberEditor.canEdit(state.session);
    for (const button of $("member-seats").querySelectorAll(".seat-edit")) {
      button.disabled = !enabled;
      button.title = enabled ? button.getAttribute("aria-label") : "会议空闲时可更改席位";
    }
    seatEditor.update(state.session, state.writing);
  }

  function renderSeats() {
    const members = sessionMembers(), session = state.session;
    $("chat-header").hidden = !session;
    if (!session) {
      seatEditor.update(null, state.writing);
      return;
    }
    loadLegacyRoster(session);
    const orbit = $("member-orbit"), cards = $("member-seats");
    const identities = JSON.stringify([session.id, members]);
    if (cards.dataset.members !== identities) {
      cards.dataset.members = identities;
      const focused = cards.contains(document.activeElement) ? document.activeElement.id : "";
      orbit.replaceChildren();
      cards.replaceChildren();
      for (const [index, member] of members.entries()) {
        const id = member.id, label = seatName(id);
        const src = memberAsset(id);
        const pic = (className) => {
          const node = document.createElement(src ? "img" : "span");
          node.className = className;
          if (src) { node.src = src; node.alt = ""; }
          else {
            node.classList.add("neutral-model");
            node.setAttribute("aria-hidden", "true");
            node.innerHTML = icon("model");
          }
          return node;
        };
        if (index < 3) orbit.append(pic("context-avatar"));
        const card = document.createElement("article");
        card.className = "seat"; card.id = "seat-" + id;
        card.dataset.memberId = id;
        const identity = document.createElement("div"); identity.className = "seat-identity";
        const copy = document.createElement("div"); copy.className = "seat-copy";
        const primary = document.createElement("div"); primary.className = "seat-primary";
        const name = document.createElement("strong"); name.textContent = label; name.title = label;
        primary.append(name);
        if (index === 0) {
          const chief = document.createElement("span"); chief.className = "chief-label"; chief.textContent = "首席"; primary.append(chief);
        }
        const model = document.createElement("div"); model.className = "seat-model";
        model.textContent = [member.model && member.model !== member.label ? member.model : "",
          member.effort ? window.RoundtableSetup.effortName(member.effort) : ""].filter(Boolean).join(" · ");
        model.title = model.textContent;
        copy.append(primary, model);
        identity.append(pic("person-avatar"), copy);
        const status = document.createElement("div"); status.className = "seat-status";
        const indicator = document.createElement("span"); indicator.className = "seat-indicator"; indicator.setAttribute("aria-hidden", "true");
        const stateLabel = document.createElement("span"); stateLabel.id = "status-" + id;
        status.append(indicator, stateLabel);
        const actions = document.createElement("div"); actions.className = "seat-row-actions";
        const edit = document.createElement("button"); edit.type = "button"; edit.className = "text-button seat-edit";
        edit.id = "seat-edit-" + id;
        const editDetail = document.createElement("span"); editDetail.className = "seat-edit-detail"; editDetail.textContent = "与思考";
        edit.append("模型", editDetail);
        edit.setAttribute("aria-label", `编辑 ${label} 的模型与思考程度`);
        edit.setAttribute("aria-haspopup", "dialog");
        edit.addEventListener("click", () => seatEditor.open(state.session, id, edit));
        const children = document.createElement("button"); children.type = "button";
        children.className = "button secondary small child-entry";
        children.id = `children-open-${id}-all`;
        children.setAttribute("aria-controls", "children-panel");
        children.setAttribute("aria-haspopup", "dialog");
        children.addEventListener("click", () => openChildren({seat:id, opener:children}));
        actions.append(edit, children);
        card.append(identity, status, actions); cards.append(card);
      }
      state.seatKeys = {};
      $("seats-label").textContent = "席位 " + members.length;
      if (focused) $(focused)?.focus({preventScroll:true});
    }
    const round = latestRound(), turns = round?.turns || [];
    const running = session.status === "running";
    const drafting = session.agenda_draft_status === "drafting";
    $("table-center-state").dataset.busy = String(drafting || running);
    for (const member of members) {
      const id = member.id;
      const turn = turns.find(item => item.seat === id);
      const draftingChair = drafting && id === members[0]?.id;
      const active = draftingChair || (running && turn?.status === "running");
      const node = $("seat-" + id);
      const handoff = Boolean(member.previous_model && (session.rounds || []).every(item =>
        item.number <= (member.switched_after_round || 0) || (item.turns || []).every(t => t.seat !== id)));
      node.classList.toggle("active", active);
      node.classList.toggle("error", !handoff && turn?.status === "error");
      const status = $("status-" + id);
      status.textContent = draftingChair ? "起草中" : active ? "工作中" : session.status === "closed" ? "已结束" :
        handoff ? "待接续" : turn ? statusText(turn.status) : round ? "旁听本轮" : "已入席";
      status.title = handoff ? `该席由 ${member.previous_model} 更换至 ${member.model}，新模型将在下次发言时接续公开上下文` : "";
      const tasks = (session.rounds || []).flatMap(item =>
        (item.turns || []).filter(t => t.seat === id).flatMap(t => t.children || []));
      const summary = window.RoundtableChildren?.summary?.(tasks);
      const key = JSON.stringify([tasks.length, summary]);
      if (state.seatKeys[id] !== key) {
        state.seatKeys[id] = key;
        const button = $(`children-open-${id}-all`);
        button.innerHTML = `${icon("subagent")}<span>子代理${tasks.length ? ` ${tasks.length}` : ""}</span>`;
        button.dataset.childEntryState = summary?.state || (tasks.length ? "complete" : "empty");
        button.setAttribute("aria-label", `${seatName(id)} 的子代理${summary?.label ? `，${summary.label}` : ""}`);
        button.title = summary?.label || "查看该席位的子代理";
      }
    }
    paintSeatAvailability();
    const activeSeats = turns.filter(turn => turn.status === "running").map(turn => seatName(turn.seat));
    $("table-center-state").textContent = activeSeats.length ? activeSeats.join("、") + " 正在工作" :
      session.status === "closed" ? "会议已结束" : drafting ? "会前准备中" : running ? "正在准备工作" : round ? "等待你的下一步" : "等待开始";
  }
  function inline(text) {
    return escape(text)
      .replace(/`([^`\n]+)`/g, "<code>$1</code>")
      .replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>")
      .replace(
        /\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g,
        '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>',
      );
  }
  function markdown(text, { report = false } = {}) {
    let html = "",
      paragraph = [],
      code = null,
      list = "";
    const flush = () => {
      if (paragraph.length) {
        html += `<p>${inline(paragraph.join("\n"))}</p>`;
        paragraph = [];
      }
    };
    const close = () => {
      if (list) {
        html += `</${list}>`;
        list = "";
      }
    };
    for (const line of String(text || "").split("\n")) {
      if (/^\s*```/.test(line)) {
        flush();
        close();
        if (code === null) code = [];
        else {
          html += `<pre><code>${escape(code.join("\n"))}</code></pre>`;
          code = null;
        }
        continue;
      }
      if (code !== null) {
        code.push(line);
        continue;
      }
      if (!line.trim()) {
        flush();
        close();
        continue;
      }
      const heading = line.match(/^(#{1,6})\s+(.+)$/);
      if (heading) {
        flush();
        close();
        const level = report ? Math.min(6, heading[1].length + 2) : 4;
        html += `<h${level}>${inline(heading[2])}</h${level}>`;
        continue;
      }
      if (report && /^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/.test(line)) {
        flush();
        close();
        html += "<hr>";
        continue;
      }
      if (report && line.startsWith("> ")) {
        flush();
        close();
        html += `<blockquote>${inline(line.slice(2))}</blockquote>`;
        continue;
      }
      const item = line.match(/^\s*(?:([-*+])|\d+[.)])\s+(.+)$/);
      if (item) {
        flush();
        const type = item[1] ? "ul" : "ol";
        if (list !== type) {
          close();
          list = type;
          html += `<${type}>`;
        }
        html += `<li>${inline(item[2])}</li>`;
        continue;
      }
      close();
      paragraph.push(line);
    }
    flush();
    close();
    if (code !== null)
      html += `<pre><code>${escape(code.join("\n"))}</code></pre>`;
    return html;
  }
  function modelChanges(session) {
    const changes = [];
    for (const round of session?.rounds || [])
      for (const turn of round.turns || [])
        for (const [index, change] of (turn.changes || []).entries())
          changes.push({
            ...change,
            round: round.number,
            seat: turn.seat,
            revision: `${round.number}:${turn.seat}:${index}`,
            at: turn.finished_at || round.created_at,
          });
    return changes;
  }
  const closedFileCatalogs = new WeakMap();
  function closedFileCatalog(session) {
    if (closedFileCatalogs.has(session)) return closedFileCatalogs.get(session);
    const applied = new Map();
    const changeKey = (seat, change) => JSON.stringify([seat, change.path, change.before, change.after]);
    const eventTimes = new Map((session.events || [])
      .filter(event => event.operation_id && ["write", "user_write"].includes(event.type))
      .map(event => [event.operation_id, event.at]));
    for (const [index, operation] of (session.operations || []).entries()) {
      if (operation.status !== "applied" || !operation.change) continue;
      const key = changeKey(operation.seat, operation.change);
      const list = applied.get(key) || [];
      list.push({ index, round: operation.round, at: eventTimes.get(operation.id) });
      applied.set(key, list);
    }
    // Report IDs enumerate model changes in round order, followed by host saves.
    const cited = [
      ...modelChanges(session),
      ...(session.user_changes || []).map(({ change, at }, index) => ({
        ...change,
        at,
        seat: "user",
        revision: `user:${index}`,
      })),
    ];
    for (const change of cited) {
      const operation = applied.get(changeKey(change.seat, change))?.shift();
      if (!operation) continue;
      if (change.seat === "user") change.round = operation.round;
      change.operationIndex = operation.index;
      change.at = operation.at || change.at;
    }
    const reviewable = cited.filter(change => change.path);
    const orderedByWrite = reviewable.every(change => Number.isInteger(change.operationIndex));
    const orderedByTime = reviewable.every(change => Number.isFinite(Date.parse(change.at)));
    if (orderedByWrite) reviewable.sort((a, b) => a.operationIndex - b.operationIndex);
    else if (orderedByTime) reviewable.sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
    const catalog = { cited, reviewable, hasChronology: orderedByWrite || orderedByTime };
    closedFileCatalogs.set(session, catalog);
    return catalog;
  }
  function allChanges() {
    return state.session?.status === "closed" ? closedFileCatalog(state.session).reviewable : modelChanges(state.session);
  }
  function openChildren({
    seat = "",
    round = null,
    opener = document.activeElement,
  } = {}) {
    if (!state.session || !window.RoundtableChildren) return;
    closeChanges(false);
    window.RoundtableChildren.open({
      session: state.session,
      seat,
      round,
      opener,
    });
  }
  function memberAvatar({asset:src, model}) {
    const content = src ? `<img src="${src}" alt="">` : icon("model");
    return `<span class="message-avatar${src ? "" : " neutral-model"}" aria-hidden="true" title="${escape(model)}">${content}</span>`;
  }
  function messageTime(value) {
    if (!value) return "";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "";
    return `<time class="message-time" datetime="${escape(value)}" title="${escape(date.toLocaleString("zh-CN"))}">${escape(date.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" }))}</time>`;
  }
  function hostMessage(text, at, target = "", round = 0, automatic = false) {
    const article = document.createElement("article");
    article.className = "message host-message";
    if (round) article.id = `round-${round}-host`;
    const recipient = target && (round ? sourceIdentity(target, state.session, round).label : seatName(target));
    const label = automatic ? "持续推进 · 下一轮任务" : recipient ? `→ ${recipient}` : "";
    article.innerHTML = `<span class="message-avatar" aria-hidden="true">${icon(automatic ? "refresh" : "person")}</span><div class="message-content"><header class="message-header">${label ? `<strong>${escape(label)}</strong>` : ""}${messageTime(at)}</header><div class="message-body">${markdown(text)}</div></div>`;
    return article;
  }
  function renderRounds() {
    const session = state.session,
      rounds = session?.rounds || [];
    $("no-rounds").hidden = rounds.length > 0 || session?.agenda_draft_status === "drafting";
    const key = JSON.stringify([
      session?.topic, session?.members, rounds, session?.events, session?.status === "running",
    ]);
    if (state.roundsKey === key) return;
    const firstRender = state.roundsKey === "";
    state.roundsKey = key;
    const scroll = $("table-scroll"),
      previousTop = scroll.scrollTop;
    const nearBottom =
      scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 110;
    const openDetails = new Set(
      [...$("rounds").querySelectorAll("details[open]")].map(
        (node) => node.dataset.key,
      ),
    );
    $("rounds").replaceChildren();
    if (session?.topic)
      $("rounds").append(hostMessage(session.topic, session.created_at));
    let currentRound = 0;
    const eventRounds = new Map();
    for (const event of session?.events || []) {
      if (event.type === "round_started")
        currentRound = event.round || currentRound + 1;
      eventRounds.set(event, event.round || currentRound);
    }
    let latestUseful = null;
    for (const round of rounds) {
      const section = document.createElement("section");
      section.className = "round";
      section.id = `round-${round.number}`;
      const title = document.createElement("h2");
      title.className = "sr-only";
      title.textContent = `第 ${round.number} 轮`;
      section.append(title);
      const actual = roundDiscussion(round);
      const context = document.createElement("details");
      context.className = "round-discussion-context";
      context.dataset.key = "round-info-" + round.number;
      context.open = openDetails.has(context.dataset.key);
      const roundLabel = document.createElement("summary");
      roundLabel.textContent = `第 ${round.number} 轮`;
      const roundMode = document.createElement("span");
      const access = actual.preset === "work" && round.settings?.allow_edits ? "可写" : "只读";
      roundMode.textContent = `${discussionPresets[actual.preset].label}${actual.preset !== "work" ? ` · ${discussionPresets[actual.preset].phases[actual.phase]}` : ""} · ${access}`;
      context.append(roundLabel, roundMode);
      if (round.project_rules?.length) {
          const details = document.createElement("details");
          details.className = "round-project-rules";
          details.dataset.key = `${round.number}-project-rules`;
          details.open = openDetails.has(details.dataset.key);
          const summary = document.createElement("summary");
          summary.textContent = `项目规则 · ${round.project_rules.length} 条`;
          const versions = document.createElement("ul");
          for (const rule of round.project_rules) {
            const entry = document.createElement("li");
            const digest = document.createElement("code");
            digest.textContent = rule.digest;
            entry.append(`${rule.path} · `, digest);
            versions.append(entry);
          }
          details.append(summary, versions);
          context.append(details);
      }
      if (round.plugin_guidance?.length) {
        const details = document.createElement("details");
        details.className = "round-project-rules round-plugin-guidance";
        details.dataset.key = round.number + "-plugin-guidance";
        details.open = openDetails.has(details.dataset.key);
        const summary = document.createElement("summary");
        summary.textContent = "本轮插件 · " + round.plugin_guidance.length + " 个";
        const items = document.createElement("ul");
        for (const plugin of round.plugin_guidance) {
          const entry = document.createElement("li");
          const name = document.createElement("strong");
          name.textContent = (plugin.name || plugin.id) + " · " + plugin.version;
          const guidance = document.createElement("p");
          guidance.textContent = plugin.round_guidance;
          entry.append(name, guidance);
          items.append(entry);
        }
        details.append(summary, items);
        context.append(details);
      }
      section.append(context);
      if (round.note)
        section.append(hostMessage(round.note, round.created_at, round.target, round.number, round.auto === true));
      const turns = (round.turns || [])
        .map((turn, index) => ({ turn, index }))
        .sort((a, b) => {
          const first = Date.parse(a.turn.started_at),
            second = Date.parse(b.turn.started_at);
          return Number.isFinite(first) && Number.isFinite(second)
            ? first - second
            : a.index - b.index;
        });
      for (const { turn } of turns) {
        const article = document.createElement("article");
        article.className = "message agent-message";
        article.id = `round-${round.number}-${turn.seat}`;
        const speaker = turnIdentity(turn, session, round);
        const showModel = speaker.model && speaker.model !== speaker.label;
        article.dataset.speakerModel = speaker.model;
        article.dataset.speakerEffort = speaker.effort;
        const progress =
          turn.status === "running"
            ? "正在工作…"
            : turn.status === "error"
              ? "未完成"
              : "";
        article.innerHTML = `${memberAvatar(speaker)}<div class="message-content"><header class="message-header"><strong>${escape(speaker.label)}${showModel ? ` · ${escape(speaker.model)}` : ""}</strong>${messageTime(turn.finished_at || turn.started_at)}${progress ? `<span class="message-status ${turn.status === "error" ? "error" : ""}">${progress}</span>` : ""}</header>${turn.text ? `<div class="message-body">${markdown(turn.text)}</div>` : turn.status === "error" ? "" : `<div class="message-body"><p class="message-placeholder">${turn.status === "pending" ? "等待回应…" : turn.status === "running" ? "正在处理任务…" : "没有返回发言。"}</p></div>`}</div>`;
        const events = (session.events || []).filter(
          (event) =>
            event.seat === turn.seat &&
            eventRounds.get(event) === round.number &&
            !["seat_started", "seat_done"].includes(event.type) &&
            !event.type.startsWith("child_") &&
            !event.type.startsWith("report_"),
        );
        const children = turn.children || [],
          changes = turn.changes || [];
        if (children.length) {
          const button = document.createElement("button");
          button.type = "button";
          button.className = "button secondary small child-entry";
          button.innerHTML = `${icon("subagent")}子代理 ${children.length}`;
          button.id = `children-open-${turn.seat}-${round.number}`;
          const childSummary = window.RoundtableChildren?.summary(children);
          button.setAttribute("aria-controls", "children-panel");
          button.setAttribute("aria-haspopup", "dialog");
          button.setAttribute("aria-expanded", "false");
          if (childSummary) {
            button.dataset.childEntryState = childSummary.state;
            button.title = childSummary.label;
          }
          button.addEventListener("click", () =>
            openChildren({
              seat: turn.seat,
              round: round.number,
              opener: button,
            }),
          );
          article.querySelector(".message-content").append(button);
        }
        if (changes.length || events.length || turn.error) {
          const details = document.createElement("details");
          details.className = "message-work";
          details.dataset.key = `${round.number}-${turn.seat}-work`;
          details.open = openDetails.has(details.dataset.key);
          const summary = document.createElement("summary");
          summary.textContent = [
            changes.length ? `${changes.length} 次修改` : "",
            events.length ? "工具记录" : "",
            turn.error ? "查看错误" : "",
          ]
            .filter(Boolean)
            .join(" · ");
          details.append(summary);
          const inner = document.createElement("div");
          inner.className = "message-work-inner";
          if (turn.error) {
            const error = document.createElement("div");
            error.className = "turn-error";
            error.textContent = detailText(turn.error);
            inner.append(error);
          }
          if (events.length) {
            const heading = document.createElement("h4");
            heading.textContent = "工具记录";
            inner.append(heading);
            for (const event of events) {
              const line = document.createElement("div");
              line.className = "tool-event";
              line.textContent = activityEvent(event).text;
              inner.append(line);
            }
          }
          if (changes.length) {
            const heading = document.createElement("h4");
            heading.textContent = "文件改动";
            inner.append(heading);
            for (const [changeIndex, change] of changes.entries()) {
              const button = document.createElement("button");
              button.type = "button";
              button.className = "turn-change";
              button.textContent = `${change.path} ↗`;
              button.addEventListener("click", () => {
                openChanges(
                  {
                    ...change,
                    round: round.number,
                    seat: turn.seat,
                    revision: `${round.number}:${turn.seat}:${changeIndex}`,
                  },
                  button,
                );
              });
              inner.append(button);
            }
          }
          details.append(inner);
          article.querySelector(".message-content").append(details);
        }
        section.append(article);
        if (turn.text) latestUseful = article;
      }
      const checkpoint = round.checkpoint;
      if (checkpoint?.items?.length) {
        const details = document.createElement("details");
        details.className = "round-checkpoint";
        details.dataset.key = `${round.number}-checkpoint`;
        details.open = openDetails.has(details.dataset.key);
        const summary = document.createElement("summary");
        const through = Number(checkpoint.through_round) || round.number;
        summary.textContent = `阶段摘要 · 截至第 ${through} 轮`;
        const list = document.createElement("ul");
        for (const item of checkpoint.items) {
          const row = document.createElement("li");
          row.append(document.createTextNode(item.text || ""));
          if (item.round && item.seat) {
            const source = document.createElement("button");
            source.type = "button";
            source.className = "continuous-source";
            source.textContent = `第 ${item.round} 轮 · ${sourceIdentity(item.seat, session, item.round, item).label}`;
            source.addEventListener("click", () => {
              const navigated = window.RoundtableReferences?.jump?.(Number(item.round), item.seat, item.model);
              if (!navigated) {
                const target = document.getElementById(`round-${item.round}-${item.seat}`);
                target?.scrollIntoView({behavior:"smooth", block:"center"});
                target?.focus({preventScroll:true});
              }
            });
            row.append(document.createTextNode(" "), source);
          }
          list.append(row);
        }
        details.append(summary, list);
        section.append(details);
      }
      $("rounds").append(section);
    }
    reportUI.linkStatements($("rounds"), session);
    if (state.anchor) {
      state.anchor = "";
      requestAnimationFrame(scrollAnchor);
    } else if (firstRender || nearBottom)
      requestAnimationFrame(() => {
        if (firstRender && latestUseful) scrollToMessage(latestUseful, "end");
        else scroll.scrollTop = scroll.scrollHeight;
        $("latest-message").hidden = true;
      });
    else
      requestAnimationFrame(() => {
        scroll.scrollTop = previousTop;
        $("latest-message").hidden = false;
      });
    const changes = allChanges();
    const count = new Set(changes.map((change) => change.path)).size;
    $("files-toggle").hidden = !count;
    $("change-count").hidden = !count;
    $("change-count").textContent = count;
    const reviewLabel = `查看 ${count} 个文件的改动`;
    $("files-toggle").setAttribute("aria-label", reviewLabel);
    $("files-toggle").title = reviewLabel;
    if (!count) closeChanges(false);
    renderChanges();
  }
  const discussionPresets = {
    work: { label: "项目协作", phases: { work: "项目协作" } },
    review: { label: "方案评审", phases: { proposal: "独立提案", challenge: "检验异议", synthesis: "汇总建议" } },
    prioritize: { label: "优先级排序", phases: { proposal: "独立排序", challenge: "核对标准", synthesis: "汇总排序" } },
    forum: { label: "多方权衡", phases: { proposal: "独立立场", challenge: "比较取舍", synthesis: "汇总分歧" } },
  };
  function roundDiscussion(round) {
    const preset = Object.hasOwn(discussionPresets, round?.preset) ? round.preset : "work";
    const phase = preset === "work" ? "work" : Object.hasOwn(discussionPresets[preset].phases, round?.phase) ? round.phase : "proposal";
    return { preset, phase };
  }
  function activeItem(session) {
    return session?.agenda?.find(item => item.id === session.active_agenda_id);
  }
  function itemDiscussion(item, preset) {
    if (item.kind === "implementation") return roundDiscussion({preset:"work"});
    const chosen = item.preset || preset;
    return roundDiscussion({preset:chosen && chosen !== "work" ? chosen : "review", phase:item.phase});
  }
  function discussionChoice() {
    const id = state.selected || "new";
    if (!state.discussionChoices.has(id)) {
      const last = latestRound();
      const active = activeItem(state.session), preset = state.session?.preset || state.session?.agenda_preset;
      const previous = active ? itemDiscussion(active, preset) : roundDiscussion(last || {preset});
      state.discussionChoices.set(id, {
        preset: previous.preset,
        phases: { review: "proposal", prioritize: "proposal", forum: "proposal", [previous.preset]: previous.phase },
        observed: 0,
        activeItem: active?.id || "",
      });
    }
    return state.discussionChoices.get(id);
  }
  function syncDiscussionRound(session) {
    const choice = discussionChoice();
    const active = activeItem(session);
    if ((active?.id || "") !== choice.activeItem) {
      choice.activeItem = active?.id || "";
      if (active) {
        const next = itemDiscussion(active, session.preset);
        choice.preset = next.preset; choice.phases[next.preset] = next.phase;
      }
    }
    const last = session?.rounds?.at(-1);
    if (!last || sessionWorking(session) || (last.turns || []).some(turn => ["running", "pending"].includes(turn.status))) return;
    if (last.number <= choice.observed) return;
    choice.observed = last.number;
    // Saved template stages advance only when the server has completed that agenda item.
    if (session.agenda?.some(item => item.phase && item.id === last.agenda_item_id)) return;
    const actual = roundDiscussion(last);
    const participants = sessionMembers(session).map(member => member.id);
    const expectedSeats = last.target ? [last.target] : actual.phase === "synthesis" ? participants.slice(0, 1) : participants;
    const complete = last.turns?.length && last.turns.every(turn => turn.status === "done" && !turn.error) && expectedSeats.every(seat => last.turns.some(turn => turn.seat === seat && turn.status === "done"));
    if (complete && actual.preset !== "work" && choice.preset === actual.preset && choice.phases[actual.preset] === actual.phase) {
      choice.phases[actual.preset] = ({ proposal: "challenge", challenge: "synthesis", synthesis: "synthesis" })[actual.phase];
    }
  }
  function paintDiscussionControls() {
    const choice = discussionChoice();
    const preset = discussionPresets[choice.preset];
    const phase = choice.preset === "work" ? "work" : choice.phases[choice.preset];
    $("run-preset").value = choice.preset;
    $("run-phase-field").hidden = choice.preset === "work";
    const phaseKey = choice.preset + ":" + phase;
    if ($("run-phase").dataset.phaseKey !== phaseKey) {
      $("run-phase").replaceChildren(...Object.entries(preset.phases).map(([value, label]) => {
        const option = document.createElement("option"); option.value = value; option.textContent = label; return option;
      }));
      $("run-phase").value = phase;
      $("run-phase").dataset.phaseKey = phaseKey;
    }
    const chief = sessionMembers()[0];
    $("run-note").placeholder = phase === "synthesis" && chief
      ? `默认由首席 ${seatName(chief.id)} 汇总，输入 @ 可点名其他席位…`
      : "发送消息，输入 @ 点名席位…";
    const access = $("run-access");
    const running = sessionWorking();
    const hasProject = Boolean(state.session?.project_id);
    const editable = hasProject && choice.preset === "work" && Boolean(state.settings?.allow_edits);
    const last = running ? latestRound() : null;
    const allowEdits = last
      ? roundDiscussion(last).preset === "work" && last.settings?.allow_edits
      : editable && choice.allowEdits !== false;
    const closed = state.session?.status === "closed";
    const shown = (running || closed) && latestRound() ? roundDiscussion(latestRound()) : choice;
    const shownWrite = closed && latestRound() ? latestRound().settings?.allow_edits : allowEdits;
    $("meeting-mode-label").textContent = discussionPresets[shown.preset].label;
    $("meeting-mode-access").textContent = shownWrite && shown.preset === "work" ? "可写" : "只读";
    $("round-settings").hidden = Boolean(closed);
    access.value = allowEdits ? "write" : "read";
    access.disabled = state.writing || running || !editable;
    access.title = running ? "本轮启动时确定的文件权限" : !hasProject ? "没有已关联的项目目录" : choice.preset !== "work" ? "此预设只读" :
      editable ? "选择模型在本轮是否可以修改项目文件" : "全局设置关闭了模型文件写入";
  }
  function updateControls() {
    const running = sessionWorking();
    reportUI.setBusy(state.writing);
    continuousUI.update(state.session);
    continuousUI.setBusy(state.writing);
    paintRunSubmit();
    paintSeatAvailability();
    const runLocked = state.writing || running || !state.session || state.session.status === "closed";
    $("run-commands").disabled = runLocked;
    runMaterials.setDisabled(runLocked);
    if (runLocked) runCommands.close();
    if (state.writing) createCommands.close();
    if (state.writing || running) seatMention.setContext();
    $("run-preset").disabled = state.writing || running;
    $("run-phase").disabled = state.writing || running;
    paintDiscussionControls();
    paintTextLimit("run-note");
    $("run-note").disabled = state.writing || running;
    $("cancel-run").hidden = !running || continuousUI.isActive();
    $("cancel-run").disabled = state.writing;
    $("run-submit").hidden = running;
    const continuousStatus = state.session?.continuous?.status;
    const continuousRequest = continuousUI.payload(state.session?.topic);
    const progressButton = $("progress-toggle");
    const progressNames = {configured:"已配置持续推进", active:"持续推进中", paused:"推进已暂停", completed:"本段已完成"};
    progressButton.hidden = !progressNames[continuousStatus];
    progressButton.textContent = state.session?.continuous?.manual ? "推进记录" : progressNames[continuousStatus] || "推进记录";
    if (progressButton.hidden && !$("progress-drawer").hidden) showRoomDrawer();
    $("run-submit").textContent = state.writing ? "正在发送…" : continuousRequest
      ? continuousStatus === "completed" ? "再次发起持续推进" : continuousStatus === "paused" ? "继续推进" : "开始持续推进"
      : state.session?.rounds?.length ? "发送" : "开始";
    $("run-hint").textContent = running
      ? continuousUI.isActive() ? "持续推进中，记录会自动更新；可随时暂停" : "本轮进行中，记录会自动更新"
      : continuousRequest ? "持续推进由本机服务按限额执行，可随时暂停" : "每次发起推进一轮";
    setup.setBusy(state.writing);
    for (const button of document.querySelectorAll("#save-settings, #save-settings-appearance"))
      button.disabled = state.writing || !state.settingsDirty;
    updateSettingsNavigation();
  }
  function paintRunSubmit() {
    $("run-submit").disabled = state.writing || sessionWorking() || !state.session ||
      state.session.status === "closed" || state.session.agenda_draft_status === "drafting" ||
      runMaterials.busy() || runMaterials.failed();
  }
  const narrowWorkspace = matchMedia("(max-width: 1000px)");
  const hasBoard = session => session?.board?.state === "published";
  let chatVisible = !narrowWorkspace.matches;
  let pairedChat = false;
  let boardSourceOpener = null;
  function conversationInUse() {
    const focus = document.activeElement;
    return Boolean($("run-form").contains(focus) ||
      ($("room-chat").contains(focus) && focus !== $("table-scroll")) ||
      $("run-note").value || runMaterials.items().length);
  }
  // Match the editor to the transcript even with macOS always-visible scrollbars.
  const chatScroll = $("table-scroll");
  new ResizeObserver(() => {
    const width = chatScroll.offsetWidth - chatScroll.clientWidth;
    $("room-chat").style.setProperty("--chat-scrollbar", width + "px");
  }).observe(chatScroll);
  function paintChatLayout() {
    const loaded = Boolean(state.session);
    const published = hasBoard(state.session);
    const showChat = loaded && (!published || chatVisible);
    const showBoth = published && showChat && narrowWorkspace.matches && pairedChat;
    const table = $("table-view");
    table.dataset.board = !loaded ? "absent" : published ? "published" : "empty";
    table.dataset.chat = showBoth ? "paired" : showChat ? "on" : "off";
    $("meeting-board").hidden = !published || (narrowWorkspace.matches && showChat && !showBoth);
    $("room-chat").hidden = !showChat;
    $("rail-to-board").hidden = !published;
    $("room-chat-toggle").hidden = !published;
    $("room-chat-toggle").setAttribute("aria-expanded", String(showChat));
    $("room-chat-toggle").title = showChat ? "收起会议对话" : "展开会议对话";
    if (!showChat) runCommands.close();
  }
  function setChatVisible(visible, {paired = false} = {}) {
    chatVisible = visible;
    pairedChat = paired;
    paintChatLayout();
  }
  function clearBoard() {
    boardPresence.stop();
    board.clear();
    boardSourceOpener = null;
    $("board-workspace").hidden = true;
    $("setup-scroll").hidden = !state.draftOpen;
    setChatVisible(!narrowWorkspace.matches);
  }
  narrowWorkspace.addEventListener("change", () => {
    const keepChat = conversationInUse();
    setChatVisible(!narrowWorkspace.matches || keepChat, {paired: keepChat && board.isDrawing()});
  });
  function returnToBoard() {
    if (narrowWorkspace.matches || !boardSourceOpener) setChatVisible(false);
    board.focusTrigger(boardSourceOpener);
    boardSourceOpener = null;
  }
  $("room-chat-toggle").addEventListener("click", () => {
    closeChanges(false);
    window.RoundtableOpinions?.close({restoreFocus:false});
    window.RoundtableChildren?.close({restoreFocus:false});
    setChatVisible(!chatVisible);
    if (chatVisible) ($("run-form").hidden ? $("rail-to-board") : $("run-note")).focus();
  });
  $("rail-to-board").addEventListener("click", returnToBoard);
  function updateSession(session, {animateInitial = false} = {}) {
    const current = state.session;
    if (current?.id === session.id && window.RoundtableBoardEdit.snapshotIsOlder(current, session)) return;
    const firstBoard = hasBoard(session) && (animateInitial || (current?.id === session.id && !hasBoard(current)));
    const hadChatFocus = $("room-chat").contains(document.activeElement);
    if (firstBoard) {
      pairedChat = narrowWorkspace.matches && conversationInUse();
      chatVisible = !narrowWorkspace.matches || pairedChat;
    }
    if (state.session?.id !== session.id) resetRoomDisclosures();
    state.session = session;
    state.selected = session.id;
    state.draftOpen = false;
    $("setup-scroll").hidden = true;
    $("board-workspace").hidden = false;
    paintChatLayout();
    setActiveProject(window.RoundtableProjects.sessionProjectKey(session));
    syncDiscussionRound(session);
    $("stage-layout").classList.remove("is-new");
    $("create-form").hidden = true;
    $("draft-project-required").hidden = true;
    $("session-content").hidden = false;
    $("run-form").hidden = session.status === "closed";
    if (session.board?.source_seat && session.board.title) {
      state.titles.set(session.id, session.board.title);
      state.titleErrors.delete(session.id);
    }
    if (state.titles.has(session.id))
      session.title = state.titles.get(session.id);
    renderHeading();
    $("session-status").textContent = statusText(session.status);
    $("session-status").className = `session-status ${session.status}`;
    $("export-session").hidden = false;
    $("export-session").href =
      `/api/studio/sessions/${encodeURIComponent(session.id)}/export.md`;
    const event = session.events?.at(-1);
    $("activity-bar").hidden = true;
    if (event) {
      const activity = activityEvent(event);
      $("activity-bar").innerHTML =
        `<strong>${escape(activity.owner)}</strong><span>${escape(activity.text)}</span>`;
    }
    const index = state.sessions.findIndex((item) => item.id === session.id);
    const summary = {
      id: session.id,
      topic: session.topic,
      title: session.title,
      project_id: session.project_id,
      project: session.project,
      status: session.status,
      created_at: session.created_at,
    };
    if (index >= 0)
      state.sessions[index] = { ...state.sessions[index], ...summary };
    else state.sessions.unshift(summary);
    renderHistory();
    renderSeats();
    renderRounds();
    updateControls();
    window.RoundtableChildren?.update(session);
    window.MeetingAgenda.render(session);
    const agenda = session.agenda || [];
    const agendaState = session.agenda_draft_status;
    $("agenda-summary").textContent = agendaState === "drafting" ? "起草中" : agendaState === "failed" && !agenda.length ? "待重试" :
      agendaState === "pending" && !agenda.length ? "待起草" : agenda.length ? `${agenda.filter(item => item.status === "done").length}/${agenda.length}` : "0";
    $("agenda-toggle").title = activeItem(session)?.title || "展开会议议程";
    reportUI.update(session);
    window.ScienceMeeting?.update(session);
    board.render(session, {animateInitial});
    syncBoardPresence();
    if (firstBoard && hadChatFocus && $("room-chat").hidden) $("meeting-board").focus({preventScroll: true});
    pluginsUI.updateSession(session);
    fileControls();
    const workspaceKey = JSON.stringify([
      allChanges().map((change) => [change.path, change.diff, change.after]),
      (session.events || [])
        .filter((event) => event.type === "write")
        .map((event) => [event.id, event.at, event.detail]),
    ]);
    if (workspaceKey !== state.workspaceKey) {
      state.workspaceKey = workspaceKey;
      state.filesSession = null;
      if (state.file || state.filePanelOpen) refreshWorkspace();
    }
  }
  function stopPoll() {
    clearTimeout(state.poll);
    state.poll = null;
  }
  let pollState = {id: "", etag: "", delay: 700};
  function schedulePoll() {
    stopPoll();
    if (!state.selected || !state.session || document.hidden) return;
    const working = sessionWorking() || state.session.agenda_draft_status === "drafting" ||
      window.RoundtableReport.isWorking(state.session.report);
    if (!working && (state.session.status === "closed" || state.view !== "table")) return;
    const id = state.selected;
    if (pollState.id !== id) pollState = {id, etag: "", delay: 700};
    const request = pollState;
    state.poll = setTimeout(async () => {
      if (state.writing) {
        schedulePoll();
        return;
      }
      try {
        const previous = state.session;
        const poll = {etag: request.etag};
        const session = await api(`/sessions/${encodeURIComponent(id)}`, undefined, poll);
        if (state.selected === id && state.session === previous && !state.writing) {
          request.etag = poll.etag;
          request.delay = session ? 700 : Math.min(2100, request.delay + 350);
          if (session) updateSession(session);
        }
      } catch (error) {
        if (state.selected === id) showError(error);
      }
      if (state.selected === id) schedulePoll();
    }, working ? request.delay : 2500);
  }
  async function openSession(id, { preserveHash = false } = {}) {
    if (state.writing) return;
    if (!restoringRoute && state.selected !== id) {
      const project=state.sessions.find(item=>item.id===id)?.project_id;
      location.assign(window.SciStationNav.route("/studio",{session:id,project}));
      return;
    }
    if (!canLeaveFile()) return;
    stopPoll();
    closeChanges(false);
    window.RoundtableChildren?.close({ restoreFocus: false });
    createCommands.close();
    setup.suspend();
    window.MeetingAgenda.clear();
    reportUI.update(null);
    window.ScienceMeeting?.update(null);
    pluginsUI.updateSession(null);
    $("create-form").hidden = true;
    $("draft-project-required").hidden = true;
    $("chat-header").hidden = true;
    $("session-content").hidden = true;
    $("run-form").hidden = true;
    resetRoomDisclosures();
    $("latest-message").hidden = true;
    state.agendaNote = "";
    $("run-note").value = "";
    runMaterials.reset();
    state.selected = id;
    state.session = null;
    state.draftOpen = false;
    clearBoard();
    continuousUI.update(null);
    state.draftOpen = false;
    const summary = state.sessions.find(session => session.id === id);
    setActiveProject(summary ? window.RoundtableProjects.sessionProjectKey(summary) : "");
    state.roundsKey = "";
    state.seatKeys = {};
    state.file = null;
    state.filesSession = null;
    state.diff = null;
    resetFiles();
    state.anchor = preserveHash ? location.hash.slice(1) : "";
    syncUrl(id, preserveHash);
    clearError();
    renderHistory();
    switchView("table");
    renderHeading();
    try {
      const session = await api(`/sessions/${encodeURIComponent(id)}`);
      if (state.selected === id) {
        updateSession(session);
        state.enteredSessions.add(id);
        requestTitle(id);
        schedulePoll();
      }
    } catch (error) {
      if (state.selected === id) {
        window.RoundtableRecovery.reveal(error.unreadableSession);
        showError(error);
      }
    }
  }
  function setActiveProject(key = "") {
    if (state.activeProject === key) return;
    state.activeProject = key;
    storageSet("studio.active-project", key);
  }
  function paintDraftProject() {
    if (!state.draftOpen) return;
    const options = projects.available();
    const project = window.RoundtableProjects.resolveSelection(
      options, state.activeProject ?? storageGet("studio.active-project"),
      state.projectListStatus === "ready",
    );
    $("create-form").hidden = !project;
    $("draft-project-required").hidden = !!project;
    if (project) {
      setActiveProject(project.id);
      createCommands.close();
      setup.open(project);
      paintTextLimit("new-topic");
      renderHistory();
      renderHeading();
      return;
    }
    createCommands.close();
    setup.suspend();
    $("draft-project-message").textContent =
      options.some(option => !option.global) ? "选择要创建圆桌的项目" :
      state.projectListStatus === "loading" ? "正在读取项目…" :
      state.projectListStatus === "failed" ? "暂时无法读取项目" : "添加项目，或创建全局圆桌";
    $("draft-retry-projects").hidden = state.projectListStatus !== "failed";
    const buttons = options.map(option => {
      const button = document.createElement("button");
      button.className = "button secondary";
      button.type = "button";
      button.textContent = options.some(other => other !== option && other.name === option.name)
        ? option.path || option.name : option.name;
      button.title = option.path || option.name;
      button.addEventListener("click", () => openDraft(option.id));
      return button;
    });
    $("draft-project-options").replaceChildren(...buttons);
    renderHeading();
  }
  function openDraft(project) {
    if (state.writing) return;
    if (!restoringRoute) {
      const key=project || state.activeProject;
      const selected=projects.available().find(item=>item.id===key && !item.global);
      const href=window.SciStationNav.route("/studio",{project:selected?.id});
      if (new URL(href,location.href).href!==location.href) {
        location.assign(href);
        return;
      }
    }
    if (!canLeaveFile()) return;
    stopPoll();
    closeChanges(false);
    window.RoundtableChildren?.close({ restoreFocus: false });
    if (project) setActiveProject(project);
    state.selected = null;
    state.session = null;
    continuousUI.update(null);
    state.draftOpen = true;
    clearBoard();
    window.MeetingAgenda.clear();
    reportUI.update(null);
    window.ScienceMeeting?.update(null);
    pluginsUI.updateSession(null);
    state.file = null;
    state.filesSession = null;
    state.diff = null;
    resetFiles();
    state.roundsKey = "";
    state.seatKeys = {};
    syncUrl(null);
    $("stage-layout").classList.add("is-new");
    $("session-content").hidden = true;
    $("run-form").hidden = true;
    $("session-status").textContent = "准备开始";
    $("session-status").className = "session-status";
    $("export-session").hidden = true;
    $("files-toggle").hidden = true;
    $("change-count").hidden = true;
    resetRoomDisclosures();
    $("latest-message").hidden = true;
    state.agendaNote = "";
    $("run-note").value = "";
    runMaterials.reset();
    $("rounds").replaceChildren();
    renderSeats();
    renderHistory();
    paintDraftProject();
    clearError();
    switchView("table");
    $("setup-scroll").scrollTop = 0;
    ($("create-form").hidden ? $("draft-project-message") : $("new-topic"))
      .focus({ preventScroll: true });
  }
  async function handleSessionError(error, id) {
    if (error.status !== 409) {
      showError(error);
      return;
    }
    try {
      const session = await api(`/sessions/${encodeURIComponent(id)}`);
      if (state.selected === id) {
        updateSession(session);
        showError(
          new Error(
            "圆桌已有更新，已刷新。你的消息草稿和材料仍保留，请确认后再发起。",
          ),
        );
      }
    } catch (failure) {
      showError(
        new Error(
          `圆桌已有更新，暂时无法刷新：${failure.message}。消息草稿和材料已保留。`,
        ),
      );
    }
  }
  async function run() {
    if (state.writing || !state.session || state.session.status === "closed" || sessionWorking() || state.session.agenda_draft_status === "drafting")
      return;
    if (runMaterials.busy() || runMaterials.failed()) return;
    const recipient = seatMention.resolve();
    if (recipient.error) {
      $("run-note").focus();
      return;
    }
    if (!continuousUI.valid(input => {
      $("run-continuous-options").querySelector("details").open = true;
      meetingActions.openSettings(input);
    })) return;
    if (!paintTextLimit("run-note")) {
      $("run-note").reportValidity();
      return;
    }
    const allowEdits = $("run-access").value === "write";
    const id = state.selected;
    state.writing = true;
    stopPoll();
    updateControls();
    clearError();
    try {
      if (!(await board.flush())) {
        board.revealDraft();
        return;
      }
      if (!state.session || state.selected !== id || state.session.status === "closed" ||
          sessionWorking() || state.session.agenda_draft_status === "drafting") return;
      const payload = {
        note: $("run-note").value.trim(),
        target: recipient.target,
        agenda_version: state.session.agenda_version || 0,
        expected_round: latestRound()?.number || 0,
        allow_edits: allowEdits,
        preset: discussionChoice().preset,
        phase: discussionChoice().preset === "work" ? "work" : discussionChoice().phases[discussionChoice().preset],
      };
      const materialIDs = runMaterials.ready().map(item => item.id);
      if (materialIDs.length) payload.material_ids = materialIDs;
      const continuous = continuousUI.payload(state.session.topic);
      if (continuous) payload.continuous = continuous;
      const session = await api(sessionPath("/run"), payload);
      if (state.selected === id) {
        state.agendaNote = "";
        seatMention.clear();
        runMaterials.reset();
        updateSession(session);
      }
    } catch (error) {
      await handleSessionError(error, id);
    } finally {
      state.writing = false;
      updateControls();
      seatMention.updateStatus();
      schedulePoll();
    }
  }
  function renderFiles() {
    const query = $("file-filter").value.toLowerCase();
    $("file-list").replaceChildren();
    const filtered = state.files.filter((path) =>
      path.toLowerCase().includes(query),
    );
    if (!filtered.length) {
      const p = document.createElement("p");
      p.className = "quiet";
      p.textContent = state.files.length
        ? "没有匹配的文件。"
        : "项目中暂无可显示文件。";
      $("file-list").append(p);
    }
    for (const path of filtered) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `file-item${state.file?.path === path ? " selected" : ""}`;
      button.textContent = path;
      button.addEventListener("click", () => openFile(path));
      $("file-list").append(button);
    }
  }
  function renderChanges() {
    if (!state.filePanelOpen) return;
    const list = $("changes-list");
    list.replaceChildren();
    const latest = new Map();
    for (const change of allChanges()) latest.set(change.path, change);
    for (const change of [...latest.values()].reverse()) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `file-item review-file${state.diff?.path === change.path ? " selected" : ""}`;
      const path = document.createElement("span");
      path.textContent = change.path;
      button.append(path);
      const count = document.createElement("span");
      count.className = "review-file-count";
      count.dataset.reviewKey = reviewKey(change);
      button.append(count);
      button.addEventListener("click", () => showDiff(change));
      list.append(button);
      if (!state.reviewSummaries.has(reviewKey(change)))
        ensureReview(change, false);
    }
    paintReviewCounts();
  }
  async function loadFiles(force = false) {
    $("files-empty").hidden = Boolean(state.session);
    $("file-workspace").hidden = !state.session;
    if (!state.session) return;
    renderChanges();
    if (state.filesSession === state.selected && !force) {
      renderFiles();
      return;
    }
    const id = state.selected;
    const request = ++state.fileListRequest;
    const result = await api(sessionPath("/files"));
    if (state.selected !== id || request !== state.fileListRequest) return;
    state.files = (result.files || [])
      .map((file) => (typeof file === "string" ? file : file.path))
      .filter(Boolean);
    state.filesSession = id;
    renderFiles();
    if (!state.file && !state.diff) {
      $("editor-empty").hidden = false;
      $("file-editor").hidden = true;
      $("diff-pane").hidden = true;
      $("file-path").textContent = "选择一个文件";
      $("save-file").disabled = true;
      $("file-dirty").hidden = true;
      fileControls();
    }
  }
  function showFile(file, { preserveScroll = false } = {}) {
    const scrollTop = $("file-editor").scrollTop;
    state.file = file;
    state.fileRawText = file.text || "";
    state.diskChanged = null;
    $("file-editor").value = normalizeNewlines(state.fileRawText);
    state.fileText = $("file-editor").value;
    $("file-path").textContent = file.path;
    if (preserveScroll) $("file-editor").scrollTop = scrollTop;
    if (!state.diff) {
      $("file-editor").hidden = false;
      $("editor-empty").hidden = true;
      $("diff-pane").hidden = true;
    }
    fileControls();
    renderFiles();
  }
  async function openFile(path) {
    if (state.savingFile || !canLeaveFile()) return;
    const id = state.selected;
    const request = ++state.fileRequest;
    state.fileRefreshRequest++;
    state.fileLoading = true;
    fileControls();
    try {
      const file = await api(
        `${sessionPath("/file")}?path=${encodeURIComponent(path)}`,
      );
      if (state.selected !== id || request !== state.fileRequest) return;
      state.diff = null;
      showFile(file);
    } catch (error) {
      if (state.selected === id && request === state.fileRequest)
        showError(error);
    } finally {
      if (request === state.fileRequest) {
        state.fileLoading = false;
        fileControls();
      }
    }
  }
  async function refreshOpenFile() {
    if (!state.file || state.fileLoading || state.savingFile) return;
    const id = state.selected;
    const file = state.file;
    const selection = state.fileRequest;
    const request = ++state.fileRefreshRequest;
    const fresh = await api(
      `${sessionPath("/file")}?path=${encodeURIComponent(file.path)}`,
    );
    if (
      state.selected !== id ||
      selection !== state.fileRequest ||
      request !== state.fileRefreshRequest ||
      state.file?.path !== file.path ||
      state.savingFile
    )
      return;
    if (fresh.version === state.file.version) return;
    if (hasFileDraft()) {
      state.diskChanged = fresh;
      fileControls();
    } else showFile(fresh, { preserveScroll: true });
  }
  async function refreshWorkspace() {
    state.workspacePending = true;
    if (state.workspaceSyncing) return;
    state.workspaceSyncing = true;
    try {
      while (state.workspacePending) {
        state.workspacePending = false;
        const id = state.selected;
        const results = await Promise.allSettled([
          loadFiles(true),
          refreshOpenFile(),
        ]);
        if (state.selected !== id) continue;
        const failure = results.find((result) => result.status === "rejected");
        if (failure) showError(failure.reason);
      }
    } finally {
      state.workspaceSyncing = false;
    }
  }
  function resolveRevision(change) {
    if (change.revision) return change;
    const existing = allChanges().findLast(
      (item) =>
        item.path === change.path &&
        item.before === change.before &&
        item.after === change.after &&
        (!change.round || item.round === change.round) &&
        (!change.seat || item.seat === change.seat),
    );
    return existing
      ? { ...existing, ...change, revision: existing.revision }
      : change;
  }
  function reviewKey(change) {
    return JSON.stringify([
      state.selected,
      change.path,
      change.before,
      change.after,
      change.revision || "current",
    ]);
  }
  function analyzeReview(record) {
    try {
      if (!state.metricsWorker) {
        state.metricsWorker = new Worker("/static/review-worker.js");
        state.metricsWorker.onmessage = (event) => {
          const request = state.metricRequests.get(event.data.id);
          if (!request) return;
          state.metricRequests.delete(event.data.id);
          const current = state.reviewCache.get(request.key);
          if (!current || current.metricVersion !== request.version) return;
          current.metrics = event.data.metrics;
          summarizeReview(current);
          paintReviewCounts();
        };
        state.metricsWorker.onerror = () => {
          for (const record of state.reviewCache.values())
            if (!record.metrics)
              record.metrics = {
                status: "unavailable",
                reason: "统计服务暂不可用。",
                lines: null,
              };
          paintReviewCounts();
        };
      }
      record.metricVersion = (record.metricVersion || 0) + 1;
      const id = `${record.key}:${record.metricVersion}`;
      state.metricRequests.set(id, {
        key: record.key,
        version: record.metricVersion,
      });
      state.metricsWorker.postMessage({
        id,
        diff: record.diff,
        path: record.change.path,
      });
    } catch (_) {
      record.metrics = {
        status: "unavailable",
        reason: "统计服务暂不可用。",
        lines: null,
      };
    }
  }
  function summarizeReview(record) {
    state.reviewSummaries.delete(record.key);
    state.reviewSummaries.set(record.key, {
      serverLines: record.serverLines,
      metrics: record.metrics
        ? {
            status: record.metrics.status,
            lines: record.metrics.lines,
            reason: record.metrics.reason,
          }
        : null,
      loading: record.loading,
      error: record.error,
    });
    while (state.reviewSummaries.size > 256)
      state.reviewSummaries.delete(state.reviewSummaries.keys().next().value);
  }
  function drainReviewQueue() {
    while (state.reviewActive < 3 && state.reviewQueue.length) {
      const task = state.reviewQueue.shift();
      state.reviewActive++;
      Promise.resolve()
        .then(task)
        .finally(() => {
          state.reviewActive--;
          drainReviewQueue();
        });
    }
  }
  function ensureReview(raw, analyze = true) {
    const change = resolveRevision(raw),
      key = reviewKey(change);
    if (state.reviewCache.has(key)) {
      const existing = state.reviewCache.get(key);
      state.reviewCache.delete(key);
      state.reviewCache.set(key, existing);
      if (analyze && !existing.analyze) {
        existing.analyze = true;
        if (existing.normalized && !existing.metrics) analyzeReview(existing);
      }
      return existing;
    }
    const record = {
      key,
      change,
      diff: change.diff || "",
      loading: true,
      metrics: null,
      serverLines: null,
      error: "",
      analyze,
      normalized: false,
    };
    state.reviewCache.set(key, record);
    while (state.reviewCache.size > 32) {
      const oldest = [...state.reviewCache.keys()].find(
        (candidate) => !state.diff || candidate !== reviewKey(state.diff),
      );
      if (!oldest) break;
      state.reviewCache.delete(oldest);
    }
    const id = state.selected,
      epoch = state.reviewEpoch;
    state.reviewQueue.push(async () => {
      if (epoch !== state.reviewEpoch || id !== state.selected) return;
      try {
        if (!change.before || !change.after)
          throw new Error("这份记录缺少修订版本，正在显示原始补丁。");
        const params = new URLSearchParams({
          path: change.path,
          before: change.before,
          after: change.after,
        });
        const result = await api(
          `/sessions/${encodeURIComponent(id)}/review?${params}`,
        );
        if (epoch !== state.reviewEpoch || id !== state.selected) return;
        if (typeof result.diff !== "string")
          throw new Error("未取得可核对的规范补丁。");
        record.diff = result.diff;
        if (
          Number.isInteger(result.added) &&
          Number.isInteger(result.removed) &&
          result.added >= 0 &&
          result.removed >= 0
        )
          record.serverLines = { added: result.added, removed: result.removed };
        record.metrics = null;
        record.normalized = true;
        if (record.analyze) analyzeReview(record);
      } catch (error) {
        record.error = error.message || "暂时无法核对这份补丁。";
        record.metrics = {
          status: "unavailable",
          reason: record.error,
          lines: null,
        };
      } finally {
        if (epoch !== state.reviewEpoch || id !== state.selected) return;
        record.loading = false;
        summarizeReview(record);
        if (
          state.selected === id &&
          state.diff &&
          reviewKey(state.diff) === key
        )
          paintCurrentReview();
        paintReviewCounts();
      }
    });
    drainReviewQueue();
    return record;
  }
  function reviewCounts(record, unit = "lines") {
    const value =
      unit === "lines"
        ? record?.serverLines || record?.metrics?.lines
        : record?.metrics?.[unit];
    return value &&
      Number.isFinite(value.added) &&
      Number.isFinite(value.removed)
      ? value
      : null;
  }
  function countLabel(record, unit = "lines") {
    const counts = reviewCounts(record, unit);
    return counts
      ? `+${counts.added} −${counts.removed} ${{ lines: "行", characters: "字", words: "词" }[unit]}`
      : record?.loading || !record?.metrics
        ? "核对中…"
        : "精确统计不可用";
  }
  function metricReason(reason) {
    return (
      {
        "missing-unified-diff": "缺少可核对的统一补丁。",
        "diff-size-budget-exceeded": "补丁较大，暂不提供精确字词统计。",
        "incomplete-or-invalid-hunk": "补丁片段不完整，无法可靠统计。",
        "unsupported-hunk-header": "这份补丁的片段格式暂不支持。",
        "unsupported-diff-content": "这份补丁含暂不支持的内容。",
        "no-unified-hunks": "没有可核对的行补丁。",
        "unicode-segmenter-unavailable": "当前环境不支持精确字词分段。",
        "fragment-size-budget-exceeded": "改动片段较大，暂不提供精确字词统计。",
        "tokenization-budget-exceeded": "文本较大，暂不提供精确字词统计。",
        "exact-comparison-budget-exceeded": "精确比较超过本机统计预算。",
        "worker-comparison-failed": "统计服务暂不可用。",
      }[reason] ||
      reason ||
      ""
    );
  }
  function paintReviewCounts() {
    for (const element of document.querySelectorAll("[data-review-key]")) {
      const record =
        state.reviewCache.get(element.dataset.reviewKey) ||
        state.reviewSummaries.get(element.dataset.reviewKey);
      element.textContent = countLabel(record);
      element.title =
        metricReason(record?.metrics?.reason) || "实际补丁中的新增与删除行数";
    }
    if (state.diff) {
      const record = state.reviewCache.get(reviewKey(state.diff));
      $("review-stats").textContent = countLabel(record, state.reviewUnit);
      const definition = {
        lines: "此修订实际新增、删除的行数。",
        characters: "字：排除空白的可见字符，按文档源文件。",
        words: "词：按中英文分词，按文档源文件。",
      }[state.reviewUnit];
      $("review-stats").title = [
        definition,
        metricReason(record?.metrics?.reason),
      ]
        .filter(Boolean)
        .join(" ");
      $("review-unit").hidden = !record?.metrics?.document;
      $("review-unit").title =
        "行｜字（排除空白的可见字符）｜词（中英文分词），均按文档源文件。";
      for (const option of $("review-unit").querySelectorAll("option"))
        if (option.value !== "lines") {
          option.disabled = !reviewCounts(record, option.value);
          option.textContent = `${option.value === "characters" ? "字" : "词"}${option.disabled ? "（暂不可用）" : ""}`;
        }
    }
  }
  function paintCurrentReview() {
    if (!state.diff) return;
    const record = state.reviewCache.get(reviewKey(state.diff));
    if (!record) return;
    $("diff-content").classList.toggle(
      "document-diff",
      record.metrics?.document ??
        /\.(?:tex|ltx|latex|md|mdx|markdown|mdown|mkd|txt|text|rst|rest|org|adoc|asciidoc)$/i.test(
          record.change.path,
        ),
    );
    let oldLines = 0,
      newLines = 0;
    $("diff-content").innerHTML = record.diff
      ? record.diff
          .split("\n")
          .map((line) => {
            let kind = "";
            const hunk = line.match(
              /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/,
            );
            if (hunk) {
              oldLines = hunk[2] === undefined ? 1 : Number(hunk[2]);
              newLines = hunk[4] === undefined ? 1 : Number(hunk[4]);
              kind = "diff-header";
            } else if (oldLines > 0 || newLines > 0) {
              if (line.startsWith("+")) {
                kind = "diff-add";
                newLines--;
              } else if (line.startsWith("-")) {
                kind = "diff-remove";
                oldLines--;
              } else if (line.startsWith(" ")) {
                oldLines--;
                newLines--;
              } else if (line.startsWith("\\")) kind = "diff-header";
            } else if (
              line.startsWith("+++") ||
              line.startsWith("---") ||
              line.startsWith("\\ No newline")
            )
              kind = "diff-header";
            return `<span class="${kind}">${escape(line)}\n</span>`;
          })
          .join("")
      : record.loading
        ? "补丁读取中…"
        : "暂无可显示的补丁。";
    const { change } = record;
    const missingVersions = !change.before || !change.after;
    const missingPatch = !record.loading && !record.diff && (missingVersions || change.before !== change.after);
    let reviewNote = "";
    if (missingPatch) reviewNote = "这份历史记录没有可显示的补丁。";
    else if (record.error) reviewNote = missingVersions
      ? "这份历史记录缺少版本信息。当前显示当时保存的原始补丁。"
      : "当前显示原始补丁，精确统计不可用。";
    $("review-note").hidden = !reviewNote;
    $("review-note").textContent = reviewNote;
    $("review-note").title = record.error;
    $("retry-review").hidden = !record.error || missingVersions;
    paintReviewCounts();
  }
  function revisionContext(change) {
    if (change.seat === "user") {
      if (change.round === 0) return "会前 · 主持人";
      return change.round ? `第 ${change.round} 轮 · 主持人` : "主持人 · 轮次未记录";
    }
    return change.round ? `第 ${change.round} 轮 · ${sourceIdentity(change.seat, state.session, change.round, change).label}` : "当前保存";
  }
  function showDiff(raw) {
    const change = resolveRevision(raw);
    state.diff = change;
    state.reviewUnit = "lines";
    $("review-unit").value = "lines";
    $("file-path").textContent = change.path;
    const revisions = allChanges().filter((item) => item.path === change.path);
    const latest = revisions.at(-1);
    const canIdentifyLatest = state.session?.status !== "closed" || closedFileCatalog(state.session).hasChronology;
    const isLatest = canIdentifyLatest && latest && reviewKey(latest) === reviewKey(change);
    $("diff-title").textContent = `${isLatest ? "最新 · " : ""}${revisionContext(change)}`;
    const select = $("review-revision");
    select.replaceChildren();
    for (const [index, revision] of revisions.entries()) {
      const option = document.createElement("option");
      option.value = reviewKey(revision);
      option.textContent = `${canIdentifyLatest && index === revisions.length - 1 ? "最新 · " : ""}修订 ${index + 1} · ${revisionContext(revision)}`;
      select.append(option);
    }
    if (!revisions.some((item) => reviewKey(item) === reviewKey(change))) {
      const option = document.createElement("option");
      option.value = reviewKey(change);
      option.textContent = "当前保存";
      select.append(option);
    }
    select.value = reviewKey(change);
    select.hidden = revisions.length < 2;
    ensureReview(change);
    paintCurrentReview();
    $("diff-pane").hidden = false;
    $("file-editor").hidden = true;
    $("editor-empty").hidden = true;
    fileControls();
    renderChanges();
  }
  $("create-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    if (state.writing || !state.draftOpen || $("create-form").hidden) return;
    if (!paintTextLimit("new-topic")) {
      $("new-topic").reportValidity();
      return;
    }
    const topic = $("new-topic").value.trim();
    if (!topic || !setup.canSubmit()) return;
    const chief = topicMention.resolve();
    if (chief.error) {
      $("new-topic").focus();
      return;
    }
    const payload = setup.payload(chief.target);
    const scope = payload.scope === "global" ? "@global" : payload.project_id || payload.project;
    if (scope !== state.activeProject ||
        !projects.available().some(project => (project.id || project.path) === scope)) return;
    state.writing = true;
    updateControls();
    clearError();
    try {
      const session = await api("/sessions", { topic, ...payload });
      setup.complete();
      state.roundsKey = "";
      state.seatKeys = {};
      syncUrl(session.id,false,session.project_id);
      updateSession(session, {animateInitial:true});
      $(hasBoard(session) ? "meeting-board" : "table-scroll").focus({preventScroll:true});
      state.enteredSessions.add(session.id);
      requestTitle(session.id);
      $("new-topic").value = "";
    } catch (error) {
      showError(error);
    } finally {
      state.writing = false;
      updateControls();
      schedulePoll();
    }
  });
  for (const id of ["new-topic", "run-note"]) {
    $(id).addEventListener("input", () => paintTextLimit(id));
  }
  $("run-form").addEventListener("submit", (event) => {
    event.preventDefault();
    run();
  });
  $("run-preset").addEventListener("change", () => {
    const choice = discussionChoice(); choice.preset = $("run-preset").value;
    paintDiscussionControls();
  });
  $("run-phase").addEventListener("change", () => {
    const choice = discussionChoice(); choice.phases[choice.preset] = $("run-phase").value;
    paintDiscussionControls();
  });
  $("run-access").addEventListener("change", () => {
    discussionChoice().allowEdits = $("run-access").value === "write";
    paintDiscussionControls();
  });
  window.addEventListener("meeting-agenda-updated", event => {
    const session = event.detail?.session;
    if (session?.id === state.selected) {
      updateSession(session);
      schedulePoll();
    }
  });
  window.addEventListener("meeting-agenda-compose", event => {
    const {sessionId, title, preset, phase} = event.detail || {};
    if (sessionId !== state.selected || !state.session || state.session.status === "closed" || !Object.hasOwn(discussionPresets, preset)) return;
    const choice = discussionChoice(); choice.preset = preset;
    if (Object.hasOwn(discussionPresets[preset].phases, phase)) choice.phases[preset] = phase;
    const note = $("run-note");
    if (title) {
      const lines = note.value.split("\n");
      const old = state.agendaNote ? lines.lastIndexOf(state.agendaNote) : -1;
      if (old >= 0) lines.splice(old, 1);
      const entered = lines.includes(title);
      if (!entered) {
        if (!lines.length || (lines.length === 1 && !lines[0])) lines.splice(0, lines.length, title);
        else lines.push(title);
      }
      note.value = lines.join("\n");
      state.agendaNote = entered ? "" : title;
    }
    setChatVisible(true);
    paintDiscussionControls(); paintTextLimit("run-note"); note.focus();
  });
  async function cancelRun() {
    if (state.writing || !state.selected) return;
    state.writing = true;
    state.cancelling = true;
    updateControls();
    renderSeats();
    const id = state.selected;
    try {
      const session = await api(sessionPath("/cancel"), {});
      if (state.selected === id) updateSession(session);
    } catch (error) {
      showError(error);
    } finally {
      state.writing = false;
      state.cancelling = false;
      updateControls();
      renderSeats();
      schedulePoll();
    }
  }
  $("cancel-run").addEventListener("click", cancelRun);
  $("run-continuous-pause").addEventListener("click", cancelRun);
  window.addEventListener("focus", refreshSettingsOverview);
  document.addEventListener("visibilitychange", refreshSettingsOverview);
  document.addEventListener("visibilitychange", schedulePoll);
  $("open-magpie").addEventListener("click", () =>
    magpieAgentAction({ action: "open" }),
  );
  $("register-magpie-agent").addEventListener("click", () =>
    magpieAgentAction({}),
  );
  $("open-rules-file").addEventListener("click", async () => {
    const button = $("open-rules-file");
    button.disabled = true;
    try {
      await api("/open-rules", {});
      clearError();
    } catch (error) {
      showError(error);
    } finally {
      button.disabled = false;
    }
  });
  $("settings-form").addEventListener("input", () => {
    state.settingsDirty = changedSettings();
    setSettingsSaveState(state.settingsDirty ? "未保存" : "");
    updateSettingsNavigation();
    updateControls();
  });
  $("latest-message").addEventListener("click", () => {
    $("table-scroll").scrollTop = $("table-scroll").scrollHeight;
    $("latest-message").hidden = true;
  });
  $("table-scroll").addEventListener("scroll", () => {
    if (
      $("table-scroll").scrollHeight -
        $("table-scroll").scrollTop -
        $("table-scroll").clientHeight <
      110
    )
      $("latest-message").hidden = true;
  });
  $("settings-panel-appearance").addEventListener("change", (event) => {
    const control = event.target;
    if (control.id === "setting-appearance") appearance.setMode(control.value);
    if (control.name === "color_theme") appearance.setColorTheme(control.value);
    if (control.id === "setting-text-size") appearance.setTextSize(control.value);
  });
  $("settings-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    if (state.writing || !changedSettings()) return;
    const invalid = [...$("settings-form").elements].find((control) => control.willValidate && !control.checkValidity());
    if (invalid) {
      const panel = invalid.closest(".settings-panel");
      const tab = panel && document.getElementById(panel.getAttribute("aria-labelledby"));
      if (tab) window.RoundtableSettingsNav?.select(tab.dataset.settingsPage);
      invalid.reportValidity();
      return;
    }
    const patch = settingsPatch();
    state.writing = true;
    updateControls();
    setSettingsSaveState("正在保存…");
    try {
      state.settings = await api("/settings", patch);
      settingsToForm();
      setSettingsSaveState("已保存");
      clearError();
    } catch (error) {
      showError(error);
      setSettingsSaveState("尚未保存");
    } finally {
      state.writing = false;
      updateControls();
    }
  });
  $("file-editor").addEventListener("input", fileControls);
  $("new-file-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    const path = $("new-file-path").value.trim();
    if (
      !path ||
      path.startsWith("/") ||
      path.includes("\\") ||
      path.split("/").includes("..") ||
      path === "."
    ) {
      showError(new Error("请输入项目内的相对文件路径，例如 notes/task.md。"));
      return;
    }
    await openFile(path);
  });
  $("reload-file").addEventListener("click", () => {
    if (state.file) openFile(state.file.path);
  });
  $("copy-file").addEventListener("click", async () => {
    const text = $("file-editor").value;
    try {
      if (!navigator.clipboard?.writeText)
        throw new Error("clipboard unavailable");
      await navigator.clipboard.writeText(text);
      $("file-change-text").textContent = "草稿已复制。";
    } catch (_) {
      $("diff-pane").hidden = true;
      $("file-editor").hidden = false;
      $("file-editor").focus({ preventScroll: true });
      $("file-editor").select();
      $("file-change-text").textContent = "草稿已选中，请按 ⌘C 复制。";
    }
    $("file-change-notice").hidden = false;
  });
  $("save-file").addEventListener("click", async () => {
    if (
      !state.file ||
      state.writing ||
      state.session?.status === "closed" ||
      state.fileLoading ||
      state.diskChanged ||
      !dirtyFile()
    )
      return;
    const id = state.selected;
    const file = state.file;
    const selection = state.fileRequest;
    const editorText = $("file-editor").value;
    const text = restoreNewlines(state.fileRawText, editorText);
    state.writing = true;
    state.savingFile = true;
    fileControls();
    clearError();
    try {
      const result = await api(sessionPath("/file"), {
        path: file.path,
        text,
        version: file.version,
      });
      if (state.selected !== id || selection !== state.fileRequest) return;
      state.fileText = editorText;
      state.fileRawText = text;
      const fresh = await api(
        `${sessionPath("/file")}?path=${encodeURIComponent(file.path)}`,
      );
      if (state.selected !== id || selection !== state.fileRequest) return;
      state.file = fresh;
      if (fresh.text !== text) state.diskChanged = fresh;
      if (result.diff) showDiff(result);
      await loadFiles(true);
    } catch (error) {
      if (error.status === 409) {
        state.diskChanged = { path: file.path };
        showError(
          new Error(
            "文件已被其他工作改动。你的草稿已保留，请复制或重新载入后核对。",
          ),
        );
      } else showError(error);
    } finally {
      state.writing = false;
      state.savingFile = false;
      fileControls();
      updateControls();
      if (state.workspacePending) refreshWorkspace();
    }
  });
  $("close-diff").addEventListener("click", () => {
    state.diff = null;
    $("diff-pane").hidden = true;
    $("file-path").textContent = state.file?.path || "选择一个文件";
    fileControls();
    $("file-editor").hidden = !state.file;
    $("editor-empty").hidden = Boolean(state.file);
  });
  $("retry-review").addEventListener("click", () => {
    if (!state.diff) return;
    state.reviewCache.delete(reviewKey(state.diff));
    ensureReview(state.diff);
    paintCurrentReview();
  });
  $("review-revision").addEventListener("change", () => {
    const change = allChanges().find(
      (item) => reviewKey(item) === $("review-revision").value,
    );
    if (change) showDiff(change);
  });
  $("review-unit").addEventListener("change", () => {
    state.reviewUnit = $("review-unit").value;
    paintReviewCounts();
  });
  window.addEventListener("roundtable:sidepanel-open", (event) => {
    if (event.detail === "children" || event.detail === "opinions") closeChanges(false);
  });
  $("edit-diff").addEventListener("click", () => {
    if (state.diff) openFile(state.diff.path);
  });
  $("files-toggle").addEventListener("click", () => {
    if (state.filePanelOpen) closeChanges();
    else openChanges(null, $("meeting-actions-toggle"));
  });
  $("close-changes").addEventListener("click", () => closeChanges());
  $("back-to-table").addEventListener("click", () => switchView("table"));
  $("file-filter").addEventListener("input", renderFiles);
  $("refresh-files").addEventListener("click", refreshWorkspace);
  for (const button of document.querySelectorAll(".view-tab"))
    button.addEventListener("click", () => switchView(button.dataset.view));
  $("menu-view-project").addEventListener("click", () =>
    showProjectPath(menuSummary()),
  );
  $("menu-copy-project").addEventListener("click", () => {
    const summary = menuSummary(),
      opener = state.menuOpener;
    closeHistoryMenu(true);
    copyProjectPath(summary?.project, summary, opener);
  });
  $("menu-regenerate-title").addEventListener("click", () => {
    const id = state.menuSession;
    closeHistoryMenu(true);
    requestTitle(id, { force: true });
  });
  for (const id of ["close-project-dialog", "done-project-dialog"])
    $(id).addEventListener("click", () => $("project-dialog").close());
  $("copy-project-dialog").addEventListener("click", () =>
    copyProjectPath($("project-dialog-path").value),
  );
  $("project-dialog").addEventListener("close", () => {
    const opener = state.dialogOpener
      ? document.getElementById(state.dialogOpener)
      : null;
    opener?.focus({ preventScroll: true });
  });
  document.addEventListener("pointerdown", (event) => {
    if (!$("history-menu").hidden && !$("history-menu").contains(event.target))
      closeHistoryMenu(false);
  });
  $("history").addEventListener("scroll", () => closeHistoryMenu(false));
  window.addEventListener("resize", () => closeHistoryMenu(false));
  window.addEventListener("blur", () => closeHistoryMenu(false));
  $("new-session").addEventListener("click", () => openDraft());
  $("dismiss-notice").addEventListener("click", clearError);
  $("toggle-sidebar").addEventListener("click", () =>
    sidebar(
      matchMedia("(max-width: 800px)").matches
        ? !document.body.classList.contains("sidebar-open")
        : document.body.classList.contains("sidebar-collapsed"),
    ),
  );
  $("sidebar-scrim").addEventListener("click", () => sidebar(false));
  document.addEventListener("keydown", (event) => {
    if (event.defaultPrevented) return;
    if (reportUI.isOpen() || pluginsUI.isOpen()) return;
    if ($("project-dialog").open) return;
    if (!$("history-menu").hidden) {
      const items = menuItems(),
        index = items.indexOf(document.activeElement);
      if (["Escape", "Tab"].includes(event.key)) {
        event.preventDefault();
        closeHistoryMenu(true);
        return;
      }
      if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
        event.preventDefault();
        const next =
          event.key === "Home"
            ? 0
            : event.key === "End"
              ? items.length - 1
              : (index + (event.key === "ArrowDown" ? 1 : -1) + items.length) %
                items.length;
        items[next]?.focus({ preventScroll: true });
        return;
      }
    }
    if ((event.metaKey || event.ctrlKey) && event.key === ",") {
      event.preventDefault();
      switchView("settings");
    }
    if (event.key === "Escape" && state.filePanelOpen) {
      event.preventDefault();
      closeChanges();
    } else if (event.key === "Escape") closeMobileSidebar();
  });
  window.addEventListener("roundtable:navigate", (event) => {
    event.preventDefault();
    switchView(["settings", "plugins"].includes(event.detail) ? event.detail : "table");
  });
  // Re-enter through the same URL resolver as an externally opened session.
  // A fragment-only jump stays in the live meeting and retains its composer.
  window.addEventListener("popstate", () => {
    const url=new URL(location.href);
    const session=url.searchParams.get("session") || null;
    const requestedView=url.searchParams.get("view") || "table";
    const draftProject=state.activeProject==="@global" ? "" : state.activeProject;
    if (session!==state.selected || (!session && (url.searchParams.get("project") || "")!==draftProject)) {
      location.reload();
    } else if (state.view!==requestedView) {
      restoringRoute=true;
      try {switchView(requestedView);} finally {restoringRoute=false;}
    }
  });
  window.addEventListener("hashchange", scrollAnchor);
  window.addEventListener("beforeunload", (event) => {
    if (dirtyFile() || state.settingsDirty) {
      event.preventDefault();
      event.returnValue = "";
    }
  });
  async function boot() {
    const requestedView = new URL(location.href).searchParams.get("view");
    clearError();
    state.projectListStatus = "loading";
    paintDraftProject();
    const results = await Promise.allSettled([api("/settings"), loadHistory(), projects.load()]);
    state.projectListStatus = results.slice(1).every(result => result.status === "fulfilled")
      ? "ready" : "failed";
    if (results[0].status === "fulfilled") {
      state.settings = results[0].value;
      settingsToForm();
      $("connection-status").classList.remove("offline");
      $("connection-status").textContent = "本机服务";
    } else {
      $("connection-status").classList.add("offline");
      $("connection-status").textContent = "连接中断";
    }
    const entry = new URL(location.href);
    const linked = entry.searchParams.get("session");
    let research = null;
    try {
      research = window.ScienceMeeting?.requestedProject(entry.searchParams.get("project"));
    } catch (error) {
      if (entry.searchParams.has("project")) { showError(error); return; }
    }
    if (linked) await openSession(linked, { preserveHash: true });
    else if (research) openDraft(research.id);
    else if (!state.selected) openDraft("@global");
    if (research) {
      try {
        await window.ScienceMeeting.receive(research, linked,
          linked ? runMaterials : createMaterials, () => state.activeProject,
          $(linked ? "run-note" : "new-topic"));
        await window.ScienceLabHandoff?.receive(research, linked, state.session,
          $(linked ? "run-note" : "new-topic"), linked ? null : setup.applyLabPreset,
          linked ? runMaterials : createMaterials);
      } catch (error) { showError(error); }
    }
    if (["settings", "files", "plugins"].includes(requestedView))
      switchView(requestedView);
    restoringRoute=false;
    const failure = results.find(result => result.status === "rejected");
    if (failure) showError(failure.reason);
  }
  const reportUI = window.RoundtableReport.mount({
    markdown,
    fileChanges: session => closedFileCatalog(session).cited,
    openRevision: change => openChanges(change, $("meeting-report")),
    hasUnsentNote: () => Boolean($("run-note").value.trim() || runMaterials.items().length),
    async write(id, payload) {
      if (state.writing || state.selected !== id) return;
      state.writing = true;
      stopPoll();
      updateControls();
      fileControls();
      try {
        if (!(await board.flush())) {
          reportUI.close();
          board.revealDraft();
          return;
        }
        if (state.selected !== id || !state.session) return;
        const session = await api(sessionPath("/report"), {
          ...payload, expected_round: state.session.rounds?.length || 0,
          agenda_version: state.session.agenda_version || 0,
        });
        if (state.selected === id) updateSession(session);
      } catch (error) {
        if (error.status === 409) {
          try {
            const current = await api(sessionPath());
            if (state.selected === id) updateSession(current);
          } catch (_) {
            // Retain the server's conflict message for the host.
          }
        }
        throw error;
      } finally {
        state.writing = false;
        updateControls();
        fileControls();
        schedulePoll();
      }
    },
    reveal(target, agenda) {
      if (state.view !== "table") switchView("table");
      if (agenda) {
        if (narrowWorkspace.matches) setChatVisible(false);
        showRoomDrawer("agenda-toggle");
      } else {
        window.RoundtableOpinions?.close({restoreFocus:false});
        setChatVisible(true);
      }
      requestAnimationFrame(() => {
        if (!target.isConnected) return;
        if (agenda) target.scrollIntoView({ block: "nearest" });
        else {
          const url = new URL(location.href);
          url.hash = target.id;
          history.replaceState(null, "", url);
          scrollToMessage(target);
          $("latest-message").hidden = false;
        }
        target.tabIndex = -1;
        target.classList.add("meeting-source-focus");
        target.focus({ preventScroll: true });
      });
    },
  });
  const board = window.RoundtableBoard.mount({
    root:$("meeting-board"),
    statusRoot:$("chat-board-status"),
    async writeEdit(id, payload) {
      const response = await fetch(`/api/studio/sessions/${encodeURIComponent(id)}/board`, {
        method: "POST",
        headers: {"Content-Type": "application/json", "X-Roundtable": "1"},
        body: JSON.stringify(payload),
        keepalive: true,
      });
      const result = await response.json();
      if (response.ok) return result;
      const error = new Error(result.error || "议题板保存失败");
      error.status = response.status;
      error.session = result.session;
      throw error;
    },
    onEdit(session) {
      if (state.selected !== session.id || !state.session) return;
      updateSession(session);
      if (!state.writing) schedulePoll();
    },
    onError: showError,
    onAgenda(id) {
      showRoomDrawer("agenda-toggle");
      const row = Array.from($("meeting-agenda").querySelectorAll("[data-agenda-item]")).find(el => el.dataset.agendaItem === id);
      if (row) { row.tabIndex = -1; row.focus(); }
      else $("agenda-toggle").focus();
    },
    onOpinions() { if ($("meeting-opinions").hidden) $("opinions-toggle").click(); },
    onSource(source, opener) {
      boardSourceOpener = opener;
      window.RoundtableReferences.jump(source.round,source.seat,source.model || undefined);
    },
    onChat(opener) {
      boardSourceOpener = opener;
      setChatVisible(true);
      ($("run-form").hidden ? $("rail-to-board") : $("run-note")).focus();
    },
    onRetry() { window.MeetingAgenda.retry(); },
  });
  const pluginsUI = window.RoundtablePlugins.mount({api});
  const seatEditor = window.RoundtableMemberEditor.mount({
    loadModels: () => api("/models"),
    write: (id, payload) => api(`/sessions/${encodeURIComponent(id)}/members`, payload),
    acceptSession(session) {
      if (state.selected !== session.id || !state.session) return;
      updateSession(session);
      if (!state.writing) schedulePoll();
    },
    membersOf: sessionMembers, displayName: seatName, effortName: window.RoundtableSetup.effortName,
  });
  const boardPresence = window.RoundtableBoardPresence.mount(snapshot => {
    if (!snapshot || state.selected === snapshot.session_id) board.setPresence(snapshot);
  }, async id => {
    const current = state.session;
    if (current?.id !== id || state.writing) return;
    try {
      const next = await api(`/sessions/${encodeURIComponent(id)}`);
      if (state.session === current && state.selected === id && !state.writing) updateSession(next);
    } catch (_) {
      // The normal meeting poll also reconciles the confirmed page.
    }
  });
  function syncBoardPresence() {
    boardPresence.sync(state.session, state.view === "table" && !document.hidden);
  }
  document.addEventListener("visibilitychange", syncBoardPresence);
  window.addEventListener("pagehide", boardPresence.stop);
  window.addEventListener("pageshow", syncBoardPresence);
  window.addEventListener("sci:language", () => {
    if (["settings", "plugins"].includes(state.view)) renderHeading();
  });
  window.addEventListener("roundtable:settings-page", (event) => {
    if (!["settings", "plugins"].includes(state.view)) return;
    const nextView = event.detail === "plugins" ? "plugins" : "settings";
    if (state.view !== nextView) {
      state.view = nextView;
      const url = new URL(location.href);
      url.searchParams.set("view", nextView);
      if (!restoringRoute) window.SciStationNav.commitURL(url,"push");
      renderHeading();
    }
    if (event.detail === "plugins") pluginsUI.openMarket();
    else if (event.detail === "models") refreshSettingsOverview();
  });
  const meetingActions = window.RoundtableActions.mount();
  const topicMention = window.RoundtableMention.mount({
    textarea: $("new-topic"), members: () => setup.mentionMembers(),
    status: $("new-topic-mention-status"), list: $("new-topic-mention-list"),
    describeTarget: label => label + " 将担任首席并起草议程",
    multipleTargetsError: "只能指定一位首席，请保留一个 @目标。",
  });
  const createMaterials = window.RoundtableMaterials.mount({
    root: $("create-materials"), pasteTarget: $("new-topic"),
    onChange: () => setup.materialsChanged(),
    onError: message => showError(new Error(message)),
  });
  const setup = window.RoundtableSetup.mount({
    api, assetFor, storageGet, storageSet, materials: createMaterials,
    onRosterChange() { topicMention.setContext(); topicMention.updateStatus(); },
  });
  const seatMention = window.RoundtableMention.mount({
    textarea:$("run-note"), members:() => sessionMembers(), getSeatName:seatName,
    status:$("run-mention-status"), list:$("run-mention-list"),
    describeTarget:label => $("run-continuous-enabled").checked ? "本段仅 " + label + " 回应" : "仅 " + label + " 回应"
  });
  const runMaterials = window.RoundtableMaterials.mount({
    root: $("run-materials"), pasteTarget: $("run-note"), onChange: paintRunSubmit,
    onError: message => showError(new Error(message)),
  });
  const continuousUI = window.RoundtableContinuous.mount("run", {onToggle() { updateControls(); seatMention.updateStatus(); }});
  function mountComposerCommands(prefix, root, materials, mention, mentionsAvailable, otherCommands) {
    const continuousToggle = $(prefix + "-continuous-enabled");
    const runComposer = prefix === "run";
    return window.RoundtableCommands.mount({
      root,
      button: $(prefix + "-commands"),
      commands: () => [
        { label: "添加图片", group: "材料", icon: "image", run: () => materials.pick("image") },
        { label: "添加文件", group: "材料", icon: "file", run: () => materials.pick("file") },
        {
          label: runComposer ? "@ 点名席位" : "@ 指定首席起草议程",
          group: "讨论", icon: "mention", disabled: !mentionsAvailable(),
          run: () => mention.open(),
        },
        ...otherCommands,
        {
          label: continuousToggle.checked ? "关闭持续推进" : "开启持续推进",
          group: "推进", icon: "continue", disabled: continuousToggle.disabled,
          run: () => continuousToggle.click(),
        },
        {
          label: "持续推进设置", group: "推进", icon: "sliders",
          disabled: !continuousToggle.checked || continuousToggle.disabled,
          run() {
            $(prefix + "-continuous-options").querySelector("details").open = true;
            const input = $(prefix + "-continuous-goal");
            if (runComposer) meetingActions.openSettings(input);
            else input.focus();
          },
        },
      ],
    });
  }
  const createCommands = mountComposerCommands("create", $("create-composer"), createMaterials, topicMention,
    () => setup.mentionMembers().length, [
      { label: "讨论预设", group: "讨论", icon: "sliders", run: () => $("preset-options").querySelector(":checked")?.focus() },
    ]);
  const runCommands = mountComposerCommands("run", $("run-form"), runMaterials, seatMention,
    () => sessionMembers().length, [
      { label: "讨论模式与权限", group: "讨论", icon: "sliders", run: () => meetingActions.openSettings($("run-preset")) },
    ]);
  const projects = window.RoundtableProjects.mount({
    api, history:$("history"), loadResearch:window.ScienceMeeting.loadProjects,
    newSession:openDraft, projectsChanged:paintDraftProject,
    rerender:() => { state.historyKey = ""; renderHistory(); },
  });
  $("draft-add-project").addEventListener("click", event => projects.openAdd(event.currentTarget));
  $("draft-import-project").addEventListener("click", event => projects.openImport(event.currentTarget));
  $("draft-retry-projects").addEventListener("click", boot);
  $("retry-connect").addEventListener("click", boot);
  sidebar(
    !matchMedia("(max-width: 800px)").matches &&
      storageGet("studio.sidebar") !== "closed",
  );
  boot();
})();
