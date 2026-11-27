"use strict";

// Run from the source checkout corresponding to the given app bundle. The
// shared WK driver links this source into a separate, disposable native copy.
// node tests/workstation-workbench-smoke.cjs /path/to/Sci-Station.app /tmp/evidence [baseline|--short-display]
const assert = require("node:assert/strict");
const {mkdir, mkdtemp, realpath, rm, writeFile} = require("node:fs/promises");
const {tmpdir} = require("node:os");
const path = require("node:path");
const {buildNativeFixture, webkitDriver, listen, closeServer, fixtureHome,
  launch, eventually, localGateway, sourcePDF} = require("./workstation-workflow-smoke.cjs");

const title = "Solar capture with orbital precession and velocity-dependent dark-matter scattering";
const projectName = "Solar capture and orbital transport across long-baseline numerical ensembles";
const otherName = "Gamma-ray response for atmospheric Cherenkov telescope observations";
const taskName = "Check the low-velocity interpolation against the published solar model";
const reasoningModel = "fixture/first";
const automaticModel = "fixture/second";
const reasoningLevels = ["low", "medium", "high"];
const routes = {
  home: '[data-workspace-nav] [data-section="home"]',
  library: '[data-workspace-nav] [data-section="library"]',
  lab: '[data-workspace-nav] [data-section="lab"]',
  settings: '[data-workspace-settings] [data-section="settings"]'
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
  const gateway = await localGateway({reasoningLevels:{[reasoningModel]:reasoningLevels}});
  const mailbox = path.join(base, "driver");
  const dataDir = path.join(base, "workspace");
  try {
    const spec = path.join(base, "Fixture.app", "Contents", "Resources", "sci-station.agent.js");
    await mkdir(path.dirname(spec), {recursive:true});
    await writeFile(spec, "// Local model catalog fixture.\n");
    const env = await fixtureHome(base, gateway.port, spec);
    const binary = await buildNativeFixture(source, base);
    const probe = await listen();
    const port = probe.address().port;
    await closeServer(probe);
    const browser = await webkitDriver(mailbox);
    const app = await launch(binary, port, dataDir, {
      ...env, TMPDIR:base + "/", SCI_STATION_WORKFLOW_DRIVER_DIR:mailbox
    }, "app", browser.quit, {PATH:"/usr/bin:/bin:/opt/homebrew/bin", LANG:"en_US.UTF-8", NO_PROXY:"127.0.0.1,localhost"});
    return {browser, app, gateway, dataDir, defaultDir:path.join(env.SCI_STATION_WORKSPACE_REGISTRY, "Data")};
  } catch (error) {
    await closeServer(gateway.server);
    throw error;
  }
}

