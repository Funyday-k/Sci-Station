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
    const result=await response.json();
    if(!response.ok){const error=Error(result.error?.message || result.error || text("本机服务未能完成操作","Local service request failed"));error.status=response.status;throw error;}
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
      link.title=text("拖动排序，或按 Option + 左右方向键","Drag to reorder, or use Alt + Left / Right");
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
          const restored=Array.from(container.querySelectorAll("a")).find(a=>a.dataset[key]===id);
          if(restored) {const menu=restored.closest("details");if(menu)menu.open=true;restored.focus();}
        }).catch(()=>{});
      };
      link.ondrop=e=>{
        const from=e.dataTransfer.getData("text/x-sci-"+kind);
        if(!movable.includes(from))return;
        e.preventDefault();commit(reorder(movable,from,id));
      };
      link.onkeydown=e=>{
        if(!e.altKey || !["ArrowLeft","ArrowRight"].includes(e.key))return;
        const at=movable.indexOf(id),dest=at+(e.key==="ArrowRight"?1:-1);
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
    const shell=document.getElementById("shell"),toggle=document.getElementById("nav-toggle");
    if(!toggle || !state)return;
    shell.classList.toggle("collapsed",!narrow.matches && !state.treeExpanded);
    shell.classList.toggle("mobile-open",narrow.matches && compactTreeOpen);
    toggle.setAttribute("aria-expanded",String(narrow.matches ? compactTreeOpen : state.treeExpanded));
  }
  function dismissProjectNav(restoreFocus=false) {
    if(!compactTreeOpen)return;
    compactTreeOpen=false;
    updateProjectNav();
    if(restoreFocus)document.getElementById("nav-toggle").focus();
  }
  const treeToggle=document.getElementById("nav-toggle");
  if(treeToggle){
    treeToggle.onclick=()=>{
      if(!state)return;
      if(!narrow.matches){save({treeExpanded:!state.treeExpanded}).catch(()=>{});return;}
      compactTreeOpen=!compactTreeOpen;
      updateProjectNav();
      if(compactTreeOpen){
        const tree=document.getElementById("projectnav");
        (tree.querySelector('[aria-current]') || tree.querySelector("a") || document.getElementById("new-project")).focus();
      }
    };
    document.addEventListener("keydown",event=>{
      if(event.key==="Escape" && compactTreeOpen){event.preventDefault();dismissProjectNav(true);}
    });
    document.addEventListener("click",event=>{
      if(!event.target.closest("#sidebar,#nav-toggle"))dismissProjectNav();
    });
    narrow.addEventListener("change",()=>{compactTreeOpen=false;updateProjectNav();});
  }
  function decorateProject(modules,tree) {
    if(!state)return;
    updateProjectNav();
    const tabs=Array.from(modules.querySelectorAll("a[data-tab-key]"));
    const sorted=[...tabs.filter(a=>a.dataset.tabKey==="overview"),...ordered(tabs.filter(a=>a.dataset.tabKey!=="overview"),state.tabOrder,a=>a.dataset.tabKey)];
    const limit=window.innerWidth>=1400?8:window.innerWidth>=1000?6:window.innerWidth>=760?4:2;
    const current=sorted.find(a=>a.getAttribute("aria-current")==="page");
    const visible=sorted.slice(0,limit);
    if(current && !visible.includes(current))visible[limit-1]=current;
    const overflow=sorted.filter(a=>!visible.includes(a));
    modules.replaceChildren(...visible);
    if(overflow.length) {
      const menu=document.createElement("details"),summary=document.createElement("summary"),items=document.createElement("div");
      menu.className="project-tab-overflow";summary.textContent=text("更多","More");items.append(...overflow);menu.append(summary,items);modules.append(menu);
    }
    decorateStrip(modules,sorted.map(a=>a.dataset.tabKey),"tabs","tabKey");
    const rows=ordered(Array.from(tree.querySelectorAll("a[data-project]")),state.pinnedProjects,a=>a.dataset.project);
    tree.replaceChildren(...rows.map(link=>{
      const row=document.createElement("div"),pin=document.createElement("button"),id=link.dataset.project;
      row.className="shell-project-row";
      pin.type="button";pin.textContent=state.pinnedProjects.includes(id)?"★":"☆";
      pin.setAttribute("aria-label",(state.pinnedProjects.includes(id)?text("取消固定 ","Unpin "):text("固定 ","Pin "))+link.textContent);
      pin.onclick=()=>save({projectId:id,pinned:!state.pinnedProjects.includes(id)}).catch(()=>{});
      row.append(link,pin);
      return row;
    }));
  }
  window.SciShellLayout={request,ready,save,top,decorateTop,decorateProject,dismissProjectNav,get state(){return state;}};
  for(const q of [narrow,matchMedia("(min-width:1400px)"),matchMedia("(min-width:760px)")])q.addEventListener("change",()=>window.SciResearch?.updateNav());
})();
