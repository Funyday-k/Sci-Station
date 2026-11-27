// Meeting room reveal and reference navigation helpers for Roundtable studio (#45).

export function revealRoomTarget(
  target,
  agenda,
  {
    $,
    state,
    switchView,
    compactWorkspace,
    setChatVisible,
    showRoomDrawer,
    openRoomTab,
    scrollToMessage,
    locationObj = location,
  },
) {
  if (state.view !== "table") switchView("table");
  if (agenda) {
    if (compactWorkspace) setChatVisible(false);
    showRoomDrawer("agenda-toggle");
  } else {
    openRoomTab("chat");
  }
  requestAnimationFrame(() => {
    if (!target.isConnected) return;
    if (agenda) target.scrollIntoView({ block: "nearest" });
    else {
      const url = new URL(locationObj.href);
      url.hash = target.id;
      window.SciStationNav.commitURL(url, "replace");
      scrollToMessage(target);
      $("latest-message").hidden = false;
    }
    target.tabIndex = -1;
    target.classList.add("meeting-source-focus");
    target.focus({ preventScroll: true });
  });
}
