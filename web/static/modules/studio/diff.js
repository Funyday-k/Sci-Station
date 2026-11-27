// Document diff renderer for Roundtable file review (#45). Zero innerHTML sinks.

export function renderDiffContent(container, record) {
  if (!container) return;
  if (!record?.diff) {
    container.textContent = record?.loading ? "补丁读取中…" : "暂无可显示的补丁。";
    return;
  }
  let oldLines = 0;
  let newLines = 0;
  const fragment = document.createDocumentFragment();
  for (const line of record.diff.split("\n")) {
    let kind = "";
    const hunk = line.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/);
    if (hunk) {
      oldLines = hunk[2] === undefined ? 1 : Number(hunk[2]);
      newLines = hunk[4] === undefined ? 1 : Number(hunk[4]);
      kind = "diff-header";
    } else if (oldLines > 0 || newLines > 0) {
      if (line.startsWith("+")) {
        kind = "diff-add";
        newLines--;
      } else if (line.startsWith("-")) {
        kind = "diff-remove";
        oldLines--;
      } else if (line.startsWith(" ")) {
        oldLines--;
        newLines--;
      } else if (line.startsWith("\\")) {
        kind = "diff-header";
      }
    } else if (
      line.startsWith("+++") ||
      line.startsWith("---") ||
      line.startsWith("\\ No newline")
    ) {
      kind = "diff-header";
    }
    const span = document.createElement("span");
    if (kind) span.className = kind;
    span.textContent = `${line}\n`;
    fragment.append(span);
  }
  container.replaceChildren(fragment);
}
