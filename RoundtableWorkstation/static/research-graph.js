"use strict";
(() => {
  const nodeKinds = {
    note: "笔记", paper: "论文", task: "任务", reference: "外部引文",
    meeting: "会议", missing: "来源已移除"
  };
  const edgeKinds = {
    wikilink: "双链", cites: "引用", reading: "阅读", supports: "支持", contradicts: "矛盾",
    extends: "扩展", related: "相关", evidence: "证据", paper: "关联论文"
  };
  const statuses = {
    missing: "来源不可用", changed: "原件已变更", unversioned: "未保存原件指纹"
  };
  const defaultQuery = Object.freeze({focus: "", target: "", depth: "2", kind: "", nodeKind: ""});

  function queryPath(base, query) {
    const params = new URLSearchParams();
    for (const key of ["focus", "target", "depth", "kind", "nodeKind"]) {
      if (query[key] !== undefined && query[key] !== "") params.set(key, query[key]);
    }
    return params.size ? base + "?" + params : base;
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
        quote: occurrence.page && occurrence.quote?.length <= 4096 ? occurrence.quote : "",
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

  function graphView({graph, result, project, query, error, pending}, ui) {
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
    if (!nodes.length) return out + panel("项目图谱", empty("暂无可关联的条目", "添加论文、笔记或任务后即可查看项目关系。"));
    const controls = '<form class="graph-picker" id="graph-query" aria-label="图谱筛选">' +
      select("起点", "focus", "全部条目", allEntries) +
      select("终点", "target", "仅查看邻居", allEntries) +
      select("深度", "depth", "", Object.fromEntries(Array.from({length: 11}, (_, n) => [n, String(n)]))) +
      select("关系类型", "kind", "全部关系", edgeKinds) +
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
    out += panel("项目图谱", controls + graphDiagram(result, keys, esc) + visualization);

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
      const flag = statuses[occurrence.status];
      const discussion = occurrence.source === "evidence" && occurrence.meetingId ?
        " · " + link("来源讨论", meetingLink(project.id, occurrence, ui.route), "bare") : "";
      return "<li>" + action + discussion + (flag ? '<span class="graph-source-status">' + esc(flag) + "</span>" : "") +
        (occurrence.quote ? "<blockquote>" + esc(occurrence.quote) + "</blockquote>" : "") + "</li>";
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

  const api = Object.freeze({defaultQuery, graphView, queryPath, occurrenceLink});
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.SciResearchGraph = api;
})();
