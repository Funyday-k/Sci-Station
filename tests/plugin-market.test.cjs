const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "web", "static", "plugin-market.js"), "utf8");
const plain = value => JSON.parse(JSON.stringify(value));
const event = { preventDefault() {} };

function setup(api) {
  class Element {
    constructor(tag) {
      this.tag = tag;
      this.children = [];
      this.listeners = {};
      this.attributes = {};
      this.classList = { toggle() {} };
      this.value = "";
      this.checked = false;
    }
    get textContent() { return this.text || this.children.map(child => child.textContent).join(""); }
    set textContent(text) { this.text = text; this.children = []; }
    set innerHTML(_) { assert.fail("Plugin data must not be assigned to innerHTML"); }
    setAttribute(key, value) { this.attributes[key] = value; }
    removeAttribute(key) { delete this.attributes[key]; }
    focus() {}
    click() {
      this.clickCount = (this.clickCount || 0) + 1;
      return this.listeners.click?.(event);
    }
    showModal() { this.open = true; }
    close() { this.open = false; }
    append(...nodes) { this.children.push(...nodes); }
    replaceChildren(...nodes) { this.text = ""; this.children = nodes; }
    querySelectorAll(tag) {
      return this.children.flatMap(child => [...(child.tag === tag ? [child] : []), ...child.querySelectorAll(tag)]);
    }
    addEventListener(type, listener) { this.listeners[type] = listener; }
  }
  const elements = new Map();
  const $ = id => {
    if (!elements.has(id)) elements.set(id, new Element());
    return elements.get(id);
  };
  const downloads = new Map();
  const URL = {
    createObjectURL(blob) {
      const href = "blob:" + downloads.size;
      downloads.set(href, blob);
      return href;
    },
    revokeObjectURL(href) { downloads.delete(href); },
  };
  const window = {};
  vm.runInNewContext(source, {
    window, Blob, URL, document: { getElementById: $, createElement: tag => new Element(tag) },
  });
  return { $, downloads, ui: window.RoundtablePlugins.mount({ api }) };
}

const plugin = {
  id: "local.test.tools",
  source_id: "builtin",
  name: "复核工具",
  author: "圆桌",
  description: "研究用途",
  version: "1.9.0",
  sha256: "old",
  capabilities: ["round.guidance"],
};

function byButton(root, name) {
  return root.querySelectorAll("button").find(node => node.textContent === name);
}

test("market requires explicit capability grants and pins the approved update", async () => {
  const calls = [];
  const next = {
    ...plugin, version: "1.10.0", sha256: "reviewed",
    capabilities: ["round.guidance", "code.execute", "meeting.report"],
  };
  const thirdParty = { ...next, source_id: "other", name: "同名目录插件", version: "2.0.0" };
  const view = {
    sources: [
      { id: "builtin", builtin: true, name: "精选目录" },
      { id: "other", name: "精选目录", url: "https://example.com/other.json" },
    ],
    installed: [{ ...plugin, enabled: false }],
    available: [next, thirdParty],
  };
  const { $, ui } = setup(async (_, body) => {
    if (body) calls.push(plain(body));
    return body?.action === "install" ? { ...view, installed: [{ ...next, enabled: false }] } : view;
  });
  await ui.openMarket();
  const results = $("plugin-market-results");
  assert.equal(results.querySelectorAll("article").length, 2);
  assert.match(results.textContent, /已从其他目录安装/);
  assert.match($("plugin-source-filter").textContent, /精选目录 · 内置.*精选目录 · https:\/\/example.com\/other.json/);

  $("plugin-source-filter").value = "other";
  $("plugin-source-filter").listeners.change();
  assert.equal(results.querySelectorAll("article").length, 1);
  assert.equal(byButton(results, "更新"), undefined);
  $("plugin-source-filter").value = "";
  $("plugin-search").value = "研究用途";
  $("plugin-search").listeners.input();
  assert.equal(results.querySelectorAll("article").length, 2);
  $("plugin-tab-installed").listeners.click();
  byButton(results, "更新").listeners.click();
  assert.match($("plugin-confirm-permissions").textContent, /继续使用的能力/);
  assert.match($("plugin-confirm-description").textContent, /来源 · 精选目录（内置来源）/);
  assert.ok($("plugin-confirm-description").textContent.includes(plugin.id));
  const granted = $("plugin-confirm-permissions").querySelectorAll("input");
  assert.equal(granted.length, 2);
  assert.ok($("plugin-confirm-submit").disabled);
  await $("plugin-confirm-form").listeners.submit(event);
  assert.deepEqual(calls, []);
  granted[0].checked = true;
  granted[0].listeners.change();
  assert.ok($("plugin-confirm-submit").disabled);
  granted[1].checked = true;
  granted[1].listeners.change();
  assert.equal($("plugin-confirm-submit").disabled, false);
  await $("plugin-confirm-form").listeners.submit(event);
  assert.deepEqual(calls, [{
    action: "install", source_id: "builtin", id: plugin.id, sha256: next.sha256,
    grants: next.capabilities,
  }]);
  assert.match(results.textContent, /已停用/);
  assert.equal(byButton(results, "更新"), undefined);
  byButton(results, "卸载").listeners.click();
  await $("plugin-confirm-form").listeners.submit(event);
  assert.deepEqual(calls.at(-1), {
    action: "uninstall", source_id: "builtin", id: plugin.id, version: next.version, sha256: next.sha256,
  });
});

