"use strict";
const assert = require("node:assert/strict");
const {test} = require("node:test");
const {readFileSync} = require("node:fs");
const vm = require("node:vm");

test("reasoning slider maps indexes to advertised model values when models change", () => {
  const events = {}, window = {addEventListener() {}};
  const input = {
    id:"effort", dataset:{},
    addEventListener(name, fn) { events[name] = fn; },
    setAttribute(key, value) { this[key] = value; }
  };
  const output = {setAttribute(key, value) { this[key] = value; }};
  vm.runInNewContext(readFileSync(require.resolve("../web/static/model-effort.js"), "utf8"), {window});
  const changes = [];
  const control = window.SciModelEffort.bind(input, output, value => changes.push(value));
  assert.equal(control.value, "");
  assert.equal(input.disabled, true);
  assert.equal(output.for, "effort");
  assert.equal(control.setOptions(["high", "auto", "low", "high"], "high"), "high");
  assert.equal(input.max, "2");
  assert.equal(input.value, "2");
  input.value = "1";
  events.input();
  assert.deepEqual(changes, ["low"]);
  assert.equal(input["aria-valuetext"], "低");
  assert.equal(control.setOptions(["medium"], "low"), "medium");
  assert.equal(input.disabled, true);
  assert.deepEqual(changes, ["low"]);
  control.setDisabled(true);
  control.setOptions(["auto","high"], "");
  assert.equal(input.disabled, true);
  control.setDisabled(false);
  assert.equal(input.disabled, false);
  assert.equal(control.setOptions(["vendor-tier"], "high"), "vendor-tier");
  assert.equal(output.textContent, "vendor-tier");
});
