import Foundation

public nonisolated struct AgentSessionTimelineItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var eventID: String
    public var sessionID: String
    public var createdAt: Date
    public var kind: AgentSessionEventKind
    public var title: String
    public var detail: String
    public var payloadPreview: String?

    public nonisolated init(event: AgentSessionEvent) {
        self.id = event.id
        self.eventID = event.id
        self.sessionID = event.sessionID
        self.createdAt = event.createdAt
        self.kind = event.kind
        self.title = Self.title(for: event.kind)
        self.detail = event.summary
        self.payloadPreview = Self.payloadPreview(for: event)
    }

    private nonisolated init(
        id: String,
        sessionID: String,
        createdAt: Date,
        kind: AgentSessionEventKind,
        title: String? = nil,
        detail: String,
        payloadPreview: String? = nil
    ) {
        self.id = id
        self.eventID = id
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.kind = kind
        self.title = title ?? Self.title(for: kind)
        self.detail = detail
        self.payloadPreview = payloadPreview?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private nonisolated static func payloadPreview(for event: AgentSessionEvent) -> String? {
        switch event.kind {
        case .userMessage, .assistantMessage:
            return nil
        default:
            return event.payloadJSON?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
    }

    public nonisolated static func items(
        from events: [AgentSessionEvent],
        sessionIDs: Set<String>? = nil,
        limit: Int? = nil
    ) -> [AgentSessionTimelineItem] {
        let filteredEvents = events.filter { event in
            sessionIDs.map { $0.contains(event.sessionID) } ?? true
        }
        .sorted(by: Self.sessionEventSort)

        let limitedEvents = Self.limited(filteredEvents, limit: limit)
        return limitedEvents.map(AgentSessionTimelineItem.init(event:))
    }

    public nonisolated static func items(
        from events: [AgentSessionEvent],
        runs: [AgentRun],
        sessionIDs: Set<String>? = nil,
        limit: Int? = nil
    ) -> [AgentSessionTimelineItem] {
        let filteredEvents = events.filter { event in
            sessionIDs.map { $0.contains(event.sessionID) } ?? true
        }
        let eventItems = filteredEvents.map(AgentSessionTimelineItem.init(event:))
        let eventSessionIDs = Set(filteredEvents.map(\.sessionID))
        var projectedRunIDs = Set<String>()
        let projectedTimelineItems = runs
            .filter { projectedRunIDs.insert($0.id).inserted }
            .filter { run in
                sessionIDs.map { $0.contains(run.id) } ?? true
            }
            .filter { !eventSessionIDs.contains($0.id) }
            .flatMap { projectedItems(from: $0) }

        let combined = (eventItems + projectedTimelineItems).sorted(by: Self.timelineItemSort)

        return Self.limited(combined, limit: limit)
    }

    private nonisolated static func limited<T>(_ values: [T], limit: Int?) -> [T] {
        guard let limit else {
            return values
        }
        guard limit > 0 else {
            return []
        }
        return Array(values.suffix(limit))
    }

    private nonisolated static func sessionEventSort(_ first: AgentSessionEvent, _ second: AgentSessionEvent) -> Bool {
        if first.createdAt != second.createdAt {
            return first.createdAt < second.createdAt
        }
        if first.sessionID != second.sessionID {
            return first.sessionID.localizedStandardCompare(second.sessionID) == .orderedAscending
        }
        let firstPriority = eventKindSortPriority(first.kind)
        let secondPriority = eventKindSortPriority(second.kind)
        if firstPriority != secondPriority {
            return firstPriority < secondPriority
        }
        return first.id.localizedStandardCompare(second.id) == .orderedAscending
    }

    private nonisolated static func timelineItemSort(_ first: AgentSessionTimelineItem, _ second: AgentSessionTimelineItem) -> Bool {
        if first.createdAt != second.createdAt {
            return first.createdAt < second.createdAt
        }
        if first.sessionID != second.sessionID {
            return first.sessionID.localizedStandardCompare(second.sessionID) == .orderedAscending
        }
        let firstPriority = eventKindSortPriority(first.kind)
        let secondPriority = eventKindSortPriority(second.kind)
        if firstPriority != secondPriority {
            return firstPriority < secondPriority
        }
        return first.id.localizedStandardCompare(second.id) == .orderedAscending
    }

    private nonisolated static func eventKindSortPriority(_ kind: AgentSessionEventKind) -> Int {
        switch kind {
        case .userMessage:
            return 0
        case .reasoningSummary:
            return 10
        case .assistantMessage:
            return 20
        case .toolCallStarted:
            return 30
        case .toolCallCompleted, .toolCallFailed:
            return 40
        case .artifactDraft, .permissionRequested:
            return 50
        case .permissionResolved:
            return 60
        case .runCancelled:
            return 70
        case .hookResult, .compactionSummary:
            return 90
        }
    }

    private nonisolated static func projectedItems(from run: AgentRun) -> [AgentSessionTimelineItem] {
        var items: [AgentSessionTimelineItem] = [
            AgentSessionTimelineItem(
                id: "projection-\(run.id)-user",
                sessionID: run.id,
                createdAt: run.createdAt,
                kind: .userMessage,
                detail: run.goal
            )
        ]

        for (index, result) in run.toolResults.enumerated() {
            items.append(AgentSessionTimelineItem(
                id: "projection-\(run.id)-tool-\(index)",
                sessionID: run.id,
                createdAt: run.createdAt.addingTimeInterval(0.01 + Double(index) * 0.001),
                kind: result.succeeded ? .toolCallCompleted : .toolCallFailed,
                detail: result.succeeded ? "已使用工具：\(result.toolName)" : "工具 \(result.toolName) 失败：\(result.errorMessage ?? result.message)",
                payloadPreview: result.payload?.canonicalJSON ?? result.message
            ))
        }

        let response = run.plan.finalResponseDraft?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        switch run.lifecycleState {
        case .cancelled:
            items.append(AgentSessionTimelineItem(
                id: "projection-\(run.id)-cancelled",
                sessionID: run.id,
                createdAt: (run.completedAt ?? run.createdAt).addingTimeInterval(0.02),
                kind: .runCancelled,
                detail: response ?? run.plan.risk ?? "用户已停止本次 AI 输出。"
            ))
        case .failed:
            if let response {
                items.append(AgentSessionTimelineItem(
                    id: "projection-\(run.id)-partial",
                    sessionID: run.id,
                    createdAt: run.createdAt.addingTimeInterval(0.02),
                    kind: .assistantMessage,
                    detail: response
                ))
            }
            items.append(AgentSessionTimelineItem(
                id: "projection-\(run.id)-failed",
                sessionID: run.id,
                createdAt: (run.completedAt ?? run.createdAt).addingTimeInterval(0.03),
                kind: .toolCallFailed,
                detail: run.plan.risk ?? run.plan.summary
            ))
        case .waitingForApproval:
            items.append(AgentSessionTimelineItem(
                id: "projection-\(run.id)-approval",
                sessionID: run.id,
                createdAt: run.createdAt.addingTimeInterval(0.02),
                kind: .permissionRequested,
                detail: run.plan.risk ?? run.plan.summary
            ))
        case .created, .running, .resuming, .completed:
            let detail = response ?? run.plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            if let detail {
                items.append(AgentSessionTimelineItem(
                    id: "projection-\(run.id)-assistant",
                    sessionID: run.id,
                    createdAt: (run.completedAt ?? run.createdAt).addingTimeInterval(0.02),
                    kind: .assistantMessage,
                    detail: detail
                ))
            }
        }

        return items
    }

    private nonisolated static func title(for kind: AgentSessionEventKind) -> String {
        switch kind {
        case .userMessage:
            return "用户消息"
        case .assistantMessage:
            return "AI 回复"
        case .reasoningSummary:
            return "思考摘要"
        case .artifactDraft:
            return "Artifact 草稿"
        case .runCancelled:
            return "已停止"
        case .permissionRequested:
            return "请求审批"
        case .permissionResolved:
            return "审批完成"
        case .toolCallStarted:
            return "工具开始"
        case .toolCallCompleted:
            return "工具完成"
        case .toolCallFailed:
            return "工具失败"
        case .hookResult:
            return "Hook 结果"
        case .compactionSummary:
            return "压缩摘要"
        }
    }
}

public nonisolated enum AgentTimelineStatus: String, Codable, Sendable {
    case pending
    case running
    case waitingForApproval
    case approved
    case denied
    case succeeded
    case failed
    case cancelled
    case info
}

public nonisolated struct AgentTimelineEvent: Identifiable, Codable, Hashable, Sendable {
    public nonisolated enum Kind: String, Codable, Sendable {
        case userMessage
        case assistantMessage
        case reasoningGroup
        case toolCall
        case permissionRequest
        case artifactDraft
        case error
        case systemNotice
    }

    public var id: String
    public var eventID: String
    public var runID: String
    public var threadID: String?
    public var kind: Kind
    public var sourceKind: AgentSessionEventKind
    public var timestamp: Date
    public var title: String
    public var summary: String
    public var status: AgentTimelineStatus
    public var targetPaths: [String]
    public var payloadPreview: String?
    public var toolName: String?
    public var stepCount: Int
    public var toolCount: Int
    public var isCollapsedByDefault: Bool

    public nonisolated init(
        id: String,
        eventID: String,
        runID: String,
        threadID: String? = nil,
        kind: Kind,
        sourceKind: AgentSessionEventKind,
        timestamp: Date,
        title: String,
        summary: String,
        status: AgentTimelineStatus,
        targetPaths: [String] = [],
        payloadPreview: String? = nil,
        toolName: String? = nil,
        stepCount: Int = 0,
        toolCount: Int = 0,
        isCollapsedByDefault: Bool = false
    ) {
        self.id = id
        self.eventID = eventID
        self.runID = runID
        self.threadID = threadID
        self.kind = kind
        self.sourceKind = sourceKind
        self.timestamp = timestamp
        self.title = title
        self.summary = summary
        self.status = status
        self.targetPaths = targetPaths
        self.payloadPreview = payloadPreview?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.toolName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.stepCount = stepCount
        self.toolCount = toolCount
        self.isCollapsedByDefault = isCollapsedByDefault
    }

    public nonisolated init(item: AgentSessionTimelineItem) {
        let mapped = Self.mapping(for: item.kind)
        self.init(
            id: item.id,
            eventID: item.eventID,
            runID: item.sessionID,
            threadID: nil,
            kind: mapped.kind,
            sourceKind: item.kind,
            timestamp: item.createdAt,
            title: mapped.title ?? item.title,
            summary: item.detail,
            status: mapped.status,
            targetPaths: Self.targetPaths(from: item.payloadPreview),
            payloadPreview: item.payloadPreview,
            toolName: Self.toolName(from: item),
            stepCount: mapped.kind == .reasoningGroup ? 1 : 0,
            toolCount: mapped.kind == .toolCall ? 1 : 0,
            isCollapsedByDefault: mapped.collapsed
        )
    }

    public nonisolated static func events(from items: [AgentSessionTimelineItem]) -> [AgentTimelineEvent] {
        let events = items
            .filter { $0.kind != .hookResult }
            .filter { !Self.isHiddenToolOnlyAssistantItem($0) }
            .map(AgentTimelineEvent.init(item:))
            .sorted { first, second in
                if first.timestamp == second.timestamp {
                    return first.id.localizedStandardCompare(second.id) == .orderedAscending
                }
                return first.timestamp < second.timestamp
            }
        return compactToolCallEvents(events)
    }

    private nonisolated static func isHiddenToolOnlyAssistantItem(_ item: AgentSessionTimelineItem) -> Bool {
        item.kind == .assistantMessage && item.detail == "工具调用准备就绪"
    }

    private nonisolated static func compactToolCallEvents(_ events: [AgentTimelineEvent]) -> [AgentTimelineEvent] {
        var compacted: [AgentTimelineEvent] = []
        var indexByKey: [String: Int] = [:]
        var openKeysByFallback: [String: [String]] = [:]

        for event in events {
            guard event.kind == .toolCall else {
                compacted.append(event)
                continue
            }

            var normalizedEvent = event
            let callKey = toolCallMergeKey(for: event)
            if let callKey {
                normalizedEvent.id = "tool-\(callKey)"
            }
            let fallbackKey = toolFallbackKey(for: event)

            if let callKey, let index = indexByKey[callKey] {
                compacted[index] = mergedToolEvent(compacted[index], with: normalizedEvent)
                closeOpenFallback(fallbackKey, key: callKey, in: &openKeysByFallback)
                continue
            }

            if event.status != .running,
               let fallbackKey,
               let openKey = openKeysByFallback[fallbackKey]?.last,
               let index = indexByKey[openKey] {
                compacted[index] = mergedToolEvent(compacted[index], with: normalizedEvent)
                if let callKey {
                    indexByKey[callKey] = index
                }
                closeOpenFallback(fallbackKey, key: openKey, in: &openKeysByFallback)
                continue
            }

            let key = callKey ?? "fallback-\(event.id)"
            indexByKey[key] = compacted.count
            if event.status == .running, let fallbackKey {
                openKeysByFallback[fallbackKey, default: []].append(key)
            }
            compacted.append(normalizedEvent)
        }

        return compacted
    }

    private nonisolated static func mergedToolEvent(
        _ existing: AgentTimelineEvent,
        with update: AgentTimelineEvent
    ) -> AgentTimelineEvent {
        var merged = existing
        merged.eventID = update.eventID
        merged.sourceKind = update.sourceKind
        merged.title = update.title
        merged.summary = update.summary.isEmpty ? existing.summary : update.summary
        merged.status = update.status
        merged.targetPaths = mergedTargetPaths(existing.targetPaths, update.targetPaths)
        merged.payloadPreview = update.payloadPreview ?? existing.payloadPreview
        merged.toolName = update.toolName ?? existing.toolName
        merged.toolCount = max(existing.toolCount, update.toolCount, 1)
        merged.isCollapsedByDefault = true
        return merged
    }

    private nonisolated static func mergedTargetPaths(_ first: [String], _ second: [String]) -> [String] {
        var seen = Set<String>()
        return (first + second).filter { path in
            seen.insert(path).inserted
        }
    }

    private nonisolated static func closeOpenFallback(
        _ fallbackKey: String?,
        key: String,
        in openKeysByFallback: inout [String: [String]]
    ) {
        guard let fallbackKey, var keys = openKeysByFallback[fallbackKey] else {
            return
        }
        keys.removeAll { $0 == key }
        openKeysByFallback[fallbackKey] = keys.isEmpty ? nil : keys
    }

    private nonisolated static func toolCallMergeKey(for event: AgentTimelineEvent) -> String? {
        guard let payloadPreview = event.payloadPreview,
              let callID = stringValue(for: ["tool_call_id", "toolCallID", "call_id", "callID"], in: payloadPreview) else {
            return nil
        }
        return "\(event.runID)-\(callID)"
    }

    private nonisolated static func toolFallbackKey(for event: AgentTimelineEvent) -> String? {
        guard let toolName = event.toolName?.lowercased() else {
            return nil
        }
        return "\(event.runID)-\(toolName)"
    }

    private nonisolated static func mapping(
        for sourceKind: AgentSessionEventKind
    ) -> (kind: Kind, status: AgentTimelineStatus, collapsed: Bool, title: String?) {
        switch sourceKind {
        case .userMessage:
            return (.userMessage, .succeeded, false, nil)
        case .assistantMessage:
            return (.assistantMessage, .succeeded, false, nil)
        case .reasoningSummary:
            return (.reasoningGroup, .info, true, "思考过程")
        case .artifactDraft:
            return (.artifactDraft, .waitingForApproval, true, "Wiki Draft Review")
        case .runCancelled:
            return (.error, .cancelled, false, nil)
        case .toolCallStarted:
            return (.toolCall, .running, true, nil)
        case .toolCallCompleted:
            return (.toolCall, .succeeded, true, nil)
        case .toolCallFailed:
            return (.toolCall, .failed, true, nil)
        case .permissionRequested:
            return (.permissionRequest, .waitingForApproval, true, "审批工具调用")
        case .permissionResolved:
            return (.permissionRequest, .approved, true, "审批结果")
        case .hookResult, .compactionSummary:
            return (.systemNotice, .info, true, nil)
        }
    }

    private nonisolated static func toolName(from item: AgentSessionTimelineItem) -> String? {
        if let payloadPreview = item.payloadPreview,
           let payloadToolName = stringValue(for: ["tool_name", "toolName", "tool", "name"], in: payloadPreview) {
            return payloadToolName
        }

        if let detailToolName = toolName(fromDetail: item.detail) {
            return detailToolName
        }

        let separators = ["：", ":"]
        for separator in separators {
            if let range = item.detail.range(of: separator) {
                let prefix = item.detail[..<range.lowerBound]
                let words = prefix.split(separator: " ")
                if let last = words.last {
                    return String(last)
                }
            }
        }
        return nil
    }

    private nonisolated static func toolName(fromDetail detail: String) -> String? {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "Running ",
            "Sidecar requested ",
            "正在使用工具：",
            "正在使用工具:",
            "已使用工具：",
            "已使用工具:"
        ]
        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            return sanitizedToolName(String(trimmed.dropFirst(prefix.count)))
        }
        if trimmed.hasPrefix("工具 ") {
            return sanitizedToolName(String(trimmed.dropFirst("工具 ".count)))
        }
        if trimmed.hasPrefix("Tool call ") {
            return sanitizedToolName(String(trimmed.dropFirst("Tool call ".count)))
        }
        return nil
    }

    private nonisolated static func sanitizedToolName(_ text: String) -> String? {
        let token = text
            .split { character in
                character.isWhitespace || ".。:：,，".contains(character)
            }
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
    }

    private nonisolated static func targetPaths(from payloadPreview: String?) -> [String] {
        guard let payloadPreview else {
            return []
        }
        var paths: [String] = []
        if let singlePath = stringValue(for: ["target_path", "draft_path", "proposed_path", "path"], in: payloadPreview) {
            paths.append(singlePath)
        }
        if let value = try? JSONValue.parse(payloadPreview), case let .object(object) = value {
            if let targetPaths = object["target_paths"]?.arrayValue {
                paths.append(contentsOf: targetPaths.compactMap(\.stringValue))
            }
            if let modifiedPaths = object["modified_paths"]?.arrayValue {
                paths.append(contentsOf: modifiedPaths.compactMap(\.stringValue))
            }
        }
        var seen = Set<String>()
        return paths.filter { path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return seen.insert(trimmed).inserted
        }
    }

    private nonisolated static func stringValue(for keys: [String], in payloadPreview: String) -> String? {
        guard let value = try? JSONValue.parse(payloadPreview), case let .object(object) = value else {
            return nil
        }
        for key in keys {
            if let text = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}

public nonisolated enum DraftReviewStatus: String, Codable, Sendable {
    case pending
    case approved
    case rejected
    case rewriteRequested
}

public nonisolated struct AgentDraftReviewItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var runID: String
    public var toolCallID: String
    public var targetPath: String
    public var markdownPreview: String
    public var diffPreview: String
    public var sourceContextSummary: String
    public var status: DraftReviewStatus

    public nonisolated init(
        id: String,
        runID: String,
        toolCallID: String,
        targetPath: String,
        markdownPreview: String,
        diffPreview: String = "",
        sourceContextSummary: String = "",
        status: DraftReviewStatus = .pending
    ) {
        self.id = id
        self.runID = runID
        self.toolCallID = toolCallID
        self.targetPath = targetPath
        self.markdownPreview = markdownPreview
        self.diffPreview = diffPreview
        self.sourceContextSummary = sourceContextSummary
        self.status = status
    }

    public nonisolated static func defaultWikiTargetPath(projectID: String?, slug: String = "ai-draft") -> String {
        let normalizedSlug = slug
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init) ?? "ai-draft"
        let filename = normalizedSlug.hasSuffix(".md") ? normalizedSlug : "\(normalizedSlug).md"
        if let projectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines), !projectID.isEmpty {
            return "projects/\(projectID)/wiki/\(filename)"
        }
        return "wiki/\(filename)"
    }
}

