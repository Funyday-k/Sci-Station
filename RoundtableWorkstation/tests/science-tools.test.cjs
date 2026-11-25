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
    window:{addEventListener(){}},
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

test("conversion uses an offline credential status, clears saved input, and sends no saved token from the page", async () => {
  const controls = {};
  class Control {
    hidden = true;
    value = "";
    replaceChildren(){ this.value = ""; }
    add(option){ if (!this.value) this.value = option.value; }
  }
  for (const match of html.matchAll(/id="([^"]+)"/g)) controls[match[1]] = new Control();
  const nativeWindow = new EventTarget();
  const changes = [];
  let configured = false;
  let savingFails = false;
  const fetch = async (url, options) => {
    const route = url.replace("/api/research/", "");
    if (route === "projects") return Response.json([]);
    if (route === "papers") return Response.json([{id:"A", title:"Paper A", has_pdf:true}]);
    assert.equal(options.headers["X-Sci-Station-Credential-Session"], "fixture-desktop-session");
    const body = options.body && JSON.parse(options.body);
    changes.push({route, body});
    if (route === "tools/mineru/start") return Response.json({batch:"fixture-batch"});
    assert.equal(route, "tools/mineru/credential");
    if (body?.action === "save") {
      if (savingFails) return Response.json({error:"Keychain denied"}, {status:503});
      configured = true;
    }
    if (body?.action === "clear") configured = false;
    return Response.json({configured});
  };
  vm.runInNewContext(script, {
    document:{getElementById:id=>controls[id],querySelectorAll:()=>[]},
    window:nativeWindow, Option:class{constructor(text,value){this.value=value;}},
    location:{search:"?tab=convert"}, URLSearchParams, fetch, confirm:()=>true
  });
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(controls.minerCredentialActions.hidden, true);
  assert.equal(changes.length, 0);
  nativeWindow.sciStationCredentialSession = "fixture-desktop-session";
  nativeWindow.dispatchEvent(new Event("scistation:credential-session"));
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(controls.minerCredentialActions.hidden, false);
  assert.equal(controls.minerClear.disabled, true);

  controls.token.value = "fixture-miner-input";
  savingFails = true;
  await controls.minerSave.onclick();
  assert.equal(controls.token.value, "fixture-miner-input");
  assert.equal(controls.status.textContent, "Keychain denied");
  savingFails = false;
  await controls.minerSave.onclick();
  assert.equal(controls.token.value, "");
  assert.equal(controls.minerClear.disabled, false);
  await controls.remote.onclick();
  assert.deepEqual(changes.at(-1), {route:"tools/mineru/start", body:{paper:"A", token:"", batch:""}});
  assert.equal(controls.batch.value, "fixture-batch");
  await controls.minerClear.onclick();
  assert.equal(controls.minerClear.disabled, true);
  assert.deepEqual(changes.at(-1), {route:"tools/mineru/credential", body:{action:"clear"}});
});

const discoveryScript = fs.readFileSync(path.join(base, "discovery-view.js"), "utf8");

