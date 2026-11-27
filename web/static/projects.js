"use strict";

(() => {
  const maxProjectSelections = 12;
  const icon = (name) => window.RoundtableIcons.icon(name);
  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  };
  const iconButton = (glyph, label, className = "") => {
    const button = element("button", `icon-button ${className}`);
    button.type = "button";
    button.title = label;
    button.setAttribute("aria-label", label);
    const svg = window.RoundtableIcons?.iconNode?.(glyph); if (svg) button.replaceChildren(svg);
    return button;
  };
  const textButton = (label, kind = "secondary") => {
    const button = element("button", `button ${kind}`, label);
    button.type = "button";
    return button;
  };
  const pathName = (path) => path.split("/").filter(Boolean).at(-1) || path;
  const unscopedProject = {id: "@global", global: true};
  const projectKey = project => project.id || project.path;
  const sessionProjectKey = session => session.project_id ||
    (session.project ? "legacy:" + session.project : unscopedProject.id);
  function resolveSelection(projects, key) {
    if (!key || key === unscopedProject.id) return unscopedProject;
    return projects.find(project => projectKey(project) === key) || null;
  }

  function mount({ api, history, loadResearch, rerender, newSession, projectsChanged }) {
    let registered = [];
    let research = [];
    let lastSelected = null;
    let lastProject = "";
    const collapsed = new Set();
    const actions = element("div", "project-rail-actions");
    const addButton = iconButton("folderPlus", "添加项目");
    const importButton = iconButton("import", "导入项目配置");
    actions.append(addButton, importButton);
    const label = history.previousElementSibling;
    label.append(actions);

    const dialog = element("dialog", "project-dialog project-management");
    dialog.setAttribute("aria-labelledby", "project-management-heading");
    const heading = element("div", "project-dialog-heading");
    const title = element("h2");
    title.id = "project-management-heading";
    const close = iconButton("close", "关闭项目操作");
    close.dataset.projectAction = "";
    heading.append(title, close);
    const body = element("div", "project-management-body");
    const status = element("p", "project-management-status");
    status.setAttribute("role", "status");
    const footer = element("div", "project-dialog-actions");
    dialog.append(heading, body, status, footer);
    document.body.append(dialog);

    let busy = false;
    let opener = null;
    function setBusy(value) {
      busy = value;
      dialog.setAttribute("aria-busy", String(value));
      for (const control of dialog.querySelectorAll("[data-project-action]")) {
        control.disabled = value;
      }
    }
    close.addEventListener("click", () => dialog.close());
    dialog.addEventListener("cancel", (event) => {
      if (busy) event.preventDefault();
    });
    dialog.addEventListener("close", () => {
      const focus = opener?.closest("[hidden]")
        ? document.getElementById("new-topic") : opener;
      focus?.focus({ preventScroll: true });
      opener = null;
    });
    function showDialog(label, button, wide = false) {
      opener = button;
      title.textContent = label;
      dialog.classList.toggle("project-management-wide", wide);
      status.textContent = "";
      body.replaceChildren();
      footer.replaceChildren();
      setBusy(false);
      if (!dialog.open) dialog.showModal();
    }
    function footerAction(label, kind, callback) {
      const button = textButton(label, kind);
      button.dataset.projectAction = "";
      button.addEventListener("click", callback);
      footer.append(button);
      return button;
    }
    function pathField(label, value = "") {
      const container = element("div", "project-management-field");
      const caption = element("label", "", label);
      caption.htmlFor = "project-management-path";
      const controls = element("div", "project-management-path-controls");
      const input = element("input");
      input.id = caption.htmlFor;
      input.type = "text";
      input.placeholder = "/Users/…";
      input.spellcheck = false;
      input.value = value;
      const choose = textButton("选择…");
      choose.dataset.projectAction = "";
      choose.addEventListener("click", async () => {
        if (busy) return;
        choose.disabled = true;
        status.textContent = "";
        try {
          const result = await api("/pick-project", {});
          if (result.path) input.value = result.path;
        } catch (error) {
          status.textContent = error.message;
          input.focus();
        } finally {
          choose.disabled = busy;
        }
      });
      controls.append(input, choose);
      container.append(caption, controls);
      return { container, input };
    }

    let revision = 0;
    function updateProjects(result) {
      revision++;
      registered = result.projects || [];
      rerender();
      projectsChanged();
    }
    async function load() {
      const initialRevision = revision;
      const [catalog, legacy] = await Promise.allSettled([loadResearch(), api("/projects")]);
      if (revision !== initialRevision) return;
      if (catalog.status === "fulfilled") research = catalog.value;
      updateProjects(legacy.status === "fulfilled" ? legacy.value : {projects: registered});
      if (catalog.status === "rejected") throw catalog.reason;
      if (legacy.status === "rejected") throw legacy.reason;
    }

    function openAdd(opener = addButton) {
      showDialog("添加本地项目", opener);
      const { container, input } = pathField("项目文件夹");
      body.append(container);
      const add = async () => {
        const path = input.value.trim();
        if (busy) return;
        if (!path) {
          status.textContent = "请选择项目文件夹，或输入完整路径。";
          input.focus();
          return;
        }
        status.textContent = "";
        setBusy(true);
        try {
          await api("/projects", { path });
          await load();
          dialog.close();
        } catch (error) {
          status.textContent = error.message;
        } finally {
          setBusy(false);
        }
      };
      input.addEventListener("keydown", (event) => {
        if (event.key === "Enter") {
          event.preventDefault();
          add();
        }
      });
      footerAction("取消", "secondary", () => dialog.close());
      footerAction("添加项目", "primary", add);
      input.focus();
    }
    addButton.addEventListener("click", () => openAdd());

    async function openImport(opener = importButton) {
      showDialog("导入项目配置", opener, true);
      const selected = new Set();
      let candidates = [];
      let legacy = [];
      let manualPath = "";
      let requestId = 0;
      const controller = {
        active: true,
        close: () => {
          controller.active = false;
        },
      };
      dialog.addEventListener("close", controller.close, { once: true });
      const useResult = (id) => controller.active && dialog.open && id === requestId;

      function renderCandidates() {
        if (!controller.active) return;
        body.replaceChildren();
        footer.replaceChildren();
        const combined = new Map(candidates.map((candidate) => [candidate.path, candidate]));
        for (const item of legacy) {
          if (!combined.has(item.path)) combined.set(item.path, {...item, sources: ["圆桌历史"]});
        }
        const caption = element("p", "quiet", "选择项目后，可预览并勾选项目规则。");
        body.append(caption);
        if (combined.size) {
          const list = element("div", "project-import-candidates");
          for (const candidate of combined.values()) {
            const row = element("label", "project-import-candidate");
            const check = element("input");
            check.type = "checkbox";
            check.checked = selected.has(candidate.path);
            check.addEventListener("change", () => {
              if (check.checked) selected.add(candidate.path);
              else selected.delete(candidate.path);
            });
            const meta = element("span", "project-import-meta");
            const name = element("strong", "", candidate.name || pathName(candidate.path));
            const source = element("span", "project-import-source", (candidate.sources || []).join(" · "));
            const path = element("span", "project-import-path", candidate.path);
            path.title = candidate.path;
            meta.append(name, source, path);
            row.append(check, meta);
            list.append(row);
          }
          body.append(list);
        }
        const saved = legacy.filter(item => item.rule_count > 0);
        if (saved.length) {
          const archive = element("details", "project-import-rules");
          archive.append(element("summary", "", "查看历史规则快照"));
          for (const item of saved) {
            const group = element("details", "project-rule-details");
            group.append(element("summary", "", item.path));
            group.addEventListener("toggle", async () => {
              if (!group.open || group.querySelector("pre")) return;
              try {
                const result = await api("/projects/rules?legacy=1&path=" + encodeURIComponent(item.path));
                if (group.isConnected && !group.querySelector("pre")) {
                  for (const rule of result.rules) group.append(element("strong", "", rule.path), element("pre", "", rule.text));
                }
              } catch (error) { if (group.isConnected) status.textContent = error.message; }
            });
            archive.append(group);
          }
          body.append(archive);
        }
        const manual = pathField("也可选择其他项目文件夹", manualPath);
        body.append(manual.container);
        footerAction("取消", "secondary", () => dialog.close());
        const preview = async () => {
          if (busy) return;
          manualPath = manual.input.value.trim();
          const paths = new Set(selected);
          if (manualPath) paths.add(manualPath);
          if (!paths.size || paths.size > maxProjectSelections) {
            status.textContent = "请为本次预览选择 1–12 个项目。";
            return;
          }
          status.textContent = "";
          setBusy(true);
          const id = ++requestId;
          try {
            const result = await api("/projects/import", { action: "preview", paths: [...paths] });
            if (useResult(id)) renderPreview(result.projects || []);
          } catch (error) {
            if (useResult(id)) status.textContent = error.message;
          } finally {
            if (useResult(id)) setBusy(false);
          }
        };
        footerAction("预览规则", "primary", preview);
        manual.input.addEventListener("keydown", (event) => {
          if (event.key === "Enter") {
            event.preventDefault();
            preview();
          }
        });
        setBusy(busy);
      }

      function renderPreview(projects) {
        body.replaceChildren();
        footer.replaceChildren();
        const list = element("div", "project-import-rules");
        const choices = new Map();
        const intro = element("p", "quiet", "勾选要随圆桌讨论提供的规则。导入时保存所选文本的快照。");
        body.append(intro, list);
        for (const project of projects) {
          const group = element("section", "project-import-group");
          const name = element("h3", "", project.name);
          const path = element("div", "project-import-path", project.path);
          path.title = project.path;
          group.append(name, path);
          const chosen = new Map();
          choices.set(project.path, chosen);
          if (!project.rules.length)
            group.append(element("p", "quiet", "这个项目没有可导入的规则文件。"));
          if (project.omitted)
            group.append(element("p", "quiet", "其余规则文件已达到本次预览上限。"));
          for (const rule of project.rules) {
            const details = element("details", "project-rule-details");
            const summary = element("summary", "", rule.path);
            const source = element("span", "project-import-source", rule.imported ? `${rule.source} · 已导入` : rule.source);
            const pre = element("pre", "project-rule-text", rule.text);
            summary.title = rule.path;
            details.append(summary, source, pre);
            const check = element("input");
            check.type = "checkbox";
            check.checked = false;
            check.setAttribute("aria-label", `导入 ${rule.path}`);
            check.addEventListener("change", () => {
              if (check.checked) chosen.set(rule.path, { path: rule.path, digest: rule.digest });
              else chosen.delete(rule.path);
              updateApplyLabel();
            });
            const row = element("div", "project-import-rule");
            row.append(check, details);
            group.append(row);
          }
          list.append(group);
        }
        footerAction("返回", "secondary", () => {
          status.textContent = "";
          renderCandidates();
          footer.querySelector(".primary")?.focus();
        });
        const apply = footerAction("添加项目", "primary", async () => {
          if (busy) return;
          setBusy(true);
          status.textContent = "";
          const id = ++requestId;
          try {
            const selections = projects.map(project => ({id: project.id, path: project.path, rules: [...choices.get(project.path).values()]}));
            await api("/projects/import", { action: "apply", selections });
            await load();
            if (useResult(id)) dialog.close();
          } catch (error) {
            if (useResult(id)) status.textContent = error.message;
          } finally {
            if (useResult(id)) setBusy(false);
          }
        });
        function updateApplyLabel() {
          const count = [...choices.values()].reduce((sum, rules) => sum + rules.size, 0);
          apply.textContent = count > 0 ? `导入所选规则（${count}）` : "添加项目";
        }
        list.querySelector("input")?.focus();
      }

      renderCandidates();
      const id = ++requestId;
      status.textContent = "正在查找已知项目…";
      try {
        const result = await api("/projects/import");
        if (useResult(id)) {
          candidates = result.candidates || [];
          legacy = result.legacy || [];
          const priorInput = body.querySelector("input[type=text]");
          const typing = document.activeElement === priorInput;
          const selection = typing ? [priorInput.selectionStart, priorInput.selectionEnd] : null;
          manualPath = priorInput?.value || "";
          status.textContent = "";
          renderCandidates();
          if (selection) {
            const nextInput = body.querySelector("input[type=text]");
            nextInput.focus({ preventScroll: true });
            nextInput.setSelectionRange(...selection);
          }
        }
      } catch (error) {
        if (useResult(id)) status.textContent = error.message;
      }
    }
    importButton.addEventListener("click", () => openImport());

    async function openRules(project, button) {
      showDialog(`${project.name} 的项目规则`, button, true);
      const done = footerAction("完成", "secondary", () => dialog.close());
      const endpoint = "/projects/rules";
      const query = `${endpoint}?id=${encodeURIComponent(project.id)}`;
      const isCurrent = () => dialog.open && opener?.dataset.projectRules === project.path;

      function renderRules(result) {
        body.replaceChildren();
        if (!result.rules.length) {
          body.append(element("p", "quiet", "当前没有生效的项目规则。"));
          return;
        }
        body.append(element("p", "quiet", "下一轮将使用这里列出的规则快照。"));
        for (const rule of result.rules) {
          const row = element("div", "project-active-rule");
          const details = element("details", "project-rule-details");
          const summary = element("summary", "", rule.path);
          const source = element("span", "project-import-source", `${rule.source} · 版本 ${rule.digest.slice(0, 12)}`);
          source.title = rule.digest;
          details.append(summary, source, element("pre", "project-rule-text", rule.text));
          const disable = textButton("停用");
          disable.dataset.projectAction = "";
          disable.setAttribute("aria-label", `停用 ${rule.path}`);
          disable.addEventListener("click", async () => {
            if (busy) return;
            status.textContent = "";
            setBusy(true);
            try {
              const updated = await api(endpoint, {
                id: project.id, rule: { path: rule.path, digest: rule.digest },
              });
              updateProjects({ projects: registered.map(item => item.id === project.id ? updated.project : item) });
              opener = Array.from(history.querySelectorAll("[data-project-rules]"))
                .find(item => item.dataset.projectRules === project.path) || opener;
              renderRules(updated);
              status.textContent = `已停用 ${rule.path}，下一轮生效。`;
            } catch (error) {
              status.textContent = error.message;
              if (error.status === 409) {
                try {
                  renderRules(await api(query));
                } catch (refreshError) {
                  status.textContent = refreshError.message;
                }
              }
            } finally {
              setBusy(false);
              if (!body.contains(disable)) done.focus({ preventScroll: true });
            }
          });
          row.append(details, disable);
          body.append(row);
        }
      }

      status.textContent = "正在读取项目规则…";
      let closed = false;
      dialog.addEventListener("close", () => { closed = true; }, { once: true });
      try {
        const result = await api(query);
        if (!closed && isCurrent()) {
          renderRules(result);
          status.textContent = "";
        }
      } catch (error) {
        if (!closed && isCurrent()) status.textContent = error.message;
      }
    }

    function available() {
      const rules = new Map(registered.filter(project => project.id).map(project => [project.id, project]));
      const sorted = research.map(project => ({
        ...project, rule_count: rules.get(project.id)?.rule_count,
      })).sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
      return sorted;
    }
    function render(sessions, rows, selected, activeProject) {
      const groups = new Map(available().map(project => [projectKey(project), { ...project, sessions: [], canCreate: true }]));
      for (const session of sessions) {
        const key = sessionProjectKey(session);
        if (!groups.has(key)) {
          const path = session.project || "";
          const unscoped = key === unscopedProject.id;
          const label = unscoped ? "未关联项目的会话" : session.project_id ? "项目已停用" : "旧会话";
          groups.set(key, { path, name: path ? label + " · " + pathName(path) : label, sessions: [], unscoped });
        }
        groups.get(key).sessions.push(session);
        if (session.id === selected && selected !== lastSelected) collapsed.delete(key);
      }
      lastSelected = selected;
      if (activeProject !== lastProject) collapsed.delete(activeProject);
      lastProject = activeProject;
      const fragment = document.createDocumentFragment();
      if (!groups.size) fragment.append(element("p", "quiet", "还没有项目。"));
      [...groups].forEach(([key, group], index) => {
        const section = element("section", "project-rail-group");
        const header = element("div", "project-rail-header");
        const current = key === activeProject;
        if (current) header.classList.add("current-project");
        const trigger = element(group.canCreate ? "button" : "span", "project-rail-trigger");
        trigger.title = group.path || group.name;
        const toggle = iconButton("chevronRight", group.name, "project-rail-chevron");
        toggle.disabled = !group.sessions.length;
        const folder = element("span", "project-rail-folder");
        const svg = window.RoundtableIcons?.iconNode?.("folder"); if (svg) folder.replaceChildren(svg);
        const name = element("span", "project-rail-name", group.name);
        if (!group.unscoped) trigger.append(folder);
        trigger.append(name);
        header.append(toggle, trigger);
        if (group.canCreate) {
          trigger.type = "button";
          if (current) trigger.setAttribute("aria-current", "true");
          trigger.addEventListener("click", () => {
            collapsed.delete(key);
            updateVisibility();
            newSession(key);
          });
          if (Number.isInteger(group.rule_count)) {
            const rules = iconButton("file", `查看 ${group.name} 的项目规则（${group.rule_count} 条生效）`, "project-rail-rules");
            rules.dataset.projectRules = group.path;
            rules.addEventListener("click", () => openRules(group, rules));
            header.append(rules);
          }
          const add = iconButton("plus", `在 ${group.name} 中新建圆桌`, "project-rail-new");
          add.addEventListener("click", () => newSession(key));
          header.append(add);
        }
        const children = element("div", "project-rail-sessions");
        children.id = `project-rail-sessions-${index}`;
        toggle.setAttribute("aria-controls", children.id);
        function updateVisibility() {
          const closed = collapsed.has(key);
          children.hidden = closed;
          const label = `${closed ? "展开" : "折叠"} ${group.name} 的圆桌`;
          toggle.setAttribute("aria-expanded", String(!closed));
          toggle.setAttribute("aria-label", label);
          toggle.title = label;
        }
        toggle.addEventListener("click", () => {
          if (collapsed.has(key)) collapsed.delete(key);
          else collapsed.add(key);
          updateVisibility();
        });
        group.sessions.forEach((session) => {
          const row = rows.get(session.id);
          if (row) children.append(row);
        });
        updateVisibility();
        section.append(header, children);
        fragment.append(section);
      });
      history.replaceChildren(fragment);
    }
    return { render, available, load, openAdd, openImport };
  }

  window.RoundtableProjects = { mount, resolveSelection, projectKey, sessionProjectKey };
})();