public nonisolated enum AgentPermissionDockApprovalState: String, Codable, Sendable {
    case autoAllowed = "auto_allowed"
    case waitingForApproval = "waiting_for_approval"
    case allowedOnce = "allowed_once"
    case denied = "denied"
    case deniedByPolicy = "denied_by_policy"
    case sessionApprovalDraft = "session_approval_draft"
    case completed = "completed"
    case failed = "failed"
}

public nonisolated struct AgentPermissionDockState: Codable, Hashable, Sendable {
    public var approvedCallIDs: Set<String>
    public var deniedCallIDs: Set<String>
    public var sessionScopedApprovalDraftCallIDs: Set<String>
    public var correctionFeedbackByCallID: [String: String]

    public nonisolated init(
        approvedCallIDs: Set<String> = [],
        deniedCallIDs: Set<String> = [],
        sessionScopedApprovalDraftCallIDs: Set<String> = [],
        correctionFeedbackByCallID: [String: String] = [:]
    ) {
        self.approvedCallIDs = approvedCallIDs
        self.deniedCallIDs = deniedCallIDs
        self.sessionScopedApprovalDraftCallIDs = sessionScopedApprovalDraftCallIDs
        self.correctionFeedbackByCallID = correctionFeedbackByCallID
    }
}

public nonisolated struct AgentPermissionDockItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var runID: String
    public var toolCallID: String
    public var toolName: String
    public var displayName: String
    public var summary: String
    public var permissionKey: String
    public var risk: AgentToolRisk
    public var targetPaths: [String]
    public var fingerprint: String
    public var diffPreview: String?
    public var summaryPreview: String?
    public var rollbackHint: AgentRollbackHint?
    public var decision: AgentPermissionDecision
    public var matchedPolicyDescription: String
    public var moduleScopeDescription: String?
    public var approvalState: AgentPermissionDockApprovalState
    public var pathPreview: [String]
    public var argumentsPreview: String
    public var correctionFeedback: String?
    public var sideEffectsRequirePermission: Bool

    public nonisolated static func items(
        for run: AgentRun,
        toolDefinitions: [AgentToolDefinition],
        state: AgentPermissionDockState = AgentPermissionDockState(),
        rules: [AgentPermissionRule] = AgentSafetyPreset.defaultPermissionRules()
    ) -> [AgentPermissionDockItem] {
        let evaluator = AgentPermissionEvaluator(rules: rules)

        return run.plan.toolCalls.map { call in
            let definition = toolDefinitions.first { $0.name == call.toolName }
            let result = run.toolResults.first { $0.callID == call.id }
            let argumentInspection = AgentToolArgumentInspection(argumentsJSON: call.argumentsJSON)
            let risk = definition?.risk ?? .externalSideEffect
            let permissionKey = definition?.permissionKey ?? risk.defaultPermissionKey
            let targetPaths = result?.modifiedPaths.nilIfEmpty ?? Self.targetPaths(for: call, inspectedPaths: argumentInspection.paths)
            let approvalArguments = (try? AgentToolArguments(rawJSON: call.argumentsJSON)) ?? .emptyObject
            let fingerprint = AgentApprovalRequest.fingerprint(
                tool: call.toolName,
                risk: risk,
                permissionKey: permissionKey,
                canonicalArgumentsJSON: approvalArguments.canonicalJSON,
                targetPaths: targetPaths
            )
            let decision = evaluator.evaluate(
                AgentPermissionRequest(
                    toolName: call.toolName,
                    permissionKey: permissionKey,
                    command: argumentInspection.command,
                    path: argumentInspection.paths.first,
                    risk: risk
                )
            )
            let policyDescription = Self.policyDescription(for: decision, rules: rules, risk: risk)
            let approvalState = Self.approvalState(
                callID: call.id,
                decision: decision,
                result: result,
                state: state
            )

            return AgentPermissionDockItem(
                id: call.id,
                runID: run.id,
                toolCallID: call.id,
                toolName: call.toolName,
                displayName: definition?.displayName ?? call.toolName,
                summary: definition?.summary ?? "Tool definition is not registered for this runtime.",
                permissionKey: permissionKey,
                risk: risk,
                targetPaths: targetPaths,
                fingerprint: fingerprint,
                diffPreview: Self.diffPreview(for: call, risk: risk, targetPaths: targetPaths),
                summaryPreview: Self.summaryPreview(for: call, risk: risk, targetPaths: targetPaths),
                rollbackHint: risk == .readOnly ? nil : AgentRollbackHint(summary: "Review or revert target paths if the approved operation is wrong.", targetPaths: targetPaths),
                decision: decision,
                matchedPolicyDescription: policyDescription,
                moduleScopeDescription: nil,
                approvalState: approvalState,
                pathPreview: targetPaths,
                argumentsPreview: call.argumentsJSON,
                correctionFeedback: state.correctionFeedbackByCallID[call.id]?.nilIfEmpty,
                sideEffectsRequirePermission: risk != .readOnly
            )
        }
    }

    private nonisolated static func targetPaths(for call: AgentToolCall, inspectedPaths: [String]) -> [String] {
        if !inspectedPaths.isEmpty {
            return inspectedPaths
        }
        guard call.toolName == "write_markdown_plan" || call.toolName == "write_wiki_markdown" else {
            return []
        }
        if let relativePath = stringArgument("relative_path", in: call.argumentsJSON)?.nilIfEmpty {
            return [relativePath]
        }
        if let title = stringArgument("title", in: call.argumentsJSON)?.nilIfEmpty {
            return ["wiki/plans/\(slug(from: title)).md"]
        }
        return ["wiki/plans/*.md"]
    }

    private nonisolated static func diffPreview(for call: AgentToolCall, risk: AgentToolRisk, targetPaths: [String]) -> String? {
        guard risk != .readOnly else {
            return nil
        }
        let pathText = targetPaths.joined(separator: ", ").nilIfEmpty ?? "workspace"
        guard call.toolName == "write_markdown_plan" || call.toolName == "write_wiki_markdown" else {
            return "Tool may modify: \(pathText)"
        }
        let title = stringArgument("title", in: call.argumentsJSON)?.nilIfEmpty ?? "Markdown draft"
        let body = stringArgument("body", in: call.argumentsJSON)?.nilIfEmpty ?? ""
        return """
        # target: \(pathText)
        # mode: create_or_replace
        # title: \(title)

        \(limited(body, maxCharacters: 1_200))
        """
    }

    private nonisolated static func summaryPreview(for call: AgentToolCall, risk: AgentToolRisk, targetPaths: [String]) -> String {
        let pathText = targetPaths.joined(separator: ", ").nilIfEmpty ?? "workspace"
        if call.toolName == "write_markdown_plan" || call.toolName == "write_wiki_markdown" {
            let title = stringArgument("title", in: call.argumentsJSON)?.nilIfEmpty ?? "Markdown draft"
            return "Markdown 写入草稿（\(risk.rawValue)）-> \(pathText)：\(title)"
        }
        return "\(call.toolName) (\(risk.rawValue)) -> \(pathText)"
    }

    private nonisolated static func stringArgument(_ key: String, in rawJSON: String) -> String? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object[key] as? String
    }

    private nonisolated static func slug(from title: String) -> String {
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
        return slug.isEmpty ? "markdown-draft" : slug
    }

    private nonisolated static func limited(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }
        return String(text.prefix(maxCharacters)) + "\n..."
    }

    private nonisolated static func policyDescription(
        for decision: AgentPermissionDecision,
        rules: [AgentPermissionRule],
        risk: AgentToolRisk
    ) -> String {
        if let ruleID = decision.ruleID,
           let rule = rules.first(where: { $0.id == ruleID }) {
            return "Matched rule: \(rule.id) - \(rule.description)"
        }

        switch decision.action {
        case .allow:
            return "Default policy: auto-allow \(risk.rawValue)"
        case .ask:
            return "Default policy: ask before \(risk.rawValue)"
        case .deny:
            return "Default policy: deny \(risk.rawValue)"
        }
    }

    private nonisolated static func approvalState(
        callID: String,
        decision: AgentPermissionDecision,
        result: AgentToolResult?,
        state: AgentPermissionDockState
    ) -> AgentPermissionDockApprovalState {
        if let result {
            return result.succeeded ? .completed : .failed
        }
        if state.deniedCallIDs.contains(callID) {
            return .denied
        }
        if state.approvedCallIDs.contains(callID) {
            return .allowedOnce
        }
        if state.sessionScopedApprovalDraftCallIDs.contains(callID) {
            return .sessionApprovalDraft
        }
        if decision.action == .deny {
            return .deniedByPolicy
        }
        if decision.action == .allow {
            return .autoAllowed
        }
        return .waitingForApproval
    }
}

