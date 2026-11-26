"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function loadLibrary(ui, globals = {}) {
  ui.state.organization ||= {revision: 0, collections: {}, tags: {}};
  ui.start = () => {};
  ui.statusLabel = {unread: "Unread", reading: "Reading", read: "Read"};
  const ctx = vm.createContext({
    window: {SciResearch: ui, addEventListener() {}},
    document: {addEventListener() {}, createElement: () => ({})},
    ...globals
  });
  for (const file of ["research-forms.js", "research-library.js"]) {
    vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "web", "static", file), "utf8"), ctx);
  }
}

test("Space previews the selected local PDF and preserves input, checkbox, dialog and Reader behavior", () => {
  const papers = [
    {id: "metadata", title: "Metadata only"},
    {id: "local", title: "Local PDF", has_pdf: true},
  ];
  const documentEvents = {}, windowEvents = {};
  const requests = [], destinations = [];
  let dialogOpen = false;
  const ui = {
    state: {view: "papers", query: "", papers},
    enc: encodeURIComponent,
    reader: id => "/reader?paper=" + id,
    render() {},
    toast: assert.fail,
    async request(url, {method, body}) {
      requests.push([url, method, body.action]);
    },
  };
  loadLibrary(ui, {
    window: {SciResearch: ui, addEventListener: (type, handler) => { windowEvents[type] = handler; }},
    document: {
      addEventListener: (type, handler) => { documentEvents[type] = handler; },
      querySelector: selector => selector === "dialog[open]" && dialogOpen ? {} : null,
    },
    location: {assign: url => destinations.push(url)},
  });
  ui.library.filterPapers(papers, "");
  const select = (id, checked) => documentEvents.change({target: {checked, dataset: {librarySelection: id}}});
  select("metadata", true);
  select("local", true);

  const space = target => {
    const event = {key: " ", target, preventDefault() { this.defaultPrevented = true; }};
    documentEvents.keydown(event);
    return Boolean(event.defaultPrevented);
  };
  const body = {closest: () => null};
  const input = {closest: selectors => selectors.split(",").includes("input") ? {} : null};
  assert.equal(space(input), false, "search and checkbox retain the browser's Space behavior");
  dialogOpen = true;
  assert.equal(space(body), false, "a non-input target in an open dialog is still protected");
  dialogOpen = false;
  assert.deepEqual(requests, []);
  assert.equal(space(body), true);
  assert.deepEqual(requests, [["papers/local/native-file", "POST", "open"]]);
  assert.deepEqual(destinations, []);

  select("metadata", false);
  windowEvents["scistation:command"]({detail: "reader", preventDefault() {}});
  assert.deepEqual(destinations, ["/reader?paper=local"]);
  assert.equal(requests.length, 1);
});

test("the native paper removal command acts on the current library scope", () => {
  const paper = {id: "paper", title: "Shared paper", project_ids: ["selected-project"]};
  const documentEvents = {}, windowEvents = {}, actions = [];
  const ui = {state: {view: "papers", query: "", papers: [paper]}, render() {}, toast: assert.fail};
  loadLibrary(ui, {
    window: {SciResearch: ui, addEventListener: (type, handler) => { windowEvents[type] = handler; }},
    document: {addEventListener: (type, handler) => { documentEvents[type] = handler; }, querySelector: () => null},
  });
  ui.formAction = (action, id) => actions.push([action, id]);
  function removeSelection(project) {
    ui.state.project = project;
    ui.library.filterPapers([paper], project?.id || "");
    documentEvents.change({target: {checked: true, dataset: {librarySelection: paper.id}}});
    windowEvents["scistation:command"]({detail: "deletePaper", preventDefault() {}});
  }
  removeSelection({id: "selected-project"});
  removeSelection(null);
  assert.deepEqual(actions, [["confirm-paper-unlink", paper.id], ["confirm-delete", "paper:" + paper.id]]);
});

