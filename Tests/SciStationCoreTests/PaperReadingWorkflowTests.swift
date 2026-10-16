import Foundation
import Testing
@testable import SciStationCore

/// These are deterministic orchestration fixtures, not model-quality acceptance tests.
@Suite("Paper reading evidence and approved writeback fixtures")
struct PaperReadingWorkflowTests {
    @Test("Empty search and metadata-only tool success do not count as paper-body evidence")
    func emptyEvidenceIsRejected() {
        let evaluator = AgentAnswerQualityEvaluator()
        for result in [
            AgentToolResult(callID: "empty", toolName: "search_papers", succeeded: true, message: "No matches", payload: .object([
                "kind": .string("paper_search"), "matches": .array([]), "count": .number("0")
            ])),
            AgentToolResult(callID: "blank", toolName: "read_paper", succeeded: true, message: "Read succeeded", payload: .object([
                "kind": .string("paper_read"), "source": .string("library/papers/fixture/paper.md"), "content": .string(" \n")
            ])),
            AgentToolResult(callID: "metadata", toolName: "read_paper_section", succeeded: true, message: "paper_id: fixture\nsource: library/papers/fixture/paper.md")
        ] {
            let report = evaluator.evaluate(goal: "请精读论文并生成研究笔记", finalMarkdown: "The paper demonstrates a scientific finding.", toolResults: [result])
            #expect(report.issues.contains { $0.code == .missingEvidence })
        }
        let match = AgentToolResult(callID: "match", toolName: "search_papers", succeeded: true, message: "Matched", payload: .object([
            "kind": .string("paper_search"), "matches": .array([.object([
                "source": .string("library/papers/fixture/paper.md"), "line": .number("3"),
                "snippet": .string("The fixture tests diffusion at fixed temperature.")
            ])])
        ]))
        #expect(!evaluator.evaluate(goal: "Create a paper reading note", finalMarkdown: "The paper tests diffusion at fixed temperature.", toolResults: [match]).issues.contains { $0.code == .missingEvidence })
    }

    @Test("Reading intent requires evidence in both supported languages")
    func readingIntentRequiresEvidence() {
        for goal in ["请精读这篇论文", "生成这篇论文的研究笔记", "Create a paper reading note", "Deep read this paper"] {
            #expect(AgentPaperIntentRouter().classify(goal).requiresPaperEvidence)
        }
    }

