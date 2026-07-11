import Foundation

public nonisolated enum AgentMCPClientError: LocalizedError, Sendable {
    case unsupportedTransport(String)
    case processUnavailable(String)
    case credentialUnavailable(String)
    case httpError(statusCode: Int, message: String)
    case invalidResponse(String)
    case unsupportedProtocolVersion(String)
    case toolNotFound(serverID: String, toolName: String)

    public nonisolated var errorDescription: String? {
        switch self {
        case let .unsupportedTransport(message),
             let .processUnavailable(message),
             let .credentialUnavailable(message),
             let .invalidResponse(message),
             let .unsupportedProtocolVersion(message):
            return message
        case let .httpError(statusCode, message):
            return "Remote MCP HTTP \(statusCode): \(message)"
        case let .toolNotFound(serverID, toolName):
            return "MCP tool \(toolName) is not available from server \(serverID)."
        }
    }
}

public typealias AgentMCPCredentialResolver = @Sendable (_ reference: String) async throws -> String?

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
    public var transport: MCPServerTransport
    public var endpointSummary: String
    public var state: AgentMCPRuntimeState
    public var connectionSummary: String
    public var protocolVersion: String?
    public var serverName: String?
    public var serverVersion: String?
    public var discoveredToolCount: Int
    public var errorMessage: String?
    public var stderrPreview: String?
    public var lastSuccessAt: Date?
    public var lastErrorAt: Date?
    public var exitCode: Int?
    public var retryCount: Int
    public var freshness: String
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case serverID
        case displayName
        case source
        case transport
        case endpointSummary
        case state
        case connectionSummary
        case protocolVersion
        case serverName
        case serverVersion
        case discoveredToolCount
        case errorMessage
        case stderrPreview
        case lastSuccessAt
        case lastErrorAt
        case exitCode
        case retryCount
        case freshness
        case updatedAt
    }

    public nonisolated init(
        serverID: String,
        displayName: String,
        source: AgentMCPServerSource,
        transport: MCPServerTransport,
        endpointSummary: String,
        state: AgentMCPRuntimeState,
        connectionSummary: String? = nil,
        protocolVersion: String? = nil,
        serverName: String? = nil,
        serverVersion: String? = nil,
        discoveredToolCount: Int = 0,
        errorMessage: String? = nil,
        stderrPreview: String? = nil,
        lastSuccessAt: Date? = nil,
        lastErrorAt: Date? = nil,
        exitCode: Int? = nil,
        retryCount: Int = 0,
        freshness: String = "current",
        updatedAt: Date = Date()
    ) {
        self.serverID = serverID
        self.displayName = displayName
        self.source = source
        self.transport = transport
        self.endpointSummary = endpointSummary
        self.state = state
        self.connectionSummary = connectionSummary ?? Self.defaultConnectionSummary(
            state: state,
            transport: transport,
            endpointSummary: endpointSummary,
            errorMessage: errorMessage,
            discoveredToolCount: discoveredToolCount
        )
        self.protocolVersion = protocolVersion
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.discoveredToolCount = discoveredToolCount
        self.errorMessage = errorMessage
        self.stderrPreview = stderrPreview
        self.lastSuccessAt = lastSuccessAt
        self.lastErrorAt = lastErrorAt
        self.exitCode = exitCode
        self.retryCount = retryCount
        self.freshness = freshness
        self.updatedAt = updatedAt
    }

    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let serverID = try container.decode(String.self, forKey: .serverID)
        let displayName = try container.decode(String.self, forKey: .displayName)
        let source = try container.decode(AgentMCPServerSource.self, forKey: .source)
        let transport = try container.decodeIfPresent(MCPServerTransport.self, forKey: .transport) ?? .localCommand
        let endpointSummary = try container.decodeIfPresent(String.self, forKey: .endpointSummary) ?? "endpoint not recorded"
        let state = try container.decode(AgentMCPRuntimeState.self, forKey: .state)
        let protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion)
        let serverName = try container.decodeIfPresent(String.self, forKey: .serverName)
        let serverVersion = try container.decodeIfPresent(String.self, forKey: .serverVersion)
        let discoveredToolCount = try container.decodeIfPresent(Int.self, forKey: .discoveredToolCount) ?? 0
        let errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        let stderrPreview = try container.decodeIfPresent(String.self, forKey: .stderrPreview)
        let connectionSummary = try container.decodeIfPresent(String.self, forKey: .connectionSummary)
        self.init(
            serverID: serverID,
            displayName: displayName,
            source: source,
            transport: transport,
            endpointSummary: endpointSummary,
            state: state,
            connectionSummary: connectionSummary,
            protocolVersion: protocolVersion,
            serverName: serverName,
            serverVersion: serverVersion,
            discoveredToolCount: discoveredToolCount,
            errorMessage: errorMessage,
            stderrPreview: stderrPreview,
            lastSuccessAt: try container.decodeIfPresent(Date.self, forKey: .lastSuccessAt),
            lastErrorAt: try container.decodeIfPresent(Date.self, forKey: .lastErrorAt),
            exitCode: try container.decodeIfPresent(Int.self, forKey: .exitCode),
            retryCount: try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0,
            freshness: try container.decodeIfPresent(String.self, forKey: .freshness) ?? "unknown",
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    private nonisolated static func defaultConnectionSummary(
        state: AgentMCPRuntimeState,
        transport: MCPServerTransport,
        endpointSummary: String,
        errorMessage: String?,
        discoveredToolCount: Int
    ) -> String {
        switch state {
        case .ready:
            return "\(transport.rawValue) connected to \(endpointSummary); \(discoveredToolCount) tool(s) available."
        case .unsupportedTransport:
            return "\(transport.rawValue) at \(endpointSummary) is configured but unsupported in this build."
        case .disabled:
            return "\(transport.rawValue) at \(endpointSummary) is disabled."
        case .invalidConfiguration:
            return errorMessage ?? "\(transport.rawValue) at \(endpointSummary) has invalid configuration."
        case .failed:
            if let errorMessage, !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(transport.rawValue) at \(endpointSummary) failed: \(errorMessage)"
            }
            return "\(transport.rawValue) at \(endpointSummary) failed."
        }
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
    private static let maxBackoffSeconds: TimeInterval = 60

    private struct LocalSession {
        var registration: AgentMCPConnectorRegistration
        var rootURL: URL
        var connection: SidecarConnection
        var initializeResult: AgentMCPInitializeResult
        var discoveredTools: [AgentMCPDiscoveredTool]
    }

    private struct RemoteSession {
        var registration: AgentMCPConnectorRegistration
        var rootURL: URL
        var client: RemoteMCPHTTPClient
        var initializeResult: AgentMCPInitializeResult
        var discoveredTools: [AgentMCPDiscoveredTool]
    }

    private struct RuntimeAudit {
        var lastSuccessAt: Date?
        var lastErrorAt: Date?
        var exitCode: Int?
        var retryCount: Int = 0
        var nextRetryAt: Date?
    }

    private let urlSession: URLSession
    private let credentialResolver: AgentMCPCredentialResolver?
    private var sessions: [String: LocalSession] = [:]
    private var remoteSessions: [String: RemoteSession] = [:]
    private var runtimeAudit: [String: RuntimeAudit] = [:]

    public init(
        urlSession: URLSession = .shared,
        credentialResolver: AgentMCPCredentialResolver? = nil
    ) {
        self.urlSession = urlSession
        self.credentialResolver = credentialResolver
    }

    public func prepare(
        registry: AgentMCPConnectorRegistrySnapshot,
        root: ResearchRoot
    ) async -> AgentMCPRuntimePreparation {
        let desiredLocalIDs = Set(registry.readyRegistrations.compactMap { registration in
            registration.server.transport == .localCommand ? registration.id : nil
        })
        let desiredRemoteIDs = Set(registry.readyRegistrations.compactMap { registration in
            registration.server.transport == .remoteHTTP || registration.server.transport == .remoteSSE ? registration.id : nil
        })
        for serverID in Array(sessions.keys) where !desiredLocalIDs.contains(serverID) {
            await stop(serverID: serverID)
        }
        for serverID in Array(remoteSessions.keys) where !desiredRemoteIDs.contains(serverID) {
            remoteSessions.removeValue(forKey: serverID)
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
                do {
                    let prepared = try await ensurePreparedSession(for: registration, root: root)
                    let allowedTools = prepared.discoveredTools.filter {
                        registry.authorize(serverID: registration.id, toolName: $0.name).decision.action != .deny
                    }
                    discovered.append(contentsOf: allowedTools.map { (registration, $0) })
                    statuses.append(status(
                        for: registration,
                        state: .ready,
                        initializeResult: prepared.initializeResult,
                        discoveredToolCount: allowedTools.count
                    ))
                } catch {
                    let stderr = await sessions[registration.id]?.connection.stderrText()
                    let isRemote = registration.server.transport == .remoteHTTP || registration.server.transport == .remoteSSE
                    markError(
                        serverID: registration.id,
                        exitCode: runtimeAudit[registration.id]?.exitCode,
                        usesBackoff: isRemote,
                        error: error
                    )
                    await stop(serverID: registration.id)
                    if isRemote {
                        remoteSessions.removeValue(forKey: registration.id)
                    }
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
        if let session = sessions[serverID], await session.connection.isRunning() {
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

        if let session = remoteSessions[serverID] {
            guard session.discoveredTools.contains(where: { $0.name == toolName }) else {
                throw AgentMCPClientError.toolNotFound(serverID: serverID, toolName: toolName)
            }
            do {
                let result = try await session.client.sendRequest(
                    method: "tools/call",
                    params: .object([
                        "name": .string(toolName),
                        "arguments": arguments
                    ]),
                    timeout: session.registration.server.timeoutSeconds
                )
                markSuccess(serverID: serverID)
                return try SidecarJSONCodec.decode(AgentMCPCallToolResult.self, from: result)
            } catch {
                markError(serverID: serverID, exitCode: nil, usesBackoff: true, error: error)
                remoteSessions.removeValue(forKey: serverID)
                throw error
            }
        }

        throw AgentMCPClientError.processUnavailable("MCP server \(serverID) is not running.")
    }

    public func stopAll() async {
        for serverID in Array(sessions.keys) {
            await stop(serverID: serverID)
        }
        remoteSessions.removeAll()
    }

    private func ensurePreparedSession(
        for registration: AgentMCPConnectorRegistration,
        root: ResearchRoot
    ) async throws -> (
        initializeResult: AgentMCPInitializeResult,
        discoveredTools: [AgentMCPDiscoveredTool]
    ) {
        switch registration.server.transport {
        case .localCommand:
            remoteSessions.removeValue(forKey: registration.id)
            let session = try await ensureSession(for: registration, root: root)
            return (session.initializeResult, session.discoveredTools)
        case .remoteHTTP, .remoteSSE:
            await stop(serverID: registration.id)
            let session = try await ensureRemoteSession(for: registration, root: root)
            return (session.initializeResult, session.discoveredTools)
        }
    }

    private func ensureRemoteSession(
        for registration: AgentMCPConnectorRegistration,
        root: ResearchRoot
    ) async throws -> RemoteSession {
        if let existing = remoteSessions[registration.id],
           existing.registration.server == registration.server,
           existing.rootURL.standardizedFileURL == root.rootURL.standardizedFileURL {
            do {
                _ = try await existing.client.sendRequest(
                    method: "ping",
                    params: .object([:]),
                    timeout: registration.server.timeoutSeconds
                )
                markSuccess(serverID: registration.id)
                return existing
            } catch {
                remoteSessions.removeValue(forKey: registration.id)
                markError(serverID: registration.id, exitCode: nil, usesBackoff: true, error: error)
            }
        }

        if let nextRetryAt = runtimeAudit[registration.id]?.nextRetryAt,
           nextRetryAt > Date() {
            throw AgentMCPClientError.processUnavailable("Remote MCP \(registration.id) is backing off after a failed probe; next retry after \(Self.timestamp(nextRetryAt)).")
        }

        guard let urlString = registration.server.urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw AgentMCPClientError.processUnavailable("Remote MCP server \(registration.id) has no valid HTTP/SSE URL.")
        }

        let headers = try await resolvedHeaders(for: registration.server, serverID: registration.id)
        let client = RemoteMCPHTTPClient(
            url: url,
            transport: registration.server.transport,
            headers: headers,
            session: urlSession
        )
        let initializeValue = try await client.sendRequest(
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
        try await client.sendNotification(method: "notifications/initialized", timeout: registration.server.timeoutSeconds)
        let discoveredTools = try await listAllTools(
            client: client,
            timeout: registration.server.timeoutSeconds
        )
        let session = RemoteSession(
            registration: registration,
            rootURL: root.rootURL,
            client: client,
            initializeResult: initializeResult,
            discoveredTools: discoveredTools
        )
        remoteSessions[registration.id] = session
        markSuccess(serverID: registration.id)
        return session
    }

    private func resolvedHeaders(
        for server: MCPServerConfiguration,
        serverID: String
    ) async throws -> [String: String] {
        var headers: [String: String] = [
            "Accept": server.transport == .remoteSSE
                ? "text/event-stream, application/json"
                : "application/json, text/event-stream",
            "Content-Type": "application/json"
        ]

        for header in server.headerReferences {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  name.rangeOfCharacter(from: CharacterSet(charactersIn: ":\r\n")) == nil else {
                throw AgentMCPClientError.credentialUnavailable("Remote MCP server \(serverID) has an invalid header reference name.")
            }
            headers[name] = try await resolveCredentialReference(header.valueReference, serverID: serverID)
        }

        for reference in server.secretReferences {
            _ = try await resolveCredentialReference(reference, serverID: serverID)
        }

        return headers
    }

    private func resolveCredentialReference(
        _ reference: String,
        serverID: String
    ) async throws -> String {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let credentialResolver {
            let resolved = try await credentialResolver(trimmed)
            if let value = resolved?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                return value
            }
        }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("env:") || lowercased.hasPrefix("environment:") {
            let key = String(trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().joined(separator: ":"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                return value
            }
            throw AgentMCPClientError.credentialUnavailable("Remote MCP server \(serverID) could not resolve environment credential reference \(redactedCredentialReference(trimmed)).")
        }

        if lowercased.hasPrefix("keychain:") {
            throw AgentMCPClientError.credentialUnavailable("Remote MCP server \(serverID) could not resolve Keychain credential reference \(redactedCredentialReference(trimmed)); provide a host credential resolver before enabling this connector.")
        }

        throw AgentMCPClientError.credentialUnavailable("Remote MCP server \(serverID) uses an unsupported credential reference \(redactedCredentialReference(trimmed)).")
    }

    private nonisolated func redactedCredentialReference(_ reference: String) -> String {
        let prefix = reference.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "credential"
        return "\(prefix):[redacted]"
    }

    private func ensureSession(
        for registration: AgentMCPConnectorRegistration,
        root: ResearchRoot
    ) async throws -> LocalSession {
        if let existing = sessions[registration.id],
           existing.registration.server == registration.server,
           existing.rootURL.standardizedFileURL == root.rootURL.standardizedFileURL,
           await existing.connection.isRunning() {
            markSuccess(serverID: registration.id)
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
        process.terminationHandler = { [weak self, weak connection] process in
            guard let connection else { return }
            Task {
                await connection.processTerminated(exitCode: process.terminationStatus)
                await self?.recordExit(serverID: registration.id, exitCode: process.terminationStatus)
            }
        }
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
            let session = LocalSession(
                registration: registration,
                rootURL: root.rootURL,
                connection: connection,
                initializeResult: initializeResult,
                discoveredTools: discoveredTools
            )
            sessions[registration.id] = session
            markSuccess(serverID: registration.id)
            return session
        } catch {
            if !process.isRunning {
                recordExit(serverID: registration.id, exitCode: process.terminationStatus)
            }
            await connection.stop()
            recordExit(serverID: registration.id, exitCode: process.terminationStatus)
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

    private func listAllTools(
        client: RemoteMCPHTTPClient,
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
            let value = try await client.sendRequest(
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

    private func recordExit(serverID: String, exitCode: Int32) {
        var audit = runtimeAudit[serverID] ?? RuntimeAudit()
        audit.exitCode = Int(exitCode)
        if exitCode != 0 {
            audit.lastErrorAt = Date()
        }
        runtimeAudit[serverID] = audit
    }

    private func markSuccess(serverID: String) {
        var audit = runtimeAudit[serverID] ?? RuntimeAudit()
        audit.lastSuccessAt = Date()
        audit.exitCode = nil
        audit.nextRetryAt = nil
        runtimeAudit[serverID] = audit
    }

    private func markError(
        serverID: String,
        exitCode: Int?,
        usesBackoff: Bool = false,
        error: Error? = nil
    ) {
        var audit = runtimeAudit[serverID] ?? RuntimeAudit()
        let now = Date()
        audit.lastErrorAt = now
        audit.exitCode = exitCode ?? audit.exitCode
        audit.retryCount += 1
        if usesBackoff, !isCredentialError(error) {
            let exponent = min(audit.retryCount, 6)
            let seconds = min(pow(2.0, Double(exponent)), Self.maxBackoffSeconds)
            audit.nextRetryAt = now.addingTimeInterval(seconds)
        }
        runtimeAudit[serverID] = audit
    }

    private nonisolated func isCredentialError(_ error: Error?) -> Bool {
        guard let error = error as? AgentMCPClientError else { return false }
        if case .credentialUnavailable = error {
            return true
        }
        return false
    }

    private func status(
        for registration: AgentMCPConnectorRegistration,
        state: AgentMCPRuntimeState,
        initializeResult: AgentMCPInitializeResult? = nil,
        discoveredToolCount: Int = 0,
        errorMessage: String? = nil,
        stderrPreview: String? = nil
    ) -> AgentMCPRuntimeStatus {
        let audit = runtimeAudit[registration.id]
        let updatedAt = Date()
        return AgentMCPRuntimeStatus(
            serverID: registration.id,
            displayName: registration.server.displayName,
            source: registration.source,
            transport: registration.server.transport,
            endpointSummary: endpointSummary(for: registration.server),
            state: state,
            connectionSummary: connectionSummary(
                for: registration,
                state: state,
                discoveredToolCount: discoveredToolCount,
                errorMessage: errorMessage,
                audit: audit,
                updatedAt: updatedAt
            ),
            protocolVersion: initializeResult?.protocolVersion,
            serverName: initializeResult?.serverInfo.name,
            serverVersion: initializeResult?.serverInfo.version,
            discoveredToolCount: discoveredToolCount,
            errorMessage: errorMessage,
            stderrPreview: stderrPreview,
            lastSuccessAt: state == .ready ? audit?.lastSuccessAt ?? updatedAt : audit?.lastSuccessAt,
            lastErrorAt: errorMessage == nil ? audit?.lastErrorAt : audit?.lastErrorAt ?? updatedAt,
            exitCode: audit?.exitCode,
            retryCount: audit?.retryCount ?? 0,
            freshness: freshness(audit: audit, updatedAt: updatedAt),
            updatedAt: updatedAt
        )
    }

    private nonisolated func connectionSummary(
        for registration: AgentMCPConnectorRegistration,
        state: AgentMCPRuntimeState,
        discoveredToolCount: Int,
        errorMessage: String?,
        audit: RuntimeAudit?,
        updatedAt: Date
    ) -> String {
        if let nextRetryAt = audit?.nextRetryAt, nextRetryAt > updatedAt {
            return "\(registration.server.transport.rawValue) at \(endpointSummary(for: registration.server)) is backing off until \(Self.timestamp(nextRetryAt)); retry_count=\(audit?.retryCount ?? 0)."
        }
        let base = AgentMCPRuntimeStatus(
            serverID: registration.id,
            displayName: registration.server.displayName,
            source: registration.source,
            transport: registration.server.transport,
            endpointSummary: endpointSummary(for: registration.server),
            state: state,
            discoveredToolCount: discoveredToolCount,
            errorMessage: errorMessage
        ).connectionSummary
        guard let audit, audit.retryCount > 0 else {
            return base
        }
        return "\(base) retry_count=\(audit.retryCount)."
    }

    private nonisolated func freshness(audit: RuntimeAudit?, updatedAt: Date) -> String {
        guard let nextRetryAt = audit?.nextRetryAt, nextRetryAt > updatedAt else {
            return "current"
        }
        return "backoff_until:\(Self.timestamp(nextRetryAt))"
    }

    private nonisolated static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private nonisolated func endpointSummary(for server: MCPServerConfiguration) -> String {
        switch server.transport {
        case .localCommand:
            return ([server.command].compactMap { $0 } + server.arguments)
                .joined(separator: " ")
                .nilIfEmpty ?? "local command not configured"
        case .remoteHTTP, .remoteSSE:
            return server.urlString?.nilIfEmpty ?? "remote URL not configured"
        }
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

private final class RemoteMCPHTTPClient: @unchecked Sendable {
    private let url: URL
    private let transport: MCPServerTransport
    private let headers: [String: String]
    private let session: URLSession

    nonisolated init(
        url: URL,
        transport: MCPServerTransport,
        headers: [String: String],
        session: URLSession
    ) {
        self.url = url
        self.transport = transport
        self.headers = headers
        self.session = session
    }

    func sendRequest(method: String, params: JSONValue? = nil, timeout: TimeInterval) async throws -> JSONValue {
        let id = "swift-remote-\(UUID().uuidString.lowercased())"
        let message = SidecarJSONRPCMessage(id: id, method: method, params: params)
        let response = try await send(message: message, timeout: timeout, expectsResponse: true)
        return response ?? .object([:])
    }

    func sendNotification(method: String, params: JSONValue? = nil, timeout: TimeInterval) async throws {
        let message = SidecarJSONRPCMessage(method: method, params: params)
        _ = try await send(message: message, timeout: timeout, expectsResponse: false)
    }

    private func send(
        message: SidecarJSONRPCMessage,
        timeout: TimeInterval,
        expectsResponse: Bool
    ) async throws -> JSONValue? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if transport == .remoteSSE {
            request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        }
        request.httpBody = try SidecarJSONCodec.encoder.encode(message)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentMCPClientError.invalidResponse("Remote MCP endpoint did not return an HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AgentMCPClientError.httpError(
                statusCode: httpResponse.statusCode,
                message: clipped(String(data: data, encoding: .utf8)) ?? "empty response"
            )
        }
        guard expectsResponse else {
            return nil
        }
        let decodedData = try responsePayloadData(from: data, contentType: httpResponse.value(forHTTPHeaderField: "Content-Type"))
        let responseMessage = try decodeMessage(from: decodedData)
        if let error = responseMessage.error {
            throw error
        }
        return responseMessage.result ?? .object([:])
    }

    private func responsePayloadData(from data: Data, contentType: String?) throws -> Data {
        guard !data.isEmpty else {
            throw AgentMCPClientError.invalidResponse("Remote MCP response was empty.")
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if contentType?.lowercased().contains("text/event-stream") == true
            || trimmedBody.hasPrefix("data:")
            || trimmedBody.hasPrefix("event:") {
            return try ssePayloadData(from: body)
        }
        return data
    }

    private func ssePayloadData(from body: String) throws -> Data {
        let events = body.components(separatedBy: "\n\n")
        for event in events {
            let payload = event
                .split(separator: "\n", omittingEmptySubsequences: false)
                .compactMap { line -> String? in
                    let trimmed = String(line)
                    guard trimmed.hasPrefix("data:") else { return nil }
                    return String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty, payload != "[DONE]" else {
                continue
            }
            if let data = payload.data(using: .utf8) {
                return data
            }
        }
        throw AgentMCPClientError.invalidResponse("Remote MCP SSE response did not include a JSON data event.")
    }

    private func decodeMessage(from data: Data) throws -> SidecarJSONRPCMessage {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let dictionary = object as? [String: Any] else {
            throw AgentMCPClientError.invalidResponse("Remote MCP JSON-RPC response must be an object.")
        }
        let error: SidecarJSONRPCError?
        if let errorObject = dictionary["error"] as? [String: Any] {
            let code = (errorObject["code"] as? NSNumber)?.intValue ?? -32603
            let message = errorObject["message"] as? String ?? "Remote MCP request failed."
            error = SidecarJSONRPCError(code: code, message: message)
        } else {
            error = nil
        }
        return try SidecarJSONRPCMessage(
            jsonrpc: dictionary["jsonrpc"] as? String ?? "2.0",
            id: dictionary["id"].flatMap { value in
                if value is NSNull { return nil }
                if let string = value as? String { return string }
                if let number = value as? NSNumber { return number.stringValue }
                return nil
            },
            method: dictionary["method"] as? String,
            params: dictionary["params"].map(JSONValue.fromJSONObject),
            result: dictionary["result"].map(JSONValue.fromJSONObject),
            error: error
        )
    }

    private func clipped(_ value: String?, maxCharacters: Int = 2_000) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.count > maxCharacters ? String(value.prefix(maxCharacters)) + "..." : value
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
