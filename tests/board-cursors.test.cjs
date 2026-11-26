const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const window = {};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, "..", "web", "static", "board-cursors.js"), "utf8"), {window});
const diff = (before, after, complete) => JSON.parse(JSON.stringify(window.RoundtableBoardCursors.diff(before, after, complete)));

test("a streamed prefix keeps the unwritten canonical suffix without marking a deletion", () => {
  assert.deepEqual(diff("先确认合同原件。", "先确认", false), [
    {kind:"same", text:"先确认"}, {kind:"tail", text:"合同原件。"},
  ]);
  assert.deepEqual(diff("旧材料。", "新", false), [
    {kind:"insert", text:"新"}, {kind:"tail", text:"旧材料。"},
  ]);
});

test("Chinese and joined emoji remain whole through independent insertions and replacements", () => {
  assert.deepEqual(diff("请保留👩‍🔬三处证据；结论😀。", "请保留👩‍🔬四处证据；暂缓结论😀。"), [
    {kind:"same", text:"请保留👩‍🔬"}, {kind:"delete", text:"三"}, {kind:"insert", text:"四"},
    {kind:"same", text:"处证据；"}, {kind:"insert", text:"暂缓"}, {kind:"same", text:"结论😀。"},
  ]);
  assert.deepEqual(diff("审阅👩‍🔬✅", "审阅🧑‍🔬✅"), [
    {kind:"same", text:"审阅"}, {kind:"delete", text:"👩‍🔬"}, {kind:"insert", text:"🧑‍🔬"}, {kind:"same", text:"✅"},
  ]);
});

test("a completed deletion marks the removed span at its location", () => {
  assert.deepEqual(diff("核对关键🔬材料。", "核对材料。"), [
    {kind:"same", text:"核对"}, {kind:"delete", text:"关键🔬"}, {kind:"same", text:"材料。"},
  ]);
});
