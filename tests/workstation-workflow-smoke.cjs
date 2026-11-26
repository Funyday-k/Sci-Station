"use strict";

// macOS: build the native binary so the browser uses real PDFKit pages.
//   node tests/workstation-workflow-smoke.cjs /path/to/Sci-Station.app/Contents/MacOS/sci-station
// Playwright must be available to Node. SCI_STATION_SMOKE_CHROME may name an
// installed Chromium/Chrome executable. SCI_STATION_SMOKE_ARTIFACTS may name a
// directory for a screenshot of the restored evidence. Use --native with an
// release .app path. The native smoke rebuilds only a disposable test copy.
// SCI_STATION_WORKFLOW_SECONDARY=1 places its window on a second display.
const assert = require("node:assert/strict");
const {execFileSync, spawn} = require("node:child_process");
const {createHash, randomUUID} = require("node:crypto");
const {once} = require("node:events");
const {cp, mkdir, mkdtemp, readFile, realpath, rename, rm, writeFile} = require("node:fs/promises");
const http = require("node:http");
const {tmpdir} = require("node:os");
const path = require("node:path");
const {setTimeout: delay} = require("node:timers/promises");

const quote = "Capture grows with cross section.";
const contextBefore = "Unselected context before the evidence.";
const contextAfter = "Unselected context after the evidence.";
const paperTitle = "Sci-Station smoke paper";
const topic = "Check the selected passage";
const models = ["fixture/first", "fixture/second"];
const statements = ["The first seat traced the stated relationship to the excerpt.",
  "The second seat recorded that the excerpt does not give a numerical bound."];
const approvedTitle = "Accepted evidence note";
const rejectedTitle = "Rejected evidence note";
const dialog = ".science-meeting-dialog";

function sourcePDF() {
  const content = lines => {
    const stream = lines.map((line, i) =>
      "BT /F1 16 Tf 32 " + (190 - 32 * i) + " Td (" + line + ") Tj ET\n"
    ).join("");
    return "<< /Length " + Buffer.byteLength(stream) + " >>\nstream\n" + stream + "endstream";
  };
  const page = contents => "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 440 250] /Resources << /Font << /F1 5 0 R >> >> /Contents " +
    contents + " 0 R >>";
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
    page(6), page(7),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    content(["First page: a different passage."]),
    content([contextBefore, quote, contextAfter])
  ];
  let file = "%PDF-1.4\n";
  const offsets = objects.map((item, i) => {
    const offset = Buffer.byteLength(file);
    file += (i + 1) + " 0 obj\n" + item + "\nendobj\n";
    return offset;
  });
  const xref = Buffer.byteLength(file);
  file += "xref\n0 " + (objects.length + 1) + "\n0000000000 65535 f \n";
  for (const offset of offsets) file += String(offset).padStart(10, "0") + " 00000 n \n";
  return Buffer.from(file + "trailer\n<< /Root 1 0 R /Size " + (objects.length + 1) +
    " >>\nstartxref\n" + xref + "\n%%EOF\n");
}

async function listen(handler) {
  const server = http.createServer(handler);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return server;
}

async function closeServer(server) {
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
}

