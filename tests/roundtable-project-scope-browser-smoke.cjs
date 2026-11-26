"use strict";

const assert = require("node:assert/strict");
const {mkdir, mkdtemp, realpath, rm, writeFile} = require("node:fs/promises");
const path = require("node:path");
const {tmpdir} = require("node:os");
const {buildNativeFixture, chromeDriver, closeServer, eventually, fixtureHome,
  launch, listen, localGateway, webkitDriver} = require("./workstation-workflow-smoke.cjs");

async function main() {
  const native = process.argv[2] === "--native";
  const target = process.argv[native ? 3 : 2];
  assert.ok(target, "Pass a workstation binary or --native and its .app bundle");
  const base = await mkdtemp(path.join(tmpdir(), "sci-roundtable-project-scope-"));
  const gateway = await localGateway();
  let app, browser;
  try {
    const source = await realpath(target);
    const binary = native ? await buildNativeFixture(source, base) : source;
    const spec = path.join(base, "Smoke.app", "Contents", "Resources", "sci-station.agent.js");
    await mkdir(path.dirname(spec), {recursive:true});
    await writeFile(spec, "// Offline workstation fixture.\n");
    const env = await fixtureHome(base, gateway.port, spec);
    const probe = await listen(), port = probe.address().port;
    await closeServer(probe);
    if (native) {
      const driver = path.join(base, "driver");
      browser = await webkitDriver(driver);
      app = await launch(binary, port, path.join(base, "root"), {...env, SCI_STATION_WORKFLOW_DRIVER_DIR:driver}, "app", browser.quit);
    } else {
      app = await launch(binary, port, path.join(base, "root"), env, "serve");
      browser = await chromeDriver(app.origin);
    }
    const {ui} = browser;
    const projects = "/api/research/projects";
    const sessions = "/api/studio/sessions";
    const a = await app.request(projects, "POST", {name:"Project A fixture"}, 201);
    const b = await app.request(projects, "POST", {name:"Project B fixture"}, 201);
    const note = await app.request(projects+"/"+a.id+"/notes", "POST", {title:"A original", body:"A project source never leaves A."}, 201);
    const citation = await app.request("/api/research/lab/sources/preview", "POST", {
      projectId:a.id, location:{kind:"note", id:note.id}
    });
    const attachments = await app.request("/api/research/lab/sources/prepare", "POST", {
      projectId:a.id, citations:[{kind:"note", id:note.id, hash:citation.hash, quote:citation.text}]
    });

    const projectSelect = "#create-project", composer = "#new-topic", access = "#create-project-access";
    const optional = "@global", roundtable = "[data-workspace-nav] a[data-section='roundtable']";
    const wiki = app.origin+"/research?project="+a.id;
    const aRoute = app.origin+"/studio?project="+a.id;
    const checkDraft = async (expected, draft, protect) => {
      await eventually(async () => (await ui.evaluate(() => document.querySelector("#create-project")?.value)) === expected,
        "selected optional project " + expected);
      assert.equal((await ui.visible(composer)).value, draft);
      assert.match((await ui.visible(access)).text, protect ? /仅读取项目文件|read-only/ : /无项目文件权限|no project file access/);
    };

    // Simulate an installed release that left a previous project pointer.
    await ui.navigate(wiki);
    await ui.visible(roundtable);
    await ui.evaluate(id => localStorage.setItem("studio.active-project", id), b.id);
    await ui.click(roundtable);
    await checkDraft(optional, "", false);
    assert.equal(new URL(await ui.evaluate(() => location.href)).searchParams.has("project"), false);
    assert.equal(await ui.evaluate(() => document.querySelector("#history")?.textContent.includes("全局圆桌")), false);

    await ui.evaluate(({id, materials}) => {
      sessionStorage.setItem("sci-station.lab-handoff", JSON.stringify({projectId:id, title:"Fixture", mode:"review",
        seats:2, prompt:"A project-only handoff.", question:"A scoped draft", materials}));
    }, {id:a.id, materials:attachments});
    await ui.navigate(aRoute);
    await eventually(async () => (await ui.visible(composer)).value.includes("A project-only handoff."), "explicit A handoff received");
    const aDraft = (await ui.visible(composer)).value;
    await ui.visible("#create-materials", "A original");
    assert.equal((await ui.visible(projectSelect)).value, a.id);

    await ui.set(projectSelect, b.id);
    await checkDraft(b.id, "", true);
    assert.equal(await ui.evaluate(() => document.querySelector("#create-materials").textContent.includes("A original")), false);
    await ui.set(composer, "B isolated draft");
    await ui.set(projectSelect, optional);
    await checkDraft(optional, "", false);
    assert.equal(await ui.evaluate(() => document.querySelector("#create-materials").textContent.includes("A original")), false);

    async function create(topic, project, expectedMaterials) {
      if (topic !== undefined) await ui.set(composer, topic);
      await ui.click("#create-submit");
      const url = await eventually(async () => {
        const current = new URL(await ui.evaluate(() => location.href));
        return current.searchParams.has("session") ? current : null;
      }, "created session with optional project");
      const room = await app.request(sessions+"/"+url.searchParams.get("session"));
      assert.equal(room.project_id || "", project);
      assert.equal(url.searchParams.get("project") || "", project);
      assert.deepEqual(room.materials.map(item => item.id), expectedMaterials);
      if (!project) assert.equal(room.project, "");
      return room;
    }
    const unscoped = await create("Discussion without a project", "", []);
    await ui.navigate(aRoute);
    await checkDraft(a.id, aDraft, true);
    await ui.visible("#create-materials", "A original");
    const roomA = await create(undefined, a.id, [attachments[0].id]);

    await ui.click(roundtable);
    await checkDraft(optional, "", false);
    await ui.set(projectSelect, b.id);
    await checkDraft(b.id, "B isolated draft", true);
    const roomB = await create(undefined, b.id, []);
    await ui.navigate(app.origin+"/studio?session="+unscoped.id);
    await ui.visible("#session-content");
    assert.equal(new URL(await ui.evaluate(() => location.href)).searchParams.has("project"), false);
    const stored = await app.request(sessions);
    assert.deepEqual(Object.fromEntries(stored.sessions.map(room => [room.id,room.project_id || ""])),
      {[unscoped.id]:"", [roomA.id]:a.id, [roomB.id]:b.id});
    await ui.visible("#history", "未关联项目的会话");
    if (browser.errors) assert.deepEqual(browser.errors, []);
    assert.deepEqual(gateway.errors, []);
    console.log("Roundtable global and project entry, isolated drafts and attachments, and saved scoped sessions verified.");
  } finally {
    await browser?.close();
    await app?.close();
    await closeServer(gateway.server);
    await rm(base, {recursive:true, force:true});
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
