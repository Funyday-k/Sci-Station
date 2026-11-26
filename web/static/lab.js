(() => {
  "use strict";
  const $=id=>document.getElementById(id);
  const handoff=window.ScienceLabHandoff;
  const api="/api/research/lab/";
  const text=(zh,en)=>window.SciStationI18n?.text(zh,en) || zh;
  let presets=[], projects=[], sessions=[], current=null, original=null, preview=null, source=null, selectedTemplate=null;
  let graphOwner="", graphPreview=null, graphGeneration=0, graphNodes=[];
  const graphPathOperations=["reading","method-lineage","bridge"];
  function tell(message){
    const activeStatus=document.querySelector(".lab-dialog[open] [data-lab-status]");
    (activeStatus || $("status")).textContent=message;
  }
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
    currentResource:()=>source, consumeResource:used=>{if(source===used) markSource(null);},setResource:markSource,
    form:()=>{
      const template=selectedTemplate ? presets.find(p=>p.id===selectedTemplate) : defaultTemplate();
      const {title,prompt,mode,seats,id}=template || {};
      return {title,prompt,mode,seats,workflow:id,question:$("question").value.trim(),resource:source};
    }});
  const defaultTemplate=()=>presets.find(p=>p.id==="research-question");
  function form(){
    return {title:$("title").value.trim(),mode:current?.mode || "review",seats:1,prompt:$("prompt").value.trim()};
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
  function select(p) {
    current=p;const x=p||{title:"",mode:"review",seats:1,prompt:""};original=snapshot(x);
    $("title").value=x.title;$("prompt").value=x.prompt;
    $("save").textContent=p&&!p.builtin?text("保存更改","Save changes"):text("保存为个人模板","Save as personal template");
    $("fork").hidden=!p||p.builtin;$("delete").hidden=!p||p.builtin;
  }
  const builtinTitles={"paper-reading":["精读论文","Read a paper"],"research-question":["研究问答","Research question"],
    "related-work":["比较相关工作","Compare related work"],"gap-planning":["查找研究空缺","Identify research gaps"]};
  function renderPresets(){
    const nav=$("presets");nav.replaceChildren();
    for(const p of presets.filter(p=>p.seats===1)){
      const b=document.createElement("button"), active=(selectedTemplate || defaultTemplate()?.id)===p.id;
      b.type="button";b.textContent=builtinTitles[p.id] ? text(...builtinTitles[p.id]) : p.title;b.dataset.id=p.id;
      b.classList.toggle("active",active); b.setAttribute("aria-pressed",String(active));
      b.onclick=()=>{if(canLeave()){selectedTemplate=p.id;select(p);renderPresets();nav.querySelector(`[data-id="${CSS.escape(p.id)}"]`)?.focus();}};
      nav.append(b);
    }
  }
  async function refresh(selected){
    presets=await req(api+"presets");
    if (selected || !presets.some(p=>p.id===selectedTemplate)) selectedTemplate=selected || null;
    renderPresets();select(presets.find(p=>p.id===selectedTemplate) || defaultTemplate() || null);
  }
  async function save(fork){
    const x=form();if(!x.title||!x.prompt)throw Error("请填写模板名称和工作指引。");
    const edit=current&&!current.builtin&&!fork;
    if(edit)x.revision=current.revision;
    const result=await req(api+"presets"+(edit?"/"+encodeURIComponent(current.id):""),edit?"PUT":"POST",x);
    await refresh(result.id);tell(text("个人模板已保存。","Personal template saved."));
  }
  let previousScope=null;
  const projectId=()=>$("project").value==="@global" ? "" : $("project").value;
  const transferQuery=id=>new URLSearchParams(id ? {project:id} : {scope:"global"});
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
    const url=new URL(location.href);
    if(p)url.searchParams.set("project",id);else url.searchParams.delete("project");
    if(id==="@global")url.searchParams.set("scope","global");else url.searchParams.delete("scope");
    if (commit) window.SciStationNav.commitURL(url,"push");
    connections.select(id,p?.name || "");
    projectContext.select(id, p?.name || "").catch(e => tell(e.message));
    runs.selectProject(id==="@global"?{id:"",global:true}:p, sessions).catch(e => tell(e.message));
    void showPendingTransfer();
  }
  window.addEventListener("popstate",()=>{
    const route=new URL(location.href).searchParams;
    const project=route.get("project") || "@global";
    if (project==="@global" || projects.some(p=>p.id===project) || !project) {
      $("project").value=project;
      projectSelection();
    }
  });
  function resetResource(){preview=null;$("resource-text").value="";$("preview-panel").hidden=true;}
  function markSource(v){
    source=v;$("source").hidden=!v;$("excerpt").textContent=v?.excerpt||"";$("source-title").textContent=v?v.server+" · "+v.uri:"";
    $("lab-attachments").hidden=!v && !$("local-list").childElementCount;
  }
  function action(id,fn){$(id).addEventListener("click",async()=>{
    const button=$(id);button.disabled=true;tell("");
    try{await fn();}catch(e){tell(e.message||text("操作未完成","The action could not be completed."));}finally{button.disabled=false;}
  });}
  let pendingTransfer=null, transferReview=null, transferSequence=0;
  async function showPendingTransfer() {
    const ticket=++transferSequence;
    pendingTransfer=null;$("lab-transfer-notice").hidden=true;
    if(new URL(location.href).searchParams.get("fromRoundtable")!=="1") return;
    const owner=projectId();
    try {
      const {workspace}=await req("/api/health");
      const input=handoff.readModeTransfer("single",{workspace,projectId:owner});
      if(!input || ticket!==transferSequence) return;
      if(input.sourceSessionId){
        const room=await req("/api/studio/sessions/"+encodeURIComponent(input.sourceSessionId));
        if(!handoff.scopeOwnsModeSource(room,owner)) return;
        const authorized=new Map((room.materials || []).map(item=>[item.id,item]));
        if(input.materials.some(item=>!authorized.has(item.id))) return;
        input.materials=input.materials.map(({id})=>({id,name:authorized.get(id).name}));
      }
      if(ticket!==transferSequence) return;
      pendingTransfer=input;$("lab-transfer-notice").hidden=false;
    } catch(error) {if(ticket===transferSequence) tell(error.message);}
  }
  function sourceUrl(path,queryKey,id,room) {
    const query=transferQuery(id);query.set(queryKey,room);
    return path+"?"+query;
  }
  function showTransfer(direction,input,limit="") {
    transferReview={direction,input};
    const incoming=direction==="in";
    $("lab-transfer-heading").textContent=incoming ? text("复核圆桌上下文","Review Roundtable context") : text("转到圆桌","Switch to Roundtable");
    $("lab-transfer-apply").textContent=incoming ? text("加入新对话草稿","Add to new chat draft") : text("在圆桌中复核","Review in Roundtable");
    $("lab-transfer-context").value=input.context;
    const sourceLink=$("lab-transfer-source");
    sourceLink.hidden=!input.sourceSessionId;
    if(input.sourceSessionId) sourceLink.href=sourceUrl(incoming?"/studio":"/lab",incoming?"session":"run",input.projectId,input.sourceSessionId);
    $("lab-transfer-limit").hidden=!limit;$("lab-transfer-limit").textContent=limit;
    $("lab-transfer-materials").replaceChildren(...input.materials.map(item=>{
      const row=document.createElement("li");row.textContent=item.name;return row;
    }));
    $("lab-transfer-dialog").querySelector("[data-lab-status]").textContent="";
    $("lab-transfer-dialog").showModal();
  }
  function finishPendingTransfer() {
    handoff.clearModeTransfer("single");pendingTransfer=null;$("lab-transfer-notice").hidden=true;
    const url=new URL(location.href);url.searchParams.delete("fromRoundtable");window.SciStationNav.commitURL(url,"replace");
  }
  action("lab-transfer-preview",()=>{if(pendingTransfer) showTransfer("in",pendingTransfer);});
  action("lab-transfer-dismiss",finishPendingTransfer);
  action("lab-transfer-apply",async()=>{
    if(!transferReview) return;
    const {direction,input}=transferReview;
    if(input.projectId!==projectId()) throw Error(text("当前范围已改变。","The active scope changed."));
    const context=$("lab-transfer-context").value.trim();
    if(!context) throw Error(text("请填写要带入的内容。","Enter the context to carry over."));
    if(direction==="in"){
      const provenance=input.sourceSessionId ? "\n\nSource Roundtable: "+sourceUrl("/studio","session",input.projectId,input.sourceSessionId) : "";
      await runs.importTransfer(input,context+provenance);
      finishPendingTransfer();$("lab-transfer-dialog").close();$("question").focus();
      return;
    }
    await runs.saveDraft();
    handoff.writeModeTransfer("roundtable",{...input,context});
    const query=transferQuery(input.projectId);query.set("fromLab","1");
    handingOff=true;location.assign("/studio?"+query);
  });
  window.addEventListener("sci:change-ai-mode",event=>{
    if(event.detail?.mode!=="roundtable") return;
    const room=runs.activeRoom(), owner=projectId(), draft=$(room?"lab-reply":"question").value.trim();
    if(!room && !draft && !runs.hasDraft() && !source) return;
    event.preventDefault();
    if($("lab-transfer-dialog").open) return;
    void (async()=>{
      try {
        const {workspace}=await req("/api/health");
        if(room && !handoff.scopeOwnsModeSource(room,owner)) return;
        const materials=room ? room.materials || [] : await runs.prepareHandoff(owner);
        if(owner!==projectId() || room?.id!==runs.activeRoom()?.id) return;
        const parts=[];
        if(room?.topic) parts.push(window.SciLabRun.messageText(room.topic,true));
        const done=room?.rounds?.flatMap(round=>round.turns || []).filter(turn=>turn.status==="done" && turn.text).at(-1);
        if(done) parts.push(text("最近的回答","Latest answer")+"\n"+done.text);
        if(draft) parts.push(room ? text("当前草稿","Current draft")+"\n"+draft : draft);
        if(source) parts.push(source.excerpt);
        const raw=parts.filter(Boolean).join("\n\n") || text("请讨论这些研究材料。","Discuss these research sources.");
        const context=Array.from(raw).slice(0,2400).join("");
        const limit=raw!==context || materials.length>12 ? text("预览包含上下文的前 2,400 字和最多 12 份材料。原对话保留完整记录。",
          "The preview contains the first 2,400 characters and up to 12 attachments. The original chat keeps the full record.") : "";
        showTransfer("out",{workspace,projectId:owner,sourceSessionId:room?.id || "",context,
          materials:materials.slice(0,12).map(({id,name})=>({id,name}))},limit);
      } catch(error) {tell(error.message);}
    })();
  });
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
    tell(text("图谱资料已加入当前消息。","Graph evidence attached to this message."));
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
    const {uri,server,sha256,projectId,receipt}=preview;markSource({kind:"mcp-resource",uri,server,sha256,projectId,receipt,excerpt:snippet});
    tell(text("选段已加入当前消息。","Excerpt attached to this message."));
  });
  action("remove",()=>markSource(null));
  $("project").onchange=()=>projectSelection(true);
  for (const [trigger,dialog] of [["lab-attach","lab-materials-dialog"],["lab-tools","lab-tools-dialog"],
    ["lab-model-trigger","lab-model-dialog"],["lab-draft-trigger","lab-draft-dialog"]]) {
    $(trigger).addEventListener("click",()=>{$("status").textContent="";$(dialog).showModal();});
  }
  for (const close of document.querySelectorAll("[data-lab-close]")) close.addEventListener("click",()=>close.closest("dialog").close());
  function scopeOptions() {
    const previous=$("project").value;
    $("project").replaceChildren(new Option(text("全局会话","Global"),"@global"),...projects.map(p=>new Option(p.name,p.id)));
    $("project").value=projects.some(p=>p.id===previous) ? previous : "@global";
  }
  window.addEventListener("sci:language",()=>{scopeOptions();renderPresets();});
  $("endpoint").oninput=projectContext.clearResource;
  $("resources").onchange=resetResource;
  (async()=>{
    const [list,rooms]=await Promise.all([req("/api/research/projects"),req("/api/studio/sessions"),refresh()]);
    projects=list;sessions=Array.isArray(rooms)?rooms:rooms.sessions||[];
    scopeOptions();
    const initial=new URLSearchParams(location.search).get("project");
    if(projects.some(p=>p.id===initial))$("project").value=initial;
    projectSelection();
  })().catch(e=>tell(e.message));
})();
