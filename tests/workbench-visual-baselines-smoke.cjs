"use strict";

// Capture visual baseline screenshots for key Sci-Station workbench screens.
//
// Usage:
//   node tests/workbench-visual-baselines-smoke.cjs <sci-station-binary> [output-dir] [pre-redesign-binary]
//
// Output defaults to .tmp/visual-baselines (or SCI_STATION_VISUAL_BASELINES_SCREENSHOTS /
// SCI_STATION_SMOKE_SCREENSHOTS / SCI_STATION_SHELL_SCREENSHOTS / SCI_STATION_LAB_SCREENSHOTS).
// Uses Playwright when available, or falls back to Chrome DevTools Protocol over Node's
// built-in WebSocket with Chrome/Chromium (override path via SCI_STATION_SMOKE_CHROME).
const assert = require("node:assert/strict");
const {spawn} = require("node:child_process");
const {once} = require("node:events");
const {existsSync} = require("node:fs");
const {mkdir, mkdtemp, realpath, rm, writeFile} = require("node:fs/promises");
const http = require("node:http");
const {tmpdir} = require("node:os");
const path = require("node:path");
const {setTimeout: delay} = require("node:timers/promises");
const {
  listen,
  closeServer,
  localGateway,
  fixtureHome,
  launch,
  eventually,
  sourcePDF,
} = require("./workstation-workflow-smoke.cjs");

const REPO_ROOT = path.resolve(__dirname, "..");

const VIEWPORTS = Object.freeze([
  Object.freeze({name: "1380x900", width: 1380, height: 900}),
  Object.freeze({name: "900x620", width: 900, height: 620}),
]);

const LOCALES = Object.freeze([
  Object.freeze({name: "zh", apiValue: "zh-Hans", browserLocale: "zh-CN"}),
  Object.freeze({name: "en", apiValue: "en", browserLocale: "en-US"}),
]);

const THEMES = Object.freeze(["light", "dark"]);
const COLOR_THEMES = Object.freeze(["iris", "teal", "amber", "blue"]);
const DEFAULT_COLOR_THEME = "iris";

const SCREENS = Object.freeze([
  Object.freeze({id: "home", label: "Home"}),
  Object.freeze({id: "project-overview", label: "Project overview"}),
  Object.freeze({id: "single-chat", label: "Single chat (empty)"}),
  Object.freeze({id: "roundtable-room", label: "Roundtable room"}),
  Object.freeze({id: "reader", label: "Reader with fixture paper"}),
  Object.freeze({id: "settings-storage", label: "Settings -> storage"}),
]);

const CHROME_CANDIDATES = Object.freeze([
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  "/usr/bin/google-chrome",
  "/usr/bin/google-chrome-stable",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
]);

function resolveOutputDir(argOutput, env = process.env, repoRoot = REPO_ROOT) {
  if (argOutput) return path.resolve(argOutput);
  for (const key of [
    "SCI_STATION_VISUAL_BASELINES_SCREENSHOTS",
    "SCI_STATION_SMOKE_SCREENSHOTS",
    "SCI_STATION_SHELL_SCREENSHOTS",
    "SCI_STATION_LAB_SCREENSHOTS",
  ]) {
    if (env[key]) return path.resolve(env[key]);
  }
  if (env.SCI_STATION_SMOKE_SCREENSHOT) {
    return path.dirname(path.resolve(env.SCI_STATION_SMOKE_SCREENSHOT));
  }
  return path.join(repoRoot, ".tmp", "visual-baselines");
}

function buildCapturePlan() {
  const plan = [];
  for (const viewport of VIEWPORTS) {
    for (const locale of LOCALES) {
      for (const theme of THEMES) {
        for (const screen of SCREENS) {
          plan.push({
            screen: screen.id,
            label: screen.label,
            viewport: viewport.name,
            width: viewport.width,
            height: viewport.height,
            locale: locale.name,
            apiLocale: locale.apiValue,
            theme,
            colorTheme: DEFAULT_COLOR_THEME,
            file: `${screen.id}__${viewport.name}__${locale.name}__${theme}__${DEFAULT_COLOR_THEME}.png`,
          });
        }
        for (const colorTheme of COLOR_THEMES) {
          if (colorTheme === DEFAULT_COLOR_THEME) continue;
          plan.push({
            screen: "home",
            label: "Home",
            viewport: viewport.name,
            width: viewport.width,
            height: viewport.height,
            locale: locale.name,
            apiLocale: locale.apiValue,
            theme,
            colorTheme,
            file: `home__${viewport.name}__${locale.name}__${theme}__${colorTheme}.png`,
          });
        }
      }
    }
  }
  return plan;
}

