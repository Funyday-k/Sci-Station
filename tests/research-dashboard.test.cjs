"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");
const dashboard = require("../web/static/research-dashboard.js");

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
    {id: "2", title: "Pending beta", status: "pending", projectId: "b", meetingId: "m2"},
    {id: "3", title: "Rejected note", status: "rejected", projectId: "a", meetingId: "m1"},
  ];
  const request = async url => ({"/api/workspace": {id: "root-one", name: "Workspace One"}, "dashboard/projects": facts, reviews,
    "dashboard/projects?project=a": {a: facts.a},
    "projects/a/reviews": reviews.filter(r => r.projectId === "a")})[url];
  const ui = {
    esc: String, heading: (title, info, buttons) => `<h1>${title}</h1>${info}${buttons}`, button: String,
    link: (label, href) => `<a href="${href}">${label}</a>`, panel: (title, body) => `<h2>${title}</h2>${body}`,
    paperRows: () => "", taskRows: () => "", meetingRows: () => "", viewURL: require("../web/static/workspace-nav.js").research, studio: String, fmtDate: String,
    row: (_glyph, title, _meta, control) => `${title} ${control}`, rowAction: String, list: rows => rows.join(""),
    empty: String, reader: String, toolsPage: String
  };
  let app = browser();
  state.dashboardData = await app.load(request);
  const now = new Date(2026, 10, 25);
  const first = app.markup(state, ui, now);
  const widgets = html => Array.from(html.matchAll(/class="dashboard-widget dashboard-(\w+)" data-dashboard-widget="(\w+)"/g),
    ([, size, id]) => [id, size]);
  assert.match(first, /class="dashboard-grid dashboard-home-grid"/);
  assert.deepEqual(widgets(first).slice(0, 4), [["today", "medium"], ["active_projects", "medium"], ["ai_review", "medium"], ["calendar", "large"]]);
  const [month, agenda] = first.split('<div class="dashboard-calendar-agenda">');
  assert.match(month, /class="dashboard-calendar-month">.*data-dashboard-control="next-month".*class="dashboard-month">/s);
  assert.match(agenda, /class="dashboard-calendar-links"><a href="\/research\?view=tasks&tab=calendar">打开日历<\/a>/);
  assert.match(first, /<h1>首页<\/h1>/);
  assert.match(first, /<b>2<\/b> 项待审核/);
  assert.match(first, /Pending beta/);
  assert.doesNotMatch(first, /Rejected note/);

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
  assert.doesNotMatch(app.markup(state, ui, now), /data-dashboard-widget="calendar"/);
  app = browser();
  const saved = app.markup(state, ui, now);
  assert.deepEqual(widgets(saved).slice(0, 3), [["today", "medium"], ["ai_review", "wide"], ["active_projects", "medium"]]);
  assert.doesNotMatch(saved, /data-dashboard-widget="calendar"/);

  state.dashboardData = {...state.dashboardData, workspace: {id: "root-two"}, modules: {modules: [{id: "paper-library", effective: false}]}};
  const second = app.markup(state, ui, now);
  assert.match(second, /data-dashboard-widget="calendar"/);
  assert.deepEqual(widgets(second).slice(0, 3), widgets(first).slice(0, 3));
  assert.doesNotMatch(second, /data-dashboard-widget="recent_papers"/);

  state.project = alpha;
  state.dashboardData = await app.load(request, alpha.id);
  const overview = app.markup(state, ui, now);
  assert.match(overview, /class="dashboard-grid"/);
  assert.deepEqual(widgets(overview).slice(0, 3), [["project_status", "small"], ["research_questions", "small"], ["project_brief", "medium"]]);
  assert.match(overview, /data-stage="drafting"/);
  assert.match(overview, /<b>1<\/b> 项待审核/);
  assert.doesNotMatch(overview, /Pending beta/);

  const failure = async path => {
    if (path.startsWith("dashboard/projects") || path.endsWith("reviews")) throw new Error("Unavailable fixture");
    return request(path);
  };
  state.dashboardData = await app.load(failure, alpha.id);
  const unavailableOverview = app.markup(state, ui, now);
  assert.match(unavailableOverview, /部分数据加载失败.*项目统计、审核队列/s);
  assert.match(unavailableOverview, /无法读取审核活动/);
  assert.doesNotMatch(unavailableOverview, /暂无近期活动/);

  state.project = undefined;
  state.dashboardData = await app.load(failure);
  const unavailableHome = app.markup(state, ui, now);
  assert.match(unavailableHome, /部分数据加载失败.*项目统计、审核队列/s);
  assert.match(unavailableHome, /暂时无法读取审核队列/);
  assert.doesNotMatch(unavailableHome, /暂无待审核草稿/);

  state.dashboardData = await app.load(path => path === "reviews" ? Promise.resolve([]) : request(path));
  assert.match(app.markup(state, ui, now), /暂无待审核草稿/);
  await assert.rejects(app.load(async path => {
    if (path === "/api/workspace") throw new Error("Workspace fixture unavailable");
    return request(path);
  }), /Workspace fixture unavailable/);
});
