import Foundation

public nonisolated struct AgentToolContext: Sendable {
    public var workspace: ResearchWorkspace
    public var selectedPaperID: String?

    public nonisolated init(workspace: ResearchWorkspace, selectedPaperID: String? = nil) {
        self.workspace = workspace
        self.selectedPaperID = selectedPaperID
    }
}

public protocol AgentTool: Sendable {
    nonisolated var definition: AgentToolDefinition { get }
    func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult
}

public actor AgentToolRegistry {
    private var tools: [String: any AgentTool]

    public init(tools: [any AgentTool]) {
        var indexedTools: [String: any AgentTool] = [:]
        for tool in tools {
            indexedTools[tool.definition.name] = tool
        }
        self.tools = indexedTools
    }

    public func definitions() -> [AgentToolDefinition] {
        tools.values
            .map(\.definition)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func definition(named name: String) -> AgentToolDefinition? {
        tools[name]?.definition
    }

    public func invoke(_ call: AgentToolCall, context: AgentToolContext) async throws -> AgentToolResult {
        guard let tool = tools[call.toolName] else {
            throw AgentError.unknownTool(call.toolName)
        }

        return try await tool.invoke(argumentsJSON: call.argumentsJSON, context: context)
    }
}

public actor AgentToolExecutor {
    private let registry: AgentToolRegistry

    public init(registry: AgentToolRegistry) {
        self.registry = registry
    }

    public func execute(
        plan: AgentPlan,
        context: AgentToolContext,
        approvedToolCallIDs: Set<String>
    ) async -> [AgentToolResult] {
        var results: [AgentToolResult] = []

        for call in plan.toolCalls {
            guard let definition = await registry.definition(named: call.toolName) else {
                results.append(
                    AgentToolResult(
                        callID: call.id,
                        toolName: call.toolName,
                        succeeded: false,
                        message: "Tool is not registered.",
                        errorMessage: AgentError.unknownTool(call.toolName).localizedDescription
                    )
                )
                continue
            }

            if definition.requiresConfirmation && !approvedToolCallIDs.contains(call.id) {
                results.append(
                    AgentToolResult(
                        callID: call.id,
                        toolName: call.toolName,
                        succeeded: false,
                        requiresConfirmation: true,
                        message: "Waiting for user confirmation before running \(definition.name)."
                    )
                )
                continue
            }

            do {
                var result = try await registry.invoke(call, context: context)
                if result.callID.isEmpty {
                    result.callID = call.id
                }
                results.append(result)
            } catch {
                results.append(
                    AgentToolResult(
                        callID: call.id,
                        toolName: call.toolName,
                        succeeded: false,
                        message: "Tool failed.",
                        errorMessage: error.localizedDescription
                    )
                )
            }
        }

        return results
    }
}