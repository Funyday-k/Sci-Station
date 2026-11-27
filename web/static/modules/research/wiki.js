// Pure-DOM wiki conflict, snippet, backlink, and metadata renderers (#45).
import { createActionButton, createReadonlyField } from "./dom.js";

export function appendSnippetOptions(selectEl, available) {
  if (!selectEl || !available?.length) return;
  const fragment = document.createDocumentFragment();
  for (const item of available) {
    const opt = document.createElement("option");
    opt.value = item.trigger;
    opt.textContent = `${item.trigger} · ${item.title}`;
    fragment.append(opt);
  }
  selectEl.append(fragment);
}

export function renderNoteConflict(host, latest, pathText, useRevision) {
  host.hidden = false;
  const details = document.createElement("details");
  details.open = true;

  const summary = document.createElement("summary");
  summary.textContent = `对照已保存版本（修订 ${latest.revision}）`;

  const pathEl = document.createElement("p");
  pathEl.textContent = pathText;

  const metaEl = document.createElement("p");
  const aliases = latest.aliases?.join(" · ") || "无";
  const tags = latest.tags?.join(" · ") || "无";
  metaEl.textContent = `别名：${aliases}　标签：${tags}`;

  details.append(summary, pathEl, metaEl, createReadonlyField("已保存正文", "savedBody", latest.body));

  const adopt = document.createElement("button");
  adopt.className = "button";
  adopt.type = "button";
  adopt.textContent = "保留草稿并使用此修订";
  adopt.onclick = () => {
    useRevision();
    host.textContent = "已采用查看到的修订。保存时将应用当前草稿。";
  };

  host.replaceChildren(details, adopt);
  summary.focus();
}

export function renderBacklinks(host, refs, wikiPath) {
  if (!host || !refs?.length) return;
  const heading = document.createElement("div");
  heading.className = "subheading";
  heading.textContent = "链接到此页面";
  const buttons = refs.map((ref) =>
    createActionButton(wikiPath(ref), "read-note", { id: ref.id, kind: "bare" }),
  );
  host.replaceChildren(heading, ...buttons);
}

export function renderWikiMetadata(host, entries) {
  if (!host?.isConnected || !entries?.length) return;
  const dl = document.createElement("dl");
  for (const entry of entries) {
    const dt = document.createElement("dt");
    dt.textContent = String(entry.key ?? "");
    const dd = document.createElement("dd");
    const pre = document.createElement("pre");
    pre.textContent = String(entry.value ?? "");
    dd.append(pre);
    dl.append(dt, dd);
  }
  host.replaceChildren(dl);
}

export function renderSnippetConflict(host, latestContent, onAdopt) {
  const details = document.createElement("details");
  details.open = true;

  const summary = document.createElement("summary");
  summary.textContent = "对照已保存片段";

  details.append(summary, createReadonlyField("已保存片段", "savedSnippets", latestContent));

  const adopt = document.createElement("button");
  adopt.type = "button";
  adopt.className = "button";
  adopt.textContent = "保留草稿并使用此修订";
  adopt.onclick = () => {
    onAdopt();
    host.textContent = "已采用查看到的修订。保存时将应用当前草稿。";
  };

  host.replaceChildren(details, adopt);
  host.hidden = false;
  summary.focus();
}
