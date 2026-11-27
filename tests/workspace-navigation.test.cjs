"use strict";

const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const navigation = require("../web/static/workspace-nav.js");
const read = name => readFileSync(path.join(__dirname, "../web/static", name), "utf8");
const origin = "http://127.0.0.1:18765";

test("every desktop surface mounts the same workspace navigation", () => {
  const shell = read("workspace-shell.html");
  assert.equal(shell.match(/<nav data-workspace-nav /g).length, 1);
  const sidebar = shell.slice(shell.indexOf('<aside id="workspace-sidebar"'), shell.indexOf('</aside>'));
  assert.match(sidebar, /<nav data-workspace-nav /);
  assert.match(sidebar, /class="workspace-sidebar-footer workspace-main-nav">\s*<nav data-workspace-settings /);
  assert.doesNotMatch(shell, /class="workspace-roots"/);
  assert.match(sidebar, /id="workspace-context"/);
  assert.match(sidebar, /id="workspace-projects"/);
  assert.match(sidebar, /id="projectnav"/);
  assert.doesNotMatch(read("research.html"), /id="projectnav"|id="project-modules"/);
  assert.match(shell, /id="workspace-nav-toggle"[^>]+aria-controls="workspace-sidebar"/);
  assert.match(shell, /id="rail-close"/);
  assert.doesNotMatch(shell, /id="shell-inspect"/);
  assert.doesNotMatch(read("research.html"), /id="nav-toggle"/);
  assert.match(shell,/src="\/static\/workspace-nav.js"/);
  assert.match(shell,/{{template "content" ./);
  for (const page of ["research", "reader", "studio", "lab", "science-tools","api"]) {
    const markup = read(page + ".html");
    assert.match(markup,/{{define "content"}}/,page);
    assert.doesNotMatch(markup,/<nav data-workspace-nav |<body|<iframe/i,page);
  }
  const links = navigation.destinations(new URL("/reader?paper=astro&project=project-B", origin));
  assert.deepEqual(links.map(l => l.key), ["home","projects","library","calendar","lab","settings"]);
  assert.equal(links.find(l => l.active).key, "projects");
  for (const link of links) {
    const url = new URL(link.href, origin);
    assert.equal(url.searchParams.get("project"), link.key === "settings" ? "project-B" : null);
  }
  assert.equal(navigation.destinations(new URL("/studio?view=settings&project=A", origin)).find(l => l.active).key, "settings");
  assert.equal(navigation.destinations(new URL("/reader?paper=astro", origin)).find(l => l.active).key, "library");
});

test("AI has one global entry and explicit chat and discussion modes with optional project scope", () => {
  for (const [path, mode] of [["/lab?project=A", "single"], ["/studio?project=A&session=room", "roundtable"]]) {
    const url = new URL(path, origin);
    const links = navigation.destinations(url);
    assert.equal(links.find(link => link.active).name, "AI");
    assert.equal(links.find(link => link.key === "lab").href, "/lab?scope=global");
    assert.equal(navigation.aiMode(url), mode);
  }
  assert.equal(navigation.modeURL("single", "A"), "/lab?project=A");
  assert.equal(navigation.modeURL("roundtable", null), "/studio?scope=global");
  assert.equal(navigation.aiMode(new URL("/studio?view=settings", origin)), "");
});

test("AI commands stay unavailable until the active workspace confirms its module", async () => {
  let complete;
  const config = new Promise(resolve => { complete = resolve; });
  const window = Object.assign(new EventTarget(), {SciStationModules:{load: () => config}});
  const links = {dataset:{},replaceChildren(...items){this.items = items;}};
  const document = {
    getElementById:()=>null,
    querySelector:selector => selector === "[data-workspace-nav]" ? links : null,
    createElement:()=>({dataset:{},setAttribute(){},append(){}}),addEventListener(){}
  };
  const location = new URL("/research", origin);
  const destinations = [];
  location.assign = value => destinations.push(value);
  const history = {state:null,replaceState(state){this.state=state;}};
  vm.runInNewContext(read("workspace-nav.js"),{window,document,history,location,URL,URLSearchParams,CustomEvent,Event,performance,fetch:async()=>({ok:true})});
  const nav = window.SciStationNav;
  const visible = () => links.items.some(link=>link.dataset.section === "lab");
  assert.equal(visible(),false);
  nav.command("lab");
  nav.command("roundtable");
  assert.deepEqual(destinations,[]);
  const moduleState = effective => ({modules:[{id:"ai-lab", effective}]});
  window.dispatchEvent(new CustomEvent("sci:modules",{detail:{project:"",state:moduleState(false)}}));
  complete(moduleState(true));
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(visible(), false);
  window.dispatchEvent(new CustomEvent("sci:modules",{detail:{project:"",state:moduleState(true)}}));
  assert.equal(visible(),true);
  nav.command("lab");
  assert.deepEqual(destinations,["/lab?scope=global"]);
});

function mountResearch(start, sessions=[], intercept) {
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
    elements[match[1]] = {classList:{remove(){},toggle(){}},setAttribute(){},addEventListener(){},replaceChildren(){}};
  }
  elements.modal.addEventListener = (event, handler) => { listeners["modal." + event] = handler; };
  const document = {getElementById:id=>elements[id],querySelector:()=>null,querySelectorAll:()=>[],addEventListener:(event,cb)=>{listeners[event]=cb;}};
  const location = {href:new URL(start, origin).href,origin};
  const window = Object.assign(new EventTarget(), {RoundtableIcons:{icon:()=>""}});
  window.SciStationModules = {
    load: async () => ({modules:Object.values(navigation.viewModules).map(id=>({id,effective:true}))})
  };
  const entries = [{state:null,href:location.href}];
  let index = 0;
  const history = {
    get state() { return entries[index].state; },
    get length() { return entries.length; },
    replaceState(state, _, url = location.href) {
      entries[index] = {state,href:new URL(url,origin).href};
      location.href = entries[index].href;
    },
    pushState(state, _, url) {
      entries.splice(++index, entries.length);
      this.replaceState(state, _, url);
    },
    go(delta) {
      queueMicrotask(() => {
        index += delta;
        location.href = entries[index].href;
        window.dispatchEvent(Object.assign(new Event("popstate"), {state:history.state}));
      });
    }
  };
  const fetch = async (url, init) => {
    calls.push({url,init});
    const intercepted = intercept?.(url, init);
    if (intercepted) return intercepted;
    if(init.method==="PATCH" && url==="/api/research/projects/B/tasks/taskB")return Response.json({});
    assert.ok(responses.has(url),url);
    return Response.json(responses.get(url));
  };
  const context={window,document,location,history,fetch,URL,URLSearchParams,FormData,Event,
    localStorage:{getItem:()=>"B"},setTimeout,clearTimeout};
  const sandbox = vm.createContext(context);
  for (const script of ["workspace-nav.js", "research.js", "research-forms.js", "research-library.js"]) {
    vm.runInContext(read(script), sandbox);
  }
  return {ui:window.SciResearch,elements,calls,listeners,window,history,location};
}

test("research keeps stale content inert and retries the failed project and calendar view", async () => {
  const hold = Promise.withResolvers();
  let fail = false;
  let delayed = true;
  const area = "/api/research/projects/B/tasks";
  const {ui, elements, listeners, location} = mountResearch("/research?view=tasks&project=A", [], url => {
    if (url !== area) return;
    if (delayed) {
      delayed = false;
      return hold.promise;
    }
    if (fail) return Response.json({error: "Task fixture unavailable"}, {status: 503});
  });
  const tick = () => new Promise(resolve => setImmediate(resolve));
  await tick();
  const firstSwitch = ui.load("B", "tasks", {historyMode: "push", calendar: true});
  await tick();
  assert.equal(elements.main.inert, true);
  assert.equal(elements["research-loading"].hidden, false);
  assert.match(elements["research-loading-message"].textContent, /Lensing/);
  assert.match(elements.main.innerHTML, /Solar task/);
  assert.equal(elements["search-open"].disabled, true);
  await ui.load("A", "tasks", {historyMode: "push"});
  hold.resolve(Response.json([{title: "Late Lensing task", status: "open"}]));
  await firstSwitch;
  assert.equal(elements.main.inert, false);
  assert.equal(elements["research-loading"].hidden, true);
  assert.doesNotMatch(elements.main.innerHTML, /Late Lensing task/);
  assert.equal(ui.state.project.id, "A");

  fail = true;
  await ui.load("B", "tasks", {historyMode: "push", calendar: true});
  assert.match(elements.main.innerHTML, /role="alert".*Task fixture unavailable/s);
  assert.match(elements.main.innerHTML, /data-action="reload"/);
  assert.doesNotMatch(elements.main.innerHTML, /当前列表没有任务/);
  assert.equal(new URL(location.href).searchParams.get("project"), "A");
  fail = false;
  await listeners.click({target: {closest: () => ({dataset: {action: "reload"}, hasAttribute: () => false})}});
  assert.equal(ui.state.project.id, "B");
  assert.equal(new URL(location.href).searchParams.get("tab"), "calendar");
  assert.match(elements.main.innerHTML, /class="calendar-head"/);
});

test("global library deep links stay global; project drilldown restricts the same papers", async () => {
  const {ui,elements,calls} = mountResearch("/research?view=papers");
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(ui.state.project,null);
  assert.match(elements.main.innerHTML,/Solar paper/);
  assert.match(elements.main.innerHTML,/Lensing paper/);
  assert.equal(calls.some(c=>c.url.includes("/projects/B")),false);
  await ui.load("A","papers");
  assert.match(elements.main.innerHTML,/Solar paper/);
  assert.doesNotMatch(elements.main.innerHTML,/Lensing paper/);
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

test("canonical and saved calendar routes open the month in the requested project", async () => {
  for (const route of [navigation.research("calendar", "A"), "/research?view=tasks&project=A&calendar=1"]) {
    const {ui, elements, listeners} = mountResearch(route);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(ui.state.calendar, true);
    assert.equal(ui.state.project.id, "A");
    assert.match(elements.main.innerHTML, /class="calendar-head"/);
    await listeners.click({target: {closest: () => ({dataset: {action: "switch-calendar"}, hasAttribute: () => false})}});
    await ui.refresh();
    assert.equal(ui.state.calendar, false);
    assert.doesNotMatch(elements.main.innerHTML, /class="calendar-head"/);
  }
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
    body:{dataset:{workspaceSurface:"lab"}},
    getElementById(){return null;},
    createElement(){return {dataset:{},setAttribute(){},append(){}};},
    querySelector(selector){if(selector==="[data-workspace-nav]")return links;return {addEventListener(){},replaceChildren(){},append(){},setAttribute(){}};},
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

test("Research confirms a dirty history traversal once and preserves Back and Forward", async () => {
  const {ui, elements, window, history, location} = mountResearch("/research?project=A&view=notes");
  const settled = () => new Promise(resolve => setImmediate(resolve));
  await settled();
  window.SciStationNav.commitURL("/research?project=A&view=papers", "push");
  window.SciStationNav.commitURL("/research?project=B&view=notes", "push");
  history.go(-1);
  await settled();
  assert.equal(ui.state.view, "papers");
  let browserChecks = 0, editorPrompts = 0, accept = false;
  window.addEventListener("beforeunload", event => {
    browserChecks++;
    event.preventDefault();
  });
  window.confirm = () => { throw Error("duplicate workspace confirmation"); };
  elements.modal.showModal = () => { elements.modal.open = true; };
  elements.modal.close = () => { elements.modal.open = false; };
  ui.dialog("Draft", "Synthetic dirty editor", {canDismiss: () => { editorPrompts++; return accept; }});

  history.go(-1);
  await settled();
  assert.equal(history.length, 3);
  assert.equal(history.state.workspacePosition, 1);
  assert.equal(new URL(location.href).searchParams.get("view"), "papers");
  assert.equal(elements.modal.open, true);
  assert.equal(editorPrompts, 1);
  assert.equal(browserChecks, 0);

  accept = true;
  history.go(-1);
  await settled();
  assert.equal(history.state.workspacePosition, 0);
  assert.equal(ui.state.view, "notes");
  assert.equal(elements.modal.open, false);
  assert.equal(editorPrompts, 2);
  history.go(1);
  await settled();
  history.go(1);
  await settled();
  assert.equal(ui.state.project.id, "B");
  assert.equal(history.state.workspacePosition, 2);
  assert.equal(browserChecks, 0);
});
