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
    discovery = {
      items: [],
      feedback: {}
    },
    conversionSequence = 0,
    result = null;
  const views = {
    discover: "文献发现",
    convert: "PDF 转换",
    calendar: "系统日历与提醒"
  };
  const tab = Object.hasOwn(views, qs.get("tab")) ? qs.get("tab") : "discover";
  const apiBase = "/api/research/";
  async function req(route, body, format = "json", method = "POST") {
    const options = body === undefined ? {} : {
      method,
      headers: {
        "X-Roundtable": "1",
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    };
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
  function scoped(route, target = project) {
    return target ? route + "?project=" + encodeURIComponent(target) : route;
  }

  async function loadProject() {
    const target = project, generation = ++projectLoad;
    nav();
    $("reminder").disabled = true;
    if (tab === "discover") {
      discovery = {items: [], feedback: {}};
      papers = [];
      $("articles").replaceChildren();
      $("readingQueue").replaceChildren();
      $("expr").value = "";
      const [feed, library, queue] = await Promise.all([
        req(scoped("tools/discover", target)), req(scoped("papers", target)), req(scoped("papers/recommendations", target))
      ]);
      if (generation !== projectLoad) return;
      discovery = feed;
      papers = library;
      $("expr").value = discovery.query || "";
      showQueue(queue);
      showFeed();
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

  async function readingTask(p, target) {
    await req("projects/" + encodeURIComponent(target) + "/tasks", {
      title: Array.from("阅读：" + p.title).slice(0, 240).join(""),
      paperId: p.id, idempotencyKey: "reading:" + p.id
    });
  }

  function showQueue(queue) {
    const list = $("readingQueue");
    list.replaceChildren();
    const target = project;
    for (const p of queue) {
      const row = make("article", "");
      const a = make("a", p.title);
      a.href = "/reader?paper=" + encodeURIComponent(p.id) + (target ? "&project=" + encodeURIComponent(target) : "");
      row.append(a);
      if (target) row.append(button("加入阅读待办", async () => {
        await readingTask(p, target);
        if (project === target) tell("阅读待办已就绪");
      }));
      list.append(row);
    }
    if (!queue.length) list.append(make("p", "暂无待阅读的馆藏论文。"));
  }

  function importCandidate(p, target) {
    return req("papers", {
      title: p.title, authors: p.authors || [], abstract: p.abstract || "", arxiv: p.arxiv,
      doi: p.doi || "", url: p.url, year: p.year || 0, tags: p.tags || [],
      project_ids: target ? [target] : []
    });
  }

  function showFeed() {
    const list = $("articles");
    list.replaceChildren();
    const mode = $("filter").value;
    const target = project;
    const candidates = SciStationDiscovery.candidates(discovery, {
      category: $("categories").value, crossList: $("crossList").checked, filter: mode,
      project: projects.find(p => p.id === target), papers
    });
    for (const p of candidates) {
      const status = SciStationDiscovery.feedbackState(discovery.feedback || {}, p.arxiv);
      const art = make("article", ""),
        h = make("h3", p.title);
      art.append(h, make("div", [(p.authors || []).join(", "), p.arxiv, ...(p.tags || [])].filter(Boolean).join(" · ")));
      const more = make("details", "");
      more.append(make("summary", "摘要"), make("p", p.abstract || "暂无摘要"));
      art.append(more);
      const actions = make("div", "");
      actions.className = "actions";
      actions.append(button("加入文献库", async () => {
          await importCandidate(p, target);
          if (project === target) { await loadProject(); tell("论文已加入文献库"); }
        }),
        button(status === "saved" ? "取消收藏" : "收藏", () => feedback(p, status === "saved" ? "" : "saved", target)),
        button(status === "hidden" ? "取消隐藏" : "隐藏", () => feedback(p, status === "hidden" ? "" : "hidden", target)));
      if (target) actions.append(button("入库并加入阅读待办", async () => {
        const paper = await importCandidate(p, target);
        await readingTask(paper, target);
        if (project === target) { await loadProject(); tell("论文已入库，阅读待办已就绪"); }
      }));
      art.append(actions);
      list.append(art);
    }
    if (!list.children.length) list.append(make("p", "当前没有符合筛选条件的论文。"));
  }
  async function feedback(p, state, target) {
    const updated = await req(scoped("tools/feedback", target), {
      arxiv: p.arxiv,
      state
    });
    if (project !== target) return;
    discovery = updated;
    showFeed();
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
    $("filter").onchange = showFeed;
    $("categories").oninput = showFeed;
    $("crossList").onchange = showFeed;
    $("search").onsubmit = e => {
      e.preventDefault();
      const b = e.submitter;
      busy(b, async () => {
        tell("正在查询 arXiv…");
        const target = project;
        const updated = await req(scoped("tools/discover", target), {
          query: $("expr").value
        });
        if (project !== target) return;
        discovery = updated;
        showFeed();
        tell("已更新检索结果");
      });
    };
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
      if (!v.token) throw Error("请输入 MinerU API Token");
      if (!confirm("将这篇 PDF 上传到 MinerU 进行转换？")) return;
      tell("正在上传…");
      const s = await req("tools/mineru/start", v);
      if (seq !== conversionSequence || v.paper !== $("paper").value) return;
      $("batch").value = s.batch;
      tell("已提交转换。任务编号可用于稍后查看进度。");
    });
    $("checkBatch").onclick = () => busy($("checkBatch"), async () => {
      const p = selectedPaper(),
        d = remoteData(),
        seq = ++conversionSequence,
        s = await req("tools/mineru/status", d);
      if (seq !== conversionSequence) return;
      if (s.state === "done") {
        renderResult((await req("tools/mineru/result", d)).markdown, p, seq);
      } else tell("MinerU 任务状态：" + s.state);
    });
    $("getZip").onclick = () => busy($("getZip"), async () => {
      const d = remoteData(),
        s = await req("tools/mineru/status", d);
      if (s.state !== "done") throw Error("结果尚未完成：" + s.state);
      saveBlob(await req("tools/mineru/result?format=zip", d, "blob"), "MinerU-" + d.paper + ".zip");
    });
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
