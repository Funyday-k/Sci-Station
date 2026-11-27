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
    const archived = await app.request("/api/research/projects", "POST", {name: "Archived fixture"}, 201);
    const preset = await app.request("/api/research/lab/presets", "POST", {
      title: "Personal Roundtable fixture", prompt: "Check the original research assumptions.", mode: "forum", seats: 3,
    }, 201);
    const missingFromCatalog = await app.request("/api/research/projects", "POST", {name: "Catalog race fixture"}, 201);
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

    const archivedReply = await fetch(app.origin + "/api/research/projects/" + archived.id + "?revision=" + archived.revision, {
      method: "DELETE", headers: {Origin: app.origin, "X-Sci-Station": "1", "X-Roundtable": "1", "Content-Type": "application/json"}, body: "{}",
    });
    assert.ok(archivedReply.ok, await archivedReply.text());
    for (const invalid of ["unknown-fixture", archived.id]) {
      const writes = [];
      const observe = request => {
        const url = new URL(request.url());
        if (url.pathname === "/api/research/lab/draft" || url.pathname === "/api/studio/sessions" && request.method() !== "GET") writes.push(url.href);
      };
      page.on("request", observe);
      await page.goto(app.origin + "/lab?project=" + invalid);
      assert.equal(new URL(page.url()).searchParams.get("view"), "projects");
      assert.deepEqual(writes, []);
      page.off("request", observe);
    }
    const catalogURL = app.origin + "/api/research/projects";
    await page.route(catalogURL, async route => {
      const response = await route.fetch();
      const projects = await response.json();
      await route.fulfill({response, json: projects.filter(item => item.id !== missingFromCatalog.id)});
    });
    await page.goto(app.origin + "/lab?project=" + missingFromCatalog.id);
    await page.locator('#project[aria-invalid="true"]').waitFor();
    assert.equal(await page.locator("#project").inputValue(), missingFromCatalog.id);
    assert.equal(await page.locator("#question").isDisabled(), true);
    assert.equal(await page.locator("#lab-start").isDisabled(), true);
    await page.unroute(catalogURL);

    await page.goto(app.origin + "/lab?project=" + encodeURIComponent(project.id));
    const start = page.locator("#lab-start");
    const question = page.locator("#question");
    await start.waitFor();
    assert.equal(await page.locator("#seats,#lab-run-mode,#session").count(), 0);
    assert.ok(await question.isVisible());
    assert.ok(await page.locator("#local-record").isHidden());
    assert.ok(await page.locator("#presets").isHidden());
    const box = await start.boundingBox();
    assert.ok(box.y + box.height <= 620, "Send remains above the bottom of a short window");
    async function attachExcerpt(title) {
      await page.locator("#lab-attach").click();
      const record = page.locator("#local-record");
      const label = "笔记 · " + title;
      await record.locator("option").filter({hasText: new RegExp(label + "$")}).waitFor({state: "attached"});
      await record.selectOption({label});
      await page.locator("#local-preview").click();
      const excerpt = page.locator("#local-text");
      await excerpt.waitFor();
      await excerpt.evaluate(input => input.select());
      await page.locator("#local-add").click();
      await page.locator("#lab-materials-dialog footer [data-lab-close]").click();
      await page.locator("#local-list").getByText(title, {exact: true}).waitFor();
    }
    await attachExcerpt("Capture");
    await page.locator("#lab-tools").click();
    await page.locator("#lab-template-settings > summary").click();
    await page.locator('#presets [data-id="research-question"]').waitFor();
    assert.equal(await page.locator('#presets [data-id="independent-check"]').count(), 0);
    await page.locator("#lab-legacy-templates > summary").click();
    await page.locator("#lab-legacy-template-list summary").filter({hasText: "双席独立复核"}).waitFor();
    const savedPreset = page.locator("#lab-legacy-template-list details").filter({hasText: preset.title});
    await savedPreset.locator("summary").click();
    assert.match(await savedPreset.innerText(), /3 个席位.*多方权衡/);
    await savedPreset.getByRole("button", {name: "编辑模板"}).click();
    await page.locator("#prompt").fill("Updated research assumptions.");
    await page.locator("#save").click();
    await page.getByText("个人模板已保存。").waitFor();
    const updatedPresets = await app.request("/api/research/lab/presets");
    const updatedPreset = updatedPresets.find(item => item.id === preset.id);
    assert.deepEqual([updatedPreset.mode, updatedPreset.seats, updatedPreset.prompt], ["forum", 3, "Updated research assumptions."]);
    await page.locator("#lab-tools-dialog footer [data-lab-close]").click();
    const original = "Review the fixture research question.";
    await question.fill(original);
    await question.evaluate(input => input.setSelectionRange(3, 10));
    await app.request("/api/research/projects/" + project.id, "PATCH", {name: "Renamed fixture", revision: project.revision});
    await page.evaluate(() => window.dispatchEvent(new CustomEvent("sci:projects-changed")));
    await page.locator("#project option").filter({hasText: "Renamed fixture"}).waitFor({state: "attached"});
    assert.deepEqual(await question.evaluate(input => [input.value, input.selectionStart, input.selectionEnd, document.activeElement === input]), [original, 3, 10, true]);
    await start.click();
    await page.locator(".lab-turn-user").filter({hasText:original}).waitFor();
    await page.locator(".lab-turn-answer").filter({hasText:"excerpt"}).waitFor();
    const reply = page.locator("#lab-reply");
    await reply.fill("Preserve this unsent follow-up.");
    await page.locator("#lab-draft-trigger").click();
    await page.locator("#lab-save-reply-draft").click();
    await page.locator("#lab-reply-draft-state").filter({hasText:"草稿已保存"}).waitFor();
    await page.locator("#lab-draft-dialog footer [data-lab-close]").click();
    await page.reload();
    await reply.waitFor();
    assert.equal(await reply.inputValue(), "Preserve this unsent follow-up.");
    await page.locator("#workspace-nav-toggle").click();
    await page.locator("#lab-history button").filter({hasText:original}).waitFor();
    await page.locator("#workspace-nav-toggle").click();
    assert.deepEqual(gateway.calls.filter(call => call.kind === "statement").length, 1);

    await attachExcerpt("Evaporation");
    const sourceChatURL = page.url();
    await page.locator('[data-ai-mode="roundtable"]').click();
    const transfer = page.locator("#lab-transfer-dialog");
    await transfer.waitFor();
    for (const name of ["Capture.txt", "Evaporation.txt"]) await transfer.locator("#lab-transfer-materials").getByText(name, {exact: true}).waitFor();
    assert.match(await transfer.locator("#lab-transfer-context").inputValue(), /Preserve this unsent follow-up/);
    await transfer.locator("#lab-transfer-apply").click();
    const imported = page.locator("#studio-mode-import");
    await imported.waitFor();
    assert.equal(await page.locator("#create-project").inputValue(), project.id);
    await imported.locator("#studio-mode-dismiss").click();
    await page.goto(app.origin + "/lab?scope=global");
    await page.locator("#question:enabled").waitFor();
    assert.equal(await page.locator("#local-list").getByText("Evaporation.txt").count(), 0);
    await page.goto(sourceChatURL);
    await page.locator("#local-list").getByText("Evaporation.txt", {exact: true}).waitFor();
    assert.equal(await reply.inputValue(), "Preserve this unsent follow-up.");
    assert.equal(await page.locator("#local-list").getByText("Capture.txt").count(), 0);

    await page.locator('[data-ai-mode="roundtable"]').click();
    await transfer.waitFor();
    await transfer.locator("#lab-transfer-apply").click();
    await imported.waitFor();
    await imported.locator("#studio-mode-apply").click();
    await page.waitForFunction(() => document.getElementById("new-topic").value.includes("Preserve this unsent follow-up"));
    for (const name of ["Capture.txt", "Evaporation.txt"]) await page.locator("#create-materials").getByText(name, {exact: true}).waitFor();
    await page.locator('[data-ai-mode="single"]').click();
    await page.locator("#lab-transfer-preview").click();
    assert.equal(await page.locator("#project").inputValue(), project.id);
    for (const name of ["Capture.txt", "Evaporation.txt"]) await transfer.locator("#lab-transfer-materials").getByText(name, {exact: true}).waitFor();
    await transfer.locator("#lab-transfer-apply").click();
    await page.waitForFunction(() => document.getElementById("question").value.includes("Preserve this unsent follow-up"));
    for (const name of ["Capture.txt", "Evaporation.txt"]) await page.locator("#local-list").getByText(name, {exact: true}).waitFor();
    assert.equal(gateway.calls.filter(call => call.kind === "statement").length, 1);
    assert.deepEqual(errors, []);
    assert.deepEqual(gateway.errors, []);
    console.log("Workbench actions, unavailable Lab scopes, saved templates, draft recovery, and verified transfer of saved and unsent attachments passed.");
  } finally {
    await browser?.close();
    await app?.close();
    await closeServer(gateway.server);
    await rm(base, {recursive: true, force: true});
  }
}

main(process.argv[2]).catch(error => { console.error(error); process.exitCode = 1; });
