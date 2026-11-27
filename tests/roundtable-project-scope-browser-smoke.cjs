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
    const pendingNote = "Pending single-chat excerpt";
    await app.request(projects+"/"+a.id+"/notes", "POST", {title:pendingNote, body:"This source has not been sent to the provider."}, 201);
    const citation = await app.request("/api/research/lab/sources/preview", "POST", {
      projectId:a.id, location:{kind:"note", id:note.id}
    });
    const attachments = await app.request("/api/research/lab/sources/prepare", "POST", {
      projectId:a.id, citations:[{kind:"note", id:note.id, hash:citation.hash, quote:citation.text}]
    });

    const projectSelect = "#create-project", composer = "#new-topic", access = "#create-project-access";
    const optional = "@global", ai = "[data-workspace-nav] a[data-section='lab']";
    const roundtable = "[data-ai-mode='roundtable']";
    async function enterUnscopedRoundtable() {
      await ui.click(ai);
      await eventually(() => ui.evaluate(() => location.pathname === "/lab" && !new URL(location.href).searchParams.has("project")),
        "workspace AI entry has no project");
      await ui.click(roundtable);
    }
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
    await ui.visible(ai);
    await ui.evaluate(id => localStorage.setItem("studio.active-project", id), b.id);
    await enterUnscopedRoundtable();
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
    async function pasteFile(target, list, name, body) {
      await ui.evaluate(({target,name,body}) => {
        const clipboardData = new DataTransfer();
        clipboardData.items.add(new File([body],name,{type:"text/plain"}));
        document.querySelector(target).dispatchEvent(new ClipboardEvent("paste",{clipboardData,bubbles:true}));
      }, {target,name,body});
      const selector = `${list} a[download="${name}"]`;
      await ui.visible(selector);
      return ui.evaluate(selector => new URL(document.querySelector(selector).href).pathname.split("/").at(-1),selector);
    }
    const unscoped = await create("Discussion without a project", "", []);
    await ui.navigate(aRoute);
    await checkDraft(a.id, aDraft, true);
    await ui.visible("#create-materials", "A original");
    const roomA = await create(undefined, a.id, [attachments[0].id]);

    await enterUnscopedRoundtable();
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

    // A saved Roundtable keeps its original messages and pending follow-up when context moves both ways.
    const aSaved = sessions+"/"+roomA.id, aSession = aRoute+"&session="+roomA.id;
    await eventually(async () => {
      const saved = await app.request(aSaved);
      return saved.status === "ready" && !["pending","drafting"].includes(saved.agenda_draft_status);
    }, "fixture agenda settled");
    await app.request(aSaved+"/run","POST",{expected_round:0, allow_edits:false},202);
    const completed = await eventually(async () => {
      const saved = await app.request(aSaved);
      return saved.status === "ready" && saved.rounds[0]?.turns.some(turn=>turn.status==="done") && saved;
    }, "fixture Roundtable has completed public messages");
    const statements = () => gateway.calls.filter(call=>call.kind==="statement").length;
    const before = statements();
    const firstMessage = completed.rounds[0].turns.find(turn=>turn.status==="done").text;
    const pending = "A follow-up still in its original Roundtable.";
    await ui.navigate(aSession);
    await ui.visible("#chat-header");
    if (!await ui.evaluate(() => !!document.querySelector("#run-note")?.getClientRects().length))
      await ui.click("#room-chat-toggle");
    await ui.set("#run-note",pending);
    const pendingFile = "roundtable-unsent.txt";
    await pasteFile("#run-note","#run-materials",pendingFile,"This Roundtable attachment is still in the composer.");
    await ui.click("[data-ai-mode='single']");
    await ui.click("#lab-transfer-preview");
    const preview = (await ui.visible("#lab-transfer-context")).value;
    assert.ok(preview.includes(firstMessage) && preview.includes(pending));
    await ui.visible("#lab-transfer-materials","A original");
    await ui.visible("#lab-transfer-materials",pendingFile);
    await ui.click("#lab-transfer-apply");
    await eventually(async () => (await ui.visible("#question")).value.includes(firstMessage), "Roundtable excerpt added to chat");
    await ui.visible("#local-list","A original");
    await ui.visible("#local-list",pendingFile);
    assert.equal(statements(),before);

    // Create a single chat explicitly, then select another source in its
    // follow-up composer without adding a second round.
    await ui.click("#lab-start");
    const single = await eventually(async () => {
      const id = await ui.evaluate(() => new URL(location.href).searchParams.get("run"));
      if (!id) return null;
      const saved = await app.request(sessions+"/"+id);
      return saved.status === "ready" && saved.rounds[0]?.turns.some(turn=>turn.status==="done") && saved;
    }, "single chat created and first reply completed");
    assert.equal(statements(),before+1);
    assert.deepEqual(single.materials.map(item=>item.name), ["A original.txt",pendingFile]);
    const pendingReply = "Keep this unsent single-chat follow-up.";
    await ui.set("#lab-reply",pendingReply);
    await ui.click("#lab-attach");
    const option = await eventually(() => ui.evaluate(title => [...document.querySelector("#local-record").options]
      .find(item=>item.text.includes(title))?.value, pendingNote), "pending note is in the project source picker");
    await ui.set("#local-record",option);
    await ui.click("#local-preview");
    await ui.visible("#local-text");
    await ui.evaluate(() => {
      const source = document.querySelector("#local-text");
      source.setSelectionRange(0,source.value.trimEnd().length);
    });
    await ui.click("#local-add");
    await ui.click("#lab-materials-dialog footer [data-lab-close]");
    await ui.visible("#local-list",pendingNote);

    await ui.click(roundtable);
    await ui.visible("#lab-transfer-dialog");
    await ui.visible("#lab-transfer-materials",pendingNote);
    assert.match((await ui.visible("#lab-transfer-context")).value,/Keep this unsent single-chat follow-up\./);
    await ui.click("#lab-transfer-apply");
    await ui.visible("#studio-mode-import");
    await checkDraft(a.id,"",true);
    await ui.set(composer,"This is a separate Roundtable draft.");
    await ui.click("#studio-mode-apply");
    await eventually(async () => (await ui.visible(composer)).value.includes(firstMessage), "single chat excerpt appended to Roundtable");
    assert.match((await ui.visible(composer)).value,/^This is a separate Roundtable draft\./);
    await ui.visible("#create-materials","A original");
    await ui.visible("#create-materials",pendingFile);
    await ui.visible("#create-materials",pendingNote);
    assert.equal(statements(),before+1);
    assert.equal((await app.request(sessions)).sessions.length,4);
    const unmodifiedSingle = await app.request(sessions+"/"+single.id);
    assert.equal(unmodifiedSingle.rounds.length,1);
    assert.deepEqual(unmodifiedSingle.materials.map(item=>item.id),single.materials.map(item=>item.id));

    await ui.navigate(aSession);
    await ui.visible("#chat-header");
    if (!await ui.evaluate(() => !!document.querySelector("#run-note")?.getClientRects().length))
      await ui.click("#room-chat-toggle");
    assert.equal((await ui.visible("#run-note")).value,pending);
    await ui.visible("#run-materials",pendingFile);
    assert.equal((await app.request(aSaved)).rounds[0].turns[0].text,completed.rounds[0].turns[0].text);

    // An existing multi-seat template is reviewable in Lab and changes the
    // Roundtable setup only on explicit Apply.
    const template = {title:"Three-seat fixture", mode:"forum", seats:3, prompt:"Compare all three fixture views."};
    await app.request("/api/research/lab/presets","POST",template,201);
    await ui.navigate(app.origin+"/lab?project="+b.id);
    await ui.click("#lab-tools");
    await ui.click("#lab-legacy-templates > summary");
    await ui.click("#lab-legacy-template-list summary",template.title);
    await ui.click("#lab-legacy-template-list details[open] button:first-of-type");
    await ui.visible("#lab-transfer-dialog");
    assert.match((await ui.visible("#lab-transfer-context")).value,/Compare all three fixture views/);
    await ui.click("#lab-transfer-apply");
    const presetNote = await ui.visible("#studio-mode-preset");
    assert.match(presetNote.text,/3 (?:个席位|seats)/);
    assert.equal(await ui.evaluate(() => document.querySelector("#preset-forum").checked),false);
    await ui.set(composer,"Keep the text already in the Roundtable draft.");
    const templateAttachment = await pasteFile(composer,"#create-materials","existing-draft.txt","Keep this attachment on Apply.");
    await ui.click("#studio-mode-apply");
    await eventually(() => ui.evaluate(() => document.querySelector("#preset-forum").checked &&
      document.querySelectorAll(".chosen-member").length===3),"explicit Apply configured three seats and the forum preset");
    const applied = (await ui.visible(composer)).value;
    assert.match(applied,/^Keep the text already in the Roundtable draft\./);
    assert.match(applied,/Compare all three fixture views/);
    await ui.visible("#create-materials","existing-draft.txt");
    assert.equal(statements(),before+1);
    const templateRoom = await create(undefined,b.id,[templateAttachment]);
    assert.equal(templateRoom.preset,"forum");
    assert.equal(templateRoom.seats.length,3);

    // A long-lived source can have up to 48 attachments. After an explicit
    // cancellation, choose a text-only transfer and leave all 13 bound here.
    const add = async i => {
      const data = new FormData();
      data.set("file",new Blob(["Synthetic content "+i],{type:"text/plain"}),`overflow-${i}.txt`);
      return (await app.request("/api/studio/materials","POST",data,201)).id;
    };
    const extra = await Promise.all(Array.from({length:12},(_,i)=>add(i+1)));
    const templateSaved = sessions+"/"+templateRoom.id;
    await eventually(async () => {
      const saved = await app.request(templateSaved);
      return saved.status==="ready" && !["pending","drafting"].includes(saved.agenda_draft_status);
    }, "template Roundtable ready for an explicit round");
    await app.request(templateSaved+"/run","POST",{expected_round:0,allow_edits:false,material_ids:extra},202);
    await eventually(async () => {
      const saved = await app.request(templateSaved);
      return ["ready","partial"].includes(saved.status) && saved.rounds[0]?.turns.some(turn=>turn.status==="done") && saved.materials.length===13;
    }, "13 attachments have been committed to the source Roundtable");
    const beforeOverflow = statements();
    await ui.navigate(app.origin+"/studio?"+new URLSearchParams({project:b.id,session:templateRoom.id}));
    await ui.visible("#chat-header");
    await ui.click("[data-ai-mode='single']");
    await ui.visible("#studio-mode-overflow-summary","13");
    const afterCancel = await ui.evaluate(async () => {
      const dialog = document.querySelector("#studio-mode-overflow");
      dialog.querySelector('button[value="cancel"]').click();
      const closed = !dialog.open;
      const session = new URL(location.href).searchParams.get("session");
      // Retry after the submit handler can settle, before the queued close event.
      await Promise.resolve();
      document.querySelector("[data-ai-mode='single']").click();
      return {closed,session,reopened:dialog.open};
    });
    assert.deepEqual(afterCancel,{closed:true,session:templateRoom.id,reopened:true});
    await ui.visible("#studio-mode-overflow-summary","13");
    await ui.click('#studio-mode-overflow button[value="text-only"]');
    await ui.click("#lab-transfer-preview");
    assert.match((await ui.visible("#lab-transfer-context")).value,/Compare all three fixture views/);
    assert.equal(await ui.evaluate(() => document.querySelector("#lab-transfer-materials").childElementCount),0);
    const overflowAfter = await app.request(templateSaved);
    assert.deepEqual(overflowAfter.materials.map(item=>item.id),[templateAttachment,...extra]);
    assert.equal(statements(),beforeOverflow);
    await ui.click("#lab-transfer-dialog footer [data-lab-close]");
    await ui.click("#lab-transfer-dismiss");

    await enterUnscopedRoundtable();
    await checkDraft(optional,"",false);
    await ui.set(composer,"Unscoped draft travels without a project.");
    await ui.click("[data-ai-mode='single']");
    await ui.click("#lab-transfer-preview");
    assert.match((await ui.visible("#lab-transfer-context")).value,/Unscoped draft travels/);
    await ui.click("#lab-transfer-apply");
    await eventually(async () => (await ui.visible("#question")).value.includes("Unscoped draft travels"),"unscoped draft in single chat");
    assert.equal(new URL(await ui.evaluate(() => location.href)).searchParams.has("project"),false);
    assert.equal(statements(),beforeOverflow);

    if (browser.errors) assert.deepEqual(browser.errors, []);
    assert.deepEqual(gateway.errors, []);
    console.log("Roundtable project scope, pending attachments in both mode switches, explicit template Apply, and over-limit text-only review verified.");
  } finally {
    await browser?.close();
    await app?.close();
    await closeServer(gateway.server);
    await rm(base, {recursive:true, force:true});
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
