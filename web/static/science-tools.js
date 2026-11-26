"use strict";
(() => {
  const $ = id => document.getElementById(id);
  const qs = new URLSearchParams(location.search);
  let project = qs.get("project") || "",
    papers = [],
    projects = [],
    projectLoad = 0,
    tasks = [],
    reminderBusy = false,
    scheduleItems = [],
    scheduleRequest = 0,
    discovery,
    conversionSequence = 0,
    result = null,
    minerSession = "",
    minerConfigured = false,
    minerCredentialBusy = false;
  const views = {
    discover: "文献发现",
    convert: "PDF 转换",
    calendar: "系统日历与提醒"
  };
  const tab = Object.hasOwn(views, qs.get("tab")) ? qs.get("tab") : "discover";
  const apiBase = "/api/research/";
  async function req(route, body, format = "json", method = "POST", extraHeaders = {}) {
    const options = body === undefined ? {} : {
      method,
      headers: {
        "X-Roundtable": "1",
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    };
    if(typeof FormData!=="undefined" && body instanceof FormData){options.body=body;delete options.headers["Content-Type"];}
    options.headers = {...options.headers, ...extraHeaders};
    const response = await fetch(apiBase + route, options);
    if (!response.ok) {
      const raw = await response.text();
      let msg = raw;
      try {
        msg = JSON.parse(raw).error || raw;
      } catch {}
      throw Error(msg || "请求失败");
    }
    return response[format]();
  }

  function minerReq(route, body, format) {
    const headers = minerSession ? {"X-Sci-Station-Credential-Session": minerSession} : {};
    return req("tools/mineru/" + route, body, format, "POST", headers);
  }

  function showMinerCredential(configured) {
    minerConfigured = configured;
    $("minerCredentialState").textContent = configured ? "此工作区的 Token 已保存在 macOS 钥匙串。输入框留空时使用已保存的 Token。" : "尚未在 macOS 钥匙串保存 Token。";
  }

  async function updateMinerCredential(input) {
    if (minerCredentialBusy) return;
    minerCredentialBusy = true;
    $("minerSave").disabled = true;
    $("minerClear").disabled = true;
    try {
      const state = await minerReq("credential", input);
      showMinerCredential(state.configured);
      if (input?.action === "save" && $("token").value === input.token) $("token").value = "";
    } catch (e) {
      if (input) tell(e.message);
      else $("minerCredentialState").textContent = e.message;
    } finally {
      minerCredentialBusy = false;
      $("minerSave").disabled = false;
      $("minerClear").disabled = !minerConfigured;
    }
  }

  function enableMinerCredential() {
    if (minerSession || typeof window.sciStationCredentialSession !== "string" || !window.sciStationCredentialSession) return;
    minerSession = window.sciStationCredentialSession;
    $("minerCredentialActions").hidden = false;
    $("minerCredentialState").textContent = "正在检查钥匙串…";
    return updateMinerCredential();
  }

  function make(tag, text) {
    const e = document.createElement(tag);
    e.textContent = text;
    return e;
  }

  function button(label, cb) {
    const e = make("button", label);
    e.type = "button";
    e.onclick = () => busy(e, cb);
    return e;
  }

  function tell(msg) {
    $("status").textContent = msg;
  }
  async function busy(el, fn) {
    el.disabled = true;
    try {
      await fn();
    } catch (e) {
      tell(e.message);
    } finally {
      el.disabled = false;
    }
  }

  function saveBlob(blob, name) {
    const a = document.createElement("a"),
      u = URL.createObjectURL(blob);
    a.href = u;
    a.download = name;
    a.click();
    setTimeout(() => URL.revokeObjectURL(u), 30000);
  }

  function choices(el, list, empty) {
    el.replaceChildren();
    if (!list.length) {
      el.add(new Option(empty, ""));
      return;
    }
    for (const [id, label] of list) el.add(new Option(label, id));
  }

  const scheduleSource = item => item.kind + ":" + (item.calendarId || item.calendar);
  const selectedSources = () => new Set(Array.from($("calendar-source").selectedOptions, option => option.value));
  function showSchedule() {
    const sources = selectedSources();
    const rows = scheduleItems.filter(item => !sources.size || sources.has(scheduleSource(item)));
    $("eventList").replaceChildren(...(rows.length ? rows.map(item => {
      const date = item.kind === "reminder" && !item.hasTime ? item.start.slice(0, 10) : item.start.slice(0, 16).replace("T", " ");
      return make("p", [date, item.title, item.calendar || (item.kind === "reminder" ? "提醒事项" : "日历")].join(" · "));
    }) : [make("p", "这个范围内没有日历事件或未完成提醒。")]));
  }

  async function readSchedule(prompt) {
    const date = $("calendar-date");
    if (!date.reportValidity()) return;
    const sequence = ++scheduleRequest;
    const reference = date.value;
    tell("正在读取系统日历与提醒事项…");
    const result = await req("tools/schedule", {reference, prompt});
    if (sequence !== scheduleRequest || reference !== date.value) return;
    scheduleItems = result.items;
    const source = $("calendar-source");
    const prior = selectedSources();
    const sources = new Map(scheduleItems.map(item => [scheduleSource(item), item.calendar || (item.kind === "reminder" ? "提醒事项" : "日历")]));
    source.replaceChildren(...Array.from(sources, ([id, label]) => new Option(label, id, false, prior.has(id))));
    showSchedule();
    tell([result.eventsError, result.remindersError].filter(Boolean).join(" ") || "已读取 " + scheduleItems.length + " 项");
  }

  function nav() {
    for (const a of document.querySelectorAll("[data-tab]")) {
      a.classList.toggle("active", a.dataset.tab === tab);
      if (a.dataset.tab === tab) a.setAttribute("aria-current", "page");
      else a.removeAttribute("aria-current");
      const u = new URLSearchParams({
        tab: a.dataset.tab
      });
      if (project) u.set("project", project);
      a.href = "?" + u;
    }
    globalThis.SciStationNav?.update();
  }
  async function loadProject() {
    const target = project, generation = ++projectLoad;
    nav();
    $("reminder").disabled = true;
    if (tab === "discover") {
      await discovery.load(target);
    } else if (tab === "calendar") {
      tasks = [];
      choices($("task"), [], "正在读取任务…");
      const loaded = await req(target ? "projects/" + encodeURIComponent(target) + "/tasks" : "tasks");
      if (generation !== projectLoad) return;
      tasks = loaded.filter(t => t.status !== "done" && t.status !== "cancelled");
      choices($("task"), tasks.map(t => [t.id, t.title]), "暂无待处理任务");
      updateReminderAction();
    }
  }

  function updateReminderAction() {
    $("reminder").disabled = reminderBusy || !tasks.some(t => t.id === $("task").value);
  }

  function renderResult(md, paper, sequence, source, quality) {
    if (sequence !== conversionSequence || $("paper").value !== paper.id) return;
    result = {
      paper,original:md,source,
      key: crypto.randomUUID(),
      saved: new Map()
    };
    $("markdown").value = md;
    window.SciPaperBodyPreview.quality($("resultQuality"), quality);
    window.SciPaperBodyPreview.renderFigures($("resultFigures"), quality?.figures);
    $("result").hidden = false;
    $("saveBody").disabled=!source || (source.kind==="mineru" && !source.bound);
    tell("转换完成，可以编辑、导出或保存到项目");
  }

  function paperBodyStatus() {
    const p=papers.find(row=>row.id===$("paper").value),body=p?.markdown_source;
    $("bodyState").textContent=body?"已存论文正文 · 版本 "+body.revision+" · "+({pdfkit:"PDFKit 转换",mineru:"MinerU 转换",import:"导入文件"}[body.origin] || body.origin):
      (p?.has_pdf?"已有 PDF，尚无 Markdown 正文。":"尚无 PDF 或 Markdown 正文。");
    $("existingBody").hidden=!body;

    for(const id of ["local","remote","checkBatch","getZip"]) $(id).disabled=!p?.has_pdf;
    $("importBody").disabled=!p;
  }

  function savedBody(updated) {
    const i=papers.findIndex(p=>p.id===updated.id);
    if(i>=0) papers[i]=updated;
    if($("paper").value===updated.id){paperBodyStatus();tell("已保存论文正文版本 "+updated.markdown_source.revision+"。");}
  }
  function allowReplace(p) {
    return !p.markdown_source || confirm("更新这篇论文的正文版本？依赖旧指纹的选段仍会保留在会话中，写入前需要重新核对。");
  }
  function selectedPaper() {
    const paper = papers.find(p => p.id === $("paper").value);
    if (!paper) throw Error("请先选择文献库中的论文");
    return paper;
  }

  function remoteData() {
    return {
      paper: selectedPaper().id,
      token: $("token").value,
      batch: $("batch").value.trim()
    };
  }

  function initActions() {
    if (tab === "discover") discovery = SciStationDiscovery.create({$, req, make, button, busy, tell, trigger: qs.get("trigger") === "lab" ? "lab" : ""});
    $("project").onchange = () => {
      project = $("project").value;
      const l = new URL(location);
      if (project) l.searchParams.set("project", project);
      else l.searchParams.delete("project");
      window.SciStationNav.commitURL(l,"push");
      loadProject().catch(e => tell(e.message));
    };
    $("paper").onchange = () => {
      conversionSequence++;
      result = null;
      $("result").hidden = true;
      $("batch").value = ""; $("bodyFile").value="";$("bodyFull").hidden=true;$("bodyLocator").hidden=true; paperBodyStatus();
    };
    $("local").onclick = () => busy($("local"), async () => {
      const p = selectedPaper(),
        seq = ++conversionSequence;
      tell("正在从原文提取…");
      const output = await req("papers/" + p.id + "/markdown?format=preview");
      renderResult(output.markdown, p, seq, {kind:"pdfkit"}, output.quality);
    });
    $("remote").onclick = () => busy($("remote"), async () => {
      const v = remoteData(),
        seq = ++conversionSequence;
      if (!v.token.trim() && !minerSession) throw Error("请输入 MinerU API Token");
      if (!confirm("将这篇 PDF 上传到 MinerU 进行转换？")) return;
      tell("正在上传…");
      const s = await minerReq("start", v);
      if (seq !== conversionSequence || v.paper !== $("paper").value) return;
      $("batch").value = s.batch;
      tell("已提交转换。任务编号可用于稍后查看进度。");
    });
    $("checkBatch").onclick = () => busy($("checkBatch"), async () => {
      const p = selectedPaper(),
        d = remoteData(),
        seq = ++conversionSequence,
        s = await minerReq("status", d);
      if (seq !== conversionSequence) return;
      if (s.state === "done") {
        const output=await minerReq("result",d);
        renderResult(output.markdown, p, seq, {
          kind:"mineru", batch:d.batch, bound:output.bound, hash:output.sha256, assetsHash:output.assetsSha256
        }, output.quality);
      } else tell("MinerU 任务状态：" + s.state);
    });
    $("getZip").onclick = () => busy($("getZip"), async () => {
      const d = remoteData(),
      s = await minerReq("status", d);
      if (s.state !== "done") throw Error("结果尚未完成：" + s.state);
      saveBlob(await minerReq("result?format=zip", d, "blob"), "MinerU-" + d.paper + ".zip");
    });
    $("minerSave").onclick = () => updateMinerCredential({action: "save", token: $("token").value});
    $("minerClear").onclick = () => {
      if (confirm("清除此工作区保存在 macOS 钥匙串中的 MinerU Token？")) {
        return updateMinerCredential({action: "clear"});
      }
    };
    $("existingBody").onclick=()=>busy($("existingBody"),async()=>{
      const p=selectedPaper(),seq=conversionSequence;
      const body=await req("papers/"+p.id+"/body/preview");
      if(seq!==conversionSequence || p.id!==$("paper").value)return;
      const format = window.SciPaperBodyPreview;
      const figures = body.quality.figures;
      format.quality($("bodyQuality"), body.quality);
      format.renderFigures($("bodyFigures"), figures, {paper:p.id, hash:body.hash});
      const limit = 120000;
      const cut = body.markdown.codePointAt(limit - 1) > 0xffff ? limit + 1 : limit;
      $("bodyPreviewLimit").hidden = body.markdown.length <= cut;
      window.SciMarkdown.render($("bodyRendered"), body.markdown.slice(0, cut), {
        allowHTML:true, headingShift:1, resolveImage:format.resolveImages(p.id, body.hash, figures)
      });
      $("bodyFullText").textContent=body.markdown;
      $("bodyFull").hidden=false;
      $("bodyFull").open=true;
    });
    $("importBody").onclick=()=>busy($("importBody"),async()=>{
      const p=selectedPaper(),file=$("bodyFile").files[0];
      if(!file) throw Error("请选择这篇论文的 Markdown 原文文件。");
      if(!allowReplace(p))return;
      const data=new FormData();data.append("revision",p.revision);data.append("file",file,file.name);
      const updated=await req("papers/"+p.id+"/body",data);
      if($("paper").value===p.id)$("bodyFile").value="";savedBody(updated);
    });
    $("saveBody").onclick=()=>busy($("saveBody"),async()=>{
      const r=result,p=selectedPaper();
      if(!r || r.paper.id!==p.id || r.paper.revision!==p.revision)throw Error("请重新预览当前论文的转换结果。");
      if($("markdown").value!==r.original.replace(/\r\n?/g,"\n"))throw Error("编辑后的文本可存为项目笔记。要保存转换原文，请重新预览。");
      if(!allowReplace(p))return;
      const updated=r.source.kind==="pdfkit"?await req("papers/"+p.id+"/body",{action:"convert",revision:p.revision}):
        await minerReq("result",{...remoteData(),paper:p.id,batch:r.source.batch,saveSource:true,revision:p.revision,expectedHash:r.source.hash,expectedAssetsHash:r.source.assetsHash});
      savedBody(updated);
    });
    $("download").onclick = () => {
      const edited = $("markdown").value;
      const markdown = edited === result.original.replace(/\r\n?/g, "\n") ? result.original : edited;
      saveBlob(new Blob([markdown], {type:"text/markdown"}), result.paper.title.replace(/[\/\\:]/g, "-") + ".md");
    };
    $("saveNote").onclick = () => busy($("saveNote"), async () => {
      if (!project || !result) throw Error("请先选择一个科研项目和转换结果");
      const source = result,
        target = project,
        base = "projects/" + target + "/notes";
      const p = source.paper,
        body = $("markdown").value,
        title = p.title + " · 转换稿";
      let prior = source.saved.get(target);
      if (!prior) {
        prior = (await req(base)).find(n => n.paperId === p.id && n.title === title);
        if (prior && !confirm("该项目已有这篇论文的转换稿，将用当前内容更新。继续？")) return;
      }
      const saved = prior ? await req(base + "/" + prior.id, {
          revision: prior.revision,
          body
        }, "json", "PATCH") :
        await req(base, {
          title,
          body,
          paperId: p.id,
          idempotencyKey: source.key
        });
      source.saved.set(target, saved);
      tell("已保存至项目笔记");
    });
    $("events").onclick = () => busy($("events"), () => readSchedule(false));
    $("calendar-connect").onclick = () => busy($("calendar-connect"), () => readSchedule(true));
    $("calendar-date").onchange = () => {
      scheduleItems = [];
      $("calendar-source").replaceChildren();
      $("eventList").replaceChildren(make("p", "刷新以读取所选月份。"));
      tell("");
    };
    $("calendar-source").onchange = showSchedule;
    $("reminder-sync").onclick = () => busy($("reminder-sync"), async () => {
      const date = $("calendar-date");
      if (!date.reportValidity()) return;
      const generation = projectLoad;
      const result = await req("tools/reminder-sync", {reference: date.value, project});
      if (generation === projectLoad) {
        await loadProject();
        tell("已同步 " + result.updated + " 项" + (result.conflicts ? "，保留 " + result.conflicts + " 项修改或冲突" : ""));
      }
    });
    $("task").onchange = updateReminderAction;
    $("reminder").onclick = async () => {
      const selected = tasks.find(t => t.id === $("task").value);
      if (!selected || reminderBusy) return;
      const generation = projectLoad;
      reminderBusy = true;
      updateReminderAction();
      tell("正在将任务写入 Apple 提醒事项…");
      try {
        await req("tools/reminder", {project: selected.projectId, task: selected.id});
        if (generation === projectLoad) tell("已保存到 Apple 提醒事项");
      } catch (err) {
        if (generation === projectLoad) tell(err.message);
      } finally {
        reminderBusy = false;
        updateReminderAction();
      }
    };
  }
  async function init() {
    $(tab).hidden = false;
    const updateTitle = () => {
      const english = {discover:"Discover papers", convert:"PDF conversion", calendar:"System calendar and reminders"};
      $("heading").textContent = window.SciStationI18n?.text(views[tab], english[tab]) || views[tab];
    };
    updateTitle();
    window.addEventListener("sci:language", updateTitle);
    if (tab === "calendar") {
      const today = new Date();
      const localDate = new Date(today.getTime() - today.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
      $("calendar-date").value = /^\d{4}-\d{2}-\d{2}$/.test(qs.get("date") || "") ? qs.get("date") : localDate;
    }
    nav();
    initActions();
    if (tab === "convert") {
      window.addEventListener("scistation:credential-session", enableMinerCredential);
      enableMinerCredential();
    }
    projects = await req("projects");
    const choicesList = projects.map(p => [p.id, p.name]);
    if (tab === "discover") choicesList.unshift(["", "整个文献库"]);
    if (tab === "calendar") choicesList.unshift(["", "全部项目"]);
    choices($("project"), choicesList, "未选择项目");
    if (project && !projects.some(p => p.id === project)) throw Error("所选项目不存在或已归档");
    if (!project && tab !== "discover") choices($("project"), [["","请选择项目"], ...choicesList], "未选择项目");
    $("project").value = project;
    await loadProject();
    if (tab === "convert") {
      papers = await req("papers");
      const target = qs.get("paper");
      const missing = target && !papers.some(p => p.id === target);
      const options = papers.map(p => [p.id, p.title]);
      if (missing) options.unshift(["", "所选文献不可用"]);
      choices($("paper"), options, "暂无本地 PDF");
      if (target && !missing) $("paper").value = target;
      if (missing) tell("所选文献已移除或不可用。请选择另一篇文献。");
      paperBodyStatus();
      if(qs.has("fingerprint") && qs.has("offset") && qs.has("end") && qs.get("paper") && project) {
        $("bodyLocator").hidden=false;
        const seq=conversionSequence, scope=project;
        try {
          const location=new URLSearchParams({offset:qs.get("offset"),end:qs.get("end"),fingerprint:qs.get("fingerprint")});
          const hit=await req("projects/"+encodeURIComponent(project)+"/source-excerpts/paper-markdown/"+encodeURIComponent(qs.get("paper"))+"?"+location);
          if(seq!==conversionSequence || scope!==project) return;
          $("bodyLocatorStatus").textContent=hit.title+" · 版本 "+hit.revision+" · 第 "+hit.line+" 行，第 "+hit.column+" 列";
          const mark=document.createElement("mark");mark.textContent=hit.quote;
          $("bodyLocatorText").replaceChildren(document.createTextNode(hit.before),mark,document.createTextNode(hit.after));
          window.SciPaperBodyPreview.renderFigures($("bodyLocatorFigures"), hit.figures, {paper:qs.get("paper"),hash:qs.get("fingerprint")});
        } catch(error){if(seq===conversionSequence && scope===project)$("bodyLocatorStatus").textContent="无法核对已保存的引文。"+error.message;}
      }
    }
  }
  globalThis.addEventListener?.("popstate",()=>{
    project=new URL(location.href).searchParams.get("project") || "";
    $("project").value=project;
    loadProject().catch(e=>tell(e.message));
  });
  init().catch(e => tell(e.message));
})();
