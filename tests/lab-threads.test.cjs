const {test} = require("node:test");
const assert = require("node:assert/strict");
const {createDraft, draftURL, matchingThreads, threadTitle, messageText} = require("../web/static/lab-run.js");

test("saved template threads show the research question and keep multi-paragraph messages", () => {
  const question = "How stable is the calibration?\n\nCheck both regimes.";
  const topic = "科研工作流 · 研究问答\n\nTrusted instruction\n\n研究问题\n" + question +
    "\n\n外部资源摘录（供核对）\n来源服务：fixture\n\nAttachment fixture";
  assert.equal(messageText(topic,true),question);
  assert.equal(threadTitle({topic}),"How stable is the calibration?");
  assert.equal(messageText("A legacy conversation" ,true),"A legacy conversation");
});

test("thread search matches title and status without showing archives by default", () => {
  const rooms = [
    {id:"one", title:"First label", topic:"Original scientific evidence", status:"ready", members:[{label:"Physics reader"}],
      lab_thread:{title:"New analysis name", revision:1}},
    {id:"two", topic:"Archived analysis", status:"closed", lab_thread:{archived_at:"2026-11-25", revision:1}},
    {id:"three", topic:"Completed analysis", status:"closed"},
  ];
  assert.equal(threadTitle(rooms[0]), "New analysis name");
  assert.deepEqual(matchingThreads(rooms, "  PHYSICS ", false).map(room=>room.id), ["one"]);
  assert.deepEqual(matchingThreads(rooms, "analysis", false).map(room=>room.id), ["one","three"]);
  assert.deepEqual(matchingThreads(rooms, "analysis", true).map(room=>room.id), ["one","two","three"]);
  assert.equal(rooms[0].topic, "Original scientific evidence");
});

test("unsent drafts are restored per scope and consumed only for the submitted value", async () => {
  class Input extends EventTarget {
    value = "";
    change(text) {this.value=text;this.dispatchEvent(new Event("input"));}
  }
  const archive = new Map();
  const saved = [];
  const req = async (url, method = "GET", value) => {
    const old = archive.get(url) || {text:"", revision:0};
    if (method === "GET") return old;
    assert.equal(method, "PUT");
    assert.equal(value.revision, old.revision);
    const next = {text:value.text, revision:old.revision+1};
    archive.set(url,next);
    saved.push(url);
    return next;
  };
  const first = {id:"p1"}, second = {id:"p2"}, global = {global:true};
  const field = new Input();
  const draft = createDraft({req, input:field, status() {}});
  await draft.select(first);
  field.change("New conversation question");
  await draft.select(first, "thread-one");
  assert.equal(field.value, "");
  field.change("Unsaved follow-up");
  const sent = draft.capture();
  await draft.save();
  await draft.select(second);
  field.change("Other project's question");
  await draft.select(global);
  assert.equal(field.value, "");
  field.change("Global question");
  await draft.save();
  draft.consume(sent,"Older submitted value");
  const later = new Input();
  const reopened = createDraft({req, input:later, status() {}});
  await reopened.select(first);
  assert.equal(later.value, "New conversation question");
  await reopened.select(first,"thread-one");
  assert.equal(later.value, "Unsaved follow-up");
  await reopened.select(second);
  assert.equal(later.value, "Other project's question");
  await reopened.select(global);
  assert.equal(later.value, "Global question");
  draft.consume(sent,"Unsaved follow-up");
  assert.equal(field.value, "Global question");
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(archive.get(draftURL(first,"thread-one")).text,"");
  assert.ok(saved.every(url=>url.startsWith("/api/research/lab/draft?")));
});

test("a failed draft read keeps the editor locked until a retry restores its revision", async () => {
  const input = new EventTarget();
  const messages = [];
  let attempts = 0;
  const draft = createDraft({input, status:message=>messages.push(message), req:async (_, method) => {
    assert.equal(method, undefined);
    if (++attempts === 1) throw Error("Temporarily unavailable");
    return {text:"Recovered project question", revision:4};
  }});
  await draft.select({id:"project"});
  assert.equal(input.disabled, true);
  assert.match(messages.at(-1), /Temporarily unavailable/);
  await draft.save();
  assert.equal(input.value, "Recovered project question");
  assert.equal(input.disabled, false);
  assert.equal(draft.unsaved(), false);
});
