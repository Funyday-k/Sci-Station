import Foundation
import CoreGraphics
import SciStationCore

struct CoreCheckSummary {
    var executed = 0
    var passed = 0
    var failures: [String] = []
}

final class CoreVerificationSuite {
    private var summary = CoreCheckSummary()

    func runAll() async -> CoreCheckSummary {
        await runSuite("Workspace") { await runWorkspace() }
        await runSuite("AgentPlatform") { await runAgentPlatform() }
        await runSuite("AgentRuntime") { await runAgentRuntime() }
        await runSuite("ShellHome") { await runShellHome() }
        await runSuite("AgentTools") { await runAgentTools() }
        await runSuite("Plugins") { await runPlugins() }
        await runSuite("AgentLoop") { await runAgentLoop() }
        await runSuite("LibraryImport") { await runLibraryImport() }
        await runSuite("Knowledge") { await runKnowledge() }
        await runSuite("Graph") { await runGraph() }
        await runSuite("TasksRecommendations") { await runTasksRecommendations() }
        return summary
    }

    private func runSuite(_ name: String, operation: () async -> Void) async {
        if let filter = ProcessInfo.processInfo.environment["SCI_STATION_CORE_TEST_SUITE"],
           !filter.isEmpty,
           name.caseInsensitiveCompare(filter) != .orderedSame {
            return
        }
        fputs("[SUITE] \(name)\n", stderr)
        await operation()
    }

    func runCheck(
        _ name: String,
        operation: () async throws -> Void
    ) async {
        if let filter = ProcessInfo.processInfo.environment["SCI_STATION_CORE_TEST_FILTER"],
           !filter.isEmpty,
           !name.localizedCaseInsensitiveContains(filter) {
            return
        }

        let startedAt = Date()
        summary.executed += 1
        fputs("[RUN] \(name)\n", stderr)
        fflush(stderr)

        do {
            try await operation()
            summary.passed += 1
            let elapsed = Date().timeIntervalSince(startedAt)
            fputs(String(format: "[PASS] %@ (%.3fs)\n", name, elapsed), stderr)
            fflush(stderr)
        } catch {
            let elapsed = Date().timeIntervalSince(startedAt)
            fputs(
                String(
                    format: "[FAIL] %@ (%.3fs): %@\n",
                    name,
                    elapsed,
                    error.localizedDescription
                ),
                stderr
            )
            fflush(stderr)
            summary.failures.append(name)
        }
    }

}
