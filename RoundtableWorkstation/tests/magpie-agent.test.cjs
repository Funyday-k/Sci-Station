const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

test("the bundled Magpie adapter writes only its loopback address", async () => {
  const source = readFileSync(path.join(__dirname, "../packaging/magpie/sci-station.agent.js"));
  const { connect } = await import("data:text/javascript;base64," + source.toString("base64"));
  const gateway = { v1: "http://127.0.0.1:3425/v1", key: "magpie-sci-station" };
  assert.deepEqual(connect({ gateway }), { baseURL: gateway.v1 });
  assert.throws(() => connect({ gateway: { ...gateway, key: "private-fixture" } }));
  assert.throws(() => connect({ gateway: { ...gateway, v1: "https://example.invalid/v1" } }));
});
