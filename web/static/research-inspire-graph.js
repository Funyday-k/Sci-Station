"use strict";
(() => {
  function publicSeed(input) {
    const text = String(input || "").trim();
    const match = /^(?:(?:https:\/\/inspirehep\.net\/literature\/|inspire:\s*))?([0-9]{1,12})\/?$/i.exec(text);
    const id = match?.[1].replace(/^0+/, "");
    return id ? "inspire:" + id : "";
  }

  function lookupPath(base, seeds, online) {
    const params = new URLSearchParams();
    for (const seed of seeds) params.append("seed", seed);
    if (online) params.set("online", "1");
    return base + "?" + params;
  }

  function renderPanel({papers, seeds, rows, pending, error}, {el, fragment, button, panel}) {
    const label = seed => papers.find(paper => paper.id === seed)?.title || "INSPIRE " + seed.replace(/^inspire:/, "");
    const chips = seeds.length ? el("ul", {class:"inspire-seeds"}, seeds.map(seed =>
      el("li", {}, el("span", {}, label(seed)), button("移除 " + label(seed), "inspire-seed-remove", {id:seed, kind:"bare"})))) : null;
    const choices = papers.filter(paper => !seeds.includes(paper.id));
    const disabled = pending || seeds.length >= 6;
    const add = el("div", {class:"inspire-picker"},
      el("label", {}, "添加项目论文 ", el("select", {id:"inspire-paper", disabled},
        el("option", {value:""}, "选择论文"), choices.map(paper => el("option", {value:paper.id}, paper.title)))),
      el("label", {}, "INSPIRE 记录 ", el("input", {id:"inspire-record", inputmode:"url", placeholder:"记录编号或论文链接", disabled})),
      button("添加种子", "inspire-seed-add"));
    const actions = seeds.length ? el("div", {class:"inspire-actions"}, button("查看本地与缓存", "inspire-local"),
      button("查询 INSPIRE", "inspire-online", {kind:"button primary"})) : null;
    const result = (rows || []).map(row => {
      const localNodes = new Map(row.local.nodes.map(node => [node.id, node]));
      const externalPaper = entry => {
        const p = entry.paper, href = "https://inspirehep.net/literature/" + encodeURIComponent(p.id);
        const detail = [p.year, p.citations ? p.citations + " 次被引" : ""].filter(Boolean).join(" · ");
        return el("li", {}, el("a", {href, target:"_blank", rel:"noopener"}, p.title),
          detail ? fragment(" ", el("small", {}, detail)) : null,
          button("设为种子", "inspire-seed-add", {id:"inspire:" + p.id, kind:"bare"}));
      };
      const localEntry = edge => {
        const id = edge.source === row.seed ? edge.target : edge.source;
        return el("li", {}, button(localNodes.get(id)?.label || id, "graph-open", {id, kind:"bare"}));
      };
      const column = (title, remote, local) => el("div", {}, el("h4", {}, title),
        remote?.length ? el("ol", {}, remote.map(externalPaper)) : null,
        local.length ? fragment(el("p", {}, "本地记录"), el("ul", {}, local.map(localEntry))) : null,
        !remote?.length && !local.length ? el("p", {class:"form-help"}, "暂无记录") : null);
      const source = {inspire:"INSPIRE 在线", cache:"INSPIRE 缓存", local:"本地图谱"}[row.source];
      const time = row.fetchedAt ? new Date(row.fetchedAt).toLocaleString() : "";
      const title = row.localLabel || row.inspire?.paper?.title || label(row.seed);
      return el("section", {class:"inspire-result"}, el("h3", {}, title),
        el("p", {class:"form-help"}, [source, time, row.warning].filter(Boolean).join(" · ")),
        el("div", {class:"inspire-columns"}, column("参考文献", row.inspire?.references, row.local.edges.filter(edge => edge.source === row.seed)),
          column("引用该论文", row.inspire?.citedBy, row.local.edges.filter(edge => edge.target === row.seed))));
    });
    const status = pending ? el("p", {class:"status", role:"status"}, "正在读取引用图谱…") :
      error ? el("p", {class:"status", role:"alert"}, error) : null;
    return panel("INSPIRE 引用图谱", fragment(add, chips, actions, status, result));
  }

  const api = Object.freeze({lookupPath, publicSeed, renderPanel});
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.SciInspireGraph = api;
})();
