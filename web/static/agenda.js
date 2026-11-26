(() => {
  let session = null;
  let lastPaint = "";
  let epoch = 0;
  let saving = false;
  let ui = null;

  function node(tag, cls, label) {
    const result = document.createElement(tag);
    if (cls) result.className = cls;
    if (label) result.textContent = label;
    return result;
  }
  function button(label, action, cls = "ag-link") {
    const el = node("button", cls, label);
    el.type = "button";
    el.addEventListener("click", action);
    return el;
  }
  function emit(name, detail) {
    window.dispatchEvent(new CustomEvent(name, {detail}));
  }
  function compose(item, kind, synthesis = false) {
    if (!session || session.status === "running" || session.status === "closed" || saving) return;
    let preset = item?.preset || session.preset || "review";
    let phase = item?.phase || "proposal";
    if (!synthesis && kind === "implementation") {
      preset = "work";
      phase = "work";
    } else {
      if (preset === "work") preset = "review";
      if (synthesis) phase = "synthesis";
    }
    const title = synthesis
      ? (item ? "汇总「" + item.title + "」的已有证据与后续重点。" : "汇总本次会议的已有证据与后续重点。")
      : item.title;
    emit("meeting-agenda-compose", {sessionId:session.id, itemId:item?.id || "", title, preset, phase});
  }

  function build(root) {
    const header = node("div", "ag-header");
    const title = node("strong", "ag-label", "议程");
    const progress = node("span", "ag-progress");
    progress.setAttribute("role", "status");
    const retry = button("重新起草", () => change({action:"draft"}));
    const add = button("添加", () => {
      editor.hidden = !editor.hidden;
      add.setAttribute("aria-expanded", String(!editor.hidden));
      if (!editor.hidden) input.focus();
    });
    add.setAttribute("aria-expanded", "false");
    const synth = button("汇总议题", () => {
      const current = session?.agenda?.find(item => item.id === session.active_agenda_id);
      compose(current, "discussion", true);
    });
    header.append(title, progress, retry, synth, add);
    const list = node("ol", "ag-list");
    list.setAttribute("aria-label", "会议议程");
    const editor = node("div", "ag-editor");
    editor.hidden = true;
    const input = node("input");
    input.placeholder = "新议程标题";
    input.setAttribute("aria-label", "新议程标题");
    const kind = node("select");
    kind.setAttribute("aria-label", "事项类型");
    for (const [value, label] of [["discussion", "讨论"], ["implementation", "实施"]]) {
      const option = node("option", "", label);
      option.value = value;
      kind.append(option);
    }
    const save = button("加入", async () => {
      if (!input.value.trim()) { input.focus(); return; }
      if (await change({action:"add", title:input.value, kind:kind.value})) {
        editor.hidden = true;
        add.setAttribute("aria-expanded", "false");
        input.value = "";
        add.focus();
      }
    });
    input.addEventListener("keydown", event => {
      if (event.key === "Enter" && !event.isComposing) {
        event.preventDefault();
        save.click();
      }
    });
    editor.append(input, kind, save);
    const message = node("div", "ag-message");
    message.setAttribute("role", "status");
    root.replaceChildren(header, list, editor, message);
    return {root, header, progress, retry, add, synth, list, editor, input, kind, save, message};
  }

  function evidence(item) {
    const revisions = item.revisions || [];
    const candidates = item.candidates || [];
    const openingModel = !item.source_round && item.source_seat && item.source_model;
    if (!item.source_round && !openingModel && !revisions.length && !candidates.length) return null;
    const roundTurn = (number, seat) => session.rounds?.find(round => round.number === number)
      ?.turns?.find(turn => turn.seat === seat && turn.status === "done");
    const author = (seat, round, source) => {
      const identity = window.RoundtableIdentity;
      const recorded = identity?.sourceIdentity?.(seat, session, round, source);
      return recorded ? identity.modelByline(recorded) : source?.model_label || source?.model || seat;
    };
    const jumpToSource = (number, seat, turn) => {
      if (!turn?.text || typeof window.RoundtableReferences?.jump !== "function") return null;
      return button("查看原话", () => window.RoundtableReferences.jump(number, seat, turn.model));
    };
    const details = node("details", "ag-source");
    details.dataset.agendaSource = item.id;
    const last = revisions.at(-1);
    const caption = last ? "第 " + last.round + " 轮修订" : openingModel ? "首席起草" :
      "第 " + item.source_round + (item.source === "synthesis" ? " 轮汇总" : " 轮新增");
    details.append(node("summary", "", candidates.length ? `待处理修订候选（${candidates.length}）` : caption));
    if (openingModel) details.append(node("strong", "", author(item.source_seat, 0, {
      model:item.source_model, model_label:item.source_model_label, model_source:item.source_model_source,
    })));
    if (item.source_round) {
      const turn = roundTurn(item.source_round, item.source_seat);
      details.append(node("strong", "", "第 " + item.source_round + " 轮 · " + author(item.source_seat, item.source_round, turn)));
      const jump = jumpToSource(item.source_round, item.source_seat, turn);
      if (jump) details.append(jump);
      if (item.reason) details.append(node("p", "", item.reason));
      if (turn?.text && turn.text !== item.reason) details.append(node("p", "", turn.text));
    }
    for (const rev of revisions) {
      const turn = roundTurn(rev.round, rev.seat);
      details.append(node("strong", "", "第 " + rev.round + " 轮 · " + author(rev.seat, rev.round, turn)));
      const jump = jumpToSource(rev.round, rev.seat, turn);
      if (jump) details.append(jump);
      details.append(node("p", "", "原议程为「" + rev.previous_title + "」" + (rev.reason ? "。" + rev.reason : "")));
    }
    for (const candidate of candidates) {
      const proposal = node("div", "ag-candidate");
      const turn = roundTurn(candidate.round, candidate.seat);
      proposal.append(node("strong", "", `第 ${candidate.round} 轮 · ${author(candidate.seat, candidate.round, turn)} 提议修订`));
      const jump = jumpToSource(candidate.round, candidate.seat, turn);
      if (jump) proposal.append(jump);
      proposal.append(node("p", "", `拟改为「${candidate.title}」（${candidate.kind === "implementation" ? "实施" : "讨论"}）`));
      if (candidate.reason) proposal.append(node("p", "", candidate.reason));
      if (session.status !== "closed" && !saving && session.status !== "running") {
        proposal.append(button("采用修订", () => change({action:"adopt_candidate",item_id:item.id,candidate_id:candidate.id})));
        proposal.append(button("忽略", () => change({action:"dismiss_candidate",item_id:item.id,candidate_id:candidate.id})));
      }
      details.append(proposal);
    }
    return details;
  }

  function row(item, running, busy) {
    const active = item.id === session.active_agenda_id;
    const done = item.status === "done";
    const li = node("li", "ag-row" + (active ? " ag-current" : "") + (done ? " ag-done" : ""));
    li.dataset.agendaItem = item.id;
    if (active) li.setAttribute("aria-current", "step");
    const body = node("div", "ag-item");
    const marker = node("span", "ag-mark", done ? "✓" : active ? "●" : "○");
    marker.setAttribute("aria-hidden", "true");
    const title = button(item.title, async () => {
      if (done) return;
      if (!active && !await change({action:"select",item_id:item.id})) return;
      compose(item, item.kind);
    }, "ag-title");
    title.title = item.title;
    if (!done) title.setAttribute("aria-label", "选择议程：" + item.title);
    title.disabled = busy || done;
    const last = session.rounds?.at(-1);
    let status = item.kind === "implementation" ? "实施" : "讨论";
    if (done) status = "已完成";
    else if (active && running && last?.agenda_item_id === item.id) status = last.preset === "work" ? "实施中" : "讨论中";
    else if (active) status = "当前 · " + status;
    const state = node("span", "ag-state", status);
    body.append(marker, title, state);
    if (!busy) {
      if (done) {
        body.append(button("恢复", () => change({action:"reopen", item_id:item.id})));
      } else if (active) {
        const other = item.kind === "implementation" ? "discussion" : "implementation";
        body.append(button(other === "discussion" ? "转讨论" : "转实施", async () => {
          if (await change({action:"select",item_id:item.id,kind:other})) compose(item, other);
        }));
        body.append(button("完成", () => change({action:"complete", item_id:item.id})));
      }
    }
    li.append(body);
    const source = evidence(item);
    if (source) li.append(source);
    return li;
  }

  function render(next) {
    if (!next?.id) { clear(); return; }
    const root = document.getElementById("meeting-agenda");
    if (!root) return;
    if (!ui || ui.root !== root || session?.id !== next.id) {
      epoch++;
      saving = false;
      lastPaint = "";
      ui = build(root);
      ui.kind.value = next.preset === "work" ? "implementation" : "discussion";
    }
    session = next;
    root.hidden = false;
    const items = next.agenda || [];
    const running = next.status === "running";
    const closed = next.status === "closed";
    const drafting = next.agenda_draft_status === "drafting";
    const failed = next.agenda_draft_status === "failed";
    const pending = next.agenda_draft_status === "pending";
    const busy = running || drafting || saving || closed;
    const key = [next.id,next.agenda_version || 0,next.active_agenda_id,next.status,next.agenda_draft_status,next.rounds?.length || 0,saving].join("|");
    if (key === lastPaint) return;
    lastPaint = key;
    const done = items.filter(item => item.status === "done").length;
    ui.progress.textContent = drafting ? "首席正在根据议题起草…" : failed && !items.length
      ? "起草未完成，可重试或开始讨论" : pending && !items.length ? "待首席起草" : items.length ? done + " / " + items.length + " 已完成" : "尚无议程";
    ui.retry.textContent = pending ? "起草议程" : "重新起草";
    ui.retry.title = failed ? next.agenda_draft_error || "" : "";
    ui.retry.disabled = busy;
    ui.retry.hidden = closed || (!failed && !pending);
    ui.synth.hidden = closed || !next.rounds?.length;
    ui.add.hidden = closed;
    ui.editor.hidden = closed || ui.editor.hidden;
    for (const control of [ui.add,ui.synth,ui.input,ui.kind,ui.save]) control.disabled = busy;
    const expanded = new Set([...ui.list.querySelectorAll("details[open]")].map(el => el.dataset.agendaSource));
    const rows = items.map(item => row(item, running, busy));
    ui.list.replaceChildren(...rows);
    for (const el of ui.list.querySelectorAll("details")) el.open = expanded.has(el.dataset.agendaSource);
  }

  async function change(payload) {
    if (!session || saving || session.status === "running" || session.status === "closed") return false;
    const id = session.id;
    const currentEpoch = epoch;
    const version = session.agenda_version || 0;
    const url = "/api/studio/sessions/" + encodeURIComponent(id);
    saving = true;
    ui.message.textContent = "";
    render(session);
    try {
      const response = await fetch(url + "/agenda", {
        method:"POST", cache:"no-store",
        headers:{"Content-Type":"application/json","X-Roundtable":"1"},
        body:JSON.stringify({...payload, expected_version:version}),
      });
      const data = await response.json();
      if (currentEpoch !== epoch) return false;
      if (!response.ok) {
        if (response.status === 409) {
          const refresh = await fetch(url, {cache:"no-store"});
          if (refresh.ok) {
            const fresh = await refresh.json();
            if (currentEpoch === epoch) emit("meeting-agenda-updated", {session:fresh});
          }
        }
        throw new Error(data.error || "议程更新失败");
      }
      if (session.agenda_version > data.agenda_version || (session.rounds?.length || 0) > (data.rounds?.length || 0)) return false;
      render(data);
      emit("meeting-agenda-updated", {session:data});
      return true;
    } catch (error) {
      if (currentEpoch === epoch) ui.message.textContent = error.message || "议程更新失败";
      return false;
    } finally {
      if (currentEpoch === epoch) { saving = false; render(session); }
    }
  }
  function clear() {
    epoch++;
    session = null; lastPaint = ""; saving = false;
    if (ui) { ui.root.replaceChildren(); ui.root.hidden = true; }
    ui = null;
  }
  window.MeetingAgenda = {render,clear,retry:() => change({action:"draft"})};
})();