public nonisolated struct AgentHookStatus: Identifiable, Hashable, Sendable {
    public var id: String
    public var eventName: AgentHookEventName
    public var matcher: String?
    public var isEnabled: Bool
    public var permissionDecision: AgentPermissionAction?
    public var message: String?
    public var additionalContext: String?

    public nonisolated init(hook: AgentHookDefinition, disabledHookIDs: Set<String> = []) {
        self.id = hook.id
        self.eventName = hook.eventName
        self.matcher = hook.matcher
        self.isEnabled = hook.isEnabled && !disabledHookIDs.contains(hook.id)
        self.permissionDecision = hook.permissionDecision
        self.message = hook.message
        self.additionalContext = hook.additionalContext
    }
}

public nonisolated struct AgentHookActivityItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var eventID: String
    public var sessionID: String
    public var createdAt: Date
    public var summary: String
    public var hookID: String?
    public var eventName: AgentHookEventName?
    public var permissionDecision: AgentPermissionAction?
    public var additionalContext: String?

    public nonisolated init(event: AgentSessionEvent) {
        self.id = event.id
        self.eventID = event.id
        self.sessionID = event.sessionID
        self.createdAt = event.createdAt
        self.summary = event.summary

        if let payload = event.payloadJSON?.data(using: .utf8),
           let result = try? JSONDecoder().decode(AgentHookResult.self, from: payload) {
            self.hookID = result.hookID
            self.eventName = result.eventName
            self.permissionDecision = result.permissionDecision
            self.additionalContext = result.additionalContext
        } else {
            self.hookID = nil
            self.eventName = nil
            self.permissionDecision = nil
            self.additionalContext = nil
        }
    }
}

