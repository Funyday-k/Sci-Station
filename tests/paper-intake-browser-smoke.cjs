"use strict";

const assert = require("node:assert/strict");
const {createHash} = require("node:crypto");
const {mkdtemp, realpath, rm, writeFile} = require("node:fs/promises");
const {tmpdir} = require("node:os");
const path = require("node:path");
const {chromium, expect} = require("playwright/test");
const {listen, closeServer, fixtureHome, launch, sourcePDF} = require("./workstation-workflow-smoke.cjs");

function pdfFixture(label) {
  return Buffer.concat([sourcePDF(), Buffer.from("\n% " + label + "\n")]);
}

async function main(binary) {
  const base = await mkdtemp(path.join(await realpath(tmpdir()), "sci-paper-intake-"));
  const gateway = await listen((req, res) => {
    res.statusCode = 503;
    res.end("Model access is not used by the paper intake fixture.");
  });
  let host, browser;
  try {
    const registration = path.join(base, "fixture.agent.js");
    await writeFile(registration, "// Offline registration fixture.\n");
    const env = await fixtureHome(base, gateway.address().port, registration);
    const probe = await listen();
    const port = probe.address().port;
    await closeServer(probe);
    host = await launch(binary, port, path.join(base, "root"), env, "serve");
    const project = await host.request("/api/research/projects", "POST", {name: "Intake fixture"}, 201);
    const library = new URL("/research", host.origin);
    library.search = new URLSearchParams({view: "papers", project: project.id});
    const paperURL = "https://publisher.example/articles/solar-fixture?section=results";
    const errors = [];
    browser = await chromium.launch({headless: true, executablePath: process.env.SCI_STATION_SMOKE_CHROME});
    const page = await browser.newPage({locale: "en-US", viewport: {width: 900, height: 620}});
    page.on("pageerror", error => errors.push(error.message));
    const modal = page.locator("dialog#modal");
    const importButton = page.locator(".page-head [data-action='new-paper']");
    const linkInput = modal.getByRole("textbox", {name: "Paper link or identifier"});
    const fileInput = modal.getByLabel("Local PDF", {exact: true});
    const details = modal.locator(".paper-import-settings");
    const submit = modal.getByRole("button", {name: "Import papers", exact: true});
    const records = () => host.request("/api/research/papers?project=" + encodeURIComponent(project.id));
    async function importRecord(button, expectedStatus) {
      const responsePromise = page.waitForResponse(response => {
        return response.url() === host.origin + "/api/research/papers" && response.request().method() === "POST";
      });
      await button.click();
      const response = await responsePromise;
      assert.equal(response.status(), expectedStatus);
      return response.json();
    }

    await page.goto(library.href);
    await importButton.click();
    await expect(linkInput).toBeFocused();
    await expect(fileInput).toBeVisible();
    await expect(details).not.toHaveAttribute("open", "");
    await expect(modal.locator("[name=title]")).toBeHidden();
    await expect(modal.locator("[name=authors]")).toBeHidden();
    const submitBox = await submit.boundingBox();
    assert.ok(submitBox.y + submitBox.height <= 620, "the primary action is visible at the initial window size");

    await linkInput.fill("not-a-paper-link");
    await importRecord(submit, 400);
    await expect(modal.getByRole("alert")).toHaveText("Enter an article URL, PDF link, DOI, arXiv ID or INSPIRE link.");
    await expect(linkInput).toHaveValue("not-a-paper-link");
    assert.deepEqual(await records(), []);
    await linkInput.fill(paperURL);
    const linked = await importRecord(submit, 201);
    await expect(modal).toBeHidden();
    assert.equal(linked.title, "publisher.example");
    assert.equal(linked.url, paperURL);
    assert.equal(linked.has_pdf, false);
    assert.deepEqual(linked.project_ids, [project.id]);
    await page.locator("#paper-query").fill("solar-fixture");
    const stored = page.getByRole("link", {name: linked.title, exact: true});
    await stored.click();
    await expect(page.locator("#empty a[href='" + paperURL + "']")).toBeVisible();

    const linkCommand = new URL(library.href);
    linkCommand.searchParams.set("command", "importIdentifier");
    await page.goto(linkCommand.href);
    await expect(linkInput).toBeFocused();
    await linkInput.fill(paperURL);
    assert.equal((await importRecord(submit, 200)).id, linked.id);
    await expect(modal).toBeHidden();

    const fileCommand = new URL(library.href);
    fileCommand.searchParams.set("command", "importPDF");
    await page.goto(fileCommand.href);
    await expect(fileInput).toBeFocused();
    await fileInput.setInputFiles({name: "Broken fixture.pdf", mimeType: "application/pdf", buffer: Buffer.from("not a PDF")});
    await importRecord(submit, 400);
    await expect(modal.getByRole("alert")).toHaveText("Choose a valid PDF file.");
    assert.equal((await records()).length, 1);
    const namedFile = pdfFixture("picker");
    const picker = page.waitForEvent("filechooser");
    await fileInput.click();
    await (await picker).setFiles({name: "Picked fixture.pdf", mimeType: "application/pdf", buffer: namedFile});
    const picked = await importRecord(submit, 201);
    await expect(modal).toBeHidden();
    assert.equal(picked.title, "Picked fixture");
    assert.equal(picked.has_pdf, true);
    assert.equal(picked.file_sha256, createHash("sha256").update(namedFile).digest("hex"));
    assert.deepEqual(picked.project_ids, [project.id]);

    const droppedFile = pdfFixture("drop");
    const transfer = await page.evaluateHandle(base64 => {
      const bytes = Uint8Array.from(atob(base64), char => char.charCodeAt(0));
      const data = new DataTransfer();
      data.items.add(new File([bytes], "Dropped fixture.pdf", {type: "application/pdf"}));
      return data;
    }, droppedFile.toString("base64"));
    await page.locator("#main").dispatchEvent("drop", {dataTransfer: transfer});
    await expect(fileInput).toBeFocused();
    assert.equal(await fileInput.evaluate(el => el.files[0]?.name), "Dropped fixture.pdf");
    await linkInput.fill(paperURL);
    await expect(modal.getByRole("status").filter({hasText: "Clear the file selection"})).toBeVisible();
    await linkInput.fill("");
    const dropped = await importRecord(submit, 201);
    await expect(modal).toBeHidden();
    assert.equal(dropped.title, "Dropped fixture");
    assert.equal(dropped.file_sha256, createHash("sha256").update(droppedFile).digest("hex"));
    assert.deepEqual(dropped.project_ids, [project.id]);
    assert.equal((await records()).length, 3);
    await transfer.dispose();

    const chinese = await browser.newPage({locale: "zh-CN", viewport: {width: 900, height: 620}});
    await chinese.goto(library.href);
    await chinese.locator(".page-head [data-action='new-paper']").click();
    const chineseModal = chinese.locator("dialog#modal");
    await expect(chineseModal.getByRole("textbox", {name: "文献链接或标识符"})).toBeFocused();
    await expect(chineseModal.getByLabel("本地 PDF", {exact: true})).toBeVisible();
    await expect(chineseModal.getByRole("button", {name: "导入文献", exact: true})).toBeVisible();
    assert.deepEqual(errors, []);
    console.log("Paper intake passed for link, picker, drop, duplicate, project scope, and English and Chinese entry controls.");
  } finally {
    await browser?.close();
    await host?.close();
    await closeServer(gateway);
    await rm(base, {recursive: true, force: true});
  }
}

main(process.argv[2]).catch(error => { console.error(error); process.exitCode = 1; });
