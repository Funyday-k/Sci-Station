"use strict";
(() => {
  for (const field of document.querySelectorAll("textarea[data-enter-submit]")) {
    const form = field.form;
    const submit = document.getElementById(field.dataset.enterSubmit);
    const surface = field.closest(".composer-surface");

    surface?.addEventListener("click", event => {
      if (event.target.matches(".composer-surface, .mention-field, .composer-bottom, .composer-actions")) {
        field.focus({preventScroll: true});
      }
    });

    let composing = false;
    let justCommitted = false;
    field.addEventListener("compositionstart", () => { composing = true; });
    field.addEventListener("compositionend", () => {
      composing = false;
      // WebKit can dispatch the final Enter just after committing an IME candidate.
      justCommitted = true;
      setTimeout(() => { justCommitted = false; }, 0);
    });
    // The field's @ menu gets the first chance to accept its highlighted seat.
    form.addEventListener("keydown", event => {
      if (event.target !== field || event.key !== "Enter" || event.defaultPrevented ||
          event.shiftKey || event.ctrlKey || event.altKey || event.metaKey ||
          composing || justCommitted || event.isComposing || event.keyCode === 229) return;
      event.preventDefault();
      if (!event.repeat && !field.disabled && !submit.disabled && !submit.hidden) {
        submit.click();
      }
    });
  }
})();
