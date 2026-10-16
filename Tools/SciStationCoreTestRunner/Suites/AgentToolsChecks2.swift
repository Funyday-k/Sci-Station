import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
            func agentThreadRepositoryArchivesAndReadsLegacyThreads() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let suiteRoot = temporaryDirectoryURL().appendingPathComponent("AgentArchivedThreadSuite", isDirectory: true)
                let workspaceRoot = suiteRoot.appendingPathComponent("AgentArchivedThreadWorkspace", isDirectory: true)
                let storeDirectory = suiteRoot.appendingPathComponent("GlobalAgentStore", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: suiteRoot)
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let threadsURL = root.fileURL(for: AgentThreadRepository.legacyRelativePath)
                let legacyLine = """
                {"created_at":"2026-04-29T00:00:00Z","id":"legacy-thread","project_id":"project-alpha","run_ids":["run-1"],"title":"Legacy thread","updated_at":"2026-04-29T00:00:01Z"}
                """
                try legacyLine.write(to: threadsURL, atomically: true, encoding: .utf8)

                let repository = AgentThreadRepository(storeDirectory: storeDirectory)
                let legacyThreads = try await repository.threads(in: root, projectID: "project-alpha")
                var archivedThread = try require(legacyThreads.first, "Legacy thread without archived_at should still decode.")
                archivedThread.archive(at: Date(timeIntervalSince1970: 1_777_600_100))
                try await repository.upsert(archivedThread, in: root)

                let activeThreads = try await repository.threads(in: root, projectID: "project-alpha")
                let allThreads = try await repository.allThreads(in: root)

                try expect(activeThreads.isEmpty, "Archived threads should be hidden from the default active thread list.")
                try expect(allThreads.map(\.id).contains("legacy-thread"), "Archived threads should remain readable from all thread history.")
            }

            func agentPaperIntentRouterMapsThirdPaperOrdinal() throws {
                let router = AgentPaperIntentRouter()
                let chineseIntent = router.classify("第三篇文章的摘要是什么？")
                let digitIntent = router.classify("第 3 篇论文的蒸发率公式是什么？")
                let englishIntent = router.classify("What is the abstract of the third paper?")
                let argumentsJSON = router.searchArgumentsJSON(for: digitIntent, paperID: "garani-paper")

                try expect(chineseIntent.kind == .sectionSummary, "Chinese third-paper abstract questions should be routed as section summaries.")
                try expect(chineseIntent.ordinalIndex == 2, "Chinese third-paper references should map to ordinal index 2.")
                try expect(digitIntent.kind == .formula, "Digit third-paper formula questions should route to formula evidence.")
                try expect(digitIntent.ordinalIndex == 2, "Digit third-paper references should map to ordinal index 2.")
                try expect(englishIntent.ordinalIndex == 2, "English third-paper references should map to ordinal index 2.")
                try expect(argumentsJSON.contains("garani-paper"), "Third-paper search arguments should be restricted to the resolved paper id.")
                try expect(!argumentsJSON.contains("第 3 篇"), "Ordinal phrases should be removed from retrieval queries.")
            }

            func agentToolDefinitionsExposePlatformMetadata() throws {
                let readDefinition = AgentToolDefinition(
                    name: "read_context",
                    summary: "Read current workspace context.",
                    inputSchema: "{}",
                    risk: .readOnly
                )
                let writeDefinition = AgentToolDefinition(
                    name: "write_note",
                    displayName: "Write Note",
                    summary: "Write a note into the workspace.",
                    inputSchema: "{\"path\":\"string\"}",
                    inputSchemaVersion: 2,
                    risk: .writesWorkspace,
                    outputPolicy: AgentToolOutputPolicy(maxCharacters: 500, includeAttachments: true)
                )

                let encoded = try JSONEncoder().encode(writeDefinition)
                let decoded = try JSONDecoder().decode(AgentToolDefinition.self, from: encoded)

                try expect(readDefinition.permissionKey == "tool.read", "Read-only tools should default to the read permission key.")
                try expect(!readDefinition.requiresConfirmation, "Read-only tools should not require confirmation by default.")
                try expect(writeDefinition.identifier == "write_note", "Tool definitions should expose a stable identifier.")
                try expect(writeDefinition.permissionKey == "tool.write_workspace", "Workspace-writing tools should expose a write permission key.")
                try expect(writeDefinition.requiresConfirmation, "Workspace-writing tools should require confirmation by default.")
                try expect(decoded.inputSchemaVersion == 2, "Tool definition schema version should round-trip.")
                try expect(decoded.outputPolicy.maxCharacters == 500, "Tool output policy should round-trip.")
            }

            func agentPermissionRulesEvaluateSafetyDecisions() throws {
                let evaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules())

                let destructive = evaluator.evaluate(
                    AgentPermissionRequest(command: "rm -rf .derivedData", risk: .externalSideEffect)
                )
                let sensitivePath = evaluator.evaluate(
                    AgentPermissionRequest(path: "settings/private_api_token.yaml", risk: .writesWorkspace)
                )
                let defaultRead = evaluator.evaluate(
                    AgentPermissionRequest(toolName: "list_papers", risk: .readOnly)
                )
                let defaultWrite = evaluator.evaluate(
                    AgentPermissionRequest(toolName: "create_todo", risk: .writesWorkspace)
                )

                try expect(destructive.action == .deny, "Safety preset should deny recursive removal commands.")
                try expect(destructive.ruleID == "deny-recursive-removal", "Permission decisions should include the matching rule id.")
                try expect(sensitivePath.action == .ask, "Safety preset should ask before sensitive-looking path writes.")
                try expect(defaultRead.action == .allow, "Read-only requests should be allowed by default.")
                try expect(defaultWrite.action == .ask, "Workspace writes should ask by default.")
            }

            func agentHookEngineEvaluatesLifecycleResults() throws {
                let hooks = AgentSafetyPreset.defaultHooks() + [
                    AgentHookDefinition(
                        id: "deny-shell-preview",
                        eventName: .preToolUse,
                        matcher: #"rm\s+-rf"#,
                        permissionDecision: .deny,
                        message: "Dangerous command blocked."
                    )
                ]
                let engine = AgentHookEngine(hooks: hooks)

                let sessionResults = engine.evaluate(AgentHookEvent(name: .sessionStart))
                let preToolResults = engine.evaluate(
                    AgentHookEvent(name: .preToolUse, toolName: "Bash", command: "rm -rf build")
                )
                let stopResults = engine.evaluate(
                    AgentHookEvent(name: .stop, modifiedPaths: ["Sci-Station/Agent/AgentModels.swift"], validationRecorded: false)
                )

                try expect(sessionResults.first?.additionalContext?.contains("Swift-native") == true, "SessionStart hooks should be able to inject context.")
                try expect(preToolResults.contains(where: { $0.permissionDecision == .deny }), "PreToolUse hooks should return permission decisions.")
                try expect(stopResults.first?.message?.contains("validation") == true, "Stop hooks should be able to remind about validation.")
            }

            func agentPluginSkillAndMCPModelsValidate() throws {
                let skill = try AgentSkillManifest.parseFrontmatter(from: """
                ---
                name: proposal-draft
                description: Draft Sci-Station proposals from project context.
                version: 0.1.0
                ---

                # Proposal Draft
                """)
                let command = AgentCommandTemplate(
                    id: "proposal-draft",
                    slashCommand: "/proposal-draft",
                    title: "Proposal Draft",
                    promptTemplate: "Draft the next proposal from current project context.",
                    requiredSkillIDs: [skill.id]
                )
                let server = MCPServerConfiguration(
                    id: "sci-station-filesystem",
                    displayName: "Sci-Station Filesystem",
                    transport: .localCommand,
                    isEnabled: true,
                    command: "npx",
                    arguments: ["-y", "@modelcontextprotocol/server-filesystem", "${workspaceRoot}"],
                    allowedTools: ["read_file"],
                    headerReferences: [MCPHeaderReference(name: "Authorization", valueReference: "keychain:mcp/filesystem/authorization")]
                )
                let manifest = AgentPluginManifest(
                    id: "research-core",
                    name: "Research Core",
                    description: "Default Sci-Station research workflow preset.",
                    commands: [command],
                    skills: [skill],
                    hooks: AgentSafetyPreset.defaultHooks(),
                    mcpServers: [server]
                )
                let invalidManifest = AgentPluginManifest(
                    id: "bad",
                    name: "Bad",
                    description: "Invalid command example.",
                    commands: [AgentCommandTemplate(id: "bad", slashCommand: "bad", title: "Bad", promptTemplate: "Bad")],
                    mcpServers: [MCPServerConfiguration(id: "remote", displayName: "Remote", transport: .remoteHTTP)]
                )

                let encodedServer = try JSONEncoder().encode(server)
                let encodedServerText = try require(String(data: encodedServer, encoding: .utf8), "Encoded MCP server should be UTF-8.")
                let issues = AgentPluginValidator().validate(manifest)
                let invalidIssues = AgentPluginValidator().validate(invalidManifest)

                try expect(skill.name == "proposal-draft", "Skill frontmatter parser should read the name.")
                try expect(issues.isEmpty, "Valid plugin manifests should pass validation.")
                try expect(invalidIssues.count == 2, "Validator should report invalid command and remote MCP URL.")
                try expect(encodedServerText.contains("value_reference"), "MCP headers should serialize credential references.")
                try expect(!encodedServerText.contains("Bearer "), "MCP config serialization should not include raw authorization values.")
            }

            func agentSessionEventLoggerAppendsAndReplaysEvents() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentSessionEventWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let logger = AgentSessionEventLogger()
                let firstEvent = AgentSessionEvent(
                    id: "event-1",
                    sessionID: "session-alpha",
                    threadID: "thread-alpha",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    kind: .userMessage,
                    summary: "User asked for a plan."
                )
                let secondEvent = AgentSessionEvent(
                    id: "event-2",
                    sessionID: "session-alpha",
                    threadID: "thread-alpha",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_001),
                    kind: .hookResult,
                    summary: "PreToolUse asked for confirmation.",
                    payloadJSON: "{\"decision\":\"ask\"}"
                )

                try await logger.append(firstEvent, in: root)
                let logURL = root.fileURL(for: AgentSessionEventLogger.relativePath)
                let existingContents = try String(contentsOf: logURL, encoding: .utf8)
                try (existingContents + "{not-json}\n").write(to: logURL, atomically: true, encoding: .utf8)
                try await logger.append(secondEvent, in: root)

                let alphaEvents = try await logger.events(in: root, sessionID: "session-alpha")
                let missingEvents = try await logger.events(in: workspace, sessionID: "missing")

                try expect(alphaEvents.map(\.id) == ["event-1", "event-2"], "Session event logger should replay valid events in append order.")
                try expect(missingEvents.isEmpty, "Session event logger should filter by session id.")
            }

            func agentSessionTimelineItemsFilterCurrentSessions() throws {
                let events = [
                    AgentSessionEvent(
                        id: "timeline-1",
                        sessionID: "run-current",
                        createdAt: Date(timeIntervalSince1970: 10),
                        kind: .userMessage,
                        summary: "Review current papers.",
                        payloadJSON: "{\"content\":\"Review current papers.\"}"
                    ),
                    AgentSessionEvent(
                        id: "timeline-2",
                        sessionID: "run-other",
                        createdAt: Date(timeIntervalSince1970: 11),
                        kind: .assistantMessage,
                        summary: "Other run summary.",
                        payloadJSON: "{\"content\":\"Other run summary.\"}"
                    ),
                    AgentSessionEvent(
                        id: "timeline-3",
                        sessionID: "run-current",
                        createdAt: Date(timeIntervalSince1970: 12),
                        kind: .permissionRequested,
                        summary: "create_todo needs approval.",
                        payloadJSON: "{\"title\":\"Follow up\"}"
                    )
                ]

                let items = AgentSessionTimelineItem.items(from: events, sessionIDs: Set(["run-current"]))

                try expect(items.map(\.eventID) == ["timeline-1", "timeline-3"], "Timeline items should filter to the current run/session ids.")
                try expect(items.first?.payloadPreview == nil, "Timeline chat bubbles should not render raw user or assistant payload JSON as message content.")
                try expect(items.last?.title == "请求审批", "Timeline items should label permission request events.")
                try expect(items.last?.payloadPreview?.contains("Follow up") == true, "Timeline items should preserve payload previews for audit.")
            }

            func agentSessionTimelineProjectsLegacyRuns() throws {
                let failedRun = AgentRun(
                    id: "legacy-failed-run",
                    goal: "Read the first paper.",
                    createdAt: Date(timeIntervalSince1970: 100),
                    completedAt: Date(timeIntervalSince1970: 101),
                    mode: .planOnly,
                    plan: AgentPlan(
                        title: "运行失败",
                        summary: "Provider failed.",
                        risk: "Provider returned an empty response.",
                        steps: [],
                        toolCalls: [],
                        finalResponseDraft: nil
                    ),
                    toolResults: [],
                    lifecycleState: .failed,
                    failureCategory: .emptyResponse
                )
                let completedRun = AgentRun(
                    id: "legacy-completed-run",
                    goal: "Hello.",
                    createdAt: Date(timeIntervalSince1970: 200),
                    completedAt: Date(timeIntervalSince1970: 201),
                    mode: .planOnly,
                    plan: AgentPlan(summary: "你好！", toolCalls: [], finalResponseDraft: "你好！"),
                    toolResults: []
                )

                let failedItems = AgentSessionTimelineItem.items(from: [], runs: [failedRun], sessionIDs: Set(["legacy-failed-run"]))
                let completedItems = AgentSessionTimelineItem.items(from: [], runs: [completedRun], sessionIDs: Set(["legacy-completed-run"]))

                try expect(failedItems.map(\.kind) == [.userMessage, .toolCallFailed], "Legacy failed runs should project to user and inline failure timeline items.")
                try expect(failedItems.last?.detail == "Provider returned an empty response.", "Projected failures should use the visible risk/failure text.")
                try expect(completedItems.map(\.kind) == [.userMessage, .assistantMessage], "Legacy completed runs should project to user and assistant timeline items.")
                try expect(completedItems.last?.detail == "你好！", "Projected completed runs should preserve final response text.")
            }

            func agentRunRetryMetadataRoundTrips() throws {
                let run = AgentRun(
                    id: "retry-run",
                    goal: "Retry this.",
                    createdAt: Date(timeIntervalSince1970: 300),
                    completedAt: Date(timeIntervalSince1970: 301),
                    mode: .planOnly,
                    plan: AgentPlan(summary: "Failed.", toolCalls: []),
                    toolResults: [],
                    lifecycleState: .failed,
                    failureCategory: .providerUnavailable,
                    retryOfRunID: "original-run"
                )
                let data = try JSONEncoder().encode(run)
                let decoded = try JSONDecoder().decode(AgentRun.self, from: data)

                try expect(decoded.lifecycleState == .failed, "AgentRun should round-trip lifecycle_state.")
                try expect(decoded.failureCategory == .providerUnavailable, "AgentRun should round-trip failure_category.")
                try expect(decoded.retryOfRunID == "original-run", "AgentRun should round-trip retry_of_run_id.")
                try expect(decoded.isRetryable, "Failed runs should be retryable.")
            }

            func agentPermissionDockSummarizesPolicies() throws {
                let writeDefinition = AgentToolDefinition(
                    name: "write_note",
                    summary: "Write a note.",
                    inputSchema: "{\"path\":\"string\"}",
                    risk: .writesWorkspace
                )
                let readDefinition = AgentToolDefinition(
                    name: "read_note",
                    summary: "Read a note.",
                    inputSchema: "{}",
                    risk: .readOnly
                )
                let plan = AgentPlan(
                    summary: "Use two tools.",
                    toolCalls: [
                        AgentToolCall(id: "call-write", toolName: "write_note", argumentsJSON: "{\"path\":\"settings/token.yaml\"}"),
                        AgentToolCall(id: "call-read", toolName: "read_note", argumentsJSON: "{}")
                    ]
                )
                let run = AgentRun(
                    id: "run-dock",
                    goal: "Test dock.",
                    createdAt: Date(timeIntervalSince1970: 1),
                    completedAt: nil,
                    mode: .planOnly,
                    plan: plan,
                    toolResults: []
                )
                let items = AgentPermissionDockItem.items(
                    for: run,
                    toolDefinitions: [readDefinition, writeDefinition],
                    state: AgentPermissionDockState(
                        approvedCallIDs: ["call-write"],
                        correctionFeedbackByCallID: ["call-write": "Use a safer path."]
                    )
                )

                let writeItem = try require(items.first { $0.id == "call-write" }, "Write dock item should exist.")
                let readItem = try require(items.first { $0.id == "call-read" }, "Read dock item should exist.")

                try expect(writeItem.permissionKey == "tool.write_workspace", "Permission dock should expose permission keys.")
                try expect(writeItem.approvalState == .allowedOnce, "Permission dock should show allow-once state.")
                try expect(writeItem.matchedPolicyDescription.contains("ask-sensitive-path"), "Permission dock should report matched policy rules.")
                try expect(writeItem.pathPreview == ["settings/token.yaml"], "Permission dock should extract path previews from structured arguments.")
                try expect(writeItem.correctionFeedback == "Use a safer path.", "Permission dock should preserve correction feedback.")
                try expect(writeItem.sideEffectsRequirePermission, "Workspace-writing tools should be marked as requiring Permission Dock approval.")
                try expect(readItem.approvalState == .autoAllowed, "Read-only tools should display auto-allow state.")
                try expect(!readItem.sideEffectsRequirePermission, "Read-only tools should be classified as auto-allowed without Permission Dock approval.")
            }

            func agentHookActivitySummaryReflectsTogglesAndResults() throws {
                let result = AgentHookResult(
                    hookID: "pre-tool-permission-reminder",
                    eventName: .preToolUse,
                    permissionDecision: .ask,
                    message: "Review write before running."
                )
                let payload = try require(String(data: JSONEncoder().encode(result), encoding: .utf8), "Hook result payload should encode.")
                let event = AgentSessionEvent(
                    id: "hook-event",
                    sessionID: "run-hook",
                    kind: .hookResult,
                    summary: "PreToolUse hook pre-tool-permission-reminder. Decision: ask.",
                    payloadJSON: payload
                )

                let summary = AgentHookActivitySummary(
                    hooks: AgentSafetyPreset.defaultHooks(),
                    events: [event],
                    disabledHookIDs: ["post-tool-audit-reminder"]
                )

                try expect(summary.enabledEventNames.contains(.sessionStart), "Hook activity should expose enabled SessionStart hooks.")
                try expect(summary.enabledEventNames.contains(.preToolUse), "Hook activity should expose enabled PreToolUse hooks.")
                try expect(!summary.hooks.first { $0.id == "post-tool-audit-reminder" }!.isEnabled, "Hook activity should reflect disabled hooks.")
                try expect(summary.results.first?.permissionDecision == .ask, "Hook activity should decode hook permission decisions.")
            }

            func agentRunManifestRoundTripsMCPAuditContext() async throws {
                let fixture = try await loopWorkspaceFixture(named: "MCPManifestWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let store = AgentRunDirectoryStore()
                let runID = "mcp-manifest-run"
                let toolCallID = "call-mcp-lookup"
                let approvalID = "approval-mcp-lookup"
                let runtimeStatus = AgentMCPRuntimeStatus(
                    serverID: "remote-index",
                    displayName: "Remote Index",
                    source: .workspaceProfile,
                    transport: .remoteSSE,
                    endpointSummary: "https://mcp.example.test/sse",
                    state: .failed,
                    connectionSummary: "remote_sse at https://mcp.example.test/sse is backing off until 2026-06-26T00:00:02Z; retry_count=2.",
                    discoveredToolCount: 0,
                    errorMessage: "HTTP 503: unavailable",
                    lastErrorAt: Date(timeIntervalSince1970: 1_782_446_400),
                    retryCount: 2,
                    freshness: "backoff_until:2026-06-26T00:00:02Z"
                )
                let ledgerRecord = AgentToolExecutionLedgerRecord(
                    runID: runID,
                    toolCallID: toolCallID,
                    approvalID: approvalID,
                    fingerprint: "fingerprint-mcp-lookup",
                    tool: "mcp__remote_index__lookup",
                    risk: .externalSideEffect,
                    targetPaths: ["projects/demo/wiki/remote_lookup.md"],
                    status: .requested
                )
                try await store.appendEvent(
                    AgentRuntimeEventEnvelope(
                        id: "evt-mcp-manifest-start",
                        runID: runID,
                        sequence: 1,
                        event: .runStarted(AgentRunStarted(goal: "Audit remote MCP"))
                    ),
                    in: fixture.root
                )
                try await store.appendToolCallRecord(ledgerRecord, in: fixture.root)
                try await store.savePromptSnapshot(
                    AgentRunPromptSnapshot(
                        runID: runID,
                        snapshots: [
                            AgentPromptSnapshot(
                                runID: runID,
                                surface: .toolLoop,
                                templateID: "tool-loop-audit",
                                templateVersion: "1.0.0",
                                templateHash: "prompt-hash"
                            )
                        ]
                    ),
                    in: fixture.root
                )
                let saved = try await store.saveManifest(
                    AgentRunManifest(
                        runID: runID,
                        provider: AgentRunProviderSnapshot(configuration: LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "audit-model")),
                        runtime: AgentRunProvenance(
                            requestedRuntime: "swift_loop",
                            effectiveRuntime: "swift_loop",
                            runtime: "swift_loop",
                            fallbackReason: "remote MCP backoff preserved in audit"
                        ),
                        prompt: AgentRunPromptManifestSnapshot(
                            surface: .toolLoop,
                            templateID: "tool-loop-audit",
                            templateVersion: "1.0.0",
                            templateHash: "prompt-hash"
                        ),
                        mcpServers: [AgentRunMCPServerSnapshot(status: runtimeStatus)],
                        mcpTools: [
                            AgentRunMCPToolSnapshot(
                                exposedName: "mcp__remote_index__lookup",
                                serverID: "remote-index",
                                remoteToolName: "lookup",
                                approvalRequired: true,
                                permissionKey: "tool.external_mcp"
                            )
                        ],
                        enabledToolNames: ["mcp__remote_index__lookup"],
                        approvals: [
                            AgentRunApprovalSnapshot(
                                toolCallID: toolCallID,
                                toolName: "mcp__remote_index__lookup",
                                decision: "ask",
                                risk: .externalSideEffect,
                                targetPaths: ["projects/demo/wiki/remote_lookup.md"],
                                approvalRef: approvalID
                            )
                        ],
                        approvalRefs: [approvalID],
                        toolLedgerRef: "tool_calls.jsonl",
                        evidence: AgentRunEvidenceSummary(
                            sourceTypes: ["mcp_remote"],
                            containsSyntheticEvidence: false,
                            evidenceProvenance: .object([
                                "sources": .array([.string("mcp_remote")]),
                                "contains_synthetic_evidence": .bool(false)
                            ])
                        )
                    ),
                    in: fixture.root
                )
                let loaded = try require(try await store.manifest(runID: runID, in: fixture.root), "Run manifest should reload from manifest.json.")
                let manifestText = try String(contentsOf: fixture.root.directoryURL(for: ".sci-station/agent/runs/\(runID)").appendingPathComponent("manifest.json"), encoding: .utf8)

                try expect(saved.mcpServers.first?.transport == .remoteSSE, "Saved manifest should preserve MCP transport.")
                try expect(loaded.provider?.model == "audit-model", "Manifest should round-trip provider/model context.")
                try expect(loaded.prompt.snapshotRef == "prompt_snapshot.json", "Manifest should point back to the prompt snapshot.")
                try expect(loaded.mcpServers.first?.serverID == "remote-index", "Manifest should round-trip MCP server identity.")
                try expect(loaded.mcpServers.first?.state == .failed, "Manifest should round-trip MCP runtime state.")
                try expect(loaded.mcpServers.first?.retryCount == 2, "Manifest should round-trip MCP retry count.")
                try expect(loaded.mcpServers.first?.freshness.hasPrefix("backoff_until:") == true, "Manifest should round-trip MCP freshness/backoff.")
                try expect(loaded.mcpTools.first?.remoteToolName == "lookup", "Manifest should round-trip remote MCP tool names.")
                try expect(loaded.mcpTools.first?.approvalRequired == true, "Manifest should preserve MCP approval gating.")
                try expect(loaded.approvalRefs == [approvalID], "Manifest should round-trip approval references.")
                try expect(loaded.approvals.first?.approvalRef == approvalID, "Approval snapshots should point at approval references.")
                try expect(loaded.toolLedgerRef == "tool_calls.jsonl", "Manifest should link to the tool ledger JSONL.")
                try expect(loaded.evidence.sourceTypes == ["mcp_remote"], "Manifest should preserve evidence source types.")
                try expect(loaded.evidence.containsSyntheticEvidence == false, "Manifest should preserve synthetic provenance.")
                try expect(loaded.files.contains { $0.path == "events.jsonl" && $0.lastSequence == 1 && $0.sha256 != nil }, "Manifest should include an events.jsonl file reference with sequence and hash.")
                try expect(loaded.files.contains { $0.path == "tool_calls.jsonl" && $0.sha256 != nil }, "Manifest should include a tool ledger file reference with hash.")
                try expect(loaded.files.contains { $0.path == "prompt_snapshot.json" && $0.sha256 != nil }, "Manifest should include a prompt snapshot file reference with hash.")
                try expect(manifestText.contains(#""mcp_servers""#), "Encoded manifest should use the mcp_servers key.")
                try expect(manifestText.contains(#""mcp_tools""#), "Encoded manifest should use the mcp_tools key.")
                try expect(manifestText.contains(#""approval_refs""#), "Encoded manifest should use the approval_refs key.")
                try expect(manifestText.contains(#""tool_ledger_ref""#), "Encoded manifest should use the tool_ledger_ref key.")
            }
}