function resolveChromeBinary(env = process.env) {
  if (env.SCI_STATION_SMOKE_CHROME) return env.SCI_STATION_SMOKE_CHROME;
  for (const candidate of CHROME_CANDIDATES) {
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

function tryLoadPlaywright() {
  try {
    return require("playwright");
  } catch (_) {
    try {
      return require("playwright/test");
    } catch (_) {
      return null;
    }
  }
}

function httpGetJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, res => {
      const chunks = [];
      res.on("data", chunk => chunks.push(chunk));
      res.on("end", () => {
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
        } catch (error) {
          reject(error);
        }
      });
    }).on("error", reject);
  });
}

async function openCdpSession(baseDir) {
  const chromePath = resolveChromeBinary();
  if (!chromePath) {
    throw new Error(
      "Could not find Chrome/Chromium and Playwright is not installed. " +
      "Set SCI_STATION_SMOKE_CHROME to a Chromium/Chrome executable or install Playwright."
    );
  }
  const profileDir = path.join(baseDir, "chrome-profile");
  await mkdir(profileDir, {recursive: true});
  const child = spawn(
    chromePath,
    [
      "--headless=new",
      "--disable-gpu",
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--hide-scrollbars",
      "--mute-audio",
      "--remote-debugging-port=0",
      "--user-data-dir=" + profileDir,
      "about:blank",
    ],
    {stdio: ["ignore", "pipe", "pipe"]}
  );
  const closed = once(child, "close");
  closed.catch(() => {});
  async function stopChrome(requestClose) {
    const terminate = setTimeout(() => child.kill("SIGTERM"), 2000).unref();
    const force = setTimeout(() => child.kill("SIGKILL"), 5000).unref();
    try {
      if (child.exitCode === null && child.signalCode === null) {
        try {
          if (requestClose) requestClose();
          else child.kill("SIGTERM");
        } catch {
          child.kill("SIGTERM");
        }
      }
      await closed;
    } finally {
      clearTimeout(terminate);
      clearTimeout(force);
    }
  }
  try {
    return await connectCdpSession(child, stopChrome);
  } catch (error) {
    await stopChrome().catch(() => {});
    throw error;
  }
}

async function connectCdpSession(child, stopChrome) {
  let stderr = "";
  let debugPort = null;
  child.stderr.on("data", chunk => {
    stderr += chunk.toString("utf8");
    const match = stderr.match(/DevTools listening on ws:\/\/127\.0\.0\.1:(\d+)\//);
    if (match) debugPort = Number(match[1]);
  });
  await eventually(() => debugPort !== null || child.exitCode !== null, "Chrome DevTools port", 15000);
  if (debugPort === null) {
    throw new Error("Chrome exited before opening DevTools:\n" + stderr);
  }

  let target;
  await eventually(async () => {
    try {
      const targets = await httpGetJson(`http://127.0.0.1:${debugPort}/json/list`);
      target = targets.find(item => item.type === "page" && item.webSocketDebuggerUrl);
      return Boolean(target);
    } catch (_) {
      return false;
    }
  }, "Chrome page target", 15000);

  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    ws.addEventListener("open", () => resolve(), {once: true});
    ws.addEventListener("error", error => reject(error), {once: true});
  });

  let nextId = 1;
  const pending = new Map();
  const pageErrors = [];
  ws.addEventListener("message", event => {
    const message = JSON.parse(String(event.data));
    if (message.id && pending.has(message.id)) {
      const {resolve, reject} = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message || JSON.stringify(message.error)));
      else resolve(message.result);
      return;
    }
    if (message.method === "Runtime.exceptionThrown") {
      const details = message.params?.exceptionDetails;
      const text = details?.exception?.description || details?.text || "Uncaught page exception";
      pageErrors.push(text);
    }
  });

  function send(method, params = {}) {
    const id = nextId++;
    return new Promise((resolve, reject) => {
      pending.set(id, {resolve, reject});
      ws.send(JSON.stringify({id, method, params}));
    });
  }

  await send("Page.enable");
  await send("Runtime.enable");

  return {
    errors: pageErrors,
    async setViewport(width, height) {
      await send("Emulation.setDeviceMetricsOverride", {
        width,
        height,
        deviceScaleFactor: 1,
        mobile: false,
      });
    },
    async emulateColorScheme(scheme) {
      await send("Emulation.setEmulatedMedia", {
        features: [{name: "prefers-color-scheme", value: scheme}],
      });
    },
    async goto(url) {
      const loaded = new Promise(resolve => {
        const handler = event => {
          const message = JSON.parse(String(event.data));
          if (message.method === "Page.loadEventFired") {
            ws.removeEventListener("message", handler);
            resolve();
          }
        };
        ws.addEventListener("message", handler);
      });
      await send("Page.navigate", {url});
      await Promise.race([loaded, delay(10000)]);
    },
    async evaluate(fn, arg) {
      const expression = `(${fn.toString()})(${JSON.stringify(arg)})`;
      const result = await send("Runtime.evaluate", {
        expression,
        awaitPromise: true,
        returnByValue: true,
      });
      if (result.exceptionDetails) {
        throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
      }
      return result.result?.value;
    },
    async screenshot(filePath) {
      const {data} = await send("Page.captureScreenshot", {format: "png"});
      await writeFile(filePath, Buffer.from(data, "base64"));
    },
    async close() {
      try {
        await stopChrome(() => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({id:nextId++, method:"Browser.close"}));
          } else {
            child.kill("SIGTERM");
          }
        });
      } finally {
        ws.close();
      }
    },
  };
}

