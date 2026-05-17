// SciStationUIProbe
//
// A minimal JSON-over-stdio bridge that exposes the macOS Accessibility
// (AXUIElement) API to the Python UI-test orchestrator under
// ``AgentRuntime/sci_station_agent/uitest/drivers/accessibility.py``.
//
// Why a Swift CLI instead of pyobjc? Three reasons:
//
//   1. AXUIElement APIs use Core Foundation / CFTypeRef plumbing that
//      pyobjc can call, but the calling code is awkward and error-prone.
//      Keeping the AX surface in Swift keeps the orchestrator portable —
//      it only needs subprocess + JSON.
//   2. Accessibility permission is per-binary. Granting "Accessibility"
//      privilege to a stable Swift binary is one button click; granting
//      it to /path/to/python3.11 is fragile and changes whenever the
//      user upgrades Python.
//   3. We can ship the probe alongside the App as a developer tool and
//      sign it once, instead of asking every user to trust their
//      interpreter.
//
// Wire format
// -----------
// stdin/stdout are NDJSON: one request per line, one response per line.
// Requests always include a ``cmd`` field; responses always include an
// ``ok`` (bool) field and, on failure, an ``error`` (string) field. The
// probe never exits on an error response — only on EOF, ``cmd: "quit"``,
// or a fatal IO failure.
//
// Supported commands
// ------------------
//
//   ping
//     {"cmd": "ping"}
//     -> {"ok": true, "version": "0.1.0"}
//
//   permission
//     {"cmd": "permission"}
//     -> {"ok": true, "trusted": <bool>}
//
//   list_running
//     {"cmd": "list_running"}
//     -> {"ok": true, "apps": [{"pid": 123, "bundle": "...", "name": "..."}]}
//
//   launch
//     {"cmd": "launch", "bundle": "Lingyu-Xia.Sci-Station",
//      "args": ["--research-root", "..."], "wait": true}
//     -> {"ok": true, "pid": 1234}
//
//   terminate
//     {"cmd": "terminate", "bundle": "Lingyu-Xia.Sci-Station"}
//     -> {"ok": true}
//
//   find
//     {"cmd": "find", "bundle": "...", "axid": "library.import.button",
//      "timeout_ms": 4000}
//     -> {"ok": true, "found": true, "role": "AXButton", "title": "Import"}
//
//   click
//     {"cmd": "click", "bundle": "...", "axid": "library.import.button"}
//     -> {"ok": true}
//
//   type
//     {"cmd": "type", "bundle": "...", "axid": "search.field", "value": "x"}
//     -> {"ok": true}
//
//   tree
//     {"cmd": "tree", "bundle": "...", "max_depth": 4}
//     -> {"ok": true, "tree": {...}}
//
//   quit
//     {"cmd": "quit"}
//     -> {"ok": true}  (process exits after writing)
//
// Failure modes are uniform: ``{"ok": false, "error": "..."}``. Callers
// can rely on every response being exactly one line of JSON.

import AppKit
import ApplicationServices
import Foundation

let VERSION = "0.1.0"

// MARK: - JSON IO --------------------------------------------------------

func writeResponse(_ payload: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A])) // newline
    } catch {
        let fallback = "{\"ok\":false,\"error\":\"encoding-failure\"}\n"
        FileHandle.standardOutput.write(fallback.data(using: .utf8) ?? Data())
    }
}

func writeError(_ message: String) {
    writeResponse(["ok": false, "error": message])
}

// MARK: - AX helpers -----------------------------------------------------

private let kAXIdentifierAttr = "AXIdentifier" as CFString

private func runningApp(bundle: String) -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundle })
}

private func appElement(bundle: String) -> AXUIElement? {
    guard let app = runningApp(bundle: bundle) else { return nil }
    return AXUIElementCreateApplication(app.processIdentifier)
}

private func attributeValue(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return result == .success ? value : nil
}

private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attributeValue(element, name) as? String
}