public nonisolated struct AgentHookActivitySummary: Hashable, Sendable {
    public var hooks: [AgentHookStatus]
    public var results: [AgentHookActivityItem]

    public nonisolated init(
        hooks: [AgentHookDefinition] = AgentSafetyPreset.defaultHooks(),
        events: [AgentSessionEvent] = [],
        disabledHookIDs: Set<String> = []
    ) {
        self.hooks = hooks.map { AgentHookStatus(hook: $0, disabledHookIDs: disabledHookIDs) }
        self.results = events
            .filter { $0.kind == .hookResult }
            .sorted { $0.createdAt < $1.createdAt }
            .map(AgentHookActivityItem.init(event:))
    }

    public nonisolated var enabledEventNames: [AgentHookEventName] {
        uniqueOrdered(hooks.filter(\.isEnabled).map(\.eventName))
    }
}

public nonisolated enum AgentMCPServerSource: String, Codable, Sendable {
    case trackedProductTemplate = "tracked_product_template"
    case workspaceProfile = "workspace_profile"
    case localWorkspaceConfig = "local_workspace_config"

    public nonisolated var label: String {
        switch self {
        case .trackedProductTemplate:
            return ".sci-ai/sci-station"
        case .workspaceProfile:
            return ".sci-station/agent/profile.json"
        case .localWorkspaceConfig:
            return ".sci-ai/workspace.local"
        }
    }
}

