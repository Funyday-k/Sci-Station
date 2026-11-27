"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const {createTestDocument, serialize} = require("./lib/research-dom-fixture.cjs");
const dashboard = require("../web/static/research-dashboard.js");

function fixtureUI() {
  const document = createTestDocument();
  const append = (node, children) => {
    for (const child of children.flat(Infinity)) {
      if (child != null && child !== false) node.append(child);
    }
    return node;
  };
  const el = (tag, attrs, ...children) => {
    const element = document.createElement(tag);
    for (const [name, value] of Object.entries(attrs)) {
      if (value != null && value !== false) element.setAttribute(name, value === true ? "" : value);
    }
    return append(element, children);
  };
  const fragment = (...children) => append(document.createDocumentFragment(), children);
  return {
    el, fragment,
    heading: (title, info, actions) => fragment(el("h1", {}, title), info, actions),
    button: (label, action, options = {}) => el("button", {"data-action":action, "data-id":options.id}, label),
    link: (label, href, kind = "button") => el("a", {class:kind, href}, label),
    panel: (title, body, actions) => el("section", {class:"panel"}, el("h2", {}, title), body, actions),
    paperRows: () => null, taskRows: items => fragment(items.map(t => el("span", {class:"task-row"}, t.title))), meetingRows: () => null,
    viewURL: require("../web/static/workspace-nav.js").research, studio: String, fmtDate: String,
    row: (_glyph, title, _meta, control) => append(control, [title]), rowAction: (action, id) => el("button", {"data-action":action, "data-id":id}),
    list: rows => fragment(rows), empty: label => el("p", {}, label), reader: String, toolsPage: String
  };
}

test("dashboard calendar uses local dates across month and daylight-saving transitions", () => {
  const now = new Date(2026, 9, 27, 23, 59);
  const tasks = [
    {status: "open", dueDate: "2026-10-26", title: "Overdue"},
    {status: "doing", dueDate: "2026-10-27", title: "Due today"},
    {status: "cancelled", dueDate: "2026-10-27", title: "Cancelled"},
    {status: "done", dueDate: "2026-10-27", title: "Completed"},
    {status: "open", dueDate: "2026-11-09", startDate: "2026-11-08", title: "Ranged task"},
    {status: "open", dueDate: "2026-11-10", title: "Horizon boundary"},
    {status: "open", dueDate: "", title: "Unscheduled"},
  ];
  const {today, upcoming, next} = dashboard.taskWindows(tasks, now);
  assert.deepEqual(today.map(t => t.title), ["Overdue", "Due today"]);
  assert.deepEqual(upcoming.map(t => t.title), ["Ranged task"]);
  assert.equal(next.title, "Due today");
  assert.deepEqual(dashboard.tasksOn(tasks, "2026-11-08").map(t => t.title), ["Ranged task"]);
  assert.deepEqual(dashboard.tasksOn(tasks, "2026-11-10").map(t => t.title), ["Horizon boundary"]);
  const month = dashboard.calendarMonth(new Date(2026, 7, 31));
  assert.equal(month.length, 42);
  assert.equal(dashboard.calendarKey(month[0]), "2026-07-27");
  assert.equal(dashboard.calendarKey(month.at(-1)), "2026-09-06");
});

test("project stages and deadline counts are scoped to current records", () => {
  const now = new Date("2026-11-25T08:00:00Z");
  const projects = [
    {id: "a", name: "Alpha", updatedAt: "2026-11-25T00:00:00Z"},
    {id: "b", name: "Beta", updatedAt: "2026-11-04T08:00:00Z"},
    {id: "idle", name: "Idle", updatedAt: "2026-11-04T07:59:59Z"},
    {id: "empty", name: "Empty", updatedAt: "2026-11-25T00:00:00Z"},
    {id: "claims", name: "Claims", updatedAt: "2026-11-02T00:00:00Z"},
    {id: "plan", name: "Plan", updatedAt: "2026-11-25T00:00:00Z"},
    {id: "missing", name: "Missing facts", updatedAt: "2026-11-25T00:00:00Z"},
  ];
  const papers = [{project_ids: ["a", "b"], core_project_ids: ["b"], updated_at: "2026-11-25T00:00:00Z"}];
  const tasks = [{projectIds: ["a", "b"], dueDate: "2026-11-26", title: "Shared"}];
  const reviews = [{projectId: "empty", status: "pending"},
    {projectId: "idle", status: "pending", updatedAt: "2026-11-25T00:00:00Z"},
    {projectId: "idle", status: "rejected", updatedAt: "2026-11-25T02:00:00Z"}];
  const facts = {
    a: {noteCount: 0, gapCount: 0, artifactKinds: ["related_work", "reviewer_response"]},
    b: {noteCount: 0, gapCount: 0, artifactKinds: ["writing_revision"]},
    idle: {noteCount: 0, gapCount: 0, artifactKinds: ["reviewer_response"], unsupportedClaimCount: 4, lastResearchActivity: "2026-11-04T07:59:59Z"},
    empty: {noteCount: 0, gapCount: 0, artifactKinds: []},
    claims: {noteCount: 0, gapCount: 0, artifactKinds: [], unsupportedClaimCount: 2, lastResearchActivity: "2026-11-25T01:00:00Z"},
    plan: {noteCount: 3, gapCount: 1, artifactKinds: []},
  };
  const summaries = dashboard.projectSummaries(projects, papers, tasks, reviews, facts, now);
  assert.deepEqual(summaries.slice(0, 2).map(s => s.project.id), ["a", "b"]);
  assert.deepEqual(summaries.slice(0, 2).map(s => s.activeTasks.length), [1, 1]);
  assert.deepEqual(summaries.slice(0, 2).map(s => s.core.length), [0, 1]);
  const byID = Object.fromEntries(summaries.map(s => [s.project.id, s.stage?.[0]]));
  assert.deepEqual(byID, {a: "reviewing", b: "drafting", idle: "on_hold", empty: "exploration", claims: "reviewing", plan: "planning", missing: undefined});
});

