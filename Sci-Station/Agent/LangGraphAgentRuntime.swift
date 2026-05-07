import Foundation

public nonisolated enum SidecarToolCallPolicy: String, Codable, Sendable {
    case disabled
    case structuredOnly = "structured_only"
    case toolCallingNodeOnly = "tool_calling_node_only"
}

public nonisolated struct SidecarAgentStartRequest: Codable, Hashable, Sendable {
    public var runID: String
    public var threadID: String?
    public var goal: String
    public var selectedPaperID: String?
    public var projectID: String?
    public var workspaceRoot: String
    public var toolCallPolicy: SidecarToolCallPolicy
    public var enabledWorkflowIDs: [String]?

    private enum CodingKeys: String, CodingKey {
        case runID
        case threadID
        case goal
        case selectedPaperID
        case projectID
        case workspaceRoot
        case toolCallPolicy
        case enabledWorkflowIDs
    }
}

public nonisolated struct SidecarAgentResumeRequest: Codable, Hashable, Sendable {
    public var runID: String
    public var decision: AgentHumanDecision
    public var writeResult: AgentToolResultWireFormat?

    private enum CodingKeys: String, CodingKey {
        case runID
        case decision
        case writeResult
    }
}

public actor LangGraphAgentRuntime: ExternalAgentRuntime {
    private let supervisor: SidecarProcessSupervisor
    private let fallbackRuntime: (any ExternalAgentRuntime)?
    private let healthCoordinator: SidecarRuntimeCoordinator?
    private let runDirectoryStore: AgentRunDirectoryStore
    private let executionLedger: AgentToolExecutionLedger
    private var requestsByRunID: [String: AgentRuntimeRequest] = [:]
    private var connectionsByRunID: [String: SidecarConnection] = [:]
    private var nextSequencesByRunID: [String: Int] = [:]

    public init(
        supervisor: SidecarProcessSupervisor,
        fallbackRuntime: (any ExternalAgentRuntime)? = LegacySwiftAgentRuntime(),
        healthCoordinator: SidecarRuntimeCoordinator? = nil,
        runDirectoryStore: AgentRunDirectoryStore = AgentRunDirectoryStore(),
        executionLedger: AgentToolExecutionLedger? = nil
    ) {
        self.supervisor = supervisor
        self.fallbackRuntime = fallbackRuntime
        self.healthCoordinator = healthCoordinator
        self.runDirectoryStore = runDirectoryStore
        self.executionLedger = executionLedger ?? AgentToolExecutionLedger(runDirectoryStore: runDirectoryStore)
    }

    public func startRun(_ request: AgentRuntimeRequest) async throws -> AsyncThrowingStream<AgentRuntimeEventEnvelope, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.performStartRun(request, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func resumeRun(runID: String, decision: AgentHumanDecision) async throws {
        guard let request = requestsByRunID[runID] else {
            throw AgentError.invalidArguments("No active LangGraph runtime request found for run id: \(runID)")
        }
        let connection = try await activeConnection(for: request, continuation: nil)
        let bridge = hostBridge(for: request)
        let terminal = SidecarRunTerminal()
        await connection.updateHandlers(
            hostRequestHandler: { method, params in try await bridge.handle(method: method, params: params) },
            notificationHandler: { [weak self] method, params in
                guard method == "runtime.event", let self else { return }
                do {
                    let terminalEvent = try await self.acceptSidecarEvent(params, for: request, continuation: nil)
                    if terminalEvent {
                        await terminal.finish()
                    }
                } catch {
                    _ = try? await self.appendRuntimeEvent(.runFailed(AgentRunFailed(error: AgentRuntimeError(code: .internalError, message: error.localizedDescription))), for: request, continuation: nil)
                    await terminal.finish()
                }
            },
            terminationHandler: { [weak self] exitCode in
                guard let self else { return }
                if exitCode != 0 {
                    await self.recordSidecarCrash(exitCode: exitCode, for: request, continuation: nil)
                }
                await terminal.finish()
            }
        )
        let writeResult = try await executeApprovedWriteIfNeeded(runID: runID, decision: decision, request: request)
        let resume = SidecarAgentResumeRequest(runID: runID, decision: decision, writeResult: writeResult.map { AgentToolResultWireFormat(result: $0, toolCallID: $0.callID) })
        _ = try await connection.sendRequest(
            method: "agent.resume",
            params: try SidecarJSONCodec.jsonValue(from: resume),
            timeout: 30
        )
        await terminal.wait()
    }

    public func cancelRun(runID: String) async throws {
        if let connection = connectionsByRunID[runID], await connection.isRunning() {
            _ = try? await connection.sendRequest(method: "agent.cancel", params: .object(["runID": .string(runID)]), timeout: 5)
        }
        if let request = requestsByRunID[runID] {
            try await appendRuntimeEvent(.runCancelled(AgentRunCancelled(reason: "Cancelled by user.")), for: request, continuation: nil)
        }
    }

    public func loadCheckpoint(runID: String) async throws -> AgentCheckpointSummary? {
        guard let request = requestsByRunID[runID] else {
            return nil
        }
        return try await runDirectoryStore.checkpointSummary(runID: runID, in: request.root)
    }

    private func performStartRun(
        _ request: AgentRuntimeRequest,
        continuation: AsyncThrowingStream<AgentRuntimeEventEnvelope, Error>.Continuation
    ) async throws {
        requestsByRunID[request.runID] = request
        nextSequencesByRunID[request.runID] = try await runDirectoryStore.nextSequence(runID: request.runID, in: request.root)
        try await appendRuntimeEvent(.sidecarStarting, for: request, continuation: continuation)
        let terminal = SidecarRunTerminal()

        do {
            let connection = try await activeConnection(for: request, continuation: continuation, terminal: terminal)
            try await appendRuntimeEvent(.sidecarReady, for: request, continuation: continuation)
            let startRequest = SidecarAgentStartRequest(
                runID: request.runID,
                threadID: request.threadID,
                goal: request.goal,
                selectedPaperID: request.toolContext.selectedPaperID,
                projectID: request.toolContext.currentProjectID,
                workspaceRoot: request.root.rootURL.path,
                toolCallPolicy: .disabled,
                enabledWorkflowIDs: request.enabledWorkflowIDs?.sorted()
            )
            _ = try await connection.sendRequest(
                method: "agent.start",
                params: try SidecarJSONCodec.jsonValue(from: startRequest),
                timeout: 30
            )
            await terminal.wait()
        } catch {
            let runtimeError = AgentRuntimeError(code: .sidecarUnavailable, message: error.localizedDescription)
            await healthCoordinator?.recordFallback(runtimeError.message)
            try await appendRuntimeEvent(.sidecarUnavailable(runtimeError), for: request, continuation: continuation)
            try await appendRuntimeEvent(.fallbackToLegacyRuntime(runtimeError), for: request, continuation: continuation)
            try await streamFallbackIfAvailable(request, continuation: continuation)
        }
    }

    private func activeConnection(
        for request: AgentRuntimeRequest,
        continuation: AsyncThrowingStream<AgentRuntimeEventEnvelope, Error>.Continuation?,
        terminal: SidecarRunTerminal? = nil
    ) async throws -> SidecarConnection {
        if let existing = connectionsByRunID[request.runID], await existing.isRunning() {
            return existing
        }
        let bridge = hostBridge(for: request)
        let connection = try await supervisor.start(
            initialization: SidecarInitializationRequest(
                workspaceRoot: request.root.rootURL.path,
                allowedRoots: AgentAuthorizedResourceProvider.defaultAllowedRoots
            ),
            hostRequestHandler: { method, params in try await bridge.handle(method: method, params: params) },
            notificationHandler: { [weak self] method, params in
                guard method == "runtime.event", let self else { return }
                do {
                    let terminalEvent = try await self.acceptSidecarEvent(params, for: request, continuation: continuation)
                    if terminalEvent {
                        await terminal?.finish()
                    }
                } catch {
                    continuation?.finish(throwing: error)
                    await terminal?.finish()
                }
            },
            terminationHandler: { [weak self] exitCode in
                guard let self else { return }
                if exitCode != 0 {
                    await self.recordSidecarCrash(exitCode: exitCode, for: request, continuation: continuation)
                }
                await terminal?.finish()
            }
        )
        connectionsByRunID[request.runID] = connection
        return connection
    }

    private func hostBridge(for request: AgentRuntimeRequest) -> SidecarHostBridge {
        SidecarHostBridge(runtimeRequest: request)
    }

    @discardableResult
    private func acceptSidecarEvent(
        _ params: JSONValue?,
        for request: AgentRuntimeRequest,
        continuation: AsyncThrowingStream<AgentRuntimeEventEnvelope, Error>.Continuation?
    ) async throws -> Bool {
        let sidecarEnvelope = try SidecarJSONCodec.decode(AgentRuntimeEventEnvelope.self, from: params)
        guard sidecarEnvelope.schemaVersion == 1 else {
            throw SidecarJSONRPCError(code: -32012, message: "Unsupported sidecar runtime event schema version: \(sidecarEnvelope.schemaVersion)")
        }
        if case let .approvalRequired(approval) = sidecarEnvelope.event {
            try await savePendingApproval(approval, for: request)
        }
        let canonical = try await canonicalEnvelope(from: sidecarEnvelope, request: request)
        try await runDirectoryStore.appendEvent(canonical, in: request.root)
        continuation?.yield(canonical)
        return canonical.event.endsSidecarStartStream
    }

    private func canonicalEnvelope(from sidecarEnvelope: AgentRuntimeEventEnvelope, request: AgentRuntimeRequest) async throws -> AgentRuntimeEventEnvelope {
        let sequence: Int
        if let cachedSequence = nextSequencesByRunID[request.runID] {
            sequence = cachedSequence
        } else {
            sequence = try await runDirectoryStore.nextSequence(runID: request.runID, in: request.root)
        }
        nextSequencesByRunID[request.runID] = sequence + 1
        return AgentRuntimeEventEnvelope(
            id: sidecarEnvelope.id,
            schemaVersion: 1,
            runID: request.runID,
            threadID: request.threadID,
            sequence: sequence,
            timestamp: sidecarEnvelope.timestamp,
            event: sidecarEnvelope.event
        )
    }

    @discardableResult
    private func appendRuntimeEvent(
        _ event: AgentRuntimeEvent,
        for request: AgentRuntimeRequest,
        continuation: AsyncThrowingStream<AgentRuntimeEventEnvelope, Error>.Continuation?
    ) async throws -> AgentRuntimeEventEnvelope {
        let sequence: Int
        if let cachedSequence = nextSequencesByRunID[request.runID] {
            sequence = cachedSequence
        } else {
            sequence = try await runDirectoryStore.nextSequence(runID: request.runID, in: request.root)
        }
        nextSequencesByRunID[request.runID] = sequence + 1
        let envelope = AgentRuntimeEventEnvelope(runID: request.runID, threadID: request.threadID, sequence: sequence, event: event)
        try await runDirectoryStore.appendEvent(envelope, in: request.root)
        continuation?.yield(envelope)
        return envelope
    }

    private func savePendingApproval(_ approval: AgentApprovalRequest, for request: AgentRuntimeRequest) async throws {
        let call = AgentToolCall(id: approval.toolCallID, toolName: approval.tool, argumentsJSON: approval.arguments.canonicalJSON)
        let pending = AgentPendingToolCall(
            runID: request.runID,
            stepIndex: nextSequencesByRunID[request.runID] ?? 1,
            toolCall: call,
            approvalRequest: approval,
            messagesBeforePause: request.initialMessages
        )
        try await runDirectoryStore.saveCheckpoint(pending, in: request.root)
    }

    private func executeApprovedWriteIfNeeded(runID: String, decision: AgentHumanDecision, request: AgentRuntimeRequest) async throws -> AgentToolResult? {
        guard decision.action == .allowOnce,
              let pending = try await runDirectoryStore.pending(runID: runID, in: request.root),
              pending.approvalRequest.risk != .readOnly else {
            return nil
        }
        if let prior = try await executionLedger.completedResult(
            runID: runID,
            approvalID: pending.approvalRequest.id,
            toolCallID: pending.toolCall.id,
            fingerprint: pending.approvalRequest.fingerprint,
            in: request.root
        ) {
            return prior
        }
        var result = try await request.toolHost.invoke(pending.toolCall, context: request.toolContext)
        if result.callID.isEmpty {
            result.callID = pending.toolCall.id
        }
        try await executionLedger.record(
            result: result,
            runID: runID,
            approvalID: pending.approvalRequest.id,
            fingerprint: pending.approvalRequest.fingerprint,
            risk: pending.approvalRequest.risk,
            targetPaths: pending.approvalRequest.targetPaths,
            in: request.root
        )
        return result
    }

    private func streamFallbackIfAvailable(
        _ request: AgentRuntimeRequest,
        continuation: AsyncThrowingStream<AgentRuntimeEventEnvelope, Error>.Continuation
    ) async throws {
        guard let fallbackRuntime else {
            return
        }
        let fallbackStream = try await fallbackRuntime.startRun(request)
        for try await envelope in fallbackStream {
            continuation.yield(envelope)
        }
    }

    private func recordSidecarCrash(
        exitCode: Int32,
        for request: AgentRuntimeRequest,
        continuation: AsyncThrowingStream<AgentRuntimeEventEnvelope, Error>.Continuation?
    ) async {
        let error = AgentRuntimeError(code: .sidecarCrashed, message: "Sidecar process exited with status \(exitCode).")
        await healthCoordinator?.recordCrash(error.message)
        _ = try? await appendRuntimeEvent(.sidecarCrashed(error), for: request, continuation: continuation)
    }
}

private actor SidecarRunTerminal {
    private var isFinished = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isFinished {
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func finish() {
        guard !isFinished else {
            return
        }
        isFinished = true
        for continuation in continuations {
            continuation.resume()
        }
        continuations.removeAll()
    }
}

private nonisolated extension AgentRuntimeEvent {
    var endsSidecarStartStream: Bool {
        switch self {
        case .finalResponse, .runFailed, .checkpointSaved:
            return true
        default:
            return false
        }
    }
}

private nonisolated struct SidecarHostBridge: Sendable {
    let runtimeRequest: AgentRuntimeRequest
    let resourceProvider = AgentAuthorizedResourceProvider()
    let llmProxy = SidecarLLMProxy()
    let embeddingProxy = SidecarEmbeddingProxy()

    func handle(method: String, params: JSONValue?) async throws -> JSONValue {
        switch method {
        case "tools.list", "tools/list":
            return try await handleMCP(method: "tools/list", params: params)
        case "tools.call", "tools/call":
            return try await handleMCP(method: "tools/call", params: params)
        case "resources.list_indexable_documents", "resources/list_indexable_documents":
            let documents = try await resourceProvider.listIndexableDocuments(in: runtimeRequest.root)
            return try SidecarJSONCodec.jsonValue(from: ["documents": documents])
        case "resources.read", "resources/read":
            let readRequest = try SidecarJSONCodec.decode(AuthorizedResourceReadRequest.self, from: params)
            let response = try await resourceProvider.read(readRequest, in: runtimeRequest.root)
            return try SidecarJSONCodec.jsonValue(from: response)
        case "llm.respond":
            return try await llmProxy.respond(params: params, runtimeRequest: runtimeRequest)
        case "embedding.embed", "embedding.respond":
            return try await embeddingProxy.embed(params: params, runtimeRequest: runtimeRequest)
        case "log.event":
            return .object(["accepted": .bool(true)])
        default:
            throw SidecarJSONRPCError(code: -32601, message: "Unsupported Swift host method: \(method)")
        }
    }

    private func handleMCP(method: String, params: JSONValue?) async throws -> JSONValue {
        let gateway = AgentMCPGateway(toolHost: runtimeRequest.toolHost, permissionEvaluator: runtimeRequest.permissionEvaluator)
        let response = await gateway.handle(
            AgentMCPEnvelope(id: "sidecar-host-\(UUID().uuidString.lowercased())", method: method, params: params),
            context: runtimeRequest.toolContext,
            runID: runtimeRequest.runID
        )
        if let error = response.error {
            throw SidecarJSONRPCError(code: error.code, message: error.message)
        }
        return response.result ?? .object([:])
    }
}

public nonisolated struct SidecarLLMRespondRequest: Codable, Hashable, Sendable {
    public var messages: [LLMChatMessage]
    public var tools: [LLMToolSpecification]
    public var toolCallPolicy: SidecarToolCallPolicy
    public var modelOptions: [String: JSONValue]

    public nonisolated init(
        messages: [LLMChatMessage],
        tools: [LLMToolSpecification] = [],
        toolCallPolicy: SidecarToolCallPolicy = .disabled,
        modelOptions: [String: JSONValue] = [:]
    ) {
        self.messages = messages
        self.tools = tools
        self.toolCallPolicy = toolCallPolicy
        self.modelOptions = modelOptions
    }

    private enum CodingKeys: String, CodingKey {
        case messages
        case tools
        case toolCallPolicy
        case modelOptions
    }
}

public nonisolated struct SidecarLLMUsage: Codable, Hashable, Sendable {
    public var inputTokens: Int?
    public var outputTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case inputTokens
        case outputTokens
    }
}

public nonisolated struct SidecarLLMRespondResponse: Codable, Hashable, Sendable {
    public var message: LLMChatMessage
    public var toolCalls: [AgentToolCall]
    public var structuredOutput: JSONValue?
    public var usage: SidecarLLMUsage?
    public var finishReason: String

    private enum CodingKeys: String, CodingKey {
        case message
        case toolCalls
        case structuredOutput
        case usage
        case finishReason
    }
}

public nonisolated struct SidecarLLMProxy: Sendable {
    public nonisolated init() {}

    public func respond(params: JSONValue?, runtimeRequest: AgentRuntimeRequest) async throws -> JSONValue {
        let request = try SidecarJSONCodec.decode(SidecarLLMRespondRequest.self, from: params)
        try validateModelOptions(request.modelOptions)
        let tools = request.toolCallPolicy == .disabled ? [] : request.tools
        let providerRequest = LLMProviderRequest(
            messages: request.messages,
            tools: tools,
            options: LLMProviderOptions(
                model: runtimeRequest.configuration.model,
                temperature: runtimeRequest.configuration.temperature,
                maxTokens: runtimeRequest.configuration.maxTokens
            )
        )
        let response = try await runtimeRequest.provider.respond(
            to: providerRequest,
            configuration: runtimeRequest.configuration,
            apiKey: runtimeRequest.apiKey
        )
        if request.toolCallPolicy == .disabled, !response.toolCalls.isEmpty {
            throw SidecarJSONRPCError(code: -32602, message: "llm.respond returned tool calls while toolCallPolicy is disabled.")
        }
        return try SidecarJSONCodec.jsonValue(from: SidecarLLMRespondResponse(
            message: response.message,
            toolCalls: response.toolCalls,
            structuredOutput: nil,
            usage: nil,
            finishReason: "stop"
        ))
    }

    private func validateModelOptions(_ options: [String: JSONValue]) throws {
        let sensitiveFragments = ["api", "key", "token", "credential", "secret", "env"]
        for key in options.keys {
            let lowered = key.lowercased()
            if sensitiveFragments.contains(where: { lowered.contains($0) }) {
                throw SidecarJSONRPCError(code: -32602, message: "modelOptions contains a sensitive key: \(key)")
            }
        }
    }
}

public nonisolated struct IndexableDocumentSnapshot: Codable, Hashable, Sendable, Identifiable {
    public var id: String { resourceID }
    public var resourceID: String
    public var relativePath: String
    public var sourceType: String
    public var sourceID: String?
    public var updatedAt: Date
    public var contentHash: String
    public var parserHint: String

    public nonisolated init(
        resourceID: String,
        relativePath: String,
        sourceType: String,
        sourceID: String? = nil,
        updatedAt: Date,
        contentHash: String,
        parserHint: String = "markdown"
    ) {
        self.resourceID = resourceID
        self.relativePath = relativePath
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.updatedAt = updatedAt
        self.contentHash = contentHash
        self.parserHint = parserHint
    }

    private enum CodingKeys: String, CodingKey {
        case resourceID = "resource_id"
        case relativePath = "relative_path"
        case sourceType = "source_type"
        case sourceID = "source_id"
        case updatedAt = "updated_at"
        case contentHash = "content_hash"
        case parserHint = "parser_hint"
    }
}

public nonisolated struct AuthorizedResourceRange: Codable, Hashable, Sendable {
    public var startLine: Int
    public var endLine: Int

    public nonisolated init(startLine: Int, endLine: Int) {
        self.startLine = startLine
        self.endLine = endLine
    }

    private enum CodingKeys: String, CodingKey {
        case startLine = "start_line"
        case endLine = "end_line"
    }
}

public nonisolated struct AuthorizedResourceReadRequest: Codable, Hashable, Sendable {
    public var resourceID: String?
    public var relativePath: String?
    public var maxBytes: Int?
    public var maxCharacters: Int?
    public var range: AuthorizedResourceRange?

    public nonisolated init(
        resourceID: String? = nil,
        relativePath: String? = nil,
        maxBytes: Int? = nil,
        maxCharacters: Int? = nil,
        range: AuthorizedResourceRange? = nil
    ) {
        self.resourceID = resourceID
        self.relativePath = relativePath
        self.maxBytes = maxBytes
        self.maxCharacters = maxCharacters
        self.range = range
    }

    private enum CodingKeys: String, CodingKey {
        case resourceID = "resource_id"
        case relativePath = "relative_path"
        case maxBytes
        case maxCharacters
        case range
    }
}

public nonisolated struct AuthorizedResourceReadResponse: Codable, Hashable, Sendable {
    public var resourceID: String
    public var relativePath: String
    public var content: String
    public var contentHash: String
    public var truncated: Bool
    public var encoding: String

    private enum CodingKeys: String, CodingKey {
        case resourceID = "resource_id"
        case relativePath = "relative_path"
        case content
        case contentHash = "content_hash"
        case truncated
        case encoding
    }
}

public actor AgentAuthorizedResourceProvider {
    public static let defaultAllowedRoots: [String] = ["library/papers", "raw/papers", "wiki", "projects", "materials", "data", "code", "figures", "outputs", "shared_research.md"]
    private let fileManager: FileManager
    private let maximumIndexedBytes: Int

    public init(fileManager: FileManager = .default, maximumIndexedBytes: Int = 2_000_000) {
        self.fileManager = fileManager
        self.maximumIndexedBytes = maximumIndexedBytes
    }

    public func listIndexableDocuments(in root: ResearchRoot, allowedRoots: [String] = AgentAuthorizedResourceProvider.defaultAllowedRoots) throws -> [IndexableDocumentSnapshot] {
        var snapshots: [IndexableDocumentSnapshot] = []
        for allowedRoot in allowedRoots {
            let rootURL = root.resolve(relativePath: allowedRoot, isDirectory: !allowedRoot.contains("."))
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                guard let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }
                for case let fileURL as URL in enumerator {
                    let relativePath = rootRelativePath(root: root, fileURL: fileURL)
                    if let snapshot = try snapshotIfIndexable(root: root, relativePath: relativePath, fileURL: fileURL) {
                        snapshots.append(snapshot)
                    }
                }
            } else if let snapshot = try snapshotIfIndexable(root: root, relativePath: allowedRoot, fileURL: rootURL) {
                snapshots.append(snapshot)
            }
        }
        return snapshots.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    public func read(_ request: AuthorizedResourceReadRequest, in root: ResearchRoot) throws -> AuthorizedResourceReadResponse {
        let snapshots = try listIndexableDocuments(in: root)
        let snapshot: IndexableDocumentSnapshot
        if let resourceID = request.resourceID, let match = snapshots.first(where: { $0.resourceID == resourceID }) {
            snapshot = match
        } else if let relativePath = request.relativePath.flatMap(normalizedRelativePath), let match = snapshots.first(where: { $0.relativePath == relativePath }) {
            snapshot = match
        } else {
            throw SidecarJSONRPCError(code: -32602, message: "Requested resource is not authorized for sidecar reading.")
        }
        let url = root.fileURL(for: snapshot.relativePath)
        let maxBytes = min(max(request.maxBytes ?? 1_048_576, 1), 5_000_000)
        let fullSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        let data: Data
        var truncated = false
        if fullSize > maxBytes {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maxBytes) ?? Data()
            truncated = true
        } else {
            data = try Data(contentsOf: url)
        }
        guard var content = String(data: data, encoding: .utf8) else {
            throw SidecarJSONRPCError(code: -32602, message: "Requested resource is not valid UTF-8 text.")
        }
        if let range = request.range {
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let start = max(range.startLine, 1)
            let end = min(max(range.endLine, start), lines.count)
            if start <= end, !lines.isEmpty {
                content = lines[(start - 1)..<end].joined(separator: "\n")
            }
        }
        if let maxCharacters = request.maxCharacters, content.count > maxCharacters {
            content = String(content.prefix(maxCharacters))
            truncated = true
        }
        return AuthorizedResourceReadResponse(
            resourceID: snapshot.resourceID,
            relativePath: snapshot.relativePath,
            content: content,
            contentHash: snapshot.contentHash,
            truncated: truncated,
            encoding: "utf-8"
        )
    }

    private func snapshotIfIndexable(root: ResearchRoot, relativePath: String, fileURL: URL) throws -> IndexableDocumentSnapshot? {
        guard let normalized = normalizedRelativePath(relativePath), isIndexable(normalized) else {
            return nil
        }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= maximumIndexedBytes else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        guard let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        let classification = classify(relativePath: normalized)
        return IndexableDocumentSnapshot(
            resourceID: "\(classification.sourceType):\(classification.sourceID ?? "workspace"):\(normalized)",
            relativePath: normalized,
            sourceType: classification.sourceType,
            sourceID: classification.sourceID,
            updatedAt: (attributes[.modificationDate] as? Date) ?? Date(),
            contentHash: AgentEmbeddingHashing.sha256(content),
            parserHint: normalized.hasSuffix(".txt") ? "text" : "markdown"
        )
    }

    private func isIndexable(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        guard !components.contains(where: { $0.hasPrefix(".") }) else {
            return false
        }
        guard relativePath.hasSuffix(".md") || relativePath.hasSuffix(".txt") else {
            return false
        }
        if relativePath.hasPrefix("library/papers/") || relativePath.hasPrefix("raw/papers/") {
            return relativePath.hasSuffix("/paper.md") || relativePath.hasSuffix("/annotations.md")
        }
        if relativePath.hasPrefix("wiki/") {
            return true
        }
        if relativePath.hasPrefix("projects/"), relativePath.contains("/wiki/") {
            return true
        }
        return relativePath.hasPrefix("materials/")
            || relativePath.hasPrefix("data/")
            || relativePath.hasPrefix("code/")
            || relativePath.hasPrefix("figures/")
            || relativePath.hasPrefix("outputs/")
            || relativePath == "shared_research.md"
    }

    private func classify(relativePath: String) -> (sourceType: String, sourceID: String?) {
        let components = relativePath.split(separator: "/").map(String.init)
        if components.count >= 4,
           (components[0] == "library" || components[0] == "raw"),
           components[1] == "papers" {
            return (relativePath.hasSuffix("annotations.md") ? "paper_annotations" : "paper", components[2])
        }
        if components.count >= 3, components[0] == "projects" {
            return ("project_wiki", components[1])
        }
        if components.first == "wiki" {
            return ("wiki", nil)
        }
        return ("material", nil)
    }

    private func rootRelativePath(root: ResearchRoot, fileURL: URL) -> String {
        let rootPath = root.rootURL.standardizedFileURL.path
        let targetPath = fileURL.standardizedFileURL.path
        guard targetPath.hasPrefix(rootPath) else {
            return targetPath
        }
        let trimmed = targetPath.dropFirst(rootPath.count)
        return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : String(trimmed)
    }

    private func normalizedRelativePath(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/"), !trimmed.contains("..") else {
            return nil
        }
        return trimmed.split(separator: "/").map(String.init).joined(separator: "/")
    }

}