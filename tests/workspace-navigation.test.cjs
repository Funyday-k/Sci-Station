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
  const shell = read("workspace-shell.html");
  assert.equal(shell.match(/<nav data-workspace-nav /g).length, 1);
  assert.match(shell,/src="\/static\/workspace-nav.js"/);
  assert.match(shell,/{{template "content" ./);
  for (const page of ["research", "reader", "studio", "lab", "science-tools","api"]) {
    const markup = read(page + ".html");
    assert.match(markup,/{{define "content"}}/,page);
    assert.doesNotMatch(markup,/<nav data-workspace-nav |<body|<iframe/i,page);
  }
  const links = navigation.destinations(new URL("/reader?paper=astro&project=project-B", origin));
  assert.deepEqual(links.map(l => l.key), ["home","projects","library","calendar","lab","roundtable","settings"]);
  assert.equal(links.find(l => l.active).key, "projects");
  for (const link of links) {
    const url = new URL(link.href, origin);
    assert.equal(url.searchParams.get("project"), ["lab","roundtable","settings"].includes(link.key) ? "project-B" : null);
  }
  assert.equal(navigation.destinations(new URL("/studio?view=settings&project=A", origin)).find(l => l.active).key, "settings");
  assert.equal(navigation.destinations(new URL("/reader?paper=astro", origin)).find(l => l.active).key, "library");
});

function mountResearch(start, sessions=[]) {
  const projects = [{id:"A",name:"Solar",path:"/one"}, {id:"B",name:"Lensing",path:"/two"}];
  const papers = [{id:"p1",title:"Solar paper",project_ids:["A"]},{id:"p2",title:"Lensing paper",project_ids:["B"]}];
  const tasks = projects.map(p => ({id:"task" + p.id, projectId:p.id, title:p.name + " task", revision:3,status:"open"}));
  const responses = new Map([
    ["/api/research/projects", projects], ["/api/research/papers", papers], ["/api/research/tasks", tasks],
    ["/api/research/task-tags", {revision: 0, tags: []}],
    ["/api/research/papers/organization", {revision: 0, collections: {}, tags: {}}],
    ["/api/studio/sessions", {sessions}],
  ]);
  for (const p of projects) {
    for (const [k,v] of Object.entries({notes:[],tasks:tasks.filter(t => t.projectId === p.id),materials:[],graph:{nodes:[],edges:[]}, "wiki/folders":[]})) {
      responses.set("/api/research/projects/" + p.id + "/" + k,v);
    }
  }
  const calls = [], listeners = {}, elements = {};
  for (const match of read("research.html").matchAll(/\bid="([^"]+)"/g)) {
    elements[match[1]] = {classList:{remove(){}},setAttribute(){},addEventListener(){},replaceChildren(){}};
  }
  elements.modal.addEventListener = (event, handler) => { listeners["modal." + event] = handler; };
  const document = {getElementById:id=>elements[id],querySelectorAll:()=>[],addEventListener:(event,cb)=>{listeners[event]=cb;}};
  const location = {href:new URL(start, origin).href,origin};
  const history = {pushState:(_s,_t,url)=>{location.href=new URL(url,origin).href;},replaceState:(_s,_t,url)=>{location.href=new URL(url,origin).href;}};
  const window = {addEventListener(){},RoundtableIcons:{icon:()=>""},SciStationNav:{...navigation,update(){},commitURL(url,mode){history[mode+"State"](null,"",url);}}};
  const fetch = async (url, init) => {
    calls.push({url,init});
    if(init.method==="PATCH" && url==="/api/research/projects/B/tasks/taskB")return Response.json({});
    assert.ok(responses.has(url),url);
    return Response.json(responses.get(url));
  };
  const context={window,document,location,history,fetch,URL,URLSearchParams,FormData,
    localStorage:{getItem:()=>"B"},setTimeout,clearTimeout};
  const sandbox = vm.createContext(context);
  for (const script of ["research.js", "research-forms.js", "research-library.js"]) {
    vm.runInContext(read(script), sandbox);
  }
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
  assert.equal(ui.state.project,null);
  assert.equal(ui.state.view,"projects");
  assert.match(elements.toast.textContent,/这个项目已归档或不存在/);
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

test("meeting lists follow the stable project across folder changes and path reuse", async () => {
  const sessions=[
    {id:"moved",project_id:"A",project:"/old",title:"Moved project"},
    {id:"archived",project_id:"archived-ID",project:"/one",title:"Reused directory"},
    {id:"legacy",project:"/one",title:"Unbound legacy meeting"},
    {id:"other",project_id:"B",project:"/two",title:"Other project"}
  ];
  const {ui}=mountResearch("/research?project=A&view=meetings",sessions);
  await new Promise(resolve=>setImmediate(resolve));
  assert.deepEqual(Array.from(ui.state.meetings,s=>s.id),["moved"]);
  await ui.load("B","meetings");
  assert.deepEqual(Array.from(ui.state.meetings,s=>s.id),["other"]);
});

test("declining to leave a draft leaves the active root and history entry intact", () => {
  const callbacks = {};
  const sent = [];
  const historyMoves=[];
  let beforeunload=0;
  const window={
    addEventListener(event,handler){callbacks[event]=handler;},
    dispatchEvent(event){
      if(event.type==="beforeunload"){beforeunload++;return false;}
      return true;
    },
    confirm(){return false;}
  };
  const location=new URL("/lab?project=active",origin);
  const history={
    state:null,
    replaceState(state,_,url){this.state=state;if(url)location.href=url;},
    pushState(state,_,url){this.state=state;location.href=url;},
    go(delta){historyMoves.push(delta);}
  };
  const links={dataset:{},replaceChildren(){}};
  const document={
    createElement(){return {dataset:{},setAttribute(){}};},
    querySelector(selector){if(selector==="[data-workspace-nav]")return links;return {addEventListener(){}};},
    addEventListener(){}
  };
  vm.runInNewContext(read("workspace-nav.js"),{
    document,window,history,location,URL,URLSearchParams,CustomEvent,Event,
    performance,fetch:async(path,init)=>{sent.push({path,init});return new Response(null,{status:204});}
  });
  window.SciStationNav.command("openWorkspace");
  assert.equal(sent.some(item=>item.path==="/api/workspace/open"),false);
  assert.equal(location.search,"?project=active");
  window.SciStationNav.commitURL("/lab?project=other","push");
  const savedCount=sent.length;
  let stopped=0;
  callbacks.popstate({state:{workspacePosition:0},stopImmediatePropagation(){stopped++;}});
  assert.deepEqual(historyMoves,[1]);
  callbacks.popstate({state:{workspacePosition:1},stopImmediatePropagation(){stopped++;}});
  assert.equal(stopped,2);
  assert.equal(beforeunload,2);
  assert.equal(sent.length,savedCount);
});

test("an earlier modal close event preserves newly opened Wiki page content", async () => {
  const {elements, listeners} = mountResearch("/research?view=notes&project=A");
  await new Promise(resolve => setImmediate(resolve));
  let cleared = 0;
  elements["dialog-content"].replaceChildren = () => { cleared++; };
  elements.modal.open = true;
  listeners["modal.close"]();
  assert.equal(cleared, 0);
  elements.modal.open = false;
  listeners["modal.close"]();
  assert.equal(cleared, 1);
});
