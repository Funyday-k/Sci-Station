"use strict";

const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const navigation = require("../static/workspace-nav.js");
const graph = require("../static/research-graph.js");
const source = require("../static/reader-graph-source.js");
const base = "http://127.0.0.1:18765";

const staticFile = name => readFileSync(path.join(__dirname, "../static", name), "utf8");
const sentence = "A <critical> & reproducible result.";
const query = href => new URL(href, base).searchParams;

test("each citation opens the appropriate stable source with its individual locator", () => {
  const edge = {source:"paper-A", target:"paper-B"};
  const reference = graph.occurrenceLink("project-A", edge,
    {source:"metadata", ordinal:2, sourceRevision:5}, navigation.route);
  const paper = {revision:5, references:[sentence, sentence], notes:"Heading\n🔎 Context\n- " + sentence + "\n  Notes\n"};
  assert.equal(query(reference).get("paper"), edge.source);
  assert.equal(query(reference).get("project"), "project-A");
  assert.deepEqual(source.savedCitation(paper, query(reference)), {text:sentence, ordinal:2});
  assert.match(source.savedCitation({...paper, revision:6}, query(reference)).error, /文献已更新/);

  const local = graph.occurrenceLink("project-A", edge,
    {source:"paper-note", ordinal:1, line:3, endLine:4, sourceRevision:5}, navigation.route);
  const anchor = source.savedCitation(paper, query(local));
  assert.equal(paper.notes.slice(anchor.start, anchor.end), "- " + sentence + "\n  Notes");

  const evidence = graph.occurrenceLink("project-A", edge,
    {source:"evidence", page:4, quote:sentence, sourceHash:"digest", status:"matched", start:0, end:sentence.length,
      ocr:true, annotationId:"ann"}, navigation.route);
  assert.deepEqual(Object.fromEntries(query(evidence)), {project:"project-A", paper:"paper-B", page:"4",
    fingerprint:"digest", quote:sentence, start:"0", end:String(sentence.length), ocr:"1", annotation:"ann"});
  const unicodeQuote = "🔎".repeat(2800);
  const longAnchor = graph.occurrenceLink("project-A", edge,
    {source:"evidence", page:4, quote:unicodeQuote, sourceHash:"digest", status:"matched"}, navigation.route);
  assert.equal(query(longAnchor).get("quote"), unicodeQuote);
  assert.equal(graph.occurrenceLink("project-A", edge, {source:"evidence", status:"missing"}, navigation.route), "");
  const meeting = graph.occurrenceLink("project-A", edge,
    {source:"meeting", meetingId:"abc", turnId:"round-2-codex"}, navigation.route);
  assert.equal(new URL(meeting, base).hash, "#round-2-codex");
});

test("graph search encodes scoped node IDs and honors zero depth", () => {
  const url = graph.queryPath("/projects/a/graph", {focus:"reference:10.1000/a+b?c", target:"", depth:0, kind:"cites"});
  assert.deepEqual(Object.fromEntries(query(url)), {focus:"reference:10.1000/a+b?c", depth:"0", kind:"cites"});
});

