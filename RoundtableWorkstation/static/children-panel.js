"use strict";
(() => {
  const state = { session: null, seat: null, round: null, selected: "", opener: null, openerID: "", visible: false, items: [], signature: "", detailSignature: "", scroll: new Map() };
  let panel, list, detail, title, count, closeButton;

  const labels = {
    pending: "等待执行",
    active: "正在执行",
    complete: "已完成",
    failed: "执行失败",
    interrupted: "已中断",
    unknown: "状态未记录",
  };
  const seatName = (seat) => window.RoundtableIdentity.seatName(seat, state.session);
  const el = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = String(text);
    return node;
  };

  function errorText(child) {
    return typeof child.error === "string" ? child.error.trim() : String(child.error?.message || "").trim();
  }

  function statusOf(child) {
    switch (child.status) {
    case "pending": return "pending";
    case "running": return "active";
    case "done": return "complete";
    case "cancelled":
    case "canceled":
    case "interrupted": return "interrupted";
    case "error":
      // Earlier archives store project shutdown and user cancellation as errors.
      return /(?:^|:\s*)(?:child interrupted|context cancel(?:l)?ed|cancel(?:l)?ed by user)\.?$/i.test(errorText(child))
        ? "interrupted" : "failed";
    default: return "unknown";
    }
  }

  function summary(children = []) {
    const counts = new Map();
    for (const child of children) {
      const status = statusOf(child);
      counts.set(status, (counts.get(status) || 0) + 1);
    }
    const label = ["active", "pending", "complete", "failed", "interrupted", "unknown"]
      .filter(status => counts.has(status))
      .map(status => `${counts.get(status)} 个${labels[status]}`).join(" · ");
    const state = ["active", "pending", "failed", "interrupted", "unknown", "complete"]
      .find(status => counts.has(status)) || "empty";
    return { label, state };
  }

  function displayName(child) {
    return [child.name, child.nickname, child.display_name]
      .find(value => typeof value === "string" && value.trim()) || "子代理";
  }

  function avatar(child) {
    const node = el("span", "children-avatar");
    const source = String(child.model || "").split(/[/:]/, 1)[0];
    const mark = window.RoundtableIcons.sourceMark(source);
    node.setAttribute("aria-hidden", "true");
    if (mark) {
      const image = el("img");
      image.src = mark;
      image.alt = "";
      node.append(image);
    } else {
      node.classList.add("children-avatar-neutral");
      node.innerHTML = window.RoundtableIcons.icon("subagent");
    }
    return node;
  }

  function statusBadge(child) {
    const badge = el("span", "children-status", labels[child.displayStatus]);
    badge.dataset.childStatus = child.displayStatus;
    return badge;
  }

  function ensurePanel() {
    if (panel?.isConnected) return true;
    const host = document.getElementById("table-view");
    if (!host) return false;
    panel = el("aside", "children-panel"); panel.id = "children-panel"; panel.hidden = true;
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-labelledby", "children-panel-title");
    const header = el("header", "children-panel-heading");
    const heading = el("div", "children-panel-heading-copy");
    title = el("h2", "", "子代理"); title.id = "children-panel-title";
    count = el("span", "children-panel-count"); count.setAttribute("aria-live", "polite");
    heading.append(title, count);
    closeButton = el("button", "children-panel-close"); closeButton.type = "button"; closeButton.setAttribute("aria-label", "关闭子代理面板"); closeButton.title = "关闭 · Esc";
    closeButton.innerHTML = window.RoundtableIcons.icon("close");
    closeButton.addEventListener("click", () => close()); header.append(heading, closeButton);
    list = el("nav", "children-task-list"); list.setAttribute("aria-label", "选择子代理");
    detail = el("section", "children-task-detail"); detail.id = "children-task-detail";
    detail.tabIndex = 0; detail.setAttribute("aria-label", "子代理任务与报告");
    panel.append(header, list, detail); host.append(panel);
    list.addEventListener("keydown", (event) => {
      const buttons = [...list.querySelectorAll("button[data-child-key]")];
      const index = buttons.indexOf(document.activeElement); if (index < 0) return;
      let next; if (event.key === "ArrowDown") next = Math.min(buttons.length - 1, index + 1);
      else if (event.key === "ArrowUp") next = Math.max(0, index - 1);
      else if (event.key === "Home") next = 0; else if (event.key === "End") next = buttons.length - 1; else return;
      event.preventDefault(); buttons[next].focus(); buttons[next].click();
    });
    return true;
  }

  function children(session) {
    const result = [];
    for (const round of session?.rounds || []) {
      if (state.round !== null && Number(round.number) !== state.round) continue;
      for (const turn of round.turns || []) {
        if (state.seat && turn.seat !== state.seat) continue;
        const owner = window.RoundtableIdentity.sourceIdentity?.(turn.seat, session, round.number)?.label || seatName(turn.seat);
        for (const [index, child] of (turn.children || []).entries()) {
          result.push({
            ...child, seat: turn.seat, round: round.number, owner,
            key: String(child.id || `${round.number}:${turn.seat}:${index}`),
            name: displayName(child),
            displayStatus: statusOf(child),
          });
        }
      }
    }
    return result;
  }

  function saveScroll() {
    if (detail && state.selected) state.scroll.set(state.selected, detail.scrollTop);
  }

  function select(key) {
    if (state.selected !== key) { saveScroll(); state.selected = key; state.detailSignature = ""; }
    for (const button of list.querySelectorAll("button[data-child-key]")) {
      const selected = button.dataset.childKey === key;
      button.classList.toggle("selected", selected); button.setAttribute("aria-pressed", String(selected));
    }
    renderDetail();
  }

  function missingReport(child) {
    if (child.displayStatus === "complete") return "这项任务没有保存报告正文。";
    if (child.displayStatus === "interrupted") return "任务中断，未收到完整报告。";
    if (child.displayStatus === "failed") return "任务失败，未收到完整报告。";
    return "报告将在任务完成后显示。";
  }

  function renderDetail() {
    const child = state.items.find((item) => item.key === state.selected);
    const signature = JSON.stringify(child || null); if (signature === state.detailSignature) return;
    const sameSelection = detail.dataset.childKey === state.selected;
    const oldScroll = sameSelection ? detail.scrollTop : state.scroll.get(state.selected) || 0;
    state.detailSignature = signature; detail.dataset.childKey = state.selected; detail.replaceChildren();
    if (!child) { detail.append(el("p", "children-empty", "这个范围内暂无子代理。")); return; }
    const byline = el("div", "children-detail-byline");
    byline.dataset.childStatus = child.displayStatus;
    const identity = el("div", "children-detail-identity");
    const model = el("span", "children-model", child.model || "未记录型号");
    identity.append(el("strong", "", child.name), model);
    byline.append(avatar(child), identity, statusBadge(child)); detail.append(byline);
    const meta = el("div", "children-detail-meta", `${child.owner} · 第 ${child.round} 轮`);
    detail.append(meta, el("h3", "", "任务"), el("p", "children-task-text", child.task || "未记录任务内容"));
    detail.append(el("h3", "", "报告"));
    detail.append(child.text ? el("div", "children-report", child.text) : el("p", "children-empty", missingReport(child)));
    const reason = errorText(child);
    if (reason) {
      const error = el("div", "children-task-error");
      error.dataset.childStatus = child.displayStatus;
      error.append(el("strong", "", child.displayStatus === "interrupted" ? "中断原因" : "失败原因"), el("p", "", reason));
      detail.append(error);
    }
    const timestamp = child.finished_at || child.started_at;
    if (timestamp && !Number.isNaN(new Date(timestamp).getTime())) {
      const time = el("time", "children-time", `${child.finished_at ? "结束" : "开始"} · ${new Date(timestamp).toLocaleString("zh-CN", { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })}`);
      time.dateTime = timestamp; detail.append(time);
    }
    detail.scrollTop = oldScroll;
  }

  function optionFor(child) {
    const button = el("button", "children-task-option");
    button.type = "button"; button.dataset.childKey = child.key; button.dataset.childStatus = child.displayStatus;
    button.setAttribute("aria-controls", detail.id);
    const identity = el("span", "children-option-identity");
    const copy = el("span", "children-option-name");
    copy.append(el("strong", "", child.name), el("span", "children-option-context",
      state.seat ? `第 ${child.round} 轮` : `${child.owner} · 第 ${child.round} 轮`));
    identity.append(avatar(child), copy, statusBadge(child));
    const task = el("span", "children-option-task", child.task || "未记录任务内容");
    button.append(identity, task); button.addEventListener("click", () => select(child.key));
    return button;
  }

  function render() {
    if (!state.visible || !ensurePanel()) return;
    const items = children(state.session); state.items = items;
    title.textContent = `${state.seat ? `${seatName(state.seat)} · ` : ""}子代理`;
    const active = items.filter(child => child.displayStatus === "active").length;
    const countLabel = [state.round !== null ? `第 ${state.round} 轮` : "", `${items.length} 个子代理`,
      active ? `${active} 个正在执行` : ""].filter(Boolean).join(" · ");
    if (count.textContent !== countLabel) count.textContent = countLabel;
    const signature = JSON.stringify([state.seat, items.map(({key, seat, round, owner, name, task, model, displayStatus}) => ({key, seat, round, owner, name, task, model, displayStatus}))]);
    if (state.signature !== signature) {
      const scroll = list.scrollTop, focus = list.contains(document.activeElement) ? document.activeElement.dataset.childKey : "";
      state.signature = signature; list.replaceChildren(...items.map(optionFor)); list.hidden = !items.length;
      list.scrollTop = scroll;
      if (focus) [...list.querySelectorAll("button")].find((button) => button.dataset.childKey === focus)?.focus({ preventScroll: true });
    }
    const next = items.some((child) => child.key === state.selected)
      ? state.selected
      : (items.find((child) => child.displayStatus === "active" || child.displayStatus === "pending") || items[0])?.key || "";
    select(next);
  }

  function currentOpener() {
    return state.opener?.isConnected ? state.opener : state.openerID ? document.getElementById(state.openerID) : null;
  }

  function setOpenerState(expanded) {
    const opener = currentOpener();
    if (opener?.getAttribute("aria-controls") === panel.id) opener.setAttribute("aria-expanded", String(expanded));
  }

  function open({ session, seat = null, round = null, opener = null, childid = null } = {}) {
    if (!session || !ensurePanel()) return false;
    saveScroll();
    if (state.visible) setOpenerState(false);
    if (state.session?.id !== session.id) { state.scroll.clear(); state.selected = ""; }
    state.session = session; state.seat = seat || null; state.round = round === null || round === undefined ? null : Number(round);
    state.opener = opener || (panel.contains(document.activeElement) ? state.opener : document.activeElement);
    state.openerID = state.opener?.id || ""; state.visible = true;
    if (childid !== null) state.selected = String(childid);
    window.dispatchEvent(new CustomEvent("roundtable:sidepanel-open", { detail: "children" }));
    panel.hidden = false; document.body.classList.add("children-panel-open");
    setOpenerState(true); render(); closeButton.focus({ preventScroll: true }); return true;
  }

  function close({ restoreFocus = true } = {}) {
    if (!state.visible) return;
    saveScroll(); state.visible = false; panel.hidden = true; document.body.classList.remove("children-panel-open");
    setOpenerState(false);
    if (restoreFocus) currentOpener()?.focus({ preventScroll: true });
    state.opener = null; state.openerID = "";
  }

  function update(session) {
    if (!state.visible) return;
    if (!session || session.id !== state.session?.id) { close({ restoreFocus: false }); return; }
    state.session = session; setOpenerState(true); render();
  }

  window.addEventListener("roundtable:sidepanel-open", (event) => { if (event.detail === "review" || event.detail === "opinions") close({ restoreFocus: false }); });
  document.addEventListener("keydown", (event) => { if (state.visible && event.key === "Escape" && !event.defaultPrevented) { event.preventDefault(); close(); } });
  window.RoundtableChildren = Object.freeze({ open, close, update, summary });
})();