async function localGateway() {
  const calls = [], errors = [];
  const server = await listen(async (req, res) => {
    const send = (status, value) => {
      res.writeHead(status, {"Content-Type": "application/json"});
      res.end(JSON.stringify(value));
    };
    try {
      assert.equal(req.headers.authorization, "Bearer magpie-sci-station");
      if (req.method === "GET" && req.url === "/v1/models") {
        send(200, {data: models.map((id, i) => ({
          id, display_name: "Fixture seat " + (i + 1), owned_by: "fixture",
          kind: "chat", native_endpoints: ["/v1/chat/completions"]
        }))});
        return;
      }
      assert.equal(req.method, "POST");
      assert.equal(req.url, "/v1/chat/completions");
      const parts = [];
      for await (const chunk of req) parts.push(chunk);
      const input = JSON.parse(Buffer.concat(parts));
      const seat = models.indexOf(input.model);
      assert.ok(seat >= 0);
      const prompt = input.messages.at(-1).content;
      assert.equal(typeof prompt, "string");
      const kind = prompt.startsWith("AGENDA DRAFT REQUEST") ? "agenda"
        : prompt.startsWith("TITLE REQUEST:") ? "title" : "statement";
      calls.push({model: input.model, prompt, kind});
      const content = kind === "title" ? "Verify the cited source" : JSON.stringify(kind === "agenda"
        ? {agenda: [{title: "Verify the cited source", kind: "discussion"}]}
        : {action: "say", text: statements[seat]});
      send(200, {model: input.model, choices: [{finish_reason: "stop", message: {content}}]});
    } catch (error) {
      errors.push(String(error));
      send(400, {error: "Unexpected smoke gateway request"});
    }
  });
  return {server, calls, errors, port: server.address().port};
}

async function eventually(check, label, timeout = 25000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = await check();
    if (value) return value;
    await delay(80);
  }
  throw new Error("Timed out: " + label);
}

function domDriver(evaluate, navigate, screenshot) {
  const inspect = (selector, text = "") => evaluate(([selector, text]) => {
    const node = [...document.querySelectorAll(selector)].find(el =>
      el.getClientRects().length && (!text || el.textContent.includes(text)));
    return node ? {text: node.textContent, value: node.value ?? "", disabled: node.disabled ?? false} : null;
  }, [selector, text]);
  const visible = (selector, text) => eventually(() => inspect(selector, text), selector + (text ? " " + text : ""));
  return {
    evaluate, navigate, visible, screenshot,
    async click(selector, text = "") {
      await eventually(async () => {
        const value = await inspect(selector, text);
        return value && !value.disabled;
      }, "enabled: " + selector + " " + text);
      await evaluate(([selector, text]) => {
        const node = [...document.querySelectorAll(selector)].find(el =>
          el.getClientRects().length && (!text || el.textContent.includes(text)));
        // Return to the automation host before this click can navigate away.
        setTimeout(() => node.click(), 0);
      }, [selector, text]);
    },
    async set(selector, value) {
      await visible(selector);
      await evaluate(([selector, value]) => {
        const node = document.querySelector(selector);
        node.value = value;
        node.dispatchEvent(new Event(node.tagName === "SELECT" ? "change" : "input", {bubbles: true}));
        if (node.value !== value) throw Error("Could not set " + selector + " to " + value);
      }, [selector, value]);
    }
  };
}

async function chromeDriver(origin) {
  const {chromium} = require("playwright");
  const browser = await chromium.launch({
    executablePath: process.env.SCI_STATION_SMOKE_CHROME || undefined,
    headless: true
  });
  const page = await browser.newPage({viewport: {width: 1360, height: 940}});
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.route("**/*", route => {
    const {protocol, origin: source} = new URL(route.request().url());
    return source === origin || ["data:", "blob:", "about:"].includes(protocol) ? route.continue() : route.abort();
  });
  async function evaluate(fn, arg) {
    return eventually(async () => {
      try {
        return {value: await page.evaluate(fn, arg)};
      } catch (error) {
        if (!error.message.includes("Execution context was destroyed")) throw error;
        return null;
      }
    }, "browser finished navigation").then(result => result.value);
  }
  return {
    ui: domDriver(evaluate, url => page.goto(url), file => page.screenshot({path: file})),
    errors, close: () => browser.close()
  };
}

