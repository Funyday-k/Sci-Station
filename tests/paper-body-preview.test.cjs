const assert = require("node:assert/strict");
const test = require("node:test");
const {figureURL, figureRange, resolveImages} = require("../static/paper-body-preview.js");

test("paper image previews use only a current paper, fingerprint and indexed local asset", () => {
  const paper = "1".repeat(32), hash = "2".repeat(64), asset = "3".repeat(64);
  const source = "/api/research/papers/" + paper + "/body/figures/" + hash + "/" + asset;
  assert.equal(figureURL(paper, hash, asset), source);
  assert.equal(figureURL(paper, hash, "../remote.png"), "");
  assert.equal(figureURL(paper, "bad-fingerprint", asset), "");
  const resolve = resolveImages(paper, hash, [
    {reference:"images/二 a.png", assetId:asset},
    {reference:"https://example.invalid/image.png"},
    {reference:"images/absent.png"},
  ]);
  assert.equal(resolve("images/%E4%BA%8C%20a.png"), source);
  assert.equal(resolve("https://example.invalid/image.png"), undefined);
  assert.equal(resolve("images/absent.png"), undefined);
});

test("figure captions preserve original Unicode offsets in the selection field", () => {
  const source = {text:"😀 prefix\nFigure 1. 🔬 Study.", offset:19};
  const result = figureRange({citeStart:28,citeEnd:46}, source);
  assert.equal(source.text.slice(...result), "Figure 1. 🔬 Study.");
  assert.deepEqual(figureRange({citeStart:1,citeEnd:3}, {text:"😀图1"}), [2,4]);
  assert.equal(figureRange({citeStart:18,citeEnd:46}, source), null);
  assert.equal(figureRange({citeStart:28,citeEnd:47}, source), null);
});