test("paper editor preserves invisible project and core memberships while updating visible choices", async () => {
  const visible = ["active-add", "active-remove", "active-core"];
  const choices = (name, defaults) => visible.map(value => ({
    type: "checkbox", name, value, checked: defaults.includes(value), defaultChecked: defaults.includes(value)
  }));
  const members = choices("project_ids", ["active-remove", "active-core"]);
  const core = choices("core_project_ids", ["active-remove"]);
  const paper = {
    id: "paper",
    title: "Original",
    revision: 7,
    project_ids: ["archived", "archived-core", "active-remove", "active-core"],
    core_project_ids: ["archived-core", "active-remove"],
  };
  paper.project_links = {
    archived: {is_pinned: true, use_for: ["hidden fixture"]},
    "active-core": {folder_path: "Background"},
  };
  const controls = {
    title: {value: "Original"},
    authors: {value: "de Vries, Ana\nEmi Ng"},
    tags: {value: ""},
    "pinned-active-add": {type: "checkbox", checked: false},
    "order-active-add": {value: ""},
    "folder-active-add": {value: ""},
    "purpose-active-add": {value: ""},
    "folder-active-core": {value: "Background"},
  };
  const libraryFields = ["doi", "arxiv", "url", "collection_id", "abstract", "year", "status", "citekey",
    "rating", "priority", "references", "publication_title", "publisher", "volume", "issue", "pages", "item_type", "categories", "bibtex"];
  for (const name of libraryFields) controls[name] = {value: ""};
  const elements = Object.entries(controls).map(([name, element]) => Object.assign(element, {name}));
  elements.namedItem = name => controls[name];
  let rendered = "";
  let submit;
  let saved;
  const form = {
    dataset: {},
    querySelector: () => ({}),
    querySelectorAll: selector => {
      const rows = selector.includes("core_project_ids") ? core : members;
      return selector.endsWith(":checked") ? rows.filter(row => row.checked) : rows;
    },
    elements,
    addEventListener: (event, handler) => { if (event === "submit") submit = handler; },
    reportValidity: () => true,
  };
  const ui = {
    state: {projects: visible.map(id => ({id, name: id})), papers: [paper]},
    $: () => ({querySelector: () => form}),
    esc: String,
    enc: encodeURIComponent,
    button: () => "",
    dialog(title, html) { rendered = html; },
    close() {},
    toast() {},
    refresh: async () => {},
    request: async (url, init) => { saved = {url, method: init.method, body: JSON.parse(JSON.stringify(init.body))}; },
  };
  loadLibrary(ui);
  await ui.formAction("edit-paper", paper.id);
  assert.match(rendered, /name="order-active-add"/);
  assert.match(rendered, /name="folder-active-core" value="Background"/);
  assert.match(rendered, /<textarea name="references"/);
  controls.title.value = "Revised";
  controls.references.value = "Exact title, with a comma\n10.1000/method\n10.1000/method";
  controls.tags.value = "nuclear, solar\nreading";
  controls.references.value = "Exact title, with a comma\n10.1000/method\n10.1000/method";
  controls["pinned-active-add"].checked = true;
  controls["order-active-add"].value = "0";
  controls["folder-active-add"].value = "Theory";
  controls["purpose-active-add"].value = "derive, compare";
  members[0].checked = core[2].checked = true;
  members[1].checked = core[1].checked = false;
  await submit({preventDefault() {}});
  assert.equal(saved.url, "papers/paper");
  assert.equal(saved.method, "PATCH");
  assert.equal(saved.body.title, "Revised");
  assert.equal(saved.body.revision, 7);
  assert.deepEqual(saved.body.references, ["Exact title, with a comma", "10.1000/method", "10.1000/method"]);
  assert.deepEqual(saved.body.project_links, {
    "active-add": {is_pinned: true, sort_order: 0, folder_path: "Theory", use_for: ["derive","compare"]},
  });
  assert.equal(Object.hasOwn(saved.body, "authors"), false);
  assert.deepEqual(saved.body.tags, ["nuclear, solar", "reading"]);
  assert.deepEqual(saved.body.project_ids.sort(), ["active-add", "active-core", "archived", "archived-core"]);
  assert.deepEqual(saved.body.core_project_ids.sort(), ["active-core", "archived-core"]);
});

