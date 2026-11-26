"use strict";

// Run from the source checkout corresponding to the given app bundle. The
// shared WK driver links this source into a separate, disposable native copy.
// node tests/workstation-workbench-smoke.cjs /path/to/Sci-Station.app /tmp/evidence [baseline]
const assert = require("node:assert/strict");
const {mkdir, mkdtemp, realpath, rm, writeFile} = require("node:fs/promises");
const {tmpdir} = require("node:os");
const path = require("node:path");
const {buildNativeFixture, webkitDriver, listen, closeServer,
  launch, eventually, sourcePDF} = require("./workstation-workflow-smoke.cjs");

const title = "Solar capture with orbital precession and velocity-dependent dark-matter scattering";
const projectName = "Solar capture and orbital transport across long-baseline numerical ensembles";
const otherName = "Gamma-ray response for atmospheric Cherenkov telescope observations";
const taskName = "Check the low-velocity interpolation against the published solar model";
const routes = {
  home: '[data-workspace-nav] [data-section="home"]',
  library: '[data-workspace-nav] [data-section="library"]',
  lab: '[data-workspace-nav] [data-section="lab"]',
  settings: '[data-workspace-nav] [data-section="settings"]'
};

async function seed(app) {
  const project = await app.request("/api/research/projects", "POST", {name:projectName}, 201);
  const other = await app.request("/api/research/projects", "POST", {name:otherName}, 201);
  const attach = async (paperTitle, authors, entry, index) => {
    const form = new FormData();
    form.append("metadata", JSON.stringify({title:paperTitle, authors, year:2025, project_ids:[entry.id]}));
    const pdf = sourcePDF().toString("latin1").replace("First page", "Paper 000" + index);
    form.append("file", new Blob([Buffer.from(pdf,"latin1")], {type:"application/pdf"}), "example.pdf");
    return app.request("/api/research/papers", "POST", form, 201);
  };
  const paper = await attach(title, ["A. Chen", "M. Patel"], project, 1);
  await attach("Solar capture benchmarks in the optically thin regime", ["L. Rivera"], project, 2);
  await attach("A reproducible calibration study of imaging air Cherenkov telescopes", ["D. Kim"], other, 3);
  const now = new Date();
  const date = [now.getFullYear(), now.getMonth() + 1, now.getDate()]
    .map(value => String(value).padStart(2, "0")).join("-");
  await app.request("/api/research/projects/" + project.id + "/tasks", "POST", {
    title:taskName, dueDate:date, dueTime:"14:30"
  }, 201);
  return {project, other, paper};
}

async function fixture(source, base) {
  const home = path.join(base, "home");
  const config = path.join(home, ".config");
  const mailbox = path.join(base, "driver");
  await mkdir(config, {recursive:true, mode:0o700});
  const binary = await buildNativeFixture(source, base);
  const probe = await listen();
  const port = probe.address().port;
  await closeServer(probe);
  const browser = await webkitDriver(mailbox);
  const app = await launch(binary, port, path.join(base, "workspace"), {
    HOME:home, XDG_CONFIG_HOME:config, TMPDIR:base + "/",
    SCI_STATION_WORKSPACE_REGISTRY:path.join(base, "roots"), SCI_STATION_WORKFLOW_DRIVER_DIR:mailbox
  }, "app", browser.quit, {PATH:"/usr/bin:/bin:/opt/homebrew/bin", LANG:"en_US.UTF-8", NO_PROXY:"127.0.0.1,localhost"});
  return {browser, app};
}