test("widget configuration normalizes old settings and preserves bidirectional movement", () => {
  const descriptors = [["today", "Today", "medium"], ["calendar", "Calendar", "large"], ["review", "Review", "small"]];
  const previous = [{id: "legacy"}, {id: "calendar", size: "invalid", visible: false}, {id: "calendar", size: "small"}];
  const items = dashboard.normalizeLayout(descriptors, previous);
  assert.deepEqual(items, [
    {id: "calendar", size: "large", visible: false}, {id: "today", size: "medium", visible: true}, {id: "review", size: "small", visible: true}
  ]);
  assert(dashboard.move(items, "calendar", "review"));
  assert.deepEqual(items.map(i => i.id), ["today", "review", "calendar"]);
  assert(dashboard.move(items, "calendar", "today"));
  assert.deepEqual(items.map(i => i.id), ["calendar", "today", "review"]);
  assert(!dashboard.move(items, "calendar", "unknown"));
  assert.notEqual(dashboard.scopeKey("first", "same"), dashboard.scopeKey("second", "same"));
  assert.notEqual(dashboard.scopeKey("first", "same"), dashboard.scopeKey("first", null));
});

test("overview extracts research questions only from corresponding brief sections", () => {
  const body = "# Background\n- General context\n## Research questions\n- [ ] Does the scaling hold?\n2. What sets the transition?\n## Methods\n### Unrelated subsection\n- Not a question\n# 研究问题\n* 可以测量什么？";
  assert.deepEqual(dashboard.researchQuestions(body), ["Does the scaling hold?", "What sets the transition?", "可以测量什么？"]);
});

