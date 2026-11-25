const test = require("node:test");
const assert = require("node:assert/strict");
const {compose,receive,key} = require("../static/lab-handoff.js");
const setup = {projectId:"p1",sessionId:"",title:"复核",prompt:"检查近似。",mode:"review",seats:2,question:"验证边界条件。"};
test("workflows preserve source provenance and Unicode limits",()=>{
 const text=compose({...setup,resource:{server:"https://tools.example/mcp",uri:"urn:paper:one",sha256:"f".repeat(64),excerpt:"原文。"}});
 assert.match(text,/urn:paper:one/);assert.match(text,/验证边界/);assert.throws(()=>compose({...setup,prompt:"a".repeat(6600)}));
});
test("a preset only enters the selected project and stays an unsent draft",async()=>{
 let stored=JSON.stringify(setup), calls=0;
 global.sessionStorage={getItem:k=>k===key?stored:null,removeItem:()=>{stored=null;}};
 const box={value:"原有问题",dispatchEvent(){},focus(){}};
 await receive({id:"wrong",path:"/tmp/q"},"",null,box,()=>{throw Error("wrong project")});assert.equal(box.value,"原有问题");
 await receive({id:"p1",path:"/tmp/p"},"",null,box,async(mode,seats)=>{assert.equal(mode,"review");assert.equal(seats,2);calls++});
 assert.equal(calls,1);assert.match(box.value,/原有问题/);assert.match(box.value,/检查近似/);assert.equal(stored,null);
 stored=JSON.stringify({...setup,sessionId:"s1"});
 await assert.rejects(receive({id:"p1",path:"/tmp/p"},"s1",{id:"s1",project_id:"other",project:"/tmp/p"},box,null));
 assert.notEqual(stored,null);
 await receive({id:"p1",path:"/tmp/p"},"s1",{id:"s1",project_id:"p1",project:"/tmp/previous"},box,null);
 assert.equal(stored,null);
});
test("project text selections retain the PDF page, digest and Unicode location",()=>{
 const {selectedCitation,ownsRun}=require("../static/lab-run.js");
 const input={kind:"paper",id:"paper-original",text:"😀  选段 α. ",page:4,offset:8,hash:"e".repeat(64)};
 const c=selectedCitation(input,2,10);
 assert.deepEqual(c,{kind:"paper",id:input.id,page:4,hash:input.hash,quote:"选段 α.",offset:11});
 assert.throws(()=>selectedCitation(input,2,4));
 assert.ok(ownsRun({project_id:"p1",seats:["seat-1"]},{id:"p1"}));
 assert.ok(!ownsRun({project_id:"p2",seats:["seat-1"]},{id:"p1"}));
});
test("a reviewed multi-seat draft attaches each selected source once",async()=>{
 const m={id:"m1",name:"Evidence page 2",excerpt:"Recorded evidence"};
 const data={...setup,materials:[m]};
 let stored=JSON.stringify(data);
 global.sessionStorage={getItem:()=>stored,removeItem:()=>{stored=null;}};
 const box={value:"",dispatchEvent(){},focus(){}};
 let attachmentRows=[m];
 const controller={busy:()=>false,failed:()=>false,ready:()=>attachmentRows,set:rows=>{attachmentRows=rows;}};
 await receive({id:"p1"},"",null,box,null,controller);
 assert.deepEqual(attachmentRows,[m]);assert.equal(stored,null);
});
test("global runs use an explicit scope and never match a legacy directory session",()=>{
 const {ownsRun}=require("../static/lab-run.js");
 assert.doesNotThrow(()=>compose({...setup,projectId:"",scope:"global"}));
 assert.throws(()=>compose({...setup,projectId:""}));
 assert.ok(ownsRun({project:"",seats:["seat-1"]},{id:"",global:true}));
 assert.ok(!ownsRun({project:"/fixture/legacy",seats:["seat-1"]},{id:"",global:true}));
});

test("a project graph preview keeps its source and cannot enter a different project",()=>{
 const resource={kind:"project-graph",projectId:"p1",server:"本地项目图谱",uri:"/api/research/projects/p1/graph/workflow?operation=reading",sha256:"f".repeat(64),excerpt:"1. Foundation"};
 const text=compose({...setup,resource});
 assert.match(text,/项目图谱资料/);assert.match(text,/1\. Foundation/);
 assert.throws(()=>compose({...setup,projectId:"p2",resource}),/图谱资料不属于当前项目/);
});
