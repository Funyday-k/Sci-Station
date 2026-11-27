"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.join(__dirname, "..");

test("Roundtable markup uses one page bar, removes separate opinions toggle, and tabs conversation with viewpoints", () => {
  const html = fs.readFileSync(path.join(root, "web/static/studio.html"), "utf8");
  const toolsBlock = html.slice(html.indexOf('{{define "tools"}}'), html.indexOf('{{define "content"}}'));
  assert.match(toolsBlock, /id="room-chat-toggle"/);
  assert.match(toolsBlock, /id="meeting-actions-toggle"/);
  assert.match(toolsBlock, /id="meeting-menu-commands"/);
  assert.doesNotMatch(toolsBlock, /id="cli-edit-open"/, "CLI edit button belongs in the single page bar");
  assert.doesNotMatch(toolsBlock, /id="session-status"/, "session status belongs in the single page bar");

  const contextBarStart = html.indexOf('<div class="room-context-bar">');
  const contextBarEnd = html.indexOf("</div>", html.indexOf('id="cli-edit-open"', contextBarStart));
  const contextBar = html.slice(contextBarStart, contextBarEnd);
  assert.match(contextBar, /id="view-title"/);
  assert.match(contextBar, /id="participants-toggle"/);
  assert.match(contextBar, /id="agenda-toggle"/);
  assert.match(contextBar, /id="table-center-state"/);
  assert.match(contextBar, /id="cli-edit-open"/);
  assert.doesNotMatch(contextBar, /id="opinions-toggle"/, "separate opinions toggle must be removed");

  assert.doesNotMatch(html, /id="opinions-scrim"/, "standalone opinions scrim must be removed");
  assert.doesNotMatch(html, /id="opinions-close"/, "standalone opinions close button must be removed");

  const panelStart = html.indexOf('<section id="room-chat"');
  const panelEnd = html.indexOf("</section>", html.indexOf('id="meeting-opinions"', panelStart));
  const panel = html.slice(panelStart, panelEnd);
  assert.match(panel, /role="tablist"/);
  assert.match(panel, /id="room-tab-chat"[^>]*role="tab"[^>]*aria-controls="room-panel-chat"/);
  assert.match(panel, /id="room-tab-opinions"[^>]*role="tab"[^>]*aria-controls="meeting-opinions"/);
  assert.match(panel, /id="room-panel-chat"[^>]*role="tabpanel"/);
  assert.match(panel, /id="meeting-opinions"[^>]*role="tabpanel"/);
  assert.match(panel, /id="opinions-toggle-count"/);
});

test("science-meeting places Research Records inside #meeting-menu-commands when present", async () => {
  class Node {
    constructor(tag) {
      this.tagName = tag;
      this.children = [];
      this.dataset = {};
      this.listeners = new Map();
      this.hidden = false;
      this.textContent = "";
    }
    get firstChild() { return this.children[0] || null; }
    insertBefore(node, before) {
      const idx = before ? this.children.indexOf(before) : -1;
      if (idx >= 0) this.children.splice(idx, 0, node);
      else this.children.push(node);
      return node;
    }
    addEventListener(type, fn) {
      const list = this.listeners.get(type) || [];
      list.push(fn);
      this.listeners.set(type, list);
    }
  }
  const menuCommands = new Node("div");
  const toolbar = new Node("div");
  const project = { id: "p1", name: "Study", revision: 1 };
  const fetch = async (url) => {
    if (url === "/api/research/projects") return { ok: true, json: async () => [project] };
    throw new Error("unexpected fetch " + url);
  };
  const ctx = vm.createContext({
    window: {},
    URL,
    URLSearchParams,
    FormData,
    fetch,
    location: new URL("http://localhost/studio?project=p1"),
    history: { replaceState() {} },
    document: {
      body: new Node("body"),
      createElement: (tag) => new Node(tag),
      getElementById: (id) => (id === "meeting-menu-commands" ? menuCommands : id === "chat-toolbar" ? toolbar : null),
    },
  });
  vm.runInContext(fs.readFileSync(path.join(root, "web/static/science-meeting.js"), "utf8"), ctx);
  await ctx.window.ScienceMeeting.loadProjects();
  ctx.window.ScienceMeeting.update({ id: "s1", project_id: "p1", topic: "Test", rounds: [] });
  assert.equal(menuCommands.children.length, 1);
  assert.equal(toolbar.children.length, 0);
  assert.equal(menuCommands.children[0].textContent, "科研记录");
  assert.equal(menuCommands.children[0].dataset.meetingCommand, "");
  assert.equal(menuCommands.children[0].hidden, false);
});

