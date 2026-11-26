const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const read = name => fs.readFileSync(path.join(__dirname, "..", "static", name), "utf8");
const plain = value => JSON.parse(JSON.stringify(value));
const one = { path: "/work/one", name: "one" };
const two = { path: "/work/two", name: "two" };
const studio = read("studio.js");

function fakeDOM() {
  const elements = new Map();
  function node() {
    return {
      value: "",
      checked: false,
      disabled: false,
      open: false,
      dataset: {},
      textContent: "",
      hidden: false,
      listeners: {},
      children: [],
      classList: { add() {}, remove() {}, toggle() {} },
      setAttribute() {},
      removeAttribute() {},
      setCustomValidity(message) { this.validationMessage = message; },
      reportValidity() { this.reportedValidity = true; },
      checkValidity() { return true; },
      addEventListener(name, callback) { this.listeners[name] = callback; },
      append(...children) { this.children.push(...children); },
      replaceChildren(...children) { this.children = children; },
      querySelector(selector) {
        this.queries ||= new Map();
        if (!this.queries.has(selector)) this.queries.set(selector, node());
        return this.queries.get(selector);
      },
      add(child) { this.append(child); },
      focus() {},
    };
  }
  const $ = id => {
    if (!elements.has(id)) elements.set(id, node());
    return elements.get(id);
  };
  return { $, document: { createElement: node, createTextNode: text => Object.assign(node(), {textContent:text}), getElementById: $, querySelectorAll: () => [] } };
}

function continuous(window, document) {
  vm.runInNewContext(read("ui-icons.js"), { window, document });
  vm.runInNewContext(read("continuous-ui.js"), { window, document });
  return window.RoundtableContinuous;
}

function inputLimit(document) {
  const window = {};
  vm.runInNewContext(read("input-limit.js"), { window, document });
  return window.RoundtableInputLimit.paint;
}

test("both clients only display a length warning above the Unicode code-point limit", () => {
  const { $, document } = fakeDOM();
  const paint = inputLimit(document);
  const boundary = "中😀".repeat(6000);
  for (const id of ["new-topic", "run-note", "topic", "followup-note"]) {
    const input = $(id);
    const hint = $(id + "-limit");
    input.value = boundary;
    assert.equal(paint(id), true);
    assert.equal(hint.hidden, true);
    assert.equal(hint.textContent, "");
    input.value += "😀";
    assert.equal(paint(id), false);
    assert.match(input.validationMessage, /超出 1 个字符/);
    assert.equal(hint.hidden, false);
    assert.equal(hint.textContent, input.validationMessage);
    input.value = "👩‍💻";
    assert.equal(paint(id), true);
    assert.equal(hint.hidden, true);
    assert.equal(hint.textContent, "");
    assert.equal(input.validationMessage, "");
  }
});

test("one confirmed project defaults; stale and partial choices do not guess", () => {
  const window = {};
  vm.runInNewContext(read("projects.js"), { window });
  const { resolveSelection } = window.RoundtableProjects;
  assert.equal(resolveSelection([], "/old", true), null);
  assert.equal(resolveSelection([one, two], "/old", true), null);
  assert.equal(resolveSelection([one, two], "", true), null);
  assert.equal(resolveSelection([one], "", false), null);
  assert.equal(resolveSelection([one], "/old", true), one);
  assert.equal(resolveSelection([one, two], two.path, false), two);
});

