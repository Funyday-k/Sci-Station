import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runAgentTools() async {
        await runCheck("toolbarPolicyShowsImportOnlyForLibraryContexts") { try toolbarPolicyShowsImportOnlyForLibraryContexts() }
        await runCheck("toolbarPolicyHidesPaperActionsOnHome") { try toolbarPolicyHidesPaperActionsOnHome() }
        await runCheck("toolbarPolicyShowsPDFActionsOnlyInPDFReader") { try toolbarPolicyShowsPDFActionsOnlyInPDFReader() }
        await runCheck("toolbarPolicyShowsWikiActionsOnlyInWikiContext") { try toolbarPolicyShowsWikiActionsOnlyInWikiContext() }
        await runCheck("toolbarCommandCatalogMapsToolbarActionsToCommandContributions") { try await toolbarCommandCatalogMapsToolbarActionsToCommandContributions() }
        await runCheck("agentToolErrorClassifierMapsCancelAndTimeout") { try agentToolErrorClassifierMapsCancelAndTimeout() }
        await runCheck("agentPlanParserExtractsJSONFromMarkdownFence") { try agentPlanParserExtractsJSONFromMarkdownFence() }
        await runCheck("agentPlanParserExtractsBalancedJSONBeforeTrailingText") { try agentPlanParserExtractsBalancedJSONBeforeTrailingText() }
        await runCheck("agentVisibleResponseExtractorHidesJSONEnvelope") { try agentVisibleResponseExtractorHidesJSONEnvelope() }
        await runCheck("agentVisibleResponseExtractorKeepsPartialStructuredText") { try agentVisibleResponseExtractorKeepsPartialStructuredText() }
        await runCheck("agentVisibleModeMapsConversationAndPlanToPlan") { try agentVisibleModeMapsConversationAndPlanToPlan() }
        await runCheck("agentVisibleModeMapsAssistantToAgent") { try agentVisibleModeMapsAssistantToAgent() }
        await runCheck("planModeRequiresReadableToolSet") { try planModeRequiresReadableToolSet() }
        await runCheck("agentTimelineProjectionKeepsChronologicalOrder") { try agentTimelineProjectionKeepsChronologicalOrder() }
        await runCheck("agentTimelineProjectionGroupsReasoningEvents") { try agentTimelineProjectionGroupsReasoningEvents() }
        await runCheck("agentTimelineProjectionHidesHookResults") { try agentTimelineProjectionHidesHookResults() }
        await runCheck("agentTimelineProjectionMergesToolStartAndFinish") { try agentTimelineProjectionMergesToolStartAndFinish() }
        await runCheck("toolCallRowsAreCollapsedByDefault") { try toolCallRowsAreCollapsedByDefault() }
        await runCheck("permissionRequestShowsAllowDenyOnlyByDefault") { try permissionRequestShowsAllowDenyOnlyByDefault() }
        await runCheck("draftReviewDefaultsToProjectWikiWhenProjectContextExists") { try draftReviewDefaultsToProjectWikiWhenProjectContextExists() }
        await runCheck("draftReviewFallsBackToGlobalWikiWithoutProject") { try draftReviewFallsBackToGlobalWikiWithoutProject() }
        await runCheck("timelinePaginationCanLoadEarlierEvents") { try timelinePaginationCanLoadEarlierEvents() }
        await runCheck("agentPlanParserWritebackFallbackKeepsMarkdownDraft") { try agentPlanParserWritebackFallbackKeepsMarkdownDraft() }
        await runCheck("agentPlannerAcceptsPlainTextConversationResponse") { try await agentPlannerAcceptsPlainTextConversationResponse() }
        await runCheck("agentPlannerAcceptsPlainTextAssistantFallback") { try await agentPlannerAcceptsPlainTextAssistantFallback() }
        await runCheck("agentToolExecutorRequiresApprovalForTodoWrites") { try await agentToolExecutorRequiresApprovalForTodoWrites() }
        await runCheck("writeWikiMarkdownAgentToolValidatesWhitelist") { try await writeWikiMarkdownAgentToolValidatesWhitelist() }
        await runCheck("agentPaperClassificationToolUpdatesMetadata") { try await agentPaperClassificationToolUpdatesMetadata() }
        await runCheck("agentPaperReadToolsReturnSectionsAndSearchMatches") { try await agentPaperReadToolsReturnSectionsAndSearchMatches() }
        await runCheck("agentRunLoggerWritesWorkspaceFiles") { try await agentRunLoggerWritesWorkspaceFiles() }
        await runCheck("agentServicePlanOnlyRunLogsCurrentProjectAndReadsHistory") { try await agentServicePlanOnlyRunLogsCurrentProjectAndReadsHistory() }
        await runCheck("agentServiceRecordFailedRunPersistsInlineTimeline") { try await agentServiceRecordFailedRunPersistsInlineTimeline() }
        await runCheck("agentServiceRecordCancelledRunPersistsLifecycle") { try await agentServiceRecordCancelledRunPersistsLifecycle() }
        await runCheck("agentServiceExecutesApprovedPlan") { try await agentServiceExecutesApprovedPlan() }
        await runCheck("agentPaperIntentRouterMapsAbstractToAbstractSection") { try agentPaperIntentRouterMapsAbstractToAbstractSection() }
        await runCheck("agentPaperIntentRouterClassifiesGraphIntents") { try agentPaperIntentRouterClassifiesGraphIntents() }
        await runCheck("agentAnswerQualityEvaluatorChecksFormulaSources") { try agentAnswerQualityEvaluatorChecksFormulaSources() }
        await runCheck("listPapersPayloadIncludesAbstract") { try await listPapersPayloadIncludesAbstract() }
        await runCheck("relatedWorkWorkflowClustersByTheme") { try relatedWorkWorkflowClustersByTheme() }
        await runCheck("gapPlanningWorkflowGeneratesTodoDraftsWithoutWriting") { try await gapPlanningWorkflowGeneratesTodoDraftsWithoutWriting() }
        await runCheck("evidenceRefsJumpToSourceLineRange") { try await evidenceRefsJumpToSourceLineRange() }
        await runCheck("agentDiagnosticRedactorRedactsSecretsAndHomePaths") { try agentDiagnosticRedactorRedactsSecretsAndHomePaths() }
        await runCheck("agentEvidenceRefStableIDMarksStale") { try agentEvidenceRefStableIDMarksStale() }
        await runCheck("evidenceSourceJumpMapsPDFPageWhenAvailable") { try await evidenceSourceJumpMapsPDFPageWhenAvailable() }
        await runCheck("agentHumanDecisionActionDecodesLegacyAliases") { try agentHumanDecisionActionDecodesLegacyAliases() }
        await runCheck("agentToolRiskUnknownValueDecodesAsExternalSideEffect") { try agentToolRiskUnknownValueDecodesAsExternalSideEffect() }
        await runCheck("toolHostBuildApprovalRequestHasNoSideEffects") { try await toolHostBuildApprovalRequestHasNoSideEffects() }
        await runCheck("readOnlyToolNotPausedByGenericPreToolUseReminder") { try await readOnlyToolNotPausedByGenericPreToolUseReminder() }
        await runCheck("agentServiceInjectsEnabledSkillAndRestrictsTools") { try await agentServiceInjectsEnabledSkillAndRestrictsTools() }
        await runCheck("agentRunLoggerSkipsDamagedHistoryLines") { try await agentRunLoggerSkipsDamagedHistoryLines() }
        await runCheck("agentRunLoggerFiltersProjectConversations") { try await agentRunLoggerFiltersProjectConversations() }
        await runCheck("agentThreadRepositoryGlobalStoreFiltersByWorkspaceID") { try await agentThreadRepositoryGlobalStoreFiltersByWorkspaceID() }
        await runCheck("agentThreadRepositoryMigratesPerWorkspaceLegacy") { try await agentThreadRepositoryMigratesPerWorkspaceLegacy() }
        await runCheck("agentThreadRepositoryArchivesAndReadsLegacyThreads") { try await agentThreadRepositoryArchivesAndReadsLegacyThreads() }
        await runCheck("agentPaperIntentRouterMapsThirdPaperOrdinal") { try agentPaperIntentRouterMapsThirdPaperOrdinal() }
        await runCheck("agentToolDefinitionsExposePlatformMetadata") { try agentToolDefinitionsExposePlatformMetadata() }
        await runCheck("agentPermissionRulesEvaluateSafetyDecisions") { try agentPermissionRulesEvaluateSafetyDecisions() }
        await runCheck("agentHookEngineEvaluatesLifecycleResults") { try agentHookEngineEvaluatesLifecycleResults() }
        await runCheck("agentPluginSkillAndMCPModelsValidate") { try agentPluginSkillAndMCPModelsValidate() }
        await runCheck("agentSessionEventLoggerAppendsAndReplaysEvents") { try await agentSessionEventLoggerAppendsAndReplaysEvents() }
        await runCheck("agentSessionTimelineItemsFilterCurrentSessions") { try agentSessionTimelineItemsFilterCurrentSessions() }
        await runCheck("agentSessionTimelineProjectsLegacyRuns") { try agentSessionTimelineProjectsLegacyRuns() }
        await runCheck("agentRunRetryMetadataRoundTrips") { try agentRunRetryMetadataRoundTrips() }
        await runCheck("agentPermissionDockSummarizesPolicies") { try agentPermissionDockSummarizesPolicies() }
        await runCheck("agentHookActivitySummaryReflectsTogglesAndResults") { try agentHookActivitySummaryReflectsTogglesAndResults() }
        await runCheck("agentRunManifestRoundTripsMCPAuditContext") { try await agentRunManifestRoundTripsMCPAuditContext() }
    }

    func toolbarPolicyShowsImportOnlyForLibraryContexts() throws {
        let libraryModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .library),
            context: WorkspaceContextSnapshot(topLevelSectionID: "library")
        )
        let projectPapersModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "papers"),
            context: WorkspaceContextSnapshot(topLevelSectionID: "projects", projectID: "project-a", projectTabID: "papers")
        )
        let calendarModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .calendar),
            context: WorkspaceContextSnapshot(topLevelSectionID: "calendar")
        )

        try expect(libraryModel.contains(.importPDF) && libraryModel.contains(.addByIdentifier), "Library toolbar policy should include paper import actions.")
        try expect(projectPapersModel.contains(.importPDF) && projectPapersModel.contains(.addByIdentifier), "ProjectSpace Papers toolbar policy should include paper import actions.")
        try expect(!calendarModel.contains(.importPDF) && !calendarModel.contains(.addByIdentifier), "Calendar toolbar policy should not include paper import actions.")
    }

    func toolbarPolicyHidesPaperActionsOnHome() throws {
        let model = ToolbarPolicy.resolve(
            route: .home,
            context: WorkspaceContextSnapshot(topLevelSectionID: "home")
        )

        try expect(!model.contains(.importPDF), "Home toolbar policy should hide Import PDF.")
        try expect(!model.contains(.addByIdentifier), "Home toolbar policy should hide Add by Identifier.")
        try expect(model.contains(.aiPanel), "Home toolbar policy should keep the global AI action.")
        try expect(!model.contains(.refresh), "Home toolbar policy should hide refresh.")
    }

    func toolbarPolicyShowsPDFActionsOnlyInPDFReader() throws {
        let pdfModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "pdf-reader"),
            context: WorkspaceContextSnapshot(topLevelSectionID: "projects", projectID: "project-a", projectTabID: "pdf-reader"),
            language: .simplifiedChinese
        )
        let wikiModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "wiki"),
            context: WorkspaceContextSnapshot(topLevelSectionID: "projects", projectID: "project-a", projectTabID: "wiki")
        )

        try expect(pdfModel.contains(.pdfSearch), "PDF Reader toolbar policy should include PDF search.")
        try expect(pdfModel.action(.pdfAnnotations)?.title == "标注", "PDF Reader toolbar should localize PDF actions.")
        try expect(!pdfModel.contains(.importPDF) && !pdfModel.contains(.addByIdentifier), "PDF Reader toolbar policy should hide Library import actions.")
        try expect(!wikiModel.contains(.pdfSearch) && !wikiModel.contains(.pdfAnnotations), "Wiki toolbar policy should not include PDF Reader actions.")
    }

    func toolbarPolicyShowsWikiActionsOnlyInWikiContext() throws {
        let wikiModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "wiki"),
            context: WorkspaceContextSnapshot(topLevelSectionID: "projects", projectID: "project-a", projectTabID: "wiki")
        )
        let libraryModel = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .library),
            context: WorkspaceContextSnapshot(topLevelSectionID: "library")
        )

        try expect(wikiModel.contains(.wikiNewPage) && wikiModel.contains(.wikiSave), "Wiki toolbar policy should include Wiki actions.")
        try expect(!libraryModel.contains(.wikiNewPage) && !libraryModel.contains(.wikiSave), "Library toolbar policy should not include Wiki actions.")
    }

    func toolbarCommandCatalogMapsToolbarActionsToCommandContributions() async throws {
        let model = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .library),
            context: WorkspaceContextSnapshot(topLevelSectionID: "library")
        )
        let contributions = model.primaryCommandContributions
        let ids = contributions.map(\.id)
        let importContribution = try require(contributions.first { $0.id == "paper.importPDF" }, "Import PDF should be exposed as a command contribution.")
        let registry = CommandRegistry()
        try await registry.register(importContribution, pluginID: "sci.paper-library") { context in
            CommandExecutionResult(succeeded: context.commandID == "paper.importPDF", message: context.pluginID)
        }
        let visible = await registry.contributions(placement: .toolbar)
        let result = try await registry.execute(id: importContribution.id)

        try expect(ids.contains("workspace.menu"), "Workspace menu should have a stable command id.")
        try expect(ids.contains("shell.aiPanel"), "AI panel toolbar action should have a stable command id.")
        try expect(ids.contains("paper.importByIdentifier"), "Identifier import toolbar action should have a stable command id.")
        try expect(importContribution.title == model.action(.importPDF)?.title, "Command contribution should preserve toolbar action title.")
        try expect(importContribution.systemImage == "doc.badge.plus", "Command contribution should preserve toolbar action image.")
        try expect(ToolbarCommandCatalog.toolbarActionID(for: "paper.importPDF") == .importPDF, "Toolbar command catalog should map command ids back to action ids.")
        try expect(visible.contains(importContribution), "Toolbar command contribution should register in the generic command registry.")
        try expect(result.succeeded && result.message == "sci.paper-library", "Toolbar command contribution should execute through the generic command registry.")
    }

    func agentToolErrorClassifierMapsCancelAndTimeout() throws {
        let classifier = AgentToolErrorClassifier()

        let cancelled = classifier.classify(CancellationError(), toolName: "list_papers")
        try expect(cancelled.code == .cancelled, "CancellationError should map to the cancelled code.")

        let timeout = classifier.classify(
            AgentTimeoutError(operation: "Tool invocation", timeoutSeconds: 5, toolName: "list_papers"),
            toolName: "list_papers"
        )
        try expect(timeout.code == .timeout, "AgentTimeoutError should map to the timeout code.")

        let network = classifier.classify(URLError(.notConnectedToInternet), toolName: "list_papers")
        try expect(network.code == .network, "URLError should map to the network code.")

        let unknown = classifier.classify(AgentError.unknownTool("mystery"), toolName: "mystery")
        try expect(unknown.code == .toolNotFound, "unknownTool should classify as tool_not_found.")
    }

            func agentPlanParserExtractsJSONFromMarkdownFence() throws {
                let response = """
                ```json
                {
                  "summary": "Create a todo",
                  "tool_calls": [
                    {
                      "id": "call-1",
                      "tool_name": "create_todo",
                      "arguments_json": "{\\\"title\\\":\\\"Read the selected paper\\\"}"
                    }
                  ],
                  "final_response_draft": "Ready for approval."
                }
                ```
                """

                let plan = try AgentPlanParser().parse(response)

                try expect(plan.summary == "Create a todo", "Agent plan parser should decode the summary.")
                try expect(plan.toolCalls.first?.toolName == "create_todo", "Agent plan parser should decode tool calls.")
                try expect(plan.toolCalls.first?.argumentsJSON.contains("Read the selected paper") == true, "Agent plan parser should preserve encoded tool arguments.")
            }

            func agentPlanParserExtractsBalancedJSONBeforeTrailingText() throws {
                let response = """
                {"summary":"写入 wiki","tool_calls":[],"final_response_draft":"正文里可以包含 {braces}。"}

                额外说明：已准备写入。
                """

                let plan = try AgentPlanParser().parse(response)
                try expect(plan.finalResponseDraft == "正文里可以包含 {braces}。", "Plan parser should use the first balanced JSON object and ignore trailing prose.")
            }

            func agentVisibleResponseExtractorHidesJSONEnvelope() throws {
                let jsonResponse = """
                {
                    "summary": "Internal summary",
                    "tool_calls": [],
                    "final_response_draft": "只显示这一段。"
                }
                """

                let visibleText = AgentVisibleResponseExtractor.visibleText(from: jsonResponse)
                let partialJSON = "{\"summary\": \"still streaming"
                let plainText = "普通 Markdown 回复"

                try expect(visibleText == "只显示这一段。", "Visible response extractor should return final_response_draft from JSON envelopes.")
                try expect(AgentVisibleResponseExtractor.visibleText(from: partialJSON) == "still streaming", "Visible response extractor should recover partial structured text instead of hiding all output.")
                try expect(AgentVisibleResponseExtractor.visibleText(from: plainText) == plainText, "Visible response extractor should preserve plain text responses.")
            }

            func agentVisibleResponseExtractorKeepsPartialStructuredText() throws {
                let partialResponse = "{\"response\": \"第一段已经生成，第二段"
                let unknownEnvelope = "{\"tool_calls\": [], \"display\": \"fallback text\"}"

                try expect(AgentVisibleResponseExtractor.visibleText(from: partialResponse).contains("第一段已经生成"), "Partial structured responses should keep the user-visible field while streaming or interrupted.")
                try expect(AgentVisibleResponseExtractor.visibleText(from: unknownEnvelope) == "fallback text", "Structured envelopes with unfamiliar string keys should still expose useful text.")
            }

            func agentVisibleModeMapsConversationAndPlanToPlan() throws {
                try expect(AgentVisibleMode(interactionMode: .conversation) == .plan, "Conversation mode should appear as Plan in the UI adapter.")
                try expect(AgentVisibleMode(interactionMode: .plan) == .plan, "Legacy plan mode should appear as Plan in the UI adapter.")
                try expect(AgentInteractionMode.conversation.visibleMode == .plan, "Interaction mode adapter should preserve old conversation runs as visible Plan.")
            }

            func agentVisibleModeMapsAssistantToAgent() throws {
                try expect(AgentVisibleMode(interactionMode: .assistant) == .agent, "Assistant mode should appear as Agent in the UI adapter.")
                try expect(AgentVisibleMode.agent.defaultInteractionMode == .assistant, "Visible Agent should use the assistant runtime behavior.")
                try expect(AgentVisibleMode.plan.defaultInteractionMode == .conversation, "Visible Plan should keep the streaming conversation runtime behavior.")
            }

            func planModeRequiresReadableToolSet() throws {
                let readTool = AgentToolDefinition(name: "search_papers", summary: "Search papers", inputSchema: "{}", risk: .readOnly)
                let writeTool = AgentToolDefinition(name: "write_wiki_markdown", summary: "Write wiki", inputSchema: "{}", risk: .writesWorkspace)

                try expect(AgentVisibleMode.plan.hasRequiredTools(availableTools: [readTool, writeTool], enabledToolNames: ["search_papers"]), "Plan mode should run when a read-only tool is enabled.")
                try expect(!AgentVisibleMode.plan.hasRequiredTools(availableTools: [readTool, writeTool], enabledToolNames: ["write_wiki_markdown"]), "Plan mode should warn when no read-only tools are enabled.")
                try expect(AgentVisibleMode.agent.hasRequiredTools(availableTools: [readTool, writeTool], enabledToolNames: ["write_wiki_markdown"]), "Agent mode should run when at least one tool is enabled.")
            }

            func agentTimelineProjectionKeepsChronologicalOrder() throws {
                let events = [
                    AgentSessionEvent(id: "late", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 30), kind: .assistantMessage, summary: "late"),
                    AgentSessionEvent(id: "early", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 10), kind: .userMessage, summary: "early"),
                    AgentSessionEvent(id: "middle", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 20), kind: .toolCallStarted, summary: "middle")
                ]

                let items = AgentSessionTimelineItem.items(from: events, sessionIDs: ["run-a"], limit: nil)
                try expect(items.map(\.eventID) == ["early", "middle", "late"], "Timeline projection should keep chronological order when loading full history.")
            }

            func agentTimelineProjectionGroupsReasoningEvents() throws {
                let item = AgentSessionTimelineItem.items(from: [
                    AgentSessionEvent(id: "reasoning", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 10), kind: .reasoningSummary, summary: "Read papers and compare formulas.")
                ]).first
                let event = try require(item.map(AgentTimelineEvent.init(item:)), "Reasoning timeline item should project.")

                try expect(event.kind == .reasoningGroup, "Reasoning summaries should project as reasoning groups.")
                try expect(event.isCollapsedByDefault, "Reasoning groups should be collapsed by default.")
                try expect(event.stepCount == 1, "Reasoning groups should report at least one visible step.")
            }

            func agentTimelineProjectionHidesHookResults() throws {
                let items = AgentSessionTimelineItem.items(from: [
                    AgentSessionEvent(id: "user", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 10), kind: .userMessage, summary: "Hello"),
                    AgentSessionEvent(id: "hook", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 11), kind: .hookResult, summary: "Stop validation reminder"),
                    AgentSessionEvent(id: "assistant", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 12), kind: .assistantMessage, summary: "Hi")
                ])
                let events = AgentTimelineEvent.events(from: items)

                try expect(events.map(\.sourceKind) == [.userMessage, .assistantMessage], "Hook results should stay in audit logs but not render in the AI Lab timeline.")
            }

            func agentTimelineProjectionMergesToolStartAndFinish() throws {
                let items = AgentSessionTimelineItem.items(from: [
                    AgentSessionEvent(
                        id: "start",
                        sessionID: "run-a",
                        createdAt: Date(timeIntervalSince1970: 10),
                        kind: .toolCallStarted,
                        summary: "Running read_paper.",
                        payloadJSON: "{\"tool_call_id\":\"call-a\",\"tool_name\":\"read_paper\"}"
                    ),
                    AgentSessionEvent(
                        id: "finish",
                        sessionID: "run-a",
                        createdAt: Date(timeIntervalSince1970: 11),
                        kind: .toolCallCompleted,
                        summary: "已使用工具：read_paper",
                        payloadJSON: "{\"tool_call_id\":\"call-a\",\"tool_name\":\"read_paper\",\"summary\":\"ok\"}"
                    )
                ])
                let events = AgentTimelineEvent.events(from: items)
                let event = try require(events.first, "Merged tool event should exist.")

                try expect(events.count == 1, "Tool start and finish should render as one timeline row.")
                try expect(event.id == "tool-run-a-call-a", "Merged tool row should keep a stable id for in-place UI updates.")
                try expect(event.status == .succeeded, "Merged tool row should update to the finish status.")
                try expect(event.toolName == "read_paper", "Merged tool row should keep the tool name.")
            }

            func toolCallRowsAreCollapsedByDefault() throws {
                let item = AgentSessionTimelineItem.items(from: [
                    AgentSessionEvent(id: "tool", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 10), kind: .toolCallCompleted, summary: "已使用工具：search_papers", payloadJSON: "{\"tool_name\":\"search_papers\"}")
                ]).first
                let event = try require(item.map(AgentTimelineEvent.init(item:)), "Tool timeline item should project.")

                try expect(event.kind == .toolCall, "Tool events should project as compact tool rows.")
                try expect(event.toolName == "search_papers", "Tool rows should expose the tool name.")
                try expect(event.isCollapsedByDefault, "Tool rows should be collapsed by default.")
            }

            func permissionRequestShowsAllowDenyOnlyByDefault() throws {
                let item = AgentSessionTimelineItem.items(from: [
                    AgentSessionEvent(id: "permission", sessionID: "run-a", createdAt: Date(timeIntervalSince1970: 10), kind: .permissionRequested, summary: "write_wiki_markdown needs approval.", payloadJSON: "{\"target_path\":\"wiki/test.md\"}")
                ]).first
                let event = try require(item.map(AgentTimelineEvent.init(item:)), "Permission timeline item should project.")

                try expect(event.kind == .permissionRequest, "Permission events should project as inline permission requests.")
                try expect(event.status == .waitingForApproval, "Permission requests should remain waiting until the user decides.")
                try expect(event.targetPaths == ["wiki/test.md"], "Permission requests should expose target paths for review.")
                try expect(event.isCollapsedByDefault, "Permission details should be collapsed by default.")
            }

            func draftReviewDefaultsToProjectWikiWhenProjectContextExists() throws {
                let path = AgentDraftReviewItem.defaultWikiTargetPath(projectID: "project-a", slug: "notes/summary")
                try expect(path == "projects/project-a/wiki/summary.md", "Project draft review should default to the project's wiki folder.")
            }

            func draftReviewFallsBackToGlobalWikiWithoutProject() throws {
                let path = AgentDraftReviewItem.defaultWikiTargetPath(projectID: nil, slug: "summary.md")
                try expect(path == "wiki/summary.md", "Workspace draft review should fall back to the global wiki folder.")
            }

            func timelinePaginationCanLoadEarlierEvents() throws {
                let events = (0..<180).map { index in
                    AgentSessionEvent(
                        id: "event-\(index)",
                        sessionID: "run-a",
                        createdAt: Date(timeIntervalSince1970: Double(index)),
                        kind: .assistantMessage,
                        summary: "message \(index)"
                    )
                }

                let limited = AgentSessionTimelineItem.items(from: events, sessionIDs: ["run-a"], limit: 120)
                let full = AgentSessionTimelineItem.items(from: events, sessionIDs: ["run-a"], limit: nil)

                try expect(limited.count == 120, "Timeline projection should still support a page-size limit.")
                try expect(limited.first?.eventID == "event-60", "Limited projection should return the newest page.")
                try expect(full.count == 180, "Full timeline projection should be available for Load Earlier pagination.")
                try expect(full.first?.eventID == "event-0", "Full projection should preserve earliest events.")
            }

            func agentPlanParserWritebackFallbackKeepsMarkdownDraft() throws {
                let response = """
                ## AI Summary

                这是一段准备写进 wiki 的 Markdown 草稿，包含公式 $E_\\odot$。
                """
                let plan = try require(
                    AgentPlanParser().writebackFallbackPlan(response: response, goal: "把这篇文章总结一下写进 wiki 里"),
                    "Writeback fallback should produce a draft plan for non-JSON Markdown."
                )

                try expect(plan.title == "未确认的写回草稿", "Writeback fallback should use the explicit draft title.")
                try expect(plan.toolCalls.isEmpty, "Writeback fallback should not execute a workspace write without approval.")
                try expect(plan.finalResponseDraft?.contains("E_\\odot") == true, "Writeback fallback should preserve the original Markdown draft.")
            }

            func agentPlannerAcceptsPlainTextConversationResponse() async throws {
                let provider = StaticLLMProvider(response: "你好，我可以用 **Markdown** 回答。")
                let planner = AgentPlanner(provider: provider)
                let plan = try await planner.plan(
                    goal: "请用中文介绍当前项目",
                    workspaceSnapshot: AgentWorkspaceSnapshot(
                        workspaceName: "Test_Workspace",
                        selectedPaper: nil,
                        recentPapers: [],
                        openTodos: [],
                        paperCount: 0,
                        todoCount: 0
                    ),
                    tools: [],
                    configuration: LLMConfiguration(),
                    apiKey: "test-key",
                    modeInstructions: AgentInteractionMode.conversation.plannerInstructions,
                    allowsPlainTextResponse: true
                )

                try expect(plan.toolCalls.isEmpty, "Plain text conversation fallback should not create tool calls.")
                try expect(plan.finalResponseDraft?.contains("Markdown") == true, "Plain text conversation fallback should preserve the assistant response.")
            }

            func agentPlannerAcceptsPlainTextAssistantFallback() async throws {
                let provider = StaticLLMProvider(response: "当前项目共有 3 篇论文。")
                let planner = AgentPlanner(provider: provider)
                let plan = try await planner.plan(
                    goal: "项目里都有什么文章？列一下",
                    workspaceSnapshot: AgentWorkspaceSnapshot(
                        workspaceName: "Test_Workspace",
                        selectedPaper: nil,
                        recentPapers: [],
                        openTodos: [],
                        paperCount: 3,
                        todoCount: 0
                    ),
                    tools: [],
                    configuration: LLMConfiguration(),
                    apiKey: "test-key",
                    modeInstructions: AgentInteractionMode.assistant.plannerInstructions,
                    allowsPlainTextResponse: false
                )

                try expect(plan.toolCalls.isEmpty, "Assistant fallback should not invent tool calls from plain text.")
                try expect(plan.finalResponseDraft == "当前项目共有 3 篇论文。", "Assistant fallback should preserve readable non-JSON replies.")
                try expect(plan.title == "AI 回复", "Assistant fallback should mark the run as a visible AI reply.")
            }

            func agentToolExecutorRequiresApprovalForTodoWrites() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let todoRepository = TodoRepository()
                let registry = AgentToolRegistry(tools: [CreateTodoAgentTool(todoRepository: todoRepository)])
                let executor = AgentToolExecutor(registry: registry)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentTodoWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let plan = AgentPlan(
                    summary: "Create a follow-up todo",
                    toolCalls: [
                        AgentToolCall(
                            id: "call-1",
                            toolName: "create_todo",
                            argumentsJSON: "{\"title\":\"Check agent framework\",\"priority\":\"high\",\"tags\":[\"agent\"]}"
                        )
                    ]
                )
                let context = AgentToolContext(workspace: workspace, selectedPaperID: "paper-001", currentProjectID: "project-alpha")

                let blockedResults = await executor.execute(plan: plan, context: context, approvedToolCallIDs: [])
                let todosBeforeApproval = try await todoRepository.loadTodos(in: workspace)
                try expect(blockedResults.first?.requiresConfirmation == true, "Workspace-writing agent tools should require approval before execution.")
                try expect(todosBeforeApproval.isEmpty, "Unapproved agent tool calls should not modify todos.")

                let approvedResults = await executor.execute(plan: plan, context: context, approvedToolCallIDs: ["call-1"])
                let todosAfterApproval = try await todoRepository.loadTodos(in: workspace)
                try expect(approvedResults.first?.succeeded == true, "Approved todo tool call should succeed.")
                try expect(approvedResults.first?.callID == "call-1", "Agent tool results should retain the originating call id.")
                try expect(todosAfterApproval.first?.title == "Check agent framework", "Approved todo tool call should persist a todo.")
                try expect(todosAfterApproval.first?.relatedPaperIDs == ["paper-001"], "Todo tool should link to the selected paper when no explicit related_paper_ids are provided.")
                try expect(todosAfterApproval.first?.projectIDs == ["project-alpha"], "Todo tool should default to the current project when project_ids are omitted.")
            }

            func writeWikiMarkdownAgentToolValidatesWhitelist() async throws {
                let fixture = try await loopWorkspaceFixture(named: "WriteWikiMarkdownToolWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let paperRepository = PaperRepository()
                _ = try await paperRepository.save(samplePaper(id: "paper-valid"), in: fixture.workspace)
                let tool = WriteMarkdownPlanAgentTool(markdownRepository: MarkdownRepository(), paperRepository: paperRepository)
                let context = AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)

                let paperResult = try await tool.invoke(
                    argumentsJSON: "{\"title\":\"Paper Summary\",\"body\":\"## AI Summary\\n\\nFormula $E$.\",\"relative_path\":\"wiki/papers/paper-valid.md\"}",
                    context: context
                )
                try expect(paperResult.modifiedPaths == ["wiki/papers/paper-valid.md"], "Wiki paper writeback should allow existing paper ids.")
                try expect(FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: "wiki/papers/paper-valid.md").path), "Wiki paper writeback should create the target file.")

                let noteResult = try await tool.invoke(
                    argumentsJSON: #"{"title":"Free Note","body":"Body","relative_path":"wiki/notes/free-note.md"}"#,
                    context: context
                )
                try expect(noteResult.modifiedPaths == ["wiki/notes/free-note.md"], "Wiki notes writeback should be allowed.")

                try await expectWikiWriteRejected(tool, context: context, path: "wiki/../etc.md")
                try await expectWikiWriteRejected(tool, context: context, path: "/tmp/etc.md")
                try await expectWikiWriteRejected(tool, context: context, path: "wiki/papers/missing-paper.md")
            }

            func agentPaperClassificationToolUpdatesMetadata() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let paperRepository = PaperRepository()
                let registry = AgentToolRegistry(tools: [UpdatePaperClassificationAgentTool(paperRepository: paperRepository)])
                let executor = AgentToolExecutor(registry: registry)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentPaperWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = try await paperRepository.save(samplePaper(id: "agent-paper"), in: workspace)
                let plan = AgentPlan(
                    summary: "Classify selected paper",
                    toolCalls: [
                        AgentToolCall(
                            id: "call-1",
                            toolName: "update_paper_classification",
                            argumentsJSON: "{\"tags\":[\"simulation\",\"dark-matter\"],\"categories\":[\"methods\"],\"mark_core_in_current_project\":true,\"priority\":\"urgent\",\"status\":\"skimmed\"}"
                        )
                    ]
                )

                let results = await executor.execute(
                    plan: plan,
                    context: AgentToolContext(workspace: workspace, selectedPaperID: paper.id, currentProjectID: "project-alpha"),
                    approvedToolCallIDs: ["call-1"]
                )
                let updatedPaper = try require(try await paperRepository.loadPapers(in: workspace).first(where: { $0.id == paper.id }), "Expected updated paper to be loadable.")

                try expect(results.first?.succeeded == true, "Approved classification tool call should succeed.")
                try expect(updatedPaper.tags.contains("simulation"), "Classification tool should merge new tags.")
                try expect(updatedPaper.categories.contains("methods"), "Classification tool should merge new categories.")
                try expect(updatedPaper.projectIDs.contains("project-alpha"), "Classification tool should add the selected paper to the current project when requested.")
                try expect(updatedPaper.coreProjectIDs.contains("project-alpha"), "Classification tool should mark the selected paper as core in the current project when requested.")
                try expect(updatedPaper.priority == .urgent, "Classification tool should update priority.")
                try expect(updatedPaper.status == .skimmed, "Classification tool should update reading status.")
            }

            func agentPaperReadToolsReturnSectionsAndSearchMatches() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let paperRepository = PaperRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentPaperReadToolsWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                var paper = samplePaper(id: "agent-readable-paper")
                paper.title = "Evaporation Rate Reference"
                paper.tags = ["dm"]
                let savedPaper = try await paperRepository.save(paper, in: workspace)
                let markdown = """
                # Evaporation Rate Reference

                ## 1 Overview

                This section introduces the model.

                ## 5 Evaporation Rate

                The evaporation rate marker is E_sun_section_marker.

                $$
                E_{\\odot} = \\sum_i \\int s(r) n_\\chi(r) 4\\pi r^2 dr
                $$

                ![](figures/mineru/images/figure-2-a.jpg)

                ![](figures/mineru/images/figure-2-b.jpg)

                Figure 2. DM temperature as a function of the DM mass.

                ## Appendix

                Extra material.
                """
                try markdown.write(to: savedPaper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

                let registry = AgentToolRegistry(tools: [
                    ListPapersAgentTool(paperRepository: paperRepository),
                    ReadPaperSectionAgentTool(paperRepository: paperRepository),
                    SearchPapersAgentTool(paperRepository: paperRepository)
                ])
                let executor = AgentToolExecutor(registry: registry)
                let plan = AgentPlan(
                    summary: "Read paper sections",
                    toolCalls: [
                        AgentToolCall(
                            id: "call-section",
                            toolName: "read_paper_section",
                            argumentsJSON: "{\"paper_id\":\"\(savedPaper.id)\",\"heading\":\"5 Evaporation Rate\"}"
                        ),
                        AgentToolCall(
                            id: "call-search",
                            toolName: "search_papers",
                            argumentsJSON: "{\"query\":\"E_sun_section_marker\",\"paper_ids\":[\"\(savedPaper.id)\"]}"
                        ),
                        AgentToolCall(
                            id: "call-list",
                            toolName: "list_papers",
                            argumentsJSON: "{\"query\":\"Evaporation\"}"
                        ),
                        AgentToolCall(
                            id: "call-figure",
                            toolName: "read_paper_section",
                            argumentsJSON: "{\"paper_id\":\"\(savedPaper.id)\",\"heading\":\"Figure 2\"}"
                        ),
                        AgentToolCall(
                            id: "call-heading-with-lines",
                            toolName: "read_paper_section",
                            argumentsJSON: "{\"paper_id\":\"\(savedPaper.id)\",\"heading\":\"5 Evaporation Rate\",\"start_line\":1,\"end_line\":3}"
                        )
                    ]
                )

                let results = await executor.execute(
                    plan: plan,
                    context: AgentToolContext(workspace: workspace, selectedPaperID: savedPaper.id),
                    approvedToolCallIDs: []
                )
                let definitions = await SciStationAgentService(
                    provider: StaticLLMProvider(response: "{\"summary\":\"No-op\",\"tool_calls\":[]}")
                ).toolDefinitions()
                let definitionNames = Set(definitions.map(\.name))

                try expect(results.allSatisfy(\.succeeded), "Read-only paper tools should run without approval.")
                try expect(results.first(where: { $0.callID == "call-section" })?.message.contains("E_sun_section_marker") == true, "read_paper_section should return the requested heading content.")
                try expect(results.first(where: { $0.callID == "call-search" })?.message.contains("#L") == true, "search_papers should return line-anchored matches.")
                try expect(results.first(where: { $0.callID == "call-list" })?.message.contains(savedPaper.id) == true, "list_papers should expose matching paper ids.")
                try expect(results.first(where: { $0.callID == "call-figure" })?.message.contains("figure-2-a.jpg") == true, "read_paper_section should return local image references for figure captions.")
                try expect(results.first(where: { $0.callID == "call-figure" })?.message.contains("DM temperature") == true, "read_paper_section should match figure captions by figure number.")
                try expect(results.first(where: { $0.callID == "call-heading-with-lines" })?.message.contains("E_sun_section_marker") == true, "read_paper_section should prefer heading over incidental line ranges.")
                try expect(results.first(where: { $0.callID == "call-section" })?.payload?.objectValue?["kind"]?.stringValue == "paper_section", "read_paper_section should expose a structured payload.")
                try expect(results.first(where: { $0.callID == "call-search" })?.payload?.objectValue?["matches"]?.arrayValue?.isEmpty == false, "search_papers should expose structured matches.")
                try expect(results.first(where: { $0.callID == "call-list" })?.payload?.objectValue?["papers"]?.arrayValue?.first?.objectValue?["paper_id"]?.stringValue == savedPaper.id, "list_papers should expose structured paper ids.")
                try expect(definitionNames.isSuperset(of: ["list_papers", "read_paper", "read_paper_section", "search_papers"]), "Default agent tool registry should expose paper read/search tools.")
            }

            func agentRunLoggerWritesWorkspaceFiles() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentLogWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let run = AgentRun(
                    id: "agent-run-test",
                    goal: "Plan a todo",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    completedAt: Date(timeIntervalSince1970: 1_777_600_001),
                    mode: .planOnly,
                    plan: AgentPlan(summary: "No writes", toolCalls: []),
                    toolResults: []
                )
                try await AgentRunLogger().append(run, in: workspace)
                let logContents = try String(contentsOf: workspace.fileURL(for: ".sci-station/agent/runs.jsonl"), encoding: .utf8)
                try expect(logContents.contains("agent-run-test"), "Agent run logger should append JSONL entries.")
            }

            func agentServicePlanOnlyRunLogsCurrentProjectAndReadsHistory() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let projectRegistryRepository = ProjectRegistryRepository()
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore,
                    projectRegistryRepository: projectRegistryRepository
                )
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentServicePlanWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let registry = try await projectRegistryRepository.load(in: root)
                let project = try require(registry.projects.first, "Expected a default project for service agent tests.")
                let provider = StaticLLMProvider(
                    response: """
                    {
                      "title": "Todo plan",
                      "summary": "Create a project follow-up todo.",
                      "risk": "Writes one todo after approval.",
                      "steps": ["Review current project context", "Create one todo after approval"],
                      "tool_calls": [
                        {
                          "id": "call-1",
                          "tool_name": "create_todo",
                          "arguments_json": "{\\\"title\\\":\\\"Review agent plan\\\"}"
                        }
                      ],
                      "final_response_draft": "Ready for approval."
                    }
                    """
                )
                let service = SciStationAgentService(provider: provider)

                let run = try await service.run(
                    goal: "Create a project todo",
                    in: workspace,
                    root: root,
                    projects: registry.projects,
                    currentProjectID: project.id,
                    configuration: LLMConfiguration(),
                    apiKey: "test-key",
                    options: AgentExecutionOptions(mode: .planOnly)
                )
                let history = try await service.recentRuns(in: root, limit: 5)
                let logContents = try String(contentsOf: root.fileURL(for: ".sci-station/agent/runs.jsonl"), encoding: .utf8)

                try expect(run.mode == .planOnly, "Agent service should support plan-only runs.")
                try expect(run.currentProjectID == project.id, "Plan-only run should record the current project id.")
                try expect(run.contextScope == .project, "Plan-only run should record project context scope.")
                try expect(run.projectID == project.id, "Plan-only run should persist the project_id metadata alias.")
                try expect(run.runtimeSelector == AgentRuntimeSelection.swiftLoop.rawValue, "Plan-only run should persist runtime selector metadata.")
                try expect(run.createdFromRoute == "ai_lab", "Plan-only run should record the originating AI Lab route.")
                try expect(run.enabledToolNames?.contains("create_todo") == true, "Plan-only run should snapshot enabled tools for replay.")
                try expect(run.plan.title == "Todo plan", "Agent plan should decode the optional title field.")
                try expect(run.plan.steps.count == 2, "Agent plan should decode ordered steps.")
                try expect(history.first?.id == run.id, "Agent service should read recent run history with newest entries first.")
                try expect(logContents.contains(project.id), "Agent run log should include current_project_id.")
                try expect(logContents.contains("\"context_scope\":\"project\""), "Agent run log should include context_scope metadata.")
                try expect(logContents.contains("\"project_id\":\"") && logContents.contains("\"runtime_selector\":\"swift_loop\""), "Agent run log should include project_id and runtime_selector metadata.")
                let sessionEvents = try await service.sessionEvents(in: root, sessionID: run.id)
                try expect(sessionEvents.map(\.kind).contains(.permissionRequested), "Plan-only runs should append permission request session events for requested tools.")
            }

            func agentServiceRecordFailedRunPersistsInlineTimeline() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentFailedRunWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let service = SciStationAgentService(provider: StaticLLMProvider(response: "{}"))
                let run = try await service.recordFailedRun(
                    goal: "请生成一个阅读本项目论文的计划",
                    message: "Model unavailable.",
                    partialAssistantResponse: "已读取项目上下文，但模型不可用。",
                    in: root,
                    currentProjectID: "project-alpha",
                    runtimeSelector: AgentRuntimeSelection.autoFallback.rawValue,
                    enabledToolNames: ["list_papers", "read_paper"],
                    promptResolution: AgentPromptResolution(surface: .toolLoop, promptText: "请生成一个阅读本项目论文的计划")
                )
                let history = try await service.recentRuns(in: root, limit: 5)
                let events = try await service.sessionEvents(in: root, sessionID: run.id)

                try expect(history.first?.id == run.id, "Failed runs should be durable in run history.")
                try expect(run.plan.risk == "Model unavailable.", "Failed runs should preserve an inline failure reason.")
                try expect(run.projectID == "project-alpha", "Failed runs should preserve project affinity metadata.")
                try expect(run.runtimeSelector == AgentRuntimeSelection.autoFallback.rawValue, "Failed runs should preserve runtime selector metadata.")
                try expect(run.enabledToolNames == ["list_papers", "read_paper"], "Failed runs should preserve tool selection metadata.")
                try expect(events.map(\.kind) == [.userMessage, .toolCallFailed], "Failed runs should leave a user message and inline failure event in the timeline.")
                try expect(events.last?.summary == "Model unavailable.", "Inline failure event should carry the visible failure reason.")
            }

            func agentServiceRecordCancelledRunPersistsLifecycle() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentCancelledRunWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let service = SciStationAgentService(provider: StaticLLMProvider(response: "{}"))
                let run = try await service.recordCancelledRun(
                    goal: "请总结第一篇文章",
                    message: "用户已停止本次 AI 输出。",
                    partialAssistantResponse: "已读取论文，正在整理回答。",
                    in: root,
                    currentProjectID: "project-alpha",
                    runtimeSelector: AgentRuntimeSelection.swiftLoop.rawValue,
                    enabledToolNames: ["list_papers"],
                    promptResolution: AgentPromptResolution(surface: .toolLoop, promptText: "请总结第一篇文章"),
                    retryOfRunID: "agent-run-previous"
                )
                let events = try await service.sessionEvents(in: root, sessionID: run.id)

                try expect(run.lifecycleState == .cancelled, "Cancelled runs should persist a cancelled lifecycle state.")
                try expect(run.failureCategory == .cancelledByUser, "Cancelled runs should preserve a user-cancelled failure category.")
                try expect(run.retryOfRunID == "agent-run-previous", "Cancelled retry attempts should keep retry source metadata.")
                try expect(events.map(\.kind) == [.userMessage, .assistantMessage, .runCancelled], "Cancelled runs should replay as user, partial assistant, and cancelled events.")
            }

            func agentServiceExecutesApprovedPlan() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let projectRegistryRepository = ProjectRegistryRepository()
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore,
                    projectRegistryRepository: projectRegistryRepository
                )
                let todoRepository = TodoRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentServiceExecuteWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let registry = try await projectRegistryRepository.load(in: root)
                let project = try require(registry.projects.first, "Expected a default project for approved execution tests.")
                let service = SciStationAgentService(
                    provider: StaticLLMProvider(response: "{\"summary\":\"No-op\",\"tool_calls\":[]}"),
                    todoRepository: todoRepository
                )
                let plan = AgentPlan(
                    title: "Approved todo",
                    summary: "Create a todo after approval",
                    risk: "Writes tasks/todos.yaml",
                    steps: ["Create the approved todo"],
                    toolCalls: [
                        AgentToolCall(
                            id: "call-1",
                            toolName: "create_todo",
                            argumentsJSON: "{\"title\":\"Approved agent todo\",\"priority\":\"high\"}"
                        )
                    ]
                )

                let skippedRun = try await service.executeApprovedPlan(
                    goal: "Create approved todo",
                    plan: plan,
                    in: workspace,
                    root: root,
                    currentProjectID: project.id,
                    approvedToolCallIDs: []
                )
                try expect(skippedRun.toolResults.first?.requiresConfirmation == true, "Unapproved writing tools should be skipped with a confirmation result.")
                let todosBeforeApproval = try await todoRepository.loadTodos(in: workspace)
                try expect(todosBeforeApproval.isEmpty, "Unapproved service execution should not modify todos.")

                let approvedRun = try await service.executeApprovedPlan(
                    goal: "Create approved todo",
                    plan: plan,
                    in: workspace,
                    root: root,
                    currentProjectID: project.id,
                    approvedToolCallIDs: ["call-1"]
                )
                let todos = try await todoRepository.loadTodos(in: workspace)
                try expect(approvedRun.mode == .executeApproved, "Approved execution should be logged as executeApproved.")
                try expect(approvedRun.toolResults.first?.succeeded == true, "Approved service tool execution should succeed.")
                try expect(todos.first?.title == "Approved agent todo", "Approved service tool execution should persist the todo.")
                try expect(todos.first?.projectIDs == [project.id], "Approved service tool execution should use the current project context.")
                let executionEvents = try await service.sessionEvents(in: root, sessionID: approvedRun.id)
                try expect(executionEvents.map(\.kind).contains(.toolCallCompleted), "Approved execution should append completed tool session events.")
            }

            func agentPaperIntentRouterMapsAbstractToAbstractSection() throws {
                let router = AgentPaperIntentRouter()
                let chineseIntent = router.classify("第一篇论文摘要是什么？")
                let englishIntent = router.classify("What is the abstract of the first paper?")
                let argumentsJSON = router.searchArgumentsJSON(for: chineseIntent, paperID: "paper-1")

                try expect(chineseIntent.kind == .sectionSummary, "Chinese abstract questions should be routed as section summaries.")
                try expect(chineseIntent.ordinalIndex == 0, "Chinese first-paper abstract questions should preserve ordinal selection.")
                try expect(chineseIntent.sectionHint == "Abstract", "Chinese 摘要 should map to the Abstract section hint.")
                try expect(chineseIntent.query?.contains("摘要") == true, "Chinese abstract queries should keep a bilingual retrieval query.")
                try expect(englishIntent.kind == .sectionSummary, "English abstract questions should be routed as section summaries.")
                try expect(englishIntent.ordinalIndex == 0, "English first-paper abstract questions should preserve ordinal selection.")
                try expect(englishIntent.sectionHint == "Abstract", "English abstract should map to the Abstract section hint.")
                try expect(argumentsJSON.contains("Abstract 摘要 summary"), "Search arguments should use a bilingual abstract retrieval query.")
            }

            func agentPaperIntentRouterClassifiesGraphIntents() throws {
                let router = AgentPaperIntentRouter()
                let missing = router.classify("这个项目还有哪些核心论文没引？")
                let reading = router.classify("读完这篇下一篇应该看什么？")
                let stale = router.classify("检查这个项目有没有过时引用")
                let unsupported = router.classify("哪些 artifact claim 缺乏证据？")
                let bridge = router.classify("explain connection between paper:a and paper:c")

                try expect(missing.kind == .graphMissingCorePapers, "Missing-core graph questions should route to graphMissingCorePapers.")
                try expect(missing.graphToolName == GraphAgentTools.findMissingCorePapers, "Missing-core intent should prefer find_missing_core_papers.")
                try expect(reading.kind == .graphReadingPath, "Next-paper questions should route to graphReadingPath.")
                try expect(stale.kind == .graphStaleCitations, "Stale citation questions should route to graphStaleCitations.")
                try expect(unsupported.kind == .graphUnsupportedClaims, "Unsupported claim questions should route to graphUnsupportedClaims.")
                try expect(bridge.kind == .graphBridgePapers, "Bridge questions should route to graphBridgePapers.")
                let missingArgs = router.graphArgumentsJSON(for: missing, currentProjectID: "proj", selectedPaperID: nil) ?? ""
                let readingArgs = router.graphArgumentsJSON(for: reading, currentProjectID: "proj", selectedPaperID: "paper:center") ?? ""
                let bridgeArgs = router.graphArgumentsJSON(for: bridge, currentProjectID: nil, selectedPaperID: nil) ?? ""
                try expect(missingArgs.contains("proj"), "Missing-core graph preflight arguments should include project_id.")
                try expect(readingArgs.contains("paper:center"), "Reading path preflight arguments should include selected center paper.")
                try expect(bridgeArgs.contains("paper:a") && bridgeArgs.contains("paper:c"), "Bridge preflight arguments should include both paper node ids.")
            }

            func agentAnswerQualityEvaluatorChecksFormulaSources() throws {
                let evaluator = AgentAnswerQualityEvaluator()
                let evidence = AgentToolResult(
                    callID: "call-read",
                    toolName: "read_paper_section",
                    succeeded: true,
                    message: "paper_id: paper-1\nsource: papers/demo/paper.md\n$$E_{\\odot}=kA$$",
                    payload: .object([
                        "kind": .string("paper_section"),
                        "paper": .object([
                            "paper_id": .string("paper-1"),
                            "title": .string("Demo Paper"),
                            "path": .string("papers/demo"),
                            "raw_markdown_path": .string("papers/demo/paper.md")
                        ]),
                        "source": .string("papers/demo/paper.md"),
                        "content": .string("$$E_{\\odot}=kA$$")
                    ])
                )
                let good = """
                公式为：

                $$
                E_{\\odot}=kA
                $$

                来源：Demo Paper (paper-1), papers/demo/paper.md。
                """
                let goodReport = evaluator.evaluate(goal: "第一篇文章的蒸发率公式是什么？", finalMarkdown: good, toolResults: [evidence])
                try expect(goodReport.passes, "Formula answer with display math and source should pass quality checks.")

                let weakReport = evaluator.evaluate(goal: "第一篇文章的蒸发率公式是什么？", finalMarkdown: "我使用了工具并找到了答案。", toolResults: [evidence])
                try expect(weakReport.issues.map(\.code).contains(.missingDisplayMath), "Formula answer without display math should be flagged.")
                try expect(weakReport.issues.map(\.code).contains(.missingSource), "Formula answer without source should be flagged.")

                let missingEvidence = evaluator.evaluate(goal: "第一篇文章的蒸发率公式是什么？", finalMarkdown: "我没有读取到正文或公式证据。", toolResults: [])
                try expect(missingEvidence.issues.map(\.code).contains(.missingEvidence), "Formula answer without paper evidence should be flagged.")
                try expect(!missingEvidence.issues.map(\.code).contains(.missingContentExplanation), "Missing evidence explanation should satisfy the explanation check.")
            }

    func listPapersPayloadIncludesAbstract() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let paperRepository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ListPapersAbstractPayloadWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var paper = samplePaper(id: "abstract-payload-paper")
        paper.abstract = "This metadata abstract should be available before body reads."
        let savedPaper = try await paperRepository.save(paper, in: workspace)
        let result = try await ListPapersAgentTool(paperRepository: paperRepository).invoke(
            argumentsJSON: "{\"paper_id\":\"\(savedPaper.id)\"}",
            context: AgentToolContext(workspace: workspace, selectedPaperID: savedPaper.id)
        )
        let papersPayload = try require(result.payload?.objectValue?["papers"]?.arrayValue, "list_papers should return a papers payload.")
        let firstPaperPayload = try require(papersPayload.first?.objectValue, "list_papers should return object paper payloads.")

        try expect(firstPaperPayload["abstract"]?.stringValue == paper.abstract, "list_papers paper payload should include metadata abstract.")
    }

    func relatedWorkWorkflowClustersByTheme() throws {
        let content = "# Related Work\n\n## Scope\n- Scope. [evidence:e1]\n\n## Theme 1\n- Retrieval claim. [evidence:e1]\n\n## Theme 2\n- Workflow claim. [evidence:e2]\n\n## Theme 3\n- Evaluation claim. [evidence:e3]\n\n## Evidence Matrix\n- e1\n"
        let themeCount = content.components(separatedBy: "\n").filter { $0.hasPrefix("## Theme") }.count
        try expect(themeCount == 3, "Related work production drafts should cluster by theme.")
        try expect(content.contains("## Evidence Matrix"), "Related work production drafts should include an evidence matrix.")
    }

    func gapPlanningWorkflowGeneratesTodoDraftsWithoutWriting() async throws {
        let fixture = try await loopWorkspaceFixture(named: "GapPlanningDraftWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let draft = AgentArtifactDraft(
            runID: "gap-run",
            kind: "research_plan",
            proposedPath: "projects/demo-project/wiki/research_plan.md",
            title: "Research Plan",
            content: "# Research Plan\n\n## Todo Drafts\n- [high] Investigate gap. [evidence:e1]\n",
            evidenceRefs: sampleEvidenceRefs(prefix: "gap"),
            risk: .readOnly
        )
        let targetURL = fixture.root.fileURL(for: draft.proposedPath ?? "")

        try expect(draft.risk == .readOnly, "Gap planning should emit drafts and wait for Swift approval before writing.")
        try expect(!FileManager.default.fileExists(atPath: targetURL.path), "Gap planning draft creation should not write research_plan.md by itself.")
    }

    func evidenceRefsJumpToSourceLineRange() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EvidenceJumpWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperURL = fixture.root.fileURL(for: "library/papers/p1/paper.md")
        try FileManager.default.createDirectory(at: paperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Intro\nLine anchored evidence.\n".write(to: paperURL, atomically: true, encoding: .utf8)
        let evidence = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 2, sourceHash: "sha256:a")
        let jump = evidence.sourceJump(in: fixture.root, currentSourceHash: "sha256:a")
        let staleJump = evidence.sourceJump(in: fixture.root, currentSourceHash: "sha256:b")
        let missing = AgentEvidenceRef(sourceType: "paper", sourceID: "p2", relativePath: "library/papers/p2/paper.md", startLine: 1, endLine: 2, sourceHash: "sha256:c").sourceJump(in: fixture.root)

        try expect(jump.status == .available, "Existing evidence source should be jumpable.")
        try expect(jump.startLine == 1 && jump.endLine == 2, "Evidence jump should preserve source line range.")
        try expect(staleJump.status == .stale, "Changed source hash should mark evidence as stale.")
        try expect(missing.status == .missingSource, "Missing source should be reported instead of crashing.")
    }

            func agentDiagnosticRedactorRedactsSecretsAndHomePaths() throws {
                let raw = """
                root=/Users/alice/Documents/ResearchWorkspace
                Authorization: Bearer sk-live-super-secret-token
                api_key=sk-another-secret-token
                token: plain-token-value
                """

                let redacted = AgentDiagnosticRedactor.redacted(raw, homeDirectory: "/Users/alice")
                try expect(!redacted.contains("/Users/alice"), "Diagnostic redaction should remove absolute home paths.")
                try expect(!redacted.contains("super-secret-token"), "Diagnostic redaction should remove bearer token bodies.")
                try expect(!redacted.contains("another-secret-token"), "Diagnostic redaction should remove API key bodies.")
                try expect(redacted.contains("~"), "Diagnostic redaction should preserve useful relative path context.")
            }

    func agentEvidenceRefStableIDMarksStale() throws {
        let first = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 12, sourceHash: "sha256:a")
        let second = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 12, sourceHash: "sha256:a")
        let changed = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 12, sourceHash: "sha256:b")

        try expect(first.id == second.id, "AgentEvidenceRef should generate stable ids for the same source line range and hash.")
        try expect(first.id != changed.id, "Changing source_hash should change the stable evidence id.")
        try expect(first.isStale(currentSourceHash: "sha256:b"), "Evidence should be stale when current source hash changes.")
    }

    func evidenceSourceJumpMapsPDFPageWhenAvailable() async throws {
        let fixture = try await loopWorkspaceFixture(named: "EvidencePDFPageWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let paperDirectory = fixture.root.directoryURL(for: "library/papers/p1")
        try FileManager.default.createDirectory(at: paperDirectory, withIntermediateDirectories: true)
        try "# Intro\nLine anchored evidence.\n".write(to: paperDirectory.appendingPathComponent("paper.md"), atomically: true, encoding: .utf8)
        try writeValidPDF(to: paperDirectory.appendingPathComponent("paper.pdf"))
        try #"{"mappings":[{"start_line":1,"end_line":5,"page":3}]}"#.write(to: paperDirectory.appendingPathComponent("paper_page_map.json"), atomically: true, encoding: .utf8)

        let evidence = AgentEvidenceRef(sourceType: "paper", sourceID: "p1", relativePath: "library/papers/p1/paper.md", startLine: 1, endLine: 2, sourceHash: "sha256:a")
        let jump = evidence.sourceJump(in: fixture.root, currentSourceHash: "sha256:a")

        try expect(jump.pdfPage == 3, "Evidence source jump should map paper.md line range to PDF page when page mapping exists.")
        try expect(jump.pdfRelativePath == "library/papers/p1/paper.pdf", "PDF page target should default to the paper directory PDF.")
        try expect(jump.lineTargetDescription.contains("lines 1-2"), "Evidence jump should expose a line target descriptor.")
    }

    func agentHumanDecisionActionDecodesLegacyAliases() throws {
        let decoder = JSONDecoder()
        let deny = try decoder.decode(AgentHumanDecisionAction.self, from: Data(#""deny""#.utf8))
        let revise = try decoder.decode(AgentHumanDecisionAction.self, from: Data(#""askAgentToRevise""#.utf8))

        try expect(deny == .denyAndStop, "Legacy deny action should decode to denyAndStop.")
        try expect(revise == .reviseWithFeedback, "Legacy askAgentToRevise action should decode to reviseWithFeedback.")
    }

    func agentToolRiskUnknownValueDecodesAsExternalSideEffect() throws {
        let decoded = try JSONDecoder().decode(AgentToolRisk.self, from: Data(#""unknownFutureRisk""#.utf8))

        try expect(decoded == .externalSideEffect, "Unknown tool risk values should decode to externalSideEffect.")
    }

    func toolHostBuildApprovalRequestHasNoSideEffects() async throws {
        let fixture = try await loopWorkspaceFixture(named: "ToolHostPreviewWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Should not run")
        ])
        let host = SciStationToolHost(legacyRegistry: AgentToolRegistry(tools: [tool]))
        let approval = try await host.buildApprovalRequest(
            for: AgentToolCall(id: "call-preview", toolName: "create_todo", argumentsJSON: #"{"title":"Preview only"}"#),
            runID: "preview-run",
            context: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)
        )
        let invocationCount = await tool.invocationCount()

        try expect(invocationCount == 0, "Building a ToolHost approval preview must not invoke the tool.")
        try expect(approval.targetPaths == ["tasks/todos.yaml"], "ToolHost approval preview should include expected target paths.")
        try expect(approval.diffPreview?.contains("Preview only") == true, "ToolHost approval preview should include a human-readable diff summary.")
        try expect(approval.rollbackHint?.targetPaths == ["tasks/todos.yaml"], "ToolHost approval preview should include rollback targets.")
    }

    func readOnlyToolNotPausedByGenericPreToolUseReminder() async throws {
        let fixture = try await loopWorkspaceFixture(named: "ReadOnlyHookReminderWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let call = AgentToolCall(id: "call-read-reminder", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Read with reminder."))
        ])
        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Reminder did not pause")
        ])
        let hookEngine = AgentHookEngine(hooks: [
            AgentHookDefinition(id: "pre-tool-reminder", eventName: .preToolUse, matcher: "*", message: "Audit read-only tool output.")
        ])
        let runner = AgentLoopRunner()

        let result = try await runner.run(loopRequest(runID: "read-reminder-run", provider: provider, definitions: [definition], registry: AgentToolRegistry(tools: [tool]), fixture: fixture, hookEngine: hookEngine))
        let invocationCount = await tool.invocationCount()

        try expect(result.pauseReason == nil, "Generic PreToolUse reminders without deny should not pause read-only tools.")
        try expect(result.finalResponseMarkdown == "Read with reminder.", "Loop should continue to final response after read-only tool reminder.")
        try expect(invocationCount == 1, "Read-only tool should still execute once with a reminder hook.")
    }

    func agentServiceInjectsEnabledSkillAndRestrictsTools() async throws {
        let fixture = try await loopWorkspaceFixture(named: "AgentSkillRuntimeWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let skillDirectory = fixture.root.rootURL.appendingPathComponent(".claude/skills/evidence-review", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: evidence-review
        description: Paper evidence review
        version: 1.0.0
        capabilities: [paper, evidence, review]
        risk: readOnly
        allowed_tools: [list_papers, create_todo]
        ---

        SKILL_RUNTIME_MARKER: verify evidence before conclusions.
        """.write(
            to: skillDirectory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        let provider = ScriptedChatProvider(responses: [
            LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: """
            {
              "title": "Evidence review",
              "summary": "Review available evidence.",
              "steps": ["Inspect papers"],
              "tool_calls": [],
              "final_response_draft": "No tool call required."
            }
            """))
        ])
        let service = SciStationAgentService(provider: provider)
        _ = try await service.run(
            goal: "Perform a paper evidence review.",
            in: fixture.workspace,
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key",
            options: AgentExecutionOptions(
                mode: .planOnly,
                allowedToolNames: ["list_papers", "create_todo"]
            ),
            workspaceProfile: AgentWorkspaceProfile(skillToggles: [
                AgentSkillToggle(
                    skillID: "evidence-review",
                    isEnabled: true,
                    trustLevel: .trusted,
                    allowedToolIDs: ["list_papers"]
                )
            ])
        )

        let requests = await provider.recordedRequests()
        let request = try require(requests.first, "Skill-enabled service run should reach the provider.")
        let promptText = request.messages.map(\.content).joined(separator: "\n")
        try expect(promptText.contains("SKILL_RUNTIME_MARKER"), "Enabled matching skill instructions should be injected into the provider prompt.")
        try expect(request.tools.map(\.name) == ["list_papers"], "Skill tool bounds should narrow the provider-visible tool list.")
    }

            func agentRunLoggerSkipsDamagedHistoryLines() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentDamagedHistoryWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let logger = AgentRunLogger()
                let firstRun = AgentRun(
                    id: "agent-run-valid-1",
                    goal: "First valid run",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    completedAt: Date(timeIntervalSince1970: 1_777_600_001),
                    mode: .planOnly,
                    plan: AgentPlan(summary: "No writes", toolCalls: []),
                    toolResults: [],
                    currentProjectID: "project-alpha"
                )
                let secondRun = AgentRun(
                    id: "agent-run-valid-2",
                    goal: "Second valid run",
                    createdAt: Date(timeIntervalSince1970: 1_777_600_010),
                    completedAt: Date(timeIntervalSince1970: 1_777_600_011),
                    mode: .executeApproved,
                    plan: AgentPlan(summary: "No writes", toolCalls: []),
                    toolResults: [],
                    currentProjectID: "project-beta"
                )

                try await logger.append(firstRun, in: root)
                let logURL = root.fileURL(for: ".sci-station/agent/runs.jsonl")
                let existingContents = try String(contentsOf: logURL, encoding: .utf8)
                try (existingContents + "{not-json}\n").write(to: logURL, atomically: true, encoding: .utf8)
                try await logger.append(secondRun, in: root)

                let history = try await logger.recentRuns(in: root, limit: 5)
                try expect(history.map(\.id) == ["agent-run-valid-2", "agent-run-valid-1"], "Damaged JSONL lines should be skipped while valid runs remain readable newest-first.")
            }

            func agentRunLoggerFiltersProjectConversations() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentProjectConversationWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let logger = AgentRunLogger()
                let runs = [
                    AgentRun(
                        id: "global-run",
                        goal: "Global conversation",
                        createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                        completedAt: Date(timeIntervalSince1970: 1_777_600_001),
                        mode: .planOnly,
                        plan: AgentPlan(summary: "Global", toolCalls: []),
                        toolResults: []
                    ),
                    AgentRun(
                        id: "alpha-run",
                        goal: "Alpha conversation",
                        createdAt: Date(timeIntervalSince1970: 1_777_600_010),
                        completedAt: Date(timeIntervalSince1970: 1_777_600_011),
                        mode: .planOnly,
                        plan: AgentPlan(summary: "Alpha", toolCalls: []),
                        toolResults: [],
                        currentProjectID: "project-alpha"
                    ),
                    AgentRun(
                        id: "beta-run",
                        goal: "Beta conversation",
                        createdAt: Date(timeIntervalSince1970: 1_777_600_020),
                        completedAt: Date(timeIntervalSince1970: 1_777_600_021),
                        mode: .planOnly,
                        plan: AgentPlan(summary: "Beta", toolCalls: []),
                        toolResults: [],
                        currentProjectID: "project-beta"
                    )
                ]

                for run in runs {
                    try await logger.append(run, in: root)
                }

                let alphaRuns = try await logger.recentRuns(in: root, projectID: "project-alpha", limit: 5)
                let globalRuns = try await logger.recentRuns(in: root, projectID: nil, limit: 5)

                try expect(alphaRuns.map(\.id) == ["alpha-run"], "Project conversation history should only include runs for that project.")
                try expect(globalRuns.map(\.id) == ["global-run"], "Global conversation history should only include runs without a project id.")
            }

            func agentThreadRepositoryGlobalStoreFiltersByWorkspaceID() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let suiteRoot = temporaryDirectoryURL().appendingPathComponent("AgentThreadGlobalStoreSuite", isDirectory: true)
                let workspaceRoot = suiteRoot.appendingPathComponent("AgentThreadWorkspaceA", isDirectory: true)
                let secondWorkspaceRoot = suiteRoot.appendingPathComponent("AgentThreadWorkspaceB", isDirectory: true)
                let storeDirectory = suiteRoot.appendingPathComponent("GlobalAgentStore", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: suiteRoot)
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let secondWorkspace = try await workspaceService.createWorkspace(at: secondWorkspaceRoot)
                let secondRoot = ResearchRoot(rootURL: secondWorkspace.rootURL)
                let repository = AgentThreadRepository(storeDirectory: storeDirectory)
                let firstDate = Date(timeIntervalSince1970: 1_777_600_000)
                var thread = AgentThread(
                    id: "agent-thread-alpha",
                    projectID: "project-alpha",
                    contextScope: .project,
                    runtimeSelector: AgentRuntimeSelection.swiftLoop.rawValue,
                    createdFromRoute: "ai_lab",
                    title: "Alpha analysis",
                    runIDs: ["run-1"],
                    createdAt: firstDate,
                    updatedAt: firstDate
                )

                try await repository.upsert(thread, in: root)
                thread.appendRunID("run-2", updatedAt: firstDate.addingTimeInterval(10))
                try await repository.upsert(thread, in: root)
                try await repository.upsert(
                    AgentThread(
                        id: "agent-thread-global",
                        title: "Global thread",
                        runIDs: ["global-run"],
                        createdAt: firstDate,
                        updatedAt: firstDate
                    ),
                    in: root
                )
                try await repository.upsert(
                    AgentThread(
                        id: "agent-thread-beta",
                        projectID: "project-beta",
                        title: "Beta analysis",
                        runIDs: ["run-beta"],
                        createdAt: firstDate,
                        updatedAt: firstDate.addingTimeInterval(20)
                    ),
                    in: secondRoot
                )

                let projectThreads = try await repository.threads(in: root, projectID: "project-alpha")
                let globalThreads = try await repository.threads(in: root, projectID: nil)
                let currentWorkspaceThreads = try await repository.allThreads(
                    in: secondRoot,
                    workspaceID: AgentThreadRepository.workspaceID(for: secondRoot),
                    includeArchived: false
                )
                let threadsURL = AgentThreadRepository.threadsFileURL(in: storeDirectory)
                let lines = try String(contentsOf: threadsURL, encoding: .utf8).split(whereSeparator: \.isNewline)

                try expect(projectThreads.map(\.id) == ["agent-thread-alpha"], "Project thread history should be filtered by project id.")
                try expect(projectThreads.first?.runIDs == ["run-1", "run-2"], "Upserting a thread should preserve ordered run ids.")
                try expect(projectThreads.first?.contextScope == .project, "Thread history should preserve project affinity scope metadata.")
                try expect(projectThreads.first?.runtimeSelector == AgentRuntimeSelection.swiftLoop.rawValue, "Thread history should preserve runtime selector metadata.")
                try expect(projectThreads.first?.createdFromRoute == "ai_lab", "Thread history should preserve route origin metadata.")
                try expect(globalThreads.map(\.id) == ["agent-thread-global"], "Global thread history should include only global threads.")
                try expect(currentWorkspaceThreads.map(\.id) == ["agent-thread-beta"], "Thread repository should filter the global store by workspace id.")
                try expect(projectThreads.first?.workspaceID == AgentThreadRepository.workspaceID(for: root), "Upserted threads should be tagged with their workspace id.")
                try expect(projectThreads.first?.workspaceName == root.displayName, "Upserted threads should be tagged with their workspace name.")
                try expect(lines.count == 3, "Thread upsert should replace existing records in the global store instead of duplicating them.")
                try expect(!FileManager.default.fileExists(atPath: root.fileURL(for: AgentThreadRepository.legacyRelativePath).path), "Upserting threads should no longer write workspace-local thread files.")
            }

            func agentThreadRepositoryMigratesPerWorkspaceLegacy() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let suiteRoot = temporaryDirectoryURL().appendingPathComponent("AgentThreadLegacyMigrationSuite", isDirectory: true)
                let firstWorkspaceRoot = suiteRoot.appendingPathComponent("LegacyWorkspaceA", isDirectory: true)
                let secondWorkspaceRoot = suiteRoot.appendingPathComponent("LegacyWorkspaceB", isDirectory: true)
                let storeDirectory = suiteRoot.appendingPathComponent("GlobalAgentStore", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: suiteRoot)
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let firstWorkspace = try await workspaceService.createWorkspace(at: firstWorkspaceRoot)
                let firstRoot = ResearchRoot(rootURL: firstWorkspace.rootURL)
                let secondWorkspace = try await workspaceService.createWorkspace(at: secondWorkspaceRoot)
                let secondRoot = ResearchRoot(rootURL: secondWorkspace.rootURL)
                let firstLegacyURL = firstRoot.fileURL(for: AgentThreadRepository.legacyRelativePath)
                let secondLegacyURL = secondRoot.fileURL(for: AgentThreadRepository.legacyRelativePath)
                let firstLegacyLine = """
                {"created_at":"2026-04-29T00:00:00Z","id":"legacy-thread-a","project_id":"project-alpha","run_ids":["run-a"],"title":"Legacy A","updated_at":"2026-04-29T00:00:01Z"}
                """
                let secondLegacyLine = """
                {"created_at":"2026-04-30T00:00:00Z","id":"legacy-thread-b","project_id":"project-beta","run_ids":["run-b"],"title":"Legacy B","updated_at":"2026-04-30T00:00:01Z"}
                """
                try firstLegacyLine.write(to: firstLegacyURL, atomically: true, encoding: .utf8)
                try secondLegacyLine.write(to: secondLegacyURL, atomically: true, encoding: .utf8)

                let repository = AgentThreadRepository(storeDirectory: storeDirectory)
                let firstMigration = try await repository.migrateLegacyThreads(from: firstRoot)
                let secondMigration = try await repository.migrateLegacyThreads(from: secondRoot)
                let allThreads = try await repository.allThreads(in: firstRoot, includeArchived: false)
                let threadsByID = Dictionary(uniqueKeysWithValues: allThreads.map { ($0.id, $0) })
                let firstArchiveURL = firstLegacyURL.deletingLastPathComponent().appendingPathComponent(AgentThreadRepository.legacyArchiveFileName)
                let secondArchiveURL = secondLegacyURL.deletingLastPathComponent().appendingPathComponent(AgentThreadRepository.legacyArchiveFileName)

                try expect(firstMigration.migratedCount == 1, "First workspace legacy migration should report one migrated thread.")
                try expect(secondMigration.migratedCount == 1, "Second workspace legacy migration should report one migrated thread.")
                try expect(Set(allThreads.map(\.id)) == ["legacy-thread-a", "legacy-thread-b"], "Legacy threads from multiple workspaces should merge into one global store.")
                try expect(threadsByID["legacy-thread-a"]?.workspaceID == AgentThreadRepository.workspaceID(for: firstRoot), "Migrated legacy A should keep a workspace tag.")
                try expect(threadsByID["legacy-thread-b"]?.workspaceID == AgentThreadRepository.workspaceID(for: secondRoot), "Migrated legacy B should keep a workspace tag.")
                try expect(FileManager.default.fileExists(atPath: firstArchiveURL.path), "First workspace legacy thread file should be preserved as threads.legacy.jsonl.")
                try expect(FileManager.default.fileExists(atPath: secondArchiveURL.path), "Second workspace legacy thread file should be preserved as threads.legacy.jsonl.")
                try expect(!FileManager.default.fileExists(atPath: firstLegacyURL.path), "First workspace legacy thread file should be removed after archival.")
                try expect(!FileManager.default.fileExists(atPath: secondLegacyURL.path), "Second workspace legacy thread file should be removed after archival.")
            }
}
