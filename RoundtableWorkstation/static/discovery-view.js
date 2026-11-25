"use strict";
(() => {
  function key(paper) {
    if (paper.arxiv) return paper.arxiv.toLowerCase().replace(/v\d+$/, "");
    if (paper.doi) return "doi:" + paper.doi.toLowerCase();
    return "paper:" + paper.paper_id;
  }

  function scope(route, project, run = "") {
    const query = new URLSearchParams();
    if (project) query.set("project", project);
    if (run) query.set("run", run);
    return route + (query.size ? "?" + query : "");
  }

  function create({$, req, make, button, busy, tell}) {
    let project = "", generation = 0, ready = false;
    let feed = {}, papers = [], queue = [];
    const current = operation => operation.generation === generation;
    const context = () => ({target: project, generation, run: feed.id});

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
        if (project) row.append(button("加入阅读待办", withCurrent(operation, async ({target}) => {
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

    function applyRun(result, resetFilter) {
      feed = result;
      $("expr").value = feed.query || "";
      $("categories").value = (feed.categories || []).join(", ");
      $("crossList").checked = feed.cross_list ?? true;
      $("source").value = feed.source || "arxiv";
      $("topK").value = feed.top_k || 24;
      $("graphSource").disabled = !project;
      $("aiSettings").hidden = $("source").value !== "arxiv";
      if (resetFilter) $("filter").value = "all";
      options($("history"), [["", "选择检索记录"], ...(feed.history || []).map(run => [
        run.id, [new Date(run.updated).toLocaleString(), run.query || (run.source === "graph" ? "项目图谱" : "分类检索"), run.count + " 篇"].join(" · ")
      ])], [feed.id || ""]);
      $("archiveRun").disabled = !feed.id;
      options($("references"), papers.map(p => [p.id, p.title]), feed.reference_ids || []);
      const queries = (feed.atom_queries || []).map(q => "arXiv 检索式 " + q);
      const source = feed.id ? [feed.source === "graph" ? "项目图谱" : "arXiv", feed.updated ? new Date(feed.updated).toLocaleString() : "", ...queries]
        .filter(Boolean).join(" · ") : "";
      $("runSource").textContent = [source, feed.notice].filter(Boolean).join("。");
      renderFeed();
    }

    async function load(target, run = "") {
      project = target;
      generation++;
      const operation = context();
      ready = false;
      $("articles").replaceChildren();
      $("readingQueue").replaceChildren();
      $("runSource").textContent = "";
      $("expr").value = "";
      $("history").replaceChildren();
      $("submitSearch").disabled = true;
      $("aiModel").value = "";
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

    function readingTask(p, target, candidate, run) {
      const task = {
        title: Array.from("阅读：" + p.title).slice(0, 240).join(""),
        kind: "reading", relatedPaperIds: [p.id], idempotencyKey: "reading:" + p.id
      };
      if (candidate) {
        task.externalSource = "sci_station_recommendation";
        task.externalIdentifier = (candidate.arxiv ? "arxiv:" : "") + key(candidate);
        task.description = [
          candidate.arxiv ? "arXiv 来源 https://arxiv.org/abs/" + candidate.arxiv : candidate.doi ? "DOI " + candidate.doi : "",
          "发现记录 " + run,
          ...(candidate.graph_evidence || []).map(edge => [edge.kind, edge.paper_title, edge.relation_id || edge.reference].filter(Boolean).join(" · "))
        ].filter(Boolean).join("\n");
      }
      return req("projects/" + encodeURIComponent(target) + "/tasks", task);
    }

    function sourceLink(p) {
      if (p.arxiv) return "https://arxiv.org/abs/" + encodeURIComponent(p.arxiv).replace(/%2F/gi, "/");
      if (p.doi) return "https://doi.org/" + encodeURIComponent(p.doi).replace(/%2F/gi, "/");
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
      link.href = "/research?" + new URLSearchParams({view: "tasks", project: target, task: task.id});
      link.hidden = false;
    }

    async function select(p, operation, task) {
      const paper = await req(scope("tools/select-discovery", operation.target), {
        run: operation.run, key: key(p), fetch_pdf: Boolean(p.arxiv && !p.paper_id)
      });
      let createdTask;
      if (task) {
        try {
          createdTask = await readingTask(paper, operation.target, p, operation.run);
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
        p.primary_category ? "主分类 " + p.primary_category : "", ...(p.tags || []).filter(t => t !== p.primary_category)
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
        article.append(detail);
      }
      const actions = make("div", "");
      actions.className = "actions";
      actions.append(button("加入文献库", withCurrent(operation, () => select(p, operation, false))));
      if (project) actions.append(button("入库并加入阅读待办", withCurrent(operation, () => select(p, operation, true))));
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
    $("source").onchange = () => { $("aiSettings").hidden = $("source").value !== "arxiv"; };
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
        categories: $("categories").value.split(/[\s,，]+/).filter(Boolean),
        cross_list: $("crossList").checked, top_k: Number($("topK").value),
        reference_ids: Array.from($("references").selectedOptions || [], option => option.value)
      };
      if (payload.source === "arxiv" && $("aiModel").value) {
        if (!confirm("将检索词、项目简介和所选参考论文的摘要片段发送给所选模型。生成的检索式将提交给 arXiv，候选摘要将用于生成阅读说明。继续？")) return;
        payload.ai_model = $("aiModel").value;
      }
      return busy(event.submitter || $("submitSearch"), withCurrent(operation, async () => {
        tell(payload.source === "graph" ? "正在读取项目图谱…" : "正在查询 arXiv…");
        const result = await req(scope("tools/discover", operation.target), payload);
        if (current(operation)) {
          applyRun(result, true);
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
