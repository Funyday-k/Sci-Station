"use strict";
(() => {
  const E = window.SciResearch;
  const {
    state,
    $,
    esc,
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
    markdown,
    math,
    bytes
  } = E;
  const attr = (v) => esc(v ?? "");
  const field = (label, content) => '<label class="field"><span>' + esc(label) + '</span>' + content + '</label>';

  function input(name, value = "", options = "") {
    return '<input name="' + name + '" value="' + attr(value) + '" ' + options + '>';
  }

  function area(name, value = "", opts = "") {
    return '<textarea name="' + name + '" ' + opts + '>' + esc(value) + '</textarea>';
  }

  function option(value, label, current) {
    return '<option value="' + esc(value) + '" ' + (String(value) === String(current) ? "selected" : "") + '>' + esc(
      label) + '</option>';
  }

  function select(name, items, current) {
    return '<select name="' + name + '">' + items.map(([v, l]) => option(v, l, current)).join("") + '</select>';
  }

  function split(s) {
    return String(s || "").split(/[,，;；\n]+/).map(s => s.trim()).filter(Boolean);
  }
  const paperSelect = id => select("paperId", [
    ["", "无关联论文"], ...state.papers.map(p => [p.id, p.title])
  ], id || "");
  const value = (f, name) => String(f.elements.namedItem(name)?.value || "").trim();
  const chosen = (f, name) => [...f.querySelectorAll('input[name="' + name + '"]:checked')].map(i => i.value);
  const formStatus = () => '<p class="error" data-error role="alert"></p><p class="status" data-status role="status"></p>';
  const formFooter = (label, del = "") => formStatus() + '<div class="form-foot">' + (del ? button(del.startsWith(
      "project:") ? "归档项目" : "删除", "confirm-delete", {
      id: del,
      kind: "bare danger"
    }) : "") +
    '<button type="button" class="button" data-action="close-dialog">取消</button><button type="submit" class="button primary">' +
    esc(label) + '</button></div>';
  let formEpoch = 0;

  function bindForm(onSubmit) {
    const f = $("dialog-content").querySelector("form");
    const token = ++formEpoch;
    f.addEventListener("submit", async e => {
      e.preventDefault();
      if (f.dataset.pending || !f.reportValidity()) return;
      f.dataset.pending = "true";
      const submit = f.querySelector("[type=submit]");
      submit.disabled = true;
      const error = f.querySelector("[data-error]"),
        status = f.querySelector("[data-status]");
      error.textContent = "";
      status.textContent = "正在保存…";
      try {
        await onSubmit(f, token);
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
      return '<div data-paper-project><div class="project-choice"><label class="check"><input type="checkbox" name="project_ids" value="' +
        esc(project.id) + '" ' + (selected.includes(project.id) ? "checked" : "") + '>' + esc(project.name) +
        '</label><label class="check"><input type="checkbox" name="core_project_ids" value="' + esc(project.id) + '" ' +
        (core.includes(project.id) ? "checked" : "") + '>核心文献</label></div>' +
        '<details><summary>' + esc(project.name) + '的阅读安排</summary><fieldset ' +
        (selected.includes(project.id) || core.includes(project.id) ? "" : "disabled") + '>' +
        '<label class="check"><input type="checkbox" name="pinned-' + id + '" ' +
        (link.is_pinned ? "checked" : "") + '>置顶</label><div class="split">' +
        field("排序序号", input("order-" + id, link.sort_order, 'type="number" step="1" min="-9007199254740991" max="9007199254740991" placeholder="可留空，较小值优先"')) +
        field("文献文件夹", input("folder-" + id, link.folder_path, 'maxlength="512" placeholder="例如：理论/散射"')) +
        '</div>' + field("研究用途", input("purpose-" + id, link.use_for?.join(", "), 'placeholder="例如：比较方法，核对推导"')) +
        '</fieldset></details></div>';
    });
    return '<fieldset class="file-drop"><legend>收录到项目</legend><div class="project-choices">' +
      choices.join("") + '</div></fieldset>';
  }

  function projectForm(edit = false) {
    const p = edit ? state.project : null;
    dialog(edit ? "项目设置" : "新建科研项目", '<form>' + field("项目名称", input("name", p?.name,
      'required maxlength="160" autofocus placeholder="例如：太阳暗物质"')) + field("项目简介", area("description", p?.description,
      'maxlength="12000" placeholder="研究问题、目标或记录范围"')) + (p ? "" :
      '<div class="field"><span>项目文件夹</span><p id="chosen-folder" class="form-help">默认使用 Sci-Station 管理的本地目录。</p><button id="pick-folder" type="button" class="button">选择已有文件夹…</button><input name="path" type="hidden"></div>'
      ) + (p?.path ? '<p class="form-help">圆桌项目文件夹<br>' + esc(p.path) + '</p>' : "") + button("已归档项目",
      "archived-projects", {
        kind: "bare"
      }) + formFooter(edit ? "保存更改" : "创建项目", p ? "project:" + p.id : "") + '</form>');
    if (!p) $("pick-folder").onclick = async () => {
      const el = $("pick-folder");
      el.disabled = true;
      try {
        const result = await request("/api/studio/pick-project", {
          method: "POST",
          body: {}
        });
        if (result.path) {
          el.parentElement.querySelector("[name=path]").value = result.path;
          $("chosen-folder").textContent = result.path;
        }
      } catch (err) {
        $("chosen-folder").textContent = err.message;
      } finally {
        el.disabled = false;
      }
    };
    bindForm(async (f, token) => {
      const body = {
        name: value(f, "name"),
        description: value(f, "description")
      };
      if (!p && value(f, "path")) body.path = value(f, "path");
      const item = await request(p ? "projects/" + enc(p.id) : "projects", {
        method: p ? "PATCH" : "POST",
        body: p ? {
          ...body,
          revision: p.revision
        } : body
      });
      done(token);
      await load(item.id, "overview", {
        historyMode: "push"
      });
      toast(p ? "项目已更新" : "项目已创建");
    });
  }

  function paperForm(p = null) {
    const edit = Boolean(p);
    const base = edit ? "papers/" + enc(p.id) : "papers";
    dialog(edit ? "编辑文献" : "导入文献", '<form>' +
      (edit ? "" : '<div class="file-drop">' + field("本地 PDF",
          '<input type="file" name="pdf" accept=".pdf,application/pdf" multiple>') +
        '<p class="form-help">所选 PDF 分别导入，共用标签、阅读状态和项目。</p></div>' +
        field("按标识符或链接导入", area("identifiers", "", 'rows="3" placeholder="每行一个 DOI、arXiv 编号、INSPIRE 链接或网址"'))) +
      field("题名", input("title", p?.title, (edit ? "required " : "") + 'maxlength="1000" placeholder="可从文件名或在线元数据获取"')) +
      '<div class="split">' + field("DOI", input("doi", p?.doi, 'placeholder="10.…"')) + field("arXiv 编号", input("arxiv",
        p?.arxiv, 'placeholder="2404.10066"')) + '</div>' +
      field("原文链接", input("url", p?.url, 'type="url" placeholder="https://…"')) +
      (edit ? "" : '<label class="check"><input type="checkbox" name="lookup_metadata" checked>查询在线元数据</label>' +
        '<label class="check"><input type="checkbox" name="fetch_pdf">同时下载在线 PDF</label>' +
        '<label class="check" hidden data-link-fallback><input type="checkbox" name="allow_link_only">在线 PDF 无法下载或阅读时仅保存链接</label>' +
        '<button type="button" class="button" data-import-preview-button>预览文献</button><p data-import-preview role="status"></p>') +
      '<details ' + (edit ? "open" : "") + '><summary>元数据与阅读状态</summary>' + field("作者", input("authors", p?.authors?.join(
        ", "), 'placeholder="多位作者用逗号分隔"')) + '<div class="split">' + field("年份", input("year", p?.year || "",
        'type="number" min="1" max="9999"')) + field("阅读状态", select("status", Object.entries({
        unread: "未读",
        reading: "阅读中",
        read: "已读"
      }), p?.status || "unread")) + '</div>' +
      field("标签", input("tags", p?.tags?.join(", "), 'placeholder="用逗号分隔"')) + field("摘要", area("abstract", p
      ?.abstract)) +
      (edit ? '<div class="split">' + field("评分（0–5）", input("rating", p.rating || 0, 'type="number" min="0" max="5"')) +
        field("优先级（0–5）", input("priority", p.priority || 0, 'type="number" min="0" max="5"')) + '</div>' + field(
          "BibTeX 引用键", input("citekey", p.citekey)) + field("参考文献", area("references", p.references?.join("\n"),
          'placeholder="每行一条，可填写引用文本、DOI、arXiv 编号或 BibTeX 引用键"')) : "") +
      '</details>' + attachProjectBoxes(p, !edit) + (edit ? "" : '<ul data-import-results aria-live="polite"></ul>') + formFooter(edit ? "保存更改" : "导入文献", edit ? "paper:" + p.id : "") +
      '</form>', {
        wide: true
      });
    const completed = new Set();
    const outcomes = new Map();
    function paperBody(f) {
      const body = {
        title: value(f, "title"),
        doi: value(f, "doi"),
        arxiv: value(f, "arxiv"),
        url: value(f, "url"),
        authors: split(value(f, "authors")),
        tags: split(value(f, "tags")),
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
        if (p?.project_links?.[project.id] || link.is_pinned || order !== "" || link.folder_path || link.use_for.length) {
          links[project.id] = link;
        }
      }
      if (Object.keys(links).length) body.project_links = links;
      const collection = value(f, "collection_id");
      if (collection) body.collection_id = collection;
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

    function importItems(f) {
      const files = [...(f.elements.pdf?.files || [])];
      const targets = importIdentifiers(f);
      if (files.length && targets.length) throw Error("请分别提交本地 PDF 和在线标识符。");
      return files.length ? files : targets.length ? targets : [null];
    }

    function drawImportResults(f, items) {
      f.querySelector("[data-import-results]").replaceChildren(...items.filter(Boolean).map(item => {
        const entry = document.createElement("li");
        entry.textContent = (item.name || item) + " · " + (outcomes.get(item) || "等待导入");
        return entry;
      }));
    }

    function importPayload(f, item, multiple) {
      const body = paperBody(f);
      const file = item && typeof item !== "string";
      if (!item && !body.title && !body.doi && !body.arxiv && !body.url) {
        throw Error("请选择 PDF，或输入题名、DOI、arXiv 编号或网址。");
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
            outcomes.set(item, "正在导入");
            drawImportResults(f, items);
            try {
              const record = await request("papers", {method: "POST", body: payload});
              const warning = [record.import_warning, record.metadata_warning].filter(Boolean).join(" · ");
              outcomes.set(item, "已入库 · " + record.title + (warning ? " · " + warning : ""));
              completed.add(item);
            } catch (err) {
              outcomes.set(item, err.message);
            }
            drawImportResults(f, items);
          }
        } finally {
          f.elements.pdf.disabled = false;
          identifiers.disabled = false;
        }
        const missing = items.length - completed.size;
        f.querySelector("[data-status]").textContent = "已入库 " + completed.size + " / " + items.length;
        f.querySelector("[type=submit]").textContent = missing ?
          (typeof items[0] === "string" ? "重试未成功的标识符" : "重试未成功的文件") : "完成";
        await refresh();
        return;
      }
      let payload;
      if (edit) {
        payload = Object.assign(paperBody(f), {
          revision: p.revision,
          citekey: value(f, "citekey"),
          rating: Number(value(f, "rating")),
          priority: Number(value(f, "priority")),
          references: value(f, "references").split(/\r?\n/).map(line => line.trim()).filter(Boolean)
        });
      } else {
        payload = importPayload(f, items[0], false);
      }
      const record = await request(base, {
        method: edit ? "PUT" : "POST",
        body: payload
      });
      done(token);
      await refresh();
      const warning = [record?.import_warning, record?.metadata_warning].filter(Boolean).join(" · ");
      toast(warning ? "文献已导入 · " + warning : edit ? "文献已更新" : "文献已导入");
    });
    if (!edit) {
      const identifiers = form.elements.namedItem("identifiers");
      const preview = form.querySelector("[data-import-preview]");
      const previewButton = form.querySelector("[data-import-preview-button]");
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
        previewButton.textContent = Math.max(files, targets) > 1 ? "预览首篇文献" : "预览文献";
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
        form.querySelector("[type=submit]").textContent = "导入文献";
        resetPreview();
        syncInputs();
      }
      form.elements.pdf.addEventListener("change", resetBatch);
      identifiers.addEventListener("input", resetBatch);
      form.elements.fetch_pdf.addEventListener("change", syncInputs);
      form.addEventListener("change", resetPreview);
      form.addEventListener("input", resetPreview);
      previewButton.addEventListener?.("click", async () => {
        if (form.dataset.pending || !form.reportValidity()) return;
        const epoch = ++previewEpoch;
        preview.textContent = "正在预览…";
        previewButton.disabled = true;
        try {
          const items = importItems(form);
          const body = importPayload(form, items[0], items.length > 1);
          const data = await request("papers/preview", {method: "POST", body});
          if (epoch !== previewEpoch) return;
          preview.textContent = [
            data.title, data.authors?.join(", "), data.year, data.metadata_source,
            data.doi, data.arxiv, data.inspire_id && "INSPIRE " + data.inspire_id,
            data.existing_title && "复用文献库中的《" + data.existing_title + "》",
            items.length > 1 && "已选 " + items.length + " 篇，预览首篇",
            data.metadata_warning
          ].filter(Boolean).join(" · ");
        } catch (err) {
          if (epoch === previewEpoch) preview.textContent = err.message;
        } finally {
          previewButton.disabled = false;
        }
      });
    }
    form.addEventListener("change", event => {
      if (!["project_ids", "core_project_ids"].includes(event.target.name)) return;
      const group = event.target.closest("[data-paper-project]");
      group.querySelector("fieldset").disabled = !group.querySelector('.project-choice input:checked');
    });
  }

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

  function noteForm(n = null, moving = false) {
    const base = projectPath("notes" + (n ? "/" + enc(n.id) : ""), n?.projectId);
    const namespace = field("目录", input("namespace", n?.namespace,
      'maxlength="500" placeholder="例如：concept 或 methods/statistics"'));
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
    dialog(moving ? "移动 Wiki 页面" : n ? "编辑 Wiki 页面" : "新建 Wiki 页面",
      '<form class="note-edit"><fieldset class="wiki-fields">' +
      (moving ? '<p class="form-help">' + esc(wikiPath(n)) + '</p>' + namespace :
        field("标题", input("title", n?.title, 'required maxlength="240" autofocus')) + namespace +
        field("别名", area("aliases", n?.aliases?.join("\n"), 'aria-label="别名" rows="2" placeholder="每行一个。可用目录/名称指定完整路径。"')) +
        field("关联论文", paperSelect(n?.paperId)) + field("标签", input("tags", n?.tags?.join(", "), 'placeholder="用逗号分隔"')) +
        '<div class="note-tools"><strong>Markdown 正文</strong><button type="button" class="bare" id="preview-toggle">预览</button></div>' +
        field("内容", area("body", n?.body, 'aria-label="内容" id="note-body" placeholder="支持 Markdown、数学公式和 [[concept:页面|显示文字]]"')) +
        '<div id="draft-preview" class="note-preview" hidden></div>') +
      '</fieldset><div data-wiki-conflict hidden></div>' + formFooter(moving ? "移动页面" : "保存页面") + '</form>', {
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
      $("preview-toggle").textContent = open ? "返回编辑" : "预览";
      if (open) {
        preview.innerHTML = markdown(splitWikiBody($("note-body").value).body);
        math(preview);
      }
    };
    f = bindForm(async (form, token) => {
      const body = {namespace: value(form, "namespace")};
      if (!moving) Object.assign(body, {
        title: value(form, "title"),
        body: form.elements.body.value,
        tags: split(value(form, "tags")),
        aliases: value(form, "aliases").split(/\r?\n/).map(s => s.trim()).filter(Boolean),
        paperId: value(form, "paperId")
      });
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
  }

  function showNoteConflict(host, latest, useRevision) {
    host.hidden = false;
    host.innerHTML = '<details open><summary>对照已保存版本（修订 ' + esc(latest.revision) + '）</summary>' +
      '<p>' + esc(wikiPath(latest)) + '</p><p>别名：' + esc(latest.aliases?.join(" · ") || "无") +
      '　标签：' + esc(latest.tags?.join(" · ") || "无") + '</p>' +
      field("已保存正文", area("savedBody", latest.body, 'aria-label="已保存正文" readonly')) + '</details>' +
      '<button class="button" type="button">保留草稿并使用此修订</button>';
    host.querySelector("button").onclick = () => {
      useRevision();
      host.textContent = "已采用查看到的修订。保存时将应用当前草稿。";
    };
  }

  function evidenceURL(e) {
    const href = new URL(reader(e.paperId), location.href);
    for (const [name, value] of Object.entries({
      page: e.page, fingerprint: e.sourceHash, quote: e.quote,
      start: e.selectionStart, end: e.selectionEnd, ocr: e.ocr ? "1" : "", annotation: e.annotationId
    })) {
      if (value !== undefined && value !== null && value !== "" && value !== false) href.searchParams.set(name, value);
    }
    return href.pathname + href.search + href.hash;
  }

  function noteOccurrence(n, locator) {
    if (!locator?.line) return "";
    if (locator.revision && locator.revision !== n.revision) {
      return '<p class="form-help" role="status">页面已在图谱读取后更新。刷新图谱后可重新定位原文。</p>';
    }
    const excerpt = n.body.split(/\r\n|\r|\n/)[locator.line - 1];
    if (excerpt === undefined) return "";
    const glyphs = Array.from(excerpt), start = Math.max(0, locator.column - 1 || 0);
    const count = Array.from(locator.text || "").length;
    const at = glyphs.slice(start, start + count).join("");
    const source = count && at === locator.text ? esc(glyphs.slice(0, start).join("")) + '<mark>' + esc(at) + '</mark>' +
      esc(glyphs.slice(start + count).join("")) : esc(excerpt);
    return '<section class="wiki-occurrence" aria-label="引用所在原文"><p class="form-help">第 ' + esc(locator.line) +
      ' 行 · 第 ' + esc(start + 1) + ' 列</p><pre>' + source + '</pre></section>';
  }

  let wikiRequest = 0, selectedWikiNote = null;
  E.openWikiNote = async function (id, locator) {
    const owner = state.project?.id;
    if (!owner || !id) return;
    const token = ++wikiRequest;
    const base = projectPath("notes/" + enc(id), owner);
    const n = await request(base);
    if (token !== wikiRequest || state.project?.id !== owner) return;
    selectedWikiNote = n;
    const {frontmatter, body} = splitWikiBody(n.body);
    const noteURL = E.wikiURL(n.id, owner);
    dialog(n.title, '<p class="form-help">' + esc(wikiPath(n)) + '</p><div class="actions">' +
      button("编辑页面", "edit-note", {id: n.id, kind: "button primary", glyph: "file"}) +
      button("移动页面", "move-note", {id: n.id}) +
      button("归档页面", "confirm-delete", {id: "note:" + n.id, kind: "button"}) +
      link("页面链接", noteURL, "button") +
      link("导出 Markdown", "/api/research/" + base + "/markdown", "button", "import") +
      (n.sourceMeetingId ? link("来源会议", "/studio?project=" + enc(owner) + "&session=" + enc(n.sourceMeetingId), "button", "chat") : "") +
      (n.paperId ? link("关联论文", reader(n.paperId), "button", "book") : "") + '</div>' +
      noteOccurrence(n, locator) + (frontmatter ? '<details class="wiki-frontmatter"><summary>Markdown 元数据</summary><pre>' +
        esc(frontmatter) + '</pre></details>' : "") +
      '<article class="note-preview" id="note-preview">' + markdown(body) + '</article><p class="form-help" id="wiki-link-status" role="status"></p>' +
      ((n.evidence || []).length ? '<div class="subheading">论文证据</div>' + n.evidence.map(e => '<p>' + (e.paperId ? link(
        (state.papers.find(p => p.id === e.paperId)?.title || "查看论文") + (e.page ? " · 第 " + e.page + " 页" : ""),
        evidenceURL(e), "bare") : "") + (e.meetingId ? link("来源会议",
        "/studio?project=" + enc(owner) + "&session=" + enc(e.meetingId), "bare") : "") +
        '</p><blockquote>' + esc(e.quote) + '</blockquote>').join("") : "") + '<div id="backlinks"></div>', {wide: true});
    const preview = $("note-preview"), backlinks = $("backlinks"), status = $("wiki-link-status");
    math(preview);
    const revision = "?revision=" + enc(n.revision);
    const [links, refs] = await Promise.allSettled([
      request(base + "/links" + revision), request(base + "/backlinks" + revision)
    ]);
    if (token !== wikiRequest || state.project?.id !== owner || !preview.isConnected) return;
    if (links.status === "fulfilled") {
      preview.innerHTML = markdown(body, links.value);
      math(preview);
    } else status.textContent = "页面链接读取失败：" + links.reason.message;
    if (refs.status === "fulfilled") {
      if (refs.value?.length) backlinks.innerHTML = '<div class="subheading">链接到此页面</div>' +
        refs.value.map(ref => button(wikiPath(ref), "read-note", {id: ref.id, kind: "bare"})).join("");
    } else backlinks.textContent = "反向链接读取失败：" + refs.reason.message;
  };

  async function archivedNotes() {
    const owner = state.project.id;
    const notes = await request(projectPath("notes", owner) + "?archived=1");
    if (state.project?.id !== owner) return;
    dialog("已归档 Wiki 页面", notes.length ? notes.map(n => '<div class="row"><span class="row-main">' +
      esc(wikiPath(n)) + '</span>' + link("导出 Markdown", "/api/research/" + projectPath("notes/" + enc(n.id) + "/markdown", owner) +
        "?archived=1", "button") + button("恢复", "restore-note", {id: n.id + ":" + n.revision}) + '</div>').join("") :
      empty("暂无已归档页面"));
  }

  function taskEvidence(t) {
    const linked = (t?.evidence || []).filter(e => e.paperId && e.page > 0);
    if (!linked.length) return "";
    return '<section class="task-evidence"><h3>原文证据</h3>' + linked.map(e => {
      const query = new URLSearchParams({project: t.projectId, paper: e.paperId, page: e.page});
      for (const [key, value] of Object.entries({
        fingerprint: e.sourceHash, quote: e.quote, start: e.selectionStart, end: e.selectionEnd,
        ocr: e.ocr ? 1 : null, annotation: e.annotationId
      })) {
        if (value != null && value !== "") query.set(key, value);
      }
      return '<blockquote>' + esc(e.quote) + '</blockquote>' + link("查看论文第 " + e.page + " 页", "/reader?" + query, "bare");
    }).join("") + '</section>';
  }

  function taskForm(t = null) {
    const pid = t?.projectId || state.project?.id;
    const members = t?.projectIds || (pid ? [pid] : []);
    if (!state.projects.length) return;
    const hiddenMembers = members.filter(id => !state.projects.some(project => project.id === id));
    const paperIds = t?.relatedPaperIds || (t?.paperId ? [t.paperId] : []);
    const multi = (label, name, choices, selected) => '<fieldset class="task-picker"><legend>' + esc(label) +
      '</legend><div class="task-options">' + choices.map(([id, title]) => '<label><input type="checkbox" name="' + name +
        '" value="' + esc(id) + '"' + (selected.includes(id) ? " checked" : "") + '> ' + esc(title) + '</label>').join("") +
      '</div></fieldset>';
    const papers = state.papers.map(p => [p.id, p.title]);
    dialog(t ? "编辑任务" : "添加任务", '<form>' +
      field("任务", input("title", t?.title, 'required autofocus maxlength="240"')) +
      '<div class="split">' + field("类型", select("kind", [["general", "普通任务"], ["reading", "论文阅读"]], t?.kind || "general")) +
      field("优先级", select("priority", Object.entries(E.taskPriorityLabels), t?.priority || "medium")) + '</div>' +
      field("状态", select("status", ["open", "inProgress", "done", "cancelled"].map(id => [id, statusLabel[id]]), t?.status || "open")) +
      '<div class="split">' + field("开始日期", input("startDate", t?.startDate, 'type="date"')) +
      field("截止日期", input("dueDate", t?.dueDate, 'type="date"')) + '</div>' +
      field("截止时间", input("dueTime", t?.dueTime, 'type="time"')) +
      multi("关联项目", "projectIds", state.projects.map(p => [p.id, p.name]), members) +
      (papers.length ? multi("关联论文", "relatedPaperIds", papers, paperIds) : "") +
      field("标签", input("tags", t?.tags?.join(", "), 'placeholder="用逗号分隔"')) +
      field("说明", area("description", t?.description)) + taskEvidence(t) + formFooter("保存任务", t ? "task:" + t.id : "") + '</form>', {wide: true});
    bindForm(async (f, token) => {
      const body = {};
      for (const key of ["title", "kind", "priority", "status", "startDate", "dueDate", "dueTime", "description"]) {
        body[key] = value(f, key);
      }
      body.tags = split(value(f, "tags"));
      const projects = chosen(f, "projectIds");
      if (!projects.length) throw Error("请至少选择一个项目");
      const routeProject = pid || projects[0];
      if (!t && !projects.includes(routeProject)) throw Error("新任务须关联当前项目");
      body.projectIds = [...projects, ...hiddenMembers];
      // Keep links to papers that are absent from the current library snapshot
      // when editing an unrelated field. Send an explicit list if links changed.
      const visiblePaperIDs = paperIds.filter(id => papers.some(([paperID]) => id === paperID));
      const selectedPaperIDs = chosen(f, "relatedPaperIds");
      if (!t || visiblePaperIDs.length !== selectedPaperIDs.length || visiblePaperIDs.some(id => !selectedPaperIDs.includes(id))) {
        body.relatedPaperIds = selectedPaperIDs;
      }
      if (t) body.revision = t.revision;
      await request(projectPath("tasks" + (t ? "/" + enc(t.id) : ""), routeProject), {
        method: t ? "PATCH" : "POST",
        body
      });
      done(token);
      await refresh();
      toast("任务已保存");
    });
  }

  function materialForm(m = null) {
    const base = projectPath("materials" + (m ? "/" + enc(m.id) : ""));
    dialog(m ? "重命名材料" : "添加项目材料", '<form>' + (m ? field("文件名", input("name", m.name, 'required autofocus')) : field("选择文件",
        '<input type="file" name="file" required>')) + formFooter(m ? "保存名称" : "添加文件", m ? "material:" + m.id : "") +
      '</form>');
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
  async function readMaterial(m) {
    const url = "/api/research/" + projectPath("materials/" + enc(m.id) + "/content");
    const img = /^image\/(png|jpeg|webp|gif)$/i.test(m.mediaType || "");
    const pdf = /^application\/pdf(?:;|$)/i.test(m.mediaType || "");
    const isText = /^text\/|json|yaml|xml|javascript/i.test(m.mediaType || "") ||
      /\.(txt|md|csv|py|tex|yml|yaml|json|tsv)$/i.test(m.name);
    dialog(m.name, '<div class="actions">' + button("重命名或删除", "edit-material", {
        id: m.id
      }) + '<a class="button" href="' + esc(url) + '" download="' + esc(m.name) +
      '">下载文件</a></div><p class="subheading">' + esc(bytes(m.size)) + ' · ' + esc(m.mediaType) +
      '</p><div id="file-display"></div>', {
        wide: true
      });
    const el = $("file-display");
    if (img) el.innerHTML = '<img class="file-preview" src="' + esc(url) + '" alt="' + esc(m.name) + '">';
    else if (pdf) {
      el.innerHTML = '<iframe class="file-preview" title="PDF 文件预览" src="' + esc(url) + '"></iframe>';
    } else if (isText) {
      if (m.size > 2 * 1024 * 1024) {
        el.textContent = "文件较大，可下载后查看。";
        return;
      }
      const res = await fetch(url);
      if (!res.ok) throw Error("读取材料失败");
      const pre = document.createElement("pre");
      pre.className = "file-text";
      pre.textContent = await res.text();
      if (el.isConnected) el.append(pre);
    } else el.textContent = "可下载原文件并在对应应用中查看。";
  }
  async function archivedProjects() {
    const all = await request("projects?archived=1");
    dialog("已归档项目", all.length ? all.map(p => '<div class="row"><span class="row-main">' + esc(p.name) + '</span>' +
      button("恢复", "restore-project", {
        id: p.id + ":" + p.revision
      }) + '</div>').join("") : empty("暂无已归档项目"));
  }

  function relationForm() {
    const choices = (state.graph.nodes || []).filter(n => n.kind !== "missing").map(n => [n.id, n.label]);
    if (choices.length < 2) {
      dialog("新增知识关系", empty("需要两个项目条目", "请先添加论文、笔记或任务。"));
      return;
    }
    dialog("新增知识关系", '<form>' + field("来源条目", select("source", choices, choices[0][0])) + field("关系", select("kind", [
      ["related", "相关"],
      ["supports", "支持"],
      ["contradicts", "矛盾"],
      ["extends", "扩展"]
    ], "related")) + field("目标条目", select("target", choices, choices[1][0])) + formFooter("添加关系") + '</form>');
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
    dialog("移除知识关系", '<form><p>移除这条手工添加的关系？两个来源条目会保留。</p>' + formFooter("移除关系") + '</form>');
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
    dialog("项目目录", '<p class="status">正在读取…</p>', {
      wide: true
    });
    const box = $("dialog-content").firstElementChild;
    try {
      const files = await request(base);
      if (!box.isConnected) return;
      box.outerHTML = '<p class="form-help">' + esc(state.project.path) + '</p>' + button("新建文本文件", "new-project-file", {
        glyph: "plus"
      }) + '<div class="list">' + (files.length ? files.map(path => button(path, "open-project-file", {
        id: path,
        kind: "search-result"
      })).join("") : empty("目录中暂无可编辑文件")) + '</div>';
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
    dialog(path ? "编辑项目文件" : "新建项目文件", '<form class="note-edit">' + field("相对路径", input("path", source.path, path ?
        "readonly" : "required placeholder=notes.md")) + field("文本", area("text", source.text)) + formFooter(
      "保存到项目目录") + '</form>', {
        wide: true
      });
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

  function confirmRemoval(id) {
    const [kind, key] = id.split(":");
    const map = {
      project: ["项目", state.projects],
      paper: ["文献", state.papers],
      note: ["页面", selectedWikiNote?.id === key ? [selectedWikiNote] : state.notes],
      task: ["任务", state.tasks],
      material: ["材料", state.materials]
    };
    if (!map[kind]) return;
    const [label, items] = map[kind], obj = items.find(x => x.id === key);
    if (!obj) return;
    const path = kind === "project" ? "projects/" + enc(key) : kind === "paper" ? "papers/" + enc(key) : projectPath(({
      note: "notes",
      task: "tasks",
      material: "materials"
    })[kind] + "/" + enc(key), obj.projectId);
    const verb = (kind === "project" || kind === "note") ? "归档" : "删除";
    const sharedTaskNotice = kind === "task" && obj.projectIds?.length > 1 ? "这会从所有关联项目中删除同一条任务。" : "";
    dialog(verb + label, '<form><p>确认' + verb + '“' + esc(obj.title || obj.name) + '”？' + (kind === "project" ?
      "项目将从工作台隐藏；保留本地文件夹。" : kind === "note" ? "可从已归档页面恢复。" : sharedTaskNotice) + '</p>' + formFooter("确认" + verb) + '</form>');
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
  E.formAction = async function(action, id) {
    if (action === "close-dialog") return close();
    if (action === "new-project" || action === "edit-project") return projectForm(action === "edit-project");
    if (action === "new-paper") return paperForm();
    if (action === "edit-paper") {
      const p = state.papers.find(p => p.id === id);
      if (p) return paperForm(p);
      return;
    }
    if (action === "confirm-delete") return confirmRemoval(id);
    if (action === "archived-projects") return archivedProjects();
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
    if (action === "new-task") return state.projects.length ? taskForm() : projectForm();
    if (action === "edit-task") {
      const t = state.tasks.find(item => item.id === id);
      if (t) return taskForm(t);
      return;
    }
    if (!state.project) {
      projectForm();
      return;
    }
    const look = (arr) => arr.find(x => x.id === id);
    if (action === "new-note") return noteForm();
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
    if (action === "project-files") return browseFiles();
    if (action === "open-project-file" || action === "new-project-file") return editFile(action === "new-project-file" ?
      "" : id);
    if (action === "new-material") return materialForm();
    if (action === "read-material" || action === "edit-material") {
      const m = look(state.materials);
      if (m) return action === "read-material" ? readMaterial(m) : materialForm(m);
    }
  };
})();
