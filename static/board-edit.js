"use strict";
(() => {
  const storePrefix = "studio.board-drafts.v1.";
  const delay = 550;
  const fieldLabels = {title: "标题", body: "内容", material_ids: "引用材料"};
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const roomKey = (id, windowId) => `${storePrefix}${encodeURIComponent(id)}.${windowId}`;
  const chars = value => Array.from(value).length;
  const binding = {
    title: {op: "rename_board"},
    agenda: {op: "edit_agenda", id: "item_id"},
    module: {op: "revise_module", id: "module_id"},
    material: {op: "annotate_material", id: "material_id"},
    point: {op: "annotate_point", id: "point_id"},
  };

  function node(tag, className, text) {
    const result = document.createElement(tag);
    if (className) result.className = className;
    if (text) result.textContent = text;
    return result;
  }

  function button(text, listener) {
    const result = node("button", "board-action", text);
    result.type = "button";
    result.addEventListener("click", listener);
    return result;
  }

  function record(session, spec) {
    if (spec.type === "title") return session.board?.title ? session.board : {
      title: session.title || Array.from(session.topic || "").slice(0, 80).join("") || "共享议题板",
    };
    if (spec.type === "agenda") return session.agenda?.find(item => item.id === spec.id);
    if (spec.type === "module") return session.board?.modules?.find(item => item.id === spec.id);
    const annotations = spec.type === "point" ? session.board?.point_annotations : session.board?.material_annotations;
    return annotations?.[spec.id] || {};
  }

  function valuesFor(spec, source) {
    return Object.fromEntries(Object.keys(spec.fields).map(field => [
      field, source?.[field] ?? (field === "material_ids" ? [] : ""),
    ]));
  }

  function normalized(value) {
    return typeof value === "string" ? value.trim() : value;
  }

  function changes(draft) {
    return Object.fromEntries(Object.entries(draft.values)
      .map(([field, value]) => [field, normalized(value)])
      .filter(([field, value]) => !same(value, draft.base[field]) || draft.uncertain?.includes(field)));
  }

  function dirty(draft) {
    return Object.keys(changes(draft)).length > 0;
  }

  function validate(spec, values) {
    for (const [field, limit] of Object.entries(spec.fields)) {
      const value = normalized(values[field]);
      const label = spec.labels?.[field] || fieldLabels[field];
      if ((field === "title" || (field === "body" && spec.kind === "note")) && !value) return `请填写${label}`;
      if (field === "material_ids" && value.length > limit) return `最多引用 ${limit} 份材料`;
      if (typeof value === "string" && chars(value) > limit) return `${label}最多 ${limit} 字`;
    }
    if (spec.kind === "materials" && normalized(values.body) && !values.material_ids.length)
      return "请为审阅内容选择引用材料";
    return "";
  }

  function browserWindowId() {
    const key = storePrefix + "window";
    const fresh = globalThis.crypto.randomUUID();
    try {
      const id = sessionStorage.getItem(key) || fresh;
      sessionStorage.setItem(key, id);
      return id;
    } catch (_) {
      return fresh;
    }
  }

  function rootState(id, windowId) {
    let saved = {};
    let recoveredKey = "";
    try {
      const key = roomKey(id, windowId);
      const own = JSON.parse(sessionStorage.getItem(key) || localStorage.getItem(key) || "null");
      if (own) saved = own.drafts;
      else {
        const prefix = roomKey(id, "");
        const available = Object.keys(localStorage).filter(candidate => candidate.startsWith(prefix))
          .map(candidate => [candidate, JSON.parse(localStorage.getItem(candidate))])
          .filter(([, value]) => value?.archived)
          .sort((a, b) => b[1].at - a[1].at);
        if (available.length) {
          recoveredKey = available[0][0];
          saved = available[0][1].drafts;
        }
      }
    } catch (_) {}
    return {
      id, session: null, open: "", noteId: "", recoveredKey, views: new Map(),
      drafts: new Map(Object.entries(saved).filter(([, value]) => value?.spec && value?.base && value?.values)),
    };
  }

  function snapshotIsOlder(current, incoming) {
    if (!current?.updated_at || !incoming?.updated_at) return false;
    const sortable = stamp => stamp.replace(/(?:\.(\d+))?Z$/, (_, fraction = "") => "." + fraction.padEnd(9, "0") + "Z");
    return sortable(incoming.updated_at) < sortable(current.updated_at);
  }

  function mount({root, write, onChange, repaint}) {
    const rooms = new Map();
    const windowId = browserWindowId();
    let active = null;
    let archived = false;

    function persist(room) {
      const pending = Object.fromEntries([...room.drafts].filter(([, draft]) => dirty(draft)).map(([key, draft]) => [
        key, {spec: draft.spec, values: draft.values, base: draft.base, version: draft.version, uncertain: draft.uncertain},
      ]));
      const key = roomKey(room.id, windowId);
      const data = Object.keys(pending).length ? JSON.stringify({drafts: pending, archived, at: Date.now()}) : "";
      try {
        if (data) sessionStorage.setItem(key, data);
        else sessionStorage.removeItem(key);
      } catch (_) {}
      try {
        if (data) localStorage.setItem(key, data);
        else localStorage.removeItem(key);
        if (room.recoveredKey) {
          localStorage.removeItem(room.recoveredKey);
          room.recoveredKey = "";
        }
      } catch (_) {}
    }

    window.addEventListener("pagehide", () => {
      archived = true;
      for (const room of rooms.values()) {
        for (const key of room.drafts.keys()) void save(room, key);
        persist(room);
      }
    });
    window.addEventListener("pageshow", () => {
      if (!archived) return;
      archived = false;
      for (const room of rooms.values()) persist(room);
    });

    function serverValue(room, draft) {
      const source = record(room.session, draft.spec);
      return {values: valuesFor(draft.spec, source), version: source?.version || 0, exists: Boolean(source)};
    }

    function reconcile(room, draft) {
      if (draft.request || draft.composing) return;
      const latest = serverValue(room, draft);
      if (latest.version === draft.version && same(latest.values, draft.base)) return;
      const local = changes(draft);
      draft.conflict = Object.keys(local).filter(field =>
        !same(draft.base[field], latest.values[field]) && !same(local[field], latest.values[field]));
      if (draft.conflict.length) return;
      for (const field of Object.keys(draft.values)) {
        if (!Object.hasOwn(local, field) || same(local[field], latest.values[field]))
          draft.values[field] = latest.values[field];
      }
      draft.base = latest.values;
      draft.version = latest.version;
      draft.uncertain = draft.uncertain?.filter(field => !same(draft.values[field], latest.values[field]));
      if (!Object.keys(changes(draft)).length) {
        draft.error = "";
      }
    }

    function sync(session) {
      if (!active || active.id !== session.id) {
        leave();
        if (!rooms.has(session.id)) rooms.set(session.id, rootState(session.id, windowId));
        active = rooms.get(session.id);
      }
      if (snapshotIsOlder(active.session, session)) return;
      active.session = session;
      for (const [key, draft] of active.drafts) {
        reconcile(active, draft);
        paint(active, key);
      }
      persist(active);
    }

    function openView(room, spec, view) {
      if (room.open && room.open !== spec.key) close(room, room.open, {focus: false});
      if (room.open && room.open !== spec.key) return;
      view = room.views.get(spec.key) || view;
      let draft = room.drafts.get(spec.key);
      if (!draft) {
        const server = serverValue(room, {spec});
        draft = {spec, base: server.values, values: {...server.values}, version: server.version};
        room.drafts.set(spec.key, draft);
      }
      room.open = spec.key;
      room.views.set(spec.key, view);
      reconcile(room, draft);
      paint(room, spec.key);
      view.inputs.get(Object.keys(spec.fields)[0])?.focus();
      if (!draft.error) schedule(room, spec.key);
    }

    function close(room, key, {focus = true, savePending = true} = {}) {
      const draft = room.drafts.get(key);
      if (draft?.composing) return;
      room.open = "";
      if (draft) draft.finish = false;
      paint(room, key);
      if (focus) room.views.get(key)?.trigger.focus({preventScroll: true});
      if (!draft || !dirty(draft)) {
        if (!draft?.request) room.drafts.delete(key);
      } else if (savePending && !draft.request && !draft.error && !draft.conflict?.length) {
        void save(room, key);
      }
      persist(room);
      if (active === room) repaint();
    }

    function leave() {
      if (!active) return;
      const room = active;
      active = null;
      if (room.open) {
        const open = room.drafts.get(room.open);
        const savePending = !open?.composing;
        if (open) open.composing = false;
        close(room, room.open, {focus: false, savePending});
      }
      room.views.clear();
      persist(room);
    }

    function schedule(room, key) {
      const draft = room.drafts.get(key);
      clearTimeout(draft.timer);
      if (dirty(draft) && !draft.composing && !draft.request && !draft.conflict?.length) {
        draft.timer = setTimeout(() => void save(room, key), delay);
      }
    }

    function input(room, key, field, value) {
      const draft = room.drafts.get(key);
      draft.values[field] = value;
      draft.error = "";
      draft.saved = false;
      persist(room);
      paint(room, key);
      schedule(room, key);
    }

    function makePayload(room, draft) {
      const {spec} = draft;
      if (spec.newNote && !serverValue(room, draft).exists)
        return {op: "add_note", module_id: spec.id, ...Object.fromEntries(Object.entries(draft.values)
          .map(([field, value]) => [field, normalized(value)]))};
      const operation = binding[spec.type];
      const payload = {op: operation.op, expected_version: draft.version, ...changes(draft)};
      if (operation.id) payload[operation.id] = spec.id;
      return payload;
    }

    function publish(room, result) {
      if (snapshotIsOlder(room.session, result)) return;
      room.session = result;
      if (active === room) onChange(result);
    }

    async function send(room, draft, payload, sent) {
      const {key} = draft.spec;
      let rejectedVersion;
      try {
        const result = await write(room.id, payload);
        if (!result || result.id !== room.id) throw new Error("无法读取保存结果");
        const source = record(result, draft.spec);
        const next = valuesFor(draft.spec, source);
        for (const field of Object.keys(draft.values)) {
          if (same(draft.values[field], sent[field])) draft.values[field] = next[field];
        }
        draft.base = next;
        draft.version = source?.version || 0;
        draft.uncertain = undefined;
        draft.saved = true;
        publish(room, result);
      } catch (error) {
        if (error.status === 409 && error.session?.id === room.id) {
          rejectedVersion = draft.version;
          publish(room, error.session);
        } else {
          draft.error = error.status === 400 ? error.message : "保存失败，草稿已保留";
          if (error.status >= 400 && error.status < 500) draft.uncertain = undefined;
        }
      } finally {
        draft.request = null;
        reconcile(room, draft);
        if (rejectedVersion === draft.version && dirty(draft) && !draft.conflict?.length)
          draft.error = "此处暂时无法保存，草稿已保留";
        persist(room);
        paint(room, key);
        if (!draft.error && !draft.conflict?.length && dirty(draft)) schedule(room, key);
        if (!draft.error && !dirty(draft) && draft.finish && room.open === key) close(room, key);
        else if (room.open !== key && !dirty(draft)) {
          room.drafts.delete(key);
          if (active === room) repaint();
        }
      }
    }

    function save(room, key) {
      const draft = room.drafts.get(key);
      if (!draft) return;
      clearTimeout(draft.timer);
      if (draft.request) return draft.request;
      if (!dirty(draft) || draft.composing || draft.conflict?.length || draft.error ||
          room.session.status === "closed" || validate(draft.spec, draft.values)) return;
      const payload = makePayload(room, draft);
      const sent = {...draft.values};
      // Set the request before dispatch so refreshes can distinguish a pending acknowledgement.
      draft.request = Promise.resolve().then(() => send(room, draft, payload, sent));
      draft.uncertain = Object.keys(draft.values).filter(field => Object.hasOwn(payload, field));
      persist(room);
      paint(room, key);
      return draft.request;
    }

    function accept(room, key, useLocal) {
      const draft = room.drafts.get(key);
      const latest = serverValue(room, draft);
      const local = changes(draft);
      if (!useLocal) for (const field of draft.conflict) delete local[field];
      draft.base = latest.values;
      draft.version = latest.version;
      draft.values = {...latest.values, ...local};
      draft.conflict = [];
      draft.error = "";
      draft.uncertain = undefined;
      draft.saved = false;
      paint(room, key);
      persist(room);
      if (dirty(draft)) void save(room, key);
    }

    function paint(room, key) {
      const view = room.views.get(key);
      if (!view) return;
      const draft = room.drafts.get(key);
      const open = room.open === key;
      const hasDraft = Boolean(draft && dirty(draft));
      view.trigger.textContent = hasDraft && !open ? `${view.label} · 草稿` : view.label;
      view.trigger.toggleAttribute("data-draft", hasDraft);
      view.trigger.setAttribute("aria-expanded", String(open));
      view.form.hidden = !open;
      if (!open || !draft) return;
      if (!draft.composing) for (const [field, control] of view.inputs) {
        if (field === "material_ids") {
          for (const check of control.querySelectorAll("input")) check.checked = draft.values[field].includes(check.value);
        } else if (control.value !== draft.values[field]) {
          const caretAtEnd = control.selectionEnd === control.value.length;
          const [start, end] = [control.selectionStart, control.selectionEnd];
          control.value = draft.values[field];
          if (control === document.activeElement) {
            const position = control.value.length;
            control.setSelectionRange(caretAtEnd ? position : Math.min(start, position), caretAtEnd ? position : Math.min(end, position));
          }
        }
      }
      const conflict = draft.conflict?.length > 0;
      const closed = room.session.status === "closed";
      const validation = hasDraft && !draft.composing ? validate(draft.spec, draft.values) : "";
      const status = draft.composing ? "" : closed ? "会议已结束，草稿已保留" : conflict ? "此处已更新，请选择要保留的内容" :
        draft.error || validation || (draft.request ? "正在保存…" : hasDraft ? "等待保存…" : draft.saved ? "已保存" : "");
      if (view.status.textContent !== status) view.status.textContent = status;
      view.status.dataset.state = conflict || draft.error || validation || closed ? "alert" : "";
      view.conflict.hidden = !conflict;
      if (conflict) {
        const remote = serverValue(room, draft).values;
        view.remote.replaceChildren(...draft.conflict.map(field => {
          const text = field === "material_ids"
            ? remote[field].map(id => room.session.materials?.find(material => material.id === id)?.name || id).join("、")
            : remote[field];
          const label = draft.spec.labels?.[field] || fieldLabels[field];
          return node("p", "", `服务器${label}：${text || "（空）"}`);
        }));
      }
      view.retry.hidden = !draft.error || closed;
      view.done.disabled = Boolean(conflict || validation || draft.error || (closed && hasDraft) || draft.composing);
      for (const [field, control] of view.inputs) {
        if (field === "material_ids") control.disabled = closed;
        else control.readOnly = closed;
      }
      view.keepLocal.disabled = closed;
    }

    function create(spec) {
      const room = active;
      const isNew = spec.newNote;
      const form = node("form", "board-edit-form");
      form.id = `${root.id}-edit-${spec.type}-${isNew ? "new" : (spec.id || "title")}`;
      form.hidden = true;
      const trigger = button(spec.action || "编辑", () => {
        if (room.open === spec.key) close(room, spec.key);
        else openView(room, spec, view);
      });
      trigger.classList.add("board-edit-trigger");
      trigger.dataset.boardFocus = `edit:${spec.key}`;
      trigger.setAttribute("aria-label", spec.label);
      trigger.setAttribute("aria-controls", form.id);
      trigger.setAttribute("aria-expanded", "false");
      const inputs = new Map();
      for (const field of Object.keys(spec.fields)) {
        const labelText = spec.labels?.[field] || fieldLabels[field];
        if (field === "material_ids") {
          const materials = room.session.materials || [];
          if (!materials.length) continue;
          const group = node("fieldset", "board-edit-materials");
          group.append(node("legend", "", labelText));
          for (const material of materials) {
            const label = node("label");
            const check = node("input");
            check.type = "checkbox";
            check.value = material.id;
            check.addEventListener("change", () => input(room, spec.key, field,
              [...group.querySelectorAll("input:checked")].map(item => item.value)));
            label.append(check, node("span", "", material.name || "会议附件"));
            group.append(label);
          }
          form.append(group);
          inputs.set(field, group);
          continue;
        }
        const label = node("label", "board-edit-field");
        const control = node(field === "body" ? "textarea" : "input");
        if (field === "body") control.rows = 3;
        else control.type = "text";
        label.append(node("span", "", labelText), control);
        form.append(label);
        inputs.set(field, control);
        control.addEventListener("compositionstart", () => {
          const draft = room.drafts.get(spec.key);
          draft.composing = true;
          clearTimeout(draft.timer);
          paint(room, spec.key);
        });
        control.addEventListener("compositionend", () => {
          const draft = room.drafts.get(spec.key);
          draft.composing = false;
          draft.justComposed = true;
          setTimeout(() => { draft.justComposed = false; }, 0);
          input(room, spec.key, field, control.value);
          reconcile(room, draft);
          persist(room);
          paint(room, spec.key);
          schedule(room, spec.key);
        });
        control.addEventListener("input", () => input(room, spec.key, field, control.value));
      }
      const status = node("span", "board-edit-status");
      status.setAttribute("role", "status");
      const remote = node("div", "board-edit-remote");
      const conflict = node("div", "board-edit-conflict");
      conflict.hidden = true;
      const keepServer = button("采用服务器内容", () => accept(room, spec.key, false));
      const keepLocal = button("采用我的修改", () => accept(room, spec.key, true));
      conflict.append(remote, keepServer, keepLocal);
      const retry = button("重试", () => {
        const draft = room.drafts.get(spec.key);
        draft.error = "";
        void save(room, spec.key);
      });
      retry.hidden = true;
      const done = node("button", "board-action board-edit-done", "完成");
      done.type = "submit";
      const footer = node("div", "board-edit-footer");
      footer.append(status, retry, done);
      form.append(footer, conflict);
      form.addEventListener("submit", event => {
        event.preventDefault();
        const draft = room.drafts.get(spec.key);
        if (!draft || draft.composing || draft.justComposed || done.disabled) return;
        if (!dirty(draft) && !draft.request) close(room, spec.key);
        else {
          draft.finish = true;
          void save(room, spec.key);
        }
      });
      form.addEventListener("keydown", event => {
        if (event.isComposing || event.keyCode === 229 || room.drafts.get(spec.key)?.composing) return;
        if (event.key === "Escape") {
          event.preventDefault();
          close(room, spec.key);
        }
      });
      const view = {label: spec.action || "编辑", trigger, form, inputs, status, conflict, remote, keepLocal, retry, done};
      room.views.set(spec.key, view);
      paint(room, spec.key);
      return {trigger, form};
    }

    function newNoteId(canAdd) {
      const existing = [...active.drafts.values()].find(draft => draft.spec.newNote &&
        (dirty(draft) || active.open === draft.spec.key));
      if (existing) return existing.spec.id;
      if (!canAdd) return "";
      if (!active.noteId || active.session.board?.modules?.some(module => module.id === active.noteId))
        active.noteId = globalThis.crypto.randomUUID();
      return active.noteId;
    }

    function newNote(id) {
      return create({
        type: "module", id, key: "module:" + id, kind: "note", newNote: true,
        action: "新增笔记", label: "新增讨论笔记",
        fields: {title: 80, body: 800, material_ids: 8}, labels: {body: "笔记"},
      });
    }

    async function flush() {
      const room = active;
      if (!room) return true;
      while (active === room) {
        const drafts = [...room.drafts].filter(([, draft]) => dirty(draft) || draft.request);
        if (!drafts.length) return true;
        const pending = drafts.map(([key]) => save(room, key)).filter(Boolean);
        if (!pending.length) return false;
        await Promise.all(pending);
      }
      return false;
    }

    function reveal() {
      const room = active;
      const blocked = room && [...room.drafts.values()].find(draft => dirty(draft));
      if (!blocked) return;
      const view = room.views.get(blocked.spec.key);
      if (!view?.trigger.isConnected) return;
      const details = view.trigger.closest("details");
      if (details) details.open = true;
      openView(room, blocked.spec, view);
      view.form.scrollIntoView({block: "nearest"});
    }

    return {
      sync, leave, create, newNoteId, newNote, flush, reveal,
      hasDraft: key => active?.drafts.has(key),
      canEdit: key => active?.session.status !== "closed" || active.drafts.has(key),
      isCreating: id => {
        const draft = active?.drafts.get("module:" + id);
        return Boolean(draft?.spec.newNote && (dirty(draft) || active.open === draft.spec.key));
      },
      isOpen: node => Boolean(active?.open && node?.contains(active.views.get(active.open)?.form)),
    };
  }

  window.RoundtableBoardEdit = Object.freeze({mount, snapshotIsOlder});
})();
