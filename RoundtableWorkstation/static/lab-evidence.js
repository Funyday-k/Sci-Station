(() => {
  "use strict";

  const sourceStatus = {
    located: "原文与位置已核对", unavailable: "当前无法读取来源", shortened: "运行输入中的摘录已缩短",
    invalid_locator: "原文定位无效", stale: "原文版本或选段已改变", invalid_quote: "原文与记录选段不符"
  };
  const claimStatus = {located: "引用已定位", missing_reference: "缺少原文引用", incomplete: "部分引用无法核对", unresolved: "引用无法核对"};
  const warnings = {strong_wording: "含强措辞，请复核其适用条件", reused_source: "同一选段用于四项或更多声明，请逐项核对"};
  const quality = {
    missing_direct_answer: "没有可核对的直接回答。",
    missing_evidence: "问题涉及论文正文，当前缺少可核对的论文选段。",
    missing_content_explanation: "回答未说明哪些正文或公式尚未读取。",
    missing_display_math: "公式问题的回答缺少独立显示的公式。",
    missing_source: "回答没有引用已核对的论文选段。"
  };

  function element(tag, content = "") {
    const node = document.createElement(tag);
    node.textContent = content;
    return node;
  }

  function sourceLocation(evidence) {
    if (evidence.source) return "字符 " + (evidence.source.offset + 1) + "–" + evidence.source.end;
    if (evidence.page) return "第 " + evidence.page + " 页" + (Number.isInteger(evidence.selectionStart) && Number.isInteger(evidence.selectionEnd)
      ? " · 页内位置 " + evidence.selectionStart + "–" + evidence.selectionEnd : "");
    return "";
  }

  const sourceAnchor = (prefix, id) => prefix + "-" + id;

  function render({project, prefix}, result) {
    const boundary = element("p", "此检查核对引用、原文版本和文字位置。声明是否得到科学支持，仍需逐条人工判断。");
    const items = [boundary];
    if (result.reviewBlock) {
      const notice = element("p", "申请入库前 · " + result.reviewBlock);
      notice.className = "lab-evidence-warning";
      items.push(notice);
    }
    if (result.truncated) items.push(element("p", "结果只显示前 160 条可识别声明。"));
    if (result.qualityIssues?.length) {
      const issues = element("ul");
      for (const key of result.qualityIssues) issues.append(element("li", quality[key] || key));
      items.push(issues);
    }
    if (result.claims?.length) {
      items.push(element("h4", "逐条声明"));
      const list = element("ol");
      const sourceIDs = new Set((result.sources || []).map(s => s.id));
      for (const claim of result.claims) {
        const entry = element("li");
        entry.append(element("strong", "第 " + claim.line + " 行 · " + (claimStatus[claim.status] || claim.status)));
        entry.append(element("p", claim.text));
        const links = element("div");
        links.className = "lab-evidence-refs";
        for (const id of claim.references || []) {
          if (!sourceIDs.has(id)) {
            links.append(element("span", id + " · 此轮未找到来源"));
            continue;
          }
          const link = element("a", id);
          link.href = "#" + sourceAnchor(prefix, id);
          links.append(link);
        }
        if (links.childNodes.length) entry.append(links);
        for (const code of claim.warnings || []) entry.append(element("small", warnings[code] || code));
        list.append(entry);
      }
      items.push(list);
    } else items.push(element("p", "此回答未识别到可逐条检查的声明。"));
    if (result.sources?.length) items.push(element("h4", "本轮原文"));
    for (const ref of result.sources || []) {
      const e = ref.evidence;
      const section = element("section");
      section.id = sourceAnchor(prefix, ref.id);
      section.className = "lab-evidence-source";
      section.append(element("h5", ref.id + " · " + (ref.title || "来源")), element("p", sourceStatus[ref.status] || ref.status));
      if (e) {
        section.append(element("blockquote", e.quote), element("p", sourceLocation(e)), element("code", e.sourceHash));
        const href = ref.status === "located" ? window.SciEvidence?.href(project, e) : "";
        if (href) {
          const link = element("a", "打开原文位置");
          link.href = href;
          section.append(link);
        }
      }
      items.push(section);
    }
    return items;
  }

  function inspection({room, project, output, req}) {
    const details = element("details");
    details.className = "lab-evidence-inspection";
    const refresh = element("button", "重新检查");
    refresh.type = "button";
    const message = element("p");
    message.setAttribute("role", "status");
    const body = element("div");
    details.append(element("summary", "证据检查"), refresh, message, body);
    let started = false;
    async function check() {
      const query = new URLSearchParams({project, output});
      refresh.disabled = true;
      message.textContent = "正在核对记录的原文…";
      body.replaceChildren();
      try {
        const result = await req("/api/research/lab/evidence/" + encodeURIComponent(room) + "?" + query);
        if (!details.isConnected || result.output !== output) return;
        body.replaceChildren(...render({project, prefix: "lab-" + room + "-" + output}, result));
        message.textContent = "";
      } catch (error) {
        if (details.isConnected) message.textContent = error.message;
      } finally {
        refresh.disabled = false;
      }
    }
    refresh.addEventListener("click", check);
    details.addEventListener("toggle", () => {
      if (details.open && !started) {
        started = true;
        check();
      }
    });
    return details;
  }

  const api = {inspection, render, sourceLocation};
  if (typeof module === "object" && module.exports) module.exports = api;
  else window.SciLabEvidence = api;
})();
