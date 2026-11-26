"use strict";
(() => {
  // Watch only the open, running meeting. A room change invalidates all pending responses.
  function mount(receive, refresh) {
    let active = null;
    function stop() {
      if (!active) return;
      const previous = active;
      active = null;
      clearTimeout(previous.timer);
      previous.controller.abort();
      receive(null);
    }
    async function poll(watch) {
      let delay = 90;
      try {
        const url = new URL("/api/studio/sessions/" + encodeURIComponent(watch.id) + "/board-presence", location.href);
        if (watch.sequence !== null) url.searchParams.set("after", watch.sequence);
        const response = await fetch(url, {signal:watch.controller.signal, cache:"no-store"});
        if (!response.ok) throw new Error("Presence unavailable");
        const snapshot = await response.json();
        if (active !== watch) return;
        if (snapshot.session_id !== watch.id || !Number.isSafeInteger(snapshot.seq) || !Array.isArray(snapshot.cursors))
          throw new Error("Invalid presence snapshot");
        if (snapshot.seq !== watch.sequence) {
          const finished = watch.hasCursors && !snapshot.cursors.length;
          watch.hasCursors = snapshot.cursors.length > 0;
          receive(snapshot);
          if (finished) refresh(watch.id);
        }
        watch.sequence = snapshot.seq;
        watch.retry = 350;
      } catch (_) {
        if (active !== watch) return;
        if (watch.sequence !== null) {
          receive(null);
          watch.hasCursors = false;
          watch.sequence = null;
        }
        delay = watch.retry;
        watch.retry = Math.min(4000, delay * 2);
      }
      if (active === watch) watch.timer = setTimeout(() => void poll(watch), delay);
    }
    function sync(session, visible) {
      const id = visible && session?.board?.state === "published" && session.status === "running" ? session.id : "";
      if (active?.id === id) return;
      stop();
      if (!id) return;
      active = {id, sequence:null, hasCursors:false, retry:350, timer:0, controller:new AbortController()};
      void poll(active);
    }
    return {sync, stop};
  }
  window.RoundtableBoardPresence = Object.freeze({mount});
})();
