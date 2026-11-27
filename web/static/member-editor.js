"use strict";
(() => {
  function canEdit(session) {
    return Boolean(session && !["running", "closed"].includes(session.status) &&
      session.agenda_draft_status !== "drafting" && !session.report);
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  }

  function mount({loadModels, write, acceptSession, membersOf, displayName}) {
    const dialog = element("dialog", "member-editor");
    dialog.setAttribute("aria-labelledby", "member-editor-heading");
    const form = element("form", "member-editor-form");
    const header = element("header", "member-editor-header");
    const title = element("h2", "", "更改席位");
    title.id = "member-editor-heading";
    const seat = element("p", "member-editor-seat");
    header.append(title, seat);
    const modelField = element("div", "member-editor-field");
    const modelLabel = element("label", "", "模型");
    const model = element("select");
    model.id = modelLabel.htmlFor = "member-editor-model";
    modelField.append(modelLabel, model);
    const effortField = element("div", "member-editor-field");
    const effortLabel = element("label", "", "思考程度");
    const effortControl = element("div", "model-effort-control");
    const slider = element("input");
    slider.id = effortLabel.htmlFor = "member-editor-effort";
    const valueLabel = element("output");
    effortControl.append(slider, valueLabel);
    effortField.append(effortLabel, effortControl);
    const effort = window.SciModelEffort.bind(slider, valueLabel, () => { failure = ""; buttons(); });
    const impact = element("p", "member-editor-impact");
    impact.setAttribute("aria-live", "polite");
    const status = element("p", "member-editor-status");
    status.setAttribute("role", "status");
    const footer = element("footer", "member-editor-footer");
    const reload = element("button", "button secondary", "读取最新设置");
    const cancel = element("button", "button secondary", "取消");
    const save = element("button", "button primary", "保存");
    const retry = element("button", "button secondary", "重试目录");
    reload.type = cancel.type = retry.type = "button";
    save.type = "submit";
    footer.append(retry, reload, cancel, save);
    form.append(header, modelField, effortField, impact, status, footer);
    dialog.append(form);
    document.body.append(dialog);

    let current = null;
    let original = null;
    let opener = null;
    let catalog = new Map();
    let generation = 0;
    let busy = false;
    let loading = false;
    let catalogError = "";
    let failure = "";
    let appBusy = false;

    function latestMember() {
      return current && original && membersOf(current).find(member => member.id === original.id);
    }

    function buttons() {
      const live = latestMember();
      const stale = Boolean(live && (live.version || 0) !== (original.version || 0));
      const locked = !canEdit(current) || appBusy;
      const available = catalog.has(model.value);
      const changed = model.value !== original?.model || effort.value !== (original.effort || "auto");
      model.disabled = busy || loading || Boolean(catalogError) || locked || stale;
      effort.setDisabled(model.disabled || !available);
      save.disabled = busy || loading || locked || stale || !available || !effort.value || !changed;
      cancel.disabled = busy;
      reload.hidden = !stale;
      reload.disabled = busy;
      retry.hidden = !catalogError;
      retry.disabled = loading || busy;
      const message = busy ? "正在保存…" : locked ? "当前会议状态下无法更改席位。" :
        stale ? "这个席位已更新。读取最新设置后可以重新选择。" :
        loading ? "正在读取模型目录…" : catalogError || failure;
      if (status.textContent !== message) status.textContent = message;
      status.toggleAttribute("data-error", !busy && Boolean(failure || catalogError || stale));
      const nextImpact = model.value && model.value !== original.model
        ? "新模型将在该席下次发言时读取共享的公开记录和议题板，并开启自己的会话。原模型的私有上下文留在原会话。"
        : changed && effort.value ? "新的思考程度将在该席下次发言时生效。" : "";
      if (impact.textContent !== nextImpact) impact.textContent = nextImpact;
      impact.hidden = !nextImpact;
    }

    function paintEfforts(desired) {
      effort.setOptions(catalog.get(model.value)?.efforts, desired);
    }

    function paintModels() {
      const options = [...catalog.values()].map(item => new Option(
        item.label && item.label !== item.id ? `${item.label} · ${item.id}` : item.id, item.id,
      ));
      if (!catalog.has(original.model)) options.unshift(new Option(
        original.model ? `${original.model}（当前型号）` : "选择可用模型", original.model,
      ));
      model.replaceChildren(...options);
      model.value = original.model;
      paintEfforts(original.effort || "auto");
      buttons();
    }

    async function refresh() {
      const token = ++generation;
      loading = true;
      catalogError = "";
      buttons();
      try {
        const result = await loadModels();
        if (token !== generation || !dialog.open) return;
        catalog = new Map((result.models || []).filter(item => item.id).map(item => [item.id, item]));
        if (!catalog.size) catalogError = "模型目录暂无可用选项。";
      } catch (_) {
        if (token !== generation || !dialog.open) return;
        catalog = new Map();
        catalogError = "暂时无法读取模型目录。";
      } finally {
        if (token === generation && dialog.open) {
          loading = false;
          paintModels();
        }
      }
    }

    function update(session, writing = false) {
      appBusy = writing;
      if (!dialog.open) return;
      if (session?.id !== current?.id) {
        dialog.close();
        return;
      }
      current = session;
      buttons();
    }

    function open(session, id, trigger) {
      if (!canEdit(session) || appBusy || dialog.open) return false;
      const member = membersOf(session).find(item => item.id === id);
      if (!member) return false;
      current = session;
      original = {...member};
      opener = trigger;
      failure = "";
      catalogError = "";
      catalog = new Map();
      seat.textContent = displayName(id, session);
      paintModels();
      dialog.showModal();
      refresh();
      return true;
    }

    model.addEventListener("change", () => {
      failure = "";
      paintEfforts(effort.value);
      buttons();
    });
    retry.addEventListener("click", refresh);
    reload.addEventListener("click", () => {
      const next = latestMember();
      if (!next) return;
      original = {...next};
      seat.textContent = displayName(next.id, current);
      failure = "";
      paintModels();
      model.focus();
    });
    cancel.addEventListener("click", () => dialog.close());
    dialog.addEventListener("cancel", event => { if (busy) event.preventDefault(); });
    dialog.addEventListener("close", () => {
      generation++;
      busy = loading = false;
      const focus = opener?.isConnected ? opener : document.getElementById(opener?.id);
      focus?.focus({preventScroll:true});
      opener = null;
      current = original = null;
    });
    form.addEventListener("submit", async event => {
      event.preventDefault();
      if (save.disabled || !dialog.open) return;
      const id = current.id;
      const token = generation;
      const payload = {seat_id:original.id, model:model.value, effort:effort.value, expected_version:original.version || 0};
      busy = true;
      buttons();
      try {
        const session = await write(id, payload);
        if (token !== generation || !dialog.open) return;
        acceptSession(session);
        dialog.close();
      } catch (error) {
        if (token !== generation || !dialog.open) return;
        if (error.session?.id === id) acceptSession(error.session);
        failure = error.message || "席位更改未保存。";
      } finally {
        if (token === generation && dialog.open) {
          busy = false;
          buttons();
        }
      }
    });
    return {open, update};
  }

  window.RoundtableMemberEditor = Object.freeze({mount, canEdit});
})();
