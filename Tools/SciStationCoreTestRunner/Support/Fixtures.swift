import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func makeWorkspaceFixture(_ name: String) throws -> (URL, ResearchWorkspace) {
        let rootURL = temporaryDirectoryURL().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return (rootURL, ResearchWorkspace(rootURL: rootURL))
    }

    func recommendationScoreForMMR(id: String, title: String, abstract: String, total: Double) -> RecommendationScore {
        let candidate = RecommendationCandidate(
            canonicalID: id,
            externalKey: id.replacingOccurrences(of: "external:", with: ""),
            displayTitle: title,
            categories: ["cs.AI"],
            abstractText: abstract
        )
        return RecommendationScore(
            id: id,
            candidate: candidate,
            features: RecommendationFeatureBreakdown(),
            total: total,
            evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
    }

    struct MarkdownRepositoryFixture {
        let workspace: ResearchWorkspace
        let repository: MarkdownRepository
        let suiteName: String
        let workspaceRoot: URL
    }

    func markdownRepositoryFixture(named name: String) async throws -> MarkdownRepositoryFixture {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: WorkspaceBookmarkStore(defaults: defaults))
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent(name, isDirectory: true)
        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        return MarkdownRepositoryFixture(workspace: workspace, repository: MarkdownRepository(), suiteName: suiteName, workspaceRoot: workspaceRoot)
    }

    func cleanupMarkdownRepositoryFixture(_ fixture: MarkdownRepositoryFixture) {
        try? FileManager.default.removeItem(at: fixture.workspaceRoot.deletingLastPathComponent())
        UserDefaults(suiteName: fixture.suiteName)?.removePersistentDomain(forName: fixture.suiteName)
    }

    struct LoopWorkspaceFixture {
        let workspace: ResearchWorkspace
        let root: ResearchRoot
        let suiteName: String
        let containerURL: URL
    }

    func loopWorkspaceFixture(named name: String) async throws -> LoopWorkspaceFixture {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let containerURL = temporaryDirectoryURL()
        let workspaceURL = containerURL.appendingPathComponent(name, isDirectory: true)
        let workspace = try await workspaceService.createWorkspace(at: workspaceURL)
        return LoopWorkspaceFixture(
            workspace: workspace,
            root: ResearchRoot(rootURL: workspace.rootURL),
            suiteName: suiteName,
            containerURL: containerURL
        )
    }

    func cleanupLoopWorkspaceFixture(_ fixture: LoopWorkspaceFixture) {
        try? FileManager.default.removeItem(at: fixture.containerURL)
        UserDefaults(suiteName: fixture.suiteName)?.removePersistentDomain(forName: fixture.suiteName)
    }

    func loopToolDefinition(
        name: String,
        risk: AgentToolRisk,
        maxOutputCharacters: Int = 12_000
    ) -> AgentToolDefinition {
        AgentToolDefinition(
            name: name,
            summary: "Loop test tool \(name).",
            inputSchema: "{\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"},\"command\":{\"type\":\"string\"}}}",
            risk: risk,
            outputPolicy: AgentToolOutputPolicy(maxCharacters: maxOutputCharacters)
        )
    }

    func loopRequest(
        runID: String,
        goal: String = "Loop test goal",
        provider: any LLMChatProvider,
        definitions: [AgentToolDefinition],
        registry: AgentToolRegistry,
        fixture: LoopWorkspaceFixture,
        configuration: LLMConfiguration = LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
        options: AgentLoopOptions = AgentLoopOptions(),
        hookEngine: AgentHookEngine = AgentHookEngine(hooks: []),
        permissionEvaluator: AgentPermissionEvaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules())
    ) -> AgentLoopRequest {
        AgentLoopRequest(
            runID: runID,
            goal: goal,
            initialMessages: [
                LLMChatMessage(role: .system, content: "Use tools when useful."),
                LLMChatMessage(role: .user, content: "Please inspect the selected context.")
            ],
            provider: provider,
            toolDefinitions: definitions,
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: configuration,
            apiKey: "test-key",
            options: options,
            hookEngine: hookEngine,
            permissionEvaluator: permissionEvaluator
        )
    }

    func loopResumeRequest(
        pending: AgentPendingToolCall,
        action: AgentHumanDecisionAction,
        feedback: String? = nil,
        editedArgumentsJSON: String? = nil,
        provider: any LLMChatProvider,
        definitions: [AgentToolDefinition],
        registry: AgentToolRegistry,
        fixture: LoopWorkspaceFixture,
        options: AgentLoopOptions = AgentLoopOptions(),
        hookEngine: AgentHookEngine = AgentHookEngine(hooks: [])
    ) -> AgentLoopResumeRequest {
        AgentLoopResumeRequest(
            pending: pending,
            action: action,
            feedback: feedback,
            editedArgumentsJSON: editedArgumentsJSON,
            provider: provider,
            toolDefinitions: definitions,
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root),
            root: fixture.root,
            configuration: LLMConfiguration(baseURLString: "https://api.example.com/v1", model: "test-model"),
            apiKey: "test-key",
            options: options,
            hookEngine: hookEngine,
            permissionEvaluator: AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules())
        )
    }

    func sidecarRuntime(
        fixtureName: String,
        handshakeTimeout: TimeInterval = 5
    ) -> LangGraphAgentRuntime {
        let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let runtimeURL = repositoryURL.appendingPathComponent("AgentRuntime", isDirectory: true)
        let fixtureURL = runtimeURL.appendingPathComponent("tests/fixtures/\(fixtureName)", isDirectory: false)
        let configuration = SidecarLaunchConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-m", "sci_station_agent.main", "--fixture", fixtureURL.path],
            environment: [
                "PYTHONPATH": runtimeURL.path,
                "PYTHONUNBUFFERED": "1"
            ],
            workingDirectoryURL: repositoryURL,
            handshakeTimeout: handshakeTimeout,
            requestTimeout: 5
        )
        return LangGraphAgentRuntime(
            supervisor: SidecarProcessSupervisor(configuration: configuration),
            fallbackRuntime: nil
        )
    }

    func sidecarCoordinator(
        fixtureName: String,
        handshakeTimeout: TimeInterval = 5
    ) -> SidecarRuntimeCoordinator {
        let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let runtimeURL = repositoryURL.appendingPathComponent("AgentRuntime", isDirectory: true)
        let fixtureURL = runtimeURL.appendingPathComponent("tests/fixtures/\(fixtureName)", isDirectory: false)
        let configuration = SidecarLaunchConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-m", "sci_station_agent.main", "--fixture", fixtureURL.path],
            environment: [
                "PYTHONPATH": runtimeURL.path,
                "PYTHONUNBUFFERED": "1"
            ],
            workingDirectoryURL: repositoryURL,
            handshakeTimeout: handshakeTimeout,
            requestTimeout: 5
        )
        return SidecarRuntimeCoordinator(supervisor: SidecarProcessSupervisor(configuration: configuration))
    }

    func sidecarRuntimeRequest(
        runID: String,
        goal: String = "P34 sidecar fixture run",
        fixture: LoopWorkspaceFixture,
        definitions: [AgentToolDefinition] = [],
        registry: AgentToolRegistry = AgentToolRegistry(tools: [])
    ) -> AgentRuntimeRequest {
        AgentRuntimeRequest(
            runID: runID,
            threadID: "thread-\(runID)",
            goal: goal,
            initialMessages: [LLMChatMessage(role: .user, content: goal)],
            provider: ScriptedChatProvider(responses: [
                LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "Sidecar provider response."))
            ]),
            toolDefinitions: definitions,
            toolRegistry: registry,
            toolContext: AgentToolContext(workspace: fixture.workspace, selectedPaperID: "demo-paper", researchRoot: fixture.root, currentProjectID: "demo-project"),
            root: fixture.root,
            configuration: LLMConfiguration(),
            apiKey: "test-key"
        )
    }

    struct GraphToolTestFixture {
        var rootURL: URL
        var root: ResearchRoot
        var workspace: ResearchWorkspace
        var repo: GraphRepository
        var paperRepository: PaperRepository
        var context: AgentToolContext
    }

    func graphToolFixture(name: String) async throws -> GraphToolTestFixture {
        let rootURL = temporaryDirectoryURL().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let workspace = ResearchWorkspace(rootURL: rootURL)
        let repo = GraphRepository()
        try await repo.open(in: root)
        let paperRepository = PaperRepository()
        let context = AgentToolContext(
            workspace: workspace,
            researchRoot: root,
            currentProjectID: "proj"
        )
        return GraphToolTestFixture(
            rootURL: rootURL,
            root: root,
            workspace: workspace,
            repo: repo,
            paperRepository: paperRepository,
            context: context
        )
    }

    func graphPaper(id: String, graphNodeID: String, title: String, year: Int, projectID: String, isCore: Bool) -> Paper {
        var paper = samplePaper(id: id)
        paper.citekey = id
        paper.title = title
        paper.year = year
        paper.arxiv = nil
        paper.graphNodeID = graphNodeID
        paper.projectIDs = [projectID]
        paper.coreProjectIDs = isCore ? [projectID] : []
        paper.paperDirectoryRelativePath = "library/papers/Uncategorized/\(id)"
        return paper
    }

    func samplePaper(id: String) -> Paper {
        Paper(
            id: id,
            citekey: "smith2024graph",
            title: "Graph-based Retrieval Augmented Generation",
            authors: ["John Smith", "Alice Wang"],
            year: 2024,
            venue: "arXiv",
            doi: nil,
            arxiv: "2401.12345",
            url: "https://arxiv.org/abs/2401.12345",
            pdfRelativePath: "paper.pdf",
            tags: ["rag"],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: ["related-work"],
            createdAt: Date(timeIntervalSince1970: 1_714_176_000),
            updatedAt: Date(timeIntervalSince1970: 1_714_176_000),
            paperDirectoryRelativePath: "library/papers/Uncategorized/\(id)",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
    }

    func sampleResearchProject(id: String) -> ResearchProject {
        ResearchProject(
            id: id,
            name: id.replacingOccurrences(of: "-", with: " ").capitalized,
            description: "P42 fixture project",
            colorHex: "#4F7CAC",
            iconName: "folder",
            relativePath: "projects/\(id)",
            createdAt: Date(timeIntervalSince1970: 1_777_500_000),
            updatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
    }

    func sampleTodo(id: String, title: String, projectID: String, dueDate: Date?) -> TodoItem {
        TodoItem(
            id: id,
            title: title,
            status: .open,
            dueDate: dueDate,
            priority: .high,
            projectIDs: [projectID],
            tags: [],
            relatedPaperIDs: [],
            notes: nil,
            createdAt: Date(timeIntervalSince1970: 1_777_500_000),
            updatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
    }

    func sampleMarkdownDocument(relativePath: String, title: String) -> MarkdownDocument {
        MarkdownDocument(
            fileURL: URL(fileURLWithPath: "/tmp/\(relativePath)"),
            relativePath: relativePath,
            category: "gaps",
            title: title,
            frontmatter: [:],
            body: "# \(title)",
            rawContents: "# \(title)",
            outgoingLinks: [],
            pageKeys: [WikiLink.normalizePageKey(title)]
        )
    }

    func sampleAgentRun(
        id: String,
        projectID: String?,
        createdAt: Date,
        lifecycleState: AgentRunState = .completed,
        toolResults: [AgentToolResult] = []
    ) -> AgentRun {
        AgentRun(
            id: id,
            goal: "P42 fixture run",
            createdAt: createdAt,
            completedAt: lifecycleState == .completed ? createdAt.addingTimeInterval(1) : nil,
            mode: .planOnly,
            plan: AgentPlan(title: "Fixture Draft", summary: "Fixture Draft", toolCalls: []),
            toolResults: toolResults,
            currentProjectID: projectID,
            lifecycleState: lifecycleState
        )
    }

    func artifactToolResult(
        runID: String,
        kind: String,
        createdAt: Date,
        title: String? = nil,
        requiresConfirmation: Bool = false
    ) throws -> AgentToolResult {
        let artifact = AgentArtifactDraft(
            id: "artifact-\(runID)-\(kind)",
            runID: runID,
            kind: kind,
            proposedPath: "wiki/projects/\(kind).md",
            title: title ?? kind.replacingOccurrences(of: "_", with: " ").capitalized,
            content: "# Artifact",
            evidenceRefs: sampleEvidenceRefs(prefix: runID, count: 1)
        )
        return AgentToolResult(
            callID: "call-\(runID)-\(kind)-\(Int(createdAt.timeIntervalSince1970))",
            toolName: "artifact_draft",
            succeeded: true,
            requiresConfirmation: requiresConfirmation,
            message: artifact.title,
            payload: try jsonValue(artifact)
        )
    }

    func jsonValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try AgentRunDirectoryStore.encoder().encode(value)
        return try AgentRunDirectoryStore.decoder().decode(JSONValue.self, from: data)
    }

    func sampleEvidenceRefs(prefix: String, count: Int = 6) -> [AgentEvidenceRef] {
        (1...count).map { index in
            AgentEvidenceRef(
                sourceType: "paper",
                sourceID: "\(prefix)-paper-\(index)",
                relativePath: "library/papers/\(prefix)-paper-\(index)/paper.md",
                startLine: 1,
                endLine: 8,
                sourceHash: "sha256:\(prefix)-\(index)",
                chunkID: "paper:\(prefix)-\(index):1-8",
                heading: "Evidence \(index)",
                quote: "Evidence-backed claim \(index).",
                confidence: 0.74
            )
        }
    }

    func temporaryDirectoryURL() -> URL {
        let baseURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL
    }

    func writeValidPDF(to url: URL) throws {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw ValidationError(message: "Could not create a PDF data consumer for the test fixture.")
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ValidationError(message: "Could not create a PDF graphics context for the test fixture.")
        }

        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(mediaBox)
        context.endPDFPage()
        context.closePDF()

        let pdfData = data as Data
        guard pdfData.starts(with: Data("%PDF-".utf8)), pdfData.count > 100 else {
            throw ValidationError(message: "Core Graphics produced an invalid PDF test fixture.")
        }
        try pdfData.write(to: url, options: .atomic)
    }

    func firstModuleConfiguration(from stream: AsyncStream<WorkspaceModuleConfiguration>) async throws -> WorkspaceModuleConfiguration {
        try await withThrowingTaskGroup(of: WorkspaceModuleConfiguration.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                guard let configuration = await iterator.next() else {
                    throw ValidationError(message: "Module configuration watch stream ended before publishing a change.")
                }
                return configuration
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                throw ValidationError(message: "Timed out waiting for workspace module configuration watcher.")
            }
            guard let configuration = try await group.next() else {
                throw ValidationError(message: "Module configuration watcher did not produce a result.")
            }
            group.cancelAll()
            return configuration
        }
    }

    func zipData(entries: [(path: String, data: Data)]) throws -> Data {
        let sourceDirectoryURL = temporaryDirectoryURL()
        let zipDirectoryURL = temporaryDirectoryURL()
        let zipURL = zipDirectoryURL.appendingPathComponent("archive.zip", isDirectory: false)

        defer {
            try? FileManager.default.removeItem(at: sourceDirectoryURL)
            try? FileManager.default.removeItem(at: zipDirectoryURL)
        }

        for entry in entries {
            let fileURL = sourceDirectoryURL.appendingPathComponent(entry.path, isDirectory: false)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: fileURL, options: .atomic)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qry", zipURL.path, "."]
        process.currentDirectoryURL = sourceDirectoryURL

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown zip error"
            throw ValidationError(message: "zip failed: \(errorText)")
        }

        return try Data(contentsOf: zipURL)
    }

    func gitTrackedFiles(in repoURL: URL) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "ls-files"]
        process.currentDirectoryURL = repoURL

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown git error"
            throw ValidationError(message: "git ls-files failed: \(errorText)")
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(whereSeparator: \.isNewline).map(String.init)
    }

    func trackedSciAIContainsRawSecrets(at directoryURL: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        let secretPattern = #"(?i)(bearer\s+[A-Za-z0-9._\-]{12,}|sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|\"(api[_-]?key|client[_-]?secret|refresh[_-]?token|private[_-]?key)\"\s*:\s*\"(?!\$\{|keychain:|env:|secret-ref:)[^\"]{8,}\")"#
        guard let expression = try? NSRegularExpression(pattern: secretPattern) else {
            return true
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if expression.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }

        return false
    }

    func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw ValidationError(message: message)
        }
    }

    func expectWikiWriteRejected(_ tool: WriteMarkdownPlanAgentTool, context: AgentToolContext, path: String) async throws {
        var didReject = false
        do {
            _ = try await tool.invoke(
                argumentsJSON: "{\"title\":\"Rejected\",\"body\":\"Body\",\"relative_path\":\"\(path)\"}",
                context: context
            )
        } catch {
            didReject = true
        }
        try expect(didReject, "Wiki writeback should reject invalid path: \(path)")
    }

    func jsonObject(_ value: JSONValue?, _ message: String) throws -> [String: JSONValue] {
        guard case let .object(object)? = value else {
            throw ValidationError(message: message)
        }
        return object
    }

    func jsonArray(_ value: JSONValue?, _ message: String) throws -> [JSONValue] {
        guard case let .array(array)? = value else {
            throw ValidationError(message: message)
        }
        return array
    }

    func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw ValidationError(message: message)
        }
        return value
    }

    func runtimeEventLabel(_ event: AgentRuntimeEvent) -> String {
        switch event {
        case .runStarted: return "runStarted"
        case .nodeStarted: return "nodeStarted"
        case .assistantDelta: return "assistantDelta"
        case .assistantMessage: return "assistantMessage"
        case .toolCallRequested: return "toolCallRequested"
        case .toolCallCompleted: return "toolCallCompleted"
        case .approvalRequired: return "approvalRequired"
        case .artifactDraft: return "artifactDraft"
        case .checkpointSaved: return "checkpointSaved"
        case .finalResponse: return "finalResponse"
        case .runCancelled: return "runCancelled"
        case .runFailed: return "runFailed"
        case .sidecarStarting: return "sidecarStarting"
        case .sidecarReady: return "sidecarReady"
        case .sidecarUnavailable: return "sidecarUnavailable"
        case .sidecarCrashed: return "sidecarCrashed"
        case .fallbackToLegacyRuntime: return "fallbackToLegacyRuntime"
        }
    }
}
