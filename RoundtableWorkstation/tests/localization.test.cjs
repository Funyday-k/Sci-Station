const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const catalog = require('../static/interface-catalog.json');
const {translate} = require('../static/interface-language.js');
const script = fs.readFileSync(require.resolve('../static/interface-language.js'), 'utf8');

function fixture(preference) {
  const root = {};
  const appListeners = new Map();
  const button = {textContent: '查找', dataset: {}};
  const paperTitle = {textContent: '查找', dataset: {}};
  const attrs = new Map([['aria-label', '查找全文'], ['placeholder', '查找全文'],
    ['data-l10n-aria-label', 'readerFindText'], ['data-l10n-placeholder', 'readerFindText']]);
  const readerSearch = {
    setAttribute: (key, value) => attrs.set(key, value),
    getAttribute: key => attrs.get(key) ?? null,
  };
  button.getAttribute = () => 'find';
  const window = {
    addEventListener: (name, handler) => appListeners.set(name, handler),
    dispatchEvent: event => appListeners.get(event.type)?.(event),
  };
  const navigator = {languages: ['zh-TW', 'en-US'], language: 'en-US'};
  const document = {
    readyState: 'complete', documentElement: root, querySelector: () => null,
    querySelectorAll: selector => ({
      '[data-l10n-text]': [button], '[data-l10n-aria-label]': [readerSearch],
      '[data-l10n-placeholder]': [readerSearch],
    })[selector] || [],
  };
  const fetch = async url => ({ok: true, json: async () => url.endsWith('/interface') ? {language: preference} : catalog});
  const runtime = vm.createContext({document, window, navigator, fetch, Event});
  vm.runInContext(script, runtime);
  return {window, root, navigator, button, paperTitle, readerSearch};
}

test('switches authored button and accessible reader copy without reading paper titles', async () => {
  const app = fixture('system');
  await app.window.SciStationI18n.ready;
  assert.equal(app.root.lang, 'zh-Hans');
  assert.equal(app.button.textContent, '查找');
  assert.equal(app.readerSearch.getAttribute('aria-label'), '查找全文');
  app.navigator.languages = ['en-GB', 'zh-Hans'];
  app.window.dispatchEvent(new Event('languagechange'));
  assert.equal(app.root.lang, 'en');
  assert.equal(app.button.textContent, 'Find');
  assert.equal(app.readerSearch.getAttribute('aria-label'), 'Find text');
  assert.equal(app.readerSearch.getAttribute('placeholder'), 'Find text');
  assert.equal(app.paperTitle.textContent, '查找');
});

test('the selected workspace preference wins over system changes and formats reader values', async () => {
  const app = fixture('en');
  await app.window.SciStationI18n.ready;
  assert.equal(app.root.lang, 'en');
  app.window.dispatchEvent(new Event('languagechange'));
  assert.equal(app.root.lang, 'en');
  assert.equal(app.window.SciStationI18n.message('readerPageFormat', 3), 'Page 3');
  assert.equal(translate(catalog, 'zh-Hans', 'readerPageFormat', [3]), '第 3 页');
});

test('dynamic workspace destinations use the active locale', async t => {
  const app = fixture('system');
  await app.window.SciStationI18n.ready;
  globalThis.SciStationI18n = app.window.SciStationI18n;
  t.after(() => { delete globalThis.SciStationI18n; });
  const {destinations} = require('../static/workspace-nav.js');
  const url = new URL('http://127.0.0.1/research?view=papers');
  assert.equal(destinations(url).find(item => item.active).name, '论文库');
  app.navigator.languages = ['en-GB'];
  app.window.dispatchEvent(new Event('languagechange'));
  assert.equal(destinations(url).find(item => item.active).name, 'Library');
  assert.equal(destinations(url).find(item => item.key === 'settings').name, 'Settings');
});
