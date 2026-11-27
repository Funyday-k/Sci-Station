"use strict";
(() => {
  const $ = id => document.getElementById(id);
  const capabilities = new Map([
    ["round.guidance", "为接下来的讨论轮次提供指引"],
    ["report.guidance", "为新生成的会议报告提供指引"],
    ["code.execute", "手动运行插件工具时执行插件代码"],
    ["meeting.public_turns", "读取当前会议议题和已公开发言"],
    ["meeting.report", "读取当前会议议题和已完成报告"],
  ]);
  const capabilityLabel = value => capabilities.get(value) || "未识别的能力（" + value + "）";
  const errorMessage = error => error?.message || String(error);

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function button(text, click, ariaLabel, primary = false) {
    const node = element("button", "button small " + (primary ? "primary" : "secondary"), text);
    node.type = "button";
    if (ariaLabel) node.setAttribute("aria-label", ariaLabel);
    node.addEventListener("click", () => click(node));
    return node;
  }

  function option(text, value) {
    const node = element("option", "", text);
    node.value = value;
    return node;
  }

  function hasNewerVersion(next, installed) {
    if (!/^\d+\.\d+\.\d+$/.test(next) || !/^\d+\.\d+\.\d+$/.test(installed)) return false;
    const before = installed.split(".").map(Number);
    const after = next.split(".").map(Number);
    const changed = after.findIndex((number, index) => number !== before[index]);
    return changed >= 0 && after[changed] > before[changed];
  }

  function mount({ api }) {
    const results = $("plugin-market-results");
    const sourceList = $("plugin-source-list");
    const search = $("plugin-search");
    const sourceFilter = $("plugin-source-filter");
    const marketStatus = $("plugin-market-status");
    const marketRetry = $("plugin-market-retry");
    const sourceInput = $("plugin-source-url");
    const sourceStatus = $("plugin-source-status");
    const discoverTab = $("plugin-tab-discover");
    const installedTab = $("plugin-tab-installed");
    const confirmDialog = $("plugin-confirm-dialog");
    const confirmError = $("plugin-confirm-error");
    const confirmSubmit = $("plugin-confirm-submit");
    const confirmCancel = $("plugin-confirm-cancel");
    const toolsDialog = $("plugin-tools-dialog");
    const toolsOpen = $("plugin-tools-open");
    const toolSelect = $("plugin-tools-action");
    const toolStatus = $("plugin-tools-status");
    const toolRun = $("plugin-tools-run");
    const toolPreview = $("plugin-tools-result");
    const toolDownload = $("plugin-tools-download");
    const fromRound = $("plugin-tools-from");
    const toRound = $("plugin-tools-to");

    let view = null;
    let registryRequest = null;
    let marketTab = "discover";
    let pendingConfirmation = null;
    const offlineSources = new Set();
    let session = null;
    let toolsScope = null;
    let choices = [];
    let actionRequest = null;
    let saveRequest = null;
    let toolOutput = null;
    let downloadURL = "";

    function setMarketStatus(message, { error = false, retry = false } = {}) {
      marketStatus.textContent = message;
      marketStatus.classList.toggle("plugin-error", error);
      marketRetry.hidden = !retry;
    }

    function setSourceStatus(message, error = false) {
      sourceStatus.textContent = message;
      sourceStatus.classList.toggle("plugin-error", error);
    }

    function updateMarketControls() {
      const busy = Boolean(registryRequest);
      $("plugin-source-add").disabled = busy;
      marketRetry.disabled = busy;
      results.setAttribute("aria-busy", String(busy));
      sourceList.setAttribute("aria-busy", String(busy));
      for (const control of [...results.querySelectorAll("button"), ...sourceList.querySelectorAll("button")])
        control.disabled = busy;
      confirmCancel.disabled = busy;
      confirmSubmit.disabled = busy || Boolean(pendingConfirmation?.checks.some(check => !check.checked));
    }

    function showConfirmation({ opener, title, description, label, payload, capabilities = [], granted = [] }) {
      const body = $("plugin-confirm-permissions");
      const checks = [];
      const existing = capabilities.filter(value => granted.includes(value));
      const added = capabilities.filter(value => !granted.includes(value));
      body.replaceChildren();
      $("plugin-confirm-title").textContent = title;
      $("plugin-confirm-description").textContent = description;
      if (existing.length) {
        const list = element("ul", "plugin-confirm-list");
        list.append(...existing.map(value => element("li", "", capabilityLabel(value))));
        body.append(element("h3", "", "继续使用的能力"), list);
      }
      if (added.length) {
        body.append(element("h3", "", granted.length ? "授权新增能力" : "授权插件能力"));
        for (const value of added) {
          const input = element("input");
          input.type = "checkbox";
          input.addEventListener("change", updateMarketControls);
          const label = element("label", "plugin-confirm-check");
          label.append(input, element("span", "", capabilityLabel(value)));
          body.append(label);
          checks.push(input);
        }
      }
      if (payload.action === "install" && !capabilities.length)
        body.append(element("p", "quiet", "此版本不需要授予能力。"));
      pendingConfirmation = { opener, label, payload, checks };
      confirmError.hidden = true;
      confirmError.textContent = "";
      confirmSubmit.textContent = label;
      updateMarketControls();
      confirmDialog.showModal();
      (checks[0] || confirmCancel).focus();
    }

    function closeConfirmation() {
      if (!confirmDialog.open) return;
      const opener = pendingConfirmation?.opener;
      pendingConfirmation = null;
      confirmDialog.close();
      (opener?.isConnected ? opener : marketTab === "installed" ? installedTab : discoverTab).focus();
    }

    function install(opener, plugin, installed, source) {
      const grants = [...new Set(plugin.capabilities || [])];
      const effects = [];
      if (grants.includes("round.guidance") || grants.includes("report.guidance"))
        effects.push("启用后，指引会用于所有项目接下来的讨论轮次或新报告。");
      if (grants.includes("code.execute"))
        effects.push("可执行工具会在你点击运行时读取工具界面列出的会议资料。");
      const version = installed
        ? "将从 " + installed.version + " 更新至 " + plugin.version + "，保留当前启用状态。"
        : "将安装并启用 " + plugin.version + " 版本。";
      const sourceLabel = source.builtin ? source.name + "（内置来源）" : [source.name, source.url].filter(Boolean).join(" · ");
      showConfirmation({
        opener,
        title: (installed ? "更新 " : "安装 ") + plugin.name,
        description: [version, "插件 ID · " + plugin.id, "作者 · " + plugin.author, "来源 · " + sourceLabel, ...effects].join("\n"),
        label: installed ? "确认更新" : "安装并启用",
        payload: { action: "install", source_id: plugin.source_id, id: plugin.id, sha256: plugin.sha256, grants },
        capabilities: grants,
        granted: installed?.capabilities || [],
      });
    }

    function pluginCard(plugin, installed, candidate, source, sourceLabel) {
      const isInstalledTab = marketTab === "installed";
      const sameSource = installed?.source_id === plugin.source_id;
      const update = sameSource && candidate && hasNewerVersion(candidate.version, installed.version);
      const card = element("article", "plugin-card");
      const info = element("div");
      const controls = element("div", "plugin-card-actions");
      const name = plugin.name || plugin.id;
      const meta = [plugin.version, plugin.author, sourceLabel].filter(Boolean).join(" · ");
      info.append(element("h2", "", name), element("p", "plugin-card-meta", meta));
      if (plugin.description) info.append(element("p", "", plugin.description));
      if (plugin.capabilities?.length) {
        const details = element("details", "plugin-card-capabilities");
        const list = element("ul");
        list.append(...plugin.capabilities.map(value => element("li", "", capabilityLabel(value))));
        details.append(element("summary", "", "查看能力"), list);
        info.append(details);
      }
      if (installed) {
        let status = sameSource ? installed.enabled ? "已启用" : "已停用" : "已从其他目录安装";
        if (sameSource && candidate) {
          if (update && isInstalledTab) status += " · 可更新至 " + candidate.version;
          if (candidate.version === installed.version && installed.sha256 && installed.sha256 !== candidate.sha256)
            status += " · 目录中的同版本内容有变";
        }
        info.append(element("p", "plugin-card-state", status));
      }
      if (!installed || update) {
        const verb = update ? "更新" : "安装";
        const selected = update ? candidate : plugin;
        controls.append(button(verb, opener => install(opener, selected, installed, source), verb + " " + name, true));
      }
      if (isInstalledTab) {
        const toggle = installed.enabled ? "停用" : "启用";
        const pin = { id: installed.id, source_id: installed.source_id, version: installed.version, sha256: installed.sha256 };
        controls.append(
          button(toggle, () => void runMarketMutation(
            { action: installed.enabled ? "disable" : "enable", ...pin },
            name + "已" + toggle,
            installedTab,
          ), toggle + " " + name),
          button("卸载", opener => showConfirmation({
            opener,
            title: "卸载 " + name,
            description: "卸载后会移除该插件的会议工具并停止应用新指引。已有讨论轮次和报告仍保留原指引。",
            label: "确认卸载",
            payload: { action: "uninstall", ...pin },
          }), "卸载 " + name),
        );
      }
      card.append(info, controls);
      return card;
    }

    function sourceLabels(sources) {
      const count = new Map();
      for (const source of sources) {
        const name = source.name || source.id;
        count.set(name, (count.get(name) || 0) + 1);
      }
      return new Map(sources.map(source => {
        const name = source.name || source.id;
        const qualifier = source.builtin ? "内置" : source.url || source.id;
        return [source.id, count.get(name) > 1 ? name + " · " + qualifier : name];
      }));
    }

    function drawResults() {
      const installed = view?.installed || [];
      const available = view?.available || [];
      const currentTab = marketTab === "installed" ? installed : available;
      const source = sourceFilter.value;
      const query = search.value.trim().toLocaleLowerCase();
      const sources = view?.sources || [];
      const labels = sourceLabels(sources);
      const sourcesByID = new Map(sources.map(row => [row.id, row]));
      const installedByID = new Map(installed.map(row => [row.id, row]));
      const latestBySource = new Map(available.map(row => [JSON.stringify([row.source_id, row.id]), row]));
      const matches = currentTab.filter(plugin =>
        (!source || plugin.source_id === source) &&
        (!query || [plugin.name, plugin.author, plugin.description, plugin.id]
          .some(value => value?.toLocaleLowerCase().includes(query))),
      );
      results.replaceChildren();
      for (const plugin of matches) {
        const source = sourcesByID.get(plugin.source_id) || { name: plugin.source_name || plugin.source_id };
        results.append(pluginCard(
          plugin,
          installedByID.get(plugin.id),
          latestBySource.get(JSON.stringify([plugin.source_id, plugin.id])),
          source,
          labels.get(plugin.source_id) || source.name,
        ));
      }
      if (view && !matches.length) {
        const message = query || source ? "没有符合筛选条件的插件。"
          : marketTab === "installed" ? "尚未安装插件。" : "暂无可发现的插件。";
        results.append(element("p", "quiet", message));
      }
      updateMarketControls();
    }

    function drawSources() {
      sourceList.replaceChildren(...(view?.sources || []).map(source => {
        const item = element("li");
        const name = source.name || source.id;
        item.append(element("strong", "", name));
        if (source.builtin) item.append(element("span", "plugin-source-status", "内置目录"));
        if (source.url) item.append(element("p", "plugin-source-url", source.url));
        if (!source.builtin) {
          const lastRefreshed = Date.parse(source.last_refreshed);
          if (Number.isFinite(lastRefreshed))
            item.append(element("span", "plugin-source-status",
              "上次刷新 " + new Date(lastRefreshed).toLocaleString("zh-CN", { dateStyle: "short", timeStyle: "short" })));
          if (offlineSources.has(source.id))
            item.append(element("span", "plugin-source-status", "刷新失败，正在显示本地缓存"));
          const actions = element("div", "plugin-source-actions");
          actions.append(
            button("刷新", () => void runMarketMutation(
              { action: "refresh", source_id: source.id },
              name + "已刷新",
              sourceInput,
            ), "刷新 " + name),
            button("移除", opener => showConfirmation({
              opener,
              title: "移除 " + name,
              description: source.url + "\n目录将从市场中移除，已安装的插件保留。",
              label: "确认移除",
              payload: { action: "unsubscribe", source_id: source.id },
            }), "移除 " + name),
          );
          item.append(actions);
        }
        return item;
      }));
    }

    function drawFilters() {
      const previous = sourceFilter.value;
      const names = sourceLabels(view?.sources || []);
      if (marketTab === "installed") {
        for (const plugin of view?.installed || []) {
          if (!names.has(plugin.source_id))
            names.set(plugin.source_id, (plugin.source_name || plugin.source_id) + "（目录已移除）");
        }
      }
      sourceFilter.replaceChildren(option("所有目录", ""), ...Array.from(names, ([id, name]) => option(name, id)));
      sourceFilter.value = names.has(previous) ? previous : "";
    }

    function drawMarket() {
      drawFilters();
      drawSources();
      drawResults();
    }

    async function withRegistryRequest(method) {
      const request = api("/plugins", method);
      registryRequest = request;
      updateMarketControls();
      try {
        view = await request;
        if (["refresh", "unsubscribe"].includes(method?.action)) offlineSources.delete(method.source_id);
        return view;
      } finally {
        registryRequest = null;
        drawMarket();
      }
    }

    function loadRegistry() {
      return registryRequest || withRegistryRequest();
    }

    async function openMarket() {
      setMarketStatus("正在读取插件市场…");
      try {
        await loadRegistry();
        setMarketStatus("");
      } catch (error) {
        setMarketStatus("读取插件市场失败。" + errorMessage(error), { error: true, retry: true });
      }
    }

    async function runMarketMutation(payload, success, focus) {
      if (registryRequest) return;
      const refreshing = payload.action === "refresh";
      if (refreshing) setSourceStatus("正在刷新目录…");
      else setMarketStatus("正在处理…");
      try {
        await withRegistryRequest(payload);
        if (refreshing) setSourceStatus(success + "。");
        else setMarketStatus(success + "。");
      } catch (error) {
        if (refreshing) {
          offlineSources.add(payload.source_id);
          drawSources();
          setSourceStatus("刷新失败，已保留本地缓存。" + errorMessage(error), true);
        } else {
          setMarketStatus("操作未完成。" + errorMessage(error), { error: true });
        }
      } finally {
        focus.focus();
      }
    }

    function selectTab(tab) {
      marketTab = tab;
      discoverTab.setAttribute("aria-pressed", String(tab === "discover"));
      installedTab.setAttribute("aria-pressed", String(tab === "installed"));
      drawFilters();
      drawResults();
    }

    if (discoverTab) {
      discoverTab.addEventListener("click", () => selectTab("discover"));
      installedTab.addEventListener("click", () => selectTab("installed"));
      search.addEventListener("input", drawResults);
      sourceFilter.addEventListener("change", drawResults);
      marketRetry.addEventListener("click", openMarket);
      $("plugin-source-form").addEventListener("submit", async event => {
        event.preventDefault();
        const url = sourceInput.value.trim();
        if (!url || registryRequest) return;
        setSourceStatus("正在订阅目录…");
        try {
          await withRegistryRequest({ action: "subscribe", url });
          if (sourceInput.value.trim() === url) sourceInput.value = "";
          setSourceStatus("已订阅目录。");
        } catch (error) {
          setSourceStatus("订阅目录失败。" + errorMessage(error), true);
        }
        sourceInput.focus();
      });
      confirmCancel.addEventListener("click", closeConfirmation);
      confirmDialog.addEventListener("cancel", event => {
        event.preventDefault();
        if (!registryRequest) closeConfirmation();
      });
      $("plugin-confirm-form").addEventListener("submit", async event => {
        event.preventDefault();
        const confirmation = pendingConfirmation;
        if (!confirmation || confirmSubmit.disabled) return;
        confirmError.hidden = true;
        confirmSubmit.textContent = "正在处理…";
        try {
          await withRegistryRequest(confirmation.payload);
          closeConfirmation();
          const outcome = {
            "安装并启用": "已安装并启用插件。",
            "确认更新": "插件已更新。",
            "确认卸载": "插件已卸载。",
          };
          if (confirmation.payload.action === "unsubscribe") setSourceStatus("已移除目录。");
          else setMarketStatus(outcome[confirmation.label]);
        } catch (error) {
          confirmError.textContent = "操作未完成。" + errorMessage(error);
          confirmError.hidden = false;
          confirmSubmit.textContent = confirmation.label;
          confirmSubmit.focus();
        }
      });
    }

    function clearToolResult() {
      toolOutput = null;
      if (downloadURL) URL.revokeObjectURL(downloadURL);
      downloadURL = "";
      toolPreview.textContent = "";
      toolPreview.hidden = true;
      toolDownload.removeAttribute("href");
      toolDownload.removeAttribute("aria-disabled");
      toolDownload.hidden = true;
    }

    function setToolStatus(message, error = false) {
      toolStatus.textContent = message;
      toolStatus.classList.toggle("plugin-error", error);
    }

    const publicRoundCount = record =>
      Math.max(0, (record?.rounds?.length || 0) - (record?.status === "running" ? 1 : 0));

    function paintToolControls() {
      const selection = choices[toolSelect.value];
      const readsTurns = selection?.action.input === "public_turns";
      const needsReport = selection?.action.input === "report";
      const canRun = Boolean(selection && (readsTurns || (needsReport && session?.report?.status === "ready")));
      const busy = Boolean(actionRequest || saveRequest);
      $("plugin-tools-action-label").hidden = !choices.length;
      toolSelect.hidden = !choices.length;
      $("plugin-tools-input").hidden = !selection;
      const last = publicRoundCount(session);
      $("plugin-tools-input").textContent = readsTurns
        ? last
          ? "可读取会议议题，以及所选轮次的已公开发言、席位和模型信息。留空时覆盖全部 " + last + " 个公开轮次。"
          : "可读取会议议题。已有发言公开后，也可读取发言、席位和模型信息。"
        : needsReport ? "可读取会议议题和定稿的会议报告。" : "";
      $("plugin-tools-range").hidden = !readsTurns || !last;
      fromRound.max = String(last);
      toRound.max = String(last);
      fromRound.disabled = !readsTurns || !last || busy;
      toRound.disabled = fromRound.disabled;
      toolSelect.disabled = busy;
      toolRun.hidden = !selection;
      toolRun.disabled = !canRun || busy;
      toolRun.textContent = actionRequest ? "正在运行…" : "运行工具";
      if (toolOutput?.nativeSave) toolDownload.setAttribute("aria-disabled", String(Boolean(saveRequest)));
      else toolDownload.removeAttribute("aria-disabled");
    }

    function drawToolChoices() {
      choices = [];
      const groups = [];
      for (const plugin of view?.installed || []) {
        if (!plugin.enabled) continue;
        const group = element("optgroup");
        group.label = [plugin.name, plugin.version, plugin.source_name].filter(Boolean).join(" · ");
        for (const action of plugin.actions || []) {
          if (!["public_turns", "report"].includes(action.input)) continue;
          group.append(option(action.label, String(choices.length)));
          choices.push({ plugin, action });
        }
        if (group.children.length) groups.push(group);
      }
      toolSelect.replaceChildren(...groups);
      toolSelect.value = choices.length ? "0" : "";
    }

    function describeToolAvailability() {
      const selection = choices[toolSelect.value];
      setToolStatus(!selection
        ? "当前没有可用的工具。可以在插件市场安装或启用带会议工具的插件。"
        : selection.action.input === "report" && session?.report?.status !== "ready"
          ? "会议报告生成后即可运行此工具。" : "");
    }

    async function openTools() {
      if (!session || toolsDialog.open) return;
      const scope = { id: session.id };
      toolsScope = scope;
      choices = [];
      toolSelect.value = "";
      fromRound.value = "";
      toRound.value = "";
      clearToolResult();
      paintToolControls();
      $("plugin-tools-retry").hidden = true;
      setToolStatus("正在读取已启用的插件工具…");
      toolsDialog.showModal();
      await loadTools(scope);
    }

    async function loadTools(scope) {
      try {
        await loadRegistry();
        if (toolsScope !== scope) return;
        drawToolChoices();
        paintToolControls();
        describeToolAvailability();
      } catch (error) {
        if (toolsScope !== scope) return;
        setToolStatus("读取插件工具失败。" + errorMessage(error), true);
        $("plugin-tools-retry").hidden = false;
      }
    }

    function closeTools(restoreFocus = false) {
      if (!toolsDialog.open) return;
      toolsScope = null;
      actionRequest = null;
      clearToolResult();
      toolsDialog.close();
      if (restoreFocus) toolsOpen.focus();
    }

    function updateSession(current) {
      if (session?.id !== current?.id) closeTools();
      const readinessChanged = session?.report?.status !== current?.report?.status;
      const roundsChanged = publicRoundCount(session) !== publicRoundCount(current);
      session = current;
      if (toolsDialog.open && !actionRequest && choices.length) {
        if (readinessChanged || roundsChanged) paintToolControls();
        if (readinessChanged && !downloadURL) describeToolAvailability();
      }
    }

    function outputFilename(name, extension) {
      const safe = String(name || "").replace(/[\\/:*?"<>|\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, "_");
      return safe.toLowerCase().endsWith(extension) ? safe : "plugin-result" + extension;
    }

    function showToolResult(result) {
      const markdown = result.format === "md" || result.format === "markdown";
      const extension = markdown ? ".md" : ".txt";
      const text = String(result.text ?? "");
      const filename = outputFilename(result.filename, extension);
      const format = markdown ? "markdown" : "text";
      toolOutput = { nativeSave: result.native_save === true, payload: { filename, text, format } };
      toolPreview.textContent = text;
      toolPreview.hidden = false;
      downloadURL = URL.createObjectURL(new Blob([text], { type: "text/plain;charset=utf-8" }));
      toolDownload.href = downloadURL;
      toolDownload.download = filename;
      const typeLabel = markdown ? " Markdown" : "文本";
      toolDownload.textContent = toolOutput.nativeSave ? "保存" + typeLabel + "…" : "下载" + typeLabel;
      toolDownload.hidden = false;
    }

    if (toolsDialog) {
      toolDownload.addEventListener("click", async event => {
        const output = toolOutput;
        if (!output?.nativeSave) return;
        event.preventDefault();
        if (saveRequest) return;
        saveRequest = output;
        paintToolControls();
        setToolStatus("请选择保存位置…");
        try {
          const result = await api("/plugins/save-output", output.payload);
          if (toolOutput !== output) return;
          if (result.browser_download === true) {
            output.nativeSave = false;
            toolDownload.textContent = output.payload.format === "markdown" ? "下载 Markdown" : "下载文本";
            toolDownload.removeAttribute("aria-disabled");
            toolDownload.click();
            setToolStatus("已将文件交给浏览器下载。");
          } else if (typeof result.saved === "boolean") {
            setToolStatus(result.saved ? "文件已保存。" : "已取消保存。");
          } else {
            throw new Error("本机服务未返回保存结果。");
          }
        } catch (error) {
          if (toolOutput === output) setToolStatus("保存失败。" + errorMessage(error), true);
        } finally {
          saveRequest = null;
          if (toolsDialog.open) paintToolControls();
        }
      });

      toolsOpen.addEventListener("click", openTools);
      $("plugin-tools-close").addEventListener("click", () => closeTools(true));
      toolsDialog.addEventListener("cancel", event => {
        event.preventDefault();
        closeTools(true);
      });
      $("plugin-tools-retry").addEventListener("click", () => {
        $("plugin-tools-retry").hidden = true;
        setToolStatus("正在读取已启用的插件工具…");
        void loadTools(toolsScope);
      });
      function changedToolInput() {
        clearToolResult();
        paintToolControls();
        describeToolAvailability();
      }
      toolSelect.addEventListener("change", changedToolInput);
      fromRound.addEventListener("input", changedToolInput);
      toRound.addEventListener("input", changedToolInput);
      $("plugin-tools-form").addEventListener("submit", async event => {
        event.preventDefault();
        if (toolRun.disabled || !toolsScope) return;
        const { plugin, action } = choices[toolSelect.value];
        const payload = {
          source_id: plugin.source_id, sha256: plugin.sha256, version: plugin.version,
          plugin_id: plugin.id, action_id: action.id,
        };
        if (action.input === "public_turns") {
          const from = !fromRound.disabled && fromRound.value ? Number(fromRound.value) : null;
          const to = !toRound.disabled && toRound.value ? Number(toRound.value) : null;
          if ([from, to].some(value => value !== null && (!Number.isSafeInteger(value) || value < 1)) ||
              (from !== null && to !== null && from > to)) {
            setToolStatus("请输入有效的轮次范围，结束轮次须不小于起始轮次。", true);
            return;
          }
          if (from !== null) payload.from_round = from;
          if (to !== null) payload.to_round = to;
        }
        const scope = toolsScope;
        const request = {};
        actionRequest = request;
        clearToolResult();
        paintToolControls();
        setToolStatus("正在运行插件工具…");
        try {
          const result = await api("/sessions/" + encodeURIComponent(scope.id) + "/plugin-action", payload);
          if (actionRequest !== request) return;
          showToolResult(result);
          setToolStatus("运行完成。");
        } catch (error) {
          if (actionRequest === request) setToolStatus("运行失败。" + errorMessage(error), true);
        } finally {
          if (actionRequest === request) {
            actionRequest = null;
            paintToolControls();
          }
        }
      });
    }

    return {
      openMarket, openTools, closeTools, updateSession,
      isOpen: () => Boolean(toolsDialog?.open || confirmDialog?.open),
    };
  }

  window.RoundtablePlugins = Object.freeze({ mount });
})();
