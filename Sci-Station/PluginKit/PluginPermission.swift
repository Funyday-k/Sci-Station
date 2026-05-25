import Foundation

public nonisolated struct PluginPermissionSet: Codable, Hashable, Sendable {
    public var readPaths: [String]
    public var writePaths: [String]
    public var networkHosts: [String]
    public var secrets: [String]
    public var allowsLLM: Bool
    public var allowsProcessExecution: Bool

    public nonisolated init(
        readPaths: [String] = [],
        writePaths: [String] = [],
        networkHosts: [String] = [],
        secrets: [String] = [],
        allowsLLM: Bool = false,
        allowsProcessExecution: Bool = false
    ) {
        self.readPaths = readPaths
        self.writePaths = writePaths
        self.networkHosts = networkHosts
        self.secrets = secrets
        self.allowsLLM = allowsLLM
        self.allowsProcessExecution = allowsProcessExecution
    }

    private enum CodingKeys: String, CodingKey {
        case readPaths = "read_paths"
        case writePaths = "write_paths"
        case networkHosts = "network_hosts"
        case secrets
        case allowsLLM = "allows_llm"
        case allowsProcessExecution = "allows_process_execution"
    }
}

public nonisolated enum PermissionAction: String, Codable, CaseIterable, Hashable, Sendable {
    case readFile = "read_file"
    case writeFile = "write_file"
    case deleteFile = "delete_file"
    case createDirectory = "create_directory"
    case networkRequest = "network_request"
    case readSecret = "read_secret"
    case runProcess = "run_process"
    case callLLM = "call_llm"
}

public nonisolated enum PermissionDecisionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case allow
    case ask
    case deny
}

public nonisolated enum PermissionDecisionScope: String, Codable, CaseIterable, Hashable, Sendable {
    case once
    case session
    case always
}

public nonisolated struct PermissionRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var pluginID: String
    public var action: PermissionAction
    public var target: String
    public var reason: String
    public var requestedAt: Date

    public nonisolated init(
        id: String = UUID().uuidString,
        pluginID: String,
        action: PermissionAction,
        target: String,
        reason: String,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.pluginID = pluginID
        self.action = action
        self.target = target
        self.reason = reason
        self.requestedAt = requestedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case pluginID = "plugin_id"
        case action
        case target
        case reason
        case requestedAt = "requested_at"
    }
}

public nonisolated struct PermissionDecision: Codable, Hashable, Sendable {
    public var kind: PermissionDecisionKind
    public var scope: PermissionDecisionScope
    public var ruleID: String?
    public var message: String?

    public nonisolated init(
        kind: PermissionDecisionKind,
        scope: PermissionDecisionScope = .once,
        ruleID: String? = nil,
        message: String? = nil
    ) {
        self.kind = kind
        self.scope = scope
        self.ruleID = ruleID
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case scope
        case ruleID = "rule_id"
        case message
    }
}

public protocol PermissionBroker: Sendable {
    func authorize(_ request: PermissionRequest) async throws -> PermissionDecision
}

public actor DeclarativePermissionBroker: PermissionBroker {
    private var manifestsByID: [String: PluginManifest]
    private let fallbackDecision: PermissionDecisionKind

    public init(manifests: [PluginManifest] = [], fallbackDecision: PermissionDecisionKind = .ask) {
        self.manifestsByID = Dictionary(uniqueKeysWithValues: manifests.map { ($0.id, $0) })
        self.fallbackDecision = fallbackDecision
    }

    public func register(_ manifest: PluginManifest) {
        manifestsByID[manifest.id] = manifest
    }

    public func authorize(_ request: PermissionRequest) async throws -> PermissionDecision {
        guard let manifest = manifestsByID[request.pluginID] else {
            return PermissionDecision(kind: fallbackDecision, message: "Plugin is not registered.")
        }
        if Self.allows(request, permissions: manifest.permissions) {
            return PermissionDecision(kind: .allow, scope: .session, ruleID: "manifest:\(manifest.id)")
        }
        return PermissionDecision(kind: fallbackDecision, message: "Permission is not declared by the plugin manifest.")
    }

    private static nonisolated func allows(_ request: PermissionRequest, permissions: PluginPermissionSet) -> Bool {
        switch request.action {
        case .readFile:
            return matchesPath(request.target, patterns: permissions.readPaths + permissions.writePaths)
        case .writeFile, .deleteFile, .createDirectory:
            return matchesPath(request.target, patterns: permissions.writePaths)
        case .networkRequest:
            return matchesHost(request.target, patterns: permissions.networkHosts)
        case .readSecret:
            return permissions.secrets.contains(request.target)
        case .runProcess:
            return permissions.allowsProcessExecution
        case .callLLM:
            return permissions.allowsLLM
        }
    }

    private static nonisolated func matchesPath(_ target: String, patterns: [String]) -> Bool {
        let normalizedTarget = normalizePath(target)
        return patterns.contains { pattern in
            let normalizedPattern = normalizePath(pattern)
            if normalizedPattern.isEmpty {
                return false
            }
            let isDirectoryPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/")
            if normalizedPattern.contains("*") {
                return wildcardMatch(normalizedTarget, pattern: normalizedPattern, allowDescendants: isDirectoryPattern)
            }
            if isDirectoryPattern {
                return normalizedTarget == normalizedPattern || normalizedTarget.hasPrefix(normalizedPattern + "/")
            }
            return normalizedTarget == normalizedPattern
        }
    }

    private static nonisolated func matchesHost(_ target: String, patterns: [String]) -> Bool {
        let host: String
        if let url = URL(string: target), let parsedHost = url.host {
            host = parsedHost.lowercased()
        } else {
            host = target.lowercased()
        }
        return patterns.contains { pattern in
            let candidate = pattern.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.hasPrefix("*.") {
                let suffix = String(candidate.dropFirst(2))
                return host == suffix || host.hasSuffix("." + suffix)
            }
            return host == candidate
        }
    }

    private static nonisolated func normalizePath(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }

    private static nonisolated func wildcardMatch(_ value: String, pattern: String, allowDescendants: Bool = false) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: "[^/]*")
        let suffix = allowDescendants ? "($|/.*)" : "$"
        guard let expression = try? NSRegularExpression(pattern: "^\(escaped)$") else {
            return false
        }
        if allowDescendants, let descendantExpression = try? NSRegularExpression(pattern: "^\(escaped)\(suffix)") {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return descendantExpression.firstMatch(in: value, range: range) != nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.firstMatch(in: value, range: range) != nil
    }
}
