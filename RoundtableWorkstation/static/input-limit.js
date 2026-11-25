"use strict";
(() => {
  const maxInputCharacters = 12000;

  function paint(id) {
    const input = document.getElementById(id);
    const hint = document.getElementById(id + "-limit");
    let length = 0;
    for (const character of input.value) length++;
    const excess = length - maxInputCharacters;
    const error = excess > 0 ? `超出 ${excess} 个字符（上限 ${maxInputCharacters}）` : "";
    input.setCustomValidity(error);
    hint.classList.toggle("over-limit", Boolean(error));
    hint.hidden = !error;
    hint.textContent = error;
    return !error;
  }

  window.RoundtableInputLimit = Object.freeze({paint});
})();
