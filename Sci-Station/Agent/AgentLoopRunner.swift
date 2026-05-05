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

    public func saveLegacyFallback(_ pending: AgentPendingToolCall, in root: ResearchRoot) throws {
        let logURL = root.fileURL(for: Self.relativePath)
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(pending)
        guard let line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }

        if fileManager.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
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

        return try await continueLoop(
            runID: request.runID,
            goal: trimmedGoal,
            messages: request.initialMessages,
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
            startingStepIndex: 1,
            existingSteps: [],
            existingToolResults: []
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
            guard messageCharacterCount(messages) <= options.maxContextCharacters,
                  accumulatedToolCharacters <= options.maxAccumulatedToolResultCharacters else {
                let pause = AgentLoopPauseReason(kind: .contextLimitExceeded, message: "Agent loop stopped because context or tool result budget was exceeded.")
                steps.append(AgentLoopStep(stepIndex: stepIndex, pauseReason: pause))
                try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
                return AgentLoopResult(runID: runID, messages: messages, toolResults: toolResults, pauseReason: pause, steps: steps)
            }

            let request = LLMProviderRequest(
                messages: messages,
                tools: options.allowProviderNativeTools ? toolDefinitions.map(LLMToolSpecification.init(agentTool:)) : []
            )
            let response = try await provider.respond(to: request, configuration: configuration, apiKey: apiKey)
            let assistantMessage = LLMChatMessage(
                role: .assistant,
                content: response.message.content,
                toolCalls: response.toolCalls
            )
            messages.append(assistantMessage)
            try await appendAssistantEvent(assistantMessage, sessionID: runID, root: root)

            if response.toolCalls.isEmpty {
                let finalMarkdown = response.message.content
                if let responseDeltaHandler, !finalMarkdown.isEmpty {
                    await responseDeltaHandler(finalMarkdown)
                }
                steps.append(AgentLoopStep(stepIndex: stepIndex, assistantMessage: assistantMessage))
                try await appendStopHooks(hookEngine, sessionID: runID, root: root, toolResults: toolResults)
                return AgentLoopResult(runID: runID, finalResponseMarkdown: finalMarkdown, messages: messages, toolResults: toolResults, steps: steps)
            }

            var stepToolResults: [AgentToolResult] = []
            var cachedToolCallIDs: [String] = []
            for call in response.toolCalls {
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
                summary: "Running \(call.toolName).",
                payloadJSON: call.argumentsJSON
            ),
            in: root
        )

        let result: AgentToolResult
        do {
            var invoked = try await toolHost.invoke(call, context: toolContext)
            if invoked.callID.isEmpty {
                invoked.callID = call.id
            }
            result = limitedResult(invoked, definition: definition, options: options)
        } catch {
            result = AgentToolResult(
                callID: call.id,
                toolName: call.toolName,
                succeeded: false,
                message: "Tool failed: \(error.localizedDescription)",
                errorMessage: error.localizedDescription
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
                summary: result.message,
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
        let summary = message.content.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (message.toolCalls.isEmpty ? "Assistant response." : "Assistant requested tools: \(message.toolCalls.map(\.toolName).joined(separator: ", ")).")
        let payload = message.toolCalls.isEmpty ? nil : try encoded(message.toolCalls)
        try await appendEvent(
            AgentSessionEvent(
                sessionID: sessionID,
                kind: .assistantMessage,
                summary: summary,
                payloadJSON: payload
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
        return AgentApprovalRequest(
            runID: runID,
            toolCallID: call.id,
            toolName: call.toolName,
            permissionKey: definition?.permissionKey ?? risk.defaultPermissionKey,
            risk: risk,
            argumentsJSON: call.argumentsJSON,
            targetPaths: inspection.paths,
            diffPreview: risk == .readOnly ? nil : "Tool may modify: \(inspection.paths.joined(separator: ", ").nilIfEmpty ?? "workspace")",
            summaryPreview: "\(call.toolName) (\(risk.rawValue))",
            reason: message,
            rollbackHint: risk == .readOnly ? nil : AgentRollbackHint(summary: "Review or revert modified paths if the approved result is wrong.", targetPaths: inspection.paths)
        )
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
            modifiedPaths: result.modifiedPaths,
            errorMessage: result.errorMessage
        )
    }

    private func limited(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }
        let endIndex = text.index(text.startIndex, offsetBy: max(0, maxCharacters - 48))
        return String(text[..<endIndex]) + "\n[Tool output truncated by Sci-Station.]"
    }

    private func summary(for text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? text
        return limited(firstLine.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 240)
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