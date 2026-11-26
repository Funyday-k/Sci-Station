"use strict";
(() => {
  function key(paper) {
    if (paper.arxiv) return paper.arxiv.toLowerCase().replace(/v\d+$/, "");
    if (paper.doi) return "doi:" + paper.doi.toLowerCase();
    return paper.paper_id ? "paper:" + paper.paper_id : "feed:" + paper.feed_id;
  }

  function scope(route, project, run = "") {
    const query = new URLSearchParams();
    if (project) query.set("project", project);
    if (run) query.set("run", run);
    return route + (query.size ? "?" + query : "");
  }

  const sourceLabels = {arxiv: "arXiv", graph: "项目图谱", library: "近期馆藏", daily: "每日文献文件"};

  function create({$, req, make, button, busy, tell, trigger = ""}) {
    let project = "", generation = 0, ready = false;
    let feed = {}, papers = [], queue = [];
    const current = operation => operation.generation === generation;
    const context = () => ({target: project, generation, run: feed.id, source: feed.source, feedSource: feed.daily_feed_source});

    function withCurrent(operation, handler) {
      return async () => {
        try {
          await handler(operation);
        } catch (error) {
          if (current(operation)) throw error;
        }
      };
    }

    function renderQueue() {
      const list = $("readingQueue");
      const operation = context();
      list.replaceChildren();
      for (const p of queue) {
        const row = make("article", "");
        const a = make("a", p.title);
        a.href = "/reader?paper=" + encodeURIComponent(p.id) + (project ? "&project=" + encodeURIComponent(project) : "");
        row.append(a);
        row.append(button("加入阅读待办", withCurrent(operation, async ({target}) => {
          const task = await readingTask(p, target);
          if (current(operation)) {
            showReadingTask(task, target);
            tell("阅读待办已就绪");
          }
        })));
        list.append(row);
      }
      if (!queue.length) list.append(make("p", "暂无待阅读的馆藏论文。"));
    }

    function options(select, entries, selected) {
      select.replaceChildren();
      for (const [value, label] of entries) {
        const option = make("option", label);
        option.value = value;
        option.selected = selected.includes(value);
        select.append(option);
      }
    }

    function showSourceFields() {
      const source = $("source").value;
      $("aiSettings").hidden = source !== "arxiv";
      $("dailyFeedField").hidden = source !== "daily";
    }

    function applyDefaults(defaults = {}) {
      $("source").value = defaults.source || "arxiv";
      $("categories").value = (defaults.categories || []).join(", ");
      $("crossList").checked = defaults.cross_list ?? true;
      $("topK").value = defaults.top_k || 24;
      $("maxCandidates").value = defaults.max_daily_candidates || 100;
      $("libraryDays").value = defaults.library_recent_days || 60;
      showSourceFields();
    }

    function categories() {
      return $("categories").value.split(/[\s,，]+/).filter(Boolean);
    }

    function applyRun(result, resetFilter) {
      feed = result;
      $("expr").value = feed.query || "";
      applyDefaults({...feed.defaults, ...feed});
      $("graphSource").disabled = !project;
      if (resetFilter) $("filter").value = "all";
      options($("history"), [["", "选择检索记录"], ...(feed.history || []).map(run => [
        run.id, [new Date(run.updated).toLocaleString(), run.query || run.feed_name || sourceLabels[run.source] || "分类检索", run.count + " 篇"].join(" · ")
      ])], [feed.id || ""]);
      $("archiveRun").disabled = !feed.id;
      options($("references"), papers.map(p => [p.id, p.title]), feed.reference_ids || []);
      const queries = (feed.atom_queries || []).map(q => "arXiv 检索式 " + q);
      const source = feed.id ? [feed.trigger === "lab" ? "AI Lab" : "", sourceLabels[feed.source], feed.daily_feed_source?.name,
        feed.updated ? new Date(feed.updated).toLocaleString() : "", ...queries]
        .filter(Boolean).join(" · ") : "";
      $("runSource").textContent = [source, feed.notice].filter(Boolean).join("。");
      renderFeed();
    }

    async function load(target, run = "") {
      project = target;
      generation++;
      const operation = context();
      ready = false;
      papers = [];
      queue = [];
      applyRun({}, true);
      $("readingQueue").replaceChildren();
      tell("");
      $("submitSearch").disabled = true;
      $("aiModel").value = "";
      $("dailyFeed").value = "";
      $("readingTaskOpen").hidden = true;
      try {
        const [result, library, queueItems] = await Promise.all([
          req(scope("tools/discover", target, run)), req(scope("papers", target)), req(scope("papers/recommendations", target))
        ]);
        if (!current(operation)) return;
        [papers, queue] = [library, queueItems];
        renderQueue();
        applyRun(result, true);
        ready = true;
      } catch (error) {
        if (current(operation)) throw error;
      } finally {
        if (current(operation)) $("submitSearch").disabled = !ready;
      }
    }

    function readingTask(p, target, candidate, run, provenance) {
      const task = {
        title: Array.from("阅读：" + p.title).slice(0, 240).join(""),
        kind: "reading", relatedPaperIds: [p.id], idempotencyKey: "reading:" + p.id
      };
      if (candidate) {
        task.externalSource = "sci_station_recommendation";
        task.externalIdentifier = (candidate.arxiv ? "arxiv:" : "") + key(candidate);
        task.description = [
          sourceLink(candidate) ? "论文来源 " + sourceLink(candidate) : "",
          "发现记录 " + run,
          provenance ? "每日文献 " + provenance.name + " · SHA256 " + provenance.sha256 : "",
          ...(candidate.graph_evidence || []).map(edge => [edge.kind, edge.paper_title, edge.relation_id || edge.reference].filter(Boolean).join(" · "))
        ].filter(Boolean).join("\n");
      }
      return req(target ? "projects/" + encodeURIComponent(target) + "/tasks" : "tasks", task);
    }

    function sourceLink(p) {
      if (p.arxiv) return "https://arxiv.org/abs/" + encodeURIComponent(p.arxiv).replace(/%2F/gi, "/");
      if (p.doi) return "https://doi.org/" + encodeURIComponent(p.doi).replace(/%2F/gi, "/");
      try {
        const url = new URL(p.url);
        if (["https:", "http:"].includes(url.protocol) && !url.username && !url.password) return url.href;
      } catch {}
      return "";
    }

    function feedbackState(p) {
      const work = key(p);
      const state = feed.feedback?.[work] || feed.feedback?.[p.arxiv];
      if (state || !p.arxiv) return state || "";
      return Object.entries(feed.feedback || {}).find(([id]) => key({arxiv: id}) === work)?.[1] || "";
    }

    function setFeedback(p, state, operation) {
      return req(scope("tools/feedback", operation.target), {run: operation.run, key: key(p), state}).then(result => {
        if (current(operation) && feed.id === operation.run) {
          feed.feedback = result.feedback;
          renderFeed();
        }
      });
    }

    function showReadingTask(task, target) {
      if (!task.id) return;
      const link = $("readingTaskOpen");
      const params = new URLSearchParams({view: "tasks"});
      if (target) params.set("project", target);
      params.set("task", task.id);
      link.href = "/research?" + params;
      link.hidden = false;
    }

    async function select(p, operation, task) {
      const paper = await req(scope("tools/select-discovery", operation.target), {
        run: operation.run, key: key(p), fetch_pdf: Boolean((!operation.source || operation.source === "arxiv") && p.arxiv && !p.paper_id)
      });
      let createdTask;
      if (task) {
        try {
          createdTask = await readingTask(paper, operation.target, p, operation.run, operation.feedSource);
        } catch (error) {
          throw Error("论文已入库。阅读待办创建失败，可重试。 " + error.message);
        }
      }
      if (current(operation)) {
        if (createdTask) showReadingTask(createdTask, operation.target);
        const complete = task ? "论文已入库，阅读待办已就绪" : "论文已加入文献库";
        tell([complete, paper.import_warning].filter(Boolean).join("。"));
        try {
          const refreshed = await req(scope("papers/recommendations", operation.target));
          if (current(operation)) {
            queue = refreshed;
            renderQueue();
          }
          if (feed.id === operation.run && feedbackState(p) !== "saved") await setFeedback(p, "saved", operation);
        } catch (error) {
          if (current(operation)) tell("论文已入库" + (task ? "，阅读待办已就绪" : "") + "。更新发现页面失败，可重新载入。 " + error.message);
        }
      }
    }

    function renderCandidate(p) {
      const operation = context();
      const status = feedbackState(p);
      const article = make("article", "");
      article.append(make("h3", p.title), make("p", [
        (p.authors || []).join(", "), p.arxiv || p.doi, p.published_at?.slice(0, 10),
        p.primary_category ? (p.first_category ? "文件首列分类 " : "主分类 ") + p.primary_category : "",
        ...new Set([...(p.categories || []), ...(p.tags || [])].filter(t => t !== p.primary_category))
      ].filter(Boolean).join(" · ")));
      const url = sourceLink(p);
      if (url) {
        const link = make("a", "打开来源");
        Object.assign(link, {href: url, target: "_blank", rel: "noopener noreferrer"});
        link.onclick = () => {
          if (!status) setFeedback(p, "opened", operation).catch(error => { if (current(operation)) tell(error.message); });
        };
        article.append(link);
      }
      if (p.abstract) {
        const abstract = make("details", "");
        abstract.append(make("summary", "摘要"), make("p", p.abstract));
        article.append(abstract);
      }
      if (p.reasons?.length) article.append(make("p", p.reasons.join(" · ")));
      if (p.search_queries?.length) {
        const queries = make("details", "");
        queries.append(make("summary", "命中检索式"), ...p.search_queries.map(query => make("p", query)));
        article.append(queries);
      }
      if (p.graph_evidence?.length) {
        const graph = make("details", "");
        graph.append(make("summary", "图谱依据"));
        const kinds = {cites: "引用", related: "相关", extends: "扩展"};
        for (const edge of p.graph_evidence) {
          graph.append(make("p", [edge.paper_title, kinds[edge.kind] || edge.kind, edge.reference || edge.relation_id].filter(Boolean).join(" · ")));
        }
        article.append(graph);
      }
      const review = feed.ai_review?.[key(p)];
      if (review) {
        const detail = make("details", "");
        detail.append(make("summary", "AI 推荐说明 · " + feed.ai_model), make("p", review));
        const evaluation = feed.ai_review_details?.[key(p)];
        if (evaluation?.summary) detail.append(make("p", evaluation.summary));
        if (evaluation) {
          const scores = Object.entries({relevance: "相关性", novelty: "新颖性", method_soundness: "方法", usefulness: "用途", risk: "风险"})
            .filter(([metric]) => typeof evaluation[metric] === "number").map(([metric, label]) => label + " " + Math.round(evaluation[metric] * 100) + "%");
          if (scores.length) detail.append(make("p", scores.join(" · ")));
        }
        article.append(detail);
      }
      const actions = make("div", "");
      actions.className = "actions";
      if (p.paper_id || url) {
        actions.append(button("加入文献库", withCurrent(operation, () => select(p, operation, false))));
        actions.append(button("入库并加入阅读待办", withCurrent(operation, () => select(p, operation, true))));
      }
      for (const [state, label, undo] of [
        ["saved", "收藏", "取消收藏"], ["liked", "相关", "取消相关"],
        ["disliked", "不相关", "取消不相关"], ["hidden", "隐藏", "取消隐藏"]
      ]) {
        const action = button(status === state ? undo : label, withCurrent(operation, () => setFeedback(p, status === state ? "" : state, operation)));
        action.setAttribute("aria-pressed", String(status === state));
        actions.append(action);
      }
      article.append(actions);
      return article;
    }

    function renderFeed() {
      const mode = $("filter").value;
      const visible = (feed.items || []).filter(p => {
        const state = feedbackState(p);
        return mode === "all" ? state !== "hidden" : state === mode;
      });
      $("articles").replaceChildren(...visible.map(renderCandidate));
      if (!visible.length) $("articles").append(make("p", feed.id ? "当前没有符合筛选条件的论文。" : "运行检索或打开历史记录。"));
    }

    $("filter").onchange = renderFeed;
    $("source").onchange = showSourceFields;
    $("useDiscoveryDefaults").onclick = () => applyDefaults(feed.defaults);
    $("saveDiscoveryDefaults").onclick = () => {
      if (!ready) return;
      const operation = context();
      return busy($("saveDiscoveryDefaults"), withCurrent(operation, async () => {
        const result = await req(scope("tools/discovery-defaults", operation.target), {
          source: $("source").value, categories: categories(), cross_list: $("crossList").checked,
          top_k: Number($("topK").value), max_daily_candidates: Number($("maxCandidates").value),
          library_recent_days: Number($("libraryDays").value)
        });
        if (current(operation)) {
          feed.defaults = result.defaults;
          tell("已保存当前范围的推荐设置");
        }
      }));
    };
    $("history").onchange = () => {
      const operation = context();
      const selected = $("history").value;
      if (!selected) return;
      return busy($("history"), withCurrent(operation, async () => {
        const result = await req(scope("tools/discover", operation.target, selected));
        if (current(operation)) applyRun(result, true);
      }));
    };
    $("archiveRun").onclick = () => {
      const operation = context();
      if (!operation.run || !confirm("归档当前检索记录？")) return;
      return busy($("archiveRun"), withCurrent(operation, async () => {
        const result = await req(scope("tools/archive-discovery", operation.target), {run: operation.run});
        if (current(operation)) {
          applyRun(result, true);
          tell("检索记录已归档");
        }
      }));
    };
    $("loadModels").onclick = () => busy($("loadModels"), async () => {
      const response = await fetch("/api/studio/models");
      if (!response.ok) throw Error("无法读取 Magpie 模型目录");
      const catalog = await response.json();
      options($("aiModel"), [["", "关闭"], ...catalog.models.map(model => [model.id, model.label || model.id])], [$("aiModel").value]);
    });
    $("search").onsubmit = event => {
      event.preventDefault();
      if (!ready) return;
      const operation = context();
      const payload = {
        source: $("source").value, query: $("expr").value,
        categories: categories(),
        cross_list: $("crossList").checked, top_k: Number($("topK").value),
        reference_ids: Array.from($("references").selectedOptions || [], option => option.value)
      };
      if (trigger) payload.trigger = trigger;
      if (payload.source === "arxiv" && $("aiModel").value) {
        if (!confirm("将检索词、项目简介和所选参考论文的摘要片段发送给所选模型。生成的检索式将提交给 arXiv，候选摘要将用于生成阅读说明。继续？")) return;
        payload.ai_model = $("aiModel").value;
      } else if (payload.source === "arxiv" && trigger === "lab" &&
          !confirm("向 arXiv 发送此次检索式与分类？")) return;
      return busy(event.submitter || $("submitSearch"), withCurrent(operation, async () => {
        if (payload.source === "daily") {
          const file = $("dailyFeed").files?.[0];
          if (!file || file.size === 0 || file.size > 2 * 1024 * 1024) throw Error("请选择至多 2 MiB 的 JSON 或 JSONL 文献文件");
          const decoder = new TextDecoder("utf-8", {fatal: true, ignoreBOM: true});
          payload.daily_feed = {name: file.name, text: decoder.decode(await file.arrayBuffer())};
          if (!current(operation)) return;
        }
        tell(payload.source === "arxiv" ? "正在查询 arXiv…" : "正在整理本地候选…");
        const result = await req(scope("tools/discover", operation.target), payload);
        if (current(operation)) {
          applyRun(result, true);
          if (payload.source === "daily") $("dailyFeed").value = "";
          tell("已更新检索结果");
        }
      }));
    };
    return {load};
  }

  const api = {create, key};
  if (typeof module !== "undefined") module.exports = api;
  else globalThis.SciStationDiscovery = api;
})();
