import AppKit
import SwiftUI
import WebKit

/// Embedded HTML/JS chat renderer. Hosts a `WKWebView` that loads
/// `ChatRenderer.bundle/index.html` once and exposes a `setChatState`
/// JavaScript function. SwiftUI deltas are pushed through `evaluateJavaScript`
/// so streaming updates re-use the same web view (no flicker, no re-mount).
@MainActor
struct ChatMarkdownWebView: NSViewRepresentable {
    let markdown: String
    let fontSize: Double
    let isError: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ChatMarkdownContainerView {
        let container = ChatMarkdownContainerView()
        context.coordinator.attach(container: container)
        context.coordinator.update(markdown: markdown, fontSize: fontSize, isError: isError)
        return container
    }

    func updateNSView(_ nsView: ChatMarkdownContainerView, context: Context) {
        context.coordinator.update(markdown: markdown, fontSize: fontSize, isError: isError)
    }

    static func dismantleNSView(_ nsView: ChatMarkdownContainerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private weak var container: ChatMarkdownContainerView?
        private var pendingState: ChatMarkdownState?
        private var lastDeliveredState: ChatMarkdownState?
        private var pageDidLoad = false

        func attach(container: ChatMarkdownContainerView) {
            self.container = container
            container.coordinator = self
            container.webView.navigationDelegate = self
            container.webView.configuration.userContentController.removeScriptMessageHandler(forName: "chatHeight")
            container.webView.configuration.userContentController.add(self, name: "chatHeight")
            container.loadInitialPageIfNeeded()
        }

        func detach() {
            container?.webView.configuration.userContentController.removeScriptMessageHandler(forName: "chatHeight")
            container?.webView.navigationDelegate = nil
            container = nil
        }

        func update(markdown: String, fontSize: Double, isError: Bool) {
            let state = ChatMarkdownState(markdown: markdown, fontSize: fontSize, isError: isError)
            if state == lastDeliveredState {
                return
            }
            pendingState = state
            flushPendingStateIfPossible()
        }

        func notePageReady() {
            pageDidLoad = true
            flushPendingStateIfPossible()
        }

        func handleHeight(_ height: CGFloat) {
            container?.applyMeasuredHeight(height)
        }

        // MARK: - WKNavigationDelegate

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                self?.notePageReady()
            }
        }

        nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            switch navigationAction.navigationType {
            case .linkActivated:
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            default:
                decisionHandler(.allow)
            }
        }

        // MARK: - WKScriptMessageHandler

        nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "chatHeight" else {
                return
            }
            let payload = message.body
            Task { @MainActor [weak self] in
                if let dict = payload as? [String: Any], let height = dict["height"] as? Double {
                    self?.handleHeight(CGFloat(height))
                } else if let height = payload as? Double {
                    self?.handleHeight(CGFloat(height))
                }
            }
        }

        // MARK: - Private

        private func flushPendingStateIfPossible() {
            guard pageDidLoad,
                  let webView = container?.webView,
                  let state = pendingState else {
                return
            }
            pendingState = nil
            lastDeliveredState = state

            let payload: [String: Any] = [
                "markdown": state.markdown,
                "fontSize": state.fontSize,
                "isError": state.isError
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            let script = "window.setChatState(\(json));"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}

private struct ChatMarkdownState: Equatable {
    let markdown: String
    let fontSize: Double
    let isError: Bool
}

@MainActor
final class ChatMarkdownContainerView: NSView {
    let webView: WKWebView
    weak var coordinator: ChatMarkdownWebView.Coordinator?

    private var measuredHeight: CGFloat = 24
    private var hasLoadedInitialPage = false

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = ChatMarkdownForwardingWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = true

        self.webView = webView
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: max(measuredHeight, 18))
    }

    func applyMeasuredHeight(_ height: CGFloat) {
        let resolved = max(height.rounded(.up), 18)
        guard abs(resolved - measuredHeight) > 0.5 else {
            return
        }
        measuredHeight = resolved
        invalidateIntrinsicContentSize()
    }

    func loadInitialPageIfNeeded() {
        guard !hasLoadedInitialPage,
              let pageURL = ChatMarkdownResources.indexURL,
              let baseURL = ChatMarkdownResources.bundleURL else {
            return
        }
        hasLoadedInitialPage = true
        webView.loadFileURL(pageURL, allowingReadAccessTo: baseURL)
    }
}

@MainActor
private final class ChatMarkdownForwardingWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas || abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
            superview?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

enum ChatMarkdownResources {
    static let bundleURL: URL? = {
        Bundle.main.url(forResource: "ChatRenderer", withExtension: "bundle")
    }()

    static let indexURL: URL? = {
        bundleURL?.appendingPathComponent("index.html")
    }()

    static let docPreviewURL: URL? = {
        bundleURL?.appendingPathComponent("doc-preview.html")
    }()

    /// True when the renderer assets are present in the running bundle.
    /// SwiftUI views can fall back to the legacy `AttributedString` renderer
    /// when this is false (e.g. in unit-test hosts that strip resources).
    static var isAvailable: Bool { indexURL != nil }
}
