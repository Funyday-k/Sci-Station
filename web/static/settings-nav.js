"use strict";
(() => {
  const nav = document.querySelector(".settings-nav");
  if (!nav) return;
  const compact = matchMedia("(max-width: 760px)");
  const updateDirection = () => nav.setAttribute("aria-orientation", compact.matches ? "horizontal" : "vertical");
  updateDirection();
  compact.addEventListener("change", updateDirection);
  const buttons = [...nav.querySelectorAll("[data-settings-page]")];
  function select(key, focus = false) {
    const selected = buttons.find((button) => button.dataset.settingsPage === key) || buttons[0];
    for (const button of buttons) {
      const active = button === selected;
      button.setAttribute("aria-selected", String(active));
      button.tabIndex = active ? 0 : -1;
      document.getElementById(button.getAttribute("aria-controls")).hidden = !active;
    }
    if (focus) selected.focus();
    window.dispatchEvent(new CustomEvent("roundtable:settings-page", { detail: selected.dataset.settingsPage }));
  }
  nav.addEventListener("click", (event) => {
    const button = event.target.closest("[data-settings-page]");
    if (button) select(button.dataset.settingsPage);
  });
  nav.addEventListener("keydown", (event) => {
    if (!["ArrowDown", "ArrowUp", "ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const current = buttons.indexOf(document.activeElement);
    const forward = event.key === "ArrowDown" || event.key === "ArrowRight";
    const index = event.key === "Home" ? 0 : event.key === "End" ? buttons.length - 1
      : (current + (forward ? 1 : -1) + buttons.length) % buttons.length;
    select(buttons[index].dataset.settingsPage, true);
  });
  window.RoundtableSettingsNav = { select };
  select(buttons.find((button) => button.getAttribute("aria-selected") === "true")?.dataset.settingsPage || "models");
})();
