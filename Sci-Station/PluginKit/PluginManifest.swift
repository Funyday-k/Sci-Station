import Foundation

public nonisolated enum PluginKind: String, Codable, CaseIterable, Hashable, Sendable {
    case builtIn = "built_in"
    case localManifest = "local_manifest"
    case sidecar
}

public nonisolated enum PluginSource: String, Codable, CaseIterable, Hashable, Sendable {
    case bundled
    case workspace
    case userInstalled = "user_installed"
    case remote
}

public nonisolated struct PluginCapability: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public nonisolated init(rawValue: String) {
        self.rawValue = rawValue
    }

    public nonisolated init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public static let workspaceRead: PluginCapability = "workspace.read"
    public static let workspaceWrite: PluginCapability = "workspace.write"
    public static let network: PluginCapability = "network"
    public static let secrets: PluginCapability = "secrets"
    public static let llm: PluginCapability = "llm"
    public static let process: PluginCapability = "process"
}

public nonisolated struct PluginManifest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var version: String
    public var kind: PluginKind
    public var source: PluginSource
    public var description: String
    public var dependencies: [String]
    public var capabilities: [PluginCapability]
    public var permissions: PluginPermissionSet
    public var contributes: PluginContribution
    public var isEnabledByDefault: Bool

    public nonisolated init(
        id: String,
        name: String,
        version: String = "0.1.0",
        kind: PluginKind = .builtIn,
        source: PluginSource = .bundled,
        description: String = "",
        dependencies: [String] = [],
        capabilities: [PluginCapability] = [],
        permissions: PluginPermissionSet = PluginPermissionSet(),
        contributes: PluginContribution = PluginContribution(),
        isEnabledByDefault: Bool = true
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.kind = kind
        self.source = source
        self.description = description
        self.dependencies = dependencies
        self.capabilities = capabilities
        self.permissions = permissions
        self.contributes = contributes
        self.isEnabledByDefault = isEnabledByDefault
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case kind
        case source
        case description
        case dependencies
        case capabilities
        case permissions
        case contributes
        case isEnabledByDefault = "is_enabled_by_default"
    }
}

public nonisolated struct PluginValidationIssue: Codable, Hashable, Sendable {
    public var field: String
    public var message: String

    public nonisolated init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

public nonisolated struct PluginManifestValidator: Sendable {
    public nonisolated init() {}

    public nonisolated func validate(_ manifest: PluginManifest) -> [PluginValidationIssue] {
        var issues: [PluginValidationIssue] = []
        if !Self.isValidIdentifier(manifest.id) {
            issues.append(PluginValidationIssue(field: "id", message: "Plugin id must be a stable identifier."))
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(PluginValidationIssue(field: "name", message: "Plugin name is required."))
        }
        if manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(PluginValidationIssue(field: "version", message: "Plugin version is required."))
        }
        for dependency in manifest.dependencies where !Self.isValidIdentifier(dependency) {
            issues.append(PluginValidationIssue(field: "dependencies", message: "Plugin dependency '\(dependency)' is not a stable identifier."))
        }
        let commandIDs = manifest.contributes.commands.map(\.id)
        if Set(commandIDs).count != commandIDs.count {
            issues.append(PluginValidationIssue(field: "contributes.commands", message: "Command contribution ids must be unique within a plugin."))
        }
        let routeIDs = manifest.contributes.routes.map(\.id)
        if Set(routeIDs).count != routeIDs.count {
            issues.append(PluginValidationIssue(field: "contributes.routes", message: "Route contribution ids must be unique within a plugin."))
        }
        return issues
    }

    public static nonisolated func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }
        let allowedScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.")
        return value.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
    }
}
