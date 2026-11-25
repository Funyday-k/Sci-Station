"use strict";
(() => {
  const cursor = "${cursor}";
  const formats = {
    heading: ["标题", text => "## " + (text || cursor + "Heading")],
    bold: ["粗体", text => "**" + (text || cursor + "bold text") + "**"],
    italic: ["斜体", text => "_" + (text || cursor + "italic text") + "_"],
    code: ["代码块", text => "```\n" + (text || cursor + "code") + "\n```"],
    link: ["链接", text => "[" + (text || "label") + "](" + cursor + "https://example.com)"],
    wiki: ["双链", text => "[[" + (text || cursor + "Page Title") + "]]"],
    task: ["任务", text => "- [ ] " + (text || cursor + "Task")],
    table: ["表格", () => "| Column | Notes |\n|---|---|\n| " + cursor + "Item | Detail |"]
  };

  function insert(source, start, end, template) {
    const marker = template.indexOf(cursor);
    const replacement = template.split(cursor).join("");
    return {
      value: source.slice(0, start) + replacement + source.slice(end),
      caret: start + (marker < 0 ? replacement.length : marker)
    };
  }

  function format(source, start, end, action) {
    if (!Object.hasOwn(formats, action)) return null;
    const template = formats[action][1](source.slice(start, end));
    if (action === "table" && start < end) {
      return insert(source, end, end, "\n\n" + template + "\n\n");
    }
    return insert(source, start, end, template);
  }

  function expand(source, caret, snippets) {
    const prefix = source.slice(0, caret);
    const selected = snippets.reduce((best, snippet) => prefix.endsWith(snippet.trigger) &&
      (!best || snippet.trigger.length > best.trigger.length) ? snippet : best, null);
    return selected ? insert(source, caret - selected.trigger.length, caret, selected.body) : null;
  }

  const editor = Object.freeze({formats, insert, format, expand});
  if (typeof module !== "undefined" && module.exports) module.exports = editor;
  if (typeof window !== "undefined") window.SciWikiEditor = editor;
})();
