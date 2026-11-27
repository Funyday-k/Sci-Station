"use strict";
const assert = require("node:assert/strict");
const {test} = require("node:test");
const {readFileSync} = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const helpers = require("../web/static/cli-edit-review.js");

const session = {id:"m", project_id:"p", topic:"Native edits", rounds:[{number:1},{number:2},{number:3}], status:"ready"};
const providers = [{id:"codex",label:"Codex CLI",available:true},{id:"cursor",label:"Cursor CLI",available:false,reason:"No per-file approval"}];
const run = {id:"run-1", projectId:"p",meetingId:"m",meetingRound:3,provider:"codex",status:"pending",threadId:"thread",turnId:"turn",
  prompt:"Edit the fixture title", paths:["notes.md"], pending:{requestId:"wire-4",itemId:"item",threadId:"thread",turnId:"turn",
    reason:"Change a heading",changes:[{path:"notes.md",kind:"update",diff:"-old\n+new <section>"}]}};
const staticFile = name => readFileSync(path.join(__dirname, "../web/static", name), "utf8");
const tick = () => new Promise(done => setImmediate(done));
const copy = value => JSON.parse(JSON.stringify(value));

function mount(handler, proof="fixture-proof") {
  const elements = new Map();
  const callbacks = {};
  const calls = [];
  let focused = null;
  class Element {
    value=""; _text=""; children=[]; hidden=false; disabled=false; open=false; className=""; attributes={}; listeners={};
    constructor(id, tag="") {this.id=id; this.tagName=tag;}
    get textContent(){
      if (this.children.length) return this.children.map(c => c.textContent).join("");
      return this._text;
    }
    set textContent(v){ this._text = String(v); this.children = []; }
    set innerHTML(_v){ throw new Error("CLI edit diff must never write innerHTML"); }
    setAttribute(name, value){ this.attributes[name] = String(value); }
    addEventListener(name, fn){ (this.listeners[name] ||= []).push(fn); }
    dispatchEvent(name){ for (const fn of this.listeners[name] || []) fn(); }
    focus(){ focused = this; }
    replaceChildren(...items){this.children=items; this._text="";}
    append(...items){this.children.push(...items);}
    cloneNode(){const copyEl = new Element(this.id, this.tagName); copyEl.className = this.className; return copyEl;}
    replaceWith(e){elements.set(this.id,e);}
    reset(){}
    showModal(){this.open=true;}
    close(){const wasOpen = this.open; this.open=false; if (wasOpen) this.dispatchEvent("close");}
  }
  const studioMarkup = staticFile("partials/studio-room.html") + "\n" + staticFile("partials/studio-dialogs.html");
  for (const match of studioMarkup.matchAll(/id="(cli-edit-[^"]+)"/g)) elements.set(match[1],new Element(match[1]));
  const get = id => elements.get("cli-edit-"+id);
  const document = {
    hidden:false,
    createElement:tag=>new Element("", tag),
    getElementById:id=>{assert.ok(elements.has(id),id);return elements.get(id);},
    addEventListener:(name,fn)=>{callbacks[name]=fn;}
  };
  const window = {sciStationCLIEditSession:proof,addEventListener:(name,fn)=>{callbacks[name]=fn;}};
  const fetch = async (url,options) => {
    assert.equal(options.headers["X-Sci-Station-CLI-Session"],window.sciStationCLIEditSession);
    const payload=options.body && JSON.parse(options.body);
    calls.push({url, method:options.method, payload});
    const envelope=await handler(options.method,payload);
    return {ok:true,json:async()=>copy(envelope)};
  };
  vm.runInNewContext(staticFile("cli-edit-review.js"),{
    window,document,fetch,Option:class{constructor(text,value){this.textContent=text;this.value=value;}},
    setTimeout:()=>1,clearTimeout(){}
  });
  return {ui:window.SciCLIEdit,get,calls,callbacks,window,getFocused:()=>focused};
}

test("project, round, CLI request identities and every file diff must match before acceptance", () => {
  const scope=helpers.meetingScope(session,"Project");
  assert.deepEqual(helpers.pendingDecision(run,scope),{projectId:"p",runId:"run-1",threadId:"thread",turnId:"turn",requestId:"wire-4",itemId:"item"});
  assert.ok(helpers.canAccept(run,scope));
  assert.ok(!helpers.canAccept(run,{...scope,round:4}));
  assert.ok(!helpers.canAccept(run,{...scope,closed:true}));
  assert.ok(!helpers.canAccept(run,{...scope,discussing:true}));
  assert.equal(helpers.pendingDecision({...run,projectId:"other"},scope),null);
  assert.equal(helpers.pendingDecision({...run,turnId:"new-turn"},scope),null);
  assert.ok(!helpers.canAccept({...run,pending:{...run.pending,changes:[{path:"notes.md",diff:""}]}},scope));
  assert.throws(()=>helpers.unpack({providers,run:{...run,meetingId:"different"}},scope));
});

