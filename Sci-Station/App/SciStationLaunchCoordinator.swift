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

    init() {
        SciStationWindowRestoration.clearMainWindowState()
    }

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

enum SciStationWindowRestoration {
    static func clearMainWindowState() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            let isMainWindowFrame = key.hasPrefix("NSWindow Frame ")
                && key.contains("AppWindow")
                && key.contains("Sci_Station")
            let isMainSplitViewFrame = key.hasPrefix("NSSplitView Subview Frames ")
                && key.contains("SidebarNavigationSplitView")
                && key.contains("Sci_Station")
            if isMainWindowFrame || isMainSplitViewFrame {
                defaults.removeObject(forKey: key)
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
        window.orderFrontRegardless()
        constrainMainWindow(window)
        constrainMainWindowAfterLayout(window)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            window.animator().alphaValue = 1
        }
    }

    private func prepareMainWindow(_ window: NSWindow) {
        window.styleMask.insert(.resizable)
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isRestorable = false
        window.setFrameAutosaveName("")
        window.contentMinSize = NSSize(width: 0, height: 0)
        constrainMainWindow(window)
    }

    private func constrainMainWindowAfterLayout(_ window: NSWindow) {
        for delay in [0.2, 0.8, 1.6, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                guard let self, let window else { return }
                self.constrainMainWindow(window)
            }
        }
    }

    private func constrainMainWindow(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen) else {
            return
        }
        if window.isZoomed {
            window.zoom(nil)
        }
        guard let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return
        }
        let maxWidth = max(visibleFrame.width - 32, 640)
        let maxHeight = max(visibleFrame.height - 32, 420)
        let launchWidth = min(1180, maxWidth)
        let launchHeight = min(740, maxHeight)
        let allowedMinSize = NSSize(width: min(700, maxWidth), height: min(480, maxHeight))
        window.contentMinSize = NSSize(width: 0, height: 0)
        window.minSize = allowedMinSize
        let currentFrame = window.frame
        let targetWidth = min(max(currentFrame.width, window.minSize.width), launchWidth)
        let targetHeight = min(max(currentFrame.height, window.minSize.height), launchHeight)
        let isOutsideVisibleFrame = !visibleFrame.contains(currentFrame)
        guard currentFrame.width != targetWidth || currentFrame.height != targetHeight || isOutsideVisibleFrame else {
            return
        }
        let targetFrame = NSRect(
            x: visibleFrame.midX - targetWidth / 2,
            y: visibleFrame.midY - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
        window.setFrame(targetFrame, display: true)
        window.contentMinSize = NSSize(width: 0, height: 0)
        window.minSize = allowedMinSize
    }
}
