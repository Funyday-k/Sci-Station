"use strict";
(() => {
  const dialog=document.getElementById("project-editor"),form=dialog.querySelector("form");
  const find=selector=>dialog.querySelector(selector),field=name=>form.elements.namedItem(name);
  const text=(zh,en)=>window.SciStationI18n?.text(zh,en) ?? zh;
  const {request}=window.SciShellLayout, nav=window.SciStationNav;
  const colors=["#A7C7E7","#B8E0D2","#F4B6C2","#CDB4DB","#F6D186","#BFC7D5"];
  const symbols=["folder","atom","sparkles","books.vertical","chart.xyaxis.line","brain"];
  let project=null, folder="", restore=null, busy=false, generation=0;
  function preview(){
    const colorHex=field("colorHex").value,iconName=field("iconName").value;
    const target=find("[data-preview]"),name=document.createElement("strong");
    target.innerHTML=nav.projectBadge({colorHex,iconName});
    name.textContent=field("name").value || text("项目预览","Project preview");target.append(name);
    for(const button of dialog.querySelectorAll("[data-color],[data-symbol]")){
      button.setAttribute("aria-pressed",String(button.dataset.color===colorHex || button.dataset.symbol===iconName));
    }
  }
  function swatches(values,key){
    return values.map(value=>{
      const button=document.createElement("button");button.type="button";button.dataset[key]=value;
      button.setAttribute("aria-label",value);button.title=value;
      if(key==="color")button.style.backgroundColor=value;
      else{const image=document.createElement("img");image.alt="";image.src="/api/workspace/symbol/"+value;button.append(image);}
      button.onclick=()=>{field(key==="color"?"colorHex":"iconName").value=value;preview();};
      return button;
    });
  }
  find("[data-colors]").replaceChildren(...swatches(colors,"color"));
  find("[data-symbols]").replaceChildren(...swatches(symbols,"symbol"));
  form.addEventListener("input",preview);
  function controls(){
    const editing=Boolean(project);
    find("#project-editor-title").textContent=editing?text("编辑项目信息","Edit project info"):text("新建项目","New project");
    find("[data-submit]").textContent=editing?text("保存更改","Save changes"):text("创建项目","Create project");
    find("[data-path]").textContent=folder || text("默认使用 Sci-Station 管理的本地目录。","Sci-Station manages the local folder by default.");
    find("[data-folder]").hidden=Boolean(project?.managedDirectory);
    find("[data-folder]").textContent=editing?text("重新授权文件夹…","Grant folder access again…"):text("选择已有文件夹…","Choose an existing folder…");
    find("[data-revoke]").hidden=!project?.directoryGrant || project.managedDirectory;
    find("[data-archive]").hidden=!editing;
  }
  function setBusy(value){
    busy=value;
    for(const element of form.elements)element.disabled=value;
  }
  async function perform(operation){
    if(busy)return;
    setBusy(true);find("[data-error]").textContent="";
    try{await operation();}
    catch(error){find("[data-error]").textContent=error.message;}
    finally{setBusy(false);}
  }
  async function open(id,focus){
    if(busy || dialog.open)return;
    const ticket=++generation;
    const opener=document.activeElement;
    restore=focus || (()=>{if(opener?.isConnected)opener.focus();});
    project=null;folder="";form.reset();find(".project-directory-settings").open=false;find("[data-error]").textContent="";
    controls();
    if(id)find("#project-editor-title").textContent=text("编辑项目信息","Edit project info");
    dialog.showModal();
    try{
      if(id){
        setBusy(true);
        project=await request("/api/research/projects/"+encodeURIComponent(id));
        if(ticket!==generation)return;
        folder=project.path;
      }
      for(const [name,value] of Object.entries({name:project?.name || "",description:project?.description || "",colorHex:project?.colorHex || "#4F7CAC",iconName:project?.iconName || "folder"}))field(name).value=value;
      controls();setBusy(false);preview();field("name").focus();
    }catch(error){
      setBusy(false);
      // A missing target must never turn into a new-project form.
      for(const element of form.elements)element.disabled=true;
      find("#project-editor-title").textContent=text("编辑项目信息","Edit project info");
      find("[data-error]").textContent=error.message;find("[data-cancel]").disabled=false;find("[data-cancel]").focus();
    }
  }
  function dismiss(){if(!busy)dialog.close();}
  find("[data-cancel]").onclick=dismiss;
  dialog.addEventListener("cancel",e=>{if(busy)e.preventDefault();});
  dialog.addEventListener("close",()=>{if(!dialog.open){generation++;setBusy(false);restore?.();restore=null;}});
  async function notifyChanged(item,creating=false){
    const research=window.SciResearch;
    if(creating){
      if(research)await research.load(item.id,"overview",{historyMode:"push"});
      else location.assign(nav.research("overview",item.id));
    }else{
      if(research)await research.refresh();
      else await window.SciProjectSidebar.refresh();
      window.dispatchEvent(new CustomEvent("sci:projects-changed",{detail:{project:item}}));
    }
  }
  form.onsubmit=e=>{
    e.preventDefault();
    if(!form.reportValidity())return;
    perform(async()=>{
      const values={name:field("name").value.trim(),description:field("description").value.trim(),colorHex:field("colorHex").value,iconName:field("iconName").value.trim()};
      const creating=!project;
      if(project)values.revision=project.revision;
      else if(folder)values.path=folder;
      const item=await request("/api/research/projects"+(project?"/"+encodeURIComponent(project.id):""),creating?"POST":"PATCH",values);
      project=item;folder=item.path;controls();
      await notifyChanged(item,creating);dialog.close();
    });
  };
  async function updateFolder(path){
    project=await request("/api/research/projects/"+encodeURIComponent(project.id)+"/directory","POST",{revision:project.revision,path});
    folder=project.path;controls();await notifyChanged(project);
  }
  find("[data-folder]").onclick=()=>perform(async()=>{
    const picked=await request("/api/studio/pick-project","POST",{});
    if(!picked.path)return;
    if(project)await updateFolder(picked.path);
    else{folder=picked.path;controls();}
  });
  find("[data-revoke]").onclick=()=>perform(()=>updateFolder(""));
  find("[data-archive]").onclick=()=>perform(async()=>{
    if(!project || !window.confirm(text("将项目归档并保留本地文件夹？","Archive this project and keep its local folder?")+"\n"+project.name))return;
    const active=new URL(location.href).searchParams.get("project");
    await request("/api/research/projects/"+encodeURIComponent(project.id)+"?revision="+project.revision,"DELETE",{});
    if(active===project.id){
      if(window.SciResearch)await window.SciResearch.load(null,"projects",{historyMode:"replace"});
      else location.assign(nav.research("projects"));
    }else await notifyChanged(project);
    dialog.close();
  });
  find("[data-archived]").onclick=()=>{
    dialog.close();
    if(window.SciResearch)window.SciResearch.formAction("archived-projects");
    else location.assign(nav.route("/research",{view:"projects",command:"archivedProjects"}));
  };
  window.SciProjectEditor={open};
})();
