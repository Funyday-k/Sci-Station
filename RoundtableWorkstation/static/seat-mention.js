"use strict";
(() => {
  const clean = value => String(value || "").trim().normalize("NFC").toLocaleLowerCase();
  function endsMention(text, end) {
    const next = text[end];
    if (!next) return true;
    // A seat called "review" must not capture an unknown "@review-bot".
    if (/[._/-]/u.test(next) && /[A-Za-z0-9_]/u.test(text[end + 1] || "")) return false;
    return /[\s\p{P}\p{S}]/u.test(next);
  }

  function isMarker(text, index) {
    return text[index] === "@" && !/[A-Za-z0-9._%+\\-]/u.test(text[index - 1] || "");
  }

  function resolve(text, members, multipleTargetsError = "一条消息只能发送给一个席位；请保留一个 @目标。") {
    const hits = [];
    for (let i = 0; i < text.length; i++) {
      // Inline code and email addresses may contain literal @ signs.
      if (text[i] === "`") {
        let end = i + 1;
        while (text[end] === "`") end++;
        const close = text.indexOf(text.slice(i, end), end);
        i = close < 0 ? end - 1 : close + (end - i) - 1;
        continue;
      }
      if (!isMarker(text, i)) continue;
      const tail = text.slice(i + 1);
      const matches = [];
      for (const member of members) {
        for (const alias of new Set([String(member.label || member.name || member.id), String(member.id)])) {
          if (!alias || clean(tail.slice(0, alias.length)) !== clean(alias)) continue;
          if (!endsMention(tail, alias.length)) continue;
          matches.push({ id: String(member.id), length: alias.length });
        }
      }
      const longest = Math.max(0, ...matches.map(match => match.length));
      const best = [...new Map(matches.filter(match => match.length === longest).map(match => [match.id, match])).values()];
      if (best.length === 1) {
        hits.push({ id: best[0].id });
        i += best[0].length;
      } else if (best.length > 1) {
        return { error: "这个 @席位名称重名，请使用界面显示的完整席位名或稳定编号。" };
      } else {
        const token = tail.match(/^[^\s，。！？；：、）》】」』\]}]+/u)?.[0] || "";
        if (!token) return { error: "请在 @ 后选择席位，或删除单独的 @ 标记。" };
        return { error: `无法识别 @${token}。请使用席位名称或稳定编号，或删除 @ 标记。` };
      }
    }
    const ids = [...new Set(hits.map(hit => hit.id))];
    if (ids.length > 1) return { error: multipleTargetsError };
    return { target: ids[0] || "" };
  }

  function mount({ textarea, members = () => [], getSeatName, status, list, describeTarget = label => "仅 " + label + " 回应", multipleTargetsError } = {}) {
    if (!textarea) throw new TypeError("RoundtableMention.mount requires a textarea");
    let current = [], active = -1, composing = false, dismissed = false;
    const getMembers = () => typeof members === "function" ? (members() || []) : members;
    const seatLabel = member => getSeatName ? getSeatName(String(member.id)) : (member.label || member.name || member.id);
    const menu = list || document.createElement("div");
    const live = status || document.createElement("div");
    if (!menu.id) menu.id = "run-mention-list";
    if (!live.id) live.id = "run-mention-status";
    textarea.setAttribute("aria-controls", menu.id);
    const descriptions = (textarea.getAttribute("aria-describedby") || "").split(/\s+/).filter(Boolean);
    textarea.setAttribute("aria-describedby", [...new Set([...descriptions, live.id])].join(" "));
    textarea.setAttribute("aria-autocomplete", "list");
    textarea.setAttribute("aria-expanded", "false");
    menu.classList.add("seat-mention-menu"); menu.setAttribute("role", "listbox"); menu.hidden = true;
    if (!list && textarea.parentNode) textarea.parentNode.insertBefore(menu, textarea.nextSibling);
    live.classList.add("seat-mention-status"); live.setAttribute("role", "status"); live.setAttribute("aria-live", "polite");
    if (!status && textarea.parentNode) textarea.parentNode.insertBefore(live, menu.nextSibling);

    function queryAtCursor() {
      const end = textarea.selectionStart;
      if (composing || textarea.disabled || end !== textarea.selectionEnd) return null;
      const start = textarea.value.lastIndexOf("@", end - 1);
      if (start < 0 || start >= end || !isMarker(textarea.value, start)) return null;
      const query = textarea.value.slice(start + 1, end);
      if (/\s/u.test(query)) return null;
      return { query, start, end };
    }
    function hide() {
      menu.hidden = true; textarea.setAttribute("aria-expanded", "false"); textarea.removeAttribute("aria-activedescendant");
      current = []; active = -1;
      menu.replaceChildren();
    }
    function refresh() {
      if (dismissed) return hide();
      const query = queryAtCursor(); if (!query) return hide();
      current = getMembers().filter(member => `${seatLabel(member)} ${member.id}`.toLocaleLowerCase().includes(query.query.toLocaleLowerCase())).map(member => ({member, label:seatLabel(member)}));
      menu.replaceChildren();
      active = current.length ? 0 : -1;
      current.forEach((item, index) => {
        const option = document.createElement("button");
        option.id = `${menu.id}-option-${index}`; option.type = "button"; option.tabIndex = -1;
        option.setAttribute("role", "option"); option.setAttribute("aria-selected", String(index === active));
        option.textContent = item.label;
        option.title = String(item.member.id);
        if (item.member.model && item.member.model !== item.label) {
          const model = document.createElement("small");
          model.textContent = item.member.model;
          option.append(model);
        }
        option.addEventListener("pointerdown", event => event.preventDefault());
        option.addEventListener("mousedown", event => event.preventDefault());
        option.addEventListener("click", () => choose(index)); menu.append(option);
      });
      menu.hidden = !current.length; textarea.setAttribute("aria-expanded", String(!menu.hidden));
      if (menu.hidden) textarea.removeAttribute("aria-activedescendant");
      else textarea.setAttribute("aria-activedescendant", `${menu.id}-option-${active}`);
    }
    function choose(index) {
      const query = queryAtCursor(), item = current[index]; if (!query || !item) return;
      const suffix = textarea.value.slice(query.end);
      const insertion = `@${item.label} `;
      textarea.setRangeText(insertion, query.start, query.end + (/^ /u.test(suffix) ? 1 : 0), "end");
      dismissed = true; hide();
      textarea.dispatchEvent(new Event("input", {bubbles:true})); textarea.focus();
      readRecipient(true);
    }
    function open() {
      const start = textarea.selectionStart ?? textarea.value.length, end = textarea.selectionEnd ?? start;
      if (textarea.disabled) return;
      const prefix = /[A-Za-z0-9._%+-]/u.test(textarea.value[start - 1] || "") ? " @" : "@";
      textarea.setRangeText(prefix, start, end, "end"); dismissed = false;
      textarea.dispatchEvent(new Event("input", {bubbles:true})); textarea.focus(); refresh();
    }
    function readRecipient(showErrors = false) {
      const roster = getMembers().map(member => ({...member, label:seatLabel(member)}));
      const result = resolve(textarea.value, roster, multipleTargetsError);
      const seat = result.target && roster.find(member => String(member.id) === result.target);
      const text = showErrors && result.error ? result.error : seat ? describeTarget(seat.label) : "";
      if (live.textContent !== text) live.textContent = text;
      return result;
    }
    textarea.addEventListener("compositionstart", () => { composing = true; hide(); });
    textarea.addEventListener("compositionend", () => { composing = false; dismissed = false; refresh(); readRecipient(); });
    textarea.addEventListener("input", () => { dismissed = false; refresh(); if (!composing) readRecipient(); });
    textarea.addEventListener("click", () => { dismissed = false; refresh(); });
    textarea.addEventListener("blur", hide);
    textarea.addEventListener("keydown", event => {
      if (composing || event.isComposing || event.keyCode === 229) return;
      if (!menu.hidden && current.length) {
        if (event.key === "ArrowDown" || event.key === "ArrowUp") {
          event.preventDefault(); active = (active + (event.key === "ArrowDown" ? 1 : current.length - 1)) % current.length;
          [...menu.children].forEach((option, index) => option.setAttribute("aria-selected", String(index === active)));
          textarea.setAttribute("aria-activedescendant", `${menu.id}-option-${active}`);
        } else if ((event.key === "Enter" && !event.shiftKey) || event.key === "Tab") { event.preventDefault(); choose(active); }
        else if (event.key === "Escape") { event.preventDefault(); dismissed = true; hide(); }
      }
    });
    return {
      resolve: () => readRecipient(true),
      clear() { textarea.value = ""; dismissed = false; hide(); live.textContent = ""; },
      refresh, open,
      updateStatus: () => readRecipient(),
      setContext() { dismissed = false; hide(); live.textContent = ""; },
    };
  }
  window.RoundtableMention = Object.freeze({ mount, resolve });
})();
