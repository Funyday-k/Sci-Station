"use strict";
(() => {
  function savedCitation(paper, params) {
    const source = params.get("citation");
    if (source !== "metadata" && source !== "paper-note") return null;
    const revision = Number(params.get("revision"));
    const ordinal = Number(params.get("ordinal"));
    if (!Number.isInteger(revision) || revision < 1 || revision !== paper.revision) {
      return {error: "文献已更新。请重新生成项目图谱后打开该处引用。"};
    }
    if (!Number.isInteger(ordinal) || ordinal < 1) return {error: "引用位置无效。"};
    if (source === "metadata") {
      const text = paper.references?.[ordinal - 1];
      return text ? {text, ordinal} : {error: "该处参考文献已无法定位。"};
    }
    const lines = (paper.notes || "").split("\n");
    const line = Number(params.get("line"));
    const endLine = Number(params.get("endLine") || line);
    if (!Number.isInteger(line) || !Number.isInteger(endLine) || line < 1 || endLine < line || endLine > lines.length) {
      return {error: "该处论文笔记已无法定位。"};
    }
    let start = 0, end;
    for (let i = 0; i < line - 1; i++) start += lines[i].length + 1;
    end = start;
    for (let i = line - 1; i < endLine; i++) end += lines[i].length + 1;
    return {line, start, end: end - 1};
  }

  function open(paper, params, by, showTab) {
    // HTML textarea values normalize CRLF before setting a selection range.
    const result = savedCitation({...paper, notes: by("notes").value}, params);
    if (!result) return;
    const notice = by("graphCitation");
    notice.hidden = false;
    if (result.error) {
      notice.textContent = result.error;
    } else if (result.line) {
      notice.textContent = "论文笔记 · 第 " + result.line + " 行";
      showTab(true);
      by("notes").focus();
      by("notes").setSelectionRange(result.start, result.end);
    } else {
      notice.textContent = "文献元数据 · 参考文献 " + result.ordinal + " · " + result.text;
    }
  }

  const api = Object.freeze({savedCitation, open});
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window !== "undefined") window.SciReaderGraphSource = api;
})();