    @Test("Actual paper tools preserve body and source lines; missing conversion is diagnostic")
    func paperBodyAndMissingConversion() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.workspace.rootURL) }
        let section = ReadPaperSectionAgentTool(paperRepository: PaperRepository())
        let result = try await section.invoke(argumentsJSON: #"{"heading":"Method"}"#, context: fixture.context)
        #expect(result.payload?.objectValue?["source"]?.stringValue == "library/papers/reading-fixture/paper.md")
        #expect(result.payload?.objectValue?["start_line"] == .number("3"))
        #expect(result.message.contains("fixed temperature"))
        try FileManager.default.removeItem(at: fixture.workspace.fileURL(for: "library/papers/reading-fixture/paper.md"))
        let call = AgentToolCall(id: "missing-conversion", toolName: section.definition.name, argumentsJSON: #"{"heading":"Method"}"#)
        let registry = AgentToolRegistry(tools: [section])
        let plan = AgentPlan(summary: "Fixture missing body", toolCalls: [call], finalResponseDraft: "")
        let results = await AgentToolExecutor(registry: registry).execute(plan: plan, context: fixture.context, approvedToolCallIDs: [])
        #expect(results.first?.succeeded == false)
        #expect(results.first?.message.contains("convert") == true || results.first?.message.contains("Markdown") == true)
    }

    @Test("A paper write request without body evidence cannot reach approval")
    func missingEvidenceCannotOfferWriteback() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.workspace.rootURL) }
        let writer = WriteWikiMarkdownAgentTool(markdownRepository: MarkdownRepository())
        let call = AgentToolCall(id: "ungrounded-write", toolName: writer.definition.name, argumentsJSON: #"{"title":"Unsupported","relative_path":"wiki/notes/unsupported.md","body":"The paper proves a result without having been read."}"#)
        let provider = ReadingWorkflowFixtureProvider(response: LLMProviderResponse(message: .init(role: .assistant, content: "", toolCalls: [call]), toolCalls: [call]))
        let result = try await AgentLoopRunner().run(AgentLoopRequest(
            goal: "Read the paper and save a research note", initialMessages: [.init(role: .user, content: "Read the paper and save a research note")],
            provider: provider, toolDefinitions: [writer.definition], toolRegistry: AgentToolRegistry(tools: [writer]),
            toolContext: fixture.context, root: fixture.root, configuration: LLMConfiguration(), apiKey: "fixture-no-network",
            hookEngine: AgentHookEngine(hooks: [])
        ))
        #expect(result.pendingToolCall == nil)
        #expect(result.finalResponseMarkdown?.contains("did not read enough") == true)
        #expect(!FileManager.default.fileExists(atPath: fixture.workspace.fileURL(for: "wiki/notes/unsupported.md").path))
    }

    @Test("A restart restores the exact draft, denial writes nothing, and approval saves a reloadable note")
    func approvedWritebackSurvivesRestart() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.workspace.rootURL) }
        let reader = ReadPaperAgentTool(paperRepository: PaperRepository())
        let writer = WriteWikiMarkdownAgentTool(markdownRepository: MarkdownRepository())
        let definitions = [reader.definition, writer.definition]
        let registry = AgentToolRegistry(tools: [reader, writer])
        let note = "# Diffusion fixture note\n\nThe method tests diffusion at fixed temperature. Source: library/papers/reading-fixture/paper.md, Method, lines 3–4.\n\nLimit: this fixture does not establish variable-temperature behavior."
        let arguments = JSONValue.object([
            "title": .string("Diffusion fixture note"), "relative_path": .string("wiki/papers/reading-fixture.md"), "body": .string(note)
        ]).canonicalJSON
        let call = AgentToolCall(id: "fixture-write", toolName: writer.definition.name, argumentsJSON: arguments)
        let provider = ReadingWorkflowFixtureProvider(response: LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: note, toolCalls: [call]), toolCalls: [call]))
        let runID = "reading-fixture-approval"
        let result = try await AgentLoopRunner().run(AgentLoopRequest(
            runID: runID, goal: "Read the paper and save a research note", initialMessages: [.init(role: .user, content: "Read the selected paper and save a note")],
            provider: provider, toolDefinitions: definitions, toolRegistry: registry, toolContext: fixture.context, root: fixture.root,
            configuration: LLMConfiguration(), apiKey: "fixture-no-network", hookEngine: AgentHookEngine(hooks: [])
        ))
        #expect(result.pauseReason?.kind == .approvalRequired)
        let path = fixture.workspace.fileURL(for: "wiki/papers/reading-fixture.md")
        #expect(!FileManager.default.fileExists(atPath: path.path))
        let restored = try #require(try await AgentLoopCheckpointStore().pending(runID: runID, in: fixture.root))
        #expect(restored.toolCall.argumentsJSON == arguments)
        #expect(restored.messagesBeforePause.contains { $0.content.contains("fixed temperature") })
        let finalProvider = ReadingWorkflowFixtureProvider(response: LLMProviderResponse(message: .init(role: .assistant, content: "The approved note was saved with its source location.")))
        func resume(_ action: AgentHumanDecisionAction) -> AgentLoopResumeRequest {
            AgentLoopResumeRequest(pending: restored, action: action, provider: finalProvider, toolDefinitions: definitions,
                                   toolRegistry: registry, toolContext: fixture.context, root: fixture.root, configuration: LLMConfiguration(),
                                   apiKey: "fixture-no-network", hookEngine: AgentHookEngine(hooks: []))
        }
        let denied = try await AgentLoopRunner().resume(resume(.denyAndStop))
        #expect(denied.pauseReason?.kind == .deniedAndStopped)
        #expect(!FileManager.default.fileExists(atPath: path.path))
        let approved = try await AgentLoopRunner().resume(resume(.allowOnce))
        #expect(approved.toolResults.contains { $0.toolName == writer.definition.name && $0.succeeded })
        let reopened = try await MarkdownRepository().loadDocument(relativePath: "wiki/papers/reading-fixture.md", in: ResearchWorkspace(rootURL: fixture.workspace.rootURL))
        #expect(reopened.rawContents.contains(note))
        #expect(reopened.rawContents.contains("lines 3–4"))
    }

    private func makeFixture() throws -> (workspace: ResearchWorkspace, root: ResearchRoot, context: AgentToolContext) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sci-reading-fixture-\(UUID().uuidString)", isDirectory: true)
        let workspace = ResearchWorkspace(rootURL: url)
        let root = ResearchRoot(rootURL: url)
        let directory = workspace.directoryURL(for: "library/papers/reading-fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "id: reading-fixture\ncitekey: readingfixture\ntitle: Explicit synthetic diffusion fixture\nauthors: []\n".write(to: directory.appendingPathComponent("meta.yaml"), atomically: true, encoding: .utf8)
        try "# Explicit synthetic diffusion fixture\n\n## Method\nThe fixture tests diffusion at fixed temperature.\n\n## Limitations\nVariable-temperature behavior was not tested.\n".write(to: directory.appendingPathComponent("paper.md"), atomically: true, encoding: .utf8)
        return (workspace, root, AgentToolContext(workspace: workspace, selectedPaperID: "reading-fixture", researchRoot: root))
    }
}

private actor ReadingWorkflowFixtureProvider: LLMChatProvider {
    let response: LLMProviderResponse

    init(response: LLMProviderResponse) { self.response = response }

    func respond(to request: LLMProviderRequest, configuration: LLMConfiguration, apiKey: String) async throws -> LLMProviderResponse {
        response
    }
}
