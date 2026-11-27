"use strict";

// Exercise the same no-argument startup as Finder with an isolated macOS home.
const assert = require("node:assert/strict");
const {spawn} = require("node:child_process");
const {once} = require("node:events");
const {mkdir, mkdtemp, readFile, realpath, rename, rm, stat, writeFile} = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const {setTimeout: delay} = require("node:timers/promises");
const {buildNativeFixture, webkitDriver, eventually} = require("./workstation-workflow-smoke.cjs");

async function main() {
  assert.equal(process.platform, "darwin");
  assert.ok(process.argv[2], "Pass the built workstation .app");
  const bundle = await realpath(process.argv[2]);
  const base = await realpath(await mkdtemp(path.join(os.tmpdir(), "sci-storage-window-")));
  try {
    const binary = await buildNativeFixture(bundle, base);
    const home = path.join(base, "home");
    const registry = path.join(home, "Library", "Application Support", "Sci-Station Workstation");
    const defaultDir = path.join(registry, "Data");
    const recent = path.join(registry, "last-workspace.json");
    const custom = path.join(base, "custom");
    await mkdir(home);
    await mkdir(custom);

    async function start(label, run) {
      const mailbox = path.join(base, label);
      const driver = await webkitDriver(mailbox);
      const child = spawn(binary, [], {stdio: ["ignore", "ignore", "inherit"], env: {
        HOME: home, CFFIXED_USER_HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"),
        TMPDIR: base + "/", PATH: "/usr/bin:/bin", LANG: "en_US.UTF-8",
        SCI_STATION_WORKFLOW_DRIVER_DIR: mailbox, SCI_STATION_WORKFLOW_SECOND_ROOT: custom
      }});
      const exited = once(child, "exit");
      try {
        await run(driver);
        await driver.quit();
        const exit = await Promise.race([exited, delay(15000, null, {ref: false})]);
        assert.deepEqual(exit, [0, null], "desktop quit " + label);
      } finally {
        if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
        await exited;
      }
    }
    async function settings(driver, data) {
      assert.equal(await driver.native({windowTitle: true}), data === defaultDir ? "Sci-Station" : "Sci-Station · " + path.basename(data));
      const url = await driver.ui.evaluate(() => location.origin);
      await driver.ui.navigate(url + "/studio?view=settings");
      await driver.ui.click("#settings-tab-storage");
      assert.deepEqual(await driver.ui.evaluate(() => ({
        data: document.querySelector("#storage-data-path").textContent,
        library: document.querySelector("#storage-library-path").textContent,
        defaultPath: document.querySelector("#storage-default-path").textContent,
        atDefault: document.querySelector("#storage-use-default").disabled
      })), {data, library: path.join(data, "research", "library"), defaultPath: defaultDir, atDefault: data === defaultDir});
      return url;
    }
    async function homeRoute(driver) {
      await eventually(() => driver.ui.evaluate(() => location.pathname === "/research"), "project home on startup");
    }
    async function recovery(driver) {
      await eventually(() => driver.ui.evaluate(() => location.pathname === "/welcome" &&
        !!document.querySelector('[role="alert"]')?.textContent &&
        !!document.querySelector('[data-setup="default-storage"]')?.textContent), "workspace recovery");
      const borderColors = [];
      for (const mode of ["light", "dark"]) {
        const styles = await driver.ui.evaluate(mode => {
          window.RoundtableAppearance.setMode(mode);
          const root = getComputedStyle(document.documentElement);
          const button = getComputedStyle(document.querySelector('[data-setup="default-storage"]'));
          return {
            scheme: root.colorScheme,
            heading: getComputedStyle(document.querySelector(".root-welcome h1")).fontSize,
            radius: button.borderTopLeftRadius,
            tokenRadius: root.getPropertyValue("--radius-sm").trim(),
            border: [button.borderTopStyle, button.borderTopWidth],
            borderColor: button.borderTopColor,
          };
        }, mode);
        assert.equal(styles.scheme, mode);
        assert.equal(styles.heading, "24px");
        assert.ok(parseFloat(styles.tokenRadius) > 0);
        assert.equal(styles.radius, styles.tokenRadius);
        assert.deepEqual(styles.border, ["solid", "1px"]);
        borderColors.push(styles.borderColor);
      }
      assert.notEqual(borderColors[0], borderColors[1], "the chooser border follows the active palette");
    }
    async function switched(driver, previousOrigin) {
      await eventually(() => driver.ui.evaluate(previous =>
        location.origin !== previous && location.pathname === "/research", previousOrigin), "changed data folder");
    }
    await start("first-launch", async driver => {
      await homeRoute(driver);
      const original = await settings(driver, defaultDir);
      assert.equal(JSON.parse(await readFile(recent)).path, defaultDir);
      assert.ok((await stat(path.join(defaultDir, ".sci-station-desktop"))).isFile());
      // The release code handles the real WK click and macOS picker completion.
      await driver.native({armSecondRoot: true});
      await driver.ui.click("#storage-choose");
      await switched(driver, original);
      assert.equal(JSON.parse(await readFile(recent)).path, custom);
      assert.ok((await stat(path.join(custom, ".sci-station-desktop"))).isFile());
    });
    console.log("PASS first desktop launch used Application Support; Settings selected an empty custom folder.");
    await start("remember-custom", async driver => {
      await homeRoute(driver);
      await settings(driver, custom);
      await driver.ui.click("#storage-use-default");
      await eventually(() => driver.native({confirmDefaultLocation: true}), "confirm default location in native sheet");
      await eventually(async () => JSON.parse(await readFile(recent)).path === defaultDir, "default selection saved");
    });
    console.log("PASS custom selection survived restart and Settings reopened the default data folder.");

    // A historical string entry names a preexisting marked directory. It has
    // never been opened in this installation and still uses its original ID.
    const legacy = path.join(base, "previous-library");
    await mkdir(legacy);
    await writeFile(path.join(legacy, ".sci-station-desktop"), "sci-station desktop workspace v1\n");
    await writeFile(recent, JSON.stringify(legacy));
    await start("legacy", async driver => {
      await homeRoute(driver);
      await settings(driver, legacy);
      assert.equal(JSON.parse(await readFile(recent)).path, legacy);
    });
    const saved = await readFile(recent, "utf8");
    await rename(legacy, legacy + "-offline");
    await start("missing", recovery);
    assert.equal(await readFile(recent, "utf8"), saved);
    await assert.rejects(stat(legacy), {code: "ENOENT"});
    await writeFile(recent, "damaged fixture");
    await start("damaged", recovery);
    assert.equal(await readFile(recent, "utf8"), "damaged fixture");
    console.log("PASS legacy data reopened; missing data and a damaged recent record retained their recovery information.");
  } finally {
    await rm(base, {recursive: true, force: true});
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
