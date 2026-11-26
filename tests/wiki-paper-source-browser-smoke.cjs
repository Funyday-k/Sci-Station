"use strict";

// Run against a Sci-Station binary with Playwright available to Node.
const assert = require("node:assert/strict");
const {mkdtemp, realpath, rm} = require("node:fs/promises");
const {tmpdir} = require("node:os");
const path = require("node:path");
const {chromium, expect} = require("playwright/test");
const {closeServer, fixtureHome, launch, listen, sourcePDF} = require("./workstation-workflow-smoke.cjs");

async function main(binary) {
  assert.ok(binary, "Pass the Sci-Station binary path");
  const fixture = await mkdtemp(path.join(await realpath(tmpdir()), "sci-wiki-paper-"));
  let app, browser;
  try {
    const portReservation = await listen();
    const port = portReservation.address().port;
    await closeServer(portReservation);
    const env = await fixtureHome(fixture, 1, path.join(fixture, "unused-agent.js"));
    const start = () => launch(binary, port, path.join(fixture, "root"), env, "serve");
    app = await start();
    const first = await app.request("/api/research/projects", "POST", {name: "Wiki fixture project"}, 201);
    const second = await app.request("/api/research/projects", "POST", {name: "Other fixture project"}, 201);
    const upload = new FormData();
    upload.append("metadata", JSON.stringify({title: "Shared Wiki fixture paper", project_ids: [first.id, second.id]}));
    upload.append("file", new Blob([sourcePDF()], {type: "application/pdf"}), "fixture.pdf");
    const paper = await app.request("/api/research/papers", "POST", upload, 201);
    const paperAPI = `/api/research/papers/${paper.id}`;
    const notesAPI = `/api/research/projects/${first.id}/notes`;

    browser = await chromium.launch({headless: true, executablePath: process.env.SCI_STATION_SMOKE_CHROME});
    const page = await browser.newPage({viewport: {width: 1200, height: 850}, locale: "zh-CN"});
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.route("**/*", route => route.request().url().startsWith(app.origin + "/") ? route.continue() : route.abort());
    const modal = page.locator("#modal");
    const sourceLink = modal.locator('a[href^="/reader"]');
    const submit = modal.locator('button[type="submit"]');
    const close = () => modal.locator("#modal-close").click();
    const papers = project => page.goto(`${app.origin}/research?view=papers&project=${project.id}`);
    const editPaper = () => page.locator(`[data-action="edit-paper"][data-id="${paper.id}"]`).click();
    const openSharedDelete = async () => {
      await editPaper();
      await modal.locator(`[data-action="confirm-delete"][data-id="paper:${paper.id}"]`).click();
      await expect(modal).toContainText("Other fixture project");
      await expect(modal).toContainText("Wiki fixture project");
      await expect(modal).toContainText(/本地 PDF|Local PDF/);
      await expect(modal).toContainText(/1 个 Wiki 页面|1 Wiki page/);
    };

    await papers(first);
    await page.locator(`[data-action="open-paper-wiki"][data-id="${paper.id}"]`).click();
    await submit.click();
    await expect(sourceLink).toBeVisible();
    const [note] = await app.request(notesAPI);
    await close();

    await editPaper();
    await modal.locator('[data-action="confirm-paper-unlink"]').click();
    await expect(modal).toContainText("Wiki fixture project");
    await expect(modal).not.toContainText("Other fixture project");
    await submit.click();
    await expect(modal).toBeHidden();
    assert.deepEqual((await app.request(paperAPI)).project_ids, [second.id]);
    const openNote = async () => {
      await page.goto(`${app.origin}/research?view=notes&project=${first.id}`);
      await page.locator(`[data-action="read-note"][data-id="${note.id}"]`).click();
    };
    await openNote();
    await expect(modal.locator('[data-wiki-paper-status="outside_project"]')).toBeVisible();
    await sourceLink.click();
    await expect(page.locator("#title")).toHaveText(paper.title);
    const readerURL = new URL(page.url());
    assert.equal(readerURL.pathname, "/reader");
    assert.equal(readerURL.searchParams.get("paper"), paper.id);
    assert.equal(readerURL.searchParams.has("project"), false);

    await papers(second);
    await openSharedDelete();
    if (process.env.SCI_STATION_SMOKE_ARTIFACTS) {
      await page.screenshot({path: path.join(process.env.SCI_STATION_SMOKE_ARTIFACTS, "shared-paper-removal.png")});
    }
    await app.request(notesAPI, "POST", {title: "Added during confirmation", paperId: paper.id}, 201);
    await submit.click();
    await expect(modal.locator("[data-error]")).toContainText("引用范围已变化");
    assert.equal((await app.request(paperAPI)).id, paper.id);
    await close();

    await editPaper();
    await modal.locator('[data-action="confirm-delete"]').click();
    await expect(modal).toContainText(/2 个 Wiki 页面|2 Wiki page/);
    await submit.click();
    await expect(modal).toBeHidden();
    await app.request(paperAPI, "GET", undefined, 404);

    await app.close();
    app = await start();
    await page.setViewportSize({width: 900, height: 620});
    await openNote();
    await expect(modal.locator('[data-wiki-paper-status="missing"]')).toContainText(paper.id);
    await expect(sourceLink).toHaveCount(0);
    if (process.env.SCI_STATION_SMOKE_ARTIFACTS) {
      await page.screenshot({path: path.join(process.env.SCI_STATION_SMOKE_ARTIFACTS, "retained-wiki-source.png")});
    }
    await modal.locator('[data-action="edit-note"]').click();
    const body = modal.locator("#note-body");
    await expect(body).toHaveValue(note.body);
    const changed = note.body + "\nReviewed from the Wiki editor after deletion.\n";
    await body.fill(changed);
    const saved = page.waitForRequest(req => req.url().endsWith(notesAPI + "/" + note.id) && req.method() === "PATCH");
    await submit.click();
    assert.equal(Object.hasOwn((await saved).postDataJSON(), "paperId"), false);
    await expect(modal).toBeHidden();
    const current = await app.request(notesAPI + "/" + note.id);
    assert.equal(current.paperId, paper.id);
    assert.equal(current.paperStatus, "missing");
    assert.equal(current.body, changed);
    assert.deepEqual(errors, []);
    console.log("Template Wiki, scoped removal, shared impact and stale-confirmation handling, source retention and editor save passed in Chromium.");
  } finally {
    await browser?.close();
    await app?.close();
    await rm(fixture, {recursive: true, force: true});
  }
}

main(process.argv[2]).catch(error => {
  console.error(error);
  process.exitCode = 1;
});
