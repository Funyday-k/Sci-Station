"use strict";

// Configure an explicit installed Codex path and run on a macOS login session:
// SCI_STATION_TEST_CODEX=/absolute/path/to/codex SCI_STATION_WORKFLOW_SECONDARY=1 \
//   node tests/workstation-cli-edit-smoke.cjs --native /absolute/path/to/Sci-Station.app
// Pass the production binary without --native for headless Chrome. The only
// model endpoints are loopback fixtures. No user profile or token is inherited.
const assert = require("node:assert/strict");
const {mkdtemp, mkdir, readFile, realpath, rm, writeFile} = require("node:fs/promises");
const {tmpdir} = require("node:os");
const path = require("node:path");
const {buildNativeFixture, chromeDriver, webkitDriver, fixtureHome, listen, closeServer,
  localGateway, launch, eventually} = require("./workstation-workflow-smoke.cjs");

const file = "result.md";
const initial = Buffer.from("Fixture heading\noriginal\nUnrelated line\n");
const edited = Buffer.from("Fixture heading\nreviewed\nUnrelated line\n");
const sentinel = Buffer.from("Outside the granted edit range.\n");
const model = "fixture/first";

async function offlineCodexProvider(home) {
  // Same SSE conversation as the native Go test. The installed Codex owns the
  // apply_patch tool, approval request, the approval outcome and file write.
  const calls = [], errors = [];
  const server = await listen(async (req, res) => {
    try {
      assert.equal(req.method, "POST");
      assert.equal(req.url, "/responses");
      assert.equal(req.headers.authorization, undefined, "CLI sent an unexpected credential");
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      const body = Buffer.concat(chunks).toString();
      const input = JSON.parse(body);
      const continuation = input.input.some(item => item.type === "custom_tool_call_output" || item.type === "function_call_output");
      calls.push(continuation ? "after-decision" : "proposal");
      const send = (type, fields) => res.write("event: " + type + "\ndata: " + JSON.stringify({type, ...fields}) + "\n\n");
      res.writeHead(200, {"Content-Type": "text/event-stream"});
      const id = "resp_fixture_" + calls.length;
      send("response.created", {response: {id, status: "in_progress"}});
      const item = continuation ? {
        type: "message", id: "msg_fixture", role: "assistant", content: [{type: "output_text", text: "Finished."}]
      } : {
        type: "custom_tool_call", name: "apply_patch", call_id: "fixture_patch", id: "ct_fixture",
        input: "*** Begin Patch\n*** Update File: result.md\n@@\n-original\n+reviewed\n*** End Patch"
      };
      send("response.output_item.done", {output_index: 0, item});
      send("response.completed", {response: {id, status: "completed", output: []}});
      res.end();
    } catch (error) {
      errors.push(error.message);
      if (!res.headersSent) res.writeHead(400, {"Content-Type": "application/json"});
      res.end(JSON.stringify({error: "Unexpected fixture Codex request"}));
    }
  });
  const config = [
    "model_provider='offline_fixture'",
    "model='gpt-6.2-sol'",
    "approval_policy='on-request'",
    "cli_auth_credentials_store='file'",
    "[model_providers.offline_fixture]",
    "name='Offline fixture'",
    "base_url='http://127.0.0.1:" + server.address().port + "'",
    "wire_api='responses'",
    "requires_openai_auth=false",
    "supports_websockets=false",
    ""
  ].join("\n");
  try {
    const dir = path.join(home, ".codex");
    await mkdir(dir, {mode: 0o700});
    await writeFile(path.join(dir, "config.toml"), config, {mode: 0o600});
    return {server, calls, errors};
  } catch (error) {
    await closeServer(server);
    throw error;
  }
}

