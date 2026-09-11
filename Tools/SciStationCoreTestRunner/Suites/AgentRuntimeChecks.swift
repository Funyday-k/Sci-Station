import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runAgentRuntime() async {
        await runCheck("workspacePreferencesDefaultRuntimeIsStableSwiftLoop") { try await workspacePreferencesDefaultRuntimeIsStableSwiftLoop() }
        await runCheck("workspacePreferencesRuntimeSelectionFallbacksToSwiftLoop") { try await workspacePreferencesRuntimeSelectionFallbacksToSwiftLoop() }
        await runCheck("swiftUIRuntimeWarningCaptureFormatsOneLinePerEntry") { try swiftUIRuntimeWarningCaptureFormatsOneLinePerEntry() }
        await runCheck("swiftUIRuntimeWarningCaptureSanitisesEmbeddedSeparators") { try swiftUIRuntimeWarningCaptureSanitisesEmbeddedSeparators() }
        await runCheck("pdfAnnotationStoreRoundTripsSidecar") { try await pdfAnnotationStoreRoundTripsSidecar() }
        await runCheck("pdfAnnotationStoreHandlesMissingSidecar") { try await pdfAnnotationStoreHandlesMissingSidecar() }
        await runCheck("agentInteractionModeRuntimePolicyMatchesVisibleModes") { try agentInteractionModeRuntimePolicyMatchesVisibleModes() }
        await runCheck("externalAgentRuntimeStreamsLegacyLoopEvents") { try await externalAgentRuntimeStreamsLegacyLoopEvents() }
        await runCheck("fakeExternalRuntimeDrivesAITimelineEvents") { try await fakeExternalRuntimeDrivesAITimelineEvents() }
        await runCheck("langGraphRuntimePerformsInitializeHandshake") { try await langGraphRuntimePerformsInitializeHandshake() }
        await runCheck("langGraphRuntimeReplaysGoldenFixtureRunSuccess") { try await langGraphRuntimeReplaysGoldenFixtureRunSuccess() }
        await runCheck("langGraphRuntimeReplaysGoldenFixtureApprovalResume") { try await langGraphRuntimeReplaysGoldenFixtureApprovalResume() }
        await runCheck("langGraphRuntimeRejectsInvalidFixtureSchemaVersion") { try await langGraphRuntimeRejectsInvalidFixtureSchemaVersion() }
        await runCheck("langGraphRuntimeCanonicalizesSidecarLocalSequence") { try await langGraphRuntimeCanonicalizesSidecarLocalSequence() }
        await runCheck("langGraphRuntimeFallsBackWhenInitializeTimesOut") { try await langGraphRuntimeFallsBackWhenInitializeTimesOut() }
        await runCheck("langGraphRuntimeDoesNotLoseApprovalWhenSidecarCrashes") { try await langGraphRuntimeDoesNotLoseApprovalWhenSidecarCrashes() }
        await runCheck("sidecarConnectionBrokenPipeThrowsInsteadOfTerminatingHost") { try await sidecarConnectionBrokenPipeThrowsInsteadOfTerminatingHost() }
        await runCheck("sidecarLLMProxyDisablesProviderNativeToolCalling") { try await sidecarLLMProxyDisablesProviderNativeToolCalling() }
        await runCheck("sidecarEmbeddingProxyRejectsSensitiveConfigAndReturnsVectors") { try await sidecarEmbeddingProxyRejectsSensitiveConfigAndReturnsVectors() }
        await runCheck("sidecarRuntimeSelectorPersistsAndFallbacks") { try await sidecarRuntimeSelectorPersistsAndFallbacks() }
        await runCheck("sidecarRuntimeCoordinatorResolvesHealthAndSelection") { try await sidecarRuntimeCoordinatorResolvesHealthAndSelection() }
        await runCheck("runReplayLoadsTimelineFromRunDirectory") { try await runReplayLoadsTimelineFromRunDirectory() }
        await runCheck("debugBundleManifestAndZipExcludeSecrets") { try await debugBundleManifestAndZipExcludeSecrets() }
        await runCheck("runtimeEventEnvelopeSequencesAreStableAndDeduplicated") { try await runtimeEventEnvelopeSequencesAreStableAndDeduplicated() }
        await runCheck("runtimeEventEnvelopeUsesExternalTaggedUnion") { try runtimeEventEnvelopeUsesExternalTaggedUnion() }
        await runCheck("p32LegacyPendingCheckpointMigratesToRunDirectory") { try await p32LegacyPendingCheckpointMigratesToRunDirectory() }
        await runCheck("agentSkillRuntimeResolutionEnforcesTrustAndToolBounds") { try await agentSkillRuntimeResolutionEnforcesTrustAndToolBounds() }
    }

    func workspacePreferencesDefaultRuntimeIsStableSwiftLoop() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("DefaultRuntimeWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let preferences = try await repository.load(in: workspace)
        let preferencesContents = try String(contentsOf: workspace.workspacePreferencesURL, encoding: .utf8)

        try expect(preferences.agentRuntimeSelection == .swiftLoop, "New workspaces should default the agent runtime selector to Swift Loop.")
        try expect(preferences.agentRuntimeSelection.effectiveRuntime(sidecarAvailable: true) == .swiftLoop, "Default Swift Loop selection should not auto-attempt Sidecar when it is healthy.")
        try expect(preferencesContents.contains("agent_runtime_selection: \"swift_loop\""), "Seeded workspace preferences should persist swift_loop as the runtime default.")
        try expect(!preferencesContents.contains("agent_runtime_selection: \"auto_fallback\""), "Seeded workspace preferences should not default to experimental Auto runtime.")
    }

    func workspacePreferencesRuntimeSelectionFallbacksToSwiftLoop() async throws {
        let repository = WorkspacePreferencesRepository()
        let rootURL = temporaryDirectoryURL().appendingPathComponent("RuntimeFallbackPreferencesWorkspace", isDirectory: true)
        let workspace = ResearchWorkspace(rootURL: rootURL)
        let preferencesURL = workspace.fileURL(for: WorkspacePreferencesRepository.relativePath)

        defer {
            try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent())
        }

        try FileManager.default.createDirectory(at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        schema_version: 2
        library_visible_columns:
          - "title"
        agent_runtime_selection: "unknown_runtime"
        """.write(to: preferencesURL, atomically: true, encoding: .utf8)

        let invalidRuntimePreferences = try await repository.load(in: workspace)
        try expect(invalidRuntimePreferences.agentRuntimeSelection == .swiftLoop, "Invalid runtime selections should fall back to stable Swift Loop.")

        try """
        schema_version: 2
        library_visible_columns:
          - "title"
        """.write(to: preferencesURL, atomically: true, encoding: .utf8)

        let missingRuntimePreferences = try await repository.load(in: workspace)
        try expect(missingRuntimePreferences.agentRuntimeSelection == .swiftLoop, "Missing runtime selections should fall back to stable Swift Loop.")

        var explicitAuto = WorkspacePreferences(agentRuntimeSelection: .autoFallback)
        explicitAuto.isSidecarDisabledForWorkspace = false
        try await repository.save(explicitAuto, in: workspace)
        let loadedAuto = try await repository.load(in: workspace)
        try expect(loadedAuto.agentRuntimeSelection == .autoFallback, "Explicit Auto runtime selections should still round-trip.")
        try expect(loadedAuto.agentRuntimeSelection.effectiveRuntime(sidecarAvailable: true) == .langGraphSidecar, "Explicit Auto should still use Sidecar when health is ready.")
    }

    func swiftUIRuntimeWarningCaptureFormatsOneLinePerEntry() throws {
        let date = Date(timeIntervalSince1970: 1_777_700_000)
        let line = SwiftUIRuntimeWarningCapture.formatLine(
            timestamp: date,
            subsystem: "com.apple.runtime-issues",
            category: "SwiftUI",
            process: "Sci-Station",
            message: "Modifying state during view update."
        )
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
        try expect(
            fields.count == 5,
            "SwiftUIRuntimeWarningCapture.formatLine should emit 5 tab-separated fields, got \(fields.count) in '\(line)'."
        )
        try expect(
            String(fields[1]) == "com.apple.runtime-issues",
            "Second field should be the subsystem."
        )
        try expect(
            String(fields[2]) == "SwiftUI",
            "Third field should be the category."
        )
        try expect(
            String(fields[3]) == "Sci-Station",
            "Fourth field should be the process."
        )
        try expect(
            String(fields[4]) == "Modifying state during view update.",
            "Fifth field should be the message."
        )
    }

    /// Embedded newlines / tabs in OS log messages would break the
    /// one-record-per-line invariant. The formatter must collapse them.

    func swiftUIRuntimeWarningCaptureSanitisesEmbeddedSeparators() throws {
        let date = Date(timeIntervalSince1970: 1_777_700_001)
        let line = SwiftUIRuntimeWarningCapture.formatLine(
            timestamp: date,
            subsystem: "com.apple.runtime-issues",
            category: "SwiftUI",
            process: "Sci-Station",
            message: "first line\nsecond line\twith tab\rand cr"
        )
        try expect(
            !line.contains("\n"),
            "Formatter must strip embedded newlines."
        )
        try expect(
            line.split(separator: "\t", omittingEmptySubsequences: false).count == 5,
            "Tab count must stay at 4 separators (5 fields) after sanitisation."
        )
        try expect(
            !line.contains("\r"),
            "Formatter must strip embedded carriage returns."
        )
    }

    func pdfAnnotationStoreRoundTripsSidecar() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let paperRepository = PaperRepository()
        let store = PDFAnnotationStore()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PDFAnnotationsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "pdf-sidecar-paper"), in: workspace)
        let annotation = PDFAnnotationRecord(
            id: "mark-1",
            paperID: paper.id,
            pageIndex: 2,
            kind: .highlight,
            bounds: [PDFAnnotationBounds(pageIndex: 2, x: 10, y: 20, width: 120, height: 18)],
            selectedTextPreview: "Important result",
            noteText: nil,
            colorHex: "#F7D154",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        try await store.saveAnnotations([annotation], for: paper, in: workspace)
        let loaded = try await store.loadAnnotations(for: paper, in: workspace)
        let sidecarPath = try await store.sidecarRelativePath(for: paper, in: workspace)

        try expect(loaded == [annotation], "PDFAnnotationStore should round-trip sidecar records.")
        try expect(sidecarPath.hasSuffix("pdf_annotations.json"), "PDFAnnotationStore should write the expected sidecar filename.")
    }

    func pdfAnnotationStoreHandlesMissingSidecar() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: WorkspaceBookmarkStore(defaults: defaults))
        let paperRepository = PaperRepository()
        let store = PDFAnnotationStore()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PDFMissingSidecarWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "missing-sidecar-paper"), in: workspace)
        let loaded = try await store.loadAnnotations(for: paper, in: workspace)

        try expect(loaded.isEmpty, "PDFAnnotationStore should treat a missing sidecar as an empty migration state.")
    }

            func agentInteractionModeRuntimePolicyMatchesVisibleModes() throws {
                try expect(AgentInteractionMode.conversation.usesToolLoopRuntime, "Visible Plan should keep the tool-loop runtime for read-only research answers.")
                try expect(AgentInteractionMode.assistant.usesToolLoopRuntime, "Visible Agent should execute read-only tools and pause only for approval-requiring writes.")
                try expect(!AgentInteractionMode.plan.usesToolLoopRuntime, "Legacy Plan mode should remain planner-only.")
            }

    func externalAgentRuntimeStreamsLegacyLoopEvents() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LegacyRuntimeEventWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-runtime-read", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Runtime final."))
        ])
        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let registry = AgentToolRegistry(tools: [
            RecordingAgentTool(definition: definition, results: [
                AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Runtime evidence")
            ])
        ])
        let runtime = LegacySwiftAgentRuntime()
        let stream = try await runtime.startRun(AgentRuntimeRequest(
            runID: "legacy-runtime-run",
            goal: "Runtime test goal",
            initialMessages: [LLMChatMessage(role: .user, content: "Read context")],
            provider: provider,
            toolDefinitions: [definition],
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        ))

        var envelopes: [AgentRuntimeEventEnvelope] = []
        for try await envelope in stream {
            envelopes.append(envelope)
        }
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "legacy-runtime-run", in: fixture.root)

        try expect(envelopes.contains { if case .runStarted = $0.event { return true }; return false }, "Legacy runtime should stream runStarted.")
        try expect(envelopes.contains { if case .toolCallRequested = $0.event { return true }; return false }, "Legacy runtime should map loop tool calls to runtime events.")
        try expect(envelopes.contains { if case .toolCallCompleted = $0.event { return true }; return false }, "Legacy runtime should map stable tool results to runtime events.")
        try expect(envelopes.contains { if case .finalResponse = $0.event { return true }; return false }, "Legacy runtime should stream finalResponse.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "Persisted runtime events should use stable per-run host sequence.")
    }

    func fakeExternalRuntimeDrivesAITimelineEvents() async throws {
        let fixture = try await loopWorkspaceFixture(named: "FakeRuntimeTimelineWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = FakeExternalAgentRuntime(scriptedEvents: [
            .runStarted(AgentRunStarted(goal: "Fake timeline")),
            .approvalRequired(AgentApprovalRequest(runID: "fake-runtime-run", toolCallID: "fake-write", toolName: "write_markdown_plan", permissionKey: AgentToolRisk.writesWorkspace.defaultPermissionKey, risk: .writesWorkspace, argumentsJSON: "{}", targetPaths: ["wiki/plans/fake.md"])),
            .finalResponse(AgentFinalResponse(markdown: "Fake done."))
        ])
        let provider = ScriptedChatProvider(responses: [])
        let request = AgentRuntimeRequest(
            runID: "fake-runtime-run",
            goal: "Fake timeline",
            initialMessages: [],
            provider: provider,
            toolDefinitions: [],
            toolRegistry: AgentToolRegistry(tools: []),
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )

        let stream = try await runtime.startRun(request)
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }

        try expect(events.contains { if case .approvalRequired = $0 { return true }; return false }, "Fake runtime should be able to drive approval timeline state.")
        try expect(events.contains { if case .finalResponse = $0 { return true }; return false }, "Fake runtime should be able to drive final response timeline state.")
    }

    func langGraphRuntimePerformsInitializeHandshake() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphHandshakeWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "run_success_paper_reading.jsonl")
        let request = sidecarRuntimeRequest(runID: "langgraph-handshake-run", fixture: fixture)
        let stream = try await runtime.startRun(request)
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }

        try expect(events.count >= 4, "LangGraph sidecar handshake should allow the run to emit lifecycle and runtime events.")
        try expect(events.contains { if case .sidecarStarting = $0 { return true }; return false }, "LangGraph runtime should emit sidecarStarting before initialize.")
        try expect(events.contains { if case .sidecarReady = $0 { return true }; return false }, "LangGraph runtime should emit sidecarReady after initialize/health.")
    }

    func langGraphRuntimeReplaysGoldenFixtureRunSuccess() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphGoldenSuccessWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "run_success_paper_reading.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-success-run", goal: "精读 demo paper", fixture: fixture))
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-success-run", in: fixture.root)

        try expect(events.contains { if case .runStarted = $0 { return true }; return false }, "Golden fixture should replay runStarted.")
        try expect(events.contains { if case .toolCallRequested = $0 { return true }; return false }, "Golden fixture should replay tool_call_requested.")
        try expect(events.contains { if case .artifactDraft = $0 { return true }; return false }, "Golden fixture should replay artifact_draft. Saw: \(events.map(runtimeEventLabel).joined(separator: ", "))")
        try expect(events.contains { if case .finalResponse = $0 { return true }; return false }, "Golden fixture should replay final_response.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "LangGraph runtime should persist host-canonical sequences for golden fixture replay.")
    }

    func langGraphRuntimeReplaysGoldenFixtureApprovalResume() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphApprovalResumeWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "write_markdown_plan", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "write_markdown_plan", succeeded: true, message: "Swift wrote the paper note once.", modifiedPaths: ["wiki/papers/demo-paper.md"])
        ])
        let runtime = sidecarRuntime(fixtureName: "run_approval_then_resume.jsonl")
        let request = sidecarRuntimeRequest(
            runID: "langgraph-approval-run",
            fixture: fixture,
            definitions: [definition],
            registry: AgentToolRegistry(tools: [tool])
        )
        let stream = try await runtime.startRun(request)
        var startEvents: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            startEvents.append(envelope.event)
        }

        let pending = try await AgentRunDirectoryStore().pending(runID: "langgraph-approval-run", in: fixture.root)
        try expect(startEvents.contains { if case .approvalRequired = $0 { return true }; return false }, "Approval fixture should pause with approvalRequired. Saw: \(startEvents.map(runtimeEventLabel).joined(separator: ", "))")
        try expect(pending?.approvalRequest.id == "approval-demo-write", "LangGraph runtime should persist sidecar approval as a run-directory checkpoint.")

        try await runtime.resumeRun(runID: "langgraph-approval-run", decision: AgentHumanDecision(action: .allowOnce))
        let invocationCount = await tool.invocationCount()
        let records = try await AgentRunDirectoryStore().toolCallRecords(runID: "langgraph-approval-run", in: fixture.root)
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-approval-run", in: fixture.root)

        try expect(invocationCount == 1, "Allow once should execute the Swift-owned write exactly once.")
        try expect(records.contains { $0.status == .completed && $0.toolCallID == "call-write-note" }, "Approved sidecar write should be recorded in the persistent ledger.")
        try expect(persisted.contains { if case .finalResponse = $0.event { return true }; return false }, "agent.resume should persist the fixture final response.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "Approval/resume fixture should keep host-canonical sequences after resume.")
    }

    func langGraphRuntimeRejectsInvalidFixtureSchemaVersion() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphInvalidSchemaWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "invalid_schema_version.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-invalid-schema-run", fixture: fixture))
        do {
            for try await _ in stream {}
            throw ValidationError(message: "Invalid sidecar event schema version should fail the runtime stream.")
        } catch let error as SidecarJSONRPCError {
            try expect(error.message.contains("schema version"), "Invalid schema version should report a schema error.")
        }
    }

    func langGraphRuntimeCanonicalizesSidecarLocalSequence() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphSequenceWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "run_success_paper_reading.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-sequence-run", fixture: fixture))
        for try await _ in stream {}
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-sequence-run", in: fixture.root)
        let eventIDs = persisted.map(\.id)

        try expect(eventIDs.contains("evt-fixture-success-node-load"), "Sequence test should include fixture events with intentionally shuffled local sequences.")
        try expect(persisted.map(\.sequence) == Array(1...persisted.count), "Swift host should canonicalize sidecar local sequences to a stable per-run sequence.")
    }

    func langGraphRuntimeFallsBackWhenInitializeTimesOut() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphTimeoutWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "handshake_timeout.jsonl", handshakeTimeout: 0.2)
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-timeout-run", fixture: fixture))
        var events: [AgentRuntimeEvent] = []
        for try await envelope in stream {
            events.append(envelope.event)
        }

        try expect(events.count == 3, "Handshake timeout without fallback runtime should emit only fixed lifecycle fallback events.")
        try expect(events[0].isSidecarStarting, "Handshake timeout should start with sidecarStarting.")
        try expect(events[1].isSidecarUnavailable, "Handshake timeout should emit sidecarUnavailable.")
        try expect(events[2].isFallbackToLegacyRuntime, "Handshake timeout should emit fallbackToLegacyRuntime.")
    }

    func langGraphRuntimeDoesNotLoseApprovalWhenSidecarCrashes() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LangGraphCrashApprovalWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let runtime = sidecarRuntime(fixtureName: "sidecar_crash_after_approval.jsonl")
        let stream = try await runtime.startRun(sidecarRuntimeRequest(runID: "langgraph-crash-run", fixture: fixture))
        for try await _ in stream {}
        let pending = try await AgentRunDirectoryStore().pending(runID: "langgraph-crash-run", in: fixture.root)
        let persisted = try await AgentRunDirectoryStore().eventEnvelopes(runID: "langgraph-crash-run", in: fixture.root)

        try expect(pending?.approvalRequest.id == "approval-crash-write", "Sidecar crash after approval should not lose the pending approval checkpoint.")
        try expect(persisted.contains { if case .checkpointSaved = $0.event { return true }; return false }, "Crash fixture should persist checkpointSaved before the crash.")
    }

    func sidecarConnectionBrokenPipeThrowsInsteadOfTerminatingHost() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec 0<&-; exit 0"]

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
        // The parent must release its copy of the read end; otherwise the
        // pipe still has a reader even after the child closes stdin.
        try inputPipe.fileHandleForReading.close()
        process.waitUntilExit()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            try? inputPipe.fileHandleForWriting.close()
            try? inputPipe.fileHandleForReading.close()
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }

        do {
            _ = try await connection.sendRequest(method: "sidecar.initialize", params: .object([:]), timeout: 1)
            throw ValidationError(message: "Broken sidecar stdin should throw instead of returning a response.")
        } catch let error as SidecarJSONRPCError {
            try expect(error.code == -32001, "Broken sidecar stdin should surface as a sidecar process error, got \(error.code): \(error.message)")
        }
    }

    func sidecarLLMProxyDisablesProviderNativeToolCalling() async throws {
        let fixture = try await loopWorkspaceFixture(named: "SidecarLLMProxyWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "LLM proxy response."))
        ])
        let request = AgentRuntimeRequest(
            runID: "llm-proxy-run",
            goal: "LLM proxy",
            initialMessages: [],
            provider: provider,
            toolDefinitions: [],
            toolRegistry: AgentToolRegistry(tools: []),
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )
        let sidecarRequest = SidecarLLMRespondRequest(
            messages: [LLMChatMessage(role: .user, content: "Summarize.")],
            tools: [LLMToolSpecification(name: "read_note", description: "Read", inputSchemaJSON: "{}")],
            toolCallPolicy: .disabled,
            modelOptions: ["temperature": .number("0.1")]
        )
        _ = try await SidecarLLMProxy().respond(params: try SidecarJSONCodec.jsonValue(from: sidecarRequest), runtimeRequest: request)
        let recorded = await provider.recordedRequests()

        try expect(recorded.count == 1, "LLMProxy should call the Swift provider once.")
        try expect(recorded.first?.tools.isEmpty == true, "toolCallPolicy disabled should strip provider-native tool specifications.")
    }

    func sidecarEmbeddingProxyRejectsSensitiveConfigAndReturnsVectors() async throws {
        let fixture = try await loopWorkspaceFixture(named: "SidecarEmbeddingProxyWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let request = AgentRuntimeRequest(
            runID: "embedding-proxy-run",
            goal: "Embedding proxy",
            initialMessages: [],
            provider: ScriptedChatProvider(responses: []),
            toolDefinitions: [],
            toolRegistry: AgentToolRegistry(tools: []),
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )
        let embeddingRequest = SidecarEmbeddingRequest(texts: ["retrieval evidence chunk"], modelRequestID: "req-1")
        let responseValue = try await SidecarEmbeddingProxy().embed(params: try SidecarJSONCodec.jsonValue(from: embeddingRequest), runtimeRequest: request)
        let responseObject = try jsonObject(responseValue, "Embedding proxy should return an object response.")
        let vectors = try jsonArray(responseObject["vectors"], "Embedding proxy should return vectors.")
        let metadata = try jsonObject(responseObject["redacted_metadata"], "Embedding proxy should return redacted metadata.")

        try expect(vectors.count == 1, "Embedding proxy should return one vector per input text.")
        try expect(metadata["redacted"] == .string("true"), "Embedding proxy metadata should be explicitly redacted.")
        do {
            let unsafeRequest = SidecarEmbeddingRequest(texts: ["secret-free text"], modelOptions: ["apiKey": .string("sk-secret")])
            _ = try await SidecarEmbeddingProxy().embed(params: try SidecarJSONCodec.jsonValue(from: unsafeRequest), runtimeRequest: request)
            throw ValidationError(message: "Embedding proxy should reject sensitive provider config keys.")
        } catch let error as SidecarJSONRPCError {
            try expect(error.message.contains("sensitive key"), "Sensitive embedding config should be rejected by contract.")
        }
    }

    func sidecarRuntimeSelectorPersistsAndFallbacks() async throws {
        let fixture = try await loopWorkspaceFixture(named: "RuntimeSelectorWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let repository = WorkspacePreferencesRepository()
        let preferences = WorkspacePreferences(agentRuntimeSelection: .langGraphSidecar)
        try await repository.save(preferences, in: fixture.workspace)
        let loaded = try await repository.load(in: fixture.workspace)

        try expect(loaded.agentRuntimeSelection == .langGraphSidecar, "Workspace preferences should persist the sidecar runtime selector.")
        try expect(loaded.agentRuntimeSelection.effectiveRuntime(sidecarAvailable: false) == .swiftLoop, "Sidecar selection should fall back to Swift Loop when health is unavailable.")
        try expect(loaded.agentRuntimeSelection.fallbackReason(sidecarAvailable: false) != nil, "Fallback should explain why Swift Loop is active.")
    }

    func sidecarRuntimeCoordinatorResolvesHealthAndSelection() async throws {
        let fixture = try await loopWorkspaceFixture(named: "RuntimeCoordinatorWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let coordinator = sidecarCoordinator(fixtureName: "run_success_paper_reading.jsonl")
        defer { Task { await coordinator.stop() } }
        let unavailableCoordinator = sidecarCoordinator(fixtureName: "handshake_timeout.jsonl", handshakeTimeout: 0.2)
        defer { Task { await unavailableCoordinator.stop() } }

        let auto = await coordinator.resolve(selection: .autoFallback, sidecarDisabled: false, root: fixture.root)
        let forcedSwift = await coordinator.resolve(selection: .swiftLoop, sidecarDisabled: false, root: fixture.root)
        let disabled = await coordinator.resolve(selection: .langGraphSidecar, sidecarDisabled: true, root: fixture.root)
        let unavailable = await unavailableCoordinator.resolve(selection: .autoFallback, sidecarDisabled: false, root: fixture.root)

        try expect(auto.health.status == "ready", "Coordinator should start and read sidecar health for auto fallback.")
        try expect(auto.effectiveRuntime == .langGraphSidecar && auto.shouldAttemptSidecar, "Auto fallback should use sidecar when health is ready.")
        try expect(forcedSwift.effectiveRuntime == .swiftLoop && !forcedSwift.shouldAttemptSidecar, "Swift Loop selection should not attempt sidecar.")
        try expect(disabled.effectiveRuntime == .swiftLoop && disabled.fallbackReason != nil, "Workspace sidecar disable should force Swift Loop with a reason.")
        try expect(unavailable.effectiveRuntime == .swiftLoop && !unavailable.shouldAttemptSidecar, "Unavailable sidecar should not block Swift Loop fallback.")
        try expect(unavailable.fallbackReason?.contains("Swift Loop") == true || unavailable.health.fallbackReason != nil, "Unavailable sidecar fallback should be visible in diagnostics.")
    }

    func runReplayLoadsTimelineFromRunDirectory() async throws {
        let fixture = try await loopWorkspaceFixture(named: "RunReplayWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let store = AgentRunDirectoryStore()
        let first = AgentRuntimeEventEnvelope(id: "evt-replay-1", runID: "replay-run", sequence: 1, event: .runStarted(AgentRunStarted(goal: "Replay")))
        let second = AgentRuntimeEventEnvelope(id: "evt-replay-2", runID: "replay-run", sequence: 2, event: .finalResponse(AgentFinalResponse(markdown: "Done")))
        try await store.appendEvent(first, in: fixture.root)
        try await store.appendEvent(second, in: fixture.root)
        try await store.saveCriticReport(.object(["can_request_approval": .bool(true)]), runID: "replay-run", in: fixture.root)
        try await store.saveRetrievalTrace(.object(["path": .string("FTS")]), runID: "replay-run", in: fixture.root)
        let replay = try await store.saveReplay(runID: "replay-run", in: fixture.root, debugPromptResponse: .object(["api_key": .string("sk-secret"), "prompt": .string("read /private/tmp/paper.md")]))
        let loaded = try await store.runReplay(runID: "replay-run", in: fixture.root)
        let manifest = try await store.saveDebugBundleManifest(runID: "replay-run", in: fixture.root)

        try expect(replay.events.map(\.id) == ["evt-replay-1", "evt-replay-2"], "Replay should preserve persisted runtime timeline events.")
        try expect(loaded.events.count == 2, "Replay should reload from replay.json.")
        try expect(manifest.includedFiles.contains("critic_report.json"), "Debug manifest should include critic reports when present.")
        if case let .object(debug) = replay.debugPromptResponse {
            try expect(debug["api_key"] == .string("[REDACTED]"), "Replay debug payload should redact API keys.")
            try expect(debug["prompt"] == .string("read [PATH]"), "Replay debug payload should redact private paths.")
        } else {
            throw ValidationError(message: "Replay should keep a redacted debug payload when explicitly requested.")
        }
    }

    func debugBundleManifestAndZipExcludeSecrets() async throws {
        let fixture = try await loopWorkspaceFixture(named: "DebugBundleWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let store = AgentRunDirectoryStore()
        try await store.appendEvent(
            AgentRuntimeEventEnvelope(id: "evt-secret", runID: "debug-run", sequence: 1, event: .finalResponse(AgentFinalResponse(markdown: "Token sk-secret should be redacted."))),
            in: fixture.root
        )
        try await store.saveCriticReport(.object(["api_key": .string("sk-secret")]), runID: "debug-run", in: fixture.root)
        try await store.saveRetrievalTrace(.object(["source": .string("/private/tmp/source.md")]), runID: "debug-run", in: fixture.root)
        _ = try await store.saveReplay(runID: "debug-run", in: fixture.root, debugPromptResponse: .object(["token": .string("sk-secret")]))
        let preview = try await store.debugBundlePreview(runID: "debug-run", in: fixture.root)
        let zipURL = try await store.saveDebugBundle(runID: "debug-run", in: fixture.root)
        let zipData = try Data(contentsOf: zipURL)
        let zipText = String(data: zipData, encoding: .utf8) ?? ""
        let manifest = try await store.saveDebugBundleManifest(runID: "debug-run", in: fixture.root)

        try expect(preview.includedFiles.contains("events.jsonl"), "Debug preview should list included run files before export.")
        try expect(manifest.redactionPolicy.contains("prompt/response"), "Debug manifest should record the redaction policy.")
        try expect(manifest.excludedPatterns.contains(".sci-station/index/embeddings/**"), "Debug manifest should exclude embedding index files by default.")
        try expect(FileManager.default.fileExists(atPath: zipURL.path), "Debug bundle should be a real zip file on disk.")
        try expect(!zipText.contains("sk-secret"), "Debug bundle zip should not contain raw API keys or tokens.")
        try expect(!zipText.contains("/private/tmp"), "Debug bundle zip should not contain private path inventory.")
    }

    func runtimeEventEnvelopeSequencesAreStableAndDeduplicated() async throws {
        let fixture = try await loopWorkspaceFixture(named: "RuntimeEventDedupeWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let store = AgentRunDirectoryStore()
        let first = AgentRuntimeEventEnvelope(id: "evt-dedupe", runID: "dedupe-run", sequence: 1, event: .runStarted(AgentRunStarted(goal: "Deduplicate")))
        let duplicate = AgentRuntimeEventEnvelope(id: "evt-dedupe", runID: "dedupe-run", sequence: 99, event: .runStarted(AgentRunStarted(goal: "Duplicate")))
        let second = AgentRuntimeEventEnvelope(id: "evt-dedupe-2", runID: "dedupe-run", sequence: 2, event: .finalResponse(AgentFinalResponse(markdown: "Done")))

        try await store.appendEvent(first, in: fixture.root)
        try await store.appendEvent(duplicate, in: fixture.root)
        try await store.appendEvent(second, in: fixture.root)
        let events = try await store.eventEnvelopes(runID: "dedupe-run", in: fixture.root)
        let nextSequence = try await store.nextSequence(runID: "dedupe-run", in: fixture.root)

        try expect(events.map(\.id) == ["evt-dedupe", "evt-dedupe-2"], "Run directory should ignore duplicate runtime event ids.")
        try expect(events.map(\.sequence) == [1, 2], "Deduplicated events should preserve committed host sequence.")
        try expect(nextSequence == 3, "nextSequence should continue after the latest committed event.")
    }

    func runtimeEventEnvelopeUsesExternalTaggedUnion() throws {
        let result = AgentToolResult(callID: "call-runtime", toolName: "read_note", succeeded: true, message: "Runtime evidence")
        let wireResult = AgentToolResultWireFormat(result: result, toolCallID: "call-runtime")
        let envelope = AgentRuntimeEventEnvelope(
            id: "evt-runtime",
            runID: "run-runtime",
            sequence: 7,
            timestamp: Date(timeIntervalSince1970: 0),
            event: .toolCallCompleted(AgentToolCallCompleted(tool: "read_note", toolCallID: "call-runtime", result: wireResult))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        let encoded = String(data: data, encoding: .utf8) ?? ""
        let decoded = try AgentRunDirectoryStore.decoder().decode(AgentRuntimeEventEnvelope.self, from: data)

        try expect(encoded.contains(#""type":"tool_call_completed""#), "Runtime events should encode as event.type.")
        try expect(encoded.contains(#""payload""#), "Runtime events should encode payload alongside type.")
        if case let .toolCallCompleted(payload) = decoded.event {
            try expect(payload.result.schemaVersion == 1, "Decoded tool completion event should preserve the V1 tool result.")
        } else {
            throw ValidationError(message: "Decoded runtime event should be toolCallCompleted.")
        }
    }

    func p32LegacyPendingCheckpointMigratesToRunDirectory() async throws {
        let fixture = try await loopWorkspaceFixture(named: "LegacyPendingMigrationWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "legacy-call", toolName: "write_note", argumentsJSON: #"{"path":"wiki/legacy.md"}"#)
        let approval = AgentApprovalRequest(
            runID: "legacy-run",
            toolCallID: call.id,
            toolName: call.toolName,
            permissionKey: AgentToolRisk.writesWorkspace.defaultPermissionKey,
            risk: .writesWorkspace,
            argumentsJSON: call.argumentsJSON,
            targetPaths: ["wiki/legacy.md"]
        )
        let pending = AgentPendingToolCall(
            runID: "legacy-run",
            stepIndex: 3,
            toolCall: call,
            approvalRequest: approval,
            messagesBeforePause: [LLMChatMessage(role: .user, content: "Legacy pending")]
        )
        let checkpointStore = AgentLoopCheckpointStore()
        try await checkpointStore.saveLegacyFallback(pending, in: fixture.root)

        let migrated = try await checkpointStore.pending(runID: "legacy-run", in: fixture.root)
        let runDirectoryPending = try await AgentRunDirectoryStore().pending(runID: "legacy-run", in: fixture.root)

        try expect(migrated?.toolCall.id == "legacy-call", "Legacy pending call should remain readable.")
        try expect(runDirectoryPending?.toolCall.id == "legacy-call", "Reading legacy pending call should migrate it into the run directory checkpoint.")
    }

    func agentSkillRuntimeResolutionEnforcesTrustAndToolBounds() async throws {
        let rootURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let bundledDirectory = rootURL.appendingPathComponent(
            ".sci-ai/sci-station/presets/research-core/skills",
            isDirectory: true
        )
        let workspaceDirectory = rootURL.appendingPathComponent(".claude/skills/workspace-review", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: bounded-review
        description: Paper evidence review
        version: 1.0.0
        capabilities: [paper, review]
        risk: readOnly
        allowed_tools: [list_papers, read_paper, create_todo]
        ---

        Use the bundled evidence checklist.
        """.write(
            to: bundledDirectory.appendingPathComponent("bounded-review.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        ---
        name: workspace-review
        description: Workspace evidence review
        version: 1.0.0
        capabilities: [workspace, review]
        risk: writesWorkspace
        allowed_tools: [write_wiki_markdown]
        ---

        Use the workspace-only review instructions.
        """.write(
            to: workspaceDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let loader = AgentSkillLoader()
        let profile = AgentWorkspaceProfile(skillToggles: [
            AgentSkillToggle(
                skillID: "bounded-review",
                isEnabled: true,
                trustLevel: .trusted,
                allowedToolIDs: ["list_papers", "read_paper_section"]
            ),
            AgentSkillToggle(
                skillID: "workspace-review",
                isEnabled: true,
                trustLevel: .untrusted,
                allowedToolIDs: ["write_wiki_markdown"]
            ),
            AgentSkillToggle(skillID: "disabled-review", isEnabled: false, trustLevel: .trusted)
        ])
        let resolution = try await loader.resolve(
            for: "Please perform a paper evidence review.",
            profile: profile,
            workspaceRoot: rootURL
        )

        try expect(resolution.selectedSkillIDs == ["bounded-review"], "Only enabled, matching, trusted skills should be selected.")
        try expect(resolution.allowedToolNames == Set(["list_papers"]), "Skill metadata and profile tool allowlists should intersect.")
        try expect(resolution.blockedSkillReasons["workspace-review"]?.contains("untrusted") == true, "Untrusted workspace skills should be blocked before body loading.")
        try expect(resolution.promptContext?.contains("Use the bundled evidence checklist.") == true, "Selected skill instructions should enter the runtime prompt context.")
        try expect(resolution.promptContext?.contains("workspace-only") == false, "Blocked skill bodies must not enter the prompt context.")
        try expect(
            resolution.restricting(["list_papers", "create_todo"]) == Set(["list_papers"]),
            "Skills may narrow but must not expand the caller's enabled tool set."
        )

        let emptyIntersectionResolution = try await loader.resolve(
            for: "Please perform a paper evidence review.",
            profile: AgentWorkspaceProfile(skillToggles: [
                AgentSkillToggle(
                    skillID: "bounded-review",
                    isEnabled: true,
                    trustLevel: .trusted,
                    allowedToolIDs: ["write_wiki_markdown"]
                )
            ]),
            workspaceRoot: rootURL
        )
        try expect(
            emptyIntersectionResolution.allowedToolNames == Set<String>(),
            "A disjoint skill/profile tool intersection should disable all tools instead of removing the restriction."
        )

        let trustedWorkspaceResolution = try await loader.resolve(
            for: "Run a workspace evidence review.",
            profile: AgentWorkspaceProfile(skillToggles: [
                AgentSkillToggle(
                    skillID: "workspace-review",
                    isEnabled: true,
                    trustLevel: .trusted,
                    allowedToolIDs: ["write_wiki_markdown"]
                )
            ]),
            workspaceRoot: rootURL
        )
        try expect(trustedWorkspaceResolution.selectedSkillIDs == ["workspace-review"], "Explicit trust should allow a matching workspace skill to load.")
    }
}
