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

  function renderPanel({papers, seeds, rows, pending, error}, {esc, button, panel}) {
    const label = seed => papers.find(paper => paper.id === seed)?.title || "INSPIRE " + seed.replace(/^inspire:/, "");
    const chips = seeds.length ? '<ul class="inspire-seeds">' + seeds.map(seed =>
      '<li><span>' + esc(label(seed)) + '</span>' + button("移除 " + label(seed), "inspire-seed-remove", {id:seed, kind:"bare"}) + "</li>"
    ).join("") + "</ul>" : "";
    const choices = papers.filter(paper => !seeds.includes(paper.id));
    const disabled = pending || seeds.length >= 6 ? " disabled" : "";
    const add = '<div class="inspire-picker"><label>添加项目论文 <select id="inspire-paper"' + disabled + '><option value="">选择论文</option>' +
      choices.map(paper => '<option value="' + esc(paper.id) + '">' + esc(paper.title) + "</option>").join("") +
      '</select></label><label>INSPIRE 记录 <input id="inspire-record" inputmode="url" placeholder="记录编号或论文链接"' + disabled +
      '></label>' + button("添加种子", "inspire-seed-add") + "</div>";
    const actions = seeds.length ? '<div class="inspire-actions">' + button("查看本地与缓存", "inspire-local") +
      button("查询 INSPIRE", "inspire-online", {kind:"button primary"}) + "</div>" : "";
    const result = (rows || []).map(row => {
      const localNodes = new Map(row.local.nodes.map(node => [node.id, node]));
      const externalPaper = entry => {
        const p = entry.paper, href = "https://inspirehep.net/literature/" + encodeURIComponent(p.id);
        const detail = [p.year, p.citations ? p.citations + " 次被引" : ""].filter(Boolean).join(" · ");
        return '<li><a href="' + esc(href) + '" target="_blank" rel="noopener">' + esc(p.title) + "</a>" +
          (detail ? ' <small>' + esc(detail) + '</small>' : "") +
          button("设为种子", "inspire-seed-add", {id:"inspire:" + p.id, kind:"bare"}) + "</li>";
      };
      const localEntry = edge => {
        const id = edge.source === row.seed ? edge.target : edge.source;
        return '<li>' + button(localNodes.get(id)?.label || id, "graph-open", {id, kind:"bare"}) + "</li>";
      };
      const column = (title, remote, local) => '<div><h4>' + title + '</h4>' +
        (remote?.length ? "<ol>" + remote.map(externalPaper).join("") + "</ol>" : "") +
        (local.length ? '<p>本地记录</p><ul>' + local.map(localEntry).join("") + "</ul>" : "") +
        (!remote?.length && !local.length ? '<p class="form-help">暂无记录</p>' : "") + '</div>';
      const source = {inspire: "INSPIRE 在线", cache: "INSPIRE 缓存", local: "本地图谱"}[row.source];
      const time = row.fetchedAt ? new Date(row.fetchedAt).toLocaleString() : "";
      const title = row.localLabel || row.inspire?.paper?.title || label(row.seed);
      return '<section class="inspire-result"><h3>' + esc(title) + '</h3><p class="form-help">' + esc([source, time, row.warning].filter(Boolean).join(" · ")) +
        '</p><div class="inspire-columns">' + column("参考文献", row.inspire?.references, row.local.edges.filter(edge => edge.source === row.seed)) +
        column("引用该论文", row.inspire?.citedBy, row.local.edges.filter(edge => edge.target === row.seed)) + "</div></section>";
    }).join("");
    const status = pending ? '<p class="status" role="status">正在读取引用图谱…</p>' : error ? '<p class="status" role="alert">' + esc(error) + '</p>' : "";
    return panel("INSPIRE 引用图谱", add + chips + actions + status + result);
  }

  const api = Object.freeze({lookupPath, publicSeed, renderPanel});
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.SciInspireGraph = api;
})();
