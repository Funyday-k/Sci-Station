const test = require('node:test');
const assert = require('node:assert/strict');
const modules = require('../static/research-modules.js');
const language = require('../static/interface-language.js');

test('module consumer checks effective state in the selected scope', () => {
  assert.equal(modules.endpoint(null), '/api/research/modules');
  assert.equal(modules.endpoint('project&A'), '/api/research/modules?project=project%26A');
  const state = {modules: [
    {id:'projects', enabled:true, effective:true},
    {id:'calendar', enabled:true, effective:false},
  ]};
  assert.equal(modules.isEnabled(state, 'projects'), true);
  assert.equal(modules.isEnabled(state, 'calendar'), false);
  assert.equal(modules.isEnabled(state, 'unknown'), false);
  assert.equal(modules.isEnabled(null, 'projects'), false);
});

test('interface language follows system or keeps an explicit choice', () => {
  assert.equal(language.resolve('system', 'zh-TW'), 'zh-Hans');
  assert.equal(language.resolve('system', 'en-HK'), 'en');
  assert.equal(language.resolve('system', 'fr-FR'), 'en');
  assert.equal(language.resolve('zh-Hans', 'en-GB'), 'zh-Hans');
  assert.equal(language.resolve('en', 'zh-HK'), 'en');
});
