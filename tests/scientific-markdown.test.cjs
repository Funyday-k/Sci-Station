const assert = require("node:assert/strict");
const {execFileSync} = require("node:child_process");
const {copyFileSync, cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync} = require("node:fs");
const {tmpdir} = require("node:os");
const {join} = require("node:path");
const test = require("node:test");

const assets = join(__dirname, "../web/static");
const dependencies = [
  "research-vendor/marked.min.js",
  "research-vendor/dompurify.min.js",
  "research-vendor/katex.min.js",
  "scientific-markdown.js",
];
const formulaMarkdown = [
  "## Capture",
  "",
  String.raw`**Particles** obey $E=m c^2$ and \(x_2 < y\).`,
  "",
  String.raw`$$
\begin{aligned}
\alpha &= \frac{1}{2} \\
\beta &= \sqrt{x_2}
\end{aligned}
$$`,
  "",
  String.raw`\[
F = G m_1 m_2 / r^2
\]`,
  "",
  "| Symbol | Value |",
  "| --- | --- |",
  "| mass | 2 |",
  "",
  'Inline `$x$` stays literal.',
  "",
  '```js',
  'const untouched = "$c$";',
  '```',
  "",
  "Costs $5 to $8.",
  "",
  "[Paper](https://example.invalid/paper) [Blocked](javascript:void(0))",
  "",
  "![Remote image](https://example.invalid/remote.png)",
  "",
  "<script>window.unsafeScientificFixture = true</script>",
].join("\n");

test("all scientific surfaces use the same bundled rendering assets", () => {
  for (const page of ["studio", "lab", "research"]) {
    const html = readFileSync(join(assets, page + ".html"), "utf8");
    for (const script of dependencies)
      assert.equal(html.split('/static/' + script).length - 1, 1, `${page} must load ${script} once`);
    assert.match(html, /\/static\/research-vendor\/katex\.min\.css/);
  }
});

test("WKWebView renders bundled math and Markdown offline while preserving raw copy", {
  skip: process.platform !== "darwin",
}, () => {
  const dir = mkdtempSync(join(tmpdir(), "sci-station-markdown-"));
  try {
    mkdirSync(join(dir, "research-vendor"));
    for (const relative of [...dependencies, "research-vendor/katex.min.css", "scientific-markdown.css"])
      copyFileSync(join(assets, relative), join(dir, relative));
    cpSync(join(assets, "research-vendor/fonts"), join(dir, "research-vendor/fonts"), {recursive:true});
    const fixtureHTML = join(dir, "index.html");
    writeFileSync(fixtureHTML, '<!doctype html><html><head><meta charset="utf-8">' +
      '<link rel="stylesheet" href="research-vendor/katex.min.css">' +
      '<link rel="stylesheet" href="scientific-markdown.css">' +
      dependencies.map(file => '<script defer src="' + file + '"></script>').join("") +
      '<script defer src="fixture.js"></script></head><body><main id="output"></main></body></html>');
    writeFileSync(join(dir, "fixture.js"), `
(async () => {
  const raw = ${JSON.stringify(formulaMarkdown)};
  const host = document.getElementById("output");
  const ensure = (result, message) => { if (!result) throw Error(message); };
  window.SciMarkdown.render(host, "Streaming $$ E=x", {headingShift:2});
  ensure(host.textContent.includes("$$ E=x") && !host.querySelector(".katex"), "incomplete math should remain visible");
  window.SciMarkdown.render(host, "\`\`\`python\\nprint('partial')");
  ensure(host.querySelector("pre code")?.textContent.trim() === "print('partial')", "open code fences stay readable");
  window.SciMarkdown.render(host, ${JSON.stringify(String.raw`$\href{https://example.invalid/math}{x}$`)});
  ensure(!host.querySelector("a[href]"), "KaTeX trust must stay disabled");
  window.SciMarkdown.render(host, raw, {headingShift:2, cache:true});
  ensure(host.querySelector("h4")?.textContent === "Capture", "heading hierarchy");
  ensure(host.querySelectorAll(".katex").length === 4, "four rendered expressions");
  ensure(host.querySelectorAll(".katex-display").length === 2, "multiline display formulas");
  ensure(host.querySelectorAll(".katex math").length === 4, "accessible MathML");
  ensure(host.querySelector("table")?.rows.length === 2, "GFM table");
  ensure(host.querySelector("p code")?.textContent === "$x$", "inline code is literal");
  ensure(host.querySelector("pre code")?.textContent.trim() === 'const untouched = "$c$";', "fenced code is literal");
  ensure(host.textContent.includes("Costs $5 to $8."), "dollar prices are literal");
  ensure(host.querySelector('a[href]')?.rel === "noopener noreferrer", "explicit external navigation");
  ensure(host.querySelectorAll('a[href]').length === 1 && !host.querySelector("img, script"),
    "untrusted HTML and URLs must not introduce executable nodes or remote images");
  ensure(!window.unsafeScientificFixture && host.textContent.includes("<script>"), "escaped raw HTML");
  await document.fonts.ready;
  ensure(Array.from(document.fonts).some(font => font.status === "loaded" && font.family.startsWith("KaTeX")),
    "bundled KaTeX fonts loaded");
  ensure(performance.getEntriesByType("resource").every(entry => entry.name.startsWith("file:")), "offline resources");
  let copied;
  Object.defineProperty(navigator, "clipboard", {value:{async writeText(value) {copied = value;}}});
  const copy = window.SciMarkdown.copyButton(raw);
  document.body.append(copy);
  await copy.onclick();
  ensure(copied === raw && copy.textContent === "已复制", "verbatim original copied");
  window.webkit.messageHandlers.scientificFixture.postMessage("ok");
})().catch(error => window.webkit.messageHandlers.scientificFixture.postMessage(String(error)));
`);
    const binary = join(dir, "probe");
    execFileSync("xcrun", ["clang", "-fobjc-arc", "-mmacosx-version-min=12.0",
      "-framework", "AppKit", "-framework", "WebKit", join(__dirname, "scientific-markdown-darwin.m"), "-o", binary],
    {stdio:"pipe", timeout:30000});
    execFileSync(binary, [fixtureHTML], {stdio:"pipe", timeout:20000});
  } finally {
    rmSync(dir, {recursive:true, force:true});
  }
});

module.exports = {formulaMarkdown};