async function createScope(app, codex) {
  await app.request("/api/studio/settings", "POST", {cli_paths: {codex}});
  const project = await app.request("/api/research/projects", "POST", {name: "CLI edit fixture"}, 201);
  const input = path.join(project.path, file);
  const other = path.join(project.path, "unselected.txt");
  await Promise.all([writeFile(input, initial, {mode: 0o600}), writeFile(other, sentinel, {mode: 0o600})]);
  const meeting = await app.request("/api/studio/sessions", "POST", {
    topic: "Review the selected file change",
    project_id: project.id,
    members: [{model, effort: "auto"}],
    preset: "work"
  }, 201);
  assert.equal(meeting.project_id, project.id);
  return {project, meeting, input, other};
}

async function openPanel(app, ui, fixture) {
  const destination = app.origin + "/studio?" + new URLSearchParams({
    project: fixture.project.id, session: fixture.meeting.id
  });
  await ui.navigate(destination);
  await ui.click("#cli-edit-open");
  await ui.visible("#cli-edit-dialog");
  const scope = await ui.visible("#cli-edit-scope", fixture.project.id);
  assert.match(scope.text, /CLI edit fixture/);
}

async function assertBytes({input, other}, expected) {
  assert.deepEqual(await readFile(input), expected);
  assert.deepEqual(await readFile(other), sentinel);
}

async function decide(ui, fixture, allow) {
  const available = await eventually(() => ui.evaluate(() => {
    const option = document.querySelector("#cli-edit-provider option[value='codex']");
    return Boolean(option && !option.disabled);
  }), "the meeting detected the installed Codex approval protocol");
  assert.equal(available, true);
  await ui.set("#cli-edit-provider", "codex");
  await ui.set("#cli-edit-paths", file);
  await ui.set("#cli-edit-prompt", "Replace the line original with reviewed in result.md. Leave other bytes unchanged.");
  await ui.click("#cli-edit-submit");
  await ui.visible("#cli-edit-run-title", "Codex");
  await ui.visible("#cli-edit-run-title", "等待审核");
  await ui.visible("#cli-edit-changes h4", file);
  const diff = await ui.visible("#cli-edit-changes pre", "+reviewed");
  const lines = diff.text.split(/\r?\n/).filter(line => /^[+-]/.test(line) && !/^(?:---|\+\+\+)/.test(line));
  assert.deepEqual(lines, ["-original", "+reviewed"]);
  assert.equal(await ui.evaluate(() => document.querySelectorAll("#cli-edit-changes pre").length), 1);
  await assertBytes(fixture, initial);

  const artifacts = process.env.SCI_STATION_SMOKE_ARTIFACTS;
  if (allow && artifacts) {
    await mkdir(artifacts, {recursive: true});
    await ui.screenshot(path.resolve(artifacts, "codex-file-approval.png"));
  }

  await ui.click(allow ? "#cli-edit-accept" : "#cli-edit-decline");
  const outcome = allow ? "CLI 已报告文件变更成功" : "CLI 已报告拒绝文件变更";
  await ui.visible("#cli-edit-run-detail", outcome);
  await ui.visible("#cli-edit-run-title", "CLI 已结束本次任务");
  await assertBytes(fixture, allow ? edited : initial);
}