public nonisolated struct AgentMCPServerStatus: Identifiable, Hashable, Sendable {
    public var id: String
    public var source: AgentMCPServerSource
    public var displayName: String
    public var isEnabled: Bool
    public var endpointSummary: String
    public var allowedTools: [String]
    public var timeoutSeconds: Double
    public var credentialReferenceCount: Int
    public var sideEffectsRequirePermission: Bool

    public nonisolated init(
        id: String,
        source: AgentMCPServerSource,
        displayName: String,
        isEnabled: Bool,
        endpointSummary: String,
        allowedTools: [String] = [],
        timeoutSeconds: Double = 30,
        credentialReferenceCount: Int = 0,
        sideEffectsRequirePermission: Bool = true
    ) {
        self.id = id
        self.source = source
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.endpointSummary = endpointSummary
        self.allowedTools = allowedTools
        self.timeoutSeconds = timeoutSeconds
        self.credentialReferenceCount = credentialReferenceCount
        self.sideEffectsRequirePermission = sideEffectsRequirePermission
    }

    public nonisolated init(server: MCPServerConfiguration, source: AgentMCPServerSource) {
        let endpoint: String
        switch server.transport {
        case .localCommand:
            endpoint = ([server.command].compactMap { $0 } + server.arguments).joined(separator: " ").nilIfEmpty ?? "local command not configured"
        case .remoteHTTP, .remoteSSE:
            endpoint = server.urlString?.nilIfEmpty ?? "remote URL not configured"
        }

        self.init(
            id: server.id,
            source: source,
            displayName: server.displayName,
            isEnabled: server.isEnabled,
            endpointSummary: endpoint,
            allowedTools: server.allowedTools,
            timeoutSeconds: server.timeoutSeconds,
            credentialReferenceCount: server.headerReferences.count + server.secretReferences.count,
            sideEffectsRequirePermission: true
        )
    }
}

