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
    browser=await chromium.launch({headless:true,executablePath:process.env.SCI_STATION_SMOKE_CHROME});
    page=await browser.newPage({locale:"zh-CN",viewport:{width:1440,height:900}});
    page.setDefaultTimeout(10000);
    const errors=[];page.on("pageerror",error=>errors.push(error.message));
    const url=host.origin+"/research?project="+a.id;
    await page.goto(url);
    await page.waitForFunction(()=>document.body.dataset.railMode==="inspector" && !!document.querySelector("#project-modules details"));
    const divider=page.locator("#shell-divider");
    await divider.focus();await divider.press("ArrowLeft");
    await page.waitForFunction(()=>document.querySelector("#shell-divider").getAttribute("aria-valuenow")==="376");
    const tabs=page.locator("#project-modules");
    await tabs.locator('[data-tab-key="notes"]').dragTo(tabs.locator('[data-tab-key="papers"]'));
    await page.waitForFunction(()=>window.SciShellLayout.state.tabOrder[0]==="notes");
    assert.equal(await tabs.locator("a").first().getAttribute("data-tab-key"),"overview");
    await page.locator("#shell-tree-toggle").click();
    await page.locator("#projectnav").waitFor({state:"hidden"});
    await page.reload();
    await page.waitForFunction(()=>window.SciShellLayout?.state?.width===376 && !window.SciShellLayout.state.treeExpanded);
    await page.locator("#shell-tree-toggle").click();
    await page.locator('#projectnav [data-project="'+a.id+'"]').waitFor();
    await tabs.locator('[data-tab-key="papers"]').click();
    await page.locator('[data-library-selection="'+paper.id+'"]').check();
    await page.locator("#rail-context").filter({hasText:paper.title}).waitFor();
    await page.locator("#rail-inspect a[href*='/reader']").click();
    await page.locator(".layout > aside").waitFor();
    assert.ok(await page.locator("#context-rail").isHidden());
    await page.locator("#textLayer span").first().waitFor();
    await page.locator("#pageNo").fill("2");await page.locator("#pageNo").dispatchEvent("change");
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
    await page.goto(host.origin+"/research?project="+b.id);
    await page.waitForFunction(()=>document.body.dataset.railMode==="ai" && !!document.querySelector("#project-modules a"));
    assert.equal(await page.locator("#rail-transcript").innerText(),"");
    assert.equal(new URL(await page.locator("#rail-lab").getAttribute("href"),host.origin).searchParams.get("run"),null);
    await page.setViewportSize({width:900,height:700});
    await page.locator("#context-rail").waitFor({state:"hidden"});
    await page.locator("#projectnav").waitFor({state:"hidden"});
    await page.setViewportSize({width:1440,height:900});
    await page.locator("#context-rail").waitFor();await page.locator("#projectnav").waitFor();
    await host.close();host=await startHost();await page.goto(url);
    await page.locator("#rail-transcript").getByText(/first seat traced/i).waitFor({timeout:25000});
    assert.equal((await host.request("/api/research/interface/layout")).width,376);
    assert.deepEqual(errors,[]);assert.deepEqual(gateway.errors,[]);
    console.log("Shell inspector, reader inspector, project tree, width, tab order, narrow layout, scoped single-seat AI and restart passed.");
  }catch(err){
    if(page)console.error("Shell state",await page.evaluate(()=>({
      path:location.pathname,mode:document.body.dataset.railMode,status:document.querySelector("#rail-status")?.textContent,
      page:document.querySelector("#pageNo")?.value,pageStatus:document.querySelector("#pageStatus")?.textContent,words:document.querySelector("#textLayer")?.textContent.slice(0,120),model:document.querySelector("#rail-model")?.value,modules:document.querySelector("#project-modules")?.textContent
    })).catch(()=>null));
    throw err;
  }finally{
    await browser?.close();await host?.close();await closeServer(gateway.server);await rm(base,{recursive:true,force:true});
  }
}
main(process.argv[2]).catch(err=>{console.error(err);process.exitCode=1;});
