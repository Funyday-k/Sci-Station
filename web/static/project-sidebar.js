"use strict";
(() => {
  const nav = window.SciStationNav, layout = window.SciShellLayout;
  const tree = document.getElementById("projectnav"), menu = document.getElementById("project-row-menu");
  const text = (zh,en) => window.SciStationI18n?.text(zh,en) ?? zh;
  const icon = key => window.RoundtableIcons.icon(key);
  const glyphs = {overview:"dashboard",papers:"book",notes:"file",tasks:"agenda",materials:"folder",graph:"subagent",
    code:"file",data:"folder",experiments:"tools",writing:"file",theory:"book",calendar:"agenda",recommendations:"search",lab:"model"};
  const configs = new Map(), pending = new Map();
  let projects = [], signature = "", menuTarget = null, listVersion = 0;
  const observer = new IntersectionObserver(entries => {
    for(const entry of entries)if(entry.isIntersecting){
      observer.unobserve(entry.target);
      populate(entry.target);
    }
  }, {root:document.querySelector(".workspace-sidebar-scroll"),rootMargin:"300px"});
  function button(glyph,label) {
    const node=document.createElement("button");
    node.type="button";node.innerHTML=icon(glyph);node.title=label;node.setAttribute("aria-label",label);
    return node;
  }
  function activeTab(url) {
    if(url.pathname==="/lab")return "lab";
    if(url.pathname==="/reader")return "papers";
    if(url.pathname==="/studio")return ["settings","plugins"].includes(url.searchParams.get("view")) ? "" : "lab";
    if(url.pathname==="/tools")return {discover:"recommendations",calendar:"calendar"}[url.searchParams.get("tab")] || "";
    if(url.pathname!=="/research")return "";
    if(url.searchParams.get("view")==="meetings")return "lab";
    return url.searchParams.get("tab")==="calendar" ? "calendar" : url.searchParams.get("view") || "overview";
  }
  function moduleURL(key,id) {
    if(key==="lab")return nav.route("/lab",{project:id});
    if(key==="recommendations")return nav.route("/tools",{project:id,tab:"discover"});
    return nav.research(key,id);
  }
  async function populate(group) {
    const id=group.dataset.moduleProject;
    try{
      if(!configs.has(id)){
        if(!pending.has(id)){
          const request=window.SciStationModules.load(id).finally(()=>{if(pending.get(id)===request)pending.delete(id);});
          pending.set(id,request);
        }
        const result=await pending.get(id);
        if(!group.isConnected)return;
        if(!configs.has(id))configs.set(id,result);
      }
      if(!group.isConnected || group.hidden)return;
      const config=configs.get(id),url=new URL(location.href);
      const labels={...nav.projectNames, calendar:text("日历","Calendar"), recommendations:text("文献推荐","Recommendations"),lab:"AI"};
      let keys=Object.keys(glyphs).filter(key=>nav.enabled(config,nav.viewModules[key]));
      const hasOverview=keys.includes("overview");
      keys=layout.ordered(keys,config?.pinnedOrder || [],key=>nav.viewModules[key]);
      keys=layout.ordered(keys.filter(key=>key!=="overview"),layout.state.tabOrder,key=>key);
      if(hasOverview)keys.unshift("overview");
      group.replaceChildren(...keys.map(key=>{
        const a=document.createElement("a"), caption=document.createElement("span");
        a.dataset.tabKey=key;a.href=moduleURL(key,id);a.innerHTML=icon(glyphs[key]);caption.textContent=labels[key];a.append(caption);
        if(id===url.searchParams.get("project")){
          if(key===activeTab(url))a.setAttribute("aria-current","page");
          if(url.pathname==="/research" && key!=="calendar" && key!=="lab" && key!=="recommendations")a.dataset.view=key;
        }
        return a;
      }));
      layout.decorateTabs(group,keys);
    }catch(error){
      if(!group.isConnected)return;
      const retry=document.createElement("button");retry.type="button";retry.textContent=text("重试加载项目模块","Retry loading project modules");
      retry.title=error.message;retry.onclick=()=>populate(group);group.replaceChildren(retry);
    }
  }
  function rowFor(id){return tree.querySelector('[data-row-project="'+CSS.escape(id)+'"]');}
  function focusRow(id,part="link"){
    const target=rowFor(id)?.querySelector('[data-row-part="'+part+'"]');
    (target?.checkVisibility() ? target : document.getElementById("workspace-nav-toggle"))?.focus();
  }
  function changeFold(id,collapsed,part) {
    return layout.save({projectId:id,collapsed}).then(()=>focusRow(id,part));
  }
  function render() {
    const state=layout.state;
    if(!state)return;
    const url=new URL(location.href), active=url.searchParams.get("project");
    const next=JSON.stringify([projects.map(p=>[p.id,p.revision,p.name,p.colorHex,p.iconName]),active,activeTab(url),
      state.tabOrder,state.collapsedProjects,state.pinnedProjects,document.documentElement.lang]);
    if(next===signature)return;
    signature=next;
    const focused=document.activeElement, focusedRow=focused?.closest("[data-row-project]")?.dataset.rowProject;
    observer.disconnect();
    const groups=[];
    tree.replaceChildren(...layout.ordered(projects,state.pinnedProjects,p=>p.id).map(project=>{
      const id=project.id, current=id===active, collapsed=state.collapsedProjects.includes(id);
      const row=document.createElement("div"),link=document.createElement("a"),label=document.createElement("span");
      row.className="shell-project-row";row.dataset.rowProject=id;
      const fold=button("chevronRight",text(collapsed?"展开项目模块":"折叠项目模块",collapsed?"Expand project sections":"Collapse project sections")+" · "+project.name);
      fold.className="project-fold";fold.dataset.rowPart="fold";fold.setAttribute("aria-expanded",String(!collapsed));
      fold.onclick=()=>changeFold(id,!collapsed,"fold").catch(()=>{});
      link.href=nav.research("overview",id);link.dataset.project=id;link.dataset.rowPart="link";link.className="project-item";
      link.innerHTML=nav.projectBadge(project);label.textContent=project.name;link.append(label);link.title=project.name;
      if(current){link.classList.add("active");link.setAttribute("aria-current","true");}
      const pinned=state.pinnedProjects.includes(id);
      row.classList.toggle("pinned",pinned);
      const more=button(pinned?"pin":"more",text("项目操作","Project actions")+" · "+project.name);more.className="project-more";
      more.dataset.rowPart="more";more.setAttribute("aria-haspopup","menu");more.setAttribute("aria-expanded",String(menuTarget?.id===id));
      more.onclick=()=>openMenu(project,more);
      const group=document.createElement("nav");group.className="project-modules";group.dataset.moduleProject=id;
      group.id=current?"project-modules":"project-modules-"+id;group.hidden=collapsed;group.setAttribute("aria-label",project.name+" · "+text("项目模块","Project sections"));
      fold.setAttribute("aria-controls",group.id);
      row.oncontextmenu=e=>{
        if(group.contains(e.target))return;
        e.preventDefault();openMenu(project,link,{x:e.clientX,y:e.clientY});
      };
      row.onkeydown=e=>{
        if(group.contains(e.target))return;
        if(e.key==="ContextMenu" || e.shiftKey && e.key==="F10" || e.target===more && e.key==="ArrowDown"){
          e.preventDefault();openMenu(project,e.target);
        }else if(!e.altKey && ["ArrowLeft","ArrowRight"].includes(e.key)){
          const close=e.key==="ArrowLeft";
          e.preventDefault();if(collapsed!==close)changeFold(id,close,e.target.dataset.rowPart).catch(()=>{});
        }
      };
      row.append(fold,link,more,group);if(!collapsed)groups.push(group);return row;
    }));
    for(const group of groups){
      if(group.dataset.moduleProject===active || configs.has(group.dataset.moduleProject))populate(group);
      else observer.observe(group);
    }
    if(focusedRow && focused.dataset.rowPart)focusRow(focusedRow,focused.dataset.rowPart);
  }
  function closeMenu(restore=true) {
    const target=menuTarget;
    if(!target)return;
    menuTarget=null;menu.hidePopover();
    rowFor(target.id)?.querySelector(".project-more")?.setAttribute("aria-expanded","false");
    if(restore)focusRow(target.id,target.part);
  }
  function openMenu(project,opener,point) {
    closeMenu(false);
    const id=project.id,part=opener.dataset.rowPart || "link";
    menuTarget={id,part};
    rowFor(id).querySelector(".project-more").setAttribute("aria-expanded","true");
    const collapsed=layout.state.collapsedProjects.includes(id),pinned=layout.state.pinnedProjects.includes(id);
    const actions=[
      [text("打开项目","Open project"),()=>rowFor(id)?.querySelector("[data-project]")?.click()],
      [text(collapsed?"展开项目模块":"折叠项目模块",collapsed?"Expand sections":"Collapse sections"),()=>changeFold(id,!collapsed,part)],
      [text("编辑项目信息","Edit project info"),()=>window.SciProjectEditor.open(id,()=>focusRow(id,part))],
      [text(pinned?"取消固定项目":"固定项目",pinned?"Unpin project":"Pin project"),()=>layout.save({projectId:id,pinned:!pinned}).then(()=>focusRow(id,part))]
    ];
    menu.replaceChildren(...actions.map(([label,action])=>{
      const item=document.createElement("button");item.type="button";item.textContent=label;item.setAttribute("role","menuitem");item.tabIndex=-1;
      item.onclick=()=>{closeMenu();Promise.resolve(action()).catch(()=>{});};return item;
    }));
    menu.setAttribute("aria-label",project.name);
    const rect=opener.getBoundingClientRect();menu.showPopover();
    menu.style.left=Math.max(4,Math.min(point?.x ?? rect.left,innerWidth-menu.offsetWidth-4))+"px";
    menu.style.top=Math.max(4,Math.min(point?.y ?? rect.bottom,innerHeight-menu.offsetHeight-4))+"px";
    menu.firstElementChild.focus();
  }
  menu.onkeydown=e=>{
    const items=Array.from(menu.children),index=items.indexOf(document.activeElement);
    if(e.key==="Escape" || e.key==="Tab"){if(e.key==="Escape")e.preventDefault();closeMenu();return;}
    const to={ArrowDown:(index+1)%items.length,ArrowUp:(index+items.length-1)%items.length,Home:0,End:items.length-1}[e.key];
    if(to!==undefined){e.preventDefault();items[to].focus();}
  };
  document.addEventListener("pointerdown",e=>{if(menuTarget && !menu.contains(e.target))closeMenu(false);});
  window.addEventListener("resize",()=>closeMenu());
  async function refresh() {
    const version=++listVersion;
    const items=await layout.request("/api/research/projects");
    if(version===listVersion){projects=items;render();}
  }
  function setProjects(items,id,config){
    listVersion++;projects=items;
    if(id && config){
      if(config.revision!==configs.get(id)?.revision)signature="";
      configs.set(id,config);
    }
    render();
  }
  window.SciProjectSidebar={render,refresh,setProjects};
  document.getElementById("new-project").onclick=()=>window.SciProjectEditor.open(null);
  window.addEventListener("sci:modules",e=>{
    if(e.detail.project){pending.delete(e.detail.project);configs.set(e.detail.project,e.detail.state);}
    else {pending.clear();configs.clear();}
    signature="";render();
  });
  if(document.body.dataset.workspaceSurface!=="research")refresh().catch(error=>{tree.textContent=error.message;});
})();