test("Home and Overview render durable draft counts and keep widget order, size and visibility scoped to each root", async () => {
  const storage = new Map();
  const window = {SciStationNav: {route: (path, params) => path + "?" + new URLSearchParams(params)}};
  const moduleIDs = ["projects","tasks","calendar","wiki","materials","paper-library","ai-lab"];
  window.SciStationModules = {
    load: async () => ({modules: moduleIDs.map(id => ({id,effective:true}))}),
    isEnabled: require("../web/static/research-modules.js").isEnabled
  };
  const js = fs.readFileSync(require.resolve("../web/static/research-dashboard.js"), "utf8");
  const browser = () => {
    vm.runInNewContext(js, {window, localStorage: {getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value)}});
    return window.SciStationDashboard;
  };
  const alpha = {id: "a", name: "Alpha"}, beta = {id: "b", name: "Beta"};
  const state = {projects: [alpha, beta], papers: [], tasks: [], meetings: [], notes: [], materials: []};
  const facts = {a: {noteCount: 0, gapCount: 0, artifactKinds: ["writing_revision"]}, b: {noteCount: 0, gapCount: 0, artifactKinds: []}};
  const reviews = [
    {id: "1", title: "Pending alpha", status: "pending", projectId: "a", meetingId: "m1"},
    {id: "2", title: "Pending beta <draft>", status: "pending", projectId: "b", meetingId: "m2"},
    {id: "3", title: "Rejected note", status: "rejected", projectId: "a", meetingId: "m1"},
  ];
  const request = async url => ({"/api/workspace": {id: "root-one", name: "Workspace One"}, "dashboard/projects": facts, reviews,
    "dashboard/projects?project=a": {a: facts.a},
    "projects/a/reviews": reviews.filter(r => r.projectId === "a")})[url];
  const ui = fixtureUI();
  let app = browser();
  const config = await window.SciStationModules.load();
  state.dashboardData = await app.load(request, null, config);
  const now = new Date(2026, 10, 25);
  const firstTree = app.markup(state, ui, now);
  assert.equal(firstTree.nodeType, 1);
  assert.ok(firstTree.textContent.includes("Pending beta <draft>"));
  const first = serialize(firstTree);
  const widgets = html => Array.from(html.matchAll(/class="dashboard-widget dashboard-(\w+)[^"]*" data-dashboard-widget="(\w+)"/g),
    ([, size, id]) => [id, size]);
  assert.match(first, /class="dashboard-grid dashboard-home-grid"/);
  assert.deepEqual(widgets(first).slice(0, 4), [["today", "medium"], ["active_projects", "medium"], ["ai_review", "medium"], ["calendar", "large"]]);
  const [month, agenda] = first.split('<div class="dashboard-calendar-agenda">');
  assert.match(month, /class="dashboard-calendar-month">.*data-dashboard-control="next-month".*class="dashboard-month">/s);
  assert.match(agenda, /class="dashboard-calendar-links"><a class="action-link" href="\/research\?view=tasks&amp;tab=calendar">打开日历<\/a>/);
  assert.match(first, /<h1>首页<\/h1>/);
  assert.match(first, /<b>2<\/b> 项待审核/);
  assert.match(first, /href="\/studio\?project=b&amp;session=m2&amp;review=2">Pending beta &lt;draft&gt;<\/a>/);
  assert.doesNotMatch(first, /Rejected note/);
  assert.match(first, /data-dashboard-widget="today" data-card-variant="primary"/);
  assert.match(first, /class="action-link" href="\/research\?view=tasks">查看任务<\/a>/);
  assert.match(first, /class="action-link" href="\/research\?view=projects">全部项目<\/a>/);

  const root = {id: "dashboard-view", ownerDocument: {getElementById: () => null}};
  app.mount(root, state, () => {}, assert.fail);
  const click = (action, id) => root.onclick({target: {closest: () => ({
    dataset: {dashboardControl: action}, closest: () => id && {dataset: {dashboardOption: id}}
  })}});
  click("edit");
  click("up", "ai_review");
  root.onchange({target: {
    dataset: {dashboardControl: "size"}, value: "wide", matches: () => true,
    closest: () => ({dataset: {dashboardOption: "ai_review"}})
  }});
  root.onchange({target: {
    dataset: {dashboardControl: "visible"}, checked: false, matches: () => true,
    closest: () => ({dataset: {dashboardOption: "calendar"}})
  }});
  assert.doesNotMatch(serialize(app.markup(state, ui, now)), /data-dashboard-widget="calendar"/);
  app = browser();
  const saved = serialize(app.markup(state, ui, now));
  assert.deepEqual(widgets(saved).slice(0, 3), [["today", "medium"], ["ai_review", "wide"], ["active_projects", "medium"]]);
  assert.doesNotMatch(saved, /data-dashboard-widget="calendar"/);

  state.dashboardData = {...state.dashboardData, workspace: {id: "root-two"}, modules: {modules: moduleIDs.map(id=>({id,effective:id !== "paper-library"}))}};
  const second = serialize(app.markup(state, ui, now));
  assert.match(second, /data-dashboard-widget="calendar"/);
  assert.deepEqual(widgets(second).slice(0, 3), widgets(first).slice(0, 3));
  assert.doesNotMatch(second, /data-dashboard-widget="recent_papers"/);

  state.project = alpha;
  state.dashboardData = await app.load(request, alpha.id, config);
  const overview = serialize(app.markup(state, ui, now));
  assert.match(overview, /class="dashboard-overview-summary"/);
  assert.deepEqual(widgets(overview), [["project_status", "small"], ["recent_activity", "medium"]]);
  assert.match(overview, /class="dashboard-quick-add quick-add-row"/);
  assert.match(overview, /data-quick-add-module="core_papers"/);
  assert.match(overview, /data-stage="drafting"/);
  assert.match(overview, /<b>1<\/b> 项待审核/);
  assert.doesNotMatch(overview, /Pending beta/);

  // Modules disabled in workspace settings stay hidden from both the primary grid and Quick add.
  state.dashboardData = {...state.dashboardData, modules: {modules: moduleIDs.map(id => ({id, effective: id !== "materials" && id !== "paper-library"}))}};
  const restrictedOverview = serialize(app.markup(state, ui, now));
  assert.doesNotMatch(restrictedOverview, /data-quick-add-module="materials"/);
  assert.doesNotMatch(restrictedOverview, /data-quick-add-module="core_papers"/);
  assert.match(restrictedOverview, /data-quick-add-module="current_tasks"/);

  const activityLayout = ["project_status", "research_questions", "project_brief", "core_papers",
    "current_tasks", "materials", "knowledge_gaps", "recent_activity", "project_documents", "workflow"]
    .map(id => ({id, visible: id === "recent_activity"}));
  const activityWorkspace = {id: "activity-only"};
  storage.set("sci-station.dashboard.v1:" + app.scopeKey(activityWorkspace.id, alpha.id), JSON.stringify(activityLayout));
  const emptyActivity = serialize(browser().markup({...state, dashboardData: {...state.dashboardData,
    workspace: activityWorkspace, reviews: []}}, ui, now));
  assert.deepEqual(widgets(emptyActivity), [["recent_activity", "medium"]]);
  assert.match(emptyActivity, /data-compact-empty="true".*暂无近期活动/s);
  assert.doesNotMatch(emptyActivity, /data-quick-add-module/);

  const failure = async path => {
    if (path.startsWith("dashboard/projects") || path.endsWith("reviews")) throw new Error("Unavailable fixture");
    return request(path);
  };
  state.dashboardData = await app.load(failure, alpha.id, config);
  const unavailableOverview = serialize(app.markup(state, ui, now));
  assert.match(unavailableOverview, /部分数据加载失败.*项目统计、审核队列/s);
  assert.match(unavailableOverview, /无法读取审核活动/);
  assert.doesNotMatch(unavailableOverview, /暂无近期活动/);

  state.project = undefined;
  state.dashboardData = await app.load(failure, null, config);
  const unavailableHome = serialize(app.markup(state, ui, now));
  assert.match(unavailableHome, /部分数据加载失败.*项目统计、审核队列/s);
  assert.match(unavailableHome, /暂时无法读取审核队列/);
  assert.doesNotMatch(unavailableHome, /暂无待审核草稿/);

  state.dashboardData = await app.load(path => path === "reviews" ? Promise.resolve([]) : request(path), null, config);
  const clearHome = serialize(app.markup(state, ui, now));
  assert.match(clearHome, /data-dashboard-widget="ai_review" data-card-variant="empty" data-compact-empty="true"/);
  assert.match(clearHome, /class="panel card card--empty empty-row"[^>]*>.*暂无待审核草稿/s);
  await assert.rejects(app.load(async path => {
    if (path === "/api/workspace") throw new Error("Workspace fixture unavailable");
    return request(path);
  }), /Workspace fixture unavailable/);
});