test("market retains cached sources after an offline refresh", async () => {
  const view = {
    sources: [{ id: "one", name: "示例目录", url: "https://example.com/catalog.json" }],
    available: [{ ...plugin, source_id: "one" }],
    installed: [],
  };
  const { $, ui } = setup(async (_, body) => {
    if (body?.action === "refresh") throw Error("连接超时");
    return view;
  });
  await ui.openMarket();
  byButton($("plugin-source-list"), "刷新").listeners.click();
  await new Promise(resolve => setImmediate(resolve));
  assert.match($("plugin-source-status").textContent, /保留本地缓存.*连接超时/);
  assert.match($("plugin-source-list").textContent, /显示本地缓存/);
  assert.match($("plugin-market-results").textContent, /复核工具/);
});

const toolPlugin = {
  ...plugin, enabled: true,
  actions: [
    { id: "report", label: "整理报告", input: "report", format: "markdown" },
    { id: "overview", label: "整理发言", input: "public_turns", format: "text" },
  ],
};
const reportWorking = { id: "meeting one", rounds: [{}, {}, {}], status: "closed", report: { status: "reviewing" } };
const reportReady = { ...reportWorking, report: { status: "ready" } };

test("tools gate report actions on readiness, pass selected public rounds, and download literal UTF-8", async () => {
  const calls = [];
  const raw = "# 复核\n<script>alert('no')</script>🪶";
  const { $, ui, downloads } = setup(async (url, body) => {
    if (!body) return { installed: [toolPlugin, { ...toolPlugin, enabled: false }] };
    calls.push({ url, body: plain(body) });
    return {
      format: body.action_id === "report" ? "markdown" : "text",
      text: raw,
      filename: body.action_id === "report" ? "复核.md" : "发言.txt",
    };
  });
  ui.updateSession(reportWorking);
  await $("plugin-tools-open").listeners.click();
  assert.equal($("plugin-tools-action").querySelectorAll("option").length, 2);
  assert.match($("plugin-tools-input").textContent, /定稿的会议报告/);
  assert.equal($("plugin-tools-run").disabled, true);
  await $("plugin-tools-form").listeners.submit(event);
  assert.equal(calls.length, 0);
  ui.updateSession(reportReady);
  assert.equal($("plugin-tools-run").disabled, false);
  await $("plugin-tools-form").listeners.submit(event);
  assert.equal($("plugin-tools-result").textContent, raw);
  const download = $("plugin-tools-download");
  assert.equal(download.textContent, "下载 Markdown");
  assert.equal(download.download, "复核.md");
  assert.equal(await downloads.get(download.href).text(), raw);
  await download.listeners.click({ preventDefault() {
    assert.fail("The browser download must preserve the native anchor action");
  } });

  $("plugin-tools-action").value = "1";
  $("plugin-tools-action").listeners.change();
  assert.equal(downloads.size, 0);
  assert.match($("plugin-tools-input").textContent, /3 个公开轮次/);
  $("plugin-tools-from").value = "2";
  await $("plugin-tools-form").listeners.submit(event);
  assert.equal(download.download, "发言.txt");
  assert.deepEqual(calls, [
    { url: "/sessions/meeting%20one/plugin-action", body: {
      plugin_id: plugin.id, action_id: "report", version: plugin.version, source_id: plugin.source_id, sha256: plugin.sha256,
    } },
    { url: "/sessions/meeting%20one/plugin-action", body: {
      plugin_id: plugin.id, action_id: "overview", version: plugin.version, source_id: plugin.source_id, sha256: plugin.sha256, from_round: 2,
    } },
  ]);
});

