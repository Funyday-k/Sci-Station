"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {appendTransfer, roundtableTransfer} = require("../web/static/studio-mode-transfer.js");

test("Roundtable transfer keeps its own project and includes completed public messages", () => {
  const first = {id:"a".repeat(32), name:"Visible source"};
  const room = {
    id:"1".repeat(32),
    topic:"Compare the estimate and the measurement",
    project_id:"fixture-project",
    rounds:[
      {number:1, turns:[
        {status:"done", model_label:"First seat", text:"Initial completed response", children:[{text:"Private work"}]},
        {status:"running", text:"Unfinalized stream"},
        {status:"done", error:"provider failed", text:"Errored text"},
      ]},
      {number:2, turns:[{status:"done", seat:"seat-2", text:"Follow-up response"}]},
    ],
    materials:[first],
  };
  const pending = {id:"b".repeat(32), name:"Pending follow-up attachment"};
  const data = roundtableTransfer({room,projectId:room.project_id,draft:"Unsent follow-up fixture",materials:[first,pending]});
  assert.equal(data.sourceSessionId, room.id);
  assert.equal(data.projectId, "fixture-project");
  assert.deepEqual(data.materials, [first,pending]);
  assert.match(data.context, /Compare the estimate/);
  assert.match(data.context, /Unsent follow-up fixture/);
  assert.match(data.context, /第 1 轮 · First seat/);
  assert.match(data.context, /第 2 轮 · seat-2/);
  assert.ok(data.context.indexOf("Initial completed response") < data.context.indexOf("Follow-up response"));
  assert.doesNotMatch(data.context, /Private work|Unfinalized stream|Errored text/);
  assert.equal(room.rounds[0].turns.length, 3);
});

test("an explicit text-only switch carries no attachments and preserves the original thread and draft", () => {
  const room = {materials:Array.from({length:12}, (_,i) => ({id:"m"+i,name:"Attachment "+i}))};
  const pending = [{id:"pending",name:"Unsent"}];
  const input = {room,projectId:"",draft:"Pending",materials:pending};
  assert.throws(() => roundtableTransfer(input), /12 份附件/);
  const transfer = roundtableTransfer({...input,textOnly:true});
  assert.deepEqual(transfer.materials, []);
  assert.match(transfer.context, /Pending/);
  assert.equal(room.materials.length, 12);
  assert.equal(pending.length, 1);
});

test("an unscoped source draft is preserved as an optional, bounded excerpt", () => {
  const draft = "中😀".repeat(1000);
  const data = roundtableTransfer({room:null, projectId:"",draft,materials:[]});
  assert.equal(data.projectId, "");
  assert.equal(data.sourceSessionId, "");
  assert.ok(Array.from(data.context).length < 1801);
  assert.match(data.context, /…$/);
  assert.equal(Array.from(draft).length, 2000);
  assert.equal(roundtableTransfer({room:null, projectId:"",draft:" ",materials:[]}).context, "");
});

test("incoming single-chat context appends to the existing Roundtable draft and deduplicates attachments", () => {
  const retained = {id:"existing", name:"Keep this name", mime:"text/plain"};
  const other = {id:"incoming", name:"New material"};
  const payload = {context:"Review this response",materials:[{id:"existing",name:"Duplicate"},other]};
  const draft = appendTransfer("Original text  ", [retained], payload);
  assert.equal(draft.topic,"Original text  \n\nReview this response");
  assert.deepEqual(draft.materials,[retained,other]);
  assert.deepEqual(appendTransfer(draft.topic,draft.materials,payload),draft);
  assert.throws(() => appendTransfer("😀".repeat(12000), [retained], payload), /12,000/);
  assert.throws(() => appendTransfer("", Array.from({length:12}, (_,i)=>({id:"m"+i})), payload), /12 个附件/);
});