async function main() {
  assert.equal(process.platform, "darwin");
  const native = process.argv[2] === "--native";
  const sourcePath = process.argv[native ? 3 : 2];
  assert.ok(sourcePath, "Pass the production binary, or --native and the signed workstation app");
  const source = await realpath(sourcePath);
  const executable = process.env.SCI_STATION_TEST_CODEX;
  assert.ok(executable && path.isAbsolute(executable), "Set SCI_STATION_TEST_CODEX to the installed Codex binary");
  const codex = await realpath(executable);
  assert.equal(path.basename(codex), "codex");
  const base = await realpath(await mkdtemp(path.join(tmpdir(), "sci-station-cli-workflow-")));
  let gateway, provider, app, browser, failure;
  try {
    const binary = native ? await buildNativeFixture(source, base) : source;
    const data = path.join(base, "workstation");
    const spec = path.join(base, "Fixture.app", "Contents", "Resources", "sci-station.agent.js");
    await mkdir(path.dirname(spec), {recursive: true});
    await writeFile(spec, "// Magpie registration fixture.\n");
    gateway = await localGateway();
    const environment = await fixtureHome(base, gateway.port, spec);
    const scratch = path.join(base, "scratch");
    await mkdir(scratch, {mode: 0o700});
    // Pass an allowlist to the app, and then to the native CLI. The fixture
    // uses the CLI's normal home-based config discovery inside this test home.
    const inherited = {
      PATH: [path.dirname(codex), "/usr/bin", "/bin", "/opt/homebrew/bin"].join(":"),
      TMPDIR: scratch + "/", LANG: "zh_HK.UTF-8", LC_ALL: "zh_HK.UTF-8",
      NO_PROXY: "127.0.0.1,localhost", RUST_LOG: "off"
    };
    provider = await offlineCodexProvider(environment.HOME);
    const probe = await listen();
    const serverPort = probe.address().port;
    await closeServer(probe);
    const start = async sequence => {
      if (native) {
        const dir = path.join(base, "driver-" + sequence);
        browser = await webkitDriver(dir);
        app = await launch(binary, serverPort, data, {
          ...environment, SCI_STATION_WORKFLOW_DRIVER_DIR: dir,
          ...(process.env.SCI_STATION_WORKFLOW_SECONDARY === "1" ? {SCI_STATION_WORKFLOW_SECONDARY: "1"} : {})
        }, "app", browser.quit, inherited);
      } else {
        app = await launch(binary, serverPort, data, environment, "serve", undefined, inherited);
        browser = await chromeDriver(app.origin);
      }
    };
    await start(1);
    const fixture = await createScope(app, codex);
    await openPanel(app, browser.ui, fixture);
    await decide(browser.ui, fixture, false);
    console.log("PASS installed Codex proposed the displayed diff, and decline preserved every byte");
    await decide(browser.ui, fixture, true);
    console.log("PASS one-time accept reached installed Codex and produced exactly the reviewed file bytes");
    assert.deepEqual(provider.calls, ["proposal", "after-decision", "proposal", "after-decision"]);
    assert.deepEqual(provider.errors, []);
    if (browser.errors) assert.deepEqual(browser.errors, []);
    await browser.close();
    browser = null;
    await app.close();
    app = null;

    await start(2);
    await openPanel(app, browser.ui, fixture);
    await browser.ui.visible("#cli-edit-status", "当前没有待审核的 CLI 请求");
    assert.ok(await browser.ui.evaluate(() =>
      document.getElementById("cli-edit-run").hidden &&
      document.getElementById("cli-edit-proposal").hidden &&
      document.getElementById("cli-edit-accept").disabled));
    await assertBytes(fixture, edited);
    assert.deepEqual(provider.calls, ["proposal", "after-decision", "proposal", "after-decision"]);
    assert.deepEqual(provider.errors, []);
    if (browser.errors) assert.deepEqual(browser.errors, []);
    console.log("PASS after process restart: no active CLI request, no approval control, no model or file replay");
  } catch (error) {
    failure = error;
    if (browser) {
      const status = await browser.ui.evaluate(() => ({
        path: location.pathname,
        status: document.getElementById("cli-edit-status")?.textContent,
        detail: document.getElementById("cli-edit-run-detail")?.textContent,
        title: document.getElementById("cli-edit-run-title")?.textContent
      })).catch(() => null);
      if (status) console.error("Fixture UI at failure:", status);
    }
    if (provider) console.error("Native provider request stages:", provider.calls, provider.errors);
  } finally {
    for (const dispose of [() => browser?.close(), () => app?.close(),
      () => gateway && closeServer(gateway.server), () => provider && closeServer(provider.server),
      () => rm(base, {recursive: true, force: true})]) {
      try { await dispose(); } catch (error) { failure ||= error; }
    }
  }
  if (failure) throw failure;
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
