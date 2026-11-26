(() => {
  "use strict";
  const $=id=>document.getElementById(id);
  const handoff=window.ScienceLabHandoff;
  const api="/api/research/lab/";
  let presets=[], projects=[], sessions=[], current=null, original=null, preview=null, source=null;
  let graphOwner="", graphPreview=null, graphGeneration=0, graphNodes=[];
  const graphPathOperations=["reading","method-lineage","bridge"];
  function tell(text){$("status").textContent=text;}
  async function req(path,method="GET",data,signal) {
    const opt={method,signal,cache:"no-store",keepalive:method==="PUT" && path.startsWith(api+"draft?"),headers:{"X-Roundtable":"1"}};
    if(path.startsWith(api+"connectors/") && window.sciStationConnectorSession)
      opt.headers["X-Sci-Station-Connector-Session"]=window.sciStationConnectorSession;
    if(data!==undefined){opt.headers["Content-Type"]="application/json";opt.body=JSON.stringify(data);}
    const res=await fetch(path,opt);
    if(res.status===204)return;
    const x=await res.json().catch(()=>null);
    if(!res.ok)throw Error(x?.error?.message || x?.error || "操作失败（"+res.status+"）");
    return x;
  }
  const projectContext = window.SciLabContext.mount({req, tell, resetResource,settingsChanged:(id,rev)=>connections.updateRevision(id,rev)});
  const connections=window.SciLabConnectors.mount({req,tell,resetResource,settingsChanged:(id,config)=>projectContext.updateRevision(id,config.revision),
    showPreview(value){preview=value;$("resource-text").value=value.text;$("preview-panel").hidden=false;}
  });
  const runs = window.SciLabRun.mount({req, tell, skillForRun:projectContext.resolve,
    form:() => ({...form(), workflow:current?.id || "", question:$("question").value.trim(), resource:source})});
  function form(){
    return {title:$("title").value.trim(),mode:$("mode").value,seats:Number($("seats").value),prompt:$("prompt").value.trim()};
  }
  function snapshot(p){return JSON.stringify([p.title,p.mode,p.seats,p.prompt]);}
  function dirtyTemplate(){return original!==null && snapshot(form())!==original;}
  function canLeave(){return !dirtyTemplate()||confirm("放弃尚未保存的模板更改？");}
  let handingOff = false;
  window.addEventListener("beforeunload", event => {
    if (!handingOff && (dirtyTemplate() || source || runs.hasDraft())) {
      event.preventDefault();
      event.returnValue = "";
    }
  });
  window.addEventListener("pageshow", () => { handingOff = false; });
  function showRunMode() {
    const roundtable = $("lab-run-mode").value === "roundtable";
    $("lab-single-controls").hidden = roundtable;
    $("lab-roundtable-controls").hidden = !roundtable;
  }
  function selectTemplateRunMode() {
    $("lab-run-mode").value = Number($("seats").value) > 1 ? "roundtable" : "single";
    showRunMode();
  }
  function select(p) {
    current=p;const x=p||{title:"",mode:"review",seats:1,prompt:""};original=snapshot(x);
    $("title").value=x.title;$("mode").value=x.mode;$("seats").value=String(x.seats);$("prompt").value=x.prompt;
    $("editor-title").textContent=p?.title||"新建个人模板";$("kind").textContent=p?.builtin?"内置模板":"个人模板";
    $("save").textContent=p&&!p.builtin?"保存更改":"保存为个人模板";
    $("fork").hidden=!p||p.builtin;$("delete").hidden=!p||p.builtin;
    selectTemplateRunMode();
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
    const discovery = $("discovery-link");
    if (discovery) {
      const query = new URLSearchParams({tab: "discover", trigger: "lab"});
      if (p) query.set("project", p.id);
      discovery.href = "/tools?" + query;
    }
    if(previousScope!==null && previousScope!==id) {markSource(null);resetResource();}
    previousScope=id;
    if (graphOwner!==id) {
      graphOwner=id;
      graphGeneration++;
      graphNodes=[];
      $("graph-controls").hidden=true;
      clearGraphPreview();
      if (source?.kind==="project-graph" && source.projectId!==id) markSource(null);
    }
    $("session").replaceChildren(new Option("新建圆桌",""));
    if(p)for(const s of sessions){if(s.project_id===p.id&&s.status!=="closed"&&!s.lab_thread?.archived_at)$("session").append(new Option(s.title||s.topic||"已有圆桌",s.id));}
    const url=new URL(location.href);
    if(p)url.searchParams.set("project",id);else url.searchParams.delete("project");
    if(id==="@global")url.searchParams.set("scope","global");else url.searchParams.delete("scope");
    if (commit) window.SciStationNav.commitURL(url,"push");
    $("handoff").disabled=!p;
    connections.select(id,p?.name || "");
    projectContext.select(id, p?.name || "").catch(e => tell(e.message));
    runs.selectProject(id==="@global"?{id:"",global:true}:p, sessions).catch(e => tell(e.message));
    hint();
  }
  window.addEventListener("popstate",()=>{
    const route=new URL(location.href).searchParams;
    const project=route.get("scope")==="global" ? "@global" : route.get("project") || "";
    if (project==="@global" || projects.some(p=>p.id===project) || !project) {
      $("project").value=project;
      projectSelection();
    }
  });
  function hint() {
    $("roster-hint").textContent = $("handoff").disabled ? "请先选择科研项目。" :
      $("session").value ? "工作指引会填入下一轮草稿，延用这场会议的席位。" :
        "在圆桌中复核席位、模型和草稿后开始。";
  }
  async function openDraft(){
    const x={...form(),workflow:current?.id || "",projectId:$("project").value,sessionId:$("session").value,question:$("question").value.trim(),resource:source};
    x.skill = await projectContext.resolve(x.projectId);
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
    try{await fn();}catch(e){tell(e.message||"操作未完成");}finally{button.disabled=id==="handoff"&&!projects.some(p=>p.id===$("project").value);}
  });}
  action("new",()=>{if(canLeave()){select(null);$("title").focus();}});
  action("save",()=>save(false));action("fork",()=>save(true));
  action("delete",async()=>{if(!current||current.builtin||!confirm("删除个人模板「"+current.title+"」？"))return;
    await req(api+"presets/"+encodeURIComponent(current.id),"DELETE",{revision:current.revision});await refresh();tell("模板已删除。");});
  function clearGraphPreview(){
    graphPreview=null;
    $("graph-preview-panel").hidden=true;
    $("graph-preview-text").value="";
  }
  function graphOperation(){
    const operation=$("graph-operation").value;
    const path=graphPathOperations.includes(operation);
    $("graph-focus-field").hidden=!path;
    $("graph-depth-field").hidden=!path;
    $("graph-target-field").hidden=operation!=="bridge";
    $("graph-direction-field").hidden=operation!=="method-lineage" && operation!=="bridge";
    const kind={reading:"paper","method-lineage":"method"}[operation];
    const focus=$("graph-node"), previous=focus.value;
    const candidates=graphNodes.filter(node=>!kind || node.kind===kind);
    focus.replaceChildren(new Option("请选择",""),...candidates.map(n=>new Option(n.label,n.id)));
    if(candidates.some(n=>n.id===previous))focus.value=previous;
    graphGeneration++;
    clearGraphPreview();
  }
  action("graph-nodes",async()=>{
    const project=$("project").value;
    if(!project)throw Error("请先选择科研项目。");
    const ticket=++graphGeneration;
    const graph=await req("/api/research/projects/"+encodeURIComponent(project)+"/graph");
    if(ticket!==graphGeneration || project!==$("project").value)return;
    graphNodes=graph.nodes.filter(n=>n.kind!=="missing");
    $("graph-target").replaceChildren(new Option("请选择",""),...graphNodes.map(n=>new Option(n.label,n.id)));
    if($("graph-operation").value==="reading" && !graphNodes.some(n=>n.kind==="paper"))$("graph-operation").value="missing-core";
    graphOperation();
    $("graph-controls").hidden=false;
  });
  action("graph-preview",async()=>{
    const project=$("project").value, focus=$("graph-node").value, operation=$("graph-operation").value;
    if(!project)throw Error("请先选择科研项目。");
    if(graphPathOperations.includes(operation) && !focus)throw Error("请选择项目图谱起点。");
    const ticket=++graphGeneration;
    clearGraphPreview();
    const query=new URLSearchParams({operation});
    if(graphPathOperations.includes(operation)){
      query.set("focus",focus);
      query.set("depth",$("graph-depth").value);
    }
    if(operation==="bridge")query.set("target",$("graph-target").value);
    if(operation==="bridge" || operation==="method-lineage")query.set("direction",$("graph-direction").value);
    const result=await req("/api/research/projects/"+encodeURIComponent(project)+"/graph/workflow?"+query);
    if(ticket!==graphGeneration || result.projectId!==$("project").value)return;
    graphPreview=result;
    $("graph-preview-text").value=result.excerpt;
    $("graph-preview-panel").hidden=false;
  });
  action("use-graph-preview",()=>{
    if(!graphPreview||graphPreview.projectId!==$("project").value)throw Error("请先预览当前项目的图谱。");
    markSource(graphPreview);
    tell("图谱资料已加入本次会议草稿。");
  });
  $("graph-operation").onchange=graphOperation;
  for(const id of ["graph-node","graph-target","graph-direction","graph-depth"])$(id).onchange=()=>{
    graphGeneration++;
    clearGraphPreview();
  };
  action("list",async()=>{
    const result=await projectContext.resource("list");
    if(!result)return;
    const {data:rows}=result;
    const pick=$("resources");pick.replaceChildren(...rows.map(item=>new Option(item.name||item.uri,item.uri)));$("resource-panel").hidden=!rows.length;
    tell(rows.length?"已列出 "+rows.length+" 条资源。":"此服务没有公开可读的资源。");
  });
  action("read",async()=>{
    const uri=$("resources").value;
    const result=await projectContext.resource("read",uri);
    if(!result || uri!==$("resources").value)return;
    preview={...result.data,projectId:result.projectId};$("resource-text").value=preview.text;$("preview-panel").hidden=false;
  });
  action("select-excerpt",()=>{
    const area=$("resource-text");if(!preview)throw Error("请先预览资源。");
    const snippet=area.value.slice(area.selectionStart,area.selectionEnd).trim();if(!snippet||Array.from(snippet).length>2000)throw Error("请在预览中选中 1–2,000 字。");
    const {uri,server,sha256,projectId,receipt}=preview;markSource({kind:"mcp-resource",uri,server,sha256,projectId,receipt,excerpt:snippet});tell("选段已加入本次会议草稿。");
  });
  action("remove",()=>markSource(null));
  action("handoff",openDraft);$("project").onchange=()=>projectSelection(true);$("session").onchange=hint;
  $("lab-run-mode").onchange = showRunMode;
  $("seats").onchange = selectTemplateRunMode;
  $("endpoint").oninput=projectContext.clearResource;
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
