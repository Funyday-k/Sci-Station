# Chat Renderer Bundle

This `.bundle` ships the KaTeX + marked.js assets used by `ChatMarkdownWebView`.

The directory uses the `.bundle` extension on purpose: Xcode's synchronized
root group treats `.bundle` as a single opaque resource and copies its
contents verbatim (including `fonts/`) into the app's
`Contents/Resources/ChatRenderer.bundle/`. That preserves the relative
`url(fonts/KaTeX_*.woff2)` paths inside `katex.min.css` without any
post-processing.

## Contents

- `index.html` — Chat renderer page; defines `window.setChatState`.
- `katex.min.css` / `katex.min.js` — KaTeX 0.16.11.
- `auto-render.min.js` — KaTeX `renderMathInElement` extension.
- `marked.min.js` — marked 14.1.3 (GFM Markdown parser).
- `fonts/*.woff2` — KaTeX woff2 fonts (only woff2 is shipped to keep size
  down; modern WebKit reads woff2 fine).

## Updating

```bash
mkdir -p /tmp/katex_pull && cd /tmp/katex_pull
npm pack katex@<new-version> marked@<new-version>
mkdir -p katex marked
tar -xzf katex-<new-version>.tgz -C katex --strip-components=1
tar -xzf marked-<new-version>.tgz -C marked --strip-components=1
cd <repo>/Sci-Station/Resources/ChatRenderer.bundle
cp /tmp/katex_pull/katex/dist/katex.min.css .
cp /tmp/katex_pull/katex/dist/katex.min.js .
cp /tmp/katex_pull/katex/dist/contrib/auto-render.min.js .
cp /tmp/katex_pull/marked/marked.min.js .
rm fonts/*.woff2
cp /tmp/katex_pull/katex/dist/fonts/*.woff2 fonts/
```

If KaTeX changes its CSS to reference fonts at a different relative path,
update `index.html` and this README accordingly.
