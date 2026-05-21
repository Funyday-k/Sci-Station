import AppKit
import Combine
import SwiftUI

@MainActor
final class SciStationLaunchCoordinator: ObservableObject {
    @Published private(set) var isLaunching = true

    private var splashWindow: NSWindow?
    private var hiddenSplashWindow: NSWindow?
    private var didStart = false
    private var didReachMinimumDuration = false
    private var didFinishAppPreparation = false

    func start() {
        guard !didStart else { return }
        didStart = true

        showSplashWindow()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_250_000_000)
            didReachMinimumDuration = true
            finishIfReady()
        }
    }

    func markAppPreparationFinished() {
        didFinishAppPreparation = true
        finishIfReady()
    }

    private func showSplashWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.title = "Sci-Station"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = SciStationLiquidLaunchView(frame: window.contentRect(forFrameRect: window.frame))
        window.center()
        window.orderFrontRegardless()

        splashWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishIfReady() {
        guard isLaunching, didReachMinimumDuration, didFinishAppPreparation else { return }

        isLaunching = false

        guard let splashWindow else { return }

        hiddenSplashWindow = splashWindow

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            splashWindow.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                splashWindow.orderOut(nil)
                self.splashWindow = nil
            }
        }
    }
}

struct SciStationMainWindowGate: NSViewRepresentable {
    let isLaunching: Bool

    func makeNSView(context: Context) -> MainWindowGateView {
        let view = MainWindowGateView()
        view.isLaunching = isLaunching
        return view
    }

    func updateNSView(_ nsView: MainWindowGateView, context: Context) {
        nsView.isLaunching = isLaunching
    }
}

final class MainWindowGateView: NSView {
    var isLaunching = true {
        didSet { applyLaunchState() }
    }

    private var didHideWindow = false
    private var didRevealWindow = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyLaunchState()
    }

    private func applyLaunchState() {
        guard let window else { return }
        prepareMainWindow(window)

        if isLaunching {
            guard !didHideWindow else { return }
            didHideWindow = true
            window.alphaValue = 0
            window.orderOut(nil)
            return
        }

        guard !didRevealWindow else { return }
        didRevealWindow = true
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            window.animator().alphaValue = 1
        }
    }

    private func prepareMainWindow(_ window: NSWindow) {
        window.styleMask.insert(.resizable)
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenPrimary)
    }
}
