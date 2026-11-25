"use strict";
(() => {
  // Project IDs only travel to project-scoped destinations. A missing ID is
  // the shared workspace, including on a fresh launch or a browser Back.
  function route(path, params = {}) {
    const query = new URLSearchParams();
    for (const [name, value] of Object.entries(params)) {
      if (value) query.set(name, value);
    }
    return path + (query.size ? "?" + query : "");
  }
  function research(view, project) {
    return route("/research", {view: view === "overview" ? "" : view, project});
  }
  function destinations(url) {
    const project = url.searchParams.get("project");
    const view = url.searchParams.get("view");
    const active = url.pathname === "/lab" ? "lab"
      : url.pathname === "/studio" && ["settings", "plugins"].includes(view) ? "settings"
      : project || url.pathname === "/studio" || view === "projects" ? "projects"
      : url.pathname === "/reader" || view === "papers" ? "library"
      : view === "tasks" || url.searchParams.get("tab") === "calendar" ? "calendar"
      : url.pathname === "/tools" ? "library" : "home";
    return [
      ["home", "首页", research("overview")], ["projects", "项目", research("projects")],
      ["library", "文献库", research("papers")], ["calendar", "日历与任务", research("tasks")],
      ["lab", "AI 实验室", route("/lab", {project})], ["settings", "设置", "/studio?view=settings"]
    ].map(([key, name, href]) => ({key, name, href, active: active === key}));
  }
  function update() {
    const nav = document.querySelector("[data-workspace-nav]");
    if (!nav) return;
    const url = new URL(location.href);
    const links = destinations(url);
    const project = url.searchParams.get("project");
    const signature = JSON.stringify([links, project]);
    if (nav.dataset.signature === signature) return;
    nav.dataset.signature = signature;
    nav.replaceChildren(...links.map(({key, name, href, active}) => {
      const link = document.createElement("a");
      link.textContent = name;
      link.href = href;
      link.dataset.section = key;
      if (active) link.setAttribute("aria-current", "page");
      if (key === "settings" && url.pathname === "/studio") {
        // The meeting editor owns its unsent draft while settings is open.
        link.addEventListener("click", event => {
          if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return;
          if (!window.dispatchEvent(new CustomEvent("roundtable:navigate", {cancelable:true, detail:"settings"}))) {
            event.preventDefault();
          }
        });
      }
      return link;
    }));
    const back = document.querySelector("[data-project-back]");
    if (back) {
      back.hidden = !project;
      back.href = research("overview", project);
    }
  }
  const nav = Object.freeze({route, research, destinations, update});
  if (typeof module !== "undefined" && module.exports) module.exports = nav;
  if (typeof window !== "undefined") {
    window.SciStationNav = nav;
    update();
    window.addEventListener("pageshow", update);
  }
})();
