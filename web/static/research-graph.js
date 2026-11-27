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
    const {el, fragment, panel, link} = ui;
    const {query = {}, error, pending, result} = workflow || {};
    const operation = query.operation || (nodes.some(n => n.kind === "paper") ? "reading" : "missing-core");
    const pathOperations = "reading method-lineage bridge";
    const field = (label, operations, control) => {
      const hidden = !operations.split(" ").includes(operation);
      control.disabled = hidden;
      return el("label", {"data-workflow-operations": operations, hidden}, label + " ", control);
    };
    const option = (value, label, selected) => el("option", {value, selected: value === selected}, label);
    const nodeSelect = (name, kind) => el("select", {name}, option("", "请选择", query[name]),
      nodes.filter(n => n.kind !== "missing").map(n => {
        const hidden = Boolean(kind && kind !== n.kind);
        return el("option", {value: n.id, "data-kind": n.kind, selected: n.id === query[name], hidden, disabled: hidden}, n.label);
      }));
    const choice = (name, entries) => el("select", {name},
      entries.map(([value, label]) => option(value, label, query[name])));
    const number = (name, min, max, value, attrs = {}) => el("input", {type:"number", name, min, max, value, ...attrs});
    const citations = operation === "stale-citations";
    const controls = el("form", {class:"graph-picker", id:"graph-workflow-query", "aria-label":"科研查询"},
      el("label", {}, "查询 ", el("select", {name:"operation"},
        Object.entries(workflowOperations).map(([value, label]) => option(value, label, operation)))),
      field("起点", pathOperations, nodeSelect("focus", {"method-lineage":"method", reading:"paper"}[operation])),
      field("终点", "bridge", nodeSelect("target")),
      field("深度", pathOperations, number("depth", 1, 10, query.depth ?? 3)),
      field("方向", "method-lineage bridge", choice("direction", [["both","双向"],["outgoing","沿关系方向"],["incoming","逆关系方向"]])),
      field("最少引用它的核心论文数", "missing-core", number("minCitations", 1, 100, query.minCitations ?? 1)),
      field("天数", "stale-citations stale-artifacts", number("thresholdDays", citations ? 365 : 1, 36500,
        query.thresholdDays ?? (citations ? 3650 : 90), {"data-operation":operation})),
      field("问题级别", "unsupported-claims", choice("severity", [["","全部"],["error","缺少原文引用"],["warning","需复核引用"]])),
      el("button", {type:"submit", class:"button", disabled:pending}, "查询"));
    const content = fragment(controls);
    if (error) content.append(el("p", {role:"alert", class:"graph-status"}, error));
    if (result) {
      const found = result.findings || [];
      if (result.notice) content.append(el("p", {class:"graph-status", role:"status"}, result.notice));
      if (found.length) {
        content.append(el("ol", {class:"graph-workflow-findings"}, found.map(row => {
          const links = (row.links || []).map(item =>
            item.nodeId ? nodeButton(item.nodeId) :
              /^\/(research|reader|tools)\?/.test(item.url || "") ? link(item.label, item.url, "bare") : null).filter(Boolean);
          const title = row.title && row.links?.[0]?.nodeId ? (links.shift() || row.title) : row.title;
          return el("li", {}, title, title && row.text ? " · " : null, row.text,
            links.length ? el("p", {}, links.flatMap((item, i) => i ? [" · ", item] : [item])) : null);
        })));
      }
      if (result.truncated) content.append(el("p", {class:"graph-status"}, "当前显示 " + found.length + " 项，共 " + Number(result.total) + " 项。"));
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

  function graphDiagram(result, keys, el) {
    if (!result.edges.length) return null;
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
    const wrapper = el("div", {class:"graph-diagram"});
    const svgElement = (name, attrs, ...children) => {
      const node = wrapper.ownerDocument.createElementNS("http://www.w3.org/2000/svg", name);
      for (const [attr, value] of Object.entries(attrs)) node.setAttribute(attr, value);
      node.append(...children);
      return node;
    };
    const svg = svgElement("svg", {width, height, viewBox:`0 0 ${width} ${height}`, role:"img", "aria-label":"部分关联预览"});
    for (const edge of result.edges) {
      const source = points.get(edge.source), target = points.get(edge.target);
      if (!source || !target || source.x === target.x) continue;
      const left = source.x < target.x ? source : target, right = left === source ? target : source;
      const mid = (left.x + 184 + right.x) / 2;
      svg.append(svgElement("path", {d:`M${left.x + 184} ${left.y} C${mid} ${left.y} ${mid} ${right.y} ${right.x} ${right.y}`}));
    }
    for (const [id, {x, y}] of points) {
      const label = keys.get(id)?.label || id;
      const chars = [...label], excerpt = chars.length > 16 ? chars.slice(0, 16).join("") + "…" : label;
      svg.append(svgElement("g", {}, svgElement("title", {}, label),
        svgElement("rect", {x, y:y - 16, width:184, height:32, rx:7}),
        svgElement("text", {x:x + 10, y:y + 4}, excerpt)));
    }
    wrapper.append(svg);
    return wrapper;
  }

  function graphView({graph, result, project, query, error, pending, workflow, citationPanel}, ui) {
    const {el, fragment, button, heading, panel, empty, link} = ui;
    const nodes = graph.nodes || [];
    const keys = new Map([...nodes, ...result.nodes].map(node => [node.id, node]));
    const allEntries = Object.fromEntries(nodes.map(node => [node.id, node.label + " · " + (nodeKinds[node.kind] || node.kind)]));
    const nodeButton = id => {
      const node = keys.get(id);
      return node ? button(node.label, "graph-open", {id, kind:"bare"}) : id;
    };
    const select = (label, name, none, entries) => {
      const option = (value, title) => el("option", {value, selected:value === query[name]}, title);
      return el("label", {}, label + " ", el("select", {id:"graph-" + name, name},
        none ? option("", none) : null, Object.entries(entries).map(([value, title]) => option(value, title))));
    };
    const actions = fragment(button("重新生成", "graph-rebuild"),
      nodes.length > 1 ? button("新增关系", "new-relation", {glyph:"plus", kind:"button primary"}) : null);
    const out = fragment(heading("知识关联", project.name, actions),
      error ? el("p", {class:"status", role:"alert"}, error) : null);
    const workflowPanel = graphWorkflowPanel(nodes, workflow, ui, nodeButton);
    if (!nodes.length) return fragment(out, panel("项目图谱", empty("暂无可关联的条目", "添加论文、笔记或任务后即可查看项目关系。")), workflowPanel, citationPanel);
    const controls = el("form", {class:"graph-picker", id:"graph-query", "aria-label":"图谱筛选"},
      select("起点", "focus", "全部条目", allEntries),
      select("终点", "target", "仅查看邻居", allEntries),
      select("深度", "depth", "", Object.fromEntries(Array.from({length:11}, (_, n) => [n, String(n)]))),
      select("方向", "direction", "双向", {outgoing:"沿关系方向", incoming:"逆关系方向"}),
      select("关系类型", "kind", query.focus ? "全部确认关系" : "全部关系", edgeKinds),
      select("条目类型", "nodeKind", "全部类型", nodeKinds),
      el("button", {type:"submit", class:"button", disabled:pending}, "应用"));
    const path = result.path;
    let visualization;
    if (path?.found) {
      visualization = el("ol", {class:"graph-path", "aria-label":"最短路径"},
        path.nodes.map(id => el("li", {}, nodeButton(id))));
    } else if (path) {
      visualization = el("p", {class:"graph-status", role:"status"}, "当前筛选条件和深度内未找到连接路径。");
    } else if (result.hops) {
      const layers = new Map();
      for (const node of result.nodes) {
        const hop = result.hops[node.id];
        if (!layers.has(hop)) layers.set(hop, []);
        layers.get(hop).push(node.id);
      }
      visualization = el("ol", {class:"graph-layers", "aria-label":"按距离展开的邻居"},
        [...layers].map(([hop, ids]) => el("li", {}, el("span", {}, hop === 0 ? "起点" : "距离 " + hop),
          el("ul", {}, ids.map(id => el("li", {}, nodeButton(id)))))));
    }
    out.append(panel("项目图谱", fragment(controls, graphDiagram(result, keys, el), visualization)), workflowPanel);
    if (citationPanel) out.append(citationPanel);

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
        button(locator, "graph-occurrence", {id: occurrence.id, kind: "bare"}) : locator;
      const flag = statuses[occurrence.status] || ({
        "normalized-title": "按题名匹配",
        "similar-title": "题名近似，待核对",
        "ambiguous-title": "有多个可能匹配，待核对"
      })[occurrence.resolution];
      const candidates = occurrence.matches?.length && occurrence.resolution === "ambiguous-title" ?
        el("ul", {}, occurrence.matches.map(match => el("li", {}, nodeButton(match.id)))) : null;
      const discussion = occurrence.source === "evidence" && occurrence.meetingId ?
        fragment(" · ", link("来源讨论", meetingLink(project.id, occurrence, ui.route), "bare")) : null;
      return el("li", {}, action, discussion, flag ? el("span", {class:"graph-source-status"}, flag) : null,
        occurrence.quote ? el("blockquote", {}, occurrence.quote) : null, candidates);
    };
    const relations = (result.edges || []).map(edge => {
      const details = edge.occurrences?.length ? el("details", {class:"graph-occurrences"},
        el("summary", {}, edge.occurrences.length + " 处来源"), el("ol", {}, edge.occurrences.map(item => renderOccurrence(edge, item)))) : null;
      return el("div", {class:"graph-edge"}, el("div", {class:"relation"}, nodeButton(edge.source),
        el("span", {class:"tag"}, edgeKinds[edge.kind] || edge.kind), nodeButton(edge.target),
        edge.id ? button("移除", "remove-relation", {id:edge.id, kind:"bare danger"}) : null),
        edge.label ? el("p", {class:"graph-status"}, edge.label) : null, details);
    });
    out.append(panel("关系 · " + relations.length, relations.length ? fragment(relations) : empty("当前范围内暂无关联")),
      panel("条目 · " + result.nodes.length, result.nodes.length ? el("ul", {class:"graph-entries"},
        result.nodes.map(node => el("li", {}, nodeButton(node.id), el("span", {class:"tag"}, nodeKinds[node.kind] || node.kind)))) : empty("暂无条目")));
    return out;
  }

  const api = Object.freeze({defaultQuery, graphView, queryPath, workflowPath, updateWorkflowForm, occurrenceLink});
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.SciResearchGraph = api;
})();
