import Foundation

public nonisolated struct AgentMCPToolAnnotations: Codable, Hashable, Sendable {
    public var readOnly: Bool
    public var destructive: Bool
    public var idempotent: Bool
    public var openWorld: Bool

    public nonisolated init(readOnly: Bool, destructive: Bool, idempotent: Bool, openWorld: Bool) {
        self.readOnly = readOnly
        self.destructive = destructive
        self.idempotent = idempotent
        self.openWorld = openWorld
    }
}

public nonisolated struct SciStationToolDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var inputSchema: String
    public var risk: AgentToolRisk
    public var permissionKey: String
    public var source: String
    public var outputPolicy: AgentToolOutputPolicy
    public var annotations: AgentMCPToolAnnotations

    public nonisolated init(definition: AgentToolDefinition) {
        self.name = definition.name
        self.description = definition.summary
        self.inputSchema = definition.inputSchema
        self.risk = definition.risk
        self.permissionKey = definition.permissionKey
        self.source = definition.source
        self.outputPolicy = definition.outputPolicy
        self.annotations = AgentMCPToolAnnotations(
            readOnly: definition.risk == .readOnly,
            destructive: definition.risk == .destructive,
            idempotent: definition.risk == .readOnly,
            openWorld: definition.risk == .network || definition.risk == .externalSideEffect
        )
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
        case risk
        case permissionKey = "permission_key"
        case source
        case outputPolicy = "output_policy"
        case annotations
    }
}

public actor SciStationToolHost {
    private let legacyRegistry: AgentToolRegistry

    public init(legacyRegistry: AgentToolRegistry) {
        self.legacyRegistry = legacyRegistry
    }

    public func definitions() async -> [AgentToolDefinition] {
        await legacyRegistry.definitions().map(normalize)
    }

    public func sciStationDefinitions() async -> [SciStationToolDefinition] {
        await definitions().map(SciStationToolDefinition.init(definition:))
    }

    public func definition(named name: String) async -> AgentToolDefinition? {
        await legacyRegistry.definition(named: name).map(normalize)
    }

    public func invoke(_ call: AgentToolCall, context: AgentToolContext) async throws -> AgentToolResult {
        try await legacyRegistry.invoke(call, context: context)
    }

    public func buildApprovalRequest(
        for call: AgentToolCall,
        runID: String = "",
        context: AgentToolContext
    ) async throws -> AgentApprovalRequest {
        guard let definition = await definition(named: call.toolName) else {
            throw AgentError.unknownTool(call.toolName)
        }
        let arguments = try AgentToolArguments(rawJSON: call.argumentsJSON)
        let targetPaths = targetPaths(for: call, definition: definition, context: context)
        let summary = summaryPreview(for: call, definition: definition, targetPaths: targetPaths)
        return AgentApprovalRequest(
            runID: runID,
            toolCallID: call.id,
            tool: call.toolName,
            risk: definition.risk,
            permissionKey: definition.permissionKey,
            arguments: arguments,
            targetPaths: targetPaths,
            diffPreview: diffPreview(for: call, definition: definition, targetPaths: targetPaths),
            summaryPreview: summary,
            reason: definition.risk == .readOnly ? "Read-only tool call." : "\(definition.displayName) requires approval before execution.",
            rollbackHint: rollbackHint(for: definition, targetPaths: targetPaths),
            suggestedDecisions: [.allowOnce, .denyAndContinue, .denyAndStop, .reviseWithFeedback, .editArguments]
        )
    }

    private nonisolated func normalize(_ definition: AgentToolDefinition) -> AgentToolDefinition {
        AgentToolDefinition(
            identifier: definition.identifier,
            name: definition.name,
            displayName: definition.displayName,
            summary: definition.summary,
            inputSchema: normalizedInputSchema(definition.inputSchema),
            inputSchemaVersion: definition.inputSchemaVersion,
            risk: definition.risk,
            requiresConfirmation: definition.requiresConfirmation,
            permissionKey: definition.permissionKey,
            outputPolicy: definition.outputPolicy,
            examples: definition.examples,
            source: definition.source
        )
    }

    private nonisolated func normalizedInputSchema(_ schema: String) -> String {
        let trimmed = schema.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: normalized, encoding: .utf8) else {
            return trimmed
        }
        return text
    }

    private nonisolated func targetPaths(for call: AgentToolCall, definition: AgentToolDefinition, context: AgentToolContext) -> [String] {
        let inspectedPaths = AgentToolArgumentInspection(argumentsJSON: call.argumentsJSON).paths
        if !inspectedPaths.isEmpty {
            return inspectedPaths
        }
        switch call.toolName {
        case "create_todo":
            return ["tasks/todos.yaml"]
        case "update_paper_classification":
            if let paperID = stringArgument("paper_id", in: call.argumentsJSON) ?? context.selectedPaperID {
                return ["library/papers/\(paperID)/meta.yaml"]
            }
            return ["library/papers/*/meta.yaml"]
        case "write_markdown_plan":
            if let path = stringArgument("relative_path", in: call.argumentsJSON) {
                return [path]
            }
            return ["wiki/plans/*.md"]
        default:
            return definition.risk == .readOnly ? [] : ["workspace"]
        }
    }

    private nonisolated func diffPreview(for call: AgentToolCall, definition: AgentToolDefinition, targetPaths: [String]) -> String? {
        guard definition.risk != .readOnly else {
            return nil
        }
        let pathText = targetPaths.isEmpty ? "workspace" : targetPaths.joined(separator: ", ")
        switch call.toolName {
        case "create_todo":
            return "+ todo: \(stringArgument("title", in: call.argumentsJSON) ?? "Untitled todo")\n# target: \(pathText)"
        case "write_markdown_plan":
            return "+ markdown document\n# target: \(pathText)"
        case "update_paper_classification":
            return "~ paper metadata\n# target: \(pathText)"
        default:
            return "Tool may modify: \(pathText)"
        }
    }

    private nonisolated func summaryPreview(for call: AgentToolCall, definition: AgentToolDefinition, targetPaths: [String]) -> String {
        let pathText = targetPaths.isEmpty ? "no target path" : targetPaths.joined(separator: ", ")
        return "\(definition.displayName) (\(definition.risk.rawValue)) -> \(pathText)"
    }

    private nonisolated func rollbackHint(for definition: AgentToolDefinition, targetPaths: [String]) -> AgentRollbackHint? {
        guard definition.risk != .readOnly else {
            return nil
        }
        return AgentRollbackHint(summary: "Review or revert the listed workspace files if the approved tool result is wrong.", targetPaths: targetPaths)
    }

    private nonisolated func stringArgument(_ key: String, in rawJSON: String) -> String? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}