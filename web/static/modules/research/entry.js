// Native ES module entry point for research workspace forms (#45).
import { renderTaskTagChip } from "./dom.js";
import {
  appendSnippetOptions,
  renderBacklinks,
  renderNoteConflict,
  renderSnippetConflict,
  renderWikiMetadata,
} from "./wiki.js";
import { renderFilePreview, renderProjectFilesList } from "./files.js";

  const E = window.SciResearch;
  const wikiEditor = window.SciWikiEditor;
  const {
    state,
    $,
    el,
    fragment,
    enc,
    request,
    projectPath,
    refresh,
    load,
    render,
    button,
    link,
    empty,
    dialog,
    close,
    toast,
    reader,
    statusLabel,
    renderWikiMarkdown,
    bytes
  } = E;
  const copy = (zh, en) => E.text?.(zh, en) ?? zh;
  const local = (key, zh, en) => E.local?.(key, zh, en) ?? copy(zh, en);
  const field = (label, content) => el("label", {class: "field"}, el("span", {}, label), content);

  function input(name, value = "", options = {}) {
    return el("input", {name, value: value ?? "", ...options});
  }

  function area(name, value = "", options = {}) {
    return el("textarea", {name, ...options}, value ?? "");
  }

  function option(value, label, current) {
    return el("option", {value, selected: String(value) === String(current)}, label);
  }

  function select(name, items, current, label = "", disabled = false) {
    return el("select", {name, "aria-label": label || null, disabled},
      items.map(([value, title]) => option(value, title, current)));
  }

  function split(s) {
    return String(s || "").split(/[,，;；\n]+/).map(s => s.trim()).filter(Boolean);
  }
  const value = (f, name) => String(f.elements.namedItem(name)?.value || "").trim();
  const chosen = (f, name) => [...f.querySelectorAll('input[name="' + name + '"]:checked')].map(i => i.value);
  const formStatus = () => fragment(el("p", {class: "error", "data-error": true, role: "alert"}),
    el("p", {class: "status", "data-status": true, role: "status"}));
  function formFooter(label, deletion = "") {
    let removeButton = null;
    if (deletion) {
      let title = copy("删除", "Delete");
      if (deletion.startsWith("project:")) title = local("projectArchiveAction", "归档项目", "Archive Project");
      if (deletion.startsWith("paper:")) title = copy("从共享文献库删除", "Delete from Shared Library");
      removeButton = button(title, "confirm-delete", {id: deletion, kind: "bare danger"});
    }
    return fragment(formStatus(), el("div", {class: "form-foot"}, removeButton,
      el("button", {type: "button", class: "button", "data-action": "close-dialog"}, local("appCancel", "取消", "Cancel")),
      el("button", {type: "submit", class: "button primary"}, label)));
  }
  let formEpoch = 0;

  function bindForm(onSubmit) {
    const f = $("dialog-content").querySelector("form");
    const token = ++formEpoch;
    f.addEventListener("submit", async e => {
      e.preventDefault();
      if (f.dataset.pending || !f.reportValidity()) return;
      f.dataset.pending = "true";
      const submit = e.submitter || f.querySelector("[type=submit]");
      submit.disabled = true;
      const error = f.querySelector("[data-error]"),
        status = f.querySelector("[data-status]");
      error.textContent = "";
      status.textContent = copy("正在保存…", "Saving…");
      try {
        await onSubmit(f, token, submit);
      } catch (err) {
        error.textContent = err.message;
        status.textContent = "";
      } finally {
        delete f.dataset.pending;
        submit.disabled = false;
      }
    });
    return f;
  }

  function done(token) {
    if (token === formEpoch) close();
  }

  function attachProjectBoxes(paper, creating) {
    if (!state.projects.length) return "";
    const selected = paper?.project_ids || (creating && state.project ? [state.project.id] : []),
      core = paper?.core_project_ids || [];
    const choices = state.projects.map(project => {
      const id = enc(project.id), link = paper?.project_links?.[project.id] || {};
      return el("div", {"data-paper-project": true},
        el("div", {class: "project-choice"},
          el("label", {class: "check"},
            el("input",
              {type: "checkbox", name: "project_ids", value: project.id, checked: selected.includes(project.id)}),
            project.name),
          el("label", {class: "check"},
            el("input",
              {type: "checkbox", name: "core_project_ids", value: project.id, checked: core.includes(project.id)}),
            copy("核心文献", "Core paper"))),
        el("details", {}, el("summary", {}, copy(`${project.name}的阅读安排`, `Reading plan for ${project.name}`)),
          el("fieldset", {disabled: !(selected.includes(project.id) || core.includes(project.id))},
            el("label", {class: "check"},
              el("input", {type: "checkbox", name: "pinned-" + id, checked: link.is_pinned}),
              local("sidebarPin", "置顶", "Pin")),
            el(
              "div", {class: "split"}, field(copy("排序序号", "Sort order"), input("order-" + id, link.sort_order, {
                type: "number",
                step: "1",
                min: "-9007199254740991",
                max: "9007199254740991",
                placeholder: "可留空，较小值优先"
              })),
              field(copy("文献文件夹", "Paper folder"),
                input("folder-" + id, link.folder_path, {maxlength: "512", placeholder: "例如：理论/散射"}))),
            field(copy("研究用途", "Research use"),
              input("purpose-" + id, link.use_for?.join(", "), {placeholder: "例如：比较方法，核对推导"})))));
    });
    return el("fieldset", {class: "file-drop"}, el("legend", {}, copy("收录到项目", "Add to projects")),
      el("div", {class: "project-choices"}, choices));
  }

  function paperImportError(error) {
    if (error.code === "invalid_paper_identifier") return copy(
      "请输入文章网址、PDF 链接、DOI、arXiv 编号或 INSPIRE 链接。",
      "Enter an article URL, PDF link, DOI, arXiv ID or INSPIRE link.");
    if (error.code === "invalid_paper_pdf") return copy("请选择有效的 PDF 文件。", "Choose a valid PDF file.");
    return error.message;
  }

  function paperImportSources() {
    return el("div", {class: "paper-import-sources"},
      field(local("paperImportLink", "文献链接或标识符", "Paper link or identifier"),
        area("identifiers", "",
          {rows: "2", "aria-describedby": "paper-link-help", placeholder: "https://… / DOI / arXiv"})),
      el("p", {class: "form-help", id: "paper-link-help"},
        copy("可粘贴文章网址、PDF 链接、DOI、arXiv 编号或 INSPIRE 链接。批量导入时每行一个。",
          "Paste an article URL, PDF link, DOI, arXiv ID or INSPIRE link. For a batch, use one per line.")),
      el("div", {class: "paper-import-or", "aria-hidden": "true"}, copy("或", "or")),
      el("div", {class: "file-drop paper-file-source"},
        field(local("paperImportFile", "本地 PDF", "Local PDF"), el("input", {
          type: "file",
          name: "pdf",
          accept: ".pdf,application/pdf",
          multiple: true,
          "aria-describedby": "paper-file-help"
        })),
        el("p", {class: "form-help", id: "paper-file-help"},
          copy("选择或拖入一份或多份 PDF。", "Choose or drop one or more PDFs.")),
        el("button", {type: "button", class: "bare", "data-clear-pdf": true, hidden: true},
          copy("清除文件选择", "Clear file selection"))),
      el("p", {class: "form-help", "data-paper-source-status": true, role: "status"}));
  }

  function setPaperFiles(form, files) {
    const input = form.elements.pdf;
    input.files = files;
    input.dispatchEvent(new Event("change", {bubbles: true}));
  }

  function paperForm(p = null, {files = null, focus = "identifiers"} = {}) {
    const edit = Boolean(p);
    const base = edit ? "papers/" + enc(p.id) : "papers";
    const originalValues = new Map();
    const bibliographicFields = fragment(field(copy("题名", "Title"), input("title", p?.title, {
      required: edit,
      maxlength: 1000,
      placeholder: copy("可从文件名或在线元数据获取", "Can be filled from the file or online metadata")
    })),
      el("div", {class: "split"}, field("DOI", input("doi", p?.doi, {placeholder: "10.…"})),
        field(copy("arXiv 编号", "arXiv ID"), input("arxiv", p?.arxiv, {placeholder: "2404.10066"}))),
      field(copy("原文链接", "Source URL"), input("url", p?.url, {type: "url", placeholder: "https://…"})));
    const readingFields = fragment(
      field(copy("作者", "Authors"),
        edit ? area("authors", p.authors?.join("\n"), {placeholder: copy("每行一位作者", "One author per line")}) :
               input("authors", "", {placeholder: copy("多位作者用逗号分隔", "Separate authors with commas")})),
      el("div", {class: "split"},
        field(copy("年份", "Year"), input("year", p?.year || "", {type: "number", min: "1", max: "9999"})),
        field(copy("阅读状态", "Reading status"),
          select("status",
            Object.entries({unread: statusLabel.unread, reading: statusLabel.reading, read: statusLabel.read}),
            p?.status || "unread"))),
      field(copy("标签", "Tags"),
        edit ? area("tags", p.tags?.join("\n"), {placeholder: copy("每行一个标签", "One tag per line")}) :
               input("tags", "", {placeholder: copy("用逗号分隔", "Separate tags with commas")})),
      E.library.collectionField(p), field(copy("摘要", "Abstract"), area("abstract", p?.abstract)));
    const editDetails = () =>
      fragment(el("details", {open: true},
                 el("summary", {}, copy("元数据与阅读状态", "Metadata and reading status")), readingFields,
                 el("div", {class: "split"},
                   field(copy("评分（0–5）", "Rating (0–5)"),
                     input("rating", p.rating || 0, {type: "number", min: "0", max: "5"})),
                   field(copy("优先级（0–5）", "Priority (0–5)"),
                     input("priority", p.priority || 0, {type: "number", min: "0", max: "5"}))),
                 field(copy("BibTeX 引用键", "BibTeX citation key"), input("citekey", p.citekey)),
                 field(copy("参考文献", "References"),
                   area("references", p.references?.join("\n"),
                     {placeholder: "每行一条，可填写引用文本、DOI、arXiv 编号或 BibTeX 引用键"}))),
        E.library.metadataFields(p), attachProjectBoxes(p, false),
        button(copy("引用文献", "Cite paper"), "show-citation", {id: p.id, kind: "bare"}),
        button(local("menuExportBibTeX", "导出 BibTeX", "Export BibTeX"), "export-paper-bibtex",
          {id: p.id, kind: "bare"}),
        p.project_ids?.includes(state.project?.id) ? button(copy("从当前项目移除", "Remove from Current Project"),
                                                       "confirm-paper-unlink", {id: p.id, kind: "bare danger"}) :
                                                     "");
    const importDetails = () => fragment(
      el("details", {class: "paper-import-settings"},
        el("summary", {},
          local("paperImportOptions", "导入选项", "Import options") +
            (state.project ? " · " + state.project.name : "")),
        el("label", {class: "check"}, el("input", {type: "checkbox", name: "lookup_metadata", checked: true}),
          copy("查询在线元数据", "Look up online metadata")),
        el("label", {class: "check"}, el("input", {type: "checkbox", name: "fetch_pdf"}),
          copy("同时下载在线 PDF", "Also download the online PDF")),
        el("label", {class: "check", hidden: true, "data-link-fallback": true},
          el("input", {type: "checkbox", name: "allow_link_only"}),
          copy("PDF 无法下载或阅读时仅保存链接", "Save the link if the PDF cannot be downloaded or read")),
        bibliographicFields, readingFields, attachProjectBoxes(null, true)),
      el("button", {type: "button", class: "button", "data-import-preview-button": true},
        copy("预览文献", "Preview paper")),
      el("p", {"data-import-preview": true, role: "status"}),
      el("ul", {"data-import-results": true, "aria-live": "polite"}));
    const title = local("paperImportTitle", "导入文献", "Import papers");
    dialog(edit ? copy("编辑文献", "Edit paper") : title,
      el("form", edit ? {"data-library-paper": p.id} : {"data-paper-intake": true},
        edit ? fragment(bibliographicFields, editDetails()) : fragment(paperImportSources(), importDetails()),
        formFooter(edit ? copy("保存更改", "Save changes") : title, edit ? "paper:" + p.id : "")),
      {wide: true});
    const completed = new Set();
    const outcomes = new Map();
    function changed(f, name) {
      const el = f.elements.namedItem(name);
      const previous = originalValues.get(name);
      return el?.type === "checkbox" ? el.checked !== previous : el?.value !== previous;
    }

    function paperBody(f) {
      const textList = edit ? E.library.lines : split;
      const body = {
        title: value(f, "title"),
        doi: value(f, "doi"),
        arxiv: value(f, "arxiv"),
        url: value(f, "url"),
        authors: textList(value(f, "authors")),
        tags: textList(value(f, "tags")),
        collection_id: value(f, "collection_id"),
        abstract: value(f, "abstract"),
        year: Number(value(f, "year")) || 0,
        status: value(f, "status"),
        project_ids: chosen(f, "project_ids"),
        core_project_ids: chosen(f, "core_project_ids")
      };
      if (edit) {
        // The form only offers active projects. Memberships outside this form
        // (for example, an archived project) cannot be changed by this edit.
        const visible = new Set([...f.querySelectorAll('input[name="project_ids"]')].map(input => input.value));
        for (const key of ["project_ids", "core_project_ids"]) {
          const hidden = (p[key] || []).filter(projectID => !visible.has(projectID));
          body[key] = [...new Set([...hidden, ...body[key]])];
        }
      }
      body.project_ids = [...new Set([...body.project_ids, ...body.core_project_ids])];
      const links = {};
      for (const project of state.projects) {
        if (!body.project_ids.includes(project.id)) continue;
        const id = enc(project.id);
        const order = value(f, "order-" + id);
        const link = {
          is_pinned: Boolean(f.elements.namedItem("pinned-" + id)?.checked),
          sort_order: order === "" ? null : Number(order),
          folder_path: value(f, "folder-" + id),
          use_for: split(value(f, "purpose-" + id))
        };
        if (edit) {
          const keys = {is_pinned: "pinned-", sort_order: "order-", folder_path: "folder-", use_for: "purpose-"};
          const patch = Object.fromEntries(Object.entries(link).filter(([key]) => changed(f, keys[key] + id)));
          if (Object.keys(patch).length) links[project.id] = patch;
        } else if (link.is_pinned || order !== "" || link.folder_path || link.use_for.length) {
          links[project.id] = link;
        }
      }
      if (Object.keys(links).length) body.project_links = links;
      return body;
    }

    function importIdentifiers(f) {
      const raw = value(f, "identifiers")
        .replace(/(^|[\s,;])(arxiv|doi|inspire)\s*:\s*/gi, "$1$2:")
        .replace(/(^|[\s,;])arxiv[ \t]+(?=\d{4}\.)/gi, "$1arXiv:");
      // A comma or semicolon inside a URL or DOI can be part of the identifier.
      const values = raw.split(/[,，;；]\s+|\s+|[,，;；](?=https?:\/\/|(?:arxiv|doi|inspire):|10\.\d{4,9}\/|\d{4}\.\d{4,5})/i);
      return [...new Set(values.filter(Boolean))];
    }

    const sourceConflict = () => copy("请清除文件选择或删除链接，再分别导入。", "Clear the file selection or remove the links, then import each source separately.");

    function importItems(f) {
      const files = [...(f.elements.pdf?.files || [])];
      const targets = importIdentifiers(f);
      if (files.length && targets.length) throw Error(sourceConflict());
      return files.length ? files : targets.length ? targets : [null];
    }

    function drawImportResults(f, items) {
      const batch = items.some(item => outcomes.has(item)) ? items.filter(Boolean) : [];
      f.querySelector("[data-import-results]").replaceChildren(...batch.map(item => {
        const entry = document.createElement("li");
        entry.textContent = (item.name || item) + " · " + (outcomes.get(item) || copy("等待导入", "Waiting to import"));
        return entry;
      }));
    }

    function importPayload(f, item, multiple) {
      const body = paperBody(f);
      const file = item && typeof item !== "string";
      if (!item && !body.title && !body.doi && !body.arxiv && !body.url) {
        throw Error(copy("请粘贴文献链接或标识符，或选择本地 PDF。", "Paste a paper link or identifier, or choose a local PDF."));
      }
      if (multiple) {
        for (const key of ["title", "doi", "arxiv", "url", "authors", "year", "abstract"]) delete body[key];
      }
      if (file) {
        const payload = new FormData();
        payload.append("file", item);
        payload.append("metadata", JSON.stringify(body));
        return payload;
      }
      if (typeof item === "string") {
        for (const key of ["doi", "arxiv", "url"]) delete body[key];
        body.identifier = item;
      }
      body.fetch_pdf = Boolean(f.elements.fetch_pdf?.checked);
      body.allow_link_only = body.fetch_pdf && Boolean(f.elements.allow_link_only?.checked);
      body.skip_metadata_lookup = !f.elements.namedItem("lookup_metadata")?.checked;
      return body;
    }

    const form = bindForm(async (f, token) => {
      const items = edit ? [] : importItems(f);
      if (items.length > 1) {
        const pending = items.filter(item => !completed.has(item));
        if (!pending.length) {
          done(token);
          return;
        }
        const identifiers = f.elements.namedItem("identifiers");
        const submissions = pending.map(item => [item, importPayload(f, item, true)]);
        f.elements.pdf.disabled = true;
        identifiers.disabled = true;
        try {
          for (const [item, payload] of submissions) {
            if (!f.closest("dialog")?.open || token !== formEpoch) break;
            outcomes.set(item, copy("正在导入", "Importing"));
            drawImportResults(f, items);
            try {
              const record = await request("papers", {method: "POST", body: payload});
              const warning = [record.import_warning, record.metadata_warning].filter(Boolean).join(" · ");
              outcomes.set(item, copy("已入库", "Imported") + " · " + record.title + (warning ? " · " + warning : ""));
              completed.add(item);
            } catch (err) {
              outcomes.set(item, paperImportError(err));
            }
            drawImportResults(f, items);
          }
        } finally {
          f.elements.pdf.disabled = false;
          identifiers.disabled = false;
        }
        const missing = items.length - completed.size;
        f.querySelector("[data-status]").textContent = copy("已入库", "Imported") + " " + completed.size + " / " + items.length;
        f.querySelector("[type=submit]").textContent = missing ?
          (typeof items[0] === "string" ? copy("重试未成功的标识符", "Retry failed links") : copy("重试未成功的文件", "Retry failed files")) :
          copy("完成", "Done");
        await refresh();
        return;
      }
      let record;
      if (edit) {
        const body = Object.assign(paperBody(f), {
          revision: p.revision,
          citekey: value(f, "citekey"),
          rating: Number(value(f, "rating")),
          priority: Number(value(f, "priority")),
          references: value(f, "references").split(/\r?\n/).map(line => line.trim()).filter(Boolean),
          ...E.library.metadataPayload(f)
        });
        const readingChoicesChanged = name =>
          [...f.querySelectorAll('input[name="' + name + '"]')].some(option => option.checked !== option.defaultChecked);
        const membershipChanged = readingChoicesChanged("project_ids") || readingChoicesChanged("core_project_ids");
        for (const key of Object.keys(body)) {
          if (key === "revision" || key === "project_links") continue;
          const membership = key === "project_ids" || key === "core_project_ids";
          if (!(membership ? membershipChanged : changed(f, key))) delete body[key];
        }
        if (Object.keys(body).length === 1) {
          done(token);
          return;
        }
        record = await E.library.saveMetadata(base, p, body);
      } else {
        try {
          record = await request(base, {method: "POST", body: importPayload(f, items[0], false)});
        } catch (error) {
          throw Error(paperImportError(error));
        }
      }
      done(token);
      await refresh();
      const warning = [record?.import_warning, record?.metadata_warning].filter(Boolean).join(" · ");
      toast(warning ? copy("文献已导入", "Paper imported") + " · " + warning :
        edit ? copy("文献已更新", "Paper updated") : copy("文献已导入", "Paper imported"));
    });
    if (edit) {
      for (const el of form.elements) {
        if (el.name) originalValues.set(el.name, el.type === "checkbox" ? el.checked : el.value);
      }
    } else {
      const identifiers = form.elements.namedItem("identifiers");
      const preview = form.querySelector("[data-import-preview]");
      const previewButton = form.querySelector("[data-import-preview-button]");
      const clearFiles = form.querySelector("[data-clear-pdf]");
      const sourceStatus = form.querySelector("[data-paper-source-status]");
      let previewEpoch = 0;
      function resetPreview() {
        previewEpoch++;
        preview.textContent = "";
      }
      function syncInputs() {
        const files = form.elements.pdf.files.length;
        const targets = importIdentifiers(form).length;
        for (const name of ["title", "doi", "arxiv", "url", "authors", "year", "abstract"]) {
          form.elements.namedItem(name).disabled = files > 1 || targets > 1 ||
            (targets > 0 && ["doi", "arxiv", "url"].includes(name));
        }
        form.elements.fetch_pdf.disabled = files > 0;
        form.elements.namedItem("lookup_metadata").disabled = files > 0;
        form.querySelector("[data-link-fallback]").hidden = files > 0 || !form.elements.fetch_pdf.checked;
        clearFiles.hidden = !files;
        sourceStatus.textContent = files && targets ? sourceConflict() : "";
        previewButton.textContent = Math.max(files, targets) > 1 ? copy("预览首篇文献", "Preview first paper") :
          copy("预览文献", "Preview paper");
      }
      function resetBatch() {
        let items = [];
        try {
          items = importItems(form);
        } catch {}
        for (const item of outcomes.keys()) {
          if (!items.includes(item)) {
            completed.delete(item);
            outcomes.delete(item);
          }
        }
        drawImportResults(form, items);
        form.querySelector("[data-error]").textContent = "";
        form.querySelector("[data-status]").textContent = "";
        form.querySelector("[type=submit]").textContent = title;
        resetPreview();
        syncInputs();
      }
      form.elements.pdf.addEventListener("change", resetBatch);
      clearFiles.addEventListener?.("click", () => {
        if (form.dataset.pending) return;
        form.elements.pdf.value = "";
        resetBatch();
        form.elements.pdf.focus();
      });
      identifiers.addEventListener("input", resetBatch);
      form.elements.fetch_pdf.addEventListener("change", syncInputs);
      form.addEventListener("change", resetPreview);
      form.addEventListener("input", resetPreview);
      previewButton.addEventListener?.("click", async () => {
        if (form.dataset.pending || !form.reportValidity()) return;
        const epoch = ++previewEpoch;
        preview.textContent = copy("正在预览…", "Preparing preview…");
        previewButton.disabled = true;
        try {
          const items = importItems(form);
          const body = importPayload(form, items[0], items.length > 1);
          const data = await request("papers/preview", {method: "POST", body});
          if (epoch !== previewEpoch) return;
          preview.textContent = [
            data.title, data.authors?.join(", "), data.year, data.metadata_source,
            data.doi, data.arxiv, data.inspire_id && "INSPIRE " + data.inspire_id, data.url,
            data.existing_title && copy("复用文献库中的《" + data.existing_title + "》", "Reuse library paper “" + data.existing_title + "”"),
            items.length > 1 && copy("已选 " + items.length + " 篇，预览首篇", "Preview of the first of " + items.length + " papers"),
            data.metadata_warning
          ].filter(Boolean).join(" · ");
        } catch (err) {
          if (epoch === previewEpoch) preview.textContent = paperImportError(err);
        } finally {
          previewButton.disabled = false;
        }
      });
      form.addEventListener("invalid", event => {
        const settings = event.target.closest(".paper-import-settings");
        if (settings) settings.open = true;
      }, true);
      if (files?.length) setPaperFiles(form, files);
      else syncInputs();
      form.elements.namedItem(focus)?.focus?.();
    }
    form.addEventListener("change", event => {
      if (!["project_ids", "core_project_ids"].includes(event.target.name)) return;
      const group = event.target.closest("[data-paper-project]");
      group.querySelector("fieldset").disabled = !group.querySelector('.project-choice input:checked');
    });
  }

  function paperDropTarget(event) {
    if (!Array.from(event.dataTransfer?.types || []).includes("Files")) return null;
    return event.target.closest?.("[data-paper-intake]") ||
      (state.view === "papers" && !$("modal").open ? event.target.closest?.("#main") : null);
  }

  document.addEventListener("dragover", event => {
    const target = paperDropTarget(event);
    if (!target) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = target.dataset.pending ? "none" : "copy";
    if (!target.dataset.pending) target.dataset.paperDragging = "";
  });
  document.addEventListener("dragleave", event => {
    const target = event.target.closest?.("[data-paper-dragging]");
    if (target && !target.contains(event.relatedTarget)) delete target.dataset.paperDragging;
  });
  document.addEventListener("drop", event => {
    const target = paperDropTarget(event);
    if (!target) return;
    event.preventDefault();
    delete target.dataset.paperDragging;
    const files = event.dataTransfer.files;
    if (!files.length || target.dataset.pending) return;
    if (target.matches("[data-paper-intake]")) setPaperFiles(target, files);
    else paperForm(null, {files, focus: "pdf"});
  });

  function wikiPath(n) {
    return [n.namespace, n.title].filter(Boolean).join("/");
  }

  function splitWikiBody(source) {
    const lines = String(source || "").split(/\r\n|\r|\n/);
    if (lines[0]?.replace(/^\uFEFF/, "") === "---") {
      const last = lines.findIndex((line, index) => index > 0 && /^(---|\.\.\.)[ \t]*$/.test(line));
      if (last > 0) return {frontmatter: lines.slice(1, last).join("\n"), body: lines.slice(last + 1).join("\n")};
    }
    return {frontmatter: "", body: source};
  }

  function wikiPaperStatus(note) {
    if (!note?.paperId) return "";
    if (note.paperStatus) return note.paperStatus;
    const paper = state.papers.find(p => p.id === note.paperId);
    if (!paper) return "missing";
    return paper.project_ids?.includes(note.projectId) ? "available" : "outside_project";
  }

  function wikiPaperSelect(note) {
    const id = note?.paperId || "";
    const status = wikiPaperStatus(note);
    const items = [["", copy("无关联论文", "No linked paper")], ...state.papers.filter(p => p.id !== id || status !== "missing").map(p => [p.id, p.title])];
    if (id && !items.some(([value]) => value === id)) items.push([id, copy("已保留的来源论文", "Retained source paper")]);
    return select("paperId", items, id, "", note?.template === "paper");
  }

  function wikiPaperNotice(note) {
    const status = wikiPaperStatus(note);
    if (status === "missing")
      return el("p", {"data-wiki-paper-status": "missing"},
        el("strong", {},
          copy("共享文献库中已找不到来源论文。", "The source paper is missing from the shared library.")),
        " ",
        copy("Wiki 仍可编辑，原论文 ID 已保留。",
          "This Wiki page remains editable and retains the original paper ID."),
        " ", el("code", {}, note.paperId));
    if (status === "outside_project")
      return el("p", {"data-wiki-paper-status": "outside_project"},
        copy("来源论文仍在共享文献库，当前项目未关联此论文。",
          "The source paper remains in the shared library and is outside this project."));
    return "";
  }

  function noteForm(n = null, moving = false, folder = "") {
    const base = projectPath("notes" + (n ? "/" + enc(n.id) : ""), n?.projectId);
    const namespace = fragment(
      field("目录",
        input("namespace", n?.namespace ?? folder,
          {list: "wiki-folder-suggestions", maxlength: "500", placeholder: "例如：concept 或 methods/statistics"})),
      el("datalist", {id: "wiki-folder-suggestions"}, state.wikiFolders.map(path => el("option", {value: path}))));
    let f, current = n, saved = false, original;
    const snapshot = () => JSON.stringify([...new FormData(f).entries()]);
    const dirty = () => f && !saved && !f.dataset.pending && snapshot() !== original;
    const beforeUnload = event => {
      if (!dirty()) return;
      event.preventDefault();
      event.returnValue = true;
    };
    const command = event => {
      if (event.detail !== "save") return;
      event.preventDefault();
      f.requestSubmit();
    };
    dialog(moving ? "移动 Wiki 页面" :
        n         ? "编辑 Wiki 页面" :
                    "新建 Wiki 页面",
      el("form", {class: "note-edit"},
        el("fieldset", {class: "wiki-fields"},
          moving ?
            fragment(el("p", {class: "form-help"}, wikiPath(n)), namespace) :
            fragment(el("div", {class: "split"},
                       field("标题", input("title", n?.title, {required: true, maxlength: "240", autofocus: true})),
                       namespace),
              el("details", {class: "wiki-page-properties"},
                el("summary", {}, E.local?.("wikiPageProperties", "页面属性", "Page properties") ?? "页面属性"),
                field("别名",
                  area("aliases", n?.aliases?.join("\n"),
                    {"aria-label": "别名", rows: "2", placeholder: "每行一个。可用目录/名称指定完整路径。"})),
                el("div", {class: "split"}, field("关联论文", wikiPaperSelect(n)),
                  field("标签", input("tags", n?.tags?.join(", "), {placeholder: "用逗号分隔"})))),
              wikiPaperNotice(n),
              el("div", {class: "note-tools"}, el("strong", {}, "Markdown 正文"),
                el("button", {type: "button", class: "bare", id: "preview-toggle"}, "预览")),
              wikiFormatTools(), field("内容", area("body", n?.body, {
                "aria-label": "内容",
                id: "note-body",
                placeholder: "支持 Markdown、数学公式和 [[concept:页面|显示文字]]"
              })),
              el("div", {id: "draft-preview", class: "note-preview", hidden: true}))),
        el("div", {"data-wiki-conflict": true, hidden: true}), formFooter(moving ? "移动页面" : "保存页面")),
      {
        wide: !moving,
        canDismiss: () => !f?.dataset.pending && (!dirty() || window.confirm("放弃当前尚未保存的 Wiki 草稿？")),
        cleanup: () => {
          window.removeEventListener("beforeunload", beforeUnload);
          window.removeEventListener("scistation:command", command);
        }
      });
    if (!moving) $("preview-toggle").onclick = () => {
      const preview = $("draft-preview"), edit = $("note-body").parentElement;
      const open = preview.hidden;
      preview.hidden = !open;
      edit.hidden = open;
      $("wiki-format-tools").hidden = open;
      $("preview-toggle").textContent = open ? "返回编辑" : "预览";
      if (open) {
        renderWikiMarkdown(preview, splitWikiBody($("note-body").value).body);
      }
    };
    f = bindForm(async (form, token) => {
      const body = {namespace: value(form, "namespace")};
      if (!moving) {
        Object.assign(body, {
          title: value(form, "title"),
          body: form.elements.body.value || (n ? "" : "# " + value(form, "title") + "\n"),
          tags: split(value(form, "tags")),
          aliases: value(form, "aliases").split(/\r?\n/).map(s => s.trim()).filter(Boolean)
        });
        const paperId = value(form, "paperId");
        if (n?.template !== "paper" && paperId !== (n?.paperId || "")) body.paperId = paperId;
      }
      if (current) body.revision = current.revision;
      const controls = form.querySelector("fieldset");
      const conflict = form.querySelector("[data-wiki-conflict]");
      controls.disabled = true;
      conflict.hidden = true;
      try {
        await request(base, {method: current ? "PATCH" : "POST", body});
        saved = true;
      } catch (err) {
        if (err.status === 409 && current) {
          try {
            const latest = await request(base);
            if (latest.revision !== current.revision) {
              showNoteConflict(conflict, latest, () => { current = latest; });
            }
          } catch { /* The save error still explains the conflict. */ }
        }
        throw err;
      } finally {
        controls.disabled = false;
      }
      delete form.dataset.pending;
      done(token);
      await refresh();
      toast(moving ? "页面已移动" : "页面已保存");
    });
    original = snapshot();
    window.addEventListener("beforeunload", beforeUnload);
    window.addEventListener("scistation:command", command);
    if (!moving) bindWikiFormatTools(f);
  }

  function wikiFormatTools() {
    return el("div",
      {class: "actions wiki-format-tools", id: "wiki-format-tools", role: "group", "aria-label": "Markdown 格式"},
      Object.entries(wikiEditor.formats).map(([key,
        [label]]) => el("button", {type: "button", class: "button", "data-format": key}, label)),
      el("button", {type: "button", class: "button", id: "wiki-add-frontmatter"}, "添加 YAML 元数据"),
      el("select", {id: "wiki-snippets", "aria-label": "插入 Markdown 片段", disabled: true},
        el("option", {value: ""}, "Markdown 片段")),
      el("span", {id: "wiki-snippet-status", role: "status"}));
  }

  async function bindWikiFormatTools(form) {
    const source = form.elements.body, tools = $("wiki-format-tools"), snippets = $("wiki-snippets"),
      status = $("wiki-snippet-status");
    const apply = result => {
      if (!result) return;
      source.value = result.value;
      source.focus();
      source.setSelectionRange(result.caret, result.caret);
    };
    const addMetadata = $("wiki-add-frontmatter");
    const updateMetadataAction = () => { addMetadata.disabled = source.value.trimStart().startsWith("---"); };
    updateMetadataAction();
    tools.addEventListener("click", event => {
      const key = event.target.dataset.format;
      if (key) apply(wikiEditor.format(source.value, source.selectionStart, source.selectionEnd, key));
      else if (event.target === addMetadata) {
        const title = value(form, "title") || "Untitled";
        const frontmatter = "---\ntitle: " + JSON.stringify(title) + "\ntags: []\n---\n\n";
        apply(wikiEditor.insert(source.value, 0, 0, frontmatter));
        updateMetadataAction();
      }
    });
    let available = [];
    source.addEventListener("input", event => {
      if (!event.isComposing && event.inputType === "insertText" && source.selectionStart === source.selectionEnd) {
        apply(wikiEditor.expand(source.value, source.selectionStart, available));
      }
      updateMetadataAction();
    });
    snippets.onchange = () => {
      const selected = available.find(item => item.trigger === snippets.value);
      if (selected) apply(wikiEditor.insert(source.value, source.selectionStart, source.selectionEnd, selected.body));
      snippets.value = "";
      updateMetadataAction();
    };
    try {
      const settings = await request("wiki/snippets");
      if (!tools.isConnected) return;
      available = settings.snippets || [];
      appendSnippetOptions(snippets, available);
      snippets.disabled = available.length === 0;
      if (settings.parseError) status.textContent = "自定义设置有误，已加载内置片段";
    } catch (err) {
      if (tools.isConnected) status.textContent = "无法加载片段";
    }
  }

  function showNoteConflict(host, latest, useRevision) {
    renderNoteConflict(host, latest, wikiPath(latest), useRevision);
  }

  function reviewedEvidence(entries, owner) {
    if (!entries?.length) return "";
    return el("section", {class: "task-evidence"}, el("h3", {}, "原文证据"), entries.map(e => {
      const href = window.SciEvidence.href(owner, e);
      const citation = href ? link(window.SciEvidence.label(e), href, "bare") : "";
      const meeting = e.meetingId ? link("来源会议", "/studio?project=" + enc(e.source?.projectId ?? owner) +
        "&session=" + enc(e.meetingId), "bare") : "";
      return fragment(el("blockquote", {}, e.quote), el("div", {class: "actions"}, citation, meeting));
    }));
  }

  function projectSourceExcerpt(owner, kind, id, locator) {
    return request(projectPath("source-excerpts/" + kind + "/" + enc(id), owner) + "?" + window.SciEvidence.query(locator));
  }

  function sourceExcerptView(excerpt) {
    return el("section", {class: "wiki-occurrence", "aria-label": "引用所在原文"},
      el("p", {class: "form-help"}, "第 ", excerpt.line, " 行 · 第 ", excerpt.column, " 列"),
      el("pre", {}, excerpt.before, el("mark", {}, excerpt.quote), excerpt.after));
  }

  function noteOccurrence(n, locator) {
    if (!locator?.line) return "";
    if (locator.revision && locator.revision !== n.revision) {
      return el("p", {class: "form-help", role: "status"}, "页面已在图谱读取后更新。刷新图谱后可重新定位原文。");
    }
    const excerpt = n.body.split(/\r\n|\r|\n/)[locator.line - 1];
    if (excerpt === undefined) return "";
    const glyphs = Array.from(excerpt), start = Math.max(0, locator.column - 1 || 0);
    const count = Array.from(locator.text || "").length;
    const at = glyphs.slice(start, start + count).join("");
    const source = count && at === locator.text ?
      fragment(glyphs.slice(0, start).join(""), el("mark", {}, at), glyphs.slice(start + count).join("")) :
      excerpt;
    return el("section", {class: "wiki-occurrence", "aria-label": "引用所在原文"},
      el("p", {class: "form-help"}, "第 ", locator.line, " 行 · 第 ", start + 1, " 列"), el("pre", {}, source));
  }

  let wikiRequest = 0, selectedWikiNote = null;
  E.openWikiNote = async function (id, locator) {
    const owner = state.project?.id;
    const isCurrent = E.currentView();
    if (!owner || !id || !isCurrent()) return;
    const token = ++wikiRequest;
    const base = projectPath("notes/" + enc(id), owner);
    const excerpt = locator?.citation ? await projectSourceExcerpt(owner, "note", id, locator.citation) : null;
    const n = await request(base);
    if (token !== wikiRequest || !isCurrent() || state.project?.id !== owner) return;
    if (excerpt && excerpt.revision !== n.revision) throw Error("Wiki 页面已更新，请重新打开引用。");
    selectedWikiNote = n;
    window.SciContextRail?.selectObject("note", n.id);
    const {frontmatter, body} = splitWikiBody(n.body);
    const noteURL = E.wikiURL(n.id, owner);
    const paperStatus = wikiPaperStatus(n);
    const paperLink = n.paperId && paperStatus !== "missing" ? link("关联论文",
      reader(n.paperId, paperStatus === "outside_project" ? null : owner), "button", "book") : "";
    dialog(n.title,
      fragment(n.namespace ? el("p", {class: "form-help"}, wikiPath(n)) : "",
        el("div", {class: "actions"},
          button("编辑页面", "edit-note", {id: n.id, kind: "button primary", glyph: "file"}),
          button("移动页面", "move-note", {id: n.id}),
          button("归档页面", "confirm-delete", {id: "note:" + n.id, kind: "button"}),
          link("页面链接", noteURL, "button"),
          link("导出 Markdown", "/api/research/" + base + "/markdown", "button", "import"),
          n.sourceMeetingId ?
            link("来源会议", "/studio?project=" + enc(owner) + "&session=" + enc(n.sourceMeetingId), "button",
              "chat") :
            "",
          paperLink),
        wikiPaperNotice(n), excerpt ? sourceExcerptView(excerpt) : noteOccurrence(n, locator),
        frontmatter ? el("details", {class: "wiki-frontmatter"}, el("summary", {}, "Markdown 元数据"),
                        el("div", {id: "wiki-metadata", "aria-live": "polite"}),
                        el("details", {}, el("summary", {}, "原始 YAML"), el("pre", {}, frontmatter))) :
                      "",
        el("article", {class: "note-preview", id: "note-preview"}),
        el("p", {class: "form-help", id: "wiki-link-status", role: "status"}), reviewedEvidence(n.evidence, owner),
        el("div", {id: "backlinks"})),
      {wide: true});
    const preview = $("note-preview"), backlinks = $("backlinks"), status = $("wiki-link-status");
    renderWikiMarkdown(preview, body);
    const revision = "?revision=" + enc(n.revision);
    if (frontmatter) showWikiMetadata(base + "/frontmatter" + revision, $("wiki-metadata"));
    const [links, refs] = await Promise.allSettled([
      request(base + "/links" + revision), request(base + "/backlinks" + revision)
    ]);
    if (token !== wikiRequest || state.project?.id !== owner || !preview.isConnected) return;
    if (links.status === "fulfilled") {
      renderWikiMarkdown(preview, body, links.value);
    } else status.textContent = "页面链接读取失败：" + links.reason.message;
    if (refs.status === "fulfilled") {
      if (refs.value?.length) renderBacklinks(backlinks, refs.value, wikiPath);
    } else backlinks.textContent = "反向链接读取失败：" + refs.reason.message;
  };

  async function showWikiMetadata(path, host) {
    try {
      const entries = await request(path);
      renderWikiMetadata(host, entries);
    } catch (err) {
      if (host.isConnected) host.textContent = err.message;
    }
  }

  async function archivedNotes() {
    const owner = state.project.id;
    const notes = await request(projectPath("notes", owner) + "?archived=1");
    if (state.project?.id !== owner) return;
    dialog("已归档 Wiki 页面",
      notes.length ?
        notes.map(
          n => el("div", {class: "row"}, el("span", {class: "row-main"}, wikiPath(n)),
            link("导出 Markdown",
              "/api/research/" + projectPath("notes/" + enc(n.id) + "/markdown", owner) + "?archived=1", "button"),
            button("恢复", "restore-note", {id: n.id + ":" + n.revision}))) :
        empty("暂无已归档页面"));
  }

  function taskEvidence(t) {
    return reviewedEvidence(t?.evidence, t?.projectId);
  }

  function wikiFolderForm() {
    const owner = state.project.id;
    dialog("新建 Wiki 目录",
      el("form", {},
        field("目录路径",
          input("path", "",
            {required: true, autofocus: true, maxlength: "500", placeholder: "例如：methods/statistics"})),
        formFooter("创建目录")));
    bindForm(async (f, token) => {
      await request(projectPath("wiki/folders", owner), {
        method: "POST", body: {path: value(f, "path")}
      });
      done(token);
      await refresh();
      toast("Wiki 目录已创建");
    });
  }

  function readWikiFolder(path) {
    const records = state.notes.filter(n => n.namespace?.toLowerCase() === path.toLowerCase());
    const children = state.wikiFolders.filter(folder => folder.toLowerCase().startsWith(path.toLowerCase() + "/") &&
      !folder.slice(path.length + 1).includes("/"));
    dialog(path,
      fragment(el("div", {class: "actions"}, button("在此目录新建页面", "new-note", {id: path, glyph: "plus"})),
        children.length ? fragment(el("div", {class: "subheading"}, "子目录"),
                            el("div", {class: "list"},
                              children.map(folder => button(folder, "read-wiki-folder",
                                             {id: folder, kind: "search-result", glyph: "folder"})))) :
                          "",
        records.length ?
          fragment(el("div", {class: "subheading"}, "页面"),
            el("div", {class: "list"},
              records.map(n => button(n.title, "read-note", {id: n.id, kind: "search-result", glyph: "file"})))) :
          empty("此目录没有页面")));
  }

  function paperWikiForm(selected = "") {
    const owner = state.project.id, papers = state.papers;
    if (!papers.length) {
      dialog("从论文创建 Wiki 页面", empty("请选择要关联的论文", "先将论文加入共享文献库。", button("导入论文", "new-paper")));
      return;
    }
    let form;
    dialog("从论文创建 Wiki 页面",
      el("form", {},
        field("论文",
          el("select", {name: "sourcePaper", "aria-label": "论文", required: true},
            el("option", {value: ""}, "选择论文"), papers.map(p => option(p.id, p.title, selected)))),
        formFooter("创建论文页面")),
      {canDismiss: () => !form?.dataset.pending});
    form = bindForm(async (f, token) => {
      const p = papers.find(p => p.id === value(f, "sourcePaper"));
      if (!p) throw Error("请选择要关联的论文");
      const n = await request(projectPath("notes/paper-template", owner), {
        method: "POST", body: {paperId: p.id, revision: p.revision}
      });
      await refresh();
      if (token === formEpoch && state.project?.id === owner && f.isConnected) await E.openWikiNote(n.id);
      toast("论文页面已创建");
    });
  }

  async function wikiSnippetSettings() {
    const endpoint = "wiki/snippets";
    const initial = await request(endpoint);
    let f, current = initial, saved = false;
    const dirty = () => f && !saved && f.elements.snippetYAML.value !== initial.content;
    const beforeUnload = event => {
      if (dirty()) {
        event.preventDefault();
        event.returnValue = true;
      }
    };
    const command = event => {
      if (event.detail !== "save") return;
      event.preventDefault();
      f.requestSubmit();
    };
    dialog("Markdown 片段",
      el("form", {class: "note-edit"},
        el("p", {class: "form-help"}, "片段在此科研工作区的项目中通用。YAML 条目包含 trigger、title 和 body。"),
        initial.parseError ? el("p", {role: "alert", class: "error"}, initial.parseError) : "",
        field("片段 YAML", area("snippetYAML", initial.content, {"aria-label": "片段 YAML", spellcheck: "false"})),
        el("div", {"data-wiki-conflict": true, hidden: true}), formFooter("保存片段")),
      {
        wide: true,
        canDismiss: () => !f?.dataset.pending && (!dirty() || window.confirm("放弃尚未保存的 Markdown 片段更改？")),
        cleanup: () => {
          window.removeEventListener("beforeunload", beforeUnload);
          window.removeEventListener("scistation:command", command);
        }
      });
    f = bindForm(async (form, token) => {
      const conflict = form.querySelector("[data-wiki-conflict]");
      const source = form.elements.snippetYAML;
      conflict.hidden = true;
      source.readOnly = true;
      try {
        await request(endpoint, {
          method: "PUT", body: {content: source.value, revision: current.revision}
        });
        saved = true;
      } catch (err) {
        if (err.status === 409) {
          try {
            const latest = await request(endpoint);
            renderSnippetConflict(conflict, latest.content, () => {
              current = latest;
            });
          } catch { /* Preserve the draft even if the newer snippet file cannot be loaded. */ }
        }
        throw err;
      } finally {
        source.readOnly = false;
      }
      delete form.dataset.pending;
      done(token);
      toast("Markdown 片段已保存");
    });
    window.addEventListener("beforeunload", beforeUnload);
    window.addEventListener("scistation:command", command);
  }

  async function openTaskForm(task) {
    if (!state.taskCatalog) {
      const {project, view} = state;
      const catalog = await request("task-tags");
      if (state.project !== project || state.view !== view) return;
      state.taskCatalog = catalog;
    }
    if (task) window.SciContextRail?.selectObject("task", task.id);
    taskForm(task);
  }

  async function manageTaskTags() {
    const catalog = await request("task-tags");
    if (state.view !== "tasks") return;
    state.taskCatalog = catalog;
    render();
    showTaskTagEditor();
  }

  function showTaskTagEditor(name = "", message = "") {
    const catalog = state.taskCatalog;
    const tag = catalog.tags.find(tag => tag.name === name);
    const colors = tag ? E.taskTagColors(name, tag.definition) : {color: "#E76F51", textColor: "#1F2937"};
    const choices = catalog.tags.slice().sort((a, b) => a.name.localeCompare(b.name));
    let form;
    dialog(copy("管理任务标签", "Manage Task Tags"),
      el("form", {class: "task-tag-manager"},
        el("div", {class: "task-tag-layout"},
          el("div", {class: "task-tag-library"},
            el("button", {type: "button", class: "button", "data-new-task-tag": true}, copy("新建标签", "New tag")),
            choices.length ? el("ul", {class: "task-tag-directory"},
                               choices.map(item =>
                                             el("li", {},
                                               el(
                                                 "button", {
                                                   type: "button",
                                                   class: "button",
                                                   "data-task-tag-name": item.name,
                                                   "aria-pressed": String(item.name === name)
                                                 },
                                                 E.taskTagChip(item.name, item.definition))))) :
                             el("p", {class: "form-help"}, copy("还没有任务标签。", "No task tags yet."))),
          el("div", {},
            field(copy("标签名称", "Tag name"),
              input("tagName", name, {required: true, maxlength: 80, readonly: Boolean(tag), autofocus: !tag})),
            el("div", {class: "split"},
              field(copy("背景色", "Background color"), input("color", colors.color, {type: "color"})),
              field(copy("文字色", "Text color"), input("textColor", colors.textColor, {type: "color"}))),
            el("div", {class: "task-tag-preview", "data-task-tag-preview": true}),
            tag?.inUse && tag.definition ?
              el("p", {class: "form-help"},
                copy("删除自定义标签后，已关联的任务仍保留此标签，并恢复默认颜色。",
                  "Tasks keep this tag in its default colors when you delete its custom definition.")) :
              "")),
        formStatus(),
        el("div", {class: "form-foot"},
          el("button", {type: "submit", value: "set", class: "button primary"}, copy("保存标签", "Save tag")),
          tag?.definition ? el("button", {type: "submit", value: "delete", class: "bare danger"},
                              copy("删除自定义标签", "Delete custom tag")) :
                            "")),
      {wide: true, canDismiss: () => !form?.dataset.pending});
    form = bindForm(async (f, _, submit) => {
      const operation = submit.value === "delete" ? "delete" : "set";
      const tagName = value(f, "tagName");
      const saved = await request("task-tags", {
        method: "PATCH",
        body: {revision: catalog.revision, operation, name: tagName, color: value(f, "color"), textColor: value(f, "textColor")}
      });
      state.taskCatalog = saved;
      const exists = saved.tags.some(tag => tag.name === tagName);
      if (!exists && state.taskTag === tagName) state.taskTag = "";
      render();
      showTaskTagEditor(exists ? tagName : "", operation === "delete" ?
        copy("已删除自定义标签。", "Custom tag deleted.") : copy("标签已保存。", "Task tag saved."));
    });
    form.querySelector("[data-status]").textContent = message;
    const showPreview = () => {
      const title = value(form, "tagName") || copy("预览", "Preview");
      const colors = E.taskTagColors(title, {color: value(form, "color"), textColor: value(form, "textColor")});
      renderTaskTagChip(form.querySelector("[data-task-tag-preview]"), title, colors);
    };
    showPreview();
    form.addEventListener("input", showPreview);
    form.addEventListener("click", e => {
      const edit = e.target.closest("[data-task-tag-name], [data-new-task-tag]");
      if (!edit || form.dataset.pending) return;
      showTaskTagEditor(edit.dataset.taskTagName || "");
    });
    if (tag) form.elements.namedItem("color").focus();
    else form.elements.namedItem("tagName").focus();
  }

  function taskForm(t = null) {
    const pid = state.project?.id;
    const member = t ? t.projectId : pid;
    const members = t?.projectIds || (member ? [member] : []);
    const hiddenMembers = members.filter(id => !state.projects.some(project => project.id === id));
    const paperIds = t?.relatedPaperIds || (t?.paperId ? [t.paperId] : []);
    const multi = (label, name, choices, selected) =>
      el("fieldset", {class: "task-picker"}, el("legend", {}, label),
        el("div", {class: "task-options"},
          choices.map(
            ([id, title]) => el("label", {},
              el("input", {type: "checkbox", name, value: id, checked: selected.includes(id)}), " ", title))));
    const papers = state.papers.map(p => [p.id, p.title]);
    const assignedTags = t?.tags || [];
    const definitions = new Map(state.taskCatalog?.tags.map(tag => [tag.name, tag.definition]));
    const tagChoices =
      E.taskTagNames(assignedTags)
        .map(name => el("label", {},
               el("input",
                 {type: "checkbox", name: "taskTagNames", value: name, checked: assignedTags.includes(name)}),
               " ", E.taskTagChip(name, definitions.get(name))));
    dialog(t ? "编辑任务" : "添加任务",
      el("form", {}, field("任务", input("title", t?.title, {required: true, autofocus: true, maxlength: "240"})),
        el("div", {class: "split"},
          field("类型", select("kind", [["general", "普通任务"], ["reading", "论文阅读"]], t?.kind || "general")),
          field("优先级", select("priority", Object.entries(E.taskPriorityLabels), t?.priority || "medium"))),
        field("状态",
          select("status", ["open", "inProgress", "done", "cancelled"].map(id => [id, statusLabel[id]]),
            t?.status || "open")),
        el("div", {class: "split"}, field("开始日期", input("startDate", t?.startDate, {type: "date"})),
          field("截止日期", input("dueDate", t?.dueDate, {type: "date"}))),
        field("截止时间", input("dueTime", t?.dueTime, {type: "time"})),
        state.projects.length ?
          multi("关联项目（可选）", "projectIds", state.projects.map(p => [p.id, p.name]), members) :
          "",
        papers.length ? multi("关联论文", "relatedPaperIds", papers, paperIds) : "",
        tagChoices.length ? el("fieldset", {class: "task-picker"}, el("legend", {}, copy("任务标签", "Task tags")),
                              el("div", {class: "task-options"}, tagChoices)) :
                            "",
        field(copy("添加标签", "Add tags"),
          input("tags", "", {placeholder: copy("用逗号分隔", "Separate with commas")})),
        field("说明", area("description", t?.description)), taskEvidence(t),
        formFooter("保存任务", t ? "task:" + t.id : "")),
      {wide: true});
    bindForm(async (f, token) => {
      const body = {};
      for (const key of ["title", "kind", "priority", "status", "startDate", "dueDate", "dueTime", "description"]) {
        body[key] = value(f, key);
      }
      const chosenTags = chosen(f, "taskTagNames");
      const tags = [...new Set([...assignedTags.filter(name => chosenTags.includes(name)), ...chosenTags, ...split(value(f, "tags"))])];
      if (!t || tags.length !== assignedTags.length || tags.some((name, index) => name !== assignedTags[index])) {
        body.tags = tags;
      }
      const projects = chosen(f, "projectIds");
      body.projectIds = projects.length ? [...projects, ...hiddenMembers] : [];
      const routeProject = t ? (t.projectId || pid) : (projects.includes(pid) ? pid : projects[0]);
      // Keep links to papers that are absent from the current library snapshot
      // when editing an unrelated field. Send an explicit list if links changed.
      const visiblePaperIDs = paperIds.filter(id => papers.some(([paperID]) => id === paperID));
      const selectedPaperIDs = chosen(f, "relatedPaperIds");
      if (!t || visiblePaperIDs.length !== selectedPaperIDs.length || visiblePaperIDs.some(id => !selectedPaperIDs.includes(id))) {
        body.relatedPaperIds = selectedPaperIDs;
      }
      if (t) body.revision = t.revision;
      const saved = await request(E.taskPath(t?.id, routeProject), {
        method: t ? "PATCH" : "POST",
        body
      });
      done(token);
      await refresh();
      toast(saved?.reminderSyncWarning ? "任务已保存。提醒事项未同步：" + saved.reminderSyncWarning : "任务已保存");
    });
  }

  function materialForm(m = null) {
    const base = projectPath("materials" + (m ? "/" + enc(m.id) : ""));
    dialog(m ? "重命名材料" : "添加项目材料",
      el("form", {},
        m ? field("文件名", input("name", m.name, {required: true, autofocus: true})) :
            field("选择文件", el("input", {type: "file", name: "file", required: true})),
        formFooter(m ? "保存名称" : "添加文件", m ? "material:" + m.id : "")));
    bindForm(async (f, token) => {
      let body;
      if (m) body = {
        revision: m.revision,
        name: value(f, "name")
      };
      else {
        const file = f.elements.file.files[0];
        if (!file) throw Error("请选择文件");
        body = new FormData();
        body.append("file", file);
      }
      await request(base, {
        method: m ? "PATCH" : "POST",
        body
      });
      done(token);
      await refresh();
      toast("材料已保存");
    });
  }
  E.openMaterialEvidence = async function (id, citation) {
    const owner = state.project?.id;
    const isCurrent = E.currentView();
    if (!owner || !id || !isCurrent()) return;
    const excerpt = await projectSourceExcerpt(owner, "material", id, citation);
    const material = await request(projectPath("materials/" + enc(id), owner));
    if (!isCurrent() || state.project?.id !== owner) return;
    if (excerpt.revision !== material.revision) throw Error("材料已更新，请重新打开引用。");
    return readMaterial(material, excerpt);
  };

  async function readMaterial(m, excerpt = null) {
    const url = "/api/research/" + projectPath("materials/" + enc(m.id) + "/content");
    const img = /^image\/(png|jpeg|webp|gif)$/i.test(m.mediaType || "");
    const pdf = /^application\/pdf(?:;|$)/i.test(m.mediaType || "");
    const isText = /^text\/|json|yaml|xml|javascript/i.test(m.mediaType || "") ||
      /\.(txt|md|csv|py|tex|yml|yaml|json|tsv)$/i.test(m.name);
    dialog(m.name,
      fragment(el("div", {class: "actions"}, button("重命名或删除", "edit-material", {id: m.id}),
                 excerpt ? button("查看完整材料", "read-material", {id: m.id}) : "",
                 el("a", {class: "button", href: url, download: m.name}, "下载文件")),
        el("p", {class: "subheading"}, bytes(m.size), " · ", m.mediaType),
        excerpt ? sourceExcerptView(excerpt) : el("div", {id: "file-display"})),
      {wide: true});
    if (excerpt) return;
    const display = $("file-display");
    if (renderFilePreview(display, {img, pdf, url, name: m.name}))
      return;
    else if (isText) {
      if (m.size > 2 * 1024 * 1024) {
        display.textContent = "文件较大，可下载后查看。";
        return;
      }
      const res = await fetch(url);
      if (!res.ok) throw Error("读取材料失败");
      const pre = document.createElement("pre");
      pre.className = "file-text";
      pre.textContent = await res.text();
      if (display.isConnected) display.append(pre);
    } else
      display.textContent = "可下载原文件并在对应应用中查看。";
  }
  async function archivedProjects(trashed = false) {
    const all = await request(trashed ? "projects?trashed=1" : "projects?archived=1");
    const rows = all.map(
      p => el("div", {class: "row"}, el("span", {class: "row-main"}, p.name),
        button(local("projectsRestore", "恢复", "Restore"), "restore-project", {id: p.id + ":" + p.revision}),
        trashed ? "" :
                  button(local("projectTrashAction", "移至回收站", "Move to Trash"), "trash-project",
                    {id: p.id + ":" + p.revision})));
    dialog(trashed ? copy("项目回收站", "Project trash") :
                     local("projectsArchivedTitle", "已归档项目", "Archived Projects"),
      fragment(rows.length ? rows :
                             empty(trashed ? copy("回收站为空", "Project trash is empty") :
                                             copy("暂无已归档项目", "No archived projects")),
        button(trashed ? local("projectsArchivedTitle", "已归档项目", "Archived Projects") :
                         copy("查看回收站", "View trash"),
          trashed ? "archived-projects" : "trashed-projects")));
  }

  function relationForm() {
    const choices = (state.graph.nodes || []).filter(n => n.kind !== "missing").map(n => [n.id, n.label]);
    if (choices.length < 2) {
      dialog("新增知识关系", empty("需要两个项目条目", "请先添加论文、笔记或任务。"));
      return;
    }
    dialog("新增知识关系",
      el("form", {}, field("来源条目", select("source", choices, choices[0][0])),
        field("关系",
          select("kind",
            [
              ["related", "相关"], ["supports", "支持"], ["contradicts", "矛盾"], ["extends", "扩展"],
              ["uses", "使用方法"]
            ],
            "related")),
        field("目标条目", select("target", choices, choices[1][0])), formFooter("添加关系")));
    bindForm(async (f, token) => {
      const source = value(f, "source"),
        target = value(f, "target");
      if (source === target) throw Error("请选择两个不同的条目");
      await request(projectPath("graph/relations"), {
        method: "POST",
        body: {
          source,
          target,
          kind: value(f, "kind")
        }
      });
      done(token);
      await refresh();
      toast("关系已添加");
    });
  }

  function removeRelation(id) {
    const edge = state.graph.edges.find(e => e.id === id);
    if (!edge) return;
    dialog("移除知识关系",
      el("form", {}, el("p", {}, "移除这条手工添加的关系？两个来源条目会保留。"), formFooter("移除关系")));
    bindForm(async (_, token) => {
      await request(projectPath("graph/relations/" + enc(id)) + "?revision=" + enc(edge.revision), {
        method: "DELETE"
      });
      done(token);
      await refresh();
      toast("关系已移除");
    });
  }
  async function browseFiles() {
    const base = projectPath("files");
    dialog("项目目录", el("p", {class: "status"}, "正在读取…"), {wide: true});
    const box = $("dialog-content").firstElementChild;
    try {
      const files = await request(base);
      if (!box.isConnected) return;
      renderProjectFilesList(box, { projectPath: state.project.path, files });
    } catch (err) {
      if (box.isConnected) box.textContent = err.message;
    }
  }
  async function editFile(path) {
    const base = projectPath("files");
    const source = path ? await request(base + "?path=" + enc(path)) : {
      path: "",
      text: "",
      version: "missing"
    };
    dialog(path ? "编辑项目文件" : "新建项目文件",
      el("form", {class: "note-edit"},
        field("相对路径",
          input("path", source.path, path ? {readonly: true} : {required: true, placeholder: "notes.md"})),
        field("文本", area("text", source.text)), formFooter("保存到项目目录")),
      {wide: true});
    bindForm(async (f, token) => {
      await request(base, {
        method: "PATCH",
        body: {
          path: value(f, "path"),
          text: f.elements.text.value,
          version: source.version
        }
      });
      done(token);
      toast("项目文件已保存");
    });
  }

  function paperRemovalProjects(projects) {
    if (!projects.length) return "";
    const rows = [...projects].sort((a, b) => (a.name || a.id).localeCompare(b.name || b.id)).map(project => {
      const state = project.trashed ? copy("回收站", "In Trash") : project.archived ? copy("已归档", "Archived") : "";
      const membership = project.member ? copy("项目文献关联将移除", "Project membership will be removed") : "";
      const pages = project.wikiPages ? copy(`${project.wikiPages} 个 Wiki 页面`, `${project.wikiPages} Wiki page(s)`) : "";
      const archived = project.archivedWikiPages ? copy(`${project.archivedWikiPages} 个归档 Wiki 页面`, `${project.archivedWikiPages} archived Wiki page(s)`) : "";
      return el("li", {}, el("strong", {}, project.name || project.id), " · ",
        [state, membership, pages, archived].filter(Boolean).join(" · "));
    });
    return el("ul", {}, rows);
  }

  async function confirmPaperRemoval(id, project = "") {
    const owner = state.project?.id;
    const path = "papers/" + enc(id);
    const preview = path + "/removal";
    const title = project ? copy("从当前项目移除", "Remove from Current Project") :
      copy("从共享文献库删除", "Delete from Shared Library");
    dialog(title,
      fragment(
        el("p", {role: "status", "data-paper-removal-loading": true}, copy("正在读取影响…", "Checking impact…")),
        el("div", {class: "form-foot"}, button(local("appCancel", "取消", "Cancel"), "close-dialog"))));
    const loading = $("dialog-content").querySelector("[data-paper-removal-loading]");
    let impact;
    try {
      impact = await request(preview);
    } catch (error) {
      loading.textContent = error.message;
      loading.setAttribute("role", "alert");
      return;
    }
    if (!loading.isConnected || !loading.closest("dialog")?.open || state.project?.id !== owner) return;

    const membership = impact.projects.find(item => item.id === project && item.member);
    if (project && !membership) {
      loading.textContent = copy("当前项目已无此文献的关联。", "This paper is already unlinked from the current project.");
      return;
    }
    let details;
    if (membership) {
      const label = membership.name || membership.id;
      details = fragment(
        el("p", {},
          copy(`从项目「${label}」移除「${impact.title}」？`, `Remove “${impact.title}” from “${label}”?`)),
        el("p", {},
          copy("此项目的核心标记、置顶和阅读安排也会移除。共享文献、附件、其他项目和 Wiki 来源引用均保留。",
            "This project’s core status, pin and reading plan will be removed. The shared paper, attachments, other projects and Wiki source references are retained.")));
    } else {
      const removed = [copy("文献记录", "Paper record"), impact.hasPDF && copy("本地 PDF", "Local PDF"),
        impact.hasMarkdown && copy("已保存的 Markdown 正文及其附件", "Saved Markdown and its attachments"),
        impact.annotations > 0 && copy(`${impact.annotations} 条 PDF 批注`, `${impact.annotations} PDF annotation(s)`)].filter(Boolean);
      const tasks = impact.relatedTasks ?
        el("p", {},
          copy(`${impact.relatedTasks} 项任务保留来源引用。`,
            `${impact.relatedTasks} task(s) will retain their source references.`)) :
        "";
      const wiki = impact.projects.some(item => item.wikiPages || item.archivedWikiPages) ?
        el("p", {},
          copy("相关 Wiki 页面保留正文和原来源引用，仍可编辑。",
            "Linked Wiki pages remain editable and retain their text and original references.")) :
        "";
      details = fragment(
        el("p", {},
          copy(`从共享文献库删除「${impact.title}」？`, `Delete “${impact.title}” from the shared library?`)),
        el("p", {},
          copy(`将永久删除${removed.join("、")}。`, `Permanently removes the following. ${removed.join(", ")}.`)),
        paperRemovalProjects(impact.projects), wiki, tasks,
        el("p", {},
          copy("历史会议和其他记录中指向该论文的链接将无法打开原文。",
            "Links to this paper in past meetings and other records will no longer open the original source.")));
    }
    let form;
    dialog(title,
      el("form", {}, details,
        formFooter(project ? copy("确认移除", "Remove from Project") :
                             copy("确认从文献库删除", "Delete from Shared Library"))),
      {canDismiss: () => !form?.dataset.pending});
    form = bindForm(async (f, token) => {
      if (state.project?.id !== owner) throw Error(copy("项目已切换，请重新打开确认。", "The current project changed. Reopen the confirmation."));
      if (project) {
        await request(path, {method: "PATCH", body: {
          revision: impact.revision,
          project_ids: (impact.projectIds || []).filter(id => id !== project),
          core_project_ids: (impact.coreProjectIds || []).filter(id => id !== project)
        }});
      } else {
        await request(preview + "?revision=" + enc(impact.revision) + "&confirmation=" + enc(impact.confirmation), {method: "DELETE"});
      }
      delete f.dataset.pending;
      done(token);
      await refresh();
      toast(project ? copy("文献已从当前项目移除", "Paper removed from the current project") :
        copy("文献已从共享文献库删除", "Paper deleted from the shared library"));
    });
  }

  function confirmRemoval(id) {
    const [kind, key] = id.split(":");
    if (kind === "paper") return confirmPaperRemoval(key);
    const map = {
      project: ["项目", state.projects],
      note: ["页面", selectedWikiNote?.id === key ? [selectedWikiNote] : state.notes],
      task: ["任务", state.tasks],
      material: ["材料", state.materials]
    };
    if (!map[kind]) return;
    const [label, items] = map[kind], obj = items.find(x => x.id === key);
    if (!obj) return;
    const path = kind === "project" ? "projects/" + enc(key) : kind === "task" ? E.taskPath(key, obj.projectId) : projectPath(({
      note: "notes",
      material: "materials"
    })[kind] + "/" + enc(key), obj.projectId);
    const verb = (kind === "project" || kind === "note") ? "归档" : "删除";
    const sharedTaskNotice = kind === "task" && obj.projectIds?.length > 1 ? "这会从所有关联项目中删除同一条任务。" : "";
    dialog(verb + label,
      el("form", {},
        el("p", {}, "确认", verb, "“", obj.title || obj.name, "”？",
          kind === "project" ? "项目将从工作台隐藏；保留本地文件夹。" :
            kind === "note"  ? "可从已归档页面恢复。" :
                               sharedTaskNotice),
        formFooter("确认" + verb)));
    bindForm(async (_, token) => {
      await request(path + "?revision=" + enc(obj.revision), {
        method: "DELETE"
      });
      done(token);
      if (kind === "project") await load(null, "projects", {historyMode: "replace"});
      else await refresh();
      toast("已" + verb + label);
    });
  }
  E.libraryForm = {field, input, area, select, bindForm, formFooter, done, value};
  E.formAction = async function(action, id) {
    if (action === "close-dialog") return close();
    if (state.loading || state.loadError) return;
    if (action === "new-project" || action === "edit-project") return window.SciProjectEditor.open(action === "edit-project" ? (id || state.project?.id) : null);
    if (action === "new-paper") return paperForm(null, {focus: id === "pdf" ? "pdf" : "identifiers"});
    if (action === "edit-paper") {
      const p = state.papers.find(p => p.id === id);
      if (p) return paperForm(p);
      return;
    }
    if (action === "confirm-delete") return confirmRemoval(id);
    if (action === "confirm-paper-unlink" && state.project?.id) return confirmPaperRemoval(id, state.project.id);
    if (action === "archived-projects") return archivedProjects();
    if (action === "trashed-projects") return archivedProjects(true);
    if (action === "trash-project") {
      const [pid, rev] = id.split(":");
      await request("projects/"+enc(pid)+"/trash", {method:"POST",body:{revision:Number(rev)}});
      await archivedProjects();
      toast("项目已移至回收站");
      return;
    }
    if (action === "restore-project") {
      const [pid, rev] = id.split(":");
      const p = await request("projects/" + enc(pid) + "/restore", {
        method: "POST",
        body: {
          revision: Number(rev)
        }
      });
      close();
      await load(p.id, "overview", {
        historyMode: "push"
      });
      toast("项目已恢复");
      return;
    }
    if (action === "manage-task-tags") return manageTaskTags();
    if (action === "new-task") return openTaskForm(null);
    if (action === "edit-task") {
      const t = state.tasks.find(item => item.id === id);
      if (t) return openTaskForm(t);
      return;
    }
    if (!state.project) {
      window.SciProjectEditor.open(null);
      return;
    }
    const look = (arr) => arr.find(x => x.id === id);
    if (action === "new-note") return noteForm(null, false, id);
    if (action === "new-wiki-folder") return wikiFolderForm();
    if (action === "read-wiki-folder") return readWikiFolder(id);
    if (action === "new-paper-wiki") return paperWikiForm();
    if (action === "open-paper-wiki") {
      const existing = state.notes.find(n => n.template === "paper" && n.paperId === id);
      return existing ? E.openWikiNote(existing.id) : paperWikiForm(id);
    }
    if (action === "wiki-snippet-settings") return wikiSnippetSettings();
    if (action === "read-note") return E.openWikiNote(id);
    if (action === "edit-note" || action === "move-note") {
      const n = selectedWikiNote?.id === id && selectedWikiNote.projectId === state.project.id ?
        selectedWikiNote : look(state.notes);
      if (n) return noteForm(n, action === "move-note");
    }
    if (action === "archived-notes") return archivedNotes();
    if (action === "restore-note") {
      const [note, revision] = id.split(":");
      await request(projectPath("notes/" + enc(note) + "/restore"), {
        method: "POST", body: {revision: Number(revision)}
      });
      close();
      await refresh();
      toast("页面已恢复");
      return;
    }
    if (action === "new-relation") return relationForm();
    if (action === "remove-relation") return removeRelation(id);
    if (["linked-materials", "preview-linked-material", "material-native"].includes(action)) {
      return E.linkedMaterialsAction(action, id);
    }
    if (action === "project-files") return browseFiles();
    if (action === "open-project-file" || action === "new-project-file") return editFile(action === "new-project-file" ?
      "" : id);
    if (action === "new-material") return materialForm();
    if (action === "read-material" || action === "edit-material") {
      const m = look(state.materials);
      if (m) return action === "read-material" ? readMaterial(m) : materialForm(m);
    }
  };
