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
