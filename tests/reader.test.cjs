const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
const {test} = require("node:test");
const vm = require("node:vm");

const html = readFileSync(join(__dirname, "../web/static/reader.html"), "utf8");
const script = readFileSync(join(__dirname, "../web/static/reader.js"), "utf8");
const shellHTML = readFileSync(join(__dirname, "../web/static/workspace-shell.html"), "utf8");
const railScript = readFileSync(join(__dirname, "../web/static/context-rail.js"), "utf8");
const nextTurn = () => new Promise(resolve => setImmediate(resolve));

class Element extends EventTarget {
  constructor() {
    super();
    this.children = [];
    this.style = {setProperty(name, value) { this[name] = value; }};
    this.dataset = {};
    this.value = "";
    this.isConnected = true;
    this.classList = {toggle() {}};
    this.clientWidth = 500;
    this.clientHeight = 650;
    this.scrollHeight = 1250;
    this.scrollTop = 0;
  }
  append(...xs) { this.children.push(...xs); }
  replaceChildren(...xs) { this.children = xs; }
  setAttribute(key, value) { this[key] = value; }
  getAttribute(key) { return this[key]; }
  removeAttribute(key) { delete this[key]; }
  closest() { return null; }
  getContext() { return {measureText: word => ({width: word.length * 8})}; }
  showModal() { this.open = true; }
  close() { this.open = false; }
  focus() { this.focused = true; }
}