test("metadata retries an unrelated revision and keeps the draft in a same-field conflict", async () => {
  const original = {revision: 2, title: "Original", notes: "A", project_ids: ["one", "two"],
    project_links: {one: {is_pinned: true}, two: {folder_path: "original"}}};
  const current = {...original, revision: 3, notes: "A concurrent note"};
  const error = Object.assign(Error("conflict"), {status: 409});
  const writes = [];
  const ui = {
    state: {},
    request: async (url, options) => {
      assert.equal(url, "papers/one");
      if (!options) return current;
      writes.push(JSON.parse(JSON.stringify(options.body)));
      if (options.body.revision !== current.revision) throw error;
      return {...current, ...options.body};
    }
  };
  loadLibrary(ui);
  const draft = {revision: 2, title: "My draft"};
  const saved = await ui.library.saveMetadata("papers/one", original, draft);
  assert.deepEqual(writes, [draft, {...draft, revision: 3}]);
  assert.equal(saved.notes, "A concurrent note");
  assert.equal(draft.revision, 2);
  current.title = "Another title";
  writes.length = 0;
  await assert.rejects(ui.library.saveMetadata("papers/one", original, draft), /草稿仍保留/);
  assert.deepEqual(writes, [draft]);
});

test("collection descendants and an exact tag filter compose without changing paper order", () => {
  const ui = {
    state: {query: "Solar", libraryCollection: "parent", libraryTag: "local", organization: {
      collections: {parent: {name: "Physics"}, child: {name: "Solar", parent_id: "parent"}},
      tags: {}
    }}
  };
  loadLibrary(ui);
  const included = {title: "Solar capture", collection_id: "child", tags: ["local"]};
  const rows = [included, {title: "Solar theory", collection_id: "child", tags: ["locality"]},
    {title: "Solar source", tags: ["local"]}, {title: "Other topic", collection_id: "parent", tags: ["local"]}];
  assert.equal(ui.library.collectionPath("child"), "Physics / Solar");
  assert.equal(ui.library.filterPapers(rows, "project").length, 1);
  assert.equal(ui.library.filterPapers(rows, "project")[0], included);
});

test("bulk library changes preserve unedited classifications and avoid rewriting unchanged records", () => {
  const ui = {state: {}};
  loadLibrary(ui);
  const paper = {tags:["keep", "old"], collection_id:"existing", status:"reading", priority:3, rating:5};
  const edit = {tags: ["keep", "add"], collection_id:"", rating:0};
  const result = ui.library.bulkPatch(paper, {addTags:["keep", "add"], removeTags:["old"], collection_id:"", status:"reading", rating:0});
  assert.deepEqual(JSON.parse(JSON.stringify(result)), edit);
  assert.equal(Object.keys(ui.library.bulkPatch(paper, {addTags:[], removeTags:[]})).length, 0);
  assert.deepEqual(paper.tags, ["keep", "old"]);
});

