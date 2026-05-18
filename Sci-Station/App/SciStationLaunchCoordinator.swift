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

    func start(appModel: AppViewModel) {
        guard !didStart else { return }
        didStart = true

        // Warm the SnellRoundhand-Bold font and the Liquid Glass / Metal
        // pipeline in parallel on a background thread. The first time
        // SwiftUI lays out a custom-font Text and a glassEffect, AppKit has
        // to load the font glyph data and compile the glass shader; doing
        // it eagerly here means the splash's first render frame doesn't
        // pay those costs synchronously on the main thread.
        Task.detached(priority: .userInitiated) {
            _ = NSFont(name: "SnellRoundhand-Bold", size: 52)
            _ = NSFont(name: "SnellRoundhand-Bold", size: 50)
            _ = NSFont(name: "Snell Roundhand", size: 52)
        }

        showSplashWindow()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_250_000_000)
            didReachMinimumDuration = true
            finishIfReady()
        }

        // Run workspace restoration AFTER the bloom is fully visible. The
        // restoration itself runs on @MainActor and triggers many
        // @Published changes that would otherwise re-evaluate the entire
        // hidden main-window SwiftUI tree mid-animation. By kicking it off
        // at +1.4s the bloom (which finishes near +0.7s) has already
        // committed and the user is just looking at a static glass panel,
        // so any main-thread blocking is invisible.
        Task { @MainActor [weak self, weak appModel] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard let appModel else {
                self?.markAppPreparationFinished()
                return
            }
            await appModel.restoreLastWorkspaceIfNeeded()
            appModel.applyRightRailRouteSuggestion()
            appModel.recordToolbarPolicyChange(appModel.toolbarModel)
            self?.markAppPreparationFinished()
        }
    }

    func markAppPreparationFinished() {
        didFinishAppPreparation = true
        finishIfReady()
    }

    private func showSplashWindow() {
        // Sized to comfortably hold the panel + the white halo + drop
        // shadow without clipping the soft glow against the window edge.
        let size = NSSize(width: 600, height: 280)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
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
        window.ignoresMouseEvents = true
        window.alphaValue = 0

        let hosting = NSHostingView(rootView: SciStationLaunchAnimationView())
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        // Force SwiftUI to lay out & rasterize once before we order the window
        // onscreen. Without this the first appearance frame and the bloom
        // animation compete for the same runloop tick, which the user saw as
        // stutter / a seed circle that lingered before the morph started.
        hosting.layoutSubtreeIfNeeded()
        window.contentView = hosting

        window.center()
        window.orderFrontRegardless()

        // Quick alpha fade so the floating splash doesn't pop in. Keep this
        // shorter than the SwiftUI bloom so the two animations stay in sync.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        splashWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishIfReady() {
        guard isLaunching, didReachMinimumDuration, didFinishAppPreparation else { return }

        isLaunching = false

        guard let splashWindow else { return }

        hiddenSplashWindow = splashWindow

        // Cross-fade: splash fades out and the main window fades in over
        // matching durations so the handoff feels like a single gradient
        // appearance rather than two discrete animations.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            splashWindow.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                splashWindow.orderOut(nil)
                self.splashWindow = nil
            }
        }
    }
}

/// Window-group root that defers constructing the heavy ContentView shell
/// until after the launch splash has finished. The previous design kept
/// ContentView (NavigationSplitView, toolbar, sidebar, right rail, sheets,
/// onChange watchers) alive but invisible during the splash – every
/// @Published change AppViewModel emitted during workspace restoration
/// re-evaluated that whole shell on the main thread, which is what the
/// user perceived as bloom-animation stutter and a hard hitch when the
/// title finished fading in. With this gate, the launching phase only
/// renders Color.clear so the splash window has the main thread to itself.
struct LaunchSplashGate<Content: View>: View {
    @ObservedObject var launchCoordinator: SciStationLaunchCoordinator
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            if launchCoordinator.isLaunching {
                Color.clear
            } else {
                content()
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .center)))
            }
        }
        .animation(.easeInOut(duration: 0.42), value: launchCoordinator.isLaunching)
        .background(SciStationMainWindowGate(isLaunching: launchCoordinator.isLaunching))
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

        // Match the splash fade-out duration so the user reads splash →
        // main UI as one continuous cross-fade.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1
        }
    }
}
