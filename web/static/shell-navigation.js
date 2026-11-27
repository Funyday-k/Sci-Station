"use strict";
(() => {
  const text=(zh,en)=>window.SciStationI18n?.text(zh,en) ?? zh;
  const url="/api/research/interface/layout";
  let state=null, writes=Promise.resolve();
  const narrow=matchMedia("(max-width:999px)");
  async function request(path,method="GET",body) {
    const options={method,cache:"no-store",headers:{Accept:"application/json"}};
    if(body!==undefined){options.headers["Content-Type"]="application/json";options.headers["X-Roundtable"]="1";options.body=JSON.stringify(body);}
    const response=await fetch(path,options);
    if(response.status===204)return null;
    const result=await response.json();
    if(!response.ok){const error=Error(result.error?.message || result.error || text("本机服务未能完成操作","Local service request failed"));error.status=response.status;throw error;}
    return result;
  }
  function updated(value) {
    state=value;
    updateProjectNav();
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
  let compactTreeOpen=false;
  function updateProjectNav() {
    const sidebar=document.getElementById("workspace-sidebar"), toggle=document.getElementById("workspace-nav-toggle");
    if(!sidebar || !toggle)return;
    const expanded=narrow.matches ? compactTreeOpen : state?.treeExpanded!==false;
    document.body.classList.toggle("workspace-nav-collapsed",!narrow.matches && !expanded);
    document.body.classList.toggle("workspace-nav-open",narrow.matches && expanded);
    sidebar.hidden=!expanded;
    sidebar.inert=!expanded;
    toggle.setAttribute("aria-expanded",String(expanded));
    const scrim=document.getElementById("workspace-nav-scrim");
    if(scrim)scrim.hidden=!narrow.matches || !expanded;
  }
  function dismissProjectNav(restoreFocus=false) {
    if(!compactTreeOpen)return;
    compactTreeOpen=false;
    updateProjectNav();
    if(restoreFocus)document.getElementById("workspace-nav-toggle")?.focus();
  }
  const treeToggle=document.getElementById("workspace-nav-toggle");
  if(treeToggle){
    treeToggle.onclick=()=>{
      if(!narrow.matches){
        if(state)save({treeExpanded:!state.treeExpanded}).catch(()=>{});
        return;
      }
      compactTreeOpen=!compactTreeOpen;
      updateProjectNav();
      if(compactTreeOpen){
        const sidebar=document.getElementById("workspace-sidebar");
        (sidebar.querySelector('[data-project][aria-current]') || sidebar.querySelector('[aria-current="page"]') || sidebar.querySelector("a"))?.focus();
      }
    };
    document.getElementById("workspace-nav-close").onclick=()=>dismissProjectNav(true);
    document.getElementById("workspace-nav-scrim").onclick=()=>dismissProjectNav(true);
    // Page menus handle Escape before the outer navigation drawer.
    window.addEventListener("keydown",event=>{
      if(event.defaultPrevented || event.key!=="Escape" || !compactTreeOpen || document.querySelector("dialog[open]"))return;
      const disclosure=event.target.closest?.("#workspace-sidebar details[open]") || document.querySelector("#workspace-sidebar .workspace-roots[open]");
      event.preventDefault();
      if(disclosure){disclosure.open=false;disclosure.querySelector("summary")?.focus();return;}
      dismissProjectNav(true);
    });
    document.addEventListener("click",event=>{
      if(!event.target.closest("#workspace-sidebar,#workspace-nav-toggle,#project-row-menu,#project-editor"))dismissProjectNav();
      else if(event.target.closest("#presets button,[data-settings-page]"))dismissProjectNav();
    });
    narrow.addEventListener("change",()=>{compactTreeOpen=false;updateProjectNav();});
    updateProjectNav();
  }
  function decorateTabs(container,ids){decorateStrip(container,ids,"tabs","tabKey");}
  window.SciShellLayout={request,ready,save,top,ordered,decorateTop,decorateTabs,dismissProjectNav,get state(){return state;}};
  for(const q of [narrow,matchMedia("(min-width:1400px)"),matchMedia("(min-width:760px)")])q.addEventListener("change",()=>window.SciResearch?.updateNav());
})();
