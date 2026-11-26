(() => {
  "use strict";
  const base="/api/research/lab/connectors/";
  function configurationSummary(c) {
    const address=c.transport==="https" ? c.endpoint+(c.bearer?" · Bearer":"") :
      c.program+" "+JSON.stringify(c.arguments || [])+(c.programHash?"\n程序 SHA-256 "+c.programHash:"")+
      (c.scriptHash?"\n脚本 SHA-256 "+c.scriptHash:"");
    return c.id+"\n"+address+"\n工具 "+((c.tools || []).join(", ") || "仅资料")+"\n"+(c.enabled?"项目已启用":"项目已停用");
  }
  function mount({req,tell,resetResource,showPreview,settingsChanged}) {
    const $=id=>document.getElementById("connector-"+id);
    let project="",title="",state=null,generation=0,tools=[],pending=null;
    const active=()=>state?.connections?.find(c=>c.id===$("select").value);
    const isDesktop=()=>Boolean(window.sciStationConnectorSession);
    function clearOperation() {
      generation++;
      pending?.abort();
      pending=null;
      tools=[];
      $("resources-panel").hidden=true;
      $("tools-panel").hidden=true;
      $("args").value="{}";
      resetResource();
    }
    function transport() {
      $("https").hidden=$("transport").value!=="https";
      $("stdio").hidden=$("transport").value!=="stdio";
    }
    function fields(c) {
      clearOperation();
      $("id").value=c?.id || ""; $("id").readOnly=Boolean(c);
      $("transport").value=c?.transport || "https"; transport();
      $("endpoint").value=c?.endpoint || ""; $("bearer").checked=Boolean(c?.bearer);
      $("program").value=c?.program || ""; $("argv").value=JSON.stringify(c?.arguments || []);
      $("tools").value=(c?.tools || []).join("\n"); $("enabled").checked=Boolean(c?.enabled);
      $("token").value=""; $("stored").hidden=!c;
      $("token-panel").hidden=!c?.bearer; $("status").textContent="";
      if(c) status().catch(e=>tell(e.message));
    }
    function readForm() {
      const c={id:$("id").value.trim(),transport:$("transport").value,enabled:$("enabled").checked,
        tools:$("tools").value.split(/\s+/).filter(Boolean)};
      if(c.transport==="https"){c.endpoint=$("endpoint").value.trim();c.bearer=$("bearer").checked;}
      else {
        c.program=$("program").value.trim();
        try {c.arguments=JSON.parse($("argv").value.trim() || "[]");}catch { throw Error("启动参数需要 JSON 字符串数组。"); }
        if(!Array.isArray(c.arguments) || !c.arguments.every(s=>typeof s==="string"))throw Error("启动参数需要 JSON 字符串数组。");
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
    }
    async function save() {
      const c=readForm(), token=generation;
      if(!confirm("保存科研连接？\n项目 "+title+"\n"+configurationSummary(c)))return;
      const config=await post("save",{id:c.id,connection:c,confirmed:true});
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
      $("args").value="{}";resetResource();
    }
    async function operation(action) {
      const c=active();if(!c)throw Error("请选择已保存的科研连接。");
      const input={action};
      if(action==="resources/read"){input.target=$("resources").value;if(!input.target)return;}
      if(action==="tools/call"){
        const tool=tools.find(t=>t.name===$("tool").value);if(!tool)return;
        input.target=tool.name;input.definition=tool.definition;
        try{input.arguments=JSON.parse($("args").value);}catch{throw Error("请填写有效的 JSON 对象参数。");}
        if(!input.arguments || Array.isArray(input.arguments) || typeof input.arguments!=="object")throw Error("参数应为 JSON 对象。");
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
    const cancelPreview=()=>{pending?.abort();pending=null;resetResource();};
    $("tool").onchange=()=>{cancelPreview();schema();};$("resources").onchange=cancelPreview;
    $("args").oninput=cancelPreview;
    bind("save",save);
    for(const [id,label] of [["trust","仅信任已保存的此版本"],["untrust","撤销信任"],["remove","移除已保存的项目连接"],["set-token","存入钥匙串"],["clear-token","清除令牌"]])bind(id,()=>edit(id,label));
    for(const [id,path] of [["list","resources/list"],["read","resources/read"],["tool-list","tools/list"],["call","tools/call"]])bind(id,()=>operation(path));
    window.addEventListener("scistation:connector-session",()=>select(project,title));
    return {select,updateRevision(id,rev){if(project===id && state)state.revision=rev;}};
  }
  if(typeof module==="object" && module.exports)module.exports={mount,configurationSummary};
  else window.SciLabConnectors={mount};
})();
