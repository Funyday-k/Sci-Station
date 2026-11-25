const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const base = path.join(__dirname, "../static");
const script = fs.readFileSync(path.join(base, "science-tools.js"), "utf8");
const html = fs.readFileSync(path.join(base, "science-tools.html"), "utf8");

test("switching papers discards stale conversion; a reviewed edit updates the original note with its revision", async () => {
  const controls = {};
  class Control {
    hidden = true;
    value = "";
    replaceChildren(){ this.value = ""; }
    add(option){ if (!this.value) this.value = option.value; }
  }
  for (const match of html.matchAll(/id="([^"]+)"/g)) controls[match[1]] = new Control();
  const papers = ["A", "B"].map(id => ({id, title: "Paper "+id, has_pdf: true}));
  const changes = [];
  let finishA;
  async function fetch(url, opt) {
    const route = url.replace("/api/research/", "");
    if (route === "projects") return Response.json([{id:"project", name:"Research"}]);
    if (route === "papers") return Response.json(papers);
    if (route === "projects/project/tasks") return Response.json([]);
    if (route === "papers/A/markdown") return new Promise(resolve => { finishA=()=>resolve(new Response("old A")); });
    if (route === "papers/B/markdown") return new Response("text B");
    if (route === "projects/project/notes" && !opt.method) return Response.json([]);
    if (opt.method && route.startsWith("projects/project/notes")) {
      changes.push({route,method: opt.method,body:JSON.parse(opt.body)});
      return Response.json({id:"N", revision:changes.length});
    }
    throw Error("Unexpected route "+route);
  }
  vm.runInNewContext(script,{
    document:{getElementById:id=>controls[id],querySelectorAll:()=>[]},
    Option:class{constructor(text,value){this.value=value;}},
    location:{search:"?tab=convert&project=project"},URLSearchParams,
    fetch,crypto:{randomUUID:()=>"conversion-test"},confirm:()=>true
  });
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(controls.paper.value, "A");
  const first = controls.local.onclick();
  controls.paper.value = "B"; controls.paper.onchange(); finishA(); await first;
  assert.equal(controls.result.hidden,true);
  await controls.local.onclick();
  assert.equal(controls.markdown.value, "text B");
  await controls.saveNote.onclick();
  controls.markdown.value="reviewed B"; await controls.saveNote.onclick();
  assert.equal(changes[0].body.paperId,"B");
  assert.deepEqual(changes[1],{route:"projects/project/notes/N",method:"PATCH",body:{revision:1,body:"reviewed B"}});
});
