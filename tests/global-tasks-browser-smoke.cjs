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
const {chromium, expect} = require("playwright/test");

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
  const tagName = "Review, findings";
  const projectTaskTitle = "Review the project findings";
  const unrelatedTitle = "Unrelated task";
  let browser;
  let taskID, projectID;
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

    async function saveTag(action) {
      const writing = page.waitForResponse(response => response.url().endsWith("/api/research/task-tags") &&
        response.request().method() === "PATCH");
      await modal.getByRole("button", {name: action}).click();
      const response = await writing;
      assert.ok(response.ok(), await response.text());
      return response.json();
    }
    async function assertTagColor(row, color, backgroundColor) {
      const chip = row.locator(".task-label").getByText(tagName, {exact: true});
      await expect(chip).toHaveCSS("color", color);
      await expect(chip).toHaveCSS("background-color", backgroundColor);
    }

    await withServer(binary, data, origin, async () => {
      await page.goto(origin + "/research");
      await page.locator(".dashboard-calendar-links a").first().click();
      await page.locator(".calendar-head").waitFor();
      assert.equal(new URL(page.url()).searchParams.get("tab"), "calendar");
      await page.reload();
      await page.locator(".calendar-head").waitFor();

      const fixturePaper = await page.request.post(origin + "/api/research/papers", {
        headers: {"X-Roundtable": "1"}, data: {title: "ab星cdef"}
      });
      assert.ok(fixturePaper.ok(), await fixturePaper.text());
      await page.goto(origin + "/research?view=papers");
      const query = page.locator("#paper-query");
      await query.fill("abcdef");
      const input = await query.elementHandle();
      await query.evaluate(el => el.setSelectionRange(2, 2));
      await page.keyboard.type("xy");
      assert.deepEqual(await input.evaluate(el => [el === document.activeElement, el.value, el.selectionStart, el.selectionEnd]),
        [true, "abxycdef", 4, 4]);
      await query.evaluate(el => el.setSelectionRange(2, 4));
      const ime = await page.context().newCDPSession(page);
      try {
        await ime.send("Input.imeSetComposition", {text: "星", selectionStart: 1, selectionEnd: 1});
        await ime.send("Input.insertText", {text: "星"});
      } finally {
        await ime.detach();
      }
      await page.locator("#paper-results").getByRole("link", {name: "ab星cdef", exact: true}).waitFor();
      assert.deepEqual(await input.evaluate(el => [el === document.activeElement, el.value, el.selectionStart, el.selectionEnd]),
        [true, "ab星cdef", 3, 3]);
      await page.goto(tasksURL);
      await page.getByRole("button", {name: "新建任务"}).click();
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
      projectID = project.id;
      await page.reload();
      await taskRow.click();
      await modal.getByRole("checkbox", {name: projectName}).check();
      const associated = await saveTask();
      assert.equal(associated.id, taskID);
      assert.deepEqual(associated.projectIds, [project.id]);

      await page.getByRole("combobox", {name: "项目", exact: true}).selectOption(project.id);
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

      const scope = page.getByRole("combobox", {name: "项目", exact: true});
      await scope.selectOption(project.id);
      await page.waitForURL(url => url.searchParams.get("project") === project.id);
      await page.getByRole("button", {name: "切换到列表"}).waitFor();
      assert.equal(await page.getByRole("button", {name: "已完成", exact: true}).getAttribute("aria-pressed"), "true");
      await calendarTask.waitFor({state: "hidden"});
      await scope.selectOption("");
      await calendarTask.waitFor();

      await page.goto(tasksURL);
      await page.locator(".more-actions summary").click();
      await page.getByRole("button", {name: "管理任务标签"}).click();
      await modal.getByRole("textbox", {name: "标签名称"}).fill(tagName);
      await modal.getByLabel("背景色").fill("#123456");
      await modal.getByLabel("文字色").fill("#fefefe");
      const createdTag = await saveTag("保存标签");
      assert.deepEqual(createdTag.tags.map(tag => tag.name), [tagName]);
      await modal.getByRole("status").filter({hasText: "标签已保存"}).waitFor();
      await modal.getByLabel("背景色").fill("#112233");
      await modal.getByLabel("文字色").fill("#abcdef");
      const updatedTag = await saveTag("保存标签");
      assert.deepEqual(updatedTag.tags, [{name: tagName, definition: {color: "#112233", textColor: "#ABCDEF"}, inUse: false}]);
      await modal.getByRole("status").filter({hasText: "标签已保存"}).waitFor();
      await modal.getByRole("button", {name: "关闭", exact: true}).click();
      await page.getByRole("button", {name: "已完成", exact: true}).click();
      await taskRow.click();
      await modal.getByRole("checkbox", {name: tagName}).check();
      assert.deepEqual((await saveTask()).tags, [tagName]);
      await assertTagColor(taskRow, "rgb(171, 205, 239)", "rgb(17, 34, 51)");

      await page.goto(`${tasksURL}&project=${projectID}`);
      for (const name of [projectTaskTitle, unrelatedTitle]) {
        await page.getByRole("button", {name: "新建任务"}).click();
        await modal.locator('[name="title"]').fill(name);
        if (name === projectTaskTitle) await modal.getByRole("checkbox", {name: tagName}).check();
        else await modal.locator('[name="tags"]').fill("existing-style entry, fieldwork");
        const saved = await saveTask();
        assert.deepEqual(saved.tags, name === projectTaskTitle ? [tagName] : ["existing-style entry", "fieldwork"]);
      }
      const projectRow = page.locator('[data-action="edit-task"]').filter({hasText: projectTaskTitle});
      await assertTagColor(projectRow, "rgb(171, 205, 239)", "rgb(17, 34, 51)");
      await page.getByRole("combobox", {name: "任务标签"}).selectOption(tagName);
      await projectRow.waitFor();
      await page.getByText(unrelatedTitle, {exact: true}).waitFor({state: "hidden"});
    });

    await withServer(binary, data, origin, async () => {
      await page.goto(`${tasksURL}&tab=calendar`);
      await page.getByRole("button", {name: `14:30 ${title}`}).click();
      assert.equal(await modal.locator('[name="title"]').inputValue(), title);
      assert.equal(await modal.locator('[name="status"]').inputValue(), "done");
      assert.equal(await modal.locator('[name="projectIds"]:checked').count(), 0);
      const response = await page.request.get(`${origin}/api/research/tasks/${taskID}`);
      assert.ok(response.ok(), await response.text());
      assert.equal((await response.json()).id, taskID);
      assert.equal(await modal.getByRole("checkbox", {name: tagName}).isChecked(), true);
      await page.goto(tasksURL);
      await page.getByRole("button", {name: "全部", exact: true}).click();
      await page.getByRole("combobox", {name: "任务标签"}).selectOption(tagName);
      const projectRow = page.locator('[data-action="edit-task"]').filter({hasText: projectTaskTitle});
      await assertTagColor(taskRow, "rgb(171, 205, 239)", "rgb(17, 34, 51)");
      await assertTagColor(projectRow, "rgb(171, 205, 239)", "rgb(17, 34, 51)");
      await page.getByText(unrelatedTitle, {exact: true}).waitFor({state: "hidden"});
      await page.locator(".more-actions summary").click();
      await page.getByRole("button", {name: "管理任务标签"}).click();
      await modal.getByRole("button", {name: tagName}).click();
      const removed = await saveTag("删除自定义标签");
      assert.deepEqual(removed.tags.find(tag => tag.name === tagName), {name: tagName, inUse: true});
      await modal.getByRole("status").filter({hasText: "已删除自定义标签"}).waitFor();
      await modal.getByRole("button", {name: "删除自定义标签"}).waitFor({state: "hidden"});
      await modal.getByRole("button", {name: "关闭", exact: true}).click();
      await page.getByRole("combobox", {name: "任务标签"}).selectOption(tagName);
      await taskRow.getByText(tagName, {exact: true}).waitFor();
      await projectRow.getByText(tagName, {exact: true}).waitFor();
      assert.notEqual(await projectRow.locator(".task-label").evaluate(el => getComputedStyle(el).backgroundColor), "rgb(17, 34, 51)");
      await projectRow.click();
      assert.equal(await modal.getByRole("checkbox", {name: tagName}).isChecked(), true);
    });
    assert.deepEqual(errors, []);
    console.log("PASS global task creation, unassignment, status/calendar, shared custom tags, filtering, and server restart in headless Chrome");
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
