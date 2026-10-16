import Foundation
import Testing
@testable import SciStationCore

@Suite("Agent child process security")
struct AgentProcessSecurityTests {
    @Test("Child processes receive only allowlisted and non-secret environment values")
    func childProcessEnvironmentIsFiltered() throws {
        let environment = AgentChildProcessEnvironment.sanitized(
            hostEnvironment: [
                "HOME": "/Users/tester",
                "LANG": "en_US.UTF-8",
                "PATH": "/Users/tester/bin:/opt/homebrew/bin:/usr/bin:/bin",
                "OPENAI_API_KEY": "host-api-key",
                "GITHUB_TOKEN": "host-token",
                "UNRELATED_HOST_VALUE": "not-allowlisted"
            ],
            overrides: [
                "PYTHONPATH": "/signed/runtime",
                "PATH": "/tmp/attacker-bin",
                "SCI_STATION_TEST_MODE": "1",
                "MINERU_API_TOKEN": "caller-token",
                "AWS_SECRET_ACCESS_KEY": "caller-secret",
                "DYLD_INSERT_LIBRARIES": "/tmp/injected.dylib",
                "BASH_ENV": "/tmp/startup.sh",
                "UNLISTED_OVERRIDE": "not-allowed"
            ]
        )

        #expect(environment["HOME"] == "/Users/tester")
        #expect(environment["PATH"] == AgentChildProcessEnvironment.controlledExecutablePath)
        #expect(!environment["PATH", default: ""].contains("/Users/tester/bin"))
        #expect(!environment["PATH", default: ""].contains("/opt/homebrew/bin"))
        #expect(environment["PYTHONPATH"] == "/signed/runtime")
        #expect(environment["SCI_STATION_TEST_MODE"] == "1")
        #expect(environment["OPENAI_API_KEY"] == nil)
        #expect(environment["GITHUB_TOKEN"] == nil)
        #expect(environment["MINERU_API_TOKEN"] == nil)
        #expect(environment["AWS_SECRET_ACCESS_KEY"] == nil)
        #expect(environment["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(environment["BASH_ENV"] == nil)
        #expect(environment["UNLISTED_OVERRIDE"] == nil)
        #expect(environment["UNRELATED_HOST_VALUE"] == nil)

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
        process.environment = environment
        process.standardOutput = outputPipe
        try process.run()
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        #expect(process.terminationStatus == 0)
        #expect(output.contains("SCI_STATION_TEST_MODE=1"))
        #expect(!output.contains("host-api-key"))
        #expect(!output.contains("host-token"))
        #expect(!output.contains("caller-token"))
        #expect(!output.contains("caller-secret"))
    }

    @Test("Default sidecar launch uses an absolute Python runtime directly")
    func defaultSidecarRuntimeIsDeterministic() {
        let configuration = SidecarLaunchConfiguration()

        #expect(configuration.executableURL.isFileURL)
        #expect((configuration.executableURL.path as NSString).isAbsolutePath)
        #expect(configuration.executableURL.path != "/usr/bin/env")
        #expect(
            configuration.arguments == SidecarRuntimeLocator.developmentArguments
                || (configuration.arguments.first == "-I" && configuration.arguments.count == 2)
        )
    }

    @Test("Bundled sidecar resolution requires sealed source and an executable runtime")
    func bundledSidecarResolutionIsCompleteAndIsolated() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("sci-station-sidecar-locator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let resourcesURL = temporaryRoot.appendingPathComponent("Resources", isDirectory: true)
        let frameworksURL = temporaryRoot.appendingPathComponent("Frameworks", isDirectory: true)
        let launcherURL = resourcesURL
            .appendingPathComponent("AgentRuntime", isDirectory: true)
            .appendingPathComponent("sci_station_sidecar.py", isDirectory: false)
        let pythonURL = frameworksURL
            .appendingPathComponent("SidecarRuntime/bin/python3", isDirectory: false)

        try FileManager.default.createDirectory(
            at: launcherURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: pythonURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("print('sidecar')\n".utf8).write(to: launcherURL)

        #expect(
            SidecarRuntimeLocator.bundledRuntime(
                resourcesURL: resourcesURL,
                privateFrameworksURL: frameworksURL,
                sharedFrameworksURL: nil
            ) == nil
        )

        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: pythonURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pythonURL.path
        )

        let runtime = try #require(
            SidecarRuntimeLocator.bundledRuntime(
                resourcesURL: resourcesURL,
                privateFrameworksURL: frameworksURL,
                sharedFrameworksURL: nil
            )
        )
        #expect(runtime.pythonExecutableURL == pythonURL)
        #expect(runtime.launcherURL == launcherURL)
        #expect(runtime.arguments == ["-I", launcherURL.path])
    }

    @Test("Packaged apps fail closed when the sealed runtime is missing")
    func packagedAppDoesNotFallBackToSystemPython() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("sci-station-missing-runtime-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let appURL = temporaryRoot.appendingPathComponent("Fixture.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": "test.SciStation.RuntimeFixture",
            "CFBundleName": "RuntimeFixture",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: appURL))

        let executableURL = SidecarRuntimeLocator.defaultPythonExecutableURL(in: bundle)
        let arguments = SidecarRuntimeLocator.defaultArguments(in: bundle)
        #expect(executableURL == resourcesURL.appendingPathComponent("SidecarRuntime/bin/python3"))
        #expect(executableURL != SidecarRuntimeLocator.developmentPythonURL)
        #expect(arguments == ["-I", resourcesURL.appendingPathComponent("AgentRuntime/sci_station_sidecar.py").path])
    }

    @Test("Local MCP commands must be absolute executable paths")
    func localMCPCommandValidation() throws {
        let executableURL = try AgentMCPLocalCommandPolicy.executableURL(
            for: "/usr/bin/true",
            serverID: "test-server"
        )
        #expect(executableURL.path == "/usr/bin/true")

        #expect(throws: AgentMCPClientError.self) {
            try AgentMCPLocalCommandPolicy.executableURL(
                for: "python3",
                serverID: "test-server"
            )
        }
        #expect(throws: AgentMCPClientError.self) {
            try AgentMCPLocalCommandPolicy.executableURL(
                for: "env node server.js",
                serverID: "test-server"
            )
        }
    }

    @Test("Broken sidecar stdin fails promptly without terminating the host")
    func brokenSidecarPipeFailsPromptly() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec 0<&-; sleep 2"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let connection = SidecarConnection(
            process: process,
            inputHandle: inputPipe.fileHandleForWriting,
            outputHandle: outputPipe.fileHandleForReading,
            errorHandle: errorPipe.fileHandleForReading
        )

        try process.run()
        try inputPipe.fileHandleForReading.close()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            try? inputPipe.fileHandleForWriting.close()
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        let startedAt = Date()
        do {
            _ = try await connection.sendRequest(
                method: "sidecar.initialize",
                params: .object([:]),
                timeout: 1
            )
            Issue.record("A closed sidecar stdin unexpectedly accepted a request.")
        } catch let error as SidecarJSONRPCError {
            #expect(error.code == -32001)
            #expect(Date().timeIntervalSince(startedAt) < 0.75)
        }
    }
}
