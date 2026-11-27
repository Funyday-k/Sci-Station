const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const read = name => fs.readFileSync(path.join(__dirname, "..", "web", "static", name), "utf8");
const plain = value => JSON.parse(JSON.stringify(value));
const one = { path: "/work/one", name: "one" };
const two = { path: "/work/two", name: "two" };
const studio = read("studio.js");

test("opening a Roundtable source replaces the anchor and keeps the history position", () => {
  const location = new URL("http://127.0.0.1:18675/studio?project=fixture&session=meeting");
  const original = {workspacePosition:7,otherState:"kept"};
  const history = {
    state: original,
    replaceState(state, _, url) {
      this.state = state;
      if (url) location.href = url;
    },
    pushState() { throw Error("source anchor must stay in the current history entry"); }
  };
  const window = {addEventListener(){}};
  const document = {getElementById:()=>null,querySelector:()=>null,addEventListener(){}};
  vm.runInNewContext(read("workspace-nav.js"), {window,document,history,location,URL,URLSearchParams});
  const { $ } = fakeDOM();
  const target = {id:"round-2-codex",isConnected:true,classList:{add(){}},focus(){}};
  let scrolled;
  const start = studio.indexOf("    reveal(target, agenda) {");
  const end = studio.indexOf("\n  });", start);
  const reveal = vm.runInNewContext("({" + studio.slice(start, end) + "}).reveal", {
    $, window, history, location, URL, state:{view:"table"},
    setChatVisible(){}, requestAnimationFrame: callback=>callback(), scrollToMessage: el=>{scrolled=el;}
  });
  reveal(target, false);
  assert.equal(location.hash, "#round-2-codex");
  assert.equal(location.search, "?project=fixture&session=meeting");
  assert.deepEqual(plain(history.state), original);
  assert.equal(scrolled, target);
});

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
  vm.runInNewContext(read("model-effort.js"), { window, document });
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

test("Roundtable defaults to no project and honors only explicit project selections", () => {
  const window = {};
  vm.runInNewContext(read("projects.js"), { window });
  const { resolveSelection } = window.RoundtableProjects;
  assert.equal(resolveSelection([], "/old"), null);
  assert.equal(resolveSelection([one, two], "/old"), null);
  assert.equal(resolveSelection([one], "/old"), null);
  assert.equal(resolveSelection([one, two], two.path), two);
  assert.equal(resolveSelection([one, two], "").global, true);
  assert.equal(resolveSelection([one], "").global, true);
  assert.equal(resolveSelection([one, two], "@global").global, true);
  assert.equal(resolveSelection([], "").global, true);
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

test("the draft seat slider sends the chosen catalog level and resets it when the model changes", async () => {
  const { $, document } = fakeDOM();
  const window = { addEventListener() {}, RoundtableSeating: { mount: () => ({ render() {} }) } };
  continuous(window, document);
  vm.runInNewContext(read("studio-setup.js"), {
    window, document, Option: function(text, value) { this.text = text; this.value = value; },
  });
  const setup = window.RoundtableSetup.mount({
    api: async () => ({
      models: [{id:"first", efforts:["auto", "high", "low"]}, {id:"second", efforts:["auto"]}],
      default_model: "first",
    }),
    assetFor: () => "",
    storageGet: () => "",
    storageSet() {},
  });
  const row = () => $("chosen-members").children[0];
  const slider = () => row().children.find(node => node.className === "effort-field").children[1].children[0];
  setup.open(one);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(slider().type, "range");
  assert.equal(slider().max, "2");
  slider().value = "2";
  slider().listeners.input();
  assert.deepEqual(plain(setup.payload().members), [{model:"first", effort:"high"}]);

  const picker = row().children.find(node => node.className === "chosen-identity").children[0];
  picker.value = "second";
  picker.listeners.change();
  assert.equal(slider().max, "0");
  assert.equal(slider().disabled, true);
  assert.deepEqual(plain(setup.payload().members), [{model:"second", effort:"auto"}]);
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
  assert.equal($("create-project-access").textContent, "此会话无项目文件权限");
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
  const window = {};
  vm.runInNewContext(read("projects.js"), {window});
  vm.runInNewContext(studio.slice(start, end), {
    $, state, window, paintTextLimit: inputLimit(document),
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
    stopPoll() {}, updateControls() {}, clearError() {}, updateSession() {}, requestTitle() {}, clearModeFollowup() {},
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
