"use strict";
(() => {
  const control = document.getElementById("sync-new-apple-reminders");
  if (!control) return;
  const status = document.getElementById("calendar-preference-status");
  const endpoint = "/api/research/tools/reminder-settings";
  async function readPreference(options) {
    const response = await fetch(endpoint, options);
    if (!response.ok) throw new Error((await response.json()).error);
    return (await response.json()).syncNewAppleReminders;
  }
  async function load() {
    control.disabled = true;
    status.textContent = "";
    try {
      control.checked = await readPreference();
      control.disabled = false;
    } catch (error) {
      status.textContent = error.message;
    }
  }
  window.addEventListener("roundtable:settings-page", event => {
    if (event.detail === "calendar") void load();
  });
  control.addEventListener("change", async () => {
    const value = control.checked;
    control.disabled = true;
    try {
      control.checked = await readPreference({
        method: "PATCH",
        headers: {"Content-Type": "application/json", "X-Roundtable": "1"},
        body: JSON.stringify({syncNewAppleReminders: value})
      });
      status.textContent = "";
    } catch (error) {
      control.checked = !value;
      status.textContent = error.message;
    } finally {
      control.disabled = false;
    }
  });
})();
