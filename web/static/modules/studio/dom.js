// Pure DOM rendering helpers for Roundtable studio (#45). Zero innerHTML sinks.

export function iconNode(name) {
  return window.RoundtableIcons?.iconNode?.(name) || null;
}

export function setIcon(node, name) {
  if (!node) return;
  const svg = iconNode(name);
  if (svg) node.replaceChildren(svg);
  else node.replaceChildren();
}

export function memberAvatarNode({ asset: src, model }) {
  const span = document.createElement("span");
  span.className = `message-avatar${src ? "" : " neutral-model"}`;
  span.setAttribute("aria-hidden", "true");
  span.title = model || "";
  if (src) {
    const img = document.createElement("img");
    img.src = src;
    img.alt = "";
    span.append(img);
  } else {
    const svg = iconNode("model");
    if (svg) span.append(svg);
  }
  return span;
}

export function messageTimeNode(value) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  const time = document.createElement("time");
  time.className = "message-time";
  time.setAttribute("datetime", String(value));
  time.title = date.toLocaleString("zh-CN");
  time.textContent = date.toLocaleTimeString("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
  });
  return time;
}

export function buildHostMessageArticle({ label, at, automatic }) {
  const article = document.createElement("article");
  article.className = "message host-message";

  const avatar = document.createElement("span");
  avatar.className = "message-avatar";
  avatar.setAttribute("aria-hidden", "true");
  const svg = iconNode(automatic ? "refresh" : "person");
  if (svg) avatar.append(svg);

  const content = document.createElement("div");
  content.className = "message-content";

  const header = document.createElement("header");
  header.className = "message-header";
  if (label) {
    const strong = document.createElement("strong");
    strong.textContent = label;
    header.append(strong);
  }
  const time = messageTimeNode(at);
  if (time) header.append(time);

  const body = document.createElement("div");
  body.className = "message-body";

  content.append(header, body);
  article.append(avatar, content);
  return article;
}

export function buildTurnMessageArticle({ speaker, showModel, turn, progress }) {
  const article = document.createElement("article");
  const content = document.createElement("div");
  content.className = "message-content";

  const header = document.createElement("header");
  header.className = "message-header";
  const strong = document.createElement("strong");
  strong.textContent = `${speaker.label}${showModel ? ` · ${speaker.model}` : ""}`;
  header.append(strong);

  const time = messageTimeNode(turn.finished_at || turn.started_at);
  if (time) header.append(time);

  if (progress) {
    const status = document.createElement("span");
    status.className = `message-status${turn.status === "error" ? " error" : ""}`;
    status.textContent = progress;
    header.append(status);
  }

  content.append(header);

  if (turn.text) {
    const body = document.createElement("div");
    body.className = "message-body";
    content.append(body);
  } else if (turn.status !== "error") {
    const body = document.createElement("div");
    body.className = "message-body";
    const placeholder = document.createElement("p");
    placeholder.className = "message-placeholder";
    placeholder.textContent =
      turn.status === "pending"
        ? "等待回应…"
        : turn.status === "running"
          ? "正在处理任务…"
          : "没有返回发言。";
    body.append(placeholder);
    content.append(body);
  }

  article.append(memberAvatarNode(speaker), content);
  return article;
}

export function setSeatChildrenButtonContent(button, count) {
  const nodes = [];
  const svg = iconNode("subagent");
  if (svg) nodes.push(svg);
  const label = document.createElement("span");
  label.textContent = `子代理${count ? ` ${count}` : ""}`;
  nodes.push(label);
  button.replaceChildren(...nodes);
}

export function setTurnChildrenButtonContent(button, count) {
  const nodes = [];
  const svg = iconNode("subagent");
  if (svg) nodes.push(svg);
  nodes.push(document.createTextNode(`子代理 ${count}`));
  button.replaceChildren(...nodes);
}

export function renderActivityBar(node, activity) {
  if (!node) return;
  const owner = document.createElement("strong");
  owner.textContent = activity.owner || "";
  const text = document.createElement("span");
  text.textContent = activity.text || "";
  node.replaceChildren(owner, text);
}