async function run({app, browser, gateway, dataDir, defaultDir}, output, {baseline, wideHeight}) {
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
  const navigate = async section => {
    const selector = routes[section];
    if (!await visible("#workspace-sidebar")) await ui.click("#workspace-nav-toggle");
    await ui.evaluate(selector => document.querySelector(selector).scrollIntoView({block:"nearest"}), selector);
    await wait(() => visible(selector), "visible " + section + " navigation");
    await ui.click(selector);
  };
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

  async function checkDashboard(label, widgetIDs, withCalendar = false) {
    const layout = await ui.evaluate(ids => {
      const measure = element => {
        const rect = element?.getBoundingClientRect();
        return rect && {left:rect.left, right:rect.right, top:rect.top, bottom:rect.bottom, height:rect.height};
      };
      const widget = id => {
        const node = document.querySelector(`[data-dashboard-widget="${id}"]`);
        const rect = measure(node?.querySelector(":scope > .panel"));
        return rect && {...rect, compact: node?.dataset.compactEmpty === "true"};
      };
      const compactAI = document.querySelector('[data-dashboard-widget="ai_review"][data-compact-empty="true"] > .panel');
      return {
        cards: ids.map(widget),
        calendar: widget("calendar"),
        compactAI: compactAI ? measure(compactAI) : null,
        summary: measure(document.querySelector(".dashboard-overview-summary [data-dashboard-widget='project_status'] > .panel")),
        quickAdd: measure(document.querySelector(".dashboard-quick-add")),
        grid: measure(document.querySelector(".dashboard-grid"))
      };
    }, widgetIDs);
    const {cards, calendar, compactAI, summary, quickAdd, grid} = layout;
    if (summary) {
      check(label + " summary strip sits above primary work area and Quick add", Boolean(summary && (!grid || summary.bottom <= grid.top + 1) &&
        (!quickAdd || summary.bottom <= quickAdd.top + 1)), layout);
    } else {
      const aligned = cards.every((box, index) => box && Math.abs(box.top - cards[0].top) <= 1 &&
        (box.compact || Math.abs(box.bottom - cards[0].bottom) <= 1) && (index === 0 || box.left > cards[index - 1].right));
      check(label + " cards share top edges and full cards share bottom edges", aligned, layout);
    }
    if (compactAI) {
      check(label + " empty AI Review renders as a compact status row", compactAI.height <= 56, compactAI);
    }
    if (withCalendar) {
      check(label + " calendar spans the dashboard width", calendar && grid &&
        Math.abs(calendar.left - grid.left) <= 1 && Math.abs(calendar.right - grid.right) <= 1, {calendar,grid});
    }
  }

  async function checkDashboardPreferences() {
    const button = action => `[data-dashboard-control="${action}"]`;
    const onWidget = (id, action) => `[data-dashboard-option="${id}"] ${button(action)}`;
    const calendar = '[data-dashboard-widget="calendar"]';
    const first = '.dashboard-grid > :first-child';
    await ui.click(button("edit"));
    await ui.click(onWidget("active_projects", "up"));
    await ui.set(onWidget("calendar", "size"), "small");
    await ui.click(button("edit"));
    await open("/research");
    await loaded();
    await ui.visible("#dashboard-view");
    const saved = await ui.evaluate(([calendar,first]) => ({
      small:document.querySelector(calendar)?.classList.contains("dashboard-small"),
      first:document.querySelector(first)?.dataset.dashboardWidget
    }), [calendar,first]);
    check("Home keeps widget size and order after reopening", saved.small && saved.first === "active_projects", saved);
    await ui.click(button("edit"));
    await ui.click(button("reset"));
    await ui.click(button("edit"));
  }

  const globalSidebar = "#workspace-sidebar";
  const historySidebar = "#workspace-session-sidebar";
  const globalToggle = "#workspace-nav-toggle";
  const historyToggle = "#workspace-session-toggle";
  async function checkAIShell(mode, compact, content) {
    const view = compact ? "Compact" : "Wide";
    const controls = [globalToggle,historyToggle,...(mode === "roundtable" ? ["#room-chat-toggle","#meeting-actions-toggle"] : [])];
    const result = await ui.evaluate(([content,controls]) => {
      const bar = document.querySelector(".workspace-bar"), modes = document.querySelector("#workspace-ai-modes");
      const rect = selector => {
        const node = typeof selector === "string" ? document.querySelector(selector) : selector;
        const bounds = node?.getBoundingClientRect();
        return bounds && {x:bounds.x,y:bounds.y,right:bounds.right,bottom:bounds.bottom};
      };
      return {bar:rect(bar), modes:rect(modes), workspace:rect(".workspace-region"), global:rect("#workspace-sidebar"),
        history:rect("#workspace-session-sidebar"),
        active:modes?.querySelector('[aria-current="page"]')?.dataset.aiMode,
        distinct:Boolean(document.querySelector("#workspace-sidebar [data-workspace-nav]") &&
          document.querySelector("#workspace-session-sidebar " + content) &&
          !document.querySelector("#workspace-sidebar " + content)),
        controls:controls.map(selector =>
          bar?.contains(document.querySelector(selector)) ? rect(selector) : null),
        stacked:Boolean(document.querySelector(".workspace-region .lab-conversation-heading")?.getClientRects().length),
        horizontalOverflow:document.documentElement.scrollWidth > innerWidth};
    }, [content,controls]);
    const {bar, modes, workspace, global, history} = result;
    const withinBar = box => box && box.right > box.x && box.y >= bar.y - 1 && box.bottom <= bar.bottom + 1;
    check(`${view} ${mode} shows one AI toolbar`, result.active === mode && !result.horizontalOverflow && !result.stacked &&
      withinBar(modes) && result.controls.every(withinBar) && Math.abs(workspace.y - bar.bottom) <= 1 &&
      Math.abs((modes.x + modes.right) / 2 - (bar.x + bar.right) / 2) <= 2, result);
    if (compact) {
      check(`${view} ${mode} separates global and conversation navigation`, result.distinct, result);
      return;
    }
    const defaultSidebarWidth = (global.right - global.x) + (history.right - history.x);
    check(`${view} ${mode} shows one sidebar by default (<= 260px)`,
      result.distinct && global.right > global.x && history.right === history.x &&
      defaultSidebarWidth <= 260 && Math.abs(global.right - workspace.x) <= 1,
      {defaultSidebarWidth, ...result});
    await ui.click(historyToggle);
    await wait(() => visible(historySidebar), `${view} ${mode} session sidebar opens`);
    const opened = await ui.evaluate(() => {
      const rect = s => { const b = document.querySelector(s)?.getBoundingClientRect(); return b && {x:b.x,right:b.right}; };
      return {global:rect("#workspace-sidebar"), history:rect("#workspace-session-sidebar"), workspace:rect(".workspace-region")};
    });
    check(`${view} ${mode} separates global and conversation navigation when expanded`,
      opened.global.right > opened.global.x && opened.history.right > opened.history.x &&
      Math.abs(opened.global.right - opened.history.x) <= 1 &&
      Math.abs(opened.history.right - opened.workspace.x) <= 1, opened);
    await ui.click(historyToggle);
    await wait(() => ui.evaluate(() => document.getElementById("workspace-session-sidebar")?.hidden), `${view} ${mode} session sidebar collapses`);
  }

  async function checkNewChat(label) {
    const layout = await ui.evaluate(() => {
      const bounds = selector => {
        const r = document.querySelector(selector)?.getBoundingClientRect();
        return r && {left:r.left, right:r.right, top:r.top, bottom:r.bottom, height:r.height};
      };
      return {pane:bounds("#lab-workspace"), heading:bounds("#lab-empty h1"), composer:bounds("#lab-composer"),
        mode:document.getElementById("lab-workspace")?.dataset.labState, start:bounds("#lab-start"),
        optionalProject:Boolean(document.querySelector('#project option[value="@global"]'))};
    });
    const {pane, heading, composer, start} = layout;
    check(label + " empty chat centers the title and composer", layout.mode === "new" && pane && heading && composer &&
      start && heading.bottom <= composer.top + 1 &&
      Math.abs((composer.left + composer.right) / 2 - (pane.left + pane.right) / 2) <= 3 &&
      Math.abs((heading.top + composer.bottom) / 2 - (pane.top + pane.bottom) / 2) <= pane.height * 0.12 &&
      start.bottom <= pane.bottom && composer.left >= pane.left && composer.right <= pane.right, layout);
    check(label + " empty chat offers optional project, files, plugins and model actions", layout.optionalProject &&
      await reachable("#project") && await reachable("#lab-attach") && await reachable("#lab-tools") &&
      await reachable("#lab-model-trigger"));
  }

  async function checkCompactDrawers() {
    await ui.click(historyToggle);
    await wait(() => visible(historySidebar), "compact conversation drawer opens");
    check("Compact AI opens its conversation navigation independently", !await visible(globalSidebar));
    await snapshot("10d-lab-conversation-drawer-compact");
    await ui.click(globalToggle);
    await wait(() => visible(globalSidebar), "compact workspace drawer opens");
    check("Compact AI shows only one open navigation drawer", !await visible(historySidebar));
    await ui.evaluate(() => document.dispatchEvent(new KeyboardEvent("keydown", {key:"Escape",bubbles:true,cancelable:true})));
    await wait(() => ui.evaluate(() => document.activeElement?.id === "workspace-nav-toggle"), "closing the compact drawer restores focus");
  }

  async function reachable(selector) {
    return ui.evaluate(selector => {
      const control = document.querySelector(selector), box = control?.getBoundingClientRect();
      return Boolean(box?.width && box.height && control.contains(document.elementFromPoint(
        (box.left + box.right) / 2, (box.top + box.bottom) / 2)));
    }, selector);
  }

  async function checkReasoning() {
    const trigger = "#lab-model-trigger", picker = "#lab-model-dialog", model = "#lab-model", effort = "#lab-effort";
    const catalog = await app.request("/api/studio/models");
    const choose = async id => {
      await ui.click(trigger);
      await ui.visible(`${picker}[open] ${model}`);
      await wait(() => ui.evaluate(([selector,id]) => Array.from(document.querySelector(selector).options).some(option => option.value === id),
        [model,id]), "local model appears in the chooser");
      await ui.set(model,id);
      await ui.click(`${picker} [data-lab-close]`);
      await wait(() => ui.evaluate(selector => !document.querySelector(selector).open,picker), "model chooser closes");
    };
    const state = () => ui.evaluate(selector => {
      const input = document.querySelector(selector);
      return {type:input.type, min:Number(input.min), max:Number(input.max), value:Number(input.value),
        label:input.getAttribute("aria-valuetext"), disabled:input.disabled, drawn:input.getClientRects().length > 0,
        announces:document.getElementById("lab-effort-value")?.textContent.trim()};
    }, effort);
    const triggerReachable = await reachable(trigger);
    await choose(reasoningModel);
    const available = catalog.models.find(item => item.id === reasoningModel).efforts;
    const multiple = await state();
    const sliderReachable = await reachable(effort);
    await ui.set(effort,String(available.length - 1));
    const selected = await state();
    check("Model chooser and capability-based reasoning slider are reachable", triggerReachable && sliderReachable &&
      multiple.drawn && multiple.type === "range" && !multiple.disabled && multiple.min === 0 && multiple.max === available.length - 1 &&
      selected.value === available.length - 1 && selected.label && selected.label !== multiple.label &&
      selected.announces === selected.label, {multiple,selected,available});
    await snapshot("10h-lab-model-effort-wide");
    await choose(automaticModel);
    const automatic = await state();
    check("Changing to an automatic-only model removes adjustable reasoning levels", automatic.value === 0 &&
      automatic.max === 0 && (automatic.disabled || !automatic.drawn) && automatic.label !== selected.label, automatic);
    await choose(reasoningModel);
    const changedBack = await state();
    check("Changing back to a multi-level model re-enables its slider", changedBack.max === available.length - 1 &&
      !changedBack.disabled && changedBack.drawn && await reachable(effort), changedBack);
  }

  async function checkToolsRoundTrip() {
    const draft = "Keep this unsent question when opening a research tool.";
    await ui.set("#question",draft);
    const tools = "#lab-tools-dialog", discovery = '[data-lab-tool="discovery"]', graph = '[data-lab-tool="graph"]';
    const clickTarget = await reachable("#lab-tools");
    await ui.click("#lab-tools");
    await ui.visible(`${tools}[open] #lab-tools-directory ${discovery}`);
    const entries = await ui.evaluate(() => Array.from(document.querySelectorAll("#lab-tools-directory [data-lab-tool]"),
      row => row.dataset.labTool));
    check("Plugins opens a browsable research tools list", clickTarget && entries.includes("discovery") && entries.includes("graph") &&
      new Set(entries).size === entries.length, entries);
    await snapshot("10i-lab-tool-directory-wide");
    await ui.click(graph);
    await ui.visible("#lab-tool-page-graph");
    await snapshot("10i2-lab-tool-graph-wide");
    const backReachable = await reachable("#lab-tool-back");
    await ui.click("#lab-tool-back");
    await ui.visible(`#lab-tools-directory ${graph}`);
    check("Tool detail has a reachable in-dialog return to the list", backReachable && await ui.evaluate(selector =>
      document.activeElement === document.querySelector(selector), graph));
    await ui.click(discovery);
    await wait(() => ui.evaluate(() => location.pathname === "/tools"), "open the Research Tools page directly");
    await ui.visible("#discovery-return-lab");
    await ui.click("#discovery-return-lab");
    await wait(() => ui.evaluate(() => location.pathname === "/lab"), "return to Lab from Research Tools");
    await ui.visible(`${tools}[open] #lab-tools-directory`);
    const restored = await ui.evaluate(() => ({project:new URL(location.href).searchParams.get("project"),
      draft:document.getElementById("question").value}));
    check("Returning from Research Tools restores the project, unsent question and tool catalog", restored.project === project.id &&
      restored.draft === draft, restored);
    await ui.click(`${tools} > header [data-lab-close]`);
    await ui.set("#question", "");
  }

  async function checkSettings() {
    const from = await ui.evaluate(() => location.pathname + location.search);
    await navigate("settings");
    await ui.visible("#workspace-settings-nav .settings-nav");
    await ui.click("#settings-tab-storage");
    await ui.visible("#settings-panel-storage");
    await ui.visible("#storage-data-path", dataDir);
    const settings = await ui.evaluate(() => {
      const drawn = selector => Boolean(document.querySelector(selector)?.getClientRects().length);
      return {global:drawn("#workspace-sidebar [data-workspace-nav]"), projects:drawn("#projectnav"), history:drawn("#workspace-session-sidebar"),
        folder:document.getElementById("storage-data-path")?.textContent.trim(),
        library:document.getElementById("storage-library-path")?.textContent.trim(),
        defaultPath:document.getElementById("storage-default-path")?.textContent.trim(),
        useDefault:!document.getElementById("storage-use-default")?.disabled,
        categories:Array.from(document.querySelectorAll("#workspace-settings-nav [data-settings-page]"), item => item.dataset.settingsPage),
        footer:drawn("[data-workspace-settings] [data-section='settings']"), back:drawn("#workspace-settings-back")};
    });
    check("Settings sidebar contains only settings categories and a return action", !settings.global && !settings.projects && !settings.history &&
      !settings.footer && settings.back && settings.categories.includes("appearance") && settings.categories.includes("storage"),settings);
    check("Data Location reports the isolated data and library paths and offers directory choices", settings.folder === dataDir &&
      settings.library === path.join(dataDir,"research","library") && settings.defaultPath === defaultDir &&
      settings.useDefault && await reachable("#storage-choose") && await reachable("#storage-use-default"),settings);
    await snapshot("10j-settings-storage-wide");
    await ui.click("#workspace-settings-back");
    await wait(() => ui.evaluate(path => location.pathname + location.search === path,from),"Settings returns to its originating screen");
    await ui.visible("#question");
    check("Settings returns to the originating project and chat", true, {from});
  }

  try {
    await resize(1440, wideHeight);
    await navigate("home");
    await loaded();
    await ui.visible("#dashboard-view");
    await snapshot("01-home-wide");
    if (!baseline) {
      const footer = await ui.evaluate(() => {
        const drawn = selector => Array.from(document.querySelectorAll(selector)).filter(node => node.getClientRects().length);
        const entries = drawn("[data-workspace-settings] :is(a,summary,button)");
        return {entries:entries.map(node => node.dataset.section || node.localName),
          inPrimaryFooter:Boolean(entries[0]?.closest("#workspace-sidebar .workspace-sidebar-footer")),
          workspace:drawn(".workspace-roots, [data-section='workspace']").length};
      });
      check("The ordinary workspace footer offers only Settings", footer.entries.length === 1 && footer.entries[0] === "settings" &&
        footer.inPrimaryFooter && footer.workspace === 0, footer);
      await checkDashboard("Wide Home", ["today","active_projects","ai_review"], true);
      await checkDashboardPreferences();
    }
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

    await navigate("library");
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
    const libraryWidth = await ui.evaluate(() => document.querySelector(".workspace-region").getBoundingClientRect().width);
    await ui.click('[data-library-selection="' + paper.id + '"]');
    const selectionLayout = await ui.evaluate(() => ({mode:document.body.dataset.railMode,
      width:document.querySelector(".workspace-region").getBoundingClientRect().width,
      selected:document.querySelector("[data-library-selection]:checked")?.dataset.librarySelection}));
    check("Selecting a paper preserves the Library layout", selectionLayout.mode === "hidden" &&
      selectionLayout.width === libraryWidth && selectionLayout.selected === paper.id, selectionLayout);
    const paperDetails = '[data-inspect-object="paper"][data-id="' + paper.id + '"]';
    check("Paper details have a visible row action", await visible(paperDetails));
    await ui.click(paperDetails);
    await wait(() => visible(rail), "explicit paper details open the inspector");
    await ui.visible("#rail-context", title);
    check("Explicit paper details show the selected object", await visible(rail));
    await snapshot("05-library-paper-detail-wide");
    await ui.click("#rail-close");
    const closedDetails = await ui.evaluate(selector => ({mode:document.body.dataset.railMode,
      focused:document.activeElement === document.querySelector(selector),
      width:document.querySelector(".workspace-region").getBoundingClientRect().width}), paperDetails);
    check("Closing paper details restores focus and content width", closedDetails.mode === "hidden" &&
      closedDetails.focused && closedDetails.width === libraryWidth, closedDetails);

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
    const navigation = await ui.evaluate(project => ({
      shared:document.querySelectorAll("[data-workspace-nav]").length === 1 &&
        Boolean(document.querySelector("#workspace-sidebar [data-workspace-nav]")),
      modules:document.querySelector("#project-modules")?.parentElement.querySelector("[data-project]")?.dataset.project,
      current:document.querySelector('#project-modules [data-tab-key="overview"]')?.getAttribute("aria-current"),
      nested:Boolean(document.querySelector("#workspace-context #project-modules")),
      headerModules:Boolean(document.querySelector(".workspace-bar #project-modules, #workarea #project-modules")),
      oldInspector:Boolean(document.querySelector("#shell-inspect")),project
    }), project.id);
    check("Project modules form secondary navigation in the shared sidebar", await visible(tree) &&
      navigation.shared && navigation.nested && navigation.modules === project.id && navigation.current === "page" &&
      !navigation.headerModules && !navigation.oldInspector, navigation);
    await snapshot("06-project-wide");
    if (!baseline) await checkDashboard("Wide project Overview", ["project_status","research_questions","project_brief"]);
    await resize(900, 620);
    await snapshot("07-project-compact-closed");
    if (!baseline) await checkDashboard("Compact project Overview", ["project_status","research_questions"]);
    const compactWidth = await ui.evaluate(() => document.querySelector("#workarea").getBoundingClientRect().width);
    await ui.click("#workspace-nav-toggle");
    const otherLink = '#projectnav [data-project="' + other.id + '"]';
    await ui.evaluate(selector => document.querySelector(selector).scrollIntoView({block:"nearest"}), otherLink);
    const opens = await wait(() => visible(otherLink), "compact switcher exposes the other project", 2200)
      .catch(() => false);
    const compactNavigation = await ui.evaluate(() => ({
      expanded:document.querySelector("#workspace-nav-toggle").getAttribute("aria-expanded"),
      width:document.querySelector("#workarea").getBoundingClientRect().width,
      overlay:document.body.classList.contains("workspace-nav-open")
    }));
    check("Compact project navigator opens over the workbench", opens && compactNavigation.overlay &&
      compactNavigation.expanded === "true" && compactNavigation.width === compactWidth, compactNavigation);
    await snapshot("08-project-compact-open");
    if (opens) {
      await ui.click(otherLink);
      await wait(() => ui.evaluate(id => new URL(location.href).searchParams.get("project") === id, other.id), "switch projects");
      await loaded();
      check("Choosing a compact project dismisses its navigator", !await visible(tree));
      await snapshot("09-project-compact-after-switch");
      await ui.click("#workspace-nav-toggle");
      await wait(() => visible(tree), "reopen compact navigator");
      if (baseline && await visible(".workspace-roots summary")) {
        await ui.click(".workspace-roots summary");
        await ui.evaluate(() => document.dispatchEvent(new KeyboardEvent("keydown", {key:"Escape",bubbles:true,cancelable:true})));
        check("Escape closes the workspace menu before its compact navigator", await visible("#workspace-sidebar") &&
          await ui.evaluate(() => !document.querySelector(".workspace-roots").open &&
            document.activeElement === document.querySelector(".workspace-roots summary")));
      }
      await ui.evaluate(() => document.dispatchEvent(new KeyboardEvent("keydown", {key:"Escape",bubbles:true,cancelable:true})));
      check("Escape dismisses the compact navigator and restores focus", !await visible(tree) &&
        await ui.evaluate(() => document.activeElement?.id === "workspace-nav-toggle"));
    }
    if (!baseline) {
      await navigate("home");
      await loaded();
      await ui.visible("#dashboard-view");
      await checkDashboard("Compact Home", ["today","active_projects"], true);
      await snapshot("09b-home-compact");
    }
    await navigate("library");
    await ui.visible(".library-paper-title", title);
    check("Compact global navigation opens the unscoped Library and closes", !await visible("#workspace-sidebar") &&
      await ui.evaluate(() => !new URL(location.href).searchParams.has("project")));
    check("Import remains visible in compact Library", await visible(importAction));
    await snapshot("10-library-compact");

    const meeting = await app.request("/api/studio/sessions", "POST", {
      topic:"Compare the solar interpolation with the published model", project_id:project.id,
      ...(baseline ? {seats:["codex"]} : {
        members:[{model:reasoningModel},{model:automaticModel}], preset:"work", start_agenda_draft:true
      })
    }, 201);
    if (!baseline) {
      await wait(async () => (await app.request("/api/studio/sessions/" + meeting.id)).board?.state === "published",
        "published two-seat Roundtable fixture");
    }
    await open("/studio?session=" + meeting.id);
    await ui.visible("#meeting-actions-toggle");
    if (!baseline) {
      await ui.visible("#room-chat-toggle");
      await checkAIShell("roundtable", true, "#studio-session-sidebar");
    }
    await ui.click("#shell-assist");
    await ui.visible("#rail-prompt");
    // The WK click helper bypasses hit testing. Check that the session toolbar
    // behind the overlay cannot intercept a real click on its close control.
    const closeTarget = await ui.evaluate(() => {
      const close = document.getElementById("rail-close");
      const {x,y,width,height} = close.getBoundingClientRect();
      const target = document.elementFromPoint(x + width/2, y + height/2);
      return {reachable:close.contains(target), hit:target?.closest("button")?.id || target?.localName};
    });
    check("Compact Roundtable overlay close control is reachable by pointer", closeTarget.reachable, closeTarget);
    await snapshot("10b-roundtable-ai-overlay-compact");
    await ui.click("#rail-close");
    await wait(() => ui.evaluate(() => document.getElementById("context-rail").hidden), "Roundtable overlay closes");
    check("Closing the Roundtable overlay restores focus", await ui.evaluate(() => document.activeElement?.id === "shell-assist"));

    if (!baseline) {
      const chat = "/lab?project=" + project.id;
      await open(chat);
      await ui.visible("#question");
      await checkAIShell("single", true, "#lab-history");
      await checkNewChat("Compact");
      await snapshot("10c-lab-empty-compact");
      await checkCompactDrawers();
      await resize(1440, wideHeight);
      await open("/studio?session=" + meeting.id);
      await ui.visible("#meeting-actions-toggle");
      await ui.visible("#room-chat-toggle");
      await checkAIShell("roundtable", false, "#studio-session-sidebar");
      await snapshot("10e-roundtable-two-nav-wide");
      await open("/studio?project=" + project.id);
      await ui.visible("#new-topic");
      const roundtable = await ui.evaluate(() => {
        const scroll = document.getElementById("setup-scroll");
        const pane = scroll.getBoundingClientRect();
        const composer = document.querySelector("#create-composer .composer-surface").getBoundingClientRect();
        return {paneCenter:pane.left + scroll.clientLeft + scroll.clientWidth / 2, composerCenter:(composer.left + composer.right) / 2,
          optionalProject:Array.from(document.getElementById("create-project").options).some(option => option.value === "@global")};
      });
      check("Roundtable setup centers its composer and exposes project, file and plugin controls", roundtable.optionalProject &&
        Math.abs(roundtable.paneCenter - roundtable.composerCenter) <= 3 && await reachable("#create-project") &&
        await reachable("#create-attach") && await reachable("#create-plugins"), roundtable);
      await snapshot("10f-roundtable-new-wide");
      await open(chat);
      await ui.visible("#question");
      await checkAIShell("single", false, "#lab-history");
      await checkNewChat("Wide");
      await snapshot("10g-lab-empty-wide");
      await checkReasoning();
      await checkToolsRoundTrip();
      await checkSettings();
      assert.deepEqual(gateway.errors, []);
      const modelCalls = gateway.calls.map(call => call.kind);
      check("Navigation, tool browsing and model selection submit no conversation messages", !modelCalls.includes("statement"), modelCalls);
    }

    async function appearance(mode, size, color) {
      await navigate("settings");
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
      if (baseline) await navigate("lab");
      else await ui.click("#workspace-settings-back");
      await ui.visible("#question");
      await wait(() => ui.evaluate(() => !document.getElementById("lab-start").disabled), "Lab composer ready");
    }
    const lab = () => ui.evaluate(() => {
      const root = document.documentElement;
      const computed = id => getComputedStyle(document.querySelector(id));
      return {theme:root.dataset.theme,size:root.dataset.textSize,colorTheme:root.dataset.colorTheme,
        rootBackground:getComputedStyle(root).backgroundColor, cardBackground:computed(".lab-composer").backgroundColor,
        questionSize:parseFloat(computed("#question").fontSize), buttonColor:computed("#lab-start").backgroundColor};
    });
    await resize(1440, wideHeight);
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
  assert.ok(bundle && destination && [undefined, "baseline", "--short-display"].includes(mode),
    "Pass a signed app bundle, an evidence directory and optionally baseline or --short-display");
  const options = {baseline:mode === "baseline", wideHeight:mode === "--short-display" ? 620 : 900};
  const output = path.resolve(destination);
  await mkdir(output, {recursive:true});
  const base = await realpath(await mkdtemp(path.join(tmpdir(), "sci-workbench-ui-")));
  try {
    const session = await fixture(await realpath(bundle), base);
    try { await run(session, output, options); }
    finally {
      try { await session.app.close(); }
      finally { await closeServer(session.gateway.server); }
    }
  } finally {
    await rm(base, {recursive:true,force:true});
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
