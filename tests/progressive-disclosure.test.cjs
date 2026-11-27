"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const staticDir = path.join(__dirname, "../web/static");
const read = name => fs.readFileSync(path.join(staticDir, name), "utf8");

test("MCP, Discovery/MinerU, and Collaboration forms place low-level fields inside Advanced disclosures with aria-live errors", () => {
  const lab = read("lab.html");
  assert.match(lab, /<details id="connector-advanced" class="disclosure">\s*<summary data-en="Advanced">高级选项<\/summary>/);
  const connectorAdvanced = lab.slice(lab.indexOf('id="connector-advanced"'), lab.indexOf("</details>", lab.indexOf('id="connector-advanced"')));
  for (const id of ["connector-program", "connector-argv-rows", "connector-argv", "connector-tools", "connector-token"]) {
    assert.match(connectorAdvanced, new RegExp(`id="${id}"`), `Expected ${id} inside connector-advanced disclosure`);
  }
  assert.match(lab, /id="connector-argv-error"[^>]*role="alert"[^>]*aria-live="polite"/);
  assert.match(lab, /id="connector-form-error"[^>]*role="alert"[^>]*aria-live="polite"/);
  assert.match(lab, /id="connector-token"[^>]*type="password"/);

  const tools = read("science-tools.html");
  assert.match(tools, /<details id="discovery-advanced" class="disclosure discovery-options">\s*<summary data-en="Advanced">高级选项<\/summary>/);
  assert.match(tools, /<details id="mineru-advanced" class="disclosure panel">/);
  assert.match(tools, /id="discovery-error"[^>]*role="alert"[^>]*aria-live="polite"/);
  assert.match(tools, /id="mineru-error"[^>]*role="alert"[^>]*aria-live="polite"/);
  assert.match(tools, /type="password"[^>]*id="token"/);

  const settings = read("settings.html");
  assert.match(settings, /<details id="collaboration-advanced" class="disclosure settings-advanced">\s*<summary data-en="Advanced">高级选项<\/summary>/);
  const collabAdvanced = settings.slice(settings.indexOf('id="collaboration-advanced"'), settings.indexOf("</details>", settings.indexOf('id="collaboration-advanced"')));
  for (const id of ["setting-max-children", "setting-max-tool-calls", "setting-context-chars", "setting-total-tool-chars", "setting-per-tool-chars"]) {
    assert.match(collabAdvanced, new RegExp(`id="${id}"`), `Expected ${id} inside collaboration-advanced disclosure`);
  }
  assert.match(settings, /id="collaboration-error"[^>]*role="alert"[^>]*aria-live="polite"/);
});

