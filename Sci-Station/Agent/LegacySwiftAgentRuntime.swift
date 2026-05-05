import Foundation

public actor LegacySwiftAgentRuntime: ExternalAgentRuntime {
    private let loopRunner: AgentLoopRunner
    private let runDirectoryStore: AgentRunDirectoryStore
    private var requestsByRunID: [String: AgentRuntimeRequest] = [:]
    private var completedResultsByRunID: [String: AgentLoopResult] = [:]

    public init(
        loopRunner: AgentLoopRunner = AgentLoopRunner(),
        runDirectoryStore: AgentRunDirectoryStore = AgentRunDirectoryStore()
    ) {
        self.loopRunner = loopRunner
        self.runDirectoryStore = runDirectoryStore
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
        guard let originalRequest = requestsByRunID[runID] else {
            throw AgentError.invalidArguments("No active legacy runtime request found for run id: \(runID)")
        }
        guard let pending = try await runDirectoryStore.pending(runID: runID, in: originalRequest.root)
            ?? completedResultsByRunID[runID]?.pendingToolCall else {
            throw AgentError.invalidArguments("No pending checkpoint found for run id: \(runID)")
        }

        let result = try await loopRunner.resume(AgentLoopResumeRequest(
            pending: pending,
            action: decision.action,
            feedback: decision.feedback,
            editedArgumentsJSON: decision.editedArguments?.canonicalJSON,
            provider: originalRequest.provider,
            toolDefinitions: originalRequest.toolDefinitions,
            toolRegistry: originalRequest.toolRegistry,
            toolHost: originalRequest.toolHost,
            toolContext: originalRequest.toolContext,
            root: originalRequest.root,
            configuration: originalRequest.configuration,
            apiKey: originalRequest.apiKey,
            options: originalRequest.options,
            hookEngine: originalRequest.hookEngine,
            permissionEvaluator: originalRequest.permissionEvaluator,
            responseDeltaHandler: originalRequest.responseDeltaHandler
        ))
        completedResultsByRunID[runID] = result

        var sequence = try await runDirectoryStore.nextSequence(runID: runID, in: originalRequest.root)
        for event in runtimeEvents(from: result, definitions: originalRequest.toolDefinitions) {
            try await runDirectoryStore.appendEvent(
                AgentRuntimeEventEnvelope(runID: runID, threadID: originalRequest.threadID, sequence: sequence, event: event),
                in: originalRequest.root
            )
            sequence += 1
        }
    }

    public func cancelRun(runID: String) async throws {
        if let request = requestsByRunID[runID] {
            let sequence = try await runDirectoryStore.nextSequence(runID: runID, in: request.root)
            try await runDirectoryStore.appendEvent(
                AgentRuntimeEventEnvelope(runID: runID, threadID: request.threadID, sequence: sequence, event: .runCancelled(AgentRunCancelled(reason: "Cancelled by user."))),
                in: request.root
            )
        }
        completedResultsByRunID[runID] = nil
    }

    public func loadCheckpoint(runID: String) async throws -> AgentCheckpointSummary? {
        guard let request = requestsByRunID[runID] else {
            return nil
        }
        return try await runDirectoryStore.checkpointSummary(runID: runID, in: request.root)
    }

    public func completedLoopResult(runID: String) -> AgentLoopResult? {
        completedResultsByRunID[runID]
    }

    private func performStartRun(
        _ request: AgentRuntimeRequest,
        continuation: AsyncThrowingStream<AgentRuntimeEventEnvelope, Error>.Continuation
    ) async throws {
        requestsByRunID[request.runID] = request
        var sequence = try await runDirectoryStore.nextSequence(runID: request.runID, in: request.root)
        try await yield(
            AgentRuntimeEventEnvelope(
                runID: request.runID,
                threadID: request.threadID,
                sequence: sequence,
                event: .runStarted(AgentRunStarted(goal: request.goal))
            ),
            root: request.root,
            continuation: continuation
        )
        sequence += 1

        let result = try await loopRunner.run(request.asLoopRequest())
        completedResultsByRunID[request.runID] = result
        for event in runtimeEvents(from: result, definitions: request.toolDefinitions) {
            try await yield(
                AgentRuntimeEventEnvelope(
                    runID: request.runID,
                    threadID: request.threadID,
                    sequence: sequence,
                    event: event
                ),
                root: request.root,
                continuation: continuation
            )
            sequence += 1
        }
    }

    private func yield(
        _ envelope: AgentRuntimeEventEnvelope,
        root: ResearchRoot,
        continuation: AsyncThrowingStream<AgentRuntimeEventEnvelope, Error>.Continuation
    ) async throws {
        try await runDirectoryStore.appendEvent(envelope, in: root)
        continuation.yield(envelope)
    }

    private nonisolated func runtimeEvents(from result: AgentLoopResult, definitions: [AgentToolDefinition]) -> [AgentRuntimeEvent] {
        var events: [AgentRuntimeEvent] = []
        let definitionsByName = Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0) })
        for step in result.steps {
            if let message = step.assistantMessage, !message.content.isEmpty {
                events.append(.assistantMessage(AgentAssistantMessage(content: message.content)))
            }
            for call in step.toolCalls {
                let definition = definitionsByName[call.toolName]
                let arguments = (try? AgentToolArguments(rawJSON: call.argumentsJSON)) ?? .emptyObject
                let targetPaths = AgentToolArgumentInspection(argumentsJSON: call.argumentsJSON).paths
                events.append(.toolCallRequested(AgentToolCallRequested(
                    tool: call.toolName,
                    toolCallID: call.id,
                    arguments: arguments,
                    risk: definition?.risk ?? .externalSideEffect,
                    targetPaths: targetPaths
                )))
            }
            for toolResult in step.toolResults {
                let wireResult = AgentToolResultWireFormat(result: toolResult, toolCallID: toolResult.callID)
                events.append(.toolCallCompleted(AgentToolCallCompleted(tool: toolResult.toolName, toolCallID: toolResult.callID, result: wireResult)))
            }
            if let approval = step.pauseReason?.approvalRequest, step.pauseReason?.kind == .approvalRequired {
                events.append(.approvalRequired(approval))
            }
        }
        if let pending = result.pendingToolCall {
            events.append(.checkpointSaved(AgentCheckpointSummary(
                runID: result.runID,
                state: .waitingForApproval,
                pendingApprovalID: pending.approvalRequest.id,
                pendingToolCallID: pending.toolCall.id,
                targetPaths: pending.approvalRequest.targetPaths
            )))
        }
        if let finalResponse = result.finalResponseMarkdown {
            events.append(.finalResponse(AgentFinalResponse(markdown: finalResponse)))
        } else if let pauseReason = result.pauseReason, pauseReason.kind != .approvalRequired {
            events.append(.runFailed(AgentRunFailed(error: AgentRuntimeError(code: errorCode(for: pauseReason.kind), message: pauseReason.message))))
        }
        return events
    }

    private nonisolated func errorCode(for pauseKind: AgentLoopPauseKind) -> AgentRuntimeErrorCode {
        switch pauseKind {
        case .approvalRequired:
            return .approvalRequired
        case .contextLimitExceeded:
            return .contextLimitExceeded
        case .maxStepsExceeded:
            return .maxStepsExceeded
        case .maxToolCallsExceeded:
            return .maxToolCallsExceeded
        case .safetyPolicyBlocked:
            return .safetyPolicyBlocked
        case .deniedAndStopped:
            return .permissionDenied
        case .providerUnavailable:
            return .providerUnavailable
        }
    }
}

