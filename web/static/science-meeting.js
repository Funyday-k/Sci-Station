/* Scholarly references are immutable copies of the selected text. The original
   paper stays in the research library. Only the selected excerpt goes to a seat. */
(() => {
  "use strict";
  const marker = "Sci-Station · 论文原文摘录 v1\n";
  const taskTarget = "@task";
  const transferKey = "sci-station.paper-handoff";
  const enc = encodeURIComponent;
  const short = (value, max) => Array.from(String(value || "")).slice(0, max).join("");
  const validId = value => typeof value === "string" && /^[a-zA-Z0-9_-]{1,100}$/.test(value);

  function reference(input) {
    if (!input || !validId(input.projectId) || !validId(input.paperId)) return null;
    const page = Number(input.page);
    const quote = String(input.quote || "").trim();
    if (!Number.isSafeInteger(page) || page < 1 || !quote || Array.from(quote).length > 2800) return null;
    const offsets = Number.isSafeInteger(input.selectionStart) && input.selectionStart >= 0 &&
      Number.isSafeInteger(input.selectionEnd) && input.selectionEnd > input.selectionStart
      ? {selectionStart:input.selectionStart, selectionEnd:input.selectionEnd} : {};
    return {projectId:input.projectId, paperId:input.paperId, page, ...offsets, ...(input.ocr ? {ocr:true} : {}), title:short(input.title, 210),
      annotationId:validId(input.annotationId) ? input.annotationId : "",
      fingerprint:short(input.fingerprint, 128), quote};
  }
  function encodeReference(source) {
    const {quote, ...metadata} = source;
    return marker + JSON.stringify(metadata) + "\n\n" + quote;
  }
  function decodeReference(text) {
    if (typeof text !== "string" || !text.startsWith(marker)) return null;
    const split = text.indexOf("\n\n", marker.length);
    if (split < 0) return null;
    try { return reference({...JSON.parse(text.slice(marker.length, split)), quote:text.slice(split + 2)}); }
    catch { return null; }
  }
  function paperHref(source) {
    const query = new URLSearchParams({paper:source.paperId, project:source.projectId, page:String(source.page)});
    if (source.quote) query.set("quote",source.quote);
    if (Number.isSafeInteger(source.selectionStart) && Number.isSafeInteger(source.selectionEnd)) {
      query.set("start",String(source.selectionStart)); query.set("end",String(source.selectionEnd));
    }
    if (source.ocr) query.set("ocr","1");
    if (source.annotationId) query.set("annotation", source.annotationId);
    if (source.fingerprint) query.set("fingerprint", source.fingerprint);
    return "/reader?" + query;
  }
  function outputs(session) {
    const items = [];
    if (session?.report?.status === "ready" && session.report.markdown?.trim())
      items.push({key:"report", label:"会议定稿报告", text:session.report.markdown});
    const rounds = session?.rounds || [];
    const published = session?.status === "running" ? rounds.slice(0, -1) : rounds;
    for (const round of [...published].reverse()) {
      for (const turn of round.turns || []) {
        if (turn.status !== "done" || !turn.text?.trim() || turn.error) continue;
        items.push({key:"round-" + round.number + "-" + turn.seat, round:round.number, seat:turn.seat,
          label:"第 " + round.number + " 轮 · " + (turn.model_label || turn.model || turn.seat), text:turn.text});
      }
    }
    for (const item of session?.agenda || []) {
      if (item.id && item.title?.trim())
        items.push({key:"agenda-"+item.id, label:"议程 · "+item.title, title:item.title, text:[item.title,item.reason].filter(Boolean).join("\n\n")});
    }
    return items;
  }
  function sources(session, projectId, throughRound) {
    const seen = new Set();
    return (session?.materials || []).flatMap(item => {
      if (throughRound !== undefined && Number(item.added_round || 0) > throughRound) return [];
      const source = decodeReference(item.excerpt);
      if (!source || source.projectId !== projectId || seen.has(item.excerpt)) return [];
      seen.add(item.excerpt); return [source];
    });
  }
  if (typeof module === "object" && module.exports) {
    module.exports = {reference, encodeReference, decodeReference, paperHref, outputs, sources}; return;
  }

  const headers = {"X-Roundtable":"1","X-Sci-Station":"1"};
  async function request(url, method = "GET", body) {
    const opt = {method, headers:{...headers}, cache:"no-store"};
    if (body instanceof FormData) opt.body = body;
    else if (body !== undefined) {opt.headers["Content-Type"] = "application/json"; opt.body = JSON.stringify(body);}
    const response = await fetch(url, opt), value = await response.json().catch(() => null);
    if (!response.ok) {
      const error = new Error(value?.error?.message || value?.error || value?.message || "没有完成请求（" + response.status + "）");
      error.status = response.status; throw error;
    }
    return value;
  }
  const projectURL = id => "/api/research/projects/" + enc(id);
  const byId = id => document.getElementById(id);
  const elem = (tag, text) => {const e = document.createElement(tag); if (text !== undefined) e.textContent = text; return e;};
  const option = (value, label) => new Option(label, value);
  const btn = (label, className="") => {const node = elem("button",label); node.type="button"; node.className=className; return node;};
  const url = new URL(location.href);
  let projects = [], session = null, project = null, btnOpen, ui;
  let currentDraft = null, fetchedReviewLink = false;

  async function loadProjects() {
    projects = await request("/api/research/projects");
    return projects;
  }
  function requestedProject(id) {
    if (!id) return null;
    const result = projects.find(item => item.id === id);
    if (!result) throw new Error("科研项目已移除，无法将这次阅读发送到圆桌。");
    return result;
  }

  function update(next) {
    session = next || null;
    project = session && projects.find(item => item.id === session.project_id) || null;
    if (!btnOpen && (byId("meeting-menu-commands") || byId("chat-toolbar"))) {
      btnOpen = btn("科研记录", "science-meeting-open"); btnOpen.title = "核对论文原文、保存笔记或建立项目任务";
      btnOpen.addEventListener("click", show);
      const menuCommands = byId("meeting-menu-commands");
      if (menuCommands) {
        btnOpen.dataset.meetingCommand = "";
        menuCommands.insertBefore(btnOpen, menuCommands.firstChild || null);
      } else {
        byId("chat-toolbar").insertBefore(btnOpen, byId("meeting-actions"));
      }
    }
    if (btnOpen) btnOpen.hidden = !project;
    if (project && session && url.searchParams.get("review") && !ui?.dialog.open && !fetchedReviewLink) {
      fetchedReviewLink=true;show();
    }
    renderReportSources();
    if (currentDraft && (currentDraft.sessionId !== session?.id || currentDraft.projectId !== project?.id)) ui?.dialog.close();
  }

  function renderReportSources() {
    const anchor = byId("meeting-report-review");
    if (!anchor) return;
    let block = byId("science-report-sources");
    const available = project && session?.report?.status === "ready" ? sources(session, project.id) : [];
    if (!available.length) {if (block) block.hidden=true;return;}
    if (!block) {
      block=elem("section");block.id="science-report-sources";block.className="science-report-sources";anchor.before(block);
    }
    block.hidden=false;
    const key=JSON.stringify([session.id,...available]);
    if (block.dataset.key===key) return;
    block.dataset.key=key;block.replaceChildren(elem("h3","会议共享的论文原文"));
    for(const source of available) {
      const details=elem("details"),summary=elem("summary",(source.title||"论文")+" · 第 "+source.page+" 页");
      const quote=elem("blockquote",source.quote),link=elem("a","回到论文原页 ↗");link.href=paperHref(source);
      details.append(summary,quote,link);block.append(details);
    }
  }

  async function receive(context, expectedSession, controller, getCurrent, box) {
    if (!context) return;
    let raw;
    try { raw = JSON.parse(sessionStorage.getItem(transferKey) || "null"); } catch { return; }
    if (!raw || raw.projectId !== context.id || (raw.projectGeneration || 0) !== (context.conversationGeneration || 0) ||
        (raw.sessionId || "") !== (expectedSession || "")) return;
    const source = reference(raw);
    if (!source) throw new Error("论文摘录无效，或超过 2,800 个字符，请回到阅读器重新选择。");
    if (expectedSession && (session?.project_id !== context.id || session?.status === "closed"))
      throw new Error("所选会议已经结束或属于另一项目。请返回阅读器另选会议。");
    const alive = () => getCurrent() === context.id && (expectedSession ? session?.id === expectedSession : !session);
    if (!alive()) return;
    const paper = await request("/api/research/papers/" + enc(source.paperId));
    if (!alive()) return;
    if (paper.id !== source.paperId || !paper.project_ids?.includes(context.id))
      throw new Error("请先将这篇论文加入当前科研项目。");
    if (!paper.file_sha256 || (source.fingerprint && source.fingerprint !== paper.file_sha256))
      throw new Error("来源 PDF 已改变，请回到阅读器核对原文后再发送。");
    source.fingerprint = paper.file_sha256;
    source.title = short(paper.title || source.title, 210);
    const text = encodeReference(source);
    if (Array.from(text).length > 4000) throw new Error("选段与来源超过会议材料的长度限制，请缩短选段。");
    if (controller.busy() || controller.failed() || controller.items().length >= 12)
      throw new Error("会议材料已满或正在处理，请整理材料后从阅读器重新添加。");
    let material;
    if (raw.materialId && validId(raw.materialId)) {
      const old = controller.ready().find(item => item.id === raw.materialId);
      if (old) material = old;
    }
    if (!material) {
      const data = new FormData();
      data.append("file",new Blob([text],{type:"text/plain"}), "论文摘录 · " + short(source.title.replace(/[/\\]/g,"-"),65) + " · p" + source.page + ".txt");
      material = await request("/api/studio/materials","POST",data);
    }
    if (!alive()) return;
    const next = controller.ready();
    if (!next.some(item => item.id === material.id)) {
      if (controller.busy() || controller.failed() || controller.items().length >= 12)
        throw new Error("会议材料已变化，请回到阅读器重试。");
      controller.set([...next, material]);
    }
    if (!box.value.trim()) {
      box.value = "讨论《" + source.title + "》第 " + source.page + " 页的选段";
      box.dispatchEvent(new Event("input",{bubbles:true}));
    }
    sessionStorage.removeItem(transferKey);
  }

  const draftKey = draft => "sci-station.meeting-note." + draft.projectId + "." + draft.sessionId;
  function rememberDraft() {
    const draft=currentDraft;
    if (!draft || !ui || !draft.items.length || ui.form.hidden) return;
    const data={projectGeneration:draft.projectGeneration,operationId:draft.operationId,output:ui.output.value,target:ui.target.value,title:ui.title.value,body:ui.body.value,
      revision:draft.base?.revision || 0};
    try {localStorage.setItem(draftKey(draft),JSON.stringify(data));} catch { /* editing remains available */ }
  }
  function forgetDraft(draft) {
    if (draft) try {localStorage.removeItem(draftKey(draft));} catch {}
  }
  function restoredDraft(draft) {
    try {
      const saved=JSON.parse(localStorage.getItem(draftKey(draft)) || "null");
      return (saved?.projectGeneration || 0)===draft.projectGeneration ? saved : null;
    } catch {return null;}
  }
  function ensureDialog() {
    if (ui) return ui;
    const dialog = elem("dialog"); dialog.className="science-meeting-dialog";
    const heading = elem("h2","保存会议成果"); heading.id="science-dialog-title"; dialog.setAttribute("aria-labelledby",heading.id);
    const close = btn("关闭","science-text"); close.addEventListener("click",()=>dialog.close());
    const header = elem("header"); header.append(heading,close);
    const contextLine=elem("p"); contextLine.className="science-context";
    const evidence=elem("section"), form=elem("form"), status=elem("p"), body=elem("textarea"), title=elem("input");
    const output=elem("select"), target=elem("select"), cancel=btn("取消","button secondary");
    status.className="science-status";status.setAttribute("role","status");
    const field=(text,input)=>{const row=elem("label"),span=elem("span",text);row.append(span,input);return row;};
    body.rows=10;title.maxLength=200;
    const actions=elem("footer"),prepare=btn("提交审核","button primary"); actions.append(cancel,prepare);
    form.append(field("会议输出",output),field("保存位置",target),field("标题",title),field("待审正文",body),actions);
    const reviews=elem("section"); reviews.setAttribute("aria-label","科研笔记与任务审核");
    dialog.append(header,contextLine,evidence,form,reviews,status); document.body.append(dialog);
    cancel.addEventListener("click",()=>{forgetDraft(currentDraft);dialog.close();});
    const edit=()=>{if(currentDraft)currentDraft.operationId=null;rememberDraft();};
    body.addEventListener("input",edit); title.addEventListener("input",edit);
    dialog.addEventListener("close",()=>{currentDraft=null;});
    prepare.addEventListener("click",propose);
    output.addEventListener("change",()=>{selectOutput();edit();});
    target.addEventListener("change",()=>selectTarget().then(edit));
    form.addEventListener("submit",event=>{event.preventDefault();});
    ui={dialog,contextLine,evidence,form,status,body,title,output,target,accept:prepare,reviews};return ui;
  }

  function show() {
    if (!project || !session) return;
    const d = ensureDialog(), rows = outputs(session), refs=sources(session,project.id);
    currentDraft={sessionId:session.id,projectId:project.id,projectGeneration:project.conversationGeneration || 0,
      snapshot:session,items:rows,refs,base:null,notes:[],busy:false};
    d.contextLine.textContent=project.name + " · " + short(session.title || session.topic, 100);
    d.evidence.replaceChildren();
    if (refs.length) {
      const caption=elem("h3","会议共享的论文原文");d.evidence.append(caption);
      for (const source of refs) {
        const details=elem("details"),summary=elem("summary",(source.title || "论文") + " · 第 " + source.page + " 页");
        const quote=elem("blockquote",source.quote),link=elem("a","打开原文 ↗");link.href=paperHref(source);
        details.append(summary,quote,link);d.evidence.append(details);
      }
    }
    d.output.replaceChildren(...rows.map(row=>option(row.key,row.label)));d.target.replaceChildren(option("","新建项目笔记"),option(taskTarget,"新建项目任务"));
    d.form.hidden=!rows.length;d.title.disabled=false;d.status.textContent=rows.length?"":"议程和公开发言会在此显示。";
    d.accept.disabled=true;
    if (rows.length) selectOutput();
    d.reviews.replaceChildren();
    if (!d.dialog.open) d.dialog.showModal();
    const draft=currentDraft, restored=restoredDraft(draft);
    loadReviews(draft).catch(error=>{if(currentDraft===draft)d.status.textContent=error.message;});
    if (rows.length) request(projectURL(project.id)+"/notes").then(async notes=>{
      if(currentDraft!==draft)return;draft.notes=notes;
      for(const note of notes)d.target.append(option(note.id,note.title));
      d.accept.disabled=false;
      if (!restored || !rows.some(item=>item.key===restored.output)) return;
      d.output.value=restored.output;
      if (restored.target === taskTarget) {
        d.target.value=taskTarget; await selectTarget();
        d.title.value=restored.title; d.status.textContent="已恢复待审任务。";
      } else if (restored.target) {
        if (!notes.some(note=>note.id===restored.target)) {
          d.status.textContent="原目标笔记已移除。草稿已恢复，请重新选择保存位置。";
          d.target.selectedIndex=-1; d.accept.disabled=true;
        } else {
          d.target.value=restored.target; await selectTarget();
          if(currentDraft!==draft)return;
          if(draft.base && draft.base.revision !== restored.revision) {
            draft.base=null;d.target.selectedIndex=-1;d.accept.disabled=true;
            d.status.textContent="草稿已恢复。原笔记已有新版本，请重新选择保存位置并审核。";
          }
        }
      } else d.status.textContent="已恢复待审草稿。";
      d.body.value=restored.body; if (!restored.target) d.title.value=restored.title;
      draft.operationId=restored.operationId;
    }).catch(error=>{if(currentDraft===draft)d.status.textContent=error.message;});
  }

  function selectOutput() {
    const selected=currentDraft?.items.find(item=>item.key===ui.output.value);
    if (!selected) return;
    ui.body.value=selected.text;
    if (!ui.target.value || ui.target.value === taskTarget)
      ui.title.value=short(selected.title || ((session.title || session.topic)+" · "+selected.label),180);
  }
  async function selectTarget() {
    const d=ui, draft=currentDraft; if (!draft) return;
    const id=d.target.value;draft.base=null;
    d.accept.disabled=!!id;d.title.disabled=!!id;d.status.textContent="";
    if (!id || id===taskTarget) {
      d.accept.disabled=false;d.title.disabled=false;
      const selected=draft.items.find(item=>item.key===d.output.value);
      d.title.value=short(selected?.title || ((session.title || session.topic)+" · "+(selected?.label || "会议笔记")),180);
      return;
    }
    try {
      const note=await request(projectURL(draft.projectId)+"/notes/"+enc(id));
      if(currentDraft!==draft||d.target.value!==id)return;
      draft.base=note;d.title.value=note.title;d.accept.disabled=false;
      d.status.textContent="将追加到当前笔记末尾（版本 "+note.revision+"）。";
    } catch(error){if(currentDraft===draft)d.status.textContent=error.message;}
  }
  const reviewURL = draft => "/api/studio/sessions/"+enc(draft.sessionId)+"/research-reviews";
  function evidenceLink(review,e) {
    return window.SciEvidence.href(review.projectId,e);
  }
  function renderReviews(draft,rows) {
    if (currentDraft!==draft) return;
    const wrap=ui.reviews; wrap.replaceChildren();
    if (!rows.length) return;
    wrap.append(elem("h3","科研笔记与任务审核"));
    const requested=new URL(location.href).searchParams.get("review");
    const actions={"create-note":"新建笔记","create-task":"新建任务","append-note":"追加笔记"};
    for(const row of rows) {
      const item=elem("details"),pending=row.status==="pending";
      item.open=pending || row.id===requested;
      const summary=elem("summary",row.title+" · "+({pending:"待审核",accepted:"已写入",rejected:"已拒绝"}[row.status]||row.status));
      const destination=elem("p",actions[row.action]+" · "+project.name+"（项目版本 "+row.projectRevision+"）"+
          (row.destinationId?" · "+row.title+"（笔记版本 "+row.destinationRevision+"）":""));
      item.append(summary,destination,elem("pre",row.body));
      const original=elem("details");original.append(elem("summary","会议原文 · "+row.turnId),elem("pre",row.sourceText));
      item.append(original);
      for(const e of row.evidence||[]){
        const citation=elem("a",window.SciEvidence.label(e)+" ↗");citation.href=evidenceLink(row,e);
        item.append(elem("blockquote",e.quote),citation,elem("code",e.sourceHash));
      }
      if(pending) {
        const accept=btn("确认写入","button primary"),reject=btn("拒绝写入","button secondary");
        for(const [button,decision] of [[accept,"accept"],[reject,"reject"]])button.addEventListener("click",async()=>{
          accept.disabled=reject.disabled=true;
          try {
            const result=await request(reviewURL(draft),"POST",{projectId:draft.projectId,operationId:row.id,decision,revision:row.revision});
            if(currentDraft!==draft)return;
            if (draft.operationId===result.id && result.status==="rejected") {draft.operationId=null;rememberDraft();}
            renderReviews(draft,rows.map(x=>x.id===result.id?result:x));
            ui.status.textContent=result.status==="accepted"?"已写入「"+result.title+"」。":"已拒绝写入。";
          } catch(error){if(currentDraft===draft){ui.status.textContent=error.message;accept.disabled=reject.disabled=false;}}
        });
        item.append(reject,accept);
      }
      wrap.append(item);
    }
  }
  async function loadReviews(draft) {
    const rows=await request(projectURL(draft.projectId)+"/reviews?meeting="+enc(draft.sessionId));
    renderReviews(draft,rows);
    return rows;
  }
  async function propose() {
    const d=ui,draft=currentDraft;if(!draft||draft.busy)return;
    const selected=draft.items.find(item=>item.key===d.output.value),target=d.target.value;
    const title=d.title.value.trim(),body=d.body.value.trim();
    if(!selected||!title||!body){d.status.textContent="请填写待审标题与正文。";return;}
    if(d.target.selectedIndex<0 || (target && target!==taskTarget && draft.base?.id!==target))return;
    const proposal={turnId:selected.key,title,body,action:target===taskTarget?"create-task":target?"append-note":"create-note",
      projectRevision:project.revision,destinationId:draft.base?.id||"",destinationRevision:draft.base?.revision||0};
    draft.operationId ||= crypto.randomUUID().replaceAll("-","");
    rememberDraft();
    draft.busy=true; d.accept.disabled=d.target.disabled=d.output.disabled=true;d.body.readOnly=d.title.readOnly=true;
    try {
      await request(reviewURL(draft),"POST",{operationId:draft.operationId,projectId:draft.projectId,decision:"propose",proposal});
      if(currentDraft!==draft)return;
      await loadReviews(draft);
      if(currentDraft!==draft)return;
      d.status.textContent="请核对下方的目标、内容与来源，再确认或拒绝写入。";
    } catch(error){if(currentDraft===draft)d.status.textContent=error.message;}
    finally{
      draft.busy=false;
      if(currentDraft===draft){d.accept.disabled=d.target.disabled=d.output.disabled=false;d.body.readOnly=d.title.readOnly=false;}
    }
  }

  window.ScienceMeeting={loadProjects,requestedProject,update,receive};
})();
