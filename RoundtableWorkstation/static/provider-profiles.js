"use strict";
(() => {
  const $ = id => document.getElementById("provider-" + id);
  if (!$("profiles")) return;
  let profiles = [];
  let proof = "";
  let busy = false;
  const fields = ["choice", "name", "url", "model", "temperature", "max-tokens", "vision", "key"];

  async function request(input) {
    const headers = {"X-Sci-Station-Credential-Session": proof};
    const options = {headers};
    if (input) {
      headers["Content-Type"] = "application/json";
      headers["X-Roundtable"] = "1";
      options.method = "POST";
      options.body = JSON.stringify(input);
    }
    const response = await fetch("/api/studio/provider-profiles", options);
    const data = await response.json();
    if (!response.ok) throw Error(data.error || "直接模型设置请求失败");
    return data;
  }

  function selected() {
    return profiles.find(profile => profile.id === $("choice").value);
  }

  function controlState() {
    const profile = selected();
    for (const id of [...fields, "save", "preset", "test"]) $(id).disabled = busy;
    $("save-key").disabled = busy || !profile;
    $("clear-key").disabled = busy || !(profile?.configured || profile?.key_unavailable);
    $("remove").disabled = busy || !profile || profile.configured || profile.key_unavailable;
  }

  function showProfile(typedKey = "", input = selected()) {
    const profile = selected();
    $("name").value = input?.name || "";
    $("url").value = input?.base_url || "";
    $("model").value = input?.model || "";
    $("temperature").value = input?.temperature ?? 0.2;
    $("max-tokens").value = input?.max_tokens || "";
    $("vision").checked = Boolean(input?.vision);
    $("key").value = typedKey;
    $("key-status").textContent = profile?.key_unavailable ? "暂时无法访问钥匙串。" :
      profile?.configured ? "API Key 已保存在 macOS 钥匙串中。更改地址前请清除 Key。" :
      "配置保存后可将 Key 存入 macOS 钥匙串。本机 HTTP 服务可以留空。";
    controlState();
  }

  async function reload(id, typedKey = "", input) {
    profiles = await request();
    $("choice").replaceChildren(new Option("新配置", ""), ...profiles.map(profile => new Option(profile.name, profile.id)));
    $("choice").value = id === undefined ? profiles[0]?.id || "" : profiles.some(profile => profile.id === id) ? id : "";
    showProfile(typedKey, input);
  }

  async function run(action) {
    if (busy) return;
    busy = true;
    controlState();
    $("status").textContent = "";
    try {
      await action();
    } catch (error) {
      $("status").textContent = error.message;
    } finally {
      busy = false;
      controlState();
    }
  }

  function draft() {
    return {
      id: $("choice").value, name: $("name").value, base_url: $("url").value, model: $("model").value,
      temperature: Number($("temperature").value), max_tokens: Number($("max-tokens").value), vision: $("vision").checked
    };
  }

  function enable() {
    if (proof || typeof window.sciStationCredentialSession !== "string" || !window.sciStationCredentialSession) return;
    proof = window.sciStationCredentialSession;
    $("profiles").hidden = false;
    run(() => reload());
  }

  $("choice").onchange = () => showProfile();
  $("profiles").addEventListener("keydown", event => {
    if (event.key === "Enter" && event.target.tagName === "INPUT") event.preventDefault();
  });
  $("preset").onclick = () => {
    $("name").value = "DeepSeek";
    $("url").value = "https://api.deepseek.com";
    $("model").value = "deepseek-v4-flash";
    $("temperature").value = 0.2;
    $("max-tokens").value = 384000;
    $("vision").checked = false;
  };
  $("save").onclick = () => run(async () => {
    const key = $("key").value;
    const profile = await request({action: "save", profile: draft()});
    await reload(profile.id, key);
    $("status").textContent = "已保存模型配置。";
    window.dispatchEvent(new Event("roundtable:models-changed"));
  });
  $("save-key").onclick = () => run(async () => {
    const profile = selected();
    if (!profile || profile.base_url !== $("url").value.trim().replace(/\/+$/, "")) {
      throw Error("请先保存当前服务地址，再保存 API Key。");
    }
    const input = draft();
    await request({action: "set_key", id: profile.id, key: $("key").value});
    $("key").value = "";
    await reload(profile.id, "", input);
    $("status").textContent = "已保存 API Key。";
  });
  $("clear-key").onclick = () => {
    const id = $("choice").value;
    if (!confirm("清除此配置的 API Key？")) return;
    return run(async () => {
      const input = draft();
      await request({action: "clear_key", id});
      await reload(id, $("key").value, input);
      $("status").textContent = "已清除 API Key。";
    });
  };
  $("remove").onclick = () => {
    const id = $("choice").value;
    if (!confirm("移除此配置？使用此模型的历史会议仍可阅读。")) return;
    return run(async () => {
      await request({action: "remove", id});
      await reload("");
      $("status").textContent = "已移除模型配置。";
      window.dispatchEvent(new Event("roundtable:models-changed"));
    });
  };
  $("test").onclick = () => run(async () => {
    $("status").textContent = "正在测试连接…";
    await request({action: "test", profile: draft(), key: $("key").value});
    $("status").textContent = "连接成功。";
  });
  window.addEventListener("scistation:credential-session", enable);
  enable();
})();
