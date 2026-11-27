"use strict";
const assert = require("node:assert/strict");
const {mkdir, mkdtemp, rm, writeFile} = require("node:fs/promises");
const path = require("node:path");
const {tmpdir} = require("node:os");
const {chromium} = require("playwright");
const {listen, closeServer, fixtureHome, launch} = require("./workstation-workflow-smoke.cjs");

async function main(binary) {
  const base = await mkdtemp(path.join(tmpdir(), "sci25-composer-"));
  const calls = [], errors = [];
  let releaseFollowup;
  const holdFollowup = new Promise(resolve => {releaseFollowup = resolve;});
  const catalog = {
    "fixture/first": {label:"Fixture first", levels:["low", "high"]},
    "fixture/second": {label:"Fixture second", levels:["medium", "xhigh"]},
    "fixture/automatic": {label:"Fixture auto only", levels:[]},
  };
  const gateway = await listen(async (req, res) => {
    const send = (status, body) => {res.writeHead(status, {"Content-Type":"application/json"});res.end(JSON.stringify(body));};
    try {
      if(req.url === "/v1/models") {
        send(200, {data:Object.entries(catalog).map(([id, fixture])=>({id, display_name:fixture.label,
          native_endpoints:["/v1/chat/completions"], kind:"chat", reasoning_levels:fixture.levels}))});
        return;
      }
      assert.equal(req.url,"/v1/chat/completions");
      const parts=[];for await(const chunk of req) parts.push(chunk);
      const body=JSON.parse(Buffer.concat(parts));
      assert.ok(catalog[body.model]);
      const prompt=body.messages.at(-1).content;
      assert.equal(typeof prompt,"string");
      if(!prompt.startsWith("TITLE REQUEST:")) {
        calls.push({model:body.model, effort:body.reasoning_effort,prompt});
        if(prompt.includes("Wait for fixture followup")) await holdFollowup;
      }
      const content=prompt.startsWith("TITLE REQUEST:")?"Composer fixture":JSON.stringify({action:"say",text:"Fixture reply from "+body.model});
      send(200,{model:body.model,choices:[{finish_reason:"stop",message:{content}}]});
    } catch(error) {errors.push(error.message);send(400,{error:"Unexpected fixture request"});}
  });
  let app,browser;
  try {
    const spec=path.join(base,"Fixture.app","Contents","Resources","sci-station.agent.js");
    await mkdir(path.dirname(spec),{recursive:true});await writeFile(spec,"// Isolated fixture\n");
    const environment=await fixtureHome(base,gateway.address().port,spec), probe=await listen(), port=probe.address().port;
    await closeServer(probe);
    app=await launch(binary,port,path.join(base,"root"),environment,"serve");
    const project=await app.request("/api/research/projects","POST",{name:"Composer project"},201);
    const other=await app.request("/api/research/projects","POST",{name:"Other composer scope"},201);
    await app.request("/api/research/projects/"+project.id+"/notes","POST",{title:"Composer note",body:"Known project excerpt."},201);
    browser=await chromium.launch({headless:true,executablePath:process.env.SCI_STATION_SMOKE_CHROME});
    const page=await browser.newPage({locale:"zh-CN",viewport:{width:1440,height:900}});
    page.setDefaultTimeout(10000);
    page.on("pageerror",error=>errors.push(error.message));
    const $=id=>page.locator("#"+id);
    const screenshotDir=process.env.SCI_STATION_LAB_SCREENSHOTS;
    if(screenshotDir) await mkdir(screenshotDir,{recursive:true});
    const screenshot=label=>screenshotDir && page.screenshot({path:path.join(screenshotDir,label+".png")});
    await page.goto(app.origin+"/lab");
    await page.locator("#question:enabled").waitFor();
    assert.match(await page.title(),/Sci-Station/);
    assert.equal(await $("project").inputValue(),"@global");
    const inspect=()=>page.evaluate(()=>{
      const box=selector=>document.querySelector(selector).getBoundingClientRect();
      const [main,heading,composer,actions]=["#lab-workspace","#lab-empty h1","#lab-composer",".lab-composer-tools"].map(box);
      return {midpoint:Math.abs((heading.top+actions.bottom)/2-(main.top+main.bottom)/2),
        adjacent:composer.top-heading.bottom<36&&actions.top-composer.bottom<20,
        noOverflow:document.documentElement.scrollWidth<=innerWidth&&main.bottom<=innerHeight+1};
    });
    for(const [width,height] of [[1440,900],[900,620],[520,490]]) {
      await page.setViewportSize({width,height});
      const geometry=await inspect();assert.ok(geometry.midpoint<35,JSON.stringify(geometry));
      assert.equal(geometry.adjacent,true);assert.equal(geometry.noOverflow,true);
      await screenshot(`lab-blank-${width}x${height}`);
    }
    await page.setViewportSize({width:900,height:620});
    const slider=$("lab-effort");
    await page.locator("#lab-effort:enabled").waitFor();
    await slider.press("End");
    assert.equal(await slider.getAttribute("aria-valuetext"),"高");
    assert.equal(await $("lab-effort-value").innerText(),"高");
    await $("lab-model-trigger").click();
    await $("lab-model").selectOption("fixture/automatic");
    await page.locator("#lab-model-dialog footer [data-lab-close]").click();
    assert.ok(await slider.isDisabled());
    assert.equal(await $("lab-effort-value").innerText(),"自动");
    await $("lab-model-trigger").click();
    await $("lab-model").selectOption("fixture/first");
    await page.locator("#lab-model-dialog footer [data-lab-close]").click();
    assert.equal(await slider.getAttribute("aria-valuetext"),"高");

    await $("lab-tools").click();
    await $("lab-tools-directory").waitFor();
    await page.locator('[data-lab-tool="templates"]').click();
    await $("presets").waitFor();
    await $("lab-tool-back").click();
    await $("lab-tools-directory").waitFor();
    await page.locator("#lab-tools-dialog footer [data-lab-close]").click();
    await page.waitForFunction(()=>document.activeElement?.id==="lab-tools");

    await $("lab-attach").click();
    assert.ok(await $("lab-file-picker").isVisible());
    assert.ok(await $("local-sources").isHidden());
    await page.locator("#lab-materials-dialog footer [data-lab-close]").click();
    await $("project").selectOption(project.id);
    await $("lab-attach").click();
    const chooser=page.waitForEvent("filechooser");
    await $("lab-file-picker").click();
    await (await chooser).setFiles({name:"composer-fixture.txt",mimeType:"text/plain",buffer:Buffer.from("Known local file content.")});
    await page.getByText("已加入 1 个文件。",{exact:true}).waitFor();
    await $("local-record").selectOption({label:"笔记 · Composer note"});
    await $("local-preview").click();
    await $("local-text").waitFor();
    await $("local-text").evaluate(input=>input.select());
    await $("local-add").click();
    await page.locator("#lab-materials-dialog footer [data-lab-close]").click();
    for(const label of ["composer-fixture.txt","Composer note"]) await $("local-list").getByText(label,{exact:true}).waitFor();
    assert.equal(calls.length,0);
    await $("lab-model-trigger").click();
    await $("lab-model").selectOption("fixture/second");
    await page.locator("#lab-model-dialog footer [data-lab-close]").click();
    await slider.press("End");
    assert.equal(await slider.getAttribute("aria-valuetext"),"极高");
    const question="Analyze the two fixture sources.";
    await $("question").fill(question);
    const draftRoute=page.url();
    await page.locator('[data-ai-mode="roundtable"]').click();
    await $("lab-transfer-apply").click();
    await $("studio-mode-import").waitFor();
    await $("studio-mode-dismiss").click();
    await page.goto(draftRoute);
    for(const label of ["composer-fixture.txt","Composer note"]) await $("local-list").getByText(label,{exact:true}).waitFor();
    await page.waitForFunction(()=>document.getElementById("lab-effort").getAttribute("aria-valuetext")==="极高");
    assert.equal(await $("lab-model").inputValue(),"fixture/second");
    await page.waitForFunction(value=>document.getElementById("question").value===value,question);
    assert.equal(calls.length,0);
    await $("lab-start").click();
    await page.getByText("Fixture reply from fixture/second",{exact:true}).waitFor();
    assert.equal(calls[0].model,"fixture/second");assert.equal(calls[0].effort,"xhigh");
    assert.match(calls[0].prompt,/Known local file content/);assert.match(calls[0].prompt,/Known project excerpt/);
    assert.equal(await $("lab-workspace").getAttribute("data-lab-state"),"conversation");
    assert.ok(await $("lab-empty").isHidden());
    const id=new URL(page.url()).searchParams.get("run");
    const before=await app.request("/api/studio/sessions/"+id);
    assert.equal(before.members[0].effort,"xhigh");
    await $("lab-edit-model").click();
    await $("member-editor-model").selectOption("fixture/first");
    await $("member-editor-effort").press("End");
    assert.equal(await $("member-editor-effort").getAttribute("aria-valuetext"),"高");
    await page.locator(".member-editor button[type=submit]").click();
    await $("lab-existing-model-label").getByText("Fixture first · 高",{exact:true}).waitFor();
    const after=await app.request("/api/studio/sessions/"+id);
    assert.equal(after.members[0].model,"fixture/first");assert.equal(after.members[0].effort,"high");
    assert.deepEqual(after.rounds,before.rounds);
    await $("lab-reply").fill("Wait for fixture followup.");
    await $("lab-resume").click();
    await page.getByText("本轮结束后可更改。",{exact:true}).waitFor();
    assert.ok(await $("lab-edit-model").isDisabled());
    releaseFollowup();
    await page.getByText("Fixture reply from fixture/first",{exact:true}).waitFor();
    assert.equal(calls[1].model,"fixture/first");assert.equal(calls[1].effort,"high");
    assert.deepEqual(errors,[]);
    const messageBottom=await page.locator(".lab-composer-dock").boundingBox();
    assert.ok(messageBottom.y + messageBottom.height <= 621);
    assert.ok(messageBottom.y > 360);
    await screenshot("lab-existing-900x620");

    await $("lab-attach").click();
    const pendingPicker=page.waitForEvent("filechooser");
    await $("lab-file-picker").click();
    const stalePicker=await pendingPicker;
    let uploads=0;
    page.on("request",request=>{if(request.method()==="POST" && request.url().endsWith("/api/studio/materials")) uploads++;});
    await $("project").evaluate((scope,id)=>{scope.value=id;scope.dispatchEvent(new Event("change",{bubbles:true}));},other.id);
    await stalePicker.setFiles({name:"stale-scope.txt",mimeType:"text/plain",buffer:Buffer.from("Never link this to the other project.")});
    await page.locator("#lab-materials-dialog footer [data-lab-close]").click();
    assert.equal(await $("project").inputValue(),other.id);
    assert.equal(await $("local-list").getByText("stale-scope.txt",{exact:true}).count(),0);
    assert.equal(uploads,0);
    console.log("Single chat composer layout, plugin navigation, catalog-backed keyboard slider, draft return with local file and project excerpt, and effective settings for the first and following turns passed.");
  } finally {releaseFollowup();await browser?.close();await app?.close();await closeServer(gateway);await rm(base,{recursive:true,force:true});}
}

main(process.argv[2]).catch(error=>{console.error(error);process.exitCode=1;});