// The optional driver lives in a disposable test build. The release server and
// web assets have no automation routes or production debug hooks.
async function webkitDriver(dir) {
  await mkdir(dir, {mode: 0o700});
  async function send(command) {
    const id = randomUUID();
    const pending = path.join(dir, id);
    await writeFile(pending, JSON.stringify({id, ...command}), {mode: 0o600});
    await rename(pending, path.join(dir, "request.json"));
    const result = await eventually(async () => {
      const bytes = await readFile(path.join(dir, "response.json"), "utf8").catch(error => {
        if (error.code !== "ENOENT") throw error;
        return "";
      });
      const reply = bytes && JSON.parse(bytes);
      return reply?.id === id ? reply : null;
    }, "WKWebView command " + Object.keys(command).join(", "));
    if (result.error) throw Error(result.error);
    return result.value;
  }
  const evaluate = (fn, arg) => send({
    script: "(" + fn.toString() + ")(" + JSON.stringify(arg) + ")"
  });
  const navigate = url => evaluate(url => {
    setTimeout(() => location.assign(url), 0);
  }, url);
  const screenshot = async file => writeFile(file, Buffer.from(await send({capture: true}), "base64"));
  return {ui: domDriver(evaluate, navigate, screenshot),native:send, close: () => {}, quit: () => send({quit: true})};
}

async function buildNativeFixture(bundle, base) {
  assert.equal(path.extname(bundle), ".app");
  const root = path.dirname(__dirname);
  const target = path.join(base, "Sci-Station Workflow Smoke.app");
  const object = path.join(base, "workflow-driver.o");
  const binary = path.join(target, "Contents", "MacOS", "sci-station");
  await cp(bundle, target, {recursive: true});
  const tools = (command, args, options = {}) => execFileSync(command, args, {stdio: "inherit", ...options});
  tools("xcrun", ["clang", "-fobjc-arc", "-mmacosx-version-min=12.0", "-c",
    path.join(__dirname, "macos-workflow-driver.m"), "-o", object]);
  const env = {
    ...process.env, MACOSX_DEPLOYMENT_TARGET: "12.0", CGO_CFLAGS: "-mmacosx-version-min=12.0",
    CGO_LDFLAGS: "-mmacosx-version-min=12.0"
  };
  tools(process.env.GO || "go", ["build", "-tags", "production", "-trimpath",
    "-ldflags", "-linkmode external -extldflags=" + object, "-o", binary, "."], {cwd: root, env});
  tools("/usr/libexec/PlistBuddy", ["-c", "Set CFBundleIdentifier com.funyday.scistation.workflow-smoke",
    path.join(target, "Contents", "Info.plist")]);
  tools("codesign", ["--force", "--options", "runtime", "--sign", "-", target]);
  tools("codesign", ["--verify", "--strict", target]);
  return binary;
}

async function fixtureHome(base, port, connectionSpec) {
  const homeDir = path.join(base, "home");
  const configDir = path.join(homeDir, ".config");
  const studio = path.join(configDir, "sci-station");
  const magpie = path.join(configDir, "magpie");
  await Promise.all([mkdir(studio, {recursive: true}), mkdir(magpie, {recursive: true})]);
  await Promise.all([
    writeFile(path.join(studio, "connection.json"), JSON.stringify({baseURL: "http://127.0.0.1:" + port + "/v1", model: models[0]})),
    writeFile(path.join(magpie, "plugins.json"), JSON.stringify({plugins: [{spec: connectionSpec}]}))
  ]);
  return {HOME: homeDir, XDG_CONFIG_HOME: configDir, SCI_STATION_WORKSPACE_REGISTRY: path.join(base, "registry")};
}

