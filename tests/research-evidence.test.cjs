"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const evidence = require("../static/research-evidence.js");

test("Wiki and material citations keep their owning project and normalized offsets", () => {
  for (const [kind, view, key] of [["note", "notes", "note"], ["material", "materials", "material"]]) {
    const source = {kind, projectId: "original", id: "record", offset: 0, end: 4};
    const href = new URL(evidence.href("destination", {source, sourceHash: "fingerprint"}), "http://localhost");
    assert.equal(href.pathname, "/research");
    assert.equal(href.searchParams.get("project"), source.projectId);
    assert.equal(href.searchParams.get("view"), view);
    assert.equal(href.searchParams.get(key), source.id);
    assert.deepEqual(evidence.locator(href.searchParams), {fingerprint:"fingerprint", offset:"0", end:"4"});
  }
  assert.equal(evidence.locator(new URLSearchParams("note=ordinary")), null);
});

test("legacy PDF citations keep page, fingerprint and UTF-16 selection", () => {
  const href = new URL(evidence.href("project", {paperId:"paper",page:2,sourceHash:"pdf",quote:"😀 sample",
    selectionStart:0,selectionEnd:9,ocr:true,annotationId:"original"}), "http://localhost");
  assert.equal(href.pathname, "/reader");
  assert.deepEqual(Object.fromEntries(href.searchParams), {
    project:"project",paper:"paper",page:"2",fingerprint:"pdf",quote:"😀 sample",start:"0",end:"9",ocr:"1",annotation:"original"
  });
});
