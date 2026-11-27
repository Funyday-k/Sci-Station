"use strict";
(() => {
  const welcome = () => document.body.classList.contains("root-welcome");
  const en = () => String(globalThis.SciStationI18n?.language || document.documentElement.lang).startsWith("en");
  const label = (zh, english) => en() ? english : zh;
  const el = (tag, text) => {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    return node;
  };
  async function request(action, body) {
    const options = body === undefined ? {} : {
      method: "POST", headers: {"Content-Type": "application/json", "X-Roundtable": "1"}, body: JSON.stringify(body)
    };
    const res = await fetch("/api/workspace" + (action ? "/" + action : ""), options);
    const data = await res.json();
    if (!res.ok) throw Error(data.error?.message || data.error || res.statusText);
    return data;
  }
  function message(text) {
    const out = document.querySelector("[data-root-status]");
    if (out) out.textContent = text;
    else window.alert(text);
  }
  function checkbox(text, checked = false) {
    const input = el("input");
    input.type = "checkbox";
    input.checked = checked;
    const field = el("label");
    field.className = "root-check";
    const caption = el("span", text);
    field.append(input, caption);
    return {field, input};
  }

  async function action(kind) {
    if (kind === "open" || kind === "default-storage" || kind === "choose-storage") {
      await request(kind, {});
      return;
    }
    if (kind === "forget") {
      if (!confirm(label("清除最近工作区记录？当前工作区会继续打开。", "Forget the recent workspace? The current workspace will stay open."))) return;
      await request("forget", {});
      message(label("已清除最近工作区。", "Recent workspace cleared."));
      return;
    }
    if (document.querySelector(".root-wizard")) return;
    const dialog = el("dialog");
    dialog.className = "root-wizard";
    dialog.setAttribute("aria-labelledby", "root-wizard-title");
    document.body.append(dialog);
    dialog.addEventListener("close", () => dialog.remove(), {once: true});
    const form = el("form");
    dialog.append(form);
    const rename = kind === "rename";
    const title = el("h2", rename ? label("重命名工作区", "Rename workspace") :
      kind === "sample" ? label("创建示例工作区", "Create sample workspace") : label("创建工作区", "Create workspace"));
    title.id = "root-wizard-title";
    const field = (text, control) => {
      const wrapper = el("label");
      wrapper.append(el("span", text), control);
      return wrapper;
    };
    const name = el("input");
    name.maxLength = 100;
    name.name = "name";
    name.required = true;
    const nameField = field(rename ? label("新的文件夹名称", "New folder name") : label("工作区名称", "Workspace name"), name);
    const alert = el("p");
    alert.setAttribute("role", "alert");
    const cancel = el("button", label("取消", "Cancel"));
    cancel.type = "button";
    cancel.onclick = () => dialog.close();
    const confirmButton = el("button", rename ? label("重命名", "Rename") : label("选择位置并创建…", "Choose location and create…"));
    confirmButton.type = "submit";
    const footer = el("footer");
    footer.append(cancel, confirmButton);
    form.append(title, nameField);
    let submit;
    try {
      if (rename) {
        const info = await request("");
        name.value = info.folder;
        form.append(el("p", label("将在同一父目录重命名工作区文件夹并重新打开。", "The workspace folder will be renamed in its current parent folder and reopened.")));
        submit = async () => {
          await request("rename", {name: name.value.trim()});
          return true;
        };
      } else {
        name.value = kind === "sample" ? "Sci-Station Sample" : "ResearchWorkspace";
        const templates = await request("templates");
        const select = el("select");
        for (const template of templates) {
          const caption = en() ? template.title : template.chineseTitle;
          const option = el("option", template.available ? caption : caption + label("（尚未开放）", " (coming later)"));
          option.value = template.id;
          option.disabled = !template.available;
          select.append(option);
        }
        select.value = "literature-review";
        const preview = el("p");
        preview.className = "root-preview";
        const updatePreview = () => {
          const template = templates.find(option => option.id === select.value);
          preview.textContent = template.modules.map(module => en() ? module.title : module.chineseTitle).join(en() ? ", " : "、");
        };
        select.onchange = updatePreview;
        updatePreview();
        const chooseEmpty = checkbox(label("使用已有空文件夹", "Use an existing empty folder"));
        chooseEmpty.input.onchange = () => {
          const existing = chooseEmpty.input.checked;
          name.required = !existing;
          nameField.firstChild.textContent = existing ? label("工作区显示名称（可选）", "Workspace display name (optional)") :
            label("工作区名称", "Workspace name");
          confirmButton.textContent = existing ? label("选择空文件夹并创建…", "Select empty folder and create…") :
            label("选择位置并创建…", "Choose location and create…");
        };
        const sample = checkbox(label("加入明确标注的示例项目与练习笔记", "Include a labelled sample project and practice notes"), kind === "sample");
        const ack = checkbox(label("我了解创建工作区不会保存模型凭据或运行 AI。", "I understand that creation does not save model credentials or run AI."));
        ack.input.required = true;
        form.append(field(label("配置模板", "Configuration template"), select), preview, chooseEmpty.field, sample.field, ack.field);
        submit = async () => {
          const result = await request("setup", {
            name: name.value.trim(), template: select.value, sample: sample.input.checked,
            acknowledged: ack.input.checked, useEmptyFolder: chooseEmpty.input.checked
          });
          return result.opened;
        };
      }
      form.append(alert, footer);
      dialog.addEventListener("cancel", event => {
        if (confirmButton.disabled) event.preventDefault();
      });
      form.onsubmit = async event => {
        event.preventDefault();
        confirmButton.disabled = true;
        cancel.disabled = true;
        alert.textContent = "";
        try {
          if (await submit()) dialog.close();
        } catch (error) {
          alert.textContent = error.message;
        } finally {
          confirmButton.disabled = false;
          cancel.disabled = false;
        }
      };
      dialog.showModal();
      name.select();
    } catch (error) {
      dialog.remove();
      throw error;
    }
  }
  function run(kind) { return action(kind).catch(error => message(error.message)); }
  window.SciWorkspaceSetup = {run};
  if (welcome()) {
    for (const node of document.querySelectorAll("[data-zh]")) node.textContent = en() ? node.dataset.en : node.dataset.zh;
    document.addEventListener("click", event => {
      const button = event.target.closest("[data-setup]");
      if (button) run(button.dataset.setup);
    });
    const commands = {openWorkspace: "open", createWorkspace: "create", forgetWorkspace: "forget"};
    window.SciStationNav = {command: key => {
      if (Object.hasOwn(commands, key)) run(commands[key]);
    }};
  }
})();
