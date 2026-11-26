(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  if (!$("prompt-editor")) return;
  const endpoint = "/api/studio/prompt-settings";
  const dialog = $("prompt-patch-review");
  const text = (zh, en) => document.documentElement.lang === "en" ? en : zh;
  let library = null;
  let pending = null;
  let busy = false;

  async function request(suffix = "", body) {
    const init = {headers: {"X-Roundtable": "1"}, cache: "no-store"};
    if (body !== undefined) {
      init.method = "POST";
      init.headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(body);
    }
    const response = await fetch(endpoint + suffix, init);
    const data = await response.json();
    if (!response.ok) throw Object.assign(Error(data.error), {status: response.status});
    return data;
  }

  function loadDraft() {
    const saved = library.templates.find(item => item.id === $("prompt-template").value);
    $("prompt-title").value = saved?.title || "";
    $("prompt-description").value = saved?.description || "";
    $("prompt-system").value = saved?.system || "";
    $("prompt-body").value = saved?.body || "";
    $("prompt-enabled").checked = saved?.enabled ?? true;
    $("prompt-active").checked = saved?.active ?? false;
    $("prompt-active").disabled = !$("prompt-enabled").checked;
    $("prompt-remove").disabled = !saved;
  }

  function render(selection) {
    const choices = library.templates.filter(item => item.surface === $("prompt-surface").value);
    $("prompt-template").replaceChildren(new Option(text("新建模板", "New template"), ""),
      ...choices.map(item => new Option(item.title + (item.active ? text(" · 正在使用", " · Active") : ""), item.id)));
    const preferred = selection ?? choices.find(item => item.active)?.id ?? choices[0]?.id ?? "";
    $("prompt-template").value = choices.some(item => item.id === preferred) ? preferred : "";
    $("prompt-restore").disabled = !choices.some(item => item.active);
    loadDraft();
  }

  async function load() {
    try {
      library = await request();
      render();
      $("prompt-editor").disabled = false;
    } catch (error) {
      $("prompt-status").textContent = error.message;
    }
  }

  function versionBlock(title, item) {
    const block = document.createElement("div");
    const heading = document.createElement("h4");
    heading.textContent = title;
    const body = document.createElement("pre");
    body.textContent = !item ? text("无模板", "No template") : [
      item.title, item.description, "v" + item.version,
      item.active ? text("正在使用", "Active") : item.enabled ? text("已启用", "Enabled") : text("已停用", "Disabled"),
      item.system, item.body,
    ].filter(Boolean).join("\n\n");
    block.append(heading, body);
    return block;
  }

  async function preview(action) {
    if (busy || pending) return;
    busy = true;
    $("prompt-status").textContent = "";
    try {
      const select = $("prompt-surface");
      const draft = {
        id: $("prompt-template").value, surface: select.value, title: $("prompt-title").value,
        description: $("prompt-description").value, system: $("prompt-system").value,
        body: $("prompt-body").value, enabled: $("prompt-enabled").checked, active: $("prompt-active").checked,
      };
      pending = await request("/preview", {revision: library.revision, action, template: draft});
      $("prompt-patch-reason").textContent = pending.source + " · " + pending.rationale;
      $("prompt-patch-scope").textContent = text("影响范围 · ", "Applies to · ") + select.selectedOptions[0].textContent;
      $("prompt-patch-status").textContent = "";
      $("prompt-patch-changes").replaceChildren(...pending.changes.map(change => {
        const row = document.createElement("section");
        row.className = "prompt-patch-versions";
        row.append(versionBlock(text("保存前", "Before"), change.before),
          versionBlock(text("应用后", "After"), change.after));
        return row;
      }));
      dialog.showModal();
    } catch (error) {
      $("prompt-status").textContent = error.message;
    } finally {
      busy = false;
    }
  }

  async function decide(action) {
    if (!pending || busy) return;
    busy = true;
    $("prompt-patch-apply").disabled = $("prompt-patch-discard").disabled = true;
    try {
      const observed = pending;
      library = await request("/decision", {id: observed.id, action});
      if (action === "apply") {
        const selected = observed.changes.find(change => change.after?.active)?.after
          ?? observed.changes.findLast(change => change.after)?.after;
        render(selected?.id);
      }
      $("prompt-status").textContent = action === "apply" ? text("提示词已保存", "Prompt saved") : text("已拒绝提案", "Proposal rejected");
      pending = null;
      dialog.close();
    } catch (error) {
      if (error.status === 409) {
        pending = null;
        dialog.close();
        await load();
        $("prompt-status").textContent = error.message;
      } else {
        $("prompt-patch-status").textContent = error.message;
      }
    } finally {
      busy = false;
      $("prompt-patch-apply").disabled = $("prompt-patch-discard").disabled = false;
    }
  }

  window.addEventListener("roundtable:settings-page", event => {
    if (event.detail === "prompts" && !library) void load();
  });
  $("prompt-surface").addEventListener("change", () => render());
  $("prompt-template").addEventListener("change", loadDraft);
  $("prompt-enabled").addEventListener("change", () => {
    $("prompt-active").disabled = !$("prompt-enabled").checked;
    if ($("prompt-active").disabled) $("prompt-active").checked = false;
  });
  for (const [id, action] of [["prompt-preview", "edit"], ["prompt-suggest", "suggest"], ["prompt-restore", "restore"], ["prompt-remove", "remove"]]) {
    $(id).addEventListener("click", () => { void preview(action); });
  }
  $("prompt-patch-discard").addEventListener("click", () => { void decide("discard"); });
  $("prompt-patch-apply").addEventListener("click", () => { void decide("apply"); });
  dialog.addEventListener("cancel", event => { event.preventDefault(); void decide("discard"); });
})();
