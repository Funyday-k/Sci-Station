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
    const badge = nav.projectBadgeNode({colorHex,iconName});
    target.replaceChildren(badge);
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
    const editing=Boolean(project), pending=Boolean(project?.conversationResetPending);
    find("#project-editor-title").textContent=editing?text("编辑项目信息","Edit project info"):text("新建项目","New project");
    find("[data-submit]").textContent=editing?text("保存更改","Save changes"):text("创建项目","Create project");
    find("[data-path]").textContent=folder || text("默认使用 Sci-Station 管理的本地目录。","Sci-Station manages the local folder by default.");
    find("[data-submit]").hidden=pending;
    find("[data-reset-pending]").hidden=!pending;
    find("[data-retry-reset]").hidden=!pending;
    if(pending) find(".project-directory-settings").open=true;
    find("[data-folder]").hidden=pending || Boolean(project?.managedDirectory);
    find("[data-folder]").textContent=editing?text("重新选取项目文件夹…","Choose project folder again…"):text("选择已有文件夹…","Choose an existing folder…");
    find("[data-revoke]").hidden=pending || !project?.directoryGrant || project.managedDirectory;
    find("[data-archive]").hidden=pending || !editing;
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
      controls();setBusy(false);preview();
      (project?.conversationResetPending ? find("[data-retry-reset]") : field("name")).focus();
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
    if(project?.conversationResetPending || !form.reportValidity())return;
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
  const resetPrefix="sci-station.project-conversation-reset.";
  const seenResets=new Map();
  function storedJSON(value) {
    try {return JSON.parse(value);} catch {return null;}
  }
  function confirmReset(item, path) {
    const confirmation=document.getElementById("project-directory-reset");
    confirmation.querySelector("h2").textContent=text(`切换「${item.name}」的项目文件夹？`,`Switch the project folder for “${item.name}”?`);
    confirmation.querySelector("#project-directory-reset-path").textContent=path;
    confirmation.returnValue="cancel";
    confirmation.showModal();
    return new Promise(resolve=>confirmation.addEventListener("close",()=>resolve(confirmation.returnValue==="reset"),{once:true}));
  }
  function purgeDrafts(id, next) {
    const older=value=>Number(value || 0)<next;
    const encoded=encodeURIComponent(id), oldScope=key=>key===id || (key.startsWith(id+":") && older(key.slice(id.length+1)));
    const railDraftPrefix="sci.shell.draft.", railPointerPrefix="sci.shell.conversation.";
    const notePrefix="sci-station.meeting-note."+id+".";
    try {
      for(const key of Object.keys(sessionStorage)) {
        if(key.startsWith("sci-station.lab-mode-draft.v1:"+encoded+":")) {
          if(older(key.split(":")[4])) sessionStorage.removeItem(key);
        } else if(key.startsWith(railDraftPrefix)) {
          const scope=storedJSON(key.slice(railDraftPrefix.length));
          if(Array.isArray(scope) && scope[0]===id && older(scope[7])) sessionStorage.removeItem(key);
        } else if(key.startsWith("sci-station.roundtable-followup.v1.") ||
          ["sci-station.paper-handoff","sci-station.lab-handoff","sci-station.roundtable-to-lab.v1","sci-station.lab-to-roundtable.v1"].includes(key)) {
          const draft=storedJSON(sessionStorage.getItem(key));
          if(draft?.projectId===id && older(draft.projectGeneration)) sessionStorage.removeItem(key);
        }
      }
    } catch {}
    try {
      for(const key of ["studio.setup-drafts.v1","studio.continuous-drafts.v1"]) {
        const drafts=storedJSON(localStorage.getItem(key));
        if(!drafts || typeof drafts!=="object" || Array.isArray(drafts)) continue;
        const expired=Object.keys(drafts).filter(oldScope);
        if(expired.length) {
          for(const scope of expired) delete drafts[scope];
          localStorage.setItem(key,JSON.stringify(drafts));
        }
      }
      for(const key of Object.keys(localStorage)) {
        if(key.startsWith(railPointerPrefix) && oldScope(key.slice(railPointerPrefix.length))) localStorage.removeItem(key);
        if(key.startsWith(notePrefix) && older(storedJSON(localStorage.getItem(key))?.projectGeneration)) localStorage.removeItem(key);
      }
    } catch {}
  }
  function applyReset(id, next, navigate=true) {
    purgeDrafts(id,next);
    if(next>(seenResets.get(id) || 0)) {
      seenResets.set(id,next);
      window.dispatchEvent(new CustomEvent("sci:project-conversations-reset",{detail:{id,generation:next}}));
    }
    const url=new URL(location.href);
    if(!navigate || url.searchParams.get("project")!==id || nav.isSettings(url)) return false;
    for(const name of ["run","session","fromLab","fromRoundtable","tools"]) url.searchParams.delete(name);
    location.replace(url);
    return true;
  }
  window.addEventListener("storage",event=>{
    if(event.key?.startsWith(resetPrefix) && Number(event.newValue)>Number(event.oldValue || 0)) {
      const id=event.key.slice(resetPrefix.length);
      if(!applyReset(id,Number(event.newValue))) void notifyChanged({id}).catch(()=>{});
    }
  });
  function observeResets(persisted) {
    try {
      for(const key of Object.keys(localStorage).filter(key=>key.startsWith(resetPrefix))) {
        const id=key.slice(resetPrefix.length), next=Number(localStorage.getItem(key));
        if(persisted && next>(seenResets.get(id) || 0)) applyReset(id,next);
        else seenResets.set(id,next);
      }
    } catch {}
  }
  observeResets(false);
  window.addEventListener("pageshow",event=>{if(event.persisted) observeResets(true);});
  const projectEndpoint=id=>"/api/research/projects/"+encodeURIComponent(id);
  async function folderChanged(item,previous){
    project=item;folder=item.path;controls();
    const next=item.conversationGeneration || 0, advanced=next>(previous.conversationGeneration || 0);
    if(item.conversationResetPending) {
      if(advanced) applyReset(item.id,next,false);
      return;
    }
    if(advanced || previous.conversationResetPending) {
      try {localStorage.setItem(resetPrefix+item.id,String(next));} catch {}
      if(applyReset(item.id,next))return;
    }
    await notifyChanged(item);
  }
  async function recoverFolderChange(previous,error){
    if(error.status && error.code!=="reset_pending") throw error;
    const latest=await request(projectEndpoint(previous.id)).catch(()=>{throw error;});
    if(!latest.conversationResetPending && !previous.conversationResetPending &&
       (latest.conversationGeneration || 0)<=(previous.conversationGeneration || 0)) throw error;
    await folderChanged(latest,previous);
  }
  async function updateFolder(path,retry=false){
    const previous=project, endpoint=projectEndpoint(previous.id)+"/directory";
    const input={revision:previous.revision,path};
    if(retry) input.resetConversations=true;
    let item;
    try {item=await request(endpoint,"POST",input);}
    catch(error) {
      if(retry || error.status!==409 || error.code!=="confirmation_required") return recoverFolderChange(previous,error);
      if(!await confirmReset(previous,path)) return;
      try {item=await request(endpoint,"POST",{...input,resetConversations:true});}
      catch(error) {return recoverFolderChange(previous,error);}
    }
    await folderChanged(item,previous);
  }
  find("[data-folder]").onclick=async()=>{
    await perform(async()=>{
      const picked=await request("/api/studio/pick-project","POST",{});
      if(!picked.path)return;
      if(project)await updateFolder(picked.path);
      else{folder=picked.path;controls();}
    });
    if(dialog.open) (project?.conversationResetPending ? find("[data-retry-reset]") : find("[data-folder]")).focus();
  };
  find("[data-retry-reset]").onclick=async()=>{
    if(!project?.conversationResetPending)return;
    await perform(()=>updateFolder(project.path,true));
    if(dialog.open) (project?.conversationResetPending ? find("[data-retry-reset]") : find("[data-folder]")).focus();
  };
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
