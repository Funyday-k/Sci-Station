(() => {
  "use strict";
  const base="/api/research/lab/connectors/";
  function configurationSummary(c) {
    const address=c.transport==="https" ? c.endpoint+(c.bearer?" · Bearer":"") :
      c.program+" "+JSON.stringify(c.arguments || [])+(c.programHash?"\n程序 SHA-256 "+c.programHash:"")+
      (c.scriptHash?"\n脚本 SHA-256 "+c.scriptHash:"");
    return c.id+"\n"+address+"\n工具 "+((c.tools || []).join(", ") || "仅资料")+"\n"+(c.enabled?"项目已启用":"项目已停用");
  }
  function parseStringArray(raw) {
    const trimmed = String(raw ?? "").trim();
    if (!trimmed) return [];
    let parsed;
    try { parsed = JSON.parse(trimmed); }
    catch { throw Error("启动参数需要 JSON 字符串数组。"); }
    if (!Array.isArray(parsed) || !parsed.every(s => typeof s === "string")) {
      throw Error("启动参数需要 JSON 字符串数组。");
    }
    return parsed;
  }
  function hasAdvancedValues(c) {
    if (!c) return false;
    return c.transport === "stdio" ||
      Boolean(c.bearer) ||
      Boolean(c.program) ||
      (Array.isArray(c.arguments) && c.arguments.length > 0) ||
      (Array.isArray(c.tools) && c.tools.length > 0);
  }
  function mount({req,tell,resetResource,showPreview,settingsChanged}) {
    const $=id=>document.getElementById("connector-"+id);
    let project="",title="",state=null,generation=0,tools=[],pending=null;
    const active=()=>state?.connections?.find(c=>c.id===$("select").value);
    const isDesktop=()=>Boolean(window.sciStationConnectorSession);

    function setFieldError(id, msg) {
      const node = $(id);
      if (!node) return;
      node.textContent = msg || "";
      node.hidden = !msg;
    }

    function openAdvanced() {
      const details = $("advanced");
      if (details) details.open = true;
    }

    function syncAdvancedOpen(c) {
      const details = $("advanced");
      if (!details) return;
      details.open = hasAdvancedValues(c);
    }

    function renderArgvRows(items) {
      const container = $("argv-rows");
      if (!container) return;
      const list = Array.isArray(items) ? items : [];
      container.replaceChildren();
      list.forEach((value, index) => {
        const row = document.createElement("div");
        row.className = "structured-array-row";
        const input = document.createElement("input");
        input.type = "text";
        input.value = value;
        input.dataset.argvIndex = String(index);
        input.setAttribute("aria-label", `参数 ${index + 1}`);
        input.addEventListener("input", () => syncRawFromRows());
        const remove = document.createElement("button");
        remove.type = "button";
        remove.className = "button secondary small";
        remove.textContent = "移除";
        remove.setAttribute("aria-label", `移除参数 ${index + 1}`);
        remove.addEventListener("click", () => {
          const current = readRowValues();
          current.splice(index, 1);
          renderArgvRows(current);
          $("argv").value = JSON.stringify(current);
          setFieldError("argv-error", "");
        });
        row.append(input, remove);
        container.append(row);
      });
    }

    function readRowValues() {
      const container = $("argv-rows");
      if (!container) return [];
      return Array.from(container.querySelectorAll("input"), input => input.value);
    }

    function syncRawFromRows() {
      const values = readRowValues();
      $("argv").value = JSON.stringify(values);
      setFieldError("argv-error", "");
      setFieldError("form-error", "");
    }

    function syncRowsFromRaw() {
      try {
        const values = parseStringArray($("argv").value);
        setFieldError("argv-error", "");
        renderArgvRows(values);
      } catch (error) {
        setFieldError("argv-error", error.message);
        openAdvanced();
      }
    }

    function clearOperation() {
      generation++;
      pending?.abort();
      pending=null;
      tools=[];
      $("resources-panel").hidden=true;
      $("tools-panel").hidden=true;
      $("args").value="{}";
      setFieldError("call-error", "");
      resetResource();
    }
    function transport() {
      const isHttps = $("transport").value === "https";
      $("https").hidden = !isHttps;
      if ($("https-advanced")) $("https-advanced").hidden = !isHttps;
      $("stdio").hidden = isHttps;
      if (!isHttps) openAdvanced();
    }
    function fields(c) {
      clearOperation();
      setFieldError("form-error", "");
      setFieldError("argv-error", "");
      $("id").value=c?.id || ""; $("id").readOnly=Boolean(c);
      $("transport").value=c?.transport || "https"; transport();
      $("endpoint").value=c?.endpoint || ""; $("bearer").checked=Boolean(c?.bearer);
      $("program").value=c?.program || "";
      const args = Array.isArray(c?.arguments) ? c.arguments : [];
      $("argv").value=JSON.stringify(args);
      renderArgvRows(args);
      $("tools").value=(c?.tools || []).join("\n"); $("enabled").checked=Boolean(c?.enabled);
      $("token").value=""; $("stored").hidden=!c;
      $("token-panel").hidden=!c?.bearer; $("status").textContent="";
      syncAdvancedOpen(c);
      if(c) status().catch(e=>tell(e.message));
    }
    function readForm() {
      setFieldError("form-error", "");
      setFieldError("argv-error", "");
      const c={id:$("id").value.trim(),transport:$("transport").value,enabled:$("enabled").checked,
        tools:$("tools").value.split(/\s+/).filter(Boolean)};
      if(c.transport==="https"){
        c.endpoint=$("endpoint").value.trim();
        c.bearer=$("bearer").checked;
      } else {
        c.program=$("program").value.trim();
        try {
          c.arguments = parseStringArray($("argv").value);
        } catch (error) {
          setFieldError("argv-error", error.message);
          setFieldError("form-error", error.message);
          openAdvanced();
          throw error;
        }
        if (!c.program) {
          const err = Error("请填写本机 MCP 程序的绝对路径。");
          setFieldError("form-error", err.message);
          openAdvanced();
          throw err;
        }
      }
      return c;
    }
    function render(config,id) {
      state=config;
      const rows=config.connections || [];
      $("select").replaceChildren(new Option("添加连接",""),...rows.map(c=>new Option(c.id,c.id)));
      if(rows.some(c=>c.id===id))$("select").value=id;
      fields(active());
    }
    function post(path,more={},signal) {
      return req(base+path,"POST",{projectId:project,revision:state?.revision || 0,id:active()?.id || "",...more},signal);
    }
    async function select(id,name) {
      project=id;title=name;state=null;clearOperation();$("token").value="";
      const section=document.getElementById("lab-connections");
      section.hidden=true;
      if(!id || id==="@global" || !isDesktop())return;
      const ticket=generation;
      try {
        const config=await post("index");
        if(ticket!==generation)return;
        render(config,"");section.hidden=false;
      } catch(e) {if(ticket===generation)tell(e.message);}
    }
    async function status(){
      const token=generation;
      const value=await post("status");
      if(token!==generation)return;
      $("status").textContent=[value.trusted?"已信任此版本":"待信任",active()?.bearer?(value.configured?"钥匙串令牌已设置":"尚缺令牌"):""].filter(Boolean).join(" · ");
      $("trust").hidden=value.trusted;$("untrust").hidden=!value.trusted;
      if (active()?.bearer && !value.configured) openAdvanced();
    }
    async function save() {
      const c=readForm(), token=generation;
      if(!confirm("保存科研连接？\n项目 "+title+"\n"+configurationSummary(c)))return;
      let config;
      try {
        config=await post("save",{id:c.id,connection:c,confirmed:true});
      } catch (error) {
        if (token !== generation) return;
        if (error.status === 400 || error.status === 422) {
          setFieldError("form-error", error.message);
          if (hasAdvancedValues(c)) openAdvanced();
          return;
        }
        throw error;
      }
      if(token===generation){render(config,c.id);settingsChanged?.(project,config);tell("项目连接已保存。");}
    }
    async function edit(action,label){
      const c=active(), token=generation;if(!c)return;
      if(!confirm(label+"？\n项目 "+title+"\n"+configurationSummary(c)))return;
      const more={confirmed:true};
      if(action==="set-token"){more.token=$("token").value;$("token").value="";}
      const response=await post(action,more);
      if(token!==generation)return;
      clearOperation();
      if(action==="remove"){render(response,"");settingsChanged?.(project,response);}else await status();
      tell("科研连接设置已更新。");
    }
    function schema(){
      const tool=tools.find(t=>t.name===$("tool").value);
      $("schema").textContent=tool ? (tool.description || "")+"\n"+JSON.stringify(tool.inputSchema,null,2) : "";
      $("args").value="{}";setFieldError("call-error", "");resetResource();
    }
    async function operation(action) {
      const c=active();if(!c)throw Error("请选择已保存的科研连接。");
      const input={action};
      setFieldError("call-error", "");
      if(action==="resources/read"){input.target=$("resources").value;if(!input.target)return;}
      if(action==="tools/call"){
        const tool=tools.find(t=>t.name===$("tool").value);if(!tool)return;
        input.target=tool.name;input.definition=tool.definition;
        try{input.arguments=JSON.parse($("args").value);}catch{
          const err = Error("请填写有效的 JSON 对象参数。");
          setFieldError("call-error", err.message);
          throw err;
        }
        if(!input.arguments || Array.isArray(input.arguments) || typeof input.arguments!=="object"){
          const err = Error("参数应为 JSON 对象。");
          setFieldError("call-error", err.message);
          throw err;
        }
      }
      pending?.abort();resetResource();
      const ctrl=new AbortController(), token=generation;
      pending=ctrl;
      try{
        const grant=await post("prepare",input,ctrl.signal);
        if(token!==generation || pending!==ctrl)return;
        if(!confirm("仅允许本次操作？\n项目 "+title+"\n"+grant.summary)){tell("已取消，未连接科研服务。");return;}
        const result=await post("execute",{...input,ticket:grant.ticket,confirmed:true},ctrl.signal);
        if(token!==generation || pending!==ctrl)return;
        if(action==="resources/list"){
          $("resources").replaceChildren(...result.data.map(r=>new Option(r.name || r.uri,r.uri)));
          $("resources-panel").hidden=!result.data.length;
        }else if(action==="tools/list"){
          tools=result.data;
          $("tool").replaceChildren(...tools.map(t=>new Option(t.name,t.name)));
          $("tools-panel").hidden=!tools.length;schema();
        }else{showPreview({...result.data,projectId:project,receipt:result.receipt});}
        const count=Array.isArray(result.data)?" · "+result.data.length+" 项":"";
        tell("已完成 "+action+count+" · 本次同意编号 "+result.receipt.id);
      }catch(e){if(!ctrl.signal.aborted)throw Error(e.message+"。可继续使用本地资料。");}
      finally{if(pending===ctrl)pending=null;}
    }
    const bind=(id,fn)=>$(id).addEventListener("click",async()=>{
      $(id).disabled=true;
      try{await fn();}catch(e){tell(e.message);}
      finally{$(id).disabled=false;}
    });
    $("transport").onchange=transport;$("select").onchange=()=>fields(active());
    $("argv")?.addEventListener("input", syncRowsFromRaw);
    $("argv-add")?.addEventListener("click", () => {
      const current = readRowValues();
      current.push("");
      renderArgvRows(current);
      syncRawFromRows();
      const inputs = $("argv-rows")?.querySelectorAll("input");
      inputs?.[inputs.length - 1]?.focus();
    });
    const cancelPreview=()=>{pending?.abort();pending=null;resetResource();};
    $("tool").onchange=()=>{cancelPreview();schema();};$("resources").onchange=cancelPreview;
    $("args").oninput=()=>{setFieldError("call-error", "");cancelPreview();};
    bind("save",save);
    for(const [id,label] of [["trust","仅信任已保存的此版本"],["untrust","撤销信任"],["remove","移除已保存的项目连接"],["set-token","存入钥匙串"],["clear-token","清除令牌"]])bind(id,()=>edit(id,label));
    for(const [id,path] of [["list","resources/list"],["read","resources/read"],["tool-list","tools/list"],["call","tools/call"]])bind(id,()=>operation(path));
    window.addEventListener("scistation:connector-session",()=>select(project,title));
    return {select,updateRevision(id,rev){if(project===id && state)state.revision=rev;}};
  }
  if(typeof module==="object" && module.exports)module.exports={mount,configurationSummary,parseStringArray,hasAdvancedValues};
  else window.SciLabConnectors={mount};
})();