public nonisolated struct AgentPresetSummary: Hashable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String
    public var manifestRelativePath: String
    public var commands: [AgentCommandTemplate]
    public var skills: [AgentSkillManifest]
    public var hooks: [AgentHookDefinition]
    public var mcpServers: [AgentMCPServerStatus]
    public var validationIssues: [AgentPluginValidationIssue]

    public nonisolated init(
        manifest: AgentPluginManifest,
        manifestRelativePath: String,
        validationIssues: [AgentPluginValidationIssue] = []
    ) {
        self.id = manifest.id
        self.name = manifest.name
        self.version = manifest.version
        self.description = manifest.description
        self.manifestRelativePath = manifestRelativePath
        self.commands = manifest.commands
        self.skills = manifest.skills
        self.hooks = manifest.hooks
        self.mcpServers = manifest.mcpServers.map { AgentMCPServerStatus(server: $0, source: .trackedProductTemplate) }
        self.validationIssues = validationIssues
    }
}

public nonisolated struct AgentWorkspaceProfileSummary: Hashable, Sendable {
    public var relativePath: String
    public var promptTemplateCount: Int
    public var enabledPromptTemplateCount: Int
    public var skillToggleCount: Int
    public var enabledSkillCount: Int
    public var mcpServers: [AgentMCPServerStatus]
    public var validationIssues: [AgentPluginValidationIssue]

    public nonisolated init(
        profile: AgentWorkspaceProfile,
        relativePath: String = AgentWorkspaceProfileRepository.relativePath,
        validationIssues: [AgentPluginValidationIssue] = []
    ) {
        self.relativePath = relativePath
        self.promptTemplateCount = profile.promptTemplates.count
        self.enabledPromptTemplateCount = profile.enabledPromptTemplates.count
        self.skillToggleCount = profile.skillToggles.count
        self.enabledSkillCount = profile.enabledSkillIDs.count
        self.mcpServers = profile.mcpServers.map { AgentMCPServerStatus(server: $0, source: .workspaceProfile) }
        self.validationIssues = validationIssues
    }
}