async function launch(binary, port, dataDir, env, mode, quit, inherited = process.env) {
  const child = spawn(binary, [mode, "-port", String(port), "-data-dir", dataDir], {
    env: {...inherited, ...env}, stdio: ["ignore", "ignore", "inherit"]
  });
  const exited = once(child, "exit");
  // The returned close() handles the same exit promise after a startup error.
  exited.catch(() => {});
  const origin = "http://127.0.0.1:" + port;
  const request = async (route, method = "GET", input, status = 200) => {
    const headers = {Accept: "application/json"};
    let body = input;
    if (method !== "GET") {
      Object.assign(headers, {Origin: origin, "X-Roundtable": "1", "X-Sci-Station": "1"});
      if (!(input instanceof FormData)) {
        headers["Content-Type"] = "application/json";
        body = JSON.stringify(input);
      }
    }
    const reply = await fetch(origin + route, {method, body, headers, signal: AbortSignal.timeout(10000)});
    const json = await reply.json();
    assert.equal(reply.status, status, method + " " + route + ": " + JSON.stringify(json));
    return json;
  };
  const processContext = {
    origin, request,
    async close() {
      if (child.exitCode === null && child.signalCode === null) {
        if (!quit || !await quit().then(() => true, () => false)) child.kill("SIGTERM");
      }
      const [exitCode, signal] = await Promise.race([exited, delay(18000, null, {ref: false})]) || [];
      if (exitCode === undefined && signal === undefined) child.kill("SIGKILL");
      assert.equal(exitCode, 0, "fixture workstation did not exit cleanly");
    }
  };
  try {
    await eventually(async () => {
      assert.ok(child.exitCode === null && child.signalCode === null, "fixture workstation exited on startup");
      return (await request("/api/health").catch(() => null))?.name === "sci-station";
    }, "owned fixture workstation HTTP endpoint");
    return processContext;
  } catch (error) {
    child.kill("SIGTERM");
    await processContext.close().catch(() => {});
    throw error;
  }
}

async function seed(app) {
  const project = await app.request("/api/research/projects", "POST", {name: "Evidence smoke project"}, 201);
  const pdf = sourcePDF();
  const digest = createHash("sha256").update(pdf).digest("hex");
  const upload = new FormData();
  upload.append("metadata", JSON.stringify({title: paperTitle, project_ids: [project.id]}));
  upload.append("file", new Blob([pdf], {type: "application/pdf"}), "evidence-smoke.pdf");
  const paper = await app.request("/api/research/papers", "POST", upload, 201);
  assert.equal(paper.file_sha256, digest);
  const page = await app.request("/api/research/papers/" + paper.id + "/pages/2");
  const start = page.text.indexOf(quote);
  assert.ok(start >= 0 && page.text.includes(contextBefore) && page.text.includes(contextAfter));
  const end = start + quote.length;
  const beginWord = page.words.findIndex(word => word.start <= start && start < word.end);
  const endWord = page.words.findIndex(word => word.start < end && end <= word.end);
  assert.ok(beginWord >= 0 && endWord >= beginWord);
  const locator = {
    beginWord, endWord, startOffset: start - page.words[beginWord].start, endOffset: end - page.words[endWord].start
  };
  const meeting = await app.request("/api/studio/sessions", "POST", {
    topic, project_id: project.id, project: project.path,
    members: models.map(model => ({model, effort: "auto"})), preset: "work"
  }, 201);
  assert.equal(meeting.seats.length, 2);
  const meetingPath = "/api/studio/sessions/" + meeting.id;
  const ready = await eventually(async () => {
    const state = await app.request(meetingPath);
    return state.agenda_draft_status !== "drafting" && state;
  }, "agenda draft settles");
  assert.notEqual(ready.agenda_draft_status, "failed", ready.agenda_draft_error);
  return {project, paper, start, end, digest, locator, meeting, meetingPath};
}

