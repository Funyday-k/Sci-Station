"use strict";

const assert = require("node:assert/strict");
const {mkdir, mkdtemp, realpath, rm, writeFile} = require("node:fs/promises");
const path = require("node:path");
const {tmpdir} = require("node:os");
const {chromium} = require("playwright");
const {listen, closeServer, fixtureHome, launch} = require("./workstation-workflow-smoke.cjs");

async function main(binary) {
  const base = await mkdtemp(path.join(await realpath(tmpdir()), "sci-paper-question-"));
  const prompts = [];
  const gateway = await listen(async (req, res) => {
    res.setHeader("Content-Type", "application/json");
    if (req.url === "/v1/models") {
      res.end(JSON.stringify({data:[{id:"fixture/first", display_name:"Paper QA fixture", owned_by:"fixture",
        kind:"chat", native_endpoints:["/v1/chat/completions"]}]}));
      return;
    }
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const input = JSON.parse(Buffer.concat(chunks));
    const prompt = input.messages.at(-1).content;
    const isTitle = prompt.startsWith("TITLE REQUEST:");
    if (!isTitle) prompts.push(prompt);
    const content = isTitle ? "Cited source question" : JSON.stringify({action:"say", text:"This excerpt supplies the requested evidence [S1]."});
    res.end(JSON.stringify({model:input.model, choices:[{finish_reason:"stop",message:{content}}]}));
  });
  let host, browser;
  try {
    const spec = path.join(base, "Smoke.app", "Contents", "Resources", "sci-station.agent.js");
    await mkdir(path.dirname(spec), {recursive:true});
    await writeFile(spec, "// Offline registration fixture.\n");
    const env = await fixtureHome(base, gateway.address().port, spec);
    const probe = await listen(), port = probe.address().port;
    await closeServer(probe);
    host = await launch(binary, port, path.join(base, "root"), env, "serve");
    const project = await host.request("/api/research/projects", "POST", {name:"Formula fixture"}, 201);
    async function addPaper(order, title, body) {
      const p = await host.request("/api/research/papers", "POST", {title, project_ids:[project.id]}, 201);
      const organized = await host.request("/api/research/papers/"+p.id, "PATCH", {
        revision:p.revision, project_links:{[project.id]:{sort_order:order}}
      });
      const form = new FormData();
      form.append("revision", organized.revision);
      form.append("file", new Blob([body], {type:"text/markdown"}), "paper.md");
      return host.request("/api/research/papers/"+p.id+"/body", "POST", form);
    }
    const caption = "**Figure 2.** Measured rate at fixed temperature.";
    const formula = "E_{\\odot}=kA(p_s-p_a)\\tag{2}";
    await addPaper(1, "Study first", "# Results\nFigure 2. A distractor in the first paper.");
    await addPaper(2, "Study second", "# Abstract\nAnother study.");
    const target = await addPaper(3, "Study third", "# Results\n"+caption+"\n\n## Evaporation Rate\n$$\n"+formula+"\n$$");

    browser = await chromium.launch({headless:true, executablePath:process.env.SCI_STATION_SMOKE_CHROME});
    const page = await browser.newPage({locale:"zh-CN",viewport:{width:1440,height:900}});
    page.setDefaultTimeout(15000);
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    const baseURL = host.origin;
    const projectQuery = "project="+project.id;
    const selection = "第三篇论文的 Figure 2 说明了什么？";
    const question = "第三篇论文的蒸发率公式是什么？";
    const approve = async (button, accept) => {
      const dialog = page.waitForEvent("dialog");
      const submitted = button.click();
      const review = await dialog;
      const message = review.message();
      if (accept) await review.accept();
      else await review.dismiss();
      await submitted;
      return message;
    };

    await page.goto(baseURL+"/lab?"+projectQuery);
    await page.locator("#question").fill(question);
    const start = page.locator("#lab-start");
    const declined = await approve(start, false);
    assert.match(declined, /Study third\nEvaporation Rate · L5–7/);
    assert.ok(declined.includes(formula));
    assert.equal(prompts.length, 0);
    assert.equal(await page.locator("#question").inputValue(), question);

    await page.locator("#question").fill("第三篇论文的 Figure 20");
    await start.click();
    await page.getByText(/未定位到图 20 的图注/).waitFor();
    assert.equal(prompts.length, 0);
    await page.locator("#question").fill(question);
    assert.equal(await approve(start, true), declined);
    await page.getByText("This excerpt supplies the requested evidence", {exact:false}).waitFor();
    const evidence = page.locator("#lab-citation-items a");
    assert.match(await evidence.textContent(), /Evaporation Rate · L5–7/);
    const href = new URL(await evidence.getAttribute("href"), baseURL);
    assert.equal(href.searchParams.get("paper"), target.id);
    assert.equal(href.searchParams.get("fingerprint"), target.markdown_source.sha256);
    assert.equal(href.searchParams.get("offset"), String([...("# Results\n"+caption+"\n\n## Evaporation Rate\n")].length));
    assert.equal(prompts.length, 1);
    assert.ok(prompts[0].includes("E_{") && prompts[0].includes("citation_id"));
    assert.ok(!prompts[0].includes("distractor"));

    await addPaper(0, "Excluded from filter", "# Results\nFigure 2. A different experiment.");
    await page.goto(baseURL+"/research?view=papers&"+projectQuery);
    const query = page.locator("#paper-query");
    await query.fill("Study");
    await page.waitForFunction(() => window.SciResearch.library.visiblePaperIds().length === 3);
    await page.locator("#shell-assist").click();
    await page.waitForFunction(() => document.querySelector("#rail-model").value);
    await page.locator("#rail-prompt").fill(selection);
    const railSend = page.locator("#rail-send");
    const figure = await approve(railSend, true);
    assert.ok(figure.includes(caption));
    assert.match(figure, /Study third\nResults · L2/);
    const railEvidence = page.locator("#rail-transcript").getByRole("link", {name:/S1.*Study third.*Results · L2/});
    await railEvidence.waitFor();
    assert.equal(new URL(await railEvidence.getAttribute("href"),baseURL).searchParams.get("paper"),target.id);
    assert.equal(prompts.length, 2);
    assert.ok(prompts[1].includes(caption));
    assert.ok(!prompts[1].includes("distractor") && !prompts[1].includes("A different experiment"));
    assert.deepEqual(errors, []);
    console.log("AI Lab and the context rail select exact scoped paper passages, preserve consent, and expose source locations.");
  } finally {
    await browser?.close();
    await host?.close();
    await closeServer(gateway);
    await rm(base, {recursive:true,force:true});
  }
}

main(process.argv[2]).catch(error => { console.error(error); process.exitCode = 1; });
