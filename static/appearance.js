"use strict";
(() => {
  const root = document.documentElement;
  const systemMode = matchMedia("(prefers-color-scheme: dark)");
  const modeKey = "studio.appearance";
  const colorKey = "studio.color-theme";
  const textSizeKey = "studio.text-size";
  let mode = "system";

  function read(key) {
    try {
      return localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  function save(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch (_) {}
  }

  function renderMode() {
    const resolved = mode === "system" ? (systemMode.matches ? "dark" : "light") : mode;
    root.dataset.theme = resolved;
    root.style.colorScheme = resolved;
  }

  function setMode(value, persist = false) {
    mode = value === "light" || value === "dark" ? value : "system";
    renderMode();
    if (persist) save(modeKey, mode);
  }

  function setColorTheme(value, persist = false) {
    const theme = ["iris", "teal", "amber", "blue"].includes(value) ? value : "iris";
    root.dataset.colorTheme = theme;
    if (persist) save(colorKey, theme);
  }

  function setTextSize(value, persist = false) {
    const size = value === "large" || value === "extra-large" ? value : "standard";
    root.dataset.textSize = size;
    if (persist) save(textSizeKey, size);
  }

  function restore() {
    setMode(read(modeKey));
    setColorTheme(read(colorKey));
    setTextSize(read(textSizeKey));
  }

  restore();
  systemMode.addEventListener("change", renderMode);
  window.RoundtableAppearance = Object.freeze({setMode, setColorTheme, setTextSize, restore});
})();
