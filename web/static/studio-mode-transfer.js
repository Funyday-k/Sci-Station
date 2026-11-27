"use strict";
(() => {
  const length = text => Array.from(text).length;
  const text = (zh, en) => globalThis.SciStationI18n?.text(zh, en) ?? zh;
  const materialLimit = 12;

  function excerpt(value, limit) {
    const chars = Array.from(value.trim());
    return chars.length <= limit ? chars.join("") : chars.slice(0, limit-1).join("")+"…";
  }

  function roundtableMaterials(room, materials) {
    return [...new Map((room?.materials || []).concat(materials).map(({id,name}) => [id,{id,name}])).values()];
  }

  function roundtableTransfer({room, projectId, draft, materials, textOnly = false}) {
    const selected = textOnly ? [] : roundtableMaterials(room,materials);
    if (selected.length > materialLimit) throw Error(text(
      "切换模式最多可带入 12 份附件。请移除草稿中不需要的附件，或从新草稿切换。",
      "A mode switch can carry up to 12 attachments. Remove unused draft attachments or switch from a new draft."));
    let context = "";
    if (room) {
      context = text("圆桌议题", "Roundtable topic")+"\n"+excerpt(room.topic || "", 570);
      if (draft.trim()) context += "\n\n"+text("未发送的追问", "Unsent follow-up")+"\n"+excerpt(draft, 360);
      const turns = (room.rounds || []).flatMap(round => (round.turns || []).flatMap(turn =>
        turn.status === "done" && !turn.error && turn.text?.trim() ? [{
          round:round.number, name:turn.model_label || turn.model || turn.seat, body:turn.text
        }] : []));
      const heading = "\n\n"+text("最近已完成的公开发言", "Recent completed public messages");
      let messages = "";
      for (const turn of turns.reverse()) {
        const label = "\n\n"+text("第 "+turn.round+" 轮", "Round "+turn.round)+" · "+excerpt(turn.name || "", 60)+"\n";
        const remaining = 1800 - length(context+heading+messages+label);
        if (remaining < 90) break;
        messages = label+excerpt(turn.body, Math.min(460, remaining))+messages;
      }
      if (messages) context += heading+messages;
    } else if (draft.trim()) {
      context = text("未发送的圆桌议题", "Unsent Roundtable topic")+"\n"+excerpt(draft, 1750);
    }
    if (!context && selected.length) context = text("从圆桌草稿选取的附件", "Attachments selected from the Roundtable draft");
    return {projectId, sourceSessionId:room?.id || "", context, materials:selected};
  }

  function appendTransfer(input, materials, incoming) {
    const prior = input.trim() ? input : "";
    const next = prior.endsWith(incoming.context) ? input : [prior,incoming.context].filter(Boolean).join("\n\n");
    if (length(next) > 12000) throw Error(text("合并后超过 12,000 字。请缩短当前议题后重试。", "The combined draft exceeds 12,000 characters. Shorten the current topic and try again."));
    const rows = new Map(materials.map(material=>[material.id,material]));
    for (const item of incoming.materials) if (!rows.has(item.id)) rows.set(item.id,item);
    if (rows.size > materialLimit) throw Error(text("合并后超过 12 个附件。请先移除不需要的附件。", "The combined draft exceeds 12 attachments. Remove unused attachments first."));
    return {topic:next, materials:[...rows.values()]};
  }

  const api = Object.freeze({materialLimit,roundtableMaterials,roundtableTransfer,appendTransfer});
  if (typeof module === "object" && module.exports) module.exports=api;
  else window.SciStudioModeTransfer=api;
})();
