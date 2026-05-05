import Foundation

public nonisolated struct AgentMCPEnvelope: Codable, Hashable, Sendable, Identifiable {
    public var jsonrpc: String
    public var id: String
    public var method: String?
    public var params: JSONValue?
    public var result: JSONValue?
    public var error: AgentMCPError?

    public nonisolated init(
        jsonrpc: String = "2.0",
        id: String,
        method: String? = nil,
        params: JSONValue? = nil,
        result: JSONValue? = nil,
        error: AgentMCPError? = nil
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }
}

public nonisolated struct AgentMCPError: Codable, Hashable, Sendable {
    public var code: Int
    public var message: String

    public nonisolated init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public actor AgentMCPGateway {
    private let toolHost: SciStationToolHost
    private let permissionEvaluator: AgentPermissionEvaluator
    private let runtimeEventHandler: (@Sendable (AgentRuntimeEvent) async -> Void)?

    public init(
        toolHost: SciStationToolHost,
        permissionEvaluator: AgentPermissionEvaluator = AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules()),
        runtimeEventHandler: (@Sendable (AgentRuntimeEvent) async -> Void)? = nil
    ) {
        self.toolHost = toolHost
        self.permissionEvaluator = permissionEvaluator
        self.runtimeEventHandler = runtimeEventHandler
    }

    public func handle(_ request: AgentMCPEnvelope, context: AgentToolContext, runID: String = "mcp-run") async -> AgentMCPEnvelope {
        guard request.jsonrpc == "2.0" else {
            return errorResponse(id: request.id, code: -32600, message: "jsonrpc must be 2.0")
        }
        guard let method = request.method else {
            return errorResponse(id: request.id, code: -32600, message: "method is required")
        }

        do {
            switch method {
            case "tools/list":
                let tools = try await toolHost.sciStationDefinitions().map(mcpToolValue)
                return AgentMCPEnvelope(id: request.id, result: .object(["tools": .array(tools)]))
            case "tools/call":
                return try await handleToolCall(request, context: context, runID: runID)
            case "resources/list":
                return AgentMCPEnvelope(id: request.id, result: .object([
                    "resources": .array([
                        .object(["uri": .string("sci-station://workspace"), "name": .string("Sci-Station Workspace")]),
                        .object(["uri": .string("sci-station://tools"), "name": .string("Sci-Station Tool Definitions")])
                    ])
                ]))
            case "resources/read":
                return AgentMCPEnvelope(id: request.id, result: .object([
                    "contents": .array([.object(["type": .string("text"), "text": .string("Sci-Station local gateway resources are metadata-only in P33 V1.")])])
                ]))
            default:
                return errorResponse(id: request.id, code: -32601, message: "Unsupported MCP method: \(method)")
            }
        } catch {
            return errorResponse(id: request.id, code: -32603, message: error.localizedDescription)
        }
    }

    private func handleToolCall(_ request: AgentMCPEnvelope, context: AgentToolContext, runID: String) async throws -> AgentMCPEnvelope {
        guard let params = request.params?.objectValue,
              let name = params["name"]?.stringValue else {
            return errorResponse(id: request.id, code: -32602, message: "tools/call requires params.name")
        }
        let argumentsValue = params["arguments"] ?? .object([:])
        let arguments = try AgentToolArguments(value: argumentsValue)
        let call = AgentToolCall(id: "mcp-call-\(UUID().uuidString.lowercased())", toolName: name, argumentsJSON: arguments.canonicalJSON)
        guard let definition = await toolHost.definition(named: name) else {
            return errorResponse(id: request.id, code: -32602, message: "Tool not found: \(name)")
        }
        let inspection = AgentToolArgumentInspection(argumentsJSON: call.argumentsJSON)
        let decision = permissionEvaluator.evaluate(AgentPermissionRequest(
            toolName: name,
            permissionKey: definition.permissionKey,
            command: inspection.command ?? call.argumentsJSON,
            path: inspection.paths.first,
            risk: definition.risk
        ))
        if definition.risk != .readOnly || decision.action != .allow {
            let approval = try await toolHost.buildApprovalRequest(for: call, runID: runID, context: context)
            if let runtimeEventHandler {
                await runtimeEventHandler(.approvalRequired(approval))
            }
            return AgentMCPEnvelope(id: request.id, result: .object([
                "status": .string("approval_required"),
                "approvalRequest": try jsonValue(from: approval)
            ]))
        }

        let result = try await toolHost.invoke(call, context: context)
        let normalizedResult = AgentToolResult(
            callID: result.callID.isEmpty ? call.id : result.callID,
            toolName: result.toolName,
            succeeded: result.succeeded,
            requiresConfirmation: result.requiresConfirmation,
            message: result.message,
            modifiedPaths: result.modifiedPaths,
            errorMessage: result.errorMessage
        )
        let wireResult = AgentToolResultWireFormat(result: normalizedResult, toolCallID: call.id)
        return AgentMCPEnvelope(id: request.id, result: .object([
            "content": .array([.object(["type": .string("text"), "text": .string(wireResult.content)])]),
            "structuredContent": try jsonValue(from: wireResult),
            "annotations": try jsonValue(from: SciStationToolDefinition(definition: definition).annotations)
        ]))
    }

    private nonisolated func mcpToolValue(_ tool: SciStationToolDefinition) throws -> JSONValue {
        .object([
            "name": .string(tool.name),
            "description": .string(tool.description),
            "inputSchema": try JSONValue.parse(tool.inputSchema),
            "risk": .string(tool.risk.rawValue),
            "permissionKey": .string(tool.permissionKey),
            "source": .string(tool.source),
            "annotations": try jsonValue(from: tool.annotations)
        ])
    }

    private nonisolated func jsonValue<T: Encodable>(from value: T) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONValue.fromJSONObject(object)
    }

    private nonisolated func errorResponse(id: String, code: Int, message: String) -> AgentMCPEnvelope {
        AgentMCPEnvelope(id: id, error: AgentMCPError(code: code, message: message))
    }
}