async function run(app, browser, output, baseline) {
  const {ui} = browser;
  const {project, other, paper} = await seed(app);
  const report = [];
  const snapshot = file => ui.screenshot(path.join(output, file + ".png"));
  const wait = (check, label, timeout = 8000) => eventually(check, label, timeout);
  const loaded = () => ui.visible('#main[aria-busy="false"]');
  const visible = selector => ui.evaluate(selector => {
    const el = document.querySelector(selector);
    const r = el?.getBoundingClientRect();
    return Boolean(r?.width && r.height && r.left >= 0 && r.right <= innerWidth && r.bottom > 0 && r.top < innerHeight);
  }, selector);
  const resize = async (width, height) => {
    const display = await browser.native({viewport:{width,height}});
    const viewport = () => ui.evaluate(() => ({width:innerWidth,height:innerHeight,state:document.visibilityState}));
    report.push({requested:[width,height], ...display, measured:await viewport()});
    await wait(async () => {
      const measured = await viewport();
      report.at(-1).measured = measured;
      return measured.width === width && measured.height === height && measured.state === "visible";
    }, `foreground WKWebView at ${width}×${height}`);
  };
  function check(expectation, passed, detail) {
    report.push({expectation, passed:Boolean(passed), detail});
    console.log((passed ? "PASS " : "GAP ") + expectation);
  }
  const open = async url => { await ui.navigate(new URL(url, app.origin).href); };

  try {
    await resize(1440, 900);
    await ui.click(routes.home);
    await loaded();
    await ui.visible("#dashboard-view");
    await snapshot("01-home-wide");
    const calendar = '#dashboard-view .dashboard-calendar-links a[href*="view=tasks"]';
    await ui.visible(calendar);
    await ui.evaluate(selector => document.querySelector(selector).scrollIntoView({block:"center"}), calendar);
    await snapshot("01b-home-calendar-action-wide");
    await ui.click(calendar);
    await wait(() => ui.evaluate(() => new URL(location.href).searchParams.get("view") === "tasks"), "Home’s task action opens Tasks");
    await loaded();
    const taskView = await ui.evaluate(name => ({url:location.pathname + location.search,
      calendar:Boolean(document.querySelector(".calendar-head")), hasTask:document.querySelector("#main").innerText.includes(name)}), taskName);
    check("Home opens the task calendar directly", taskView.calendar && taskView.hasTask, taskView);
    await snapshot("02-task-calendar-wide");

    await ui.click(routes.library);
    await ui.visible(".library-paper-title", title);
    const importAction = '[data-action="new-paper"].primary';
    const rail = "#context-rail";
    const libraryLayout = {importVisible:await visible(importAction), inspectorVisible:await visible(rail),
      reservedWidth:await ui.evaluate(() => parseFloat(getComputedStyle(document.querySelector(".workspace-region")).marginRight))};
    check("Library has visible primary Import and no default empty inspector", libraryLayout.importVisible &&
      !libraryLayout.inspectorVisible && libraryLayout.reservedWidth === 0, libraryLayout);
    await snapshot("03-library-default-wide");
    await ui.click(importAction);
    await ui.visible("#modal[open]");
    check("Visible Import opens its own dialog", await ui.evaluate(() => /导入|import/i.test(document.querySelector("#dialog-title").textContent)));
    await snapshot("04-library-import-wide");
    await ui.click("#modal-close");
    await ui.click('[data-library-selection="' + paper.id + '"]');
    if (baseline && !await visible(rail)) await ui.click("#shell-inspect");
    await wait(() => visible(rail), "selected paper shows the inspector");
    await ui.visible("#rail-context", title);
    check("Selected paper has visible object details", await visible(rail));
    await snapshot("05-library-paper-detail-wide");

    await ui.set("#paper-query", "Solar caure");
    const edit = await ui.evaluate(() => {
      const query = document.querySelector("#paper-query");
      query.focus();
      query.setSelectionRange(8, 8);
      const inserted = document.execCommand("insertText", false, "pt");
      const active = document.querySelector("#paper-query");
      return {inserted,value:active.value,start:active.selectionStart,end:active.selectionEnd,
        focused:document.activeElement === active};
    });
    check("Mid-query typing keeps the Library insertion point", edit.inserted && edit.focused &&
      edit.value === "Solar capture" && edit.start === 10 && edit.end === 10, edit);
    const replace = await ui.evaluate(() => {
      const query = document.querySelector("#paper-query");
      query.focus();
      query.setSelectionRange(6, 10);
      const inserted = document.execCommand("insertText", false, "cap");
      const active = document.querySelector("#paper-query");
      return {inserted,value:active.value,start:active.selectionStart,end:active.selectionEnd,
        focused:document.activeElement === active};
    });
    check("Replacing selected query text keeps focus and the expected insertion point", replace.inserted && replace.focused &&
      replace.value === "Solar capure" && replace.start === 9 && replace.end === 9, replace);

    await open("/research?project=" + project.id);
    await loaded();
    await ui.visible("#project-modules");
    const tree = "#projectnav";
    check("Wide project tree switches projects and modules live in the header", await visible(tree) &&
      await ui.evaluate(() => Boolean(document.querySelector('#project-modules [data-tab-key="papers"]')) &&
        !document.querySelector("#projectnav .shell-project-children a")));
    await snapshot("06-project-wide");
    await resize(900, 620);
    await snapshot("07-project-compact-closed");
    await ui.click("#nav-toggle");
    const otherLink = '#projectnav [data-project="' + other.id + '"]';
    const opens = await wait(() => visible(otherLink), "compact switcher exposes the other project", 2200)
      .catch(() => false);
    check("Compact project navigator opens over the workbench", opens);
    await snapshot("08-project-compact-open");
    if (opens) {
      await ui.click(otherLink);
      await wait(() => ui.evaluate(id => new URL(location.href).searchParams.get("project") === id, other.id), "switch projects");
      await loaded();
      check("Choosing a compact project dismisses its navigator", !await visible(tree));
      await snapshot("09-project-compact-after-switch");
      await ui.click("#nav-toggle");
      await wait(() => visible(tree), "reopen compact navigator");
      await ui.evaluate(() => document.dispatchEvent(new KeyboardEvent("keydown", {key:"Escape",bubbles:true})));
      check("Escape dismisses the compact project navigator", !await visible(tree));
    }
    await open("/research?view=papers");
    await ui.visible(".library-paper-title", title);
    check("Import remains visible in compact Library", await visible(importAction));
    await snapshot("10-library-compact");

    async function appearance(mode, size, color) {
      await ui.click(routes.settings);
      await ui.click("#settings-tab-appearance");
      await wait(() => ui.evaluate(() => Boolean(document.getElementById("setting-max-children").value)), "settings loaded");
      await ui.evaluate(([mode, size]) => {
        for (const [id, value] of [["setting-appearance", mode], ["setting-text-size", size]]) {
          const control = document.getElementById(id);
          control.value = value;
          control.dispatchEvent(new Event("input", {bubbles:true}));
          control.dispatchEvent(new Event("change", {bubbles:true}));
        }
      }, [mode, size]);
      await ui.click(`label.theme-choice:has(input[value="${color}"])`);
      await ui.click("#save-settings-appearance");
      await wait(async () => {
        const stored = await app.request("/api/studio/settings");
        return stored.appearance === mode && stored.text_size === size && stored.color_theme === color;
      }, "appearance stored");
      await ui.click(routes.lab);
      await ui.visible("#question");
      await wait(() => ui.evaluate(() => Boolean(document.querySelector("#presets button"))), "Lab presets loaded");
    }
    const lab = () => ui.evaluate(() => {
      const root = document.documentElement;
      const computed = id => getComputedStyle(document.querySelector(id));
      return {theme:root.dataset.theme,size:root.dataset.textSize,colorTheme:root.dataset.colorTheme,
        rootBackground:getComputedStyle(root).backgroundColor, cardBackground:computed(".card").backgroundColor,
        questionSize:parseFloat(computed("#question").fontSize), buttonColor:computed("#lab-start").backgroundColor};
    });
    await resize(1440, 900);
    await appearance("light", "standard", "iris");
    const standard = await lab();
    await snapshot("11-lab-light-wide");
    await appearance("dark", "extra-large", "blue");
    const manual = await lab();
    check("AI Lab renders the selected dark, XL and blue appearance", manual.theme === "dark" &&
      manual.size === "extra-large" && manual.colorTheme === "blue" && manual.questionSize > standard.questionSize &&
      manual.cardBackground !== standard.cardBackground && manual.buttonColor !== standard.buttonColor, {standard,manual});
    await snapshot("12-lab-dark-xl-blue-wide");
    await resize(900, 620);
    await snapshot("13-lab-dark-xl-blue-compact");
  } finally {
    await writeFile(path.join(output,"checks.json"), JSON.stringify(report,null,2) + "\n");
  }
  if (!baseline) assert.ok(report.every(entry => entry.passed !== false), "See the acceptance gaps in checks.json");
}

async function main() {
  assert.equal(process.platform, "darwin");
  const [bundle, destination, mode] = process.argv.slice(2);
  assert.ok(bundle && destination && (mode === undefined || mode === "baseline"), "Pass a signed app bundle and an evidence directory");
  const output = path.resolve(destination);
  await mkdir(output, {recursive:true});
  const base = await realpath(await mkdtemp(path.join(tmpdir(), "sci-workbench-ui-")));
  try {
    const {app, browser} = await fixture(await realpath(bundle), base);
    try { await run(app, browser, output, mode === "baseline"); }
    finally { await app.close(); }
  } finally {
    await rm(base, {recursive:true,force:true});
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
