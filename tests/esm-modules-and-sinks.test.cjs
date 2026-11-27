"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const { loadESMInContext } = require("./lib/esm-vm-loader.cjs");

const STATIC_DIR = path.join(__dirname, "..", "web", "static");
const readStatic = (rel) => fs.readFileSync(path.join(STATIC_DIR, rel), "utf8");

function makeDomEnv() {
  const created = [];
  function makeNode(tagName) {
    const attrs = new Map();
    const styleProps = new Map();
    const node = {
      tagName: String(tagName || "").toUpperCase(),
      className: "",
      textContent: "",
      value: "",
      hidden: false,
      open: false,
      readOnly: false,
      isConnected: true,
      dataset: {},
      children: [],
      style: {
        setProperty(name, value) {
          styleProps.set(name, value);
        },
        getPropertyValue(name) {
          return styleProps.get(name) || "";
        },
      },
      setAttribute(name, value) {
        attrs.set(name, String(value));
      },
      classList: { toggle() {} },
      addEventListener() {},
      removeAttribute(name) { attrs.delete(name); },
      getAttribute(name) {
        return attrs.get(name) ?? null;
      },
      append(...items) {
        for (const item of items) {
          if (item && item.tagName === "#FRAGMENT") this.children.push(...item.children);
          else this.children.push(item);
        }
      },
      replaceChildren(...items) {
        this.children = [];
        this.append(...items);
      },
      replaceWith(...items) {
        this.replacedWith = items;
      },
      querySelector(selector) {
        const cls = selector.startsWith(".") ? selector.slice(1) : null;
        const queue = [...this.children];
        while (queue.length) {
          const cur = queue.shift();
          if (!cur || typeof cur !== "object") continue;
          if (cls && String(cur.className || "").split(/\s+/).includes(cls)) return cur;
          if (!cls && cur.tagName === selector.toUpperCase()) return cur;
          if (Array.isArray(cur.children)) queue.push(...cur.children);
        }
        return null;
      },
      focus() {
        this.focused = true;
      },
    };
    created.push(node);
    return node;
  }

  const document = {
    createElement: (tag) => makeNode(tag),
    createElementNS: (_ns, tag) => makeNode(tag),
    createTextNode: (text) => ({ nodeType: 3, textContent: String(text) }),
    createDocumentFragment: () => makeNode("#FRAGMENT"),
  };
  const window = { RoundtableIcons: { iconNode: (name) => makeNode(`svg-${name}`) } };
  return { document, window, created, makeNode };
}

function collectText(node) {
  if (!node) return "";
  if (node.nodeType === 3) return node.textContent;
  const own = node.textContent || node.value || "";
  const childText = (node.children || []).map(collectText).join("");
  return own + childText;
}

function collectTags(node, out = []) {
  if (!node || typeof node !== "object") return out;
  if (node.tagName) out.push(node.tagName);
  for (const child of node.children || []) collectTags(child, out);
  return out;
}

