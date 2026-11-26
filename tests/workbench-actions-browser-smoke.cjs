"use strict";
const assert = require("node:assert/strict");
const {mkdir, mkdtemp, realpath, rm, writeFile} = require("node:fs/promises");
const path = require("node:path");
const {tmpdir} = require("node:os");
const {chromium} = require("playwright");
const {listen, closeServer, localGateway, fixtureHome, launch, sourcePDF} = require("./workstation-workflow-smoke.cjs");

async function main(binary) {
  const base = await mkdtemp(path.join(await realpath(tmpdir()), "sci-workbench-actions-"));
  const gateway = await localGateway();
  let app, browser;
  try {
    const spec = path.join(base, "Smoke.app", "Contents", "Resources", "sci-station.agent.js");
    await mkdir(path.dirname(spec), {recursive: true});
    await writeFile(spec, "// Offline registration fixture.\n");
    const env = await fixtureHome(base, gateway.port, spec);
    const probe = await listen();
    const port = probe.address().port;
    await closeServer(probe);
    app = await launch(binary, port, path.join(base, "root"), env, "serve");

    const project = await app.request("/api/research/projects", "POST", {name: "Action fixture"}, 201);
    const notesPath = "/api/research/projects/" + project.id + "/notes";
    await app.request(notesPath, "POST", {title: "Capture", body: "# Capture", aliases: ["Solar capture"]}, 201);
    await app.request(notesPath, "POST", {title: "Evaporation", body: "# Evaporation"}, 201);
    async function importPDF(title) {
      const upload = new FormData();
      upload.append("metadata", JSON.stringify({title, project_ids: [project.id]}));
      upload.append("file", new Blob([sourcePDF(), "\n% " + title + "\n"], {type: "application/pdf"}), "fixture.pdf");
      return app.request("/api/research/papers", "POST", upload, 201);
    }
    const first = await importPDF("First PDF fixture");
    const target = await importPDF("Selected PDF fixture");
    const metadata = await app.request("/api/research/papers", "POST",
      {title: "Metadata fixture", project_ids: [project.id]}, 201);

    browser = await chromium.launch({headless: true, executablePath: process.env.SCI_STATION_SMOKE_CHROME});
    const page = await browser.newPage({locale: "zh-CN", viewport: {width: 900, height: 620}});
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    const main = page.locator("#main");
    const modal = page.locator("#modal");
    const more = main.locator(".more-actions");
    const conversion = main.getByRole("link", {name: "PDF 转换"});
    const selectPaper = id => main.locator('[data-library-selection="' + id + '"]');
    const primary = () => main.locator(".page-head .primary").allTextContents();
    const scope = "&project=" + encodeURIComponent(project.id);

    await page.goto(app.origin + "/research?view=papers" + scope);
    await selectPaper(first.id).waitFor();
    assert.match(await page.title(), /Sci-Station/);
    assert.deepEqual(await primary(), ["导入文献"]);
    assert.equal(await conversion.count(), 0);
    assert.ok(await page.locator("#paper-query").isVisible());
    assert.ok(await main.locator('[name="library-tag"]').isVisible());
    await main.getByRole("button", {name: "表格列"}).click();
    await modal.getByText("显示列与顺序").waitFor();
    assert.equal(await modal.locator('[name="default_collection"]').count(), 0);
    await page.locator("#modal-close").click();

    const summary = more.locator("summary");
    await summary.focus();
    await summary.press("Enter");
    const manage = more.getByRole("button", {name: "管理集合和标签"});
    await manage.waitFor();
    const menuInViewport = await manage.evaluate(el => {
      const {left, right} = el.getBoundingClientRect();
      return left >= 0 && right <= innerWidth;
    });
    assert.equal(menuInViewport, true);
    await summary.press("Escape");
    assert.ok(await manage.isHidden());
    assert.equal(await summary.evaluate(el => document.activeElement === el), true);
    await summary.press("Enter");
    await manage.click();
    await modal.getByText("管理集合和标签").waitFor();
    await page.locator("#modal-close").click();
    assert.ok(await manage.isHidden());
    await main.locator('[data-action="new-paper"]').click();
    await modal.locator('[name="pdf"]').waitFor();
    await page.locator("#modal-close").click();

    await selectPaper(metadata.id).check();
    assert.equal(await conversion.count(), 0);
    await selectPaper(metadata.id).uncheck();
    await selectPaper(first.id).check();
    await selectPaper(target.id).check();
    assert.equal(await conversion.count(), 0);
    await selectPaper(first.id).uncheck();
    await conversion.waitFor();
    await page.locator("#paper-query").fill(first.title);
    await conversion.waitFor({state: "hidden"});
    await page.locator("#paper-query").fill("");
    await conversion.click();
    const route = new URL(page.url());
    assert.equal(route.searchParams.get("tab"), "convert");
    assert.equal(route.searchParams.get("paper"), target.id);
    assert.equal(route.searchParams.get("project"), project.id);
    await page.waitForFunction(id => document.querySelector("#paper").value === id, target.id);
    assert.equal(await page.locator("#project").inputValue(), project.id);
    assert.equal(await page.locator("#local").isEnabled(), true);
    const preview = page.waitForResponse(response =>
      response.url().endsWith("/papers/" + target.id + "/markdown?format=preview"));
    await page.locator("#local").click();
    await preview;
    route.searchParams.set("paper", "removed-fixture");
    await page.goto(route.href);
    await page.getByText("所选文献已移除或不可用。请选择另一篇文献。").waitFor();
    assert.equal(await page.locator("#paper").inputValue(), "");
    assert.equal(await page.locator("#local").isEnabled(), false);

    await page.goto(app.origin + "/research?view=notes" + scope);
    const wiki = page.getByRole("searchbox", {name: "搜索 Wiki 页面"});
    await wiki.fill("Solar capture");
    assert.ok(await main.getByRole("button", {name: /^Capture/}).isVisible());
    assert.equal(await main.getByRole("button", {name: /^Evaporation/}).count(), 0);
    assert.equal(await wiki.evaluate(el => document.activeElement === el), true);
    assert.deepEqual(await primary(), ["新建页面"]);
    await main.getByRole("button", {name: "新建页面", exact: true}).click();
    const properties = modal.getByText("页面属性", {exact: true});
    await properties.waitFor();
    const aliases = modal.locator('[name="aliases"]');
    assert.ok(await aliases.isHidden());
    await properties.click();
    assert.ok(await aliases.isVisible());
    assert.ok(await modal.locator("#note-body").isVisible());
    await page.locator("#modal-close").click();

    await page.goto(app.origin + "/lab?project=" + encodeURIComponent(project.id));
    const start = page.locator("#lab-start");
    const handoff = page.locator("#handoff");
    const mode = page.locator("#lab-run-mode");
    const templateSettings = page.getByText("模板与席位设置", {exact: true});
    await start.waitFor();
    assert.ok(await handoff.isHidden());
    assert.ok(await page.locator("#question").isVisible());
    assert.ok(await page.locator("#local-record").isVisible());
    assert.ok(await page.locator("#save").isHidden());
    await templateSettings.click();
    assert.ok(await page.locator("#seats").isVisible());
    assert.ok(await page.locator("#save").isVisible());
    await templateSettings.click();
    await page.locator("#lab-models").click();
    await page.locator("#lab-model-state").filter({hasText: "可用模型"}).waitFor();
    await mode.selectOption("roundtable");
    assert.ok(await start.isHidden());
    assert.ok(await handoff.isVisible());
    await mode.selectOption("single");
    const pair = page.getByRole("button", {name: "双席独立复核"});
    await pair.click();
    assert.equal(await mode.inputValue(), "roundtable");
    assert.ok(await start.isHidden());
    assert.ok(await handoff.isEnabled());
    await page.locator("#question").fill("Review the fixture research question.");
    await handoff.click();
    await page.waitForURL(url => url.pathname === "/studio" && url.searchParams.get("project") === project.id);
    assert.equal(await page.request.get(app.origin + "/api/studio/sessions").then(response => response.json())
      .then(result => (result.sessions || result).length), 0, "opening the draft must not send a run");
    assert.deepEqual(errors, []);
    assert.deepEqual(gateway.errors, []);
    console.log("Workbench toolbar, scoped PDF conversion, Wiki search and properties, and AI Lab run modes passed.");
  } finally {
    await browser?.close();
    await app?.close();
    await closeServer(gateway.server);
    await rm(base, {recursive: true, force: true});
  }
}

main(process.argv[2]).catch(error => { console.error(error); process.exitCode = 1; });
