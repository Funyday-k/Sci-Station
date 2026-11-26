"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const navigation = require("../static/workspace-nav.js");

function researchUI() {
  const nodes = new Map();
  const element = id => {
    if (!nodes.has(id)) nodes.set(id, {
      addEventListener() {},
      setAttribute() {},
      classList: {
        toggle() {},
        add() {},
        remove() {}
      },
      dataset: {}
    });
    return nodes.get(id);
  };
  const context = {
    document: {
      getElementById: id => id === "dashboard-view" ? null : element(id),
      querySelectorAll: () => [],
      addEventListener() {}
    },
    window: {
      SciStationNav: {...navigation, update() {}},
      RoundtableIcons: {
        icon: () => ""
      },
      addEventListener() {}
    },
    location: new URL("http://localhost/research"),
    URL,
    URLSearchParams,
    FormData,
    fetch: () => new Promise(() => {}),
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../static/research.js"), "utf8"), context);
  return {
    ui: context.window.SciResearch,
    element,
    context
  };
}

test("project calendar includes each day of a reading range and shows local due time on the final day", () => {
  const {
    ui,
    element
  } = researchUI();
  const task = {
    id: "sample",
    title: "Compare papers",
    startDate: "2026-11-30",
    dueDate: "2026-12-02",
    dueTime: "08:15",
    status: "inProgress"
  };
  const project = {
    id: "proj",
    name: "Project"
  };
  Object.assign(ui.state, {
    view: "tasks",
    calendar: true,
    projects: [project],
    project,
    tasks: [task],
    month: new Date(2026, 11, 1)
  });
  assert.equal(ui.taskOnDate(task, "2026-11-29"), false);
  assert.equal(ui.taskOnDate(task, "2026-11-30"), true);
  assert.equal(ui.taskOnDate(task, "2026-12-01"), true);
  assert.equal(ui.taskOnDate(task, "2026-12-02"), true);
  assert.equal(ui.taskOnDate(task, "2026-12-03"), false);
  ui.render();
  assert.equal((element("main").innerHTML.match(/data-id="sample"/g) || []).length, 2);
  assert.match(element("main").innerHTML, /08:15 Compare papers/);
});

test("task editor preserves archived project membership, multiple papers and revision", async () => {
  const {
    ui,
    context
  } = researchUI();
  const task = {
    id: "task",
    projectId: "visible",
    projectIds: ["visible", "archived"],
    title: "Original",
    revision: 7,
    status: "open",
    tags: ["comma, kept"],
    evidence: [{paperId: "p1", page: 2, quote: "<excerpt>", sourceHash: "hash", selectionStart: 0, selectionEnd: 9}]
  };
  const selections = {
    projectIds: ["visible", "added"],
    relatedPaperIds: ["p1", "p2"],
    taskTagNames: ["comma, kept", "review"]
  };
  const values = {
    title: "Edited",
    kind: "reading",
    priority: "high",
    status: "inProgress",
    tags: "alpha，beta",
    startDate: "2026-11-30",
    dueDate: "2026-12-02",
    dueTime: "14:30"
  };
  let submit, saved, dialogHTML;
  const form = {
    dataset: {},
    querySelector: () => ({}),
    querySelectorAll: selector => (selections[selector.match(/name="([^"]+)"/)[1]] || []).map(value => ({value})),
    elements: {namedItem: name => ({value: values[name] || ""})},
    addEventListener(_, fn) {
      submit = fn;
    },
    reportValidity: () => true
  };
  const project = {
    id: "visible",
    name: "Owner"
  };
  Object.assign(ui.state, {
    tasks: [task],
    taskCatalog: {revision: 1, tags: [{name: "review", definition: {color: "#AABBCC", textColor: "#123456"}}]},
    project,
    projects: [project, {
      id: "added",
      name: "Added"
    }],
    papers: [{
      id: "p1",
      title: "A"
    }, {
      id: "p2",
      title: "B"
    }]
  });
  Object.assign(ui, {
    $: () => ({
      querySelector: () => form
    }),
    dialog(_, html) { dialogHTML = html; },
    close() {},
    toast() {},
    refresh: async () => {},
    request: async (route, init) => {
      saved = {
        route,
        body: JSON.parse(JSON.stringify(init.body))
      };
    }
  });
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../static/research-evidence.js"), "utf8"), context);
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../static/research-forms.js"), "utf8"), context);
  await ui.formAction("edit-task", "task");
  assert.match(dialogHTML, /<blockquote>&lt;excerpt&gt;<\/blockquote>/);
  assert.match(dialogHTML, /name="taskTagNames" value="comma, kept" checked/);
  assert.match(dialogHTML, /name="taskTagNames" value="review"[^]*--task-label-bg:#AABBCC;--task-label-fg:#123456/);
  const readerLink = dialogHTML.match(/href="(\/reader\?[^"]+)"/)[1].replaceAll("&amp;", "&");
  const params = new URL(readerLink, "http://localhost").searchParams;
  for (const [key, value] of Object.entries({paper: "p1", project: "visible", page: "2", fingerprint: "hash", start: "0", end: "9"})) {
    assert.equal(params.get(key), value);
  }
  await submit({
    preventDefault() {}
  });
  assert.equal(saved.route, "projects/visible/tasks/task");
  assert.deepEqual(saved.body.projectIds, ["visible", "added", "archived"]);
  assert.deepEqual(saved.body.relatedPaperIds, ["p1", "p2"]);
  assert.deepEqual(saved.body.tags, ["comma, kept", "review", "alpha", "beta"]);
  assert.equal(saved.body.revision, 7);
  assert.equal(saved.body.dueTime, "14:30");
});