async function enterAndRun(app, ui, fixture, gateway) {
  const {project, paper, meeting, meetingPath, locator} = fixture;
  const readerURL = new URL("/reader", app.origin);
  for (const [key, value] of Object.entries({paper: paper.id, project: project.id, page: 2})) {
    readerURL.searchParams.set(key, value);
  }
  await ui.navigate(readerURL.href);
  await ui.visible("#pageStatus", "第 2 页");
  await ui.visible("#textLayer span");
  await ui.evaluate(({beginWord, endWord, startOffset, endOffset}) => {
    const layer = document.getElementById("textLayer"), spans = layer.querySelectorAll("span");
    const range = document.createRange();
    range.setStart(spans[beginWord].firstChild, startOffset);
    range.setEnd(spans[endWord].firstChild, endOffset);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    layer.dispatchEvent(new KeyboardEvent("keyup", {bubbles: true, key: "Shift"}));
  }, locator);
  assert.equal((await ui.visible("#selectedText", quote)).text, quote);
  await ui.click("#handoff");
  assert.equal((await ui.visible("#handoffQuote", quote)).text, quote);
  assert.equal((await ui.visible("#projectSelect")).value, project.id);
  await ui.set("#sessionSelect", meeting.id);
  await ui.click("#submitHandoff");
  await ui.visible("#chat-toolbar");
  const collapsed = await ui.evaluate(() =>
    document.querySelector("#room-chat-toggle[aria-expanded='false']")?.getClientRects().length > 0);
  if (collapsed) await ui.click("#room-chat-toggle");
  await ui.visible("#run-form");
  await eventually(async () => (await ui.visible("#run-note")).value.includes("第 2 页"), "reader draft arrives in studio");
  const destination = new URL(await ui.evaluate(() => location.href));
  assert.equal(destination.pathname, "/studio");
  assert.equal(destination.searchParams.get("session"), meeting.id);
  assert.equal(((await app.request(meetingPath)).rounds || []).length, 0, "reader handoff must wait for the host");
  await ui.click("#run-submit");
  const complete = await eventually(async () => {
    const current = await app.request(meetingPath);
    return current.status === "ready" && current.rounds.length === 1 && current;
  }, "two-seat discussion finishes");
  const turns = complete.rounds[0].turns;
  assert.equal(turns.length, 2);
  assert.deepEqual(turns.map(turn => turn.text).sort(), [...statements].sort());
  assert.ok(turns.every(turn => turn.status === "done"));
  for (const text of statements) await ui.visible("#rounds .message-body", text);
  assert.equal(complete.materials.length, 1, "reader handoff attached more than one source");
  const calls = gateway.calls.filter(call => call.kind === "statement");
  assert.deepEqual(calls.map(call => call.model).sort(), [...models].sort());
  for (const call of calls) {
    assert.ok(call.prompt.includes(quote), "a seat did not receive the exact selected excerpt");
    assert.ok(!call.prompt.includes(contextBefore) && !call.prompt.includes(contextAfter), "a seat received unselected material");
  }
  assert.deepEqual(gateway.errors, []);
  return turns.map(turn => ({key: "round-1-" + turn.seat, text: turn.text}));
}

async function review(app, ui, fixture, outputs) {
  const {project, meeting, meetingPath, paper, digest, start, end} = fixture;
  const projectPath = "/api/research/projects/" + project.id;
  const reviews = () => app.request(projectPath + "/reviews?meeting=" + meeting.id);
  const notes = () => app.request(projectPath + "/notes");
  await ui.click(".science-meeting-open", "科研记录");
  await eventually(async () => ui.evaluate(([selector, values]) => {
    const control = document.querySelector(selector);
    return control && values.every(value => [...control.options].some(option => option.value === value));
  }, [dialog + " select", outputs.map(output => output.key)]), "both completed outputs available for review");
  assert.equal((await notes()).length, 0, "a discussion must not write a project note");
  const propose = async (title, output, body) => {
    await ui.set(dialog + " select", output.key);
    await ui.set(dialog + " input", title);
    await ui.set(dialog + " textarea", body);
    await ui.click(dialog + " button", "提交审核");
    await ui.visible(dialog + " summary", title + " · 待审核");
    const pending = (await reviews()).find(row => row.title === title);
    assert.equal(pending.status, "pending");
    assert.equal(pending.sourceText, output.text);
    assert.equal(pending.evidence.length, 1);
    const ref = pending.evidence[0];
    assert.deepEqual([ref.paperId, ref.page, ref.quote, ref.sourceHash, ref.selectionStart, ref.selectionEnd],
      [paper.id, 2, quote, digest, start, end]);
    assert.equal((await notes()).length, 0, "pending review must leave notes unchanged");
    return pending;
  };
  const rejected = await propose(rejectedTitle, outputs[0], "The researcher rejects this wording.");
  await ui.click(dialog + " button", "拒绝写入");
  await ui.visible(dialog + " summary", rejectedTitle + " · 已拒绝");
  assert.equal((await notes()).length, 0, "rejected review wrote a note");

  const pending = await propose(approvedTitle, outputs[1], "The selected sentence supports a qualitative relationship.");
  await ui.click(dialog + " button", "确认写入");
  await ui.visible(dialog + " summary", approvedTitle + " · 已写入");
  const decided = await reviews();
  assert.equal(decided.find(row => row.id === rejected.id).status, "rejected");
  const accepted = decided.find(row => row.id === pending.id);
  assert.equal(accepted.status, "accepted");
  const replay = await app.request(meetingPath + "/research-reviews", "POST", {
    projectId: project.id, operationId: pending.id, decision: "accept", revision: pending.revision
  });
  assert.equal(replay.resultId, accepted.resultId, "retry duplicated the accepted note");
  const saved = await notes();
  assert.equal(saved.length, 1);
  assert.equal(saved[0].id, accepted.resultId);
  assert.equal(saved[0].title, approvedTitle);
  assert.deepEqual(saved[0].evidence, accepted.evidence);
  return {accepted, rejected, note: saved[0]};
}

