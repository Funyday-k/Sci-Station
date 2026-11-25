'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const metrics = require('../static/review-metrics.js');
const patch = (before, after) => {
  const old = before === '' ? [] : before.split('\n');
  const next = after === '' ? [] : after.split('\n');
  return `--- a/paper.md\n+++ b/paper.md\n@@ -1,${old.length} +1,${next.length} @@\n` + old.map(s => '-' + s + '\n').join('') + next.map(s => '+' + s + '\n').join('');
};
const run = (before, after, filename = 'paper.md') => metrics.analyze(patch(before, after), filename);

test('one word in a long sentence counts only its changed tokens', () => {
  const r = run('The long unchanged sentence has one old word at the end.', 'The long unchanged sentence has one new word at the end.');
  assert.equal(r.status, 'ok');
  assert.deepEqual(r.lines, { added: 1, removed: 1 });
  assert.deepEqual(r.words, { added: 1, removed: 1 });
  assert.deepEqual(r.characters, { added: 3, removed: 3 });
});

test('pure addition/deletion, whitespace and cross-line replacements stay neutral', () => {
  assert.deepEqual(run('', 'Hello world\n你好 世界').words, { added: 4, removed: 0 });
  assert.deepEqual(run('Hello world', '').words, { added: 0, removed: 2 });
  const whitespace = run('Hello world', ' Hello\nworld\t');
  assert.deepEqual(whitespace.words, { added: 0, removed: 0 });
  assert.deepEqual(whitespace.characters, { added: 0, removed: 0 });
  assert.deepEqual(run('Hello old\nworld', 'Hello new world').words, { added: 1, removed: 1 });
});

test('Unicode uses graphemes and Chinese-English word boundaries', () => {
  const r = run('', '你好 世界 hello 42 e\u0301 👩‍👩‍👧‍👦');
  assert.deepEqual(r.characters, { added: 13, removed: 0 });
  const expected = [...new Intl.Segmenter('zh', { granularity: 'word' }).segment('你好 世界 hello 42 e\u0301 👩‍👩‍👧‍👦')].filter(s => s.isWordLike).length;
  assert.deepEqual(r.words, { added: expected, removed: 0 });
  assert.deepEqual(run('👩‍👩‍👧‍👦', '👍🏽').characters, { added: 1, removed: 1 });
});

test('hunk counts, not header-looking source, distinguish file metadata', () => {
  const diff = 'diff --git a/paper.md b/paper.md\nindex a..b 100644\n--- a/paper.md\n+++ b/paper.md\n@@ -1,2 +1,2 @@\n---not a header\n-old\n+++not a header\n+new\n';
  const r = metrics.analyze(diff, 'paper.md');
  assert.equal(r.status, 'ok');
  assert.deepEqual(r.lines, { added: 2, removed: 2 });
  assert.deepEqual(r.words, { added: 1, removed: 1 });
});

test('CRLF, omitted hunk counts, EOF markers and mixed hunks parse exactly', () => {
  const diff = '--- a/x.md\r\n+++ b/x.md\r\n@@ -1 +1 @@\r\n-old\r\n\\ No newline at end of file\r\n+new\r\n\\ No newline at end of file\r\n@@ -5,2 +5,2 @@ function\r\n stable\r\n-other\r\n+changed\r\n';
  const r = metrics.analyze(diff, 'x.md');
  assert.equal(r.status, 'ok');
  assert.deepEqual(r.lines, { added: 2, removed: 2 });
  assert.deepEqual(r.words, { added: 2, removed: 2 });
});

test('context and hunk boundaries prevent unrelated fragment cancellation', () => {
  const diff = '@@ -1,3 +1,3 @@\n-alpha\n+beta\n context\n-beta\n+alpha\n@@ -7 +7 @@\n-one\n+two\n';
  assert.deepEqual(metrics.analyze(diff, 'notes.org').words, { added: 3, removed: 3 });
});

test('document extension gating, source syntax, empty diffs and invalid input are explicit', () => {
  for (const ext of ['tex','md','mdx','txt','rst','org','adoc','markdown','ltx','LaTeX']) assert.equal(run('a', 'b', 'FILE.' + ext).document, true);
  const code = run('a', 'b', 'main.go');
  assert.deepEqual(code.lines, { added: 1, removed: 1 });
  assert.equal(code.document, false); assert.equal(code.words, undefined);
  assert.deepEqual(run('\\section{Old}', '\\section{New}', 'x.tex').words, { added: 1, removed: 1 });
  assert.deepEqual(metrics.analyze('', 'x.md').words, { added: 0, removed: 0 });
  for (const diff of [undefined, 'Binary files differ', '@@ -1,2 +1,2 @@\n-a\n+b\n', '@@@ -1,1 -1,1 +1,1 @@@\n-x\n+y']) {
    const r = metrics.analyze(diff, 'x.md');
    assert.equal(r.status, 'unavailable'); assert.equal(r.lines, null); assert.ok(r.reason);
  }
});

test('bounded exact computation never presents estimates as metrics', () => {
  const r = run('a'.repeat(4000), 'b'.repeat(4000));
  assert.equal(r.status, 'unavailable');
  assert.equal(r.reason, 'exact-comparison-budget-exceeded');
  assert.deepEqual(r.lines, { added: 1, removed: 1 });
  assert.equal(r.characters, undefined); assert.equal(r.words, undefined);
  const large = run('a'.repeat(400001), 'b');
  assert.equal(large.reason, 'fragment-size-budget-exceeded');
  assert.deepEqual(large.lines, { added: 1, removed: 1 });
});

test('random short comparisons agree with an independent LCS matrix', () => {
  let seed = 47;
  const rand = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed; };
  const lcs = (a,b) => {
    const d = Array.from({length:a.length+1},()=>new Uint16Array(b.length+1));
    for(let i=1;i<=a.length;i++)for(let j=1;j<=b.length;j++)d[i][j]=a[i-1]===b[j-1]?d[i-1][j-1]+1:Math.max(d[i-1][j],d[i][j-1]);
    return d[a.length][b.length];
  };
  for(let t=0;t<250;t++){
    const a=Array.from({length:rand()%25},()=>String.fromCharCode(97+rand()%5)).join('');
    const b=Array.from({length:rand()%25},()=>String.fromCharCode(97+rand()%5)).join('');
    const common=lcs(a,b),r=run(a,b);
    assert.equal(r.status,'ok'); assert.deepEqual(r.characters,{added:b.length-common,removed:a.length-common});
  }
});

test('exact-content cache separates revisions and worker preserves request ids', () => {
  const first=patch('old','new'),second=patch('old','new extra');
  assert.strictEqual(metrics.analyze(first,'a.md'),metrics.analyze(first,'other.md'));
  assert.deepEqual(metrics.analyze(second,'a.md').words,{added:2,removed:1});
  const replies=[];
  const ctx=vm.createContext({Intl,self:{postMessage:x=>replies.push(x)}});
  ctx.importScripts = file => vm.runInContext(fs.readFileSync(path.join(__dirname,'../static',file),'utf8'),ctx);
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../static/review-worker.js'),'utf8'),ctx);
  ctx.self.onmessage({data:{id:'revision-42',diff:first,path:'a.md'}});
  assert.equal(replies[0].id,'revision-42');
  assert.equal(replies[0].metrics.status,'ok');
  assert.equal(replies[0].metrics.words.added,1);
});
