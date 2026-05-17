import Foundation
import OSLog

/// Captures SwiftUI runtime warnings (Xcode's purple-banner "Runtime
/// Issues") to a workspace-local JSONL/text file so the AI usage-test
/// orchestrator can assert on a "no warnings during scenario" channel.
///
/// **Why this exists.** SwiftUI runtime warnings are emitted as `os_log`
/// faults on the ``com.apple.runtime-issues`` subsystem. They never appear
/// on stderr, so a simple `dup2(stderr, …)` cannot catch them. The only
/// in-process reader is ``OSLogStore`` against the current process scope.
/// On macOS 12+ this works without entitlements; on earlier OS releases the
/// capture silently degrades to an empty log file (the orchestrator then
/// treats the absence as a soft signal, not a hard failure).
///
/// **Lifecycle.** ``install(in:)`` is idempotent per ``ResearchRoot``. It
/// creates the parent directory, opens the log for append, and spawns a
/// detached polling task. When a workspace changes, callers invoke
/// ``stop()`` so the previous workspace's log file isn't polluted by
/// warnings emitted by a different window or research root.
///
/// **Debug-only.** The capture is a no-op in non-DEBUG builds because:
/// 1) SwiftUI does not file most runtime issues in release builds, and
/// 2) we don't want shipping users' workspaces to grow a warnings log.
///
/// **Format.** One line per warning, tab-separated::
///
///     <ISO8601 timestamp>\t<subsystem>\t<category>\t<process>\t<message>
///
/// Lines never include user data: ``OSLogEntryLog.composedMessage`` already
/// applies the formatter's privacy attributes for SwiftUI's own messages.
/// We still strip embedded newlines and tabs so the log stays one-record-
/// per-line for the orchestrator.
public final class SwiftUIRuntimeWarningCapture: @unchecked Sendable {

    public static let relativePath = ".sci-station/debug/swiftui_warnings.log"

    /// SwiftUI / runtime-issues subsystem. Kept as a constant so future OS
    /// renames or third-party UI frameworks (UIKit on Mac Catalyst) can
    /// be added here in one place.
    public static let trackedSubsystems: Set<String> = [
        "com.apple.runtime-issues"
    ]

    public static let shared = SwiftUIRuntimeWarningCapture()

    private let lock = NSLock()
    private var currentRootURL: URL?
    private var currentTask: Task<Void, Never>?
    private var anchorDate: Date?

    /// Format a single captured log entry as a one-line record. Exposed
    /// (rather than kept private) so unit tests can drive it with synthetic
    /// inputs — ``OSLogEntryLog`` cannot be instantiated directly.
    public static func formatLine(
        timestamp: Date,
        subsystem: String,
        category: String,
        process: String,
        message: String,
        formatter: ISO8601DateFormatter = SwiftUIRuntimeWarningCapture.iso8601Formatter
    ) -> String {
        let cleaned = sanitize(message)
        let isoStamp = formatter.string(from: timestamp)
        return "\(isoStamp)\t\(subsystem)\t\(category)\t\(process)\t\(cleaned)"
    }

    /// Idempotently install the capture against ``rootURL``. Calling
    /// repeatedly with the same root is a no-op; calling with a different
    /// root cancels the previous task and starts a fresh one.
    @discardableResult
    public func install(rootURL: URL) -> Bool {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        if currentRootURL == rootURL, currentTask != nil {
            return true
        }
        currentTask?.cancel()
        currentTask = nil

        let logURL = rootURL.appendingPathComponent(
            Self.relativePath, isDirectory: false
        )
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return false
        }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        currentRootURL = rootURL
        anchorDate = Date()
        currentTask = Task.detached(priority: .utility) { [weak self] in
            await self?.pollLoop(logURL: logURL)
        }
        return true
        #else
        return false
        #endif
    }

    /// Cancel the polling task. Safe to call when nothing is installed.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        currentTask?.cancel()
        currentTask = nil
        currentRootURL = nil
        anchorDate = nil
    }

    // MARK: - Internals

    nonisolated private func pollLoop(logURL: URL) async {
        lock.lock()
        var lastDate = self.anchorDate ?? Date()
        lock.unlock()
        while !Task.isCancelled {
            await Self.collectAndAppend(
                logURL: logURL,
                startingAt: lastDate,
                advance: { lastDate = $0 }
            )
            // 2 seconds is fast enough that warnings show up while a
            // scenario is still running, and slow enough to keep idle
            // workspaces from burning CPU on log queries.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private static func collectAndAppend(
        logURL: URL,
        startingAt: Date,
        advance: (Date) -> Void
    ) async {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else {
            return
        }
        let position = store.position(date: startingAt)
        let predicate = NSPredicate(
            format: "subsystem IN %@",
            Array(trackedSubsystems)
        )
        let entries: AnySequence<OSLogEntry>
        do {
            entries = try store.getEntries(at: position, matching: predicate)
        } catch {
            return
        }

        var latestSeen = startingAt
        var lines: [String] = []
        for entry in entries {
            guard let log = entry as? OSLogEntryLog else { continue }
            // Skip our own bookkeeping at the exact anchor instant — the
            // anchor inclusive boundary causes a duplicate otherwise.
            if log.date <= startingAt { continue }
            latestSeen = max(latestSeen, log.date)
            lines.append(
                formatLine(
                    timestamp: log.date,
                    subsystem: log.subsystem,
                    category: log.category,
                    process: log.process,
                    message: log.composedMessage
                )
            )
        }
        guard !lines.isEmpty else {
            advance(latestSeen)
            return
        }

        let blob = lines.joined(separator: "\n") + "\n"
        guard let data = blob.data(using: .utf8) else {
            advance(latestSeen)
            return
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // Best-effort — capture failures must not break the App.
            }
        } else {
            try? data.write(to: logURL)
        }
        advance(latestSeen)
    }

    fileprivate static func sanitize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    public static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