async function openPlaywrightSession(playwright, origin) {
  const browser = await playwright.chromium.launch({
    headless: true,
    executablePath: process.env.SCI_STATION_SMOKE_CHROME,
  });
  const page = await browser.newPage({locale: "zh-CN", viewport: {width: 1380, height: 900}});
  await page.route("**/*", route =>
    new URL(route.request().url()).origin === origin ? route.continue() : route.abort()
  );
  const pageErrors = [];
  page.on("pageerror", error => pageErrors.push(error.message));
  return {
    errors: pageErrors,
    async setViewport(width, height) {
      await page.setViewportSize({width, height});
    },
    async emulateColorScheme(scheme) {
      await page.emulateMedia({colorScheme: scheme});
    },
    async goto(url) {
      await page.goto(url, {waitUntil: "domcontentloaded"});
    },
    async evaluate(fn, arg) {
      return page.evaluate(fn, arg);
    },
    async screenshot(filePath) {
      await page.screenshot({path: filePath});
    },
    async close() {
      await browser.close();
    },
  };
}

async function seedSyntheticFixtures(host) {
  const api = host.request;
  const project = await api("/api/research/projects", "POST", {
    name: "Synthetic Visual Baseline Project",
    description: "Synthetic fixture project for repeatable visual baseline screenshots.",
  }, 201);
  await api("/api/research/projects", "POST", {
    name: "Synthetic Companion Project",
    description: "Secondary synthetic project for navigation sidebar density.",
  }, 201);

  const upload = new FormData();
  upload.append(
    "metadata",
    JSON.stringify({
      title: "Synthetic Visual Baseline Paper",
      authors: ["Fixture Author A", "Fixture Author B"],
      year: 2026,
      project_ids: [project.id],
      citekey: "SyntheticBaseline2026",
    })
  );
  upload.append("file", new Blob([sourcePDF()], {type: "application/pdf"}), "synthetic-baseline.pdf");
  const paper = await api("/api/research/papers", "POST", upload, 201);

  const now = new Date();
  const today = [now.getFullYear(), now.getMonth() + 1, now.getDate()]
    .map(value => String(value).padStart(2, "0"))
    .join("-");

  await api(`/api/research/projects/${project.id}/tasks`, "POST", {
    title: "Synthetic baseline review task",
    status: "inProgress",
    priority: "high",
    dueDate: today,
    dueTime: "14:30",
    description: "Synthetic task item for visual baseline captures.",
  }, 201);

  await api(`/api/research/projects/${project.id}/notes`, "POST", {
    title: "Synthetic project brief",
    body: "Synthetic overview note used to validate typography and layout spacing.",
    tags: ["project_brief"],
  }, 201);

  const meeting = await api("/api/studio/sessions", "POST", {
    topic: "Synthetic roundtable baseline review",
    project_id: project.id,
    members: [{model: "fixture/first"}, {model: "fixture/second"}],
    preset: "work",
    start_agenda_draft: true,
  }, 201);

  await eventually(
    async () => (await api(`/api/studio/sessions/${meeting.id}`)).board?.state === "published",
    "synthetic roundtable session ready",
    20000
  );

  return {project, paper, meeting};
}

