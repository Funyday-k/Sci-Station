"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

test("paper editor preserves invisible project and core memberships while updating visible choices", async () => {
  const visible = ["active-add", "active-remove", "active-core"];
  const selections = {
    'input[name="project_ids"]': visible,
    'input[name="project_ids"]:checked': ["active-add"],
    'input[name="core_project_ids"]:checked': ["active-core"],
  };
  const paper = {
    id: "paper",
    title: "Original",
    revision: 7,
    project_ids: ["archived", "archived-core", "active-remove"],
    core_project_ids: ["archived-core", "active-remove"],
  };
  paper.project_links = {
    archived: {is_pinned: true, use_for: ["hidden fixture"]},
    "active-core": {folder_path: "Background"},
  };
  const controls = {
    title: {value: "Revised"},
    "pinned-active-add": {checked: true},
    "order-active-add": {value: "0"},
    "folder-active-add": {value: "Theory"},
    "purpose-active-add": {value: "derive, compare"},
    "folder-active-core": {value: "Background"},
  };
  let rendered = "";
  let submit;
  let saved;
  const form = {
    dataset: {},
    querySelector: () => ({}),
    querySelectorAll: selector => selections[selector].map(value => ({value})),
    elements: {namedItem: name => (controls[name] || {value: ""})},
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
  const js = fs.readFileSync(path.join(__dirname, "..", "static", "research-forms.js"), "utf8");
  vm.runInNewContext(js, {window: {SciResearch: ui}});
  await ui.formAction("edit-paper", paper.id);
  assert.match(rendered, /name="order-active-add"/);
  assert.match(rendered, /name="folder-active-core" value="Background"/);
  await submit({preventDefault() {}});
  assert.equal(saved.url, "papers/paper");
  assert.equal(saved.method, "PUT");
  assert.equal(saved.body.title, "Revised");
  assert.equal(saved.body.revision, 7);
  assert.deepEqual(saved.body.project_links, {
    "active-add": {is_pinned: true, sort_order: 0, folder_path: "Theory", use_for: ["derive","compare"]},
    "active-core": {is_pinned: false, sort_order: null, folder_path: "Background", use_for: []},
  });
  assert.deepEqual(saved.body.project_ids.sort(), ["active-add", "active-core", "archived", "archived-core"]);
  assert.deepEqual(saved.body.core_project_ids.sort(), ["active-core", "archived-core"]);
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
    elements: {pdf: field("pdf"), fetch_pdf: field("fetch_pdf"), namedItem: field},
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
      assert.deepEqual(JSON.parse(options.body.get("metadata")), {tags:["research"],status:"unread",project_ids:["p1"],core_project_ids:[]});
      if (calls.length === 2) throw Error("PDF 暂时无法读取");
      return {title: name};
    }
  };
  const script = fs.readFileSync(path.join(__dirname, "..", "static", "research-forms.js"), "utf8");
  vm.runInNewContext(script, {window: {SciResearch: ui}, document: {createElement: () => ({})}, FormData: class extends Map { append(k, v) { this.set(k, v); } }});
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
  control("identifiers").value = "arXiv:2404.12345v2\nhttps://doi.org/10.1000/abc\narXiv:2404.12345v2";
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
  const script = fs.readFileSync(path.join(__dirname, "..", "static", "research-forms.js"), "utf8");
  vm.runInNewContext(script, {window: {SciResearch: ui}, document: {createElement: () => ({})}});
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
