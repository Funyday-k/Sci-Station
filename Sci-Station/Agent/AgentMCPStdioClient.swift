import Foundation

public nonisolated enum AgentMCPClientError: LocalizedError, Sendable {
    case unsupportedTransport(String)
    case processUnavailable(String)
    case invalidResponse(String)
    case unsupportedProtocolVersion(String)
    case toolNotFound(serverID: String, toolName: String)

    public nonisolated var errorDescription: String? {
        switch self {
        case let .unsupportedTransport(message),
             let .processUnavailable(message),
             let .invalidResponse(message),
             let .unsupportedProtocolVersion(message):
            return message
        case let .toolNotFound(serverID, toolName):
            return "MCP tool \(toolName) is not available from server \(serverID)."
        }
    }
}

public nonisolated struct AgentMCPImplementationInfo: Codable, Hashable, Sendable {
    public var name: String
    public var version: String
    public var title: String?

    public nonisolated init(name: String, version: String, title: String? = nil) {
        self.name = name
        self.version = version
        self.title = title
    }
}

public nonisolated struct AgentMCPInitializeResult: Codable, Hashable, Sendable {
    public var protocolVersion: String
    public var capabilities: JSONValue
    public var serverInfo: AgentMCPImplementationInfo
    public var instructions: String?

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case capabilities
        case serverInfo
        case instructions
    }
}

public nonisolated struct AgentMCPToolAnnotationsWire: Codable, Hashable, Sendable {
    public var title: String?
    public var readOnlyHint: Bool?
    public var destructiveHint: Bool?
    public var idempotentHint: Bool?
    public var openWorldHint: Bool?

    public nonisolated init(
        title: String? = nil,
        readOnlyHint: Bool? = nil,
        destructiveHint: Bool? = nil,
        idempotentHint: Bool? = nil,
        openWorldHint: Bool? = nil
    ) {
        self.title = title
        self.readOnlyHint = readOnlyHint
        self.destructiveHint = destructiveHint
        self.idempotentHint = idempotentHint
        self.openWorldHint = openWorldHint
    }
}

public nonisolated struct AgentMCPDiscoveredTool: Codable, Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var title: String?
    public var description: String?
    public var inputSchema: JSONValue
    public var annotations: AgentMCPToolAnnotationsWire?

    private enum CodingKeys: String, CodingKey {
        case name
        case title
        case description
        case inputSchema
        case annotations
    }
}

public nonisolated struct AgentMCPListToolsResult: Codable, Hashable, Sendable {
    public var tools: [AgentMCPDiscoveredTool]
    public var nextCursor: String?
}

public nonisolated struct AgentMCPCallToolResult: Codable, Hashable, Sendable {
    public var content: [JSONValue]
    public var structuredContent: JSONValue?
    public var isError: Bool?

    public nonisolated init(
        content: [JSONValue] = [],
        structuredContent: JSONValue? = nil,
        isError: Bool? = nil
    ) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }
}

public nonisolated enum AgentMCPRuntimeState: String, Codable, Sendable {
    case disabled
    case unsupportedTransport = "unsupported_transport"
    case invalidConfiguration = "invalid_configuration"
    case ready
    case failed
}

public nonisolated struct AgentMCPRuntimeStatus: Codable, Hashable, Sendable, Identifiable {
    public var id: String { serverID }
    public var serverID: String
    public var displayName: String
    public var source: AgentMCPServerSource
    public var state: AgentMCPRuntimeState
    public var protocolVersion: String?
    public var serverName: String?
    public var serverVersion: String?
    public var discoveredToolCount: Int
    public var errorMessage: String?
    public var stderrPreview: String?

    public nonisolated init(
        serverID: String,
        displayName: String,
        source: AgentMCPServerSource,
        state: AgentMCPRuntimeState,
        protocolVersion: String? = nil,
        serverName: String? = nil,
        serverVersion: String? = nil,
        discoveredToolCount: Int = 0,
        errorMessage: String? = nil,
        stderrPreview: String? = nil
    ) {
        self.serverID = serverID
        self.displayName = displayName
        self.source = source
        self.state = state
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.discoveredToolCount = discoveredToolCount
        self.errorMessage = errorMessage
        self.stderrPreview = stderrPreview
    }
}

public nonisolated struct AgentMCPRuntimePreparation: Sendable {
    public var tools: [AgentMCPExternalTool]
    public var statuses: [AgentMCPRuntimeStatus]

    public nonisolated init(
        tools: [AgentMCPExternalTool] = [],
        statuses: [AgentMCPRuntimeStatus] = []
    ) {
        self.tools = tools
        self.statuses = statuses
    }
}

