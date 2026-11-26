"use strict";
(() => {
  const nodeKinds = {
    note: "笔记", paper: "论文", task: "任务", reference: "外部引文",
    meeting: "会议", method: "方法", missing: "来源已移除"
  };
  const edgeKinds = {
    wikilink: "双链", cites: "引用", "possible-cites": "疑似引用", reading: "阅读", supports: "支持", contradicts: "矛盾",
    extends: "扩展", uses: "使用方法", related: "相关", evidence: "证据", paper: "关联论文"
  };
  const statuses = {
    missing: "来源不可用", changed: "原件已变更", unversioned: "未保存原件指纹"
  };
  const defaultQuery = Object.freeze({focus: "", target: "", depth: "2", direction: "", kind: "", nodeKind: ""});
  const workflowOperations = {
    reading: "论文阅读顺序",
    "missing-core": "核心论文引用的未关联文献",
    "stale-citations": "查找待核对的陈旧引文",
    "unsupported-claims": "查找需核对证据的声明",
    "stale-artifacts": "查找待复核的保存成果",
    "method-lineage": "方法沿革",
    bridge: "最短关系路径"
  };

  function queryPath(base, query, fields = ["focus", "target", "depth", "direction", "kind", "nodeKind"]) {
    const params = new URLSearchParams();
    for (const key of fields) {
      if (query[key] !== undefined && query[key] !== "") params.set(key, query[key]);
    }
    return params.size ? base + "?" + params : base;
  }

  function workflowPath(base, query) {
    return queryPath(base, query, ["operation", "focus", "target", "depth", "direction", "minCitations", "thresholdDays", "severity"]);
  }

  function updateWorkflowForm(form) {
    const operation = form.elements.operation.value;
    for (const label of form.querySelectorAll("[data-workflow-operations]")) {
      const hidden = !label.dataset.workflowOperations.split(" ").includes(operation);
      label.hidden = hidden;
      label.firstElementChild.disabled = hidden;
    }
    const focus = form.elements.focus;
    const kind = {"method-lineage": "method", reading: "paper"}[operation];
    for (const option of focus.options) {
      option.hidden = option.disabled = Boolean(option.value && kind && option.dataset.kind !== kind);
    }
    if (focus.selectedOptions[0]?.disabled) focus.value = "";
    const threshold = form.elements.thresholdDays;
    const min = operation === "stale-citations" ? 365 : 1;
    const fallback = operation === "stale-citations" ? 3650 : 90;
    threshold.min = min;
    if (Number(threshold.value) < min || threshold.dataset.operation !== operation) threshold.value = fallback;
    threshold.dataset.operation = operation;
  }

  function graphWorkflowPanel(nodes, workflow, ui, nodeButton) {
    const {esc, panel, link} = ui;
    const {query = {}, error, pending, result} = workflow || {};
    const operation = query.operation || (nodes.some(n => n.kind === "paper") ? "reading" : "missing-core");
    const pathOperations = "reading method-lineage bridge";
    const field = (label, operations, content) => '<label data-workflow-operations="' + operations + '"' +
      (operations.split(" ").includes(operation) ? "" : " hidden") + ">" + label + " " + content + "</label>";
    const disabled = operations => operations.split(" ").includes(operation) ? "" : " disabled";
    const option = (value, title, selected) =>
      '<option value="' + esc(value) + '"' + (value === selected ? " selected" : "") + ">" + esc(title) + "</option>";
    const nodeOptions = (name, kind) => option("", "请选择", query[name]) + nodes.filter(n => n.kind !== "missing").map(n =>
      '<option data-kind="' + esc(n.kind) + '" value="' + esc(n.id) + '"' +
      (n.id === query[name] ? " selected" : "") + (kind && kind !== n.kind ? " hidden disabled" : "") +
      ">" + esc(n.label) + "</option>").join("");
    const select = (name, operations, options) => '<select name="' + name + '"' + disabled(operations) + ">" + options + "</select>";
    const number = (name, operations, min, max, value, attrs = "") => '<input type="number" name="' + name + '"' +
      disabled(operations) + ' min="' + min + '" max="' + max + '" value="' + esc(value) + '"' + attrs + ">";
    const thresholdOperations = "stale-citations stale-artifacts";
    const citations = operation === "stale-citations";
    let content = '<form class="graph-picker" id="graph-workflow-query" aria-label="科研查询">' +
      '<label>查询 <select name="operation">' + Object.entries(workflowOperations).map(([value, title]) =>
        option(value, title, operation)).join("") + "</select></label>" +
      field("起点", pathOperations, select("focus", pathOperations,
        nodeOptions("focus", {"method-lineage":"method", reading:"paper"}[operation]))) +
      field("终点", "bridge", select("target", "bridge", nodeOptions("target"))) +
      field("深度", pathOperations, number("depth", pathOperations, 1, 10, query.depth ?? 3)) +
      field("方向", "method-lineage bridge", select("direction", "method-lineage bridge",
        [["both","双向"],["outgoing","沿关系方向"],["incoming","逆关系方向"]].map(([value, title]) =>
          option(value, title, query.direction)).join(""))) +
      field("最少引用它的核心论文数", "missing-core", number("minCitations", "missing-core", 1, 100, query.minCitations ?? 1)) +
      field("天数", thresholdOperations, number("thresholdDays", thresholdOperations, citations ? 365 : 1, 36500,
        query.thresholdDays ?? (citations ? 3650 : 90), ' data-operation="' + esc(operation) + '"')) +
      field("问题级别", "unsupported-claims", select("severity", "unsupported-claims",
        [["","全部"],["error","缺少原文引用"],["warning","需复核引用"]].map(([value, title]) =>
          option(value, title, query.severity)).join(""))) +
      '<button type="submit" class="button"' + (pending ? " disabled" : "") + ">查询</button></form>";
    if (error) content += '<p role="alert" class="graph-status">' + esc(error) + "</p>";
    if (result) {
      const found = result.findings || [];
      if (result.notice) content += '<p class="graph-status" role="status">' + esc(result.notice) + "</p>";
      if (found.length) {
        content += '<ol class="graph-workflow-findings">' + found.map(row => {
          const links = (row.links || []).map(item =>
            item.nodeId ? nodeButton(item.nodeId) :
              /^\/(research|reader|tools)\?/.test(item.url || "") ? link(item.label, item.url, "bare") : "").filter(Boolean);
          const title = row.title ? (row.links?.[0]?.nodeId ? links.shift() || esc(row.title) : esc(row.title)) : "";
          const detail = (title && row.text ? " · " : "") + esc(row.text);
          return "<li>" + title + detail + (links.length ? '<p>' + links.join(" · ") + "</p>" : "") + "</li>";
        }).join("") + "</ol>";
      }
      if (result.truncated) content += '<p class="graph-status">当前显示 ' + found.length + " 项，共 " + Number(result.total) + " 项。</p>";
    }
    return panel("科研查询", content);
  }

  function meetingLink(project, occurrence, route) {
    const url = route("/studio", {project, session: occurrence.meetingId});
    return /^round-[0-9]+-[\w-]+$/.test(occurrence.turnId || "") ? url + "#" + occurrence.turnId : url;
  }

  function occurrenceLink(project, edge, occurrence, route) {
    if (occurrence.source === "metadata" || occurrence.source === "paper-note") {
      return route("/reader", {project, paper: edge.source, citation: occurrence.source,
        ordinal: occurrence.ordinal, line: occurrence.line, endLine: occurrence.endLine, revision: occurrence.sourceRevision});
    }
    if (occurrence.source === "meeting") {
      return meetingLink(project, occurrence, route);
    }
    if (occurrence.source === "evidence" && occurrence.status !== "missing") {
      return route("/reader", {project, paper: edge.target, page: occurrence.page, fingerprint: occurrence.sourceHash,
        quote: occurrence.page ? occurrence.quote : "",
        start: Number.isInteger(occurrence.start) ? String(occurrence.start) : "",
        end: occurrence.end, ocr: occurrence.ocr ? "1" : "", annotation: occurrence.annotationId});
    }
    return "";
  }

  function graphDiagram(result, keys, esc) {
    if (!result.edges.length) return "";
    const layers = new Map();
    const add = (id, hop) => {
      if (!layers.has(hop)) layers.set(hop, new Set());
      layers.get(hop).add(id);
    };
    if (result.hops) {
      for (const [id, hop] of Object.entries(result.hops)) add(id, hop);
    } else {
      const focus = result.edges[0].source;
      add(focus, 0);
      for (const edge of result.edges) {
        if (edge.source === focus && edge.target !== focus) add(edge.target, 1);
        else if (edge.target === focus && edge.source !== focus) add(edge.source, 1);
      }
    }
    const points = new Map();
    const height = Math.max(...[...layers.values()].map(nodes => Math.min(nodes.size, 6))) * 50 + 20;
    const width = layers.size * 224;
    for (const [hop, nodes] of layers) {
      const visible = [...nodes].slice(0, 6);
      visible.forEach((id, i) => points.set(id, {x: 17 + hop * 224, y: (height - (visible.length - 1) * 50) / 2 + i * 50}));
    }
    const lines = result.edges.map(edge => {
      const source = points.get(edge.source), target = points.get(edge.target);
      if (!source || !target || source.x === target.x) return "";
      const left = source.x < target.x ? source : target, right = left === source ? target : source;
      const mid = (left.x + 184 + right.x) / 2;
      return `<path d="M${left.x + 184} ${left.y} C${mid} ${left.y} ${mid} ${right.y} ${right.x} ${right.y}"/>`;
    }).join("");
    const items = [...points].map(([id, {x, y}]) => {
      const label = keys.get(id)?.label || id;
      const chars = [...label], excerpt = chars.length > 16 ? chars.slice(0, 16).join("") + "…" : label;
      return `<g><title>${esc(label)}</title><rect x="${x}" y="${y - 16}" width="184" height="32" rx="7"/><text x="${x + 10}" y="${y + 4}">${esc(excerpt)}</text></g>`;
    }).join("");
    return `<div class="graph-diagram"><svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-label="部分关联预览">${lines}${items}</svg></div>`;
  }

  function graphView({graph, result, project, query, error, pending, workflow, citationPanel = ""}, ui) {
    const {esc, button, heading, panel, empty, link} = ui;
    const nodes = graph.nodes || [];
    const keys = new Map([...nodes, ...result.nodes].map(node => [node.id, node]));
    const allEntries = Object.fromEntries(nodes.map(node => [node.id, node.label + " · " + (nodeKinds[node.kind] || node.kind)]));
    const nodeButton = id => {
      const node = keys.get(id);
      return node ? button(node.label, "graph-open", {id, kind: "bare"}) : esc(id);
    };
    const option = (value, label, selected) => '<option value="' + esc(value) + '"' +
      (value === selected ? " selected" : "") + ">" + esc(label) + "</option>";
    const select = (label, name, none, entries) => '<label>' + label + ' <select id="graph-' + name + '" name="' + name + '">' +
      (none ? option("", none, query[name]) : "") +
      Object.entries(entries).map(([value, label]) => option(value, label, query[name])).join("") +
      "</select></label>";
    const actions = button("重新生成", "graph-rebuild") +
      (nodes.length > 1 ? button("新增关系", "new-relation", {glyph: "plus", kind: "button primary"}) : "");
    let out = heading("知识关联", project.name, actions);
    if (error) out += '<p class="status" role="alert">' + esc(error) + "</p>";
    const workflowPanel = graphWorkflowPanel(nodes, workflow, ui, nodeButton);
    if (!nodes.length) return out + panel("项目图谱", empty("暂无可关联的条目", "添加论文、笔记或任务后即可查看项目关系。")) + workflowPanel + citationPanel;
    const controls = '<form class="graph-picker" id="graph-query" aria-label="图谱筛选">' +
      select("起点", "focus", "全部条目", allEntries) +
      select("终点", "target", "仅查看邻居", allEntries) +
      select("深度", "depth", "", Object.fromEntries(Array.from({length: 11}, (_, n) => [n, String(n)]))) +
      select("方向", "direction", "双向", {outgoing: "沿关系方向", incoming: "逆关系方向"}) +
      select("关系类型", "kind", query.focus ? "全部确认关系" : "全部关系", edgeKinds) +
      select("条目类型", "nodeKind", "全部类型", nodeKinds) +
      '<button type="submit" class="button"' + (pending ? " disabled" : "") + ">应用</button></form>";
    const path = result.path;
    let visualization = "";
    if (path?.found) {
      visualization = '<ol class="graph-path" aria-label="最短路径">' +
        path.nodes.map(id => "<li>" + nodeButton(id) + "</li>").join("") + "</ol>";
    } else if (path) {
      visualization = '<p class="graph-status" role="status">当前筛选条件和深度内未找到连接路径。</p>';
    } else if (result.hops) {
      const layers = new Map();
      for (const node of result.nodes) {
        const hop = result.hops[node.id];
        if (!layers.has(hop)) layers.set(hop, []);
        layers.get(hop).push(node.id);
      }
      visualization = '<ol class="graph-layers" aria-label="按距离展开的邻居">' +
        [...layers].map(([hop, ids]) => '<li><span>' + (hop === 0 ? "起点" : "距离 " + hop) +
          '</span><ul>' + ids.map(id => "<li>" + nodeButton(id) + "</li>").join("") + "</ul></li>").join("") + "</ol>";
    }
    out += panel("项目图谱", controls + graphDiagram(result, keys, esc) + visualization) + workflowPanel + citationPanel;

    const labelOccurrence = occurrence => {
      const {source, ordinal, line, page} = occurrence;
      if (source === "wikilink" || source === "paper-note") return "第 " + line + " 行";
      if (source === "metadata") return "参考文献 " + ordinal;
      if (source === "meeting") return occurrence.turnId ? "讨论轮次 " + occurrence.turnId : "会议记录";
      return page ? "PDF 第 " + page + " 页" : "证据 " + ordinal;
    };
    const renderOccurrence = (edge, occurrence) => {
      const locator = labelOccurrence(occurrence);
      const href = occurrenceLink(project.id, edge, occurrence, ui.route);
      const action = href ? link(locator, href, "bare") : occurrence.source === "wikilink" ?
        button(locator, "graph-occurrence", {id: occurrence.id, kind: "bare"}) : esc(locator);
      const flag = statuses[occurrence.status] || ({
        "normalized-title": "按题名匹配",
        "similar-title": "题名近似，待核对",
        "ambiguous-title": "有多个可能匹配，待核对"
      })[occurrence.resolution];
      const candidates = occurrence.matches?.length && occurrence.resolution === "ambiguous-title" ?
        '<ul>' + occurrence.matches.map(match => '<li>' + nodeButton(match.id) + '</li>').join("") + '</ul>' : "";
      const discussion = occurrence.source === "evidence" && occurrence.meetingId ?
        " · " + link("来源讨论", meetingLink(project.id, occurrence, ui.route), "bare") : "";
      return "<li>" + action + discussion + (flag ? '<span class="graph-source-status">' + esc(flag) + "</span>" : "") +
        (occurrence.quote ? "<blockquote>" + esc(occurrence.quote) + "</blockquote>" : "") + candidates + "</li>";
    };
    const relations = (result.edges || []).map(edge => {
      const details = edge.occurrences?.length ? '<details class="graph-occurrences"><summary>' + edge.occurrences.length +
        ' 处来源</summary><ol>' + edge.occurrences.map(occurrence => renderOccurrence(edge, occurrence)).join("") + "</ol></details>" : "";
      return '<div class="graph-edge"><div class="relation">' + nodeButton(edge.source) +
        '<span class="tag">' + esc(edgeKinds[edge.kind] || edge.kind) + '</span>' + nodeButton(edge.target) +
        (edge.id ? button("移除", "remove-relation", {id: edge.id, kind: "bare danger"}) : "") + "</div>" +
        (edge.label ? '<p class="graph-status">' + esc(edge.label) + "</p>" : "") + details + "</div>";
    }).join("");
    out += panel("关系 · " + (result.edges || []).length, relations || empty("当前范围内暂无关联"));
    out += panel("条目 · " + (result.nodes || []).length,
      result.nodes.length ? '<ul class="graph-entries">' + result.nodes.map(node => "<li>" + nodeButton(node.id) +
        '<span class="tag">' + esc(nodeKinds[node.kind] || node.kind) + "</span></li>").join("") + "</ul>" : empty("暂无条目"));
    return out;
  }

  const api = Object.freeze({defaultQuery, graphView, queryPath, workflowPath, updateWorkflowForm, occurrenceLink});
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.SciResearchGraph = api;
})();
