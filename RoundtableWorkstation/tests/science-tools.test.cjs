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

const ranking = require("../static/discovery-ranking.js");
test("arXiv ranking uses the project, category boundary, cross-lists, feedback and diversity", () => {
  const one = {arxiv:"2401.00001v1", title:"Solar evaporation", tags:["hep-ph","hep-ex"]};
  const duplicate = {...one, arxiv:"2401.00001v2"};
  const neighbor = {...one, arxiv:"2401.00002"};
  const different = {arxiv:"2401.00003", title:"Detector calibration", tags:["hep-ex"]};
  const feed = {items:[different, one, duplicate, neighbor]};
  const options = {category:"HEP-EX", crossList:true, filter:"all", papers:[], project:{description:"solar evaporation"}};
  const rank = (changes = {}) => ranking.candidates(feed, {...options, ...changes}).map(p => p.arxiv);
  assert.deepEqual(rank(), [one.arxiv, different.arxiv, neighbor.arxiv]);
  assert.deepEqual(rank({crossList:false}), [different.arxiv]);
  assert.deepEqual(rank({project:{description:"detector calibration"}})[0], different.arxiv);
  feed.feedback = {"2401.00001":"hidden", "2401.00003v1":"saved"};
  assert.deepEqual(rank({filter:"saved"}), [different.arxiv]);
  assert.deepEqual(rank({filter:"hidden"}), [one.arxiv]);
  assert.deepEqual(rank({category:"astro-ph.HE"}), []);
});

test("adding a candidate twice reuses the library ID and a project-scoped reading task key", async () => {
  const controls = {};
  class Control {
    children = []; value = ""; checked = true;
    replaceChildren(...nodes) {this.children = nodes;}
    add(option) {this.children.push(option);}
    append(...nodes) {this.children.push(...nodes);}
  }
  for (const match of html.matchAll(/id="([^"]+)"/g)) controls[match[1]] = new Control();
  controls.filter.value = "all";
  const p = {arxiv:"2404.12345v3", title:"Capture", tags:["hep-ph"]};
  const addedTasks = [];
  const imports = [];
  const project = "project";
  const fetch = async (url, options) => {
    const route = url.replace("/api/research/", "");
    if (route === "projects") return Response.json([{id:project, name:"Solar"}]);
    if (route === "tools/discover?project=project") return Response.json({items:[p]});
    if (["papers?project=project","papers/recommendations?project=project"].includes(route)) return Response.json([]);
    if (route === "papers" && options.method === "POST") {
      imports.push(JSON.parse(options.body));
      return Response.json({id:"stable-id", title:p.title});
    }
    if (route === "projects/project/tasks" && options.method === "POST") {
      addedTasks.push(JSON.parse(options.body));
      return Response.json({id:"saved-task"});
    }
    throw Error("Unexpected route "+route);
  };
  vm.runInNewContext(script, {
    document: {getElementById:id=>controls[id], querySelectorAll:()=>[], createElement:()=>new Control()},
    Option:class{constructor(text,value){this.value=value;}},
    location:{search:"?tab=discover&project=project"},URLSearchParams,fetch,SciStationDiscovery:ranking
  });
  await new Promise(resolve=>setImmediate(resolve));
  for (let i=0; i<2; i++) {
    const actions = controls.articles.children[0].children.at(-1);
    await actions.children.find(el=>el.textContent==="入库并加入阅读待办").onclick();
  }
  assert.deepEqual(imports.map(p=>p.project_ids),[[project],[project]]);
  assert.equal(addedTasks.length,2);
  assert.deepEqual(addedTasks[0],addedTasks[1]);
  assert.equal(addedTasks[0].idempotencyKey, "reading:stable-id");
  assert.equal(addedTasks[0].paperId, "stable-id");
});
