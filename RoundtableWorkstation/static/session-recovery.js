"use strict";
(() => {
  const panel = document.getElementById("session-recovery");
  const heading = panel.querySelector("summary");
  const list = panel.querySelector("ul");
  let entries = [];
  let rendered = "";

  function render(issues = []) {
    entries = issues;
    const key = JSON.stringify(entries);
    if (key === rendered) return;
    rendered = key;
    panel.hidden = entries.length === 0;
    heading.textContent = `存档恢复（${entries.length}）`;
    list.replaceChildren();
    for (const issue of entries) {
      const item = document.createElement("li");
      const id = document.createElement("strong");
      id.textContent = issue.id;
      const reason = document.createElement("span");
      reason.textContent = issue.reason;
      const path = document.createElement("code");
      path.textContent = issue.path;
      item.append(id, reason, path);
      list.append(item);
    }
  }

  function reveal(issue) {
    if (!issue) return;
    render([...entries.filter(entry => entry.id !== issue.id), issue]);
    panel.open = true;
  }

  window.RoundtableRecovery = Object.freeze({ render, reveal });
})();
