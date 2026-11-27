"use strict";
(() => {
  function route(path, params = {}) {
    const query = new URLSearchParams();
    for (const [name, value] of Object.entries(params)) {
      if (value) query.set(name, value);
    }
    return path + (query.size ? "?" + query : "");
  }
  function research(view, project) {
    if (view === "calendar") return route("/research", {view: "tasks", tab: "calendar", project});
    return route("/research", {view: view === "overview" ? "" : view, project});
  }
  const label = (zh, en) => globalThis.SciStationI18n?.text(zh, en) ?? zh;
  const local = (key, zh, en) => globalThis.SciStationI18n?.message?.(key) ?? label(zh, en);
  const projectNames = {
    get overview() { return local("routeOverview", "概览", "Overview"); },
    get projects() { return local("routeProjects", "项目", "Projects"); },
    get papers() { return local("routePapers", "论文", "Papers"); },
    get notes() { return local("routeWiki", "Wiki", "Wiki"); },
    get tasks() { return local("routeTasks", "任务", "Tasks"); },
    get materials() { return local("routeMaterials", "材料", "Materials"); },
    get graph() { return local("routeGraph", "图谱", "Graph"); },
    get meetings() { return local("roundtable", "圆桌", "Roundtable"); },
    get code() { return label("代码", "Code"); },
    get data() { return label("数据", "Data"); },
    get experiments() { return label("实验", "Experiments"); },
    get writing() { return label("写作", "Writing"); },
    get theory() { return label("理论笔记", "Theory Notes"); },
  };
  function projectBadge(project) {
    const color = /^#[0-9a-f]{6}$/i.test(project.colorHex) ? project.colorHex : "#4F7CAC";
    const symbol = /^[a-z0-9][a-z0-9.-]{0,79}$/i.test(project.iconName || "") ? project.iconName : "folder";
    return '<span class="project-badge" style="--project-color:' + color + '"><img alt="" src="/api/workspace/symbol/' + encodeURIComponent(symbol) + '"></span>';
  }
  const icons = {home:"dashboard",projects:"folder",library:"book",calendar:"agenda",lab:"model",roundtable:"chat",settings:"settings"};
  function destinationLink({key,name,href,active}) {
    const link=document.createElement("a"), caption=document.createElement("span");
    link.href=href;
    link.dataset.section=key;
    link.setAttribute("aria-label",name);
    link.title=name;
    link.innerHTML=window.RoundtableIcons?.icon(icons[key]) || "";
    caption.className="workspace-nav-label";
    caption.textContent=name;
    link.append(caption);
    if(active)link.setAttribute("aria-current","page");
    return link;
  }
  function isSettings(url) {
    return url.pathname === "/settings" ||
      (url.pathname === "/studio" && ["settings", "plugins"].includes(url.searchParams.get("view")));
  }
  function aiMode(url) {
    if (url.pathname === "/lab") return "single";
    if (url.pathname === "/studio" && !isSettings(url)) return "roundtable";
    return "";
  }

  function modeURL(mode, project) {
    return route(mode === "single" ? "/lab" : "/studio", project ? {project} : {scope:"global"});
  }

  let checkedProject;
  let projectAllowsChat = false;
  let modeGeneration = 0;
  let globalGeneration = 0;
  let globalChecked = false, projectChecked = false;
  function aiAvailable(project = "") {
    return project ? checkedProject === project && projectAllowsChat : enabled(globalModules, "ai-lab");
  }
  function checkScope(project) {
    if (project === checkedProject) return;
    const generation = ++modeGeneration;
    checkedProject = project;
    projectChecked = false;
    projectAllowsChat = false;
    if (!project || !window.SciStationModules) return;
    window.SciStationModules.load(project).then(config => {
      if (generation !== modeGeneration) return;
      projectChecked = true;
      projectAllowsChat = enabled(config, "ai-lab");
      update();
    }).catch(() => {
      if (generation === modeGeneration) { projectChecked = true; update(); }
    });
  }
  function updateModes(url) {
    const modes = document.getElementById("workspace-ai-modes");
    if (!modes) return;
    const current = aiMode(url);
    modes.hidden = !current;
    if (!current) return;
    const project = url.searchParams.get("project") || "";
    const available = aiAvailable(project);
    for (const item of modes.querySelectorAll("[data-ai-mode]")) {
      const mode = item.dataset.aiMode;
      if (!available) {
        item.removeAttribute("href");
        item.setAttribute("aria-disabled", "true");
        item.title = label("当前范围未启用 AI", "AI is unavailable in this scope");
      } else {
        item.removeAttribute("aria-disabled");
        item.removeAttribute("title");
        item.href = modeURL(mode, project);
      }
      if (mode === current) item.setAttribute("aria-current", "page");
      else item.removeAttribute("aria-current");
    }
  }

  function destinations(url) {
    const project = url.searchParams.get("project");
    const view = url.searchParams.get("view");
    const active = url.pathname === "/api-docs" || isSettings(url) ? "settings"
      : aiMode(url) ? "lab"
      : project || view === "projects" ? "projects"
      : url.pathname === "/reader" || view === "papers" ? "library"
      : view === "tasks" || url.searchParams.get("tab") === "calendar" ? "calendar"
      : url.pathname === "/tools" ? "library" : "home";
    return [
      ["home", local("routeHome","首页","Home"), research("overview")],
      ["projects", local("routeProjects","项目","Projects"), research("projects")],
      ["library", local("routeLibrary","文献库","Library"), research("papers")],
      ["calendar", local("routeCalendar","日历与任务","Calendar"), research("calendar")],
      ["lab", "AI", modeURL("single")],
      ["settings", local("routeSettings","设置","Settings"), route("/settings",{project})]
    ].map(([key,name,href]) => ({key,name,href,active:active===key}));
  }
  const globalSections={projects:"projects",library:"paper-library",calendar:"calendar",lab:"ai-lab"};
  const viewModules={overview:"projects",papers:"paper-library",notes:"wiki",tasks:"tasks",calendar:"calendar",materials:"materials",graph:"citation-graph",recommendations:"recommendation",lab:"ai-lab",meetings:"ai-lab",code:"code",data:"datasets",experiments:"experiments",writing:"writing",theory:"theory-notes"};
  function enabled(config, id) {
    return !id || (!config && id !== "ai-lab") || config?.modules?.some(module=>module.id===id && module.effective === true) === true;
  }
  let globalModules;
  function currentURL() {
    return new URL(location.href);
  }
  let saved = "";
  let position = 0;
  let historyGuard = mayDiscard;
  function remember(force = false) {
    const {pathname,search,hash} = currentURL();
    const route = pathname + search + hash;
    if (!force && saved === route) return;
    saved = route;
    // The event timestamp orders overlapping deliveries from different pages,
    // including pages restored from WebKit's back-forward cache.
    const event = performance.timeOrigin + performance.now();
    fetch("/api/workspace/navigation", {
      method:"POST", keepalive:true, headers:{"Content-Type":"application/json","X-Roundtable":"1"},
      body:JSON.stringify({route,event})
    }).then(response => {
      if (!response.ok) throw Error("无法保存工作区位置");
    }).catch(() => {
      if (saved === route) saved = "";
    });
  }
  function settingsReturnRoute() {
    const source = history.state?.settingsReturn;
    if (source) {
      const url = new URL(source, location.href);
      if (url.origin === location.origin && !isSettings(url)) return url.href;
    }
    return "/research";
  }
  function update() {
    const nav = document.querySelector("[data-workspace-nav]");
    if (!nav) return;
    const url = currentURL();
    const back = document.getElementById("workspace-settings-back");
    if (back && isSettings(url)) back.href = settingsReturnRoute();
    window.SciShellLayout?.updateNavigation();
    const project = url.searchParams.get("project");
    checkScope(project || "");
    const surface = document.querySelector(".workspace-region");
    if (surface) surface.inert = Boolean(aiMode(url) && !aiAvailable(project));
    if (aiMode(url) && (project ? projectChecked : globalChecked) && !aiAvailable(project)) {
      location.replace(research("overview", project));
      return;
    }
    updateModes(url);
    const returnToTable = document.getElementById("back-to-table");
    if (returnToTable) {
      const pluginsOpen = url.searchParams.get("section") === "plugins" || url.searchParams.get("view") === "plugins";
      returnToTable.hidden = !pluginsOpen || !aiAvailable(url.searchParams.get("project"));
    }
    const visible = destinations(url).filter(item=>enabled(globalModules,globalSections[item.key]));
    const links=window.SciShellLayout?.top(visible) || visible;
    const signature = JSON.stringify([links,project]);
    if (nav.dataset.signature !== signature) {
      nav.dataset.signature = signature;
      nav.replaceChildren(...links.filter(link=>link.key!=="settings").map(destinationLink));
      document.querySelector("[data-workspace-settings]")?.replaceChildren(...links.filter(link=>link.key==="settings").map(destinationLink));
      const locationLabel=document.querySelector("[data-workspace-location]");
      if(locationLabel)locationLabel.textContent=links.find(link=>link.active)?.name || "Sci-Station";
    }
    window.SciShellLayout?.decorateTop(nav);
    window.SciProjectSidebar?.render();
    window.SciContextRail?.update();
    remember();
  }
  function commitURL(value, mode = "replace") {
    const url = new URL(value, location.href);
    if (url.origin !== location.origin || !["push","replace"].includes(mode)) throw Error("无效的工作区导航");
    if (url.href !== location.href) {
      if (mode === "push") position++;
      const next = {...history.state, workspacePosition:position};
      if (isSettings(url) && !isSettings(currentURL())) {
        next.settingsReturn = location.href;
        next.settingsReturnPosition = mode === "push" ? position - 1 : null;
      } else if (!isSettings(url)) {
        delete next.settingsReturn;
        delete next.settingsReturnPosition;
      }
      history[mode+"State"](next,"",url);
    }
    update();
  }
  function mayDiscard() {
    return window.dispatchEvent(new Event("beforeunload",{cancelable:true})) ||
      window.confirm(label("有未保存的更改。继续离开？","Leave with unsaved changes?"));
  }
  function setHistoryGuard(guard) {
    historyGuard = guard;
  }
  async function rootAction(action) {
    if (["create","open","rename","choose-storage","default-storage"].includes(action) && !mayDiscard()) return;
    if (window.SciWorkspaceSetup && ["create","rename","forget"].includes(action))return window.SciWorkspaceSetup.run(action);
    try {
      const res = await fetch("/api/workspace/"+action,{
        method:"POST",headers:{"Content-Type":"application/json","X-Roundtable":"1"},body:"{}"
      });
      if (!res.ok) {
        const detail=await res.json().catch(()=>({}));
        throw Error(detail.error?.message || detail.error || local("workspaceActionFailed", "工作区操作失败", "Workspace action failed"));
      }
    } catch (error) { window.alert(error.message); }
  }
  function command(key) {
    if ((key === "lab" || key === "roundtable") && !aiAvailable()) return true;
    if (!window.dispatchEvent(new CustomEvent("scistation:command",{detail:key,cancelable:true}))) return true;
    if (key === "back" || key === "forward") {history[key]();return true;}
    if (key === "openWorkspace" || key === "createWorkspace" || key === "revealWorkspace" || key==="renameWorkspace" || key==="forgetWorkspace") {
      rootAction({openWorkspace:"open",createWorkspace:"create",revealWorkspace:"reveal",renameWorkspace:"rename",forgetWorkspace:"forget"}[key]);return true;
    }
    const url=currentURL();
    if (key === "plugins" && isSettings(url) && window.RoundtableSettingsNav) {
      window.RoundtableSettingsNav.select("plugins");
      return true;
    }
    if (key === "roundtable" && url.pathname === "/studio" && !isSettings(url) && !url.searchParams.has("project")) {
      if (!window.dispatchEvent(new CustomEvent("roundtable:navigate",{detail:"table",cancelable:true}))) return true;
    }
    let destination=destinations(url).find(link=>link.key===key)?.href;
    if (key === "roundtable") destination = modeURL("roundtable");
    if (key === "plugins") destination=route("/settings",{section:"plugins",project:url.searchParams.get("project")});
    if (["newProject","importIdentifier","importPDF","find"].includes(key)) {
      const view=key==="newProject"?"projects":key==="find"?"overview":"papers";
      destination=route("/research",{view,project:key==="newProject"?null:url.searchParams.get("project"),command:key});
    }
    if (!destination) return false;
    const nextURL = new URL(destination, url);
    if (nextURL.href !== url.href) {
      // Workstation pages omit referrers. Carry the exact source, including
      // its evidence anchor, across this navigation in the same window.
      if (isSettings(nextURL) && !isSettings(url)) {
        try { sessionStorage.setItem("sci.settings.entry", JSON.stringify({from:url.href, to:nextURL.href})); } catch {}
      }
      location.assign(destination);
    }
    return true;
  }
  function keyCommand(event) {
    if (!(event.metaKey || event.ctrlKey) || event.altKey || event.isComposing) return "";
    const key=event.key.toLowerCase();
    if (key==="g") return event.shiftKey?"findPrevious":"findNext";
    if (event.shiftKey) return "";
    return {n:"newProject",o:"openWorkspace",f:"find",s:"save",i:"inspector",",":"settings","[":"back","]":"forward",backspace:"deletePaper",delete:"deletePaper"}[key] || "";
  }
  const nav=Object.freeze({projectNames,projectBadge,route,research,isSettings,aiAvailable,aiMode,modeURL,destinations,update,commitURL,setHistoryGuard,command,keyCommand,viewModules,enabled});
  if (typeof module !== "undefined" && module.exports) module.exports = nav;
  if (typeof window !== "undefined") {
    window.SciStationNav=nav;
    document.getElementById("workspace-ai-modes")?.addEventListener("click", event => {
      const link = event.target.closest("[data-ai-mode]");
      if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return;
      event.preventDefault();
      if (!link.hasAttribute("href") || link.dataset.aiMode === aiMode(currentURL())) return;
      const change = new CustomEvent("sci:change-ai-mode", {
        cancelable:true, detail:{mode:link.dataset.aiMode, href:link.getAttribute("href")}
      });
      if (window.dispatchEvent(change)) location.assign(link.href);
    });
    position = history.state?.workspacePosition || 0;
    const initial = {...history.state, workspacePosition:position};
    try {
      const entry = JSON.parse(sessionStorage.getItem("sci.settings.entry"));
      sessionStorage.removeItem("sci.settings.entry");
      if (entry?.to === location.href && isSettings(currentURL())) {
        initial.settingsReturn = entry.from;
        initial.settingsReturnPosition = -1;
      }
    } catch {}
    history.replaceState(initial,"");
    const settingsBack = document.getElementById("workspace-settings-back");
    settingsBack?.addEventListener("click", event => {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      const from = history.state?.settingsReturnPosition;
      if (Number.isInteger(from) && from < position) history.go(from - position);
      else location.assign(settingsReturnRoute());
    });
    document.addEventListener("click",event=>{
      if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return;
      const rootButton = event.target.closest("[data-root-action]");
      if (rootButton) {
        event.preventDefault();
        rootAction(rootButton.dataset.rootAction);
        return;
      }
      if (!event.target.closest(".workspace-bar,#workspace-sidebar")) return;
      const target=event.target.closest("[data-command],[data-section]");
      if (!target) return;
      if (command(target.dataset.command || target.dataset.section)) {
        event.preventDefault();
        window.SciShellLayout?.dismissProjectNav();
      }
    });
    document.addEventListener("keydown",event=>{
      if (event.defaultPrevented || event.repeat) return;
      const key=keyCommand(event);
      if (key && command(key)) event.preventDefault();
    });
    update();
    if (window.SciStationModules) {
      const generation = ++globalGeneration;
      window.SciStationModules.load("").then(config => {
        if (generation === globalGeneration) { globalChecked = true; globalModules = config; update(); }
      }).catch(() => {
        if (generation === globalGeneration) { globalChecked = true; update(); }
      });
    }
    window.addEventListener("pageshow",event=>{
      if (event.persisted) { location.reload();return; }
      update();
    });
    let undoingPop = false;
    window.addEventListener("popstate", event => {
      const next=event.state?.workspacePosition;
      if (undoingPop) {
        undoingPop=false;
        event.stopImmediatePropagation();
        return;
      }
      if(Number.isInteger(next) && next!==position) {
        if (!historyGuard()) {
          undoingPop=true;
          event.stopImmediatePropagation();
          history.go(position-next);
          return;
        }
        position=next;
      }
      update();
    });
    window.addEventListener("hashchange",update);
    window.addEventListener("sci:language",update);
    window.addEventListener("sci:modules",event=>{
      if (!event.detail.project) {
        globalChecked = true;
        globalGeneration++;
        globalModules=event.detail.state;
        checkedProject=undefined;
        modeGeneration++;
      } else if (event.detail.project === checkedProject) {
        modeGeneration++;
        projectChecked = true;
        projectAllowsChat=enabled(event.detail.state, "ai-lab");
      }
      update();
    });
  }
})();