private func children(_ element: AXUIElement) -> [AXUIElement] {
    (attributeValue(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

private func findByIdentifier(
    root: AXUIElement,
    axid: String,
    depthLimit: Int = 64
) -> AXUIElement? {
    var stack: [(AXUIElement, Int)] = [(root, 0)]
    while let (current, depth) = stack.popLast() {
        if let identifier = stringAttribute(current, kAXIdentifierAttr as String),
           identifier == axid {
            return current
        }
        if depth >= depthLimit { continue }
        for child in children(current) {
            stack.append((child, depth + 1))
        }
    }
    return nil
}

private func findByIdentifierWithRetry(
    bundle: String,
    axid: String,
    timeoutMs: Int
) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(Double(max(0, timeoutMs)) / 1000.0)
    while true {
        if let root = appElement(bundle: bundle),
           let found = findByIdentifier(root: root, axid: axid) {
            return found
        }
        if Date() >= deadline { return nil }
        Thread.sleep(forTimeInterval: 0.1)
    }
}

private func describe(_ element: AXUIElement, depth: Int, maxDepth: Int) -> [String: Any] {
    var dict: [String: Any] = [:]
    dict["role"] = stringAttribute(element, kAXRoleAttribute as String) ?? ""
    if let identifier = stringAttribute(element, kAXIdentifierAttr as String), !identifier.isEmpty {
        dict["axid"] = identifier
    }
    if let title = stringAttribute(element, kAXTitleAttribute as String), !title.isEmpty {
        dict["title"] = title
    }
    if let value = stringAttribute(element, kAXValueAttribute as String), !value.isEmpty {
        dict["value"] = value
    }
    if depth < maxDepth {
        let kids = children(element)
        if !kids.isEmpty {
            dict["children"] = kids.map { describe($0, depth: depth + 1, maxDepth: maxDepth) }
        }
    }
    return dict
}

// MARK: - Command handlers ----------------------------------------------

private func handlePing() {
    writeResponse(["ok": true, "version": VERSION])
}

private func handlePermission() {
    let trusted = AXIsProcessTrusted()
    writeResponse(["ok": true, "trusted": trusted])
}

private func handleListRunning() {
    let apps = NSWorkspace.shared.runningApplications.compactMap { app -> [String: Any]? in
        guard let bundle = app.bundleIdentifier else { return nil }
        return [
            "pid": Int(app.processIdentifier),
            "bundle": bundle,
            "name": app.localizedName ?? ""
        ]
    }
    writeResponse(["ok": true, "apps": apps])
}

private func handleLaunch(_ request: [String: Any]) {
    guard let bundle = request["bundle"] as? String else {
        writeError("missing 'bundle'")
        return
    }
    let waitForActivation = (request["wait"] as? Bool) ?? false

    if let existing = runningApp(bundle: bundle) {
        writeResponse(["ok": true, "pid": Int(existing.processIdentifier), "already_running": true])
        return
    }

    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
        writeError("application not found for bundle '\(bundle)'")
        return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    if let args = request["args"] as? [String] {
        configuration.arguments = args
    }

    let semaphore = DispatchSemaphore(value: 0)
    var launchedApp: NSRunningApplication?
    var launchError: Error?
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
        launchedApp = app
        launchError = error
        semaphore.signal()
    }
    semaphore.wait()

    if let error = launchError {
        writeError("launch failed: \(error.localizedDescription)")
        return
    }
    guard let app = launchedApp else {
        writeError("launch returned no running application")
        return
    }
    if waitForActivation {
        let deadline = Date().addingTimeInterval(10)
        while !app.isFinishedLaunching, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
    writeResponse(["ok": true, "pid": Int(app.processIdentifier)])
}

private func handleTerminate(_ request: [String: Any]) {
    guard let bundle = request["bundle"] as? String else {
        writeError("missing 'bundle'")
        return
    }
    guard let app = runningApp(bundle: bundle) else {
        writeResponse(["ok": true, "already_terminated": true])
        return
    }
    app.terminate()
    writeResponse(["ok": true])
}

private func handleFind(_ request: [String: Any]) {
    guard let bundle = request["bundle"] as? String,
          let axid = request["axid"] as? String else {
        writeError("missing 'bundle' or 'axid'")
        return
    }
    let timeoutMs = (request["timeout_ms"] as? Int) ?? 4000
    guard let element = findByIdentifierWithRetry(bundle: bundle, axid: axid, timeoutMs: timeoutMs) else {
        writeResponse(["ok": true, "found": false])
        return
    }
    var payload: [String: Any] = ["ok": true, "found": true]
    payload["role"] = stringAttribute(element, kAXRoleAttribute as String) ?? ""
    if let title = stringAttribute(element, kAXTitleAttribute as String) {
        payload["title"] = title
    }
    if let value = stringAttribute(element, kAXValueAttribute as String) {
        payload["value"] = value
    }
    writeResponse(payload)
}

private func handleClick(_ request: [String: Any]) {
    guard let bundle = request["bundle"] as? String,
          let axid = request["axid"] as? String else {
        writeError("missing 'bundle' or 'axid'")
        return
    }
    let timeoutMs = (request["timeout_ms"] as? Int) ?? 4000
    guard let element = findByIdentifierWithRetry(bundle: bundle, axid: axid, timeoutMs: timeoutMs) else {
        writeError("element not found for axid '\(axid)'")
        return
    }
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if result == .success {
        writeResponse(["ok": true])
    } else {
        writeError("press action failed: AXError=\(result.rawValue)")
    }
}

private func handleType(_ request: [String: Any]) {
    guard let bundle = request["bundle"] as? String,
          let axid = request["axid"] as? String,
          let value = request["value"] as? String else {
        writeError("missing 'bundle', 'axid' or 'value'")
        return
    }
    let timeoutMs = (request["timeout_ms"] as? Int) ?? 4000
    guard let element = findByIdentifierWithRetry(bundle: bundle, axid: axid, timeoutMs: timeoutMs) else {
        writeError("element not found for axid '\(axid)'")
        return
    }
    // Most text fields accept AXValue with a CFString. Some (e.g. NSTextView)
    // also accept AXSelectedText / AXInsertText, but Sci-Station's editable
    // surfaces use plain TextFields which accept AXValue directly.
    let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
    if result == .success {
        writeResponse(["ok": true])
    } else {
        writeError("set value failed: AXError=\(result.rawValue)")
    }
}

private func handleTree(_ request: [String: Any]) {
    guard let bundle = request["bundle"] as? String else {
        writeError("missing 'bundle'")
        return
    }
    guard let root = appElement(bundle: bundle) else {
        writeError("application not running for bundle '\(bundle)'")
        return
    }
    let maxDepth = (request["max_depth"] as? Int) ?? 4
    let tree = describe(root, depth: 0, maxDepth: maxDepth)
    writeResponse(["ok": true, "tree": tree])
}

// MARK: - Main loop ------------------------------------------------------

private func dispatch(_ raw: String) -> Bool {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return true }

    guard let data = trimmed.data(using: .utf8) else {
        writeError("invalid utf8 line")
        return true
    }
    let parsed: [String: Any]
    do {
        guard let object = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            writeError("expected a JSON object")
            return true
        }
        parsed = object
    } catch {
        writeError("invalid json: \(error.localizedDescription)")
        return true
    }

    let command = (parsed["cmd"] as? String) ?? ""
    switch command {
    case "ping":         handlePing()
    case "permission":   handlePermission()
    case "list_running": handleListRunning()
    case "launch":       handleLaunch(parsed)
    case "terminate":    handleTerminate(parsed)
    case "find":         handleFind(parsed)
    case "click":        handleClick(parsed)
    case "type":         handleType(parsed)
    case "tree":         handleTree(parsed)
    case "quit":
        writeResponse(["ok": true])
        return false
    default:
        writeError("unknown command '\(command)'")
    }
    return true
}

private func runLoop() {
    let stdin = FileHandle.standardInput
    var buffer = Data()
    while true {
        let chunk = stdin.availableData
        if chunk.isEmpty {
            return
        }
        buffer.append(chunk)
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: 0..<newlineIndex)
            buffer.removeSubrange(0...newlineIndex)
            let line = String(data: lineData, encoding: .utf8) ?? ""
            if !dispatch(line) {
                return
            }
        }
    }
}

runLoop()