async function reopen(app, ui, fixture, reviewed) {
  const {project, paper, meeting, meetingPath, digest, start, end} = fixture;
  const {accepted, rejected, note} = reviewed;
  const session = await app.request(meetingPath);
  assert.equal(session.rounds[0].turns.length, 2);
  const projectPath = "/api/research/projects/" + project.id;
  const decisions = await app.request(projectPath + "/reviews?meeting=" + meeting.id);
  assert.equal(decisions.find(row => row.id === rejected.id).status, "rejected");
  assert.equal(decisions.find(row => row.id === accepted.id).resultId, note.id);
  const saved = await app.request(projectPath + "/notes/" + note.id);
  assert.deepEqual(saved.evidence, note.evidence);

  await ui.navigate(app.origin + "/research?view=notes&project=" + project.id);
  await ui.click("[data-action='read-note']", approvedTitle);
  await ui.visible("dialog .note-preview", "The selected sentence supports a qualitative relationship.");
  await ui.visible("dialog blockquote", quote);
  const links = await ui.evaluate(() => [...document.querySelectorAll('dialog a[href*="/reader?"]')]
    .map(link => link.href));
  const citation = links.find(href => new URL(href).searchParams.get("fingerprint") === digest);
  assert.ok(citation, "the note has no source link pinned to the PDF fingerprint");
  const expected = {paper: paper.id, project: project.id, page: "2", fingerprint: digest, quote,
    start: String(start), end: String(end)};
  const actual = new URL(citation);
  for (const [key, value] of Object.entries(expected)) assert.equal(actual.searchParams.get(key), value, key);
  const linkSelector = 'dialog a[href*="fingerprint=' + digest + '"]';
  await ui.click(linkSelector);
  await ui.visible("#pageStatus", "第 2 页");
  await ui.visible("#highlights .mark.found");
  const current = new URL(await ui.evaluate(() => location.href));
  assert.equal(current.pathname, "/reader");
  for (const [key, value] of Object.entries(expected)) assert.equal(current.searchParams.get(key), value, key);
  const artifacts = process.env.SCI_STATION_SMOKE_ARTIFACTS;
  if (artifacts && ui.screenshot) {
    await mkdir(artifacts, {recursive: true});
    await ui.screenshot(path.resolve(artifacts, "restored-paper-evidence.png"));
  }
}

