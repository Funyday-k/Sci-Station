import AppKit
import XCTest

@MainActor
final class InstalledAppUITests: XCTestCase {
    func testLibraryNavigation() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let appPath = try XCTUnwrap(environment["SCI_STATION_INSTALLED_UI_APP"])
        let profile = try XCTUnwrap(environment["SCI_STATION_INSTALLED_UI_PROFILE"])
        let root = try XCTUnwrap(environment["SCI_STATION_INSTALLED_UI_ROOT"])
        let registry = try XCTUnwrap(environment["SCI_STATION_INSTALLED_UI_REGISTRY"])
        let appURL = URL(fileURLWithPath: appPath).resolvingSymlinksInPath()
        let app = XCUIApplication(url: appURL)
        app.launchArguments = ["app", "-data-dir", root]
        app.launchEnvironment = [
            "HOME": profile + "/home",
            "CFFIXED_USER_HOME": profile + "/home",
            "XDG_CONFIG_HOME": profile + "/home/.config",
            "SCI_STATION_WORKSPACE_REGISTRY": registry,
            "TMPDIR": profile + "/tmp",
            "PATH": "/usr/bin:/bin"
        ]
        addTeardownBlock {
            if app.state != .notRunning {
                app.terminate()
            }
        }
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let process = try XCTUnwrap(NSWorkspace.shared.frontmostApplication)
        XCTAssertEqual(process.bundleURL?.resolvingSymlinksInPath(), appURL)
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/sci-station")
        XCTAssertEqual(process.executableURL?.resolvingSymlinksInPath(), executableURL)
        print("Installed app PID \(process.processIdentifier) from \(appURL.path)")

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "The installed app must open a native window.")
        XCTAssertGreaterThanOrEqual(window.frame.width, 680)
        XCTAssertGreaterThanOrEqual(window.frame.height, 460)

        let content = window.descendants(matching: .any)
        let home = matching(["Today", "今日", "今日任务"], in: content)
        let library = matching(["The library is empty", "还没有收录文献"], in: content)
        let libraryLink = matching(["Library", "论文库", "文献库"], in: window.links)
        let homeLink = matching(["Home", "首页"], in: window.links)
        waitUntilVisible(home, in: window)
        XCTAssertFalse(library.exists)

        click(libraryLink, process: process)
        waitUntilVisible(library, in: window)
        XCTAssertFalse(home.exists, "Library must replace the Home content.")
        click(homeLink, process: process)
        waitUntilVisible(home, in: window)
        XCTAssertFalse(library.exists, "Returning to Home must replace the Library content.")

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "The installed app must quit after Command-Q.")
    }

    private func matching(_ labels: [String], in query: XCUIElementQuery) -> XCUIElement {
        query.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func click(_ link: XCUIElement, process: NSRunningApplication) {
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        XCTAssertTrue(link.isEnabled)
        XCTAssertTrue(link.isHittable)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, process.processIdentifier)
        link.click()
    }

    private func waitUntilVisible(_ element: XCUIElement, in window: XCUIElement) {
        let predicate = NSPredicate { _, _ in
            element.exists && !element.frame.isEmpty && window.frame.intersects(element.frame)
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 15)
        XCTAssertEqual(result, .completed, "The destination content must be visible within the native window.")
    }
}
