import AppKit
import Darwin
import Foundation

@MainActor
enum SidecarRuntimeSmokeTest {
    private static let argument = "--sidecar-runtime-smoke-test"
    private static let successPrefix = "SCI_STATION_SIDECAR_SMOKE_OK"
    private static let failurePrefix = "SCI_STATION_SIDECAR_SMOKE_FAILED"
    private static var didStart = false

    static func startIfRequested(processInfo: ProcessInfo = .processInfo) -> Bool {
        guard processInfo.arguments.contains(argument) else {
            return false
        }

        guard !didStart else {
            return true
        }
        didStart = true

        Task {
            let exitCode = await run()
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(exitCode)
        }
        return true
    }

    private static func run() async -> Int32 {
        guard let bundledRuntime = SidecarRuntimeLocator.bundledRuntime() else {
            print("\(failurePrefix) reason=missing_bundled_runtime")
            return 1
        }

        let bundleRoot = Bundle.main.bundleURL.standardizedFileURL.path
        guard bundledRuntime.pythonExecutableURL.standardizedFileURL.path.hasPrefix(bundleRoot + "/"),
              bundledRuntime.launcherURL.standardizedFileURL.path.hasPrefix(bundleRoot + "/"),
              bundledRuntime.arguments.first == "-I" else {
            print("\(failurePrefix) reason=runtime_outside_bundle_or_not_isolated")
            return 1
        }

        let smokeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("sci-station-sidecar-app-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: smokeRoot) }

        do {
            try FileManager.default.createDirectory(at: smokeRoot, withIntermediateDirectories: true)
            let supervisor = SidecarProcessSupervisor()
            _ = try await supervisor.start(
                initialization: SidecarInitializationRequest(
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    workspaceRoot: smokeRoot.path,
                    allowedRoots: ["workspace"]
                )
            )
            let health = await supervisor.health()
            try await supervisor.stop()

            guard health.status == "ready",
                  health.protocolVersion == "1.0",
                  health.schemaVersion == 1,
                  health.pythonVersion == "3.12.13" else {
                print("\(failurePrefix) reason=unexpected_health status=\(health.status) python=\(health.pythonVersion ?? "unknown")")
                return 1
            }

            print("\(successPrefix) status=\(health.status) python=\(health.pythonVersion ?? "unknown") isolated=1")
            return 0
        } catch {
            let reason = error.localizedDescription
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            print("\(failurePrefix) reason=\(reason)")
            return 1
        }
    }
}
