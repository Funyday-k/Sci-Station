import Foundation

public nonisolated struct AgentMCPConnectorCandidate: Hashable, Sendable {
    public var server: MCPServerConfiguration
    public var source: AgentMCPServerSource

    public nonisolated init(server: MCPServerConfiguration, source: AgentMCPServerSource) {
        self.server = server
        self.source = source
    }
}

public nonisolated enum AgentMCPConnectorState: String, Codable, Sendable {
    case disabled
    case readyForDiscovery = "ready_for_discovery"
    case invalidConfiguration = "invalid_configuration"
    case unresolvedCredentialReference = "unresolved_credential_reference"
}

public nonisolated struct AgentMCPConnectorRegistration: Hashable, Sendable, Identifiable {
    public var id: String { server.id }
    public var server: MCPServerConfiguration
    public var source: AgentMCPServerSource
    public var state: AgentMCPConnectorState
    public var issues: [AgentPluginValidationIssue]

    public nonisolated init(
        server: MCPServerConfiguration,
        source: AgentMCPServerSource,
        state: AgentMCPConnectorState,
        issues: [AgentPluginValidationIssue] = []
    ) {
        self.server = server
        self.source = source
        self.state = state
        self.issues = issues
    }
}

public nonisolated struct AgentMCPToolAuthorization: Hashable, Sendable {
    public var serverID: String
    public var toolName: String
    public var decision: AgentPermissionDecision

    public nonisolated init(serverID: String, toolName: String, decision: AgentPermissionDecision) {
        self.serverID = serverID
        self.toolName = toolName
        self.decision = decision
    }
}

public nonisolated struct AgentMCPConnectorRegistrySnapshot: Hashable, Sendable {
    public var registrations: [AgentMCPConnectorRegistration]

    public nonisolated init(registrations: [AgentMCPConnectorRegistration] = []) {
        self.registrations = registrations
    }

    public nonisolated var readyRegistrations: [AgentMCPConnectorRegistration] {
        registrations.filter { $0.state == .readyForDiscovery }
    }

    public nonisolated func registration(id: String) -> AgentMCPConnectorRegistration? {
        registrations.first { $0.id == id }
    }

    public nonisolated func authorize(serverID: String, toolName: String) -> AgentMCPToolAuthorization {
        guard let registration = registration(id: serverID) else {
            return denied(serverID: serverID, toolName: toolName, message: "MCP server is not registered.")
        }
        guard registration.state == .readyForDiscovery else {
            return denied(
                serverID: serverID,
                toolName: toolName,
                message: "MCP server is not ready: \(registration.state.rawValue)."
            )
        }

        let allowedTools = Set(registration.server.allowedTools)
        if !allowedTools.isEmpty && !allowedTools.contains(toolName) {
            return denied(serverID: serverID, toolName: toolName, message: "MCP tool is outside the server allowlist.")
        }

        return AgentMCPToolAuthorization(
            serverID: serverID,
            toolName: toolName,
            decision: AgentPermissionDecision(
                action: .ask,
                ruleID: "ask-external-mcp",
                scope: .once,
                message: "External MCP startup, network access, and tool calls require explicit approval."
            )
        )
    }

    private nonisolated func denied(serverID: String, toolName: String, message: String) -> AgentMCPToolAuthorization {
        AgentMCPToolAuthorization(
            serverID: serverID,
            toolName: toolName,
            decision: AgentPermissionDecision(
                action: .deny,
                ruleID: "deny-unavailable-mcp",
                scope: .once,
                message: message
            )
        )
    }
}

public nonisolated struct AgentMCPConnectorRegistryResolver: Sendable {
    public nonisolated init() {}

    public nonisolated func resolve(candidates: [AgentMCPConnectorCandidate]) -> AgentMCPConnectorRegistrySnapshot {
        var selectedByID: [String: AgentMCPConnectorCandidate] = [:]
        for candidate in candidates.sorted(by: sourcePrecedence) {
            selectedByID[candidate.server.id] = candidate
        }

        let registrations = selectedByID.values
            .map(registration)
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        return AgentMCPConnectorRegistrySnapshot(registrations: registrations)
    }

    public nonisolated func resolve(
        productServers: [MCPServerConfiguration] = [],
        profileServers: [MCPServerConfiguration] = [],
        localServers: [MCPServerConfiguration] = []
    ) -> AgentMCPConnectorRegistrySnapshot {
        resolve(candidates:
            productServers.map { AgentMCPConnectorCandidate(server: $0, source: .trackedProductTemplate) }
            + localServers.map { AgentMCPConnectorCandidate(server: $0, source: .localWorkspaceConfig) }
            + profileServers.map { AgentMCPConnectorCandidate(server: $0, source: .workspaceProfile) }
        )
    }

    private nonisolated func registration(_ candidate: AgentMCPConnectorCandidate) -> AgentMCPConnectorRegistration {
        let server = candidate.server
        let issues = validationIssues(for: server)
        let state: AgentMCPConnectorState
        if !server.isEnabled {
            state = .disabled
        } else if issues.contains(where: { $0.field.contains("credential") }) {
            state = .unresolvedCredentialReference
        } else if !issues.isEmpty {
            state = .invalidConfiguration
        } else {
            state = .readyForDiscovery
        }
        return AgentMCPConnectorRegistration(
            server: server,
            source: candidate.source,
            state: state,
            issues: issues
        )
    }

    private nonisolated func validationIssues(for server: MCPServerConfiguration) -> [AgentPluginValidationIssue] {
        let manifest = AgentPluginManifest(
            id: "mcp-registry-validation",
            name: "MCP Registry Validation",
            description: "Validates one MCP connector registration.",
            mcpServers: [server]
        )
        var issues = AgentPluginValidator().validate(manifest).filter { $0.field.hasPrefix("mcp_servers.") }

        for reference in server.secretReferences where !isSupportedCredentialReference(reference) {
            issues.append(AgentPluginValidationIssue(
                field: "mcp_servers.\(server.id).credential_reference",
                message: "Credential references must use keychain:, env:, or environment: prefixes."
            ))
        }
        for header in server.headerReferences where !isSupportedCredentialReference(header.valueReference) {
            issues.append(AgentPluginValidationIssue(
                field: "mcp_servers.\(server.id).credential_reference",
                message: "Header values must use keychain:, env:, or environment: references."
            ))
        }
        return issues
    }

    private nonisolated func isSupportedCredentialReference(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("keychain:")
            || normalized.hasPrefix("env:")
            || normalized.hasPrefix("environment:")
    }

    private nonisolated func sourcePrecedence(
        _ lhs: AgentMCPConnectorCandidate,
        _ rhs: AgentMCPConnectorCandidate
    ) -> Bool {
        let lhsPriority = sourcePriority(lhs.source)
        let rhsPriority = sourcePriority(rhs.source)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        if lhs.server.id != rhs.server.id {
            return lhs.server.id.localizedStandardCompare(rhs.server.id) == .orderedAscending
        }
        return lhs.server.displayName.localizedStandardCompare(rhs.server.displayName) == .orderedAscending
    }

    private nonisolated func sourcePriority(_ source: AgentMCPServerSource) -> Int {
        switch source {
        case .trackedProductTemplate:
            return 0
        case .localWorkspaceConfig:
            return 1
        case .workspaceProfile:
            return 2
        }
    }
}
