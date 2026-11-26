(() => {
  "use strict";
  const states = {done:"完成",error:"失败",cancelled:"已取消",interrupted:"已中断",running:"运行中",pending:"等待"};
  const events = {
    round_started:"开始运行", round_finished:"结束运行", seat_started:"开始请求模型", seat_done:"已保存回答",
    seat_error:"模型请求失败", cancel_requested:"停止请求", shutdown_requested:"应用关闭", recovered:"已恢复中断记录",
    read:"读取项目文件", read_statement:"读取历史发言", read_approval_requested:"请求读取授权",
    read_approval_allowed:"允许读取", read_approval_denied:"拒绝读取",
    child_started:"发起子任务", child_done:"子任务完成", child_error:"子任务失败", child_read:"子任务读取项目文件",
    child_read_statement:"子任务读取历史发言", child_read_error:"子任务读取文件失败", child_read_statement_error:"子任务读取发言失败",
    action_error:"工具动作失败或受限", protocol_error:"模型动作无效", write_outcome_unknown:"历史写入结果待查",
    write:"历史模型写入", write_failed:"历史模型写入失败", user_write:"已记录手动写入"
  };
  const sources = {recorded:"已记录摘录",shortened:"摘录受长度限制",invalid_locator:"来源定位无效",unavailable:"附件"};
  const reads = {text:"可读文本",failed:"提取失败",original_only:"原始附件",no_extractable_text:"没有可提取文本"};
  function runURL(room, project, scopeQuery, round) {
    const query = scopeQuery(project);
    if (round) query.set("round", round);
    return "/api/research/lab/runs/" + encodeURIComponent(room.id) + "?" + query;
  }
  function canRetry(room) {
    if (room?.seats?.length !== 1 || room.lab_thread?.archived_at || room.continuous?.status === "active" ||
        room.report || room.agenda_draft_status === "drafting") return false;
    const rounds = room.rounds || [];
    if (!rounds.length) return room.status === "ready";
    const last = rounds.at(-1);
    return room.status === "partial" && last.number === rounds.length && !last.auto &&
      last.turns?.length === 1 && last.turns[0].status !== "done";
  }
  function retry(req, room, project, scopeQuery) {
    return req(runURL(room, project, scopeQuery), "POST", {expected_round:room.rounds?.length || 0});
  }
  function element(tag, text) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function section(title, rows) {
    const block = element("section");
    const list = element("ul");
    if (rows.length) list.replaceChildren(...rows);
    block.append(element("h4", title), rows.length ? list : element("p", "无记录"));
    return block;
  }
  function displayDate(value) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? "" : parsed.toLocaleString();
  }
  function render(data, project) {
    const config = data.configuration, record = data.record;
    const fields = [
      ["结果", states[data.status] || "未记录"], ["开始时间", displayDate(data.started_at)],
      ["重试来源", record?.retry_of_round ? `第 ${record.retry_of_round} 轮` : ""],
      ["范围", data.scope === "global" ? "全局会话" : "当前项目"],
      ["模型", [config.model,config.model_source].filter(Boolean).join(" · ")],
      ["思考程度", config.effort], ["讨论模式", [config.preset,config.phase].filter(Boolean).join(" · ")],
      ["连接方式", config.transport], ["每步超时", config.timeout ? `${config.timeout} 秒` : ""],
      ["模型步骤上限", config.max_steps || ""], ["子任务上限", config.max_steps ? String(config.max_children) : ""],
      ["项目文件范围", config.may_edit_files ? "历史记录启用写入" : (data.scope === "global" ? "无项目文件权限" : "只读，写入需另行审核 CLI 编辑")],
      ["项目规则", data.rules?.length ? "见下方版本" : (data.rules ? "无" : "无版本记录")],
      ["提示词版本", config.prompt ? `${config.prompt.id} · v${config.prompt.version} · ${config.prompt.surface}` : (record ? "内置" : "无版本记录")],
      ["工作区提示词 SHA-256", config.prompt?.digest], ["本轮模型指引 SHA-256", record?.prompt_digest]
    ];
    if (config.budget) {
      const b = config.budget;
      fields.push(["读取授权",b.auto_read ? "按项目权限自动读取" : "逐次请求确认"],
        ["工具调用上限",String(b.max_calls)], ["上下文字符上限",String(b.context_chars)],
        ["工具结果字符上限",`${b.total_results} 总计 · ${b.per_result} 每次`]);
    } else fields.push(["工具预算", "无快照"]);
    const list = element("dl");
    for (const [label, value] of fields) if (value) list.append(element("dt", label), element("dd", value));
    const input = element("details");
    input.append(element("summary", "本轮保存的输入"));
    if (data.note) input.append(element("h4","本轮追问"), element("blockquote",data.note));
    input.append(element("h4","会话题目与工作指引"),element("blockquote",data.topic));
    const sourceItems = data.sources.map(source => {
      const item = element("li", [source.id,source.title,sources[source.status],reads[source.read_status]].filter(Boolean).join(" · "));
      if (source.evidence) {
        const link = element("a",window.SciEvidence.label(source.evidence));
        link.href = window.SciEvidence.href(project.id, source.evidence);
        item.append(document.createTextNode(" · "),link);
        if (source.evidence.sourceHash) item.append(element("code",source.evidence.sourceHash));
      }
      return item;
    });
    const revisions = [...data.files, ...data.plugins, ...(data.rules || []).map(rule => ({name:rule.path,version:rule.digest}))]
      .map(entry => element("li", [entry.name,entry.version].filter(Boolean).join(" · ")));
    const timeline = data.timeline.map(event => {
      const item = element("li", [displayDate(event.at),events[event.kind] || event.kind,event.detail].filter(Boolean).join(" · "));
      item.dataset.eventKind = event.kind;
      if (event.file_version) item.append(element("code",event.file_version));
      return item;
    });
    return [list,input,section("本轮来源",sourceItems),section("文件与规则版本",revisions),section("运行时间线",timeline)];
  }
  function mount({req, scopeQuery}) {
    const $ = id => document.getElementById(id);
    const panel = $("lab-run-audit"), select = $("lab-audit-round"), status = $("lab-audit-status"), content = $("lab-audit-content");
    let currentRoom, currentProject, last = "", key = "", token = 0;
    async function load() {
      const round = select.value, room = currentRoom;
      if (!panel.open || !room || !round) return;
      const refresh = room.status === "running" && round === last ? room.updated_at : "settled";
      const next = `${room.id}/${round}/${refresh}`;
      if (key === next) return;
      key = next;
      const generation = ++token;
      const project = currentProject;
      status.textContent = "正在读取运行记录…";
      content.replaceChildren();
      try {
        const data = await req(runURL(room, project, scopeQuery, round));
        if (generation !== token) return;
        content.replaceChildren(...render(data,project));
        status.textContent = "";
      } catch(error) {
        if (generation !== token) return;
        key = "";
        status.textContent = error.message;
      }
    }
    function show(room, project) {
      if (room?.id !== currentRoom?.id) {
        token++;
        key = last = "";
        panel.open = false;
        content.replaceChildren();
        status.textContent = "";
      }
      currentRoom = room;
      currentProject = project;
      const rounds = room?.rounds || [];
      panel.hidden = !rounds.length;
      const latest = String(rounds.at(-1)?.number || "");
      if (latest !== last || !select.options.length) {
        const selected = select.value;
        select.replaceChildren(...rounds.slice().reverse().map(r => new Option(`第 ${r.number} 轮`,String(r.number))));
        select.value = last && selected !== last && rounds.some(r => String(r.number) === selected) ? selected : latest;
        last = latest;
      }
      void load();
    }
    panel.addEventListener("toggle",load);
    select.addEventListener("change",load);
    return {show};
  }
  const api = {mount, canRetry, retry};
  if (typeof module === "object" && module.exports) module.exports = api;
  else window.SciLabRunAudit = api;
})();
