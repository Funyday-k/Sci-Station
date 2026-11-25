"use strict";
(() => {
  const formats = {
    "related-work": {tag:"research-comparison", columns:[["theme","主题"],["claim","比较结论"],["conditions","适用条件"]]},
    "gap-planning": {tag:"research-tasks", columns:[["title","候选任务"],["priority","优先级"],["reason","依据"],["acceptance","完成标准"]]}
  };
  function projectRows(topic, text, materials, round, tasks, projectId) {
    const id=String(topic).split("\n")[1]?.match(/^工作流 ID：(related-work|gap-planning)$/)?.[1];
    if(!id) return null;
    const spec=formats[id], lines=String(text).split(/\r?\n/);
    const start=lines.findIndex(line=>line.trim()==="\x60\x60\x60"+spec.tag);
    if(start<0)return null;
    const end=lines.findIndex((line,i)=>i>start && line.trim()==="\x60\x60\x60");
    const invalid={error:"结构化草稿的字段或引文不完整。请在会话中核对原始答复。"};
    if(end<0)return invalid;
    let values;
    try { values=JSON.parse(lines.slice(start+1,end).join("\n")); } catch{return invalid;}
    if(!Array.isArray(values) || values.length<1 || values.length>30)return invalid;
    const rows=[];
    for(const item of values){
      if(!item || spec.columns.some(([key])=>typeof item[key]!=="string"||!item[key].trim()))return invalid;
      if(!Array.isArray(item.evidence_refs)||!item.evidence_refs.length)return invalid;
      const refs=[];
      for(const id of new Set(item.evidence_refs)){
        if(typeof id!=="string"||!/^S[1-9]\d*$/.test(id))return invalid;
        const mat=materials[Number(id.slice(1))-1];
        if(!mat || Number(mat.added_round||0)>round)return invalid;
        const parts=String(mat.excerpt||"").split("\n\n"), head=parts.shift().split("\n");
        if(parts.join("\n\n").trim()==="" || !["Sci-Station · 论文原文摘录 v1","Sci-Station · 项目原文摘录 v1"].includes(head[0]))return invalid;
        let ref;
        try {ref=JSON.parse(head.slice(1).join("\n"));}catch{return invalid;}
        if(ref.projectId!==projectId)return invalid;
        refs.push({id,ref,quote:parts.join("\n\n")});
      }
      const duplicate=id==="gap-planning" && tasks?.find(t=>String(t.title).trim().toLowerCase()===item.title.trim().toLowerCase());
      rows.push({fields:spec.columns.map(([key])=>item[key]),refs,duplicate:duplicate?.title || ""});
    }
    return {title:id==="related-work"?"相关工作证据矩阵":"有引文的候选任务", headings:[...spec.columns.map(([,label])=>label),"原文证据"],rows,
      narrative:[...lines.slice(0,start),...lines.slice(end+1)].join("\n").trim()};
  }

  function render(data) {
    const wrapper=document.createElement("section");
    if(data.error){wrapper.textContent=data.error;return wrapper;}
    const table=document.createElement("table"), caption=table.createCaption();
    caption.textContent=data.title;
    const header=table.createTHead().insertRow();
    for(const label of data.headings){const th=document.createElement("th");th.scope="col";th.textContent=label;header.append(th);}
    const body=table.createTBody();
    for (const row of data.rows){
      const tr=body.insertRow();
      for(const value of row.fields)tr.insertCell().textContent=value;
      if(row.duplicate){const flag=document.createElement("p");flag.textContent="已有同名项目任务："+row.duplicate;tr.cells[0].append(flag);}
      const cell=tr.insertCell();
      for(const {id,ref,quote} of row.refs){
        const anchor=document.createElement("a");
        const evidence=ref.paperId?{paperId:ref.paperId,page:ref.page,sourceHash:ref.fingerprint,selectionStart:ref.selectionStart,
          selectionEnd:ref.selectionEnd,ocr:ref.ocr,quote}:{source:{kind:ref.kind,projectId:ref.projectId,id:ref.id,offset:ref.offset,end:ref.end},sourceHash:ref.sha256,quote};
        anchor.href=window.SciEvidence.href(ref.projectId,evidence);anchor.textContent="["+id+"] "+(ref.title||"原文");cell.append(anchor,document.createElement("br"));
      }
    }
    wrapper.className="lab-artifact";wrapper.append(table);return wrapper;
  }
  const api={projectRows,render};if(typeof module!=="undefined" && module.exports)module.exports=api;else window.SciLabArtifacts=api;
})();
