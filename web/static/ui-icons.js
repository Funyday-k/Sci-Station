"use strict";

(() => {
  const sourceMarks = Object.freeze({
    codex: "/static/codex-avatar.svg",
    cursor: "/static/cursor-avatar.svg",
    claude: "/static/cli-claude.svg",
    gemini: "/static/cli-gemini.svg",
    copilot: "/static/cli-copilot.svg",
    opencode: "/static/cli-opencode.svg",
    qwen: "/static/cli-qwen.svg",
    aider: "/static/cli-aider.svg",
    kimi: "/static/cli-kimi.svg",
    pi: "/static/cli-pi.svg",
    amp: "/static/cli-amp.svg",
    droid: "/static/cli-droid.svg",
  });

  const folder = [["path", { d: "M3.5 7a2 2 0 0 1 2-2H10l2 2h6.5a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z" }]];
  const shapes = {
    dashboard: [
      ["rect", { x: "3", y: "3", width: "8", height: "7", rx: "1.5" }],
      ["rect", { x: "14", y: "3", width: "7", height: "11", rx: "1.5" }],
      ["rect", { x: "3", y: "13", width: "8", height: "8", rx: "1.5" }],
      ["rect", { x: "14", y: "17", width: "7", height: "4", rx: "1.5" }],
    ],
    book: [["path", { d: "M3 5.5c3.5-1.5 6.5-1 9 .7 2.5-1.7 5.5-2.2 9-.7v13c-3.5-1.5-6.5-1-9 .7-2.5-1.7-5.5-2.2-9-.7zM12 6.2v13" }]],
    search: [
      ["circle", { cx: "10", cy: "10", r: "6.3" }],
      ["path", { d: "m15 15 5.5 5.5" }],
    ],
    tools: [["path", { d: "m9 3 6 0m-4 0v6l-6 9a2 2 0 0 0 1.5 3h11a2 2 0 0 0 1.5-3l-6-9V3m-4 12h7" }]],
    // Lucide pin: https://github.com/lucide-icons/lucide/blob/main/icons/pin.svg
    // ISC license and copyright: research-vendor/LICENSE-Lucide.txt.
    pin: [
      ["path", { d: "M12 17v5" }],
      ["path", { d: "M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z" }],
    ],
    sidebar: [
      ["rect", { x: "3", y: "5", width: "18", height: "14", rx: "2" }],
      ["path", { d: "M9 5v14" }],
    ],
    refresh: [["path", { d: "M20 6v5h-5M4 18v-5h5M5 9a7.5 7.5 0 0 1 12.5-2.4L20 9M4 15l2.5 2.4A7.5 7.5 0 0 0 19 15" }]],
    close: [["path", { d: "m6.5 6.5 11 11m0-11-11 11" }]],
    more: [
      ["circle", { cx: "5.5", cy: "12", r: "1.4", fill: "currentColor", stroke: "none" }],
      ["circle", { cx: "12", cy: "12", r: "1.4", fill: "currentColor", stroke: "none" }],
      ["circle", { cx: "18.5", cy: "12", r: "1.4", fill: "currentColor", stroke: "none" }],
    ],
    settings: [
      ["path", { d: "m10 4 .6-1.5h2.8L14 4l.4 1.6 1.8 1 1.7-.5 1.5-.5 1.4 2.4-1.1 1.2-1.2 1.2v2.2l1.2 1.2 1.1 1.2-1.4 2.4-1.5-.5-1.7-.5-1.8 1-.4 1.6-.6 1.5h-2.8L10 19l-.4-1.6-1.8-1-1.7.5-1.5.5-1.4-2.4 1.1-1.2 1.2-1.2v-2.2L4.3 9.2 3.2 8l1.4-2.4 1.5.5 1.7.5 1.8-1z", transform: "translate(0 .5)" }],
      ["circle", { cx: "12", cy: "12", r: "2.8" }],
    ],
    plus: [["path", { d: "M12 5v14M5 12h14" }]],
    chevronLeft: [["path", { d: "m14.5 6.5-5.5 5.5 5.5 5.5" }]],
    chevronRight: [["path", { d: "m9.5 6.5 5.5 5.5-5.5 5.5" }]],
    arrowUpRight: [["path", { d: "M6 18 18 6m-9 0h9v9" }]],
    person: [
      ["circle", { cx: "12", cy: "8", r: "3.3" }],
      ["path", { d: "M5.5 20v-1a6.5 6.5 0 0 1 13 0v1" }],
    ],
    model: [
      ["rect", { x: "5.5", y: "5.5", width: "13", height: "13", rx: "3" }],
      ["path", { d: "M12 3v2.5m0 13V21M3 12h2.5m13 0H21" }],
      ["rect", { x: "10", y: "10", width: "4", height: "4", rx: ".75" }],
    ],
    subagent: [
      ["path", { d: "M7 8.5v7A2.5 2.5 0 0 0 9.5 18H15M9.5 6H15" }],
      ["circle", { cx: "7", cy: "6", r: "2.5" }],
      ["circle", { cx: "17.5", cy: "6", r: "2.5" }],
      ["circle", { cx: "17.5", cy: "18", r: "2.5" }],
    ],
    folder,
    folderPlus: [...folder, ["path", { d: "M12 10v6m-3-3h6" }]],
    import: [["path", { d: "M12 3.5V14m-3.5-3.5L12 14l3.5-3.5M4.5 15v3a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-3" }]],
    file: [
      ["path", { d: "M7 3.5h6.5L19 9v9.5a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2Z" }],
      ["path", { d: "M13.5 3.5V9H19M9 13h6m-6 4h6" }],
    ],
    copy: [
      ["rect", { x: "8.5", y: "8.5", width: "12", height: "12", rx: "2" }],
      ["path", { d: "M6.5 15h-1a2 2 0 0 1-2-2V5.5a2 2 0 0 1 2-2H13a2 2 0 0 1 2 2v1" }],
    ],
    chat: [
      ["path", { d: "M5.5 4.5h13a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H10l-4.5 3v-3a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2Z" }],
      ["path", { d: "M7.5 9h9m-9 3.5h6" }],
    ],
    image: [
      ["rect", { x: "3.5", y: "3.5", width: "17", height: "17", rx: "2.5" }],
      ["circle", { cx: "8.5", cy: "8.5", r: "1.4" }],
      ["path", { d: "m20.5 15-4.5-4.5-10 10" }],
    ],
    mention: [
      ["circle", { cx: "11.75", cy: "12", r: "3" }],
      ["path", { d: "M14.75 9v4a2 2 0 0 0 4 0v-1a7.75 7.75 0 1 0-3.2 6.25" }],
    ],
    sliders: [
      ["path", { d: "M4 6h5m4 0h7M4 12h9m4 0h3M4 18h3m4 0h9" }],
      ["path", { d: "M11 4v4m4 2v4m-6 2v4" }],
    ],
    continue: [["path", { d: "M5 7.5h9a4.5 4.5 0 0 1 0 9H7m3.5-3.5L7 16.5l3.5 3.5" }]],
    agenda: [
      ["rect", { x: "4.5", y: "3.5", width: "15", height: "17", rx: "2" }],
      ["path", { d: "M8.5 8.5h.5m3 0h3.5m-7 3.5h.5m3 0h3.5m-7 3.5h.5m3 0h3.5" }],
    ],
  };

  const SVG_NS = "http://www.w3.org/2000/svg";
  const viewBox = "0 0 24 24";
  const groupAttrs = {
    fill: "none",
    stroke: "currentColor",
    "stroke-width": "1.7",
    "stroke-linecap": "round",
    "stroke-linejoin": "round",
  };
  const attributes = 'fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"';

  function attrsToString(attrs) {
    return Object.entries(attrs).map(([k, v]) => `${k}="${v}"`).join(" ");
  }

  function drawing(name) {
    if (!Object.hasOwn(shapes, name)) return "";
    const parts = shapes[name].map(([tag, attrs]) => `<${tag} ${attrsToString(attrs)}/>`).join("");
    return `<g ${attributes}>${parts}</g>`;
  }

  function icon(name) {
    const content = drawing(name);
    return content
      ? `<svg class="ui-icon" viewBox="${viewBox}" width="20" height="20" aria-hidden="true" focusable="false">${content}</svg>`
      : "";
  }

  function populateSvg(svg, name) {
    if (!svg || !Object.hasOwn(shapes, name) || typeof document.createElementNS !== "function") return;
    const g = document.createElementNS(SVG_NS, "g");
    for (const [k, v] of Object.entries(groupAttrs)) g.setAttribute(k, v);
    for (const [tag, attrs] of shapes[name]) {
      const child = document.createElementNS(SVG_NS, tag);
      for (const [k, v] of Object.entries(attrs)) child.setAttribute(k, v);
      g.append(child);
    }
    svg.replaceChildren(g);
  }

  function iconNode(name) {
    if (!Object.hasOwn(shapes, name) || typeof document.createElementNS !== "function") return null;
    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "ui-icon");
    svg.setAttribute("viewBox", viewBox);
    svg.setAttribute("width", "20");
    svg.setAttribute("height", "20");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");
    populateSvg(svg, name);
    return svg;
  }

  function sourceMark(source) {
    const id = String(source || "").toLowerCase();
    return Object.hasOwn(sourceMarks, id) ? sourceMarks[id] : "";
  }

  window.RoundtableIcons = Object.freeze({ icon, iconNode, populateSvg, sourceMark });
  for (const node of document.querySelectorAll("svg[data-ui-icon]")) {
    node.setAttribute("viewBox", viewBox);
    node.setAttribute("focusable", "false");
    populateSvg(node, node.dataset.uiIcon);
  }
})();