function screenRoute(screenId, fixtures) {
  switch (screenId) {
    case "home":
      return "/research";
    case "project-overview":
      return `/research?project=${encodeURIComponent(fixtures.project.id)}`;
    case "single-chat":
      return "/lab";
    case "roundtable-room":
      return `/studio?session=${encodeURIComponent(fixtures.meeting.id)}&project=${encodeURIComponent(fixtures.project.id)}`;
    case "reader":
      return `/reader?paper=${encodeURIComponent(fixtures.paper.id)}&project=${encodeURIComponent(fixtures.project.id)}`;
    case "settings-storage":
      return "/studio?view=settings";
    default:
      throw new Error(`Unknown screen id: ${screenId}`);
  }
}

async function expectMeetingPanes(session, mode) {
  await eventually(() => session.evaluate(mode => {
    const workspace = document.querySelector(".workspace-region").getBoundingClientRect();
    const grid = document.getElementById("board-workspace").getBoundingClientRect();
    const board = document.getElementById("meeting-board").getBoundingClientRect();
    const chat = document.getElementById("room-chat").getBoundingClientRect();
    if (window.innerWidth !== 1380 || grid.height <= 0) return false;
    if (mode === "split") {
      return workspace.width > 900 && board.width > 0 && board.height > 0 &&
        chat.width > 0 && chat.height > 0 && Math.abs(board.right - chat.left) <= 1;
    }
    const [visible, hidden] = mode === "board" ? [board, chat] : [chat, board];
    return workspace.width <= 900 && hidden.width === 0 && visible.height > 0 &&
      Math.abs(visible.left - grid.left) <= 1 && Math.abs(visible.right - grid.right) <= 1;
  }, mode), `meeting panes in ${mode} layout with a fixed 1380px viewport`, 5000);
}

async function waitForScreenReady(session, step, fixtures) {
  await eventually(
    () =>
      session.evaluate(
        ({screen, apiLocale, theme, colorTheme, paperTitle}) => {
          const root = document.documentElement;
          if (root.lang !== apiLocale) return false;
          if (root.dataset.theme !== theme) return false;
          if (root.dataset.colorTheme !== colorTheme) return false;
          if (screen === "home" || screen === "project-overview") {
            const main = document.querySelector("#main");
            return Boolean(main && main.getAttribute("aria-busy") === "false" && main.textContent.trim().length > 0);
          }
          if (screen === "single-chat") {
            return (
              document.body.dataset.workspaceSurface === "lab" &&
              Boolean(document.querySelector("#question"))
            );
          }
          if (screen === "roundtable-room") {
            const toggle = document.querySelector("#meeting-actions-toggle");
            return Boolean(toggle && toggle.offsetParent !== null);
          }
          if (screen === "reader") {
            const title = document.querySelector("#title");
            return Boolean(title && title.textContent.includes(paperTitle));
          }
          if (screen === "settings-storage") {
            const tab = document.querySelector("#settings-tab-storage");
            const panel = document.querySelector("#settings-panel-storage");
            if (!tab || !panel) return false;
            if (panel.hidden) {
              tab.click();
              return false;
            }
            return true;
          }
          return false;
        },
        {
          screen: step.screen,
          apiLocale: step.apiLocale,
          theme: step.theme,
          colorTheme: step.colorTheme,
          paperTitle: fixtures.paper.title,
        }
      ),
    `screen ready: ${step.file}`,
    15000
  );

  // Let layout and paint settle for two animation frames.
  await session.evaluate(
    () => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve(true))))
  );
}

function isReaderComparisonView(step) {
  return step.screen === "reader" && step.width === 1380 && step.height === 900 &&
    step.locale === "zh" && step.theme === "light" && step.colorTheme === "iris";
}

