"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const {chromium} = require("playwright");

async function main(origin, project, other, log, approved, denied, cancelled) {
  const browser = await chromium.launch({headless: true, executablePath: process.env.SCI_STATION_SMOKE_CHROME});
  try {
    const page = await browser.newPage({locale: "zh-CN", viewport: {width: 1440, height: 900}});
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.addInitScript(fs.readFileSync(0, "utf8"));
    await page.addInitScript(([owner, run]) => {
      if (location.pathname === "/research") localStorage.setItem("sci.shell.conversation." + owner, run);
    }, [project, cancelled]);

    const api = session => origin + "/api/studio/sessions/" + session;
    const run = id => page.request.post(api(id) + "/run", {
      headers: {"X-Roundtable": "1"},
      data: {expected_round: 0},
    }).then(async response => assert.equal(response.status(), 202, await response.text()));
    const state = id => page.request.get(api(id)).then(response => response.json());
    const calls = () => fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n") : [];
    const observedSessions = [];
    page.on("request", request => {
      if (request.method() === "POST" && request.url().endsWith("/read-review")) {
        observedSessions.push({url: request.url(), payload: request.postDataJSON()});
      }
    });

    async function verifyRequest(panel) {
      await panel.getByText("模型申请一次性科研读取", {exact: true}).waitFor();
      await panel.getByText(project, {exact: false}).waitFor();
      await panel.getByText("fixture", {exact: true}).waitFor();
      await panel.getByText("lookup", {exact: true}).waitFor();
      await panel.getByText(/server\.py/).waitFor();
      await panel.getByText("调用服务端只读工具 · tools/call").waitFor();
      await panel.getByText("JSON 参数", {exact: true}).waitFor();
      assert.equal(await panel.locator("dd pre").last().textContent(), '{"query":"gamma","sample_id":9007199254740993}');
    }

    await run(approved);
    await page.goto(origin + "/studio?project=" + project + "&session=" + approved);
    const studio = page.locator("#studio-read-review");
    await verifyRequest(studio);
    assert.deepEqual(calls(), []);
    if (process.env.SCI_STATION_MCP_REVIEW_SCREENSHOT) {
      await page.screenshot({path: process.env.SCI_STATION_MCP_REVIEW_SCREENSHOT});
    }
    await studio.getByRole("button", {name: "允许一次"}).click();
    await page.getByText("The model received the approved gamma result.").waitFor();
    const approvedCalls = calls();
    assert.equal(approvedCalls.filter(method => method === "tools/call").length, 1);

    await run(denied);
    await page.goto(origin + "/lab?project=" + project + "&run=" + denied);
    const lab = page.locator("#lab-read-review");
    await verifyRequest(lab);
    // A project switch clears the older request and emits no approval.
    await page.locator("#project").selectOption(other);
    await lab.waitFor({state: "hidden"});
    assert.equal(observedSessions.length, 1);
    assert.deepEqual(calls(), approvedCalls);
    await page.goto(origin + "/lab?project=" + project + "&run=" + denied);
    await verifyRequest(lab);
    await lab.getByRole("button", {name: "拒绝"}).click();
    await page.getByText("The model received no connector result.").waitFor();
    assert.deepEqual(calls(), approvedCalls);

    await run(cancelled);
    await page.goto(origin + "/research?project=" + project);
    if (await page.locator("#shell-assist").getAttribute("aria-pressed") !== "true") {
      await page.locator("#shell-assist").click();
    }
    const rail = page.locator("#rail-read-review");
    await verifyRequest(rail);
    await page.locator("#rail-stop").click();
    await rail.waitFor({state: "hidden"});
    await page.waitForFunction(async url => (await fetch(url).then(response => response.json())).status !== "running", api(cancelled));
    assert.notEqual((await state(cancelled)).rounds[0].turns[0].text, "The model received the approved gamma result.");
    assert.deepEqual(calls(), approvedCalls);
    assert.deepEqual(observedSessions.map(entry => [entry.url, entry.payload.project_id, entry.payload.action]), [
      [api(approved) + "/read-review", project, "allow"],
      [api(denied) + "/read-review", project, "deny"],
    ]);
    assert.deepEqual(errors, []);
    console.log("Roundtable approval, AI Lab rejection and project switch, AI side panel cancellation, exact JSON, connector invocation and model result passed.");
  } finally {
    await browser.close();
  }
}

main(...process.argv.slice(2)).catch(error => {console.error(error); process.exitCode = 1;});
