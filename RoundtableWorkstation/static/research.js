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
  const names = {
    overview: "项目概览",
    papers: "共享文献",
    notes: "知识笔记",
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
    done: "已完成"
  };
  const colors = ["#8170c1", "#4c9188", "#cb835c", "#708abe", "#a1698e"];
  const state = {
    projects: [],
    project: null,
    papers: [],
    notes: [],
    tasks: [],
    materials: [],
    meetings: [],
    graph: {
      nodes: [],
      edges: []
    },
    view: "overview",
    graphFocus: "",
    scope: "project",
    query: "",
    taskFilter: "open",
    calendar: false,
    month: new Date(),
    loading: false,
    loadError: ""
  };
  let navEpoch = 0,
    toastTimer, modalCleanup = null;
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
      throw new Error(msg || "操作失败（" + res.status + "）");
    }
    if (res.status === 204) return null;
    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }

  function projectPath(suffix = "") {
    return "projects/" + enc(state.project.id) + (suffix ? "/" + suffix : "");
  }

  function studio(session = "") {
    const u = new URL("/studio", location.origin);
    if (state.project) u.searchParams.set("project", state.project.id);
    if (session) u.searchParams.set("session", session);
    return u.pathname + u.search;
  }

  function reader(id) {
    const u = new URL("/reader", location.origin);
    u.searchParams.set("paper", id);
    if (state.project) u.searchParams.set("project", state.project.id);
    return u.pathname + u.search;
  }

  function toolsPage(tab = "") {
    const u = new URL("/tools", location.origin);
    if (state.project) u.searchParams.set("project", state.project.id);
    if (tab) u.searchParams.set("tab", tab);
    return u.pathname + u.search;
  }

  function viewURL(view, id = state.project?.id) {
    const u = new URL("/research", location.origin);
    if (view !== "overview") u.searchParams.set("view", view);
    if (id) u.searchParams.set("project", id);
    return u.pathname + u.search;
  }

  function readLocal(key) {
    try {
      return localStorage.getItem(key)
    } catch {
      return null
    }
  }

  function saveLocal(key, val) {
    try {
      localStorage.setItem(key, val)
    } catch {}
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
    cleanup = null
  } = {}) {
    if (modalCleanup) modalCleanup();
    modalCleanup = cleanup;
    $("dialog-title").textContent = title;
    $("dialog-content").innerHTML = html;
    $("modal").classList.toggle("wide", wide);
    if (!$("modal").open) $("modal").showModal();
  }

  function close() {
    if ($("modal").open) $("modal").close();
  }
  $("modal").addEventListener("close", () => {
    if (modalCleanup) modalCleanup();
    modalCleanup = null;
    $("dialog-content").replaceChildren();
  });

  function button(label, action, options = {}) {
    const {
      id = "", kind = "button", glyph = ""
    } = options;
    return '<button type="button" class="' + kind + '" data-action="' + action + '" data-id="' + esc(id) + '">' + (glyph ?
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

  function paperRows(papers) {
    return list(papers.map(p => row("book", p.title, [p.authors?.slice(0, 3).join("、"), p.year || "", p.citekey].filter(
      Boolean).join(" · "), 'a href="' + esc(reader(p.id)) + '"', statusLabel[p.status] || "未读", button("编辑",
      "edit-paper", {
        id: p.id,
        kind: "bare"
      }))));
  }

  function taskRows(tasks) {
    return list(tasks.map(t => '<div class="row ' + (t.status === "done" ? "completed" : "") +
      '"><button type="button" class="task-check ' + (t.status === "done" ? "done" : "") + '" aria-label="' + esc((t
        .status === "done" ? "重新打开" : "完成") + "：" + t.title) + '" data-action="toggle-task" data-id="' + esc(t.id) +
      '">' + (t.status === "done" ? "✓" : "") + '</button><button class="row-main" data-action="edit-task" data-id="' +
      esc(t.id) + '"><span class="title">' + esc(t.title) + '</span><span class="meta">' + esc([t.dueDate, t
        .description].filter(Boolean).join(" · ").slice(0, 120)) + '</span></button><span class="tag">' + esc(
        statusLabel[t.status] || "待办") + '</span></div>'));
  }
  const byRecent = (a, b) => String(b.updatedAt || b.updated_at || b.createdAt || "").localeCompare(String(a.updatedAt || a
    .updated_at || a.createdAt || ""));

  function updateNav() {
    $("mainnav").innerHTML = Object.entries(names).map(([id, name]) => '<a class="navitem ' + (state.view === id ?
      "active" : "") + '" ' + (state.view === id ? 'aria-current="page"' : '') + ' data-view="' + id + '" href="' + esc(
      viewURL(id)) + '">' + icon(glyphs[id]) + esc(name) + '</a>').join("") + link("科研工具", toolsPage(), "navitem",
      "tools") + link("AI 实验室", "/lab" + (state.project ? "?project=" + enc(state.project.id) : ""), "navitem", "model");
    $("projectnav").innerHTML = state.projects.map((p, i) => '<a class="project-item ' + (p.id === state.project?.id ?
        'active' : '') + '" data-project="' + esc(p.id) + '" href="' + esc(viewURL("overview", p.id)) +
      '"><span class="project-dot" style="--project-color:' + colors[i % colors.length] + '"></span><span>' + esc(p
      .name) + '</span></a>').join("");
    $("crumb").innerHTML = '<span>科研工作台</span><span>/</span><strong>' + esc(names[state.view]) + '</strong>';
    document.title = names[state.view] + " · Sci-Station";
  }

  function overview() {
    const p = state.project,
      papers = scopedPapers().slice().sort(byRecent),
      tasks = state.tasks.filter(t => t.status !== "done").sort((a, b) => (a.dueDate || "9999").localeCompare(b.dueDate ||
        "9999"));
    let out = heading(p ? p.name : "科研工作台", p?.description || new Intl.DateTimeFormat("zh-CN", {
      year: "numeric",
      month: "long",
      day: "numeric",
      weekday: "long"
    }).format(new Date()), p ? button("项目设置", "edit-project", {
      kind: "button",
      glyph: "sliders"
    }) + link("进入圆桌", studio(), "button primary", "chat") : button("新建项目", "new-project", {
      glyph: "plus",
      kind: "button primary"
    }));
    if (!p) out += '<section class="overview-intro"><div><h2>创建你的第一个科研项目</h2><p>在项目中整理文献、记录想法、安排任务，并与圆桌讨论。</p></div>' +
      button("创建项目", "new-project", {
        glyph: "folderPlus"
      }) + '</section>';
    const metrics = [
      ["papers", "文献", papers.length],
      ["notes", "知识笔记", state.notes.length],
      ["tasks", "未完成任务", tasks.length],
      ["meetings", "项目圆桌", state.meetings.length]
    ];
    out += '<div class="metrics">' + metrics.map(([v, l, n]) => '<a class="metric" data-view="' + v + '" href="' + esc(
      viewURL(v)) + '"><span>' + l + '</span>' + icon(glyphs[v]) + '<strong>' + n + '</strong></a>').join("") + '</div>';
    out += '<div class="columns"><div>' + panel("最近文献", papers.length ? paperRows(papers.slice(0, 5)) : empty("还没有文献",
        "可以导入 PDF，或用 DOI、arXiv 编号添加。", button("导入文献", "new-paper", {
          glyph: "import"
        })), navLink("papers", "查看文献库")) +
      panel("近期圆桌", state.meetings.length ? meetingRows(state.meetings.slice(0, 3)) : empty("还没有项目会议",
        "从圆桌中选择模型、设置议题并开始讨论。", link("打开圆桌", studio(), "bare", "arrowUpRight")), navLink("meetings", "全部会议")) +
      '</div><div>' + panel("待办任务", tasks.length ? taskRows(tasks.slice(0, 5)) : empty("暂无待办任务", "给下一次阅读、计算或复核安排时间。",
        button("添加任务", "new-task", {
          glyph: "plus"
        })), navLink("tasks", "查看日历")) +
      panel("最近笔记", state.notes.length ? noteRows(state.notes.slice().sort(byRecent).slice(0, 3)) : empty("暂无笔记",
        "记录项目想法，或从论文选段建立笔记。", button("写笔记", "new-note", {
          glyph: "plus"
        })), navLink("notes", "全部笔记")) + '</div></div>';
    return out;
  }

  function meetingRows(items) {
    return list(items.map(m => row("chat", m.title || m.topic || "未命名圆桌", fmtDate(m.updated_at || m.created_at),
      'a href="' + esc(studio(m.id)) + '"', m.status === "closed" ? "已结束" : "会议")));
  }

  function noteRows(notes) {
    return list(notes.map(n => row("file", n.title, [n.tags?.join(" · "), fmtDate(n.updatedAt)].filter(Boolean).join(" · "),
      rowAction("read-note", n.id))));
  }

  function publicLibrary() {
    const limited = state.scope === "project" && state.project;
    const all = (limited ? scopedPapers() : state.papers).slice().sort(byRecent);
    const query = state.query.trim().toLowerCase();
    const papers = all.filter(p => [p.title, ...(p.authors || []), p.year, p.doi, p.arxiv, p.citekey, ...(p.tags || [])]
      .join(" ").toLowerCase().includes(query));
    const actions = link("导出 BibTeX", "/api/research/papers/bibtex" + (limited ? "?project=" + enc(state.project.id) : ""),
      "button") + button("导入文献", "new-paper", {
      glyph: "import",
      kind: "button primary"
    });
    return heading("文献库", "论文原文、阅读笔记和引用信息", actions) + '<div class="toolbar"><div class="filters">' + (state.project ?
        button("当前项目", "scope-project", {
          kind: "chip " + (limited ? "active" : "")
        }) : "") + button("全部文献", "scope-all", {
        kind: "chip " + (!limited ? "active" : "")
      }) + '</div><input type="search" class="query" id="paper-query" value="' + esc(state.query) +
      '" placeholder="搜索标题、作者、DOI…" aria-label="筛选文献"></div>' + panel(limited ? state.project.name + " · " + papers.length +
        " 篇" : "全部文献 · " + papers.length + " 篇", papers.length ? paperRows(papers) : empty(query ? "没有匹配的文献" : "还没有收录文献",
          query ? "可以尝试作者、标签或 DOI。" : "添加本地 PDF 或线上文献记录。", query ? "" : button("导入文献", "new-paper", {
            glyph: "import"
          })));
  }

  function projectNeeded() {
    return heading(names[state.view]) + panel("科研项目", empty("先创建一个科研项目", "笔记、任务、材料和圆桌可按项目整理。", button("新建项目",
    "new-project", {
      kind: "button primary",
      glyph: "plus"
    })));
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
      cells.push('<div class="day ' + (today === date ? "today" : "") + '"><b>' + i + '</b>' + state.tasks.filter(t => t
        .dueDate === date).map(t => button(t.title, "edit-task", {
        id: t.id,
        kind: "day-task"
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
      $("main").innerHTML = heading("读取工作区时遇到问题") + panel("本机服务", empty(state.loadError, "", button("重试", "reload")));
      return;
    }
    if (state.view === "overview") out = overview();
    else if (state.view === "papers") out = publicLibrary();
    else if (state.view === "meetings") out = heading("工作圆桌", state.project?.name || "模型讨论与研究报告", link("进入圆桌", studio(),
      "button primary", "chat")) + panel("项目会议", state.meetings.length ? meetingRows(state.meetings) : empty("暂无项目会议",
      "进入圆桌后可以创建讨论。"));
    else if (!state.project) out = projectNeeded();
    else if (state.view === "notes") out = heading("知识笔记", state.project.name, button("写笔记", "new-note", {
      glyph: "plus",
      kind: "button primary"
    })) + panel("项目笔记 · " + state.notes.length, state.notes.length ? noteRows(state.notes.slice().sort(byRecent)) : empty(
      "暂无项目笔记", "使用 Markdown、公式和 [[双链]] 记录研究过程。"));
    else if (state.view === "tasks") {
      const t = state.tasks.filter(t => state.taskFilter === "all" || (state.taskFilter === "done" ? t.status === "done" : t
        .status !== "done")).sort((a, b) => (a.dueDate || "9999").localeCompare(b.dueDate || "9999") || byRecent(a, b));
      out = heading("任务与日历", state.project.name, link("系统日历", toolsPage("calendar"), "button") + button(state.calendar ?
        "切换到列表" : "切换到月历", "switch-calendar", {
          glyph: "agenda"
        }) + button("添加任务", "new-task", {
        glyph: "plus",
        kind: "button primary"
      }));
      out += state.calendar ? calendarView() : '<div class="toolbar"><div class="filters">' + [
        ["open", "未完成"],
        ["done", "已完成"],
        ["all", "全部"]
      ].map(([key, title]) => button(title, "task-filter", {
        id: key,
        kind: "chip " + (state.taskFilter === key ? "active" : "")
      })).join("") + '</div></div>' + panel("项目任务 · " + t.length, t.length ? taskRows(t) : empty("当前列表没有任务",
        "可以创建带截止日期的项目任务。"));
    } else if (state.view === "materials") {
      out = heading("研究材料", state.project.name, button("打开项目目录", "project-files", {
        glyph: "folder"
      }) + button("添加文件", "new-material", {
        glyph: "import",
        kind: "button primary"
      })) + panel("项目文件 · " + state.materials.length, state.materials.length ? list(state.materials.slice().sort(byRecent)
          .map(m => row("file", m.name, bytes(m.size) + " · " + fmtDate(m.updatedAt), rowAction("read-material", m.id)))
          ) : empty("暂无材料", "在这里保存与项目相关的图表、数据、代码或补充文件。"));
    } else if (state.view === "graph") out = graphView();
    $("main").innerHTML = out;
    $("main").setAttribute("aria-busy", "false");
  }

  function shortLabel(s, n) {
    const a = Array.from(s);
    return a.length > n ? a.slice(0, n).join("") + "…" : s;
  }

  function graphView() {
    const {
      nodes = [], edges = []
    } = state.graph, keys = new Map(nodes.map(n => [n.id, n])), kindTitle = {
      note: "笔记",
      paper: "论文",
      task: "任务",
      reference: "外部引文"
    };
    const graphBtn = id => {
      const n = keys.get(id);
      return n ? button(n.label, "graph-open", {
        id: n.id,
        kind: "bare"
      }) : esc(id)
    };
    let out = heading("知识关联", state.project.name, button("新增关系", "new-relation", {
      glyph: "plus",
      kind: "button primary"
    }));
    if (edges.length) {
      const anchor = nodes.find(n => n.id === state.graphFocus) || keys.get(edges[0].source);
      const connected = [...new Set(edges.filter(e => e.source === anchor.id || e.target === anchor.id).map(e => e
        .source === anchor.id ? e.target : e.source))].slice(0, 10);
      const height = Math.max(160, connected.length * 43 + 30),
        svg = '<svg class="network" viewBox="0 0 680 ' + height + '" role="img" aria-label="当前条目与相邻条目的关联">' + connected.map(
          (id, i) => {
            const y = 30 + i * 43;
            return '<path d="M218 ' + height / 2 + ' C312 ' + height / 2 + ' 313 ' + y + ' 388 ' + y + '"/>'
          }).join("") + '<g><rect x="20" y="' + (height / 2 - 17) + '" width="198" height="34" rx="8"/><text x="32" y="' + (
          height / 2 + 5) + '">' + esc(shortLabel(anchor.label, 14)) + '</text></g>' + connected.map((id, i) => {
          const y = 30 + i * 43,
            n = keys.get(id);
          return '<g><rect x="388" y="' + (y - 15) + '" width="260" height="30" rx="7"/><text x="400" y="' + (y + 5) +
            '">' + esc(shortLabel(n?.label || id, 20)) + '</text></g>'
        }).join("") + '</svg>';
      out += panel("关系图", '<div class="graph-picker"><label>查看条目 <select id="graph-focus">' + nodes.map(n =>
        '<option value="' + esc(n.id) + '" ' + (n.id === anchor.id ? 'selected' : '') + '>' + esc(n.label) + '</option>'
        ).join("") + '</select></label></div>' + svg);
    }
    out += panel("引用关系 · " + edges.length, edges.length ? edges.map(e => '<div class="relation">' + graphBtn(e.source) +
      '<span class="tag">' + esc(({
        wikilink: "双链",
        reference: "引用",
        cites: "引用",
        reading: "阅读",
        supports: "支持",
        contradicts: "矛盾",
        extends: "扩展",
        related: "相关",
        evidence: "证据",
        paper: "关联论文",
        source: "来源"
      })[e.kind] || e.kind) + '</span>' + graphBtn(e.target) + (e.id ? button("移除", "remove-relation", {
        id: e.id,
        kind: "bare danger"
      }) : "") + '</div>').join("") : empty("尚无关联", "在笔记中使用 [[笔记标题]]，或关联一篇论文。"));
    out += panel("项目条目 · " + nodes.length, nodes.length ? list(nodes.map(n => row(({
        paper: "book",
        note: "file",
        task: "agenda"
      })[n.kind] || "file", n.label, "", rowAction("graph-open", n.id), kindTitle[n.kind] || n.kind))) : empty(
      "暂无可关联的条目"));
    return out;
  }
  async function load(projectId, view, {
    historyMode = "replace"
  } = {}) {
    const token = ++navEpoch;
    state.view = Object.hasOwn(names, view) ? view : "overview";
    state.loadError = "";
    $("main").setAttribute("aria-busy", "true");
    try {
      const [projects, papers, sessions] = await Promise.all([request("projects"), request("papers"), request(
        "/api/studio/sessions")]);
      if (token !== navEpoch) return;
      const allProjects = projects || [];
      const nextProject = allProjects.find(p => p.id === projectId) ||
        allProjects.find(p => p.id === readLocal("scistation.project")) || allProjects[0] || null;
      const suffixes = ["notes", "tasks", "materials", "graph"];
      const values = nextProject ?
        await Promise.all(suffixes.map(k => request("projects/" + enc(nextProject.id) + "/" + k))) :
        [[], [], [], {nodes: [], edges: []}];
      if (token !== navEpoch) return;
      // Publish the complete snapshot together. Until this point the visible
      // controls and their actions both belong to the previous project.
      state.projects = allProjects;
      state.papers = papers || [];
      state.project = nextProject;
      state.meetings = (sessions.sessions || []).filter(m => m.project === nextProject?.path);
      [state.notes, state.tasks, state.materials, state.graph] = values;
      if (nextProject) saveLocal("scistation.project", nextProject.id);
      if (historyMode !== "none") history[historyMode + "State"](null, "", viewURL(state.view));
    } catch (err) {
      if (token !== navEpoch) return;
      state.loadError = err.message;
    }
    render();
  }

  function go(view) {
    if (!Object.hasOwn(names, view)) return;
    state.view = view;
    state.query = "";
    history.pushState(null, "", viewURL(view));
    $("shell").classList.remove("mobile-open");
    render();
    window.scrollTo(0, 0);
  }

  function refresh() {
    return load(state.project?.id, state.view, {
      historyMode: "replace"
    });
  }

  function markdown(source) {
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
        re = /\[\[([^\]\n]{1,160})\]\]/g;
      let match, pos = 0;
      const frag = document.createDocumentFragment();
      while ((match = re.exec(str))) {
        frag.append(str.slice(pos, match.index));
        const ref = state.notes.find(n => n.title === match[1]);
        if (ref) {
          const a = document.createElement("button");
          a.className = "bare";
          a.dataset.action = "read-note";
          a.dataset.id = ref.id;
          a.textContent = match[1];
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
    statusLabel,
    toolsPage,
    markdown,
    math,
    bytes,
    search
  };
  window.SciResearch = E;
  document.addEventListener("click", async ev => {
    const target = ev.target.closest?.("button,a");
    if (!target || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
    if (target.hasAttribute("data-project")) {
      ev.preventDefault();
      close();
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
      if (action === "scope-project" || action === "scope-all") {
        state.scope = action === "scope-all" ? "all" : "project";
        render();
      } else if (action === "task-filter") {
        state.taskFilter = id;
        render();
      } else if (action === "switch-calendar") {
        state.calendar = !state.calendar;
        render();
      } else if (action.startsWith("month-")) {
        state.month = new Date(state.month.getFullYear(), state.month.getMonth() + (action === "month-prev" ? -1 : 1),
          1);
        render();
      } else if (action === "reload") await refresh();
      else if (action === "graph-open") {
        const n = (state.graph.nodes || []).find(n => n.id === id);
        if (!n) return;
        const raw = n.id.replace(/^(?:note|paper|task)[:/]/, "");
        if (n.kind === "reference") dialog("外部引文", empty(n.label, "此标识符尚未关联到库内论文。", button("导入文献", "new-paper")));
        else if (n.kind === "paper") location.href = reader(raw);
        else await E.formAction(n.kind === "task" ? "edit-task" : "read-note", raw);
      } else if (action === "toggle-task") {
        const t = state.tasks.find(t => t.id === id);
        if (!t) return;
        target.disabled = true;
        await request(projectPath("tasks/" + enc(id)), {
          method: "PATCH",
          body: {
            revision: t.revision,
            status: t.status === "done" ? "open" : "done"
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
    if (ev.target.id === "graph-focus") {
      state.graphFocus = ev.target.value;
      render();
    }
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

  function route() {
    const u = new URL(location.href);
    return load(u.searchParams.get("project"), u.searchParams.get("view") || "overview", {
      historyMode: "none"
    });
  }
  window.addEventListener("popstate", () => {
    close();
    route();
  });
  window.addEventListener("pageshow", ev => {
    if (ev.persisted) route();
  });
  for (const el of document.querySelectorAll("[data-icon]")) el.innerHTML = icon(el.dataset.icon);
  route();
})();
