"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const editor = require("../static/wiki-editor.js");

test("formats apply at the selected text without replacing the rest of a Wiki draft", () => {
  const source = "前言 Hidden result 之后";
  const start = source.indexOf("Hidden");
  const end = source.indexOf(" 之后");
  const result = editor.format(source, start, end, "bold");
  assert.equal(result.value, "前言 **Hidden result** 之后");
  assert.equal(result.caret, start + "**Hidden result**".length);
  assert.equal(editor.format(source, start, end, "invalid"), null);
});

test("longest snippet triggers insert at the caret and retain both sides of the draft", () => {
  const snippet = {trigger:";eq", body:"$$\n${cursor}\n$$"};
  const input = "证明 ;eq assumption";
  const out = editor.expand(input, "证明 ;eq".length, [{trigger:"eq", body:"wrong"}, snippet]);
  assert.equal(out.value, "证明 $$\n\n$$ assumption");
  assert.equal(out.caret, "证明 $$\n".length);
  assert.equal(editor.expand(input, input.length, [snippet]), null);
});

test("inserting an explicit snippet replaces the selected range and keeps the cursor marker out of the draft", () => {
  const out = editor.insert("Use placeholder today.", 4, 15, "## ${cursor}\n\n");
  assert.deepEqual(out, {value:"Use ## \n\n today.", caret:7});
});

test("inserting a table keeps any selected text as a preceding paragraph", () => {
  const out = editor.format("Scope", 0, 5, "table");
  assert.match(out.value, /^Scope\n\n\| Column \| Notes \|/);
});