public nonisolated struct AgentMCPExternalTool: AgentTool {
    public let definition: AgentToolDefinition
    public let serverID: String
    public let remoteToolName: String
    private let connectorManager: AgentMCPConnectorManager

    public nonisolated init(
        exposedName: String,
        registration: AgentMCPConnectorRegistration,
        discoveredTool: AgentMCPDiscoveredTool,
        connectorManager: AgentMCPConnectorManager
    ) {
        self.serverID = registration.server.id
        self.remoteToolName = discoveredTool.name
        self.connectorManager = connectorManager
        self.definition = AgentToolDefinition(
            identifier: "mcp:\(registration.server.id):\(discoveredTool.name)",
            name: exposedName,
            displayName: discoveredTool.title
                ?? discoveredTool.annotations?.title
                ?? discoveredTool.name,
            summary: "[MCP \(registration.server.displayName)] \(discoveredTool.description ?? "External MCP tool.")",
            inputSchema: Self.normalizedInputSchema(discoveredTool.inputSchema),
            risk: .externalSideEffect,
            requiresConfirmation: true,
            permissionKey: "mcp.external.\(registration.server.id).\(discoveredTool.name)",
            outputPolicy: AgentToolOutputPolicy(maxCharacters: 16_000),
            source: "mcp:\(registration.server.id)"
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let arguments = try AgentToolArguments(rawJSON: argumentsJSON)
        let result = try await connectorManager.callTool(
            serverID: serverID,
            toolName: remoteToolName,
            arguments: arguments.value
        )
        let isError = result.isError == true
        let message = Self.userVisibleText(from: result)
        let payload = JSONValue.object([
            "schema_version": .number("1"),
            "kind": .string("mcp_tool_result"),
            "server_id": .string(serverID),
            "remote_tool_name": .string(remoteToolName),
            "structured_content": result.structuredContent ?? .null,
            "content": .array(result.content),
            "is_error": .bool(isError)
        ])
        return AgentToolResult(
            callID: "",
            toolName: definition.name,
            succeeded: !isError,
            message: message,
            payload: payload,
            errorMessage: isError ? message : nil
        )
    }

    private nonisolated static func normalizedInputSchema(_ schema: JSONValue) -> String {
        guard case .object = schema else {
            return #"{"type":"object","properties":{}}"#
        }
        return schema.canonicalJSON
    }

    private nonisolated static func userVisibleText(from result: AgentMCPCallToolResult) -> String {
        let text = result.content.compactMap { block -> String? in
            guard let object = block.objectValue,
                  object["type"]?.stringValue == "text" else {
                return nil
            }
            return object["text"]?.stringValue
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        if !text.isEmpty {
            return text.count > 16_000 ? String(text.prefix(16_000)) + "\n[MCP output truncated]" : text
        }
        if let structuredContent = result.structuredContent {
            let rendered = structuredContent.canonicalJSON
            return rendered.count > 16_000 ? String(rendered.prefix(16_000)) + "\n[MCP output truncated]" : rendered
        }
        return result.isError == true
            ? "The MCP server reported a tool error."
            : "The MCP tool completed without text output."
    }
}

public actor AgentMCPConnectorManager {
    public static let protocolVersion = "2025-06-18"
    private static let supportedProtocolVersions = Set(["2025-06-18", "2025-03-26", "2024-11-05"])

    private struct Session {
        var registration: AgentMCPConnectorRegistration
        var rootURL: URL
        var connection: SidecarConnection
        var initializeResult: AgentMCPInitializeResult
        var discoveredTools: [AgentMCPDiscoveredTool]
    }

    private var sessions: [String: Session] = [:]

    public init() {}

    public func prepare(
        registry: AgentMCPConnectorRegistrySnapshot,
        root: ResearchRoot
    ) async -> AgentMCPRuntimePreparation {
        let desiredLocalIDs = Set(registry.readyRegistrations.compactMap { registration in
            registration.server.transport == .localCommand ? registration.id : nil
        })
        for serverID in sessions.keys where !desiredLocalIDs.contains(serverID) {
            await stop(serverID: serverID)
        }

        var statuses: [AgentMCPRuntimeStatus] = []
        var discovered: [(AgentMCPConnectorRegistration, AgentMCPDiscoveredTool)] = []

        for registration in registry.registrations {
            switch registration.state {
            case .disabled:
                statuses.append(status(for: registration, state: .disabled))
            case .invalidConfiguration, .unresolvedCredentialReference:
                statuses.append(status(
                    for: registration,
                    state: .invalidConfiguration,
                    errorMessage: registration.issues.map(\.message).joined(separator: " ")
                ))
            case .readyForDiscovery:
                guard registration.server.transport == .localCommand else {
                    statuses.append(status(
                        for: registration,
                        state: .unsupportedTransport,
                        errorMessage: "Remote MCP transport is not enabled in this build."
                    ))
                    continue
                }

                do {
                    let session = try await ensureSession(for: registration, root: root)
                    let allowedTools = session.discoveredTools.filter {
                        registry.authorize(serverID: registration.id, toolName: $0.name).decision.action != .deny
                    }
                    discovered.append(contentsOf: allowedTools.map { (registration, $0) })
                    statuses.append(status(
                        for: registration,
                        state: .ready,
                        initializeResult: session.initializeResult,
                        discoveredToolCount: allowedTools.count
                    ))
                } catch {
                    let stderr = await sessions[registration.id]?.connection.stderrText()
                    await stop(serverID: registration.id)
                    statuses.append(status(
                        for: registration,
                        state: .failed,
                        errorMessage: error.localizedDescription,
                        stderrPreview: clipped(stderr)
                    ))
                }
            }
        }

        var usedNames: Set<String> = []
        let tools = discovered.map { registration, remoteTool -> AgentMCPExternalTool in
            let baseName = exposedToolName(serverID: registration.id, toolName: remoteTool.name)
            let exposedName: String
            if usedNames.insert(baseName).inserted {
                exposedName = baseName
            } else {
                let suffix = AgentToolCallFingerprint.stableHash("\(registration.id):\(remoteTool.name)").prefix(8)
                exposedName = "\(baseName)_\(suffix)"
                usedNames.insert(exposedName)
            }
            return AgentMCPExternalTool(
                exposedName: exposedName,
                registration: registration,
                discoveredTool: remoteTool,
                connectorManager: self
            )
        }

        return AgentMCPRuntimePreparation(
            tools: tools.sorted { $0.definition.name.localizedStandardCompare($1.definition.name) == .orderedAscending },
            statuses: statuses.sorted { $0.serverID.localizedStandardCompare($1.serverID) == .orderedAscending }
        )
    }

    public func callTool(
        serverID: String,
        toolName: String,
        arguments: JSONValue
    ) async throws -> AgentMCPCallToolResult {
        guard let session = sessions[serverID],
              await session.connection.isRunning() else {
            throw AgentMCPClientError.processUnavailable("MCP server \(serverID) is not running.")
        }
        guard session.discoveredTools.contains(where: { $0.name == toolName }) else {
            throw AgentMCPClientError.toolNotFound(serverID: serverID, toolName: toolName)
        }
        let result = try await session.connection.sendRequest(
            method: "tools/call",
            params: .object([
                "name": .string(toolName),
                "arguments": arguments
            ]),
            timeout: session.registration.server.timeoutSeconds
        )
        return try SidecarJSONCodec.decode(AgentMCPCallToolResult.self, from: result)
    }

    public func stopAll() async {
        for serverID in Array(sessions.keys) {
            await stop(serverID: serverID)
        }
    }

    private func ensureSession(
        for registration: AgentMCPConnectorRegistration,
        root: ResearchRoot
    ) async throws -> Session {
        if let existing = sessions[registration.id],
           existing.registration.server == registration.server,
           existing.rootURL.standardizedFileURL == root.rootURL.standardizedFileURL,
           await existing.connection.isRunning() {
            return existing
        }
        await stop(serverID: registration.id)

        guard let command = registration.server.command?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else {
            throw AgentMCPClientError.processUnavailable("Local MCP server \(registration.id) has no command.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [expand(command, root: root)] + registration.server.arguments.map { expand($0, root: root) }
        process.currentDirectoryURL = root.rootURL
        var environment = ProcessInfo.processInfo.environment
        environment["SCI_STATION_WORKSPACE_ROOT"] = root.rootURL.path
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let connection = SidecarConnection(
            process: process,
            inputHandle: inputPipe.fileHandleForWriting,
            outputHandle: outputPipe.fileHandleForReading,
            errorHandle: errorPipe.fileHandleForReading
        )
        do {
            try process.run()
            await connection.startReading()
            let initializeValue = try await connection.sendRequest(
                method: "initialize",
                params: .object([
                    "protocolVersion": .string(Self.protocolVersion),
                    "capabilities": .object([:]),
                    "clientInfo": .object([
                        "name": .string("Sci-Station"),
                        "title": .string("Sci-Station"),
                        "version": .string("0.x")
                    ])
                ]),
                timeout: registration.server.timeoutSeconds
            )
            let initializeResult = try SidecarJSONCodec.decode(AgentMCPInitializeResult.self, from: initializeValue)
            guard Self.supportedProtocolVersions.contains(initializeResult.protocolVersion) else {
                throw AgentMCPClientError.unsupportedProtocolVersion(
                    "MCP server \(registration.id) selected unsupported protocol version \(initializeResult.protocolVersion)."
                )
            }
            try await connection.sendNotification(method: "notifications/initialized")
            let discoveredTools = try await listAllTools(
                connection: connection,
                timeout: registration.server.timeoutSeconds
            )
            let session = Session(
                registration: registration,
                rootURL: root.rootURL,
                connection: connection,
                initializeResult: initializeResult,
                discoveredTools: discoveredTools
            )
            sessions[registration.id] = session
            return session
        } catch {
            await connection.stop()
            let stderr = await connection.stderrText()
            if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw AgentMCPClientError.processUnavailable(
                    "\(error.localizedDescription) MCP stderr: \(clipped(stderr) ?? "")"
                )
            }
            throw error
        }
    }

    private func listAllTools(
        connection: SidecarConnection,
        timeout: TimeInterval
    ) async throws -> [AgentMCPDiscoveredTool] {
        var tools: [AgentMCPDiscoveredTool] = []
        var cursor: String?
        var seenCursors: Set<String> = []

        for _ in 0..<50 {
            var params: [String: JSONValue] = [:]
            if let cursor {
                params["cursor"] = .string(cursor)
            }
            let value = try await connection.sendRequest(
                method: "tools/list",
                params: .object(params),
                timeout: timeout
            )
            let result = try SidecarJSONCodec.decode(AgentMCPListToolsResult.self, from: value)
            tools.append(contentsOf: result.tools)
            guard let nextCursor = result.nextCursor?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !nextCursor.isEmpty else {
                return deduplicatedTools(tools)
            }
            guard seenCursors.insert(nextCursor).inserted else {
                throw AgentMCPClientError.invalidResponse("MCP tools/list repeated cursor \(nextCursor).")
            }
            cursor = nextCursor
        }
        throw AgentMCPClientError.invalidResponse("MCP tools/list exceeded the pagination limit.")
    }

    private func deduplicatedTools(_ tools: [AgentMCPDiscoveredTool]) -> [AgentMCPDiscoveredTool] {
        var byName: [String: AgentMCPDiscoveredTool] = [:]
        for tool in tools where !tool.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            byName[tool.name] = tool
        }
        return byName.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func stop(serverID: String) async {
        guard let session = sessions.removeValue(forKey: serverID) else {
            return
        }
        await session.connection.stop()
    }

    private nonisolated func status(
        for registration: AgentMCPConnectorRegistration,
        state: AgentMCPRuntimeState,
        initializeResult: AgentMCPInitializeResult? = nil,
        discoveredToolCount: Int = 0,
        errorMessage: String? = nil,
        stderrPreview: String? = nil
    ) -> AgentMCPRuntimeStatus {
        AgentMCPRuntimeStatus(
            serverID: registration.id,
            displayName: registration.server.displayName,
            source: registration.source,
            state: state,
            protocolVersion: initializeResult?.protocolVersion,
            serverName: initializeResult?.serverInfo.name,
            serverVersion: initializeResult?.serverInfo.version,
            discoveredToolCount: discoveredToolCount,
            errorMessage: errorMessage,
            stderrPreview: stderrPreview
        )
    }

    private nonisolated func expand(_ value: String, root: ResearchRoot) -> String {
        value
            .replacingOccurrences(of: "${workspaceRoot}", with: root.rootURL.path)
            .replacingOccurrences(of: "$WORKSPACE_ROOT", with: root.rootURL.path)
    }

    private nonisolated func exposedToolName(serverID: String, toolName: String) -> String {
        "mcp__\(sanitizedIdentifier(serverID))__\(sanitizedIdentifier(toolName))"
    }

    private nonisolated func sanitizedIdentifier(_ value: String) -> String {
        let mapped = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "_"
        }
        let collapsed = String(mapped)
            .replacingOccurrences(of: #"_+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return collapsed.isEmpty ? "tool" : collapsed
    }

    private nonisolated func clipped(_ value: String?, maxCharacters: Int = 2_000) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.count > maxCharacters ? String(value.prefix(maxCharacters)) + "..." : value
    }
}