async function reviewProjectSources(app, ui, fixture) {
  const {project} = fixture, path = "/api/research/projects/" + project.id;
  const wiki = "A recorded Wiki observation.";
  const material = "Source data documented in the actual project attachment.";
  const source = await app.request(path + "/notes", "POST", {title:"Wiki evidence page", body:"😀\r\n" + wiki}, 201);
  const file = new FormData();
  file.append("file", new Blob(["Context\n" + material]), "source-data.txt");
  const attachment = await app.request(path + "/materials", "POST", file, 201);
  await ui.navigate(app.origin + "/lab?project=" + project.id);
  await eventually(() => ui.evaluate(name => [...document.querySelectorAll("#local-record option")]
    .some(option => option.textContent.includes(name)), attachment.name), "AI Lab loads the project source list");
  await ui.click("#local-search summary");
  await ui.set("#local-query", "actual project attachment");
  await ui.click("#local-find");
  await ui.visible("#local-search-status", "已核对");
  await ui.click("#local-hits button", "L1–2");
  assert.ok((await ui.visible("#local-text")).value.includes(material));
  await ui.set("#local-rank", "hybrid");
  await ui.click("#local-rebuild");
  await ui.visible("#local-search-status", "已重建索引");
  await ui.click("#local-find");
  await ui.visible("#local-search-status", "复用");
  await ui.visible("#local-hits button", material);
  console.log("PASS AI Lab offline project search, original passage, and hybrid rebuild and reuse");
  const sourcePath = "/api/research/lab/sources/";
  const citations = [];
  for (const [kind, id, offset, quote] of [["note",source.id,2,wiki],["material",attachment.id,8,material]]) {
    const location = {kind,id,offset};
    const preview = await app.request(sourcePath + "preview", "POST", {projectId:project.id, workflow:"gap-planning", location});
    assert.equal(preview.text, quote);
    citations.push({...location, hash:preview.hash, quote});
  }
  const materials = await app.request(sourcePath + "prepare", "POST", {projectId:project.id, workflow:"gap-planning", citations});
  const room = await app.request("/api/studio/sessions", "POST", {topic:"Review Wiki and material originals",
    project_id:project.id, project:project.path, members:[{model:models[0],effort:"auto"}], preset:"work",
    material_ids:materials.map(record => record.id)}, 201);
  const sessionPath = "/api/studio/sessions/" + room.id;
  await eventually(async () => (await app.request(sessionPath)).agenda_draft_status !== "drafting", "project evidence agenda");
  await app.request(sessionPath + "/run", "POST", {expected_round:0,allow_edits:false}, 202);
  const done = await eventually(async () => {
    const current = await app.request(sessionPath);
    return current.status === "ready" && current.rounds[0]?.turns[0]?.text && current;
  }, "project evidence meeting output");
  const operationId = randomUUID().replaceAll("-", "");
  const pending = await app.request(sessionPath + "/research-reviews", "POST", {operationId, projectId:project.id,
    decision:"propose", proposal:{projectRevision:project.revision, turnId:"round-1-" + done.rounds[0].turns[0].seat,
      action:"create-note", title:"Reviewed project sources", body:"Review of the Wiki and material."}}, 201);
  assert.equal(pending.evidence.length, 2);
  await ui.navigate(app.origin + "/studio?project=" + project.id + "&session=" + room.id);
  await ui.click(".science-meeting-open", "科研记录");
  await ui.visible(dialog + " a", "打开 Wiki 原文");
  await ui.visible(dialog + " a", "打开项目材料原文");
  await ui.click(dialog + " button", "确认写入");
  const accepted = await eventually(async () => {
    const rows = await app.request(path + "/reviews?meeting=" + room.id);
    return rows.find(row => row.id === operationId && row.status === "accepted");
  }, "approved Wiki and material write");
  return {project, resultId:accepted.resultId, wiki, material, source, attachment};
}

async function reopenProjectSources(app, ui, evidence) {
  const route = app.origin + "/research?view=notes&project=" + evidence.project.id + "&note=" + evidence.resultId;
  for (const [key, id, quote] of [["note", evidence.source.id, evidence.wiki], ["material", evidence.attachment.id, evidence.material]]) {
    await ui.navigate(route);
    await ui.visible("dialog blockquote", quote);
    await ui.click("dialog a[href*='" + key + "=" + id + "']");
    assert.equal((await ui.visible("dialog .wiki-occurrence mark", quote)).text, quote);
    const url = new URL(await ui.evaluate(() => location.href));
    assert.equal(url.searchParams.get("project"), evidence.project.id);
    assert.equal(url.searchParams.get(key), id);
  }
  const artifacts = process.env.SCI_STATION_SMOKE_ARTIFACTS;
  if (artifacts && ui.screenshot) {
    await mkdir(artifacts, {recursive: true});
    await ui.screenshot(path.resolve(artifacts, "restored-project-material-evidence.png"));
  }
}

