(() => {
  "use strict";

  const escape = value => String(value || "").replace(/[&<>"']/g, c =>
    ({"&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;"})[c]);
  const delimiters = [
    {open:"$$", close:"$$", display:true},
    {open:"\\[", close:"\\]", display:true},
    {open:"\\(", close:"\\)", display:false},
    {open:"$", close:"$", display:false},
  ];
  const maxMathCharacters = 8000;
  const memo = new Map();
  const maxCachedFragments = 32;
  let cachedCharacters = 0;
  const deferMath = document.currentScript?.hasAttribute("data-defer-math");
  let mathStylesReady = !deferMath;

  function renderExpression(placeholder, token) {
    try {
      window.katex.render(token.expression, placeholder, {
        displayMode:token.display, trust:false, throwOnError:true, strict:"ignore", maxExpand:500, maxSize:24,
      });
    } catch {
      placeholder.textContent = token.raw.trim();
    }
  }

  function loadMath() {
    const {loadAsset} = window.SciShellLayout;
    return Promise.all([
      loadAsset("/static/research-vendor/katex.min.js"),
      loadAsset("/static/research-vendor/katex.min.css"),
    ]).then(() => { mathStylesReady = true; });
  }

  function escapedAt(text, index) {
    let backslashes = 0;
    while (index > 0 && text[--index] === "\\") backslashes++;
    return backslashes % 2 !== 0;
  }

  function mathToken(source) {
    const delimiter = delimiters.find(item => source.startsWith(item.open));
    if (!delimiter) return;
    const {open, close, display} = delimiter;
    const singleDollar = open === "$";
    const start = open.length;
    const candidate = source.slice(0, start + maxMathCharacters + close.length);
    if (singleDollar && /^\s/.test(source.slice(start))) return;
    let end = candidate.indexOf(close, start);
    while (end !== -1 && escapedAt(candidate, end)) end = candidate.indexOf(close, end + close.length);
    if (end <= start) return;
    const expression = source.slice(start, end);
    const after = end + close.length;
    if (!expression.trim() || (singleDollar && (/\n|\s$/.test(expression) || /^\d/.test(source.slice(after)))))
      return;
    return {raw:source.slice(0, after), expression, display};
  }

  function mathBlock(source) {
    const indent = /^ {0,3}/.exec(source)[0];
    const token = mathToken(source.slice(indent.length));
    if (!token?.display) return;
    const rest = source.slice(indent.length + token.raw.length);
    const tail = /^ *(?:\n+|$)/.exec(rest);
    if (tail) return {...token, raw:indent + token.raw + tail[0]};
  }

  function makeFragment(source, {headingShift = 0, breaks = true, allowHTML = false, resolveImage} = {}) {
    if (!window.marked?.Marked || !window.DOMPurify) {
      const fragment = document.createDocumentFragment();
      const plain = document.createElement("pre");
      plain.textContent = source;
      fragment.append(plain);
      return {fragment, cacheable:false};
    }

    const expressions = [];
    const mathPlaceholder = token => {
      const id = expressions.push(token) - 1;
      return '<span data-sci-expression="' + id + '"></span>';
    };
    const parser = new window.marked.Marked({
      gfm:true,
      breaks,
      extensions:[
        {
          name:"sciBlockMath", level:"block",
          start(text) {
            const match = /(?:^|\n) {0,3}(?=\$\$|\\\[)/.exec(text);
            if (match) return match.index + (match[0].startsWith("\n") ? 1 : 0);
          },
          tokenizer(text) {
            const token = mathBlock(text);
            if (token) return {type:"sciBlockMath", ...token};
          },
          renderer:mathPlaceholder,
        },
        {
          name:"sciInlineMath", level:"inline",
          start(text) { const index = text.search(/\$|\\[([]/); if (index >= 0) return index; },
          tokenizer(text) {
            const token = mathToken(text);
            if (token) return {type:"sciInlineMath", ...token};
          },
          renderer:mathPlaceholder,
        },
      ],
      renderer:{
        html(token) { return allowHTML ? token.text : escape(token.text); },
        heading(token) {
          const depth = Math.min(6, token.depth + headingShift);
          return `<h${depth}>${this.parser.parseInline(token.tokens)}</h${depth}>\n`;
        },
        image(token) {
          if (resolveImage) return false;
          return escape(token.text);
        },
      },
    });

    const fragment = window.DOMPurify.sanitize(parser.parse(source), {
      RETURN_DOM_FRAGMENT:true,
      USE_PROFILES:{html:true},
      SANITIZE_NAMED_PROPS:true,
      ALLOW_DATA_ATTR:false,
      ADD_ATTR:["data-sci-expression"],
      FORBID_TAGS:["style", "iframe", "object", "embed", "form", "input", "textarea", "button",
        "script", "video", "audio", "source", "link"],
      FORBID_ATTR:["style", "srcset", "action", "formaction", "ping"],
    });
    for (const image of fragment.querySelectorAll("img")) {
      const target = resolveImage?.(image.getAttribute("src") || "");
      if (typeof target === "string" && target.startsWith("/api/research/")) {
        image.src = target;
        image.loading = "lazy";
      } else {
        image.replaceWith(document.createTextNode(image.alt || "未找到项目图片"));
      }
    }
    for (const anchor of fragment.querySelectorAll("a")) {
      if (/^https?:\/\//i.test(anchor.getAttribute("href") || "")) {
        anchor.target = "_blank";
        anchor.rel = "noopener noreferrer";
      } else {
        anchor.replaceWith(...anchor.childNodes);
      }
    }
    const pending = [];
    for (const placeholder of fragment.querySelectorAll("span[data-sci-expression]")) {
      const token = expressions[Number(placeholder.dataset.sciExpression)];
      placeholder.removeAttribute("data-sci-expression");
      if (!token) continue;
      placeholder.textContent = token.raw.trim();
      if (window.katex && mathStylesReady) renderExpression(placeholder, token);
      else if (deferMath) pending.push([placeholder, token]);
    }
    if (pending.length) {
      // Keep the sanitized Markdown and its raw formulas visible while the
      // typesetter loads. Render into the original fragment's placeholders.
      loadMath().then(() => {
        for (const [placeholder, token] of pending) renderExpression(placeholder, token);
      }, () => {});
    }
    return {fragment, cacheable:!pending.length};
  }

  function render(host, value, options = {}) {
    const source = String(value || "");
    const cache = options.cache && !options.allowHTML && !options.resolveImage && options.breaks !== false;
    const key = cache && source.length <= 32000 ? JSON.stringify([source, options.headingShift || 0]) : "";
    host.classList.add("scientific-content");
    try {
      let content = key && memo.get(key);
      let clone = Boolean(content);
      if (!content) {
        const {fragment, cacheable} = makeFragment(source, options);
        content = fragment;
        if (key && cacheable) {
          memo.set(key, content);
          clone = true;
          cachedCharacters += key.length;
          while (memo.size > maxCachedFragments || cachedCharacters > 256000) {
            const oldest = memo.keys().next().value;
            memo.delete(oldest);
            cachedCharacters -= oldest.length;
          }
        }
      }
      host.replaceChildren(clone ? content.cloneNode(true) : content);
    } catch {
      const plain = document.createElement("pre");
      plain.textContent = source;
      host.replaceChildren(plain);
    }
  }

  async function copySource(source, button) {
    try {
      if (!navigator.clipboard?.writeText) throw Error("clipboard unavailable");
      await navigator.clipboard.writeText(source);
    } catch {
      const field = document.createElement("textarea");
      field.className = "scientific-copy-buffer";
      field.value = source;
      field.readOnly = true;
      (button.closest("dialog[open]") || document.body).append(field);
      try {
        field.select();
        if (!document.execCommand("copy")) throw Error("clipboard unavailable");
      } finally {
        field.remove();
        button.focus();
      }
    }
  }

  function bindCopy(button, source) {
    button.textContent = "复制原文";
    button.onclick = async () => {
      button.disabled = true;
      try {
        await copySource(source, button);
        if (button.isConnected) button.textContent = "已复制";
      } catch {
        if (button.isConnected) button.textContent = "复制失败";
      } finally {
        button.disabled = false;
      }
    };
    return button;
  }

  function copyButton(source) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "scientific-copy";
    return bindCopy(button, source);
  }

  window.SciMarkdown = {render, bindCopy, copyButton};
})();
