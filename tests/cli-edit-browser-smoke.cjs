"use strict";

// Invoked by TestCLIEditReviewBrowser. The Go fixture owns the loopback port,
// project and mock CLI. No provider or model process outside the fixture runs.
const assert=require("node:assert/strict");
const {readFile}=require("node:fs/promises");
const {chromium}=require("playwright");

async function exercise(origin,project,meeting,file,phase) {
  const browser=await chromium.launch({headless:true,executablePath:process.env.SCI_STATION_SMOKE_CHROME});
  try {
    const page=await browser.newPage({viewport:{width:1280,height:820},locale:"zh-CN"});
    const proofScript=require("node:fs").readFileSync(0,"utf8");
    // Only the isolated test browser receives the normal window script.
    // Run after navigation like Wails, after listeners are installed.
    await page.addInitScript({content:"window.addEventListener('load',()=>{"+proofScript+"});"});
    page.setDefaultTimeout(8000);
    const writes=[],errors=[];
    page.on("pageerror",error=>errors.push(error.message));
    page.on("request",request=>{
      if(request.url().endsWith("/cli-edits") && request.method()==="POST") writes.push(request.postDataJSON());
    });
    await page.route("**/*",route=>route.request().url().startsWith(origin+"/")?route.continue():route.abort());
    await page.goto(origin+"/studio?"+new URLSearchParams({project,session:meeting}));
    const panel=page.locator("#cli-edit-dialog");
    const open=async()=>{await page.locator("#cli-edit-open").click();await panel.waitFor();};
    await open();
    if(phase==="reopen") {
      await panel.getByText("当前没有待审核的 CLI 请求。").waitFor();
      assert.equal(writes.length,0);
      assert.equal(await readFile(file,"utf8"),"approved fixture\n");
      console.log("Reopening the same root and meeting has no active request, no outgoing decision and no unapproved edit.");
      return;
    }
    const propose=async(text)=>{
      await panel.locator("#cli-edit-prompt").fill(text);
      await panel.locator("#cli-edit-paths").fill("measurement.txt");
      await panel.locator("#cli-edit-submit").click();
      await panel.locator("#cli-edit-changes pre").filter({hasText:"+"+text}).waitFor();
      assert.match(await panel.locator("#cli-edit-run-title").innerText(),/Mock Codex CLI/);
      assert.match(await panel.locator("#cli-edit-scope").innerText(),new RegExp(project));
      assert.match(await panel.locator("#cli-edit-reason").innerText(),/Mock CLI proposes/);
    };
    const settled=async(text)=>panel.locator("#cli-edit-run-detail").filter({hasText:text}).waitFor();
    await panel.locator("#cli-edit-capabilities").getByText(/cursor.*no per-file/).waitFor();
    await propose("declined fixture");
    const header = await panel.locator(".diff-view > .diff-header").first().evaluate(row => {
      const probe = document.createElement("span");
      probe.style.color = "var(--ink-muted)";
      row.append(probe);
      const styles = [getComputedStyle(row).display, getComputedStyle(row.querySelector(".diff-text")).color, getComputedStyle(probe).color];
      probe.remove();
      return styles;
    });
    assert.equal(header[0], "grid");
    assert.equal(header[1], header[2], "the CLI header text inherits the muted row ink");
    await panel.locator("#cli-edit-decline").click();
    await settled("CLI 已报告拒绝文件变更");
    assert.equal(await readFile(file,"utf8"),"initial fixture\n");
    await propose("approved fixture");
    await panel.locator("#cli-edit-accept").click();
    await settled("CLI 已报告文件变更成功");
    assert.equal(await readFile(file,"utf8"),"approved fixture\n");
    await propose("cancelled fixture");
    await panel.locator("#cli-edit-cancel").click();
    await panel.locator("#cli-edit-run-title").filter({hasText:"已取消"}).waitFor();
    assert.equal(await readFile(file,"utf8"),"approved fixture\n");
    await propose("unanswered fixture");
    await page.route("**/cli-edits",route=>route.request().method()==="GET"?route.abort("connectionreset"):route.continue());
    await panel.locator("#cli-edit-refresh").click();
    await panel.locator("#cli-edit-status").filter({hasText:"未能确认"}).waitFor();
    assert.ok(await panel.locator("#cli-edit-accept").isDisabled());
    assert.ok(await panel.locator("#cli-edit-decline").isDisabled());
    await page.unroute("**/cli-edits");
    await page.reload();
    await open();
    await panel.locator("#cli-edit-changes pre").filter({hasText:"+unanswered fixture"}).waitFor();
    assert.deepEqual(writes.map(request=>request.action),["start","decline","start","accept","start","cancel","start"]);
    assert.equal(await readFile(file,"utf8"),"approved fixture\n");
    assert.deepEqual(errors,[]);
    if(process.env.SCI_STATION_SMOKE_SCREENSHOT) await page.screenshot({path:process.env.SCI_STATION_SMOKE_SCREENSHOT});
    console.log("Project UI forwarded decline, accept and cancel; only the approved mock CLI change reached the project. Disconnect gated decisions; reload observed the original pending request.");
  } finally {await browser.close();}
}
exercise(...process.argv.slice(2)).catch(error=>{console.error(error);process.exitCode=1;});
