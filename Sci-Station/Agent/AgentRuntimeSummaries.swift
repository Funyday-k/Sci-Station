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
        self.payloadPreview = event.payloadJSON?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public nonisolated static func items(
        from events: [AgentSessionEvent],
        sessionIDs: Set<String>? = nil,
        limit: Int = 120
    ) -> [AgentSessionTimelineItem] {
        let filteredEvents = events.filter { event in
            sessionIDs.map { $0.contains(event.sessionID) } ?? true
        }
        .sorted { first, second in
            if first.createdAt == second.createdAt {
                return first.id.localizedStandardCompare(second.id) == .orderedAscending
            }
            return first.createdAt < second.createdAt
        }

        return Array(filteredEvents.suffix(max(0, limit))).map(AgentSessionTimelineItem.init(event:))
    }

    private nonisolated static func title(for kind: AgentSessionEventKind) -> String {
        switch kind {
        case .userMessage:
            return "用户消息"
        case .assistantMessage:
            return "AI 回复"
        case .reasoningSummary:
            return "思考摘要"
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
            let targetPaths = result?.modifiedPaths.nilIfEmpty ?? argumentInspection.paths
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
                diffPreview: risk == .readOnly ? nil : "Tool may modify: \(targetPaths.joined(separator: ", ").nilIfEmpty ?? "workspace")",
                summaryPreview: "\(call.toolName) (\(risk.rawValue))",
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
    case localWorkspaceConfig = "local_workspace_config"

    public nonisolated var label: String {
        switch self {
        case .trackedProductTemplate:
            return ".sci-ai/sci-station"
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

public struct AgentRuntimeConfigurationLoader {
    public var fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadProductPreset(
        in root: ResearchRoot,
        presetID: String = "research-core"
    ) throws -> AgentPresetSummary? {
        let relativePath = ".sci-ai/sci-station/presets/\(presetID)/plugin.json"
        let url = root.fileURL(for: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(AgentPluginManifest.self, from: data)
        let issues = AgentPluginValidator().validate(manifest)
        return AgentPresetSummary(
            manifest: manifest,
            manifestRelativePath: relativePath,
            validationIssues: issues
        )
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
        let isEnabled = boolValue(dictionary["is_enabled"]) ?? boolValue(dictionary["enabled"]) ?? true
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