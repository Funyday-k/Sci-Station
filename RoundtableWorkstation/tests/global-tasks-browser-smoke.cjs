"use strict";

// Run against a standalone Sci-Station binary with Playwright available to Node.
// SCI_STATION_SMOKE_CHROME can select an installed Chrome or Chromium executable.
const assert = require("node:assert/strict");
const {spawn} = require("node:child_process");
const {once} = require("node:events");
const {mkdtemp, realpath, rm} = require("node:fs/promises");
const net = require("node:net");
const {tmpdir} = require("node:os");
const path = require("node:path");
const {setTimeout: delay} = require("node:timers/promises");
const {chromium} = require("playwright");

async function freePort() {
  const listener = net.createServer().listen(0, "127.0.0.1");
  await once(listener, "listening");
  const {port} = listener.address();
  await new Promise((resolve, reject) => listener.close(error => error ? reject(error) : resolve()));
  return port;
}

async function withServer(binary, data, origin, exercise) {
  const server = spawn(binary, ["serve", "-data-dir", data, "-port", new URL(origin).port], {stdio: "inherit"});
  const exiting = once(server, "exit");
  try {
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline && server.exitCode === null) {
      const response = await fetch(`${origin}/api/health`, {signal: AbortSignal.timeout(500)}).catch(() => null);
      if (response?.ok && (await response.json()).name === "sci-station") {
        await exercise();
        return;
      }
      await delay(50);
    }
    throw new Error("Sci-Station did not start on the fixture port");
  } finally {
    server.kill("SIGTERM");
    const kill = setTimeout(() => server.kill("SIGKILL"), 9000);
    try {
      const [code] = await exiting;
      assert.equal(code, 0, "the fixture failed to shut down cleanly");
    } finally {
      clearTimeout(kill);
    }
  }
}

async function smoke(binary) {
  const data = await mkdtemp(path.join(await realpath(tmpdir()), "sci-global-tasks-"));
  const origin = `http://127.0.0.1:${await freePort()}`;
  const tasksURL = `${origin}/research?view=tasks`;
  const title = "Verify the global calculation";
  const projectName = "Fixture project";
  let browser;
  let taskID;
  const errors = [];
  try {
    browser = await chromium.launch({headless: true, executablePath: process.env.SCI_STATION_SMOKE_CHROME});
    const page = await browser.newPage({timezoneId: "UTC"});
    page.setDefaultTimeout(10000);
    page.on("pageerror", error => errors.push(error.message));
    await page.route("**/*", route => route.request().url().startsWith(`${origin}/`) ? route.continue() : route.abort());
    const modal = page.locator("#modal");
    const taskRow = page.locator('[data-action="edit-task"]').filter({hasText: title});
    async function saveTask() {
      const saved = page.waitForResponse(response => response.url().includes("/api/research/") &&
        response.url().includes("/tasks") && ["POST", "PATCH"].includes(response.request().method()));
      await modal.getByRole("button", {name: "保存任务"}).click();
      const response = await saved;
      assert.ok(response.ok(), await response.text());
      await modal.waitFor({state: "hidden"});
      return response.json();
    }

    await withServer(binary, data, origin, async () => {
      await page.goto(tasksURL);
      await page.getByRole("button", {name: "添加任务"}).click();
      await modal.locator('[name="title"]').fill(title);
      await modal.locator('[name="dueDate"]').fill(new Date().toISOString().slice(0, 10));
      await modal.locator('[name="dueTime"]').fill("14:30");
      const created = await saveTask();
      taskID = created.id;
      assert.deepEqual(created.projectIds, []);
      await taskRow.waitFor();
      assert.match(await taskRow.innerText(), /未分配/);

      const projectResponse = await page.request.post(`${origin}/api/research/projects`, {
        headers: {"X-Roundtable": "1"}, data: {name: projectName}
      });
      assert.ok(projectResponse.ok(), await projectResponse.text());
      const project = await projectResponse.json();
      await page.reload();
      await taskRow.click();
      await modal.getByRole("checkbox", {name: projectName}).check();
      const associated = await saveTask();
      assert.equal(associated.id, taskID);
      assert.deepEqual(associated.projectIds, [project.id]);

      await page.goto(`${tasksURL}&project=${project.id}`);
      await taskRow.click();
      await modal.getByRole("checkbox", {name: projectName}).uncheck();
      const unassigned = await saveTask();
      assert.equal(unassigned.id, taskID);
      assert.deepEqual(unassigned.projectIds, []);
      await taskRow.waitFor({state: "hidden"});

      await page.goto(tasksURL);
      await page.getByRole("button", {name: `完成：${title}`, exact: true}).click();
      await taskRow.waitFor({state: "hidden"});
      await page.getByRole("button", {name: "已完成", exact: true}).click();
      await taskRow.waitFor();
      await page.getByRole("button", {name: "切换到月历"}).click();
      const calendarTask = page.getByRole("button", {name: `14:30 ${title}`});
      await calendarTask.waitFor();
      assert.match(await calendarTask.getAttribute("class"), /\bcompleted\b/);
    });

    await withServer(binary, data, origin, async () => {
      await page.goto(`${tasksURL}&calendar=1`);
      await page.getByRole("button", {name: `14:30 ${title}`}).click();
      assert.equal(await modal.locator('[name="title"]').inputValue(), title);
      assert.equal(await modal.locator('[name="status"]').inputValue(), "done");
      assert.equal(await modal.locator('[name="projectIds"]:checked').count(), 0);
      const response = await page.request.get(`${origin}/api/research/tasks/${taskID}`);
      assert.ok(response.ok(), await response.text());
      assert.equal((await response.json()).id, taskID);
    });
    assert.deepEqual(errors, []);
    console.log("PASS global task creation, unassignment, status/calendar, and server restart in headless Chrome");
  } finally {
    await browser?.close();
    await rm(data, {recursive: true, force: true});
  }
}

if (!process.argv[2]) {
  console.error("Usage: node tests/global-tasks-browser-smoke.cjs /path/to/sci-station");
  process.exitCode = 2;
} else {
  smoke(path.resolve(process.argv[2])).catch(error => {
    console.error(error);
    process.exitCode = 1;
  });
}
