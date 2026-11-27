"use strict";
(() => {
  const $ = id => document.getElementById(id);
  const esc = value => String(value ?? "").replace(/[&<>"']/g, ch => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;"
  } [ch]));
  const enc = encodeURIComponent;
  const navigation = window.SciStationNav;
  const text = (zh, en) => window.SciStationI18n?.text(zh, en) ?? zh;
  const local = (key, zh, en) => window.SciStationI18n?.message?.(key) ?? text(zh, en);
  const names = navigation.projectNames;
  const icon = key => window.RoundtableIcons.icon(key);
  const statusLabel = {
    get unread() { return text("未读", "Unread"); },
    get reading() { return text("阅读中", "Reading"); },
    get read() { return text("已读", "Read"); },
    get open() { return text("待办", "Open"); },
    get doing() { return text("进行中", "In progress"); },
    get inProgress() { return text("进行中", "In progress"); },
    get cancelled() { return text("已取消", "Cancelled"); },
    get done() { return text("已完成", "Completed"); },
  };
  const projectBadge = navigation.projectBadge;
  const state = {
    projects: [],
    project: null,
    papers: [],
    organization: {revision: 0, collections: {}, tags: {}},
    paperWikiStatus: {},
    libraryCollection: "",
    libraryTag: "",
    notes: [],
    wikiFolders: [],
    wikiQuery: "",
    tasks: [],
    taskCatalog: null,
    materials: [],
    meetings: [],
    graph: {
      nodes: [],
      edges: []
    },
    view: "overview",
    graphResult: null,
    graphQuery: null,
    graphError: "",
    graphPending: false,
    graphWorkflow: null,
    inspire: {seeds: [], rows: [], pending: false, error: ""},
    query: "",
    taskFilter: "",
    taskKind: "",
    taskTag: "",
    calendar: false,
    month: new Date(),
    loading: false,
    loadError: ""
  };
  let navEpoch = 0,
    failedLoad, toastTimer, modalCleanup = null, modalCanDismiss = null;
  const apiRoot = "/api/research/";
  async function request(path, options = {}) {
    const init = {
      method: options.method || "GET",
      signal: options.signal,
      headers: {
        Accept: "application/json"
      }
    };
    if (init.method !== "GET") init.headers["X-Roundtable"] = "1";
    if (options.body instanceof FormData) init.body = options.body;
    else if (options.body !== undefined) {
      init.headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(options.body);
    }
    const res = await fetch(path.startsWith("/api/") ? path : apiRoot + path, init);
    if (!res.ok) {
      let msg, code;
      try {
        const j = await res.json();
        msg = j.error || j.message;
        code = j.code;
      } catch {}
      const error = new Error(msg || "操作失败（" + res.status + "）");
      error.status = res.status;
      error.code = code;
      throw error;
    }
    if (res.status === 204) return null;
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }

  function projectPath(suffix = "", id = state.project?.id) {
    if (!id) throw new Error("请选择所属项目");
    return "projects/" + enc(id) + (suffix ? "/" + suffix : "");
  }

  function taskPath(id = "", project) {
    const path = "tasks" + (id ? "/" + enc(id) : "");
    return project ? projectPath(path, project) : path;
  }

  function studio(session) {
    return navigation.route("/studio", {project: state.project?.id, session});
  }

  function reader(paper, project = state.project?.id) {
    return navigation.route("/reader", {paper, project});
  }

  function toolsPage(tab, paper) {
    return navigation.route("/tools", {
      tab, paper, project: state.project?.id,
      date: tab === "calendar" && state.calendar ? localDate(state.month) : null
    });
  }

  function viewURL(view, id = state.project?.id) {
    return navigation.research(view, id);
  }

  function wikiURL(note, project = state.project?.id) {
    return navigation.route("/research", {view: "notes", project, note});
  }

  function toast(msg) {
    const el = $("toast");
    el.textContent = msg;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.hidden = true, 3300);
  }

  function dialog(title, html, {
    wide = false,
    cleanup = null,
    canDismiss = null
  } = {}) {
    if (modalCleanup) modalCleanup();
    modalCleanup = cleanup;
    modalCanDismiss = canDismiss;
    $("dialog-title").textContent = title;
    $("dialog-content").innerHTML = html;
    $("modal").classList.toggle("wide", wide);
    if (!$("modal").open) $("modal").showModal();
  }

  function close() {
    if (!$("modal").open) return true;
    if (modalCanDismiss && !modalCanDismiss()) return false;
    $("modal").close();
    return true;
  }
  $("modal").addEventListener("cancel", ev => {
    if (modalCanDismiss && !modalCanDismiss()) ev.preventDefault();
  });
  $("modal").addEventListener("close", () => {
    // A queued close event can arrive after another workflow opens this dialog.
    if ($("modal").open) return;
    if (modalCleanup) modalCleanup();
    modalCleanup = null;
    modalCanDismiss = null;
    $("dialog-content").replaceChildren();
  });

  function button(label, action, options = {}) {
    const {
      id = "", kind = "button", glyph = "", title = "", pressed, iconOnly = false
    } = options;
    return '<button type="button" class="' + kind + '" data-action="' + action + '" data-id="' + esc(id) +
      '"' + (title || iconOnly ? ' title="' + esc(title || label) + '"' : '') +
      (iconOnly ? ' aria-label="' + esc(title || label) + '"' : '') +
      (pressed === undefined ? '' : ' aria-pressed="' + pressed + '"') + '>' + (glyph ?
      icon(glyph) : "") + (iconOnly ? '' : esc(label)) + '</button>';
  }

  function link(label, href, kind = "button", glyph = "") {
    return '<a class="' + kind + '" href="' + esc(href) + '">' + (glyph ? icon(glyph) : "") + esc(label) + '</a>';
  }

  function navLink(view, label, kind = "bare") {
    return '<a class="' + kind + '" data-view="' + view + '" href="' + esc(viewURL(view)) + '">' + esc(label) + '</a>';
  }

  function empty(title, description = "", action = "") {
    return '<div class="empty"><h3>' + esc(title) + '</h3>' + (description ? '<p>' + esc(description) + '</p>' : '') + (
      action ? '<div class="actions">' + action + '</div>' : '') + '</div>';
  }

  function panel(title, body, action = "") {
    return '<section class="panel"><div class="panel-header"><h2>' + esc(title) + '</h2>' + action + '</div>' + body +
      '</section>';
  }

  function list(rows) {
    return '<div class="list">' + rows.join("") + '</div>';
  }

  function heading(title, sub = "", actions = "", project = null) {
    const badge = project ? projectBadge(project) : "";
    return '<div class="page-head workspace-page-heading"><div><h1>' + badge + esc(title) + '</h1>' + (sub ? '<p>' + esc(sub) + '</p>' : '') +
      '</div><div class="head-actions">' + actions + '</div></div>';
  }

  function moreActions(actions) {
    const title=local("toolbarMoreActions", "更多操作", "More actions");
    return '<details class="more-actions"><summary class="icon" aria-label="'+esc(title)+'" title="'+esc(title)+'">' + icon("more") +
      '</summary><div class="more-action-items">' + actions + '</div></details>';
  }

  function row(glyph, title, meta, control, tag = "", more = "", project = null) {
    return '<div class="row"><div class="glyph">' + (project ? projectBadge(project) : icon(glyph)) + '</div><' + control +
      ' class="row-main"><span class="title">' + esc(title) + '</span>' + (meta ? '<span class="meta">' + esc(meta) +
        '</span>' : '') + '</' + (control.startsWith("a ") ? 'a' : 'button') + '>' + (tag ? '<span class="tag status-tag">' + esc(
        tag) + '</span>' : '') + more + '</div>';
  }

  function rowAction(action, id) {
    return 'button type="button" data-action="' + action + '" data-id="' + esc(id) + '"';
  }

  function fmtDate(raw) {
    if (!raw) return "";
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? raw : new Intl.DateTimeFormat(window.SciStationI18n?.language || "zh-Hans", {
      month: "short",
      day: "numeric"
    }).format(d);
  }

  function localDate(d) {
    return [d.getFullYear(), String(d.getMonth() + 1).padStart(2, "0"), String(d.getDate()).padStart(2, "0")].join("-");
  }

  function bytes(n) {
    return n < 1024 ? n + " B" : n < 1048576 ? Math.ceil(n / 1024) + " KB" : (n / 1048576).toFixed(1) + " MB";
  }

  function scopedPapers() {
    return state.project ? state.papers.filter(p => (p.project_ids || []).includes(state.project.id)) : state.papers;
  }

  function paperRows(papers, projectID = "") {
    return list(papers.map(p => {
      const link = p.project_links?.[projectID];
      const meta = [p.authors?.slice(0, 3).join("、"), p.year || ""];
      if (projectID) {
        if (p.core_project_ids?.includes(projectID)) meta.push(text("核心文献", "Core paper"));
        if (link?.is_pinned) meta.push(text("已置顶", "Pinned"));
      }
      return row("book", p.title, meta.filter(Boolean).join(" · "), 'a href="' + esc(reader(p.id)) + '"',
        statusLabel[p.status] || statusLabel.unread, (projectID ? button(text("论文 Wiki", "Paper Wiki"), "open-paper-wiki", {id:p.id,kind:"bare"}) : "") +
        button(local("settingsEdit", "编辑", "Edit"), "edit-paper", {id:p.id,kind:"bare"}));
    }));
  }

  const taskPriorityLabels = {low: "低", medium: "中", high: "高", urgent: "紧急"};
  const taskTagPalette = [
    ["#A7D8F0", "#17465F"], ["#BEE7C8", "#1F5130"], ["#F7C8D0", "#6B2637"], ["#F9D99A", "#62440E"],
    ["#CDBFF5", "#3D2F73"], ["#BFE7E2", "#1E5550"], ["#F4C7A1", "#6A3A14"], ["#D6E3A3", "#48551A"]
  ];
  const closedTask = t => t.status === "done" || t.status === "cancelled";
  function taskDateLabel(t) {
    const range = t.startDate && t.dueDate && t.startDate !== t.dueDate ?
      t.startDate + " 至 " + t.dueDate : t.dueDate || t.startDate;
    return [range, t.dueTime].filter(Boolean).join(" ");
  }
  function taskOnDate(t, date) {
    const start = t.startDate || t.dueDate, end = t.dueDate || t.startDate;
    return Boolean(start && date >= start && date <= end);
  }
  function taskTagNames(extra = []) {
    const names = [...(state.taskCatalog?.tags.map(tag => tag.name) || []),
      ...state.tasks.flatMap(t => t.tags || []), ...extra];
    return [...new Set(names)].sort((a, b) => a.localeCompare(b));
  }

  // Keep the historical fallback palette for tags saved as plain task strings.
  function taskTagColors(name, definition) {
    let index = 0;
    for (const scalar of name) index = (index + scalar.codePointAt(0)) % taskTagPalette.length;
    const [background, foreground] = taskTagPalette[index];
    const hex = value => /^#[0-9a-f]{6}$/i.test(value || "");
    return {
      color: hex(definition?.color) ? definition.color : background,
      textColor: hex(definition?.textColor) ? definition.textColor : (definition ? "#1F2937" : foreground)
    };
  }

  function taskTagChip(name, definition) {
    const {color, textColor} = taskTagColors(name, definition);
    return '<span class="task-label" style="--task-label-bg:' + color + ';--task-label-fg:' + textColor + '">' + esc(name) + '</span>';
  }

  function detailButton(kind, object) {
    const label = text("查看详情", "View details") + " · " + object.title;
    return '<button type="button" class="icon" data-inspect-object="' + kind + '" data-id="' + esc(object.id) +
      '" aria-label="' + esc(label) + '" title="' + esc(label) + '" aria-pressed="false">' + icon("sidebar") + '</button>';
  }

  function taskRows(tasks) {
    const tags = new Map(state.taskCatalog?.tags.map(tag => [tag.name, tag.definition]));
    return list(tasks.map(t => {
      const closed = closedTask(t);
      const projects = (t.projectIds || [t.projectId]).map(id => state.projects.find(p => p.id === id)?.name);
      const facts = [
        !state.project && (projects.filter(Boolean).join("、") || "未分配"),
        taskDateLabel(t),
        taskPriorityLabels[t.priority] && taskPriorityLabels[t.priority] + "优先级",
        t.kind === "reading" && "论文阅读"
      ].filter(Boolean).join(" · ");
      const labels = (t.tags || []).map(name => taskTagChip(name, tags.get(name))).join("");
      return '<div class="row ' + (closed ? "completed" : "") + '"><button type="button" class="task-check ' +
        (closed ? "done" : "") + '" aria-label="' + esc((closed ? "重新打开" : "完成") + "：" + t.title) +
        '" data-action="toggle-task" data-id="' + esc(t.id) + '">' + (closed ? "✓" : "") +
        '</button><button class="row-main" data-action="edit-task" data-id="' + esc(t.id) + '"><span class="title">' +
        esc(t.title) + '</span>' + (facts ? '<span class="row-facts">' + esc(facts) + '</span>' : "") +
        (t.description ? '<span class="meta">' + esc(t.description.slice(0, 140)) + '</span>' : "") +
        (labels ? '<span class="task-labels">' + labels + '</span>' : "") +
        '</button><span class="tag status-tag">' + esc(statusLabel[t.status] || "待办") + '</span>' + detailButton("task", t) + '</div>';
    }));
  }
  const byRecent = (a, b) => String(b.updatedAt || b.updated_at || b.createdAt || "").localeCompare(String(a.updatedAt || a
    .updated_at || a.createdAt || ""));

  function updateNav() {
    navigation.update();
    window.SciProjectSidebar?.setProjects(state.projects, state.project?.id, state.modules);
    const title = state.view === "overview" && !state.project ? local("routeHome", "首页", "Home") : names[state.view];
    $("crumb").innerHTML = (state.project ? '<a href="' + esc(viewURL("projects", null)) + '">' + esc(names.projects) + '</a><span>/</span><a href="' +
      esc(viewURL("overview")) + '">' + esc(state.project.name) + '</a><span>/</span>' : "") + '<strong>' + esc(title) + '</strong>';
    document.title = title + " · Sci-Station";
  }

  function projectDirectory() {
    const create = button(local("toolbarNewProject", "新建项目", "New Project"), "new-project", {kind: "button primary", glyph: "plus"});
    return heading(names.projects, "", button(local("projectsArchivedTitle", "已归档项目", "Archived Projects"), "archived-projects") + create) +
      panel("我的项目 · " + state.projects.length, state.projects.length ? projectRows(state.projects) : empty(local("sidebarNoProjects", "暂无项目", "No projects")));
  }

  function projectRows(projects) {
    return list(projects.map(p => row("folder", p.name, p.description, 'a href="' + esc(viewURL("overview", p.id)) + '"', "", "", p)));
  }

  const dashboard = window.SciStationDashboard;
  const dashboardUI = {
    esc, heading, button, link, panel, paperRows, taskRows, meetingRows, viewURL, studio, fmtDate, row, rowAction, list, empty, reader, toolsPage
  };

  function meetingRows(items) {
    return list(items.map(m => row("chat", m.title || m.topic || "未命名圆桌", fmtDate(m.updated_at || m.created_at),
      'a href="' + esc(studio(m.id)) + '"', m.status === "closed" ? "已结束" : "会议")));
  }

  function noteRows(notes) {
    return list(notes.map(n => row("file", n.title, [n.namespace, n.tags?.join(" · "), fmtDate(n.updatedAt)].filter(Boolean).join(" · "),
      rowAction("read-note", n.id), "", detailButton("note", n))));
  }

  function wikiResults() {
    const query = state.wikiQuery.trim().toLocaleLowerCase();
    const notes = state.notes.filter(note => [note.title, note.namespace, ...(note.aliases || []), ...(note.tags || [])]
      .some(value => value?.toLocaleLowerCase().includes(query)));
    return panel(text("页面", "Pages") + " · " + notes.length, notes.length ? noteRows(notes.sort(byRecent)) :
      query ? empty(text("没有匹配的 Wiki 页面", "No matching wiki pages")) :
        empty(text("暂无 Wiki 页面", "No wiki pages yet"), "使用 Markdown、公式和 [[双链]] 记录研究过程。"));
  }

  function wikiPage() {
    const actions = moreActions(button(text("从论文创建", "Create from Paper"), "new-paper-wiki") +
      button(text("新建目录", "New Folder"), "new-wiki-folder", {glyph: "folder"}) +
      button(text("Markdown 片段", "Markdown Snippets"), "wiki-snippet-settings") +
      button(text("已归档页面", "Archived Pages"), "archived-notes")) +
      button(local("toolbarWikiNewPage", "新建页面", "New Page"), "new-note", {glyph: "plus", kind: "button primary"});
    const folders = state.wikiFolders.length ? panel(text("目录", "Folders"), list(state.wikiFolders.map(path =>
      row("folder", path, "", rowAction("read-wiki-folder", path))))) : "";
    const search = text("搜索 Wiki 页面", "Search wiki pages");
    return heading(text("项目 Wiki", "Project Wiki"), state.project.name, actions) +
      '<div class="toolbar"><input type="search" class="query" id="wiki-query" value="' + esc(state.wikiQuery) +
      '" placeholder="' + esc(search) + '" aria-label="' + esc(search) + '"></div>' +
      folders + '<div id="wiki-results" aria-live="polite">' + wikiResults() + '</div>';
  }

  function orderedLibraryPapers(projectID) {
    return (projectID ? scopedPapers() : state.papers).slice().sort((a, b) => {
      if (projectID) {
        const first = a.project_links?.[projectID], second = b.project_links?.[projectID];
        const pin = Number(Boolean(second?.is_pinned)) - Number(Boolean(first?.is_pinned));
        if (pin) return pin;
        if (first?.sort_order != null || second?.sort_order != null) {
          if (first?.sort_order == null) return 1;
          if (second?.sort_order == null) return -1;
          if (first.sort_order !== second.sort_order) return first.sort_order - second.sort_order;
        }
      }
      return byRecent(a, b) || a.id.localeCompare(b.id);
    });
  }

  function libraryResults(papers, projectID) {
    const filtered = Boolean(state.query.trim() || state.libraryCollection || state.libraryTag);
    return '<div id="library-selection-actions">' + E.library.renderSelectionActions(papers) + '</div>' +
      panel((projectID ? state.project.name : local("routePapers", "论文", "Papers")) + " · " + papers.length,
        papers.length ? E.library.renderPaperTable(papers, projectID) : empty(filtered ? text("没有匹配的文献", "No matching papers") : text("还没有收录文献", "The library is empty"),
          filtered ? "" : text("添加本地 PDF 或线上文献记录。", "Import a local PDF or add a paper by identifier.")));
  }

  function publicLibrary() {
    const limited = Boolean(state.project);
    const projectID = state.project?.id || "";
    const all = orderedLibraryPapers(projectID);
    const papers = E.library.filterPapers(all, projectID);
    const actions = moreActions(link(text("文献发现", "Discover papers"), toolsPage("discover")) +
      '<span id="library-export-action"' + (papers.length ? '' : ' hidden') + '>' +
      (papers.length ? E.library.exportButton(papers) : "") + '</span>' +
      button(text("管理集合和标签", "Manage collections and tags"), "manage-library")) +
      button(text("导入文献", "Import papers"), "new-paper", {glyph: "import", kind: "button primary"});
    return heading(limited ? text("项目文献", "Project Papers") : local("routeLibrary", "文献库", "Library"), "", actions) +
      '<div class="toolbar library-toolbar"><input type="search" class="query" id="paper-query" value="' + esc(state.query) +
      '" placeholder="' + esc(text("搜索标题、作者、DOI 或链接…", "Search title, author, DOI or link…")) +
      '" aria-label="' + esc(text("筛选文献", "Filter papers")) + '">' + E.library.renderFilters(all) +
      button(local("toolbarLibraryColumns", "表格列", "Table columns"), "library-columns") + '</div>' +
      '<div id="paper-results">' + libraryResults(papers, projectID) + '</div>';
  }

  function projectNeeded() {
    return heading(names[state.view]) + panel(text("科研项目", "Research projects"), empty(text("请选择科研项目", "Select a research project"), "", link(text("项目列表", "Projects"), viewURL("projects", null)) + button(local("toolbarNewProject", "新建项目", "New Project"),
    "new-project", {
      kind: "button primary",
      glyph: "plus"
    })));
  }

  function taskFilterSelect(id, label, all, selected, values) {
    const options = [["", all], ...values];
    return '<select id="' + id + '" aria-label="' + esc(label) + '">' + options.map(([value, text]) =>
      '<option value="' + esc(value) + '"' + (selected === value ? " selected" : "") + '>' + esc(text) + '</option>'
    ).join("") + '</select>';
  }

  function calendarView(tasks) {
    const d = state.month,
      year = d.getFullYear(),
      month = d.getMonth(),
      start = (new Date(year, month, 1).getDay() + 6) % 7,
      end = new Date(year, month + 1, 0).getDate(),
      today = localDate(new Date());
    const cells = Array.from({
      length: start
    }, () => '<div class="day" aria-hidden="true"></div>');
    for (let i = 1; i <= end; i++) {
      const date = localDate(new Date(year, month, i));
      const scheduled = tasks.filter(t => taskOnDate(t, date));
      cells.push('<div class="day ' + (today === date ? "today" : "") + '"><b>' + i + '</b>' +
        scheduled.map(t => button((date === t.dueDate && t.dueTime ? t.dueTime + " " : "") + t.title, "edit-task", {
          id: t.id,
          kind: "day-task" + (closedTask(t) ? " completed" : ""),
          title: [t.title, statusLabel[t.status], taskDateLabel(t)].filter(Boolean).join(" · ")
        })).join("") + '</div>');
    }
    return '<section class="panel"><div class="calendar-head">' + button("上一月", "month-prev", {
      kind: "bare"
    }) + '<strong>' + year + " 年 " + (month + 1) + ' 月</strong>' + button("下一月", "month-next", {
      kind: "bare"
    }) + '</div><div class="cal-grid">' + ["一", "二", "三", "四", "五", "六", "日"].map(s => '<span class="weekday">周' + s +
      '</span>').join("") + cells.join("") + '</div></section>';
  }

  function syncLoadPresentation() {
    $("main").setAttribute("aria-busy", String(state.loading));
    $("main").inert = state.loading;
    $("search-open").disabled = state.loading || Boolean(state.loadError);
    $("research-loading").hidden = !state.loading;
  }

  function render() {
    if (state.loading) return;
    updateNav();
    let out = "";
    if (state.loadError) {
      $("main").innerHTML = heading(text("页面加载失败", "Could not load view"), failedLoad?.label) +
        panel(text("本机服务", "Local service"), '<div role="alert">' +
          empty(state.loadError, "", button(local("homeRetry", "重试", "Retry"), "reload") +
            link(text("项目列表", "Projects"), viewURL("projects", null))) + '</div>');
      syncLoadPresentation();
      return;
    }
    if (state.view === "overview") out = dashboard.markup(state, dashboardUI);
    else if (["code","data","experiments","writing","theory"].includes(state.view)) {
      out = heading(names[state.view], state.project?.name) + panel(names[state.view], empty(text("此模块尚未提供编辑器", "This module has no editor yet"), "", state.project ? link(text("查看研究材料", "Open Materials"),viewURL("materials")) : ""));
    }
    else if (state.view === "projects") out = projectDirectory();
    else if (state.view === "papers") out = publicLibrary();
    else if (state.view === "meetings") out = heading("工作圆桌", state.project?.name || "模型讨论与研究报告", link("进入圆桌", studio(),
      "button primary", "chat")) + panel("项目会议", state.meetings.length ? meetingRows(state.meetings) : empty("暂无项目会议",
      "进入圆桌后可以创建讨论。"));
    else if (!state.project && state.view !== "tasks") out = projectNeeded();
    else if (state.view === "notes") out = wikiPage();
    else if (state.view === "tasks") {
      const tags = taskTagNames();
      const chosenTag = tags.includes(state.taskTag) ? state.taskTag : "";
      const filter = state.taskFilter || (state.calendar ? "all" : "open");
      const t = state.tasks.filter(t =>
        (filter === "all" || (filter === "open" ? !closedTask(t) : t.status === filter)) &&
        (!state.taskKind || t.kind === state.taskKind) &&
        (!chosenTag || t.tags?.includes(chosenTag))
      );
      const actions = moreActions(link(text("系统日历", "System Calendar"), toolsPage("calendar")) +
        button(text("管理任务标签", "Manage Task Tags"), "manage-task-tags")) +
        button(local("toolbarNewTask", "新建任务", "New Task"), "new-task", {glyph: "plus", kind: "button primary"});
      out = heading(text("日历与任务", "Calendar and Tasks"), state.project?.name || text("工作区", "Workspace"), actions);
      out += '<div class="toolbar task-filters">' + taskFilterSelect("task-project", text("项目", "Project"), text("全部项目", "All projects"),
        state.project?.id || "", state.projects.map(p => [p.id, p.name])) + '<div class="filters">' + [
        ["open", text("未完成", "Open")],
        ["done", text("已完成", "Completed")],
        ["cancelled", text("已取消", "Cancelled")],
        ["all", text("全部", "All")]
      ].map(([key, title]) => button(title, "task-filter", {
        id: key,
        kind: "chip " + (filter === key ? "active" : ""),
        pressed: filter === key
      })).join("") + '</div>' + taskFilterSelect("task-kind", text("任务类型", "Task type"), text("全部类型", "All types"), state.taskKind,
        [["general", text("普通任务", "General")], ["reading", text("论文阅读", "Paper reading")]]) +
        (tags.length ? taskFilterSelect("task-tag", text("任务标签", "Task tags"), text("全部标签", "All tags"), chosenTag, tags.map(tag => [tag, tag])) : "") +
        button(state.calendar ? text("切换到列表", "Switch to list") : text("切换到月历", "Switch to month"), "switch-calendar", {glyph: "agenda"}) +
        '</div>' + (state.calendar ? calendarView(t) : panel((state.project ? text("项目任务", "Project Tasks") : text("全部任务", "All Tasks")) + " · " + t.length,
          t.length ? taskRows(t) : empty(text("当前列表没有任务", "No tasks in this list"), text("可以创建带截止日期的任务。", "You can create a task with a due date."))));
    } else if (state.view === "materials") {
      out = heading("研究材料", state.project.name, button("浏览项目目录", "linked-materials", {
        glyph: "folder"
      }) + button("添加文件", "new-material", {
        glyph: "import",
        kind: "button primary"
      })) + panel("已添加的文件 · " + state.materials.length, state.materials.length ? list(state.materials.slice().sort(byRecent)
          .map(m => row("file", m.name, bytes(m.size) + " · " + fmtDate(m.updatedAt), rowAction("read-material", m.id)))
          ) : empty("暂无材料", "在这里保存与项目相关的图表、数据、代码或补充文件。"));
    } else if (state.view === "graph") out = graphView();
    $("main").innerHTML = out;
    window.SciContextRail?.update();
    const dashboardRoot = $("dashboard-view");
    if (dashboardRoot) dashboard.mount(dashboardRoot, state, render, toast);
    syncLoadPresentation();
  }

  function graphView() {
    const graphUI = window.SciResearchGraph;
    return graphUI.graphView({
      graph: state.graph,
      result: state.graphResult || state.graph,
      project: state.project,
      query: state.graphQuery || graphUI.defaultQuery,
      error: state.graphError,
      pending: state.graphPending,
      workflow: state.graphWorkflow,
      citationPanel: window.SciInspireGraph?.renderPanel({...state.inspire, papers: scopedPapers()}, {esc, button, panel})
    }, {esc, button, heading, panel, empty, link, route: navigation.route});
  }

  let citationRequest;
  async function applyInspire(online) {
    if (!state.inspire.seeds.length || state.view !== "graph" || state.inspire.pending) return;
    citationRequest?.abort();
    const controller = new AbortController();
    citationRequest = controller;
    const project = state.project.id;
    state.inspire.pending = true;
    state.inspire.error = "";
    render();
    try {
      const path = window.SciInspireGraph.lookupPath(projectPath("graph/citations", project), state.inspire.seeds, online);
      const rows = await request(path, {signal: controller.signal});
      if (citationRequest === controller && state.project?.id === project) state.inspire.rows = rows;
    } catch (error) {
      if (!controller.signal.aborted && citationRequest === controller) state.inspire.error = error.message;
    } finally {
      if (citationRequest === controller) {
        state.inspire.pending = false;
        citationRequest = null;
        render();
      }
    }
  }

  async function changeCitationSeeds(action, id) {
    if (state.inspire.pending) return;
    if (action === "inspire-seed-remove") {
      state.inspire.seeds = state.inspire.seeds.filter(seed => seed !== id);
    } else {
      if (state.inspire.seeds.length >= 6) throw new Error("最多同时查看 6 个种子。");
      const raw = $("inspire-record")?.value?.trim();
      const seed = id || (raw ? window.SciInspireGraph.publicSeed(raw) : $("inspire-paper")?.value);
      if (!seed) throw new Error("请选择项目论文，或填写有效的 INSPIRE 编号。");
      if (state.inspire.seeds.includes(seed)) return;
      state.inspire.seeds = [...state.inspire.seeds, seed];
    }
    state.inspire.rows = [];
    state.inspire.error = "";
    if (state.inspire.seeds.length) await applyInspire(false);
    else render();
  }

  let graphQueryNumber = 0;
  async function applyGraphQuery(query) {
    const project = state.project?.id;
    const currentLoad = navEpoch;
    const currentQuery = ++graphQueryNumber;
    const isCurrent = () => currentLoad === navEpoch && currentQuery === graphQueryNumber &&
      state.view === "graph" && state.project?.id === project;
    state.graphQuery = query;
    state.graphPending = true;
    state.graphError = "";
    render();
    try {
      if (query.target && !query.focus) throw new Error("请选择路径起点。");
      const path = window.SciResearchGraph.queryPath(projectPath("graph", project), query);
      const result = await request(path);
      if (isCurrent()) state.graphResult = result;
    } catch (err) {
      if (isCurrent()) {
        state.graphError = err.message;
        state.graphResult = null;
      }
    } finally {
      if (isCurrent()) {
        state.graphPending = false;
        render();
        $("graph-query")?.querySelector("button[type=submit]")?.focus();
      }
    }
  }

  async function applyGraphWorkflow(query) {
    const project = state.project?.id;
    const currentLoad = navEpoch;
    const lookup = {query, pending: true};
    const isCurrent = () => state.graphWorkflow === lookup && currentLoad === navEpoch &&
      state.view === "graph" && state.project?.id === project;
    state.graphWorkflow = lookup;
    render();
    try {
      const path = window.SciResearchGraph.workflowPath(projectPath("graph/workflow", project), query);
      const result = await request(path);
      if (isCurrent()) lookup.result = result;
    } catch (err) {
      if (isCurrent()) lookup.error = err.message;
    } finally {
      if (isCurrent()) {
        lookup.pending = false;
        render();
        $("graph-workflow-query")?.querySelector("button[type=submit]")?.focus();
      }
    }
  }

  function currentView() {
    const token = navEpoch;
    return () => token === navEpoch && !state.loading && !state.loadError;
  }

  async function load(projectId, view, options = {}) {
    const {historyMode = "replace", calendar: requestedCalendar, afterLoad} = options;
    const token = ++navEpoch;
    let targetView = Object.hasOwn(names, view) ? view : "overview";
    const scope = state.projects.find(project => project.id === projectId)?.name;
    const title = targetView === "overview" && !projectId ? local("routeHome", "首页", "Home") : names[targetView];
    const label = scope ? scope + " · " + title : title;
    const params = new URL(location.href).searchParams;
    const tab = params.get("tab");
    const savedCalendar = tab === "calendar" || (tab === null && params.get("calendar") === "1");
    const calendarRequested = requestedCalendar ?? (historyMode !== "push" && savedCalendar);
    citationRequest?.abort();
    citationRequest = null;
    state.inspire.pending = false;
    failedLoad = null;
    state.loadError = "";
    state.loading = true;
    syncLoadPresentation();
    $("research-loading-message").textContent = text(`正在加载 ${label}…`, `Loading ${label}…`);
    window.SciContextRail?.update();
    try {
      const [projects, papers, sessions, organization] = await Promise.all([
        request("projects"), request("papers"), request("/api/studio/sessions"), request("papers/organization")
      ]);
      if (token !== navEpoch) return;
      const allProjects = projects || [];
      let nextProject = allProjects.find(p => p.id === projectId) || null;
      let fallback = Boolean(projectId && !nextProject);
      if (fallback) targetView = "projects";
      const config = await window.SciStationModules?.load(nextProject?.id || "");
      if (token !== navEpoch) return;
      const calendar = targetView === "tasks" && calendarRequested;
      const module = targetView==="overview" && !nextProject ? null : navigation.viewModules[calendar?"calendar":targetView] || (targetView==="projects"?"projects":null);
      if (!navigation.enabled(config,module)) {
        fallback = true;
        if(module==="projects") nextProject=null;
        targetView="overview";
      }
      const suffixes = ["notes", "tasks", "materials"];
      let graphError = "";
      const graph = {nodes: [], edges: []};
      const graphLoad = nextProject && targetView === "graph" ?
        request("projects/" + enc(nextProject.id) + "/graph").catch(err => {
          graphError = err.message;
          return graph;
        }) : graph;
      const [values,dashboardData,paperWikiStatus,taskCatalog] = await Promise.all([nextProject ?
        Promise.all([...suffixes.map(k => request("projects/" + enc(nextProject.id) + "/" + k)), graphLoad, targetView === "notes" ? request("projects/" + enc(nextProject.id) + "/wiki/folders") : []]) :
        Promise.all([[], ["overview", "tasks"].includes(targetView) ? request("tasks") : [], [], {nodes: [], edges: []}]),
        targetView === "overview" ? dashboard.load(request, nextProject?.id, config) : null,
        targetView === "papers" && !nextProject && organization.library?.visible_columns.includes("wiki") ?
          request("paper-wiki-status") : {},
        targetView === "tasks" ? request("task-tags") : null
      ]);
      if (token !== navEpoch) return;
      // Publish the snapshot together before unlocking the new view.
      state.modules = config;
      state.view = targetView;
      state.calendar = calendar && !fallback;
      state.projects = allProjects;
      state.papers = papers || [];
      state.organization = organization;
      state.paperWikiStatus = paperWikiStatus;
      state.taskCatalog = taskCatalog;
      if (state.libraryCollection !== "unfiled" && !Object.hasOwn(organization.collections, state.libraryCollection)) state.libraryCollection = "";
      if (nextProject?.id !== state.project?.id) {
        state.wikiQuery = "";
        state.inspire = {seeds: [], rows: [], pending: false, error: ""};
      }
      state.project = nextProject;
      const rooms = Array.isArray(sessions) ? sessions : sessions.sessions || [];
      state.meetings = nextProject ? rooms.filter(m => m.project_id === nextProject.id) : rooms;
      [state.notes, state.tasks, state.materials, state.graph, state.wikiFolders = []] = values;
      state.graphResult = null;
      state.graphQuery = null;
      state.graphError = graphError;
      state.graphPending = false;
      state.graphWorkflow = null;
      state.dashboardData = dashboardData;
      const current=new URL(location.href);
      if (fallback || historyMode==="push" || (historyMode==="replace" &&
          ((current.searchParams.get("view") || "overview") !== state.view ||
           (current.searchParams.get("project") || "") !== (nextProject?.id || "")))) {
        navigation.commitURL(viewURL(state.calendar ? "calendar" : state.view),fallback?"replace":historyMode);
      }
      if(fallback && projectId && !nextProject) toast("这个项目已归档或不存在，请从项目列表重新选择。");
    } catch (err) {
      if (token !== navEpoch) return;
      state.loadError = err.message || text("本机服务暂时无法完成此请求。", "The local service could not complete this request.");
      failedLoad = {label, retry: () => load(projectId, view, {...options, calendar: calendarRequested})};
    }
    state.loading = false;
    render();
    if (state.loadError) return;
    await afterLoad?.(currentView());
    return token === navEpoch;
  }

  function go(view) {
    if (!Object.hasOwn(names, view) || !close()) return;
    state.query = "";
    state.libraryCollection = "";
    state.libraryTag = "";
    E.library.clearSelection();
    load(state.project?.id, view, {historyMode: "push"});
    window.SciShellLayout?.dismissProjectNav();
    window.scrollTo(0, 0);
  }

  function refresh() {
    if (state.loading) return;
    if (failedLoad) return failedLoad.retry();
    return load(state.project?.id, state.view, {
      historyMode: "replace"
    });
  }

  function renderWikiMarkdown(host, source, links = {}) {
    window.SciMarkdown.render(host, source, {
      breaks:false,
      allowHTML:true,
      resolveImage(raw) {
        let filename = raw;
        try { filename = decodeURIComponent(raw); } catch {}
        const material = state.materials.find(m => m.name === filename && /^image\/(jpeg|png|gif|webp)$/i.test(m.mediaType || ""));
        if (material && state.project)
          return "/api/research/" + projectPath("materials/" + enc(material.id) + "/content");
      },
    });
    const walker = document.createTreeWalker(host, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const node of nodes) {
      if (node.parentElement?.closest("code,pre,a,.katex")) continue;
      const str = node.textContent,
        re = /\[\[([^\[\]\n|#]+)(?:#[^\[\]|]*)?(?:\|([^\[\]]*))?\]\]/g;
      let match, pos = 0;
      const frag = document.createDocumentFragment();
      while ((match = re.exec(str))) {
        frag.append(str.slice(pos, match.index));
        const key = match[1].trim();
        if (Object.hasOwn(links, key)) {
          const a = document.createElement("button");
          a.type = "button";
          a.className = "bare wiki-reference";
          a.dataset.action = "read-note";
          a.dataset.id = links[key];
          a.textContent = match[2]?.trim() || key;
          frag.append(a);
        } else {
          frag.append(match[0]);
        }
        pos = re.lastIndex;
      }
      if (pos) {
        frag.append(str.slice(pos));
        node.replaceWith(frag);
      }
    }
  }

  function search() {
    if (state.loading || state.loadError) return;
    dialog("搜索工作区",
      '<input id="search-query" class="query-input" type="search" placeholder="输入标题、作者、标签或笔记内容" aria-label="搜索"><div id="search-results" class="search-results"></div>'
      );
    const input = $("search-query");

    function update() {
      const query = input.value.trim().toLowerCase();
      if (!query) {
        $("search-results").textContent = "搜索共享文献和当前项目的笔记、任务、材料。";
        return;
      }
      const groups = [
        [state.papers, "论文", "paper"],
        [state.notes, "笔记", "note"],
        [state.tasks, "任务", "task"],
        [state.materials, "材料", "material"]
      ];
      const hits = [];
      for (const [items, label, kind] of groups)
        for (const x of items) {
          const title = x.title || x.name;
          const text = [title, x.body, x.description, x.abstract, x.doi, x.citekey, ...(x.authors || []), ...(x.tags || [])]
            .join(" ").toLowerCase();
          if (!text.includes(query)) continue;
          const content = '<span class="title">' + esc(title) + '</span><span class="meta">' + label + '</span>';
          hits.push(kind === "paper" ? '<a class="search-result" href="' + esc(reader(x.id)) + '">' + content + '</a>' :
            '<button class="search-result" data-action="' + ({
              note: "read-note",
              task: "edit-task",
              material: "read-material"
            })[kind] + '" data-id="' + esc(x.id) + '">' + content + '</button>');
        }
      $("search-results").innerHTML = hits.slice(0, 40).join("") || empty("没有找到匹配内容");
    }
    input.addEventListener("input", update);
    update();
    input.focus();
  }
  const E = {
    projectBadge,
    state,
    text,
    local,
    $,
    esc,
    enc,
    request,
    projectPath,
    taskPath,
    refresh,
    load,
    render,
    button,
    detailButton,
    link,
    empty,
    dialog,
    close,
    toast,
    reader,
    wikiURL,
    statusLabel,
    taskPriorityLabels,
    taskOnDate,
    taskTagNames,
    taskTagColors,
    taskTagChip,
    toolsPage,
    renderWikiMarkdown,
    bytes,
    search,
    updateNav,
    currentView,
    start: route
  };
  window.SciResearch = E;
  function handleWorkspaceCommand(key) {
    if ((state.loading || state.loadError) &&
        ["archivedProjects", "find", "newProject", "importIdentifier", "importPDF"].includes(key)) return true;
    if(key==="archivedProjects"){E.formAction("archived-projects");return true;}
    if(key==="find") {search();return true;}
    if(!["newProject","importIdentifier","importPDF"].includes(key) || !E.formAction) return false;
    const field = key === "importPDF" ? "pdf" : "identifiers";
    if ($("modal").open) {
      if (key !== "newProject") $("dialog-content").querySelector('[data-paper-intake] [name="' + field + '"]')?.focus();
      return true;
    }
    if (key === "newProject") E.formAction("new-project");
    else E.formAction("new-paper", field);
    return true;
  }
  window.addEventListener("scistation:command",event=>{
    if(handleWorkspaceCommand(event.detail)) event.preventDefault();
  });
  document.addEventListener("click", async ev => {
    const more = document.querySelectorAll("#main .more-actions[open]")[0];
    if (more && (!more.contains(ev.target) || ev.target.closest?.(".more-action-items button, .more-action-items a"))) {
      if (more.contains(ev.target)) more.querySelector("summary").focus();
      more.open = false;
    }
    const target = ev.target.closest?.("button,a");
    if (!target || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
    if (state.loading && target.closest("#main")) {
      ev.preventDefault();
      return;
    }
    if (target.dataset.inspectObject) {
      window.SciContextRail?.selectObject(target.dataset.inspectObject, target.dataset.id, true);
      return;
    }
    if (target.hasAttribute("data-project")) {
      ev.preventDefault();
      if (!close()) return;
      window.SciShellLayout?.dismissProjectNav();
      await load(target.dataset.project, "overview", {
        historyMode: "push"
      });
      return;
    }
    if (target.dataset.view) {
      ev.preventDefault();
      go(target.dataset.view);
      return;
    }
    const action = target.dataset.action,
      id = target.dataset.id;
    if (!action) return;
    const isCurrent = currentView();
    try {
      if (action === "task-filter") {
        state.taskFilter = id;
        render();
        $("main").querySelector('[data-action="task-filter"][aria-pressed="true"]')?.focus();
      } else if (action === "switch-calendar") {
        state.calendar = !state.calendar;
        const url = new URL(location.href);
        url.searchParams.delete("calendar");
        if (state.calendar) url.searchParams.set("tab","calendar"); else url.searchParams.delete("tab");
        navigation.commitURL(url,"push");
        render();
      } else if (action.startsWith("month-")) {
        state.month = new Date(state.month.getFullYear(), state.month.getMonth() + (action === "month-prev" ? -1 : 1),
          1);
        render();
      } else if (action === "reload") await refresh();
      else if (action === "inspire-online" || action === "inspire-local") await applyInspire(action === "inspire-online");
      else if (action === "inspire-seed-add" || action === "inspire-seed-remove") await changeCitationSeeds(action, id);
      else if (action === "graph-rebuild") {
        const query = state.graphQuery;
        const workflow = state.graphWorkflow?.query;
        const project = state.project?.id;
        if (!await refresh()) return;
        if (query && !state.graphError && state.project?.id === project && state.view === "graph") {
          const ids = new Set(state.graph.nodes.map(node => node.id));
          if ((!query.focus || ids.has(query.focus)) && (!query.target || ids.has(query.target))) await applyGraphQuery(query);
        }
        if (workflow && state.project?.id === project && state.view === "graph") await applyGraphWorkflow(workflow);
      } else if (action === "graph-occurrence") {
        const edge = (state.graphResult || state.graph).edges.find(edge => edge.occurrences?.some(item => item.id === id));
        const occurrence = edge?.occurrences.find(item => item.id === id);
        if (occurrence?.source === "wikilink") {
          if (E.openWikiNote) await E.openWikiNote(edge.source, {line: occurrence.line, column: occurrence.column,
            revision: occurrence.sourceRevision, text: occurrence.quote});
          else await E.formAction("read-note", edge.source);
        }
      } else if (action === "graph-open") {
        const n = state.graphResult?.nodes.find(n => n.id === id) || state.graph.nodes.find(n => n.id === id);
        if (!n) return;
        const raw = n.id.replace(/^(?:note|paper|task)[:/]/, "");
        if (n.kind === "reference") dialog("外部引文", empty(n.label, "此标识符尚未关联到库内论文。", button(text("导入文献", "Import papers"), "new-paper")));
        else if (n.kind === "paper") location.href = reader(raw);
        else if (n.kind === "meeting") location.href = studio(n.id.slice("meeting:".length));
        else if (n.kind === "missing") dialog("来源已移除", empty("此条目当前不可用"));
        else await E.formAction(n.kind === "task" ? "edit-task" : "read-note", raw);
      } else if (action === "toggle-task") {
        const t = state.tasks.find(t => t.id === id);
        if (!t) return;
        target.disabled = true;
        await request(taskPath(id, t.projectId || state.project?.id), {
          method: "PATCH",
          body: {
            revision: t.revision,
            status: closedTask(t) ? "open" : "done"
          }
        });
        await refresh();
      } else await E.formAction(action, id);
    } catch (err) {
      target.disabled = false;
      if (isCurrent()) toast(err.message);
    }
  });
  document.addEventListener("change", async ev => {
    if (state.loading || state.loadError) return;
    if (ev.target.id === "task-project") {
      if (!close()) {
        ev.target.value = state.project?.id || "";
        return;
      }
      await load(ev.target.value, "tasks", {historyMode: "push", calendar: state.calendar});
      $("task-project")?.focus();
    } else if (ev.target.id === "task-kind") {
      state.taskKind = ev.target.value;
      render();
      $("task-kind").focus();
    } else if (ev.target.id === "task-tag") {
      state.taskTag = ev.target.value;
      render();
      $("task-tag").focus();
    } else if (ev.target.name === "operation" && ev.target.form?.id === "graph-workflow-query") {
      window.SciResearchGraph.updateWorkflowForm(ev.target.form);
    }
  });
  document.addEventListener("submit", ev => {
    if (ev.target.id !== "graph-query" && ev.target.id !== "graph-workflow-query") return;
    ev.preventDefault();
    if (state.loading || state.loadError) return;
    const data = new FormData(ev.target);
    const query = Object.fromEntries(data);
    if (ev.target.id === "graph-workflow-query") void applyGraphWorkflow(query);
    else void applyGraphQuery(query);
  });
  function filterResults(event) {
    const input = event.target;
    if (event.isComposing || state.loading || state.loadError) return;
    if (input.id === "wiki-query" && state.wikiQuery !== input.value) {
      state.wikiQuery = input.value;
      $("wiki-results").innerHTML = wikiResults();
      return;
    }
    if (input.id !== "paper-query" || input.value === state.query) return;
    state.query = input.value;
    const projectID = state.project?.id || "";
    const papers = E.library.filterPapers(orderedLibraryPapers(projectID), projectID);
    $("paper-results").innerHTML = libraryResults(papers, projectID);
    $("library-export-action").hidden = papers.length === 0;
    $("library-export-action").innerHTML = papers.length ? E.library.exportButton(papers) : "";
    window.SciContextRail?.update();
  }
  document.addEventListener("input", filterResults);
  document.addEventListener("compositionend", filterResults);
  $("search-open").onclick = search;
  $("modal-close").onclick = close;
  document.addEventListener("keydown", ev => {
    if (ev.key === "Escape") {
      const more = document.querySelectorAll("#main .more-actions[open]")[0];
      if (more) {
        ev.preventDefault();
        more.open = false;
        more.querySelector("summary").focus();
      }
    }
    if (!$("modal").open && (ev.metaKey || ev.ctrlKey) && ev.key.toLowerCase() === "k") {
      ev.preventDefault();
      search();
    }
  });

  async function route() {
    const u = new URL(location.href);
    const project = u.searchParams.get("project");
    const view = u.searchParams.get("view") || "overview";
    const task = u.searchParams.get("task");
    const command = u.searchParams.get("command");
    if (command) {
      u.searchParams.delete("command");
      navigation.commitURL(u, "replace");
    }
    await window.SciStationI18n?.ready;
    if (location.href !== u.href) return;
    await load(project, view, {historyMode: "none", afterLoad: async isCurrent => {
      if (!isCurrent() || location.href !== u.href) return;
      if (command) handleWorkspaceCommand(command);
      if (task && view === "tasks" && (state.project?.id || null) === project && state.tasks.some(t => t.id === task)) {
        await E.formAction?.("edit-task", task);
      }
      if (state.project?.id !== project) return;
      const note = u.searchParams.get("note"), material = u.searchParams.get("material");
      const citation = window.SciEvidence?.locator(u.searchParams);
      try {
        if (note && state.view === "notes") await E.openWikiNote(note, {citation});
        else if (material && citation && state.view === "materials") await E.openMaterialEvidence(material, citation);
      } catch (error) {
        if (!isCurrent()) return;
        if (citation) dialog("引用原文不可用", empty(error.message));
        else toast(error.message);
      }
    }});
  }
  navigation.setHistoryGuard(close);
  window.addEventListener("popstate", route);
  window.addEventListener("sci:language", () => {
    if ($("main").getAttribute("aria-busy") === "false" && !$("modal").open) render();
  });
  window.addEventListener("pageshow", ev => {
    if (ev.persisted) route();
  });
  for (const el of document.querySelectorAll("[data-icon]")) el.innerHTML = icon(el.dataset.icon);
})();