public actor FakeExternalAgentRuntime: ExternalAgentRuntime {
    private let scriptedEvents: [AgentRuntimeEvent]

    public init(scriptedEvents: [AgentRuntimeEvent]? = nil) {
        self.scriptedEvents = scriptedEvents ?? [
            .runStarted(AgentRunStarted(goal: "Fake runtime run")),
            .toolCallRequested(AgentToolCallRequested(tool: "read_paper_section", toolCallID: "fake-call-1", arguments: .emptyObject, risk: .readOnly)),
            .approvalRequired(AgentApprovalRequest(runID: "fake-run", toolCallID: "fake-call-2", toolName: "write_markdown_plan", permissionKey: AgentToolRisk.writesWorkspace.defaultPermissionKey, risk: .writesWorkspace, argumentsJSON: "{}", targetPaths: ["wiki/plans/fake.md"])),
            .finalResponse(AgentFinalResponse(markdown: "Fake runtime response."))
        ]
    }

    public func startRun(_ request: AgentRuntimeRequest) async throws -> AsyncThrowingStream<AgentRuntimeEventEnvelope, Error> {
        AsyncThrowingStream { continuation in
            for (offset, event) in scriptedEvents.enumerated() {
                continuation.yield(AgentRuntimeEventEnvelope(runID: request.runID, threadID: request.threadID, sequence: offset + 1, event: event))
            }
            continuation.finish()
        }
    }

    public func resumeRun(runID: String, decision: AgentHumanDecision) async throws {}
    public func cancelRun(runID: String) async throws {}
    public func loadCheckpoint(runID: String) async throws -> AgentCheckpointSummary? { nil }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}