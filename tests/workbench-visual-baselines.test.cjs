"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const baselines = require("./workbench-visual-baselines-smoke.cjs");

test("visual baseline plan covers all 6 screens, both window sizes, zh/en, light/dark, and Home color themes", () => {
  const plan = baselines.buildCapturePlan();
  const screens = new Set(plan.map(entry => entry.screen));
  assert.deepEqual(
    [...screens].sort(),
    ["home", "project-overview", "reader", "roundtable-room", "settings-storage", "single-chat"]
  );

  const viewports = new Set(plan.map(entry => entry.viewport));
  assert.deepEqual([...viewports].sort(), ["1380x900", "900x620"]);

  // 6 screens x 2 viewports x 2 locales x 2 themes (iris) = 48
  // + 3 additional color themes (teal, amber, blue) on Home only x 2 viewports x 2 locales x 2 themes = 24
  assert.equal(plan.length, 72);

  // Verify all 16 combinations of zh/en x light/dark x 4 color themes exist on Home for both viewports.
  for (const viewport of ["1380x900", "900x620"]) {
    const homeCombos = new Set(
      plan
        .filter(entry => entry.screen === "home" && entry.viewport === viewport)
        .map(entry => `${entry.locale}:${entry.theme}:${entry.colorTheme}`)
    );
    assert.equal(homeCombos.size, 16);
  }

  // Non-Home screens run only the default color theme.
  const nonHomeThemes = new Set(
    plan.filter(entry => entry.screen !== "home").map(entry => entry.colorTheme)
  );
  assert.deepEqual([...nonHomeThemes], ["iris"]);

  // Every filename in the plan is unique.
  assert.equal(new Set(plan.map(entry => entry.file)).size, plan.length);
});

test("visual baseline output directory defaults to .tmp/visual-baselines and honors SCI_STATION_*_SCREENSHOT hooks", () => {
  const repoRoot = "/tmp/fake-repo";
  assert.equal(
    baselines.resolveOutputDir(undefined, {}, repoRoot),
    path.join(repoRoot, ".tmp", "visual-baselines")
  );
  assert.equal(
    baselines.resolveOutputDir(undefined, {SCI_STATION_SMOKE_SCREENSHOTS: "/tmp/custom-shots"}, repoRoot),
    path.resolve("/tmp/custom-shots")
  );
  assert.equal(
    baselines.resolveOutputDir(undefined, {SCI_STATION_VISUAL_BASELINES_SCREENSHOTS: "/tmp/vb"}, repoRoot),
    path.resolve("/tmp/vb")
  );
  assert.equal(
    baselines.resolveOutputDir(undefined, {SCI_STATION_SMOKE_SCREENSHOT: "/tmp/one/shot.png"}, repoRoot),
    path.resolve("/tmp/one")
  );
  assert.equal(
    baselines.resolveOutputDir("/tmp/explicit", {SCI_STATION_SMOKE_SCREENSHOTS: "/tmp/ignored"}, repoRoot),
    path.resolve("/tmp/explicit")
  );
});

test("Reader geometry rejects a reverted layout and requires a full measured row of visible PDF height", () => {
  const configuration = {window: [1380, 900], inspectorOpen: false, contextRailOpen: false};
  const before = {configuration, visibleViewportHeight: 610, headerRowHeight: 54.5};
  const after = {...before, visibleViewportHeight: 664.5};
  assert.doesNotThrow(() => baselines.assertReaderHeightGain(before, after));
  assert.throws(() => baselines.assertReaderHeightGain(before, before), /Reader gained 0px/);
  assert.throws(() => baselines.assertReaderHeightGain(before, {...after, visibleViewportHeight: 664}), /expected at least/);
  assert.throws(() => baselines.assertReaderHeightGain(before, {...after, configuration: {...configuration, inspectorOpen: true}}), /settings changed/);
});

test("only current capture plans exercise the post-redesign workspace containers", () => {
  const plan = baselines.buildCapturePlan();
  const reader = plan.find(step => step.screen === "reader" && step.viewport === "1380x900" &&
    step.locale === "zh" && step.theme === "light" && step.colorTheme === "iris");
  assert.equal(baselines.checksWorkspaceLayout(reader, "historical"), false);
  assert.equal(baselines.checksWorkspaceLayout(reader, "current"), true);
  assert.equal(baselines.checksWorkspaceLayout(reader), true);
  assert.equal(plan.filter(step => baselines.checksWorkspaceLayout(step, "current")).length, 8);
});
