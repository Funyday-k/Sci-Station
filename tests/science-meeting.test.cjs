const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const {reference, encodeReference, decodeReference, paperHref, outputs, sources} = require('../static/science-meeting.js');

const ref = {projectId:'project_1', paperId:'p123', title:'半径与 Δt', page:3, quote:'原文第一行\n\n第二行',
  fingerprint:'a'.repeat(64),annotationId:'annotation-1'};
test('the selected page, multiline quote and document version round-trip unchanged', () => {
  const encoded = encodeReference(ref);
  assert.deepEqual(decodeReference(encoded),ref);
  assert.equal(decodeReference('unrelated document'),null);
  assert.equal(reference({...ref,quote:'地'.repeat(2801)}),null);
  assert.equal(reference({...ref,paperId:'../private'}),null);
  assert.equal(reference({...ref,page:0}),null);
  assert.equal(new URL(paperHref(ref),'http://localhost').searchParams.get('fingerprint'),ref.fingerprint);
  const s={materials:[{excerpt:encoded},{excerpt:encoded},{excerpt:encodeReference({...ref,projectId:'other'})}]};
  assert.deepEqual(sources(s,'project_1'),[ref]);
  s.materials.push({excerpt:encodeReference({...ref,page:5}), added_round:3});
  assert.deepEqual(sources(s,'project_1',2),[ref]);
});
test('only finished public statements and the approved final report can be written as notes',() => {
  const session={report:{status:'drafting',markdown:'unreviewed'},rounds:[{number:1,turns:[
    {seat:'s1',status:'done',text:'final',model:'m',children:[{text:'private'}]},
    {seat:'s2',status:'running',text:'partial'},{seat:'s3',status:'done',text:'broken',error:'timeout'}]}]};
  assert.deepEqual(outputs(session).map(x=>x.text),['final']);
  session.report.status='ready';
  assert.deepEqual(outputs(session).map(x=>x.key),['report','round-1-s1']);
});
test('reader handoff queues only the selected excerpt, enforces project and source revision, and leaves sending to the host',async()=>{
  const src=fs.readFileSync(path.join(__dirname,'../static/science-meeting.js'),'utf8');
  const storage = new Map(), operations=[];
  const project={id:ref.projectId,path:'/research/one',name:'One'};
  let paper={id:ref.paperId,title:ref.title,project_ids:[project.id],file_sha256:ref.fingerprint};
  const document={getElementById(){return null;}};
  const fetch=async(url,opt)=>{
    operations.push([url,opt.method]);
    if(url==='/api/research/projects') return {ok:true,json:async()=>[project]};
    if(url==='/api/research/papers/'+ref.paperId) return {ok:true,json:async()=>paper};
    if(url==='/api/studio/materials'){
      const attachment=opt.body.get('file'), content=await attachment.text();
      assert.deepEqual(decodeReference(content),ref);
      return {ok:true,json:async()=>({id:'m-1',name:attachment.name,excerpt:content})};
    }
    throw new Error('unexpected network request '+url);
  };
  const context=vm.createContext({window:{},URL,URLSearchParams,FormData,Blob,Event,location:new URL('http://localhost/studio?project=project_1'),
    document,history:{replaceState(){}},fetch,sessionStorage:{getItem:k=>storage.get(k),removeItem:k=>storage.delete(k)}});
  vm.runInContext(src,context);
  const bridge=context.window.ScienceMeeting; await bridge.loadProjects();
  assert.equal(bridge.requestedProject(project.id).id,project.id);
  let materials=[];
  const control={busy:()=>false,failed:()=>false,items:()=>materials,ready:()=>materials,set(items){materials=items;}};
  const box={value:'',dispatchEvent(){}}, key='sci-station.paper-handoff';
  storage.set(key,JSON.stringify(ref)); await bridge.receive(project,'',control,()=>project.id,box);
  assert.equal(materials.length,1);assert.equal(box.value.includes(ref.title),true);assert.equal(storage.has(key),false);
  assert.ok(operations.every(([url])=>!url.includes('/sessions')));
  storage.set(key,JSON.stringify(ref));paper={...paper,file_sha256:'b'.repeat(64)};
  await assert.rejects(bridge.receive(project,'',control,()=>project.id,box),/重新|核对/);
  paper={...paper,project_ids:[]};
  await assert.rejects(bridge.receive(project,'',control,()=>project.id,box),/加入/);
  assert.equal(materials.length,1);
  storage.set(key,JSON.stringify({...ref,sessionId:'existing'}));
  bridge.update({id:'existing',project_id:'other-project',project:project.path});
  await assert.rejects(bridge.receive(project,'existing',control,()=>project.id,box),/另一项目/);
});
test('reviewing is read-only until confirmation; notes honor revision and meeting tasks are deduplicated',async()=>{
  class Node {
    constructor(tag,text='') {this.tag=tag;this.textContent=text;this.value='';this.children=[];this.handlers={};this.selectedIndex=0;}
    append(...children){this.children.push(...children);if(this.tag==='select' && this.children.length===children.length)this.value=children[0]?.value||'';}
    replaceChildren(...children){this.children=[];this.append(...children);}
    insertBefore(child){this.children.unshift(child);}
    addEventListener(type,fn){(this.handlers[type]||=[]).push(fn);}
    async fire(type){for(const fn of this.handlers[type]||[])await fn({preventDefault(){}});await new Promise(setImmediate);}
    setAttribute(){} showModal(){this.open=true;} close(){this.open=false;this.fire('close');}
    all(tag){return [...(this.tag===tag?[this]:[]),...this.children.flatMap(c=>c.all(tag))];}
  }
  class Option extends Node {constructor(label,value){super('option',label);this.value=value;}}
  const body=new Node('body'),toolbar=new Node('div'),map=new Map(),writes=[];
  const project={id:ref.projectId,name:'Study',path:'/tmp/one',revision:7},session={id:'s018',title:'研究会',project_id:project.id,project:project.path,agenda:[{id:'a1',title:'检查公式'}],materials:[],
    rounds:[{number:3,turns:[{seat:'a',model:'A',status:'done',text:'结论'}]}]};
  const existing={id:'note01',title:'已有笔记',body:'以前的内容',revision:4,evidence:[]};
  const reviews=new Map();
  const fetch=async(url,opt)=>{
    let out;
    if(opt.method==='GET') {
      if(url==='/api/research/projects')out=[project];
      else if(url.endsWith('/notes/note01'))out=existing;
      else if(url.endsWith('/notes'))out=[existing];
      else if(url.endsWith('/reviews?meeting=s018'))out=[...reviews.values()];
    } else if(url==='/api/studio/sessions/s018/research-reviews'){
      const payload=JSON.parse(opt.body); writes.push(payload);
      if(payload.decision==='propose') {
        out={...payload.proposal,projectId:payload.projectId,id:payload.operationId,status:'pending',revision:1,sourceText:'Recorded statement',evidence:[]};
      } else {
        assert.equal(payload.revision,1);
        out={...reviews.get(payload.operationId),status:payload.decision==='accept'?'accepted':'rejected',revision:2};
      }
      reviews.set(out.id,out);
    }
    if(!out)throw new Error('unhandled '+url);
    return {ok:true,json:async()=>out};
  };
  const localStorage={setItem:(k,v)=>map.set(k,v),getItem:k=>map.get(k),removeItem:k=>map.delete(k)};
  const ctx=vm.createContext({window:{},URL,URLSearchParams,FormData,Blob,Event,Option,fetch,localStorage,crypto:require('node:crypto'),
    location:new URL('http://localhost/studio?project='+project.id),history:{replaceState(){}},
    document:{body,createElement:t=>new Node(t),getElementById:id=>id==='chat-toolbar'?toolbar:null}});
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../static/science-meeting.js'),'utf8'),ctx);
  const bridge=ctx.window.ScienceMeeting;await bridge.loadProjects();bridge.update(session);
  const open=()=>toolbar.children[0].fire('click');
  await open();const dialog=body.children[0], [out,target]=dialog.all('select'), findButton=text=>dialog.all('button').find(b=>b.textContent===text);
  assert.equal(writes.length,0);await findButton('取消').fire('click');assert.equal(writes.length,0);
  await open();target.value='note01';await target.fire('change');
  await findButton('提交审核').fire('click');
  assert.equal(writes.length,1);assert.equal(writes[0].decision,'propose');
  assert.deepEqual(writes[0].proposal,{action:'append-note',projectRevision:7,destinationRevision:4,destinationId:'note01',
    turnId:'round-3-a',title:'已有笔记',body:'结论'});
  const pending=writes[0].operationId;
  dialog.close();map.clear();await open();await findButton('拒绝写入').fire('click');
  assert.equal(writes[1].operationId,pending);assert.equal(writes[1].decision,'reject');
  out.value='agenda-a1';await out.fire('change');target.value='@task';await target.fire('change');
  await findButton('提交审核').fire('click');await findButton('确认写入').fire('click');
  assert.equal(writes[2].proposal.action,'create-task');assert.equal(writes[2].proposal.title,'检查公式');
  assert.notEqual(writes[2].operationId,pending);assert.equal(writes[3].operationId,writes[2].operationId);
  assert.equal(writes[3].decision,'accept');assert.equal(writes[3].proposal,undefined);
});