public nonisolated struct AgentRuntimeConfigurationLoader {
    public var fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadProductPreset(
        in root: ResearchRoot,
        presetID: String = "research-core"
    ) throws -> AgentPresetSummary? {
        guard let manifest = try loadProductPresetManifest(in: root, presetID: presetID) else {
            return nil
        }
        let relativePath = ".sci-ai/sci-station/presets/\(presetID)/plugin.json"
        let issues = AgentPluginValidator().validate(manifest)
        return AgentPresetSummary(
            manifest: manifest,
            manifestRelativePath: relativePath,
            validationIssues: issues
        )
    }

    public func loadProductPresetManifest(
        in root: ResearchRoot,
        presetID: String = "research-core"
    ) throws -> AgentPluginManifest? {
        let relativePath = ".sci-ai/sci-station/presets/\(presetID)/plugin.json"
        let url = root.fileURL(for: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try JSONDecoder().decode(AgentPluginManifest.self, from: Data(contentsOf: url))
    }

    public func loadWorkspaceProfile(in root: ResearchRoot) async throws -> AgentWorkspaceProfileSummary {
        let profile = try await AgentWorkspaceProfileRepository(fileManager: fileManager).load(in: root)
        let issues = AgentWorkspaceProfileValidator().validate(profile)
        return AgentWorkspaceProfileSummary(profile: profile, validationIssues: issues)
    }

    public func loadLocalMCPServerStatuses(in root: ResearchRoot) throws -> [AgentMCPServerStatus] {
        let candidateRelativePaths = [
            ".sci-ai/workspace.local/mcp.json",
            ".sci-ai/workspace.local/mcp.local.json",
            ".mcp.json"
        ]

        for relativePath in candidateRelativePaths {
            let url = root.fileURL(for: relativePath)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            let data = try Data(contentsOf: url)
            return try Self.localMCPServerStatuses(from: data)
        }

        return []
    }

    public func loadLocalMCPServerConfigurations(in root: ResearchRoot) throws -> [MCPServerConfiguration] {
        let candidateRelativePaths = [
            ".sci-ai/workspace.local/mcp.json",
            ".sci-ai/workspace.local/mcp.local.json",
            ".mcp.json"
        ]

        for relativePath in candidateRelativePaths {
            let url = root.fileURL(for: relativePath)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            return try Self.localMCPServerConfigurations(from: Data(contentsOf: url))
        }
        return []
    }

    public nonisolated static func localMCPServerConfigurations(from data: Data) throws -> [MCPServerConfiguration] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        if let serverArray = root["mcp_servers"] as? [[String: Any]] {
            return serverArray.compactMap { configuration(fromLocalServerDictionary: $0, fallbackID: nil) }
        }
        if let serverDictionary = root["mcpServers"] as? [String: [String: Any]] {
            return serverDictionary.keys.sorted().compactMap { key in
                configuration(fromLocalServerDictionary: serverDictionary[key] ?? [:], fallbackID: key)
            }
        }
        return []
    }

    public nonisolated static func localMCPServerStatuses(from data: Data) throws -> [AgentMCPServerStatus] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        if let serverArray = root["mcp_servers"] as? [[String: Any]] {
            return serverArray.compactMap { status(fromLocalServerDictionary: $0, fallbackID: nil) }
        }

        if let serverDictionary = root["mcpServers"] as? [String: [String: Any]] {
            return serverDictionary.keys.sorted().compactMap { key in
                status(fromLocalServerDictionary: serverDictionary[key] ?? [:], fallbackID: key)
            }
        }

        return []
    }

    private nonisolated static func status(
        fromLocalServerDictionary dictionary: [String: Any],
        fallbackID: String?
    ) -> AgentMCPServerStatus? {
        let id = stringValue(dictionary["id"]) ?? fallbackID
        guard let id, !id.isEmpty else {
            return nil
        }

        let displayName = stringValue(dictionary["display_name"])
            ?? stringValue(dictionary["name"])
            ?? id
        let isEnabled = boolValue(dictionary["is_enabled"]) ?? boolValue(dictionary["enabled"]) ?? false
        let command = stringValue(dictionary["command"])
        let arguments = stringArray(dictionary["arguments"]) ?? stringArray(dictionary["args"]) ?? []
        let urlString = stringValue(dictionary["url"])
            ?? stringValue(dictionary["remote_url"])
        let endpointSummary = urlString?.nilIfEmpty
            ?? (([command].compactMap { $0 } + arguments).joined(separator: " ").nilIfEmpty ?? "local endpoint not configured")
        let allowedTools = stringArray(dictionary["allowed_tools"]) ?? stringArray(dictionary["allowedTools"]) ?? []
        let timeoutSeconds = doubleValue(dictionary["timeout_seconds"])
            ?? doubleValue(dictionary["timeout"])
            ?? 30

        return AgentMCPServerStatus(
            id: id,
            source: .localWorkspaceConfig,
            displayName: displayName,
            isEnabled: isEnabled,
            endpointSummary: endpointSummary,
            allowedTools: allowedTools,
            timeoutSeconds: timeoutSeconds,
            credentialReferenceCount: credentialReferenceCount(in: dictionary),
            sideEffectsRequirePermission: true
        )
    }

    private nonisolated static func configuration(
        fromLocalServerDictionary dictionary: [String: Any],
        fallbackID: String?
    ) -> MCPServerConfiguration? {
        let id = stringValue(dictionary["id"]) ?? fallbackID
        guard let id, !id.isEmpty else {
            return nil
        }

        let command = stringValue(dictionary["command"])
        let urlString = stringValue(dictionary["url"]) ?? stringValue(dictionary["remote_url"])
        let explicitTransport = stringValue(dictionary["transport"]).flatMap(MCPServerTransport.init(rawValue:))
        let transport = explicitTransport ?? (command == nil ? .remoteHTTP : .localCommand)
        let environment = dictionary["env"] as? [String: Any] ?? [:]
        let invalidSensitiveEnvironmentKeys = environment.compactMap { key, value -> String? in
            guard isSensitiveName(key),
                  let text = stringValue(value),
                  !text.hasCredentialReferencePrefix else {
                return nil
            }
            return "invalid_raw:\(key)"
        }
        let secretReferences = (stringArray(dictionary["secret_references"]) ?? []) + invalidSensitiveEnvironmentKeys
        let headerReferences = (dictionary["header_references"] as? [[String: Any]] ?? []).compactMap { header -> MCPHeaderReference? in
            guard let name = stringValue(header["name"]),
                  let valueReference = stringValue(header["value_reference"]) else {
                return nil
            }
            return MCPHeaderReference(name: name, valueReference: valueReference)
        }

        return MCPServerConfiguration(
            id: id,
            displayName: stringValue(dictionary["display_name"]) ?? stringValue(dictionary["name"]) ?? id,
            transport: transport,
            isEnabled: boolValue(dictionary["is_enabled"]) ?? boolValue(dictionary["enabled"]) ?? false,
            command: command,
            arguments: stringArray(dictionary["arguments"]) ?? stringArray(dictionary["args"]) ?? [],
            urlString: urlString,
            timeoutSeconds: doubleValue(dictionary["timeout_seconds"]) ?? doubleValue(dictionary["timeout"]) ?? 30,
            allowedTools: stringArray(dictionary["allowed_tools"]) ?? stringArray(dictionary["allowedTools"]) ?? [],
            headerReferences: headerReferences,
            secretReferences: secretReferences
        )
    }

    private nonisolated static func credentialReferenceCount(in dictionary: [String: Any]) -> Int {
        var count = 0
        count += stringArray(dictionary["secret_references"])?.count ?? 0
        count += (dictionary["header_references"] as? [[String: Any]])?.count ?? 0

        if let env = dictionary["env"] as? [String: Any] {
            count += env.filter { key, value in
                isSensitiveName(key) || (stringValue(value)?.hasCredentialReferencePrefix == true)
            }.count
        }

        return count
    }

    private nonisolated static func isSensitiveName(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        return ["token", "secret", "password", "credential", "api_key", "apikey", "private_key"]
            .contains { lowercasedName.contains($0) }
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private nonisolated static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let string = value as? String {
            return Bool(string)
        }
        return nil
    }

    private nonisolated static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private nonisolated static func stringArray(_ value: Any?) -> [String]? {
        value as? [String]
    }
}

