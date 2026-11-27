// Pure-DOM material preview and project file browser renderers (#45).
import { createActionButton } from "./dom.js";

export function renderFilePreview(host, { img, pdf, url, name }) {
  if (!host) return;
  if (img) {
    const image = document.createElement("img");
    image.className = "file-preview";
    image.src = url;
    image.alt = String(name ?? "");
    host.replaceChildren(image);
    return true;
  }
  if (pdf) {
    const frame = document.createElement("iframe");
    frame.className = "file-preview";
    frame.title = "PDF 文件预览";
    frame.src = url;
    host.replaceChildren(frame);
    return true;
  }
  return false;
}

export function renderProjectFilesList(box, { projectPath, files }) {
  const help = document.createElement("p");
  help.className = "form-help";
  help.textContent = String(projectPath ?? "");

  const createBtn = createActionButton("新建文本文件", "new-project-file", { glyph: "plus" });

  const list = document.createElement("div");
  list.className = "list";
  if (files?.length) {
    for (const filePath of files) {
      list.append(createActionButton(filePath, "open-project-file", { id: filePath, kind: "search-result" }));
    }
  } else {
    const emptyEl = document.createElement("div");
    emptyEl.className = "empty";
    const h3 = document.createElement("h3");
    h3.textContent = "目录中暂无可编辑文件";
    emptyEl.append(h3);
    list.append(emptyEl);
  }

  box.replaceWith(help, createBtn, list);
}