async function main() {
  assert.ok(process.platform === "darwin", "This smoke uses the macOS PDFKit adapter");
  const native = process.argv[2] === "--native";
  const binaryPath = process.argv[native ? 3 : 2];
  assert.ok(binaryPath, "Specify a production binary or pass --native followed by the release .app path");
  const source = await realpath(binaryPath);
  const base = await mkdtemp(path.join(tmpdir(), "sci-station-workflow-"));
  const dataDir = path.join(base, "workstation");
  const spec = path.join(base, "Smoke.app", "Contents", "Resources", "sci-station.agent.js");
  let workstation, browser, gateway, failure;
  try {
    const binary = native ? await buildNativeFixture(source, base) : source;
    gateway = await localGateway();
    await mkdir(path.dirname(spec), {recursive: true});
    await writeFile(spec, "// Registration fixture; the smoke gateway never runs a real plugin.\n");
    const environment = await fixtureHome(base, gateway.port, spec);
    const probe = await listen();
    const serverPort = probe.address().port;
    await closeServer(probe);
    const startWorkstation = async sequence => {
      if (native) {
        const dir = path.join(base, "driver-" + sequence);
        browser = await webkitDriver(dir);
        workstation = await launch(binary, serverPort, dataDir, {
          ...environment, SCI_STATION_WORKFLOW_DRIVER_DIR: dir
        }, "app", browser.quit);
      } else {
        workstation = await launch(binary, serverPort, dataDir, environment, "serve");
        browser = await chromeDriver(workstation.origin);
      }
    };
    const stopWorkstation = async () => {
      await browser.close();
      browser = null;
      await workstation.close();
      workstation = null;
    };

    await startWorkstation(1);
    const fixture = await seed(workstation);
    console.log("PASS fixture PDFKit page and two configured seats");
    const turns = await enterAndRun(workstation, browser.ui, fixture, gateway);
    console.log("PASS reader selection reaches both seats in the existing meeting");
    const reviewed = await review(workstation, browser.ui, fixture, turns);
    console.log("PASS rejected and accepted proposals; accept retry reuses the note");
    const projectReviewed = await reviewProjectSources(workstation, browser.ui, fixture);
    console.log("PASS reviewed Wiki and material evidence reaches the saved note");
    if (browser.errors) assert.deepEqual(browser.errors, []);
    await stopWorkstation();

    await startWorkstation(2);
    await reopen(workstation, browser.ui, fixture, reviewed);
    if (browser.errors) assert.deepEqual(browser.errors, []);
    console.log("PASS restart, project note citation and restored PDF page, quote and hash");
    await reopenProjectSources(workstation, browser.ui, projectReviewed);
    if (browser.errors) assert.deepEqual(browser.errors, []);
    console.log("PASS restart and Wiki/material links highlight the original selected ranges");
  } catch (error) {
    failure = error;
    if (browser) {
      const state = await browser.ui.evaluate(() => ({
        path: location.pathname,
        notices: [...document.querySelectorAll("[role='alert'], #sourceNotice, #message, #notice-text, .science-status")]
          .filter(el => el.getClientRects().length && el.textContent.trim())
          .map(el => el.textContent.trim().slice(0, 200))
      })).catch(() => null);
      if (state) console.error("Fixture UI at failure:", state);
    }
  } finally {
    for (const dispose of [() => browser?.close(), () => workstation?.close(),
      () => gateway && closeServer(gateway.server), () => rm(base, {recursive: true, force: true})]) {
      try { await dispose(); } catch (error) { failure ||= error; }
    }
  }
  if (failure) throw failure;
}

module.exports = {buildNativeFixture, chromeDriver, webkitDriver, fixtureHome, listen, closeServer, localGateway, launch, eventually, sourcePDF};

if (require.main === module) main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
