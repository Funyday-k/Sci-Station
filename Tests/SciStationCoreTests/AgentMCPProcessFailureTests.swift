import Darwin
import Foundation
import Testing
@testable import SciStationCore

@Suite("Local MCP process failure recovery")
struct AgentMCPProcessFailureTests {
    @Test("An initialize timeout returns while a child ignores termination")
    func timeoutDoesNotReadRunningProcessExitStatus() async throws {
        let root = try makeRoot()
        let pidURL = root.rootURL.appendingPathComponent("fixture.pid")
        defer {
            if let text = try? String(contentsOf: pidURL, encoding: .utf8),
               let pid = Int32(text) {
                kill(pid, SIGKILL)
            }
            try? FileManager.default.removeItem(at: root.rootURL)
        }
        // exec preserves ignored SIGTERM and the PID, so stop() cannot finish
        // termination before ensureSession returns its timeout diagnostic.
        let server = MCPServerConfiguration(
            id: "unresponsive-fixture", displayName: "Unresponsive fixture",
            transport: .localCommand, isEnabled: true, command: "/bin/sh",
            arguments: ["-c", "trap '' TERM\nprintf '%s' \"$$\" > \"$1\"\nexec /bin/sleep 30", "fixture", pidURL.path],
            timeoutSeconds: 0.25
        )
        let result = await AgentMCPConnectorManager().prepare(
            registry: AgentMCPConnectorRegistryResolver().resolve(profileServers: [server]), root: root
        )
        let status = try #require(result.statuses.first)
        #expect(result.tools.isEmpty)
        #expect(status.state == .failed)
        #expect(status.errorMessage?.contains("timed out: initialize") == true)
        #expect(status.exitCode == nil)
        #expect(status.retryCount == 1)
        let pid = try #require(Int32(String(contentsOf: pidURL, encoding: .utf8)))
        #expect(kill(pid, 0) == 0, "The fixture must still be running after stop requested termination.")
    }

    @Test("An executable launch failure has no termination status")
    func launchFailureDoesNotReadUnstartedProcessExitStatus() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root.rootURL) }
        let server = MCPServerConfiguration(
            id: "missing-fixture", displayName: "Missing executable fixture",
            transport: .localCommand, isEnabled: true,
            command: root.rootURL.appendingPathComponent("missing-executable").path,
            timeoutSeconds: 0.25
        )
        let result = await AgentMCPConnectorManager().prepare(
            registry: AgentMCPConnectorRegistryResolver().resolve(profileServers: [server]), root: root
        )
        let status = try #require(result.statuses.first)
        #expect(result.tools.isEmpty)
        #expect(status.state == .failed)
        #expect(status.errorMessage?.isEmpty == false)
        #expect(status.exitCode == nil)
        #expect(status.retryCount == 1)
    }

    private func makeRoot() throws -> ResearchRoot {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SciStationMCPFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return ResearchRoot(rootURL: url)
    }
}
