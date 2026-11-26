"use strict";
const assert=require("node:assert/strict");
const {mkdir,mkdtemp,realpath,rm,writeFile}=require("node:fs/promises");
const path=require("node:path");
const {tmpdir}=require("node:os");
const {chromium}=require("playwright");
const {listen,closeServer,localGateway,fixtureHome,launch,sourcePDF}=require("./workstation-workflow-smoke.cjs");

async function main(binary) {
  const base=await mkdtemp(path.join(await realpath(tmpdir()),"sci-shell-layout-"));
  const gateway=await localGateway();
  let host,browser,page;
  try {
    const spec=path.join(base,"Smoke.app","Contents","Resources","sci-station.agent.js");
    await mkdir(path.dirname(spec),{recursive:true}); await writeFile(spec,"// Offline registration fixture.\n");
    const fixtureEnvironment=await fixtureHome(base,gateway.port,spec);
    const probe=await listen(),port=probe.address().port;await closeServer(probe);
    const startHost=()=>launch(binary,port,path.join(base,"root"),fixtureEnvironment,"serve");
    host=await startHost();
    const api=host.request;
    const a=await api("/api/research/projects","POST",{name:"Solar fixture"},201);
    const b=await api("/api/research/projects","POST",{name:"Independent fixture"},201);
    const upload=new FormData(),quote="Capture grows with cross section.";
    upload.append("metadata",JSON.stringify({title:"Shared fixture paper",project_ids:[a.id]}));
    upload.append("file",new Blob([sourcePDF()],{type:"application/pdf"}),"fixture.pdf");
    const paper=await api("/api/research/papers","POST",upload,201);
    const task=await api("/api/research/projects/"+a.id+"/tasks","POST",{title:"Check fixture timing",status:"open",dueDate:"2026-02-10",description:"Compare the observation windows."},201);
    const note=await api("/api/research/projects/"+a.id+"/notes","POST",{title:"Fixture observation",body:"Compare the two fixture spectra.",tags:["fixture"]},201);
    browser=await chromium.launch({headless:true,executablePath:process.env.SCI_STATION_SMOKE_CHROME});
    page=await browser.newPage({locale:"zh-CN",viewport:{width:1440,height:900}});
    page.setDefaultTimeout(10000);
    const errors=[];page.on("pageerror",error=>errors.push(error.message));
    const url=host.origin+"/research?project="+a.id;
    const mode=value=>page.waitForFunction(mode=>document.body.dataset.railMode===mode,value);
    const goto=async path=>{
      await page.goto(host.origin+path);
      await page.locator('#main[aria-busy="false"]').waitFor();
      await page.waitForFunction(()=>!!window.SciShellLayout?.state);
    };
    async function capture(name){
      if(process.env.SCI_STATION_SHELL_SCREENSHOTS){
        await page.screenshot({path:path.join(process.env.SCI_STATION_SHELL_SCREENSHOTS,name+".png")});
      }
    }
    const width=async selector=>(await page.locator(selector).boundingBox()).width;
    const readerInspector=page.locator("#reader-inspector");
    for(const readerWidth of [900,1440]){
      await page.setViewportSize({width:readerWidth,height:900});
      await page.goto(host.origin+"/reader");
      await page.locator("#empty").filter({hasText:/未选择论文|Open a paper/}).waitFor();
      await page.waitForFunction(()=>!!window.SciShellLayout?.state);
      await mode("hidden");
      assert.ok(await readerInspector.isHidden());
      assert.equal(await width(".viewer"),await width(".layout"));
      await page.locator("#shell-inspect").click();
      await mode("inspector");await readerInspector.waitFor();
      if(readerWidth===900){
        await page.locator("#shell-pin").click();
        await page.waitForFunction(()=>window.SciShellLayout.state.panelPinned);
        await page.reload();
        await mode("inspector");await readerInspector.waitFor();
      }
      await page.locator("#shell-inspect").click();
      await mode("hidden");
      await page.goto(host.origin+"/reader?paper="+paper.id);
      await page.locator("#title").filter({hasText:paper.title}).waitFor();
      await mode("inspector");await readerInspector.waitFor();
    }
    for(const view of ["overview","papers","tasks"]){
      await goto("/research?view="+view);
      await mode("hidden");
      assert.equal(await page.locator("#context-rail").isVisible(),false);
    }
    const taskDetails=page.locator('[data-inspect-object="task"][data-id="'+task.id+'"]');
    await taskDetails.click();
    await mode("inspector");
    await taskDetails.click();
    await mode("hidden");
    await taskDetails.click();
    await mode("inspector");
    await page.locator("#rail-inspect").getByText(task.description).waitFor();
    await page.locator("#rail-inspect").getByRole("button",{name:/打开任务|Open task/}).click();
    await page.locator('#modal input[name="title"]').waitFor();
    await page.locator("#modal-close").click();
    await goto("/research?view=notes&project="+a.id);
    await mode("hidden");
    await page.locator('[data-inspect-object="note"][data-id="'+note.id+'"]').click();
    await page.locator("#rail-inspect").getByText(note.body).waitFor();
    await page.locator("#rail-inspect").getByRole("button",{name:/打开知识笔记|Open Wiki page/}).click();
    await page.locator("#note-preview").getByText(note.body).waitFor();
    await page.locator("#modal-close").click();
    await goto("/research?project="+a.id);
    await mode("hidden");
    await page.locator("#project-modules details").waitFor();
    const whole=await width(".workspace-region");
    await page.locator("#shell-inspect").click();
    await mode("inspector");
    assert.ok(await width(".workspace-region")<=whole-360);
    const divider=page.locator("#shell-divider");
    await divider.focus();await divider.press("ArrowLeft");
    await page.waitForFunction(()=>document.querySelector("#shell-divider").getAttribute("aria-valuenow")==="376");
    const tabs=page.locator("#project-modules");
    const tree=page.locator("#projectnav"),toggle=page.locator("#nav-toggle");
    assert.equal(await tree.locator("a").count(),2);
    assert.equal(await tree.locator("a[aria-current]").getAttribute("data-project"),a.id);
    await tabs.locator('[data-tab-key="notes"]').dragTo(tabs.locator('[data-tab-key="papers"]'));
    await page.waitForFunction(()=>window.SciShellLayout.state.tabOrder[0]==="notes");
    assert.equal(await tabs.locator("a").first().getAttribute("data-tab-key"),"overview");
    await tabs.locator('[data-tab-key="notes"]').press("Alt+ArrowRight");
    await page.waitForFunction(()=>window.SciShellLayout.state.tabOrder[0]==="papers");
    assert.equal(await page.locator(":focus").getAttribute("data-tab-key"),"notes");
    const withTree=await width("#workarea");
    await toggle.click();
    await tree.waitFor({state:"hidden"});
    assert.ok(await width("#workarea")>withTree+180);
    await page.reload();
    await page.waitForFunction(()=>window.SciShellLayout?.state?.width===376 && !window.SciShellLayout.state.treeExpanded);
    await mode("hidden");
    await toggle.click();
    await tree.locator('[data-project="'+a.id+'"]').waitFor();
    for(const compactWidth of [760,900,999]){
      await page.setViewportSize({width:compactWidth,height:620});
      await tree.waitFor({state:"hidden"});
      await page.waitForFunction(()=>document.getElementById("nav-toggle").getAttribute("aria-expanded")==="false");
      assert.equal(await width("#workarea"),compactWidth);
      await toggle.click();
      await tree.locator('[aria-current]').waitFor();
      assert.equal(await toggle.getAttribute("aria-expanded"),"true");
      if(compactWidth===900)await capture("compact-projects");
      assert.equal(await width("#workarea"),compactWidth);
      await page.keyboard.press("Escape");
      await tree.waitFor({state:"hidden"});
      assert.equal(await page.locator(":focus").getAttribute("id"),"nav-toggle");
    }
    await toggle.click();
    await tree.locator('[data-project="'+b.id+'"]').click();
    await page.waitForFunction(id=>window.SciResearch.state.project?.id===id,b.id);
    await tree.waitFor({state:"hidden"});
    await goto("/research?project="+a.id);
    await page.setViewportSize({width:1000,height:700});
    await tree.waitFor();
    await page.setViewportSize({width:1440,height:900});
    await tabs.locator('[data-tab-key="papers"]').click();
    await mode("hidden");
    const checkbox=page.locator('[data-library-selection="'+paper.id+'"]');
    await capture("library");
    await checkbox.check();
    await mode("inspector");
    await capture("selected-paper");
    await page.locator("#rail-context").filter({hasText:paper.title}).waitFor();
    await checkbox.uncheck();
    await mode("hidden");
    assert.equal(await width(".workspace-region"),whole);
    await checkbox.check();
    await page.locator("#rail-inspect a[href*='/reader']").click();
    await page.locator(".layout > aside").waitFor();
    assert.ok(await page.locator("#context-rail").isHidden());
    await page.locator("#textLayer span").first().waitFor();
    await page.locator("#pageNo").fill("2");await page.locator("#pageNo").press("Tab");
    await page.waitForFunction(q=>document.querySelector("#textLayer").textContent.includes(q),quote);
    const source=await api("/api/research/papers/"+paper.id+"/pages/2"),start=source.text.indexOf(quote),end=start+quote.length;
    assert.ok(start>=0);
    const first=source.words.findIndex(w=>w.start<=start && start<w.end),last=source.words.findIndex(w=>w.start<end && end<=w.end);
    await page.evaluate(([first,last,from,to])=>{
      const layer=document.querySelector("#textLayer"),spans=layer.querySelectorAll("span"),range=document.createRange();
      range.setStart(spans[first].firstChild,from);range.setEnd(spans[last].firstChild,to);
      const selection=getSelection();selection.removeAllRanges();selection.addRange(range);
      layer.dispatchEvent(new KeyboardEvent("keyup",{bubbles:true,key:"Shift"}));
    },[first,last,start-source.words[first].start,end-source.words[last].start]);
    await page.locator("#selectedText").filter({hasText:quote}).waitFor();
    await page.locator("#shell-assist").click();
    await page.locator("#rail-excerpt").filter({hasText:quote}).waitFor();
    await page.waitForFunction(()=>!!document.querySelector("#rail-model")?.value);
    assert.equal(await page.locator("#rail-model").inputValue(),"fixture/first");
    await page.locator("#rail-prompt").fill("Explain this fixture's scope without changing any files.");
    await page.locator("#rail-send").click();
    await page.locator("#rail-transcript").getByText(/first seat traced/i).waitFor({timeout:25000});
    const link=new URL(await page.locator("#rail-lab").getAttribute("href"),host.origin);
    assert.equal(link.searchParams.get("project"),a.id);
    const id=link.searchParams.get("run");assert.ok(id);
    const room=await api("/api/studio/sessions/"+id);
    assert.equal(room.project_id,a.id);assert.equal(room.seats.length,1);
    assert.equal(room.materials.length,1);assert.ok(room.materials[0].excerpt.includes(quote));
    assert.ok(room.materials[0].excerpt.includes(paper.file_sha256));
    assert.ok(!room.materials[0].excerpt.includes("Unselected context"));
    if(process.env.SCI_STATION_SMOKE_SCREENSHOT)await page.screenshot({path:process.env.SCI_STATION_SMOKE_SCREENSHOT});
    // An explicit AI action is local unless the user deliberately pins it.
    await goto("/research?project="+a.id);
    await mode("hidden");
    await page.locator("#shell-assist").click();
    await page.locator("#rail-transcript").getByText(/first seat traced/i).waitFor();
    await page.locator("#shell-pin").click();
    await page.waitForFunction(()=>window.SciShellLayout.state.panelPinned);
    await page.goto(host.origin+"/research?project="+b.id);
    await page.waitForFunction(()=>document.body.dataset.railMode==="ai" && !!document.querySelector("#project-modules a"));
    assert.equal(await page.locator("#rail-transcript").innerText(),"");
    assert.equal(new URL(await page.locator("#rail-lab").getAttribute("href"),host.origin).searchParams.get("run"),null);
    await page.setViewportSize({width:900,height:700});
    await page.locator("#context-rail").waitFor();
    await page.locator("#projectnav").waitFor({state:"hidden"});
    assert.equal(await width(".workspace-region"),900);
    await page.setViewportSize({width:1440,height:900});
    await page.locator("#context-rail").waitFor();await page.locator("#projectnav").waitFor();
    await host.close();host=await startHost();await page.goto(url);
    await page.locator("#rail-transcript").getByText(/first seat traced/i).waitFor({timeout:25000});
    assert.equal((await host.request("/api/research/interface/layout")).width,376);
    await page.locator("#shell-pin").click();
    await page.waitForFunction(()=>!window.SciShellLayout.state.panelPinned);
    await page.reload();await mode("hidden");
    assert.deepEqual(errors,[]);assert.deepEqual(gateway.errors,[]);
    console.log("Shell inspector, reader inspector, project tree, width, tab order, narrow layout, scoped single-seat AI and restart passed.");
  }catch(err){
    if(page)console.error("Shell state",await page.evaluate(()=>({
      path:location.pathname,mode:document.body.dataset.railMode,status:document.querySelector("#rail-status")?.textContent,
      selected:window.SciShellReader?.()?.quote,railQuote:document.querySelector("#rail-excerpt")?.textContent,page:document.querySelector("#pageNo")?.value,pageStatus:document.querySelector("#pageStatus")?.textContent,words:document.querySelector("#textLayer")?.textContent.slice(0,120),model:document.querySelector("#rail-model")?.value,modules:document.querySelector("#project-modules")?.textContent
    })).catch(()=>null));
    throw err;
  }finally{
    await browser?.close();await host?.close();await closeServer(gateway.server);await rm(base,{recursive:true,force:true});
  }
}
main(process.argv[2]).catch(err=>{console.error(err);process.exitCode=1;});