function checksWorkspaceLayout(step, readerComparison) {
  return readerComparison !== "historical" &&
    step.locale === "zh" && step.theme === "light" && step.colorTheme === DEFAULT_COLOR_THEME &&
    ["home", "project-overview", "roundtable-room", "reader"].includes(step.screen);
}

async function measureReader(session) {
  await eventually(() => session.evaluate(() => {
    const image = document.querySelector("#pageImage");
    return !document.querySelector("#pageSurface").hidden && image.complete && image.naturalWidth > 0;
  }), "first synthetic PDF page rendered", 15000);

  return session.evaluate(async () => {
    await document.fonts.ready;
    const viewport = document.querySelector("#viewport").getBoundingClientRect();
    return {
      configuration: {
        window: [innerWidth, innerHeight],
        paper: document.querySelector("#title").textContent.trim(),
        page: document.querySelector("#pageNo").value,
        locale: document.documentElement.lang,
        theme: document.documentElement.dataset.theme,
        colorTheme: document.documentElement.dataset.colorTheme,
        textSize: document.documentElement.dataset.textSize,
        navigationExpanded: document.querySelector("#workspace-nav-toggle").getAttribute("aria-expanded"),
        inspectorOpen: !document.querySelector("#reader-inspector").hidden,
        contextRailOpen: !document.querySelector("#context-rail").hidden,
      },
      viewportTop: viewport.top,
      viewportBottom: viewport.bottom,
      visibleViewportHeight: Math.min(innerHeight, viewport.bottom) - Math.max(0, viewport.top),
      headerRowHeight: document.querySelector(".reader-header")?.getBoundingClientRect().height || 0,
    };
  });
}

function assertReaderHeightGain(before, after) {
  assert.deepEqual(after.configuration, before.configuration, "Reader comparison settings changed");
  assert.deepEqual(before.configuration.window, [1380, 900]);
  assert.equal(before.configuration.inspectorOpen, false);
  assert.equal(before.configuration.contextRailOpen, false);
  assert.ok(before.headerRowHeight > 0 && before.visibleViewportHeight > 0,
    "Historical Reader must show its header row and PDF viewport");
  const gain = after.visibleViewportHeight - before.visibleViewportHeight;
  assert.ok(gain >= before.headerRowHeight,
    `Reader gained ${gain}px (${before.visibleViewportHeight} → ${after.visibleViewportHeight}px); expected at least one historical header row (${before.headerRowHeight}px)`);
}

