"use strict";
(() => {
  function resolve(preference, system) {
    if (preference === "zh-Hans" || preference === "en") return preference;
    return String(system).toLowerCase().startsWith("zh") ? "zh-Hans" : "en";
  }

  if (typeof module !== "undefined" && module.exports) module.exports = {resolve};
  if (typeof window === "undefined") return;

  const originals = new WeakMap();
  // Keep the current copy until the selected root returns its language setting.
  let preference = "system";
  let language = "zh-Hans";
  let loadSerial = 0;
  const text = (zh, en) => language === "en" ? en : zh;

  function apply() {
    document.documentElement.lang = language;
    for (const element of document.querySelectorAll("[data-en], [data-en-aria-label]")) {
      if (!originals.has(element)) originals.set(element, {
        copy: element.textContent,
        ariaLabel: element.getAttribute("aria-label"),
      });
      const original = originals.get(element);
      if (element.dataset.en !== undefined) element.textContent = text(original.copy, element.dataset.en);
      if (element.dataset.enAriaLabel !== undefined) element.setAttribute("aria-label", text(original.ariaLabel, element.dataset.enAriaLabel));
    }
    window.dispatchEvent(new Event("sci:language"));
  }

  function update(next) {
    preference = next;
    language = resolve(next, navigator.language);
    apply();
  }

  async function request(init) {
    const response = await fetch("/api/research/interface", init);
    if (!response.ok) throw new Error(text("无法读取或保存界面语言。", "Could not read or save the interface language."));
    return (await response.json()).language;
  }

  async function refresh() {
    const serial = ++loadSerial;
    try {
      const next = await request();
      if (serial === loadSerial) update(next);
    } catch (_) {
      // Keep the existing visible language if a root is unavailable.
    }
  }

  async function save(next) {
    const selected = await request({
      method: "PATCH",
      headers: {"Content-Type": "application/json", "X-Roundtable": "1"},
      body: JSON.stringify({language: next}),
    });
    ++loadSerial;
    update(selected);
  }

  const ready = document.readyState === "loading"
    ? new Promise(resolve => document.addEventListener("DOMContentLoaded", () => resolve(refresh()), {once: true}))
    : refresh();
  window.SciStationI18n = Object.freeze({text, ready, get preference() { return preference; }});

  window.addEventListener("pageshow", event => { if (event.persisted) refresh(); });
  window.addEventListener("languagechange", () => { if (preference === "system") update(preference); });
  ready.then(() => {
    const picker = document.querySelector("#interface-language");
    const status = document.querySelector("#interface-language-status");
    if (!picker) return;
    picker.value = preference;
    picker.disabled = false;
    window.addEventListener("sci:language", () => { picker.value = preference; });
    picker.addEventListener("change", async () => {
      picker.disabled = true;
      try {
        await save(picker.value);
        status.textContent = text("已保存", "Saved");
      } catch (error) {
        picker.value = preference;
        status.textContent = error.message;
      } finally {
        picker.disabled = false;
      }
    });
  });
})();
