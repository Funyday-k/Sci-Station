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
  function mountContextNavigation() {
    const context=document.getElementById("workspace-context");
    if(!context)return;
    const surface=document.body.dataset.workspaceSurface;
    const selector={research:"#sidebar",studio:".app > .sidebar",lab:".shell > aside","science-tools":".frame > aside"}[surface];
    const sidebar=selector && document.querySelector(selector);
    if(sidebar)context.append(sidebar);
    if(surface==="research") {
      const modules=document.getElementById("project-modules"), crumb=document.getElementById("crumb"), search=document.getElementById("search-open");
      if(modules && sidebar)sidebar.append(modules);
      if(crumb)document.getElementById("workspace-breadcrumb").replaceChildren(crumb);
      if(search)document.getElementById("workspace-tools").append(search);
      document.querySelector("#workarea > .topbar")?.remove();
    }
    if(surface==="studio") {
      const settings=document.querySelector(".settings-nav");
      if(settings)context.append(settings);
    }
  }
  function destinations(url) {
    const project = url.searchParams.get("project");
    const view = url.searchParams.get("view");
    const active = url.pathname === "/api-docs" ? "settings"
      : url.pathname === "/lab" ? "lab"
      : url.pathname === "/studio" ? (["settings", "plugins"].includes(view) ? "settings" : "roundtable")
      : project || view === "projects" ? "projects"
      : url.pathname === "/reader" || view === "papers" ? "library"
      : view === "tasks" || url.searchParams.get("tab") === "calendar" ? "calendar"
      : url.pathname === "/tools" ? "library" : "home";
    return [
      ["home", local("routeHome","首页","Home"), research("overview")],
      ["projects", local("routeProjects","项目","Projects"), research("projects")],
      ["library", local("routeLibrary","文献库","Library"), research("papers")],
      ["calendar", local("routeCalendar","日历与任务","Calendar"), research("calendar")],
      ["lab", local("routeAILab","AI 实验室","AI Lab"), route("/lab", {project})],
      ["roundtable", local("roundtable","圆桌","Roundtable"), route("/studio")],
      ["settings", local("routeSettings","设置","Settings"), route("/studio",{view:"settings",project})]
    ].map(([key,name,href]) => ({key,name,href,active:active===key}));
  }
  const globalSections={projects:"projects",library:"paper-library",calendar:"calendar",lab:"ai-lab"};
  const viewModules={overview:"projects",papers:"paper-library",notes:"wiki",tasks:"tasks",calendar:"calendar",materials:"materials",graph:"citation-graph",recommendations:"recommendation",lab:"ai-lab",code:"code",data:"datasets",experiments:"experiments",writing:"writing",theory:"theory-notes"};
  function enabled(config, id) {
    return !config || !id || config.modules.some(module=>module.id===id && module.effective);
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
  function update() {
    const nav = document.querySelector("[data-workspace-nav]");
    if (!nav) return;
    const url = currentURL();
    const visible = destinations(url).filter(item=>!globalModules || enabled(globalModules,globalSections[item.key]));
    const links=window.SciShellLayout?.top(visible) || visible;
    const project = url.searchParams.get("project");
    const signature = JSON.stringify([links,project]);
    if (nav.dataset.signature !== signature) {
      nav.dataset.signature = signature;
      nav.replaceChildren(...links.filter(link=>link.key!=="settings").map(destinationLink));
      document.querySelector("[data-workspace-settings]")?.replaceChildren(...links.filter(link=>link.key==="settings").map(destinationLink));
      const back = document.querySelector("[data-project-back]");
      back.hidden = !project || document.body.dataset.workspaceSurface==="research";
      back.href = research("overview",project);
      const backLabel=local("projectSpaceBackToProjects","返回当前项目","Back to project");
      back.innerHTML=window.RoundtableIcons?.icon("chevronLeft") || "";
      const caption=document.createElement("span");caption.textContent=backLabel;back.append(caption);
      back.setAttribute("aria-label",backLabel);
      const locationLabel=document.querySelector("[data-workspace-location]");
      if(locationLabel)locationLabel.textContent=links.find(link=>link.active)?.name || "Sci-Station";
    }
    window.SciShellLayout?.decorateTop(nav);
    window.SciContextRail?.update();
    remember();
  }
  function commitURL(value, mode = "replace") {
    const url = new URL(value, location.href);
    if (url.origin !== location.origin || !["push","replace"].includes(mode)) throw Error("无效的工作区导航");
    if (url.href !== location.href) {
      if (mode === "push") position++;
      history[mode+"State"]({...history.state, workspacePosition:position},"",url);
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
    if (["create","open","rename"].includes(action) && !mayDiscard()) return;
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
    if (!window.dispatchEvent(new CustomEvent("scistation:command",{detail:key,cancelable:true}))) return true;
    if (key === "back" || key === "forward") {history[key]();return true;}
    if (key === "openWorkspace" || key === "createWorkspace" || key === "revealWorkspace" || key==="renameWorkspace" || key==="forgetWorkspace") {
      rootAction({openWorkspace:"open",createWorkspace:"create",revealWorkspace:"reveal",renameWorkspace:"rename",forgetWorkspace:"forget"}[key]);return true;
    }
    const url=currentURL();
    if (["settings","roundtable","plugins"].includes(key) && url.pathname === "/studio" &&
        (key !== "roundtable" || !url.searchParams.has("project"))) {
      const view={roundtable:"table",settings:"settings",plugins:"plugins"}[key];
      if (!window.dispatchEvent(new CustomEvent("roundtable:navigate",{detail:view,cancelable:true}))) return true;
    }
    let destination=destinations(url).find(link=>link.key===key)?.href;
    if (key === "plugins") destination=route("/studio",{view:"plugins",project:url.searchParams.get("project")});
    if (["newProject","importIdentifier","importPDF","find"].includes(key)) {
      const view=key==="newProject"?"projects":key==="find"?"overview":"papers";
      destination=route("/research",{view,project:key==="newProject"?null:url.searchParams.get("project"),command:key});
    }
    if (!destination) return false;
    if (new URL(destination,url).href!==url.href) location.assign(destination);
    return true;
  }
  function keyCommand(event) {
    if (!(event.metaKey || event.ctrlKey) || event.altKey || event.isComposing) return "";
    const key=event.key.toLowerCase();
    if (key==="g") return event.shiftKey?"findPrevious":"findNext";
    if (event.shiftKey) return "";
    return {n:"newProject",o:"openWorkspace",f:"find",s:"save",i:"inspector",",":"settings","[":"back","]":"forward",backspace:"deletePaper",delete:"deletePaper"}[key] || "";
  }
  const nav=Object.freeze({route,research,destinations,update,commitURL,setHistoryGuard,command,keyCommand,viewModules,enabled});
  if (typeof module !== "undefined" && module.exports) module.exports = nav;
  if (typeof window !== "undefined") {
    window.SciStationNav=nav;
    mountContextNavigation();
    position = history.state?.workspacePosition || 0;
    history.replaceState({...history.state, workspacePosition:position},"");
    document.addEventListener("click",event=>{
      if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return;
      if (!event.target.closest(".workspace-bar,#workspace-sidebar")) return;
      const target=event.target.closest("[data-command],[data-section],[data-root-action]");
      if (!target) return;
      if (target.dataset.rootAction) {
        target.closest("details").open=false;
        rootAction(target.dataset.rootAction);
      } else if (command(target.dataset.command || target.dataset.section)) {
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
    if(window.SciStationModules) window.SciStationModules.load("").then(config=>{globalModules=config;update();}).catch(()=>{});
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
      if (!event.detail.project) {globalModules=event.detail.state;update();}
    });
  }
})();
