"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const lab = require("../web/static/lab-evidence.js");

function element(tag) {
  return {
    tag, textContent: "", childNodes: [],
    append(...nodes) { this.childNodes.push(...nodes); }
  };
}

function flat(nodes) {
  return nodes.flatMap(node => [node, ...flat(node.childNodes)]);
}

test("claim links are tied to the inspected output and changed sources retain their recorded quote", () => {
  const opened = [];
  global.document = {createElement: element};
  global.window = {SciEvidence: {href(project, evidence) {
    opened.push({project, evidence});
    return "/research?view=notes&note=fixture";
  }}};
  const source = {source: {offset: 0, end: 9}, sourceHash: "abc", quote: "原始内容 <span>"};
  const result = {
    claims: [{line: 2, text: "<script> never interpreted [S1] [S2] [S3]", status: "incomplete", references: ["S1", "S2", "S3"]}],
    sources: [
      {id: "S1", title: "Verified", status: "located", evidence: source},
      {id: "S2", title: "Changed", status: "stale", evidence: {...source, quote: "previous original"}}
    ]
  };
  const nodes = flat(lab.render({project: "project", prefix: "room-round-2"}, result));
  assert.deepEqual(nodes.filter(n => n.tag === "a").map(n => n.href), ["#room-round-2-S1", "#room-round-2-S2", "/research?view=notes&note=fixture"]);
  assert(nodes.some(n => n.textContent === "S3 · 此轮未找到来源"));
  assert(nodes.some(n => n.tag === "blockquote" && n.textContent === source.quote));
  assert(nodes.some(n => n.tag === "blockquote" && n.textContent === "previous original"));
  assert.equal(nodes.filter(n => n.tag === "script").length, 0);
  assert.deepEqual(opened, [{project: "project", evidence: source}]);
  assert.equal(lab.sourceLocation(source), "字符 1–9");
  assert.equal(lab.sourceLocation({page: 2, selectionStart: 0, selectionEnd: 3}), "第 2 页 · 页内位置 0–3");
});
