"use strict";
const assert = require("node:assert/strict");
const {test} = require("node:test");
const {readFileSync} = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const helpers = require("../static/cli-edit-review.js");

const session = {id:"m", project_id:"p", topic:"Native edits", rounds:[{number:3}], status:"ready"};
const providers = [{id:"codex",label:"Codex CLI",available:true},{id:"cursor",label:"Cursor CLI",available:false,reason:"No per-file approval"}];
const run = {id:"run-1", projectId:"p",meetingId:"m",meetingRound:3,provider:"codex",status:"pending",threadId:"thread",turnId:"turn",
  prompt:"Edit the fixture title", paths:["notes.md"], pending:{requestId:"wire-4",itemId:"item",threadId:"thread",turnId:"turn",
    reason:"Change a heading",changes:[{path:"notes.md",kind:"update",diff:"-old\n+new <section>"}]}};
const staticFile = name => readFileSync(path.join(__dirname, "../static", name), "utf8");
const tick = () => new Promise(done => setImmediate(done));
const copy = value => JSON.parse(JSON.stringify(value));

function mount(handler) {
  const elements = new Map();
  const callbacks = {};
  const calls = [];
  class Element {
    value=""; textContent=""; children=[]; hidden=false; disabled=false; open=false;
    constructor(id) {this.id=id;}
    replaceChildren(...items){this.children=items;}
    append(...items){this.children.push(...items);}
    cloneNode(){return new Element(this.id);}
    replaceWith(e){elements.set(this.id,e);}
    reset(){}
    showModal(){this.open=true;}
    close(){this.open=false;}
  }
  for (const match of staticFile("studio.html").matchAll(/id="(cli-edit-[^"]+)"/g)) elements.set(match[1],new Element(match[1]));
  const get = id => elements.get("cli-edit-"+id);
  const document = {
    hidden:false,
    createElement:()=>new Element(),
    getElementById:id=>{assert.ok(elements.has(id),id);return elements.get(id);},
    addEventListener:(name,fn)=>{callbacks[name]=fn;}
  };
  const window = {addEventListener:(name,fn)=>{callbacks[name]=fn;}};
  const fetch = async (url,options) => {
    const payload=options.body && JSON.parse(options.body);
    calls.push({url, method:options.method, payload});
    const envelope=await handler(options.method,payload);
    return {ok:true,json:async()=>copy(envelope)};
  };
  vm.runInNewContext(staticFile("cli-edit-review.js"),{
    window,document,fetch,Option:class{constructor(text,value){this.textContent=text;this.value=value;}},
    setTimeout:()=>1,clearTimeout(){}
  });
  return {ui:window.SciCLIEdit,get,calls,callbacks};
}

test("project, round, CLI request identities and every file diff must match before acceptance", () => {
  const scope=helpers.meetingScope(session,"Project");
  assert.deepEqual(helpers.pendingDecision(run,scope),{projectId:"p",runId:"run-1",threadId:"thread",turnId:"turn",requestId:"wire-4",itemId:"item"});
  assert.ok(helpers.canAccept(run,scope));
  assert.ok(!helpers.canAccept(run,{...scope,round:4}));
  assert.ok(!helpers.canAccept(run,{...scope,closed:true}));
  assert.equal(helpers.pendingDecision({...run,projectId:"other"},scope),null);
  assert.equal(helpers.pendingDecision({...run,turnId:"new-turn"},scope),null);
  assert.ok(!helpers.canAccept({...run,pending:{...run.pending,changes:[{path:"notes.md",diff:""}]}},scope));
  assert.throws(()=>helpers.unpack({providers,run:{...run,meetingId:"different"}},scope));
});

test("starting and reviewing from the meeting requires one explicit click per request", async () => {
  let current=null;
  const {ui,get,calls}=mount((method,action)=>{
    if (method==="POST" && action.action==="start") current=copy(run);
    if (method==="POST" && action.action==="accept") current={...run,status:"responded",pending:null};
    return {providers,run:current};
  });
  ui.setSession(session,"Known project"); await tick();
  get("open").onclick();await tick();
  assert.equal(get("dialog").open,true);
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
  assert.equal(get("changes").children[0].children[1].textContent,run.pending.changes[0].diff);
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

test("closing the dialog leaves a task running and cancel sends only this run identity", async () => {
  let current=run;
  const {ui,get,calls}=mount((method,payload)=>{
    if(method==="POST") current={...run,status:"cancelled",pending:null};
    return {providers,run:current};
  });
  ui.setSession(session,"Project");await tick();get("open").onclick();await tick();
  get("close").onclick();assert.equal(calls.some(item=>item.method==="POST"),false);
  get("open").onclick();await tick();get("cancel").onclick();await tick();
  assert.deepEqual(calls.at(-1).payload,{action:"cancel",projectId:"p",runId:"run-1"});
  assert.match(get("run-title").textContent,/已取消/);
  assert.equal(get("accept").disabled,true);
  ui.setSession({...session,id:"global",project_id:""});await tick();
  assert.equal(get("start").hidden,true);
  assert.match(get("status").textContent,/关联项目/);
});
