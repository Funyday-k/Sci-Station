// Shared pure-DOM helpers for research workspace forms (#45).

export function createActionButton(label, action, options = {}) {
  const { id = "", kind = "button", glyph = "", title = "", iconOnly = false } = options;
  const button = document.createElement("button");
  button.type = "button";
  button.className = kind;
  button.dataset.action = action;
  button.dataset.id = String(id ?? "");
  if (title || iconOnly) button.title = title || label;
  if (iconOnly) button.setAttribute("aria-label", title || label);
  if (glyph) {
    const svg = window.RoundtableIcons?.iconNode?.(glyph);
    if (svg) button.append(svg);
  }
  if (!iconOnly) button.append(document.createTextNode(String(label ?? "")));
  return button;
}

export function createReadonlyField(labelText, name, value) {
  const label = document.createElement("label");
  label.className = "field";
  const span = document.createElement("span");
  span.textContent = labelText;
  const textarea = document.createElement("textarea");
  textarea.name = name;
  textarea.setAttribute("aria-label", labelText);
  textarea.readOnly = true;
  textarea.value = String(value ?? "");
  label.append(span, textarea);
  return label;
}

export function renderTaskTagChip(host, name, colors) {
  if (!host) return;
  const chip = document.createElement("span");
  chip.className = "task-label";
  chip.style.setProperty("--task-label-bg", colors.color);
  chip.style.setProperty("--task-label-fg", colors.textColor);
  chip.textContent = String(name ?? "");
  host.replaceChildren(chip);
}