test("project switching restores only that project's draft and drops legacy path and agenda values", async () => {
  const { $, document } = fakeDOM();
  const window = {
    addEventListener() {},
    RoundtableSeating: { mount: () => ({ render() {} }) },
  };
  continuous(window, document);
  const draftStore = new Map([["studio.setup-drafts.v1", JSON.stringify({
    [one.path]: {
      project: "/old-mismatched-path",
      topic: "first project draft",
      agenda: ["legacy agenda"],
      customAgenda: true,
      preset: "review",
    },
    [two.path]: { topic: "second project draft", members: [null] },
  })]]);
  vm.runInNewContext(read("studio-setup.js"), {
    window, document, Option: function(text, value) { this.text = text; this.value = value; },
  });
  const setup = window.RoundtableSetup.mount({
    api: async () => ({ models: [{ id: "test", label: "Test", source: "sample", efforts: [] }], default_model: "test" }),
    assetFor: () => "",
    storageGet: key => draftStore.get(key),
    storageSet: (key, value) => draftStore.set(key, value),
  });
  setup.open(one);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal($("new-topic").value, "first project draft");
  assert.equal($("create-project-access").textContent, "讨论仅读取项目文件");
  assert.deepEqual(plain(setup.payload()), {
    project: one.path, members: [{ model: "test", effort: "auto" }], preset: "review",
  });
  $("new-topic").value = "unsent edits";
  $("new-topic").listeners.input();
  setup.open(two);
  assert.equal($("new-topic").value, "second project draft");
  assert.equal($("create-project-access").textContent, "讨论仅读取项目文件");
  assert.equal(setup.payload().project, two.path);
  setup.suspend();
  assert.equal(setup.canSubmit(), false);
  setup.open(one);
  assert.equal($("new-topic").value, "unsent edits");
  assert.equal(setup.payload().project, one.path);
  setup.complete();
  setup.open(one);
  assert.equal($("new-topic").value, "");
  setup.open(two);
  assert.equal($("new-topic").value, "second project draft");
});

test("project attachments and a named chief survive switching drafts", async () => {
  const { $, document } = fakeDOM();
  const window = {
    addEventListener() {},
    RoundtableSeating: { mount: () => ({ render() {} }) },
  };
  continuous(window, document);
  const draftStore = new Map([["studio.setup-drafts.v1", JSON.stringify({
    [one.path]: {
      topic: "@Second · 席位 2，请起草议程",
      members: [{model:"first", effort:"auto"}, {model:"second", effort:"high"}],
    },
  })]]);
  let attached = [], uploading = false, failed = false;
  const materials = {
    set(items) { attached = items || []; },
    reset() { attached = []; },
    ready() { return attached; },
    busy() { return uploading; },
    failed() { return failed; },
  };
  for (const script of ["studio-setup.js", "seat-mention.js"]) {
    vm.runInNewContext(read(script), {
      window, document, Option: function(text, value) { this.text = text; this.value = value; },
    });
  }
  const setup = window.RoundtableSetup.mount({
    api: async () => ({
      models: [{id:"first", label:"First", efforts:[]}, {id:"second", label:"Second", efforts:["high"]}],
      default_model: "first",
    }),
    assetFor: () => "",
    storageGet: key => draftStore.get(key),
    storageSet: (key, value) => draftStore.set(key, value),
    materials,
  });
  setup.open(one);
  await new Promise(resolve => setImmediate(resolve));
  materials.set([{id:"material-1", name:"notes.md", mime:"text/markdown", excerpt:"private extract"}]);
  uploading = true;
  setup.materialsChanged();
  assert.equal($("create-submit").disabled, true);
  assert.equal(setup.canSubmit(), false);
  uploading = false;
  failed = true;
  assert.equal(setup.canSubmit(), false);
  failed = false;
  setup.materialsChanged();
  assert.equal(setup.canSubmit(), true);
  setup.open(two);
  assert.equal(setup.payload().material_ids, undefined);
  setup.open(one);
  const { target } = window.RoundtableMention.resolve($("new-topic").value, setup.mentionMembers());
  assert.equal(target, "seat-2");
  assert.deepEqual(plain(setup.payload(target)), {
    project: one.path, preset: "work", material_ids: ["material-1"],
    members: [{model:"second", effort:"high"}, {model:"first", effort:"auto"}],
  });
  assert.match(draftStore.get("studio.setup-drafts.v1"), /notes\.md/);
  assert.doesNotMatch(draftStore.get("studio.setup-drafts.v1"), /private extract/);
  setup.complete();
  setup.open(one);
  assert.equal(setup.payload().material_ids, undefined);
});

