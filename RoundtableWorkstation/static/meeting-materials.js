(() => {
  "use strict";

  const MAX_ITEMS = 12;
  const MAX_BYTES = 12 * 1024 * 1024;
  const ENDPOINT = "/api/studio/materials";
  const IMAGE_TYPES = new Set(["image/png", "image/jpeg", "image/gif", "image/webp"]);
  const pendingDownloads = new Set();
  const READ_LABELS = {
    text: "已提取文字",
    failed: "文字提取失败 · 已保留原件",
    original_only: "已保留原件",
    no_extractable_text: "未提取到文字 · 已保留原件",
  };

  function originalHref(id) {
    return `${ENDPOINT}/${encodeURIComponent(id)}`;
  }

  function canPreview(material) {
    return IMAGE_TYPES.has(material.mime);
  }

  async function downloadOriginal(event, material, {onStart, onSaved, onError} = {}) {
    if (!navigator.userAgent.includes("SciStationDesktop/") || event.defaultPrevented ||
        event.button !== 0 || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    event.preventDefault();
    if (pendingDownloads.has(material.id)) return;
    pendingDownloads.add(material.id);
    const link = event.currentTarget;
    link.setAttribute("aria-busy", "true");
    onStart?.();
    try {
      const url = originalHref(material.id);
      const response = await fetch(`${url}/save`, {
        method: "POST",
        headers: {"Content-Type": "application/json", "X-Roundtable": "1"},
        body: "{}",
      });
      const result = await response.json().catch(() => null);
      if (!response.ok || !result) throw new Error(result?.error || "无法保存会议附件");
      if (result.browser_download) {
        const fallback = document.createElement("a");
        fallback.href = url;
        fallback.download = material.name || "";
        document.body.append(fallback);
        fallback.click();
        fallback.remove();
      }
      if (result.saved) onSaved?.();
    } catch (error) {
      onError?.(error.message || "无法保存会议附件");
    } finally {
      pendingDownloads.delete(material.id);
      link.removeAttribute("aria-busy");
    }
  }

  function mount({ root, pasteTarget, onChange = () => {}, onError = () => {} } = {}) {
    if (!root) throw new TypeError("RoundtableMaterials.mount requires a root element");

    let rows = [];
    let generation = 0;
    let serial = 0;
    let disabled = false;
    const inputs = new Set();

    root.classList.add("roundtable-materials");
    root.setAttribute("aria-label", "会议材料");
    root.tabIndex = -1;
    const list = document.createElement("ul");
    list.className = "roundtable-materials__list";
    list.setAttribute("aria-label", "已选材料");
    const downloadStatus = document.createElement("p");
    downloadStatus.className = "sr-only";
    downloadStatus.setAttribute("role", "status");
    const preview = document.createElement("dialog");
    preview.className = "roundtable-materials__preview";
    const previewHeader = document.createElement("header");
    const previewTitle = document.createElement("h2");
    const previewTools = document.createElement("div");
    const previewImage = document.createElement("img");
    const dismiss = document.createElement("button");
    dismiss.className = "roundtable-materials__action";
    dismiss.type = "button";
    dismiss.textContent = "关闭";
    dismiss.autofocus = true;
    dismiss.addEventListener("click", () => preview.close());
    previewTitle.id = `${root.id}-preview-title`;
    preview.setAttribute("aria-labelledby", previewTitle.id);
    previewHeader.append(previewTitle, previewTools);
    preview.append(previewHeader, previewImage);
    root.append(downloadStatus, preview);

    let previewRow = "";
    preview.addEventListener("click", event => {
      if (event.target === preview) preview.close();
    });
    preview.addEventListener("close", () => {
      if (preview.open) return;
      previewImage.removeAttribute("src");
      previewTitle.textContent = "";
      previewTools.replaceChildren();
      if (previewRow) (findControl(previewRow, "open") || root).focus({preventScroll: true});
      previewRow = "";
    });

    function trackControl(node, id, action) {
      node.dataset.materialRow = id;
      node.dataset.materialAction = action;
      return node;
    }

    function findControl(id, action) {
      if (!id) return null;
      return [...list.querySelectorAll("[data-material-action]")]
        .find(node => node.dataset.materialRow === id && node.dataset.materialAction === action && !node.disabled);
    }

    function originalLink(material, text, className) {
      const link = document.createElement("a");
      link.className = className;
      link.href = originalHref(material.id);
      link.download = material.name || "";
      link.textContent = text;
      link.setAttribute("aria-label", `下载 ${material.name}`);
      link.addEventListener("click", event => {
        const downloadGeneration = generation;
        return downloadOriginal(event, material, {
          onStart: () => { downloadStatus.textContent = ""; },
          onSaved: () => {
            if (generation === downloadGeneration) downloadStatus.textContent = `已保存 ${material.name}`;
          },
          onError: message => {
            if (generation === downloadGeneration) reportError(message);
          },
        });
      });
      return link;
    }

    function openPreview(row) {
      if (preview.open) return;
      previewRow = row.id;
      previewTitle.textContent = row.name;
      previewImage.alt = row.name;
      previewImage.src = originalHref(row.material.id) + "?preview=1";
      previewTools.replaceChildren(originalLink(row.material, "下载", "roundtable-materials__action"), dismiss);
      preview.showModal();
    }

    function materialName(row) {
      const label = row.name || "未命名文件";
      if (row.material && !canPreview(row.material)) {
        const link = originalLink(row.material, label, "roundtable-materials__name");
        link.title = label;
        return trackControl(link, row.id, "open");
      }
      const name = document.createElement("span");
      name.className = "roundtable-materials__name";
      name.textContent = label;
      name.title = label;
      if (!row.material) return name;

      const opener = document.createElement("button");
      opener.type = "button";
      opener.className = "roundtable-materials__opener";
      opener.setAttribute("aria-label", `预览 ${label}`);
      opener.setAttribute("aria-haspopup", "dialog");
      opener.addEventListener("click", () => openPreview(row));
      const image = document.createElement("img");
      image.src = originalHref(row.material.id) + "?preview=1";
      image.alt = "";
      image.loading = "lazy";
      image.addEventListener("error", () => { image.hidden = true; }, {once: true});
      opener.append(image, name);
      return trackControl(opener, row.id, "open");
    }

    function snapshot() {
      return rows.map((row) => row.material || {
        id: row.id,
        name: row.name,
        mime: row.mime,
        size: row.size,
        excerpt: "",
        read_status: row.status,
        status: row.status,
        error: row.error || "",
      });
    }

    function emit() {
      render();
      onChange(snapshot());
    }

    function render() {
      const focused = root.contains(document.activeElement) ? document.activeElement.dataset : {};
      list.replaceChildren();

      rows.forEach((row) => {
        const item = document.createElement("li");
        item.className = "roundtable-materials__item";
        item.dataset.status = row.status;

        const details = document.createElement("div");
        details.className = "roundtable-materials__details";
        details.append(materialName(row));

        const state = document.createElement("span");
        state.className = "roundtable-materials__state";
        if (row.status === "uploading") {
          state.textContent = `正在上传 · ${formatSize(row.size)}`;
          state.setAttribute("role", "status");
        } else if (row.status === "error") {
          const detail = row.error || "上传失败";
          state.textContent = detail.startsWith("上传失败") ? detail : `上传失败 · ${detail}`;
          state.classList.add("is-error");
          state.setAttribute("role", "alert");
        } else {
          const status = row.material?.read_status;
          state.textContent = Object.hasOwn(READ_LABELS, status) ? READ_LABELS[status] : "已就绪";
        }
        state.title = state.textContent;
        details.append(state);
        item.append(details);

        if (row.status === "error") {
          const retry = document.createElement("button");
          retry.type = "button";
          retry.className = "roundtable-materials__remove";
          retry.textContent = "重试";
          retry.title = "重试上传";
          retry.setAttribute("aria-label", `重新上传：${row.name}`);
          retry.disabled = disabled;
          retry.addEventListener("click", () => startUpload(row));
          item.append(trackControl(retry, row.id, "retry"));
        }

        const remove = document.createElement("button");
        remove.type = "button";
        remove.className = "roundtable-materials__remove roundtable-materials__remove--icon";
        remove.textContent = "×";
        remove.title = "移除材料";
        remove.setAttribute("aria-label", `移除材料：${row.name || "未命名文件"}`);
        remove.disabled = disabled;
        remove.addEventListener("click", () => removeRow(row.id, document.activeElement === remove));
        item.append(trackControl(remove, row.id, "remove"));
        list.append(item);
      });

      if (rows.length && !list.isConnected) root.prepend(list);
      if (!rows.length) list.remove();
      root.dataset.disabled = String(disabled);
      if (focused.materialRow) {
        const next = findControl(focused.materialRow, focused.materialAction) || findControl(focused.materialRow, "remove");
        next?.focus({preventScroll: true});
      }
    }

    function removeRow(id, restoreFocus) {
      const index = rows.findIndex((row) => row.id === id);
      if (index < 0) return;
      const [row] = rows.splice(index, 1);
      row.controller?.abort();
      emit();
      if (restoreFocus) (findControl((rows[index] || rows[index - 1])?.id, "remove") || pasteTarget || root).focus();
    }

    function choose(kind) {
      if (disabled) return;
      if (kind !== "image" && kind !== "file") throw new TypeError("pick expects 'image' or 'file'");
      const input = document.createElement("input");
      input.type = "file";
      input.multiple = true;
      input.accept = kind === "image" ? "image/*" : "*/*";
      input.className = "roundtable-materials__input";
      input.setAttribute("aria-label", kind === "image" ? "选择图片" : "选择文件");
      const pickerGeneration = generation;
      inputs.add(input);
      input.addEventListener("change", () => {
        const chosen = Array.from(input.files || []);
        input.remove();
        inputs.delete(input);
        if (pickerGeneration === generation) enqueue(chosen);
      }, { once: true });
      input.addEventListener("cancel", () => {
        input.remove();
        inputs.delete(input);
      }, { once: true });
      document.body.append(input);
      // Must remain synchronous with the external button click to preserve the picker gesture.
      input.click();
    }

    function paste(event) {
      const clipboard = event.clipboardData;
      if (disabled || event.defaultPrevented || pasteTarget.disabled || pasteTarget.readOnly || !clipboard) return;
      let files = Array.from(clipboard.files || []);
      // Both views usually describe the same files. Use items only as a fallback.
      if (!files.length) {
        files = Array.from(clipboard.items || []).flatMap(item => {
          const file = item.kind === "file" ? item.getAsFile() : null;
          return file ? [file] : [];
        });
      }
      if (!files.length) return;
      if (!clipboard.getData("text/plain") && !clipboard.types.includes("text/html")) event.preventDefault();
      enqueue([...new Set(files)]);
    }

    function enqueue(files) {
      if (!files.length || disabled) return;
      const available = Math.max(0, MAX_ITEMS - rows.length);
      const accepted = [];
      const rejected = [];
      for (const file of files) {
        if (accepted.length >= available) {
          rejected.push(`${file.name}: 最多添加 ${MAX_ITEMS} 件材料`);
        } else if (file.size > MAX_BYTES) {
          rejected.push(`${file.name}: 文件超过 12 MiB 上限`);
        } else {
          accepted.push(file);
        }
      }
      if (rejected.length) reportError(rejected.join("\n"));
      if (!accepted.length) return;

      const batchGeneration = generation;
      const added = accepted.map((file) => ({
        id: `upload-${++serial}`,
        name: file.name,
        mime: file.type || "application/octet-stream",
        size: file.size,
        status: "uploading",
        file,
        controller: new AbortController(),
      }));
      rows.push(...added);
      emit();
      added.forEach((row) => upload(row, batchGeneration));
    }

    function startUpload(row) {
      if (disabled || row.status !== "error" || !row.file || !rows.includes(row)) return;
      row.status = "uploading";
      row.error = "";
      row.controller = new AbortController();
      emit();
      upload(row, generation);
    }

    async function upload(row, batchGeneration) {
      const form = new FormData();
      form.append("file", row.file, row.name);
      try {
        const response = await fetch(ENDPOINT, {
          method: "POST",
          headers: { "X-Roundtable": "1" },
          body: form,
          signal: row.controller.signal,
        });
        const payload = await response.json().catch(() => null);
        if (!response.ok) throw new Error(errorMessage(payload, response.status));
        const material = payload?.material || payload;
        if (!material || typeof material.id !== "string" || typeof material.name !== "string") {
          throw new Error("服务器返回的材料信息无效");
        }
        if (!isCurrent(row, batchGeneration)) return;
        row.material = {
          id: material.id,
          name: material.name,
          mime: material.mime || row.mime,
          size: Number.isFinite(material.size) ? material.size : row.size,
          excerpt: material.excerpt || "",
          read_status: material.read_status || "",
        };
        row.status = "ready";
        row.file = null;
        row.controller = null;
        emit();
      } catch (error) {
        if (error?.name === "AbortError" || !isCurrent(row, batchGeneration)) return;
        row.status = "error";
        row.error = error?.message || "上传失败，请检查网络后重试";
        row.controller = null;
        emit();
      }
    }

    function isCurrent(row, batchGeneration) {
      return generation === batchGeneration && rows.includes(row);
    }

    function reportError(message) {
      onError(message);
    }

    function clearRows() {
      generation += 1;
      previewRow = "";
      if (preview.open) preview.close();
      downloadStatus.textContent = "";
      rows.forEach((row) => row.controller?.abort());
      inputs.forEach(input => input.remove());
      inputs.clear();
      rows = [];
    }

    function set(items) {
      clearRows();
      rows = Array.isArray(items) ? items.filter(material => typeof material?.id === "string" && material.id).slice(0, MAX_ITEMS).map((material) => ({
        id: material.id,
        name: material.name || "未命名文件",
        mime: material.mime || "application/octet-stream",
        size: Number(material.size) || 0,
        status: "ready",
        material: {
          id: material.id,
          name: material.name || "未命名文件",
          mime: material.mime || "application/octet-stream",
          size: Number(material.size) || 0,
          excerpt: material.excerpt || "",
          read_status: material.read_status || "",
        },
      })) : [];
      emit();
    }

    function reset() {
      clearRows();
      emit();
    }

    function setDisabled(flag) {
      if (disabled === Boolean(flag)) return;
      disabled = Boolean(flag);
      render();
    }

    function busy() {
      return rows.some((row) => row.status === "uploading");
    }

    function formatSize(bytes) {
      if (!Number.isFinite(bytes) || bytes <= 0) return "大小未知";
      return bytes < 1024 * 1024 ? `${Math.max(1, Math.round(bytes / 1024))} KiB` : `${(bytes / 1024 / 1024).toFixed(1)} MiB`;
    }

    function errorMessage(payload, status) {
      const detail = payload?.error || payload?.message || payload?.detail;
      return typeof detail === "string" && detail.trim() ? detail : `上传失败（HTTP ${status}）`;
    }

    pasteTarget?.addEventListener("paste", paste);
    render();
    return {
      pick: choose,
      set,
      items: snapshot,
      busy,
      failed: () => rows.some(row => row.status === "error"),
      ready: () => rows.flatMap(row => row.material ? [row.material] : []),
      reset,
      setDisabled,
    };
  }

  window.RoundtableMaterials = { mount, canPreview, originalHref, downloadOriginal };
})();
