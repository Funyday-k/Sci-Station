"use strict";
(() => {
  const E = window.SciResearch;
  const {state, esc, enc, request, button, dialog, render, refresh, toast} = E;
  const {field, input, area, select, bindForm, formFooter, done, value} = E.libraryForm;
  const text = (zh, en) => E.text?.(zh, en) ?? zh;
  const local = (key, zh, en) => E.local?.(key, zh, en) ?? text(zh, en);
  const organizationPath = "papers/organization";
  const bibtexPath = "papers/bibtex";
  const selected = new Set();
  let visiblePapers = [];
  let selectedProject = "";
  const lines = text => String(text || "").split(/\r?\n/).map(line => line.trim()).filter(Boolean);
  const hexColor = /^#[0-9a-f]{6}$/i;
  const columns = {
    title: "题名", authors: "作者", year: "年份", tags: "标签", projects: "项目", collection: "集合",
    coreProjects: "核心项目", publication: "出版物", itemType: "类型", doi: "DOI", arxiv: "arXiv",
    wiki: "Wiki", status: "阅读状态", priority: "优先级", rating: "评分", updated: "更新时间"
  };
  const defaultColumns = ["title", "authors", "year", "tags", "projects", "collection"];
  const sortable = new Set(["title", "authors", "year", "status", "priority", "rating", "updated"]);
  const statusOrder = {unread: 1, reading: 2, read: 3};
  const libraryPreferences = () => state.organization.library || {visible_columns: defaultColumns};

  function collectionPath(id) {
    const names = [];
    while (id && Object.hasOwn(state.organization.collections, id)) {
      const collection = state.organization.collections[id];
      names.unshift(collection.name);
      id = collection.parent_id;
    }
    return names.join(" / ");
  }

  function collectionOptions() {
    return Object.keys(state.organization.collections).map(id => [id, collectionPath(id)])
      .sort((a, b) => a[1].localeCompare(b[1]));
  }

  function collectionField(paper) {
    const initial = paper ? paper.collection_id || "" :
      state.libraryCollection === "unfiled" ? "" : state.libraryCollection || libraryPreferences().default_collection || "";
    return field(text("文献集合", "Collection"), select("collection_id", [["", text("未归类", "Unfiled")], ...collectionOptions()], initial));
  }

  const stringMetadata = [
    ["publication_title", "期刊或会议论文集"], ["publisher", "出版者"], ["volume", "卷"],
    ["issue", "期"], ["pages", "页码"], ["item_type", "文献类型"]
  ];

  function metadataFields(paper) {
    const controls = stringMetadata.map(([key, title]) => field(title, input(key, paper[key],
      key === "item_type" ? 'placeholder="例如 journal-article、conference-paper 或 thesis"' : "")));
    return '<details><summary>出版信息与来源 BibTeX</summary><div class="split">' + controls.join("") +
      '</div>' + field("分类（每行一个）", area("categories", paper.categories?.join("\n"))) +
      field("来源 BibTeX", area("bibtex", paper.bibtex, 'spellcheck="false"')) + '</details>';
  }

  function metadataPayload(form) {
    return Object.assign(Object.fromEntries(stringMetadata.map(([key]) => [key, value(form, key)])), {
      categories: lines(value(form, "categories")),
      bibtex: form.elements.namedItem("bibtex").value
    });
  }

  function changedFields(original, latest, body) {
    const canonical = value => Array.isArray(value) && value.length === 0 ? null : (value ?? null);
    const differs = (a, b) => JSON.stringify(canonical(a)) !== JSON.stringify(canonical(b));
    return Object.keys(body).some(key => {
      if (key === "revision") return false;
      if (key === "project_links") return Object.entries(body[key]).some(([id, fields]) =>
        Object.keys(fields).some(field => differs(original[key]?.[id]?.[field], latest[key]?.[id]?.[field])) ||
        original.project_ids?.includes(id) !== latest.project_ids?.includes(id));
      return differs(original[key], latest[key]);
    });
  }

  async function saveMetadata(path, original, body) {
    const patch = body => request(path, {method: "PATCH", body});
    try {
      return await patch(body);
    } catch (error) {
      if (error.status !== 409) throw error;
      const latest = await request(path);
      if (changedFields(original, latest, body)) {
        throw Error("同一字段已在其他位置修改。此处的草稿仍保留，请先核对最新记录。");
      }
      return patch({...body, revision: latest.revision});
    }
  }

  function filterPapers(papers, projectID) {
    if (projectID !== selectedProject) {
      selected.clear();
      selectedProject = projectID;
    }
    const query = state.query.trim().toLowerCase();
    const collection = state.libraryCollection;
    const tag = state.libraryTag;
    visiblePapers = papers.filter(p => {
      if (tag && !p.tags?.includes(tag)) return false;
      if (collection === "unfiled" && p.collection_id) return false;
      if (collection && collection !== "unfiled") {
        let ancestor = p.collection_id;
        while (ancestor && ancestor !== collection) {
          ancestor = state.organization.collections[ancestor]?.parent_id;
        }
        if (ancestor !== collection) return false;
      }
      const scope = p.project_links?.[projectID];
      return [p.title, (p.authors || []).join(" "), p.year || 0, p.doi, p.arxiv, p.citekey,
        (p.tags || []).join(" "), p.publication_title, p.abstract, scope?.folder_path, (scope?.use_for || []).join(" ")]
        .join(" ").toLowerCase().includes(query);
    });
    return visiblePapers;
  }

  function renderFilters(papers) {
    const collections = [["", text("全部集合", "All collections")], ["unfiled", text("未归类", "Unfiled")], ...collectionOptions()];
    const tags = [...new Set([state.libraryTag, ...papers.flatMap(p => p.tags || []), ...Object.keys(state.organization.tags)])]
      .filter(Boolean).sort((a, b) => a.localeCompare(b));
    return '<div class="library-filters">' +
      field(text("集合", "Collection"), select("library-collection", collections, state.libraryCollection, text("集合", "Collection"))) +
      field(text("标签", "Tag"), select("library-tag", [["", text("全部标签", "All tags")], ...tags.map(tag => [tag, tag])], state.libraryTag, text("标签", "Tag"))) +
      '</div>';
  }

  function paperTags(paper) {
    if (!paper.tags?.length) return "";
    const chips = paper.tags.slice(0, 3).map(name => {
      const {color, text_color: text} = Object.hasOwn(state.organization.tags, name) ? state.organization.tags[name] : {};
      let style = "";
      if (hexColor.test(color)) {
        const [r, g, b] = color.slice(1).match(/../g).map(pair => {
          const c = parseInt(pair, 16) / 255;
          return c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4;
        });
        const foreground = hexColor.test(text) ? text : r * .2126 + g * .7152 + b * .0722 > .179 ? "#000000" : "#ffffff";
        style = ' style="background:' + color + ';color:' + foreground + '"';
      }
      return '<button class="tag paper-tag" type="button" data-action="filter-paper-tag" data-id="' +
        esc(name) + '" title="' + esc(name) + '"' + style + '>' + esc(name) + '</button>';
    });
    if (paper.tags.length > 3) chips.push('<span class="tag">+' + (paper.tags.length - 3) + '</span>');
    return '<div class="paper-tags">' + chips.join("") + '</div>';
  }

  function selectionCheckbox(paper) {
    return '<input type="checkbox" data-library-selection="' + esc(paper.id) + '" aria-label="' + esc(text("选择文献 ", "Select paper ") + paper.title) +
      '"' + (selected.has(paper.id) ? " checked" : "") + '>';
  }

  const selection = papers => papers.filter(paper => selected.has(paper.id));
  const clearSelection = () => selected.clear();
  function exportButton(papers) {
    const count = selection(papers).length;
    return (count ? button(text(`批量编辑（${count} 篇）`, `Edit ${count} selected`), "edit-library-selection") : "") +
      button(count ? local("menuExportBibTeXForSelection", "导出所选 BibTeX", "Export BibTeX for Selection") : local("menuExportBibTeX", "导出 BibTeX", "Export BibTeX"), "export-library-bibtex");
  }

  const projectNames = ids => (ids || []).map(id => state.projects.find(project => project.id === id)?.name).filter(Boolean).join("、");
  function tableValue(paper, column) {
    switch (column) {
      case "title": return paper.title;
      case "authors": return (paper.authors || []).join("、");
      case "year": return paper.year || null;
      case "tags": return (paper.tags || []).join("、");
      case "projects": return projectNames(paper.project_ids);
      case "coreProjects": return projectNames(paper.core_project_ids);
      case "collection": return collectionPath(paper.collection_id);
      case "publication": return paper.publication_title;
      case "itemType": return paper.item_type;
      case "doi": return paper.doi;
      case "arxiv": return paper.arxiv;
      case "wiki": {
        const linked = state.project ? (state.notes || []).some(note => note.paperId === paper.id) :
          state.paperWikiStatus?.[paper.id];
        return linked ? "已关联" : "未关联";
      }
      case "status": return E.statusLabel[paper.status];
      case "priority": return paper.priority || null;
      case "rating": return paper.rating || null;
      case "updated": return paper.updated_at?.slice(0, 10);
    }
  }

  function comparePapers(a, b, projectID, column) {
    if (projectID) {
      const first = a.project_links?.[projectID], second = b.project_links?.[projectID];
      const pin = Number(Boolean(second?.is_pinned)) - Number(Boolean(first?.is_pinned));
      if (pin) return pin;
      const order = (first?.sort_order ?? Infinity) - (second?.sort_order ?? Infinity);
      if (order) return order;
    }
    const x = column === "updated" ? a.updated_at : column === "status" ? statusOrder[a.status] : tableValue(a, column);
    const y = column === "updated" ? b.updated_at : column === "status" ? statusOrder[b.status] : tableValue(b, column);
    if (!x || !y) return Number(!x) - Number(!y);
    const cmp = typeof x === "number" ? x - y : String(x).localeCompare(String(y), undefined, {numeric: true});
    return libraryPreferences().sort_descending ? -cmp : cmp;
  }

  function renderPaperTable(papers, projectID) {
    const {visible_columns: shown, sort_column: column, sort_descending: descending} = libraryPreferences();
    const rows = column ? [...papers].sort((a, b) => comparePapers(a, b, projectID, column)) : papers;
    const headings = shown.map(key => '<th scope="col"' +
      (column === key ? ' aria-sort="' + (descending ? "descending" : "ascending") + '"' : "") + '>' +
      (sortable.has(key) ? button(columns[key], "sort-library-column", {id: key, kind: "bare"}) : esc(columns[key])) + '</th>');
    const contents = rows.map(paper => {
      const cells = shown.map(key => {
        if (key === "tags") return '<td>' + (paperTags(paper) || "—") + '</td>';
        if (key === "title") {
          const link = paper.project_links?.[projectID];
          const details = [paper.citekey, paper.core_project_ids?.includes(projectID) && "核心文献",
            link?.is_pinned && "已置顶", link?.sort_order != null && ("序号 " + link.sort_order),
            link?.folder_path && ("文件夹 " + link.folder_path), link?.use_for?.length && ("用途 " + link.use_for.join("、"))]
            .filter(Boolean).join(" · ");
          return '<th scope="row">' + E.link(paper.title, E.reader(paper.id), "library-paper-title") +
            (details ? '<span class="meta">' + esc(details) + '</span>' : "") + '</th>';
        }
        return '<td>' + esc(tableValue(paper, key) || "—") + '</td>';
      }).join("");
      const actions = (!shown.includes("title") ? E.link("阅读", E.reader(paper.id), "bare") : "") +
        button("引文", "show-citation", {id: paper.id, kind: "bare"}) +
        button("编辑", "edit-paper", {id: paper.id, kind: "bare"}) +
        (projectID ? button("论文 Wiki", "open-paper-wiki", {id: paper.id, kind: "bare"}) : "");
      return '<tr><td>' + selectionCheckbox(paper) + '</td>' + cells + '<td><div class="library-table-actions">' + actions + '</div></td></tr>';
    });
    return '<div class="library-table-scroll" tabindex="0" role="region" aria-label="文献表格滚动区域">' +
      '<table class="library-table" aria-label="文献表格"><thead><tr>' +
      '<th scope="col">选择</th>' + headings.join("") + '<th scope="col">操作</th></tr></thead><tbody>' + contents.join("") + '</tbody></table></div>';
  }

  async function saveLibraryPreferences(library, revision = state.organization.revision) {
    state.organization = await request(organizationPath, {method: "PATCH", body: {
      revision, operation: "set_library_preferences", library
    }});
  }

  function libraryPreferencesForm() {
    const revision = state.organization.revision;
    const saved = libraryPreferences();
    const ordered = [...new Set([...saved.visible_columns, ...Object.keys(columns)])];
    dialog("文献库设置", '<form>' + field("默认导入集合", select("default_collection",
      [["", "未归类"], ...collectionOptions()], saved.default_collection || "")) +
      '<fieldset><legend>显示列与顺序</legend><ol data-library-columns class="library-columns">' +
      ordered.map(key => '<li data-column="' + key + '"><label><input type="checkbox" value="' + key + '"' +
        (saved.visible_columns.includes(key) ? " checked" : "") + '> ' + esc(columns[key]) +
        '</label><div><button type="button" class="bare" data-move="-1" aria-label="上移' + esc(columns[key]) +
        '">↑</button><button type="button" class="bare" data-move="1" aria-label="下移' + esc(columns[key]) +
        '">↓</button></div></li>').join("") +
      '</ol><button type="button" class="button" data-reset-columns>恢复默认列</button></fieldset>' +
      '<p class="form-help">工作区书目保存于 <code>research/library/refs/library.bib</code>。</p>' +
      '<a class="bare" href="/api/research/papers/bibliography" download="library.bib">下载工作区书目</a>' +
      formFooter("保存设置") + '</form>', {wide: true});
    const form = bindForm(async (form, token) => {
      const visible = [...form.querySelectorAll("[data-column] input:checked")].map(input => input.value);
      if (!visible.length) throw Error("请至少保留一个文献列");
      const next = {visible_columns: visible, default_collection: value(form, "default_collection")};
      if (visible.includes(saved.sort_column)) {
        next.sort_column = saved.sort_column;
        next.sort_descending = Boolean(saved.sort_descending);
      }
      await saveLibraryPreferences(next, revision);
      done(token);
      await refresh();
      toast("已保存文献库设置");
    });
    const list = form.querySelector("[data-library-columns]");
    list.addEventListener("click", event => {
      const control = event.target.closest("[data-move]");
      if (!control) return;
      const row = control.closest("[data-column]");
      if (control.dataset.move === "-1" && row.previousElementSibling) list.insertBefore(row, row.previousElementSibling);
      if (control.dataset.move === "1" && row.nextElementSibling) list.insertBefore(row.nextElementSibling, row);
      control.focus();
    });
    form.querySelector("[data-reset-columns]").addEventListener("click", () => {
      for (const key of [...new Set([...defaultColumns, ...Object.keys(columns)])]) {
        const row = list.querySelector('[data-column="' + key + '"]');
        row.querySelector("input").checked = defaultColumns.includes(key);
        list.append(row);
      }
    });
  }

  function bulkPatch(paper, changes) {
    const patch = {};
    for (const key of ["collection_id", "status", "rating", "priority"]) {
      if (Object.hasOwn(changes, key) && changes[key] !== (paper[key] ?? "")) patch[key] = changes[key];
    }
    if (changes.addTags.length || changes.removeTags.length) {
      const original = paper.tags || [];
      const tags = [...new Set([...original, ...changes.addTags])].filter(tag => !changes.removeTags.includes(tag));
      if (tags.length !== original.length || tags.some((tag, index) => tag !== original[index])) patch.tags = tags;
    }
    return patch;
  }

  function bulkEditForm() {
    const papers = selection(visiblePapers);
    if (!papers.length) return;
    const keep = ["keep", "保留当前"];
    const fields = field("移动到集合", select("collection_id", [keep, ["", text("未归类", "Unfiled")], ...collectionOptions()], "keep")) +
      field("阅读状态", select("status", [keep, ...Object.entries(E.statusLabel).filter(([key]) =>
        ["unread", "reading", "read"].includes(key))], "keep")) +
      '<div class="split">' + field("评分（0–5）", input("rating", "", 'type="number" min="0" max="5" placeholder="留空则保留"')) +
      field("优先级（0–5）", input("priority", "", 'type="number" min="0" max="5" placeholder="留空则保留"')) +
      '</div><div class="split">' + field("添加标签（每行一个）", area("addTags")) +
      field("移除标签（每行一个）", area("removeTags")) + '</div>';
    dialog("批量编辑 " + papers.length + " 篇文献", '<form><fieldset data-bulk-fields>' + fields +
      '</fieldset><ul data-bulk-results aria-live="polite"></ul>' + formFooter("应用更改") + '</form>', {wide: true});
    const completed = new Set();
    const outcomes = new Map();
    let changes;
    bindForm(async (form, token) => {
      if (!changes) {
        const addTags = lines(value(form, "addTags")), removeTags = lines(value(form, "removeTags"));
        if (addTags.some(tag => removeTags.includes(tag))) throw Error("同一标签不能同时添加和移除");
        changes = {addTags, removeTags};
        for (const key of ["collection_id", "status"]) {
          const next = value(form, key);
          if (next !== "keep") changes[key] = next;
        }
        for (const key of ["rating", "priority"]) {
          const next = value(form, key);
          if (next !== "") changes[key] = Number(next);
        }
        form.querySelector("[data-bulk-fields]").disabled = true;
      }
      const results = form.querySelector("[data-bulk-results]");
      for (const paper of papers) {
        if (completed.has(paper.id)) continue;
        if (!form.closest("dialog")?.open) break;
        const patch = bulkPatch(paper, changes);
        try {
          if (Object.keys(patch).length) {
            await saveMetadata("papers/" + enc(paper.id), paper, {...patch, revision: paper.revision});
          }
          completed.add(paper.id);
          outcomes.set(paper.id, Object.keys(patch).length ? "已更新" : "无需更改");
        } catch (error) {
          outcomes.set(paper.id, error.message);
        }
        results.replaceChildren(...papers.map(item => {
          const li = document.createElement("li");
          li.textContent = item.title + " · " + (outcomes.get(item.id) || "等待处理");
          return li;
        }));
      }
      await refresh();
      if (completed.size === papers.length) {
        done(token);
        toast("已处理 " + completed.size + " 篇文献");
      } else {
        form.querySelector("[data-status]").textContent = "已处理 " + completed.size + " / " + papers.length;
        form.querySelector("[type=submit]").textContent = "重试未完成的文献";
      }
    });
  }

  function exportQuery(ids = [], filter = false) {
    const q = new URLSearchParams();
    if (state.project) q.set("project", state.project.id);
    if (filter && state.query) q.set("q", state.query);
    if (filter && state.libraryTag) q.set("tag", state.libraryTag);
    if (filter && state.libraryCollection) q.set("collection", state.libraryCollection);
    for (const id of ids) q.append("paper", id);
    return "?" + q;
  }

  async function exportBibtex(ids, filtered) {
    const query = exportQuery(ids, filtered);
    const result = await request(bibtexPath + "/save" + query, {method: "POST", body: {}});
    if (result.saved) toast("已保存 BibTeX");
    if (result.browser_download) {
      const element = document.createElement("a");
      element.href = "/api/research/" + bibtexPath + query;
      element.download = "references.bib";
      document.body.append(element);
      element.click();
      element.remove();
    }
  }

  function citationLine(paper) {
    const authors = paper.authors?.length ? paper.authors.join(", ") : "Unknown";
    const venue = paper.publication_title?.trim();
    return authors + " (" + (paper.year || "n.d.") + "). " + paper.title + "." + (venue ? " " + venue + "." : "");
  }

  async function copyText(text) {
    if (window.ClipboardItem && navigator.clipboard?.write) {
      const content = Promise.resolve(text).then(value => new Blob([value], {type: "text/plain"}));
      await navigator.clipboard.write([new ClipboardItem({"text/plain": content})]);
    } else {
      await navigator.clipboard.writeText(await text);
    }
    toast("已复制");
  }

  async function bibtexText(ids) {
    const response = await fetch("/api/research/" + bibtexPath + exportQuery(ids, false));
    if (!response.ok) throw Error("无法读取 BibTeX");
    return response.text();
  }

  async function paperCommand(command) {
    const editing = document.querySelector("dialog[open] [data-library-paper]")?.dataset.libraryPaper;
    const active = editing ? state.papers.filter(p => p.id === editing) : state.view === "papers" ? selection(visiblePapers) : [];
    if (!active.length) throw Error("请先在文献库中选择文献");
    const ids = active.map(p => p.id);
    if (command === "copyCitation") return copyText(active.map(citationLine).join("\n"));
    if (command === "copyBibtex") return copyText(bibtexText(ids));
    if (command === "bibtex") return exportBibtex(ids, false);
    if (active.length !== 1) throw Error("此操作只能用于一篇文献");
    const paper = active[0];
    if (command === "inspector") {
      if (!editing) return E.formAction("edit-paper", paper.id);
      return;
    }
    if (command === "reader" || command === "preview") {
      if (editing) throw Error("请先保存或关闭当前文献的编辑窗口");
      return location.assign(E.reader(paper.id));
    }
    if (command === "deletePaper") {
      if (editing) throw Error("请在当前文献的编辑窗口中确认删除");
      return E.formAction("confirm-delete", "paper:" + paper.id);
    }
    if (!paper.has_pdf) throw Error("此文献尚无本地 PDF");
    return request("papers/" + enc(paper.id) + "/native-file", {
      method: "POST", body: {action: command === "reveal" ? "reveal" : "open"}
    });
  }

  const paperCommands = new Set(["reader", "externalPDF", "preview", "reveal", "copyCitation", "copyBibtex", "bibtex", "deletePaper", "inspector"]);
  window.addEventListener("scistation:command", event => {
    if (!paperCommands.has(event.detail) || event.defaultPrevented) return;
    event.preventDefault();
    paperCommand(event.detail).catch(error => toast(error.message));
  });

  function manageLibrary() {
    const collections = collectionOptions();
    const tags = Object.keys(state.organization.tags).sort((a, b) => a.localeCompare(b));
    const collectionRows = collections.map(([id, path]) => '<div class="row"><span class="row-main">' + esc(path) + '</span>' +
      button("重命名", "rename-library-collection", {id, kind: "bare"}) +
      button("删除", "delete-library-collection", {id, kind: "bare danger"}) + '</div>');
    const tagRows = tags.map(name => '<div class="row"><span class="row-main">' + esc(name) + '</span>' +
      button("颜色", "set-library-tag", {id: name, kind: "bare"}) +
      button("移除颜色", "delete-library-tag", {id: name, kind: "bare danger"}) + '</div>');
    dialog("管理集合和标签", '<div class="split"><section><h3>文献集合</h3>' +
      collectionRows.join("") + button("新建集合", "create-library-collection") +
      '</section><section><h3>标签颜色</h3>' + tagRows.join("") + button("添加标签颜色", "set-library-tag") +
      '</section></div><div class="form-foot">' + button("文献库设置", "library-preferences") +
      button("完成", "close-dialog") + '</div>', {wide: true});
  }

  const collectionActions = {
    "create-library-collection": "create_collection",
    "rename-library-collection": "rename_collection",
    "delete-library-collection": "delete_collection"
  };

  function collectionForm(action, id) {
    const revision = state.organization.revision;
    const operation = collectionActions[action];
    const item = state.organization.collections[id];
    const creating = operation === "create_collection";
    const removing = operation === "delete_collection";
    const fields = removing ? '<p>删除空集合“' + esc(collectionPath(id)) + '”？</p>' :
      field("集合名称", input("name", item?.name, 'required maxlength="128" autofocus')) +
      (creating ? field("上级集合", select("parent_id", [["", "无"], ...collectionOptions()],
        state.libraryCollection)) : "");
    organizationForm(creating ? "新建集合" : removing ? "删除集合" : "重命名集合", fields, {
      revision, operation, collection_id: id
    }, form => ({name: value(form, "name"), parent_id: value(form, "parent_id")}));
  }

  function tagForm(action, name) {
    const revision = state.organization.revision;
    const tag = Object.hasOwn(state.organization.tags, name) ? state.organization.tags[name] : undefined;
    const removing = action === "delete-library-tag";
    const fields = removing ? '<p>移除“' + esc(name) + '”的颜色定义？文献上的标签会保留。</p>' :
      field("标签名称", input("name", name, 'required maxlength="128"' + (name ? " readonly" : " autofocus"))) +
      field("标签颜色", input("color", tag?.color || "#617faa", 'type="color" required')) +
      field("文字颜色（可选）", input("text_color", tag?.text_color, 'placeholder="#ffffff" pattern="#[0-9A-Fa-f]{6}"'));
    organizationForm(removing ? "移除标签颜色" : "设置标签颜色", fields, {
      revision, operation: removing ? "delete_tag" : "set_tag"
    }, form => ({name: form.elements.namedItem("name") ? value(form, "name") : name,
      color: value(form, "color"), text_color: value(form, "text_color")}));
  }

  function organizationForm(title, fields, edit, read) {
    dialog(title, '<form>' + fields + formFooter("确认") + '</form>');
    bindForm(async (form, token) => {
      state.organization = await request(organizationPath, {method: "PATCH", body: {...edit, ...read(form)}});
      if (state.libraryCollection !== "unfiled" && !Object.hasOwn(state.organization.collections, state.libraryCollection)) {
        state.libraryCollection = "";
      }
      done(token);
      render();
      toast("文献分类已更新");
    });
  }

  document.addEventListener("change", ({target}) => {
    if (target.name === "library-collection" || target.name === "library-tag") {
      state[target.name === "library-collection" ? "libraryCollection" : "libraryTag"] = target.value;
      render();
      document.querySelector('select[name="' + target.name + '"]')?.focus();
    } else if (target.dataset.librarySelection) {
      const id = target.dataset.librarySelection;
      if (target.checked) selected.add(id);
      else selected.delete(id);
      render();
      document.querySelector('[data-library-selection="' + id + '"]')?.focus();
    }
  });

  const otherActions = E.formAction;
  E.formAction = async function(action, id) {
    if (action === "manage-library") {
      state.organization = await request(organizationPath);
      return manageLibrary();
    }
    if (action === "library-preferences") return libraryPreferencesForm();
    if (action === "show-citation") return window.SciStationCitations?.open(id);
    if (action === "sort-library-column") {
      const library = libraryPreferences();
      await saveLibraryPreferences({
        ...library, sort_column: id, sort_descending: library.sort_column === id && !library.sort_descending
      });
      return render();
    }
    if (Object.hasOwn(collectionActions, action)) return collectionForm(action, id);
    if (["set-library-tag", "delete-library-tag"].includes(action)) return tagForm(action, id);
    if (action === "filter-paper-tag") {
      state.libraryTag = state.libraryTag === id ? "" : id;
      return render();
    }
    if (action === "export-library-bibtex") return exportBibtex(selection(visiblePapers).map(paper => paper.id), true);
    if (action === "edit-library-selection") return bulkEditForm();
    if (action === "export-paper-bibtex") return exportBibtex([id], false);
    return otherActions(action, id);
  };

  E.library = {lines, collectionPath, collectionField, metadataFields, metadataPayload, saveMetadata,
    filterPapers, renderFilters, paperTags, selectionCheckbox, exportButton, clearSelection, bulkPatch, renderPaperTable};
  E.start();
})();