async function mount(suffix = "", options = {}) {
  const markup = html + (options.realRail ? shellHTML : "");
  const ids = new Map(Array.from(markup.matchAll(/\bid="([^"]+)"/g), m => [m[1],new Element()]));
  const get = id => { assert.ok(ids.has(id), "missing HTML element " + id); return ids.get(id); };
  const paper = {id: "P1", title:"Paper", authors:["Author"], notes:"old", revision:1,
    file_sha256:"verified", project_ids:["project"], has_pdf:true, ...options.paper};
  const mark = {id:"ann",page:1,kind:"highlight",selected_text:"Evidence",rects:[],
    selectionStart:0,selectionEnd:8};
  const calls = [], memory = new Map();
  let destination, route;
  const browser = new EventTarget();
  browser.getSelection = () => null;
  browser.SciStationNav = {update() {}};
  browser.SciStationModules = {load:async()=>({}),isEnabled:()=>true};
  const railActions = [];
  get("reader-inspector").hidden = true;
  get("notesPanel").hidden = true;
  browser.SciContextRail = {
    update() {},
    show(mode) { railActions.push(["show",mode]); get("reader-inspector").hidden = mode !== "inspector"; },
    toggle(mode) { railActions.push(["toggle",mode]); get("reader-inspector").hidden = !get("reader-inspector").hidden; },
    close() { railActions.push(["close"]); get("reader-inspector").hidden = true; },
    pin() { railActions.push(["pin"]); }
  };
  const env = {
    document:{getElementById:get,createElement:()=>new Element(),createDocumentFragment:()=>new Element(),
      createTextNode:text=>text},
    getComputedStyle:()=>({paddingLeft:"8px"}),
    Image:class {async decode() {}},
    Option:class {constructor(text,value){this.text=text;this.value=value;}},
    sessionStorage:{getItem:k=>memory.get(k) || null,setItem:(k,v)=>memory.set(k,v),removeItem:k=>memory.delete(k)},
    localStorage:{getItem:()=>null,setItem(){}},
    history:{replaceState(_state,_title,url){route=String(url);}},
    location:{search:"?paper=P1&project=project"+suffix,href:"http://localhost/reader?paper=P1&project=project"+suffix,
      origin:"http://localhost",assign:url=>{destination=String(url);}},
    window:browser, URL, URLSearchParams, setTimeout, clearTimeout,
    fetch:async(url, opts)=>{
      calls.push({url,opts});
      let data;
      if(url === "/api/research/papers/P1") {
        if(options.missingPaper)return {ok:false,status:404,text:async()=>JSON.stringify({error:"Missing paper"})};
        if(opts.method==="PUT") {
          const patch = JSON.parse(opts.body);
          if (patch.revision !== paper.revision)
            return {ok:false,status:409,text:async()=>JSON.stringify({error:"conflict"})};
          Object.assign(paper, {notes:patch.notes,revision:paper.revision + 1});
        }
        data={...paper, annotations:[mark]};
      }else if(url.includes("/annotations/ann?revision=")){
        return {ok:false,status:409,text:async()=>JSON.stringify({error:"conflict"})};
      } else if(url.endsWith("/annotations")) {
        if (opts.method === "POST")
          paper.revision++;
        data=[mark];
      } else if(url.endsWith("/verify-evidence")) {
        if (options.invalidQuote)
          return {ok:false,status:409,text:async()=>JSON.stringify({error:"quote mismatch"})};
        return {ok:true,status:204};
      } else if(url.endsWith("/reading-position")) {
        paper.reading_position = JSON.parse(opts.body);
        return {ok:true,status:204};
      } else if(url.endsWith("/pages")) data={pages:2};
      else if(url.endsWith("/pages/1") || url.endsWith("/pages/2")) {
        const box = y => ({x:.1,y,width:.2,height:.1});
        data={width:250,height:350,text:"Evidence Evidence",words:[
          {text:"Evidence",start:0,end:8,box:box(.15)},
          {text:"Evidence",start:9,end:17,box:box(.75)}
        ]};
      } else if(url==="/api/research/projects")data=[{id:"project",name:"Project",path:"/new-path"}];
      else if(url.startsWith("/api/research/projects/"))data={id:url.split("/").at(-1),name:"Project"};
      else if(url==="/api/studio/sessions")data={sessions:[
        {id:"round",title:"Round",project:"/old-path",project_id:"project"},
        {id:"other",title:"Other",project:"/new-path",project_id:"other"}
      ]};
      else throw Error("unexpected fetch "+url);
      return {ok:true,status:200,json:async()=>data};
    }
  };
  if (options.realRail) {
    env.document.body = new Element();
    env.document.body.dataset.workspaceSurface = "reader";
    env.document.title = "Paper · Sci-Station";
    env.document.getElementById = id => ids.get(id) || null;
    env.document.querySelectorAll = () => [];
    env.document.querySelector = () => null;
    env.document.addEventListener = () => {};
    env.matchMedia = () => ({matches:false,addEventListener() {}});
    browser.SciShellLayout = {
      state:{mode:"hidden",panelPinned:false,width:360},
      request:async url => (await env.fetch(url, {method:"GET"})).json(),
      async save(patch) { Object.assign(this.state, patch); browser.SciContextRail.update(); }
    };
    browser.SciStationModules = {load:async()=>({}),isEnabled:()=>false};
    browser.SciStationNav = {
      aiAvailable: () => true,
      update() { browser.SciContextRail?.update(); },
      route(path, params) { return path + "?" + new URLSearchParams(params); },
      commitURL(url) {
        route = String(url);
        env.location.href = route;
        env.location.search = new URL(route).search;
        this.update();
      }
    };
    vm.runInNewContext(railScript, env);
    browser.SciContextRail.update();
  }
  vm.runInNewContext(script,env);
  await nextTurn();
  return {get,calls,memory,paper,browser,railActions,document:env.document,getDestination:()=>destination,getRoute:()=>route};
}

test("editing an annotation on another PDF page keeps explicitly opened details visible", async () => {
  const {get,browser,document,getRoute} = await mount("&page=2", {realRail:true});
  assert.equal(document.body.dataset.railMode, "hidden");
  get("reader-inspect").onclick({currentTarget:get("reader-inspect")});
  assert.equal(document.body.dataset.railMode, "inspector");
  get("annotations").children[0].children[0].children
    .find(button => button.textContent === "编辑").dispatchEvent(new Event("click"));
  await nextTurn();
  assert.equal(get("pageNo").value, 1);
  assert.match(getRoute(), /page=1/);
  assert.equal(document.body.dataset.railMode, "inspector");
  assert.equal(get("reader-inspector").hidden, false);
  assert.equal(get("selectionBox").hidden, false);
  assert.equal(get("comment").focused, true);
  assert.equal(browser.SciShellReader().quote, "Evidence");
});

test("AI stays open with its frozen draft while the same PDF changes page and source anchor", async () => {
  const {get,browser,document,memory} = await mount("&page=1", {realRail:true});
  get("shell-assist").onclick({currentTarget:get("shell-assist")});
  get("rail-prompt").value = "Explain this paper's first-page argument.";
  get("rail-prompt").oninput();
  await get("next").onclick();
  assert.equal(get("pageNo").value, 2);
  assert.equal(document.body.dataset.railMode, "ai");
  assert.equal(get("context-rail").hidden, false);
  const location = "http://localhost/reader?paper=P1&project=project&page=2&quote=Evidence&start=9&end=17&fingerprint=verified";
  browser.SciStationNav.commitURL(location);
  assert.equal(document.body.dataset.railMode, "ai");
  assert.equal(get("rail-prompt").value, "Explain this paper's first-page argument.");
  const draft = JSON.parse(Array.from(memory.entries()).find(([key]) => key.startsWith("sci.shell.draft."))[1]);
  assert.equal(draft.context.paper, "P1");
  assert.equal(draft.context.project, "project");
  assert.equal(draft.context.page, 1);
});

test("reader panels still close across paper, project and surface boundaries", async () => {
  for (const destination of [
    "http://localhost/reader?paper=P2&project=project&page=1",
    "http://localhost/reader?paper=P1&project=another&page=1",
    "http://localhost/research?project=project&view=papers"
  ]) {
    const {get,browser,document} = await mount("&page=1", {realRail:true});
    get("reader-inspect").onclick({currentTarget:get("reader-inspect")});
    browser.SciStationNav.commitURL(destination);
    assert.equal(document.body.dataset.railMode, "hidden", destination);
    assert.equal(get("reader-inspector").hidden, true, destination);
  }
});

test("non-reader navigation continues to dismiss unpinned panels on a query change", async () => {
  const {get,browser,document} = await mount("", {realRail:true});
  document.body.dataset.workspaceSurface = "research";
  browser.SciStationNav.commitURL("http://localhost/research?view=tasks&tab=list");
  get("shell-assist").onclick({currentTarget:get("shell-assist")});
  assert.equal(document.body.dataset.railMode, "ai");
  browser.SciStationNav.commitURL("http://localhost/research?view=tasks&tab=calendar");
  assert.equal(document.body.dataset.railMode, "hidden");
});

test("the shell receives a Reader selection only for a loaded paper", async () => {
  const missing = await mount("", {missingPaper:true});
  assert.equal(missing.browser.SciShellReader(), null);
  const loaded = await mount();
  assert.equal(loaded.browser.SciShellReader().id, loaded.paper.id);
  assert.equal(loaded.browser.SciShellReader().title, loaded.paper.title);
});

test("a stale paper fingerprint displays a warning and does not open the obsolete page anchor",async()=>{
  const {get,calls} = await mount("&page=2&fingerprint=obsolete");
  assert.equal(get("sourceNotice").hidden,false);
  assert.match(get("sourceNotice").textContent,/指纹不同/);
  assert.equal(calls.some(c=>c.url.endsWith("/pages/1")),true);
  assert.equal(calls.some(c=>c.url.endsWith("/pages/2")),false);
});

test("research note changes use the original revision and the desktop request header",async()=>{
  const {get,calls} = await mount();
  get("notes").value="research note";
  get("notes").oninput();
  await get("saveNotes").onclick();
  const write=calls.find(c=>c.opts.method==="PUT");
  assert.equal(write.opts.headers["X-Roundtable"],"1");
  assert.deepEqual(JSON.parse(write.opts.body),{revision:1,notes:"research note"});
  assert.equal(get("notesStatus").textContent,"已保存");
});

test("sending an annotation hands a frozen quote and source identity to the chosen meeting",async()=>{
  const {get,memory,getDestination}=await mount();
  const actions=get("annotations").children[0].children[0];
  actions.children.find(b=>b.textContent==="入会").dispatchEvent(new Event("click"));
  await nextTurn();
  assert.equal(get("handoffDialog").open,true);
  assert.deepEqual(get("sessionSelect").children.map(option => option.value), ["", "round"]);
  get("sessionSelect").value="round";
  await get("submitHandoff").onclick();
  const draft=JSON.parse(memory.get("sci-station.paper-handoff"));
  assert.deepEqual(draft,{projectId:"project",paperId:"P1",title:"Paper",page:1,quote:"Evidence",
    fingerprint:"verified",annotationId:"ann",selectionStart:0,selectionEnd:8,sessionId:"round"});
  assert.equal(getDestination(),"http://localhost/studio?project=project&session=round");
});

test("annotation edits send the original revision and preserve the draft on conflict",async()=>{
  const {get,calls}=await mount();
  const actions=get("annotations").children[0].children[0];
  actions.children.find(b=>b.textContent==="编辑").dispatchEvent(new Event("click"));
  await nextTurn();
  get("comment").value="my draft";
  await get("saveSelection").onclick();
  assert.ok(calls.some(c=>c.opts.method==="PUT" && c.url.endsWith("/annotations/ann?revision=1")));
  assert.equal(get("comment").value,"my draft");
  assert.equal(get("reloadAnnotations").hidden,false);
});


test("an evidence link restores the second occurrence without changing saved reading position", async () => {
  const {get,calls,browser,getRoute} = await mount("&page=2&fingerprint=verified&quote=Evidence&start=9&end=17", {
    paper:{reading_position:{sourceHash:"verified",page:1,zoom:1.2,scroll:.4}}
  });
  const verification = calls.find(call => call.url.endsWith("/verify-evidence"));
  assert.deepEqual(JSON.parse(verification.opts.body), {
    page:2,quote:"Evidence",sourceHash:"verified",annotationId:null,
    selectionStart:9,selectionEnd:17,ocr:false
  });
  assert.equal(get("pageNo").value, 2);
  assert.equal(get("viewport").scrollTop, .75 * 650 - 100);
  assert.match(getRoute(), /start=9&end=17/);
  get("viewport").dispatchEvent(new Event("scroll"));
  browser.dispatchEvent(new Event("pagehide"));
  assert.equal(calls.some(call => call.url.endsWith("/reading-position")), false);
  await get("prev").onclick();
  browser.dispatchEvent(new Event("pagehide"));
  await nextTurn();
  assert.match(getRoute(), /page=1$/);
  assert.equal(JSON.parse(calls.find(call => call.url.endsWith("/reading-position")).opts.body).page, 1);
});

test("the local server's saved position wins across a new browser origin", async () => {
  const {get,calls,browser,paper} = await mount("", {
    paper:{reading_position:{sourceHash:"verified",page:2,zoom:1.4,scroll:.5}}
  });
  assert.equal(get("pageNo").value, 2);
  assert.equal(get("fit").textContent, "140%");
  assert.equal(get("viewport").scrollTop, 300);
  get("viewport").scrollTop = 450;
  get("viewport").dispatchEvent(new Event("scroll"));
  browser.dispatchEvent(new Event("pagehide"));
  await nextTurn();
  assert.equal(calls.filter(call => call.url.endsWith("/reading-position")).length, 1);
  assert.deepEqual(paper.reading_position, {sourceHash:"verified",page:2,zoom:1.4,scroll:.75});
});

test("saving a paper note refreshes the annotation revision and leaves its draft intact", async () => {
  const {get,calls} = await mount();
  get("annotations").children[0].children[0].children
    .find(button => button.textContent === "编辑").dispatchEvent(new Event("click"));
  await nextTurn();
  get("comment").value = "annotation draft";
  get("notes").value="note draft";
  get("notes").oninput();
  await get("saveNotes").onclick();
  assert.equal(get("comment").value, "annotation draft");
  await get("saveSelection").onclick();
  const write = calls.find(call => call.opts.method === "PUT" && call.url.includes("/annotations/"));
  assert.match(write.url, /revision=2$/);
  assert.equal(JSON.parse(write.opts.body).note, "annotation draft");
  await get("reloadAnnotations").onclick();
  assert.equal(get("comment").value, "annotation draft");
});

test("a source verification failure never submits the handoff", async () => {
  const {get,memory,getDestination} = await mount("", {invalidQuote:true});
  get("annotations").children[0].children[0].children
    .find(button => button.textContent === "入会").dispatchEvent(new Event("click"));
  await nextTurn();
  await get("submitHandoff").onclick();
  assert.equal(getDestination(), undefined);
  assert.equal(memory.size, 0);
  assert.match(get("message").textContent, /quote mismatch/);
});


test("Inspector command focuses the reader's active sidebar tab", async () => {
  const {get,browser,railActions} = await mount();
  get("annTab").onclick();
  const inspect = () => new CustomEvent("scistation:command", {detail:"inspector",cancelable:true});
  assert.equal(browser.dispatchEvent(inspect()), false);
  assert.equal(get("annTab").focused, true);
  get("notesTab").onclick();
  assert.equal(browser.dispatchEvent(inspect()), false);
  assert.equal(get("notesTab").focused, true);
  assert.deepEqual(railActions.at(-1), ["show","inspector"]);
});

test("reader details open explicitly and closing them preserves the unsaved note", async () => {
  const {get,calls,railActions} = await mount();
  assert.equal(get("reader-inspector").hidden, true);
  assert.deepEqual(railActions, []);
  get("reader-inspect").onclick();
  assert.deepEqual(railActions.at(-1), ["toggle","inspector"]);
  assert.equal(get("annTab").focused, true);
  get("notesTab").onclick();
  get("notes").value = "unsaved reader draft";
  get("notes").oninput();
  get("reader-close").onclick();
  assert.deepEqual(railActions.at(-1), ["close"]);
  assert.equal(get("reader-inspector").hidden, true);
  assert.equal(get("notes").value, "unsaved reader draft");
  assert.equal(calls.some(call => call.opts.method === "PUT"), false);
  get("reader-inspect").onclick();
  assert.equal(get("notesTab").focused, true);
  get("reader-pin").onclick();
  assert.deepEqual(railActions.at(-1), ["pin"]);
});
