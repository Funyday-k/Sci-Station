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
    return {projectId:input.projectId, paperId:input.paperId, page, title:short(input.title, 210),
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
  let projects = [], session = null, project = null, btnOpen, fetched = false, ui;
  let currentDraft = null;

  async function loadProject() {
    // Resolve all paths before accepting a reader handoff. The same workspace
    // is used for the meeting, the attachment and the eventual note.
    projects = await request("/api/research/projects");
    fetched = true;
    const id = url.searchParams.get("project");
    if (!id) return null;
    const result = projects.find(item => item.id === id);
    if (!result) throw new Error("科研项目已移除，无法将这次阅读发送到圆桌。");
    return result;
  }

  function update(next, draftPath) {
    session = next || null;
    project = session && projects.find(item => item.path === session.project) || null;
    if (!btnOpen && byId("chat-toolbar")) {
      btnOpen = btn("科研记录", "science-meeting-open"); btnOpen.title = "核对论文原文、保存笔记或建立项目任务";
      btnOpen.addEventListener("click", show);
      byId("chat-toolbar").insertBefore(btnOpen, byId("meeting-actions"));
    }
    if (btnOpen) btnOpen.hidden = !project;
    renderReportSources();
    if (currentDraft && (currentDraft.sessionId !== session?.id || currentDraft.projectId !== project?.id)) ui?.dialog.close();
    const param = new URL(location.href);
    if ((session || draftPath) && fetched) {
      const active = project || projects.find(item => item.path === draftPath);
      if (active) param.searchParams.set("project",active.id); else param.searchParams.delete("project");
      history.replaceState(null,"",param);
    }
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
    if (!raw || raw.projectId !== context.id || (raw.sessionId || "") !== (expectedSession || "")) return;
    const source = reference(raw);
    if (!source) throw new Error("论文摘录无效，或超过 2,800 个字符，请回到阅读器重新选择。");
    if (expectedSession && (session?.project !== context.path || session?.status === "closed"))
      throw new Error("所选会议已经结束或属于另一项目。请返回阅读器另选会议。");
    const alive = () => getCurrent() === context.path && (expectedSession ? session?.id === expectedSession : !session);
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
    const data={output:ui.output.value,target:ui.target.value,title:ui.title.value,body:ui.body.value,
      revision:draft.base?.revision || 0};
    try {localStorage.setItem(draftKey(draft),JSON.stringify(data));} catch { /* editing remains available */ }
  }
  function forgetDraft(draft) {
    if (draft) try {localStorage.removeItem(draftKey(draft));} catch {}
  }
  function restoredDraft(draft) {
    try {return JSON.parse(localStorage.getItem(draftKey(draft)) || "null");} catch {return null;}
  }
  function ensureDialog() {
    if (ui) return ui;
    const dialog = elem("dialog"); dialog.className="science-meeting-dialog";
    const heading = elem("h2","保存会议成果"); heading.id="science-dialog-title"; dialog.setAttribute("aria-labelledby",heading.id);
    const close = btn("关闭","science-text"); close.addEventListener("click",()=>dialog.close());
    const header = elem("header"); header.append(heading,close);
    const contextLine=elem("p"); contextLine.className="science-context";
    const evidence=elem("section"), form=elem("form"), status=elem("p"), body=elem("textarea"), title=elem("input");
    const output=elem("select"), target=elem("select"), accept=btn("确认写入","button primary"), cancel=btn("取消","button secondary");
    status.className="science-status";status.setAttribute("role","status");
    const field=(text,input)=>{const row=elem("label"),span=elem("span",text);row.append(span,input);return row;};
    body.rows=10;title.maxLength=200;
    const actions=elem("footer"); actions.append(cancel,accept);
    form.append(field("会议输出",output),field("保存位置",target),field("标题",title),field("确认写入的正文",body),actions);
    dialog.append(header,contextLine,evidence,form,status); document.body.append(dialog);
    cancel.addEventListener("click",()=>{forgetDraft(currentDraft);dialog.close();});
    body.addEventListener("input",rememberDraft);
    title.addEventListener("input",rememberDraft);
    dialog.addEventListener("close",()=>{currentDraft=null;});
    accept.addEventListener("click",save);
    output.addEventListener("change",()=>{selectOutput();rememberDraft();});
    target.addEventListener("change",()=>selectTarget().then(rememberDraft));
    form.addEventListener("submit",event=>{event.preventDefault();});
    ui={dialog,contextLine,evidence,form,status,body,title,output,target,accept};return ui;
  }

  function show() {
    if (!project || !session) return;
    const d = ensureDialog(), rows = outputs(session), refs=sources(session,project.id);
    currentDraft={sessionId:session.id,projectId:project.id,snapshot:session,items:rows,refs,base:null,notes:[],busy:false};
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
    if (!d.dialog.open) d.dialog.showModal();
    const draft=currentDraft, restored=restoredDraft(draft);
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
  async function save() {
    const d=ui,draft=currentDraft; if (!draft||draft.busy) return;
    const selected=draft.items.find(item=>item.key===d.output.value), body=d.body.value.trim(), target=d.target.value;
    const title=d.title.value.trim();
    if(!selected||!title||!body){d.status.textContent="请输入标题与正文后写入。";return;}
    if(d.target.selectedIndex<0 || (target && target!==taskTarget && draft.base?.id!==target))return;
    const route=projectURL(draft.projectId)+"/notes", key="meeting:"+draft.sessionId+":"+selected.key;
    const self="/studio?"+new URLSearchParams({project:draft.projectId,session:draft.sessionId})+
      (selected.round?"#round-"+selected.round+"-"+encodeURIComponent(selected.seat):"");
    const markerText="<!-- sci-station:"+key+" -->";
    const shared = sources(draft.snapshot, draft.projectId, selected.round);
    const refs = shared.map(source => ({paperId:source.paperId,page:source.page,quote:source.quote,
      sourceHash:source.fingerprint,meetingId:draft.sessionId,turnId:selected.key}));
    const content=body+"\n\n[查看会议记录]("+self+")"+(shared.length?"\n\n会议共享原文\n"+
      shared.map(source=>"- [第 "+source.page+" 页]("+paperHref(source)+") "+source.title.replace(/[\r\n]/g," ")).join("\n"):"")+"\n\n"+markerText;
    draft.busy=true;d.accept.disabled=true;d.target.disabled=true;d.output.disabled=true;d.body.readOnly=true;
    try {
      let saved, replayed = false;
      if(target===taskTarget) {
        const description=content.replace("\n\n"+markerText,"");
        saved=await request(projectURL(draft.projectId)+"/tasks","POST",{title,description,status:"open",
          paperId:refs.length===1?refs[0].paperId:"",idempotencyKey:key});
        replayed=saved?.description!==description;
      } else if(target) {
        if(!draft.base.body?.includes(markerText)) {
          const existing=draft.base.evidence||[];
          saved = await request(route+"/"+enc(target),"PATCH",{revision:draft.base.revision,
            body:(draft.base.body||"").trimEnd()+"\n\n"+content,evidence:[...existing,...refs]});
        } else {saved = draft.base; replayed = true;}
      } else {
        saved = await request(route,"POST",{title,body:content,idempotencyKey:key,sourceMeetingId:draft.sessionId,sourceTurnId:selected.key,evidence:refs});
      }
      forgetDraft(draft);
      if(currentDraft===draft){
        d.status.textContent=(replayed || (!target && saved?.body !== content) ? "此份输出已保存在「":"已保存到「") + (saved?.title || title) + "」。";
        d.form.hidden=true;
      }
    } catch(error) {
      if(currentDraft===draft) {
        d.status.textContent=error.status===409?"原笔记已由其他窗口修改。请重新选择保存位置，核对新版本后再写入。":error.message;
        if(error.status===409 && target && target!==taskTarget){draft.base=null;d.target.selectedIndex=-1;}
      }
    } finally {
      draft.busy=false;d.target.disabled=false;d.output.disabled=false;d.body.readOnly=false;
      d.accept.disabled=!!target&&target!==taskTarget&&!draft.base;
    }
  }

  window.ScienceMeeting={loadProject,update,receive};
})();
