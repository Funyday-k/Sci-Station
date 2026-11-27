"use strict";
(() => {
  const levels = new Map([
    ["auto", ["自动", "Auto"]], ["none", ["无", "None"]], ["minimal", ["极低", "Minimal"]],
    ["low", ["低", "Low"]], ["medium", ["中", "Medium"]], ["high", ["高", "High"]],
    ["xhigh", ["极高", "Extra high"]], ["max", ["最大", "Max"]], ["ultra", ["超高", "Ultra"]]
  ]);
  const bound = new WeakMap();
  const text = (zh, en) => window.SciStationI18n?.text(zh, en) ?? zh;

  function label(value) {
    const names = levels.get(value);
    return names ? text(...names) : value;
  }

  function bind(input, output, onChange) {
    let values = [];
    let locked = false;
    input.type = "range";
    input.min = "0";
    input.step = "1";
    input.dataset.modelEffort = "";
    if (input.id) output.setAttribute("for", input.id);
    const selected = () => values[Number(input.value)] || "";
    function refresh() {
      const value = selected();
      const caption = value ? label(value) : text("无可选档位", "Unavailable");
      output.textContent = caption;
      input.setAttribute("aria-valuetext", caption);
      input.disabled = locked || values.length < 2;
    }
    function setOptions(available, preferred) {
      const offered = new Set((available || []).filter(value => typeof value === "string" && value));
      values = [...levels.keys()].filter(value => offered.has(value));
      for (const value of offered) if (!levels.has(value)) values.push(value);
      const index = values.indexOf(preferred);
      input.max = String(Math.max(0, values.length - 1));
      input.value = String(Math.max(0, index));
      refresh();
      return selected();
    }
    bound.set(input, refresh);
    input.addEventListener("input", () => {
      refresh();
      if (!input.disabled) onChange?.(selected());
    });
    setOptions([]);
    return {
      setOptions, refresh,
      get value() { return selected(); },
      setDisabled(disabled) { locked = disabled; refresh(); }
    };
  }
  window.addEventListener("sci:language", () => {
    for (const input of document.querySelectorAll("input[data-model-effort]")) bound.get(input)?.();
  });
  window.SciModelEffort = Object.freeze({bind, label});
})();
