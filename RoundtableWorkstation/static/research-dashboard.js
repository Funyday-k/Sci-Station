"use strict";
(() => {
  const sizes = {small: "小", wide: "宽", tall: "高", medium: "中", large: "大"};
  const homeWidgets = [
    ["today", "今日任务", "medium", "tasks"],
    ["active_projects", "活跃项目", "medium", "projects"],
    ["ai_review", "待审核草稿", "medium", "ai-lab"],
    ["calendar", "日历", "large", "calendar"],
    ["recent_papers", "最近文献", "medium", "paper-library"],
    ["reading_plan", "阅读计划", "medium", "paper-library"],
    ["project_health", "项目动态", "small", "projects"],
    ["quick_actions", "快速操作", "medium"],
    ["meetings", "最近圆桌", "medium", "ai-lab"]
  ];
  const projectWidgets = [
    ["project_status", "项目状态", "small"],
    ["research_questions", "研究问题", "small", "wiki"],
    ["project_brief", "项目简报", "medium", "wiki"],
    ["core_papers", "核心论文", "medium", "paper-library"],
    ["current_tasks", "当前任务", "medium", "tasks"],
    ["materials", "研究材料", "small", "materials"],
    ["knowledge_gaps", "知识缺口", "small", "wiki"],
    ["recent_activity", "近期活动", "medium"],
    ["project_documents", "项目文档", "medium", "wiki"],
    ["workflow", "工作流", "medium", "ai-lab"]
  ];

  const layouts = new Map();
  const timestamp = item => item.last_read_at || item.updatedAt || item.updated_at || item.createdAt || item.created_at || "";
  const instant = value => Date.parse(value) || 0;
  const recent = (a, b) => instant(timestamp(b)) - instant(timestamp(a));
  const calendarKey = day => [day.getFullYear(), day.getMonth() + 1, day.getDate()]
    .map(part => String(part).padStart(2, "0")).join("-");
  const open = task => task.status !== "done" && task.status !== "cancelled";
  const priority = {urgent: 4, high: 3, medium: 2, low: 1};
  const byDue = (a, b) => (a.dueDate || "9999").localeCompare(b.dueDate || "9999") ||
    (a.dueTime || "").localeCompare(b.dueTime || "") ||
    (priority[b.priority] || 0) - (priority[a.priority] || 0) || a.title.localeCompare(b.title);
  const taskProjects = task => task.projectIds?.length ? task.projectIds : [task.projectId];
  const tag = (note, value) => note.tags?.some(t => t.trim().toLowerCase() === value);
  const noteIsGap = note => /(^|\/)gaps?(\/|$)/i.test(note.namespace || "") || tag(note, "gap") || tag(note, "research_gap");

  function dayAt(now, offset) {
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset);
  }

  function monthAt(day, offset) {
    return new Date(day.getFullYear(), day.getMonth() + offset, 1);
  }

  function localDay(key) {
    const [year, month, day] = key.split("-").map(Number);
    return new Date(year, month - 1, day);
  }

  function calendarMonth(day) {
    const month = monthAt(day, 0);
    const start = dayAt(month, -(month.getDay() + 6) % 7);
    return Array.from({length: 42}, (_, i) => dayAt(start, i));
  }

  function taskWindows(tasks, now) {
    const today = calendarKey(now);
    const horizon = calendarKey(dayAt(now, 14));
    const activeTasks = tasks.filter(open).sort(byDue);
    return {
      today: activeTasks.filter(t => t.dueDate && t.dueDate <= today),
      upcoming: activeTasks.filter(t => t.dueDate > today && t.dueDate < horizon),
      next: activeTasks.find(t => t.dueDate >= today),
      activeTasks
    };
  }

  function tasksOn(tasks, day) {
    return tasks.filter(t => {
      const start = t.startDate || t.dueDate;
      const end = t.dueDate || start;
      return start && start <= day && end >= day;
    }).sort(byDue);
  }

  function stage({papers, notes, gaps, kinds, activity}, now) {
    if (activity && +now - activity > 21 * 86400000) return ["on_hold", "搁置", "最近 21 天无活动"];
    if (kinds.has("reviewer_response")) return ["reviewing", "审阅", "已登记审稿回复"];
    if (kinds.has("writing_revision") || kinds.has("related_work")) return ["drafting", "撰写", "已登记写作修订或相关工作"];
    if (papers >= 5 && gaps > 0 && kinds.has("research_plan")) return ["planning", "规划", "已有研究计划、论文和待研究缺口"];
    if (papers < 5 && notes < 3 && !kinds.size) return ["exploration", "探索", "论文少于五篇，且项目笔记少于三篇"];
    return ["planning", "规划", "已积累项目资料"];
  }

  function grouped(items, keys) {
    const index = new Map();
    for (const item of items) {
      for (const id of keys(item)) {
        if (!id) continue;
        if (!index.has(id)) index.set(id, []);
        index.get(id).push(item);
      }
    }
    return index;
  }

  function projectSummaries(projects, papers, tasks, reviews, facts, now) {
    const paperIndex = grouped(papers, p => p.project_ids || []);
    const taskIndex = grouped(tasks, taskProjects);
    const reviewIndex = grouped(reviews || [], r => [r.projectId]);
    return projects.map(project => {
      const linked = paperIndex.get(project.id) || [];
      const deadlines = taskIndex.get(project.id) || [];
      const drafts = reviewIndex.get(project.id) || [];
      const core = linked.filter(p => p.core_project_ids?.includes(project.id));
      const info = facts?.[project.id];
      const kinds = new Set(info?.artifactKinds || []);
      let activity = instant(timestamp(project));
      for (const item of [...linked, ...deadlines, ...drafts]) activity = Math.max(activity, instant(timestamp(item)));
      const windows = taskWindows(deadlines, now);
      const readingCount = linked.filter(p => +now - instant(timestamp(p)) <= 14 * 86400000).length;
      return {project, linked, core, ...windows, readingCount, facts: info, drafts, activity, stage: info ? stage({
        papers: linked.length, notes: info.noteCount, gaps: info.gapCount, kinds, activity
      }, now) : null};
    }).sort((a, b) => (a.next?.dueDate || "9999").localeCompare(b.next?.dueDate || "9999") ||
      a.project.name.localeCompare(b.project.name, "zh-CN", {numeric: true}));
  }

  function researchQuestions(markdown) {
    let reading = false;
    const questions = [];
    for (const line of (markdown || "").split(/\r?\n/)) {
      const heading = line.match(/^\s*#{1,6}\s+(.+)/);
      if (heading) reading = /research questions?|研究问题/i.test(heading[1]);
      else if (reading && line.trim()) questions.push(line.trim().replace(/^(?:[-+*]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)/, ""));
    }
    return questions;
  }

  function normalizeLayout(descriptors, stored) {
    const byId = new Map(descriptors.map(d => [d[0], d]));
    const items = [];
    for (const item of Array.isArray(stored) ? stored : []) {
      const descriptor = byId.get(item?.id);
      if (!descriptor) continue;
      items.push({id: item.id, size: Object.hasOwn(sizes, item.size) ? item.size : descriptor[2], visible: item.visible !== false});
      byId.delete(item.id);
    }
    for (const [id, , size] of byId.values()) items.push({id, size, visible: true});
    return items;
  }

  function move(items, source, destination) {
    const from = items.findIndex(item => item.id === source);
    const to = items.findIndex(item => item.id === destination);
    if (from < 0 || to < 0 || from === to) return false;
    items.splice(to, 0, items.splice(from, 1)[0]);
    return true;
  }

  function enabled(modules, id) {
    if (!id || !modules) return true;
    return window.SciStationModules?.isEnabled(modules, id) ??
      (modules.modules || []).find(item => item.id === id)?.effective !== false;
  }

  const scopeKey = (rootID, projectID) => JSON.stringify([rootID || "", projectID || ""]);

  function preference(state, descriptors) {
    const projectID = state.project?.id;
    const rootID = state.dashboardData?.workspace?.id;
    const key = scopeKey(rootID, projectID);
    if (!layouts.has(key)) {
      const storageKey = rootID ? "sci-station.dashboard.v1:" + key : null;
      let stored;
      if (storageKey) {
        try { stored = JSON.parse(localStorage.getItem(storageKey)); } catch {}
      }
      layouts.set(key, {key, storageKey, items: normalizeLayout(descriptors, stored), editing: false, selected: ""});
    }
    return layouts.get(key);
  }

  function save(board) {
    if (board.storageKey) {
      try { localStorage.setItem(board.storageKey, JSON.stringify(board.items)); } catch { return false; }
    }
    return true;
  }

  async function load(request, projectID) {
    const dataOrUnavailable = promise => promise.catch(() => null);
    const moduleService = window.SciStationModules;
    const [workspace, facts, reviews, modules] = await Promise.all([
      dataOrUnavailable(request("/api/workspace")), dataOrUnavailable(request("dashboard/projects")),
      dataOrUnavailable(request(projectID ? "projects/" + encodeURIComponent(projectID) + "/reviews" : "reviews")),
      moduleService ? dataOrUnavailable(moduleService.load(projectID)) : null
    ]);
    return {workspace, facts, reviews, modules};
  }

  function markup(state, ui, now = new Date()) {
    const {esc, heading, button, link, panel, paperRows, taskRows, meetingRows, viewURL, studio, fmtDate, row, rowAction, list} = ui;
    const project = state.project;
    const {workspace, facts, reviews, modules} = state.dashboardData || {};
    const descriptors = project ? projectWidgets : homeWidgets;
    const board = preference(state, descriptors);
    const isEnabled = id => enabled(modules, id);
    const today = calendarKey(now);
    const dateHeading = new Intl.DateTimeFormat("zh-CN", {dateStyle: "full"}).format(now);
    const dateStr = value => /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : fmtDate(value);
    const dashboardNav = (title, view, id = project?.id) => link(title, viewURL(view, id), "bare");
    const reviewURL = r => window.SciStationNav.route("/studio", {project: r.projectId, session: r.meetingId, review: r.id});
    const url = (path, params) => window.SciStationNav.route(path, params);
    const calendar = url("/research", {view: "tasks", project: project?.id, calendar: "1"});
    const overview = projectSummaries(project ? [project] : state.projects, state.papers, state.tasks, reviews, facts, now);
    const {today: due, upcoming} = taskWindows(state.tasks, now);
    const stageBadge = summary => summary.stage
      ? '<span class="dashboard-stage" data-stage="' + summary.stage[0] + '" title="' + esc(summary.stage[2]) + '">' + summary.stage[1] + '</span>'
      : '<span class="dashboard-muted">阶段暂不可用</span>';
    const message = text => '<p class="dashboard-muted">' + esc(text) + '</p>';
    const subhead = text => '<h3 class="dashboard-subhead">' + esc(text) + '</h3>';
    const metric = (value, label) => '<span class="dashboard-stat"><b>' + esc(value) + '</b> ' + esc(label) + '</span>';
    const groupedMetrics = (...metrics) => '<div class="dashboard-stats">' + metrics.filter(Boolean).join("") + '</div>';
    const callout = (items, render, fallback) => items.length ? render(items) : message(fallback);
    const dateLabel = item => [dateStr(item.dueDate || timestamp(item)), item.dueTime].filter(Boolean).join(" · ");
    const noteRows = items => list(items.map(n => row("file", n.title, fmtDate(n.updatedAt), rowAction("read-note", n.id))));
    const pending = (reviews || []).filter(r => r.status === "pending" && (!project || r.projectId === project.id)).sort(recent);
    const paperLimit = size => ({small: 1, wide: 2, tall: 3, medium: 4, large: 6})[size];
    const sections = project ? projectSections() : homeSections();
    const title = project ? project.name : (workspace?.name || "首页");
    const edit = '<button type="button" class="button" data-dashboard-control="edit" aria-expanded="' + board.editing + '"' +
      ' aria-controls="dashboard-layout">' + (board.editing ? "完成布局" : "自定义组件") + '</button>';
    const projectActions = project ? button("项目设置", "edit-project", {glyph: "sliders"}) +
      (isEnabled("ai-lab") ? link("进入圆桌", studio(), "button primary", "chat") : "") : "";
    const available = new Map(descriptors.filter(([, , , required]) => isEnabled(required)).map(d => [d[0], d]));
    const visible = board.items.filter(item => item.visible && available.has(item.id));
    const widget = item => {
      const [, title] = available.get(item.id);
      const handle = board.editing ? '<span aria-hidden="true" class="dashboard-drag" draggable="true" title="拖动排序">⠿</span>' : "";
      return '<article class="dashboard-widget dashboard-' + item.size + '" data-dashboard-widget="' + item.id + '">' +
        handle + panel(title, sections[item.id](paperLimit(item.size))) + '</article>';
    };
    const layoutOption = (item, index, availableItems) => {
      const [id, label] = available.get(item.id);
      const options = Object.entries(sizes).map(([size, label]) => '<option value="' + size + '"' +
        (item.size === size ? ' selected' : '') + '>' + label + '</option>').join("");
      return '<div class="dashboard-layout-row" data-dashboard-option="' + id + '"><label><input type="checkbox" data-dashboard-control="visible"' +
        (item.visible ? ' checked' : '') + '> ' + label + '</label><select aria-label="' + label + '尺寸" data-dashboard-control="size">' +
        options + '</select>' + direction("up", "上移", index === 0) + direction("down", "下移", index === availableItems.length - 1) + '</div>';
      function direction(direction, text, disabled) {
        return '<button type="button" class="bare" data-dashboard-control="' + direction + '" aria-label="' + text + label + '"' +
          (disabled ? ' disabled' : '') + '>' + text + '</button>';
      }
    };
    const gallery = board.editing ? '<section id="dashboard-layout" class="panel dashboard-layout" aria-label="自定义组件">' +
      '<div class="dashboard-layout-options">' + board.items.filter(i => available.has(i.id)).map(layoutOption).join("") + '</div>' +
      '<button type="button" class="button" data-dashboard-control="reset">恢复默认布局</button></section>' : '<div id="dashboard-layout" hidden></div>';
    return '<div id="dashboard-view">' + heading(title, project ? project.description : dateHeading, projectActions + edit) + gallery +
      (visible.length ? '<div class="dashboard-grid">' + visible.map(widget).join("") + '</div>' : ui.empty("没有显示的组件")) + '</div>';

    function homeSections() {
      const reading = state.papers.filter(p => p.status === "unread" || p.status === "reading")
        .sort((a, b) => b.priority - a.priority || Number(b.status === "reading") - Number(a.status === "reading") || recent(a, b));
      const projectRows = items => list(items.map(summary => row("folder", summary.project.name,
        [isEnabled("paper-library") && summary.core.length + " 篇核心文献", isEnabled("tasks") && summary.activeTasks.length + " 项待办",
          isEnabled("tasks") && summary.next && dateLabel(summary.next)].filter(Boolean).join(" · "),
        'a data-project="' + esc(summary.project.id) + '" href="' + esc(viewURL("overview", summary.project.id)) + '"',
        summary.stage?.[1] || "阶段暂不可用")));
      return {
        today: limit => groupedMetrics(metric(due.length, "今日到期或逾期"), metric(upcoming.length, "未来两周"),
          isEnabled("paper-library") && metric(reading.length, "篇待读"), isEnabled("ai-lab") && reviews && metric(pending.length, "项待审核")) +
          callout(due.slice(0, limit), taskRows, "今天没有到期任务") + (upcoming.length && limit > 1
            ? subhead("近期截止") + taskRows(upcoming.slice(0, Math.min(limit - 1, 3))) : "") + dashboardNav("查看任务", "tasks"),
        active_projects: limit => callout(overview.slice(0, limit), projectRows, "暂无活跃项目") + dashboardNav("全部项目", "projects"),
        ai_review: limit => reviews ? groupedMetrics(metric(pending.length, "项待审核")) + callout(pending.slice(0, limit), items =>
          list(items.map(r => row("file", r.title, [state.projects.find(p => p.id === r.projectId)?.name, fmtDate(r.createdAt)].filter(Boolean).join(" · "),
            'a href="' + esc(reviewURL(r)) + '"'))), "暂无待审核草稿") : message("暂时无法读取审核队列"),
        calendar: calendarWidget,
        recent_papers: limit => callout(state.papers.slice().sort(recent).slice(0, limit), paperRows, "暂无文献") + dashboardNav("文献库", "papers"),
        reading_plan: limit => groupedMetrics(metric(reading.length, "篇待读")) +
          callout(reading.slice(0, limit), paperRows, "暂无待读论文") + dashboardNav("文献库", "papers"),
        project_health: () => groupedMetrics(metric(overview.length, "个活跃项目"),
          isEnabled("tasks") && metric(due.filter(t => t.dueDate < today).length, "项逾期任务")) + dashboardNav("全部项目", "projects"),
        quick_actions: () => '<div class="actions">' + [isEnabled("projects") && button("新建项目", "new-project"),
          isEnabled("paper-library") && button("导入文献", "new-paper"), isEnabled("tasks") && button("添加任务", "new-task"),
          isEnabled("ai-lab") && link("AI 实验室", url("/lab"))].filter(Boolean).join("") + '</div>',
        meetings: limit => callout(state.meetings.slice().sort(recent).slice(0, limit), meetingRows, "暂无圆桌") + link("打开圆桌", studio(), "bare")
      };
    }

    function calendarWidget(limit) {
      const selected = board.selected || today;
      const selectedDate = localDay(selected);
      const display = monthAt(board.month || selectedDate, 0);
      const dateFormat = new Intl.DateTimeFormat("zh-CN", {dateStyle: "long"});
      const calendarTasks = isEnabled("tasks") ? state.tasks : [];
      const events = tasksOn(calendarTasks, selected);
      const controls = '<div class="dashboard-calendar-head"><b>' +
        new Intl.DateTimeFormat("zh-CN", {year: "numeric", month: "long"}).format(display) + '</b>' +
        '<div><button type="button" class="bare" data-dashboard-control="prev-month" aria-label="上一月">‹</button>' +
        '<button type="button" class="bare" data-dashboard-control="today">今天</button>' +
        '<button type="button" class="bare" data-dashboard-control="next-month" aria-label="下一月">›</button></div></div>';
      const weekdays = Array.from("一二三四五六日", label => '<span aria-hidden="true">' + label + '</span>').join("");
      const days = calendarMonth(display).map(date => {
        const key = calendarKey(date);
        if (date.getMonth() !== display.getMonth()) return '<span aria-hidden="true"></span>';
        const count = calendarTasks.filter(t => {
          const start = t.startDate || t.dueDate;
          return start && start <= key && (t.dueDate || start) >= key;
        }).length;
        const label = dateFormat.format(date) + (count ? "，" + count + " 项任务" : "");
        return '<button type="button" class="dashboard-day' + (count ? ' has-events' : '') + '" data-dashboard-control="pick-day" value="' + key +
          '" aria-label="' + esc(label) + '" aria-pressed="' + (key === selected) + '"' + (key === today ? ' aria-current="date"' : '') +
          '>' + date.getDate() + '</button>';
      }).join("");
      return controls + '<div class="dashboard-month">' + weekdays + days + '</div>' + subhead(dateFormat.format(selectedDate)) +
        callout(events.slice(0, limit), taskRows, "当天没有任务") + '<div class="dashboard-calendar-links">' + link("打开日历", calendar, "bare") +
        link("系统日历", ui.toolsPage("calendar"), "bare") + '</div>';
    }

    function projectSections() {
      const info = overview[0];
      const notes = state.notes.slice().sort(recent);
      const brief = notes.find(n => (n.namespace === "projects" && /^project[ _-]overview$/i.test(n.title)) || tag(n, "project_brief"));
      const gaps = notes.filter(noteIsGap);
      const materials = state.materials.slice().sort(recent);
      const core = info.core.slice().sort((a, b) => b.priority - a.priority || b.rating - a.rating || recent(a, b));
      const activity = [
        ...(isEnabled("paper-library") ? info.linked.map(p => ({date: timestamp(p), html: row("book", p.title, fmtDate(timestamp(p)),
          'a href="' + esc(ui.reader(p.id)) + '"')})) : []),
        ...(isEnabled("materials") ? materials.map(m => ({date: timestamp(m), html: row("file", m.name, fmtDate(m.updatedAt), rowAction("read-material", m.id))})) : []),
        ...(isEnabled("ai-lab") ? info.drafts.filter(r => r.status !== "rejected").map(r => ({date: timestamp(r), html: row("file", r.title,
          fmtDate(timestamp(r)), 'a href="' + esc(reviewURL(r)) + '"', r.status === "accepted" ? "已接受" : "待审核")})) : [])
      ].sort((a, b) => instant(b.date) - instant(a.date));
      return {
        project_status: () => stageBadge(info) + (info.stage ? message(info.stage[2]) : "") + groupedMetrics(
          isEnabled("paper-library") && metric(info.linked.length, "篇论文"), isEnabled("paper-library") && metric(core.length, "篇核心论文"),
          isEnabled("wiki") && metric(notes.length, "篇笔记"), isEnabled("tasks") && metric(info.activeTasks.length, "项待办"),
          isEnabled("ai-lab") && reviews && metric(pending.length, "项待审核")) + (isEnabled("tasks") && info.next
          ? subhead("下一项截止") + taskRows([info.next]) : ""),
        research_questions: limit => callout(researchQuestions(brief?.body).slice(0, limit), items => '<ul class="dashboard-questions">' +
          items.map(item => '<li>' + esc(item) + '</li>').join("") + '</ul>', "简报中暂无研究问题"),
        project_brief: limit => (brief ? '<p class="dashboard-brief">' + esc(brief.body.slice(0, limit * 180)) + '</p>' +
          button("编辑简报", "edit-note", {id: brief.id, kind: "bare"}) : message("暂无项目简报") + dashboardNav("打开 Wiki", "notes")),
        core_papers: limit => callout(core.slice(0, limit), items => paperRows(items, project.id), "暂无核心论文") + dashboardNav("项目论文", "papers"),
        current_tasks: limit => callout(info.activeTasks.slice(0, limit), taskRows, "暂无未完成任务") + dashboardNav("查看任务", "tasks"),
        materials: limit => callout(materials.slice(0, limit), items => list(items.map(m => row("file", m.name, fmtDate(m.updatedAt),
          rowAction("read-material", m.id)))), "暂无材料") + dashboardNav("全部材料", "materials"),
        knowledge_gaps: limit => callout(gaps.slice(0, limit), noteRows, "没有登记的研究缺口") + dashboardNav("打开 Wiki", "notes"),
        recent_activity: limit => callout(activity.slice(0, limit), items => list(items.map(a => a.html)), "暂无近期活动"),
        project_documents: limit => callout(notes.slice(0, limit), noteRows, "暂无项目文档") + dashboardNav("全部文档", "notes"),
        workflow: limit => callout(state.meetings.slice().sort(recent).slice(0, limit), meetingRows, "暂无项目圆桌") +
          link("AI 工作流", url("/lab", {project: project.id}), "bare") + dashboardNav("全部圆桌", "meetings")
      };
    }
  }

  function mount(root, state, render, toast) {
    const descriptors = state.project ? projectWidgets : homeWidgets;
    const board = preference(state, descriptors);
    const modules = state.dashboardData?.modules;
    const available = new Set(descriptors.filter(d => enabled(modules, d[3])).map(d => d[0]));
    const selector = "[data-dashboard-control]";
    let dragged = "";
    function update(control) {
      const action = control.dataset.dashboardControl;
      const id = control.closest("[data-dashboard-option]")?.dataset.dashboardOption;
      const dateControl = ["today", "pick-day", "prev-month", "next-month"].includes(action);
      if (action === "edit") board.editing = !board.editing;
      else if (action === "pick-day") board.selected = control.value;
      else if (action === "today") {
        board.selected = "";
        board.month = null;
      } else if (dateControl) {
        const day = board.month || (board.selected ? localDay(board.selected) : new Date());
        board.month = monthAt(day, action === "prev-month" ? -1 : 1);
      }
      else if (action === "reset") board.items = normalizeLayout(descriptors, null);
      else {
        const item = board.items.find(i => i.id === id);
        if (!board.editing || !available.has(id) || !item) return;
        if (action === "visible") item.visible = control.checked;
        else if (action === "size" && Object.hasOwn(sizes, control.value)) item.size = control.value;
        else if (action === "up" || action === "down") {
          const relevant = board.items.filter(i => available.has(i.id));
          const target = relevant[relevant.indexOf(item) + (action === "up" ? -1 : 1)];
          if (target) move(board.items, id, target.id);
        }
      }
      if (action !== "edit" && !dateControl && !save(board)) toast("无法保存组件设置");
      render();
      const search = id ? '[data-dashboard-option="' + id + '"] ' : "";
      const updated = root.ownerDocument.getElementById(root.id);
      const valueSelector = action === "pick-day" ? '[aria-pressed="true"]' : "";
      const next = updated?.querySelector(search + '[data-dashboard-control="' + action + '"]' + valueSelector);
      (next?.disabled ? updated.querySelector(search + selector) : next)?.focus();
    }
    root.onclick = event => {
      const control = event.target.closest('button' + selector);
      if (control) update(control);
    };
    root.onchange = event => {
      if (event.target.matches(selector)) update(event.target);
    };
    root.ondragstart = event => {
      if (!board.editing || !event.target.matches(".dashboard-drag")) return;
      dragged = event.target.closest("[data-dashboard-widget]").dataset.dashboardWidget;
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", dragged);
    };
    root.ondragover = event => {
      if (dragged && event.target.closest("[data-dashboard-widget]")) event.preventDefault();
    };
    root.ondrop = event => {
      const id = event.target.closest("[data-dashboard-widget]")?.dataset.dashboardWidget;
      if (!dragged || !id) return;
      event.preventDefault();
      if (move(board.items, dragged, id)) {
        if (!save(board)) toast("无法保存组件设置");
        render();
      }
      dragged = "";
    };
    root.ondragend = () => { dragged = ""; };
  }

  const dashboard = {load, markup, mount, calendarKey, calendarMonth, tasksOn, taskWindows, projectSummaries, normalizeLayout, move, scopeKey, researchQuestions};
  if (typeof module !== "undefined" && module.exports) module.exports = dashboard;
  if (typeof window !== "undefined") window.SciStationDashboard = dashboard;
})();
