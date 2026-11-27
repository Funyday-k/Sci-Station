"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const presetCards = [
    ["work", "项目协作", "接续工作，复核改动", '<path d="M14 20h17m11-1 10-7m-10 9 10 8m10-16 10 6m-10 9 10-7"/><rect x="4" y="15" width="11" height="10" rx="2"/><rect x="30" y="15" width="12" height="10" rx="2"/><circle cx="57" cy="10" r="4"/><circle cx="57" cy="30" r="4"/><rect x="72" y="15" width="12" height="10" rx="2"/>'],
    ["review", "方案评审", "提出方案，检验异议", '<rect x="8" y="7" width="29" height="26" rx="3"/><path d="M14 14h15m-15 6h11m-11 6h8m18-6h9"/><circle cx="58" cy="18" r="10"/><path d="m65 26 8 7m-19-15 3 3 5-6"/>'],
    ["prioritize", "优先级排序", "比较标准，排列次序", '<circle cx="12" cy="10" r="2"/><circle cx="12" cy="20" r="2"/><circle cx="12" cy="30" r="2"/><path d="M19 10h48M19 20h34M19 30h18m39-22v23m-5-5 5 5 5-5"/>'],
    ["forum", "多方权衡", "比较立场，保留分歧", '<path d="m22 10 20 7m-20 13 20-7m-1-15 4 6m7 6 17-2m-18 6 14 7"/><circle cx="17" cy="8" r="5"/><circle cx="17" cy="32" r="5"/><circle cx="38" cy="6" r="3"/><circle cx="47" cy="20" r="6"/><circle cx="75" cy="17" r="5"/><circle cx="70" cy="33" r="3"/>'],
  ];
  const effortNames = {auto:"自动",minimal:"极低",low:"低",medium:"中",high:"高",xhigh:"极高",max:"最大",ultra:"超高",none:"无"};
  const effortName = (value) => Object.hasOwn(effortNames, value) ? effortNames[value] : value;
  const make = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };
  function mount({api, assetFor, storageGet, storageSet, materials, onRosterChange}) {
    const form = $("create-form");
    const continuous = window.RoundtableContinuous.mount("create", {storageGet, storageSet});
    const draftsKey = "studio.setup-drafts.v1";
    let drafts = {};
    try {
      const stored = JSON.parse(storageGet(draftsKey) || "{}");
      if (stored && typeof stored === "object" && !Array.isArray(stored)) drafts = stored;
    } catch (_) {}
    let draftKey = null, scope = null, members = [], preset = "work", selectionTouched = false;
    let lastDraftSeat = 0;
    let models = [], modelIndex = new Map(), defaultModel = "", loading = false, issue = "", writing = false;
    let request = 0, directoryLoaded = false, directoryRequest = null;


    function save() {
      if (draftKey === null) return;
      drafts[draftKey] = {topic: $("new-topic").value, members, preset, selectionTouched, lastDraftSeat};
      const attachments = materials?.ready() || [];
      if (attachments.length) {
        drafts[draftKey].materials = attachments.map(({id, name, mime, size, read_status}) => ({
          id, name, mime, size, read_status,
        }));
      }
      storageSet(draftsKey, JSON.stringify(drafts));
    }
    function mentionMembers() {
      if (draftKey === null) return [];
      return members.map(({model, label, draftSeat}) => ({
        id: "seat-" + draftSeat,
        label: `${label || modelIndex.get(model)?.label || model} · 席位 ${draftSeat}`,
        model,
      }));
    }
    function setDirectory(open) {
      $("member-directory").hidden = !open;
      $("member-picker").setAttribute("aria-expanded", String(open));
      if (open) $("member-search").focus({preventScroll:true});
    }
    function validMember(member) {
      const model = modelIndex.get(member.model);
      return !!model && (member.effort === "auto" || model.efforts?.includes(member.effort));
    }
    function canSubmit() {
      return draftKey !== null && !loading && !issue && members.length > 0 &&
        members.every(validMember) && !materials?.busy() && !materials?.failed();
    }
    function paintStatus() {
      const unavailable = members.some(member => !validMember(member));
      $("member-status").textContent = loading ? "正在读取模型…" : issue ||
        (unavailable ? "已选型号或思考程度已下线，请调整成员。" : members.length ? "" : "请选择至少一位成员。");
      $("retry-members").hidden = loading || !issue;
      $("create-submit").disabled = writing || !canSubmit();
    }
    function setBusy(busy) {
      writing = busy;
      form.inert = busy;
      form.setAttribute("aria-busy", String(busy));
      materials?.setDisabled(busy);
      $("create-submit").textContent = busy ? "正在创建…" : "创建圆桌";
      paintStatus();
    }
    function modelIcon(source) {
      const src = assetFor(source);
      if (src) { const img = make("img", "model-source-icon"); img.src = src; img.alt = ""; return img; }
      const tile = make("span", "model-source-icon neutral-model");
      tile.setAttribute("aria-hidden", "true");
      tile.innerHTML = window.RoundtableIcons.icon("model");
      return tile;
    }
    const seatingPlan = window.RoundtableSeating.mount(assetFor);
    function paintMembers(changedMember) {
      seatingPlan.render(members, modelIndex, changedMember);
      const rows = members.map((member, index) => {
        const model = modelIndex.get(member.model);
        const name = model?.label || member.label || member.model;
        const source = model?.source || member.source || "";
        const row = make("div", "chosen-member");
        row.addEventListener("pointerenter", () => seatingPlan.highlight(member));
        row.addEventListener("pointerleave", () => seatingPlan.highlight(null));
        row.addEventListener("focusin", () => seatingPlan.reveal(member));
        row.addEventListener("focusout", () => seatingPlan.highlight(null));
        row.append(modelIcon(source));
        const identity = make("div", "chosen-identity");
        const picker = make("select", "chosen-model-select");
        picker.setAttribute("aria-label", `第 ${index + 1} 席的模型`);
        if (!model) picker.add(new Option(name, member.model));
        for (const candidate of models)
          picker.add(new Option(candidate.label || candidate.id, candidate.id));
        picker.value = member.model;
        picker.disabled = !models.length;
        picker.addEventListener("change", () => {
          const candidate = modelIndex.get(picker.value);
          if (!candidate) return;
          const efforts = candidate.efforts || [];
          member.model = candidate.id;
          member.label = candidate.label;
          member.source = candidate.source;
          member.effort = efforts.includes(member.effort) ? member.effort :
            efforts.includes("auto") ? "auto" : efforts[0] || "auto";
          selectionTouched = true;
          save();
          paintMembers(member);
          paintOptions();
          $("chosen-members").children[index]?.querySelector(".chosen-model-select").focus({preventScroll:true});
        });
        identity.append(picker);
        if (member.model !== name) identity.append(make("span", "model-source", member.model));
        identity.title = member.model;
        row.append(identity);
        if (index === 0) row.append(make("span", "chief-label", "首席"));
        else {
          const chief = make("button", "text-button make-chief", "设为首席");
          chief.type = "button"; chief.setAttribute("aria-label", "设 " + name + " 为首席");
          chief.addEventListener("click", () => {
            members.unshift(members.splice(index, 1)[0]); selectionTouched = true; save(); paintMembers(member);
          });
          row.append(chief);
        }
        const level = make("label", "effort-field");
        level.append(make("span", "", "思考"));
        const select = make("select");
        select.setAttribute("aria-label", name + " 的思考程度");
        const values = [...new Set(["auto", ...(model?.efforts || []), member.effort])];
        for (const value of values) select.add(new Option(effortName(value), value));
        select.value = member.effort;
        select.disabled = values.length === 1 || !model;
        select.addEventListener("change", () => { member.effort = select.value; selectionTouched = true; save(); paintStatus(); });
        level.append(select); row.append(level);
        const duplicate = make("button", "icon-button duplicate-member");
        duplicate.type = "button";
        duplicate.title = "复制席位";
        duplicate.setAttribute("aria-label", "复制 " + name + " 的席位");
        duplicate.innerHTML = window.RoundtableIcons.icon("copy");
        duplicate.addEventListener("click", () => {
          members.splice(index + 1, 0, {...member, draftSeat: ++lastDraftSeat});
          selectionTouched = true;
          save();
          paintMembers(members[index + 1]);
          const row = $("chosen-members").children[index + 1];
          const effort = row.querySelector(".effort-field select");
          (effort.disabled ? row.querySelector(".duplicate-member") : effort).focus({preventScroll:true});
        });
        row.append(duplicate);
        const remove = make("button", "icon-button remove-member");
        remove.innerHTML = window.RoundtableIcons.icon("close");
        remove.type = "button"; remove.title = "移除 " + name; remove.setAttribute("aria-label", remove.title);
        remove.addEventListener("click", () => {
          selectionTouched = true; members.splice(index, 1); save(); paintMembers(members[index] || members[index - 1]); paintOptions();
        });
        row.append(remove);
        return row;
      });
      const list = $("chosen-members");
      list.replaceChildren(...rows);
      const selectedRow = rows[members.indexOf(changedMember)];
      if (selectedRow && list.scrollHeight > list.clientHeight) {
        const viewport = list.getBoundingClientRect();
        const target = selectedRow.getBoundingClientRect();
        if (target.bottom > viewport.bottom) list.scrollTop += target.bottom - viewport.bottom;
        else if (target.top < viewport.top) list.scrollTop += target.top - viewport.top;
      }
      paintStatus();
      onRosterChange?.();
    }
    function paintOptions() {
      const query = $("member-search").value.trim().toLocaleLowerCase(), source = $("member-source").value;
      const results = models.filter(model => (!source || model.source === source) &&
        (!query || [model.id, model.label, model.source].join(" ").toLocaleLowerCase().includes(query)));
      const rows = results.map(model => {
        const label = make("label", "model-option");
        const input = make("input"); input.type = "checkbox"; input.value = model.id;
        input.checked = members.some(member => member.model === model.id);
        input.addEventListener("change", () => {
          selectionTouched = true;
          if (input.checked) members.push(createMember(model));
          else members = members.filter(member => member.model !== model.id);
          save(); paintMembers(input.checked ? members.at(-1) : null);
        });
        label.append(input, modelIcon(model.source), make("strong", "", model.label || model.id), make("span", "model-source", model.source));
        label.title = model.id;
        return label;
      });
      if (!rows.length) rows.push(make("p", "directory-empty", loading ? "正在读取…" : issue ? "目录暂不可用" : "没有匹配的型号"));
      $("member-options").replaceChildren(...rows);
    }
    function selectDefault() {
      if (selectionTouched || members.length || !modelIndex.has(defaultModel)) return;
      members = [createMember(modelIndex.get(defaultModel))];
    }
    function createMember(model) {
      return {model: model.id, effort: "auto", label: model.label, source: model.source, draftSeat: ++lastDraftSeat};
    }
    function restoreMembers(saved, previousSeat) {
      const old = Array.isArray(saved) ? saved.filter(member => typeof member?.model === "string") : [];
      const valid = number => Number.isSafeInteger(number) && number > 0 && number < 1e9;
      const seen = new Set();
      lastDraftSeat = old.reduce((last, member) => valid(member.draftSeat) ? Math.max(last, member.draftSeat) : last,
        valid(previousSeat) ? previousSeat : 0);
      return old.map(member => {
        const draftSeat = valid(member.draftSeat) && !seen.has(member.draftSeat) ? member.draftSeat : ++lastDraftSeat;
        seen.add(draftSeat);
        return {...member, effort: member.effort || "auto", draftSeat};
      });
    }
    function refresh() {
      directoryRequest = readModelDirectory();
      return directoryRequest;
    }
    async function readModelDirectory() {
      const current = ++request;
      loading = true; issue = ""; paintStatus(); paintOptions();
      try {
        const result = await api("/models");
        if (current !== request) return;
        models = (result.models || []).filter(model => model && typeof model.id === "string");
        defaultModel = result.default_model || "";
        directoryLoaded = true;
        if (!models.length) issue = "模型目录中暂无可用型号。";
      } catch (error) {
        if (current !== request) return;
        models = []; defaultModel = ""; directoryLoaded = false;
        issue = "无法读取模型目录。" + (error.message || "");
      } finally {
        if (current === request) {
          loading = false; modelIndex = new Map(models.map(model => [model.id, model]));
          const filter = $("member-source"), old = filter.value;
          const sources = [...new Set(models.map(model => model.source).filter(Boolean))].sort();
          filter.replaceChildren(new Option("所有来源", ""), ...sources.map(source => new Option(source, source)));
          filter.value = sources.includes(old) ? old : "";
          selectDefault(); paintOptions(); paintMembers();
        }
      }
    }
    async function applyLabPreset(mode, count, stillCurrent = () => true) {
      if (!draftKey || writing || !["review","forum","prioritize"].includes(mode)) return false;
      const key = draftKey, seats = Number(count);
      if (!Number.isInteger(seats) || seats < 1 || seats > 4) return false;
      const previousPreset = preset;
      if (!directoryLoaded) await (loading && directoryRequest ? directoryRequest : refresh());
      if (draftKey !== key || writing || preset !== previousPreset || !models.length || !stillCurrent()) return false;
      preset = mode;
      $("preset-" + mode).checked = true;
      const roster = members.filter(validMember).slice(0, seats);
      const preferred = modelIndex.get(defaultModel) || models[0];
      while (roster.length < seats) {
        const available = models.find(candidate => !roster.some(member => member.model === candidate.id));
        roster.push(createMember(roster.length ? available || modelIndex.get(roster[0].model) : preferred));
      }
      members = roster;
      selectionTouched = true;
      save(); paintOptions(); paintMembers();
      return true;
    }
    function open(project) {
      const key = project.id || project.path;
      if (draftKey === key) return;
      save();
      draftKey = key;
      scope = project.global ? {scope: "global"} :
        (project.id ? {project_id: project.id} : {project: project.path});
      $("create-project-access").textContent = project.global
        ? (window.SciStationI18n?.text("此会话无项目文件权限", "This session has no project file access") ?? "此会话无项目文件权限")
        : (window.SciStationI18n?.text("讨论仅读取项目文件", "Discussion has read-only access to project files") ?? "讨论仅读取项目文件");
      continuous.open(key);
      const draft = drafts[key] || {};
      members = restoreMembers(draft.members, draft.lastDraftSeat);
      preset = presetCards.some(([id]) => id === draft.preset) ? draft.preset : "work";
      selectionTouched = !!draft.selectionTouched;
      $("new-topic").value = typeof draft.topic === "string" ? draft.topic : "";
      materials?.set(draft.materials);
      $("preset-" + preset).checked = true;
      $("member-search").value = ""; $("member-source").value = "";
      setDirectory(false); selectDefault(); paintOptions(); paintMembers();
      if (!directoryLoaded && !loading) refresh();
    }
    function suspend() {
      save();
      draftKey = null;
      materials?.reset();
      onRosterChange?.();
      setDirectory(false);
    }
    function complete() {
      if (draftKey !== null) {
        delete drafts[draftKey]; storageSet(draftsKey, JSON.stringify(drafts));
      }
      continuous.complete();
      draftKey = null;
      materials?.reset();
      onRosterChange?.();
      setDirectory(false);
    }
    function payload(target = "") {
      const chief = members.find(member => target === "seat-" + member.draftSeat);
      const roster = chief ? [chief, ...members.filter(member => member !== chief)] : members;
      const result = {...scope, members:roster.map(({model,effort}) => ({model,effort})), preset};
      const attachments = materials?.ready() || [];
      if (attachments.length) result.material_ids = attachments.map(item => item.id);
      const configured = continuous.payload($("new-topic").value);
      if (configured) result.continuous = configured;
      return result;
    }
    for (const [id, title, caption, drawing] of presetCards) {
      const label = make("label", "preset-card");
      const input = make("input"); input.type = "radio"; input.name = "create-preset"; input.value = id; input.id = "preset-" + id;
      const art = make("span", "preset-figure");
      art.innerHTML = '<svg viewBox="0 0 90 40" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + drawing + "</svg>";
      label.title = caption;
      label.append(input, art, make("strong", "", title), make("span", "sr-only", caption));
      input.addEventListener("change", () => { preset = id; save(); });
      $("preset-options").append(label);
    }
    $("new-topic").addEventListener("input", save);
    $("member-picker").addEventListener("click", () => {
      const show = $("member-directory").hidden;
      setDirectory(show);
      if (show) refresh();
    });
    $("member-search").addEventListener("input", paintOptions);
    $("member-source").addEventListener("change", paintOptions);
    $("retry-members").addEventListener("click", refresh);
    form.addEventListener("keydown", event => {
      if (event.key === "Escape" && !$("member-directory").hidden) {
        event.stopPropagation(); event.preventDefault(); setDirectory(false); $("member-picker").focus();
      }
    });
    window.addEventListener("roundtable:models-changed", () => {
      directoryLoaded = false;
      if (!$("table-view").hidden && !form.hidden) refresh();
    });
    return { open, suspend, complete, setBusy, payload, canSubmit, mentionMembers, applyLabPreset,
      materialsChanged() { save(); paintStatus(); },
      resume:() => { if (!directoryLoaded && !loading) refresh(); } };
  }
  window.RoundtableSetup = Object.freeze({mount, effortName});
})();