test("batch PDF import retries only failed files and inherits shared properties", async () => {
  const files = [{name: "first.pdf"}, {name: "retry.pdf"}];
  const fields = new Map();
  const field = name => {
    if (!fields.has(name)) fields.set(name, {value: "", addEventListener() {}});
    return fields.get(name);
  };
  field("pdf").files = files;
  field("title").value = "Do not apply this title to multiple PDFs";
  field("tags").value = "research";
  field("status").value = "unread";
  let submit, closed = false, resultItems;
  const status = {}, submitButton = {};
  const form = {
    dataset: {},
    elements: {pdf: field("pdf"), fetch_pdf: field("fetch_pdf"), namedItem: field, *[Symbol.iterator]() {}},
    querySelector: selector => {
      if (selector === "[data-import-results]") return {replaceChildren(...items) { resultItems = items.map(i => i.textContent); }};
      if (selector === "[data-status]") return status;
      if (selector === "[type=submit]") return submitButton;
      return {};
    },
    querySelectorAll: selector => selector.includes("core_project_ids") ? [] : [{value: "p1"}],
    addEventListener(event, handler) { if (event === "submit") submit = handler; },
    closest: () => ({open: !closed}),
    reportValidity: () => true
  };
  const calls = [];
  const ui = {
    state: {projects: [], papers: []}, $: () => ({querySelector: () => form}),
    esc: String, enc: encodeURIComponent, button: () => "", dialog() {}, toast() {},
    close: () => {closed = true;}, refresh: async () => {},
    request: async (url, options) => {
      const name = options.body.get("file").name;
      calls.push(name);
      assert.deepEqual(JSON.parse(options.body.get("metadata")), {tags:["research"],status:"unread",collection_id:"",project_ids:["p1"],core_project_ids:[]});
      if (calls.length === 2) throw Error("PDF 暂时无法读取");
      return {title: name};
    }
  };
  loadLibrary(ui, {FormData: class extends Map { append(k, v) { this.set(k, v); } }});
  await ui.formAction("new-paper");
  await submit({preventDefault() {}});
  assert.deepEqual(calls, ["first.pdf", "retry.pdf"]);
  assert.deepEqual(resultItems, ["first.pdf · 已入库 · first.pdf", "retry.pdf · PDF 暂时无法读取"]);
  assert.equal(submitButton.textContent, "重试未成功的文件");
  await submit({preventDefault() {}});
  assert.deepEqual(calls, ["first.pdf", "retry.pdf", "retry.pdf"]);
  assert.equal(status.textContent, "已入库 2 / 2");
  await submit({preventDefault() {}});
  assert.equal(calls.length, 3);
  assert.equal(closed, true);
});

test("identifier import previews the first target and retries only failed targets", async () => {
  const inputs = new Map();
  const control = name => {
    if (!inputs.has(name)) inputs.set(name, {value: "", addEventListener() {}});
    return inputs.get(name);
  };
  control("identifiers").value = "arXiv 2404.12345v2, https://doi.org/10.1000/abc; arXiv:2404.12345v2";
  control("pdf").files = [];
  control("collection_id").value = "chosen-collection";
  const controls = new Map();
  const getElement = selector => {
    if (!controls.has(selector)) controls.set(selector, {replaceChildren() {}, addEventListener(event, fn) { this[event] = fn; }});
    return controls.get(selector);
  };
  let submit;
  const form = {
    dataset: {},
    elements: {pdf: control("pdf"), fetch_pdf: control("fetch_pdf"), namedItem: control},
    querySelector: getElement,
    querySelectorAll: selector => selector.includes("core_project_ids") ? [] : [{value: "project-one"}],
    addEventListener(event, fn) { if (event === "submit") submit = fn; },
    closest: () => ({open: true}),
    reportValidity: () => true,
  };
  const calls = [];
  const ui = {
    state: {projects: [], papers: []}, $: () => ({querySelector: () => form}),
    esc: String, enc: encodeURIComponent, button: () => "", dialog() {}, toast() {},
    close() {}, refresh: async () => {},
    request: async (url, {body}) => {
      calls.push([url, body.identifier]);
      assert.equal(body.skip_metadata_lookup, true);
      assert.equal(body.collection_id, "chosen-collection");
      assert.equal(body.project_ids[0], "project-one");
      if (url === "papers/preview") return {title: "First source", existing_title: "Saved source"};
      if (calls.length === 3) throw Error("远端暂时不可用");
      return {title: body.identifier};
    }
  };
  loadLibrary(ui);
  await ui.formAction("new-paper");
  await getElement("[data-import-preview-button]").click();
  assert.match(getElement("[data-import-preview]").textContent, /First source.*Saved source.*2 篇/);
  await submit({preventDefault() {}});
  assert.equal(getElement("[type=submit]").textContent, "重试未成功的标识符");
  await submit({preventDefault() {}});
  assert.deepEqual(calls, [
    ["papers/preview", "arXiv:2404.12345v2"],
    ["papers", "arXiv:2404.12345v2"],
    ["papers", "https://doi.org/10.1000/abc"],
    ["papers", "https://doi.org/10.1000/abc"],
  ]);
  assert.equal(getElement("[data-status]").textContent, "已入库 2 / 2");
});
