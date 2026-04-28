import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
  let baseURL: URL?

  init(markdown: String, baseURL: URL? = nil) {
    self.markdown = markdown
    self.baseURL = baseURL
  }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(renderedHTML, baseURL: baseURL)
        context.coordinator.lastHTML = renderedHTML
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = renderedHTML
        guard context.coordinator.lastHTML != html else {
            return
        }

        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private var renderedHTML: String {
        let encodedMarkdown = Data(markdown.utf8).base64EncodedString()
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.css">
          <style>
            :root {
              color-scheme: light dark;
              --text: #202124;
              --secondary: #5f6368;
              --border: rgba(127, 127, 127, 0.24);
              --code: rgba(127, 127, 127, 0.12);
              --link: #0a66d9;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --text: #eceff4;
                --secondary: #b8bec8;
                --border: rgba(255, 255, 255, 0.18);
                --code: rgba(255, 255, 255, 0.10);
                --link: #7eb6ff;
              }
            }
            body {
              margin: 0;
              padding: 20px 22px 40px;
              color: var(--text);
              font: -apple-system-body;
              line-height: 1.55;
              background: transparent;
            }
            #content { max-width: 900px; }
            h1, h2, h3, h4 { line-height: 1.2; margin: 1.15em 0 0.45em; }
            h1:first-child, h2:first-child { margin-top: 0; }
            p, ul, ol, blockquote, table, pre { margin: 0.75em 0; }
            a { color: var(--link); text-decoration: none; }
            a:hover { text-decoration: underline; }
            code {
              padding: 0.12em 0.34em;
              border-radius: 5px;
              background: var(--code);
              font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
              font-size: 0.92em;
            }
            pre {
              padding: 13px 14px;
              border-radius: 8px;
              overflow: auto;
              background: var(--code);
              border: 1px solid var(--border);
            }
            pre code { padding: 0; background: transparent; }
            blockquote {
              padding: 0.1em 0 0.1em 1em;
              color: var(--secondary);
              border-left: 3px solid var(--border);
            }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid var(--border); padding: 6px 8px; }
            th { background: var(--code); }
            img { max-width: 100%; height: auto; border-radius: 6px; }
            .fallback {
              white-space: pre-wrap;
              font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            }
          </style>
        </head>
        <body>
          <main id="content"></main>
          <script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"></script>
          <script src="https://cdn.jsdelivr.net/npm/dompurify@3.1.6/dist/purify.min.js"></script>
          <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/katex.min.js"></script>
          <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.10/dist/contrib/auto-render.min.js"></script>
          <script>
            const encodedMarkdown = "\(encodedMarkdown)";
            const markdown = new TextDecoder().decode(Uint8Array.from(atob(encodedMarkdown), c => c.charCodeAt(0)));
            const content = document.getElementById('content');

            function escaped(text) {
              return text.replace(/[&<>]/g, char => ({'&':'&amp;', '<':'&lt;', '>':'&gt;'}[char]));
            }

            function renderMarkdown() {
              if (!window.marked || !window.DOMPurify) {
                content.innerHTML = '<pre class="fallback">' + escaped(markdown) + '</pre>';
                return;
              }

              marked.setOptions({ gfm: true, breaks: true, mangle: false, headerIds: false });
              content.innerHTML = DOMPurify.sanitize(marked.parse(markdown));

              if (window.renderMathInElement) {
                renderMathInElement(content, {
                  delimiters: [
                    {left: '$$', right: '$$', display: true},
                    {left: '\\\\[', right: '\\\\]', display: true},
                    {left: '$', right: '$', display: false},
                    {left: '\\\\(', right: '\\\\)', display: false}
                  ],
                  throwOnError: false
                });
              }
            }

            window.addEventListener('load', renderMarkdown);
            setTimeout(renderMarkdown, 900);
          </script>
        </body>
        </html>
        """
    }

    final class Coordinator {
        var lastHTML = ""
    }
}