async function captureVisualBaselines(binary, outputDir, plan, readerComparison) {
  await mkdir(outputDir, {recursive: true});

  const base = await mkdtemp(path.join(await realpath(tmpdir()), "sci-visual-baselines-"));
  const gateway = await localGateway();
  let host;
  let session;
  try {
    const spec = path.join(base, "Baseline.app", "Contents", "Resources", "sci-station.agent.js");
    await mkdir(path.dirname(spec), {recursive: true});
    await writeFile(spec, "// Offline synthetic model catalog fixture.\n");
    const env = await fixtureHome(base, gateway.port, spec);
    const probe = await listen();
    const {port} = probe.address();
    await closeServer(probe);

    host = await launch(binary, port, path.join(base, "root"), env, "serve");
    const fixtures = await seedSyntheticFixtures(host);
    const playwright = tryLoadPlaywright();
    session = playwright
      ? await openPlaywrightSession(playwright, host.origin)
      : await openCdpSession(base);

    // Bootstrap origin so localStorage can be configured before navigating through the matrix.
    await session.goto(host.origin + "/research");

    let readerGeometry;
    let currentViewport = "";
    let currentLocale = "";
    let currentTheme = "";
    let currentColorTheme = "";
    const manifestEntries = [];

    for (const step of plan) {
      if (currentViewport !== step.viewport) {
        await session.setViewport(step.width, step.height);
        currentViewport = step.viewport;
      }
      if (currentLocale !== step.apiLocale) {
        await host.request("/api/research/interface", "PATCH", {language: step.apiLocale}, 200);
        currentLocale = step.apiLocale;
      }
      if (currentTheme !== step.theme || currentColorTheme !== step.colorTheme) {
        await session.emulateColorScheme(step.theme);
        await session.evaluate(
          ({theme, colorTheme}) => {
            localStorage.setItem("studio.appearance", theme);
            localStorage.setItem("studio.color-theme", colorTheme);
            localStorage.setItem("studio.text-size", "standard");
            if (window.RoundtableAppearance) {
              window.RoundtableAppearance.setMode(theme, true);
              window.RoundtableAppearance.setColorTheme(colorTheme, true);
              window.RoundtableAppearance.setTextSize("standard", true);
            }
          },
          {theme: step.theme, colorTheme: step.colorTheme}
        );
        currentTheme = step.theme;
        currentColorTheme = step.colorTheme;
      }

      const route = screenRoute(step.screen, fixtures);
      await session.goto(host.origin + route);
      await waitForScreenReady(session, step, fixtures);

      if (step.screen === "home" && step.viewport === "1380x900") {
        const audit = await session.evaluate(() => {
          const canvas = document.createElement("canvas");
          canvas.width = canvas.height = 1;
          const ctx = canvas.getContext("2d");
          const rgb = color => {
            ctx.clearRect(0, 0, 1, 1);
            ctx.fillStyle = color;
            ctx.fillRect(0, 0, 1, 1);
            return Array.from(ctx.getImageData(0, 0, 1, 1).data);
          };
          const lum = ([r, g, b]) => {
            const lin = [r, g, b].map(v => {
              const s = v / 255;
              return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
            });
            return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
          };
          const ratio = (fg, bg) => {
            const l1 = lum(rgb(fg)), l2 = lum(rgb(bg));
            return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
          };
          const styles = getComputedStyle(document.documentElement);
          const token = name => styles.getPropertyValue(name).trim();
          const canvasBg = token("--bg-canvas");
          const surfaceBg = token("--bg-surface");
          const subtleBg = token("--bg-subtle");
          const ink = token("--ink-primary");
          const muted = token("--ink-muted");
          const accent = token("--accent");
          const accentInk = token("--accent-ink");
          const focusRing = token("--focus-ring");
          const danger = token("--danger");
          const warning = token("--warning");
          const success = token("--success");
          const actionLink = document.querySelector("#dashboard-view .action-link");
          const checks = [
            ["ink on canvas", ratio(ink, canvasBg), 4.5],
            ["ink on surface", ratio(ink, surfaceBg), 4.5],
            ["ink on subtle", ratio(ink, subtleBg), 4.5],
            ["muted on surface", ratio(muted, surfaceBg), 4.5],
            ["muted on canvas", ratio(muted, canvasBg), 4.5],
            ["accent on surface", ratio(accent, surfaceBg), 4.5],
            ["accent-ink on accent", ratio(accentInk, accent), 4.5],
            ["focus-ring on surface", ratio(focusRing, surfaceBg), 3.0],
            ["focus-ring on canvas", ratio(focusRing, canvasBg), 3.0],
            ["danger on surface", ratio(danger, surfaceBg), 4.5],
            ["warning on surface", ratio(warning, surfaceBg), 4.5],
            ["success on surface", ratio(success, surfaceBg), 4.5],
            ["diff addition gutter", ratio(token("--diff-add-gutter"), token("--diff-add-bg")), 4.5],
            ["diff removal gutter", ratio(token("--diff-remove-gutter"), token("--diff-remove-bg")), 4.5],
          ];
          if (actionLink) {
            checks.push(["rendered .action-link", ratio(getComputedStyle(actionLink).color, surfaceBg), 4.5]);
          }
          return checks.map(([label, value, min]) => ({label, value: Number(value.toFixed(2)), min, ok: value >= min}));
        });
        const failed = audit.filter(item => !item.ok);
        assert.deepEqual(
          failed,
          [],
          `WCAG AA contrast failed for ${step.locale}/${step.theme}/${step.colorTheme}: ${JSON.stringify(failed)}`
        );
      }
      if (readerComparison && isReaderComparisonView(step)) readerGeometry = await measureReader(session);

      const dest = path.join(outputDir, step.file);
      await session.screenshot(dest);
      manifestEntries.push({
        file: step.file,
        screen: step.screen,
        viewport: step.viewport,
        locale: step.locale,
        theme: step.theme,
        colorTheme: step.colorTheme,
      });

      if (checksWorkspaceLayout(step, readerComparison)) {
        const checkLayout = () =>
          session.evaluate(() => {
            const region = document.querySelector(".workspace-region");
            const rail = document.querySelector("#context-rail");
            const visibleControls = selector => {
              const bar = document.querySelector(selector);
              if (!bar) return [];
              const barRect = bar.getBoundingClientRect();
              if (barRect.width === 0 || barRect.height === 0) return [];
              const items = Array.from(bar.querySelectorAll("a, button, summary, select")).filter(el => {
                if (el.hidden || el.closest("[hidden]")) return false;
                const style = getComputedStyle(el);
                if (style.display === "none" || style.visibility === "hidden") return false;
                const rect = el.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
              });
              const issues = [];
              for (const el of items) {
                const r = el.getBoundingClientRect();
                if (r.right > window.innerWidth + 1 || r.left < -1) {
                  issues.push({
                    kind: "clipped",
                    selector,
                    id: el.id || el.textContent.trim().slice(0, 24),
                    left: Math.round(r.left),
                    right: Math.round(r.right),
                    vw: window.innerWidth,
                  });
                }
              }
              for (let i = 0; i < items.length; i++) {
                const a = items[i].getBoundingClientRect();
                for (let j = i + 1; j < items.length; j++) {
                  const b = items[j].getBoundingClientRect();
                  const overlapX = Math.min(a.right, b.right) - Math.max(a.left, b.left);
                  const overlapY = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
                  if (overlapX > 2 && overlapY > 2) {
                    issues.push({
                      kind: "overlap",
                      selector,
                      a: items[i].id || items[i].textContent.trim().slice(0, 20),
                      b: items[j].id || items[j].textContent.trim().slice(0, 20),
                      overlapX: Math.round(overlapX),
                      overlapY: Math.round(overlapY),
                    });
                  }
                }
              }
              return issues;
            };
            const overflowX = document.documentElement.scrollWidth - window.innerWidth;
            return {
              regionContainer: region ? getComputedStyle(region).containerType : "",
              railContainer: rail ? getComputedStyle(rail).containerType : "",
              railVisible: Boolean(rail && !rail.hidden),
              overflowX,
              issues: [
                ...visibleControls(".workspace-bar"),
                ...visibleControls(".room-context-bar"),
              ],
            };
          });

        const closedState = await checkLayout();
        assert.equal(closedState.regionContainer, "inline-size", `${step.screen}@${step.viewport} .workspace-region container-type`);
        assert.equal(closedState.railContainer, "inline-size", `${step.screen}@${step.viewport} #context-rail container-type`);
        assert.ok(closedState.overflowX <= 1, `${step.screen}@${step.viewport} rail-closed horizontal overflow: ${closedState.overflowX}px`);
        assert.deepEqual(closedState.issues, [], `${step.screen}@${step.viewport} rail-closed control overlap/clipping`);

        const wideMeeting = step.screen === "roundtable-room" && step.viewport === "1380x900";
        if (wideMeeting) {
          await expectMeetingPanes(session, "split");
          await eventually(() => session.evaluate(() => !document.getElementById("shell-assist").disabled),
            "meeting context rail available");
        }
        const canToggle = await session.evaluate(() => {
          const btn = document.getElementById("shell-assist");
          if (!btn || btn.disabled) return false;
          btn.focus();
          btn.click();
          return true;
        });
        if (canToggle) {
          await eventually(
            () => session.evaluate(() => {
              const rail = document.getElementById("context-rail");
              return Boolean(rail && !rail.hidden);
            }),
            `context rail open on ${step.screen}@${step.viewport}`,
            5000
          );
          await delay(120);
          const openState = await checkLayout();
          assert.equal(openState.railVisible, true, `${step.screen}@${step.viewport} context rail should be open`);
          assert.ok(openState.overflowX <= 1, `${step.screen}@${step.viewport} rail-open horizontal overflow: ${openState.overflowX}px`);
          assert.deepEqual(openState.issues, [], `${step.screen}@${step.viewport} rail-open control overlap/clipping`);
          if (wideMeeting) {
            await expectMeetingPanes(session, "board");
            await session.evaluate(() => document.getElementById("room-chat-toggle").click());
            await expectMeetingPanes(session, "chat");
            await session.evaluate(() => document.getElementById("rail-to-board").click());
            await expectMeetingPanes(session, "board");
            await session.evaluate(() => document.getElementById("workspace-nav-toggle").click());
            await expectMeetingPanes(session, "split");
            await session.evaluate(() => {
              const note = document.getElementById("run-note");
              note.value = "Synthetic meeting draft";
              note.dispatchEvent(new Event("input", {bubbles: true}));
              document.getElementById("workspace-nav-toggle").click();
            });
            await expectMeetingPanes(session, "chat");
            const retainedDraft = await session.evaluate(() => {
              const note = document.getElementById("run-note");
              const draft = note.value;
              note.value = "";
              note.dispatchEvent(new Event("input", {bubbles: true}));
              document.getElementById("rail-to-board").click();
              return draft;
            });
            assert.equal(retainedDraft, "Synthetic meeting draft");
            await expectMeetingPanes(session, "board");
          }
          await session.screenshot(path.join(outputDir, `${step.screen}__${step.viewport}__rail-open.png`));
          await session.evaluate(() => {
            const btn = document.getElementById("shell-assist");
            if (btn && btn.getAttribute("aria-pressed") === "true") btn.click();
          });
          await eventually(
            () => session.evaluate(() => {
              const rail = document.getElementById("context-rail");
              return Boolean(!rail || rail.hidden);
            }),
            `context rail closed on ${step.screen}@${step.viewport}`,
            5000
          );
          if (wideMeeting) await expectMeetingPanes(session, "split");
        }
      }
    }

    assert.deepEqual(session.errors, [], "Unexpected page errors during visual baseline capture");
    const manifestPath = path.join(outputDir, "manifest.json");
    await writeFile(
      manifestPath,
      JSON.stringify(
        {
          generatedAt: new Date().toISOString(),
          count: manifestEntries.length,
          viewports: VIEWPORTS,
          screens: SCREENS,
          entries: manifestEntries,
          readerGeometry,
        },
        null,
        2
      ) + "\n"
    );

    if (process.env.SCI_STATION_SMOKE_SCREENSHOT && plan.some(step => step.screen === "home")) {
      const homeDefault = path.join(outputDir, "home__1380x900__zh__light__iris.png");
      const target = path.resolve(process.env.SCI_STATION_SMOKE_SCREENSHOT);
      if (target !== homeDefault) {
        const {copyFile} = require("node:fs/promises");
        await mkdir(path.dirname(target), {recursive: true});
        await copyFile(homeDefault, target);
      }
    }

    console.log(
      `Captured ${manifestEntries.length} visual baseline screenshots in ${outputDir} (0 page errors).`
    );
    return {outputDir, manifestPath, count: manifestEntries.length, readerGeometry};
  } finally {
    const stopped = await Promise.allSettled([session?.close(), host?.close()]);
    try {
      await closeServer(gateway.server);
    } finally {
      await rm(base, {recursive: true, force: true, maxRetries: 5, retryDelay: 200});
    }
    for (const result of stopped) {
      if (result.status === "rejected") throw result.reason;
    }
  }
}

