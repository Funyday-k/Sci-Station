const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const source = fs.readFileSync(path.join(__dirname, "../static/board-presence.js"), "utf8");

test("an older meeting cannot publish a late cursor; release reconciles the current document", async () => {
  const requests = [];
  const timers = new Map();
  let tick = 0;
  const window = {};
  const fetch = (url, options) => new Promise(resolve => requests.push({url, options, resolve}));
  vm.runInNewContext(source, {
    window, URL, AbortController, fetch, location: {href:"http://localhost:9000/studio"},
    setTimeout(fn) { timers.set(++tick, fn); return tick; },
    clearTimeout(id) { timers.delete(id); },
  });
  const snapshots = [], refreshed = [];
  const watch = window.RoundtableBoardPresence.mount(s => snapshots.push(s), id => refreshed.push(id));
  const old = {id:"one", status:"running", board:{state:"published"}};
  const current = {...old, id:"two"};
  const step = () => new Promise(resolve => setImmediate(resolve));
  const respond = (i, session_id, seq, cursors) => requests[i].resolve({
    ok:true, json:async () => ({session_id, seq, cursors}),
  });
  watch.sync({...old,board:{state:"empty"}},true);
  assert.equal(requests.length,0);
  watch.sync(old,true);
  watch.sync(current,true);
  assert.equal(requests[0].options.signal.aborted,true);
  respond(0,"one",3,[{seat:"one-seat"}]);
  respond(1,"two",1,[{seat:"two-seat"}]);
  await step();
  assert.deepEqual(snapshots.filter(Boolean).map(s => s.session_id),["two"]);
  assert.equal(timers.size,1);
  const runTimer = [...timers.values()][0];
  timers.clear(); runTimer();
  assert.equal(requests[2].url.searchParams.get("after"),"1");
  respond(2,"two",2,[]);
  await step();
  assert.deepEqual(refreshed,["two"]);
  watch.sync(current,false);
  assert.equal(timers.size,0);
  assert.equal(snapshots.at(-1),null);
});
