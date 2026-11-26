"use strict";
(() => {
  function endpoint(projectID) {
    const query = projectID ? "?" + new URLSearchParams({project: projectID}) : "";
    return "/api/research/modules" + query;
  }

  function isEnabled(state, id) {
    return state?.modules?.find(module => module.id === id)?.effective === true;
  }

  async function request(url, init) {
    const response = await fetch(url, init);
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(result.error || response.statusText);
      error.status = response.status;
      throw error;
    }
    return result;
  }

  const load = projectID => request(endpoint(projectID));
  const change = (projectID, revision, patch) => request(endpoint(projectID), {
    method: "PATCH",
    headers: {"Content-Type": "application/json", "X-Roundtable": "1"},
    body: JSON.stringify({revision, ...patch}),
  });
  const api = Object.freeze({endpoint, load, change, isEnabled});
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof window === "undefined") return;
  window.SciStationModules = api;

  const panel = document.querySelector("#settings-panel-modules");
  if (!panel) return;
  const project = panel.querySelector("#module-settings-project");
  const reset = panel.querySelector("#module-settings-reset");
  const reload = panel.querySelector("#module-settings-reload");
  const status = panel.querySelector("#module-settings-status");
  const list = panel.querySelector("#module-settings-list");
  const dialog = panel.querySelector("#module-settings-confirm");
  const text = (zh, en) => window.SciStationI18n?.text(zh, en) ?? zh;
  const moduleTitle = module => text(module.chineseTitle, module.title);
  let snapshot;
  let projectOptionsLoaded = false;
  let loading = false;
  let pending;

  function element(tag, copy, className) {
    const node = document.createElement(tag);
    node.textContent = copy;
    if (className) node.className = className;
    return node;
  }

  function action(label, id, key, handler, disabled = false) {
    const button = element("button", label, "button secondary small");
    button.type = "button";
    button.disabled = loading || disabled;
    button.dataset.moduleControl = `${id}:${key}`;
    button.addEventListener("click", handler);
    return button;
  }

  function confirm(copy, patch) {
    pending = patch;
    dialog.querySelector("p").textContent = copy;
    dialog.showModal();
  }

  function render() {
    const openIDs = new Set([...list.querySelectorAll("details[open]")].map(node => node.dataset.module));
    const focused = document.activeElement?.dataset.moduleControl;
    project.disabled = loading || !projectOptionsLoaded;
    reset.disabled = loading || Boolean(project.value) || !snapshot;
    reload.disabled = loading;
    const position = new Map(snapshot?.pinnedOrder.map((id, index) => [id, index]));
    const definitions = new Map(snapshot?.modules.map(module => [module.id, module]));
    const modules = [...(snapshot?.modules ?? [])].sort((a, b) => (position.get(a.id) ?? Infinity) - (position.get(b.id) ?? Infinity));
    list.replaceChildren(...modules.map(module => {
      const {id, enabled, effective, pinned, missing} = module;
      const title = moduleTitle(module);
      const row = element("article", "", "module-settings-row");
      row.dataset.module = id;
      const main = element("div", "", "module-settings-main");
      const heading = element("div", "", "module-settings-heading");
      heading.append(element("h3", title));
      if (module.placeholder) heading.append(element("span", text("预留", "Placeholder"), "module-settings-label"));
      main.append(heading);
      const available = effective ? text("已启用", "Enabled") : enabled ? text("依赖未满足", "Dependencies unavailable") : text("已停用", "Disabled");
      main.append(element("p", available, enabled && !effective ? "module-settings-blocked" : "quiet"));
      row.append(main);

      const controls = element("div", "", "module-settings-controls");
      if (project.value) {
        const choice = element("select", "");
        choice.setAttribute("aria-label", text(`${title} 的项目覆盖`, `Project override for ${title}`));
        choice.dataset.moduleControl = `${id}:override`;
        for (const [value, label] of [
          ["inherit", module.workspaceEnabled ? text("继承（启用）", "Inherit (on)") : text("继承（停用）", "Inherit (off)")],
          ["on", text("为此项目启用", "Enable for this project")],
          ["off", text("为此项目停用", "Disable for this project")],
        ]) {
          const option = element("option", label);
          option.value = value;
          choice.append(option);
        }
        choice.value = module.override === undefined ? "inherit" : module.override ? "on" : "off";
        choice.disabled = loading;
        choice.addEventListener("change", () => persist({action: "set", id, enabled: choice.value === "inherit" ? undefined : choice.value === "on"}));
        controls.append(choice);
      } else {
        const toggle = element("input", "");
        toggle.type = "checkbox";
        toggle.checked = enabled;
        toggle.disabled = loading;
        toggle.dataset.moduleControl = `${id}:toggle`;
        toggle.setAttribute("aria-label", text(`启用 ${title}`, `Enable ${title}`));
        toggle.addEventListener("change", () => persist({action: "set", id, enabled: toggle.checked}));
        const label = element("label", "", "module-settings-toggle");
        label.append(toggle, element("span", text("启用", "Enable")));
        const pin = action(pinned ? text("取消固定", "Unpin") : text("固定", "Pin"), id, "pin", () => persist({action: "pin", id, enabled: !pinned}));
        pin.setAttribute("aria-label", pinned ? text(`取消固定 ${title}`, `Unpin ${title}`) : text(`固定 ${title}`, `Pin ${title}`));
        controls.append(label, pin);
        if (pinned) {
          const rank = position.get(id);
          for (const [offset, icon, description] of [[-1, "↑", text(`上移 ${title}`, `Move ${title} up`)], [1, "↓", text(`下移 ${title}`, `Move ${title} down`)]]) {
            const move = action(icon, id, `move:${offset}`, () => persist({action: "move", id, position: rank + offset}), rank + offset < 0 || rank + offset >= position.size);
            move.setAttribute("aria-label", description);
            controls.append(move);
          }
        }
      }
      row.append(controls);

      if (missing?.length) {
        const dependency = element("div", "", "module-settings-dependencies");
        const names = missing.map(id => moduleTitle(definitions.get(id))).join(text("、", ", "));
        dependency.append(element("span", text(`需要 ${names}`, `Requires ${names}`)));
        if (!project.value || enabled) {
          dependency.append(action(text("启用依赖及此模块", "Enable dependencies and module"), id, "dependencies", () => persist({action: "enable-dependencies", id})));
        }
        row.append(dependency);
      }
      if (module.dependencies.length || module.paths?.length || module.placeholder) {
        const details = element("details", "", "module-settings-details");
        details.dataset.module = id;
        details.open = openIDs.has(id);
        details.append(element("summary", text("详情", "Details")));
        if (module.placeholder) details.append(element("p", text("此页面预留给后续实现。项目文件可从材料页面访问。", "This page is reserved for future implementation. Open project files in Materials.")));
        if (module.dependencies.length) {
          const names = module.dependencies.map(id => moduleTitle(definitions.get(id))).join(text("、", ", "));
          details.append(element("p", text(`依赖 ${names}`, `Depends on ${names}`)));
        }
        for (const path of module.paths ?? []) {
          const directory = element("div", "", "module-settings-directory");
          directory.append(element("code", path.path));
          directory.append(element("span", path.exists ? text("可用", "Available") : text("缺失或不可用", "Missing or unavailable")));
          if (path.repairable && !project.value) {
            directory.append(action(text("修复", "Repair"), id, `repair:${path.path}`, () => confirm(
              text(`在当前工作区内创建 ${path.path}？`, `Create ${path.path} in this workspace?`), {action: "repair", id, path: path.path},
            )));
          }
          details.append(directory);
        }
        row.append(details);
      }
      return row;
    }));
    if (focused && !loading) {
      [...list.querySelectorAll("[data-module-control]")].find(node => node.dataset.moduleControl === focused)?.focus();
    }
  }

  async function refresh({projects = false} = {}) {
    if (loading) return;
    loading = true;
    status.textContent = text("正在读取模块设置…", "Loading module settings…");
    render();
    try {
      if (projects || !projectOptionsLoaded) {
        const options = await request("/api/research/projects");
        const previous = projectOptionsLoaded ? project.value : new URL(location.href).searchParams.get("project");
        project.replaceChildren(new Option(text("工作区默认", "Workspace defaults"), ""), ...options.map(item => new Option(item.name, item.id)));
        project.value = options.some(item => item.id === previous) ? previous : "";
        projectOptionsLoaded = true;
      }
      snapshot = await load(project.value);
      status.textContent = "";
    } catch (error) {
      snapshot = undefined;
      status.textContent = text(`无法读取模块设置。${error.message}`, `Could not load module settings. ${error.message}`);
    } finally {
      loading = false;
      render();
    }
  }

  async function persist(patch) {
    if (loading || !snapshot) return;
    const id = project.value;
    const focused = document.activeElement?.dataset.moduleControl;
    loading = true;
    status.textContent = text("正在保存模块设置…", "Saving module settings…");
    render();
    try {
      snapshot = await change(id, snapshot.revision, patch);
      status.textContent = text("已保存", "Saved");
      window.dispatchEvent(new CustomEvent("sci:modules", {detail: {project: id, state: snapshot}}));
    } catch (error) {
      if (error.status === 409) {
        try {
          snapshot = await load(id);
        } catch (_) {
          snapshot = undefined;
        }
        status.textContent = text("模块设置已改变。请检查当前状态后重试。", "Module settings changed. Review current values and retry.");
      } else {
        status.textContent = text(`无法保存模块设置。${error.message}`, `Could not save module settings. ${error.message}`);
      }
    } finally {
      loading = false;
      render();
      if (focused) [...list.querySelectorAll("[data-module-control]")].find(node => node.dataset.moduleControl === focused)?.focus();
    }
  }

  project.addEventListener("change", () => { snapshot = undefined; refresh(); });
  reload.addEventListener("click", () => refresh({projects: true}));
  reset.addEventListener("click", () => confirm(
    text("恢复工作区默认的模块和固定顺序？项目覆盖会保留。", "Restore workspace module defaults and pin order? Project overrides will be kept."),
    {action: "reset"},
  ));
  dialog.addEventListener("close", () => {
    const patch = pending;
    pending = undefined;
    if (dialog.returnValue === "confirm" && patch) persist(patch);
    dialog.returnValue = "";
  });
  window.addEventListener("roundtable:settings-page", event => {
    if (event.detail === "modules") refresh({projects: true});
  });
  window.addEventListener("sci:language", () => {
    if (projectOptionsLoaded) project.options[0].textContent = text("工作区默认", "Workspace defaults");
    render();
  });
  if (!panel.hidden) refresh({projects: true});
})();
