"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  const defaults = { goal: "", criteria: "", max_rounds: 12, summary_every: 4 };
  const stateLabels = {
    configured: "已配置，开始后持续推进",
    active: "正在持续推进",
    paused: "已暂停",
    completed: "本段持续推进已完成 · 等待主持人继续讨论或完成会议",
  };

  function mount(prefix, storage = {}) {
    const toggle = $(`${prefix}-continuous-enabled`);
    const options = $(`${prefix}-continuous-options`);
    const fields = {
      goal: $(`${prefix}-continuous-goal`),
      criteria: $(`${prefix}-continuous-criteria`),
      max_rounds: $(`${prefix}-continuous-max-rounds`),
      summary_every: $(`${prefix}-continuous-summary-every`),
    };
    const isRun = prefix === "run";
    const status = isRun ? $("run-continuous-status") : null;
    const checkpoint = isRun ? $("run-continuous-checkpoint") : null;
    const checkpointSummary = isRun ? checkpoint.querySelector("summary") : null;
    const checkpointList = isRun ? checkpoint.querySelector("ul") : null;
    const pause = isRun ? $("run-continuous-pause") : null;
    let draftKey = null;
    let sessionID = null;
    let session = null;
    const getStorage = storage.storageGet || (key => localStorage.getItem(key));
    const setStorage = storage.storageSet || ((key, value) => localStorage.setItem(key, value));

    function read() {
      return {
        goal: fields.goal.value.trim(),
        criteria: fields.criteria.value.trim(),
        max_rounds: Number(fields.max_rounds.value),
        summary_every: Number(fields.summary_every.value),
      };
    }
    function valid(onInvalid) {
      if (!toggle.checked) return true;
      for (const input of [fields.max_rounds, fields.summary_every]) {
        if (!input.checkValidity()) { onInvalid?.(input); input.reportValidity(); return false; }
      }
      return true;
    }
    function paint() {
      options.hidden = !toggle.checked;
      toggle.setAttribute("aria-expanded", String(toggle.checked));
      const running = isRun && session?.status === "running" && (session?.continuous?.manual || !["paused", "completed"].includes(session?.continuous?.status));
      const active = isRun && session?.continuous?.status === "active" && !session?.continuous?.manual;
      const closed = isRun && session?.status === "closed";
      toggle.disabled = Boolean(running || active || closed);
      for (const input of Object.values(fields)) input.disabled = Boolean(running || active || closed || !toggle.checked);
      if (!isRun) return;
      renderStatus();
    }
    function renderStatus() {
      const continuous = session?.continuous;
      const hasStatus = continuous && stateLabels[continuous.status];
      status.hidden = !hasStatus;
      pause.hidden = continuous?.status !== "active" || continuous.manual || session?.status === "closed";
      pause.disabled = session?.status !== "running";
      const wasOpen = checkpoint.open;
      checkpoint.hidden = true;
      checkpointSummary.textContent = "";
      checkpointList.replaceChildren();
      if (!hasStatus) return;

      const config = continuous.config || {};
      const maxRounds = Number(config.max_rounds) || Number(fields.max_rounds.value) || 12;
      const startRound = Number(continuous.start_round) || 1;
      const latestRound = Number(session.rounds?.at(-1)?.number) || 0;
      const done = Math.max(0, latestRound ? latestRound - startRound + 1 : 0);
      const previousStatus = continuous.manual && continuous.status === "active" ? "已切换为单轮推进" : stateLabels[continuous.status];
      const text = document.createElement("strong");
      text.textContent = continuous.manual
        ? `上次持续推进 · ${previousStatus}`
        : continuous.status === "active"
          ? `${stateLabels.active} · 第 ${done} / ${maxRounds} 轮`
          : stateLabels[continuous.status];
      status.replaceChildren(text);
      if (continuous.reason) {
        const reason = document.createElement("span");
        reason.className = "continuous-reason";
        reason.textContent = `${continuous.status === "active" ? continuous.manual ? "上次进展核对" : "进展核对" : "停止原因"}：${continuous.reason}`;
        reason.title = reason.textContent;
        status.append(reason);
      }
      if (continuous.next) {
        const next = document.createElement("span");
        next.className = "continuous-next";
        const value = typeof continuous.next === "string" ? continuous.next :
          continuous.next.title || continuous.next.text || JSON.stringify(continuous.next);
        next.textContent = `${continuous.manual ? "上次下一轮任务" : "下一轮任务"}：${value}`;
        next.title = next.textContent;
        status.append(next);
      }
      const items = continuous.checkpoint?.items || [];
      if (!items.length) return;
      checkpoint.hidden = false;
      const through = Number(continuous.checkpoint.through_round) || 0;
      const preview = String(items[0]?.text || "").replace(/\s+/g, " ").trim();
      checkpointSummary.textContent = `${continuous.manual ? "上次阶段摘要" : "阶段摘要"}${through ? ` · 截至第 ${through} 轮` : ""}${preview ? ` · ${preview}` : ""}`;
      for (const item of items) {
        const row = document.createElement("li");
        const source = item.round && item.seat
          ? `（第 ${item.round} 轮 · ${window.RoundtableIdentity?.seatName(item.seat, session) || item.seat}）`
          : "";
        row.append(document.createTextNode(`${item.text || ""}${source} `));
        if (item.round && item.seat) {
          const link = document.createElement("button");
          link.type = "button";
          link.className = "continuous-source";
          link.textContent = "查看原话";
          link.addEventListener("click", () => {
            const navigated = window.RoundtableReferences?.jump?.(Number(item.round), item.seat, item.model);
            if (!navigated) {
              const target = document.getElementById(`round-${item.round}-${item.seat}`);
              target?.scrollIntoView({behavior:"smooth", block:"center"});
              target?.focus({preventScroll:true});
            }
          });
          row.append(link);
        }
        checkpointList.append(row);
      }
      checkpoint.open = wasOpen;
    }
    function set(config, enabled) {
      const value = {...defaults, ...(config || {})};
      fields.goal.value = value.goal || "";
      fields.criteria.value = value.criteria || "";
      fields.max_rounds.value = String(value.max_rounds || defaults.max_rounds);
      fields.summary_every.value = String(value.summary_every || defaults.summary_every);
      toggle.checked = Boolean(enabled);
      options.querySelector("details").open = false;
      paint();
    }
    function payload(goalFallback = "") {
      if (!toggle.checked) return null;
      return {...read(), goal: fields.goal.value.trim() || goalFallback.trim()};
    }
    function loadDraft(key) {
      draftKey = key;
      let saved = {};
      try {
        const all = JSON.parse(getStorage("studio.continuous-drafts.v1") || "{}");
        if (all && typeof all === "object" && !Array.isArray(all)) saved = all[key] || {};
      } catch (_) {}
      set(saved, Boolean(saved.enabled));
    }
    function saveDraft() {
      if (!draftKey) return;
      try {
        const all = JSON.parse(getStorage("studio.continuous-drafts.v1") || "{}");
        const drafts = all && typeof all === "object" && !Array.isArray(all) ? all : {};
        drafts[draftKey] = {...read(), enabled:toggle.checked};
        setStorage("studio.continuous-drafts.v1", JSON.stringify(drafts));
      } catch (_) {}
    }
    for (const input of [toggle, ...Object.values(fields)]) {
      input.addEventListener(input === toggle ? "change" : "input", () => {
        paint();
        if (!isRun) saveDraft();
        else if (input === toggle) storage.onToggle?.();
      });
      if (input !== toggle) input.addEventListener("change", () => {
        if (!isRun) saveDraft();
      });
    }
    return {
      payload,
      valid,
      paint,
      setBusy(busy) { if (pause) pause.disabled = Boolean(busy) || session?.status !== "running"; },
      open(key) {
        if (draftKey !== key) loadDraft(key);
      },
      complete() {
        if (draftKey) {
          try {
            const all = JSON.parse(getStorage("studio.continuous-drafts.v1") || "{}");
            if (all && typeof all === "object") {
              delete all[draftKey];
              setStorage("studio.continuous-drafts.v1", JSON.stringify(all));
            }
          } catch (_) {}
        }
        draftKey = null;
      },
      update(next) {
        if (!isRun) return;
        session = next;
        if (sessionID !== next?.id) {
          sessionID = next?.id || null;
          if (checkpoint) checkpoint.open = false;
          const continuous = next?.continuous;
          set(continuous?.config, Boolean(continuous && !continuous.manual && ["configured", "active", "paused", "completed"].includes(continuous.status)));
        } else paint();
      },
      isActive() { return isRun && session?.continuous?.status === "active" && !session?.continuous?.manual; },
    };
  }

  window.RoundtableContinuous = Object.freeze({mount});
})();