async function runVisualBaselines(binary, outputArg, referenceBinary) {
  if (!binary) throw new Error(
    "Usage: node tests/workbench-visual-baselines-smoke.cjs <sci-station-binary> [output-dir] [pre-redesign-binary]"
  );
  const outputDir = resolveOutputDir(outputArg);
  const plan = buildCapturePlan();
  if (!referenceBinary) return captureVisualBaselines(binary, outputDir, plan);

  const reference = await captureVisualBaselines(referenceBinary, path.join(outputDir, "reader-before"),
    plan.filter(isReaderComparisonView), "historical");
  const candidate = await captureVisualBaselines(binary, outputDir, plan, "current");
  const before = reference.readerGeometry;
  const after = candidate.readerGeometry;
  const comparison = {before, after, gain: after.visibleViewportHeight - before.visibleViewportHeight};
  await writeFile(path.join(outputDir, "reader-geometry.json"), JSON.stringify(comparison, null, 2) + "\n");
  console.log("Reader geometry (CSS pixels)", JSON.stringify(comparison));
  assertReaderHeightGain(before, after);
  return candidate;
}

module.exports = {
  assertReaderHeightGain,
  checksWorkspaceLayout,
  VIEWPORTS,
  LOCALES,
  THEMES,
  COLOR_THEMES,
  SCREENS,
  buildCapturePlan,
  resolveOutputDir,
  resolveChromeBinary,
  runVisualBaselines,
};

if (require.main === module) {
  runVisualBaselines(process.argv[2], process.argv[3], process.argv[4]).catch(error => {
    console.error(error);
    process.exitCode = 1;
  });
}
