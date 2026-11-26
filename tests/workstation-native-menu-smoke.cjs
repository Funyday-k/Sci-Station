"use strict";

// Pass a built workstation .app. Only the re-signed test copy contains the
// driver. The native picker callback supplies the second disposable root.
const assert = require("node:assert/strict");
const {mkdtemp, mkdir, writeFile, realpath, rm} = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const {
  buildNativeFixture, webkitDriver, fixtureHome, listen, closeServer, localGateway, launch, eventually
} = require("./workstation-workflow-smoke.cjs");

async function main() {
  assert.equal(process.platform, "darwin");
  assert.ok(process.argv[2], "Pass the built workstation .app");
  const bundle = await realpath(process.argv[2]);
  const base = await realpath(await mkdtemp(path.join(os.tmpdir(), "sci-menu-window-")));
  let app, gateway;
  try {
    const executable = await buildNativeFixture(bundle, base);
    gateway = await localGateway();
    const spec = path.join(base, "Fixture.app", "Contents", "Resources", "sci-station.agent.js");
    await mkdir(path.dirname(spec), {recursive: true});
    await writeFile(spec, "// Registration fixture.\n");

    const second = path.join(base, "second");
    await mkdir(second);
    await writeFile(path.join(second, ".sci-station-desktop"), "sci-station desktop workspace v1\n");
    const environment = await fixtureHome(base, gateway.port, spec);
    const mailbox = path.join(base, "driver");
    const browser = await webkitDriver(mailbox);
    const available = await listen();
    const port = available.address().port;
    await closeServer(available);
    app = await launch(executable, port, path.join(base, "first"), {
      ...environment, SCI_STATION_WORKFLOW_DRIVER_DIR: mailbox, SCI_STATION_WORKFLOW_SECOND_ROOT: second
    }, "app", browser.quit);

    const ui = browser.ui;
    const proofs = () => ui.evaluate(() => ({
      cli: typeof window.sciStationCLIEditSession === "string",
      credential: typeof window.sciStationCredentialSession === "string"
    }));
    const hasBoth = async () => {
      const presence = await proofs();
      return presence.cli && presence.credential;
    };
    await ui.navigate(app.origin + "/studio");
    await eventually(hasBoth, "both scoped capabilities");
    assert.ok(await browser.native({captureProof: true}));
    assert.ok(await browser.native({homeMenu: true}));
    await eventually(() => ui.evaluate(() => location.pathname === "/research"), "native Home menu navigation");
    assert.deepEqual(await proofs(), {cli: false, credential: false});
    console.log("PASS native Command-1 reached Research. Both capabilities were present in Studio and absent on Home.");

    assert.ok(await browser.native({openSecondRoot: true}));
    const next = await eventually(async () => {
      const current = await ui.evaluate(() => location.origin);
      return current !== app.origin && current.startsWith("http://127.0.0.1:") && current;
    }, "native Open Workspace on the second fixture root", 15000);
    await ui.navigate(next + "/studio");
    await eventually(hasBoth, "new root capabilities");
    assert.equal(await browser.native({checkOldProof: true}), 403);
    console.log("PASS native Command-O switched roots. The new Studio acquired the capabilities and rejected the old CLI proof with HTTP 403.");
  } finally {
    try {
      if (app) await app.close();
    } finally {
      try {
        if (gateway) await closeServer(gateway.server);
      } finally {
        await rm(base, {recursive: true, force: true});
      }
    }
  }
}

main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
