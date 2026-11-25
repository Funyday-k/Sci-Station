"use strict";
(() => {
  const $ = id => document.getElementById(id);
  const qs = new URLSearchParams(location.search);
  let project = qs.get("project") || "",
    papers = [],
    tasks = [],
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
  async function loadProject() {
    nav();
    tasks = project ? await req("projects/" + encodeURIComponent(project) + "/tasks") : [];
    choices($("task"), tasks.filter(t => t.status !== "done").map(t => [t.id, t.title]), "暂无待处理任务");
    $("reminder").disabled = !$("task").value;
  }

  function showFeed() {
    const list = $("articles");
    list.replaceChildren();
    const mode = $("filter").value;
    for (const p of discovery.items || []) {
      const status = (discovery.feedback || {})[p.arxiv] || "";
      if (mode === "all" ? status === "hidden" : status !== mode) continue;
      const art = make("article", ""),
        h = make("h3", p.title);
      art.append(h, make("div", (p.authors || []).join(", ") + " · " + p.arxiv));
      const more = make("details", "");
      more.append(make("summary", "摘要"), make("p", p.abstract || "暂无摘要"));
      art.append(more);
      const actions = make("div", "");
      actions.className = "actions";
      actions.append(button("加入文献库", async () => {
          await req("papers", {
            title: p.title,
            authors: p.authors || [],
            abstract: p.abstract || "",
            arxiv: p.arxiv,
            doi: p.doi || "",
            url: p.url,
            year: p.year || 0,
            project_ids: project ? [project] : []
          });
          tell("论文已加入文献库");
        }),
        button(status === "saved" ? "取消收藏" : "收藏", () => feedback(p, status === "saved" ? "" : "saved")),
        button(status === "hidden" ? "取消隐藏" : "隐藏", () => feedback(p, status === "hidden" ? "" : "hidden")));
      art.append(actions);
      list.append(art);
    }
    if (!list.children.length) list.append(make("p", "当前没有符合筛选条件的论文。"));
  }
  async function feedback(p, state) {
    discovery = await req("tools/feedback", {
      arxiv: p.arxiv,
      state
    });
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
    $("search").onsubmit = e => {
      e.preventDefault();
      const b = e.submitter;
      busy(b, async () => {
        tell("正在查询 arXiv…");
        discovery = await req("tools/discover", {
          query: $("expr").value
        });
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
    $("reminder").onclick = () => busy($("reminder"), async () => {
      if (!$("task").value) return;
      await req("tools/reminder", {
        project,
        task: $("task").value
      });
      tell("任务已发布到 Apple 提醒事项");
    });
  }
  async function init() {
    $(tab).hidden = false;
    $("heading").textContent = views[tab];
    nav();
    initActions();
    const projs = await req("projects");
    choices($("project"), projs.map(p => [p.id, p.name]), "未选择项目");
    if (!projs.some(p => p.id === project)) project = projs[0]?.id || "";
    $("project").value = project;
    await loadProject();
    if (tab === "discover") {
      discovery = await req("tools/discover");
      $("expr").value = discovery.query || "";
      showFeed();
    }
    if (tab === "convert") {
      papers = (await req("papers")).filter(p => p.has_pdf);
      choices($("paper"), papers.map(p => [p.id, p.title]), "暂无本地 PDF");
      if (qs.get("paper") && papers.some(p => p.id === qs.get("paper"))) $("paper").value = qs.get("paper");
      $("local").disabled = !papers.length;
    }
  }
  init().catch(e => tell(e.message));
})();
