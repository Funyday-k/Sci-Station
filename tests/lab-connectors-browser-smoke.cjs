"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const {chromium}=require("playwright");
async function main(origin,project,other,program,script,log){
  const browser=await chromium.launch({headless:true,executablePath:process.env.SCI_STATION_SMOKE_CHROME});
  try{
    const page=await browser.newPage();
    const errors=[];page.on("pageerror",e=>errors.push(e.message));
    await page.addInitScript(fs.readFileSync(0,"utf8"));
    await page.goto(origin+"/lab?project="+project);
    await page.locator("#mcp summary").click();
    await page.locator("#connector-transport").selectOption("stdio");
    await page.locator("#connector-id").fill("fixture");
    await page.locator("#connector-program").fill(program);
    await page.locator("#connector-argv").fill(JSON.stringify([script,log]));
    await page.locator("#connector-tools").fill("lookup");
    await page.locator("#connector-enabled").check();
    let decision=true;
    const questions=[];page.on("dialog",async d=>{questions.push(d.message());await(decision?d.accept():d.dismiss());});
    await page.locator("#connector-save").click();
    await page.locator("#connector-trust").click();
    await page.locator("#connector-untrust").waitFor();
    decision=false;await page.locator("#connector-tool-list").click();
    await page.getByText("已取消，未连接科研服务。").waitFor();
    assert.equal(fs.existsSync(log),false);
    decision=true;await page.locator("#connector-tool-list").click();
    await page.locator("#connector-tool").selectOption("lookup");
    await page.locator("#connector-args").fill('{"query":"source evidence"}');
    await page.locator("#connector-call").click();
    await page.locator("#resource-text").waitFor();
    assert.equal(await page.locator("#resource-text").inputValue(),"source evidence");
    assert.ok(questions.at(-1).includes('"query":"source evidence"'));
    await page.locator("#resource-text").evaluate(n=>n.setSelectionRange(0,6));
    await page.locator("#select-excerpt").click();
    assert.equal(await page.locator("#excerpt").textContent(),"source");
    assert.equal(fs.readFileSync(log,"utf8").split("\n").filter(x=>x==="tools/call").length,1);
    await page.locator("#project").selectOption(other);
    await page.waitForFunction(()=>document.querySelector("#connector-select").options.length===1);
    assert.equal(await page.locator("#source").isVisible(),false);
    assert.equal(await page.locator("#connector-token").inputValue(),"");
    assert.deepEqual(errors,[]);
    console.log("Project registration, desktop trust, cancel, read-only discovery, exact-argument approval, excerpt selection and project switch passed.");
  }finally{await browser.close();}
}
main(...process.argv.slice(2)).catch(e=>{console.error(e);process.exitCode=1;});
