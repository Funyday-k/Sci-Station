(() => {
  "use strict";
  const base = "/api/research/lab/";
  function skillMatches(skill, query) {
    const record = [skill.name,skill.description,skill.author,skill.version,skill.risk,...(skill.capabilities || [])].join(" ").toLowerCase();
    return query.trim().toLowerCase().split(/\s+/).every(word=>record.includes(word));
  }
  function eligible(skill) {
    return skill.enabled && skill.trusted && !skill.invalid;
  }

  function mount({req,tell,resetResource}) {
    const $=id=>document.getElementById(id);
    let project="", title="", state=null, generation=0, review=null, remote=null;
    function clearPreview() {
      review=null;
      $("lab-skill-review").hidden=true;
      $("lab-skill-summary").textContent="";
      $("lab-skill-body").value="";
      $("lab-skill-install").hidden=true;
    }
    function clearResource() {
      remote?.abort();
      remote=null;
      resetResource();
      $("resource-panel").hidden=true;
    }
    function action(id, fn) {
      const control=$(id);
      control.addEventListener("click",async()=>{
        control.disabled=true;
        try { await fn(); } catch(error) { tell(error.message); }
        finally { control.disabled=false; }
      });
    }
    function drawSkills() {
      const selection=$("lab-skill-selected");
      const prior=selection.value;
      selection.replaceChildren(new Option("不使用项目技能",""),...state.skills.filter(eligible).map(row=>new Option(row.name,row.id)));
      if (state.skills.some(row=>row.id===prior && eligible(row))) selection.value=prior;
      const rows=[];
      const query=$("lab-skill-query").value;
      for (const row of state.skills) {
        if(!skillMatches(row,query)) continue;
        const item=document.createElement("li");
        const label=document.createElement("span");
        const status=row.invalid?"内容无法验证":(row.enabled?"已启用":"已停用")+" · "+(row.trusted?"已信任":"待信任");
        label.textContent=row.name+" · "+status+(row.description?" · "+row.description:"");
        item.append(label);
        const button=(text,fn)=>{
          const control=document.createElement("button");
          control.type="button";control.textContent=text;
          control.onclick=()=>Promise.resolve().then(fn).catch(error=>tell(error.message));
          item.append(control);
          return control;
        };
        if(!row.invalid) {
          button("查看正文",()=>viewStored(row));
          button(row.enabled?"停用":"启用",()=>editSkill(row,"enable",!row.enabled));
          const trust=button(row.trusted?"撤销信任":"信任此版本",()=>editSkill(row,"trust",!row.trusted));
          trust.disabled=!row.trusted && (review?.id!==row.id || review?.digest!==row.digest || !!review?.markdown);
        }
        button("移除",()=>editSkill(row,"remove",false));
        rows.push(item);
      }
      $("lab-skill-list").replaceChildren(...rows);
    }
    function showSkill(skill, markdown="") {
      review={id:skill.id,digest:skill.digest,markdown};
      const tools=(skill.allowedTools || []).join(", ");
      $("lab-skill-summary").textContent=[skill.name,skill.description,skill.author,skill.version,"SHA-256 "+skill.digest,
        tools?"声明的工具 "+tools:""].filter(Boolean).join(" · ");
      $("lab-skill-body").value=skill.body;
      $("lab-skill-review").hidden=false;
      $("lab-skill-install").hidden=!markdown;
      drawSkills();
    }
    async function viewStored(row) {
      const token=generation;
      const data=await req(base+"context/skill","POST",{projectId:project,id:row.id,digest:row.digest});
      if(token===generation)showSkill(data);
    }
    async function update(edit, question) {
      if(!state || !project || project==="@global")throw Error("请选择已打开的科研项目。");
      if(!confirm(question+"\n项目："+title)) { tell("已取消，项目设置未更改。"); return false; }
      const token=generation, owner=project;
      const config=await req(base+"context","PATCH",{projectId:owner,revision:state.revision,confirmed:true,...edit});
      if(token!==generation) return false;
      state=config;
      drawSkills();
      return true;
    }
    async function editSkill(row, operation, value) {
      const labels={enable:value?"启用":"停用",trust:value?"信任此版本":"撤销信任",remove:"移除"};
      if(await update({operation,id:row.id,digest:row.digest,value},labels[operation]+"「"+row.name+"」？")) {
        if(operation==="remove" && review?.id===row.id)clearPreview();
        tell("项目技能设置已保存。");
      }
    }
    async function select(id,name) {
      if(id===project) return;
      project=id;title=name;state=null;
      const token=++generation;
      clearPreview();clearResource();
      $("lab-skill-selected").replaceChildren();
      $("lab-skill-list").replaceChildren();
      $("lab-skill-query").value="";
      $("lab-skill-file").value="";
      $("endpoint").value="";
      $("lab-mcp-enabled").checked=false;
      $("lab-skills").hidden=true;
      $("mcp").hidden=id!=="@global";
      $("lab-mcp-settings").hidden=id==="@global";
      if(!id || id==="@global")return;
      const config=await req(base+"context?project="+encodeURIComponent(id));
      if(token!==generation)return;
      state=config;
      $("lab-skills").hidden=false;
      $("mcp").hidden=false;
      $("endpoint").value=config.endpoint;
      $("lab-mcp-enabled").checked=config.mcpEnabled;
      drawSkills();
    }
    async function resolve(projectId) {
      const id=$("lab-skill-selected").value;
      if(!id)return null;
      if(!state || projectId!==project)throw Error("当前科研项目已改变，请重新选择技能。");
      const skill=state.skills.find(row=>row.id===id && eligible(row));
      if(!skill)throw Error("此技能不可用，请重新选择。");
      const token=generation;
      const resolved=await req(base+"context/resolve","POST",{projectId,id,digest:skill.digest});
      if(token!==generation || $("lab-skill-selected").value!==id)throw Error("项目或所选技能已改变，请重试。");
      return {...resolved,projectId};
    }
    async function resource(operation,uri="") {
      const endpoint=$("endpoint").value.trim(), owner=project;
      if(!owner || !endpoint)throw Error("请选择工作范围并填写公开 HTTPS MCP 地址。");
      if(owner!=="@global" && (!state?.mcpEnabled || state.endpoint!==endpoint))throw Error("请先保存并启用当前项目的 MCP 服务。");
      const description=operation==="list"?"列出公开资源？":"读取公开资源「"+uri+"」？";
      if(!confirm(description+"\n服务："+endpoint+"\n工作范围："+(title || "全局会话"))) {
        tell("已取消，未连接外部服务。");
        return null;
      }
      if(operation==="list")clearResource();
      else resetResource();
      remote?.abort();
      const controller=new AbortController();
      remote=controller;
      const token=generation, projectId=owner==="@global"?"":owner;
      try {
        const data=await req(base+"resources/"+operation,"POST",{endpoint,uri,projectId,scope:owner==="@global"?"global":"",
          revision:state?.revision || 0,confirmed:true},controller.signal);
        if(token!==generation || remote!==controller || endpoint!==$("endpoint").value.trim())return null;
        return {data,projectId};
      } catch(error) {
        if(controller.signal.aborted || token!==generation)return null;
        throw Error(error.message+"。可重试，或继续使用项目原文和本地技能。");
      } finally {
        if(remote===controller)remote=null;
      }
    }
    $("lab-skill-query").oninput=()=>{if(state)drawSkills();};
    $("lab-skill-file").onchange=async()=>{
      const file=$("lab-skill-file").files[0], token=generation;
      clearPreview();
      if(!file)return;
      try {
        if(!/\.(?:md|markdown)$/i.test(file.name) || file.size>64*1024)throw Error("请选择不超过 64 KiB 的 Markdown 技能文件。");
        const markdown=new TextDecoder("utf-8",{fatal:true}).decode(await file.arrayBuffer());
        if(token!==generation)return;
        const data=await req(base+"context/preview","POST",{projectId:project,markdown});
        if(token===generation && $("lab-skill-file").files[0]===file)showSkill(data,markdown);
      } catch(error) { if(token===generation)tell(error.message); }
    };
    action("lab-skill-install",async()=>{
      if(!review?.markdown)return;
      const {id,digest,markdown}=review;
      if(await update({operation:"install",id,digest,markdown},"在当前项目复制这份 Markdown 技能？")) {
        clearPreview();
        $("lab-skill-file").value="";
        tell("技能已导入。请查看正文后选择启用和信任。");
      }
    });
    action("lab-mcp-save",async()=>{
      const endpoint=$("endpoint").value.trim(), value=$("lab-mcp-enabled").checked;
      if(await update({operation:"mcp",endpoint,value},"保存公开 MCP 资源设置？\n服务："+(endpoint || "无"))) {
        clearResource();tell("项目 MCP 设置已保存。");
      }
    });
    return {select,resolve,resource,clearResource};
  }
  if(typeof module==="object" && module.exports)module.exports={skillMatches,eligible,mount};
  else window.SciLabContext={mount};
})();
