"use strict";
(() => {
  const formats = {bibtex: "BibTeX", apa: "APA", mla: "MLA", chicago: "Chicago", ieee: "IEEE", ris: "RIS"};
  const make = (tag, text) => {
    const element = document.createElement(tag);
    if (text) element.textContent = text;
    return element;
  };
  async function response(path, method = "GET") {
    const options = method === "POST" ? {
      method, headers: {"X-Roundtable": "1", "Content-Type": "application/json"}, body: "{}"
    } : {method};
    const res = await fetch(path, options);
    const body = await res.json();
    if (!res.ok) throw Error(body.error || "无法读取引文");
    return body;
  }
  function open(paperID) {
    if (!paperID || document.querySelector(".sci-citations[open]")) return;
    const panel = make("dialog");
    panel.className = "sci-citations";
    panel.setAttribute("aria-label", "引用文献");
    const title = make("h2", "引用文献");
    const label = make("label", "引文格式");
    const format = make("select");
    format.setAttribute("aria-label", "引文格式");
    for (const [id, name] of Object.entries(formats)) {
      const option = make("option", name);
      option.value = id;
      format.append(option);
    }
    label.append(" ", format);
    const preview = make("textarea");
    preview.readOnly = true;
    preview.setAttribute("aria-label", "引文预览");
    preview.rows = 12;
    const status = make("p");
    status.setAttribute("role", "status");
    const actions = make("div");
    const control = name => {
      const button = make("button", name);
      button.type = "button";
      actions.append(button);
      return button;
    };
    const copy = control("复制");
    const save = control("保存 BibTeX");
    const close = control("关闭");
    const base = "/api/research/papers/" + encodeURIComponent(paperID);
    let version = 0;
    async function changeFormat() {
      const request = ++version;
      const chosen = format.value;
      preview.value = "";
      copy.disabled = save.disabled = true;
      status.textContent = "";
      try {
        const result = await response(base + "/citation?format=" + chosen);
        if (request !== version) return;
        preview.value = result.text;
        copy.disabled = false;
        save.disabled = chosen !== "bibtex";
      } catch (error) {
        if (request === version) status.textContent = error.message;
      }
    }
    format.addEventListener("change", changeFormat);
    copy.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(preview.value);
        status.textContent = "引文已复制";
      } catch {
        preview.focus();
        preview.select();
        status.textContent = "已选中引文，可使用系统复制";
      }
    });
    save.addEventListener("click", async () => {
      save.disabled = true;
      try {
        const result = await response("/api/research/papers/bibtex/save?paper=" + encodeURIComponent(paperID), "POST");
        if (result.saved) status.textContent = "已保存 BibTeX";
        if (result.browser_download) {
          const download = make("a");
          download.href = base + "/bibtex";
          download.download = "references.bib";
          document.body.append(download);
          download.click();
          download.remove();
        }
      } catch (error) {
        status.textContent = error.message;
      } finally {
        save.disabled = format.value !== "bibtex" || !preview.value;
      }
    });
    close.addEventListener("click", () => panel.close());
    panel.addEventListener("close", () => panel.remove(), {once: true});
    panel.append(title, label, preview, status, actions);
    document.body.append(panel);
    panel.showModal();
    changeFormat();
  }
  window.SciStationCitations = {open};
  document.addEventListener("click", event => {
    const target = event.target.closest?.("[data-citation-paper]");
    if (!target) return;
    open(target.dataset.citationPaper || new URLSearchParams(location.search).get("paper"));
  });
})();