test("switching sessions while a tool runs discards the previous session result", async () => {
  let finish;
  const { $, ui, downloads } = setup(async (url, body) => {
    if (!body) return { installed: [toolPlugin] };
    if (url.includes("meeting%20one")) return new Promise(resolve => { finish = resolve; });
    return { text: "第二场会议", format: "markdown", filename: "second.md" };
  });
  ui.updateSession(reportReady);
  await $("plugin-tools-open").listeners.click();
  const original = $("plugin-tools-form").listeners.submit(event);
  ui.updateSession({ ...reportReady, id: "meeting two" });
  assert.equal(ui.isOpen(), false);
  await $("plugin-tools-open").listeners.click();
  await $("plugin-tools-form").listeners.submit(event);
  finish({ text: "第一场会议", format: "markdown", filename: "first.md" });
  await original;
  assert.equal($("plugin-tools-result").textContent, "第二场会议");
  assert.deepEqual([...downloads.keys()], [$("plugin-tools-download").href]);
});

test("desktop save reuses the approved result, blocks duplicate requests, and permits retries", async () => {
  const savedRequests = [];
  const raw = "统计\n🪶";
  let cancelSave;
  let runs = 0;
  const { $, ui } = setup(async (url, body) => {
    if (!body) return { installed: [toolPlugin] };
    if (url.endsWith("/plugin-action")) {
      runs++;
      return { text: raw, format: "markdown", filename: "整理.md", native_save: true };
    }
    assert.equal(url, "/plugins/save-output");
    savedRequests.push(plain(body));
    if (savedRequests.length === 1) return new Promise(resolve => { cancelSave = resolve; });
    if (savedRequests.length === 2) throw Error("无法写入文件");
    return { saved: true };
  });
  ui.updateSession(reportReady);
  await $("plugin-tools-open").listeners.click();
  await $("plugin-tools-form").listeners.submit(event);
  const download = $("plugin-tools-download");
  let prevented = 0;
  assert.equal(download.textContent, "保存 Markdown…");
  const click = () => download.listeners.click({ preventDefault() { prevented++; } });
  const first = click();
  assert.equal(download.attributes["aria-disabled"], "true");
  await click();
  assert.equal(prevented, 2);
  assert.deepEqual(savedRequests, [{ filename: "整理.md", text: raw, format: "markdown" }]);
  cancelSave({ saved: false });
  await first;
  assert.equal($("plugin-tools-status").textContent, "已取消保存。");
  assert.equal(download.attributes["aria-disabled"], "false");
  assert.equal($("plugin-tools-result").textContent, raw);
  await click();
  assert.match($("plugin-tools-status").textContent, /保存失败.*无法写入文件/);
  await click();
  assert.equal($("plugin-tools-status").textContent, "文件已保存。");
  assert.equal(runs, 1);
  assert.equal(savedRequests.length, 3);
});

test("native-save fallback triggers a single direct browser download", async () => {
  let requests = 0;
  const { $, ui } = setup(async (url, body) => {
    if (!body) return { installed: [toolPlugin] };
    if (url.endsWith("/plugin-action")) return { native_save: true, text: "问答", format: "text", filename: "检索.txt" };
    requests++;
    return { browser_download: true };
  });
  ui.updateSession(reportReady);
  await $("plugin-tools-open").listeners.click();
  await $("plugin-tools-form").listeners.submit(event);
  const download = $("plugin-tools-download");
  await download.listeners.click(event);
  assert.equal(download.clickCount, 1);
  assert.equal(requests, 1);
  assert.equal(download.textContent, "下载文本");
  assert.equal(download.download, "检索.txt");
  assert.equal(download.attributes["aria-disabled"], undefined);
});
