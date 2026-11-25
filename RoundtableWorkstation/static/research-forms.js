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
    return '<fieldset class="file-drop"><legend>收录到项目</legend><div class="project-choices">' + state.projects.map(p =>
      '<div class="project-choice"><label class="check"><input type="checkbox" name="project_ids" value="' + esc(p.id) +
      '" ' + (selected.includes(p.id) ? "checked" : "") + '>' + esc(p.name) +
      '</label><label class="check"><input type="checkbox" name="core_project_ids" value="' + esc(p.id) + '" ' + (core
        .includes(p.id) ? "checked" : "") + '>核心文献</label></div>').join("") + '</div></fieldset>';
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
        '<p class="form-help">多份 PDF 分别按文件名入库，共用所选标签、阅读状态和项目。</p></div>') +
      field("题名", input("title", p?.title, (edit ? "required " : "") + 'maxlength="1000" placeholder="可从文件名或在线元数据获取"')) +
      '<div class="split">' + field("DOI", input("doi", p?.doi, 'placeholder="10.…"')) + field("arXiv 编号", input("arxiv",
        p?.arxiv, 'placeholder="2404.10066"')) + '</div>' +
      field("原文链接", input("url", p?.url, 'type="url" placeholder="https://…"')) +
      (edit ? "" : '<label class="check"><input type="checkbox" name="fetch_pdf">同时下载在线 PDF</label><label class="check" hidden data-link-fallback><input type="checkbox" name="allow_link_only">在线 PDF 无法下载或阅读时仅保存链接</label>') +
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
          "BibTeX 引用键", input("citekey", p.citekey)) + field("引用的论文", input("references", p.references?.join(", "),
          'placeholder="论文 ID、DOI、arXiv 编号或 citekey，用逗号分隔"')) : "") +
      '</details>' + attachProjectBoxes(p, !edit) + (edit ? "" : '<ul data-import-results aria-live="polite"></ul>') + formFooter(edit ? "保存更改" : "导入文献", edit ? "paper:" + p.id : "") +
      '</form>', {
        wide: true
      });
    const completed = new Set();
    const outcomes = new Map();
    const form = bindForm(async (f, token) => {
      const files = [...(f.elements.pdf?.files || [])];
      const file = files[0];
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
      if (!edit && !file && !body.title && !body.doi && !body.arxiv && !body.url) throw Error(
        "请选择 PDF，或输入题名、DOI、arXiv 编号或网址。");
      if (files.length > 1) {
        const pending = files.filter(item => !completed.has(item));
        if (!pending.length) {
          done(token);
          return;
        }
        const metadata = {tags: body.tags, status: body.status, project_ids: body.project_ids, core_project_ids: body.core_project_ids};
        const results = f.querySelector("[data-import-results]");
        const drawResults = () => {
          results.replaceChildren(...files.map(item => {
            const li = document.createElement("li");
            li.textContent = item.name + " · " + (outcomes.get(item) || "等待导入");
            return li;
          }));
        };
        f.elements.pdf.disabled = true;
        try {
          for (const item of pending) {
            if (!f.closest("dialog")?.open || token !== formEpoch) break;
            outcomes.set(item, "正在导入");
            drawResults();
            const payload = new FormData();
            payload.append("file", item);
            payload.append("metadata", JSON.stringify(metadata));
            try {
              const record = await request("papers", {method: "POST", body: payload});
              outcomes.set(item, "已入库 · " + record.title);
              completed.add(item);
            } catch (err) {
              outcomes.set(item, err.message);
            }
            drawResults();
          }
        } finally {
          f.elements.pdf.disabled = false;
        }
        const missing = files.length - completed.size;
        f.querySelector("[data-status]").textContent = "已入库 " + completed.size + " / " + files.length;
        f.querySelector("[type=submit]").textContent = missing ? "重试未成功的文件" : "完成";
        await refresh();
        return;
      }
      let payload = body;
      if (edit) {
        Object.assign(body, {
          revision: p.revision,
          citekey: value(f, "citekey"),
          rating: Number(value(f, "rating")),
          priority: Number(value(f, "priority")),
          references: split(value(f, "references"))
        });
      } else {
        body.fetch_pdf = !file && Boolean(f.elements.fetch_pdf?.checked);
        body.allow_link_only = body.fetch_pdf && Boolean(f.elements.allow_link_only?.checked);
        if (file) {
          payload = new FormData();
          payload.append("file", file);
          payload.append("metadata", JSON.stringify(body));
        }
      }
      const record = await request(base, {
        method: edit ? "PUT" : "POST",
        body: payload
      });
      done(token);
      await refresh();
      toast(record?.import_warning ? "已仅保存链接 · " + record.import_warning : edit ? "文献已更新" : "文献已导入");
    });
    if (!edit) {
      const syncInputs = () => {
        const count = form.elements.pdf.files.length;
        for (const name of ["title", "doi", "arxiv", "url", "authors", "year", "abstract"]) {
          form.elements.namedItem(name).disabled = count > 1;
        }
        form.elements.fetch_pdf.disabled = count > 0;
        form.querySelector("[data-link-fallback]").hidden = count > 0 || !form.elements.fetch_pdf.checked;
      };
      form.elements.pdf.addEventListener("change", () => {
        completed.clear();
        outcomes.clear();
        form.querySelector("[data-import-results]").replaceChildren();
        form.querySelector("[type=submit]").textContent = "导入文献";
        syncInputs();
      });
      form.elements.fetch_pdf.addEventListener("change", syncInputs);
    }
  }

  function noteForm(n = null) {
    const base = projectPath("notes" + (n ? "/" + enc(n.id) : ""));
    dialog(n ? "编辑笔记" : "新建笔记", '<form class="note-edit">' + field("标题", input("title", n?.title,
        'required maxlength="240" autofocus')) + field("关联论文", paperSelect(n?.paperId)) + field("标签", input("tags", n
        ?.tags?.join(", "), 'placeholder="用逗号分隔"')) +
      '<div class="note-tools"><strong>Markdown 正文</strong><button type="button" class="bare" id="preview-toggle">预览</button></div>' +
      field("内容", area("body", n?.body, 'id="note-body" placeholder="支持 Markdown、数学公式和 [[笔记标题]]"')) +
      '<div id="draft-preview" class="note-preview" hidden></div>' + formFooter("保存笔记", n ? "note:" + n.id : "") +
      '</form>', {
        wide: true
      });
    $("preview-toggle").onclick = () => {
      const preview = $("draft-preview"),
        edit = $("note-body").parentElement;
      const open = preview.hidden;
      preview.hidden = !open;
      edit.hidden = open;
      $("preview-toggle").textContent = open ? "返回编辑" : "预览";
      if (open) {
        preview.innerHTML = markdown($("note-body").value);
        math(preview);
      }
    };
    bindForm(async (f, token) => {
      const body = {
        title: value(f, "title"),
        body: f.elements.body.value,
        tags: split(value(f, "tags")),
        paperId: value(f, "paperId")
      };
      if (n) body.revision = n.revision;
      await request(base, {
        method: n ? "PATCH" : "POST",
        body
      });
      done(token);
      await refresh();
      toast("笔记已保存");
    });
  }
  async function readNote(n) {
    const base = projectPath("notes/" + enc(n.id));
    dialog(n.title, '<div class="actions">' + button("编辑笔记", "edit-note", {
        id: n.id,
        kind: "button primary",
        glyph: "file"
      }) + link("导出 Markdown", "/api/research/" + base + "/markdown", "button", "import") + (n.sourceMeetingId ? link(
          "来源会议", "/studio?project=" + enc(state.project.id) + "&session=" + enc(n.sourceMeetingId), "button", "chat") :
        "") + (n.paperId ? link("关联论文", reader(n.paperId), "button", "book") : "") +
      '</div><article class="note-preview" id="note-preview">' + markdown(n.body) + '</article>' +
      ((n.evidence || []).length ? '<div class="subheading">论文证据</div>' + n.evidence.map(e => '<p>' + (e.paperId ? link(
          (state.papers.find(p => p.id === e.paperId)?.title || "查看论文") + (e.page ? " · 第 " + e.page + " 页" : ""),
          reader(e.paperId) + (e.page ? "&page=" + enc(e.page) : ""), "bare") : "") + (e.meetingId ? link("来源会议",
          "/studio?project=" + enc(state.project.id) + "&session=" + enc(e.meetingId), "bare") : "") +
        '</p><blockquote>' + esc(e.quote) + '</blockquote>').join("") : "") + '<div id="backlinks"></div>', {
        wide: true
      });
    math($("note-preview"));
    const el = $("backlinks");
    try {
      const refs = await request(base + "/backlinks");
      if (!el.isConnected) return;
      if (refs?.length) el.innerHTML = '<div class="subheading">链接到这篇笔记</div>' + refs.map(r => button(r.title,
        "read-note", {
          id: r.id,
          kind: "bare"
        })).join("");
    } catch (err) {
      if (el.isConnected) el.textContent = "反向链接读取失败：" + err.message;
    }
  }

  function taskForm(t = null) {
    const owner = t?.projectId || state.project?.id;
    const projectPicker = owner ? "" : field("所属项目", '<select name="owner" required><option value="">选择项目</option>' +
      state.projects.map(p => option(p.id, p.name, "")).join("") + '</select>');
    dialog(t ? "编辑任务" : "添加任务", '<form>' + projectPicker + field("任务", input("title", t?.title, 'required autofocus maxlength="300"')) +
      '<div class="split">' + field("截止日期", input("dueDate", t?.dueDate, 'type="date"')) + field("状态", select("status",
        Object.entries({
          open: "待办",
          doing: "进行中",
          done: "已完成"
        }), t?.status || "open")) + '</div>' + field("关联论文", paperSelect(t?.paperId)) + field("说明", area("description", t
        ?.description)) + formFooter("保存任务", t ? "task:" + t.id : "") + '</form>');
    bindForm(async (f, token) => {
      const body = {
        title: value(f, "title"),
        dueDate: value(f, "dueDate"),
        status: value(f, "status"),
        paperId: value(f, "paperId"),
        description: value(f, "description")
      };
      if (t) body.revision = t.revision;
      const base = projectPath("tasks" + (t ? "/" + enc(t.id) : ""), owner || value(f, "owner"));
      await request(base, {
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
    const choices = (state.graph.nodes || []).map(n => [n.id, n.label]);
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
      note: ["笔记", state.notes],
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
    const verb = kind === "project" ? "归档" : "删除";
    dialog(verb + label, '<form><p>确认' + verb + '“' + esc(obj.title || obj.name) + '”？' + (kind === "project" ?
      "项目将从工作台隐藏；保留本地文件夹。" : "") + '</p>' + formFooter("确认" + verb) + '</form>');
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
    if (action === "read-note" || action === "edit-note") {
      const n = look(state.notes);
      if (n) return action === "read-note" ? readNote(n) : noteForm(n);
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
