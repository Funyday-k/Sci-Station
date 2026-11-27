"use strict";
(() => {
  const text = (zh, en) => globalThis.SciStationI18n?.text(zh, en) ?? zh;
  const local = (key, zh, en) => globalThis.SciStationI18n?.message?.(key) ?? text(zh, en);
  const locale = () => globalThis.SciStationI18n?.language || "zh-Hans";
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
  const homeTitles = {
    today: ["homeWidgetToday", "Today"], active_projects: ["homeWidgetActiveProjects", "Active Projects"],
    ai_review: ["homeWidgetAIReview", "AI Review"], calendar: ["homeWidgetCalendar", "Calendar"],
    recent_papers: ["homeWidgetRecentPapers", "Recent Papers"], reading_plan: ["homeWidgetReading", "Reading"],
    project_health: ["homeWidgetProjectHealth", "Project Health"], quick_actions: ["homeWidgetQuickActions", "Quick Actions"]
  };
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

  const projectTitles = {project_status: "Project Status", research_questions: "Research Questions", project_brief: "Project Brief",
    core_papers: "Core Papers", current_tasks: "Current Tasks", materials: "Materials", knowledge_gaps: "Knowledge Gaps",
    recent_activity: "Recent Activity", project_documents: "Project Documents", workflow: "Workflows"};
  function widgetTitle([id, zh]) {
    const [key, english] = homeTitles[id] || [];
    return key ? local(key, zh, english) : text(zh, projectTitles[id] || "Recent Roundtables");
  }
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

  function stage({papers, notes, gaps, kinds, activity, unsupportedClaimCount}, now) {
    if (activity && +now - activity > 21 * 86400000) return ["on_hold", text("搁置", "On hold"), text("最近 21 天无活动", "No activity in the last 21 days")];
    if (unsupportedClaimCount > 0) return ["reviewing", text("审阅", "In review"), text("有声明缺少原文证据", "Claims are missing source evidence")];
    if (kinds.has("reviewer_response")) return ["reviewing", text("审阅", "In review"), text("已登记审稿回复", "Reviewer response recorded")];
    if (kinds.has("writing_revision") || kinds.has("related_work")) return ["drafting", text("撰写", "Drafting"), text("已登记写作修订或相关工作", "Writing revisions or related work recorded")];
    if (papers >= 5 && gaps > 0 && kinds.has("research_plan")) return ["planning", text("规划", "Planning"), text("已有研究计划、论文和待研究缺口", "Research plan, papers, and research gaps recorded")];
    if (papers < 5 && notes < 3 && !kinds.size) return ["exploration", text("探索", "Exploration"), text("论文少于五篇，且项目笔记少于三篇", "Fewer than five papers and three project notes")];
    return ["planning", text("规划", "Planning"), text("已积累项目资料", "Project materials recorded")];
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
      let activity = Math.max(instant(timestamp(project)), instant(info?.lastResearchActivity));
      for (const item of [...linked, ...deadlines, ...drafts.filter(r => r.status === "accepted")]) activity = Math.max(activity, instant(timestamp(item)));
      const windows = taskWindows(deadlines, now);
      const readingCount = linked.filter(p => +now - instant(timestamp(p)) <= 14 * 86400000).length;
      return {project, linked, core, ...windows, readingCount, facts: info, drafts, activity, stage: info ? stage({
        papers: linked.length, notes: info.noteCount, gaps: info.gapCount, kinds, activity, unsupportedClaimCount: info.unsupportedClaimCount
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
    if (!id) return true;
    if (!modules) return id !== "ai-lab";
    return window.SciStationModules?.isEnabled(modules, id) ??
      (modules.modules || []).find(item => item.id === id)?.effective === true;
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

  async function load(request, projectID, modules) {
    const project = projectID ? encodeURIComponent(projectID) : "";
    const [workspace, [facts, reviews]] = await Promise.all([
      request("/api/workspace"),
      Promise.allSettled([
        request("dashboard/projects" + (project ? "?project=" + project : "")),
        enabled(modules, "ai-lab") ? request(project ? "projects/" + project + "/reviews" : "reviews") : []
      ])
    ]);
    return {workspace, facts: facts.value, reviews: reviews.value, modules,
      failures: {facts: facts.status === "rejected", reviews: reviews.status === "rejected"}};
  }

  function markup(state, ui, now = new Date()) {
    const {esc, heading, button, link, panel, paperRows, taskRows, meetingRows, viewURL, studio, fmtDate, row, rowAction, list} = ui;
    const project = state.project;
    const {facts, reviews, modules, failures = {}} = state.dashboardData || {};
    const descriptors = project ? projectWidgets : homeWidgets;
    const board = preference(state, descriptors);
    const isEnabled = id => enabled(modules, id);
    const today = calendarKey(now);
    const dateHeading = new Intl.DateTimeFormat(locale(), {dateStyle: "full"}).format(now);
    const dateStr = value => /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : fmtDate(value);
    const dashboardNav = (title, view, id = project?.id) => link(title, viewURL(view, id), "action-link");
    const reviewURL = r => window.SciStationNav.route("/studio", {project: r.projectId, session: r.meetingId, review: r.id});
    const url = (path, params) => window.SciStationNav.route(path, params);
    const calendar = viewURL("calendar", project?.id);
    const overview = projectSummaries(project ? [project] : state.projects, state.papers, state.tasks, reviews, facts, now);
    const {today: due, upcoming} = taskWindows(state.tasks, now);
    const stageBadge = summary => summary.stage
      ? '<span class="dashboard-stage" data-stage="' + summary.stage[0] + '" title="' + esc(summary.stage[2]) + '">' + summary.stage[1] + '</span>'
      : '<span class="dashboard-muted">阶段暂不可用</span>';
    const message = text => '<p class="dashboard-muted">' + esc(text) + '</p>';
    const subhead = text => '<h3 class="dashboard-subhead">' + esc(text) + '</h3>';
    const metric = (value, label) => value ? '<span class="dashboard-stat"><b>' + esc(value) + '</b> ' + esc(label) + '</span>' : "";
    const groupedMetrics = (...metrics) => metrics.some(Boolean) ? '<div class="dashboard-stats">' + metrics.filter(Boolean).join("") + '</div>' : "";
    const unavailable = [
      failures.facts && text("项目统计", "Project statistics"),
      failures.reviews && text("审核队列", "Review queue")
    ].filter(Boolean);
    const warning = unavailable.length ? '<div class="dashboard-load-warning" role="alert">' +
      panel(text("部分数据加载失败", "Some dashboard data could not be loaded"), message(unavailable.join(text("、", ", "))),
        button(local("homeRetry", "重试", "Retry"), "reload")) + '</div>' : "";
    const callout = (items, render, fallback) => items.length ? render(items) : message(fallback);
    const dateLabel = item => [dateStr(item.dueDate || timestamp(item)), item.dueTime].filter(Boolean).join(" · ");
    const noteRows = items => list(items.map(n => row("file", n.title, fmtDate(n.updatedAt), rowAction("read-note", n.id))));
    const pending = (reviews || []).filter(r => r.status === "pending" && (!project || r.projectId === project.id)).sort(recent);
    const totalUnsupported = overview.reduce((sum, item) => sum + (item.facts?.unsupportedClaimCount || 0), 0);
    const paperLimit = size => ({small: 1, wide: 2, tall: 3, medium: 4, large: 6})[size];
    const available = new Map(descriptors.filter(([, , , required]) => isEnabled(required)).map(d => [d[0], d]));
    const visible = board.items.filter(item => item.visible && available.has(item.id));
    const visibleIds = new Set(visible.map(item => item.id));
    const todayWidget = visible.find(item => item.id === "today");
    const taskIdentity = t => t.id ? "id:" + t.id : "t:" + (t.dueDate || "") + ":" + (t.dueTime || "") + ":" + t.title;
    const todayShownIds = new Set();
    if (!project && todayWidget) {
      const todayLimit = paperLimit(todayWidget.size);
      for (const task of due.slice(0, todayLimit)) todayShownIds.add(taskIdentity(task));
      if (upcoming.length && todayLimit > 1) {
        for (const task of upcoming.slice(0, Math.min(todayLimit - 1, 3))) todayShownIds.add(taskIdentity(task));
      }
    }
    const projectMeta = project ? projectData() : null;
    const sections = project ? projectSections(projectMeta) : homeSections();
    const title = project ? project.name : local("routeHome", "首页", "Home");
    const editLabel = board.editing ? local("homeDoneEditing", "完成布局", "Done") : local("homeEditLayout", "编辑布局", "Edit Layout");
    const edit = '<button type="button" class="' + (board.editing ? 'button primary' : 'button dashboard-edit-layout') +
      '" data-dashboard-control="edit" aria-expanded="' + board.editing + '" aria-controls="dashboard-layout"' +
      ' aria-label="' + esc(editLabel) + '" title="' + esc(editLabel) + '">' +
      (board.editing ? esc(editLabel) : window.RoundtableIcons?.icon("sliders") || "") + '</button>';
    const aiHome = url("/lab", project ? {project: project.id} : {scope: "global"});
    const projectActions = project && isEnabled("ai-lab") ? link(local("openAIWorkspace", "打开 AI", "Open AI"), aiHome,
      board.editing ? "button" : "button primary", "chat") : "";
    const styledPanel = (variant, titleText, body, action = "", extraClass = "") => {
      const rendered = panel(titleText, body, action);
      const classes = ["panel", "card", "card--" + variant, extraClass].filter(Boolean).join(" ");
      return rendered.startsWith('<section class="panel">')
        ? '<section class="' + classes + '">' + rendered.slice('<section class="panel">'.length)
        : rendered;
    };
    const homeCardVariant = id => {
      if (id === "today") return "primary";
      if (id === "project_health" || id === "quick_actions") return "compact";
      if (id === "ai_review" && reviews && !pending.length && !totalUnsupported) return "empty";
      if (id === "active_projects" && !overview.length) return "empty";
      if (id === "recent_papers" && !state.papers.length) return "empty";
      if (id === "reading_plan" && !state.papers.some(p => p.status === "unread" || p.status === "reading")) return "empty";
      if (id === "meetings" && !state.meetings.length) return "empty";
      return "secondary";
    };
    const projectCardVariant = id => {
      if (id === "project_status") return "compact";
      if (projectMeta?.emptyModules.has(id)) return "empty";
      if (id === "current_tasks" || id === "core_papers" || id === "project_brief") return "primary";
      return "secondary";
    };
    const widget = item => {
      const label = widgetTitle(available.get(item.id));
      const handle = board.editing ? '<span aria-hidden="true" class="dashboard-drag" draggable="true" title="' +
        esc(text("拖动排序", "Drag to reorder")) + '">⠿</span>' : "";
      const variant = project ? projectCardVariant(item.id) : homeCardVariant(item.id);
      const compactAIReview = !project && item.id === "ai_review" && !board.editing && reviews && !pending.length && !totalUnsupported;
      if (compactAIReview) {
        const statusBody = '<span class="empty-row__title">' + esc(label) + '</span>' +
          '<span class="empty-row__meta">' + esc(local("homeAIReviewClear", "暂无待审核草稿", "No drafts pending review")) + '</span>';
        return '<article class="dashboard-widget dashboard-' + item.size + ' dashboard-widget--compact-row" data-dashboard-widget="' +
          item.id + '" data-card-variant="empty" data-compact-empty="true"><section class="panel card card--empty empty-row" aria-label="' +
          esc(label) + '">' + statusBody + '</section></article>';
      }
      return '<article class="dashboard-widget dashboard-' + item.size + '" data-dashboard-widget="' + item.id +
        '" data-card-variant="' + variant + '">' +
        styledPanel(variant, label, sections[item.id](paperLimit(item.size), item.size), handle) + '</article>';
    };
    const layoutOption = (item, index, availableItems) => {
      const id = item.id, label = widgetTitle(available.get(item.id));
      const options = Object.entries(sizes).map(([size, label]) => '<option value="' + size + '"' +
        (item.size === size ? ' selected' : '') + '>' + text(label, size) + '</option>').join("");
      return '<div class="dashboard-layout-row" data-dashboard-option="' + id + '"><label><input type="checkbox" data-dashboard-control="visible"' +
        (item.visible ? ' checked' : '') + '> ' + esc(label) + '</label><select aria-label="' + esc(text(`${label}尺寸`, `Size of ${label}`)) + '" data-dashboard-control="size">' +
        options + '</select>' + direction("up", local("homeMoveEarlier", "上移", "Move earlier"), index === 0) +
        direction("down", local("homeMoveLater", "下移", "Move later"), index === availableItems.length - 1) + '</div>';
      function direction(direction, text, disabled) {
        return '<button type="button" class="bare" data-dashboard-control="' + direction + '" aria-label="' + esc(`${text} ${label}`) + '"' +
          (disabled ? ' disabled' : '') + '>' + text + '</button>';
      }
    };
    const gallery = board.editing ? '<section id="dashboard-layout" class="panel card card--secondary dashboard-layout" aria-label="' +
      esc(local("homeWidgetGallery", "小组件库", "Widget Gallery")) + '">' +
      '<div class="dashboard-layout-options">' + board.items.filter(i => available.has(i.id)).map(layoutOption).join("") + '</div>' +
      '<button type="button" class="button" data-dashboard-control="reset">' + esc(local("homeResetDefault", "恢复默认布局", "Reset Default")) + '</button></section>' : '<div id="dashboard-layout" hidden></div>';
    let widgets;
    if (!visible.length) {
      widgets = ui.empty(local("homeNoEnabledWidgets", "没有显示的组件", "No widgets are enabled."));
    } else if (project) {
      const statusItem = visible.find(item => item.id === "project_status");
      const summaryStrip = statusItem ? '<div class="dashboard-overview-summary">' + widget(statusItem) + '</div>' : "";
      const rest = visible.filter(item => item.id !== "project_status");
      const collapsed = board.editing ? [] : rest.filter(item => projectMeta.emptyModules.has(item.id));
      const active = board.editing ? rest : rest.filter(item => !projectMeta.emptyModules.has(item.id));
      const primaryGrid = active.length ? '<div class="dashboard-grid dashboard-overview-grid">' + active.map(widget).join("") + '</div>' : "";
      const quickAddItems = collapsed.map(item => projectQuickAdd(item.id)).filter(Boolean);
      const quickAdd = quickAddItems.length
        ? '<section class="dashboard-quick-add quick-add-row" aria-label="' + esc(local("overviewQuickAdd", "快速添加", "Quick add")) + '">' +
          '<span class="quick-add-row__label">' + esc(local("overviewQuickAdd", "快速添加", "Quick add")) + '</span>' +
          '<div class="quick-add-row__items">' + quickAddItems.join("") + '</div></section>'
        : "";
      widgets = summaryStrip + primaryGrid + quickAdd;
    } else {
      widgets = '<div class="dashboard-grid dashboard-home-grid">' + visible.map(widget).join("") + '</div>';
    }
    return '<div id="dashboard-view">' + heading(title, project ? project.description : dateHeading, projectActions + edit, project) +
      warning + gallery + widgets + '</div>';

    function projectQuickAdd(id) {
      const destinations = {
        research_questions: ["notes", text("添加研究问题", "Add research questions")],
        project_brief: ["notes", text("编写项目简报", "Write project brief")],
        core_papers: ["papers", text("添加核心论文", "Add core papers")],
        current_tasks: ["tasks", text("新建任务", "Add task")],
        materials: ["materials", text("添加材料", "Add material")],
        knowledge_gaps: ["notes", text("记录知识缺口", "Log knowledge gap")],
        project_documents: ["notes", text("新建项目文档", "Add project document")],
        workflow: ["meetings", text("开始工作流", "Start workflow")]
      };
      const entry = destinations[id];
      if (!entry) return "";
      const [view, label] = entry;
      return '<a class="action-link" data-quick-add-module="' + id + '" href="' + esc(viewURL(view, project.id)) + '">' + esc(label) + '</a>';
    }

    function homeSections() {
      const reading = state.papers.filter(p => p.status === "unread" || p.status === "reading")
        .sort((a, b) => b.priority - a.priority || Number(b.status === "reading") - Number(a.status === "reading") || recent(a, b));
      const projectRows = items => list(items.map(summary => row("folder", summary.project.name,
        [isEnabled("paper-library") && summary.core.length + " 篇核心文献", isEnabled("tasks") && summary.activeTasks.length + " 项待办",
          summary.facts?.unsupportedClaimCount > 0 && text(summary.facts.unsupportedClaimCount + " 项缺证据声明", summary.facts.unsupportedClaimCount + " claims need evidence"),
          isEnabled("tasks") && summary.next && dateLabel(summary.next)].filter(Boolean).join(" · "),
        'a data-project="' + esc(summary.project.id) + '" href="' + esc(viewURL("overview", summary.project.id)) + '"',
        summary.stage?.[1] || text("阶段暂不可用", "Stage unavailable"), "", summary.project)));
      return {
        today: limit => groupedMetrics(metric(due.length, text("今日到期或逾期", "due today or overdue")), metric(upcoming.length, text("未来两周", "in the next two weeks")),
          isEnabled("paper-library") && metric(reading.length, text("篇待读", "to read")), isEnabled("ai-lab") && reviews && metric(pending.length, text("项待审核", "for review"))) +
          callout(due.slice(0, limit), taskRows, text("今天没有到期任务", "No tasks are due today")) + (upcoming.length && limit > 1
            ? subhead(text("近期截止", "Upcoming deadlines")) + taskRows(upcoming.slice(0, Math.min(limit - 1, 3))) : "") + dashboardNav(text("查看任务", "View tasks"), "tasks"),
        active_projects: limit => callout(overview.slice(0, limit), projectRows, text("暂无活跃项目", "No active projects")) + dashboardNav(text("全部项目", "All projects"), "projects"),
        ai_review: limit => reviews ? groupedMetrics(metric(pending.length, text("项待审核", "for review")),
          facts && metric(totalUnsupported, text("项缺证据声明", "claims missing evidence"))) + callout(pending.slice(0, limit), items =>
          list(items.map(r => row("file", r.title, [state.projects.find(p => p.id === r.projectId)?.name, fmtDate(r.createdAt)].filter(Boolean).join(" · "),
            'a href="' + esc(reviewURL(r)) + '"'))), local("homeAIReviewClear", "暂无待审核草稿", "No drafts pending review")) : message(text("暂时无法读取审核队列", "Could not load the review queue")),
        calendar: calendarWidget,
        recent_papers: limit => callout(state.papers.slice().sort(recent).slice(0, limit), paperRows, text("暂无文献", "No papers yet")) + dashboardNav(local("routeLibrary", "文献库", "Library"), "papers"),
        reading_plan: limit => groupedMetrics(metric(reading.length, text("篇待读", "to read"))) +
          callout(reading.slice(0, limit), paperRows, local("homeReadingEmpty", "暂无待读论文", "No papers to read yet.")) + dashboardNav(local("routeLibrary", "文献库", "Library"), "papers"),
        project_health: () => (groupedMetrics(metric(overview.length, text("个活跃项目", "active projects")),
          isEnabled("tasks") && metric(due.filter(t => t.dueDate < today).length, text("项逾期任务", "overdue tasks"))) ||
          message(text("暂无活跃项目", "No active projects"))) + dashboardNav(text("全部项目", "All projects"), "projects"),
        quick_actions: () => '<div class="actions">' + [isEnabled("projects") && button(local("toolbarNewProject", "新建项目", "New Project"), "new-project"),
          isEnabled("paper-library") && button(text("导入文献", "Import papers"), "new-paper"), isEnabled("tasks") && button(text("添加任务", "New task"), "new-task"),
          isEnabled("ai-lab") && link(local("openAIWorkspace", "打开 AI", "Open AI"), aiHome)].filter(Boolean).join("") + '</div>',
        meetings: limit => callout(state.meetings.slice().sort(recent).slice(0, limit), meetingRows, text("暂无圆桌", "No Roundtables yet")) + link(local("openRoundtable", "打开圆桌", "Open Roundtable"), studio(), "action-link")
      };
    }

    function calendarWidget(limit) {
      const selected = board.selected || today;
      const selectedDate = localDay(selected);
      const display = monthAt(board.month || selectedDate, 0);
      const dateFormat = new Intl.DateTimeFormat(locale(), {dateStyle: "long"});
      const calendarTasks = isEnabled("tasks") ? state.tasks : [];
      const rawEvents = tasksOn(calendarTasks, selected);
      const deduplicateToday = !project && visibleIds.has("today") && selected === today && todayShownIds.size > 0;
      const events = deduplicateToday ? rawEvents.filter(t => !todayShownIds.has(taskIdentity(t))) : rawEvents;
      const controls = '<div class="dashboard-calendar-head"><h3>' +
        esc(new Intl.DateTimeFormat(locale(), {year: "numeric", month: "long"}).format(display)) + '</h3>' +
        '<div><button type="button" class="bare" data-dashboard-control="prev-month" aria-label="' + esc(text("上一月", "Previous month")) + '">‹</button>' +
        '<button type="button" class="bare" data-dashboard-control="today">' + esc(local("homeWidgetToday", "今天", "Today")) + '</button>' +
        '<button type="button" class="bare" data-dashboard-control="next-month" aria-label="' + esc(text("下一月", "Next month")) + '">›</button></div></div>';
      const weekdays = text(["一", "二", "三", "四", "五", "六", "日"], ["M", "T", "W", "T", "F", "S", "S"])
        .map(label => '<span aria-hidden="true">' + label + '</span>').join("");
      const days = calendarMonth(display).map(date => {
        const key = calendarKey(date);
        if (date.getMonth() !== display.getMonth()) return '<span aria-hidden="true"></span>';
        const count = calendarTasks.filter(t => {
          const start = t.startDate || t.dueDate;
          return start && start <= key && (t.dueDate || start) >= key;
        }).length;
        const label = dateFormat.format(date) + (count ? text(`，${count} 项任务`, `, ${count} tasks`) : "");
        return '<button type="button" class="dashboard-day' + (count ? ' has-events' : '') + '" data-dashboard-control="pick-day" value="' + key +
          '" aria-label="' + esc(label) + '" aria-pressed="' + (key === selected) + '"' + (key === today ? ' aria-current="date"' : '') +
          '>' + date.getDate() + '</button>';
      }).join("");
      const month = '<div class="dashboard-calendar-month">' + controls +
        '<div class="dashboard-month">' + weekdays + days + '</div></div>';
      const emptyAgendaText = deduplicateToday && rawEvents.length > 0
        ? local("homeCalendarShownInToday", "今日任务已显示在「今日」中。", "Today’s tasks are listed in Today.")
        : text("当天没有任务", "No tasks on this day");
      const agenda = '<div class="dashboard-calendar-agenda"><div class="dashboard-calendar-head"><h3>' +
        esc(dateFormat.format(selectedDate)) + '</h3></div>' +
        callout(events.slice(0, limit), taskRows, emptyAgendaText) +
        '<div class="dashboard-calendar-links">' + link(text("打开日历", "Open calendar"), calendar, "action-link") +
        link(text("系统日历", "System calendar"), ui.toolsPage("calendar"), "action-link") + '</div></div>';
      return '<div class="dashboard-calendar">' + month + agenda + '</div>';
    }

    function projectData() {
      const info = overview[0];
      const notes = state.notes.slice().sort(recent);
      const brief = notes.find(n => (n.namespace === "projects" && /^project[ _-]overview$/i.test(n.title)) || tag(n, "project_brief"));
      const questions = researchQuestions(brief?.body);
      const gaps = notes.filter(noteIsGap);
      const materials = state.materials.slice().sort(recent);
      const core = info.core.slice().sort((a, b) => b.priority - a.priority || b.rating - a.rating || recent(a, b));
      const meetings = state.meetings.slice().sort(recent);
      const activity = [
        ...(isEnabled("paper-library") ? info.linked.map(p => ({date: timestamp(p), html: row("book", p.title, fmtDate(timestamp(p)),
          'a href="' + esc(ui.reader(p.id)) + '"')})) : []),
        ...(isEnabled("materials") ? materials.map(m => ({date: timestamp(m), html: row("file", m.name, fmtDate(m.updatedAt), rowAction("read-material", m.id))})) : []),
        ...(isEnabled("ai-lab") ? info.drafts.filter(r => r.status !== "rejected").map(r => ({date: timestamp(r), html: row("file", r.title,
          fmtDate(timestamp(r)), 'a href="' + esc(reviewURL(r)) + '"', r.status === "accepted" ? text("已接受", "Accepted") : text("待审核", "In review"))})) : [])
      ].sort((a, b) => instant(b.date) - instant(a.date));
      const emptyModules = new Set();
      if (!questions.length) emptyModules.add("research_questions");
      if (!brief?.body?.trim()) emptyModules.add("project_brief");
      if (!core.length) emptyModules.add("core_papers");
      if (!info.activeTasks.length) emptyModules.add("current_tasks");
      if (!materials.length) emptyModules.add("materials");
      if (!gaps.length) emptyModules.add("knowledge_gaps");
      if (!activity.length && !failures.reviews) emptyModules.add("recent_activity");
      if (!notes.length) emptyModules.add("project_documents");
      if (!meetings.length) emptyModules.add("workflow");
      return {info, notes, brief, questions, gaps, materials, core, meetings, activity, emptyModules};
    }

    function projectSections({info, notes, brief, questions, gaps, materials, core, meetings, activity}) {
      return {
        project_status: (_limit, size) => '<div class="dashboard-summary-row">' + stageBadge(info) + groupedMetrics(
          isEnabled("paper-library") && metric(info.linked.length, text("篇论文", "papers")), isEnabled("paper-library") && metric(core.length, text("篇核心论文", "core papers")),
          isEnabled("wiki") && metric(notes.length, text("篇笔记", "notes")), isEnabled("tasks") && metric(info.activeTasks.length, text("项待办", "open tasks")),
          info.facts && metric(info.facts.unsupportedClaimCount || 0, text("项缺证据声明", "claims missing evidence")),
          isEnabled("ai-lab") && reviews && metric(pending.length, text("项待审核", "for review"))) + '</div>' + (isEnabled("tasks") && info.next && size !== "small" && size !== "wide"
          ? subhead(text("下一项截止", "Next deadline")) + taskRows([info.next]) : ""),
        research_questions: limit => callout(questions.slice(0, limit), items => '<ul class="dashboard-questions">' +
          items.map(item => '<li>' + esc(item) + '</li>').join("") + '</ul>', text("简报中暂无研究问题", "No research questions in the brief yet")),
        project_brief: limit => {
          const preview = brief?.body?.trim();
          return (preview ? '<div class="dashboard-brief">' + esc(preview.slice(0, limit * 180)) + '</div>' :
            message(text("暂无项目简报", "No project brief"))) + (brief ?
            button(text("编辑简报", "Edit brief"), "edit-note", {id: brief.id, kind: "action-link"}) :
            dashboardNav(local("homeQuickActionOpenWiki", "打开 Wiki", "Open Wiki"), "notes"));
        },
        core_papers: limit => callout(core.slice(0, limit), items => paperRows(items, project.id), text("暂无核心论文", "No core papers yet")) + dashboardNav(text("项目论文", "Project papers"), "papers"),
        current_tasks: limit => callout(info.activeTasks.slice(0, limit), taskRows, text("暂无未完成任务", "No open tasks")) + dashboardNav(text("查看任务", "View tasks"), "tasks"),
        materials: limit => callout(materials.slice(0, limit), items => list(items.map(m => row("file", m.name, fmtDate(m.updatedAt),
          rowAction("read-material", m.id)))), text("暂无材料", "No materials")) + dashboardNav(text("全部材料", "All materials"), "materials"),
        knowledge_gaps: limit => callout(gaps.slice(0, limit), noteRows, text("没有登记的研究缺口", "No research gaps recorded")) + dashboardNav(local("homeQuickActionOpenWiki", "打开 Wiki", "Open Wiki"), "notes"),
        recent_activity: limit => callout(activity.slice(0, limit), items => list(items.map(a => a.html)),
          failures.reviews ? text("无法读取审核活动", "Could not load review activity") : text("暂无近期活动", "No recent activity")),
        project_documents: limit => callout(notes.slice(0, limit), noteRows, text("暂无项目文档", "No project documents")) + dashboardNav(text("全部文档", "All documents"), "notes"),
        workflow: limit => callout(meetings.slice(0, limit), meetingRows, text("暂无项目圆桌", "No project Roundtables")) +
          dashboardNav(text("查看项目会话", "View project sessions"), "meetings")
      };
    }
  }

  function mount(root, state, render, toast) {
    const brief = root.querySelector?.(".dashboard-brief");
    if (brief) window.SciMarkdown?.render(brief, brief.textContent, {headingShift: 2, cache: true});
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
