(() => {
  "use strict";
  const $=id=>document.getElementById(id);
  const handoff=window.ScienceLabHandoff;
  const api="/api/research/lab/";
  let presets=[], projects=[], sessions=[], current=null, original=null, preview=null, source=null;
  function tell(text){$("status").textContent=text;}
  async function req(path,method="GET",data) {
    const opt={method,cache:"no-store",headers:{"X-Roundtable":"1"}};
    if(data!==undefined){opt.headers["Content-Type"]="application/json";opt.body=JSON.stringify(data);}
    const res=await fetch(path,opt);
    if(res.status===204)return;
    const x=await res.json().catch(()=>null);
    if(!res.ok)throw Error(x?.error?.message || x?.error || "操作失败（"+res.status+"）");
    return x;
  }
  const runs = window.SciLabRun.mount({req, tell, form:() => ({...form(), workflow:current?.id || "", question:$("question").value.trim(), resource:source})});
  function form(){
    return {title:$("title").value.trim(),mode:$("mode").value,seats:Number($("seats").value),prompt:$("prompt").value.trim()};
  }
  function snapshot(p){return JSON.stringify([p.title,p.mode,p.seats,p.prompt]);}
  function dirtyTemplate(){return original!==null && snapshot(form())!==original;}
  function canLeave(){return !dirtyTemplate()||confirm("放弃尚未保存的模板更改？");}
  let handingOff = false;
  window.addEventListener("beforeunload", event => {
    if (!handingOff && (dirtyTemplate() || $("question").value.trim() || source || runs.hasDraft())) {
      event.preventDefault();
      event.returnValue = "";
    }
  });
  window.addEventListener("pageshow", () => { handingOff = false; });
  function select(p) {
    current=p;const x=p||{title:"",mode:"review",seats:1,prompt:""};original=snapshot(x);
    $("title").value=x.title;$("mode").value=x.mode;$("seats").value=String(x.seats);$("prompt").value=x.prompt;
    $("editor-title").textContent=p?.title||"新建个人模板";$("kind").textContent=p?.builtin?"内置模板":"个人模板";
    $("save").textContent=p&&!p.builtin?"保存更改":"保存为个人模板";
    $("fork").hidden=!p||p.builtin;$("delete").hidden=!p||p.builtin;
    for(const b of $("presets").children){b.classList.toggle("active",b.dataset.id===p?.id);b.setAttribute("aria-current",b.dataset.id===p?.id?"true":"false");}
  }
  function renderPresets(){
    const nav=$("presets");nav.replaceChildren();
    for(const p of presets){const b=document.createElement("button");b.type="button";b.textContent=p.title;b.dataset.id=p.id;b.onclick=()=>{if(canLeave())select(p);};nav.append(b);}
  }
  async function refresh(selected){
    presets=await req(api+"presets");renderPresets();select(presets.find(p=>p.id===selected)||presets[0]||null);
  }
  async function save(fork){
    const x=form();if(!x.title||!x.prompt)throw Error("请填写模板名称和工作指引。");
    const edit=current&&!current.builtin&&!fork;
    if(edit)x.revision=current.revision;
    const result=await req(api+"presets"+(edit?"/"+encodeURIComponent(current.id):""),edit?"PUT":"POST",x);
    await refresh(result.id);tell("个人模板已保存。");
  }
  let previousScope=null;
  function projectSelection(commit = false){
    const id=$("project").value,p=projects.find(v=>v.id===id);
    if(previousScope!==null && previousScope!==id) {markSource(null);resetResource();}
    previousScope=id;
    $("session").replaceChildren(new Option("新建圆桌",""));
    if(p)for(const s of sessions){if(s.project_id===p.id&&s.status!=="closed")$("session").append(new Option(s.title||s.topic||"已有圆桌",s.id));}
    const url=new URL(location.href);
    if(p)url.searchParams.set("project",id);else url.searchParams.delete("project");
    if(id==="@global")url.searchParams.set("scope","global");else url.searchParams.delete("scope");
    if (commit) window.SciStationNav.commitURL(url,"push");
    $("handoff").disabled=!p;
    runs.selectProject(id==="@global"?{id:"",global:true}:p, sessions).catch(e => tell(e.message));
    hint();
  }
  window.addEventListener("popstate",()=>{
    const project=new URL(location.href).searchParams.get("project") || "";
    if (projects.some(p=>p.id===project) || !project) { $("project").value=project; projectSelection(); }
  });
  function hint(){$("roster-hint").textContent=$("session").value?"工作指引会填入下一轮草稿，延用这场会议的席位。":"在圆桌中复核席位和草稿后开始。";}
  async function openDraft(){
    const x={...form(),projectId:$("project").value,sessionId:$("session").value,question:$("question").value.trim(),resource:source};
    handoff.compose(x);
    x.materials = await runs.prepareHandoff(current?.id || "", x.projectId);
    if ($("project").value !== x.projectId || $("session").value !== x.sessionId) return;
    sessionStorage.setItem(handoff.key,JSON.stringify(x));
    const q=new URLSearchParams({project:x.projectId});if(x.sessionId)q.set("session",x.sessionId);
    handingOff = true;
    location.assign("/studio?"+q);
  }
  function resetResource(){preview=null;$("resource-text").value="";$("preview-panel").hidden=true;}
  function markSource(v){source=v;$("source").hidden=!v;$("excerpt").textContent=v?.excerpt||"";$("source-title").textContent=v?v.server+" · "+v.uri:"";}
  function action(id,fn){$(id).addEventListener("click",async()=>{
    const button=$(id);button.disabled=true;tell("");
    try{await fn();}catch(e){tell(e.message||"操作未完成");}finally{button.disabled=id==="handoff"&&!$("project").value;}
  });}
  action("new",()=>{if(canLeave()){select(null);$("title").focus();}});
  action("save",()=>save(false));action("fork",()=>save(true));
  action("delete",async()=>{if(!current||current.builtin||!confirm("删除个人模板「"+current.title+"」？"))return;
    await req(api+"presets/"+encodeURIComponent(current.id),"DELETE",{revision:current.revision});await refresh();tell("模板已删除。");});
  action("list",async()=>{
    const endpoint=$("endpoint").value.trim();resetResource();$("resource-panel").hidden=true;
    const rows=await req(api+"resources/list","POST",{endpoint});
    if(endpoint!==$("endpoint").value.trim())return;
    const pick=$("resources");pick.replaceChildren(...rows.map(item=>new Option(item.name||item.uri,item.uri)));$("resource-panel").hidden=!rows.length;
    tell(rows.length?"已列出 "+rows.length+" 条资源。":"此服务没有公开可读的资源。");
  });
  action("read",async()=>{
    const endpoint=$("endpoint").value.trim(),uri=$("resources").value;resetResource();
    const data=await req(api+"resources/read","POST",{endpoint,uri});if(endpoint!==$("endpoint").value.trim()||uri!==$("resources").value)return;
    preview=data;$("resource-text").value=data.text;$("preview-panel").hidden=false;
  });
  action("select-excerpt",()=>{
    const area=$("resource-text");if(!preview)throw Error("请先预览资源。");
    const snippet=area.value.slice(area.selectionStart,area.selectionEnd).trim();if(!snippet||Array.from(snippet).length>2000)throw Error("请在预览中选中 1–2,000 字。");
    const {uri,server,sha256}=preview;markSource({uri,server,sha256,excerpt:snippet});tell("选段已加入本次会议草稿。");
  });
  action("remove",()=>markSource(null));
  action("handoff",openDraft);$("project").onchange=()=>projectSelection(true);$("session").onchange=hint;
  $("endpoint").oninput=()=>{resetResource();$("resource-panel").hidden=true;};
  $("resources").onchange=resetResource;
  (async()=>{
    const [list,rooms]=await Promise.all([req("/api/research/projects"),req("/api/studio/sessions"),refresh()]);
    projects=list;sessions=Array.isArray(rooms)?rooms:rooms.sessions||[];
    $("project").replaceChildren(new Option("选择作用范围",""),new Option("全局会话","@global"), ...projects.map(p=>new Option(p.name,p.id)));
    const initial=new URLSearchParams(location.search).get("project");
    if(projects.some(p=>p.id===initial))$("project").value=initial;
    else if(new URLSearchParams(location.search).get("scope")==="global")$("project").value="@global";
    projectSelection();if(!projects.length)tell("可先编辑模板。可在全局会话中研究问答，或创建项目后引用项目原文。");
  })().catch(e=>tell(e.message));
})();
