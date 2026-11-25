const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {join} = require("node:path");
const {test} = require("node:test");
const vm = require("node:vm");

const html = readFileSync(join(__dirname, "../static/reader.html"), "utf8");
const script = readFileSync(join(__dirname, "../static/reader.js"), "utf8");
const nextTurn = () => new Promise(resolve => setImmediate(resolve));

class Element extends EventTarget {
  constructor() {
    super();
    this.children = [];
    this.style = {};
    this.dataset = {};
    this.classList = {toggle() {}};
    this.clientWidth = 500;
    this.clientHeight = 650;
  }
  append(...xs) { this.children.push(...xs); }
  replaceChildren(...xs) { this.children = xs; }
  setAttribute(key, value) { this[key] = value; }
  removeAttribute(key) { delete this[key]; }
  getContext() { return {measureText: word => ({width: word.length * 8})}; }
  showModal() { this.open = true; }
  focus() {}
}

async function mount(suffix = "") {
  const ids = new Map(Array.from(html.matchAll(/\bid="([^"]+)"/g), m => [m[1],new Element()]));
  const get = id => { assert.ok(ids.has(id), "missing HTML element " + id); return ids.get(id); };
  const paper = {id: "P1", title:"Paper", authors:["Author"], notes:"old", revision:1,
    file_sha256:"verified", project_ids:["project"], has_pdf:true};
  const mark = {id:"ann",page:1,kind:"highlight",selected_text:"Evidence",rects:[]};
  const calls = [], memory = new Map();
  let destination;
  const env = {
    document:{getElementById:get,createElement:()=>new Element(),createDocumentFragment:()=>new Element(),
      createTextNode:text=>text},
    getComputedStyle:()=>({paddingLeft:"8px"}),
    Image:class {async decode() {}},
    Option:class {constructor(text,value){this.text=text;this.value=value;}},
    sessionStorage:{setItem:(k,v)=>memory.set(k,v)},
    localStorage:{getItem:()=>null,setItem(){}},
    history:{replaceState(){}},
    location:{search:"?paper=P1&project=project"+suffix,href:"http://localhost/reader?paper=P1&project=project"+suffix,
      origin:"http://localhost",assign:url=>{destination=String(url);}},
    window:new EventTarget(), URL, URLSearchParams, setTimeout,
    fetch:async(url, opts)=>{
      calls.push({url,opts});
      let data;
      if(url === "/api/research/papers/P1") {
        if(opts.method==="PUT")Object.assign(paper, {notes: JSON.parse(opts.body).notes,revision:2});
        data={...paper, annotations:[mark]};
      }else if(url.includes("/annotations/ann?revision=")){
        return {ok:false,status:409,text:async()=>JSON.stringify({error:"conflict"})};
      }else if(url.endsWith("/annotations"))data=[mark];
      else if(url.endsWith("/pages"))data={pages:2};
      else if(url.endsWith("/pages/1") || url.endsWith("/pages/2"))data={width:250,height:350,text:"text",words:[]};
      else if(url==="/api/research/projects")data=[{id:"project",name:"Project",path:"/project"}];
      else if(url==="/api/studio/sessions")data={sessions:[{id:"round",title:"Round",project:"/project"}]};
      else throw Error("unexpected fetch "+url);
      return {ok:true,status:200,json:async()=>data};
    }
  };
  vm.runInNewContext(script,env);
  await nextTurn();
  return {get,calls,memory,paper,getDestination:()=>destination};
}

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
  get("sessionSelect").value="round";
  get("submitHandoff").onclick();
  const draft=JSON.parse(memory.get("sci-station.paper-handoff"));
  assert.deepEqual(draft,{projectId:"project",paperId:"P1",title:"Paper",page:1,quote:"Evidence",
    fingerprint:"verified",annotationId:"ann",sessionId:"round"});
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
