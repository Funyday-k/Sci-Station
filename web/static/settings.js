"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const form = $("settings-form");
  if (!form) return;

  const appearance = window.RoundtableAppearance;
  const colorThemeControl = form.elements.namedItem("color_theme");
  const text = (zh, en) => window.SciStationI18n?.text(zh, en) ?? zh;

  const clientLogos = {
    codex: "/static/openai.svg",
    claude: "/static/claude.svg",
    gemini: "/static/gemini.svg",
    copilot: "/static/github-copilot.svg",
    opencode: "/static/opencode.svg",
    magpie: "/static/magpie-avatar.svg",
  };
  const assetFor = (id) => clientLogos[String(id || "").toLowerCase()] || "";

  const state = {
    settings: null,
    dirty: false,
    writing: false,
    activeSection: "models",
    restoringRoute: false,
  };

  const overview = {
    checkedAt: 0,
    loading: false,
    modelsKey: null,
    modelRequest: 0,
    agent: null,
    agentAction: false,
    agentRequest: 0,
  };

  const toolBudgetDefaults = {
    max_calls: 240,
    context_chars: 5000000,
    total_results: 5000000,
    per_result: 5000000,
    auto_read: true,
  };
  const toolBudgetControls = {
    max_calls: "setting-max-tool-calls",
    context_chars: "setting-context-chars",
    total_results: "setting-total-tool-chars",
    per_result: "setting-per-tool-chars",
  };

  async function api(path, body) {
    const options = {
      headers: { Accept: "application/json" },
      cache: "no-store",
    };
    if (body !== undefined) {
      options.method = "POST";
      options.headers["Content-Type"] = "application/json";
      options.headers["X-Roundtable"] = "1";
      options.body = JSON.stringify(body);
    }
    const response = await fetch(`/api/studio${path}`, options);
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(data.error || text("设置请求失败", "Settings request failed"));
      error.status = response.status;
      throw error;
    }
    return data;
  }

  function showError(error) {
    const banner = $("error-banner");
    const label = $("error-text");
    if (!banner || !label) return;
    label.textContent = error?.message || String(error);
    banner.hidden = false;
  }

  function clearError() {
    const banner = $("error-banner");
    if (banner) banner.hidden = true;
  }

  $("dismiss-error")?.addEventListener("click", clearError);

  function showToolBudget(budget) {
    for (const [key, id] of Object.entries(toolBudgetControls)) {
      const input = $(id);
      if (input) input.value = budget[key];
    }
    const autoRead = $("setting-auto-read");
    if (autoRead) autoRead.checked = Boolean(budget.auto_read);
  }

  function settingsPatch() {
    return {
      appearance: $("setting-appearance").value,
      color_theme: colorThemeControl.value,
      text_size: $("setting-text-size").value,
      max_children: Number($("setting-max-children").value),
      max_steps: Number($("setting-max-steps").value),
      timeout: Number($("setting-timeout").value),
      tool_budget: {
        ...Object.fromEntries(
          Object.entries(toolBudgetControls).map(([key, id]) => [key, Number($(id).value)]),
        ),
        auto_read: $("setting-auto-read").checked,
      },
    };
  }

  function changedToolBudget(patch) {
    const baseline = state.settings.tool_budget || toolBudgetDefaults;
    return Object.entries(patch.tool_budget).some(([key, value]) => baseline[key] !== value);
  }

  function changedSettings() {
    if (!state.settings) return false;
    const patch = settingsPatch();
    const baseline = {
      ...state.settings,
      appearance: state.settings.appearance || "system",
      color_theme: state.settings.color_theme || "iris",
      text_size: state.settings.text_size || "standard",
    };
    return Object.entries(patch).some(([key, value]) =>
      key === "tool_budget" ? changedToolBudget(patch) : value !== baseline[key],
    );
  }

  function updateSaveButtons() {
    for (const button of document.querySelectorAll("#save-settings, #save-settings-appearance")) {
      button.disabled = state.writing || !state.dirty;
    }
  }

  function updateSettingsNavigation() {
    if (!state.settings) return;
    const patch = settingsPatch();
    const collaborationChanged =
      ["max_children", "max_steps", "timeout"].some((key) => patch[key] !== state.settings[key]) ||
      changedToolBudget(patch);
    const appearanceChanged =
      patch.appearance !== (state.settings.appearance || "system") ||
      patch.color_theme !== (state.settings.color_theme || "iris") ||
      patch.text_size !== (state.settings.text_size || "standard");
    for (const tab of document.querySelectorAll(".settings-nav-item")) {
      const key = tab.dataset.settingsPage;
      tab.dataset.unsaved = String(
        (key === "collaboration" && collaborationChanged) ||
          (key === "appearance" && appearanceChanged),
      );
    }
  }

  function setSaveState(message) {
    for (const status of document.querySelectorAll(".settings-save-state")) {
      status.textContent = message;
    }
  }

  function settingsToForm() {
    const settings = state.settings;
    if (!settings) return;
    state.dirty = false;
    $("setting-appearance").value = settings.appearance || "system";
    colorThemeControl.value = settings.color_theme || "iris";
    $("setting-text-size").value = settings.text_size || "standard";
    appearance?.setMode($("setting-appearance").value, true);
    appearance?.setColorTheme(colorThemeControl.value, true);
    appearance?.setTextSize($("setting-text-size").value, true);
    for (const [id, key] of [
      ["setting-max-children", "max_children"],
      ["setting-max-steps", "max_steps"],
      ["setting-timeout", "timeout"],
    ]) {
      $(id).value = settings[key] ?? "";
    }
    showToolBudget(settings.tool_budget || toolBudgetDefaults);
    const advanced = $("collaboration-advanced");
    if (advanced) {
      const budget = settings.tool_budget || toolBudgetDefaults;
      const hasNonDefaultBudget =
        (settings.max_children !== undefined && Number(settings.max_children) !== 2) ||
        Object.keys(toolBudgetControls).some((key) => Number(budget[key]) !== toolBudgetDefaults[key]);
      advanced.open = hasNonDefaultBudget;
    }
    updateSettingsNavigation();
    updateSaveButtons();
  }

  function setStatus(id, label, tone = "") {
    const status = $(id);
    if (!status) return;
    status.textContent = label;
    status.className = `settings-status ${tone}`.trim();
  }

  function setNote(id, message) {
    const note = $(id);
    if (!note) return;
    note.textContent = message;
    note.hidden = !message;
  }

  async function loadSettingsModels() {
    const request = ++overview.modelRequest;
    try {
      const result = await api("/models");
      if (request !== overview.modelRequest) return;
      const catalog = Array.isArray(result.models) ? result.models : [];
      const models = catalog.filter((model) => !model.id.startsWith("sci-station-byok/"));
      const list = $("magpie-model-list");
      list.replaceChildren();
      for (const model of models) {
        const row = document.createElement("li");
        row.textContent = model.label || model.id;
        if (model.label && model.label !== model.id) {
          const id = document.createElement("small");
          id.textContent = model.id;
          row.append(id);
        }
        list.append(row);
      }
      if (!models.length) {
        const empty = document.createElement("li");
        empty.textContent = text("目录为空", "No models available");
        list.append(empty);
      }
      setStatus(
        "magpie-connection",
        result.magpie_error ? text("目录暂不可用", "Catalog unavailable") : text("已连接", "Connected"),
        result.magpie_error ? "settings-warning" : "settings-ready",
      );
      setNote("magpie-connection-detail", result.magpie_error || "");
      $("magpie-model-count").textContent = text(`${models.length} 个模型`, `${models.length} models`);
      $("magpie-models").hidden = Boolean(result.magpie_error);
      const key = JSON.stringify([result.default_model, catalog]);
      if (overview.modelsKey !== key) {
        overview.modelsKey = key;
        window.dispatchEvent(new Event("roundtable:models-changed"));
      }
    } catch (error) {
      if (request !== overview.modelRequest) return;
      $("magpie-models").hidden = true;
      $("magpie-model-list").replaceChildren();
      setStatus("magpie-connection", text("目录暂不可用", "Catalog unavailable"), "settings-warning");
      setNote("magpie-connection-detail", error.message);
      if (overview.modelsKey !== null) {
        overview.modelsKey = null;
        window.dispatchEvent(new Event("roundtable:models-changed"));
      }
    }
  }

  function renderMagpieAgent(result, error = "") {
    const open = $("open-magpie");
    const register = $("register-magpie-agent");
    open.disabled = overview.agentAction || !result?.can_open;
    register.disabled = overview.agentAction;
    register.hidden = !result?.can_install;
    if (error) {
      setStatus("magpie-agent-status", text("状态暂不可用", "Status unavailable"), "settings-warning");
      setNote("magpie-agent-detail", error);
      return;
    }
    const label = result.connected
      ? text("已连接", "Connected")
      : result.registered
        ? text("已注册，等待连接", "Registered, waiting to connect")
        : result.installed && !result.enabled
          ? text("未启用", "Disabled")
          : result.installed
            ? text("等待 Magpie 加载", "Waiting for Magpie")
            : text("未注册", "Not registered");
    setStatus(
      "magpie-agent-status",
      label,
      result.connected || result.registered ? "settings-ready" : "",
    );
    setNote(
      "magpie-agent-detail",
      !result.connected && (result.installed || !result.can_install) ? result.detail || "" : "",
    );
  }

  async function loadMagpieAgent() {
    if (overview.agentAction) return;
    const request = ++overview.agentRequest;
    try {
      const result = await api("/magpie-agent");
      if (request !== overview.agentRequest) return;
      overview.agent = result;
      renderMagpieAgent(result);
    } catch (error) {
      if (request === overview.agentRequest) renderMagpieAgent(overview.agent, error.message);
    }
  }

  async function magpieAgentAction(action) {
    if (overview.agentAction) return;
    overview.agentAction = true;
    overview.agentRequest++;
    overview.checkedAt = 0;
    $("open-magpie").disabled = true;
    $("register-magpie-agent").disabled = true;
    let errorMessage = "";
    try {
      overview.agent = await api("/magpie-agent", action);
    } catch (error) {
      errorMessage = error.message;
    } finally {
      overview.agentAction = false;
      renderMagpieAgent(overview.agent, errorMessage);
    }
    if (!errorMessage && !action.action) await loadSettingsModels();
  }

  function renderClients(clients) {
    const list = $("clients-list");
    list.replaceChildren();
    const installed = clients
      .filter((client) => client.installed === true)
      .sort((a, b) => a.name.localeCompare(b.name));
    for (const client of installed) {
      const row = document.createElement("li");
      row.className = "client-row";
      const src = assetFor(client.id);
      if (src) {
        const tile = document.createElement("span");
        tile.className = "client-logo";
        const image = document.createElement("img");
        image.src = src;
        image.alt = "";
        image.width = 24;
        image.height = 24;
        tile.append(image);
        row.append(tile);
      }
      const identity = document.createElement("div");
      identity.className = "client-identity";
      const name = document.createElement("strong");
      name.textContent = client.name;
      identity.append(name);
      if (client.path) {
        const pathNode = document.createElement("small");
        pathNode.textContent = client.path;
        pathNode.title = client.path;
        identity.append(pathNode);
      }
      const status = document.createElement("span");
      status.className = "settings-status";
      if (client.state === "ready") {
        status.classList.add("settings-ready");
        status.textContent = client.version
          ? text(`可运行 · ${client.version}`, `Ready · ${client.version}`)
          : text("可运行", "Ready");
      } else if (client.state === "check_failed") {
        status.classList.add("settings-warning");
        status.textContent = text("已安装 · 检查失败", "Installed · Check failed");
      } else {
        status.textContent = text("已安装 · 版本未检查", "Installed · Version unchecked");
      }
      row.append(identity, status);
      list.append(row);
    }
    setNote("clients-state", installed.length ? "" : text("未找到已安装的 CLI", "No installed CLIs detected"));
  }

  async function loadClients() {
    try {
      const result = await api("/cli-health");
      renderClients(result.clients || []);
    } catch (error) {
      setNote("clients-state", error.message);
    }
  }

  async function refreshOverview() {
    if (document.hidden || overview.loading || Date.now() - overview.checkedAt < 30000) return;
    overview.loading = true;
    try {
      await Promise.allSettled([loadSettingsModels(), loadMagpieAgent(), loadClients()]);
    } finally {
      overview.loading = false;
      overview.checkedAt = Date.now();
    }
  }

  const pluginsUI = window.RoundtablePlugins?.mount({ api });

  function updateBackToTable(section) {
    const back = $("back-to-table");
    if (!back) return;
    const project = new URL(location.href).searchParams.get("project");
    back.hidden = section !== "plugins" || !window.SciStationNav?.aiAvailable(project);
  }

  $("back-to-table")?.addEventListener("click", () => {
    const project = new URL(location.href).searchParams.get("project");
    const destination = window.SciStationNav?.modeURL("roundtable", project) || "/studio";
    location.assign(destination);
  });

  $("open-magpie")?.addEventListener("click", () => magpieAgentAction({ action: "open" }));
  $("register-magpie-agent")?.addEventListener("click", () => magpieAgentAction({}));

  $("open-rules-file")?.addEventListener("click", async () => {
    const button = $("open-rules-file");
    button.disabled = true;
    try {
      await api("/open-rules", {});
      clearError();
    } catch (error) {
      showError(error);
    } finally {
      button.disabled = false;
    }
  });

  $("restore-tool-budget")?.addEventListener("click", () => {
    showToolBudget(toolBudgetDefaults);
    $("setting-max-steps").value = 10;
    $("setting-auto-read").dispatchEvent(new Event("input", { bubbles: true }));
  });

  form.addEventListener("input", () => {
    state.dirty = changedSettings();
    setSaveState(state.dirty ? text("未保存", "Unsaved changes") : "");
    updateSettingsNavigation();
    updateSaveButtons();
  });

  $("settings-panel-appearance")?.addEventListener("change", (event) => {
    const control = event.target;
    if (control.id === "setting-appearance") appearance?.setMode(control.value);
    if (control.name === "color_theme") appearance?.setColorTheme(control.value);
    if (control.id === "setting-text-size") appearance?.setTextSize(control.value);
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const collabError = $("collaboration-error");
    if (collabError) {
      collabError.textContent = "";
      collabError.hidden = true;
    }
    if (state.writing || !changedSettings()) return;
    const invalid = [...form.elements].find((control) => control.willValidate && !control.checkValidity());
    if (invalid) {
      const panel = invalid.closest(".settings-panel");
      const tab = panel && document.getElementById(panel.getAttribute("aria-labelledby"));
      if (tab) window.RoundtableSettingsNav?.select(tab.dataset.settingsPage);
      const disclosure = invalid.closest("details");
      if (disclosure) disclosure.open = true;
      if (collabError && panel?.id === "settings-panel-collaboration") {
        collabError.textContent = invalid.validationMessage || text("请核对输入范围。", "Please check the entered value.");
        collabError.hidden = false;
      }
      invalid.reportValidity();
      return;
    }
    const patch = settingsPatch();
    state.writing = true;
    updateSaveButtons();
    setSaveState(text("正在保存…", "Saving…"));
    try {
      state.settings = await api("/settings", patch);
      settingsToForm();
      setSaveState(text("已保存", "Saved"));
      clearError();
    } catch (error) {
      showError(error);
      setSaveState(text("尚未保存", "Not saved"));
    } finally {
      state.writing = false;
      updateSaveButtons();
    }
  });

  window.addEventListener("focus", refreshOverview);
  document.addEventListener("visibilitychange", refreshOverview);
  window.addEventListener("beforeunload", (event) => {
    if (state.dirty) {
      event.preventDefault();
      event.returnValue = "";
    }
  });

  window.addEventListener("roundtable:settings-page", (event) => {
    const section = event.detail || "models";
    state.activeSection = section;
    updateBackToTable(section);
    if (section === "plugins") pluginsUI?.openMarket();
    else if (section === "models" || section === "tools") refreshOverview();
    if (!state.restoringRoute && window.SciStationNav) {
      const url = new URL(location.href);
      if (url.pathname === "/settings") {
        if (section === "models") url.searchParams.delete("section");
        else url.searchParams.set("section", section);
        url.searchParams.delete("view");
        if (url.href !== location.href) window.SciStationNav.commitURL(url, "replace");
      } else if (url.pathname === "/studio") {
        const nextView = section === "plugins" ? "plugins" : "settings";
        if (url.searchParams.get("view") !== nextView) {
          url.searchParams.set("view", nextView);
          window.SciStationNav.commitURL(url, "push");
        }
      }
    }
  });

  function sectionFromURL(url) {
    const section = url.searchParams.get("section");
    if (section && $("settings-tab-" + section)?.dataset.settingsPage === section) return section;
    if (url.searchParams.get("view") === "plugins") return "plugins";
    return "models";
  }

  window.addEventListener("popstate", () => {
    const next = sectionFromURL(new URL(location.href));
    if (next === state.activeSection) return;
    state.restoringRoute = true;
    try {
      window.RoundtableSettingsNav?.select(next);
    } finally {
      state.restoringRoute = false;
    }
  });

  async function boot() {
    clearError();
    const initialSection = sectionFromURL(new URL(location.href));
    state.restoringRoute = true;
    try {
      window.RoundtableSettingsNav?.select(initialSection);
    } finally {
      state.restoringRoute = false;
    }
    try {
      state.settings = await api("/settings");
      settingsToForm();
    } catch (error) {
      showError(error);
    }
    await refreshOverview();
  }

  void boot();
})();
