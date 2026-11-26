(() => {
  "use strict";
  const mounts = new WeakMap();
  const text = (zh, en) => document.documentElement.lang === "en" ? en : zh;

  async function request(session, payload) {
    const init = {headers: {"X-Roundtable": "1"}, cache: "no-store"};
    if (payload) {
      init.method = "POST";
      init.headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(payload);
    }
    const response = await fetch("/api/studio/sessions/" + encodeURIComponent(session) + "/read-review", init);
    if (response.status === 204) return;
    const data = await response.json();
    if (!response.ok) throw Error(data.error);
    return data;
  }

  function render(panel, state, pending) {
    if (state.pending === pending?.id) return;
    state.pending = pending?.id;
    panel.replaceChildren();
    panel.hidden = !pending;
    if (!pending) return;
    const label = document.createElement("p");
    const action = pending.action === "read" ? text("项目文件", "Project file") : text("会议发言", "Discussion statement");
    label.textContent = text("模型申请读取 · ", "Model requests a read · ") + action + " · " + pending.target;
    const controls = document.createElement("div");
    controls.className = "actions";
    const status = document.createElement("p");
    status.setAttribute("role", "status");
    for (const [action, title] of [["allow", text("允许一次", "Allow once")], ["deny", text("拒绝", "Deny")]]) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "button secondary small";
      button.textContent = title;
      button.addEventListener("click", async () => {
        state.deciding = true;
        for (const control of controls.children) control.disabled = true;
        try {
          await request(state.session, {id: pending.id, action});
          if (mounts.get(panel) === state) render(panel, state, null);
        } catch (error) {
          status.textContent = error.message;
        } finally {
          state.deciding = false;
          for (const control of controls.children) control.disabled = false;
        }
      });
      controls.append(button);
    }
    panel.append(label, controls, status);
  }

  async function update(panel, room) {
    if (!panel) return;
    const session = room?.status === "running" ? room.id : "";
    let state = mounts.get(panel);
    if (!state || state.session !== session) {
      state = {session};
      mounts.set(panel, state);
      panel.replaceChildren();
      panel.hidden = true;
    }
    if (!session || state.loading || state.deciding) return;
    // Historical running rounds and auto-read rounds do not need a request.
    if (room.rounds?.at(-1)?.settings?.tool_budget?.auto_read !== false) return;
    state.loading = true;
    try {
      const pending = await request(session);
      if (mounts.get(panel) === state && !state.deciding) render(panel, state, pending);
    } catch {
      // The conversation's next refresh retries transient local connection errors.
    } finally {
      state.loading = false;
    }
  }

  window.SciStationReadReview = {update};
})();
