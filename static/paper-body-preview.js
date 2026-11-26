(() => {
  "use strict";

  function figureURL(paper, hash, asset) {
    if (!/^[a-f0-9]{32}$/.test(paper || "") || !/^[a-f0-9]{64}$/.test(hash || "") || !/^[a-f0-9]{64}$/.test(asset || "")) return "";
    return "/api/research/papers/" + paper + "/body/figures/" + hash + "/" + asset;
  }

  function figureRange(figure, source) {
    const chars = Array.from(source.text);
    const start = figure.citeStart - (source.offset || 0);
    const end = figure.citeEnd - (source.offset || 0);
    if (start < 0 || end <= start || end - start > 1000 || end > chars.length) return null;
    return [chars.slice(0, start).join("").length, chars.slice(0, end).join("").length];
  }

  function imageKey(raw) {
    const value = raw.trim();
    if (/[?#]/.test(value)) return null;
    try {
      return decodeURIComponent(value);
    } catch {
      return value;
    }
  }

  function resolveImages(paper, hash, figures) {
    const paths = new Map((figures || []).flatMap(figure => {
      const url = figureURL(paper, hash, figure.assetId);
      const key = imageKey(figure.reference);
      return url && key ? [[key, url]] : [];
    }));
    return raw => paths.get(imageKey(raw));
  }

  if (typeof module !== "undefined") {
    module.exports = {figureURL, figureRange, resolveImages};
    return;
  }

  function element(tag, text = "") {
    const value = document.createElement(tag);
    value.textContent = text;
    return value;
  }

  function quality(host, report) {
    host.replaceChildren();
    if (!report) return;
    const labels = {mineru:"MinerU 转换", pdfkit:"PDFKit 文本提取", import:"导入文件 · 抽取工具未标注"};
    const figures = report.figures || [];
    const summary = [
      labels[report.engine] || "抽取工具未标注",
      report.hasAbstract ? "有摘要标题" : "未识别到摘要标题",
      report.hasDisplayMath ? "有独立公式" : "未识别到独立公式",
    ];
    if (figures.length) summary.push((figures.length - report.missingFigures) + " 条引用有本地附件 · " + report.missingFigures + " 条缺失");
    host.append(element("p", summary.join(" · ")));
    if (report.engine === "pdfkit") host.append(element("p", "PDFKit 提取的是 PDF 文本。公式、图片和版面请对照原始 PDF。"));
    if (report.assetCheckFailed) host.append(element("p", "无法核对图片目录。正文仍可查看。"));
    if (report.figureListLimited) host.append(element("p", "图片列表已达到 512 条。其余引用仍保留在正文中。"));
  }

  function renderFigures(host, figures, {paper, hash, select} = {}) {
    host.replaceChildren();
    host.hidden = !figures?.length;
    if (host.hidden) return;
    const list = element("ul");
    for (const figure of figures) {
      const row = element("li");
      const label = figure.label || figure.reference;
      const title = "第 " + figure.line + " 行 · " + label + (label === figure.reference ? "" : " · " + figure.reference);
      const url = figureURL(paper, hash, figure.assetId);
      if (url) {
        const details = element("details");
        details.append(element("summary", title));
        details.addEventListener("toggle", () => {
          if (!details.open || details.childElementCount !== 1) return;
          const image = element("img");
          image.alt = label;
          image.loading = "lazy";
          image.addEventListener("error", () => image.replaceWith(element("p", "无法读取此图片，请核对当前来源版本。")), {once:true});
          image.src = url;
          details.append(image);
        });
        row.append(details);
      } else {
        const status = figure.assetId ? "已找到本地附件" : "缺少可用的本地附件";
        row.append(element("p", title + " · " + status));
      }
      if (select) {
        const button = element("button", "定位原文");
        button.type = "button";
        button.onclick = () => select(figure);
        row.append(button);
      }
      list.append(row);
    }
    host.append(list);
  }

  window.SciPaperBodyPreview = {figureRange, resolveImages, quality, renderFigures};
})();