test("MCP connectors structured array rows sync with raw JSON, auto-open Advanced on non-default or error, and never echo Keychain tokens", async () => {
  class MockNode {
    constructor(tag = "div", id = "") {
      this.tag = tag;
      this.id = id;
      this.value = "";
      this.checked = false;
      this.hidden = false;
      this.disabled = false;
      this.open = false;
      this.readOnly = false;
      this.textContent = "";
      this.className = "";
      this.dataset = {};
      this.attrs = {};
      this.children = [];
      this.listeners = new Map();
    }
    setAttribute(k, v) { this.attrs[k] = String(v); }
    getAttribute(k) { return this.attrs[k] ?? null; }
    addEventListener(type, fn) {
      if (!this.listeners.has(type)) this.listeners.set(type, []);
      this.listeners.get(type).push(fn);
    }
    dispatch(type, event = {}) {
      for (const fn of this.listeners.get(type) || []) fn(event);
      if (type === "change" && this.onchange) this.onchange(event);
      if (type === "input" && this.oninput) this.oninput(event);
    }
    append(...nodes) { this.children.push(...nodes); }
    replaceChildren(...nodes) { this.children = nodes; }
    querySelectorAll(sel) {
      const out = [];
      const walk = node => {
        for (const c of node.children || []) {
          if (c.tag === sel) out.push(c);
          walk(c);
        }
      };
      walk(this);
      return out;
    }
    focus() {}
  }

  const lab = read("lab.html");
  const nodes = new Map();
  for (const m of lab.matchAll(/id="([^"]+)"/g)) nodes.set(m[1], new MockNode("div", m[1]));
  const get = id => nodes.get(id) || null;
  const messages = [];
  const sent = [];

  const context = {
    document: {
      getElementById: get,
      createElement: tag => new MockNode(tag),
    },
    window: {
      sciStationConnectorSession: "session-token",
      addEventListener() {},
    },
    Option: class { constructor(text, value) { this.text = text; this.value = value; } },
    AbortController,
    confirm: () => true,
  };
  vm.runInNewContext(read("lab-connectors.js"), context);

  const api = context.window.SciLabConnectors.mount({
    req: async (url, method, body) => {
      sent.push({url, body});
      if (url.endsWith("/index")) {
        return {
          revision: 1,
          connections: [
            {id: "simple", transport: "https", endpoint: "https://example.org/mcp", bearer: false, enabled: true, tools: []},
            {id: "local-mcp", transport: "stdio", program: "/usr/local/bin/mcp", arguments: ["--stdio", "--read-only"], tools: ["lookup"], enabled: true},
            {id: "authed", transport: "https", endpoint: "https://secure.example/mcp", bearer: true, enabled: true, tools: []},
          ],
        };
      }
      if (url.endsWith("/status")) return {trusted: true, configured: true};
      if (url.endsWith("/set-token")) return {ok: true};
      if (url.endsWith("/save")) return {revision: 2, connections: [body.connection]};
      return {};
    },
    tell: msg => messages.push(msg),
    resetResource() {},
    showPreview() {},
    settingsChanged() {},
  });

  await api.select("proj-1", "Project One");

  // Default new HTTPS connector keeps Advanced collapsed.
  assert.equal(get("connector-advanced").open, false);

  // Selecting simple HTTPS connector with default options keeps Advanced collapsed.
  get("connector-select").value = "simple";
  get("connector-select").dispatch("change");
  assert.equal(get("connector-advanced").open, false);

  // Selecting stdio connector with arguments & tools auto-opens Advanced and populates structured rows.
  get("connector-select").value = "local-mcp";
  get("connector-select").dispatch("change");
  assert.equal(get("connector-advanced").open, true);
  assert.deepEqual(
    get("connector-argv-rows").querySelectorAll("input").map(i => i.value),
    ["--stdio", "--read-only"]
  );

  // Adding a structured argument row syncs raw JSON array.
  get("connector-argv-add").dispatch("click");
  const rowInputs = get("connector-argv-rows").querySelectorAll("input");
  assert.equal(rowInputs.length, 3);
  rowInputs[2].value = "--verbose";
  rowInputs[2].dispatch("input");
  assert.equal(get("connector-argv").value, '["--stdio","--read-only","--verbose"]');

  // Invalid raw JSON opens Advanced and reports inline aria-live error.
  get("connector-advanced").open = false;
  get("connector-argv").value = "{not-an-array}";
  get("connector-argv").dispatch("input");
  assert.equal(get("connector-advanced").open, true);
  assert.equal(get("connector-argv-error").hidden, false);
  assert.match(get("connector-argv-error").textContent, /JSON 字符串数组/);

  // Keychain token input is cleared after saving and never echoed back.
  get("connector-select").value = "authed";
  get("connector-select").dispatch("change");
  assert.equal(get("connector-advanced").open, true);
  assert.equal(get("connector-token").value, "");
  get("connector-token").value = "secret-bearer-token";
  await get("connector-set-token").listeners.get("click")[0]();
  assert.equal(get("connector-token").value, "");
  const tokenCall = sent.find(call => call.url.endsWith("/set-token"));
  assert.equal(tokenCall.body.token, "secret-bearer-token");
});

test("collaboration settings use the fresh workspace seat limit when opening Advanced", async () => {
  for (const [maxChildren, expected] of [[1, false], [2, true], [0, true]]) {
    const controls = new Map();
    const get = id => {
      if (!controls.has(id)) controls.set(id, {value:"", open:false, dataset:{},
        addEventListener() {}, setAttribute() {}, classList:{toggle() {}},
        elements:{namedItem: () => get("color_theme")}});
      return controls.get(id);
    };
    const settings = {max_children:maxChildren, max_steps:10, timeout:180};
    vm.runInNewContext(read("settings.js"), {
      window:{addEventListener() {}}, document:{getElementById:get, querySelectorAll:()=>[], querySelector:()=>null, addEventListener(){}},
      URL, location:new URL("http://localhost/settings?section=collaboration"),
      fetch:async url => ({ok:true, json:async () => url.endsWith("/settings") ? settings : {models:[]}})
    });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(get("setting-max-children").value, maxChildren);
    assert.equal(get("collaboration-advanced").open, expected);
  }
});

