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
  let submit;
  let saved;
  const form = {
    dataset: {},
    querySelector: () => ({}),
    querySelectorAll: selector => selections[selector].map(value => ({value})),
    elements: {namedItem: name => ({value: name === "title" ? "Revised" : ""})},
    addEventListener: (event, handler) => { if (event === "submit") submit = handler; },
    reportValidity: () => true,
  };
  const ui = {
    state: {projects: visible.map(id => ({id, name: id})), papers: [paper]},
    $: () => ({querySelector: () => form}),
    esc: String,
    enc: encodeURIComponent,
    button: () => "",
    dialog() {},
    close() {},
    toast() {},
    refresh: async () => {},
    request: async (url, init) => { saved = {url, method: init.method, body: JSON.parse(JSON.stringify(init.body))}; },
  };
  const js = fs.readFileSync(path.join(__dirname, "..", "static", "research-forms.js"), "utf8");
  vm.runInNewContext(js, {window: {SciResearch: ui}});
  await ui.formAction("edit-paper", paper.id);
  await submit({preventDefault() {}});
  assert.equal(saved.url, "papers/paper");
  assert.equal(saved.method, "PUT");
  assert.equal(saved.body.title, "Revised");
  assert.equal(saved.body.revision, 7);
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
