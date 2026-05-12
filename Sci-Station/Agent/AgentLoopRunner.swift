import Foundation

public struct AgentLoopRequest: Sendable {
    public var runID: String
    public var goal: String
    public var initialMessages: [LLMChatMessage]
    public var provider: any LLMChatProvider
    public var toolDefinitions: [AgentToolDefinition]
    public var toolRegistry: AgentToolRegistry
    public var toolHost: SciStationToolHost
    public var toolContext: AgentToolContext
    public var root: ResearchRoot
    public var configuration: LLMConfiguration
    public var apiKey: String
    public var options: AgentLoopOptions
    public var hookEngine: AgentHookEngine
    public var permissionEvaluator: AgentPermissionEvaluator
    public var responseDeltaHandler: (@Sendable (String) async -> Void)?

    public nonisolated init(
        runID: String = "agent-run-\(UUID().uuidString.lowercased())",
        goal: String,
        initialMessages: [LLMChatMessage],
        provider: any LLMChatProvider,
        toolDefinitions: [AgentToolDefinition],
        toolRegistry: AgentToolRegistry,
        toolHost: SciStationToolHost? = nil,
        toolContext: AgentToolContext,
        root: ResearchRoot,
        configuration: LLMConfiguration,
        apiKey: String,
        options: AgentLoopOptions = AgentLoopOptions(),
        hookEngine: AgentHookEngine = AgentHookEngine(hooks: AgentSafetyPreset.defaultHooks()),
        permissionEvaluator: AgentPermissionEvaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules()),
        responseDeltaHandler: (@Sendable (String) async -> Void)? = nil
    ) {
        self.runID = runID
        self.goal = goal
        self.initialMessages = initialMessages
        self.provider = provider
        self.toolDefinitions = toolDefinitions
        self.toolRegistry = toolRegistry
        self.toolHost = toolHost ?? SciStationToolHost(legacyRegistry: toolRegistry)
        self.toolContext = toolContext
        self.root = root
        self.configuration = configuration
        self.apiKey = apiKey
        self.options = options
        self.hookEngine = hookEngine
        self.permissionEvaluator = permissionEvaluator
        self.responseDeltaHandler = responseDeltaHandler
    }
}

public struct AgentLoopResumeRequest: Sendable {
    public var pending: AgentPendingToolCall
    public var action: AgentHumanDecisionAction
    public var feedback: String?
    public var editedArgumentsJSON: String?
    public var provider: any LLMChatProvider
    public var toolDefinitions: [AgentToolDefinition]
    public var toolRegistry: AgentToolRegistry
    public var toolHost: SciStationToolHost
    public var toolContext: AgentToolContext
    public var root: ResearchRoot
    public var configuration: LLMConfiguration
    public var apiKey: String
    public var options: AgentLoopOptions
    public var hookEngine: AgentHookEngine
    public var permissionEvaluator: AgentPermissionEvaluator
    public var responseDeltaHandler: (@Sendable (String) async -> Void)?

    public nonisolated init(
        pending: AgentPendingToolCall,
        action: AgentHumanDecisionAction,
        feedback: String? = nil,
        editedArgumentsJSON: String? = nil,
        provider: any LLMChatProvider,
        toolDefinitions: [AgentToolDefinition],
        toolRegistry: AgentToolRegistry,
        toolHost: SciStationToolHost? = nil,
        toolContext: AgentToolContext,
        root: ResearchRoot,
        configuration: LLMConfiguration,
        apiKey: String,
        options: AgentLoopOptions = AgentLoopOptions(),
        hookEngine: AgentHookEngine = AgentHookEngine(hooks: AgentSafetyPreset.defaultHooks()),
        permissionEvaluator: AgentPermissionEvaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules()),
        responseDeltaHandler: (@Sendable (String) async -> Void)? = nil
    ) {
        self.pending = pending
        self.action = action
        self.feedback = feedback
        self.editedArgumentsJSON = editedArgumentsJSON
        self.provider = provider
        self.toolDefinitions = toolDefinitions
        self.toolRegistry = toolRegistry
        self.toolHost = toolHost ?? SciStationToolHost(legacyRegistry: toolRegistry)
        self.toolContext = toolContext
        self.root = root
        self.configuration = configuration
        self.apiKey = apiKey
        self.options = options
        self.hookEngine = hookEngine
        self.permissionEvaluator = permissionEvaluator
        self.responseDeltaHandler = responseDeltaHandler
    }
}

public actor AgentLoopCheckpointStore {
    public static let relativePath = ".sci-station/agent/pending_tool_calls.jsonl"

    private let fileManager: FileManager
    private let runDirectoryStore: AgentRunDirectoryStore

    public init(fileManager: FileManager = .default, runDirectoryStore: AgentRunDirectoryStore = AgentRunDirectoryStore()) {
        self.fileManager = fileManager
        self.runDirectoryStore = runDirectoryStore
    }

    public func save(_ pending: AgentPendingToolCall, in root: ResearchRoot) async throws {
        try await runDirectoryStore.saveCheckpoint(pending, in: root)
    }

    public func saveLegacyFallback(_ pending: AgentPendingToolCall, in root: ResearchRoot) async throws {
        let logURL = root.fileURL(for: Self.relativePath)
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let writer = await JSONLWriterRegistry.shared.writer(for: logURL)
        try await writer.append(pending, encoder: encoder)
    }

    public func pending(runID: String, in root: ResearchRoot) async throws -> AgentPendingToolCall? {
        if let migratedPending = try await runDirectoryStore.pending(runID: runID, in: root) {
            return migratedPending
        }
        if let legacyPending = try pendingCalls(in: root).last(where: { pending in
            pending.runID == runID && !pending.isExpired
        }) {
            try await runDirectoryStore.saveCheckpoint(legacyPending, in: root)
            return legacyPending
        }
        return nil
    }

    public func pending(callID: String, in root: ResearchRoot) async throws -> AgentPendingToolCall? {
        if let migratedPending = try await runDirectoryStore.pending(callID: callID, in: root) {
            return migratedPending
        }
        if let legacyPending = try pendingCalls(in: root).last(where: { pending in
            pending.toolCall.id == callID && !pending.isExpired
        }) {
            try await runDirectoryStore.saveCheckpoint(legacyPending, in: root)
            return legacyPending
        }
        return nil
    }

    private func pendingCalls(in root: ResearchRoot) throws -> [AgentPendingToolCall] {
        let logURL = root.fileURL(for: Self.relativePath)
        guard fileManager.fileExists(atPath: logURL.path) else {
            return []
        }

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                try? decoder.decode(AgentPendingToolCall.self, from: Data(line.utf8))
            }
    }
}

