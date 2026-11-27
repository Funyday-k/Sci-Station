"use strict";

// DOM subset used by the Research controller tests. Text is always a text node.
// Rendering tests can inspect the tree or serialize it, just as a browser would.
const voidTags = new Set(["br", "hr", "img", "input", "source", "wbr"]);
const escapeText = value => String(value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
const escapeAttribute = value => escapeText(value).replaceAll('"', "&quot;");

function serialize(node) {
  if (node == null) return "";
  if (Array.isArray(node)) return node.map(serialize).join("");
  if (typeof node !== "object") return escapeText(node);
  if (node.nodeType === 3) return escapeText(node.data);
  const children = node.childNodes.map(serialize).join("");
  if (node.nodeType === 11) return children;
  const attrs = [...node.attributes].map(([key, value]) => ' ' + key + '="' + escapeAttribute(value) + '"').join("");
  const name = node.localName;
  return "<" + name + attrs + ">" + (voidTags.has(name) ? "" : children + "</" + name + ">");
}

class TestNode extends EventTarget {
  constructor(document, name, type = 1) {
    super();
    this.ownerDocument = document;
    this.nodeType = type;
    this.localName = name;
    this.tagName = type === 1 ? name.toUpperCase() : undefined;
    this.childNodes = [];
    this.attributes = new Map();
    this.dataset = {};
    const classes = () => (this.className || "").split(/\s+/).filter(Boolean);
    this.classList = {
      contains: token => classes().includes(token),
      add: (...tokens) => { this.className = [...new Set([...classes(), ...tokens])].join(" "); },
      remove: (...tokens) => { this.className = classes().filter(token => !tokens.includes(token)).join(" "); },
      toggle: (token, force) => {
        const on = force ?? !this.classList.contains(token);
        if (on) this.classList.add(token);
        else this.classList.remove(token);
        return on;
      }
    };
    const styles = new Map();
    this.style = {
      setProperty: (key, val) => {
        styles.set(key, String(val));
        this.setAttribute("style", [...styles].map(([k, v]) => k + ":" + v).join(";"));
      },
      getPropertyValue: key => styles.get(key) || ""
    };
  }
  setAttribute(key, value) {
    this.attributes.set(key, String(value));
    if (key.startsWith("data-")) this.dataset[key.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = String(value);
  }
  getAttribute(key) { return this.attributes.get(key) ?? null; }
  hasAttribute(key) { return this.attributes.has(key); }
  get className() { return this.getAttribute("class") || ""; }
  set className(value) { this.setAttribute("class", value); }
  get children() { return this.childNodes.filter(node => node.nodeType === 1); }
  get firstElementChild() { return this.children[0] || null; }
  get textContent() { return this.nodeType === 3 ? this.data : this.childNodes.map(node => node.textContent).join(""); }
  set textContent(value) {
    if (this.nodeType === 3) this.data = String(value);
    else this.replaceChildren(String(value));
  }
  get innerHTML() { return this.childNodes.map(serialize).join(""); }
  get outerHTML() { return serialize(this); }
  append(...items) {
    for (let node of items) {
      if (node?.nodeType === 11) {
        this.append(...node.childNodes.splice(0));
      } else {
        if (!node?.nodeType) node = this.ownerDocument.createTextNode(node);
        if (node.parentNode) {
          const siblings = node.parentNode.childNodes;
          const index = siblings.indexOf(node);
          if (index !== -1) siblings.splice(index, 1);
        }
        node.parentNode = this;
        this.childNodes.push(node);
      }
    }
  }
  replaceChildren(...items) {
    for (const node of this.childNodes) node.parentNode = null;
    this.childNodes = [];
    this.append(...items);
  }
}

function createTestDocument() {
  return {
    createElement(name) { return new TestNode(this, name); },
    createElementNS(namespace, name) {
      const node = this.createElement(name);
      node.namespaceURI = namespace;
      return node;
    },
    createTextNode(text) {
      const node = new TestNode(this, "#text", 3);
      node.data = String(text);
      return node;
    },
    createDocumentFragment() { return new TestNode(this, "#fragment", 11); }
  };
}

module.exports = {createTestDocument, serialize};