test("a reopened discovery run restores its filters and can retry a partially completed reading task", async () => {
  const controls = {};
  class Control {
    children = []; value = ""; checked = true; attributes = {};
    replaceChildren(...nodes) { this.children = nodes; }
    add(option) { this.children.push(option); }
    append(...nodes) { this.children.push(...nodes); }
    setAttribute(key, value) { this.attributes[key] = value; }
  }
  for (const match of html.matchAll(/id="([^"]+)"/g)) controls[match[1]] = new Control();
  controls.filter.value = "all";
  const paper = {arxiv: "2404.12345v3", title: "Capture", tags: ["hep-ph"], primary_category: "hep-ph"};
  const history = [
    {id: "new", query: "evaporation", updated: "2026-10-21T10:00:00Z", count: 0, source: "arxiv"},
    {id: "old", query: "capture", updated: "2026-10-20T10:00:00Z", count: 1, source: "arxiv"}
  ];
  const addedTasks = [], imports = [];
  const fetch = async (url, options) => {
    const route = url.replace("/api/research/", "");
    if (route === "projects") return Response.json([{id: "project", name: "Solar"}, {id: "unavailable", name: "Unavailable"}]);
    if (route === "tools/discover?project=unavailable") return Response.json({error: "fixture project failed"}, {status: 500});
    if (route.includes("project=unavailable")) return Response.json([]);
    if (route === "tools/discover?project=project") {
      return Response.json({...history[0], history, items: []});
    }
    if (route === "tools/discover?project=project&run=old") {
      return Response.json({...history[1], history, items: [paper], feedback: {"2404.12345v2":"liked"}, categories: ["hep-ph"], cross_list: false, top_k: 7});
    }
    if (["papers?project=project", "papers/recommendations?project=project"].includes(route)) return Response.json([]);
    if (route === "tools/select-discovery?project=project" && options.method === "POST") {
      imports.push(JSON.parse(options.body));
      return Response.json({id: "stable-id", title: paper.title});
    }
    if (route === "projects/project/tasks" && options.method === "POST") {
      addedTasks.push(JSON.parse(options.body));
      if (addedTasks.length === 1) return Response.json({error: "fixture failure"}, {status: 500});
      return Response.json({id: "saved-task"});
    }
    if (route === "tools/feedback?project=project" && options.method === "POST") {
      const {run, key, state} = JSON.parse(options.body);
      assert.equal(run, "old");
      return Response.json({feedback: {[key]: state}});
    }
    throw Error("Unexpected route " + route);
  };
  const context = vm.createContext({
    document: {getElementById: id => controls[id], querySelectorAll: () => [], createElement: () => new Control()},
    Option: class {constructor(text, value) {this.value = value;}},
    location: new URL("http://localhost/tools?tab=discover&project=project"), URL, URLSearchParams, fetch,
    history: {replaceState() {}},
    window: {SciStationNav: {commitURL(url) { context.location = url; }}}
  });
  vm.runInContext(discoveryScript, context);
  vm.runInContext(script, context);
  await new Promise(resolve => setImmediate(resolve));
  controls.history.value = "old";
  await controls.history.onchange();
  assert.equal(controls.expr.value, "capture");
  assert.equal(controls.categories.value, "hep-ph");
  assert.equal(controls.crossList.checked, false);
  assert.equal(controls.topK.value, 7);
  assert.equal(controls.articles.children[0].children[2].href, "https://arxiv.org/abs/2404.12345v3");

  const action = text => controls.articles.children[0].children.at(-1).children.find(el => el.textContent === text);
  assert.equal(action("取消相关").attributes["aria-pressed"], "true");
  await action("入库并加入阅读待办").onclick();
  assert.match(controls.status.textContent, /论文已入库。阅读待办创建失败，可重试/);
  await action("入库并加入阅读待办").onclick();
  assert.equal(controls.status.textContent, "论文已入库，阅读待办已就绪");
  assert.equal(controls.readingTaskOpen.href, "/research?view=tasks&project=project&task=saved-task");
  assert.equal(controls.readingTaskOpen.hidden, false);
  assert.deepEqual(imports, [{run:"old", key:"2404.12345", fetch_pdf:true}, {run:"old", key:"2404.12345", fetch_pdf:true}]);
  assert.equal(addedTasks.length, 2);
  assert.deepEqual(addedTasks[0], addedTasks[1]);
  assert.equal(addedTasks[0].idempotencyKey, "reading:stable-id");
  assert.equal(addedTasks[0].kind, "reading");
  assert.deepEqual(addedTasks[0].relatedPaperIds, ["stable-id"]);
  assert.match(addedTasks[0].description, /2404\.12345v3/);
  controls.filter.value = "saved";
  controls.filter.onchange();
  assert.equal(controls.articles.children[0].children[0].textContent, "Capture");
  await action("隐藏").onclick();
  assert.match(controls.articles.children[0].textContent, /当前没有/);
  controls.filter.value = "hidden";
  controls.filter.onchange();
  assert.equal(action("取消隐藏").attributes["aria-pressed"], "true");

  controls.project.value = "unavailable";
  controls.project.onchange();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(controls.status.textContent, "fixture project failed");
  assert.equal(controls.expr.value, "");
  assert.equal(controls.categories.value, "");
  assert.equal(controls.archiveRun.disabled, true);
  assert.equal(controls.readingTaskOpen.hidden, true);
  assert.match(controls.articles.children[0].textContent, /运行检索或打开历史记录/);
});