test("starting and reviewing from the meeting requires one explicit click per request", async () => {
  let current=null;
  const {ui,get,calls,getFocused}=mount((method,action)=>{
    if (method==="POST" && action.action==="start") current=copy(run);
    if (method==="POST" && action.action==="accept") current={...run,status:"responded",pending:null};
    return {providers,run:current};
  });
  ui.setSession(session,"Known project"); await tick();
  get("open").onclick();await tick();
  assert.equal(get("dialog").open,true);
  assert.equal(getFocused().id,"cli-edit-close");
  assert.match(get("scope").textContent,/Known project \(p\)/);
  assert.match(get("capabilities").children[0].textContent,/No per-file approval/);
  get("paths").value="notes.md"; get("prompt").value="Edit the fixture title";
  get("start").onsubmit({preventDefault(){}});
  get("start").onsubmit({preventDefault(){}});
  await tick();
  const requests=calls.filter(c=>c.method==="POST");
  assert.equal(requests.length,1);
  assert.deepEqual(requests[0],{url:"/api/studio/sessions/m/cli-edits",method:"POST",payload:{
    action:"start",projectId:"p",meetingRound:3,provider:"codex",prompt:"Edit the fixture title",paths:["notes.md"]}});
  const diffPre = get("changes").children[0].children[1];
  assert.equal(diffPre.className, "diff-view");
  assert.equal(diffPre.children.length, 2);
  assert.equal(diffPre.children[0].className, "diff-line diff-remove");
  assert.equal(diffPre.children[0].children[0].textContent, "−");
  assert.deepEqual(diffPre.children[0].children[0].attributes, {role: "img", "aria-label": "删除行"});
  assert.equal(diffPre.children[0].children[1].textContent, "old");
  assert.equal(diffPre.children[1].className, "diff-line diff-add");
  assert.equal(diffPre.children[1].children[0].textContent, "+");
  assert.deepEqual(diffPre.children[1].children[0].attributes, {role: "img", "aria-label": "新增行"});
  assert.equal(diffPre.children[1].children[1].textContent, "new <section>");
  assert.equal(get("decision-actions").hidden, false);
  const obsolete=get("accept");
  current={...run,pending:{...run.pending,requestId:"next",changes:[{path:"notes.md",kind:"update",diff:"+correct"}]}};
  get("refresh").onclick();await tick();
  obsolete.onclick();
  assert.equal(calls.filter(c=>c.method==="POST").length,1);
  get("accept").onclick();get("accept").onclick();await tick();
  assert.equal(calls.filter(c=>c.method==="POST").length,2);
  assert.equal(calls.at(-1).payload.requestId,"next");
  assert.match(get("run-title").textContent,/等待执行结果/);
  assert.equal(get("proposal").hidden,true);
  assert.equal(get("decision-actions").hidden,true);
});

test("diff parser distinguishes headers, additions, removals and context with +/- gutters", () => {
  const parsed = helpers.parseDiffLines("@@ -1,2 +1,2 @@\n keep\n-before\n+after <script>alert(1)</script>");
  assert.deepEqual(parsed, [
    {kind: "header", gutter: "", text: "@@ -1,2 +1,2 @@"},
    {kind: "context", gutter: " ", text: "keep"},
    {kind: "remove", gutter: "−", text: "before"},
    {kind: "add", gutter: "+", text: "after <script>alert(1)</script>"},
  ]);
});

test("hunk content resembling file headers keeps its change markers", () => {
  const source = "--- a/one\n+++ b/one\n@@ -1,2 +1,2 @@ section\n keep\n--- before\n+++ after\n" +
    "\\ No newline at end of file\n--- a/two\n+++ b/two\n@@ -0,0 +1 @@\n+++ another";
  const lines = helpers.parseDiffLines(source);
  assert.deepEqual(lines.map(line => line.kind), [
    "header", "header", "header", "context", "remove", "add", "header", "header", "header", "header", "add"
  ]);
  assert.equal(lines[4].text, "-- before");
  assert.equal(lines[5].text, "++ after");
});

