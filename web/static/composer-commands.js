(() => {
  "use strict";

  const { icon } = window.RoundtableIcons;

  function mount({ root, button, commands } = {}) {
    if (!root || !button || !root.contains(button) || typeof commands !== "function") {
      throw new TypeError("RoundtableCommands.mount requires a root containing button and a commands callback");
    }
    if (root.__roundtableCommands) return root.__roundtableCommands;

    const panel = document.createElement("div");
    panel.className = "roundtable-commands";
    panel.hidden = true;
    panel.setAttribute("role", "menu");
    panel.setAttribute("aria-label", button.getAttribute("aria-label") || "输入工具");
    panel.id = `roundtable-commands-${Math.random().toString(36).slice(2, 9)}`;
    document.body.append(panel);

    button.type = "button";
    button.classList.add("roundtable-commands-button");
    button.setAttribute("aria-haspopup", "menu");
    button.setAttribute("aria-controls", panel.id);
    button.setAttribute("aria-expanded", "false");
    if (!button.hasAttribute("aria-label") && !button.getAttribute("title")) button.setAttribute("aria-label", "输入工具");
    if (!button.querySelector("svg") && !button.textContent.trim()) {
      const plus = window.RoundtableIcons?.iconNode?.("plus"); if (plus) button.replaceChildren(plus);
    }

    let open = false;
    let items = [];
    const listeners = new AbortController();
    const listen = { signal: listeners.signal };
    const notify = (name, detail = {}) => root.dispatchEvent(new CustomEvent(`roundtable:commands-${name}`, { bubbles: true, detail: { root, button, panel, ...detail } }));
    const place = () => {
      if (!open) return;
      const rect = button.getBoundingClientRect();
      const vv = window.visualViewport;
      const leftEdge = vv ? vv.offsetLeft : 0;
      const topEdge = vv ? vv.offsetTop : 0;
      const width = vv ? vv.width : document.documentElement.clientWidth;
      const height = vv ? vv.height : document.documentElement.clientHeight;
      const margin = 8;
      const panelWidth = Math.min(280, width - margin * 2);
      panel.style.width = `${panelWidth}px`;
      panel.style.maxHeight = `${Math.max(100, height - margin * 2)}px`;
      const panelHeight = panel.offsetHeight;
      let left = rect.left;
      if (left + panelWidth > leftEdge + width - margin) left = rect.right - panelWidth;
      left = Math.max(leftEdge + margin, Math.min(left, leftEdge + width - panelWidth - margin));
      let top = rect.bottom + 7;
      if (top + panelHeight > topEdge + height - margin && rect.top - panelHeight - 7 >= topEdge + margin) top = rect.top - panelHeight - 7;
      top = Math.max(topEdge + margin, Math.min(top, topEdge + height - panelHeight - margin));
      panel.style.left = `${left}px`;
      panel.style.top = `${top}px`;
    };
    const render = () => {
      panel.replaceChildren();
      items = Array.from(commands() || []).filter((item) => item && typeof item.run === "function");
      let lastGroup = null;
      items.forEach((item, index) => {
        const group = item.group || "";
        if (group && group !== lastGroup) {
          const heading = document.createElement("div");
          heading.className = "roundtable-commands-group";
          heading.textContent = group;
          panel.append(heading);
        }
        lastGroup = group;
        const row = document.createElement("button");
        row.type = "button";
        row.className = "roundtable-commands-item";
        row.setAttribute("role", "menuitem");
        row.disabled = Boolean(item.disabled);
        row.dataset.commandIndex = String(index);
        const iconWrap = document.createElement("span"); iconWrap.className = "roundtable-commands-icon"; iconWrap.setAttribute("aria-hidden", "true"); const svg = window.RoundtableIcons?.iconNode?.(item.icon); if (svg) iconWrap.append(svg); row.append(iconWrap);
        const label = document.createElement("span");
        label.className = "roundtable-commands-label";
        label.textContent = String(item.label ?? "");
        row.append(label);
        panel.append(row);
      });
      if (!items.length) {
        const empty = document.createElement("div");
        empty.className = "roundtable-commands-empty";
        empty.textContent = "暂无可用操作";
        panel.append(empty);
      }
      place();
    };
    const close = (restoreFocus = false) => {
      if (!open) return;
      open = false;
      panel.hidden = true;
      button.setAttribute("aria-expanded", "false");
      notify("close");
      if (restoreFocus) button.focus();
    };
    const show = (focusFirst = false) => {
      if (button.disabled) return;
      render();
      open = true;
      panel.hidden = false;
      button.setAttribute("aria-expanded", "true");
      place();
      notify("open", { items: items.slice() });
      if (focusFirst) panel.querySelector(".roundtable-commands-item:not(:disabled)")?.focus();
    };

    button.addEventListener("click", () => open ? close() : show(true), listen);
    button.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown") { event.preventDefault(); if (!open) show(true); else panel.querySelector(".roundtable-commands-item:not(:disabled)")?.focus(); }
      if (event.key === "Escape" && open) { event.preventDefault(); event.stopPropagation(); close(true); }
    }, listen);
    panel.addEventListener("click", async (event) => {
      const row = event.target.closest("[data-command-index]");
      if (!row || row.disabled) return;
      const item = items[Number(row.dataset.commandIndex)];
      close(true);
      notify("select", { item });
      await item.run();
    }, listen);
    panel.addEventListener("keydown", (event) => {
      const rows = Array.from(panel.querySelectorAll(".roundtable-commands-item:not(:disabled)"));
      const index = rows.indexOf(document.activeElement);
      if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); close(true); }
      else if (event.key === "Tab") close(true);
      else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        const delta = event.key === "ArrowDown" ? 1 : -1;
        rows[(index + delta + rows.length) % rows.length]?.focus();
      } else if (event.key === "Home") { event.preventDefault(); rows[0]?.focus(); }
      else if (event.key === "End") { event.preventDefault(); rows.at(-1)?.focus(); }
    }, listen);
    document.addEventListener("pointerdown", (event) => {
      if (open && !root.contains(event.target) && !panel.contains(event.target)) close();
    }, { capture: true, ...listen });
    document.addEventListener("focusin", (event) => {
      if (open && event.target !== button && !panel.contains(event.target)) close();
    }, listen);
    document.addEventListener("keydown", (event) => { if (open && event.key === "Escape" && !panel.contains(event.target)) close(true); }, listen);
    window.addEventListener("resize", place, listen);
    window.addEventListener("scroll", place, { capture: true, ...listen });
    window.visualViewport?.addEventListener("resize", place, listen);
    window.visualViewport?.addEventListener("scroll", place, listen);

    const api = { open: () => show(false), close: () => close(false), refresh: render, destroy() { close(); listeners.abort(); panel.remove(); delete root.__roundtableCommands; } };
    root.__roundtableCommands = api;
    return api;
  }

  window.RoundtableCommands = { mount };
})();
