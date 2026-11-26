(() => {
  "use strict";

  function mount() {
    const root = document.getElementById("meeting-actions");
    const toggle = document.getElementById("meeting-actions-toggle");
    const panel = document.getElementById("meeting-actions-panel");
    if (!root || !toggle || !panel) return { close() {}, openSettings() {} };
    if (root.__roundtableActions) return root.__roundtableActions;

    toggle.type = "button";
    toggle.setAttribute("aria-haspopup", "true");
    toggle.setAttribute("aria-controls", panel.id);

    let closeTimer = 0;
    let hoverOpened = false;
    let pendingDialogCommand = null;
    const inside = (node) => root.contains(node);
    const visible = (node) => Boolean(node?.isConnected && node.getClientRects().length);

    function setOpen(open, focusNode) {
      window.clearTimeout(closeTimer);
      panel.hidden = !open;
      toggle.setAttribute("aria-expanded", String(open));
      if (open && focusNode) focusNode.focus();
    }
    function open(focusNode = null) {
      hoverOpened = false;
      setOpen(true, focusNode);
    }
    function close(restoreFocus = false) {
      hoverOpened = false;
      setOpen(false);
      if (restoreFocus && visible(toggle)) toggle.focus();
    }
    function openSettings(focusNode) {
      open(focusNode);
    }
    function scheduleHoverClose() {
      window.clearTimeout(closeTimer);
      closeTimer = window.setTimeout(() => {
        if (hoverOpened && !inside(document.activeElement)) close(false);
      }, 260);
    }

    panel.hidden = true;
    toggle.setAttribute("aria-expanded", "false");

    toggle.addEventListener("click", () => {
      if (panel.hidden) open();
      else if (hoverOpened) hoverOpened = false;
      else close(false);
    });
    toggle.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown") {
        event.preventDefault();
        open();
        const controls = panel.querySelectorAll("select:not(:disabled), [data-meeting-command]:not(:disabled)");
        Array.from(controls).find(visible)?.focus();
      } else if (event.key === "Escape" && !panel.hidden) {
        event.preventDefault();
        close(true);
      }
    });
    root.addEventListener("pointerenter", (event) => {
      if (event.pointerType === "mouse" && panel.hidden) {
        hoverOpened = true;
        setOpen(true);
      }
      window.clearTimeout(closeTimer);
    });
    root.addEventListener("pointerleave", (event) => {
      if (event.pointerType === "mouse") scheduleHoverClose();
    });
    panel.addEventListener("pointerenter", () => window.clearTimeout(closeTimer));
    panel.addEventListener("pointerleave", (event) => {
      if (event.pointerType === "mouse") scheduleHoverClose();
    });

    root.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && !panel.hidden) {
        event.preventDefault();
        close(true);
      }
    });
    document.addEventListener("focusin", (event) => {
      if (!panel.hidden && !inside(event.target)) close(false);
    });
    document.addEventListener("pointerdown", (event) => {
      if (!panel.hidden && !inside(event.target)) close(false);
    });

    for (const dialog of document.querySelectorAll("dialog")) {
      dialog.addEventListener("close", () => {
        const command = pendingDialogCommand;
        if (!command || command.getAttribute("aria-controls") !== dialog.id) return;
        pendingDialogCommand = null;
        if (!visible(command) || panel.hidden) {
          if (visible(toggle)) toggle.focus();
        }
      });
    }

    panel.addEventListener("click", (event) => {
      const command = event.target.closest("[data-meeting-command]");
      if (!command) return;
      close(false);
      const dialogId = command.getAttribute("aria-controls");
      const dialog = dialogId && document.getElementById(dialogId);
      pendingDialogCommand = dialog?.matches("dialog") ? command : null;
      if (command.matches("a[download]")) toggle.focus({preventScroll:true});
    });

    const api = { close, openSettings };
    root.__roundtableActions = api;
    return api;
  }

  window.RoundtableActions = { mount };
})();