test("Home deduplicates today's tasks between Today and Calendar while preserving other dates", () => {
  const window = {SciStationNav: {route: (path, params) => path + "?" + new URLSearchParams(params)}};
  const moduleIDs = ["projects", "tasks", "calendar", "wiki", "materials", "paper-library", "ai-lab"];
  window.SciStationModules = {
    isEnabled: require("../web/static/research-modules.js").isEnabled
  };
  const js = fs.readFileSync(require.resolve("../web/static/research-dashboard.js"), "utf8");
  vm.runInNewContext(js, {window, localStorage: {getItem: () => null, setItem: () => {}}});
  const app = window.SciStationDashboard;
  const now = new Date(2026, 10, 25);
  const state = {
    projects: [{id: "p1", name: "Study"}],
    papers: [],
    meetings: [],
    notes: [],
    materials: [],
    tasks: [
      {id: "t1", projectId: "p1", status: "open", dueDate: "2026-11-25", title: "Submit camera-ready"},
      {id: "t2", projectId: "p1", status: "open", dueDate: "2026-11-28", title: "Draft appendix"}
    ],
    dashboardData: {
      workspace: {id: "dedup-root"},
      facts: {p1: {noteCount: 0, gapCount: 0, artifactKinds: []}},
      reviews: [],
      modules: {modules: moduleIDs.map(id => ({id, effective: true}))}
    }
  };
  const ui = fixtureUI();
  const html = serialize(app.markup(state, ui, now));
  const [beforeAgenda, agenda] = html.split('<div class="dashboard-calendar-agenda">');
  assert.match(beforeAgenda, /Submit camera-ready/);
  assert.doesNotMatch(agenda, /Submit camera-ready/, "task already shown in Today must not repeat in Calendar agenda");
  assert.match(agenda, /今日任务已显示在「今日」中/);

  // Selecting another date displays tasks on that day normally.
  const root = {id: "dashboard-view", ownerDocument: {getElementById: () => null}};
  app.mount(root, state, () => {}, assert.fail);
  root.onclick({target: {closest: () => ({dataset: {dashboardControl: "pick-day"}, value: "2026-11-28", closest: () => null})}});
  const picked = serialize(app.markup(state, ui, now));
  const [, pickedAgenda] = picked.split('<div class="dashboard-calendar-agenda">');
  assert.match(pickedAgenda, /Draft appendix/);
});
