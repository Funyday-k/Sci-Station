'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');

class FakeElement {
  constructor(tag = 'div') { this.tagName = tag; this.attrs = {}; this.listeners = {}; this.children = []; this.hidden = false; this.value = ''; this.selectionStart = 0; this.selectionEnd = 0; this.classList = {add() {}}; }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  getAttribute(k) { return this.attrs[k]; }
  removeAttribute(k) { delete this.attrs[k]; }
  addEventListener(k, fn) { (this.listeners[k] ||= []).push(fn); }
  dispatchEvent(event) { for (const fn of this.listeners[event.type] || []) fn(event); return true; }
  append(child) { this.children.push(child); }
  replaceChildren(...items) { this.children = items; }
  setRangeText(value, start, end, mode) { this.value = this.value.slice(0, start) + value + this.value.slice(end); this.selectionStart = this.selectionEnd = mode === 'end' ? start + value.length : start; }
  focus() { this.focused = true; }
  preventDefault() { this.defaultPrevented = true; }
}
global.window = {};
global.document = { createElement: tag => new FakeElement(tag) };
global.Event = class { constructor(type, init = {}) { this.type = type; Object.assign(this, init); } };
require('../web/static/seat-mention.js');
const resolve = window.RoundtableMention.resolve;
const members = [
  { id: 'seat-a', label: '分析员 · 席位 1' },
  { id: 'seat-b', label: '分析员 · 席位 2' },
  { id: 'seat-c', label: 'Reviewer' },
];

test('resolves names next to Chinese prose and punctuation, and stable IDs', () => {
  assert.deepEqual(resolve('请@分析员 · 席位 2，复核', members), { target: 'seat-b' });
  assert.deepEqual(resolve('请@seat-c！', members), { target: 'seat-c' });
});

test('preserves ordinary prose and email addresses, blocks unknown, ambiguous, multiple, and lone @', () => {
  assert.deepEqual(resolve('hello a@b.example, 普通文本', members), { target: '' });
  assert.match(resolve('发给 @missing，复核', members).error, /无法识别/);
  assert.match(resolve('@same', [{ id:'one', label:'same' }, { id:'two', label:'same' }]).error, /重名/);
  assert.match(resolve('@Reviewer @seat-a', members).error, /只能发送给一个席位/);
  assert.match(resolve('你好 @', members).error, /单独的 @/);
});

function fixture() {
  const textarea = new FakeElement('textarea'), list = new FakeElement(), status = new FakeElement();
  const api = window.RoundtableMention.mount({textarea, members, status, list});
  const key = value => { const event = {key:value, preventDefault() { this.defaultPrevented = true; }}; textarea.dispatchEvent(Object.assign(event, {type:'keydown'})); return event; };
  const type = value => { textarea.value = value; textarea.selectionStart = textarea.selectionEnd = value.length; textarea.dispatchEvent({type:'input'}); };
  return {textarea, list, status, api, key, type};
}

test('menu uses accessible listbox state, supports arrows and selection, then stays closed', () => {
  const f = fixture(); f.type('@');
  assert.equal(f.list.hidden, false);
  assert.equal(f.textarea.getAttribute('aria-controls'), f.list.id);
  assert.equal(f.textarea.getAttribute('aria-expanded'), 'true');
  assert.equal(f.textarea.getAttribute('aria-activedescendant'), `${f.list.id}-option-0`);
  f.key('ArrowDown');
  assert.equal(f.textarea.getAttribute('aria-activedescendant'), `${f.list.id}-option-1`);
  f.key('Enter');
  assert.match(f.textarea.value, /^@分析员 · 席位 2\s$/u);
  assert.equal(f.list.hidden, true);
  assert.match(f.status.textContent, /仅 分析员 · 席位 2 回应/);
  f.textarea.dispatchEvent({type:'keyup'});
  assert.equal(f.list.hidden, true);
  assert.deepEqual(f.api.resolve(), {target:'seat-b'});
});

test('Escape dismisses until the next edit, IME composition does not intercept keys, and open inserts @', () => {
  const f = fixture(); f.type('@'); f.key('Escape');
  assert.equal(f.list.hidden, true);
  f.textarea.dispatchEvent({type:'keyup'}); assert.equal(f.list.hidden, true);
  f.textarea.dispatchEvent({type:'compositionstart'});
  const enter = f.key('Enter'); assert.equal(enter.defaultPrevented, undefined);
  f.textarea.dispatchEvent({type:'compositionend'}); assert.equal(f.list.hidden, false);
  f.api.clear(); f.textarea.value = 'hello '; f.textarea.selectionStart = f.textarea.selectionEnd = 6;
  f.api.open(); assert.equal(f.textarea.value, 'hello @'); assert.equal(f.list.hidden, false);
});

test('click selection inserts a usable mention and blur closes the list', async () => {
  const f = fixture(); f.type('@Reviewer');
  f.list.children[0].dispatchEvent({type:'click'});
  assert.equal(f.textarea.value, '@Reviewer ');
  assert.deepEqual(f.api.resolve(), {target:'seat-c'});
  f.type('@'); f.textarea.dispatchEvent({type:'blur'});
  await new Promise(resolve => setTimeout(resolve, 1));
  assert.equal(f.list.hidden, true);
});

test('literal code, identifier prefixes, and editing a recipient do not misroute', () => {
  const seats = [{id:"a", label:"review"}, {id:"b", label:"second"}];
  assert.deepEqual(resolve("代码 `@review` 和 `邮件@名称`", seats), {target:""});
  assert.match(resolve("@review-bot", seats).error, /无法识别/);
  assert.equal(resolve("@review. Thanks", seats).target, "a");
  assert.equal(resolve("请@second，复核", seats).target, "b");
  const f = fixture();
  f.type("@Reviewer 请检查");
  assert.match(f.status.textContent, /仅 Reviewer 回应/);
  f.type("请检查");
  assert.equal(f.status.textContent, "");
});
