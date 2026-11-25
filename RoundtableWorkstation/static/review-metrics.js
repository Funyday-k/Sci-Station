/* Exact, bounded source-text change metrics. Loaded by the review worker; also
 * exported for the Node regression suite. No network or DOM access is used. */
(function (root) {
  'use strict';
  const DOCUMENT = /\.(?:tex|ltx|latex|md|mdx|markdown|mdown|mkd|txt|text|rst|rest|org|adoc|asciidoc)$/i;
  const MAX_DIFF = 4 * 1024 * 1024;
  const MAX_TEXT = 400000;
  const MAX_TOKENS = 250000;
  const MAX_STEPS = 4000000;
  const MAX_DISTANCE = 2048;
  const CACHE_BYTES = 8 * 1024 * 1024;
  const cache = new Map();
  let cacheBytes = 0;
  const definition = Object.freeze({
    characters: 'Non-whitespace Unicode grapheme clusters (user-perceived characters).',
    words: 'Intl.Segmenter("zh", {granularity:"word"}), isWordLike tokens.',
    scope: 'Exact token insertions/deletions inside each contiguous changed fragment; document source, including TeX/Markdown syntax.',
  });
  const failure = (reason) => { const e = new Error(reason); e.reason = reason; throw e; };

  // Read only unified hunks. Header-like source lines inside a hunk remain
  // source: +++x means the added line ++x, not a file header.
  function parseUnified(diff) {
    if (diff === '') return { lines: { added: 0, removed: 0 }, blocks: [] };
    let oldLeft = 0, newLeft = 0, active = false, seen = false;
    let added = 0, removed = 0, block = null;
    const blocks = [];
    const flush = () => { if (block) { blocks.push(block); block = null; } };
    const rows = diff.split('\n');
    for (let i = 0; i < rows.length; i++) {
      let row = rows[i];
      if (row.endsWith('\r')) row = row.slice(0, -1);
      if (active && oldLeft === 0 && newLeft === 0) { active = false; flush(); }
      if (active) {
        if (row === '\\ No newline at end of file') continue;
        const mark = row[0];
        if (mark === ' ' && oldLeft > 0 && newLeft > 0) {
          flush(); oldLeft--; newLeft--; continue;
        }
        if (mark === '-' && oldLeft > 0) {
          block ||= { before: [], after: [] };
          block.before.push(row.slice(1)); oldLeft--; removed++; continue;
        }
        if (mark === '+' && newLeft > 0) {
          block ||= { before: [], after: [] };
          block.after.push(row.slice(1)); newLeft--; added++; continue;
        }
        failure('incomplete-or-invalid-hunk');
      }
      if (row.startsWith('@@')) {
        const h = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?:.*)$/.exec(row);
        if (!h) failure('unsupported-hunk-header');
        oldLeft = h[2] === undefined ? 1 : Number(h[2]);
        newLeft = h[4] === undefined ? 1 : Number(h[4]);
        if (!Number.isSafeInteger(oldLeft) || !Number.isSafeInteger(newLeft)) failure('unsupported-hunk-header');
        active = true; seen = true;
      } else if (row === '\\ No newline at end of file' || row === '' ||
        /^(?:diff |index |--- |\+\+\+ |new file mode |deleted file mode |old mode |new mode |similarity index |dissimilarity index |rename from |rename to |copy from |copy to )/.test(row)) {
        // Metadata is outside all counted source regions.
      } else {
        failure('unsupported-diff-content');
      }
    }
    if (active && (oldLeft || newLeft)) failure('incomplete-or-invalid-hunk');
    flush();
    if (!seen) failure('no-unified-hunks');
    return { lines: { added, removed }, blocks };
  }

  // Myers' shortest edit distance computes exact token insertion/deletion
  // counts without constructing an alignment matrix or retaining edit traces.
  function compare(before, after, budget) {
    let start = 0, aEnd = before.length, bEnd = after.length;
    while (start < aEnd && start < bEnd && before[start] === after[start]) start++;
    while (aEnd > start && bEnd > start && before[aEnd - 1] === after[bEnd - 1]) { aEnd--; bEnd--; }
    const n = aEnd - start, m = bEnd - start;
    if (!n || !m) return { added: m, removed: n };
    if (Math.abs(n - m) > MAX_DISTANCE) failure('exact-comparison-budget-exceeded');
    const limit = Math.min(n + m, MAX_DISTANCE);
    const offset = limit + 1;
    let v = new Int32Array(2 * limit + 3);
    v.fill(-1); v[offset + 1] = 0;
    for (let d = 0; d <= limit; d++) {
      for (let k = -d; k <= d; k += 2) {
        if (++budget.steps > MAX_STEPS) failure('exact-comparison-budget-exceeded');
        const slot = offset + k;
        let x = k === -d || (k !== d && v[slot - 1] < v[slot + 1]) ? v[slot + 1] : v[slot - 1] + 1;
        let y = x - k;
        while (x < n && y < m && before[start + x] === after[start + y]) {
          if (++budget.steps > MAX_STEPS) failure('exact-comparison-budget-exceeded');
          x++; y++;
        }
        v[slot] = x;
        if (x >= n && y >= m) return { added: (d + m - n) / 2, removed: (d + n - m) / 2 };
      }
    }
    failure('exact-comparison-budget-exceeded');
  }

  function compute(diff, path) {
    const document = DOCUMENT.test(path || '');
    const result = { status: 'ok', document, lines: null, definition };
    if (typeof diff !== 'string') return { ...result, status: 'unavailable', reason: 'missing-unified-diff' };
    if (diff.length > MAX_DIFF) return { ...result, status: 'unavailable', reason: 'diff-size-budget-exceeded' };
    let parsed;
    try { parsed = parseUnified(diff); } catch (e) { return { ...result, status: 'unavailable', reason: e.reason || 'invalid-diff' }; }
    result.lines = parsed.lines;
    if (!document) return result;
    if (typeof Intl.Segmenter !== 'function') return { ...result, status: 'unavailable', reason: 'unicode-segmenter-unavailable' };
    const totals = { characters: { added: 0, removed: 0 }, words: { added: 0, removed: 0 } };
    const budget = { steps: 0, tokens: 0 };
    const segments = {
      characters: new Intl.Segmenter('zh', { granularity: 'grapheme' }),
      words: new Intl.Segmenter('zh', { granularity: 'word' }),
    };
    const tokenize = (text, mode) => {
      const tokens = [];
      for (const item of segments[mode].segment(text)) {
        if (mode === 'words' ? item.isWordLike : /\S/u.test(item.segment)) {
          if (++budget.tokens > MAX_TOKENS) failure('tokenization-budget-exceeded');
          tokens.push(item.segment);
        }
      }
      return tokens;
    };
    try {
      for (const block of parsed.blocks) {
        const before = block.before.join('\n'), after = block.after.join('\n');
        if (before.length + after.length > MAX_TEXT) failure('fragment-size-budget-exceeded');
        for (const mode of ['characters', 'words']) {
          // Each source fragment is segmented once per definition. Cached
          // results allow toggling the UI metric without re-tokenizing.
          const metric = compare(tokenize(before, mode), tokenize(after, mode), budget);
          totals[mode].added += metric.added;
          totals[mode].removed += metric.removed;
        }
      }
    } catch (e) { return { ...result, status: 'unavailable', reason: e.reason || 'comparison-failed' }; }
    return { ...result, ...totals };
  }

  function analyze(diff, path) {
    // Exact content is the key, so revisions of the same path cannot collide.
    const key = typeof diff === 'string' ? (DOCUMENT.test(path || '') ? 'doc\0' : 'code\0') + diff : null;
    if (key && cache.has(key)) { const value = cache.get(key); cache.delete(key); cache.set(key, value); return value; }
    const result = compute(diff, path);
    if (key && key.length <= CACHE_BYTES / 2) {
      cache.set(key, result); cacheBytes += key.length * 2;
      while (cache.size > 8 || cacheBytes > CACHE_BYTES) {
        const oldest = cache.keys().next().value; cache.delete(oldest); cacheBytes -= oldest.length * 2;
      }
    }
    return result;
  }
  const api = Object.freeze({ analyze, parseUnified });
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.RoundtableReviewMetrics = api;
})(typeof self !== 'undefined' ? self : globalThis);
