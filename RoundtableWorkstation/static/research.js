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
  const names = {
    overview: "项目概览",
    projects: "项目",
    papers: "共享文献",
    notes: "项目 Wiki",
    tasks: "任务与日历",
    materials: "研究材料",
    graph: "知识关联",
    meetings: "工作圆桌"
  };
  const glyphs = {
    overview: "dashboard",
    papers: "book",
    notes: "file",
    tasks: "agenda",
    materials: "folder",
    graph: "subagent",
    meetings: "chat"
  };
  const shapes = {
    dashboard: '<rect x="3" y="3" width="8" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="11" rx="1.5"/><rect x="3" y="13" width="8" height="8" rx="1.5"/><rect x="14" y="17" width="7" height="4" rx="1.5"/>',
    book: '<path d="M3 5.5c3.5-1.5 6.5-1 9 .7 2.5-1.7 5.5-2.2 9-.7v13c-3.5-1.5-6.5-1-9 .7-2.5-1.7-5.5-2.2-9-.7zM12 6.2v13"/>',
    search: '<circle cx="10" cy="10" r="6.3"/><path d="m15 15 5.5 5.5"/>',
    tools: '<path d="m9 3 6 0m-4 0v6l-6 9a2 2 0 0 0 1.5 3h11a2 2 0 0 0 1.5-3l-6-9V3m-4 12h7"/>'
  };
  const icon = key => shapes[key] ?
    '<svg aria-hidden="true" class="ui-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linejoin="round" stroke-linecap="round">' +
    shapes[key] + '</svg>' : window.RoundtableIcons.icon(key);
  const statusLabel = {
    unread: "未读",
    reading: "阅读中",
    read: "已读",
    open: "待办",
    doing: "进行中",
    inProgress: "进行中",
    cancelled: "已取消",
    done: "已完成"
  };
  const colors = ["#8170c1", "#4c9188", "#cb835c", "#708abe", "#a1698e"];
  const state = {
    projects: [],
    project: null,
    papers: [],
    organization: {revision: 0, collections: {}, tags: {}},
    libraryCollection: "",
    libraryTag: "",
    notes: [],
    tasks: [],
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
    query: "",
    taskFilter: "open",
    taskKind: "",
    taskTag: "",
    calendar: false,
    month: new Date(),
    loading: false,
    loadError: ""
  };
  let navEpoch = 0,
    toastTimer, modalCleanup = null, modalCanDismiss = null;
  const apiRoot = "/api/research/";
  async function request(path, options = {}) {
    const init = {
      method: options.method || "GET",
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
      let msg;
      try {
        const j = await res.json();
        msg = j.error || j.message;
      } catch {}
      const error = new Error(msg || "操作失败（" + res.status + "）");
      error.status = res.status;
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

  function reader(paper) {
    return navigation.route("/reader", {paper, project: state.project?.id});
  }

  function toolsPage(tab) {
    return navigation.route("/tools", {tab, project: state.project?.id});
  }

  function viewURL(view, id = state.project?.id) {
    if (view === "tasks" && state.calendar) return navigation.route("/research", {view, project: id, calendar: 1});
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
    if (modalCanDismiss && !modalCanDismiss()) return false;
    if ($("modal").open) $("modal").close();
    return true;
  }
  $("modal").addEventListener("cancel", ev => {
    if (modalCanDismiss && !modalCanDismiss()) ev.preventDefault();
  });
  $("modal").addEventListener("close", () => {
    if (modalCleanup) modalCleanup();
    modalCleanup = null;
    modalCanDismiss = null;
    $("dialog-content").replaceChildren();
  });

  function button(label, action, options = {}) {
    const {
      id = "", kind = "button", glyph = "", title = ""
    } = options;
    return '<button type="button" class="' + kind + '" data-action="' + action + '" data-id="' + esc(id) +
      '"' + (title ? ' title="' + esc(title) + '"' : '') + '>' + (glyph ?
      icon(glyph) : "") + esc(label) + '</button>';
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

  function heading(title, sub = "", actions = "") {
    return '<div class="page-head"><div><h1>' + esc(title) + '</h1>' + (sub ? '<p>' + esc(sub) + '</p>' : '') +
      '</div><div class="head-actions">' + actions + '</div></div>';
  }

  function row(glyph, title, meta, control, tag = "", more = "") {
    return '<div class="row"><div class="glyph">' + icon(glyph) + '</div><' + control +
      ' class="row-main"><span class="title">' + esc(title) + '</span>' + (meta ? '<span class="meta">' + esc(meta) +
        '</span>' : '') + '</' + (control.startsWith("a ") ? 'a' : 'button') + '>' + (tag ? '<span class="tag">' + esc(
        tag) + '</span>' : '') + more + '</div>';
  }

  function rowAction(action, id) {
    return 'button type="button" data-action="' + action + '" data-id="' + esc(id) + '"';
  }

  function fmtDate(raw) {
    if (!raw) return "";
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? raw : new Intl.DateTimeFormat("zh-CN", {
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

  function paperRows(papers, projectID = "", showOrganization = false) {
    return list(papers.map(p => {
      const link = p.project_links?.[projectID];
      const meta = [p.authors?.slice(0, 3).join("、"), p.year || "", p.citekey];
      if (showOrganization) {
        meta.push(p.publication_title);
        if (p.collection_id) meta.push(E.library.collectionPath(p.collection_id));
      }
      if (projectID) {
        if (p.core_project_ids?.includes(projectID)) meta.push("核心文献");
        if (link?.is_pinned) meta.push("已置顶");
        if (link?.sort_order != null) meta.push("序号 " + link.sort_order);
        if (link?.folder_path) meta.push("文件夹 " + link.folder_path);
        if (link?.use_for?.length) meta.push("用途 " + link.use_for.join("、"));
      }
      return row("book", p.title, meta.filter(Boolean).join(" · "), 'a href="' + esc(reader(p.id)) + '"',
        statusLabel[p.status] || "未读", (showOrganization ? E.library.paperTags(p) : "") +
        button("编辑", "edit-paper", {id: p.id, kind: "bare"}) +
        (showOrganization ? E.library.selectionCheckbox(p) : ""));
    }));
  }

  const taskPriorityLabels = {low: "低", medium: "中", high: "高", urgent: "紧急"};
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
  function taskRows(tasks) {
    return list(tasks.map(t => {
      const closed = closedTask(t);
      const projects = (t.projectIds || [t.projectId]).map(id => state.projects.find(p => p.id === id)?.name);
      const meta = [!state.project ? projects.filter(Boolean).join("、") || "未分配" : "", t.kind === "reading" ? "论文阅读" : "", taskDateLabel(t),
        taskPriorityLabels[t.priority] ? taskPriorityLabels[t.priority] + "优先级" : "", ...(t.tags || []), t.description];
      return '<div class="row ' + (closed ? "completed" : "") + '"><button type="button" class="task-check ' +
        (closed ? "done" : "") + '" aria-label="' + esc((closed ? "重新打开" : "完成") + "：" + t.title) +
        '" data-action="toggle-task" data-id="' + esc(t.id) + '">' + (closed ? "✓" : "") +
        '</button><button class="row-main" data-action="edit-task" data-id="' + esc(t.id) + '"><span class="title">' +
        esc(t.title) + '</span><span class="meta">' + esc(meta.filter(Boolean).join(" · ").slice(0, 140)) +
        '</span></button><span class="tag">' + esc(statusLabel[t.status] || "待办") + '</span></div>';
    }));
  }
  const byRecent = (a, b) => String(b.updatedAt || b.updated_at || b.createdAt || "").localeCompare(String(a.updatedAt || a
    .updated_at || a.createdAt || ""));

  function updateNav() {
    navigation.update();
    const modules = $("project-modules");
    modules.hidden = !state.project;
    modules.innerHTML = state.project ? Object.entries(names).filter(([id]) => id !== "projects").map(([id, name]) =>
      '<a data-view="' + id + '" href="' + esc(viewURL(id)) + '"' +
      (id === state.view ? ' aria-current="page"' : '') + '>' + esc(name) + '</a>').join("") +
      link("文献推荐", toolsPage("discover"), "module") +
      link("AI 工作流", navigation.route("/lab", {project: state.project.id}), "module") : "";
    $("projectnav").innerHTML = state.projects.map((p, i) => '<a class="project-item ' + (p.id === state.project?.id ?
        'active' : '') + '" data-project="' + esc(p.id) + '" href="' + esc(viewURL("overview", p.id)) +
      '"><span class="project-dot" style="--project-color:' + colors[i % colors.length] + '"></span><span>' + esc(p
      .name) + '</span></a>').join("");
    const title = state.view === "overview" && !state.project ? "首页" : names[state.view];
    $("crumb").innerHTML = (state.project ? '<a href="' + esc(viewURL("projects", null)) + '">项目</a><span>/</span><a href="' +
      esc(viewURL("overview")) + '">' + esc(state.project.name) + '</a><span>/</span>' : "") + '<strong>' + esc(title) + '</strong>';
    document.title = title + " · Sci-Station";
  }

  function projectDirectory() {
    const create = button("新建项目", "new-project", {kind: "button primary", glyph: "plus"});
    return heading("项目", "", button("已归档项目", "archived-projects") + create) +
      panel("我的项目 · " + state.projects.length, state.projects.length ? projectRows(state.projects) : empty("暂无项目"));
  }

  function projectRows(projects) {
    return list(projects.map(p => row("folder", p.name, p.description, 'a href="' + esc(viewURL("overview", p.id)) + '"')));
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
      rowAction("read-note", n.id))));
  }

  function publicLibrary() {
    const limited = Boolean(state.project);
    const projectID = limited ? state.project.id : "";
    const all = (limited ? scopedPapers() : state.papers).slice().sort((a, b) => {
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
    const papers = E.library.filterPapers(all, projectID);
    const filtered = Boolean(state.query.trim() || state.libraryCollection || state.libraryTag);
    const actions = (papers.length ? E.library.exportButton(papers) : "") +
      button("管理集合和标签", "manage-library") + button("导入文献", "new-paper", {
      glyph: "import",
      kind: "button primary"
    });
    return heading(limited ? "项目文献" : "文献库", "", link("文献发现", toolsPage("discover")) + link("PDF 转换", toolsPage("convert")) + actions) +
      '<div class="toolbar"><input type="search" class="query" id="paper-query" value="'  + esc(state.query) +
      '" placeholder="搜索标题、作者、DOI…" aria-label="筛选文献">' + E.library.renderFilters(all) + '</div>' +
      panel((limited ? state.project.name : "文献") + " · " + papers.length + " 篇",
        papers.length ? paperRows(papers, projectID, true) : empty(filtered ? "没有匹配的文献" : "还没有收录文献",
          filtered ? "" : "添加本地 PDF 或线上文献记录。", filtered ? "" : button("导入文献", "new-paper", {
            glyph: "import"
          })));
  }

  function projectNeeded() {
    return heading(names[state.view]) + panel("科研项目", empty("请选择科研项目", "", link("项目列表", viewURL("projects", null)) + button("新建项目",
    "new-project", {
      kind: "button primary",
      glyph: "plus"
    })));
  }

  function taskFilterSelect(id, label, all, selected, values) {
    const options = [["", all], ...values];
    return '<select id="' + id + '" aria-label="' + label + '">' + options.map(([value, text]) =>
      '<option value="' + esc(value) + '"' + (selected === value ? " selected" : "") + '>' + esc(text) + '</option>'
    ).join("") + '</select>';
  }

  function calendarView() {
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
      const tasks = state.tasks.filter(t => taskOnDate(t, date));
      cells.push('<div class="day ' + (today === date ? "today" : "") + '"><b>' + i + '</b>' +
        tasks.map(t => button((date === t.dueDate && t.dueTime ? t.dueTime + " " : "") + t.title, "edit-task", {
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

  function render() {
    updateNav();
    let out = "";
    if (state.loadError) {
      $("main").setAttribute("aria-busy", "false");
      $("main").innerHTML = heading("读取工作区时遇到问题") + panel("本机服务", empty(state.loadError, "", button("重试", "reload") + link("项目列表", viewURL("projects", null))));
      return;
    }
    if (state.view === "overview") out = dashboard.markup(state, dashboardUI);
    else if (state.view === "projects") out = projectDirectory();
    else if (state.view === "papers") out = publicLibrary();
    else if (state.view === "meetings") out = heading("工作圆桌", state.project?.name || "模型讨论与研究报告", link("进入圆桌", studio(),
      "button primary", "chat")) + panel("项目会议", state.meetings.length ? meetingRows(state.meetings) : empty("暂无项目会议",
      "进入圆桌后可以创建讨论。"));
    else if (!state.project && state.view !== "tasks") out = projectNeeded();
    else if (state.view === "notes") out = heading("项目 Wiki", state.project.name, button("已归档页面", "archived-notes") + button("新建页面", "new-note", {
      glyph: "plus",
      kind: "button primary"
    })) + panel("页面 · " + state.notes.length, state.notes.length ? noteRows(state.notes.slice().sort(byRecent)) : empty(
      "暂无 Wiki 页面", "使用 Markdown、公式和 [[双链]] 记录研究过程。"));
    else if (state.view === "tasks") {
      const tags = [...new Set(state.tasks.flatMap(t => t.tags || []))].sort((a, b) => a.localeCompare(b));
      const chosenTag = tags.includes(state.taskTag) ? state.taskTag : "";
      const t = state.tasks.filter(t =>
        (state.taskFilter === "all" || (state.taskFilter === "open" ? !closedTask(t) : t.status === state.taskFilter)) &&
        (!state.taskKind || t.kind === state.taskKind) &&
        (!chosenTag || t.tags?.includes(chosenTag))
      );
      out = heading("日历与任务", state.project?.name || "工作区", link("系统日历", toolsPage("calendar"), "button") + button(state.calendar ?
        "切换到列表" : "切换到月历", "switch-calendar", {
          glyph: "agenda"
        }) + button("添加任务", "new-task", {
        glyph: "plus",
        kind: "button primary"
      }));
      out += state.calendar ? calendarView() : '<div class="toolbar task-filters"><div class="filters">' + [
        ["open", "未完成"],
        ["done", "已完成"],
        ["cancelled", "已取消"],
        ["all", "全部"]
      ].map(([key, title]) => button(title, "task-filter", {
        id: key,
        kind: "chip " + (state.taskFilter === key ? "active" : "")
      })).join("") + '</div>' + taskFilterSelect("task-kind", "任务类型", "全部类型", state.taskKind,
        [["general", "普通任务"], ["reading", "论文阅读"]]) +
        (tags.length ? taskFilterSelect("task-tag", "任务标签", "全部标签", chosenTag, tags.map(tag => [tag, tag])) : "") +
        '</div>' + panel((state.project ? "项目任务" : "全部任务") + " · " + t.length, t.length ? taskRows(t) : empty("当前列表没有任务",
        "可以创建带截止日期的任务。"));
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
    const dashboardRoot = $("dashboard-view");
    if (dashboardRoot) dashboard.mount(dashboardRoot, state, render, toast);
    $("main").setAttribute("aria-busy", "false");
  }

  function graphView() {
    const graphUI = window.SciResearchGraph;
    return graphUI.graphView({
      graph: state.graph,
      result: state.graphResult || state.graph,
      project: state.project,
      query: state.graphQuery || graphUI.defaultQuery,
      error: state.graphError,
      pending: state.graphPending
    }, {esc, button, heading, panel, empty, link, route: navigation.route});
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

  async function load(projectId, view, {
    historyMode = "replace"
  } = {}) {
    const token = ++navEpoch;
    const targetView = Object.hasOwn(names, view) ? view : "overview";
    state.loadError = "";
    $("main").setAttribute("aria-busy", "true");
    try {
      const [projects, papers, sessions, organization] = await Promise.all([
        request("projects"), request("papers"), request("/api/studio/sessions"), request("papers/organization")
      ]);
      if (token !== navEpoch) return;
      const allProjects = projects || [];
      const nextProject = allProjects.find(p => p.id === projectId) || null;
      if (projectId && !nextProject) throw new Error("这个项目已归档或不存在。请从项目列表重新选择。");
      const suffixes = ["notes", "tasks", "materials"];
      let graphError = "";
      const graph = {nodes: [], edges: []};
      const graphLoad = nextProject && targetView === "graph" ?
        request("projects/" + enc(nextProject.id) + "/graph").catch(err => {
          graphError = err.message;
          return graph;
        }) : graph;
      const [values,dashboardData] = await Promise.all([nextProject ?
        Promise.all([...suffixes.map(k => request("projects/" + enc(nextProject.id) + "/" + k)), graphLoad]) :
        Promise.all([[], ["overview", "tasks"].includes(targetView) ? request("tasks") : [], [], {nodes: [], edges: []}]),
        targetView === "overview" ? dashboard.load(request, nextProject?.id) : null
      ]);
      if (token !== navEpoch) return;
      // Publish the complete snapshot together. Until this point the visible
      // controls and their actions both belong to the previous project.
      state.view = targetView;
      state.projects = allProjects;
      state.papers = papers || [];
      state.organization = organization;
      if (state.libraryCollection !== "unfiled" && !Object.hasOwn(organization.collections, state.libraryCollection)) state.libraryCollection = "";
      state.project = nextProject;
      const rooms = Array.isArray(sessions) ? sessions : sessions.sessions || [];
      state.meetings = nextProject ? rooms.filter(m => m.project === nextProject.path) : rooms;
      [state.notes, state.tasks, state.materials, state.graph] = values;
      state.graphResult = null;
      state.graphQuery = null;
      state.graphError = graphError;
      state.graphPending = false;
      state.dashboardData = dashboardData;
      if (historyMode !== "none") history[historyMode + "State"](null, "", viewURL(state.view));
    } catch (err) {
      if (token !== navEpoch) return;
      state.loadError = err.message;
    }
    render();
  }

  function go(view) {
    if (!Object.hasOwn(names, view)) return;
    state.query = "";
    state.libraryCollection = "";
    state.libraryTag = "";
    E.library.clearSelection();
    load(state.project?.id, view, {historyMode: "push"});
    $("shell").classList.remove("mobile-open");
    window.scrollTo(0, 0);
  }

  function refresh() {
    return load(state.project?.id, state.view, {
      historyMode: "replace"
    });
  }

  function markdown(source, links = {}) {
    if (!window.marked || !window.DOMPurify) return '<pre>' + esc(source) + '</pre>';
    // Work only on text nodes for wikilinks; generated elements cannot inherit raw HTML from note titles.
    const template = document.createElement("template");
    template.innerHTML = DOMPurify.sanitize(marked.parse(source || ""), {
      SANITIZE_NAMED_PROPS: true,
      FORBID_TAGS: ["style", "iframe", "object", "form", "input", "textarea", "button", "svg", "math", "video", "audio",
        "source"
      ],
      FORBID_ATTR: ["style", "srcset", "action", "formaction", "data-id", "data-action", "data-project", "data-view"]
    });
    for (const img of template.content.querySelectorAll("img")) {
      const raw = img.getAttribute("src") || "";
      let filename = raw;
      try {
        filename = decodeURIComponent(raw);
      } catch {}
      const m = state.materials.find(m => m.name === filename && /^image\/(jpeg|png|gif|webp)$/i.test(m.mediaType || ""));
      if (m && state.project) {
        img.src = "/api/research/" + projectPath("materials/" + enc(m.id) + "/content");
        img.loading = "lazy";
      } else {
        img.replaceWith(document.createTextNode(img.alt || "未找到项目图片"));
      }
    }
    for (const a of template.content.querySelectorAll("a")) {
      const raw = a.getAttribute("href") || "";
      if (!/^https?:\/\//i.test(raw)) {
        a.removeAttribute("href");
      } else {
        a.target = "_blank";
        a.rel = "noopener noreferrer";
      }
    }
    const walker = document.createTreeWalker(template.content, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const node of nodes) {
      if (node.parentElement?.closest("code,pre,a")) continue;
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
    const host = document.createElement("div");
    host.append(template.content);
    return host.innerHTML;
  }

  function math(el) {
    if (window.renderMathInElement) window.renderMathInElement(el, {
      delimiters: [{
        left: "$$",
        right: "$$",
        display: true
      }, {
        left: "\\[",
        right: "\\]",
        display: true
      }, {
        left: "\\(",
        right: "\\)",
        display: false
      }, {
        left: "$",
        right: "$",
        display: false
      }],
      throwOnError: false,
      trust: false
    });
  }

  function search() {
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
    state,
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
    toolsPage,
    markdown,
    math,
    bytes,
    search,
    start: route
  };
  window.SciResearch = E;
  document.addEventListener("click", async ev => {
    const target = ev.target.closest?.("button,a");
    if (!target || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
    if (target.hasAttribute("data-project")) {
      ev.preventDefault();
      if (!close()) return;
      $("shell").classList.remove("mobile-open");
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
    try {
      if (action === "task-filter") {
        state.taskFilter = id;
        render();
      } else if (action === "switch-calendar") {
        state.calendar = !state.calendar;
        history.replaceState(null, "", viewURL("tasks"));
        render();
      } else if (action.startsWith("month-")) {
        state.month = new Date(state.month.getFullYear(), state.month.getMonth() + (action === "month-prev" ? -1 : 1),
          1);
        render();
      } else if (action === "reload") await route();
      else if (action === "graph-rebuild") {
        const query = state.graphQuery;
        const project = state.project?.id;
        await refresh();
        if (query && !state.graphError && state.project?.id === project && state.view === "graph") {
          const ids = new Set(state.graph.nodes.map(node => node.id));
          if ((!query.focus || ids.has(query.focus)) && (!query.target || ids.has(query.target))) await applyGraphQuery(query);
        }
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
        if (n.kind === "reference") dialog("外部引文", empty(n.label, "此标识符尚未关联到库内论文。", button("导入文献", "new-paper")));
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
      toast(err.message);
    }
  });
  document.addEventListener("change", ev => {
    if (ev.target.id === "task-kind") {
      state.taskKind = ev.target.value;
      render();
      $("task-kind").focus();
    } else if (ev.target.id === "task-tag") {
      state.taskTag = ev.target.value;
      render();
      $("task-tag").focus();
    }
  });
  document.addEventListener("submit", ev => {
    if (ev.target.id !== "graph-query") return;
    ev.preventDefault();
    const data = new FormData(ev.target);
    void applyGraphQuery(Object.fromEntries(data));
  });
  document.addEventListener("input", ev => {
    if (ev.target.id === "paper-query" && !ev.isComposing) {
      state.query = ev.target.value;
      render();
      const next = $("paper-query");
      next.focus();
      next.setSelectionRange(next.value.length, next.value.length);
    }
  });
  $("search-open").onclick = search;
  $("new-project").onclick = () => E.formAction("new-project");
  $("modal-close").onclick = close;
  $("nav-toggle").onclick = () => $("shell").classList.toggle(matchMedia("(max-width:760px)").matches ? "mobile-open" :
    "collapsed");
  document.addEventListener("keydown", ev => {
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
    state.calendar = u.searchParams.get("calendar") === "1";
    await load(project, view, {historyMode: "none"});
    if (task && view === "tasks" && !state.loadError && location.href === u.href &&
        (state.project?.id || null) === project && state.tasks.some(t => t.id === task)) {
      await E.formAction?.("edit-task", task);
    }
    const note = u.searchParams.get("note");
    if (note && state.view === "notes" && state.project?.id === project) {
      try { await E.openWikiNote(note); } catch (error) { toast(error.message); }
    }
  }
  window.addEventListener("popstate", () => {
    if (!close()) {
      history.pushState(null, "", viewURL(state.view));
      return;
    }
    route();
  });
  window.addEventListener("pageshow", ev => {
    if (ev.persisted) route();
  });
  for (const el of document.querySelectorAll("[data-icon]")) el.innerHTML = icon(el.dataset.icon);
})();
