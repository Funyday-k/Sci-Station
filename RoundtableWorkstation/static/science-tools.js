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
    const headers = minerSession ? {"X-Sci-Station-Miner-Session": minerSession} : {};
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
    if (minerSession || typeof window.sciStationMinerSession !== "string" || !window.sciStationMinerSession) return;
    minerSession = window.sciStationMinerSession;
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

  function nav() {
    for (const a of document.querySelectorAll("[data-tab]")) {
      a.classList.toggle("active", a.dataset.tab === tab);
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

  function renderResult(md, paper, sequence) {
    if (sequence !== conversionSequence || $("paper").value !== paper.id) return;
    result = {
      paper,
      key: crypto.randomUUID(),
      saved: new Map()
    };
    $("markdown").value = md;
    $("result").hidden = false;
    tell("转换完成，可以编辑、导出或保存到项目");
  }

  function selectedPaper() {
    const paper = papers.find(p => p.id === $("paper").value);
    if (!paper) throw Error("请先在文献库中导入一份 PDF");
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
    if (tab === "discover") discovery = SciStationDiscovery.create({$, req, make, button, busy, tell});
    $("project").onchange = () => {
      project = $("project").value;
      const l = new URL(location);
      if (project) l.searchParams.set("project", project);
      else l.searchParams.delete("project");
      history.replaceState(null, "", l);
      loadProject().catch(e => tell(e.message));
    };
    $("paper").onchange = () => {
      conversionSequence++;
      result = null;
      $("result").hidden = true;
      $("batch").value = "";
    };
    $("local").onclick = () => busy($("local"), async () => {
      const p = selectedPaper(),
        seq = ++conversionSequence;
      tell("正在从原文提取…");
      const md = await req("papers/" + p.id + "/markdown", undefined, "text");
      renderResult(md, p, seq);
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
        renderResult((await minerReq("result", d)).markdown, p, seq);
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
    $("download").onclick = () => saveBlob(new Blob([$("markdown").value], {
      type: "text/markdown"
    }), result.paper.title.replace(/[\/\\:]/g, "-") + ".md");
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
    $("events").onclick = () => busy($("events"), async () => {
      tell("正在读取系统日历…");
      const events = await req("tools/events", {});
      $("eventList").replaceChildren(...events.map(e => make("p", e.start.slice(0, 16).replace("T", " ") + " · " + e.title + " · " + e.calendar)));
      tell(events.length ? "已读取 " + events.length + " 项" : "未来 30 天没有日历事件");
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
    $("heading").textContent = views[tab];
    nav();
    initActions();
    if (tab === "convert") {
      window.addEventListener("scistation:miner-session", enableMinerCredential);
      enableMinerCredential();
    }
    projects = await req("projects");
    const choicesList = projects.map(p => [p.id, p.name]);
    if (tab === "discover") choicesList.unshift(["", "整个文献库"]);
    if (tab === "calendar") choicesList.unshift(["", "全部项目"]);
    choices($("project"), choicesList, "未选择项目");
    if (project && !projects.some(p => p.id === project)) throw Error("所选项目不存在或已归档");
    if (!project && tab === "convert") project = projects[0]?.id || "";
    $("project").value = project;
    await loadProject();
    if (tab === "convert") {
      papers = (await req("papers")).filter(p => p.has_pdf);
      choices($("paper"), papers.map(p => [p.id, p.title]), "暂无本地 PDF");
      if (qs.get("paper") && papers.some(p => p.id === qs.get("paper"))) $("paper").value = qs.get("paper");
      $("local").disabled = !papers.length;
    }
  }
  init().catch(e => tell(e.message));
})();
