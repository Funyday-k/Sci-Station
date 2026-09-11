import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runAgentLoop() async {
        await runCheck("agentLoopBudgetDefaultsAreExpanded") { try agentLoopBudgetDefaultsAreExpanded() }
        await runCheck("llmRequestBuildsExpectedPayload") { try llmRequestBuildsExpectedPayload() }
        await runCheck("openAIProviderPreservesReasoningContent") { try openAIProviderPreservesReasoningContent() }
        await runCheck("openAIProviderRejectsThinkingModeToolReplayWithoutReasoning") { try openAIProviderRejectsThinkingModeToolReplayWithoutReasoning() }
        await runCheck("openAIProviderTreatsDeepSeekV4FlashAsThinkingMode") { try openAIProviderTreatsDeepSeekV4FlashAsThinkingMode() }
        await runCheck("llmConfigurationStorePersistsWithoutAPIKey") { try await llmConfigurationStorePersistsWithoutAPIKey() }
        await runCheck("llmAPIKeyResolverTrimsAndPrefersInMemoryKey") { try llmAPIKeyResolverTrimsAndPrefersInMemoryKey() }
        await runCheck("llmWritebackServiceKeepsDraftsSeparateFromWiki") { try await llmWritebackServiceKeepsDraftsSeparateFromWiki() }
        await runCheck("agentLoopRunnerCallsReadOnlyToolThenContinues") { try await agentLoopRunnerCallsReadOnlyToolThenContinues() }
        await runCheck("agentLoopRunnerReturnsVisibleFallbackAfterToolThenEmptyProvider") { try await agentLoopRunnerReturnsVisibleFallbackAfterToolThenEmptyProvider() }
        await runCheck("agentLoopRunnerEmptyResponseWithoutToolsKeepsContextFallback") { try await agentLoopRunnerEmptyResponseWithoutToolsKeepsContextFallback() }
        await runCheck("agentLoopRunnerReturnsVisibleProviderFailureAfterPreflightTools") { try await agentLoopRunnerReturnsVisibleProviderFailureAfterPreflightTools() }
        await runCheck("agentLoopRunnerPaperFormulaFlowUsesListSearchReadBeforeFinal") { try await agentLoopRunnerPaperFormulaFlowUsesListSearchReadBeforeFinal() }
        await runCheck("agentLoopRunnerFallsBackToReadPaperWhenSearchHasNoMatch") { try await agentLoopRunnerFallsBackToReadPaperWhenSearchHasNoMatch() }
        await runCheck("agentLoopRunnerPreflightEvidenceIsInjectedAsUserContext") { try await agentLoopRunnerPreflightEvidenceIsInjectedAsUserContext() }
        await runCheck("agentLoopRunnerThinkingModePayloadHasNoAssistantToolCallWithoutReasoning") { try await agentLoopRunnerThinkingModePayloadHasNoAssistantToolCallWithoutReasoning() }
        await runCheck("agentLoopRunnerPreservesReasoningContentForNativeToolCalls") { try await agentLoopRunnerPreservesReasoningContentForNativeToolCalls() }
        await runCheck("agentLoopRunnerPausesForWorkspaceWrite") { try await agentLoopRunnerPausesForWorkspaceWrite() }
        await runCheck("agentLoopRunnerStopsAtMaxSteps") { try await agentLoopRunnerStopsAtMaxSteps() }
        await runCheck("agentLoopRunnerInjectsToolResultMessages") { try await agentLoopRunnerInjectsToolResultMessages() }
        await runCheck("agentLoopRunnerResumesPendingApproval") { try await agentLoopRunnerResumesPendingApproval() }
        await runCheck("agentLoopRunnerDoesNotRepeatApprovedWriteOnResume") { try await agentLoopRunnerDoesNotRepeatApprovedWriteOnResume() }
        await runCheck("agentLoopRunnerEditArgumentsRevalidatesBeforeExecution") { try await agentLoopRunnerEditArgumentsRevalidatesBeforeExecution() }
        await runCheck("agentLoopRunnerSafetyDenyIsFatal") { try await agentLoopRunnerSafetyDenyIsFatal() }
        await runCheck("agentLoopRunnerCachesRepeatedReadOnlyToolCall") { try await agentLoopRunnerCachesRepeatedReadOnlyToolCall() }
        await runCheck("agentLoopRunnerStopsAtContextBudget") { try await agentLoopRunnerStopsAtContextBudget() }
        await runCheck("openAIProviderPayloadIncludesToolChoiceAuto") { try openAIProviderPayloadIncludesToolChoiceAuto() }
        await runCheck("openAIProviderNormalizesLegacyToolSchemas") { try openAIProviderNormalizesLegacyToolSchemas() }
        await runCheck("openAIStreamDeltaParserIgnoresBadChunks") { try openAIStreamDeltaParserIgnoresBadChunks() }
        await runCheck("llmProviderV2RequestModelsToolDefinitions") { try llmProviderV2RequestModelsToolDefinitions() }
    }

    func agentLoopBudgetDefaultsAreExpanded() throws {
        let options = AgentLoopOptions()
        try expect(options.maxSteps == 20, "Agent loop should default to 20 model steps.")
        try expect(options.maxToolCalls == 80, "Agent loop should default to a larger tool-call budget.")
        try expect(options.maxContextCharacters == 1_000_000, "Agent loop should default to a 1M context character budget.")
        try expect(options.maxToolResultCharactersPerCall == 384_000, "Agent loop should default to a 384K per-tool output budget.")
        try expect(options.maxAccumulatedToolResultCharacters == 1_000_000, "Agent loop should default to a 1M accumulated tool-result budget.")
        try expect(LLMConfiguration().maxTokens == 384_000, "LLM output should default to 384K max tokens for DeepSeek-class models.")
    }

            func llmRequestBuildsExpectedPayload() throws {
                let provider = OpenAICompatibleProvider()
                let configuration = LLMConfiguration(
                    provider: .openAICompatible,
                    baseURLString: "https://api.example.com/v1",
                    model: "test-model",
                    temperature: 0.3,
                    maxTokens: 256
                )

                let request = try provider.buildRequest(configuration: configuration, apiKey: "secret-key", prompt: "Summarize this paper")
                let body = try require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Expected request body to be encoded.")
                try expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions", "Provider should target /chat/completions on the configured base URL.")
                try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key", "Provider should attach the API key as a bearer token.")
                try expect(body.contains("test-model"), "Provider request body should contain the configured model.")
                try expect(body.contains("Summarize this paper"), "Provider request body should contain the prompt content.")
            }

                        func openAIProviderPreservesReasoningContent() throws {
                                let provider = OpenAICompatibleProvider()
                                let completionJSON = """
                                {
                                    "choices": [
                                        {
                                            "message": {
                                                "role": "assistant",
                                                "content": "I need a tool.",
                                                "reasoning_content": "private chain summary required by thinking-mode APIs",
                                                "tool_calls": [
                                                    {
                                                        "id": "call-1",
                                                        "type": "function",
                                                        "function": {
                                                            "name": "read_note",
                                                            "arguments": "{\\\"path\\\":\\\"paper.md\\\"}"
                                                        }
                                                    }
                                                ]
                                            }
                                        }
                                    ]
                                }
                                """
                                let parsed = try OpenAICompatibleProvider.parseChatCompletionMessage(from: Data(completionJSON.utf8))
                                try expect(parsed.reasoningContent?.contains("thinking-mode") == true, "Provider should parse reasoning_content from assistant responses.")
                                try expect(parsed.toolCalls.first?.toolName == "read_note", "Provider should preserve tool calls while parsing reasoning_content.")

                                let request = LLMProviderRequest(messages: [parsed])
                                let chatRequest = try provider.buildChatRequest(
                                        configuration: LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
                                        apiKey: "secret-key",
                                        providerRequest: request
                                )
                                let bodyData = try require(chatRequest.httpBody, "Expected chat body data.")
                                let root = try require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any], "Expected JSON request object.")
                                let messages = try require(root["messages"] as? [[String: Any]], "Expected messages array.")
                                try expect(messages.first?["reasoning_content"] as? String == parsed.reasoningContent, "Provider should pass assistant reasoning_content back in the next request.")
                        }

            func openAIProviderRejectsThinkingModeToolReplayWithoutReasoning() throws {
                let provider = OpenAICompatibleProvider()
                let call = AgentToolCall(id: "call-missing-reasoning", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
                let request = LLMProviderRequest(messages: [
                    LLMChatMessage(role: .assistant, content: "", toolCalls: [call])
                ])

                do {
                    _ = try provider.buildChatRequest(
                        configuration: LLMConfiguration(baseURLString: "https://api.deepseek.com", model: "deepseek-reasoner"),
                        apiKey: "secret-key",
                        providerRequest: request
                    )
                    throw ValidationError(message: "Thinking-mode request should reject assistant tool calls without reasoning_content.")
                } catch let error as LLMProviderRequestSanitizer.Failure {
                    try expect(error.localizedDescription.contains("reasoning_content"), "Sanitizer error should explain the missing reasoning_content replay requirement.")
                }
            }

            func openAIProviderTreatsDeepSeekV4FlashAsThinkingMode() throws {
                let call = AgentToolCall(id: "call-deepseek-v4", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
                let request = LLMProviderRequest(messages: [
                    LLMChatMessage(role: .assistant, content: "", toolCalls: [call])
                ])
                let configuration = LLMConfiguration(baseURLString: "https://api.deepseek.com/v1", model: "deepseek-v4-flash")

                try expect(
                    LLMProviderRequestSanitizer.requiresReasoningContentForToolReplay(request: request, configuration: configuration),
                    "DeepSeek v4 flash should use thinking-mode replay validation when assistant tool calls are present."
                )
            }

            func llmConfigurationStorePersistsWithoutAPIKey() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore
                )
                let store = LLMConfigurationStore()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LLMSettingsWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                try await store.save(
                    LLMConfiguration(
                        provider: .openAICompatible,
                        baseURLString: "https://api.example.com/v1",
                        model: "gpt-4.1-mini",
                        temperature: 0.2,
                        maxTokens: 1200
                    ),
                    in: workspace
                )

                let settingsContents = try String(contentsOf: workspace.fileURL(for: "settings.yaml"), encoding: .utf8)
                try expect(settingsContents.contains("base_url"), "LLM settings should be written to settings.yaml.")
                try expect(!settingsContents.lowercased().contains("api_key"), "API keys must not be written into settings.yaml.")
            }

            func llmAPIKeyResolverTrimsAndPrefersInMemoryKey() throws {
                try expect(
                    LLMAPIKeyResolver.resolve(inMemory: "  live-key  ", persisted: "stored-key") == "live-key",
                    "In-memory API keys should be trimmed and take precedence over persisted keys."
                )
                try expect(
                    LLMAPIKeyResolver.resolve(inMemory: " \n\t ", persisted: "  stored-key\n") == "stored-key",
                    "Persisted API keys should be trimmed when no in-memory key is available."
                )
                try expect(
                    LLMAPIKeyResolver.resolve(inMemory: " \n\t ", persisted: "   ").isEmpty,
                    "Blank in-memory and persisted API keys should resolve to an empty missing-key value."
                )
            }

            func llmWritebackServiceKeepsDraftsSeparateFromWiki() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore
                )
                let service = LLMWritebackService()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LLMWritebackWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = samplePaper(id: "writeback-paper")
                let wikiURL = workspace.fileURL(for: "wiki/papers/\(paper.citekey).md")
                try "# Original Wiki\n\nManual note.".write(to: wikiURL, atomically: true, encoding: .utf8)

                let firstDraft = try await service.write("Draft summary", to: wikiURL, mode: .saveDraft, paper: paper, in: workspace)
                let secondDraft = try await service.write("Second draft", to: wikiURL, mode: .saveDraft, paper: paper, in: workspace)
                let wikiAfterDraft = try String(contentsOf: wikiURL, encoding: .utf8)

                try expect(!firstDraft.didModifyWiki, "Saving a draft should report that the canonical wiki page was not modified.")
                try expect(firstDraft.writtenURL != secondDraft.writtenURL, "Multiple draft saves should not overwrite older drafts.")
                try expect(wikiAfterDraft == "# Original Wiki\n\nManual note.", "Saving a draft should leave the canonical wiki page unchanged.")

                let appendResult = try await service.write("Appended summary", to: wikiURL, mode: .append, paper: paper, in: workspace)
                let appendedWiki = try String(contentsOf: wikiURL, encoding: .utf8)

                try expect(appendResult.didModifyWiki, "Appending should report that the canonical wiki page was modified.")
                try expect(appendedWiki.contains("## AI Summary"), "Append mode should add an AI Summary section.")
                try expect(appendedWiki.contains("Appended summary"), "Append mode should write generated content.")

                let replaceResult = try await service.write("Replacement summary", to: wikiURL, mode: .replace, paper: paper, in: workspace)
                let replacedWiki = try String(contentsOf: wikiURL, encoding: .utf8)

                try expect(replaceResult.didModifyWiki, "Replace should report that the canonical wiki page was modified.")
                try expect(replacedWiki == "Replacement summary", "Replace mode should replace the canonical wiki content.")
            }

            func agentLoopRunnerCallsReadOnlyToolThenContinues() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopReadOnlyWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-read", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "最终回答包含 $E_{\\odot}$."))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "section 5 says E_sun_section_marker")
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-read-only",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let events = try await logger.events(in: fixture.root, sessionID: "loop-read-only")

                try expect(result.finalResponseMarkdown?.contains("E_{\\odot}") == true, "Loop should continue after a read-only tool and return the final assistant message.")
                try expect(result.toolResults.first?.message.contains("E_sun_section_marker") == true, "Loop should preserve read-only tool output.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Read-only tool should execute once.")
                try expect(events.map(\.kind).contains(.toolCallStarted), "Loop should append tool start events.")
                try expect(events.map(\.kind).contains(.toolCallCompleted), "Loop should append tool completion events.")
            }

            func agentLoopRunnerReturnsVisibleFallbackAfterToolThenEmptyProvider() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopEmptyProviderAfterToolWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-read-section", toolName: "read_paper_section", argumentsJSON: #"{"paper_id":"paper-1","heading":"Evaporation Rate"}"#)
                let provider = ScriptedFailingChatProvider(steps: [
                    .success(LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])),
                    .failure(.emptyResponse)
                ])
                let definition = loopToolDefinition(name: "read_paper_section", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_paper_section", succeeded: true, message: "Evaporation Rate marker: E_sun_section_marker and formula context.")
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-empty-provider-after-tool",
                    goal: "第一篇论文的 evaporation rate 公式是什么？",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let events = try await logger.events(in: fixture.root, sessionID: "loop-empty-provider-after-tool")

                try expect(result.pauseReason?.kind == .providerUnavailable, "Empty provider response after tool results should be represented as providerUnavailable.")
                try expect(result.finalResponseMarkdown?.contains("模型没有返回最终回复") == true, "Empty provider response after tool results should produce a visible Chinese fallback.")
                try expect(result.finalResponseMarkdown?.contains("E_sun_section_marker") == true, "Fallback should include the last tool result summary.")
                try expect(result.toolResults.first?.toolName == "read_paper_section", "Fallback should preserve the successful tool result.")
                try expect(events.contains { $0.kind == .toolCallCompleted && $0.summary == "已使用工具：read_paper_section" }, "Tool completion timeline should use a compact used-tool summary.")
                try expect(events.contains { $0.kind == .assistantMessage && $0.summary.contains("最后一个工具结果摘要") }, "Fallback should be appended as an assistant timeline event.")
            }

            func agentLoopRunnerEmptyResponseWithoutToolsKeepsContextFallback() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopEmptyProviderNoToolWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: ""))
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-empty-provider-no-tool",
                    goal: "继续总结这篇论文并保留草稿",
                    provider: provider,
                    definitions: [],
                    registry: AgentToolRegistry(tools: []),
                    fixture: fixture
                ))
                let events = try await logger.events(in: fixture.root, sessionID: "loop-empty-provider-no-tool")

                try expect(result.pauseReason?.kind == .providerUnavailable, "Empty provider response without tools should become providerUnavailable instead of throwing.")
                try expect(result.finalResponseMarkdown?.contains("上下文已保留") == true, "Empty provider response without tools should preserve context in a visible fallback.")
                try expect(result.toolResults.isEmpty, "No-tool fallback should not invent tool results.")
                try expect(events.contains { $0.kind == .assistantMessage && $0.summary.contains("上下文已保留") }, "No-tool fallback should be appended as an assistant event.")
            }

            func agentLoopRunnerReturnsVisibleProviderFailureAfterPreflightTools() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopPreflightProviderFailureWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let provider = ScriptedFailingChatProvider(steps: [
                    .failure(.httpError(statusCode: 400, message: "The reasoning_content in the thinking mode must be passed back to the API."))
                ])
                let listDefinition = loopToolDefinition(name: "list_papers", risk: .readOnly)
                let listTool = RecordingAgentTool(definition: listDefinition, results: [
                    AgentToolResult(
                        callID: "",
                        toolName: "list_papers",
                        succeeded: true,
                        message: "paper_id: paper-1\ntitle: Demo Paper",
                        payload: .object([
                            "kind": .string("paper_list"),
                            "papers": .array([.object([
                                "paper_id": .string("paper-1"),
                                "title": .string("Demo Paper")
                            ])])
                        ])
                    )
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-preflight-provider-failure",
                    goal: "请列出当前论文。",
                    provider: provider,
                    definitions: [listDefinition],
                    registry: AgentToolRegistry(tools: [listTool]),
                    fixture: fixture
                ))
                let requests = await provider.recordedRequests()

                try expect(result.pauseReason?.kind == .providerUnavailable, "Provider failure after deterministic preflight should become a visible providerUnavailable fallback.")
                try expect(result.finalResponseMarkdown?.contains("模型没有返回最终回复") == true, "Preflight provider failure should produce a visible Chinese fallback.")
                try expect(result.finalResponseMarkdown?.contains("复制脱敏诊断") == true, "Fallback should expose a copy-diagnostics action.")
                try expect(result.finalResponseMarkdown?.contains("paper-1") == true, "Fallback should summarize the already-read preflight tool result.")
                try expect(result.toolResults.map(\.toolName) == ["list_papers"], "Preflight tool result should be preserved when provider fails.")
                try expect(requests.count == 1, "Preflight failure should happen after one provider request with evidence context.")
                try expect(requests.first?.messages.contains { $0.role == .user && $0.content.contains("deterministic preflight evidence") } == true, "Provider request should include preflight evidence as user context.")
            }

            func agentLoopRunnerPaperFormulaFlowUsesListSearchReadBeforeFinal() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopPaperFormulaFlowWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: """
                    公式为：

                    $$
                    E_{\\odot}=k A (p_s-p_a)
                    $$

                    其中 $k$ 为局部系数，$A$ 为有效面积，$p_s-p_a$ 为压差。来源：Demo Paper (paper-1), papers/demo/paper.md。
                    """))
                ])
                let listDefinition = loopToolDefinition(name: "list_papers", risk: .readOnly)
                let searchDefinition = loopToolDefinition(name: "search_papers", risk: .readOnly)
                let readDefinition = loopToolDefinition(name: "read_paper_section", risk: .readOnly)
                let listTool = RecordingAgentTool(definition: listDefinition, results: [
                    AgentToolResult(
                        callID: "",
                        toolName: "list_papers",
                        succeeded: true,
                        message: "paper_id: paper-1\ntitle: Demo Paper\npath: papers/demo",
                        payload: .object([
                            "kind": .string("paper_list"),
                            "papers": .array([.object([
                                "paper_id": .string("paper-1"),
                                "title": .string("Demo Paper"),
                                "path": .string("papers/demo"),
                                "raw_markdown_path": .string("papers/demo/paper.md")
                            ])])
                        ])
                    )
                ])
                let searchTool = RecordingAgentTool(definition: searchDefinition, results: [
                    AgentToolResult(
                        callID: "",
                        toolName: "search_papers",
                        succeeded: true,
                        message: "Matched Demo Paper section Evaporation Rate.",
                        payload: .object([
                            "kind": .string("paper_search"),
                            "matches": .array([.object([
                                "paper_id": .string("paper-1"),
                                "title": .string("Demo Paper"),
                                "source": .string("papers/demo/paper.md"),
                                "heading": .string("Evaporation Rate"),
                                "line": .number("42"),
                                "snippet": .string("E_{\\odot}=k A (p_s-p_a)")
                            ])])
                        ])
                    )
                ])
                let readTool = RecordingAgentTool(definition: readDefinition, results: [
                    AgentToolResult(callID: "", toolName: "read_paper_section", succeeded: true, message: "## Evaporation Rate\n$E_{\\odot}=k A (p_s-p_a)$ with local symbol context.")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-paper-formula-flow",
                    goal: "第一篇论文里的 evaporation rate 公式是什么？",
                    provider: provider,
                    definitions: [listDefinition, searchDefinition, readDefinition],
                    registry: AgentToolRegistry(tools: [listTool, searchTool, readTool]),
                    fixture: fixture,
                    options: AgentLoopOptions(maxSteps: 5)
                ))
                let requests = await provider.recordedRequests()
                let listInvocationCount = await listTool.invocationCount()
                let searchInvocationCount = await searchTool.invocationCount()
                let readInvocationCount = await readTool.invocationCount()

                try expect(result.finalResponseMarkdown?.contains("$$") == true, "Paper formula flow should finish with display math.")
                try expect(result.finalResponseMarkdown?.contains("papers/demo/paper.md") == true, "Paper formula final answer should include a source path.")
                try expect(result.toolResults.map(\.toolName) == ["list_papers", "search_papers", "read_paper_section"], "Paper formula flow should preserve list/search/read tool order.")
                try expect(listInvocationCount == 1, "list_papers should run once.")
                try expect(searchInvocationCount == 1, "search_papers should run once.")
                try expect(readInvocationCount == 1, "read_paper_section should run once.")
                try expect(requests.count == 1, "Paper formula preflight should make one model request after deterministic read-only tools.")
                let finalRequest = try require(requests.last, "Expected the final provider request.")
                try expect(finalRequest.messages.filter { $0.role == .tool }.isEmpty, "Preflight evidence should not be sent as provider-native tool result messages.")
                try expect(!finalRequest.messages.contains { $0.role == .assistant && !$0.toolCalls.isEmpty }, "Preflight should not emit synthetic assistant tool-call messages.")
                let evidenceMessage = try require(finalRequest.messages.last(where: { $0.role == .user && $0.content.contains("deterministic preflight evidence") }), "Final request should include deterministic evidence as user context.")
                try expect(evidenceMessage.content.contains("preflight-list-papers"), "Evidence context should include the list_papers preflight call.")
                try expect(evidenceMessage.content.contains("preflight-search-papers"), "Evidence context should include the search_papers preflight call.")
                try expect(evidenceMessage.content.contains("preflight-read-paper-section"), "Evidence context should include the read_paper_section preflight call.")
            }

            func agentLoopRunnerFallsBackToReadPaperWhenSearchHasNoMatch() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopSearchEmptyFallbackWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Fallback answer from page 1 evidence."))
                ])
                let listDefinition = loopToolDefinition(name: "list_papers", risk: .readOnly)
                let searchDefinition = loopToolDefinition(name: "search_papers", risk: .readOnly)
                let readSectionDefinition = loopToolDefinition(name: "read_paper_section", risk: .readOnly)
                let readPaperDefinition = loopToolDefinition(name: "read_paper", risk: .readOnly)
                let listTool = RecordingAgentTool(definition: listDefinition, results: [
                    AgentToolResult(
                        callID: "",
                        toolName: "list_papers",
                        succeeded: true,
                        message: "paper_id: paper-1\ntitle: Demo Paper\npath: papers/demo",
                        payload: .object([
                            "kind": .string("paper_list"),
                            "papers": .array([.object([
                                "paper_id": .string("paper-1"),
                                "title": .string("Demo Paper"),
                                "path": .string("papers/demo"),
                                "raw_markdown_path": .string("papers/demo/paper.md")
                            ])])
                        ])
                    )
                ])
                let searchTool = RecordingAgentTool(definition: searchDefinition, results: [
                    AgentToolResult(
                        callID: "",
                        toolName: "search_papers",
                        succeeded: true,
                        message: "No matches for \"missing_marker\" in converted paper.md files.",
                        payload: .object([
                            "kind": .string("paper_search"),
                            "status": .string("empty_search"),
                            "matches": .array([])
                        ])
                    )
                ])
                let readSectionTool = RecordingAgentTool(definition: readSectionDefinition, results: [
                    AgentToolResult(callID: "", toolName: "read_paper_section", succeeded: true, message: "This should not run without a heading or line match.")
                ])
                let readPaperTool = RecordingAgentTool(definition: readPaperDefinition, results: [
                    AgentToolResult(callID: "", toolName: "read_paper", succeeded: true, message: "paper_id: paper-1\nsource: papers/demo/paper.md\nrange: page 1\n\nPage 1 fallback body evidence.")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-search-empty-fallback",
                    goal: "第一篇论文正文里 missing_marker 是什么？",
                    provider: provider,
                    definitions: [listDefinition, searchDefinition, readSectionDefinition, readPaperDefinition],
                    registry: AgentToolRegistry(tools: [listTool, searchTool, readSectionTool, readPaperTool]),
                    fixture: fixture,
                    options: AgentLoopOptions(maxSteps: 5)
                ))
                let requests = await provider.recordedRequests()
                let readSectionInvocationCount = await readSectionTool.invocationCount()
                let readPaperInvocationCount = await readPaperTool.invocationCount()

                try expect(result.finalResponseMarkdown == "Fallback answer from page 1 evidence.", "Loop should continue after page 1 fallback evidence.")
                try expect(result.toolResults.map(\.toolName) == ["list_papers", "search_papers", "read_paper"], "Empty search should fall back to read_paper instead of stopping after search.")
                try expect(readSectionInvocationCount == 0, "read_paper_section should not run when search produced no heading or line match.")
                try expect(readPaperInvocationCount == 1, "read_paper should run once as the page 1 fallback.")
                let evidenceMessage = try require(requests.first?.messages.last(where: { $0.role == .user && $0.content.contains("deterministic preflight evidence") }), "Fallback request should include deterministic preflight evidence.")
                try expect(evidenceMessage.content.contains("preflight-read-paper"), "Evidence context should include the read_paper fallback call.")
            }

            func agentLoopRunnerPreflightEvidenceIsInjectedAsUserContext() async throws {
                try await agentLoopRunnerPaperFormulaFlowUsesListSearchReadBeforeFinal()
            }

            func agentLoopRunnerThinkingModePayloadHasNoAssistantToolCallWithoutReasoning() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopThinkingModeMissingReasoningWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-read", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "This should not be reached."))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Tool evidence before sanitizer block.")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-thinking-mode-missing-reasoning",
                    goal: "请读取论文证据。",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture,
                    configuration: LLMConfiguration(baseURLString: "https://api.deepseek.com", model: "deepseek-reasoner")
                ))
                let requests = await provider.recordedRequests()

                try expect(result.pauseReason?.kind == .providerUnavailable, "Missing thinking-mode reasoning_content should be blocked before a bad replay request reaches the provider.")
                try expect(result.finalResponseMarkdown?.contains("reasoning_content") == true, "Visible fallback should include the sanitizer reason.")
                try expect(requests.count == 1, "Provider should not receive a second request containing assistant tool calls without reasoning_content.")
            }

            func agentLoopRunnerPreservesReasoningContentForNativeToolCalls() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopPreserveReasoningWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-read", toolName: "read_note", argumentsJSON: #"{"path":"paper.md"}"#)
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(
                        message: LLMChatMessage(
                            role: .assistant,
                            content: "",
                            reasoningContent: "thinking-mode tool replay token",
                            toolCalls: [call]
                        ),
                        toolCalls: [call]
                    ),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Final answer after preserved reasoning."))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Reasoned tool evidence.")
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-preserve-reasoning",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture,
                    configuration: LLMConfiguration(baseURLString: "https://api.deepseek.com", model: "deepseek-reasoner")
                ))
                let requests = await provider.recordedRequests()
                let secondRequest = try require(requests.dropFirst().first, "Reasoning-preserving provider should receive the replay request.")
                let assistantReplay = try require(secondRequest.messages.first { $0.role == .assistant && !$0.toolCalls.isEmpty }, "Replay request should include the provider-native assistant tool call.")
                let events = try await logger.events(in: fixture.root, sessionID: "loop-preserve-reasoning")

                try expect(result.finalResponseMarkdown == "Final answer after preserved reasoning.", "Loop should complete when provider-native tool calls include reasoning_content.")
                try expect(assistantReplay.reasoningContent == "thinking-mode tool replay token", "Provider-native tool replay should preserve assistant reasoning_content.")
                try expect(events.contains { $0.kind == .assistantMessage && ($0.payloadJSON?.contains("reasoning_content") ?? false) }, "Assistant session event payload should persist reasoning_content.")
            }

            func agentLoopRunnerPausesForWorkspaceWrite() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopWritePauseWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"Review\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created todo")
                ])
                let logger = AgentSessionEventLogger()
                let runner = AgentLoopRunner(sessionEventLogger: logger)

                let result = try await runner.run(loopRequest(
                    runID: "loop-write-pause",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let pending = try await AgentLoopCheckpointStore().pending(runID: "loop-write-pause", in: fixture.root)
                let events = try await logger.events(in: fixture.root, sessionID: "loop-write-pause")

                try expect(result.pauseReason?.kind == .approvalRequired, "Workspace writes should pause for approval.")
                try expect(result.pendingToolCall?.toolCall.toolName == "create_todo", "Paused result should include the pending tool call.")
                try expect(pending?.toolCall.id == "call-write", "Pending write tool call should be saved as a checkpoint.")
                try expect(events.map(\.kind).contains(.permissionRequested), "Loop should append a permissionRequested event.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 0, "Write tool must not run before approval.")
            }

            func agentLoopRunnerStopsAtMaxSteps() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopMaxStepsWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-repeat", toolName: "read_note", argumentsJSON: "{}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "same result")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-max-steps",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture,
                    options: AgentLoopOptions(maxSteps: 2)
                ))

                try expect(result.pauseReason?.kind == .maxStepsExceeded, "Loop should stop when maxSteps is exceeded.")
            }

            func agentLoopRunnerInjectsToolResultMessages() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopInjectsToolResultWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-inject", toolName: "read_note", argumentsJSON: "{}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Final"))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Injected evidence")
                ])
                let runner = AgentLoopRunner()

                _ = try await runner.run(loopRequest(
                    runID: "loop-inject",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))
                let requests = await provider.recordedRequests()
                let secondRequestMessages = try require(requests.dropFirst().first?.messages, "Expected a second model request.")
                let toolMessage = try require(secondRequestMessages.first { $0.role == .tool }, "Second request should include a tool result message.")

                try expect(toolMessage.toolCallID == "call-inject", "Tool result message should preserve tool_call_id.")
                try expect(toolMessage.content.contains("schema_version"), "Tool result message should be stable JSON.")
                try expect(toolMessage.content.contains("Injected evidence"), "Tool result message should include tool content.")
            }

            func agentLoopRunnerResumesPendingApproval() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopResumeWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"Resume\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Created after approval."))
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created todo", modifiedPaths: ["tasks/todos.yaml"])
                ])
                let registry = AgentToolRegistry(tools: [tool])
                let runner = AgentLoopRunner()
                let paused = try await runner.run(loopRequest(runID: "loop-resume", provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                let pending = try require(paused.pendingToolCall, "Expected pending write call.")

                let resumed = try await runner.resume(loopResumeRequest(
                    pending: pending,
                    action: .allowOnce,
                    provider: provider,
                    definitions: [definition],
                    registry: registry,
                    fixture: fixture
                ))

                try expect(resumed.finalResponseMarkdown?.contains("approval") == true, "Approved pending call should continue to a final assistant message.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Approved write should execute exactly once.")
            }

            func agentLoopRunnerDoesNotRepeatApprovedWriteOnResume() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopNoRepeatWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"No repeat\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Done once.")),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Done twice."))
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created once", modifiedPaths: ["tasks/todos.yaml"])
                ])
                let registry = AgentToolRegistry(tools: [tool])
                let runner = AgentLoopRunner()
                let paused = try await runner.run(loopRequest(runID: "loop-no-repeat", provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                let pending = try require(paused.pendingToolCall, "Expected pending write call.")

                _ = try await runner.resume(loopResumeRequest(pending: pending, action: .allowOnce, provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                _ = try await runner.resume(loopResumeRequest(pending: pending, action: .allowOnce, provider: provider, definitions: [definition], registry: registry, fixture: fixture))

                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Write ledger should prevent repeat execution for an already approved fingerprint.")
            }

            func agentLoopRunnerEditArgumentsRevalidatesBeforeExecution() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopEditArgsWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-write", toolName: "create_todo", argumentsJSON: "{\"title\":\"Original\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Created edited")
                ])
                let registry = AgentToolRegistry(tools: [tool])
                let runner = AgentLoopRunner()
                let paused = try await runner.run(loopRequest(runID: "loop-edit-args", provider: provider, definitions: [definition], registry: registry, fixture: fixture))
                let pending = try require(paused.pendingToolCall, "Expected pending write call.")

                let edited = try await runner.resume(loopResumeRequest(
                    pending: pending,
                    action: .editArguments,
                    editedArgumentsJSON: "{\"title\":\"Edited\"}",
                    provider: provider,
                    definitions: [definition],
                    registry: registry,
                    fixture: fixture
                ))

                try expect(edited.pauseReason?.kind == .approvalRequired, "Edited write arguments should be revalidated and return to approval instead of executing directly.")
                try expect(edited.pendingToolCall?.toolCall.argumentsJSON.contains("Edited") == true, "Edited arguments should be normalized into the new pending call.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 0, "Edited arguments should not execute before the fresh approval pass.")
            }

            func agentLoopRunnerSafetyDenyIsFatal() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopSafetyDenyWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-danger", toolName: "write_note", argumentsJSON: "{\"command\":\"git reset --hard\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "write_note", risk: .writesWorkspace)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "write_note", succeeded: true, message: "Should not run")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-safety-deny",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))

                try expect(result.pauseReason?.kind == .safetyPolicyBlocked, "Deterministic safety deny should stop the run.")
                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 0, "Safety-denied tools should never execute.")
            }

            func agentLoopRunnerCachesRepeatedReadOnlyToolCall() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopReadCacheWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let firstCall = AgentToolCall(id: "call-read-1", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                let secondCall = AgentToolCall(id: "call-read-2", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [firstCall, secondCall]), toolCalls: [firstCall, secondCall]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Cached final."))
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "Cached once")
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-read-cache",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture
                ))

                let invocationCount = await tool.invocationCount()
                try expect(invocationCount == 1, "Repeated read-only fingerprint should reuse cache in the same run.")
                try expect(result.steps.first?.cachedToolCallIDs == Optional(["call-read-2"]), "Loop step should record cached read-only call ids.")
            }

            func agentLoopRunnerStopsAtContextBudget() async throws {
                let fixture = try await loopWorkspaceFixture(named: "AgentLoopContextBudgetWorkspace")
                defer { cleanupLoopWorkspaceFixture(fixture) }

                let call = AgentToolCall(id: "call-large", toolName: "read_note", argumentsJSON: "{}")
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]),
                    LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call])
                ])
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly, maxOutputCharacters: 2_000)
                let tool = RecordingAgentTool(definition: definition, results: [
                    AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: String(repeating: "x", count: 1_600))
                ])
                let runner = AgentLoopRunner()

                let result = try await runner.run(loopRequest(
                    runID: "loop-context-budget",
                    provider: provider,
                    definitions: [definition],
                    registry: AgentToolRegistry(tools: [tool]),
                    fixture: fixture,
                    options: AgentLoopOptions(maxSteps: 4, maxAccumulatedToolResultCharacters: 1_000)
                ))

                try expect(result.pauseReason?.kind == .contextLimitExceeded, "Loop should stop when accumulated tool result budget is exceeded.")
                try expect(result.finalResponseMarkdown?.contains("context or tool result budget") == true, "Context budget stops should still produce a visible fallback reply when tool evidence exists.")
            }

            func openAIProviderPayloadIncludesToolChoiceAuto() throws {
                let provider = OpenAICompatibleProvider()
                let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
                let request = LLMProviderRequest(
                    messages: [
                        LLMChatMessage(role: .system, content: "Use tools."),
                        LLMChatMessage(role: .assistant, content: "", toolCalls: [
                            AgentToolCall(id: "call-1", toolName: "read_note", argumentsJSON: "{\"path\":\"paper.md\"}")
                        ]),
                        LLMChatMessage(role: .tool, content: "{\"schema_version\":1}", name: "read_note", toolCallID: "call-1")
                    ],
                    tools: [LLMToolSpecification(agentTool: definition)]
                )
                let chatRequest = try provider.buildChatRequest(
                    configuration: LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
                    apiKey: "secret-key",
                    providerRequest: request
                )
                let body = try require(chatRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Expected chat body.")

                try expect(body.contains("tool_choice"), "Provider payload should include tool_choice when tools are present.")
                try expect(body.contains("auto"), "Provider payload should set tool_choice to auto.")
                try expect(body.contains("tool_calls"), "Assistant messages should serialize tool_calls.")
                try expect(body.contains("tool_call_id"), "Tool result messages should serialize tool_call_id.")
            }

            func openAIProviderNormalizesLegacyToolSchemas() throws {
                let provider = OpenAICompatibleProvider()
                let definition = AgentToolDefinition(
                    name: "create_todo",
                    summary: "Create a todo.",
                    inputSchema: #"{"title":"string","priority":"low|medium|high|urgent optional","tags":["string"]}"#,
                    risk: .writesWorkspace
                )
                let chatRequest = try provider.buildChatRequest(
                    configuration: LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
                    apiKey: "secret-key",
                    providerRequest: LLMProviderRequest(
                        messages: [LLMChatMessage(role: .user, content: "Create a todo")],
                        tools: [LLMToolSpecification(agentTool: definition)]
                    )
                )
                let bodyData = try require(chatRequest.httpBody, "Expected chat body data.")
                let root = try require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any], "Expected JSON request object.")
                let tools = try require(root["tools"] as? [[String: Any]], "Expected tools array.")
                let function = try require(tools.first?["function"] as? [String: Any], "Expected function tool payload.")
                let parameters = try require(function["parameters"] as? [String: Any], "Expected tool parameters schema.")
                let properties = try require(parameters["properties"] as? [String: Any], "Expected schema properties.")
                let title = try require(properties["title"] as? [String: Any], "Expected title property schema.")
                let priority = try require(properties["priority"] as? [String: Any], "Expected priority property schema.")
                let tags = try require(properties["tags"] as? [String: Any], "Expected tags property schema.")

                try expect(parameters["type"] as? String == "object", "Provider should send a JSON Schema object for tool parameters.")
                try expect(title["type"] as? String == "string", "Legacy string shorthand should become a string property schema.")
                try expect((priority["enum"] as? [String]) == ["low", "medium", "high", "urgent"], "Pipe-delimited shorthand should become enum values.")
                try expect(tags["type"] as? String == "array", "Legacy array shorthand should become an array property schema.")
                try expect((parameters["required"] as? [String])?.contains("title") == true, "Non-optional legacy fields should be marked required.")
            }

            func openAIStreamDeltaParserIgnoresBadChunks() throws {
                let validChunk = Data(#"{"choices":[{"delta":{"content":"Hello"}}]}"#.utf8)
                let emptyDeltaChunk = Data(#"{"choices":[{"delta":{}}]}"#.utf8)
                let badChunk = Data("{not-json}".utf8)

                try expect(OpenAICompatibleStreamDeltaParser.contentDelta(from: validChunk) == "Hello", "SSE parser should decode content deltas.")
                try expect(OpenAICompatibleStreamDeltaParser.contentDelta(from: emptyDeltaChunk) == nil, "SSE parser should ignore empty deltas.")
                try expect(OpenAICompatibleStreamDeltaParser.contentDelta(from: badChunk) == nil, "SSE parser should ignore malformed JSON chunks.")
            }

            func llmProviderV2RequestModelsToolDefinitions() throws {
                let definition = AgentToolDefinition(
                    name: "create_todo",
                    summary: "Create a todo.",
                    inputSchema: "{\"title\":\"string\"}",
                    risk: .writesWorkspace
                )
                let tool = LLMToolSpecification(agentTool: definition)
                let request = LLMProviderRequest(
                    messages: [
                        LLMChatMessage(role: .system, content: "Plan first."),
                        LLMChatMessage(role: .user, content: "Create a follow-up todo.")
                    ],
                    tools: [tool],
                    options: LLMProviderOptions(model: "gpt-4.1", temperature: 0.2)
                )
                let response = LLMProviderResponse(
                    message: LLMChatMessage(role: .assistant, content: "Ready."),
                    toolCalls: [AgentToolCall(id: "call-1", toolName: "create_todo", argumentsJSON: "{\"title\":\"Review\"}")]
                )
                let adapterFlow = LLMProviderV2AdapterFlow(
                    messages: request.messages,
                    toolDefinitions: [definition],
                    options: request.options
                )
                let provider = OpenAICompatibleProvider()
                let configuration = LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "fallback-model")
                let chatRequest = try provider.buildChatRequest(
                    configuration: configuration,
                    apiKey: "secret-key",
                    providerRequest: adapterFlow.request
                )
                let chatBody = try require(chatRequest.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Provider V2 chat body should encode as UTF-8.")

                let decodedRequest = try JSONDecoder().decode(LLMProviderRequest.self, from: JSONEncoder().encode(request))
                let decodedResponse = try JSONDecoder().decode(LLMProviderResponse.self, from: JSONEncoder().encode(response))

                try expect(decodedRequest.messages.count == 2, "Provider V2 requests should preserve message history.")
                try expect(decodedRequest.tools.first?.permissionKey == "tool.write_workspace", "Provider V2 tool specs should preserve permission keys.")
                try expect(decodedRequest.options.model == "gpt-4.1", "Provider V2 requests should preserve model options.")
                try expect(decodedResponse.toolCalls.first?.toolName == "create_todo", "Provider V2 responses should preserve tool calls.")
                try expect(adapterFlow.preservesLegacyCompletePath, "Provider V2 adapter flow should explicitly preserve the legacy complete path.")
                try expect(adapterFlow.supportsTaskCancellation, "Provider V2 adapter flow should document Task cancellation support.")
                try expect(chatBody.contains("tools"), "OpenAI-compatible Provider V2 wrapper should encode tool definitions.")
                try expect(chatBody.contains("gpt-4.1"), "OpenAI-compatible Provider V2 wrapper should use request model options.")
            }
}
