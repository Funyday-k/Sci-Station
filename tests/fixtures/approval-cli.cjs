#!/usr/bin/env node
"use strict";
// A local JSON-RPC peer for the browser smoke test. It only edits the named
// synthetic fixture after its own wire request receives a one-time acceptance.
const assert = require("node:assert/strict");
const {readFileSync, writeFileSync} = require("node:fs");
const path = require("node:path");
const readline = require("node:readline");
const send = packet => process.stdout.write(JSON.stringify(packet) + "\n");
const identity = {threadId:"fixture-thread", turnId:"fixture-turn"};
const allowed = new Set(["declined fixture", "approved fixture", "cancelled fixture", "unanswered fixture"]);
let target = "", prompt = "", changes = [];

readline.createInterface({input:process.stdin}).on("line", line => {
  const msg = JSON.parse(line);
  const reply = result => send({id:msg.id,result});
  const notify = (method,params) => send({method, params:{...identity,...params}});
  switch (msg.method) {
    case "initialize": reply({userAgent:"SciStation-test-only"}); break;
    case "initialized": break;
    case "thread/start":
      assert.equal(msg.params.sandbox,"read-only");
      target = path.join(msg.params.cwd,"measurement.txt");
      reply({thread:{id:identity.threadId},cwd:msg.params.cwd,approvalPolicy:"on-request",
        approvalsReviewer:"user",sandbox:{type:"readOnly",networkAccess:false}});
      break;
    case "mcpServerStatus/list": reply({data:[]}); break;
    case "turn/start": {
      prompt = msg.params.input[0].text.split("\n")[0];
      assert.ok(allowed.has(prompt));
      const old = readFileSync(target,"utf8").trimEnd();
      assert.ok(old === "initial fixture" || old === "approved fixture");
      changes = [{path:"measurement.txt",kind:{type:"update"},diff:"@@ -1 +1 @@\n-"+old+"\n+"+prompt}];
      reply({turn:{id:identity.turnId}});
      notify("item/started",{item:{id:"fixture-file",type:"fileChange",status:"inProgress",changes}});
      send({method:"item/fileChange/requestApproval",id:"wire-approval",
        params:{...identity,itemId:"fixture-file",reason:"Mock CLI proposes a measurement label change"}});
      break;
    }
    default: {
      assert.equal(msg.id,"wire-approval");
      const decision = msg.result.decision;
      assert.ok(decision === "accept" || decision === "decline");
      if (decision === "accept") writeFileSync(target,prompt+"\n");
      notify("item/completed",{item:{id:"fixture-file",type:"fileChange",status:decision==="accept"?"completed":"declined",changes}});
      notify("turn/completed",{turn:{id:identity.turnId,status:"completed"}});
    }
  }
});