function mount() {
  const projects = [{id:"A",name:"Solar"}, {id:"B",name:"Lensing"}];
  const a = {nodes:[{id:"note-A",kind:"note",label:"Solar note"}, {id:"note-A2",kind:"note",label:"Methods"}],
    edges:[{source:"note-A",target:"note-A2",kind:"wikilink",
      occurrences:[{id:"occurrence",source:"wikilink",ordinal:2,line:4,column:3,sourceRevision:6,quote:"[[Methods]]"}]}]};
  const b = {nodes:[{id:"note-B",kind:"note",label:"Lensing note"}], edges:[]};
  const entries = new Map([
    ["/api/research/projects", projects], ["/api/research/papers", []], ["/api/studio/sessions", {sessions:[]}],
    ["/api/research/papers/organization", {revision:0, collections:{}, tags:{}}],
    ["/api/research/projects/A/graph", a], ["/api/research/projects/B/graph", b]
  ]);
  for (const p of projects) {
    for (const area of ["notes", "tasks", "materials"]) entries.set("/api/research/projects/" + p.id + "/" + area, []);
  }
  const elements = {}, listeners = {}, calls = [];
  for (const match of staticFile("research.html").matchAll(/\bid="([^"]+)"/g)) {
    elements[match[1]] = {classList:{remove(){}},setAttribute(){},addEventListener(){},replaceChildren(){}};
  }
  const document = {getElementById:id=>elements[id],querySelectorAll:()=>[],addEventListener:(event,cb)=>{listeners[event]=cb;}};
  const location = {href:base + "/research?project=A&view=graph", origin:base};
  const history = {replaceState:(_s,_t,url)=>{location.href=new URL(url,base).href;}};
  const window = {addEventListener(){},RoundtableIcons:{icon:()=>""},SciStationNav:{...navigation,update(){}},SciResearchGraph:graph};
  let resolveQuery, rejectQuery;
  const fetch = async url => {
    calls.push(url);
    if (url.startsWith("/api/research/projects/A/graph?")) {
      return new Promise((resolve, reject) => {resolveQuery = resolve; rejectQuery = reject;});
    }
    assert.ok(entries.has(url), url);
    return Response.json(entries.get(url));
  };
  class FormData {
    constructor(form) {this.fields = form?.fields || {};}
    [Symbol.iterator]() {return Object.entries(this.fields)[Symbol.iterator]();}
  }
  const sandbox = vm.createContext({window,document,location,history,fetch,URL,URLSearchParams,FormData,setTimeout,clearTimeout,
    localStorage:{getItem:()=>null}});
  for (const script of ["research.js", "research-forms.js", "research-library.js"]) {
    vm.runInContext(staticFile(script), sandbox);
  }
  return {ui:window.SciResearch,elements,calls,listeners,resolveQuery:data=>resolveQuery(Response.json(data)),
    rejectQuery:error=>rejectQuery(error)};
}

const tick = () => new Promise(resolve => setImmediate(resolve));

test("research graph exposes real occurrence navigation and discards an old project's lookup", async () => {
  const {ui,elements,listeners,calls,resolveQuery} = mount();
  await tick();
  assert.match(elements.main.innerHTML, /Solar note/);
  assert.match(elements.main.innerHTML, /第 4 行/);
  let opened;
  ui.openWikiNote = (...args) => {opened=args;};
  await listeners.click({target:{closest:()=>({dataset:{action:"graph-occurrence",id:"occurrence"},hasAttribute:()=>false})}});
  assert.equal(opened[0], "note-A");
  assert.deepEqual({...opened[1]}, {line:4,column:3,revision:6,text:"[[Methods]]"});
  listeners.submit({preventDefault(){},target:{id:"graph-query",fields:{focus:"note-A",target:"",depth:"1",kind:"wikilink"}}});
  assert.equal(calls.at(-1), "/api/research/projects/A/graph?focus=note-A&depth=1&kind=wikilink");
  await ui.load("B", "graph");
  resolveQuery({nodes:[{id:"late",label:"Old project response"}], edges:[]});
  await tick();
  assert.match(elements.main.innerHTML, /Lensing note/);
  assert.doesNotMatch(elements.main.innerHTML, /Old project response/);
});

test("project graph lookup failure exposes a retry and retains current source entries", async () => {
  const {ui,elements,listeners,rejectQuery} = mount();
  await tick();
  listeners.submit({preventDefault(){},target:{id:"graph-query",fields:{focus:"note-A",target:"",depth:"1"}}});
  rejectQuery(new Error("读取图谱失败"));
  await tick();
  assert.match(elements.main.innerHTML, /读取图谱失败/);
  assert.match(elements.main.innerHTML, /重新生成/);
  assert.match(elements.main.innerHTML, /Solar note/);
  assert.equal(ui.state.graphPending,false);
});