test("large and multi-file proposals keep the complete diff with bounded highlighted rows", async () => {
  const block = Array.from({length: 200}, (_, n) => "+short line " + n).join("\n");
  const large = "+head\r\n" + "-line\r\n+line\r\n".repeat(5000) + "+<tail>";
  const proposal = copy(run);
  proposal.pending.changes = [block, block, large].map((diff, i) => ({path: i + ".md", kind: "update", diff}));
  const {ui, get} = mount(() => ({providers, run: proposal}));
  ui.setSession(session, "Project");
  await tick();
  const [first, second, third] = get("changes").children.map(section => section.children[1]);
  assert.equal(first.children.length, 200);
  for (const [plain, expected] of [[second, block], [third, large]]) {
    assert.equal(plain.children.length, 0);
    assert.equal(plain.textContent, expected);
    assert.match(plain.attributes["aria-description"], /加号.*减号/);
    assert.equal(plain.tabIndex, 0);
  }
  assert.equal(get("accept").disabled, false);
});

test("unified dialog footer places tertiary actions leading and primary Approve trailing", () => {
  const html = staticFile("partials/studio-dialogs.html");
  const dialogHtml = html.slice(html.indexOf('<dialog id="cli-edit-dialog"'));
  const footer = dialogHtml.slice(dialogHtml.indexOf('<footer class="dialog-footer">'));
  const idxRefresh = footer.indexOf('id="cli-edit-refresh"');
  const idxCancel = footer.indexOf('id="cli-edit-cancel"');
  const idxDecline = footer.indexOf('id="cli-edit-decline"');
  const idxAccept = footer.indexOf('id="cli-edit-accept"');
  assert.ok(idxRefresh > 0 && idxCancel > idxRefresh && idxDecline > idxCancel && idxAccept > idxDecline);
  assert.equal(dialogHtml.indexOf('id="cli-edit-accept"'), dialogHtml.lastIndexOf('id="cli-edit-accept"'));
});

test("disconnect, session switch and restart cannot replay an approval or redirect it to the new meeting", async () => {
  let finish,phase="pending";
  const host=async(method,payload)=>{
    if(method==="POST" && payload.action==="decline"){phase="lost";throw Error("offline");}
    if(phase==="lost")throw Error("offline");
    if(phase==="delayed")return new Promise(resolve=>{finish=resolve;});
    return {providers,run:phase==="pending"?run:null};
  };
  const {ui,get,calls}=mount(host);
  ui.setSession(session,"A");await tick();
  get("decline").onclick();await tick();
  assert.equal(get("accept").disabled,true);
  assert.equal(get("decline").disabled,true);
  assert.match(get("status").textContent,/未能确认/);
  get("refresh").onclick();await tick();
  assert.equal(calls.filter(c=>c.method==="POST").length,1);
  phase="delayed";get("refresh").onclick();await tick();
  phase="expired";ui.setSession({...session,id:"m2",project_id:"p2"},"B");await tick();
  finish({providers,run});await tick();
  assert.equal(get("run").hidden,true);
  assert.equal(get("accept").disabled,true);
  assert.match(get("scope").textContent,/B \(p2\)/);
  const fresh=mount(host);
  fresh.ui.setSession(session,"A");await tick();
  assert.deepEqual(fresh.calls.map(item=>item.method),["GET"]);
  assert.match(fresh.get("status").textContent,/没有待审核/);
});

test("closing the dialog leaves a task running, restores focus, and cancel sends only this run identity", async () => {
  let current=run;
  const {ui,get,calls,getFocused}=mount((method,payload)=>{
    if(method==="POST") current={...run,status:"cancelled",pending:null};
    return {providers,run:current};
  });
  ui.setSession(session,"Project");await tick();get("open").onclick();await tick();
  get("close").onclick();
  assert.equal(calls.some(item=>item.method==="POST"),false);
  assert.equal(getFocused().id,"cli-edit-open");
  get("open").onclick();await tick();get("cancel").onclick();await tick();
  assert.deepEqual(calls.at(-1).payload,{action:"cancel",projectId:"p",runId:"run-1"});
  assert.match(get("run-title").textContent,/已取消/);
  assert.equal(get("accept").disabled,true);
  ui.setSession({...session,id:"global",project_id:""});await tick();
  assert.equal(get("start").hidden,true);
  assert.match(get("status").textContent,/关联项目/);
});

test("browser sessions can read the meeting but require a native window to review CLI files", async () => {
  const {ui,get,calls,callbacks,window}=mount(()=>({providers,run}),"");
  ui.setSession(session,"Project");get("open").onclick();await tick();
  assert.equal(calls.length,0);
  assert.equal(get("start").hidden,true);
  assert.match(get("status").textContent,/桌面窗口/);
  window.sciStationCLIEditSession="fixture-proof";
  callbacks["scistation:cli-edit-session"]();await tick();
  assert.deepEqual(calls.map(c=>c.method),["GET"]);
  assert.equal(get("accept").disabled,false);
  window.sciStationCLIEditSession="";
  callbacks["scistation:cli-edit-session"]();await tick();
  assert.equal(get("proposal").hidden,true);
  assert.equal(get("decision-actions").hidden,true);
  assert.equal(get("accept").disabled,true);
});
