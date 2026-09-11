import AppKit
import Darwin
import Foundation

@MainActor
enum AppUISmokeTest {
    private enum SmokeResult {
        case success(NSSize)
        case failure(String)
    }

    private static let argument = "--app-ui-smoke-test"
    private static let environmentKey = "SCI_STATION_UI_SMOKE_TEST"
    private static let successPrefix = "SCI_STATION_UI_SMOKE_OK"
    private static let failurePrefix = "SCI_STATION_UI_SMOKE_FAILED"
    private static let timeout: TimeInterval = 20
    private static let maximumAccessibilityElementsPerTraversal = 10_000
    private static var didStart = false

    static func isRequested(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(argument)
            || processInfo.environment[environmentKey] == "1"
    }

    @discardableResult
    static func startIfRequested(
        appModel: AppViewModel,
        launchCoordinator: SciStationLaunchCoordinator,
        processInfo: ProcessInfo = .processInfo
    ) -> Bool {
        guard isRequested(processInfo: processInfo) else {
            return false
        }
        guard !didStart else { return true }
        didStart = true
        launchCoordinator.prepareForUISmokeTest()

        print("SCI_STATION_UI_SMOKE_STARTED")
        fflush(stdout)

        Task { @MainActor in
            await Task.yield()
            let result = await run(appModel: appModel, launchCoordinator: launchCoordinator)
            finish(result)
        }
        return true
    }

    private static func finish(_ result: SmokeResult) {
        switch result {
        case let .success(windowSize):
            print(
                "\(successPrefix) "
                    + "root=\(UITestAccessibilityID.App.mainWindowRoot) "
                    + "action=\(UITestAccessibilityID.Sidebar.tab(WorkspaceRoute.Top.library.rawValue)) "
                    + "destination=\(UITestAccessibilityID.Workspace.section(WorkspaceSection.library.rawValue)) "
                    + "window=\(Int(windowSize.width))x\(Int(windowSize.height))"
            )
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(0)
        case let .failure(reason):
            print("\(failurePrefix) reason=\(sanitize(reason))")
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(1)
        }
    }

    private static func run(
        appModel: AppViewModel,
        launchCoordinator: SciStationLaunchCoordinator
    ) async -> SmokeResult {
        let deadline = Date().addingTimeInterval(timeout)

        guard let window = await waitForMainWindow(
            launchCoordinator: launchCoordinator,
            deadline: deadline
        ) else {
            return .failure("main_window_not_visible")
        }
        guard let contentView = window.contentView else {
            return .failure("main_window_missing_content_view")
        }
        guard await waitForElement(
            identifier: UITestAccessibilityID.App.mainWindowRoot,
            in: contentView,
            deadline: deadline
        ) != nil else {
            return .failure("main_window_root_not_accessible")
        }

        appModel.selectSection(.dashboard)
        guard await waitForElement(
            identifier: UITestAccessibilityID.Workspace.section(WorkspaceSection.dashboard.rawValue),
            in: contentView,
            deadline: deadline
        ) != nil else {
            return .failure("home_destination_not_rendered")
        }

        let actionIdentifier = UITestAccessibilityID.Sidebar.tab(WorkspaceRoute.Top.library.rawValue)
        guard let libraryButton = await waitForElement(
            identifier: actionIdentifier,
            in: contentView,
            deadline: deadline
        ) else {
            return .failure("library_navigation_control_not_accessible")
        }
        guard performPress(on: libraryButton) else {
            return .failure("library_navigation_press_rejected")
        }

        let destinationIdentifier = UITestAccessibilityID.Workspace.section(WorkspaceSection.library.rawValue)
        guard await waitFor(
            {
                appModel.selectedSection == .library
                    && accessibilityElement(
                        identifier: destinationIdentifier,
                        in: contentView,
                        deadline: deadline
                    ) != nil
            },
            deadline: deadline
        ) else {
            return .failure("library_destination_not_rendered_after_press")
        }

        return .success(window.frame.size)
    }

    private static func waitForMainWindow(
        launchCoordinator: SciStationLaunchCoordinator,
        deadline: Date
    ) async -> NSWindow? {
        await waitForValue(deadline: deadline) {
            guard !launchCoordinator.isLaunching else {
                return nil
            }
            return NSApp.windows.first { window in
                window.isVisible
                    && !window.isMiniaturized
                    && window.alphaValue > 0.5
                    && window.frame.width >= 680
                    && window.frame.height >= 460
                    && window.contentView != nil
            }
        }
    }

    private static func waitForElement(
        identifier: String,
        in root: NSObject,
        deadline: Date
    ) async -> NSObject? {
        await waitForValue(deadline: deadline) {
            accessibilityElement(identifier: identifier, in: root, deadline: deadline)
        }
    }

    private static func waitFor(_ condition: () -> Bool, deadline: Date) async -> Bool {
        await waitForValue(deadline: deadline) { condition() ? true : nil } ?? false
    }

    private static func waitForValue<Value>(deadline: Date, _ value: () -> Value?) async -> Value? {
        while Date() < deadline {
            if let result = value() {
                return result
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }

    private static func accessibilityElement(
        identifier: String,
        in root: NSObject,
        deadline: Date
    ) -> NSObject? {
        var queue = [root]
        var nextIndex = 0
        var enqueued = Set([ObjectIdentifier(root)])

        while nextIndex < queue.count,
              nextIndex < maximumAccessibilityElementsPerTraversal,
              Date() < deadline {
            let element = queue[nextIndex]
            nextIndex += 1

            if accessibilityIdentifier(of: element) == identifier {
                return element
            }

            for child in accessibilityChildren(of: element) {
                guard queue.count < maximumAccessibilityElementsPerTraversal else {
                    break
                }
                guard enqueued.insert(ObjectIdentifier(child)).inserted else {
                    continue
                }
                queue.append(child)
            }
        }
        return nil
    }

    private static func accessibilityIdentifier(of object: NSObject) -> String? {
        (object as? NSAccessibilityElementProtocol)?.accessibilityIdentifier?()
    }

    private static func accessibilityChildren(of object: NSObject) -> [NSObject] {
        var children: [NSObject] = []
        if let view = object as? NSView {
            children.append(contentsOf: view.subviews)
        }

        let selector = #selector(NSAccessibilityLayoutArea.accessibilityChildren)
        if object.responds(to: selector) {
            let value = object.perform(selector)?.takeUnretainedValue() as? [Any]
            children.append(contentsOf: value?.compactMap { $0 as? NSObject } ?? [])
        }

        var seen = Set<ObjectIdentifier>()
        return children.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    private static func performPress(on object: NSObject) -> Bool {
        (object as? NSAccessibilityButton)?.accessibilityPerformPress() ?? false
    }

    private static func sanitize(_ message: String) -> String {
        message
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
