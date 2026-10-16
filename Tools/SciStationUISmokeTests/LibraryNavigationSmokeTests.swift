import AppKit
import Foundation
import XCTest

@MainActor
final class LibraryNavigationSmokeTests: XCTestCase {
    func testLibraryNavigation() throws {
        continueAfterFailure = false
        let appPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["SCI_STATION_UI_TEST_APP_PATH"],
            "The smoke script must supply the exact application path."
        )
        let processID = try XCTUnwrap(
            ProcessInfo.processInfo.environment["SCI_STATION_UI_TEST_APP_PID"].flatMap(Int32.init),
            "The smoke script must supply the exact process it launched."
        )
        let appURL = URL(fileURLWithPath: appPath).resolvingSymlinksInPath()
        let launchedApp = try XCTUnwrap(NSRunningApplication(processIdentifier: processID))
        XCTAssertEqual(launchedApp.bundleURL?.resolvingSymlinksInPath(), appURL)
        addTeardownBlock {
            launchedApp.terminate()
        }
        XCTAssertTrue(launchedApp.activate(options: [.activateAllWindows]))

        let app = XCUIApplication(url: appURL)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, launchedApp.processIdentifier)
        print("UI_SMOKE_HOST pid=\(launchedApp.processIdentifier) path=\(appURL.path)")

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20), "The main window must appear.")
        XCTAssertGreaterThanOrEqual(window.frame.width, 680)
        XCTAssertGreaterThanOrEqual(window.frame.height, 460)

        let root = element("app.main_window.root", in: window)
        XCTAssertTrue(waitUntilVisible(root, in: window), "The main content must be visible.")
        let home = element("workspace.section.dashboard", in: window)
        XCTAssertTrue(waitUntilVisible(home, in: window), "The host must start on Home.")
        let destination = element("workspace.section.library", in: window)
        XCTAssertFalse(destination.exists, "Library must not be the initial screen.")

        let libraryButton = window.buttons["sidebar.tab.library"]
        XCTAssertTrue(libraryButton.waitForExistence(timeout: 20), "Library must expose its real navigation button.")
        XCTAssertTrue(libraryButton.isEnabled)
        if !libraryButton.isHittable {
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = "Isolated UI host before navigation"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: window.debugDescription)
            hierarchy.name = "Isolated UI host accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(libraryButton.isHittable, "Library must be clickable on screen.")
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, launchedApp.processIdentifier)
        libraryButton.click()

        XCTAssertTrue(waitUntilVisible(destination, in: window), "Clicking Library must render its destination.")
        XCTAssertTrue(home.waitForNonExistence(timeout: 10), "Home must be replaced after navigation.")
    }

    private func element(_ identifier: String, in window: XCUIElement) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitUntilVisible(_ element: XCUIElement, in window: XCUIElement) -> Bool {
        let predicate = NSPredicate { _, _ in
            guard element.exists, window.exists else { return false }
            let frame = element.frame
            return !frame.isEmpty && !frame.isInfinite && !frame.isNull
                && window.frame.intersection(frame).width > 0
                && window.frame.intersection(frame).height > 0
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
            timeout: 20
        ) == .completed
    }
}