test("setup shows read-only discussion in every preset and no project directories in the global scope", async () => {
  const { $, document } = fakeDOM();
  const window = {
    addEventListener() {},
    RoundtableSeating: { mount: () => ({ render() {} }) },
  };
  continuous(window, document);
  vm.runInNewContext(read("studio-setup.js"), {
    window, document, Option: function(text, value) { this.text = text; this.value = value; },
  });
  const setup = window.RoundtableSetup.mount({
    api: async () => ({ models: [{ id: "test", label: "Test", source: "sample", efforts: [] }], default_model: "test" }),
    assetFor: () => "",
    storageGet: () => "",
    storageSet() {},
  });
  setup.open(one);
  await new Promise(resolve => setImmediate(resolve));
  for (const [id] of [
    ["work"], ["review"], ["prioritize"], ["forum"],
  ]) {
    const input = $("preset-options").children.find(card => card.children[0].value === id).children[0];
    input.checked = true;
    input.listeners.change();
    assert.equal($("create-project-access").textContent, "讨论仅读取项目文件");
  }
  setup.open({id: "@global", path: "", global: true});
  assert.equal($("create-project-access").textContent, "全局圆桌无项目文件访问");
  const html = read("studio.html");
  assert.match(html, /配置持续推进/);
  assert.match(html, /创建后请先核对议程，再点击「开始持续推进」/);
  assert.ok(html.indexOf("id=\"create-project-access\"") < html.indexOf("id=\"create-continuous\""));
  assert.match(html, /id=\"run-continuous-enabled\"[^>]*\/>持续推进/);
});

test("create refuses a stale path and retains the current draft on a request failure", async () => {
  const { $, document } = fakeDOM();
  const state = { writing: false, draftOpen: true, activeProject: one.path, enteredSessions: new Set() };
  const calls = [];
  const errors = [];
  let completions = 0;
  let chiefTarget = "";
  let payloadPath = two.path;
  let failNext = true;
  let focusedAfterCreation = "";
  $("table-scroll").focus = () => { focusedAfterCreation = "conversation"; };
  const start = studio.indexOf('  $("create-form").addEventListener("submit"');
  const end = studio.indexOf('  $("run-form").addEventListener("submit"', start);
  vm.runInNewContext(studio.slice(start, end), {
    $, state, paintTextLimit: inputLimit(document),
    projects: { available: () => [one, two] },
    topicMention: { resolve: () => ({target:"seat-2"}) },
    setup: {
      canSubmit: () => true,
      payload: target => {
        chiefTarget = target;
        return { project: payloadPath, members: [{ model: "test", effort: "auto" }], preset: "work", material_ids: ["material-1"] };
      },
      complete: () => { completions++; },
    },
    api: async (endpoint, payload) => {
      calls.push({ endpoint, payload });
      if (failNext) {
        failNext = false;
        throw Error("connection interrupted");
      }
      return { id: "created", board: {state: "empty", modules: []} };
    },
    showError: error => errors.push(error.message),
    clearError() {}, updateControls() {}, syncUrl() {}, storageSet() {},
    hasBoard: session => session.board?.state === "published",
    updateSession() {}, requestTitle() {}, schedulePoll() {},
  });
  const submit = () => $("create-form").listeners.submit({ preventDefault() {} });
  $("new-topic").value = "中😀".repeat(6001);
  await submit();
  assert.equal($("new-topic").reportedValidity, true);
  assert.equal(calls.length, 0);
  $("new-topic").value = "same draft";
  await submit();
  assert.equal(calls.length, 0);
  payloadPath = one.path;
  await submit();
  assert.equal(completions, 0);
  assert.equal($("new-topic").value, "same draft");
  assert.equal(state.writing, false);
  assert.deepEqual(errors, ["connection interrupted"]);
  await submit();
  assert.equal(completions, 1);
  assert.equal($("new-topic").value, "");
  assert.equal(focusedAfterCreation, "conversation");
  assert.deepEqual(errors, ["connection interrupted"]);
  assert.equal(calls.length, 2);
  assert.equal(chiefTarget, "seat-2");
  assert.deepEqual(plain(calls[0]), plain(calls[1]));
  assert.deepEqual(plain(calls[1]), {
    endpoint: "/sessions",
    payload: { topic: "same draft", project: one.path, members: [{ model: "test", effort: "auto" }], preset: "work", material_ids: ["material-1"] },
  });
});

test("continuous settings persist in drafts and survive all four meeting mode changes", async () => {
  const { $, document } = fakeDOM();
  const window = {
    addEventListener() {},
    RoundtableSeating: { mount: () => ({ render() {} }) },
  };
  const continuousAPI = continuous(window, document);
  const draftStore = new Map();
  vm.runInNewContext(read("studio-setup.js"), {
    window, document, Option: function(text, value) { this.text = text; this.value = value; },
  });
  const setup = window.RoundtableSetup.mount({
    api: async () => ({ models: [{ id: "test", label: "Test", source: "sample", efforts: [] }], default_model: "test" }),
    assetFor: () => "",
    storageGet: key => draftStore.get(key),
    storageSet: (key, value) => draftStore.set(key, value),
  });
  setup.open(one);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal($("preset-options").children.length, 4);
  assert.equal($("create-continuous-enabled").checked, false);
  assert.equal($("create-continuous-max-rounds").value, "12");
  assert.equal($("create-continuous-summary-every").value, "4");
  $("new-topic").value = "Create topic";
  $("create-continuous-enabled").checked = true;
  $("create-continuous-enabled").listeners.change();
  $("create-continuous-criteria").value = "Complete the reproducible check";
  $("create-continuous-criteria").listeners.input();
  $("create-continuous-max-rounds").value = "6";
  $("create-continuous-max-rounds").listeners.input();
  $("create-continuous-summary-every").value = "3";
  $("create-continuous-summary-every").listeners.input();
  for (const card of $("preset-options").children) {
    const input = card.children[0];
    const mode = input.value;
    input.checked = true;
    input.listeners.change();
    assert.equal(setup.payload().preset, mode);
    assert.deepEqual(plain(setup.payload().continuous), {
      goal: "Create topic", criteria: "Complete the reproducible check", max_rounds: 6, summary_every: 3,
    });
  }
  setup.suspend();
  setup.open(two);
  assert.equal($("create-continuous-enabled").checked, false);
  setup.suspend();
  setup.open(one);
  assert.equal($("create-continuous-enabled").checked, true);
  assert.equal($("create-continuous-max-rounds").value, "6");

  const runContinuous = continuousAPI.mount("run");
  runContinuous.update({
    id: "session", topic: "Meeting topic", status: "ready",
    continuous: {status:"paused", config:{goal:"", criteria:"Keep the boundary evidence", max_rounds:8, summary_every:4}},
  });
  assert.equal($("run-continuous-enabled").checked, true);
  $("run-continuous-max-rounds").value = "10";
  $("run-continuous-max-rounds").listeners.input();
  runContinuous.update({
    id: "session", topic: "Meeting topic", status: "ready",
    continuous: {status:"paused", config:{goal:"", criteria:"server refresh", max_rounds:2, summary_every:2}},
  });
  assert.equal($("run-continuous-max-rounds").value, "10", "polling must not replace edited values");
  assert.deepEqual(plain(runContinuous.payload("Meeting topic")), {
    goal: "Meeting topic", criteria: "Keep the boundary evidence", max_rounds: 10, summary_every: 4,
  });

  const choice = {preset:"work", phases:{review:"proposal",prioritize:"proposal",forum:"proposal"}};
  const changeStart = studio.indexOf('  $("run-preset").addEventListener("change"');
  const changeEnd = studio.indexOf('  window.addEventListener("meeting-agenda-updated"', changeStart);
  vm.runInNewContext(studio.slice(changeStart, changeEnd), {
    $, discussionChoice:() => choice, paintDiscussionControls() {},
  });
  for (const mode of ["work", "review", "prioritize", "forum"]) {
    $("run-preset").value = mode;
    $("run-preset").listeners.change();
    assert.equal(choice.preset, mode);
    assert.equal(runContinuous.payload("Meeting topic").max_rounds, 10);
  }

  const sent = [];
  let uploadsInProgress = true, attached = [{id:"material-1", name:"constraint.md"}];
  let rejected = 0, boardReady = false, revealedBoardDrafts = 0;
  const state = {writing:false, selected:"session", session:{id:"session", topic:"Meeting topic", status:"ready", agenda_version:9, rounds:[]}, agendaNote:""};
  const runStart = studio.indexOf("  async function run() {");
  const runEnd = studio.indexOf("  function renderFiles()", runStart);
  const context = {
    $, state, continuousUI:runContinuous, sessionWorking:() => false,
    seatMention:{resolve:() => ({target:"member-2"}), clear:() => { $("run-note").value = ""; }, updateStatus() {}},
    runMaterials: {busy:() => uploadsInProgress, failed:() => false, ready:() => attached, reset:() => { attached = []; }},
    paintTextLimit:() => true, discussionChoice:() => choice, latestRound:() => null,
    board:{flush:async () => boardReady, revealDraft:() => { revealedBoardDrafts++; }},
    sessionPath: suffix => "/sessions/session" + suffix,
    api: async (path, payload) => {
      sent.push({path,payload});
      if (sent.length === 1) throw new Error("connection interrupted");
      return {...state.session, status:"running"};
    },
    stopPoll() {}, updateControls() {}, clearError() {}, updateSession() {}, requestTitle() {},
    schedulePoll() {}, handleSessionError:async () => { rejected++; },
  };
  $("run-note").value = "Continue with this constraint";
  vm.runInNewContext(studio.slice(runStart, runEnd), context);
  await context.run();
  assert.equal(sent.length, 0);
  uploadsInProgress = false;
  await context.run();
  assert.equal(sent.length, 0);
  assert.equal(revealedBoardDrafts, 1);
  assert.equal($("run-note").value, "Continue with this constraint");
  assert.equal(attached.length, 1);
  boardReady = true;
  await context.run();
  assert.equal(sent.length, 1);
  assert.equal(rejected, 1);
  assert.equal($("run-note").value, "Continue with this constraint");
  assert.equal(attached.length, 1);
  await context.run();
  assert.equal(sent.length, 2);
  assert.deepEqual(plain(sent[0]), plain(sent[1]));
  assert.equal($("run-note").value, "");
  assert.equal(attached.length, 0);
  assert.equal(sent[0].path, "/sessions/session/run");
  assert.equal(sent[0].payload.preset, "forum");
  assert.equal("allow_edits" in sent[0].payload, false);
  assert.equal(sent[0].payload.target, "member-2");
  assert.deepEqual(plain(sent[0].payload.material_ids), ["material-1"]);
  assert.deepEqual(plain(sent[0].payload.continuous), {
    goal: "Meeting topic", criteria: "Keep the boundary evidence", max_rounds: 10, summary_every: 4,
  });
  runContinuous.update(null);
  runContinuous.update({
    id: "session", topic: "Meeting topic", status: "ready",
    continuous: {manual:true,status:"completed",config:{max_rounds:8,summary_every:4}},
  });
  assert.equal($("run-continuous-enabled").checked, false);
  assert.match($("run-continuous-status").children[0].textContent, /上次持续推进/);
  runContinuous.update(null);
  runContinuous.update({
    id: "running", topic: "Meeting topic", status: "running",
    continuous: {manual:true,status:"paused",config:{max_rounds:8,summary_every:4}},
  });
  assert.equal($("run-continuous-enabled").disabled, true, "ordinary work in progress locks the configuration");
  runContinuous.update(null);
  runContinuous.update({
    id: "closed", topic: "Meeting topic", status: "closed",
    continuous: {manual:true,status:"completed",config:{max_rounds:8,summary_every:4}},
  });
  assert.equal($("run-continuous-enabled").disabled, true, "closed meetings cannot re-enable continuous mode");
});
