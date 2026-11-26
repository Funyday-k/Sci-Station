"use strict";

// Run with Playwright against a fresh standalone Sci-Station test binary.
const assert = require("node:assert/strict");
const {mkdtemp, realpath, rm} = require("node:fs/promises");
const {tmpdir} = require("node:os");
const path = require("node:path");
const {chromium, expect} = require("playwright/test");
const {listen, closeServer, launch, sourcePDF} = require("./workstation-workflow-smoke.cjs");

async function saveAppearance(page, origin, {mode, size, system}) {
  await page.emulateMedia({colorScheme: system});
  const loaded = page.waitForResponse(response => response.url().endsWith("/api/studio/settings") &&
    response.request().method() === "GET" && response.ok());
  await page.goto(origin + "/studio?view=settings");
  await loaded;
  await page.locator("#settings-tab-appearance").click();
  await page.locator("#setting-appearance").selectOption(mode);
  await page.locator("#setting-text-size").selectOption(size);
  await page.locator('label.theme-choice:has([value="blue"])').click();
  const saved = page.waitForResponse(response => response.url().endsWith("/api/studio/settings") &&
    response.request().method() === "POST");
  await page.locator("#save-settings-appearance").click();
  const response = await saved;
  assert.ok(response.ok(), await response.text());
  await page.waitForFunction(({mode, size}) => localStorage.getItem("studio.appearance") === mode &&
    localStorage.getItem("studio.text-size") === size && localStorage.getItem("studio.color-theme") === "blue", {mode, size});
}

async function contrast(locator) {
  return locator.evaluate(node => {
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 1;
    const context = canvas.getContext("2d");
    function colorBytes(color) {
      context.clearRect(0, 0, 1, 1);
      context.fillStyle = color;
      context.fillRect(0, 0, 1, 1);
      return context.getImageData(0, 0, 1, 1).data;
    }
    function luminance([r, g, b]) {
      const linear = [r, g, b].map(byte => {
        const srgb = byte / 255;
        return srgb <= .04045 ? srgb / 12.92 : ((srgb + .055) / 1.055) ** 2.4;
      });
      return .2126 * linear[0] + .7152 * linear[1] + .0722 * linear[2];
    }
    let background;
    for (let ancestor = node; ancestor; ancestor = ancestor.parentElement) {
      const color = colorBytes(getComputedStyle(ancestor).backgroundColor);
      if (color[3]) {
        background = luminance(color);
        break;
      }
    }
    if (background === undefined) throw Error("Expected a painted background");
    const text = luminance(colorBytes(getComputedStyle(node).color));
    return (Math.max(background, text) + .05) / (Math.min(background, text) + .05);
  });
}

async function assertReadable(locator, expectedSize) {
  await expect(locator).toBeVisible();
  await expect(locator).toHaveCSS("font-size", expectedSize);
  const actual = await contrast(locator);
  assert.ok(actual >= 4.5, "Text contrast below 4.5:1 for " + await locator.innerText() + " (" + actual.toFixed(2) + ":1)");
}