test("Discovery Advanced disclosure stays closed for defaults and opens automatically on non-default values or validation error", async () => {
  const controls = {};
  class Control {
    value = "";
    checked = true;
    hidden = false;
    open = false;
    disabled = false;
    textContent = "";
    children = [];
    replaceChildren(...nodes) { this.children = nodes; }
    append(...nodes) { this.children.push(...nodes); }
    add(o) { this.children.push(o); }
    addEventListener(event, callback) { this[event] = callback; }
    contains(control) { return control === controls.topK; }
    get selectedOptions() { return this.children.filter(c => c.selected); }
  }
  for (const m of read("science-tools.html").matchAll(/id="([^"]+)"/g)) controls[m[1]] = new Control();
  const told = [];
  const ctx = vm.createContext({
    URLSearchParams,
    window: {addEventListener() {}},
    document: {getElementById: id => controls[id], createElement: () => new Control()},
    confirm: () => true,
  });
  vm.runInContext(read("discovery-view.js"), ctx);

  let mode = "default", rejectSubmission;
  const disc = ctx.SciStationDiscovery.create({
    $: id => controls[id],
    req: async (route, body) => {
      if (body) return new Promise((_, reject) => { rejectSubmission = () => reject(Object.assign(Error("Invalid category"), {status:400})); });
      if (route.startsWith("tools/discover")) {
        if (mode === "history") return {id:"saved", source:"arxiv", ai_model:"saved/model", history:[], items:[]};
        return mode === "default"
          ? {source: "arxiv", query: "", defaults: {source: "arxiv", categories: [], cross_list: true, top_k: 24, max_daily_candidates: 100, library_recent_days: 60}, history: [], items: []}
          : {source: "arxiv", query: "gravitational", categories: ["astro-ph.HE"], cross_list: true, top_k: 40, defaults: {source: "arxiv", categories: ["astro-ph.HE"], cross_list: true, top_k: 40, max_daily_candidates: 100, library_recent_days: 60}, history: [], items: []};
      }
      return [];
    },
    make: (_t, text) => Object.assign(new Control(), {textContent: text || ""}),
    button: (label, cb) => Object.assign(new Control(), {textContent: label, onclick: cb}),
    busy: (_el, fn) => fn(),
    tell: msg => told.push(msg),
  });

  await disc.load("");
  assert.equal(controls["discovery-advanced"].open, false);

  // Validation error in topK auto-opens Advanced and sets #discovery-error.
  controls.topK.value = "999";
  controls.search.onsubmit({preventDefault() {}});
  assert.equal(controls["discovery-advanced"].open, true);
  assert.equal(controls["discovery-error"].hidden, false);
  assert.match(controls["discovery-error"].textContent, /1 到 100/);

  // The browser fires invalid in the capture phase instead of submitting an invalid number.
  controls.topK.validationMessage = "Choose a value within range";
  controls["discovery-advanced"].open = false;
  controls.search.invalid({target:controls.topK});
  assert.equal(controls["discovery-advanced"].open, true);
  assert.equal(controls["discovery-error"].textContent, controls.topK.validationMessage);

  controls.topK.value = "24";
  controls.categories.value = "bad!";
  controls["discovery-advanced"].open = false;
  const rejected = controls.search.onsubmit({preventDefault() {}});
  rejectSubmission();
  await assert.rejects(rejected, /Invalid category/);
  assert.equal(controls["discovery-advanced"].open, true);
  assert.equal(controls["discovery-error"].textContent, "Invalid category");

  const stale = controls.search.onsubmit({preventDefault() {}});
  await disc.load("unrelated-project");
  rejectSubmission();
  await stale;
  assert.equal(controls["discovery-advanced"].open, false);
  assert.equal(controls["discovery-error"].textContent, "");

  mode = "history";
  await disc.load("p1", "saved");
  assert.equal(controls.aiModel.value, "saved/model");
  assert.ok(controls.aiModel.children.some(option => option.value === "saved/model"));
  assert.equal(controls["discovery-advanced"].open, true);

  // Non-default run auto-opens Advanced.
  controls["discovery-advanced"].open = false;
  mode = "custom";
  await disc.load("p1");
  assert.equal(controls["discovery-advanced"].open, true);
});