test("studio.html and research.html use single native ES module entries and drop legacy scripts", () => {
  const studioHtml = readStatic("studio.html");
  const researchHtml = readStatic("research.html");

  const studioModules = [...studioHtml.matchAll(/<script\s+type="module"\s+src="([^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(studioModules, ["/static/modules/studio/entry.js"]);
  assert.doesNotMatch(studioHtml, /src="\/static\/studio\.js"/);

  const researchModules = [...researchHtml.matchAll(/<script\s+type="module"\s+src="([^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(researchModules, ["/static/modules/research/entry.js"]);
  assert.doesNotMatch(researchHtml, /src="\/static\/research-forms\.js"/);

  assert.equal(fs.existsSync(path.join(STATIC_DIR, "studio.js")), false);
  assert.equal(fs.existsSync(path.join(STATIC_DIR, "research-forms.js")), false);
});

test("studio and research ESM DOM helpers treat untrusted XSS strings as literal text", () => {
  const payload = `<img src=x onerror="alert(1)"><script>alert(2)</script>`;
  const env = makeDomEnv();
  const sandbox = vm.createContext({ window: env.window, document: env.document });

  const studioDom = loadESMInContext("modules/studio/dom.js", sandbox);
  const studioDiff = loadESMInContext("modules/studio/diff.js", sandbox);
  const researchDom = loadESMInContext("modules/research/dom.js", sandbox);
  const researchWiki = loadESMInContext("modules/research/wiki.js", sandbox);
  const researchFiles = loadESMInContext("modules/research/files.js", sandbox);

  const turnArticle = studioDom.buildTurnMessageArticle({
    speaker: { label: payload, model: payload, asset: "" },
    showModel: true,
    turn: { status: "done", text: "ok", started_at: "2026-01-01T00:00:00Z" },
    progress: payload,
  });
  assert.ok(collectText(turnArticle).includes(payload));
  assert.equal(collectTags(turnArticle).includes("SCRIPT"), false);
  assert.equal(collectTags(turnArticle).includes("IMG"), false);

  const diffHost = env.makeNode("pre");
  studioDiff.renderDiffContent(diffHost, { diff: `@@ -1 +1 @@\n+${payload}` });
  assert.ok(collectText(diffHost).includes(payload));
  assert.equal(collectTags(diffHost).includes("SCRIPT"), false);

  const chipHost = env.makeNode("span");
  researchDom.renderTaskTagChip(chipHost, payload, { color: "#112233", textColor: "#ffffff" });
  assert.equal(chipHost.children[0].textContent, payload);
  assert.equal(chipHost.children[0].style.getPropertyValue("--task-label-bg"), "#112233");

  const conflictHost = env.makeNode("div");
  researchWiki.renderNoteConflict(
    conflictHost,
    { revision: 4, aliases: [payload], tags: [payload], body: payload },
    payload,
    () => {},
  );
  assert.ok(collectText(conflictHost).includes(payload));
  assert.equal(collectTags(conflictHost).includes("SCRIPT"), false);

  const box = env.makeNode("p");
  researchFiles.renderProjectFilesList(box, { projectPath: payload, files: [payload] });
  assert.equal(box.replacedWith.length, 3);
  assert.equal(box.replacedWith[0].textContent, payload);
  assert.equal(collectTags(box.replacedWith[2]).includes("SCRIPT"), false);
});

test("a new Roundtable renders its first seat and neutral model icon", () => {
  const {window, document, makeNode} = makeDomEnv();
  const controls = new Map(["room", "scroll", "workspace", "pan", "left", "right"].map(id => ["seating-" + id, makeNode("div")]));
  const props = makeNode("g"), people = makeNode("g");
  const root = controls.get("seating-room");
  root.querySelectorAll = () => [];
  root.querySelector = selector => selector === ".table-objects" ? props : people;
  document.getElementById = id => controls.get(id);
  vm.runInNewContext(readStatic("seating-plan.js"), {
    window, document, ResizeObserver:class { observe() {} }, requestAnimationFrame:() => 1, cancelAnimationFrame() {},
  });
  const member = {model:"fixture/unknown", label:"Researcher <A>"};
  const plan = window.RoundtableSeating.mount(() => "");
  plan.render([member], new Map());
  assert.equal(people.children.length, 1);
  assert.equal(people.children[0].querySelector("title").textContent, "首席 · Researcher <A>");
  assert.ok(people.children[0].querySelector("svg-model"));
});

test("linked materials keep workspace paths as text and preserve preview and native actions", async () => {
  const {window, document, makeNode} = makeDomEnv();
  const name = "code/notes <sample>.py";
  let dialogContent;
  const calls = [];
  function el(tag, attrs, ...children) {
    const node = makeNode(tag);
    for (const [key, value] of Object.entries(attrs)) node.setAttribute(key, value);
    node.append(...children.flat(Infinity).map(item => typeof item === "string" ? document.createTextNode(item) : item));
    return node;
  }
  const ui = {
    state:{project:{id:"project"}}, enc:encodeURIComponent, el,
    fragment:(...items) => el("#fragment", {}, items), bytes:() => "16 B", projectPath:path => "projects/project/" + path,
    $:id => {
      const nodes = [dialogContent];
      while (nodes.length) {
        const node = nodes.pop();
        if (node.getAttribute?.("id") === id) return node;
        nodes.push(...(node.children || []));
      }
    },
    button:(title, action, {id} = {}) => el("button", {"data-action":action, "data-id":id || ""}, title),
    dialog:(_title, content) => { dialogContent = content; },
    request:async (path, options) => {
      if (options) { calls.push(options.body); return {performed:true}; }
      return path.endsWith("view=materials") ? [{path:name, kind:"python", size:16}] : {native:true};
    },
  };
  window.SciResearch = ui;
  vm.runInNewContext(readStatic("research-materials.js"), {window, document,
    fetch:async () => ({ok:true, text:async () => "print('<example>')"})});
  await ui.linkedMaterialsAction("linked-materials");
  const items = dialogContent.replacedWith;
  const fileButton = items.find(item => item.getAttribute("class") === "list").children[0];
  assert.equal(fileButton.getAttribute("data-action"), "preview-linked-material");
  assert.equal(fileButton.getAttribute("data-id"), name);
  assert.equal(collectText(fileButton), name);
  await ui.linkedMaterialsAction(fileButton.getAttribute("data-action"), fileButton.getAttribute("data-id"));
  assert.ok(collectText(dialogContent).includes(name));
  assert.ok(collectText(dialogContent).includes("print('<example>')"));
  assert.ok(!collectTags(dialogContent).includes("EXAMPLE"));
  await ui.linkedMaterialsAction("material-native", "reveal");
  assert.deepEqual(JSON.parse(JSON.stringify(calls)), [{project:"project", action:"reveal", path:name, runtime:"system"}]);
});

test("only the reviewed built-in SVG illustrations use HTML sinks", () => {
  const illustrations = new Map([
    ["seating-plan.js", ["figure.innerHTML =", "root.innerHTML = artwork;"]],
    ["studio-setup.js", ["art.innerHTML ="]],
  ]);
  const sinkRe = /\.\s*(?:innerHTML|outerHTML|insertAdjacentHTML)\b|\[\s*['"](?:innerHTML|outerHTML|insertAdjacentHTML)['"]\s*\]/;
  const missing = [];

  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === "research-vendor") continue;
        walk(full);
      } else if (entry.name.endsWith(".js")) {
        const lines = fs.readFileSync(full, "utf8").split("\n");
        lines.forEach((line, idx) => {
          const trimmed = line.trim();
          if (trimmed.startsWith("//") || trimmed.startsWith("*")) return;
          if (!sinkRe.test(line)) return;
          const prev = lines.slice(Math.max(0, idx - 3), idx + 1).join("\n");
          const file = path.relative(STATIC_DIR, full);
          if (!illustrations.get(file)?.some(prefix => trimmed.startsWith(prefix)) || !prev.includes("html-sink:")) {
            missing.push(`${path.relative(STATIC_DIR, full)}:${idx + 1}`);
          }
        });
      }
    }
  }

  walk(STATIC_DIR);
  assert.deepEqual(missing, [], `Unjustified HTML sinks found: ${missing.join(", ")}`);
});
