"use strict";
(() => {
  function href(project, evidence) {
    const source = evidence.source;
    if (source && (source.kind === "note" || source.kind === "material")) {
      const note = source.kind === "note";
      return "/research?" + new URLSearchParams({
        project: source.projectId, view: note ? "notes" : "materials", [note ? "note" : "material"]: source.id,
        fingerprint: evidence.sourceHash, offset: source.offset, end: source.end
      });
    }
    if (!evidence.paperId) return "";
    const query = new URLSearchParams({paper: evidence.paperId});
    if (project) query.set("project", project);
    for (const [key, value] of Object.entries({
      page: evidence.page, fingerprint: evidence.sourceHash, quote: evidence.quote,
      start: evidence.selectionStart, end: evidence.selectionEnd, ocr: evidence.ocr ? "1" : "", annotation: evidence.annotationId
    })) if (value !== null && value !== undefined && value !== "") query.set(key, value);
    return "/reader?" + query;
  }

  function label(evidence) {
    if (evidence.source?.kind === "note") return "打开 Wiki 原文";
    if (evidence.source?.kind === "material") return "打开项目材料原文";
    return evidence.page > 0 ? "打开论文第 " + evidence.page + " 页" : "打开关联论文";
  }

  function locator(query) {
    if (!query.has("fingerprint") && !query.has("offset") && !query.has("end")) return null;
    return {fingerprint: query.get("fingerprint") || "", offset: query.get("offset") || "", end: query.get("end") || ""};
  }

  function query(location) {
    return new URLSearchParams(location).toString();
  }

  const evidence = Object.freeze({href, label, locator, query});
  if (typeof module !== "undefined" && module.exports) module.exports = evidence;
  if (typeof window !== "undefined") window.SciEvidence = evidence;
})();
