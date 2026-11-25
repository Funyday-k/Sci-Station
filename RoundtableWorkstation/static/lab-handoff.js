(() => {
  "use strict";
  const key = "sci-station.lab-handoff";
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
      chunks.push((kind === "project-graph" ? "项目图谱资料（供核对）" : "外部资源摘录（供核对）") + "\n来源服务："+server+"\n资源："+uri+"\n原文 SHA-256："+sha256+"\n\n"+excerpt.trim());
    }
    const text = chunks.join("\n\n");
    if(count(text)>12000) throw Error("会议草稿超过 12,000 字，请缩短工作指引、研究问题或摘录，或取消本次技能。");
    return text;
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
  const exposed={key,compose,receive};
  if(typeof module==="object" && module.exports){module.exports=exposed;return;}
  window.ScienceLabHandoff=exposed;
})();