async function smoke(binary) {
  const base = await mkdtemp(path.join(await realpath(tmpdir()), "sci-workbench-appearance-"));
  let host, browser;
  try {
    const probe = await listen();
    const {port} = probe.address();
    await closeServer(probe);
    host = await launch(binary, port, path.join(base, "root"), {
      HOME: base,
      XDG_CONFIG_HOME: path.join(base, "config"),
      SCI_STATION_WORKSPACE_REGISTRY: path.join(base, "registry")
    }, "serve");
    const {origin, request} = host;
    const project = await request("/api/research/projects", "POST", {name: "Solar contrast fixture"}, 201);
    const task = await request("/api/research/tasks", "POST", {
      title: "Check the rendered contrast", projectIds: [project.id], status: "inProgress",
      priority: "high", dueDate: "2027-01-05", description: "Supplementary task description."
    }, 201);
    const upload = new FormData();
    upload.append("metadata", JSON.stringify({title: "Solar capture fixture", authors: ["Fixture Author"], project_ids: [project.id], citekey: "FixtureContrast2026"}));
    upload.append("file", new Blob([sourcePDF()], {type: "application/pdf"}), "fixture.pdf");
    const paper = await request("/api/research/papers", "POST", upload, 201);
    browser = await chromium.launch({headless: true, executablePath: process.env.SCI_STATION_SMOKE_CHROME});
    const page = await browser.newPage({locale: "zh-CN", viewport: {width: 1360, height: 940}});
    await page.route("**/*", route => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));

    for (const theme of [
      {mode: "dark", size: "extra-large", system: "light", text: "18px", small: "17px",
        paper: "rgb(27, 29, 33)", surface: "rgb(32, 35, 40)", inset: "rgb(40, 44, 50)", accent: "rgb(146, 197, 246)"},
      {mode: "light", size: "standard", system: "dark", text: "14px", small: "13px",
        paper: "rgb(247, 247, 248)", surface: "rgb(255, 255, 255)", inset: "rgb(241, 242, 244)", accent: "rgb(34, 95, 152)"}
    ]) {
      await saveAppearance(page, origin, theme);
      await page.goto(origin + "/research?view=tasks");
      await expect(page.locator("html")).toHaveCSS("color-scheme", theme.mode);
      await expect(page.locator("body")).toHaveCSS("background-color", theme.paper);
      await expect(page.locator("#workspace-sidebar")).toHaveCSS("background-color", theme.inset);
      await expect(page.locator("#workspace-sidebar [data-workspace-nav]")).toBeVisible();
      const item = page.locator(".row").filter({has: page.locator(`[data-action="edit-task"][data-id="${task.id}"]`)});
      await expect(item.locator(".row-facts")).toContainText(project.name);
      await expect(item.locator(".row-facts")).toContainText(task.dueDate);
      await assertReadable(item.locator(".title"), theme.text);
      await assertReadable(item.locator(".row-facts"), theme.text);
      await assertReadable(item.locator(".status-tag"), theme.text);
      await assertReadable(item.locator(".meta"), theme.small);
      const taskType = page.locator(".task-filters select").first();
      await expect(taskType).toHaveCSS("background-color", theme.surface);
      await assertReadable(taskType, theme.text);

      await page.goto(origin + "/research?view=papers");
      await assertReadable(page.locator(".library-paper-title").filter({hasText: paper.title}), theme.text);
      await expect(page.locator(".library-table")).not.toContainText(paper.citekey);
      await page.locator(`[data-action="edit-paper"][data-id="${paper.id}"]`).click();
      await expect(page.locator('#modal input[name="citekey"]')).toHaveValue(paper.citekey);

      await page.locator("#modal-close").click();
      await page.locator('[data-workspace-nav] a[data-section="lab"]').click();
      await expect(page.locator("body")).toHaveAttribute("data-workspace-surface", "lab");
      await expect(page.locator("html")).toHaveCSS("color-scheme", theme.mode);
      await expect(page.locator("body")).toHaveCSS("background-color", theme.paper);
      await expect(page.locator(".workspace-bar")).toHaveCSS("background-color", theme.surface);
      await expect(page.locator("#workspace-sidebar")).toHaveCSS("background-color", theme.inset);
      await expect(page.locator(".shell .card").first()).toHaveCSS("background-color", theme.surface);
      await expect(page.locator("#question")).toHaveCSS("background-color", theme.surface);
      await assertReadable(page.locator("#question"), theme.text);
      await assertReadable(page.locator('label:has(#question)'), theme.small);
      await page.locator("#project").selectOption(project.id);
      await page.locator("#lab-run-mode").selectOption("roundtable");
      await expect(page.locator("#handoff")).toBeEnabled();
      await expect(page.locator("#handoff")).toHaveCSS("background-color", theme.accent);
      await assertReadable(page.locator("#handoff"), theme.text);

      const assistant = page.locator("#shell-assist");
      if (await assistant.getAttribute("aria-pressed") !== "true") await assistant.click();
      await expect(page.locator("#context-rail")).toHaveCSS("background-color", theme.inset);
      await assertReadable(page.locator("#rail-prompt"), theme.text);
      if (process.env.SCI_STATION_SMOKE_SCREENSHOTS && theme.mode === "dark") {
        await page.locator(".section-head", {hasText: "本次研究"}).scrollIntoViewIfNeeded();
        await page.screenshot({path: path.join(process.env.SCI_STATION_SMOKE_SCREENSHOTS, "appearance-lab.png")});
        await page.setViewportSize({width: 900, height: 620});
        await page.goto(origin + "/research?view=tasks");
        await expect(item.locator(".status-tag")).toBeVisible();
        await page.screenshot({path: path.join(process.env.SCI_STATION_SMOKE_SCREENSHOTS, "appearance-tasks.png")});
        await page.setViewportSize({width: 1360, height: 940});
      }

      await page.goto(origin + "/reader?paper=" + paper.id + "&project=" + project.id);
      await expect(page.locator("#title")).toHaveText(paper.title);
      await expect(page.locator("html")).toHaveCSS("color-scheme", theme.mode);
      await expect(page.locator("body")).toHaveCSS("background-color", theme.paper);
      await expect(page.locator("#workspace-sidebar")).toHaveCSS("background-color", theme.inset);
      await expect(page.locator("#workspace-sidebar")).toHaveCSS("padding-left", "0px");
      await expect(page.locator("#workspace-sidebar")).toHaveCSS("padding-right", "0px");
      await expect(page.locator(".titlebar")).toHaveCSS("background-color", theme.surface);
      await expect(page.locator("#viewport")).toHaveCSS("background-color", theme.inset);
      await expect(page.locator("#pageSurface")).toHaveCSS("background-color", "rgb(255, 255, 255)");
      await assertReadable(page.locator("#byline"), theme.small);
      await expect(page.locator("#reader-inspector")).toBeHidden();
      await page.locator("#reader-inspect").click();
      await expect(page.locator("#reader-inspector")).toHaveCSS("background-color", theme.surface);
      await page.locator("#notesTab").click();
      await assertReadable(page.locator("#notes"), theme.text);
      await page.locator("#reader-close").click();
      await expect(page.locator("#reader-inspect")).toBeFocused();
    }
    assert.deepEqual(errors, []);
    console.log("Saved appearance overrides both OS modes in the workbench, library, Lab, reader, and shared sidebar. Text, controls, status and accents passed.");
  } finally {
    await browser?.close();
    await host?.close();
    await rm(base, {recursive: true, force: true});
  }
}

smoke(process.argv[2]).catch(error => { console.error(error); process.exitCode = 1; });