test("global Ask AI context rail scopes to the active Roundtable meeting", () => {
  const nodes = new Map();
  class Element {
    constructor(id) {
      this.id = id;
      this.dataset = {};
      this.style = { setProperty() {} };
      this.attributes = new Map();
      this.hidden = false;
      this.disabled = false;
      this.textContent = "";
      this.value = "";
      this.children = [];
    }
    setAttribute(name, value) { this.attributes.set(name, String(value)); }
    getAttribute(name) { return this.attributes.get(name); }
    replaceChildren(...items) { this.children = items; }
    append(...items) { this.children.push(...items); }
    focus() {}
    closest() { return null; }
  }
  for (const id of [
    "context-rail", "shell-divider", "shell-assist", "shell-pin", "rail-close",
    "rail-title", "rail-context", "rail-inspect", "rail-ai", "rail-prompt",
    "rail-status", "rail-retry", "rail-excerpt", "rail-actions", "rail-send",
    "rail-new", "rail-stop", "rail-lab", "rail-model", "rail-effort",
    "rail-read-review", "rail-transcript",
  ]) {
    nodes.set(id, new Element(id));
  }
  const body = new Element("body");
  body.dataset.workspaceSurface = "studio";
  const storage = new Map();
  const windowObj = {
    SciShellLayout: {
      state: { mode: "hidden", panelPinned: false, width: 360 },
      request: async (url) => {
        if (url === "/api/research/projects/proj1") return { id: "proj1", name: "Quantum Study", conversationGeneration: 2 };
        if (url === "/api/studio/models") return { models: [], default_model: "" };
        return {};
      },
      save: async () => {},
      loadAsset: async () => {},
    },
    SciStationNav: {
      aiAvailable: () => true,
      isSettings: () => false,
      route: (p, q) => p + "?" + new URLSearchParams(q || {}),
    },
    SciStationModules: {
      load: async () => ({}),
      isEnabled: () => true,
    },
    SciShellMeeting: () => ({
      id: "sess42",
      project: "proj1",
      title: "QEC Decoder Review",
      topic: "Compare surface-code decoders on bias noise.",
      mode: "方案评审",
      access: "只读",
      status: "就绪",
      seats: ["席位 1", "席位 2"],
    }),
    addEventListener() {},
  };
  const ctx = vm.createContext({
    window: windowObj,
    document: {
      body,
      title: "QEC Decoder Review · 工作圆桌",
      activeElement: null,
      getElementById: (id) => nodes.get(id) || null,
      querySelector: () => ({}),
      querySelectorAll: () => [],
      createElement: (tag) => new Element(tag),
      addEventListener() {},
    },
    location: new URL("http://localhost/studio?session=sess42"),
    URL,
    URLSearchParams,
    matchMedia: () => ({ matches: false, addEventListener() {} }),
    sessionStorage: {
      getItem: (k) => storage.get(k) ?? null,
      setItem: (k, v) => storage.set(k, v),
      removeItem: (k) => storage.delete(k),
    },
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    MutationObserver: class { observe() {} },
    setTimeout,
    clearTimeout,
    innerWidth: 1400,
  });
  vm.runInContext(fs.readFileSync(path.join(root, "web/static/context-rail.js"), "utf8"), ctx);
  windowObj.SciContextRail.toggle("ai", nodes.get("shell-assist"));
  assert.equal(nodes.get("context-rail").hidden, false);
  assert.equal(nodes.get("rail-ai").hidden, false);
  assert.match(nodes.get("rail-context").textContent, /QEC Decoder Review/);
  assert.match(nodes.get("rail-excerpt").textContent, /Compare surface-code decoders/);
});
