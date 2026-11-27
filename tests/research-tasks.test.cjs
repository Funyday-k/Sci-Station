"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const navigation = require("../web/static/workspace-nav.js");
const {createTestDocument} = require("./lib/research-dom-fixture.cjs");

function researchUI() {
  const document = createTestDocument();
  const nodes = new Map();
  const element = id => {
    if (!nodes.has(id)) nodes.set(id, document.createElement("div"));
    return nodes.get(id);
  };
  Object.assign(document, {
    getElementById: id => id === "dashboard-view" ? null : element(id),
    querySelectorAll: () => [],
    addEventListener() {}
  });
  const context = {
    document,
    window: {
      SciStationNav: {...navigation, update() {}},
      RoundtableIcons: {iconNode: () => null},
      addEventListener() {}
    },
    location: new URL("http://localhost/research"),
    URL,
    URLSearchParams,
    FormData,
    fetch: () => new Promise(() => {}),
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../web/static/research.js"), "utf8"), context);
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
    title: 'Compare "water" <samples>',
    description: "Use <angle brackets> literally.",
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
  let submit, saved, dialogForm;
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
    dialog(_, content) { dialogForm = content; },
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
  const { loadESMInContext } = require("./lib/esm-vm-loader.cjs");
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "../web/static/research-evidence.js"), "utf8"), context);
  loadESMInContext("modules/research/entry.js", context);
  await ui.formAction("edit-task", "task");
  const descendants = node => [node, ...node.children.flatMap(descendants)];
  const nodes = descendants(dialogForm);
  assert.equal(dialogForm.localName, "form");
  const control = name => nodes.find(node => node.getAttribute("name") === name);
  assert.equal(control("title").getAttribute("value"), task.title);
  assert.equal(control("title").hasAttribute("required"), true);
  assert.equal(control("description").textContent, task.description);
  assert.equal(control("description").children.length, 0);
  assert.equal(control("dueTime").getAttribute("type"), "time");
  assert.deepEqual(control("status").children.filter(node => node.hasAttribute("selected"))
    .map(node => node.getAttribute("value")), ["open"]);
  const quote = nodes.find(node => node.localName === "blockquote");
  assert.equal(quote.textContent, "<excerpt>");
  assert.equal(quote.children.length, 0);
  const inputs = nodes.filter(node => node.getAttribute("name") === "taskTagNames");
  assert.deepEqual(inputs.map(node => [node.getAttribute("value"), node.hasAttribute("checked")]),
    [["comma, kept", true], ["review", false]]);
  const chip = inputs[1].parentNode.children.find(node => node.classList.contains("task-label"));
  assert.equal(chip.style.getPropertyValue("--task-label-bg"), "#AABBCC");
  assert.equal(chip.style.getPropertyValue("--task-label-fg"), "#123456");
  const readerLink = nodes.find(node => node.getAttribute("href")?.startsWith("/reader?")).getAttribute("href");
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
