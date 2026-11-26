(() => {
  "use strict";
  const mounts = new WeakMap();
  const text = (zh, en) => document.documentElement.lang === "en" ? en : zh;

  async function request(session, payload) {
    const init = {headers: {"X-Roundtable": "1"}, cache: "no-store"};
    const bridgeProof = window.sciStationConnectorReview;
    if (typeof bridgeProof === "string" && bridgeProof) {
      init.headers["X-Sci-Station-Connector-Review"] = bridgeProof;
    }
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

  function appendField(fields, label, value, code = false, scrollable = false) {
    if (typeof value !== "string" || !value) return;
    const name = document.createElement("dt");
    name.textContent = label;
    const item = document.createElement("dd");
    if (code) {
      const exact = document.createElement("pre");
      exact.textContent = value;
      if (scrollable) {
        exact.tabIndex = 0;
        exact.setAttribute("aria-label", label);
      }
      item.append(exact);
    } else {
      item.textContent = value;
    }
    fields.append(name, item);
  }

  function researchRequest(pending) {
    const operations = {
      "resources/list": text("列出资料", "List resources"),
      "resources/read": text("读取资料", "Read resource"),
      "tools/list": text("列出只读工具", "List read-only tools"),
      "tools/call": text("调用服务端只读工具", "Call a server read-only tool"),
    };
    if (!Object.hasOwn(operations, pending.operation) || !pending.project_id || !pending.connection || !pending.destination) return null;
    const usesTarget = pending.operation === "resources/read" || pending.operation === "tools/call";
    if (usesTarget && !pending.resource) return null;
    if (pending.operation === "tools/call" && !pending.arguments_json) return null;
    const fields = document.createElement("dl");
    fields.className = "model-read-details";
    const project = pending.project_label ? pending.project_label + " · " + pending.project_id : pending.project_id;
    appendField(fields, text("项目", "Project"), project);
    appendField(fields, text("科研连接", "Research connector"), pending.connection);
    appendField(fields, text("目标地址或进程", "Endpoint or process"), pending.destination, true, true);
    appendField(fields, text("动作", "Operation"), operations[pending.operation] + " · " + pending.operation);
    appendField(fields, pending.operation === "tools/call"
      ? text("服务端工具", "Server tool") : text("资源 URI", "Resource URI"), pending.resource, true);
    appendField(fields, text("JSON 参数", "JSON arguments"), pending.arguments_json, true, true);
    return fields;
  }

  function render(panel, state, pending) {
    if (state.pending === pending?.id) return;
    state.pending = pending?.id;
    panel.replaceChildren();
    panel.hidden = !pending;
    if (!pending) return;
    const label = document.createElement("p");
    const research = pending.action === "research_read";
    let fields;
    if (research) {
      fields = researchRequest(pending);
      label.textContent = text("模型申请一次性科研读取", "Model requests a one-time research read");
      if (!fields) {
        label.textContent = text("读取请求缺少审阅详情。请取消本轮并重试。", "Read details are unavailable. Cancel the round and retry.");
        panel.append(label);
        return;
      }
    } else {
      const action = pending.action === "read" ? text("项目文件", "Project file") : text("会议发言", "Discussion statement");
      label.textContent = text("模型申请读取 · ", "Model requests a read · ") + action + " · " + pending.target;
    }
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
          const decision = {id: pending.id, action};
          if (research) decision.project_id = pending.project_id;
          await request(state.session, decision);
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
    panel.append(label);
    if (fields) {
      panel.append(fields);
      const resultNote = document.createElement("p");
      const recheck = pending.operation === "resources/read" || pending.operation === "tools/call";
      resultNote.textContent = recheck
        ? text("批准后会先核对服务的当前目录，再执行所列操作一次，并将结果交回当前模型。", "Approval checks the server’s current catalog, performs the listed operation once, and returns the result to the current model.")
        : text("批准后，查询结果会交回当前模型。", "Approval returns the query result to the current model.");
      panel.append(resultNote);
    }
    panel.append(controls, status);
  }

  async function update(panel, room) {
    if (!panel) return;
    const session = room?.status === "running" && !room.cancel_requested ? room.id : "";
    const project = session ? room.project_id || "" : "";
    let state = mounts.get(panel);
    if (!state || state.session !== session || state.project !== project) {
      state = {session, project};
      mounts.set(panel, state);
      panel.replaceChildren();
      panel.hidden = true;
    }
    if (!session || state.loading || state.deciding) return;
    // A ready connector capable of proposing a request always requires its
    // own approval, including when ordinary project reads are automatic.
    if (!window.sciStationConnectorReview && room.rounds?.at(-1)?.settings?.tool_budget?.auto_read !== false) return;
    state.loading = true;
    try {
      const pending = await request(session);
      if (mounts.get(panel) !== state || state.deciding) return;
      const matchesProject = pending?.action !== "research_read" || pending.project_id === state.project;
      render(panel, state, matchesProject ? pending : null);
    } catch {
      // The conversation's next refresh retries transient local connection errors.
    } finally {
      state.loading = false;
    }
  }

  window.SciStationReadReview = {update};
})();
