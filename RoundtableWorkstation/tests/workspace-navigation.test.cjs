"use strict";

const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const navigation = require("../static/workspace-nav.js");
const read = name => readFileSync(path.join(__dirname, "../static", name), "utf8");
const origin = "http://127.0.0.1:18765";

test("every desktop surface mounts the same workspace navigation", () => {
  for (const page of ["research", "reader", "studio", "lab", "science-tools"]) {
    const markup = read(page + ".html");
    assert.equal(markup.match(/<nav data-workspace-nav /g)?.length, 1, page);
    assert.match(markup, /src="\/static\/workspace-nav.js"/);
  }
  const links = navigation.destinations(new URL("/reader?paper=astro&project=project-B", origin));
  assert.deepEqual(links.map(l => l.key), ["home","projects","library","calendar","lab","settings"]);
  assert.equal(links.find(l => l.active).key, "projects");
  for (const link of links) {
    const url = new URL(link.href, origin);
    assert.equal(url.searchParams.get("project"), link.key === "lab" ? "project-B" : null);
  }
  assert.equal(navigation.destinations(new URL("/studio?view=settings&project=A", origin)).find(l => l.active).key, "settings");
  assert.equal(navigation.destinations(new URL("/reader?paper=astro", origin)).find(l => l.active).key, "library");
});

function mountResearch(start) {
  const projects = [{id:"A",name:"Solar",path:"/one"}, {id:"B",name:"Lensing",path:"/two"}];
  const papers = [{id:"p1",title:"Solar paper",project_ids:["A"]},{id:"p2",title:"Lensing paper",project_ids:["B"]}];
  const tasks = projects.map(p => ({id:"task" + p.id, projectId:p.id, title:p.name + " task", revision:3,status:"open"}));
  const responses = new Map([
    ["/api/research/projects", projects], ["/api/research/papers", papers], ["/api/research/tasks", tasks],
    ["/api/studio/sessions", {sessions:[]}],
  ]);
  for (const p of projects) {
    for (const [k,v] of Object.entries({notes:[],tasks:tasks.filter(t => t.projectId === p.id),materials:[],graph:{nodes:[],edges:[]}})) {
      responses.set("/api/research/projects/" + p.id + "/" + k,v);
    }
  }
  const calls = [], listeners = {}, elements = {};
  for (const match of read("research.html").matchAll(/\bid="([^"]+)"/g)) {
    elements[match[1]] = {classList:{remove(){}},setAttribute(){},addEventListener(){},replaceChildren(){}};
  }
  const document = {getElementById:id=>elements[id],querySelectorAll:()=>[],addEventListener:(event,cb)=>{listeners[event]=cb;}};
  const location = {href:new URL(start, origin).href,origin};
  const history = {pushState:(_s,_t,url)=>{location.href=new URL(url,origin).href;},replaceState:(_s,_t,url)=>{location.href=new URL(url,origin).href;}};
  const window = {addEventListener(){},RoundtableIcons:{icon:()=>""},SciStationNav:{...navigation,update(){}}};
  const fetch = async (url, init) => {
    calls.push({url,init});
    if(init.method==="PATCH" && url==="/api/research/projects/B/tasks/taskB")return Response.json({});
    assert.ok(responses.has(url),url);
    return Response.json(responses.get(url));
  };
  const context={window,document,location,history,fetch,URL,URLSearchParams,FormData,
    localStorage:{getItem:()=>"B"},setTimeout,clearTimeout};
  vm.runInNewContext(read("research.js"), context);
  return {ui:window.SciResearch,elements,calls,listeners};
}

test("global library deep links stay global; project drilldown restricts the same papers", async () => {
  const {ui,elements,calls} = mountResearch("/research?view=papers");
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(ui.state.project,null);
  assert.match(elements.main.innerHTML,/Solar paper/);
  assert.match(elements.main.innerHTML,/Lensing paper/);
  assert.equal(elements["project-modules"].hidden,true);
  assert.equal(calls.some(c=>c.url.includes("/projects/B")),false);
  await ui.load("A","papers");
  assert.match(elements.main.innerHTML,/Solar paper/);
  assert.doesNotMatch(elements.main.innerHTML,/Lensing paper/);
  assert.equal(elements["project-modules"].hidden,false);
  await ui.load("missing","tasks");
  assert.match(elements.main.innerHTML,/这个项目已归档或不存在/);
});

test("global tasks act on the owning project and reload the global calendar", async () => {
  const {ui,elements,calls,listeners} = mountResearch("/research?view=tasks");
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(ui.state.project,null);
  assert.match(elements.main.innerHTML,/Solar task/);
  assert.match(elements.main.innerHTML,/Lensing task/);
  const button={dataset:{action:"toggle-task",id:"taskB"},hasAttribute:()=>false};
  await listeners.click({target:{closest:()=>button}});
  const writes=calls.filter(c=>c.init.method==="PATCH");
  assert.equal(writes.length,1);
  assert.equal(writes[0].url,"/api/research/projects/B/tasks/taskB");
  assert.deepEqual(JSON.parse(writes[0].init.body),{revision:3,status:"done"});
  assert.equal(ui.state.project,null);
});

test("a Wiki page link resolves in its named project after the project loads", async () => {
  const {ui} = mountResearch("/research?view=notes&project=A&note=page-1");
  const opened = [];
  ui.openWikiNote = id => opened.push([ui.state.project.id, id]);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(opened, [["A", "page-1"]]);
  assert.equal(ui.wikiURL("page-1"), "/research?view=notes&project=A&note=page-1");

  const missing = mountResearch("/research?view=notes&project=missing&note=page-1");
  missing.ui.openWikiNote = id => opened.push(["unexpected", id]);
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(opened, [["A", "page-1"]]);
});
