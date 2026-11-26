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

        let home = matching(["Edit Layout", "编辑布局", "自定义组件"], in: window.buttons).firstMatch
        let library = matching(["Manage collections and tags", "管理集合和标签"], in: window.buttons).firstMatch
        let libraryLinks = matching(["Library", "论文库", "文献库"], in: window.links)
        let homeLinks = matching(["Home", "首页"], in: window.links)
        waitUntilVisible(home, in: window, step: "Home after launch")
        XCTAssertFalse(library.exists)

        click(libraryLinks, name: "Library", in: window, process: process)
        waitUntilVisible(library, in: window, step: "Library after clicking its link")
        XCTAssertFalse(home.exists, "Library must replace the Home content.")
        click(homeLinks, name: "Home", in: window, process: process)
        waitUntilVisible(home, in: window, step: "Home after clicking its link")
        XCTAssertFalse(library.exists, "Returning to Home must replace the Library content.")

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "The installed app must quit after Command-Q.")
    }

    private func matching(_ labels: [String], in query: XCUIElementQuery) -> XCUIElementQuery {
        query.matching(NSPredicate(format: "label IN %@", labels))
    }

    private func click(_ query: XCUIElementQuery, name: String, in window: XCUIElement, process: NSRunningApplication) {
        if query.firstMatch.waitForExistence(timeout: 10) {
            // Dashboard widgets can have additional links to the same page.
            // Select the highest visible link, where the workspace navigation sits.
            if let link = query.allElementsBoundByIndex.filter({ $0.isEnabled && $0.isHittable })
                .min(by: { $0.frame.minY < $1.frame.minY }) {
                XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, process.processIdentifier)
                link.click()
                return
            }
        }
        attachWindow(window, step: "Click " + name)
        XCTFail("The installed app must provide a clickable " + name + " link.")
    }

    private func waitUntilVisible(_ element: XCUIElement, in window: XCUIElement, step: String) {
        let predicate = NSPredicate { _, _ in
            element.exists && !element.frame.isEmpty && window.frame.intersects(element.frame)
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 15)
        if result != .completed {
            attachWindow(window, step: step)
        }
        XCTAssertEqual(result, .completed, "Expected visible page controls for " + step + ".")
        print("Installed app displayed " + step)
    }

    private func attachWindow(_ window: XCUIElement, step: String) {
        let hierarchy = XCTAttachment(string: window.debugDescription)
        hierarchy.name = step + " – accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = step + " – window"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
