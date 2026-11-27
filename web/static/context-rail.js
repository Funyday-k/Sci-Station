"use strict";
(() => {
  const layout=window.SciShellLayout;
  const node=id=>document.getElementById(id);
  const text=(zh,en)=>window.SciStationI18n?.text(zh,en) ?? zh;
  const req=layout.request;
  async function loadRun() {
    await Promise.all([
      window.SciLabRun || layout.loadAsset("/static/lab-run.js"),
      window.SciStationReadReview || layout.loadAsset("/static/model-read-review.js")
    ]);
    return window.SciLabRun;
  }
  const reader=()=>document.body.dataset.workspaceSurface==="reader";
  const narrow=matchMedia("(max-width:999px)");
  let selectedObject=null, requestedMode=null, requestedRoute="", returnFocus=null;
  const projectRecords=new Map();
  let context, draftContext, key="", generation=0, room=null, busy=false, models=[], poll=0;
  let catalogScope="", moduleEnabled=false, runLookup="";
  const projectOf=c=>({id:c.project,global:!c.project,conversationGeneration:c.projectGeneration});
  const storage={
    get(key){try{return sessionStorage.getItem(key);}catch{return null;}},
    set(key,value){try{if(value)sessionStorage.setItem(key,value);else sessionStorage.removeItem(key);}catch{}}
  };
  const paperSelection=()=>window.SciResearch?.library?.selectedPapers?.() || [];
  const selectionKey=papers=>papers.map(p=>p.id).sort().join("\u0000");
  function panelRoute() {
    const url=new URL(location.href);
    // A page or evidence anchor changes position within the same reader task.
    return reader() ? JSON.stringify([url.pathname,url.searchParams.get("project") || "",url.searchParams.get("paper") || ""]) : url.href;
  }
  function contextOf() {
    const url=new URL(location.href), params=url.searchParams;
    const meeting=document.body.dataset.workspaceSurface==="studio" ? window.SciShellMeeting?.() || null : null;
    const project=meeting?.project || params.get("project") || "";
    const research=window.SciResearch?.state;
    const matchesProject=(research?.project?.id || "")===project;
    const data=matchesProject && !research?.loading && !research?.loadError ? research:null;
    const view=params.get("view") || "overview";
    if(selectedObject?.route!==url.href)selectedObject=null;
    const selection=view==="papers" && data?.view==="papers" ? paperSelection() : [];
    if(selectedObject?.paper && selectedObject.selection!==selectionKey(selection))selectedObject=null;
    const inspectedPaper=data?.papers?.find(p=>p.id===selectedObject?.paper && (!project || p.project_ids?.includes(project)));
    const paper=reader()?window.SciShellReader?.():inspectedPaper || (selection.length===1?selection[0]:null);
    const note=data?.notes?.find(n=>n.id===(selectedObject ? selectedObject.note : params.get("note")));
    const task=data?.tasks?.find(t=>t.id===(selectedObject ? selectedObject.task : params.get("task")));
    const title=(!inspectedPaper && selection.length>1 ? text("已选 "+selection.length+" 篇文献",selection.length+" papers selected") : "") || paper?.title || note?.title || task?.title || meeting?.title || document.getElementById("view-title")?.textContent ||
      (data?.project && view==="overview" ? data.project.name : document.title.split(" · ")[0]);
    const noteExcerpt=note ? Array.from((note.body || "").replace(/\r\n?/g,"\n")).slice(0,1000).join("").trim() : "";
    const meetingExcerpt=meeting?.topic ? Array.from(meeting.topic.replace(/\r\n?/g,"\n")).slice(0,1000).join("").trim() : "";
    const facts=paper ? [
      [text("作者","Authors"),paper.authors?.join(", ")],[text("年份","Year"),paper.year],["DOI",paper.doi],["arXiv",paper.arxiv],
      [text("阅读状态","Reading status"),window.SciResearch?.statusLabel[paper.status] || paper.status]
    ] : task ? [
      [text("状态","Status"),window.SciResearch.statusLabel[task.status] || task.status],
      [text("截止时间","Due"),[task.dueDate,task.dueTime].filter(Boolean).join(" ")],
      [text("标签","Tags"),task.tags?.join(", ")],
      [text("说明","Description"),task.description]
    ] : note ? [
      [text("目录","Folder"),note.namespace],
      [text("标签","Tags"),note.tags?.join(", ")],
      [text("别名","Aliases"),note.aliases?.join(", ")]
    ] : meeting ? [
      [text("讨论模式","Mode"),meeting.mode],
      [text("文件权限","File access"),meeting.access],
      [text("状态","Status"),meeting.status],
      [text("席位","Seats"),meeting.seats?.join("、")]
    ] : [];
    const item=data?.project || projectRecords.get(project)?.item;
    return {project,projectGeneration:project ? item ? item.conversationGeneration || 0 : null : 0,
      projectName:item?.name || "",facts:facts.filter(([,value])=>Boolean(value)), path:url.pathname,view, paper:paper?.id || "",
      visiblePaperIds:project && data?.view==="papers" ? window.SciResearch.library?.visiblePaperIds?.() : undefined,
      note:note?.id || "",task:task?.id || "",meeting:meeting?.id || params.get("session") || "", title:title || "",
      page:paper?.page || 0, quote:paper?.quote || noteExcerpt || meetingExcerpt, citation:paper?.citation || null};
  }
  function draftKey(c){
    if(c.projectGeneration===null)return "";
    const scope=[c.project,c.path,c.view,c.paper,c.note,c.task,c.meeting];
    if(c.projectGeneration)scope.push(c.projectGeneration);
    return "sci.shell.draft."+JSON.stringify(scope);
  }
  function roomPointer(c,id){
    const key="sci.shell.conversation."+c.project+(c.projectGeneration ? ":"+c.projectGeneration : "");
    try{
      if(id===undefined)return localStorage.getItem(key);
      if(id)localStorage.setItem(key,id);else localStorage.removeItem(key);
    } catch{}
  }
  function rememberDraft(){
    if(key)storage.set(key,node("rail-prompt").value ? JSON.stringify({value:node("rail-prompt").value,context:draftContext || context}):"");
  }
  function status(message,retry=false){node("rail-status").textContent=message || "";node("rail-retry").hidden=!retry;}
  function button(label,action) {
    const btn=document.createElement("button");btn.type="button";btn.textContent=label;
    btn.onclick=()=>Promise.resolve().then(action).catch(e=>status(e.message));
    return btn;
  }
  function anchor(label,href){const a=document.createElement("a");a.textContent=label;a.href=href;return a;}
  function routeLink(c,id){return window.SciStationNav.route("/research",{project:c.project,view:id});}
  function mode(){
    const state=layout.state;
    if(!state || window.SciStationNav.isSettings?.(new URL(location.href)))return "hidden";
    const active = requestedMode || (state.panelPinned ? state.mode : "hidden");
    return active === "ai" && !window.SciStationNav.aiAvailable(context?.project) ? "hidden" : active;
  }
  function loadProject(id) {
    if(projectRecords.has(id)) return;
    const lookup={};
    projectRecords.set(id,lookup);
    req("/api/research/projects/"+encodeURIComponent(id)).then(item=>{
      const version=item?.conversationGeneration ?? 0;
      if(item?.id!==id || !Number.isSafeInteger(version) || version<0) throw Error("Invalid project record");
      lookup.item=item;
    }).catch(()=>{lookup.failed=true;}).finally(()=>{
      if(context?.project===id && projectRecords.get(id)===lookup)update();
    });
  }
  function update() {
    const next=contextOf(), nextKey=draftKey(next);
    const route=panelRoute();
    if(requestedRoute!==route){requestedMode=null;requestedRoute=route;returnFocus=null;}
    if(next.projectGeneration===null)loadProject(next.project);
    const changedScope=context?.project!==next.project || context.projectGeneration!==next.projectGeneration;
    if(nextKey!==key){
      rememberDraft(); key=nextKey;draftContext=null;node("rail-prompt").value="";
      try{const old=key && JSON.parse(storage.get(key));if(old?.context?.project===next.project){node("rail-prompt").value=old.value;draftContext={...old.context,projectGeneration:next.projectGeneration};}}catch{}
    }
    context=next;
    if(changedScope){generation++;clearTimeout(poll);room=null;busy=false;runLookup="";catalogScope="";moduleEnabled=false;status("");}
    const active=mode(), nativeInspector=reader() && active==="inspector";
    const {body}=document, rail=node("context-rail"), divider=node("shell-divider");
    body.dataset.railMode=active;
    rail.hidden=active==="hidden" || nativeInspector;
    divider.hidden=active==="hidden" || narrow.matches;
    const lower=active==="ai"?240:200, upper=active==="ai"?640:560;
    const width=Math.min(upper,Math.max(lower,layout.state?.width || 360));
    body.style.setProperty("--shell-panel-width",width+"px");
    divider.setAttribute("aria-valuemin",String(lower));divider.setAttribute("aria-valuemax",String(upper));divider.setAttribute("aria-valuenow",String(width));
    node("shell-assist").setAttribute("aria-pressed",String(active==="ai"));
    node("shell-assist").hidden = !window.SciStationNav.aiAvailable(next.project);
    node("shell-assist").disabled = !layout.state || node("shell-assist").hidden;
    const pinned=Boolean(layout.state?.panelPinned);
    for(const id of ["shell-pin","reader-pin"]){
      const pin=node(id);if(!pin)continue;
      pin.hidden=active==="hidden";
      pin.setAttribute("aria-pressed",String(pinned));
      pin.setAttribute("aria-label",pinned?text("取消固定侧栏","Unpin panel"):text("固定侧栏","Pin panel"));
      pin.title=pin.getAttribute("aria-label");
    }
    if(reader()){
      node("reader-inspector").hidden=!nativeInspector;
      node("reader-inspect").disabled=!layout.state;
      node("reader-inspect").setAttribute("aria-expanded",String(nativeInspector));
    }
    for(const detail of document.querySelectorAll("[data-inspect-object]")){
      detail.setAttribute("aria-pressed",String(active==="inspector" && context[detail.dataset.inspectObject]===detail.dataset.id));
    }
    node("rail-title").textContent=active==="ai"?"AI":text("详情","Details");
    node("rail-context").textContent=[context.projectName || context.project,context.title,context.page?text("第 "+context.page+" 页","Page "+context.page):""].filter(Boolean).join(" · ");
    node("rail-inspect").hidden=active!=="inspector";
    node("rail-ai").hidden=active!=="ai";
    if(active==="inspector" && !nativeInspector)drawInspector();
    if(active==="ai"){
      drawAI();
      if(next.projectGeneration===null) {
        const failed=projectRecords.get(next.project)?.failed;
        status(failed ? text("无法读取项目信息。","Could not load the project.") : text("正在读取项目信息…","Loading project…"),failed);
      } else loadScope();
    }
  }
  function drawInspector() {
    const c=context, items=[];
    if(c.facts.length){
      const facts=document.createElement("dl");
      for(const [label,value] of c.facts){const term=document.createElement("dt"),detail=document.createElement("dd");term.textContent=label;detail.textContent=value;facts.append(term,detail);}
      items.push(facts);
    }
    if(c.paper) {
      items.push(anchor(text("打开阅读器","Open reader"),window.SciStationNav.route("/reader",{project:c.project,paper:c.paper})));
      items.push(button(text("文献元数据","Paper metadata"),()=>window.SciResearch.formAction("edit-paper",c.paper)));
    } else if(c.note) {
      if(c.quote){
        const preview=document.createElement("p");
        preview.className="rail-note-preview";
        preview.textContent=c.quote.replace(/^---\n[\s\S]*?\n---(?:\n|$)/,"").trim().slice(0,320);
        if(preview.textContent)items.push(preview);
      }
      items.push(button(text("打开知识笔记","Open Wiki page"),()=>window.SciResearch.formAction("read-note",c.note)));
    } else if(c.task) {
      items.push(button(text("打开任务","Open task"),()=>window.SciResearch.formAction("edit-task",c.task)));
    }
    if(window.SciStationNav.aiAvailable(c.project))items.push(button(text("询问当前视图","Ask about this view"),()=>showMode("ai")));
    if(!c.paper && !c.note && !c.task){
      items.push(button(text("刷新当前视图","Refresh view"),()=>window.SciResearch?.refresh?.() ?? location.reload()));
      if(c.project)items.push(anchor(text("项目概览","Project overview"),routeLink(c,"overview")));
      if(c.path==="/research" && (c.view==="projects" || c.project))items.push(button(text("新建项目","New project"),()=>window.SciStationNav.command("newProject")));
      if(c.view==="tasks")items.push(anchor(text("全部任务","All tasks"),"/research?view=tasks"));
      if(document.body.dataset.nativeWorkspace !== undefined)items.push(button(text("在 Finder 中显示工作区","Reveal workspace"),()=>window.SciStationNav.command("revealWorkspace")));
    }
    node("rail-inspect").replaceChildren(...items);
  }
  function drawAI() {
    const c=draftContext || context;
    const hint=node("rail-excerpt");hint.hidden=!c.quote;hint.textContent=c.quote;
    const quick=[
      [text("提问","Ask"),text("请基于当前视图回答我的问题。","Answer my question about this view.")],
      [text("解释","Explain"),text("请解释所选内容并指出关键点。","Explain the selection and identify its key points.")],
      [text("总结","Summarize"),text("请总结所选内容。","Summarize the selection.")],
      [text("起草待办","Draft task"),text("请依据所选内容起草待办，供我审阅。","Draft a task from the selection for review.")]
    ];
    node("rail-actions").replaceChildren(...quick.map(([label,prompt],i)=>{
      const b=button(label,()=>{
        draftContext={...context};
        node("rail-prompt").value=prompt;rememberDraft();drawAI();node("rail-prompt").focus();
        if(i===1 && node("rail-model").value && !busy)return send();
      });
      b.disabled=busy || c.projectGeneration===null || (i>0 && !context.quote);return b;
    }));
    node("rail-prompt").disabled=c.projectGeneration===null;
    node("rail-send").disabled=busy || !moduleEnabled || (!room && !node("rail-model").value) || Boolean(room && (!["ready","partial"].includes(room.status) || room.lab_thread?.archived_at));
    node("rail-new").hidden=!room;node("rail-new").disabled=busy;
    node("rail-stop").hidden=room?.status!=="running";
    node("rail-lab").href=window.SciStationNav.route("/lab",{project:c.project,run:room?.id});
    node("rail-model").disabled=Boolean(room) || busy;
    node("rail-effort").disabled=Boolean(room) || busy;
    const turns=[];
    if(room?.topic){const first=document.createElement("p");first.textContent=room.topic;turns.push(first);}
    for(const round of room?.rounds || []) {
      if(round.note){const p=document.createElement("p");p.textContent=round.note;turns.push(p);}
      for(const turn of round.turns || []){
        if(!turn.text && !turn.error)continue;
        const block=document.createElement("article");
        const h=document.createElement("strong");h.textContent=turn.model_label || turn.model || "AI";
        const answer=document.createElement("div");
        if(window.SciMarkdown && turn.text)window.SciMarkdown.render(answer,turn.text,{cache:turn.status!=="running"});
        else answer.textContent=turn.error || turn.text;
        block.append(h,answer);
        const cited=new Set(Array.from((turn.text || "").matchAll(/\[(S[1-9][0-9]*)\]/g),m=>m[1]));
        for(const [index,material] of (room.materials || []).entries()) {
          if((material.added_round || 0)>round.number || !cited.has("S"+(index+1))) continue;
          const source=window.SciLabRun.recordedSource(material,c.project,index);
          if(source)block.append(anchor(source.id+" · "+source.title+" · "+source.label,source.href));
        }
        turns.push(block);
      }
    }
    window.SciStationReadReview?.update(node("rail-read-review"), room);
    node("rail-transcript").replaceChildren(...turns);
  }
  async function loadScope() {
    const c=context, project=c.project,id=project || "@global",ticket=generation;
    if(c.projectGeneration===null)return;
    if(catalogScope===id)return;
    catalogScope=id;
    try {
      const config=await window.SciStationModules.load(project);
      if(ticket!==generation)return;
      moduleEnabled=window.SciStationModules.isEnabled(config,"ai-lab");
      if(!moduleEnabled){status(text("AI 实验室模块已停用。","AI Lab is disabled."));drawAI();return;}
      const saved=roomPointer(c);
      if(saved)await readRoom(saved,ticket);
      if(!models.length){
        const catalog=await req("/api/studio/models");
        if(ticket!==generation)return;
        models=catalog.models || [];
        node("rail-model").replaceChildren(...models.map(m=>new Option(m.label || m.id,m.id)));
        if(models.some(m=>m.id===catalog.default_model))node("rail-model").value=catalog.default_model;
        effortOptions();
      }
      if(!models.length)status(text("模型目录为空，请检查 AI 实验室设置。","No models are available. Check AI Lab settings."));
      drawAI();
    } catch(err){if(ticket===generation){status(err.message,true);catalogScope="";}}
  }
  function effortOptions() {
    const model=models.find(m=>m.id===node("rail-model").value);
    node("rail-effort").replaceChildren(...(model?.efforts || []).map(e=>new Option(e,e)));
    if(model?.efforts?.includes("auto"))node("rail-effort").value="auto";
  }
  async function readRoom(id,ticket) {
    runLookup=id;
    let snapshot;
    try{snapshot=await req("/api/studio/sessions/"+encodeURIComponent(id));}
    catch(error){if(error.status===404 && ticket===generation){roomPointer(context,"");room=null;drawAI();return;}throw error;}
    if(ticket!==generation || runLookup!==id)return;
    const runs=await loadRun();
    if(ticket!==generation || runLookup!==id)return;
    if(!runs.ownsRun(snapshot,projectOf(context))){
      roomPointer(context,"");runLookup="";room=null;
      status(text("已清除不属于当前项目的会话位置。","Cleared a conversation pointer belonging to another project."));drawAI();return;
    }
    room=snapshot;drawAI();
    clearTimeout(poll);
    if(room.status==="running")poll=setTimeout(()=>readRoom(id,ticket).catch(err=>{if(ticket===generation)status(err.message);}),1000);
  }
  async function send() {
    const c=draftContext || context, prompt=node("rail-prompt").value.trim(), ticket=generation, submittedKey=key;
    if(!prompt || busy || !moduleEnabled || !window.SciStationNav.aiAvailable(c.project) || c.project!==context.project ||
        c.projectGeneration!==context.projectGeneration || room && (!["ready","partial"].includes(room.status) || room.lab_thread?.archived_at))return;
    const model=node("rail-model").value, effort=node("rail-effort").value;
    if(!room && (!model || !effort))return;
    busy=true;status("");drawAI();
    try {
      const runs=await loadRun();
      if(ticket!==generation)return;
      const project=projectOf(c);
      let citation=c.citation;
      if(c.note && c.quote && c.project) {
        const preview=await req("/api/research/lab/sources/preview","POST",{projectId:c.project,location:{kind:"note",id:c.note}});
        const offset=preview.text.indexOf(c.quote);
        if(offset<0)throw Error(text("笔记已更新，请重新选择摘录。","The note changed. Select its excerpt again."));
        citation={kind:"note",id:c.note,hash:preview.hash,quote:c.quote,offset:Array.from(preview.text.slice(0,offset)).length};
      }
      if(c.project && c.paper && c.quote && !citation)throw Error(text("无法核对选段位置，请在阅读器中重新选择。","Select the passage again to verify its location."));
      const citations=c.project && citation ? [citation]:[];
      const prepared=await runs.prepareQuestionSources(req,project,"",prompt,citations,{
        currentPaper:c.paper || runs.paperFromRun(room,c.project),
        visiblePaperIds:c.visiblePaperIds
      });
      if(!prepared || ticket!==generation)return;
      const message=[prompt,c.title,c.page?text("第 "+c.page+" 页","Page "+c.page):"",c.quote && !citations.length?c.quote:""].filter(Boolean).join("\n\n");
      let run=room;
      const followUp=Boolean(run);
      if(!run){
        run=await runs.createSingle(req,project,message,{model,effort},"review",prepared || []);
        if(ticket!==generation)return;
        roomPointer(c,run.id);
        room=run;
      }
      const started=await runs.advance(req,run,followUp?message:"",followUp?prepared || []:[]);
      if(ticket!==generation)return;
      room=started;
      if(key===submittedKey && node("rail-prompt").value.trim()===prompt){node("rail-prompt").value="";draftContext=null;rememberDraft();}
      else if(key!==submittedKey)storage.set(submittedKey,"");
      await readRoom(run.id,ticket);
    } catch(err){if(ticket===generation)status(err.message);}
    finally{if(ticket===generation){busy=false;drawAI();}}
  }
  function showMode(next,trigger=document.activeElement){
    if(!layout.state || window.SciStationNav.isSettings?.(new URL(location.href)))return;
    if(next === "ai" && !window.SciStationNav.aiAvailable(context?.project))return;
    const previous=mode();
    if(next!=="hidden" && trigger && !trigger.closest?.("#context-rail,#reader-inspector"))returnFocus=trigger;
    requestedRoute=panelRoute();
    requestedMode=next;
    if(next==="hidden")rememberDraft();
    update();
    if(next==="hidden" && previous!=="hidden"){
      const fallback=reader() && previous==="inspector"?node("reader-inspect"):node("shell-assist");
      (returnFocus?.isConnected?returnFocus:fallback)?.focus();
    }
    if(layout.state.panelPinned && (layout.state.mode!==next || next==="hidden")){
      return layout.save({mode:next,panelPinned:next!=="hidden"}).catch(()=>{});
    }
  }
  function toggle(next,trigger){return showMode(mode()===next ? "hidden" : next,trigger);}
  function closePanel(){return showMode("hidden");}
  function selectObject(kind,id,open=false){
    const close=open && mode()==="inspector" && context?.[kind]===id;
    selectedObject={route:location.href,[kind]:id,selection:selectionKey(paperSelection())};
    update();
    if(open){
      const trigger=Array.from(document.querySelectorAll("[data-inspect-object]")).find(el=>el.dataset.inspectObject===kind && el.dataset.id===id);
      return showMode(close?"hidden":"inspector",trigger);
    }
  }
  node("shell-assist").onclick=event=>toggle("ai",event?.currentTarget || node("shell-assist"));
  function pinPanel(){
    if(!layout.state || mode()==="hidden")return;
    requestedMode=mode();
    return layout.save({mode:requestedMode,panelPinned:!layout.state.panelPinned}).catch(()=>{});
  }
  node("shell-pin").onclick=pinPanel;
  if(node("rail-close"))node("rail-close").onclick=closePanel;
  node("rail-prompt").oninput=()=>{if(!draftContext)draftContext={...context};rememberDraft();};
  node("rail-prompt").onkeydown=e=>{if(e.key==="Enter" && (e.metaKey || e.ctrlKey)){e.preventDefault();send();}};
  node("rail-model").onchange=()=>{effortOptions();drawAI();};
  node("rail-send").onclick=send;
  node("rail-retry").onclick=()=>{
    if(context.projectGeneration===null) {
      projectRecords.delete(context.project);
      update();
    } else {catalogScope="";status("");loadScope();}
  };
  node("rail-new").onclick=()=>{clearTimeout(poll);runLookup="";room=null;roomPointer(context,"");status("");drawAI();};
  node("rail-stop").onclick=async()=>{
    if(!room || busy)return;
    const id=room.id,ticket=generation;
    try{await req("/api/studio/sessions/"+encodeURIComponent(id)+"/cancel","POST",{});await readRoom(id,ticket);}
    catch(err){if(ticket===generation)status(err.message);}
  };
  const divider=node("shell-divider");
  const clamp=value=>Math.round(Math.max(Number(divider.getAttribute("aria-valuemin")),Math.min(Number(divider.getAttribute("aria-valuemax")),value)));
  function commitWidth(value){layout.save({width:clamp(value)}).catch(()=>{});}
  divider.onpointerdown=e=>{if(e.button!==0)return;divider.setPointerCapture(e.pointerId);};
  divider.onpointermove=e=>{if(divider.hasPointerCapture(e.pointerId))document.body.style.setProperty("--shell-panel-width",clamp(innerWidth-e.clientX)+"px");};
  divider.onpointerup=e=>{if(divider.hasPointerCapture(e.pointerId)){divider.releasePointerCapture(e.pointerId);commitWidth(innerWidth-e.clientX);}};
  divider.onkeydown=e=>{if(!["ArrowLeft","ArrowRight"].includes(e.key))return;e.preventDefault();commitWidth(Number(divider.getAttribute("aria-valuenow"))+(e.key==="ArrowLeft"?16:-16));};
  window.addEventListener("scistation:command",e=>{
    if(e.detail!=="inspector")return;
    if(reader())return;
    if(context?.view==="papers")return;
    e.preventDefault();toggle("inspector");
  });
  window.SciContextRail={update,selectObject,show:showMode,toggle,close:closePanel,pin:pinPanel};
  window.addEventListener("sci:project-conversations-reset",({detail})=>{
    projectRecords.delete(detail.id);
    if(context?.project!==detail.id)return;
    generation++;clearTimeout(poll);room=null;busy=false;moduleEnabled=false;
    key="";draftContext=null;node("rail-prompt").value="";
  });
  narrow.addEventListener("change",update);
  window.addEventListener("sci:shell-layout",update);window.addEventListener("sci:language",update);
  document.addEventListener("DOMContentLoaded",()=>{update();new MutationObserver(update).observe(document.querySelector("title"),{childList:true});});
})();
