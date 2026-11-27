(() => {
  "use strict";
  const $=id=>document.getElementById(id);
  const handoff=window.ScienceLabHandoff;
  const api="/api/research/lab/";
  const text=(zh,en)=>window.SciStationI18n?.text(zh,en) || zh;
  const toolPanel=window.SciLabTools.mount({
    dialog:$("lab-tools-dialog"),
    trigger:$("lab-tools"),
    onNavigate:(id)=> { if(id==="discovery") openDiscoveryTool(); }
  });
  let presets=[], projects=[], sessions=[], current=null, original=null, preview=null, source=null, selectedTemplate=null;
  let draftWorkspace="", workspaceLookup=null;
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
    if(data instanceof FormData) opt.body=data;
    else if(data!==undefined){opt.headers["Content-Type"]="application/json";opt.body=JSON.stringify(data);}
    const res=await fetch(path,opt);
    if(res.status===204)return;
    const x=await res.json().catch(()=>null);
    if(!res.ok){
      const error=Error(x?.error?.message || x?.error || "操作失败（"+res.status+"）");
      error.status=res.status;
      error.session=x?.session;
      throw error;
    }
    return x;
  }
  async function checkedMaterials({sourceSessionId,projectId,materials}) {
    const checked=await req("/api/studio/materials/transfer-check","POST",{
      sessionId:sourceSessionId,projectId,materialIds:materials.map(item=>item.id)
    });
    return checked.materials;
  }
  async function refreshReviewedMaterials(input) {
    const verified=await checkedMaterials(input);
    if(JSON.stringify(verified)!==JSON.stringify(input.materials)) throw Error(text(
      "附件有变化，请重新打开转换预览。","The attachments changed. Open the transfer preview again."));
    return verified;
  }
  const projectContext = window.SciLabContext.mount({req, tell, resetResource,settingsChanged:(id,rev)=>connections.updateRevision(id,rev)});
  const connections=window.SciLabConnectors.mount({req,tell,resetResource,settingsChanged:(id,config)=>projectContext.updateRevision(id,config.revision),
    showPreview(value){preview=value;$("resource-text").value=value.text;$("preview-panel").hidden=false;}
  });
  const runs = window.SciLabRun.mount({req, tell, scopeAvailable, rememberDraft, restoreModeDraft, restoreTemplate, resetTemplate, checkedMaterials, skillForRun:projectContext.resolve,
    currentResource:()=>source, consumeResource:used=>{if(source===used) markSource(null);},setResource:markSource,
    form:()=>{
      const template=selectedTemplate ? presets.find(p=>p.id===selectedTemplate) : defaultTemplate();
      const {title,prompt,mode,seats,id}=template || {};
      return {title,prompt,mode,seats,workflow:id,question:$("question").value.trim(),resource:source};
    }});
  const defaultTemplate=()=>presets.find(p=>p.id==="research-question");
  function form(){
    return {title:$("title").value.trim(),mode:current?.mode || "review",seats:current?.seats || 1,prompt:$("prompt").value.trim()};
  }
  function snapshot(p){return JSON.stringify([p.title,p.mode,p.seats,p.prompt]);}
  function dirtyTemplate(){return original!==null && snapshot(form())!==original;}
  function canLeave(){return !dirtyTemplate()||confirm(text("放弃尚未保存的模板更改？","Discard unsaved template changes?"));}
  let handingOff = false;
  window.addEventListener("beforeunload", event => {
    if (!handingOff && (dirtyTemplate() || runs.hasUnsavedInput() || (!runs.rememberComposition() && (source || runs.hasDraft())))) {
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
    "related-work":["比较相关工作","Compare related work"],"gap-planning":["查找研究空缺","Identify research gaps"],
    "independent-check":["双席独立复核","Independent review"],"research-design":["多席研究方案评议","Research design review"],
    "research-priorities":["研究任务排序","Research priorities"]};
  const modeNames={review:["方案评审","Review"],forum:["多方权衡","Forum"],prioritize:["优先级排序","Prioritize"]};
  const templateTitle=template=>builtinTitles[template.id] ? text(...builtinTitles[template.id]) : template.title;
  function findTemplateAction(id,action) {
    return $("lab-tools-dialog").querySelector(`[data-template-action="${action}"][data-template-id="${CSS.escape(id)}"]`);
  }
  function templateEditButton(template) {
    const edit=document.createElement("button");
    edit.type="button"; edit.dataset.templateId=template.id; edit.dataset.templateAction="edit";
    edit.textContent=template.builtin ? text("作为个人模板编辑","Edit as a personal template") : text("编辑模板","Edit template");
    edit.onclick=()=>{if(canLeave()) editTemplate(template,() => findTemplateAction(template.id,"edit"));};
    return edit;
  }
  function renderPresets(){
    const nav=$("presets");nav.replaceChildren();
    for(const p of presets.filter(p=>p.seats===1)){
      const row=document.createElement("li"), b=document.createElement("button"), active=(selectedTemplate || defaultTemplate()?.id)===p.id;
      b.type="button";b.textContent=templateTitle(p);b.dataset.id=p.id;b.className="lab-template-choice";
      b.classList.toggle("active",active); b.setAttribute("aria-pressed",String(active));
      b.onclick=()=>{if(canLeave()){selectedTemplate=p.id;select(p);renderPresets();nav.querySelector(`[data-id="${CSS.escape(p.id)}"]`)?.focus();}};
      row.append(b,templateEditButton(p));nav.append(row);
    }
    renderRoundtableTemplates();
  }
  function renderRoundtableTemplates() {
    const legacy=presets.filter(p=>p.seats>1);
    $("lab-legacy-template-list").replaceChildren(...legacy.map(template=>{
      const entry=document.createElement("li"), identity=document.createElement("div"), title=document.createElement("h3"),
        metadata=document.createElement("p"), actions=document.createElement("div"), open=document.createElement("button");
      entry.dataset.templateId=template.id;identity.className="lab-template-description";title.textContent=templateTitle(template);
      const mode=modeNames[template.mode] ? text(...modeNames[template.mode]) : template.mode;
      const description=text(`${template.seats} 个席位 · ${mode}`,`${template.seats} seats · ${mode}`);
      metadata.className="hint";metadata.textContent=description;
      actions.className="actions";
      open.type="button";open.textContent=text("复核后转到圆桌","Review and open Roundtable");
      open.dataset.templateId=template.id;open.dataset.templateAction="review";
      open.onclick=async()=>{
        open.disabled=true;
        const owner=projectId();
        try{
          const {workspace}=await req("/api/health");
          if(owner!==projectId() || !scopeAvailable() || !$("lab-tools-dialog").open ||
              toolPanel.active()!=="roundtable-templates" || !open.isConnected) return;
          const context=[template.title,template.prompt].join("\n\n");
          const roundtablePreset={mode:template.mode,seats:template.seats};
          $("lab-tools-dialog").close();
          showTransfer("out",{workspace,projectId:owner,projectGeneration:scopeGeneration(owner),sourceSessionId:"",context,materials:[],roundtablePreset},description);
          $("lab-transfer-dialog").addEventListener("close",()=>{
            if(!handingOff) toolPanel.open("roundtable-templates",findTemplateAction(template.id,"review") || undefined);
          },{once:true});
        } catch(error){tell(error.message);}
        finally{open.disabled=false;}
      };
      identity.append(title,metadata);actions.append(open,templateEditButton(template));entry.append(identity,actions);return entry;
    }));
  }
  function editTemplate(template,opener) {
    select(template);
    toolPanel.enter("template-edit",opener);
    $("title").focus();
  }
  function restoreTemplate(id,revision) {
    if(!id) return;
    const template=presets.find(item=>item.id===id && item.seats===1 && item.revision===revision);
    if(!template) {
      tell(text("原回答模板有变化，请重新选择。","The original answer template changed. Select a template again."));
      return;
    }
    selectedTemplate=template.id;
    if(!dirtyTemplate()) select(template);
    renderPresets();
  }
  function resetTemplate() {
    if(!selectedTemplate) return;
    selectedTemplate=null;
    if(!dirtyTemplate()) select(defaultTemplate() || null);
    renderPresets();
  }
  async function refresh(selected){
    presets=await req(api+"presets");
    const saved=presets.find(p=>p.id===selected);
    if(saved?.seats===1) selectedTemplate=saved.id;
    if(!presets.some(p=>p.id===selectedTemplate && p.seats===1)) selectedTemplate=null;
    renderPresets();select(saved || presets.find(p=>p.id===selectedTemplate) || defaultTemplate() || null);
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
  const scopeGeneration=id=>projects.find(item=>item.id===id)?.conversationGeneration || 0;
  function scopeAvailable(){
    const id=$("project").value;
    return id==="@global" || projects.some(p=>p.id===id);
  }
  const unavailableScope=()=>text("此项目不可用。请选择一个项目或全局会话。","This project is unavailable. Select a project or Global.");
  function showScopeStatus(){
    const available=scopeAvailable(), status=$("status");
    $("project").setAttribute("aria-invalid",String(!available));
    if(!available) status.textContent=unavailableScope();
    else if(status.dataset.scopeUnavailable) status.textContent="";
    status.dataset.scopeUnavailable=available ? "" : "1";
  }
  const transferQuery=id=>new URLSearchParams(id ? {project:id} : {scope:"global"});
  function projectSelection(commit = false){
    const id=$("project").value,p=projects.find(v=>v.id===id);
    $("graph-nodes").disabled=!p;
    for(const note of document.querySelectorAll("[data-lab-project-tool-note]")) note.hidden=Boolean(p);
    if(previousScope!==null && previousScope!==id) resetResource();
    previousScope=id;
    if (graphOwner!==id) {
      graphOwner=id;
      graphGeneration++;
      graphNodes=[];
      $("graph-controls").hidden=true;
      clearGraphPreview();
    }
    const url=new URL(location.href);
    if(p)url.searchParams.set("project",id);else url.searchParams.delete("project");
    if(id==="@global")url.searchParams.set("scope","global");else url.searchParams.delete("scope");
    const available=scopeAvailable();
    if (commit && available) window.SciStationNav.commitURL(url,"push");
    connections.select(available ? id : "",p?.name || "");
    projectContext.select(available ? id : "", p?.name || "").catch(e => tell(e.message));
    runs.selectProject(id==="@global"?{id:"",global:true}:p, sessions).catch(e => tell(e.message));
    showScopeStatus();
    void showPendingTransfer();
  }
  window.addEventListener("popstate",()=>{
    const route=new URL(location.href).searchParams;
    const project=route.get("project") || "@global";
    scopeOptions(project);
    projectSelection();
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
  const draftPrefix=(owner,thread)=>"sci-station.lab-mode-draft.v1:"+encodeURIComponent(owner)+":"+encodeURIComponent(thread)+":";
  const modeDraftKey=(workspace,owner,thread,generation)=>draftPrefix(owner,thread)+encodeURIComponent(workspace)+(generation ? ":"+generation : "");
  function workspaceForDraft() {
    if(draftWorkspace) return Promise.resolve(draftWorkspace);
    if(!workspaceLookup) workspaceLookup=req("/api/health").then(({workspace})=>draftWorkspace=workspace).finally(()=>{workspaceLookup=null;});
    return workspaceLookup;
  }
  async function verifyDraftCitation(owner,reference) {
    const {kind,id,page,offset,hash,characters}=reference.citation || reference;
    const original=await req(api+"sources/preview","POST",{projectId:owner,location:{kind,id,page,offset}});
    const length=characters ?? Array.from(reference.citation?.quote || "").length;
    const excerpt=Array.from(original.text).slice(0,length);
    if(!Number.isInteger(length) || length<1 || length>1000 || original.hash!==hash || (original.offset || 0)!==offset || excerpt.length!==length ||
       (reference.citation?.quote && excerpt.join("")!==reference.citation.quote)) throw Error(text(
      "草稿中的原文已更改，请重新选择选段。","A source in the draft changed. Select the excerpt again."));
    return {title:original.title,citation:{kind,id,page,offset,hash,quote:excerpt.join("")}};
  }
  async function verifyDraftFile(owner,thread,{id,revision}) {
    const [material]=await checkedMaterials({sourceSessionId:thread,projectId:owner,materials:[{id}]});
    if(!material || (revision && material.revision!==revision)) throw Error(text("草稿附件已更改。","A draft attachment changed."));
    return material;
  }
  function restoreModeDraft(owner,thread,generation) {
    const prefix=draftPrefix(owner,thread);
    try {
      if(!Object.keys(sessionStorage).some(key=>key.startsWith(prefix))) return null;
    } catch { return null; }
    return (async()=>{
      const workspace=await workspaceForDraft();
      const key=modeDraftKey(workspace,owner,thread,generation), value=sessionStorage.getItem(key);
      if(!value) return null;
      const {ids=[],imports=ids.map(id=>({id})),resource,citations=[],templateId="",templateRevision,modelChoice}=JSON.parse(value);
      if(!Array.isArray(imports) || !Array.isArray(citations) || imports.length+citations.length>12 || citations.length>4 ||
        imports.some(item=>!item || typeof item.id!=="string" || !/^[a-f0-9]{32}$/.test(item.id))) return null;
      const [files,sources]=await Promise.all([
        Promise.allSettled(imports.map(item=>verifyDraftFile(owner,thread,item))),
        Promise.allSettled(citations.map(citation=>verifyDraftCitation(owner,citation)))
      ]);
      const valid=items=>items.flatMap(result=>result.status==="fulfilled" ? [result.value] : []);
      const warning=[...files,...sources].some(result=>result.status==="rejected") ? text(
        "部分草稿附件已更改或不可用。请核对并重新添加缺失的材料。",
        "Some draft attachments changed or are unavailable. Review the draft and attach any missing materials again.") : "";
      return {materials:valid(files),selected:valid(sources),templateId,templateRevision,modelChoice,warning,
        resource:handoff.retainExcerpt(resource,owner),consume(){
        if(sessionStorage.getItem(key)===value) sessionStorage.removeItem(key);
      }};
    })();
  }
  function rememberDraft(owner,thread,draft,generation,workspace=draftWorkspace) {
    if(!workspace) return false;
    const key=modeDraftKey(workspace,owner,thread,generation);
    const template=presets.find(item=>item.id===selectedTemplate && item.seats===1);
    const imports=draft.materials.map(({id,revision})=>({id,revision}));
    const citations=draft.citations.map(({citation:{kind,id,page,offset,hash,quote}})=>({kind,id,page,offset,hash,characters:Array.from(quote).length}));
    // External excerpts were explicitly selected. Keep this exact approved text in the tab without opening the connection again.
    const resource=handoff.retainExcerpt(draft.resource,owner);
    const {modelChoice}=draft;
    if(imports.length || citations.length || resource || template || modelChoice) {
      sessionStorage.setItem(key,JSON.stringify({imports,citations,resource,templateId:template?.id,templateRevision:template?.revision,modelChoice}));
    } else sessionStorage.removeItem(key);
    return true;
  }
  async function retainModeDraft(workspace,owner,thread,materials) {
    const draft=runs.compositionState();
    const importedIds=new Set(draft.materials.map(item=>item.id));
    if(!materials) {
      materials=importedIds.size ? await checkedMaterials({sourceSessionId:thread,projectId:owner,materials:draft.materials}) : [];
    }
    if(!scopeAvailable() || owner!==projectId() || thread!==runs.activeThread()) return false;
    return rememberDraft(owner,thread,{...draft,materials:materials.filter(item=>importedIds.has(item.id))},scopeGeneration(owner),workspace);
  }
  function discoveryRoute() {
    const owner=projectId(), thread=runs.activeThread();
    const query=new URLSearchParams({tab:"discover",trigger:"lab",labProject:owner});
    if(owner) query.set("project",owner);
    if(thread) query.set("labRun",thread);
    if(new URL(location.href).searchParams.get("fromRoundtable")==="1") query.set("labFromRoundtable","1");
    return "/tools?"+query;
  }
  let leavingForDiscovery=false;
  async function openDiscoveryTool() {
    const destination=discoveryRoute();
    if(leavingForDiscovery || !scopeAvailable() || !canLeave()) return;
    if(runs.restoringDraft()) {
      tell(text("草稿正在恢复，请稍后再打开文献推荐。","Wait for the draft to finish restoring before opening recommendations."));
      return;
    }
    leavingForDiscovery=true;
    const owner=projectId(), thread=runs.activeThread();
    const onCatalog=()=>$("lab-tools-dialog").open && toolPanel.active()==="directory" &&
      owner===projectId() && thread===runs.activeThread();
    try {
      const {workspace}=await req("/api/health");
      if(!onCatalog()) return;
      await runs.saveDraft();
      if(!onCatalog() || !await retainModeDraft(workspace,owner,thread) || !onCatalog()) return;
      const from=new URL(location.href);
      from.searchParams.set("tools","discovery");
      handingOff=true;
      if(window.SciShellLayout?.navigate) window.SciShellLayout.navigate(destination,{from});
      else {
        window.SciStationNav.commitURL(from,"replace");
        location.assign(destination);
      }
    } catch(error) {if(onCatalog()) tell(error.message);}
    finally {leavingForDiscovery=false;}
  }
  function restoreDiscoveryPanel() {
    const from=new URL(location.href);
    if(from.searchParams.get("tools")!=="discovery") return;
    from.searchParams.delete("tools");
    window.SciStationNav.commitURL(from,"replace");
    toolPanel.open("discovery");
  }
  window.addEventListener("popstate",restoreDiscoveryPanel);
  async function showPendingTransfer() {
    const ticket=++transferSequence;
    pendingTransfer=null;$("lab-transfer-notice").hidden=true;
    if(!scopeAvailable() || new URL(location.href).searchParams.get("fromRoundtable")!=="1") return;
    const owner=projectId();
    try {
      const {workspace}=await req("/api/health");
      const input=handoff.readModeTransfer("single",{workspace,projectId:owner,projectGeneration:scopeGeneration(owner)});
      if(!input || ticket!==transferSequence) return;
      input.materials=await checkedMaterials(input);
      if(ticket!==transferSequence) return;
      pendingTransfer=input;$("lab-transfer-notice").hidden=false;
    } catch(error) {if(ticket===transferSequence) tell(error.message);}
  }
  function sourceUrl(path,queryKey,id,room) {
    const query=transferQuery(id);query.set(queryKey,room);
    return path+"?"+query;
  }
  function showTransfer(direction,input,limit="",retainedMaterials) {
    transferReview={direction,input,originThread:runs.activeThread(),retainedMaterials,
      epoch:transferSequence,draft:runs.handoffDraftStamp()};
    const incoming=direction==="in";
    $("lab-transfer-heading").textContent=incoming ? text("复核圆桌上下文","Review Roundtable context") : text("转到圆桌","Switch to Roundtable");
    $("lab-transfer-apply").textContent=incoming ? text("加入新对话草稿","Add to new chat draft") : text("在圆桌中复核","Review in Roundtable");
    const context=$("lab-transfer-context");
    context.maxLength=input.roundtablePreset ? handoff.roundtablePresetContextLimit : handoff.modeContextLimit;
    context.value=input.context;
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
  function reviewIsCurrent(review) {
    return transferReview===review && $("lab-transfer-dialog").open && review.epoch===transferSequence &&
      review.originThread===runs.activeThread() && scopeAvailable() && review.input.projectId===projectId() &&
      (review.input.projectGeneration || 0)===scopeGeneration(review.input.projectId);
  }
  action("lab-transfer-preview",async()=>{
    const input=pendingTransfer, epoch=transferSequence, thread=runs.activeThread();
    if(!input) return;
    const materials=await checkedMaterials(input);
    if(epoch===transferSequence && thread===runs.activeThread() && scopeAvailable() && input===pendingTransfer &&
        (input.projectGeneration || 0)===scopeGeneration(input.projectId)) {
      showTransfer("in",{...input,materials});
    }
  });
  action("lab-transfer-dismiss",finishPendingTransfer);
  action("lab-transfer-apply",async()=>{
    const review=transferReview;
    if(!review || !reviewIsCurrent(review)) throw Error(text("当前范围已改变。","The active scope changed."));
    const {direction,input,originThread,retainedMaterials}=review;
    const context=$("lab-transfer-context").value.trim();
    if(!context) throw Error(text("请填写要带入的内容。","Enter the context to carry over."));
    const materials=input.roundtablePreset ? await checkedMaterials(input) : await refreshReviewedMaterials(input);
    if(!reviewIsCurrent(review)) return;
    if(direction==="in"){
      const provenance=input.sourceSessionId ? "\n\nSource Roundtable: "+sourceUrl("/studio","session",input.projectId,input.sourceSessionId) : "";
      await runs.importTransfer({...input,materials},context+provenance);
      finishPendingTransfer();$("lab-transfer-dialog").close();$("question").focus();
      return;
    }
    if(!canLeave()) return;
    await runs.saveDraft();
    const pending=retainedMaterials?.length && !materials.length ?
      await refreshReviewedMaterials({...input,sourceSessionId:originThread,materials:retainedMaterials}) : retainedMaterials;
    if(!reviewIsCurrent(review)) return;
    if(review.draft!==runs.handoffDraftStamp()) throw Error(text("草稿附件有变化，请重新打开转换预览。",
      "The draft attachments changed. Open the transfer preview again."));
    if(!await retainModeDraft(input.workspace,input.projectId,originThread,pending)) return;
    if(!reviewIsCurrent(review)) return;
    handoff.writeModeTransfer("roundtable",{...input,context,materials});
    const query=transferQuery(input.projectId);query.set("fromLab","1");
    handingOff=true;location.assign("/studio?"+query);
  });
  let openingTransfer=false;
  window.addEventListener("sci:change-ai-mode",event=>{
    if(event.detail?.mode!=="roundtable") return;
    const room=runs.activeRoom(), owner=projectId(), draft=$(room?"lab-reply":"question").value.trim();
    if(!room && !draft && !runs.hasDraft() && !source) return;
    event.preventDefault();
    if($("lab-transfer-dialog").open || openingTransfer) return;
    openingTransfer=true;
    const epoch=transferSequence, thread=runs.activeThread(), sourceStamp=runs.restoringDraft() ? null : runs.handoffDraftStamp();
    const current=()=>epoch===transferSequence && scopeAvailable() && owner===projectId() && thread===runs.activeThread();
    void (async()=>{
      try {
        const {workspace}=await req("/api/health");
        if(room && !handoff.scopeOwnsModeSource(room,owner)) return;
        const pending=await runs.prepareHandoff(owner);
        if(!current() || room?.id!==runs.activeRoom()?.id) return;
        const materials=[...new Map([...pending,...(room?.materials || [])].map(item=>[item.id,item])).values()];
        const parts=[];
        if(room?.topic) parts.push(window.SciLabRun.messageText(room.topic,true));
        const done=room?.rounds?.flatMap(round=>round.turns || []).filter(turn=>turn.status==="done" && turn.text).at(-1);
        if(done) parts.push(text("最近的回答","Latest answer")+"\n"+done.text);
        if(draft) parts.push(room ? text("当前草稿","Current draft")+"\n"+draft : draft);
        if(source) parts.push(source.excerpt);
        const raw=parts.filter(Boolean).join("\n\n") || text("请讨论这些研究材料。","Discuss these research sources.");
        const context=Array.from(raw).slice(0,handoff.modeContextLimit).join("");
        const overflow=materials.length>12;
        const limit=[raw===context ? "" : text("预览包含上下文的前 2,400 字。原对话保留完整记录。",
          "The preview contains the first 2,400 characters. The original chat keeps the full record."),
          overflow ? text("原对话和草稿的附件超过 12 份。本次只带入文字，附件留在原处。",
            "The original chat and draft have more than 12 attachments. This transfer carries text only and leaves all attachments in place.") : ""].filter(Boolean).join(" ");
        const input={workspace,projectId:owner,projectGeneration:scopeGeneration(owner),sourceSessionId:room?.id || "",context,materials:overflow ? [] : materials};
        input.materials=await checkedMaterials(input);
        const ids=new Set(pending.map(item=>item.id));
        const retained=overflow && pending.length ? await checkedMaterials({...input,materials:pending}) :
          input.materials.filter(item=>ids.has(item.id));
        if(!current() || room?.id!==runs.activeRoom()?.id) return;
        if(sourceStamp!==null && sourceStamp!==runs.handoffDraftStamp()) throw Error(text("草稿附件有变化，请重新切换模式。",
          "The draft attachments changed. Switch modes again."));
        showTransfer("out",input,limit,retained);
      } catch(error) {if(current()) tell(error.message);}
      finally {openingTransfer=false;}
    })();
  });
  action("new",()=>{if(canLeave()) editTemplate(null,() => $("new"));});
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
  for (const [trigger,dialog] of [["lab-attach","lab-materials-dialog"],
    ["lab-model-trigger","lab-model-dialog"],["lab-draft-trigger","lab-draft-dialog"]]) {
    $(trigger).addEventListener("click",()=>{
      $("status").textContent="";$(dialog).showModal();
      if(trigger==="lab-model-trigger") runs.ensureModels();
    });
  }
  for (const close of document.querySelectorAll("[data-lab-close]")) close.addEventListener("click",()=>close.closest("dialog").close());
  function scopeOptions(id=$("project").value || "@global") {
    const scope=$("project"), prior=scope.selectedOptions[0];
    scope.replaceChildren(new Option(text("不关联项目","No project"),"@global"),...projects.map(p=>new Option(p.name,p.id)));
    if(id!=="@global" && !projects.some(p=>p.id===id)) {
      const name=prior?.value===id ? prior.dataset.projectName || prior.textContent : id;
      const unavailable=new Option(text("项目不可用 · ","Project unavailable · ")+name,id);
      unavailable.dataset.projectName=name;unavailable.disabled=true;scope.append(unavailable);
    }
    scope.value=id;
  }
  window.addEventListener("sci:language",()=>{scopeOptions();showScopeStatus();renderPresets();});
  $("endpoint").oninput=projectContext.clearResource;
  $("resources").onchange=resetResource;
  const initialScope=(async()=>{
    const [list,rooms]=await Promise.all([req("/api/research/projects"),req("/api/studio/sessions"),refresh(),workspaceForDraft().catch(()=>{})]);
    projects=list;sessions=Array.isArray(rooms)?rooms:rooms.sessions||[];
    scopeOptions(new URLSearchParams(location.search).get("project") || "@global");
    projectSelection();
    restoreDiscoveryPanel();
  })().catch(e=>tell(e.message));
  let scopeRefresh=0;
  window.addEventListener("sci:projects-changed",()=>{
    const ticket=++scopeRefresh;
    initialScope.then(()=>req("/api/research/projects")).then(list=>{
      if(ticket!==scopeRefresh) return;
      projects=list;scopeOptions();showScopeStatus();runs.updateComposer();
    }).catch(error=>{if(ticket===scopeRefresh) tell(error.message);});
  });
  window.addEventListener("sci:project-conversations-reset",event=>{
    if(projectId()!==event.detail.id)return;
    handingOff=true;transferSequence++;runs.retireProject(event.detail.id);
  });
})();