public nonisolated enum AgentDiagnosticRedactor {
    public static func redacted(_ value: String, homeDirectory: String = NSHomeDirectory()) -> String {
        var output = value
        if !homeDirectory.isEmpty {
            output = output.replacingOccurrences(of: homeDirectory, with: "~")
        }
        output = replacing(pattern: #"/Users/[^/\s]+"#, in: output, with: "~")
        output = replacing(pattern: #"(?i)(bearer\s+)[A-Za-z0-9._\-+/=]{12,}"#, in: output, with: "$1[redacted]")
        output = replacing(pattern: #"(?i)(api[_-]?key|token|secret|password)(\s*[:=]\s*)[^\s;&]+"#, in: output, with: "$1$2[redacted]")
        output = replacing(pattern: #"sk-[A-Za-z0-9._\-]{12,}"#, in: output, with: "sk-[redacted]")
        return output
    }

    private static func replacing(pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}

private nonisolated func uniqueOrdered<T: Hashable>(_ values: [T]) -> [T] {
    var seen: Set<T> = []
    var result: [T] = []
    for value in values where !seen.contains(value) {
        seen.insert(value)
        result.append(value)
    }
    return result
}

private extension Array {
    nonisolated var nilIfEmpty: [Element]? {
        isEmpty ? nil : self
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    nonisolated var hasCredentialReferencePrefix: Bool {
        lowercased().hasPrefix("keychain:") || lowercased().hasPrefix("env:") || hasPrefix("${")
    }
}
