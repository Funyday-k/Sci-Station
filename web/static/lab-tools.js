"use strict";

(() => {
  function mount({dialog, trigger}) {
    const directory = "directory";
    const heading = dialog.querySelector("#lab-tools-title");
    const back = dialog.querySelector("#lab-tool-back");
    const body = dialog.querySelector(".lab-dialog-content");
    const status = dialog.querySelector("[data-lab-status]");
    const pages = new Map([...dialog.querySelectorAll("[data-lab-tool-page]")].map(page => [page.dataset.labToolPage,page]));
    const cards = new Map([...dialog.querySelectorAll("[data-lab-tool]")].map(card => [card.dataset.labTool,card]));
    let active = directory, trail = [];

    function updateHeading() {
      const {zhTitle,enTitle} = pages.get(active).dataset;
      heading.textContent = window.SciStationI18n?.text(zhTitle,enTitle) || zhTitle;
    }

    function show(page, focus = heading) {
      active = page;
      for (const [id,panel] of pages) panel.hidden = id !== active;
      back.hidden = !trail.length;
      body.scrollTop = 0;
      status.textContent = "";
      updateHeading();
      if (dialog.open) focus.focus({preventScroll:true});
    }

    function open(page = directory, focus = heading) {
      if (dialog.open) return;
      trail = page === directory ? [] : [{page:directory, focus:() => cards.get(page)}];
      show(page);
      dialog.showModal();
      focus.focus({preventScroll:true});
    }

    function enter(page, focus) {
      if (!dialog.open || page === active) return;
      trail.push({page:active,focus});
      show(page);
    }

    function previous() {
      const prior = trail.pop();
      if (prior) show(prior.page, prior.focus?.() || heading);
    }

    for (const [id,card] of cards) card.addEventListener("click", () => enter(id, () => card));
    trigger.addEventListener("click", () => open());
    back.addEventListener("click",previous);
    dialog.addEventListener("cancel", event => {
      if (trail.length) {
        event.preventDefault();
        previous();
      }
    });
    dialog.addEventListener("close", () => {
      if (!document.querySelector("dialog[open]")) trigger.focus({preventScroll:true});
    });
    window.addEventListener("sci:language",updateHeading);
    return {open,enter,active:() => active};
  }

  window.SciLabTools = Object.freeze({mount});
})();
