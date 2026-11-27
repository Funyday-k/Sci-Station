"use strict";
(() => {
  const text=(zh,en)=>window.SciStationI18n?.text(zh,en) ?? zh;
  const url="/api/research/interface/layout";
  let state=null, writes=Promise.resolve();
  const narrow=matchMedia("(max-width:999px)");
  const assets=new Map();
  function loadAsset(path) {
    if(assets.has(path))return assets.get(path);
    const stylesheet=path.endsWith(".css");
    const element=document.createElement(stylesheet ? "link" : "script");
    if(stylesheet){element.rel="stylesheet";element.href=path;}
    else element.src=path;
    const ready=new Promise((resolve,reject)=>{
      element.onload=resolve;
      element.onerror=()=>{
        assets.delete(path);
        element.remove();
        reject(Error(text("无法加载界面资源，请重试。","Could not load an interface resource. Please try again.")));
      };
      document.head.append(element);
    });
    assets.set(path,ready);
    return ready;
  }
  async function request(path,method="GET",body) {
    const options={method,cache:"no-store",headers:{Accept:"application/json"}};
    if(body!==undefined){options.headers["Content-Type"]="application/json";options.headers["X-Roundtable"]="1";options.body=JSON.stringify(body);}
    const response=await fetch(path,options);
    if(response.status===204)return null;
    const result=await response.json();
    if(!response.ok){const error=Error(result.error?.message || result.error || text("本机服务未能完成操作","Local service request failed"));error.status=response.status;error.code=result.code;throw error;}
    return result;
  }
  function updated(value) {
    state=value;
    window.SciStationNav.update();
    window.SciResearch?.updateNav();
    window.dispatchEvent(new Event("sci:shell-layout"));
  }
  const ready=request(url).then(updated).catch(error=>{document.getElementById("rail-status").textContent=error.message;});
  function save(patch) {
    const operation=writes.then(()=>request(url,"PATCH",patch)).then(updated);
    writes=operation.catch(error=>{
      document.getElementById("rail-status").textContent=error.message;
      window.SciResearch?.toast(error.message);
    });
    return operation;
  }
  function ordered(items,pins,key) {
    const rank=item=>{const i=pins.indexOf(key(item));return i===-1 ? pins.length:i;};
    return items.slice().sort((a,b)=>rank(a)-rank(b));
  }
  function reorder(ids,from,before) {
    const result=ids.filter(id=>id!==from);
    if(!ids.includes(from) || from===before)return ids;
    const at=result.indexOf(before);
    result.splice(at===-1?result.length:at,0,from);
    return result;
  }
  function decorateStrip(container, order, kind, key) {
    const movable=order.filter(id=>kind==="tabs"?id!=="overview":id!=="settings");
    for(const link of container.querySelectorAll("a")) {
      const id=link.dataset[key];
      if(!movable.includes(id))continue;
      link.draggable=true;
      link.title=(link.getAttribute("aria-label") || link.textContent.trim())+" · "+text("拖动排序，或按 Option + 上下方向键","Drag to reorder, or use Alt + Up / Down");
      link.ondragstart=e=>{e.dataTransfer.effectAllowed="move";e.dataTransfer.setData("text/x-sci-"+kind,id);};
      link.ondragover=e=>{if(e.dataTransfer.types.includes("text/x-sci-"+kind))e.preventDefault();};
      const commit=ids=>{
        const field=kind==="tabs"?"tabOrder":"topOrder";
        // A module hidden in this project keeps its place when changing the
        // common workspace order.
        const prior=state[field] || [];
        const slots=[...prior,...movable.filter(id=>!prior.includes(id))];
        let index=0;
        save({[field]:slots.map(id=>movable.includes(id)?ids[index++]:id)}).then(()=>{
          const live=document.getElementById(container.id) || container;
          if(live.dataset.moduleProject!==container.dataset.moduleProject)return;
          const restored=Array.from(live.querySelectorAll("a")).find(a=>a.dataset[key]===id);
          if(restored) {const menu=restored.closest("details");if(menu)menu.open=true;restored.focus();}
        }).catch(()=>{});
      };
      link.ondrop=e=>{
        const from=e.dataTransfer.getData("text/x-sci-"+kind);
        if(!movable.includes(from))return;
        e.preventDefault();commit(reorder(movable,from,id));
      };
      link.onkeydown=e=>{
        if(!e.altKey || !["ArrowUp","ArrowDown","ArrowLeft","ArrowRight"].includes(e.key))return;
        const at=movable.indexOf(id),dest=at+(["ArrowDown","ArrowRight"].includes(e.key)?1:-1);
        if(dest<0 || dest>=movable.length)return;
        e.preventDefault();
        const next=movable.slice();next.splice(at,1);next.splice(dest,0,id);commit(next);
      };
    }
  }
  function top(links) {
    if(!state)return links;
    return [...ordered(links.filter(link=>link.key!=="settings"),state.topOrder,link=>link.key),...links.filter(link=>link.key==="settings")];
  }
  function decorateTop(nav) {
    if(state)decorateStrip(nav,Array.from(nav.querySelectorAll("a"),a=>a.dataset.section),"top","section");
  }
  const primary = document.getElementById("workspace-sidebar");
  const primaryToggle = document.getElementById("workspace-nav-toggle");
  const sessions = document.getElementById("workspace-session-sidebar");
  const sessionToggle = document.getElementById("workspace-session-toggle");
  let compactPanel = null, settingsMode = document.body.classList.contains("settings-mode");
  let settingsExpanded = true, sessionsExpanded = false;

  function setExpanded(panel, toggle, expanded) {
    panel.hidden = !expanded;
    panel.inert = !expanded;
    toggle.setAttribute("aria-expanded", String(expanded));
  }
  function updateNavigation() {
    const url = new URL(location.href);
    const settings = window.SciStationNav.isSettings(url);
    const modeChanged = settings !== settingsMode;
    if (modeChanged) {
      compactPanel = null;
      settingsExpanded = true;
      settingsMode = settings;
    }
    document.body.classList.toggle("settings-mode", settings);
    const treeOpen = narrow.matches ? compactPanel === primary : settings ? settingsExpanded : state?.treeExpanded !== false;
    const sessionsAvailable = sessions && !settings && window.SciStationNav.aiAvailable(url.searchParams.get("project"));
    const sessionPersisted = state ? state.sessionSidebar === true : sessionsExpanded;
    const chatsOpen = Boolean(sessionsAvailable && (narrow.matches ? compactPanel === sessions : sessionPersisted));
    document.body.classList.toggle("workspace-nav-collapsed", !narrow.matches && !treeOpen);
    document.body.classList.toggle("workspace-nav-open", narrow.matches && treeOpen);
    document.body.classList.toggle("workspace-session-expanded", chatsOpen);
    setExpanded(primary, primaryToggle, treeOpen);
    if (sessions) {
      sessionToggle.hidden = !sessionsAvailable;
      setExpanded(sessions, sessionToggle, chatsOpen);
    }
    document.getElementById("workspace-nav-scrim").hidden = !narrow.matches || !compactPanel;
    if (modeChanged) {
      const target = settings ? (treeOpen ? document.getElementById("workspace-settings-back") : primaryToggle) :
        (treeOpen ? document.querySelector("[data-workspace-settings] a") : primaryToggle);
      target?.focus({preventScroll:true});
    }
  }
  function dismissPanel(panel, restoreFocus) {
    if (!panel || compactPanel !== panel) return;
    compactPanel = null;
    updateNavigation();
    if (restoreFocus) (panel === primary ? primaryToggle : sessionToggle).focus();
  }
  const dismissProjectNav = (restoreFocus = false) => dismissPanel(primary, restoreFocus);
  const dismissSessionNav = (restoreFocus = false) => dismissPanel(sessions, restoreFocus);
  function togglePanel(panel) {
    if (narrow.matches) {
      if (compactPanel === panel) { dismissPanel(panel, true); return; }
      compactPanel = panel;
      updateNavigation();
      const selected = settingsMode ? panel.querySelector('[aria-selected="true"]') :
        panel.querySelector('[data-project][aria-current]') || panel.querySelector('[aria-current]');
      const fallback = panel === primary ? panel.querySelector("a") : panel.querySelector("#lab-new-thread,#new-session");
      (selected || fallback)?.focus();
      return;
    }
    if (panel === sessions) {
      const next = !(state ? state.sessionSidebar === true : sessionsExpanded);
      sessionsExpanded = next;
      if (state) {
        save({sessionSidebar: next}).then(() => {
          if (!next) sessionToggle.focus();
        }).catch(() => {});
        return;
      }
      updateNavigation();
      if (!next) sessionToggle.focus();
      return;
    } else if (settingsMode) {
      settingsExpanded = !settingsExpanded;
      updateNavigation();
      if (!settingsExpanded) primaryToggle.focus();
      return;
    } else {
      if (state) {
        const next = !state.treeExpanded;
        save({treeExpanded: next}).then(() => {
          if (!next) primaryToggle.focus();
        }).catch(() => {});
      }
      return;
    }
  }
  primaryToggle.onclick = () => togglePanel(primary);
  if (sessions) {
    sessionToggle.onclick = () => togglePanel(sessions);
    document.getElementById("workspace-session-close").onclick = () => {
      if (narrow.matches) dismissSessionNav(true);
      else togglePanel(sessions);
    };
  }
  document.getElementById("workspace-nav-close").onclick = () => dismissProjectNav(true);
  document.getElementById("workspace-nav-scrim").onclick = () => dismissPanel(compactPanel, true);
  // Let an open menu or dialog handle Escape before dismissing its drawer.
  window.addEventListener("keydown", event => {
    if (event.defaultPrevented || event.key !== "Escape" || !compactPanel || document.querySelector("dialog[open]")) return;
    event.preventDefault();
    const disclosure = event.target.closest?.("details[open]");
    if (disclosure && compactPanel.contains(disclosure)) {
      disclosure.open = false;
      disclosure.querySelector("summary")?.focus();
    } else dismissPanel(compactPanel, true);
  });
  document.addEventListener("click", event => {
    if (!compactPanel) return;
    if (event.target.closest("#presets button,[data-settings-page]")) {
      dismissPanel(compactPanel, true);
    } else if (!event.target.closest("#workspace-sidebar,#workspace-session-sidebar,#workspace-nav-toggle,#workspace-session-toggle,#project-row-menu,#history-menu,dialog")) {
      dismissPanel(compactPanel, false);
    }
  });
  document.addEventListener("focusin", event => {
    if (compactPanel && !event.target.closest("#workspace-sidebar,#workspace-session-sidebar,#workspace-nav-toggle,#workspace-session-toggle,#workspace-nav-scrim,#project-row-menu,#history-menu,dialog")) {
      dismissPanel(compactPanel, false);
    }
  });
  narrow.addEventListener("change", () => {
    const focused = document.activeElement;
    compactPanel = null;
    updateNavigation();
    if (primary.hidden && primary.contains(focused)) primaryToggle.focus();
    if (sessions?.hidden && sessions.contains(focused) && !sessionToggle.hidden) sessionToggle.focus();
  });
  updateNavigation();
  function decorateTabs(container,ids){decorateStrip(container,ids,"tabs","tabKey");}
  window.SciShellLayout={request,ready,save,loadAsset,top,ordered,decorateTop,decorateTabs,updateNavigation,dismissProjectNav,dismissSessionNav,get state(){return state;}};
  for(const q of [narrow,matchMedia("(min-width:1400px)"),matchMedia("(min-width:760px)")])q.addEventListener("change",()=>window.SciResearch?.updateNav());
})();
