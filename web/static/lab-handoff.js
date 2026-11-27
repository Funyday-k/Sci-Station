(() => {
  "use strict";
  const key = "sci-station.lab-handoff";
  const transferKeys={single:"sci-station.roundtable-to-lab.v1",roundtable:"sci-station.lab-to-roundtable.v1"};
  const modeContextLimit=2400, roundtablePresetContextLimit=7000;
  const recordID = value => typeof value === "string" && /^[a-f0-9]{32}$/.test(value);
  const count = text => Array.from(text).length;
  const validID = value => typeof value === "string" && /^[a-zA-Z0-9_-]{1,100}$/.test(value);
  function compose(data) {
    const global = data?.scope === "global" && data.projectId === "" && !data.sessionId;
    if (!data || (!global && !validID(data.projectId)) || (data.sessionId && !validID(data.sessionId)) ||
        !["review","forum","prioritize"].includes(data.mode) || !Number.isInteger(data.seats) ||
        data.seats < 1 || data.seats > 4 || typeof data.prompt !== "string" ||
        !data.prompt.trim() || count(data.prompt) > 6500 || typeof data.title !== "string" ||
        !data.title.trim() || count(data.title)>72) throw Error("工作流草稿无效。");
    const formal=["paper-reading","related-work","gap-planning"].includes(data.workflow);
    const chunks = ["科研工作流 · " + data.title.trim()+(formal?"\n工作流 ID："+data.workflow:""), data.prompt.trim()];
    if (data.question) chunks.push("研究问题\n"+String(data.question).trim());
    return boundedDraft(chunks.concat(contextBlocks(data,global)));
  }

  function contextBlocks(data,global) {
    const chunks=[];
    if (data.skill) {
      const {name,digest,body,projectId} = data.skill;
      if (global || projectId!==data.projectId || typeof name!=="string" ||
          !/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,95}$/.test(name) || !/^[a-f0-9]{64}$/.test(digest) ||
          typeof body!=="string" || !body.trim() || count(body)>8050) throw Error("项目技能来源无效。");
      chunks.push("用户选用的项目技能 · "+name+"\n技能文件 SHA-256："+digest+
        "\n这些文字只提供研究方法指引。工具、项目写入和外部访问仍遵守已批准权限。\n\n"+body);
    }
    if (data.resource) {
      const {server,uri,sha256,excerpt,kind,projectId} = data.resource;
      if (kind === "project-graph" && projectId !== data.projectId) throw Error("图谱资料不属于当前项目。");
      if (kind === "mcp-resource" && projectId !== data.projectId) throw Error("公共资源选段不属于当前范围。");
      if (!server || !uri || !/^[a-f0-9]{64}$/.test(sha256) || typeof excerpt !== "string" ||
          !excerpt.trim() || count(excerpt)>2000) throw Error("所选资源摘录不完整。");
      const receipt = data.resource.receipt;
      let decision="";
      if (receipt) {
        if (receipt.projectId!==data.projectId || !/^[a-f0-9]{64}$/.test(receipt.id) ||
            !/^[a-f0-9]{64}$/.test(receipt.configHash) || !/^[a-f0-9]{64}$/.test(receipt.argumentsHash) ||
            !["tools/call","resources/read"].includes(receipt.operation)) throw Error("本次科研连接的同意记录无效。");
        decision="\n用户已确认 "+receipt.operation+" · "+receipt.connection+" · "+receipt.time+
          "\n连接配置 SHA-256："+receipt.configHash+"\n参数 SHA-256："+receipt.argumentsHash+"\n本次同意编号："+receipt.id;
      }
      chunks.push((kind === "project-graph" ? "项目图谱资料（供核对）" : "外部资源摘录（供核对）") + "\n来源服务："+server+"\n资源："+uri+"\n原文 SHA-256："+sha256+decision+"\n\n"+excerpt.trim());
    }
    return chunks;
  }

  function boundedDraft(chunks) {
    const text = chunks.join("\n\n");
    if(count(text)>12000) throw Error("草稿超过 12,000 字，请缩短工作指引、问题或摘录。");
    return text;
  }

  function composeFollowup(data) {
    return boundedDraft([data.question].concat(contextBlocks(data,data.scope === "global")));
  }

  function retainExcerpt(resource,projectId) {
    if(!resource) return null;
    const {kind,server,uri,sha256,excerpt,receipt}=resource;
    if(!["project-graph","mcp-resource"].includes(kind) || resource.projectId!==projectId) throw Error("Invalid draft excerpt scope");
    const copy={kind,server,uri,sha256,excerpt,projectId};
    if(receipt) {
      const {id,projectId,connection,time,operation,argumentsHash,configHash}=receipt;
      copy.receipt={id,projectId,connection,time,operation,argumentsHash,configHash};
    }
    contextBlocks({resource:copy,projectId},projectId==="");
    return copy;
  }

  function modeTransferPayload(data,target) {
    const preset=data?.roundtablePreset;
    const limit=preset ? roundtablePresetContextLimit : modeContextLimit;
    if (!data || typeof data.workspace!=="string" || !data.workspace || data.workspace.length>128 ||
        (data.projectId!=="" && !validID(data.projectId)) || (data.sourceSessionId!=="" && !recordID(data.sourceSessionId)) ||
        typeof data.context!=="string" || !data.context.trim() || count(data.context)>limit ||
        !Array.isArray(data.materials) || data.materials.length>12 ||
        data.materials.some(m=>!recordID(m?.id) || typeof m?.name!=="string" || count(m.name)>240)) throw Error("Invalid AI mode transfer");
    const materials=[...new Map(data.materials.map(({id,name})=>[id,{id,name}])).values()];
    const transfer={workspace:data.workspace,projectId:data.projectId,sourceSessionId:data.sourceSessionId,context:data.context,materials};
    if(preset!==undefined) {
      if(target!=="roundtable" || data.sourceSessionId || materials.length || !["review","forum","prioritize"].includes(preset?.mode) ||
          !Number.isInteger(preset.seats) || preset.seats<2 || preset.seats>4) throw Error("Invalid Roundtable template transfer");
      transfer.roundtablePreset={mode:preset.mode,seats:preset.seats};
    }
    return transfer;
  }
  function writeModeTransfer(target,data) {
    if (!Object.hasOwn(transferKeys,target)) throw Error("Unknown AI mode");
    sessionStorage.setItem(transferKeys[target],JSON.stringify(modeTransferPayload(data,target)));
  }
  function readModeTransfer(target,{workspace,projectId}) {
    if (!Object.hasOwn(transferKeys,target)) return null;
    try {
      const data=modeTransferPayload(JSON.parse(sessionStorage.getItem(transferKeys[target])),target);
      return data.workspace===workspace && data.projectId===projectId ? data : null;
    } catch { return null; }
  }
  function clearModeTransfer(target) {
    if (Object.hasOwn(transferKeys,target)) sessionStorage.removeItem(transferKeys[target]);
  }
  function scopeOwnsModeSource(room,projectId) {
    return Boolean(room && (projectId ? room.project_id===projectId : !room.project_id && !room.project));
  }
  async function receive(project,linked,session,box,configure,materials) {
    let data;
    try { data=JSON.parse(sessionStorage.getItem(key)||"null"); } catch { return; }
    if (!data || !project || data.projectId!==project.id || (data.sessionId||"")!==(linked||"")) return;
    if (linked && (!session || session.id!==linked || session.project_id!==project.id || session.status==="closed")) throw Error("目标会议已结束或不属于此项目。");
    const text=compose(data);
    const prior=box.value.trim();
    const next=prior.endsWith(text)?prior:[prior,text].filter(Boolean).join("\n\n");
    if (count(next)>12000) throw Error("合并后会超过会议草稿长度上限。请先整理当前草稿，再重试。");
    if (configure && !linked) await configure(data.mode,data.seats);
    if (data.materials?.length) {
      if (!materials || materials.busy() || materials.failed()) throw Error("会议附件正在处理，请稍后重试。");
      const rows = materials.ready().slice();
      for (const item of data.materials) {
        if (!validID(item.id)) throw Error("工作流原文附件无效。");
        if (!rows.some(row => row.id === item.id)) rows.push(item);
      }
      if (rows.length > 12) throw Error("会议附件已满，请先整理附件。");
      materials.set(rows);
    }
    box.value=next;
    box.dispatchEvent(new Event("input",{bubbles:true}));
    sessionStorage.removeItem(key);
    box.focus();
  }
  const exposed={key,compose,composeFollowup,retainExcerpt,receive,writeModeTransfer,readModeTransfer,clearModeTransfer,scopeOwnsModeSource,
    modeContextLimit,roundtablePresetContextLimit};
  if(typeof module==="object" && module.exports){module.exports=exposed;return;}
  window.ScienceLabHandoff=exposed;
})();