public actor AgentLoopRunner {
    private let sessionEventLogger: AgentSessionEventLogger
    private let checkpointStore: AgentLoopCheckpointStore
    private let runDirectoryStore: AgentRunDirectoryStore
    private let executionLedger: AgentToolExecutionLedger
    private var readOnlyCacheByRunID: [String: [AgentToolCallFingerprint: AgentToolResult]] = [:]
    private var executedWriteResultsByRunID: [String: [AgentToolCallFingerprint: AgentToolResult]] = [:]

    public init(
        sessionEventLogger: AgentSessionEventLogger = AgentSessionEventLogger(),
        checkpointStore: AgentLoopCheckpointStore = AgentLoopCheckpointStore(),
        runDirectoryStore: AgentRunDirectoryStore = AgentRunDirectoryStore(),
        executionLedger: AgentToolExecutionLedger = AgentToolExecutionLedger()
    ) {
        self.sessionEventLogger = sessionEventLogger
        self.checkpointStore = checkpointStore
        self.runDirectoryStore = runDirectoryStore
        self.executionLedger = executionLedger
    }

    public func run(_ request: AgentLoopRequest) async throws -> AgentLoopResult {
        let trimmedGoal = request.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else {
            throw AgentError.emptyGoal
        }
        if let denial = AgentDeterministicSafetyPolicy().evaluatePrompt(trimmedGoal), denial.action == .deny {
            throw AgentError.invalidArguments(denial.message ?? "Prompt was blocked by the deterministic safety policy.")
        }

        try await appendEvent(
            AgentSessionEvent(
                sessionID: request.runID,
                createdAt: Date(),
                kind: .userMessage,
                summary: trimmedGoal
            ),
            in: request.root
        )

        let preflight = try await executePaperPreflightIfNeeded(
            runID: request.runID,
            goal: trimmedGoal,
            initialMessages: request.initialMessages,
            toolDefinitions: request.toolDefinitions,
            toolRegistry: request.toolRegistry,
            toolHost: request.toolHost,
            toolContext: request.toolContext,
            root: request.root,
            options: request.options,
            hookEngine: request.hookEngine
        )

        return try await continueLoop(
            runID: request.runID,
            goal: trimmedGoal,
            messages: preflight.messages,
            provider: request.provider,
            toolDefinitions: request.toolDefinitions,
            toolRegistry: request.toolRegistry,
            toolHost: request.toolHost,
            toolContext: request.toolContext,
            root: request.root,
            configuration: request.configuration,
            apiKey: request.apiKey,
            options: request.options,
            hookEngine: request.hookEngine,
            permissionEvaluator: request.permissionEvaluator,
            responseDeltaHandler: request.responseDeltaHandler,
            startingStepIndex: preflight.nextStepIndex,
            existingSteps: preflight.steps,
            existingToolResults: preflight.toolResults
        )
    }

    private struct PaperPreflightResult {
        var messages: [LLMChatMessage]
        var steps: [AgentLoopStep]
        var toolResults: [AgentToolResult]

        var nextStepIndex: Int {
            steps.count + 1
        }
    }

    private func executePaperPreflightIfNeeded(
        runID: String,
        goal: String,
        initialMessages: [LLMChatMessage],
        toolDefinitions: [AgentToolDefinition],
        toolRegistry: AgentToolRegistry,
        toolHost: SciStationToolHost,
        toolContext: AgentToolContext,
        root: ResearchRoot,
        options: AgentLoopOptions,
        hookEngine: AgentHookEngine
    ) async throws -> PaperPreflightResult {
        let router = AgentPaperIntentRouter()
        let intent = router.classify(goal)
        let availableToolNames = Set(toolDefinitions.map(\.name))
        guard router.shouldPreflight(intent, availableToolNames: availableToolNames) else {
            return PaperPreflightResult(messages: initialMessages, steps: [], toolResults: [])
        }

        let messages = initialMessages
        var steps: [AgentLoopStep] = []
        var results: [AgentToolResult] = []
        var evidence: [AgentPreflightEvidenceEnvelope] = []
        var resolvedPaperID = toolContext.selectedPaperID
        var firstSearchMatch: (paperID: String?, heading: String?, line: Int?)?
        var didReadPaperBody = false

        func preflightResult() throws -> PaperPreflightResult {
            guard !evidence.isEmpty else {
                return PaperPreflightResult(messages: messages, steps: steps, toolResults: results)
            }
            var evidenceMessages = messages
            evidenceMessages.append(try preflightEvidenceMessage(for: evidence))
            return PaperPreflightResult(messages: evidenceMessages, steps: steps, toolResults: results)
        }

        func runPreflightCall(_ call: AgentToolCall) async throws -> AgentToolResult {
            let execution = try await executeAllowedToolCall(
                call,
                runID: runID,
                toolDefinitions: toolDefinitions,
                toolRegistry: toolRegistry,
                toolHost: toolHost,
                toolContext: toolContext,
                root: root,
                options: options,
                hookEngine: hookEngine,
                approvalID: nil,
                forceWriteExecution: false
            )
            results.append(execution.result)
            evidence.append(AgentPreflightEvidenceEnvelope(
                toolName: call.toolName,
                toolCallID: call.id,
                argumentsJSON: call.argumentsJSON,
                result: AgentToolResultWireFormat(
                    result: execution.result,
                    toolCallID: call.id,
                    summary: summary(for: execution.result.message)
                )
            ))
            steps.append(AgentLoopStep(stepIndex: steps.count + 1, toolCalls: [call], toolResults: [execution.result]))
            return execution.result
        }

        if availableToolNames.contains("list_papers"), intent.kind == .paperListing || intent.ordinalIndex != nil || intent.requiresPaperEvidence {
            let listResult = try await runPreflightCall(AgentToolCall(
                id: "preflight-list-papers",
                toolName: "list_papers",
                argumentsJSON: "{}"
            ))
            if let index = intent.ordinalIndex {
                resolvedPaperID = paperID(at: index, in: listResult) ?? resolvedPaperID
            } else {
                resolvedPaperID = resolvedPaperID ?? singlePaperID(in: listResult)
            }
        }

        guard intent.kind != .paperListing else {
            return try preflightResult()
        }

        if availableToolNames.contains("search_papers"), intent.requiresPaperEvidence {
            let searchResult = try await runPreflightCall(AgentToolCall(
                id: "preflight-search-papers",
                toolName: "search_papers",
                argumentsJSON: router.searchArgumentsJSON(for: intent, paperID: resolvedPaperID)
            ))
            firstSearchMatch = firstMatch(in: searchResult)
            resolvedPaperID = firstSearchMatch?.paperID ?? resolvedPaperID
        }

        guard intent.requiresPaperEvidence else {
            return try preflightResult()
        }

        if availableToolNames.contains("read_paper_section") {
            let heading = intent.sectionHint?.nilIfEmpty ?? firstSearchMatch?.heading?.nilIfEmpty
            let line = firstSearchMatch?.line
            if let heading, heading != "Document" {
                var fields: [String: JSONValue] = [
                    "heading": .string(heading),
                    "max_characters": .number("12000")
                ]
                if let resolvedPaperID {
                    fields["paper_id"] = .string(resolvedPaperID)
                }
                let sectionResult = try await runPreflightCall(AgentToolCall(
                    id: "preflight-read-paper-section",
                    toolName: "read_paper_section",
                    argumentsJSON: JSONValue.object(fields).canonicalJSON
                ))
                didReadPaperBody = sectionResult.succeeded || didReadPaperBody
            } else if let line {
                var fields: [String: JSONValue] = [
                    "start_line": .number(String(max(line - 8, 1))),
                    "end_line": .number(String(line + 32)),
                    "max_characters": .number("12000")
                ]
                if let resolvedPaperID {
                    fields["paper_id"] = .string(resolvedPaperID)
                }
                let sectionResult = try await runPreflightCall(AgentToolCall(
                    id: "preflight-read-paper-section",
                    toolName: "read_paper_section",
                    argumentsJSON: JSONValue.object(fields).canonicalJSON
                ))
                didReadPaperBody = sectionResult.succeeded || didReadPaperBody
            }
        }

        if !didReadPaperBody, availableToolNames.contains("read_paper") {
            var fields: [String: JSONValue] = [
                "page": .number("1"),
                "page_size": .number("8000")
            ]
            if let resolvedPaperID {
                fields["paper_id"] = .string(resolvedPaperID)
            }
            _ = try await runPreflightCall(AgentToolCall(
                id: "preflight-read-paper",
                toolName: "read_paper",
                argumentsJSON: JSONValue.object(fields).canonicalJSON
            ))
            didReadPaperBody = true
        }

        return try preflightResult()
    }

    private func preflightEvidenceMessage(for evidence: [AgentPreflightEvidenceEnvelope]) throws -> LLMChatMessage {
        let evidenceJSON = try encoded(evidence) ?? "[]"
        return LLMChatMessage(
            role: .user,
            content: """
            Sci-Station deterministic preflight evidence has already been read from local read-only tools.
            Use this evidence to answer the latest user question.
            Do not treat it as provider-native tool-call transcript.

            \(evidenceJSON)
            """
        )
    }

    public func resume(_ request: AgentLoopResumeRequest) async throws -> AgentLoopResult {
        try await appendEvent(
            AgentSessionEvent(
                sessionID: request.pending.runID,
                kind: .permissionResolved,
                summary: "Human decision for \(request.pending.toolCall.toolName): \(request.action.rawValue).",
                payloadJSON: request.feedback ?? request.editedArgumentsJSON
            ),
            in: request.root
        )

        switch request.action {
        case .denyAndStop:
            let pause = AgentLoopPauseReason(
                kind: .deniedAndStopped,
                message: "User denied \(request.pending.toolCall.toolName) and stopped the run.",
                toolCallID: request.pending.toolCall.id,
                approvalRequest: request.pending.approvalRequest
            )
            return AgentLoopResult(
                runID: request.pending.runID,
                messages: request.pending.messagesBeforePause,
                pauseReason: pause,
                pendingToolCall: request.pending,
                steps: [AgentLoopStep(stepIndex: request.pending.stepIndex, pauseReason: pause)]
            )
        case .denyAndContinue:
            let deniedResult = AgentToolResult(
                callID: request.pending.toolCall.id,
                toolName: request.pending.toolCall.toolName,
                succeeded: false,
                message: ["Tool execution denied by the user.", request.feedback].compactMap { $0?.nilIfEmpty }.joined(separator: " "),
                errorMessage: "denied_by_user"
            )
            var messages = request.pending.messagesBeforePause
            messages.append(try stableToolMessage(for: deniedResult, callID: request.pending.toolCall.id, definition: definition(for: request.pending.toolCall, in: request.toolDefinitions), options: request.options))
            return try await continueLoop(
                runID: request.pending.runID,
                goal: "",
                messages: messages,
                provider: request.provider,
                toolDefinitions: request.toolDefinitions,
                toolRegistry: request.toolRegistry,
                toolHost: request.toolHost,
                toolContext: request.toolContext,
                root: request.root,
                configuration: request.configuration,
                apiKey: request.apiKey,
                options: request.options,
                hookEngine: request.hookEngine,
                permissionEvaluator: request.permissionEvaluator,
                responseDeltaHandler: request.responseDeltaHandler,
                startingStepIndex: request.pending.stepIndex + 1,
                existingSteps: [],
                existingToolResults: [deniedResult]
            )
        case .reviseWithFeedback:
            var messages = request.pending.messagesBeforePause
            let feedback = request.feedback?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Please revise the plan without executing that tool call."
            messages.append(LLMChatMessage(role: .user, content: "Tool approval feedback:\n\(feedback)"))
            return try await continueLoop(
                runID: request.pending.runID,
                goal: "",
                messages: messages,
                provider: request.provider,
                toolDefinitions: request.toolDefinitions,
                toolRegistry: request.toolRegistry,
                toolHost: request.toolHost,
                toolContext: request.toolContext,
                root: request.root,
                configuration: request.configuration,
                apiKey: request.apiKey,
                options: request.options,
                hookEngine: request.hookEngine,
                permissionEvaluator: request.permissionEvaluator,
                responseDeltaHandler: request.responseDeltaHandler,
                startingStepIndex: request.pending.stepIndex + 1,
                existingSteps: [],
                existingToolResults: []
            )
        case .editArguments:
            let editedArguments = try normalizedEditedArguments(request.editedArgumentsJSON)
            let rebuiltCall = AgentToolCall(
                id: request.pending.toolCall.id,
                toolName: request.pending.toolCall.toolName,
                argumentsJSON: editedArguments
            )
            let rebuiltPending = request.pending.replacing(
                toolCall: rebuiltCall,
                approvalRequest: approvalRequest(for: rebuiltCall, runID: request.pending.runID, definitions: request.toolDefinitions, message: "Edited arguments require a fresh permission pass.")
            )
            return try await resumeValidatedAllowOnce(
                pending: rebuiltPending,
                request: request,
                mustPauseIfPermissionAsks: true
            )
        case .allowOnce:
            return try await resumeValidatedAllowOnce(
                pending: request.pending,
                request: request,
                mustPauseIfPermissionAsks: false
            )
        }
    }

    private func resumeValidatedAllowOnce(
        pending: AgentPendingToolCall,
        request: AgentLoopResumeRequest,
        mustPauseIfPermissionAsks: Bool
    ) async throws -> AgentLoopResult {
        try validateArgumentsJSON(pending.toolCall.argumentsJSON)
        let evaluation = evaluatePermission(
            call: pending.toolCall,
            definitions: request.toolDefinitions,
            evaluator: request.permissionEvaluator
        )

        if evaluation.decision.action == .deny {
            let pause = AgentLoopPauseReason(
                kind: .safetyPolicyBlocked,
                message: evaluation.decision.message ?? "Tool call was denied by safety policy.",
                toolCallID: pending.toolCall.id,
                approvalRequest: pending.approvalRequest
            )
            return AgentLoopResult(
                runID: pending.runID,
                messages: pending.messagesBeforePause,
                pauseReason: pause,
                pendingToolCall: pending,
                steps: [AgentLoopStep(stepIndex: pending.stepIndex, toolCalls: [pending.toolCall], pauseReason: pause)]
            )
        }

        if mustPauseIfPermissionAsks, evaluation.decision.action == .ask {
            let refreshedApproval = approvalRequest(
                for: pending.toolCall,
                runID: pending.runID,
                definitions: request.toolDefinitions,
                message: evaluation.decision.message ?? pending.approvalRequest.reason
            )
            let refreshedPending = pending.replacing(toolCall: pending.toolCall, approvalRequest: refreshedApproval)
            try await checkpointStore.save(refreshedPending, in: request.root)
            try await appendEvent(
                AgentSessionEvent(
                    sessionID: pending.runID,
                    kind: .permissionRequested,
                    summary: "Edited \(pending.toolCall.toolName) arguments need approval.",
                    payloadJSON: pending.toolCall.argumentsJSON
                ),
                in: request.root
            )
            let pause = AgentLoopPauseReason(
                kind: .approvalRequired,
                message: "Edited arguments require approval before execution.",
                toolCallID: pending.toolCall.id,
                approvalRequest: refreshedApproval
            )
            return AgentLoopResult(
                runID: pending.runID,
                messages: pending.messagesBeforePause,
                pauseReason: pause,
                pendingToolCall: refreshedPending,
                steps: [AgentLoopStep(stepIndex: pending.stepIndex, toolCalls: [pending.toolCall], pauseReason: pause)]
            )
        }

        var messages = pending.messagesBeforePause
        let execution = try await executeAllowedToolCall(
            pending.toolCall,
            runID: pending.runID,
            toolDefinitions: request.toolDefinitions,
            toolRegistry: request.toolRegistry,
            toolHost: request.toolHost,
            toolContext: request.toolContext,
            root: request.root,
            options: request.options,
            hookEngine: request.hookEngine,
            approvalID: pending.approvalRequest.id,
            forceWriteExecution: true
        )
        messages.append(execution.message)
        return try await continueLoop(
            runID: pending.runID,
            goal: "",
            messages: messages,
            provider: request.provider,
            toolDefinitions: request.toolDefinitions,
            toolRegistry: request.toolRegistry,
            toolHost: request.toolHost,
            toolContext: request.toolContext,
            root: request.root,
            configuration: request.configuration,
            apiKey: request.apiKey,
            options: request.options,
            hookEngine: request.hookEngine,
            permissionEvaluator: request.permissionEvaluator,
            responseDeltaHandler: request.responseDeltaHandler,
            startingStepIndex: pending.stepIndex + 1,
            existingSteps: [AgentLoopStep(stepIndex: pending.stepIndex, toolCalls: [pending.toolCall], toolResults: [execution.result])],
            existingToolResults: [execution.result]
        )
    }

    private func continueLoop(
        runID: String,
        goal: String,
        messages initialMessages: [LLMChatMessage],
        provider: any LLMChatProvider,
        toolDefinitions: [AgentToolDefinition],
        toolRegistry: AgentToolRegistry,
        toolHost: SciStationToolHost,
        toolContext: AgentToolContext,
        root: ResearchRoot,
        configuration: LLMConfiguration,
        apiKey: String,
        options: AgentLoopOptions,
        hookEngine: AgentHookEngine,
        permissionEvaluator: AgentPermissionEvaluator,
        responseDeltaHandler: (@Sendable (String) async -> Void)?,
        startingStepIndex: Int,
        existingSteps: [AgentLoopStep],
        existingToolResults: [AgentToolResult]
    ) async throws -> AgentLoopResult {
        var messages = initialMessages
        var steps = existingSteps
        var toolResults = existingToolResults
        var toolCallCount = 0
        var accumulatedToolCharacters = existingToolResults.reduce(0) { $0 + $1.message.count }
        let definitionsByName = Dictionary(uniqueKeysWithValues: toolDefinitions.map { ($0.name, $0) })

        for stepIndex in startingStepIndex..<(startingStepIndex + options.maxSteps) {
            try Task.checkCancellation()
            guard messageCharacterCount(messages) <= options.maxContextCharacters,
                  accumulatedToolCharacters <= options.maxAccumulatedToolResultCharacters else {
                let pause = AgentLoopPauseReason(kind: .contextLimitExceeded, message: "Agent loop stopped because context or tool result budget was exceeded.")
                if let fallback = try await visibleLoopBudgetResult(
                    pause: pause,
                    runID: runID,
                    goal: goal,
                    messages: messages,
                    steps: steps,
                    toolResults: toolResults,
                    root: root,
                    configuration: configuration,
                    hookEngine: hookEngine,
                    responseDeltaHandler: responseDeltaHandler,
                    stepIndex: stepIndex
                ) {
                    return fallback
                }
                steps.append(AgentLoopStep(stepIndex: stepIndex, pauseReason: pause))
                try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
                return AgentLoopResult(runID: runID, messages: messages, toolResults: toolResults, pauseReason: pause, steps: steps)
            }

            let providerRequest = LLMProviderRequest(
                messages: messages,
                tools: options.allowProviderNativeTools ? toolDefinitions.map(LLMToolSpecification.init(agentTool:)) : []
            )
            let response: LLMProviderResponse
            do {
                let request = try LLMProviderRequestSanitizer.sanitized(providerRequest, configuration: configuration)
                // Hard timeout so a hung provider cannot park the entire loop.
                // Cooperative cancellation inside the task group gives the
                // URLSession a chance to unwind its socket before we surface
                // the error.
                let capturedProvider = provider
                let capturedConfiguration = configuration
                let capturedAPIKey = apiKey
                response = try await withAgentTimeout(
                    options.providerTimeoutSeconds,
                    operation: "LLM provider.respond"
                ) {
                    try await capturedProvider.respond(to: request, configuration: capturedConfiguration, apiKey: capturedAPIKey)
                }
                try Task.checkCancellation()
            } catch {
                if let fallback = try await visibleProviderFailureResult(
                    errorMessage: error.localizedDescription,
                    runID: runID,
                    goal: goal,
                    messages: messages,
                    steps: steps,
                    toolResults: toolResults,
                    root: root,
                    configuration: configuration,
                    hookEngine: hookEngine,
                    responseDeltaHandler: responseDeltaHandler,
                    stepIndex: stepIndex
                ) {
                    return fallback
                }
                throw error
            }
            let assistantMessage = LLMChatMessage(
                role: .assistant,
                content: response.message.content,
                reasoningContent: response.message.reasoningContent,
                toolCalls: response.toolCalls
            )
            messages.append(assistantMessage)
            try await appendAssistantEvent(assistantMessage, sessionID: runID, root: root)

            if response.toolCalls.isEmpty {
                let finalMarkdown = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if finalMarkdown.isEmpty {
                    if let fallback = try await visibleProviderFailureResult(
                        errorMessage: LLMProviderError.emptyResponse.localizedDescription,
                        runID: runID,
                        goal: goal,
                        messages: Array(messages.dropLast()),
                        steps: steps,
                        toolResults: toolResults,
                        root: root,
                        configuration: configuration,
                        hookEngine: hookEngine,
                        responseDeltaHandler: responseDeltaHandler,
                        stepIndex: stepIndex
                    ) {
                        return fallback
                    }
                    throw LLMProviderError.emptyResponse
                }
                let qualityReport = AgentAnswerQualityEvaluator().evaluate(goal: goal, finalMarkdown: finalMarkdown, toolResults: toolResults)
                let resolvedFinalMarkdown: String
                if qualityReport.issues.contains(where: { $0.code == .missingEvidence }) {
                    resolvedFinalMarkdown = AgentAnswerQualityEvaluator().missingEvidenceMarkdown(goal: goal, toolResults: toolResults)
                } else {
                    resolvedFinalMarkdown = finalMarkdown
                }
                let resolvedAssistantMessage = resolvedFinalMarkdown == assistantMessage.content
                    ? assistantMessage
                    : LLMChatMessage(role: .assistant, content: resolvedFinalMarkdown)
                if resolvedFinalMarkdown != assistantMessage.content {
                    messages[messages.count - 1] = resolvedAssistantMessage
                    try await appendAssistantEvent(resolvedAssistantMessage, sessionID: runID, root: root)
                }
                if let responseDeltaHandler {
                    await responseDeltaHandler(resolvedFinalMarkdown)
                }
                steps.append(AgentLoopStep(stepIndex: stepIndex, assistantMessage: resolvedAssistantMessage))
                try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
                return AgentLoopResult(runID: runID, finalResponseMarkdown: resolvedFinalMarkdown, messages: messages, toolResults: toolResults, steps: steps)
            }

            var stepToolResults: [AgentToolResult] = []
            var cachedToolCallIDs: [String] = []
            for call in response.toolCalls {
                try Task.checkCancellation()
                toolCallCount += 1
                guard toolCallCount <= options.maxToolCalls else {
                    let pause = AgentLoopPauseReason(kind: .maxToolCallsExceeded, message: "Agent loop stopped after \(options.maxToolCalls) tool calls.", toolCallID: call.id)
                    steps.append(AgentLoopStep(stepIndex: stepIndex, assistantMessage: assistantMessage, toolCalls: response.toolCalls, toolResults: stepToolResults, cachedToolCallIDs: cachedToolCallIDs, pauseReason: pause))
                    try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
                    return AgentLoopResult(runID: runID, messages: messages, toolResults: toolResults, pauseReason: pause, steps: steps)
                }

                try validateArgumentsJSON(call.argumentsJSON)
                let definition = definitionsByName[call.toolName]
                if let safetyDecision = AgentDeterministicSafetyPolicy().evaluateToolCall(call, definition: definition), safetyDecision.action == .deny {
                    let pause = AgentLoopPauseReason(
                        kind: .safetyPolicyBlocked,
                        message: safetyDecision.message ?? "Tool call was blocked by deterministic safety policy.",
                        toolCallID: call.id,
                        approvalRequest: approvalRequest(for: call, runID: runID, definitions: toolDefinitions, message: safetyDecision.message)
                    )
                    steps.append(AgentLoopStep(stepIndex: stepIndex, assistantMessage: assistantMessage, toolCalls: response.toolCalls, toolResults: stepToolResults, cachedToolCallIDs: cachedToolCallIDs, pauseReason: pause))
                    try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
                    return AgentLoopResult(runID: runID, messages: messages, toolResults: toolResults, pauseReason: pause, steps: steps)
                }
                let hookResults = hookEngine.evaluate(
                    AgentHookEvent(
                        name: .preToolUse,
                        toolName: call.toolName,
                        command: call.argumentsJSON,
                        prompt: goal
                    )
                )
                try await appendHookResults(hookResults, sessionID: runID, in: root)
                if let deny = hookResults.first(where: { $0.permissionDecision == .deny }) {
                    let pause = AgentLoopPauseReason(
                        kind: .safetyPolicyBlocked,
                        message: deny.message ?? "PreToolUse hook denied \(call.toolName).",
                        toolCallID: call.id,
                        approvalRequest: approvalRequest(for: call, runID: runID, definitions: toolDefinitions, message: deny.message)
                    )
                    steps.append(AgentLoopStep(stepIndex: stepIndex, assistantMessage: assistantMessage, toolCalls: response.toolCalls, toolResults: stepToolResults, cachedToolCallIDs: cachedToolCallIDs, pauseReason: pause))
                    try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
                    return AgentLoopResult(runID: runID, messages: messages, toolResults: toolResults, pauseReason: pause, steps: steps)
                }

                let evaluation = evaluatePermission(call: call, definitions: toolDefinitions, evaluator: permissionEvaluator)
                try Task.checkCancellation()
                if evaluation.decision.action == .deny {
                    let pause = AgentLoopPauseReason(
                        kind: .safetyPolicyBlocked,
                        message: evaluation.decision.message ?? "Tool call was denied by deterministic safety policy.",
                        toolCallID: call.id,
                        approvalRequest: approvalRequest(for: call, runID: runID, definitions: toolDefinitions, message: evaluation.decision.message)
                    )
                    steps.append(AgentLoopStep(stepIndex: stepIndex, assistantMessage: assistantMessage, toolCalls: response.toolCalls, toolResults: stepToolResults, cachedToolCallIDs: cachedToolCallIDs, pauseReason: pause))
                    try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
                    return AgentLoopResult(runID: runID, messages: messages, toolResults: toolResults, pauseReason: pause, steps: steps)
                }

                if evaluation.decision.action == .ask {
                    let approval = approvalRequest(for: call, runID: runID, definitions: toolDefinitions, message: evaluation.decision.message)
                    let pending = AgentPendingToolCall(
                        runID: runID,
                        stepIndex: stepIndex,
                        toolCall: call,
                        approvalRequest: approval,
                        messagesBeforePause: messages
                    )
                    try await checkpointStore.save(pending, in: root)
                    try await appendEvent(
                        AgentSessionEvent(
                            sessionID: runID,
                            kind: .permissionRequested,
                            summary: "\(call.toolName) requires approval before execution.",
                            payloadJSON: call.argumentsJSON
                        ),
                        in: root
                    )
                    let pause = AgentLoopPauseReason(
                        kind: .approvalRequired,
                        message: "\(call.toolName) requires approval before execution.",
                        toolCallID: call.id,
                        approvalRequest: approval
                    )
                    steps.append(AgentLoopStep(stepIndex: stepIndex, assistantMessage: assistantMessage, toolCalls: response.toolCalls, toolResults: stepToolResults, cachedToolCallIDs: cachedToolCallIDs, pauseReason: pause))
                    return AgentLoopResult(runID: runID, messages: messages, toolResults: toolResults, pauseReason: pause, pendingToolCall: pending, steps: steps)
                }

                let fingerprint = AgentToolCallFingerprint(call: call, targetPaths: evaluation.argumentInspection.paths)
                if definition?.risk == .readOnly,
                   let cached = readOnlyCacheByRunID[runID]?[fingerprint] {
                    let message = try stableToolMessage(for: cached, callID: call.id, definition: definition, options: options)
                    messages.append(message)
                    stepToolResults.append(cached)
                    toolResults.append(cached)
                    cachedToolCallIDs.append(call.id)
                    accumulatedToolCharacters += message.content.count
                    continue
                }

                let execution = try await executeAllowedToolCall(
                    call,
                    runID: runID,
                    toolDefinitions: toolDefinitions,
                    toolRegistry: toolRegistry,
                    toolHost: toolHost,
                    toolContext: toolContext,
                    root: root,
                    options: options,
                    hookEngine: hookEngine,
                    approvalID: nil,
                    forceWriteExecution: false
                )
                try Task.checkCancellation()
                messages.append(execution.message)
                stepToolResults.append(execution.result)
                toolResults.append(execution.result)
                accumulatedToolCharacters += execution.message.content.count
            }

            steps.append(AgentLoopStep(stepIndex: stepIndex, assistantMessage: assistantMessage, toolCalls: response.toolCalls, toolResults: stepToolResults, cachedToolCallIDs: cachedToolCallIDs))
        }

        let pause = AgentLoopPauseReason(kind: .maxStepsExceeded, message: "Agent loop stopped after \(options.maxSteps) model steps.")
        steps.append(AgentLoopStep(stepIndex: startingStepIndex + options.maxSteps, pauseReason: pause))
        try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
        return AgentLoopResult(runID: runID, messages: messages, toolResults: toolResults, pauseReason: pause, steps: steps)
    }

    private func visibleLoopBudgetResult(
        pause: AgentLoopPauseReason,
        runID: String,
        goal: String,
        messages: [LLMChatMessage],
        steps: [AgentLoopStep],
        toolResults: [AgentToolResult],
        root: ResearchRoot,
        configuration: LLMConfiguration,
        hookEngine: AgentHookEngine,
        responseDeltaHandler: (@Sendable (String) async -> Void)?,
        stepIndex: Int
    ) async throws -> AgentLoopResult? {
        guard !toolResults.isEmpty || messages.contains(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }

        let finalMarkdown = providerFailureMarkdown(
            errorMessage: pause.message,
            goal: goal,
            model: configuration.model,
            toolResults: toolResults,
            messages: messages
        )
        let assistantMessage = LLMChatMessage(role: .assistant, content: finalMarkdown)
        var updatedMessages = messages
        updatedMessages.append(assistantMessage)
        var updatedSteps = steps
        updatedSteps.append(AgentLoopStep(stepIndex: stepIndex, assistantMessage: assistantMessage, pauseReason: pause))
        try await appendAssistantEvent(assistantMessage, sessionID: runID, root: root)
        if let responseDeltaHandler {
            await responseDeltaHandler(finalMarkdown)
        }
        try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
        return AgentLoopResult(
            runID: runID,
            finalResponseMarkdown: finalMarkdown,
            messages: updatedMessages,
            toolResults: toolResults,
            pauseReason: pause,
            steps: updatedSteps
        )
    }

    private func visibleProviderFailureResult(
        errorMessage: String,
        runID: String,
        goal: String,
        messages: [LLMChatMessage],
        steps: [AgentLoopStep],
        toolResults: [AgentToolResult],
        root: ResearchRoot,
        configuration: LLMConfiguration,
        hookEngine: AgentHookEngine,
        responseDeltaHandler: (@Sendable (String) async -> Void)?,
        stepIndex: Int
    ) async throws -> AgentLoopResult? {
        guard !toolResults.isEmpty || messages.contains(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }

        let finalMarkdown = providerFailureMarkdown(
            errorMessage: errorMessage,
            goal: goal,
            model: configuration.model,
            toolResults: toolResults,
            messages: messages
        )
        let assistantMessage = LLMChatMessage(role: .assistant, content: finalMarkdown)
        var updatedMessages = messages
        updatedMessages.append(assistantMessage)
        var updatedSteps = steps
        let pause = AgentLoopPauseReason(kind: .providerUnavailable, message: errorMessage)
        updatedSteps.append(AgentLoopStep(stepIndex: stepIndex, assistantMessage: assistantMessage, pauseReason: pause))
        try await appendAssistantEvent(assistantMessage, sessionID: runID, root: root)
        if let responseDeltaHandler {
            await responseDeltaHandler(finalMarkdown)
        }
        try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
        return AgentLoopResult(
            runID: runID,
            finalResponseMarkdown: finalMarkdown,
            messages: updatedMessages,
            toolResults: toolResults,
            pauseReason: pause,
            steps: updatedSteps
        )
    }

    private nonisolated func providerFailureMarkdown(
        errorMessage: String,
        goal: String,
        model: String,
        toolResults: [AgentToolResult],
        messages: [LLMChatMessage]
    ) -> String {
        let wantsChinese = Self.containsChinese(goal) || messages.contains { Self.containsChinese($0.content) }
        if toolResults.isEmpty {
            let contextSummary = latestContextSummary(from: messages)
            if wantsChinese {
                return """
                模型没有返回最终回复，但本次对话上下文已保留。

                - 模型：\(model)
                - 失败原因：\(errorMessage)
                - 已读取上下文消息：\(messages.count)

                最近上下文摘要：\(contextSummary)

                - 操作：重试 / 复制脱敏诊断 / 调小问题范围

                可以直接重试；如果这是写回 wiki 的任务，请先复制上面的草稿或补充目标路径后再次提交。
                """
            }

            return """
            The model did not return a final response, but the conversation context was preserved.

            - Model: \(model)
            - Failure: \(errorMessage)
            - Context messages read: \(messages.count)

            Latest context summary: \(contextSummary)

            - Actions: retry / copy redacted diagnostics / narrow the question

            Retry directly, or restate the target wiki path if this was a writeback task.
            """
        }

        let usedTools = distinctToolNames(from: toolResults).joined(separator: ", ")
        let lastResult = toolResults.last
        let lastSummary = lastResult.map { summary(for: $0.message) } ?? ""
        if wantsChinese {
            return """
            模型没有返回最终回复，但本次工具读取已经完成。

            - 模型：\(model)
            - 失败原因：\(errorMessage)
            - 已使用工具：\(usedTools)

            最后一个工具结果摘要：\(lastSummary)

            - 操作：重试 / 复制脱敏诊断 / 展开详情

            可以直接重试本问题，或把问题缩小到上面工具结果中的论文、章节、公式关键词。
            """
        }

        return """
        The model did not return a final response, but the tool reads completed.

        - Model: \(model)
        - Failure: \(errorMessage)
        - Tools used: \(usedTools)

        Last tool result summary: \(lastSummary)

        - Actions: retry / copy redacted diagnostics / expand details

        Retry the question, or narrow it to the paper, section, or formula keyword shown in the tool result above.
        """
    }

    private nonisolated func latestContextSummary(from messages: [LLMChatMessage]) -> String {
        let latestContent = messages.reversed().compactMap { message in
            message.content.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }.first ?? "没有可见的上下文消息。"
        return summary(for: latestContent)
    }

    private func executeAllowedToolCall(
        _ call: AgentToolCall,
        runID: String,
        toolDefinitions: [AgentToolDefinition],
        toolRegistry: AgentToolRegistry,
        toolHost: SciStationToolHost,
        toolContext: AgentToolContext,
        root: ResearchRoot,
        options: AgentLoopOptions,
        hookEngine: AgentHookEngine,
        approvalID: String?,
        forceWriteExecution: Bool
    ) async throws -> (result: AgentToolResult, message: LLMChatMessage) {
        let definition = definition(for: call, in: toolDefinitions)
        let argumentInspection = AgentToolArgumentInspection(argumentsJSON: call.argumentsJSON)
        let fingerprint = AgentToolCallFingerprint(call: call, targetPaths: argumentInspection.paths)
        let ledgerApprovalID = approvalID ?? "auto-\(fingerprint.idempotencyFingerprint)"

        if definition?.risk != .readOnly,
           let priorResult = try await executionLedger.completedResult(
            runID: runID,
            approvalID: ledgerApprovalID,
            toolCallID: call.id,
            fingerprint: fingerprint.idempotencyFingerprint,
            in: root
           ) {
            return (priorResult, try stableToolMessage(for: priorResult, callID: call.id, definition: definition, options: options))
        }

        if definition?.risk != .readOnly,
           let priorResult = executedWriteResultsByRunID[runID]?[fingerprint] {
            return (priorResult, try stableToolMessage(for: priorResult, callID: call.id, definition: definition, options: options))
        }

        try await appendEvent(
            AgentSessionEvent(
                sessionID: runID,
                kind: .toolCallStarted,
                summary: "正在使用工具：\(call.toolName)",
                payloadJSON: toolCallPayloadJSON(for: call)
            ),
            in: root
        )

        let result: AgentToolResult
        do {
            // Hard timeout per tool so a wedged graph query, PDF reader, or
            // stuck embedding store cannot wedge the whole loop. See
            // DOC/comment.md §1.5.
            let capturedHost = toolHost
            let capturedCall = call
            let capturedContext = toolContext
            var invoked = try await withAgentTimeout(
                options.toolTimeoutSeconds,
                operation: "Tool invocation",
                toolName: call.toolName
            ) {
                try await capturedHost.invoke(capturedCall, context: capturedContext)
            }
            if invoked.callID.isEmpty {
                invoked.callID = call.id
            }
            result = limitedResult(invoked, definition: definition, options: options)
        } catch {
            let classification = AgentToolErrorClassifier().classify(error, toolName: call.toolName)
            result = AgentToolResult(
                callID: call.id,
                toolName: call.toolName,
                succeeded: false,
                message: "Tool failed (\(classification.code.rawValue)): \(classification.userMessage)\nSuggestion: \(classification.suggestion)",
                payload: classification.payload,
                errorMessage: classification.code.rawValue
            )
        }

        let postHookResults = hookEngine.evaluate(
            AgentHookEvent(
                name: .postToolUse,
                toolName: result.toolName,
                modifiedPaths: result.modifiedPaths,
                validationRecorded: result.succeeded
            )
        )
        try await appendHookResults(postHookResults, sessionID: runID, in: root)
        try await appendEvent(
            AgentSessionEvent(
                sessionID: runID,
                kind: result.succeeded ? .toolCallCompleted : .toolCallFailed,
                summary: toolEventSummary(for: result),
                payloadJSON: try stableToolResultJSON(for: result, callID: call.id, definition: definition, options: options)
            ),
            in: root
        )

        if definition?.risk == .readOnly {
            var cache = readOnlyCacheByRunID[runID] ?? [:]
            cache[fingerprint] = result
            readOnlyCacheByRunID[runID] = cache
        } else if result.succeeded || forceWriteExecution {
            var ledger = executedWriteResultsByRunID[runID] ?? [:]
            ledger[fingerprint] = result
            executedWriteResultsByRunID[runID] = ledger
            try await executionLedger.record(
                result: result,
                runID: runID,
                approvalID: ledgerApprovalID,
                fingerprint: fingerprint.idempotencyFingerprint,
                risk: definition?.risk ?? .externalSideEffect,
                targetPaths: argumentInspection.paths,
                in: root
            )
        }

        return (result, try stableToolMessage(for: result, callID: call.id, definition: definition, options: options))
    }

    private func appendAssistantEvent(_ message: LLMChatMessage, sessionID: String, root: ResearchRoot) async throws {
        let summary: String
        if let visibleContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            summary = visibleContent
        } else if !message.toolCalls.isEmpty || message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            summary = "工具调用准备就绪"
        } else {
            return
        }
        try await appendEvent(
            AgentSessionEvent(
                sessionID: sessionID,
                kind: .assistantMessage,
                summary: summary,
                payloadJSON: try encoded(AgentAssistantMessageEventPayload(message: message))
            ),
            in: root
        )
    }

    private func appendStopHooks(_ hookEngine: AgentHookEngine, sessionID: String, root: ResearchRoot, toolResults: [AgentToolResult]) async throws {
        let results = hookEngine.evaluate(
            AgentHookEvent(
                name: .stop,
                modifiedPaths: toolResults.flatMap(\.modifiedPaths),
                validationRecorded: !toolResults.isEmpty && toolResults.allSatisfy(\.succeeded)
            )
        )
        try await appendHookResults(results, sessionID: sessionID, in: root)
    }

    private func appendHookResults(_ results: [AgentHookResult], sessionID: String, in root: ResearchRoot) async throws {
        for result in results {
            try await appendEvent(
                AgentSessionEvent(
                    sessionID: sessionID,
                    kind: .hookResult,
                    summary: hookSummary(result),
                    payloadJSON: try encoded(result)
                ),
                in: root
            )
        }
    }

    private func appendEvent(_ event: AgentSessionEvent, in root: ResearchRoot) async throws {
        try await sessionEventLogger.append(event, in: root)
    }

    private func evaluatePermission(
        call: AgentToolCall,
        definitions: [AgentToolDefinition],
        evaluator: AgentPermissionEvaluator
    ) -> (decision: AgentPermissionDecision, argumentInspection: AgentToolArgumentInspection) {
        let definition = definition(for: call, in: definitions)
        let risk = definition?.risk ?? .externalSideEffect
        let inspection = AgentToolArgumentInspection(argumentsJSON: call.argumentsJSON)
        let decision = evaluator.evaluate(
            AgentPermissionRequest(
                toolName: call.toolName,
                permissionKey: definition?.permissionKey ?? risk.defaultPermissionKey,
                command: inspection.command ?? call.argumentsJSON,
                path: inspection.paths.first,
                risk: risk
            )
        )
        return (decision, inspection)
    }

    private func approvalRequest(for call: AgentToolCall, runID: String, definitions: [AgentToolDefinition], message: String?) -> AgentApprovalRequest {
        let definition = definition(for: call, in: definitions)
        let risk = definition?.risk ?? .externalSideEffect
        let inspection = AgentToolArgumentInspection(argumentsJSON: call.argumentsJSON)
        let targetPaths = approvalTargetPaths(for: call, risk: risk, inspectedPaths: inspection.paths)
        return AgentApprovalRequest(
            runID: runID,
            toolCallID: call.id,
            toolName: call.toolName,
            permissionKey: definition?.permissionKey ?? risk.defaultPermissionKey,
            risk: risk,
            argumentsJSON: call.argumentsJSON,
            targetPaths: targetPaths,
            diffPreview: approvalDiffPreview(for: call, risk: risk, targetPaths: targetPaths),
            summaryPreview: approvalSummaryPreview(for: call, risk: risk, targetPaths: targetPaths),
            reason: message,
            rollbackHint: risk == .readOnly ? nil : AgentRollbackHint(summary: "Review or revert the listed workspace files if the approved result is wrong.", targetPaths: targetPaths)
        )
    }

    private nonisolated func approvalTargetPaths(for call: AgentToolCall, risk: AgentToolRisk, inspectedPaths: [String]) -> [String] {
        if !inspectedPaths.isEmpty {
            return inspectedPaths
        }
        switch call.toolName {
        case "create_todo":
            return ["tasks/todos.yaml"]
        case "write_markdown_plan", "write_wiki_markdown":
            if let path = stringArgument("relative_path", in: call.argumentsJSON)?.nilIfEmpty {
                return [path]
            }
            if let title = stringArgument("title", in: call.argumentsJSON)?.nilIfEmpty {
                return ["wiki/plans/\(slug(from: title)).md"]
            }
            return ["wiki/plans/*.md"]
        case "update_paper_classification":
            if let paperID = stringArgument("paper_id", in: call.argumentsJSON)?.nilIfEmpty {
                return ["library/papers/\(paperID)/meta.yaml"]
            }
            return ["library/papers/*/meta.yaml"]
        default:
            return risk == .readOnly ? [] : ["workspace"]
        }
    }

    private nonisolated func approvalDiffPreview(for call: AgentToolCall, risk: AgentToolRisk, targetPaths: [String]) -> String? {
        guard risk != .readOnly else {
            return nil
        }
        let pathText = targetPaths.isEmpty ? "workspace" : targetPaths.joined(separator: ", ")
        switch call.toolName {
        case "write_markdown_plan", "write_wiki_markdown":
            let title = stringArgument("title", in: call.argumentsJSON)?.nilIfEmpty ?? "Untitled"
            let body = stringArgument("body", in: call.argumentsJSON)?.nilIfEmpty ?? ""
            let bodyPreview = limited(body, maxCharacters: 900)
            return """
            # target: \(pathText)
            # mode: create_or_replace
            # title: \(title)

            \(bodyPreview)
            """
        case "create_todo":
            return "+ todo: \(stringArgument("title", in: call.argumentsJSON)?.nilIfEmpty ?? "Untitled todo")\n# target: \(pathText)"
        case "update_paper_classification":
            return "~ paper metadata\n# target: \(pathText)"
        default:
            return "Tool may modify: \(pathText)"
        }
    }

    private nonisolated func approvalSummaryPreview(for call: AgentToolCall, risk: AgentToolRisk, targetPaths: [String]) -> String {
        let pathText = targetPaths.isEmpty ? "no target path" : targetPaths.joined(separator: ", ")
        if call.toolName == "write_markdown_plan" || call.toolName == "write_wiki_markdown" {
            let title = stringArgument("title", in: call.argumentsJSON)?.nilIfEmpty ?? "Markdown draft"
            return "Markdown 写入草稿（\(risk.rawValue)）-> \(pathText)：\(title)"
        }
        return "\(call.toolName) (\(risk.rawValue)) -> \(pathText)"
    }

    private nonisolated func stringArgument(_ key: String, in rawJSON: String) -> String? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object[key] as? String
    }

    private nonisolated func slug(from title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let lowercased = title.lowercased()
        var output = ""
        var previousWasDash = false
        for scalar in lowercased.unicodeScalars {
            if allowed.contains(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                output.append("-")
                previousWasDash = true
            }
        }
        let slug = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "plan-\(UUID().uuidString.lowercased())" : slug
    }

    private func definition(for call: AgentToolCall, in definitions: [AgentToolDefinition]) -> AgentToolDefinition? {
        definitions.first { $0.name == call.toolName }
    }

    private func stableToolMessage(
        for result: AgentToolResult,
        callID: String,
        definition: AgentToolDefinition?,
        options: AgentLoopOptions
    ) throws -> LLMChatMessage {
        LLMChatMessage(
            role: .tool,
            content: try stableToolResultJSON(for: result, callID: callID, definition: definition, options: options),
            name: result.toolName,
            toolCallID: callID
        )
    }

    private func stableToolResultJSON(
        for result: AgentToolResult,
        callID: String,
        definition: AgentToolDefinition?,
        options: AgentLoopOptions
    ) throws -> String {
        let limited = limitedResult(result, definition: definition, options: options)
        return try AgentToolResultWireFormat(
            result: limited,
            toolCallID: callID,
            summary: summary(for: limited.message)
        ).stableJSON()
    }

    private func limitedResult(_ result: AgentToolResult, definition: AgentToolDefinition?, options: AgentLoopOptions) -> AgentToolResult {
        let maxCharacters = min(definition?.outputPolicy.maxCharacters ?? options.maxToolResultCharactersPerCall, options.maxToolResultCharactersPerCall)
        let limitedMessage = limited(result.message, maxCharacters: maxCharacters)
        return AgentToolResult(
            callID: result.callID,
            toolName: result.toolName,
            succeeded: result.succeeded,
            requiresConfirmation: result.requiresConfirmation,
            message: limitedMessage,
            payload: result.payload,
            modifiedPaths: result.modifiedPaths,
            errorMessage: result.errorMessage
        )
    }

    private nonisolated func limited(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }
        let endIndex = text.index(text.startIndex, offsetBy: max(0, maxCharacters - 48))
        return String(text[..<endIndex]) + "\n[Tool output truncated by Sci-Station.]"
    }

    private nonisolated func summary(for text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? text
        return limited(firstLine.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 240)
    }

    private nonisolated func toolEventSummary(for result: AgentToolResult) -> String {
        if result.succeeded {
            return "已使用工具：\(result.toolName)"
        }
        return "工具 \(result.toolName) 失败：\(summary(for: result.errorMessage ?? result.message))"
    }

    private nonisolated func toolCallPayloadJSON(for call: AgentToolCall) -> String {
        var object: [String: JSONValue]
        if let value = try? JSONValue.parse(call.argumentsJSON), case let .object(arguments) = value {
            object = arguments
        } else {
            object = ["arguments_json": .string(call.argumentsJSON)]
        }
        object["tool_call_id"] = .string(call.id)
        object["tool_name"] = .string(call.toolName)
        return JSONValue.object(object).canonicalJSON
    }

    private nonisolated func distinctToolNames(from results: [AgentToolResult]) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for result in results where !seen.contains(result.toolName) {
            seen.insert(result.toolName)
            names.append(result.toolName)
        }
        return names
    }

    private nonisolated static func containsChinese(_ text: String) -> Bool {
        text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private nonisolated func paperID(at index: Int, in result: AgentToolResult) -> String? {
        guard let papers = result.payload?.objectValue?["papers"]?.arrayValue,
              papers.indices.contains(index),
              let paper = papers[index].objectValue else {
            return fallbackPaperIDs(in: result).dropFirst(index).first
        }
        return paper["paper_id"]?.stringValue?.nilIfEmpty
    }

    private nonisolated func singlePaperID(in result: AgentToolResult) -> String? {
        guard let papers = result.payload?.objectValue?["papers"]?.arrayValue else {
            let fallback = fallbackPaperIDs(in: result)
            return fallback.count == 1 ? fallback.first : nil
        }
        guard papers.count == 1, let paper = papers.first?.objectValue else {
            return nil
        }
        return paper["paper_id"]?.stringValue?.nilIfEmpty
    }

    private nonisolated func firstMatch(in result: AgentToolResult) -> (paperID: String?, heading: String?, line: Int?)? {
        guard let matches = result.payload?.objectValue?["matches"]?.arrayValue,
              let first = matches.first?.objectValue else {
            return nil
        }
        let paperID = first["paper_id"]?.stringValue?.nilIfEmpty
            ?? first["paper"]?.objectValue?["paper_id"]?.stringValue?.nilIfEmpty
        let heading = first["heading"]?.stringValue?.nilIfEmpty
        let line = numberValue(first["line"])
        return (paperID, heading, line)
    }

    private nonisolated func numberValue(_ value: JSONValue?) -> Int? {
        guard let value else {
            return nil
        }
        switch value {
        case let .number(number):
            return Int(number)
        case let .string(string):
            return Int(string)
        default:
            return nil
        }
    }

    private nonisolated func fallbackPaperIDs(in result: AgentToolResult) -> [String] {
        let pattern = #"paper_id:\s*([^\s]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(result.message.startIndex..<result.message.endIndex, in: result.message)
        return expression.matches(in: result.message, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: result.message) else {
                return nil
            }
            return String(result.message[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }

    private func normalizedEditedArguments(_ value: String?) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidArguments("edited arguments are required")
        }
        try validateArgumentsJSON(value)
        return AgentToolCallFingerprint.normalizedJSON(value)
    }

    private func validateArgumentsJSON(_ value: String) throws {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              object is [String: Any] else {
            throw AgentError.invalidArguments("tool arguments must be a JSON object")
        }
    }

    private func messageCharacterCount(_ messages: [LLMChatMessage]) -> Int {
        messages.reduce(0) { partial, message in
            partial
                + message.content.count
                + (message.name?.count ?? 0)
                + (message.toolCallID?.count ?? 0)
                + message.toolCalls.reduce(0) { $0 + $1.toolName.count + $1.argumentsJSON.count }
        }
    }

    private func hookSummary(_ result: AgentHookResult) -> String {
        [
            "\(result.eventName.rawValue) hook \(result.hookID).",
            result.permissionDecision.map { "Decision: \($0.rawValue)." },
            result.message,
            result.additionalContext
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        .joined(separator: " ")
    }

    private func encoded<T: Encodable>(_ value: T) throws -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8)
    }
}

private extension AgentPendingToolCall {
    nonisolated var isExpired: Bool {
        expiresAt.map { $0 < Date() } ?? false
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}