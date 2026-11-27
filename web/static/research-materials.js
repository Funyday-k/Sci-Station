"use strict";
(() => {
  const E = window.SciResearch;
  const {state, $, enc, esc, request, projectPath, dialog, empty, button, bytes} = E;
  const actionPath = "/api/research/tools/project-material";
  const groups = new Map([["code", "代码"], ["data", "数据"], ["figures", "图表"], ["outputs", "输出"]]);
  const nativeActions = new Map([
    ["reveal", "已在 Finder 中打开"],
    ["editor", "已在 VS Code 中打开"],
    ["open", "已在默认应用中打开"],
    ["select-venv", "已选择 Python 虚拟环境"],
    ["create-venv", "已在终端打开环境创建任务"],
    ["run-terminal", "已在终端打开 Python 运行任务"],
    ["run-editor", "已生成 VS Code 工作区，可从运行任务菜单启动 Python"]
  ]);
  let snapshot = null;
  let runtime = "system";

  function previewURL(project, path) {
    return "/api/research/" + projectPath("files", project) + "?view=preview&path=" + enc(path);
  }

  function controls(file) {
    if (!snapshot?.caps.native) return "";
    return button(file ? "在 Finder 中显示" : "在 Finder 中打开目录", "material-native", {id: "reveal", glyph: "folder"}) +
      button(file ? "在 VS Code 中打开" : "在 VS Code 中打开目录", "material-native", {id: "editor"}) +
      (file ? button("用默认应用打开", "material-native", {id: "open"}) : "");
  }

  function pythonControls(item) {
    if (!snapshot.caps.native || item.kind !== "python") return "";
    return '<div class="field"><label for="material-runtime">Python 环境</label><select id="material-runtime">' +
      [
        ["system", "系统 Python"],
        ["local", "项目 .venv"],
        ["chosen", "本次已选择的虚拟环境"]
      ].filter(([key]) => key !== "chosen" || snapshot.caps.chosen).map(([key, title]) =>
        '<option value="' + key + '"' + (runtime === key ? " selected" : "") + '>' + esc(title) + '</option>').join("") +
      '</select></div><div class="actions">' + button("在终端运行", "material-native", {id: "run-terminal"}) +
      button("准备 VS Code 任务", "material-native", {id: "run-editor"}) +
      (snapshot.caps.localEnv ? "" : button("创建项目 .venv", "material-native", {id: "create-venv"})) +
      button("选择虚拟环境文件夹", "material-native", {id: "select-venv"}) + '</div>';
  }

  function statusLine() {
    return '<p id="linked-material-status" class="status" role="status"></p>';
  }

  async function browse() {
    const project = state.project?.id;
    if (!project) return;
    if (snapshot?.project !== project) runtime = "system";
    const next = {project, tools: projectPath("files", project), caps: {}, files: [], selected: null, busy: false};
    snapshot = next;
    dialog("项目目录", '<p class="status">正在读取…</p>', {wide: true});
    const box = $("dialog-content").firstElementChild;
    try {
      [next.files, next.caps] = await Promise.all([
        request(next.tools + "?view=materials"),
        request(actionPath + "?project=" + enc(project))
      ]);
      if (!box.isConnected || snapshot !== next || state.project?.id !== project) return;
      const rows = [...groups].map(([folder, label]) => {
        const files = next.files.filter(file => file.path.startsWith(folder + "/"));
        return files.length ? '<h3>' + label + '</h3><div class="list">' +
          files.map(file => button(file.path, "preview-linked-material", {id: file.path, kind: "search-result"})).join("") + '</div>' : "";
      }).join("");
      /* html-sink: all dynamic file paths and labels are HTML-escaped via button()/empty()/controls(). */
      box.outerHTML = '<div class="actions">' + controls(null) +
        button("浏览及编辑项目文本", "project-files") + button("刷新目录", "linked-materials") +
        '</div>' + statusLine() + (rows || empty("四个材料目录中暂无文件", "将代码、数据、图表和输出放入项目的 code、data、figures 或 outputs 目录。"));
    } catch (err) {
      if (box.isConnected) box.textContent = err.message;
    }
  }

  function markdownPreview(host, item, text) {
    const base = "https://project-material.invalid/" + item.path.split("/").map(enc).join("/");
    host.className = "markdown-body";
    window.SciMarkdown.render(host, text, {
      breaks:false,
      allowHTML:true,
      resolveImage(raw) {
        try {
          const resolved = new URL(raw, base);
          const path = decodeURIComponent(resolved.pathname.slice(1));
          if (resolved.origin === "https://project-material.invalid" &&
              snapshot.files.some(file => file.path === path && file.kind === "image"))
            return previewURL(snapshot.project, path);
        } catch {}
      },
    });
  }

  async function preview(item, message = "") {
    const current = snapshot;
    current.selected = item;
    dialog(item.path.split("/").at(-1), '<div class="actions">' + button("返回项目目录", "linked-materials") +
      controls(item) + '</div><p class="subheading">' + esc(item.path) + ' · ' + esc(bytes(item.size)) + '</p>' +
      pythonControls(item) + statusLine() + '<div id="linked-material-preview"></div>', {wide: true});
    $("linked-material-status").textContent = message;
    const host = $("linked-material-preview");
    const url = previewURL(current.project, item.path);
    const error = "该文件无法在这里预览，可在 Finder 或对应应用中打开。";
    if (item.kind === "image") {
      const img = document.createElement("img");
      img.className = "file-preview";
      img.alt = item.path;
      img.onerror = () => { if (host.isConnected) host.textContent = error; };
      img.src = url;
      host.append(img);
    } else if (item.kind === "pdf") {
      const res = await fetch(url, {method: "HEAD"});
      if (!host.isConnected) return;
      if (!res.ok) {
        host.textContent = error;
        return;
      }
      const frame = document.createElement("iframe");
      frame.className = "file-preview";
      frame.title = "PDF 文件预览";
      frame.src = url;
      host.append(frame);
    } else if (["text", "markdown", "python"].includes(item.kind)) {
      const res = await fetch(url);
      if (!host.isConnected) return;
      if (!res.ok) {
        host.textContent = error;
        return;
      }
      const text = await res.text();
      if (!host.isConnected) return;
      if (item.kind === "markdown") markdownPreview(host, item, text);
      else {
        const pre = document.createElement("pre");
        pre.className = "file-text";
        pre.textContent = text;
        host.append(pre);
      }
    } else {
      host.textContent = error;
    }
  }

  async function nativeAction(action) {
    const current = snapshot;
    const output = $("linked-material-status");
    if (!nativeActions.has(action) || !output || !current?.caps.native ||
        current.project !== state.project?.id || current.busy) return;
    const mode = $("material-runtime")?.value;
    if (mode) runtime = mode;
    current.busy = true;
    try {
      const file = current.selected;
      const result = await request(actionPath, {
        method: "POST",
        body: {
          project: current.project,
          action,
          path: action === "create-venv" || action === "select-venv" ? "" : file?.path || "",
          runtime
        }
      });
      if (!output.isConnected || current !== snapshot) return;
      if (result.performed && action === "select-venv") {
        runtime = "chosen";
        current.caps.chosen = true;
        await preview(file, nativeActions.get(action));
      } else output.textContent = result.performed ? nativeActions.get(action) : "已取消";
    } catch (err) {
      if (output.isConnected) output.textContent = err.message;
    } finally {
      current.busy = false;
    }
  }

  E.linkedMaterialsAction = async function(action, id) {
    if (action === "linked-materials") return browse();
    if (action === "material-native") return nativeAction(id);
    if (action === "preview-linked-material" && snapshot && snapshot.project === state.project?.id) {
      const item = snapshot.files.find(file => file.path === id);
      if (item) return preview(item);
    }
  };
})();
