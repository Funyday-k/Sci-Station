const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const script = readFileSync(join(__dirname, "../static/meeting-materials.js"), "utf8");

class Element extends EventTarget {
  dataset = {};
  children = [];
  classList = { add() {} };
  setAttribute() {}
  contains() { return false; }
  append(...children) { this.children.push(...children); }
  prepend(child) { this.children.unshift(child); child.isConnected = true; }
  replaceChildren() { this.children = []; }
  remove() { this.isConnected = false; }
}

function setup() {
  const requests = [];
  const errors = [];
  const window = {};
  vm.runInNewContext(script, {
    window, AbortController, FormData,
    document: { createElement: () => new Element() },
    fetch: async (url, request) => {
      const file = request.body.get("file");
      requests.push([url, request.headers["X-Roundtable"], file]);
      return {ok: true, json: async () => ({id: file.name, name: file.name, mime: file.type, size: file.size})};
    },
  });
  const target = new Element();
  const materials = window.RoundtableMaterials.mount({root: new Element(), pasteTarget: target, onError: error => errors.push(error)});
  return {target, materials, requests, errors};
}

function paste(target, {files = [], items = [], text = "", types = []} = {}) {
  const event = new Event("paste", {cancelable: true});
  event.clipboardData = {files, items, types, getData: type => type === "text/plain" ? text : ""};
  return target.dispatchEvent(event);
}

test("file paste uploads once when both clipboard representations are present", async () => {
  const {target, materials, requests} = setup();
  const original = new File(["local bytes"], "sample.txt", {type: "text/plain"});
  const alternate = {kind: "file", getAsFile: () => assert.fail("file items duplicate the file list")};
  assert.equal(paste(target, {files: [original, original], items: [alternate]}), false);
  assert.equal(materials.busy(), true);
  assert.equal(requests.length, 1);
  const [url, header, uploaded] = requests[0];
  assert.equal(url, "/api/studio/materials");
  assert.equal(header, "1");
  assert.equal(uploaded.name, original.name);
  assert.equal(await uploaded.text(), "local bytes");
});

test("plain and mixed clipboard pastes retain native text insertion", () => {
  const {target, requests} = setup();
  const image = new File(["image bytes"], "pasted.png", {type: "image/png"});
  const item = {kind: "file", getAsFile: () => image};
  assert.equal(paste(target, {text: "pasted text", types: ["text/plain"]}), true);
  assert.equal(requests.length, 0);
  assert.equal(paste(target, {items: [item], text: "caption", types: ["Files", "text/plain"]}), true);
  assert.equal(paste(target, {files: [image], types: ["Files", "text/html"]}), true);
  assert.deepEqual(requests.map(([, , file]) => file.name), ["pasted.png", "pasted.png"]);
});

test("paste respects the attachment size limit and composer lock", () => {
  const {target, materials, requests, errors} = setup();
  const original = new File(["ok"], "sample.txt");
  const large = {name: "too-large.bin", size: 12 * 1024 * 1024 + 1};
  materials.setDisabled(true);
  assert.equal(paste(target, {files: [original]}), true);
  materials.setDisabled(false);
  target.readOnly = true;
  assert.equal(paste(target, {files: [original]}), true);
  target.readOnly = false;
  assert.equal(paste(target, {files: [large]}), false);
  assert.equal(requests.length, 0);
  assert.match(errors[0], /12 MiB/);
  materials.set(Array.from({length: 12}, (_, i) => ({id: `file-${i}`})));
  assert.equal(paste(target, {files: [original]}), false);
  assert.equal(requests.length, 0);
  assert.match(errors[1], /12 件/);
});
