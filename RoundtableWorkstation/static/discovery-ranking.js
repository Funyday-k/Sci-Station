"use strict";
(() => {
  const terms = text => new Set((text.toLowerCase().match(/[\p{L}\p{N}]{3,}/gu) || []));
  const paperTerms = p => terms([p.title, p.abstract, ...(p.tags || [])].join(" "));

  function similarity(a, b) {
    if (!a.size || !b.size) return 0;
    let common = 0;
    for (const term of a) if (b.has(term)) common++;
    return common / Math.sqrt(a.size * b.size);
  }

  function canonical(arxiv) {
    return arxiv.toLowerCase().replace(/v\d+$/, "");
  }

  function feedbackState(feedback, arxiv) {
    const key = canonical(arxiv);
    return feedback[key] ?? feedback[arxiv] ?? Object.entries(feedback).find(([id]) => canonical(id) === key)?.[1] ?? "";
  }

  // Use local context for ranking; only the user's search expression goes to arXiv.
  function candidates(feed, options) {
    const {category, crossList, filter, project, papers} = options;
    const selected = new Set(category.toLowerCase().split(/[\s,，]+/).filter(Boolean));
    const items = feed.items || [];
    const feedback = feed.feedback || {};
    const text = terms([project?.name, project?.description].join(" "));
    const seeds = papers.filter(p => p.core_project_ids?.includes(project?.id) || p.rating >= 4 || p.status === "read").map(paperTerms);
    const saved = items.filter(p => feedbackState(feedback, p.arxiv) === "saved").map(paperTerms);
    const search = terms((feed.query || "").replace(/\b(?:all|ti|abs|cat|au):|\b(?:AND|OR|NOT)\b/gi, " "));
    const seen = new Set();
    const remaining = [];
    for (const [index, p] of items.entries()) {
      const state = feedbackState(feedback, p.arxiv);
      if (filter === "all" ? state === "hidden" : state !== filter) continue;
      const categories = p.tags || [];
      if (selected.size && !(crossList ? categories : categories.slice(0, 1)).some(t => selected.has(t.toLowerCase()))) continue;
      const key = canonical(p.arxiv);
      if (seen.has(key)) continue;
      seen.add(key);
      const words = paperTerms(p);
      const strongest = corpus => corpus.reduce((best, other) => Math.max(best, similarity(words, other)), 0);
      const relevance = 0.34 * strongest(seeds) + 0.25 * similarity(words, text) + 0.20 * similarity(words, search)
        + 0.11 * strongest(saved) + 0.10 / (1 + index / 10);
      remaining.push({paper: p, words, relevance, redundancy: 0});
    }
    const ranked = [];
    while (remaining.length) {
      // The legacy pipeline uses maximal marginal relevance with lambda = 0.75.
      const score = row => 0.75 * row.relevance - 0.25 * row.redundancy;
      const best = remaining.reduce((i, row, j) => score(row) > score(remaining[i]) ? j : i, 0);
      const [next] = remaining.splice(best, 1);
      ranked.push(next.paper);
      for (const row of remaining) row.redundancy = Math.max(row.redundancy, similarity(row.words, next.words));
    }
    return ranked;
  }

  const api = {canonical, candidates, feedbackState};
  if (typeof module !== "undefined") module.exports = api;
  else globalThis.SciStationDiscovery = api;
})();
