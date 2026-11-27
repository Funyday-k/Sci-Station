(() => {
  "use strict";
  const base = "/api/research/lab/sources/";
  const studio = "/api/studio/";
  const chars = text => Array.from(text);
  const text=(zh,en)=>globalThis.window?.SciStationI18n?.text(zh,en) ?? zh;
  const states = {partial:["未完成","Incomplete"],error:["失败","Failed"],running:["运行中","Running"],ready:["就绪","Ready"],closed:["已结束","Closed"],done:["完成","Complete"],failed:["失败","Failed"],cancelled:["已取消","Cancelled"],interrupted:["已中断","Interrupted"],pending:["等待","Waiting"],skipped:["已跳过","Skipped"]};
  const statusText = state => states[state] ? text(...states[state]) : state;
  const contextMarkers = ["\n\n用户选用的项目技能 · ","\n\n项目图谱资料（供核对）","\n\n外部资源摘录（供核对）"];
  function messageText(value, initial=false) {
    const message = value || "";
    const header = initial && message.startsWith("科研工作流 · ");
    const marker = "\n\n研究问题\n";
    const first = header ? message.indexOf(marker) : -1;
    const body = first >= 0 ? message.slice(first + marker.length) : message;
    const end = contextMarkers.map(mark=>body.indexOf(mark)).filter(i=>i>=0);
    return (end.length ? body.slice(0,Math.min(...end)) : body).trim();
  }

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

  function createSingle(req, project, topic, member, preset, materials) {
    return req(studio+"sessions","POST",{project_id:project.id,scope:project.global?"global":"",topic,
      members:[member],preset,material_ids:materials.map(m=>m.id),start_agenda_draft:false});
  }
  function advance(req, room, note, materials=[]) {
    const body={expected_round:room.rounds?.length || 0, allow_edits:false};
    if(note)body.note=note;
    if(materials.length)body.material_ids=materials.map(m=>m.id);
    return req(studio+"sessions/"+encodeURIComponent(room.id)+"/run","POST",body);
  }

  async function prepareQuestionSources(req, project, workflow, question, citations, options={}) {
    const request = {workflow,projectId:project.id,scope:project.global?"global":"",citations};
    if (question?.trim()) {
      const found = await req(base+"question","POST",{...request,question,
        currentPaper:options.currentPaper,visiblePaperIds:options.visiblePaperIds}) || [];
      if (found.length) {
        if (citations.length+found.length>4) throw Error("每次最多选择四段原文。请先移除不相关的选段。");
        const preview = found.map(source => [source.title,
          (source.heading?source.heading+" · ":"")+"L"+source.line+(source.endLine!==source.line?"–"+source.endLine:""),
          source.quote].join("\n")).join("\n\n");
        const confirm = options.confirm || globalThis.confirm;
        if (!confirm("发送问题，并将以下论文原文交给所选模型？\n\n"+preview)) return null;
        request.citations = citations.concat(found.map(({kind,id,offset,page,hash,quote})=>({kind,id,offset,page,hash,quote})));
      }
    }
    return req(base+"prepare","POST",request);
  }

  function recordedSource(material, project, index) {
    const text=material.excerpt || "", split=text.indexOf("\n\n"), headerEnd=text.indexOf("\n");
    if ((!text.startsWith("Sci-Station · 论文原文摘录 v1\n") && !text.startsWith("Sci-Station · 项目原文摘录 v1\n")) || split<0) return null;
    let ref;
    try {ref=JSON.parse(text.slice(headerEnd+1,split));} catch {return null;}
    if (ref.projectId!==project) return null;
    const id="S"+(index+1), title=ref.title || material.name, quote=text.slice(split+2);
    if (ref.paperId && Number.isInteger(ref.page)) {
      const query=new URLSearchParams({project,paper:ref.paperId,page:ref.page,fingerprint:ref.fingerprint,quote});
      if(Number.isInteger(ref.selectionStart) && Number.isInteger(ref.selectionEnd)) {
        query.set("start",ref.selectionStart);query.set("end",ref.selectionEnd);
      }
      if(ref.ocr)query.set("ocr","1");
      return {id,title,quote,paper:ref.paperId,href:"/reader?"+query,label:"打开原文第 "+ref.page+" 页"};
    }
    if (["note","material","paper-markdown"].includes(ref.kind) && Number.isSafeInteger(ref.offset)) {
      const evidence={sourceHash:ref.sha256, source:{projectId:project,kind:ref.kind,id:ref.id,
        offset:ref.offset,end:ref.end ?? ref.offset+chars(quote).length}};
      const where=ref.lineStart ? [ref.heading,"L"+ref.lineStart+(ref.lineEnd!==ref.lineStart?"–"+ref.lineEnd:"")].filter(Boolean).join(" · ") : "";
      return {id,title,quote,paper:ref.kind==="paper-markdown"?ref.id:"",
        href:window.SciEvidence.href(project,evidence),label:where? "打开原文 · "+where : window.SciEvidence.label(evidence)};
    }
    return null;
  }

  function paperFromRun(room, project) {
    const ids = new Set((room?.materials || []).map((m,i)=>recordedSource(m,project,i)?.paper).filter(Boolean));
    return ids.size===1 ? ids.values().next().value : "";
  }

  const threadTitle = room => room.lab_thread?.title || room.title || messageText(room.topic,true).split("\n")[0] || text("研究对话","Research chat");
  const threadDetails = room => [statusText(room.status), ...(room.members || []).map(item => item.label || item.model)].filter(Boolean).join(" · ");
  function matchingThreads(history, query, showArchived) {
    const term = query.trim().toLowerCase();
    return history.filter(room => (showArchived || !room.lab_thread?.archived_at)
      && [threadTitle(room), threadDetails(room)].some(value => value.toLowerCase().includes(term)));
  }
  const scopeQuery = project => new URLSearchParams(project.global ? {scope:"global"} : {project:project.id});
  function draftURL(project, id = "") {
    if (!project) return "";
    const query = scopeQuery(project);
    if (id) query.set("thread", id);
    return "/api/research/lab/draft?" + query;
  }

  function createDraft({req, input, status}) {
    const saved = new Map();
    let current = null;
    function notify(record, message) {
      record.message = message;
      if (current === record) status(message);
    }
    function flush(record = current) {
      if (!record) return Promise.resolve();
      clearTimeout(record.timer);
      const work = record.pending.catch(() => {}).then(async () => {
        if (record.text === record.confirmed) return;
        if (record.revision === null) throw Error("无法读取草稿版本");
        const value = record.text;
        const draft = await req(record.url, "PUT", {text:value, revision:record.revision});
        record.revision = draft.revision;
        record.confirmed = draft.text;
        if (record.text === value) notify(record, value ? "草稿已保存" : "");
      });
      record.pending = work;
      work.catch(error => notify(record, error.message + "。当前输入仍保留。"));
      return work;
    }
    function load(record) {
      notify(record, "正在读取草稿…");
      if (current === record) input.disabled = true;
      record.pending = req(record.url).then(draft => {
        record.text = record.confirmed = draft.text;
        record.revision = draft.revision;
        notify(record, draft.text ? "已恢复草稿" : "");
        if (current === record) { input.value = draft.text; input.disabled = false; }
      }).catch(error => {
        notify(record, error.message + "。点击保存草稿可重试读取。");
      });
      return record.pending;
    }
    function select(project, id = "") {
      const url = draftURL(project, id);
      if (url === current?.url && saved.has(url)) return current.pending;
      if (current) void flush(current);
      current = url && saved.get(url) || null;
      if (!url) {
        input.disabled = true; input.value = ""; status("");
        return Promise.resolve();
      }
      if (!current) {
        const record = {url, text:"", confirmed:"", revision:null, message:"正在读取草稿…"};
        current = record;
        saved.set(url, record);
        load(record);
      }
      input.value = current.text;
      input.disabled = current.revision === null;
      status(current.message);
      return current.pending;
    }
    input.addEventListener("input", () => {
      const record = current;
      if (!record) return;
      record.text = input.value;
      notify(record, "草稿待保存");
      clearTimeout(record.timer);
      record.timer = setTimeout(() => {void flush(record);}, 220);
    });
    function consume(record, value) {
      if (record && record.text === value) {
        record.text = "";
        if (current === record) input.value = "";
        void flush(record);
      }
    }
    function save() {
      if (current?.revision === null) {
        return current.message === "正在读取草稿…" ? current.pending : load(current);
      }
      return flush();
    }
    return {select, save, capture:() => current, consume,
      unsaved:() => [...saved.values()].some(record => record.text !== record.confirmed)};
  }

  function mount({req,tell,form,scopeAvailable,restoreModeDraft,restoreTemplate,skillForRun,currentResource,consumeResource,setResource}) {
    const $ = id => document.getElementById(id);
    let project = null, records = [], existingTasks=[], preview = null, selected = [], generation = 0;
    let enabledModules=null;
    const recentRooms=new Map();
    let visibleRoom=null, searchState=null, renameTarget=null, painted="", scrollOnOpen=false;
    let history = [], active = "", pollTimer = 0, models = [], modelFlight=null, previewSequence = 0;
    let importedMaterials=[], restoringDraft=null, legacyMember=null;
    let filePickerOwner=null, fileBatch=null;
    const chatAttachments=new Map();
    const effortChoices=new Map();
    const reasoning=window.SciModelEffort.bind($("lab-effort"),$("lab-effort-value"),effort=>{
      effortChoices.set($("lab-model").value,effort);
    });
    const memberEditor=window.RoundtableMemberEditor.mount({
      loadModels:()=>req(studio+"models"),
      write:(id,change)=>{
        if(!scopeAvailable() || active!==id || memberLock(visibleRoom)) throw Error(text("当前对话无法更改模型。","The model cannot be changed in this chat right now."));
        return req(sessionURL(id)+"/members","POST",change);
      },
      acceptSession(room){
        if(!ownsRun(room,project) || active!==room.id) return;
        recentRooms.set(room.id,room);
        history=history.map(item=>item.id===room.id ? room : item);
        renderRun(room);displayHistory();
        if(room.status==="running") schedule(room.id);
      },
      membersOf:room=>[effectiveMember(room)].filter(Boolean),
      displayName:(_id,room)=>threadTitle(room)
    });
    const audit = window.SciLabRunAudit.mount({req, scopeQuery});
    const questionDraft = createDraft({req,input:$("question"),status:message=>{$("lab-question-draft-state").textContent=message;}});
    const replyDraft = createDraft({req,input:$("lab-reply"),status:message=>{$("lab-reply-draft-state").textContent=message;}});
    function bind(id, fn) {
      $(id).addEventListener("click", async () => {
        const button=$(id), started=generation;
        button.dataset.labBusy="1";button.disabled=true; tell("");updateComposer();
        try { await fn(); } catch(error) { if(started===generation) tell(error.message); }
        finally { delete button.dataset.labBusy;button.disabled=false;updateComposer(); }
      });
    }
    function lookAt(id) {
      const changed=active!==id;
      if(changed) {
        stopFileUpload();
        legacyMember=null;
        chatAttachments.set(active,{selected,importedMaterials,resource:currentResource()});
        const saved=chatAttachments.get(id);
        selected=saved?.selected || []; importedMaterials=saved?.importedMaterials || [];
        setResource(saved?.resource || null); displaySelected();
        window.SciStationReadReview?.update($("lab-read-review"), null);
        visibleRoom=null;
        painted=""; scrollOnOpen=Boolean(id);
        audit.show(null, null);
        $("lab-result").hidden=true;
        void replyDraft.select(null);
      }
      active=id;
      if(changed) restoreAttachments();
      updateComposer();
      const url = new URL(location.href);
      if((url.searchParams.get("run") || "")===id) return;
      if(id) url.searchParams.set("run",id); else url.searchParams.delete("run");
      window.SciStationNav.commitURL(url,"replace");
    }
    function restoreAttachments() {
      const owner=project, thread=active, token=generation;
      const pending=owner ? restoreModeDraft(owner.id,thread) : null;
      restoringDraft=pending;
      if(!pending) return;
      const current=()=>generation===token && active===thread && restoringDraft===pending;
      void pending.then(draft=>{
        if(!draft || !current() || !scopeAvailable()) return;
        const key=({citation})=>JSON.stringify(citation);
        selected=[...new Map(draft.selected.concat(selected).map(item=>[key(item),item])).values()].slice(0,4);
        importedMaterials=[...new Map(importedMaterials.concat(draft.materials).map(item=>[item.id,item])).values()];
        restoreTemplate(draft.templateId,draft.templateRevision);
        if(!thread) restoreDraftModel(draft.modelChoice);
        if(draft.resource && !currentResource()) setResource(draft.resource);
        displaySelected();
        draft.consume();
      }).catch(error=>{
        if(current()) tell(error.message);
      }).finally(()=>{
        if(current()){restoringDraft=null;updateComposer();}
      });
    }
    function updateComposer() {
      const archived=Boolean(visibleRoom?.lab_thread?.archived_at);
      const running=visibleRoom?.status==="running";
      const writable=Boolean(!active || (visibleRoom && !archived && ["ready","partial"].includes(visibleRoom.status)));
      const scopeReady=scopeAvailable();
      const enabled=scopeReady && window.SciStationModules.isEnabled(enabledModules,"ai-lab");
      const sending=Boolean($("lab-start").dataset.labBusy || $("lab-resume").dataset.labBusy);
      const canAttach=writable && enabled && !restoringDraft && !sending;
      $("lab-workspace").dataset.labState=active ? "conversation" : "new";
      $("lab-empty").hidden=Boolean(active);
      $("lab-opening-chat").hidden=!active || Boolean(visibleRoom);
      $("lab-thread-actions").hidden=!visibleRoom;
      $("lab-composer").hidden=!writable && !running;
      $("lab-initial").hidden=Boolean(active) || !writable;
      $("lab-followup").hidden=!active || !writable;
      $("lab-question-draft-actions").hidden=Boolean(active);
      $("lab-reply-draft-actions").hidden=!active;
      $("lab-start").hidden=Boolean(active) || !writable;
      $("lab-resume").hidden=!active || !writable;
      $("lab-stop").hidden=!running || visibleRoom.cancel_requested;
      $("lab-start").disabled=!enabled || Boolean(restoringDraft || fileBatch || sending);
      $("lab-resume").disabled=!enabled || Boolean(restoringDraft || fileBatch || sending);
      $("lab-attach").disabled=!canAttach;
      $("lab-file-picker").disabled=!canAttach || Boolean(fileBatch);
      $("local-sources").hidden=!scopeReady || !project?.id;
      $("local-sources").disabled=!canAttach || Boolean(fileBatch);
      $("lab-tools").disabled=!writable || !enabled || Boolean(restoringDraft || fileBatch);
      $("lab-draft-trigger").disabled=!writable || !project || !scopeReady;
      $("lab-model-controls").hidden=Boolean(active);
      $("lab-model-trigger").disabled=!enabled || sending || Boolean(restoringDraft);
      reasoning.setDisabled(!enabled || sending || Boolean(restoringDraft));
      const member=effectiveMember(visibleRoom), locked=memberLock(visibleRoom);
      $("lab-existing-model").hidden=!visibleRoom;
      $("lab-edit-model").disabled=!enabled || sending || Boolean(locked);
      const memberLabel=member?.model ? [member.label || member.model,
        window.SciModelEffort.label(member.effort)].filter(Boolean).join(" · ") : text("模型","Model");
      $("lab-existing-model-label").textContent=memberLabel;
      $("lab-edit-model").setAttribute("aria-label",text("更改对话模型","Change chat model")+" · "+memberLabel);
      $("lab-model-lock").hidden=!locked;
      $("lab-model-lock").textContent=locked;
      memberEditor.update(visibleRoom,sending || Boolean(locked));
      $("lab-readonly").hidden=Boolean(!active || !visibleRoom || writable || running);
      $("lab-readonly").textContent=archived ? text("此对话已归档。","This chat is archived.") : text("此对话已结束。","This conversation is closed.");
      $("lab-run-state").textContent=visibleRoom ? [threadTitle(visibleRoom),archived ? text("已归档","Archived") : "",statusText(visibleRoom.status)].filter(Boolean).join(" · ") : "";
      $("lab-run-state").title=$("lab-run-state").textContent;
    }
    function dismissThreadNavigation() {
      const layout=window.SciShellLayout;
      if(layout?.dismissSessionNav) layout.dismissSessionNav(true);
      else layout?.dismissProjectNav();
    }
    function displayHistory() {
      const rows=matchingThreads(history,$("lab-thread-search").value,$("lab-show-archived").checked);
      const focused=document.activeElement?.dataset.labThread;
      $("lab-history").replaceChildren(...rows.map(room=>{
        const item=document.createElement("li"), button=document.createElement("button"), title=document.createElement("span"), detail=document.createElement("span");
        button.type="button";button.dataset.labThread=room.id;button.setAttribute("aria-current",String(room.id===active));
        title.className="lab-thread-title";title.textContent=threadTitle(room);button.title=title.textContent;
        detail.className="lab-thread-meta";detail.textContent=(room.lab_thread?.archived_at ? text("已归档 · ","Archived · ") : "")+threadDetails(room);
        button.append(title,detail);item.append(button);
        button.onclick=()=>{dismissThreadNavigation();void openRun(room.id);};
        return item;
      }));
      if(focused) $("lab-history").querySelector(`[data-lab-thread="${CSS.escape(focused)}"]`)?.focus();
      $("lab-thread-empty").hidden=rows.length>0;
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
        const li=document.createElement("li"), label=document.createElement("span"), remove=document.createElement("button");
        label.textContent=item.title+(item.citation.page?" · p. "+item.citation.page:"");label.title=item.citation.quote;
        remove.type="button"; remove.textContent=text("移除","Remove");remove.setAttribute("aria-label",remove.textContent+" "+item.title);
        remove.onclick=()=>{selected.splice(index,1);displaySelected();}; li.append(label,remove);
        return li;
      });
      for(const material of importedMaterials){
        const li=document.createElement("li"), label=document.createElement("span"), remove=document.createElement("button");
        label.textContent=material.name;remove.type="button";remove.textContent=text("移除","Remove");
        remove.setAttribute("aria-label",remove.textContent+" "+material.name);
        remove.onclick=()=>{importedMaterials=importedMaterials.filter(m=>m.id!==material.id);displaySelected();};
        li.append(label,remove);rows.push(li);
      }
      $("local-list").replaceChildren(...rows);
      $("lab-attachments").hidden=!rows.length && !currentResource();
    }
    async function selectProject(next, sessions) {
      const token=++generation, requested=new URL(location.href).searchParams.get("run");
      stopFileUpload();
      window.SciStationReadReview?.update($("lab-read-review"), null);
      project=next; records=[];existingTasks=[]; selected=[];importedMaterials=[]; restoringDraft=null; legacyMember=null;
      clearTimeout(pollTimer); active=""; visibleRoom=null; enabledModules=null;
      chatAttachments.clear();
      painted="";$("lab-thread-actions").open=false;
      audit.show(null, null);
      void questionDraft.select(project);
      void replyDraft.select(null);
      $("lab-thread-search").value=""; $("lab-show-archived").checked=false;
      $("local-record").replaceChildren(); chooseRecord(); displaySelected();
      $("lab-result").hidden=true;
      history=[...recentRooms.values(),...sessions.filter(s=>!recentRooms.has(s.id))].filter(s=>ownsRun(s,project)); displayHistory();
      if(!project) {lookAt("");return;}
      const linked=history.find(s=>s.id===requested);
      if(linked) {
        $("lab-show-archived").checked=Boolean(linked.lab_thread?.archived_at);
        displayHistory();
        void openRun(requested);
      } else {lookAt("");restoreAttachments();}
      const prefix="/api/research/projects/"+encodeURIComponent(project.id)+"/";
      const config=await window.SciStationModules.load(project.id);
      if(generation!==token) return;
      enabledModules=config;
      updateComposer();
      const enabled = id=>window.SciStationModules.isEnabled(config,id);
      if(!active && enabled("ai-lab")) ensureModels();
      if(project.global) return;
      const [papers,notes,materials,tasks]=await Promise.all([
        (enabled("paper-library")||enabled("pdf-reader"))?req("/api/research/papers?project="+encodeURIComponent(project.id)):[],
        enabled("wiki")?req(prefix+"notes"):[], enabled("materials")?req(prefix+"materials"):[],enabled("tasks")?req(prefix+"tasks"):[]
      ]);
      if(generation!==token) return;
      existingTasks=tasks;
      if(visibleRoom && ownsRun(visibleRoom,project)){painted="";renderRun(visibleRoom);}
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
    async function showPreview(offset=0,line=0,expectedHash="") {
      const record=records[$("local-record").value], token=++previewSequence;
      if(!record || !project) throw Error("请先选择项目原文。");
      const page=record.kind==="paper"?Number($("local-page").value):0;
      preview=null; $("local-window").hidden=true;
      const data=await req(base+"preview","POST",{projectId:project.id,line,location:{kind:record.kind,id:record.id,page,offset}});
      if(token!==previewSequence) return;
      if(expectedHash && data.hash!==expectedHash) throw Error("原文已改变，请重新检索。");
      preview=data;
      const md=data.kind==="paper-markdown";
      $("body-location").hidden=!md;$("body-sections-label").hidden=!md||!data.sections?.length;
      if(md) {
        $("body-line").value=String(data.line);
        $("body-location").textContent="正文版本 "+data.revision+" · 第 "+data.line+" 行"+(data.heading?" · "+data.heading:"");
        $("body-sections").replaceChildren(new Option("选择章节",""),...(data.sections||[]).map(h=>new Option("L"+h.line+" · "+h.heading,String(h.line))));
      }
      $("local-text").value=data.text; $("local-window").hidden=false;
      $("local-prev").hidden=!data.offset; $("local-next").hidden=!data.more;
      window.SciPaperBodyPreview.renderFigures($("body-preview-figures"), data.figures, {
        paper:data.id, hash:data.hash, select:figure=>locateFigure(figure, data).catch(e=>tell(e.message))
      });
    }
    async function locateFigure(figure, source) {
      const format = window.SciPaperBodyPreview;
      let range = format.figureRange(figure, source);
      if (!range) {
        const expected = previewSequence + 1;
        await showPreview(figure.citeStart, 0, source.hash);
        if (previewSequence !== expected || !preview) return;
        range = format.figureRange(figure, preview);
      }
      if (!range) throw Error("此图片引用超过 1,000 字。请在正文中手动选择所需部分。");
      const area = $("local-text");
      area.focus();
      area.setSelectionRange(...range);
    }
    function resetSearch() {
      searchState?.controller?.abort();
      searchState=null;
      $("local-hits").replaceChildren();
      $("local-search-more").hidden=true;
      $("local-search-stop").hidden=true;
      $("local-search-status").hidden=true;
    }
    function updateSearchOptions() {
      resetSearch();
      const indexed=$("local-search-scope").value==="project";
      $("local-rank-label").hidden=!indexed;
      $("local-index-actions").hidden=!indexed || $("local-rank").value!=="hybrid";
    }
    function addHit(state,record,hit) {
      const li=document.createElement("li"),button=document.createElement("button");
      button.type="button";
      const where=hit.page?" · 第 "+hit.page+" 页":hit.line?" · L"+hit.line+(hit.line!==hit.endLine?"–"+hit.endLine:""):"";
      button.textContent=record.label+where+(hit.heading?" · "+hit.heading:"")+" · "+hit.text;
      button.onclick=()=>{
        if(searchState!==state) return;
        let index=records.findIndex(x=>x.kind===record.kind && x.id===record.id);
        if(index<0) {
          index=records.push(record)-1;
          $("local-record").add(new Option(record.label,String(index)));
        }
        $("local-record").value=String(index);
        $("local-page").value=String(hit.page || 1);
        chooseRecord(false);
        showPreview(hit.hash?hit.offset:Math.max(0,hit.offset-35),0,hit.hash).catch(e=>tell(e.message));
      };
      li.append(button);$("local-hits").append(li);
    }
    async function runProjectSearch(query,rebuild=false,selectedOnly=false) {
      resetSearch();
      if(!project?.id) throw Error("请选择科研项目。");
      const record=selectedOnly?records[$("local-record").value]:null;
      if(selectedOnly && (!record || record.missing || record.kind==="paper")) throw Error("请选择已有正文的论文 Markdown、笔记或文本材料。");
      const state={controller:new AbortController()};
      searchState=state;
      $("local-search-stop").hidden=false;
      const request={projectId:project.id,query,mode:$("local-rank").value,rebuild};
      if(record) request.location={kind:record.kind,id:record.id};
      try {
        const data=await req(base+"search","POST",request,state.controller.signal);
        if(searchState!==state || state.controller.signal.aborted) return;
        const trace=data.trace, output=$("local-search-status");
        const changed=trace.cacheStatus==="version_changed" || trace.cacheStatus==="invalid";
        const fallback={query_has_no_vector:"当前词句使用关键词排序。",cache_write_failed:"索引无法保存，已使用关键词排序。"};
        const indexed=trace.mode==="hybrid";
        output.textContent=(rebuild?(trace.cacheStatus==="rebuilt"?"已重建索引。":"索引未能保存。"):"显示 "+data.items.length+" 段。")+
          "已核对 "+trace.verified+" / "+trace.sources+" 份来源。"+
          (indexed?"向量更新 "+trace.updated+" 份，复用 "+trace.reused+" 份。":"")+
          (indexed && changed?"已刷新旧版本或损坏的本地索引。":"")+
          (trace.skipped?"跳过 "+trace.skipped+" 份来源。":"")+
          (data.limited?"本次结果达到检索上限。":"")+
          (fallback[trace.fallbackReason] || "");
        output.hidden=false;
        for(const hit of data.items){
          const source=records.find(x=>x.kind===hit.kind && x.id===hit.id) || {kind:hit.kind,id:hit.id,label:hit.title};
          addHit(state,source,hit);
        }
      } catch(error) {
        if(!state.controller.signal.aborted && searchState===state) throw error;
      } finally {
        if(searchState===state) $("local-search-stop").hidden=true;
      }
    }
    async function findSources(more=false) {
      if(!more) {
        resetSearch();
        const query=$("local-query").value.trim();
        if(!query || !project?.id) throw Error("请选择项目并输入要检索的词句。");
        const scope=$("local-search-scope").value;
        if(scope==="project") return runProjectSearch(query);
        const items=scope==="exact-project"?records.filter(r=>!r.missing):[records[$("local-record").value]].filter(Boolean);
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
      if(selected.length+importedMaterials.length>=12) throw Error(text("每次最多加入 12 份附件。","Attach no more than 12 files or excerpts at a time."));
      const area=$("local-text"), citation=selectedCitation(preview,area.selectionStart,area.selectionEnd);
      if(selected.some(x=>x.citation.kind===citation.kind && x.citation.id===citation.id && x.citation.page===citation.page && x.citation.offset===citation.offset))
        throw Error("此选段已加入。");
      selected.push({title:preview.title,citation}); displaySelected();
      tell(text(`已加入 ${selected.length} 段项目原文。`,`${selected.length} project excerpt(s) attached.`));
    }
    function consumeSelection(used, imported) {
      selected=selected.filter(item=>!used.includes(item));
      importedMaterials=importedMaterials.filter(item=>!imported.includes(item));
      displaySelected();
    }
    function stopFileUpload() {
      filePickerOwner=null;
      fileBatch?.abort();
      fileBatch=null;
    }
    function draftOwner() {return {project,thread:active,generation};}
    function ownsDraft(owner) {
      return owner.project===project && owner.thread===active && owner.generation===generation && scopeAvailable();
    }
    $("lab-file-picker").addEventListener("click",()=>{
      filePickerOwner=draftOwner();
      $("lab-file-input").click();
    });
    $("lab-file-input").addEventListener("cancel",()=>{filePickerOwner=null;});
    $("lab-file-input").addEventListener("change",async event=>{
      const owner=filePickerOwner;
      filePickerOwner=null;
      const files=Array.from(event.target.files || []);
      event.target.value="";
      if(!files.length || !owner?.project || !ownsDraft(owner) || $("lab-file-picker").disabled) return;
      const available=12-selected.length-importedMaterials.length;
      if(files.length>available) {
        tell(text("每次最多加入 12 份附件。请减少选中的文件。","Attach no more than 12 files or excerpts at a time. Select fewer files."));
        return;
      }
      const batch=new AbortController();fileBatch=batch;
      updateComposer();
      tell(text("正在添加本地文件…","Adding local files…"));
      const errors=[];
      let added=0;
      try {
        for(const file of files) {
          if(!ownsDraft(owner) || fileBatch!==batch) return;
          if(file.size>12*1024*1024) {
            errors.push(file.name+text("：文件超过 12 MiB。",": File exceeds 12 MiB."));
            continue;
          }
          const data=new FormData();data.append("file",file,file.name);
          try {
            const {id,name}=await req(studio+"materials","POST",data,batch.signal);
            if(!ownsDraft(owner) || fileBatch!==batch) return;
            importedMaterials.push({id,name});
            added++;displaySelected();
          } catch(error) {
            if(batch.signal.aborted || !ownsDraft(owner) || fileBatch!==batch) return;
            errors.push(file.name+": "+error.message);
          }
        }
        if(added) errors.unshift(text(`已加入 ${added} 个文件。`,`${added} file(s) attached.`));
        if(errors.length) tell(errors.join("\n"));
      } finally {
        if(fileBatch===batch){fileBatch=null;updateComposer();}
      }
    });
    async function prepare(workflow,projectId,question="",room=null) {
      if(!project || project.id!==projectId) throw Error("请先选择科研项目。");
      const token=generation, conversation=active, inherited=importedMaterials.slice();
      const result=await prepareQuestionSources(req,project,workflow,question,selected.map(x=>x.citation),{
        currentPaper:selected.some(x=>["paper","paper-markdown"].includes(x.citation.kind))?"":paperFromRun(room,projectId)
      });
      if(token!==generation || conversation!==active) throw Error(text("当前对话已改变。","The active chat changed."));
      if(!result) return null;
      const combined=[...new Map([...inherited,...result].map(material=>[material.id,material])).values()];
      if(combined.length>12) throw Error(text("每次最多加入 12 份材料。","Attach no more than 12 sources at a time."));
      return combined;
    }
    function effortOptions() {
      const model=models.find(m=>m.id===$("lab-model").value);
      const effort=reasoning.setOptions(model?.efforts,effortChoices.get(model?.id));
      if(model && effort) effortChoices.set(model.id,effort);
      showModelLabel();
    }
    function showModelLabel() {
      const model=models.find(m=>m.id===$("lab-model").value);
      $("lab-model-trigger-text").textContent=model?.label || model?.id || text("模型","Model");
      $("lab-model-trigger").setAttribute("aria-label",[text("选择模型","Choose model"),model?.label || model?.id].filter(Boolean).join(" · "));
    }
    function ensureModels() {
      if(!models.length) void loadModels().catch(()=>{});
    }
    function draftModelChoice() {
      const model=$("lab-model").value, effort=reasoning.value;
      return model && effort ? {model,effort} : undefined;
    }
    function restoreDraftModel(choice) {
      if(!choice?.model || !choice?.effort) return;
      const owner=draftOwner();
      const restore=()=>{
        if(!ownsDraft(owner)) return;
        const available=models.find(model=>model.id===choice.model);
        if(!available) {
          tell(text("草稿原来选用的模型已不可用，请重新选择。","The model selected for this draft is unavailable. Choose a model again."));
          return;
        }
        $("lab-model").value=available.id;
        effortChoices.set(available.id,choice.effort);
        effortOptions();
        if(reasoning.value!==choice.effort) tell(text("原思考档位已不可用，已选用该模型的可用档位。",
          "The draft’s reasoning level is unavailable. The model now uses one of its supported levels."));
      };
      if(models.length) restore();
      else void loadModels().then(restore).catch(error=>{if(ownsDraft(owner)) tell(error.message);});
    }
    function loadModels() {
      if(modelFlight) return modelFlight;
      $("lab-model-state").textContent = text("正在读取模型目录…","Loading models…");
      modelFlight=(async()=>{
        const previous=$("lab-model").value;
        const catalog = await req(studio + "models");
        models = catalog.models || [];
        $("lab-model").replaceChildren(...models.map(m => new Option(m.label || m.id, m.id)));
        if (models.some(m=>m.id===previous)) $("lab-model").value=previous;
        else if (models.some(m => m.id === catalog.default_model)) $("lab-model").value = catalog.default_model;
        $("lab-model").disabled=!models.length;
        effortOptions();
        if (!models.length) throw Error(text("模型目录为空，请检查 AI 设置。","No models available. Check AI settings."));
        $("lab-model-state").textContent = text("可用模型 · ","Available models · ") + models.length;
      })().catch(error=>{
        $("lab-model-state").textContent = error.message;
        throw error;
      }).finally(()=>{modelFlight=null;});
      return modelFlight;
    }
    function sessionURL(id) {return studio+"sessions/"+encodeURIComponent(id);}
    function effectiveMember(room) {
      if(!room) return null;
      return room.members?.[0] || room.seat_overrides?.[room.seats[0]] || (legacyMember?.id===room.id ? legacyMember.member : null);
    }
    function memberLock(room) {
      if(!room) return "";
      if (room.lab_thread?.archived_at) return text("恢复归档后可更改。","Restore this chat to change its model.");
      if (room.status==="closed" || room.report) return text("对话已结束。","This chat has ended.");
      if (room.status==="running" || room.agenda_draft_status==="drafting") return text("本轮结束后可更改。","Change the model after this turn.");
      if (!effectiveMember(room)) return legacyMember?.failed ? text("模型信息暂时不可用。","Model details are unavailable.") : text("正在读取模型…","Loading model…");
      return "";
    }
    function loadLegacyMember(room) {
      if(room.members?.length || room.seat_overrides?.[room.seats[0]]) return;
      const key=JSON.stringify([room.id,room.status,room.rounds?.at(-1)?.number]);
      if(legacyMember?.key===key) return;
      const lookup={id:room.id,key,member:null,failed:false};legacyMember=lookup;
      req(sessionURL(room.id)+"/members").then(result=>{
        lookup.member=result.members.find(member=>member.id===room.seats[0]);
        lookup.failed=!lookup.member;
      }).catch(()=>{lookup.failed=true;}).finally(()=>{
        if(legacyMember===lookup && active===room.id) updateComposer();
      });
    }
    async function start() {
      const data=form(), pid=project?.id, token=generation;
      const draft=questionDraft.capture(), expectedDraft=$("question").value;
      if(!data.question) throw Error(text("请先填写研究问题。","Enter a research question."));
      if(data.seats!==1) throw Error(text("无法载入单人对话模板。","Could not load the chat template."));
      if(!project || !scopeAvailable()) throw Error("请选择科研项目或全局会话。");
      if(!window.SciStationModules.isEnabled(enabledModules,"ai-lab")) throw Error("AI 实验室模块未启用或仍在加载。");
      if(!$("lab-model").value) await loadModels();
      if(token!==generation || active || !scopeAvailable()) return;
      const member={model:$("lab-model").value,effort:reasoning.value};
      if(!member.model || !member.effort) throw Error("请先读取模型目录并选择模型。");
      const scope=project.global?"global":"";
      const skill=await skillForRun(pid);
      if(token!==generation || active || !scopeAvailable()) return;
      const topic=window.ScienceLabHandoff.compose({...data,scope,projectId:pid,skill});
      const used=selected.slice(), inherited=importedMaterials.slice();
      const materials=await prepare(data.workflow,pid,data.question);
      if(!materials || token!==generation || active || !scopeAvailable()) return;
      // Creating the session records a recoverable ID before the first model call.
      const room=await createSingle(req,project,topic,member,data.mode,materials);
      questionDraft.consume(draft, expectedDraft);
      recentRooms.set(room.id,room);
      if(token!==generation) return;
      history=[room,...history];
      if(active) {displayHistory();return;}
      consumeSelection(used,inherited);consumeResource(data.resource);
      lookAt(room.id);
      void replyDraft.select(project,room.id);
      displayHistory(); renderRun(room);
      try {
        const result=await advance(req,room,"");
        if(token===generation && active===room.id) {renderRun(result); schedule(room.id);}
      } catch(error) {
        throw Error("会话已保存，可从会话记录重新启动。"+error.message);
      }
    }
    function displaySources(room) {
      const entries=[];
      for(const [index,material] of (room.materials || []).entries()) {
        const source=recordedSource(material,project?.id,index);
        if(!source) continue;
        const title=document.createElement("h3"), quote=document.createElement("blockquote"), link=document.createElement("a");
        title.textContent=source.id+" · "+source.title; quote.textContent=source.quote;
        link.href=source.href; link.textContent=source.label;
        entries.push(title,quote,link);
      }
      $("lab-citation-items").replaceChildren(...entries);$("lab-citations").hidden=!entries.length;
    }
    function userMessage(value, initial=false) {
      const body=messageText(value,initial);
      if(!body) return null;
      const message=document.createElement("p");
      message.className="lab-turn-user";
      const origin=body.match(/(?:^|\n)Source Roundtable: (\/studio\?[^\n ]+)\s*$/);
      if(origin) {
        const query=new URL(origin[1],location.origin).searchParams;
        const bound=project.global ? query.get("scope")==="global" && !query.get("project") : query.get("project")===project.id;
        if(bound && /^[a-f0-9]{32}$/.test(query.get("session") || "")){
          const link=document.createElement("a");link.href=origin[1];link.textContent=text("打开来源圆桌","Open source Roundtable");
          message.textContent=body.slice(0,origin.index).trim();message.append(document.createElement("br"),link);
          return message;
        }
      }
      message.textContent=body;
      return message;
    }
    function renderRun(room) {
      if(!ownsRun(room,project) || active!==room.id) return;
      if ((room.lab_thread?.revision || 0) < (visibleRoom?.lab_thread?.revision || 0)) return;
      visibleRoom=room;
      loadLegacyMember(room);
      if(recentRooms.has(room.id)) recentRooms.set(room.id,room);
      const rounds=room.rounds||[];
      const archived=Boolean(room.lab_thread?.archived_at);
      updateComposer();
      $("lab-result").hidden=false;
      window.SciStationReadReview?.update($("lab-read-review"), room);
      $("lab-archive-thread").hidden=archived;
      $("lab-restore-thread").hidden=!archived;
      $("lab-retry").hidden=!window.SciLabRunAudit.canRetry(room);
      $("lab-retry").textContent=rounds.length ? text("重试本轮","Retry") : text("启动已保存的对话","Start saved chat");
      $("lab-open").href="/studio?"+new URLSearchParams(project.global?{session:room.id}:{project:project.id,session:room.id});
      if(painted===room.updated_at) return;
      painted=room.updated_at;
      displaySources(room);
      $("lab-no-turns").hidden=Boolean(rounds.length);
      const timeline=$("lab-timeline");
      const atEnd=scrollOnOpen || timeline.scrollHeight-timeline.scrollTop-timeline.clientHeight<80;
      const turns=[];
      const first=userMessage(room.topic,true);if(first) turns.push(first);
      for(const round of rounds) {
        if(round.note && !round.lab_run?.retry_of_round){const note=userMessage(round.note);if(note) turns.push(note);}
        for(const turn of round.turns||[]) {
          const article=document.createElement("article"), heading=document.createElement("h3");
          article.className="lab-turn-answer";
          heading.textContent=[turn.model_label||turn.model||turn.seat,turn.status!=="done" ? statusText(turn.status) : ""].filter(Boolean).join(" · ");
          if(round.lab_run?.retry_of_round) heading.textContent+=text(` · 重试第 ${round.lab_run.retry_of_round} 轮`,` · Retry of turn ${round.lab_run.retry_of_round}`);
          const structured=turn.status==="done" && window.SciLabArtifacts?.projectRows(room.topic,turn.text,room.materials||[],round.number,existingTasks,project.id);
          const body=document.createElement(turn.error ? "p" : "div");
          if(turn.error) body.textContent=turn.error;
          else if(turn.text) {
            window.SciMarkdown.render(body,structured && !structured.error ? structured.narrative : turn.text,{headingShift:3,cache:turn.status!=="running"});
            heading.append(window.SciMarkdown.copyButton(turn.text));
          }
          article.append(heading,body);
          if(structured) article.append(window.SciLabArtifacts.render(structured));
          if (!project.global && room.status !== "running" && turn.status === "done" && !turn.error && turn.text?.trim()) {
            article.append(window.SciLabEvidence.inspection({room: room.id, project: project.id, output: "round-"+round.number+"-"+turn.seat, req}));
          }
          turns.push(article);
        }
      }
      $("lab-turns").replaceChildren(...turns);
      audit.show(room, project);
      if(atEnd) requestAnimationFrame(()=>{if(active===room.id)timeline.scrollTop=timeline.scrollHeight;});
      scrollOnOpen=false;
    }
    function schedule(id) {clearTimeout(pollTimer);pollTimer=setTimeout(()=>openRun(id),1000);}
    async function openRun(id) {
      clearTimeout(pollTimer);
      const changed=active!==id;
      lookAt(id);
      if(changed) {$("lab-thread-actions").open=false;displayHistory();}
      if(!id) {$("lab-result").hidden=true;return;}
      const token=generation;
      try {
        const room=await req(sessionURL(id));
        if(token!==generation || active!==id) return;
        if(!ownsRun(room,project)) {lookAt(""); $("lab-result").hidden=true;throw Error("此会话不属于当前项目。");}
        void replyDraft.select(project,room.id);
        renderRun(room); if(room.status==="running") schedule(id);
      } catch(error) {if(token===generation && active===id){$("lab-opening-chat").hidden=true;tell(error.message);}}
    }
    async function ask() {
      const room=visibleRoom, id=room?.id, pid=project?.id, token=generation;
      const draft=replyDraft.capture(), expectedDraft=$("lab-reply").value;
      const note=expectedDraft.trim(), resource=currentResource();
      if(!scopeAvailable() || !ownsRun(room,project) || room.lab_thread?.archived_at || id!==active || !["ready","partial"].includes(room.status)) throw Error("请先打开可继续的会话。");
      if(!note) throw Error("请填写追问。");
      const used=selected.slice(), inherited=importedMaterials.slice();
      const materials=await prepare("",pid,note,room);
      if(!materials || token!==generation || id!==active || !scopeAvailable()) return;
      const message=window.ScienceLabHandoff.composeFollowup({question:note,projectId:pid,scope:project.global?"global":"",resource});
      const next=await advance(req,room,message,materials);
      replyDraft.consume(draft, expectedDraft);
      if(token===generation && id===active) {
        consumeSelection(used,inherited);consumeResource(resource);
        renderRun(next);schedule(id);
      }
    }
    async function changeThread(action, title = "", target = {room:visibleRoom, owner:project}) {
      const {room,owner}=target;
      if(owner!==project || !ownsRun(room,owner) || active!==room.id) throw Error("请先打开会话。");
      const url="/api/research/lab/threads/"+encodeURIComponent(room.id)+"?"+scopeQuery(owner);
      const next=await req(url,"PATCH",{action,title,revision:room.lab_thread?.revision || 0});
      recentRooms.set(next.id,next);
      if(owner!==project || active!==next.id) return;
      history=history.map(item=>item.id===next.id ? next : item);
      if(action==="archive" && !$("lab-show-archived").checked) {
        await openRun("");
      } else renderRun(next);
      displayHistory();
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
    async function retry() {
      const room=visibleRoom, owner=project;
      if(!ownsRun(room,owner) || active!==room.id || !window.SciLabRunAudit.canRetry(room)) return;
      const rounds=room.rounds?.length || 0;
      if(rounds && !confirm("用本轮已保存的输入和当前设置重新运行？项目文件写入仍需另行发起 CLI 编辑并审核。")) return;
      const next=await window.SciLabRunAudit.retry(req,room,owner,scopeQuery);
      if(owner===project && active===room.id) {renderRun(next); schedule(room.id);}
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
    $("local-query").oninput=resetSearch; $("local-search-scope").onchange=updateSearchOptions;
    $("local-rank").onchange=updateSearchOptions;
    $("lab-thread-search").oninput=displayHistory;
    $("lab-show-archived").onchange=displayHistory;
    bind("lab-new-thread",async()=>{dismissThreadNavigation();await openRun(""); $("question").focus();});
    $("lab-edit-model").addEventListener("click",()=>{
      const member=effectiveMember(visibleRoom);
      if(member && !memberLock(visibleRoom)) memberEditor.open(visibleRoom,member.id,$("lab-edit-model"));
    });
    bind("lab-rename-thread",async()=>{
      if(!visibleRoom) return;
      renameTarget={room:visibleRoom,owner:project};
      $("lab-thread-title").value=threadTitle(visibleRoom).slice(0,96);
      $("lab-rename-error").textContent="";
      $("lab-rename-dialog").showModal();
      $("lab-thread-title").select();
    });
    $("lab-rename-cancel").onclick=()=>$("lab-rename-dialog").close();
    $("lab-rename-form").onsubmit=async event=>{
      event.preventDefault();
      const dialog=$("lab-rename-dialog");
      try {
        if(!renameTarget) return;
        await changeThread("rename",$("lab-thread-title").value,renameTarget);
        dialog.close();
      }
      catch(error) {$("lab-rename-error").textContent=error.message;}
    };
    bind("lab-archive-thread",async()=>{if(confirm("归档此会话？归档记录会保留发言，取消归档后可以继续编辑草稿。")) await changeThread("archive");});
    bind("lab-restore-thread",()=>changeThread("restore"));
    bind("lab-save-question-draft",()=>questionDraft.save());
    bind("lab-save-reply-draft",()=>replyDraft.save());
    for(const [id,draft,input] of [
      ["lab-discard-question-draft",questionDraft,$("question")],
      ["lab-discard-reply-draft",replyDraft,$("lab-reply")],
    ]) bind(id,async()=>{draft.consume(draft.capture(),input.value);await draft.save();});
    window.addEventListener("pagehide",()=>{void questionDraft.save();void replyDraft.save();});
    bind("local-find",()=>findSources());bind("local-search-more",()=>findSources(true));
    bind("local-rebuild",()=>runProjectSearch("",true));bind("local-rebuild-source",()=>runProjectSearch("",true,true));
    $("local-search-stop").onclick=()=>searchState?.controller?.abort();
     $("body-sections").onchange=()=>{if($("body-sections").value)showPreview(0,Number($("body-sections").value)).catch(e=>tell(e.message));};
    bind("local-preview",()=>showPreview(0,records[$("local-record").value]?.kind==="paper-markdown"?Number($("body-line").value):0)); bind("local-add",addSelection);
    bind("local-prev",()=>showPreview(Math.max(0,(preview?.offset || 0)-4000)));
    bind("local-next",()=>showPreview((preview?.offset || 0)+chars(preview?.text || "").length));
    bind("lab-models",loadModels); bind("lab-start",start); bind("lab-stop",cancel); bind("lab-resume",ask); bind("lab-export",exportReplay); bind("lab-retry",retry);
    for (const [input,send] of [["question","lab-start"],["lab-reply","lab-resume"]]) $(input).addEventListener("keydown",event=>{
      if(event.key!=="Enter" || event.shiftKey || event.isComposing || event.keyCode===229) return;
      event.preventDefault();$(send).click();
    });
    function drawLanguage() {
      $("question").placeholder=text("输入研究问题…","Ask a research question…");
      $("lab-reply").placeholder=text("继续追问…","Ask a follow-up…");
      $("lab-thread-search").placeholder=text("搜索对话","Search chats");
      displayHistory();updateComposer();showModelLabel();
      if(visibleRoom){painted="";renderRun(visibleRoom);}
    }
    drawLanguage();window.addEventListener("sci:language",drawLanguage);
    async function importTransfer(transfer, message) {
      if(active || !project || project.id!==transfer.projectId || !window.SciStationModules.isEnabled(enabledModules,"ai-lab")) {
        throw Error(text("请在同一范围内打开新对话。","Open a new chat in the same scope."));
      }
      const owner=project;
      await questionDraft.select(owner);
      if(restoringDraft) await restoringDraft;
      if(project!==owner || active || $("question").disabled) throw Error(text("尚不能写入当前草稿。","The current draft is unavailable."));
      const prior=$("question").value;
      const next=[prior,message].filter(Boolean).join("\n\n");
      if(chars(next).length>2500) throw Error(text("合并后超过 2,500 字。请缩短转入内容或先整理已有草稿。","The combined draft exceeds 2,500 characters. Shorten the import or edit the existing draft first."));
      const materials=[...new Map(importedMaterials.concat(transfer.materials).map(item=>[item.id,item])).values()];
      if(materials.length+selected.length>12) throw Error(text("合并后超过 12 份原文。","The combined draft exceeds 12 attachments."));
      $("question").value=next;
      $("question").dispatchEvent(new Event("input",{bubbles:true}));
      importedMaterials=materials;displaySelected();
    }
    return {selectProject,updateComposer,ensureModels,draftModelChoice,importTransfer,activeRoom:()=>visibleRoom,activeThread:()=>active,
      restoringDraft:()=>Boolean(restoringDraft),
      modeDraftSelections:()=>({citations:selected.slice(),importedIds:importedMaterials.map(item=>item.id)}),
      handoffDraftStamp:()=>JSON.stringify([active,selected.map(item=>item.citation),importedMaterials.map(item=>item.id),currentResource()]),
      saveDraft:()=>active ? replyDraft.save() : questionDraft.save(),
      prepareHandoff:async pid=>{
        if(fileBatch) throw Error(text("请等文件添加完成后再切换模式。","Wait for files to finish attaching before switching modes."));
        if(restoringDraft) await restoringDraft;
        return selected.length || importedMaterials.length ? prepare("",pid) : [];
      },
      hasDraft:()=>Boolean(fileBatch || restoringDraft || selected.length || importedMaterials.length || questionDraft.unsaved() || replyDraft.unsaved())};
  }
  const api={mount, selectedCitation, ownsRun, createSingle, advance, threadTitle, matchingThreads, draftURL, createDraft, prepareQuestionSources, recordedSource, paperFromRun, messageText};
  if(typeof module==="object" && module.exports) module.exports=api;
  else window.SciLabRun=api;
})();
