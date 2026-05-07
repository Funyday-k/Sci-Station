import AppKit
import Foundation
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
        configuration.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView: webView, readAccessURL: readAccessURL)
        context.coordinator.update(markdown: markdown, baseURLString: baseURLString)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(markdown: markdown, baseURLString: baseURLString)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.navigationDelegate = nil
        coordinator.detach()
    }

    private var baseURLString: String {
        guard let baseURL else {
            return ""
        }
        let directoryURL = baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()
        return directoryURL.absoluteString
    }

    private var readAccessURL: URL? {
        guard let bundleURL = ChatMarkdownResources.bundleURL else {
            return baseURL
        }
        guard let baseURL else {
            return bundleURL
        }
        return Self.commonAncestorURL(bundleURL.standardizedFileURL, baseURL.standardizedFileURL)
    }

    private static func commonAncestorURL(_ first: URL, _ second: URL) -> URL {
        let firstComponents = first.pathComponents
        let secondComponents = second.pathComponents
        var common: [String] = []
        for (left, right) in zip(firstComponents, secondComponents) {
            guard left == right else {
                break
            }
            common.append(left)
        }
        if common.isEmpty {
            return URL(fileURLWithPath: "/", isDirectory: true)
        }
        let path = NSString.path(withComponents: common)
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private weak var webView: WKWebView?
        private var pendingState: MarkdownPreviewState?
        private var lastDeliveredState: MarkdownPreviewState?
        private var pageDidLoad = false
        private var usesFallbackHTML = false

        func attach(webView: WKWebView, readAccessURL: URL?) {
            self.webView = webView
            guard let pageURL = ChatMarkdownResources.docPreviewURL,
                  let readAccessURL else {
                usesFallbackHTML = true
                pageDidLoad = true
                return
            }
            webView.loadFileURL(pageURL, allowingReadAccessTo: readAccessURL)
        }

        func detach() {
            webView = nil
        }

        func update(markdown: String, baseURLString: String) {
            let state = MarkdownPreviewState(markdown: markdown, baseURLString: baseURLString)
            guard state != lastDeliveredState else {
                return
            }
            pendingState = state
            flushPendingStateIfPossible()
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                self?.pageDidLoad = true
                self?.flushPendingStateIfPossible()
            }
        }

        nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }

        private func flushPendingStateIfPossible() {
            guard pageDidLoad,
                  let webView,
                  let state = pendingState else {
                return
            }
            pendingState = nil
            lastDeliveredState = state

            if usesFallbackHTML {
                webView.loadHTMLString(Self.fallbackHTML(markdown: state.markdown), baseURL: URL(string: state.baseURLString))
                return
            }

            let payload: [String: Any] = [
                "markdown": state.markdown,
                "baseURL": state.baseURLString
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            webView.evaluateJavaScript("window.setMarkdownPreviewState(\(json));", completionHandler: nil)
        }

        private static func fallbackHTML(markdown: String) -> String {
            let escaped = markdown
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return """
            <!doctype html>
            <html>
            <head>
              <meta charset=\"utf-8\">
              <style>
                body { margin: 0; padding: 20px 22px 40px; font: -apple-system-body; background: transparent; }
                pre { white-space: pre-wrap; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; }
              </style>
            </head>
            <body><pre>\(escaped)</pre></body>
            </html>
            """
        }
    }
}

private struct MarkdownPreviewState: Equatable {
    let markdown: String
    let baseURLString: String
}
