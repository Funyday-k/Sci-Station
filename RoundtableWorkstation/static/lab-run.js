(() => {
  "use strict";
  const base = "/api/research/lab/sources/";
  const studio = "/api/studio/";
  const chars = text => Array.from(text);
  const states = {partial:"本轮未完成",error:"未完成",running:"运行中", ready:"就绪", closed:"已归档", done:"完成", failed:"失败", cancelled:"已取消", interrupted:"已中断", pending:"等待", skipped:"已跳过"};

  // Textarea selection is in UTF-16 units. Store character offsets for Go.
  function selectedCitation(source, start, end) {
    const exact = source.text.slice(start, end);
    const quote = exact.trim();
    if (!quote || chars(quote).length > 1000) throw Error("请在预览中选择 1 至 1,000 字。");
    return {kind:source.kind, id:source.id, page:source.page || 0, hash:source.hash, quote,
      offset:(source.offset || 0) + chars(source.text.slice(0,start) + exact.slice(0,exact.length-exact.trimStart().length)).length};
  }
  function ownsRun(session, project) {
    if(!project || session?.seats?.length !== 1) return false;
    return project.global ? !session.project_id && !session.project : session.project_id === project.id;
  }

  function mount({req,tell,form,skillForRun}) {
    const $ = id => document.getElementById(id);
    let project = null, records = [], existingTasks=[], preview = null, selected = [], generation = 0;
    let enabledModules=null;
    const recentRooms=new Map();
    let visibleRoom=null, searchState=null;
    let history = [], active = "", pollTimer = 0, models = [], previewSequence = 0;
    function bind(id, fn) {
      $(id).addEventListener("click", async () => {
        const button=$(id), started=generation;
        button.disabled=true; tell("");
        try { await fn(); } catch(error) { if(started===generation) tell(error.message); }
        finally { button.disabled=false; }
      });
    }
    function lookAt(id) {
      if(active!==id) {visibleRoom=null; $("lab-reply").value="";}
      active=id;
      const url = new URL(location.href);
      if(id) url.searchParams.set("run",id); else url.searchParams.delete("run");
      window.history.replaceState(null,"",url);
    }
    function displayHistory() {
      $("lab-history").replaceChildren(new Option("选择会话",""),...history.map(s=>new Option(s.title || s.topic.split("\n")[0],s.id)));
      $("lab-history").value=active;
    }
    function chooseRecord(reset=true) {
      previewSequence++;
      if(reset) resetSearch();
      preview=null;
      $("local-window").hidden=true;
      const chosen=records[$("local-record").value];$("local-page-label").hidden=chosen?.kind!=="paper";
      $("body-controls").hidden=chosen?.kind!=="paper-markdown";
      $("body-line").value="1";
      if(chosen?.kind==="paper-markdown")$("body-manage").href="/tools?"+new URLSearchParams({tab:"convert",paper:chosen.id,project:project.id});
    }
    function displaySelected() {
      const rows=selected.map((item,index)=>{
        const li=document.createElement("li"), remove=document.createElement("button");
        li.textContent=item.title+(item.citation.page?" · 第 "+item.citation.page+" 页":"")+" · "+chars(item.citation.quote).slice(0,70).join("");
        remove.type="button"; remove.textContent="移除"; remove.onclick=()=>{selected.splice(index,1);displaySelected();}; li.append(remove);
        return li;
      });
      $("local-list").replaceChildren(...rows);
    }
    async function selectProject(next, sessions) {
      const token=++generation, requested=new URL(location.href).searchParams.get("run");
      project=next; records=[];existingTasks=[]; selected=[]; clearTimeout(pollTimer); active=""; enabledModules=null;
      $("local-record").replaceChildren(); chooseRecord(); displaySelected();
      $("local-sources").disabled=!project; $("lab-result").hidden=true;
      history=[...recentRooms.values(),...sessions.filter(s=>!recentRooms.has(s.id))].filter(s=>ownsRun(s,project)); displayHistory();
      if(!project) {lookAt("");return;}
      if(history.some(s=>s.id===requested)) openRun(requested); else lookAt("");
      const prefix="/api/research/projects/"+encodeURIComponent(project.id)+"/";
      const config=await window.SciStationModules.load(project.id);
      if(generation!==token) return;
      enabledModules=config;
      const enabled = id=>window.SciStationModules.isEnabled(config,id);
      if(project.global){ $("local-sources").disabled=true; return; }
      $("local-sources").disabled=!enabled("ai-lab");
      const [papers,notes,materials,tasks]=await Promise.all([
        (enabled("paper-library")||enabled("pdf-reader"))?req("/api/research/papers?project="+encodeURIComponent(project.id)):[],
        enabled("wiki")?req(prefix+"notes"):[], enabled("materials")?req(prefix+"materials"):[],enabled("tasks")?req(prefix+"tasks"):[]
      ]);
      if(generation!==token) return;
      existingTasks=tasks;
      if(visibleRoom && ownsRun(visibleRoom,project))renderRun(visibleRoom);
      records=[
        ...papers.filter(p=>p.has_pdf && enabled("pdf-reader")).map(p=>({kind:"paper",id:p.id,label:"论文 PDF · "+p.title})),
        ...papers.filter(()=>enabled("paper-library")).map(p=>({kind:"paper-markdown",id:p.id,missing:!p.markdown_source,
          label:"论文 Markdown · "+p.title+(p.markdown_source?"":"（待导入或转换）")})),
        ...notes.map(n=>({kind:"note",id:n.id,label:"笔记 · "+n.title})),
        ...materials.filter(m=>m.mediaType?.startsWith("text/plain")).map(m=>({kind:"material",id:m.id,label:"材料 · "+m.name}))
      ];
      $("local-record").replaceChildren(...records.map((x,i)=>new Option(x.label,String(i))));
      chooseRecord();
    }
    async function showPreview(offset=0,line=0) {
      const record=records[$("local-record").value], token=++previewSequence;
      if(!record || !project) throw Error("请先选择项目原文。");
      const page=record.kind==="paper"?Number($("local-page").value):0;
      preview=null; $("local-window").hidden=true;
      const data=await req(base+"preview","POST",{projectId:project.id,line,location:{kind:record.kind,id:record.id,page,offset}});
      if(token!==previewSequence) return;
      preview=data;
      const md=data.kind==="paper-markdown";
      $("body-location").hidden=!md;$("body-sections-label").hidden=!md||!data.sections?.length;
      if(md) {
        $("body-line").value=String(data.line);
        $("body-location").textContent="正文版本 "+data.revision+" · 第 "+data.line+" 行"+(data.heading?" · "+data.heading:"");
        $("body-sections").replaceChildren(new Option("选择章节",""),...(data.sections||[]).map(h=>new Option("L"+h.line+" · "+h.heading,String(h.line))));
      }
      $("local-text").value=data.text; $("local-window").hidden=false;
      $("local-prev").hidden=!offset; $("local-next").hidden=!data.more;
    }
    function resetSearch() {
      searchState?.controller?.abort();
      searchState=null;
      $("local-hits").replaceChildren();
      $("local-search-more").hidden=true;
      $("local-search-stop").hidden=true;
    }
    function addHit(state,record,hit) {
      const li=document.createElement("li"),button=document.createElement("button");
      button.type="button";
      button.textContent=record.label+(hit.page?" · 第 "+hit.page+" 页":"")+" · "+hit.text;
      button.onclick=()=>{
        if(searchState!==state) return;
        $("local-record").value=String(records.indexOf(record));
        $("local-page").value=String(hit.page || 1);
        chooseRecord(false);
        showPreview(Math.max(0,hit.offset-35)).catch(e=>tell(e.message));
      };
      li.append(button);$("local-hits").append(li);
    }
    async function findSources(more=false) {
      if(!more) {
        resetSearch();
        const query=$("local-query").value.trim();
        if(!query || !project?.id) throw Error("请选择项目并输入要检索的词句。");
        const scope=$("local-search-scope").value;
        const items=scope==="project"?records.filter(r=>!r.missing):[records[$("local-record").value]].filter(Boolean);
        searchState={query,items,index:0,failed:0,hits:0,limited:false};
      }
      const state=searchState;
      if(!state || state.controller) return;
      state.controller=new AbortController();
      const end=Math.min(state.items.length,state.index+6);
      $("local-search-more").hidden=true;$("local-search-stop").hidden=false;
      try {
        while(state.index<end) {
          const record=state.items[state.index];
          const location={kind:record.kind,id:record.id};
          try {
            const data=await req(base+"search","POST",{projectId:project.id,query:state.query,location},state.controller.signal);
            if(searchState!==state || state.controller.signal.aborted) return;
            for(const hit of data.items || []){addHit(state,record,hit);state.hits++;}
            state.limited ||= data.limited;
          } catch(error) {
            if(searchState!==state || state.controller.signal.aborted) return;
            state.failed++;
            const li=document.createElement("li");li.textContent=record.label+" · "+error.message;$("local-hits").append(li);
          }
          state.index++;
        }
      } finally {
        if(searchState===state) {
          state.controller=null;
          $("local-search-stop").hidden=true;$("local-search-more").hidden=state.index>=state.items.length;
          tell("已检索 "+state.index+" / "+state.items.length+" 份来源，匹配 "+state.hits+" 处。"+
            (state.failed?" "+state.failed+" 份未能读取。":"")+(state.limited?" 单份来源最多显示 12 处。":""));
        }
      }
    }
    function addSelection() {
      if(!preview || selected.length>=4) throw Error("每次最多选择四段原文。");
      const area=$("local-text"), citation=selectedCitation(preview,area.selectionStart,area.selectionEnd);
      if(selected.some(x=>x.citation.kind===citation.kind && x.citation.id===citation.id && x.citation.page===citation.page && x.citation.offset===citation.offset))
        throw Error("此选段已加入。");
      selected.push({title:preview.title,citation}); displaySelected();
    }
    function consumeSelection(used) {
      selected=selected.filter(item=>!used.includes(item));
      displaySelected();
    }
    async function prepare(workflow,projectId) {
      if(!project || project.id!==projectId) throw Error("请先选择科研项目。");
      const token=generation;
      const result=await req(base+"prepare","POST",{workflow,projectId,scope:project.global?"global":"",citations:selected.map(x=>x.citation)});
      if(token!==generation) throw Error("当前项目已改变。");
      return result;
    }
    function effortOptions() {
      const model=models.find(m=>m.id===$("lab-model").value);
      $("lab-effort").replaceChildren(...(model?.efforts || []).map(e=>new Option(e,e)));
      if(model?.efforts.includes("auto")) $("lab-effort").value="auto";
    }
    async function loadModels() {
      const catalog=await req(studio+"models");
      models=catalog.models||[];
      $("lab-model").replaceChildren(...models.map(m=>new Option(m.label||m.id,m.id)));
      if(models.some(m=>m.id===catalog.default_model)) $("lab-model").value=catalog.default_model;
      effortOptions(); if(!models.length) throw Error("模型目录为空，请检查圆桌设置。");
    }
    function sessionURL(id) {return studio+"sessions/"+encodeURIComponent(id);}
    async function start() {
      const data=form(), pid=project?.id, token=generation;
      if(data.seats!==1) throw Error("此模板使用多个席位。请打开会议草稿，或将席位数改为 1。");
      if(!project) throw Error("请选择科研项目或全局会话。");
      if(!window.SciStationModules.isEnabled(enabledModules,"ai-lab")) throw Error("AI 实验室模块未启用或仍在加载。");
      const member={model:$("lab-model").value,effort:$("lab-effort").value};
      if(!member.model || !member.effort) throw Error("请先读取模型目录并选择模型。");
      const scope=project.global?"global":"";
      const skill=await skillForRun(pid);
      if(token!==generation) return;
      const topic=window.ScienceLabHandoff.compose({...data,scope,projectId:pid,skill});
      const used=selected.slice();
      const materials=await prepare(data.workflow,pid);
      if(token!==generation) return;
      // Creating the session records a recoverable ID before the first model call.
      const room=await req(studio+"sessions","POST",{project_id:pid, scope, topic, members:[member],preset:data.mode,
        material_ids:materials.map(m=>m.id),start_agenda_draft:false});
      if(token!==generation) return;
      consumeSelection(used);
      recentRooms.set(room.id,room);history=[room,...history]; lookAt(room.id); displayHistory(); renderRun(room);
      try {
        const result=await req(sessionURL(room.id)+"/run","POST",{expected_round:0,allow_edits:false});
        if(token===generation && active===room.id) {renderRun(result); schedule(room.id);}
      } catch(error) {
        throw Error("会话已保存，可在圆桌中重试。"+error.message);
      }
    }
    function displaySources(room) {
      const entries=[];
      for(const material of room.materials || []) {
        const text=material.excerpt || "", split=text.indexOf("\n\n"), headerEnd=text.indexOf("\n");
        if(!text.startsWith("Sci-Station · 论文原文摘录 v1\n") && !text.startsWith("Sci-Station · 项目原文摘录 v1\n")) continue;
        if(split<0) continue;
        let ref;
        try {ref=JSON.parse(text.slice(headerEnd+1,split));} catch {continue;}
        if(ref.projectId!==project?.id) continue;
        const title=document.createElement("h3"), quote=document.createElement("blockquote");
        title.textContent=ref.title || material.name; quote.textContent=text.slice(split+2);
        entries.push(title,quote);
        if(ref.paperId && Number.isInteger(ref.page)) {
          const query=new URLSearchParams({project:ref.projectId,paper:ref.paperId,page:ref.page,fingerprint:ref.fingerprint,quote:quote.textContent});
          if(Number.isInteger(ref.selectionStart) && Number.isInteger(ref.selectionEnd)) {
            query.set("start",ref.selectionStart);query.set("end",ref.selectionEnd);
          }
          if(ref.ocr)query.set("ocr","1");
          const link=document.createElement("a");link.href="/reader?"+query;link.textContent="打开原文第 "+ref.page+" 页";entries.push(link);
        } else if ((["note","material","paper-markdown"].includes(ref.kind)) && Number.isSafeInteger(ref.offset)) {
          const evidence={sourceHash:ref.sha256, source:{projectId:ref.projectId,kind:ref.kind,id:ref.id,
            offset:ref.offset,end:ref.end ?? ref.offset+Array.from(quote.textContent).length}};
          const link=document.createElement("a");
          link.href=window.SciEvidence.href(ref.projectId,evidence);
          link.textContent=window.SciEvidence.label(evidence);
          entries.push(link);
        }
      }
      $("lab-citation-items").replaceChildren(...entries);$("lab-citations").hidden=!entries.length;
    }
    function renderRun(room) {
      if(!ownsRun(room,project) || active!==room.id) return;
      visibleRoom=room;displaySources(room);
      if(recentRooms.has(room.id)) recentRooms.set(room.id,room);
      const rounds=room.rounds||[];
      $("lab-followup").hidden=!["ready","partial"].includes(room.status);
      $("lab-result").hidden=false;
      $("lab-run-state").textContent=(room.title||room.topic.split("\n")[0])+" · "+(states[room.status]||room.status);
      $("lab-stop").hidden=room.status!=="running" || room.cancel_requested;
      $("lab-open").href="/studio?"+new URLSearchParams(project.global?{session:room.id}:{project:project.id,session:room.id});
      const turns=[];
      for(const round of rounds) for(const turn of round.turns||[]) {
        const heading=document.createElement("h3");
        heading.textContent="第 "+round.number+" 轮 · "+(turn.model_label||turn.model||turn.seat)+" · "+(states[turn.status]||turn.status);
        const structured=turn.status==="done" && window.SciLabArtifacts?.projectRows(room.topic,turn.text,room.materials||[],round.number,existingTasks,project.id);
        const body=document.createElement(turn.error ? "p" : "div");
        if(turn.error) body.textContent=turn.error;
        else if(turn.text) {
          window.SciMarkdown.render(body,structured && !structured.error ? structured.narrative : turn.text,{headingShift:3,cache:turn.status!=="running"});
          heading.append(window.SciMarkdown.copyButton(turn.text));
        }
        turns.push(heading,body);
        if(structured) turns.push(window.SciLabArtifacts.render(structured));
        if (!project.global && room.status !== "running" && turn.status === "done" && !turn.error && turn.text?.trim()) {
          turns.push(window.SciLabEvidence.inspection({room: room.id, project: project.id, output: "round-"+round.number+"-"+turn.seat, req}));
        }
      }
      $("lab-turns").replaceChildren(...turns);
    }
    function schedule(id) {clearTimeout(pollTimer);pollTimer=setTimeout(()=>openRun(id),1000);}
    async function openRun(id) {
      clearTimeout(pollTimer); lookAt(id); $("lab-history").value=id;
      if(!id) {$("lab-result").hidden=true;return;}
      const token=generation;
      try {
        const room=await req(sessionURL(id));
        if(token!==generation || active!==id) return;
        if(!ownsRun(room,project)) {lookAt(""); $("lab-result").hidden=true;throw Error("此会话不属于当前项目。");}
        renderRun(room); if(room.status==="running") schedule(id);
      } catch(error) {if(token===generation && active===id)tell(error.message);}
    }
    async function ask() {
      const room=visibleRoom, id=room?.id, pid=project?.id, token=generation;
      const note=$("lab-reply").value.trim();
      if(!ownsRun(room,project) || id!==active || !["ready","partial"].includes(room.status)) throw Error("请先打开可继续的会话。");
      if(!note) throw Error("请填写追问。");
      const used=selected.slice();
      const materials=await prepare("",pid);
      if(token!==generation || id!==active) return;
      const next=await req(sessionURL(id)+"/run","POST",{note,expected_round:room.rounds.length,allow_edits:false,material_ids:materials.map(m=>m.id)});
      if(token===generation && id===active) {
        consumeSelection(used);
        if($("lab-reply").value.trim()===note) $("lab-reply").value="";
        renderRun(next);schedule(id);
      }
    }
    async function exportReplay() {
      const room=visibleRoom;
      if(!ownsRun(room,project)) throw Error("请先打开要导出的会话。");
      const scope=project.global?{scope:"global"}:{project:project.id};
      const url="/api/research/lab/replay/"+encodeURIComponent(room.id)+"?"+new URLSearchParams(scope);
      const result=await req(url,"POST",{});
      if(result.browser_download) {
        const link=document.createElement("a");
        link.href=url;link.download="sci-station-run-"+room.id+".zip";document.body.append(link);link.click();link.remove();
      } else if(result.saved) tell("已保存脱敏诊断包。");
    }
    async function cancel() {
      const id=active, token=generation;
      if(!history.some(s=>s.id===id && ownsRun(s,project))) return;
      const room=await req(sessionURL(id)+"/cancel","POST",{});
      if(token===generation && id===active) {renderRun(room);schedule(id);}
    }
    $("local-record").onchange=()=>{$("local-page").value="1";chooseRecord();};
    $("local-page").oninput=chooseRecord;
    $("lab-model").onchange=effortOptions;
    $("lab-history").onchange=()=>openRun($("lab-history").value);
    $("local-query").oninput=resetSearch; $("local-search-scope").onchange=resetSearch;
    bind("local-find",()=>findSources());bind("local-search-more",()=>findSources(true));
    $("local-search-stop").onclick=()=>searchState?.controller?.abort();
     $("body-sections").onchange=()=>{if($("body-sections").value)showPreview(0,Number($("body-sections").value)).catch(e=>tell(e.message));};
    bind("local-preview",()=>showPreview(0,records[$("local-record").value]?.kind==="paper-markdown"?Number($("body-line").value):0)); bind("local-add",addSelection);
    bind("local-prev",()=>showPreview(Math.max(0,(preview?.offset || 0)-4000)));
    bind("local-next",()=>showPreview((preview?.offset || 0)+chars(preview?.text || "").length));
    bind("lab-models",loadModels); bind("lab-start",start); bind("lab-stop",cancel); bind("lab-resume",ask); bind("lab-export",exportReplay);
    return {selectProject, hasDraft:()=>selected.length>0 || !!$("lab-reply").value.trim(), prepareHandoff:(_,pid)=>selected.length?prepare("",pid):Promise.resolve([])};
  }
  const api={mount, selectedCitation, ownsRun};
  if(typeof module==="object" && module.exports) module.exports=api;
  else window.SciLabRun=api;
})();
