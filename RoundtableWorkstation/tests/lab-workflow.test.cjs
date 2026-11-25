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
 stored=JSON.stringify({...setup,sessionId:"s1"});await assert.rejects(receive({id:"p1",path:"/tmp/p"},"s1",{id:"s1",project:"/tmp/q"},box,null));assert.notEqual(stored,null);
});
