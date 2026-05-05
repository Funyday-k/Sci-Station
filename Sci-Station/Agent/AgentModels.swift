import Foundation

public nonisolated enum AgentRunMode: String, Codable, Sendable {
    case planOnly
    case executeApproved
}

public nonisolated enum AgentToolRisk: String, Codable, Sendable {
    case readOnly
    case network
    case writesWorkspace
    case externalSideEffect
    case modifiesMetadata
    case runsCode
    case destructive
    case credentialAccess

    public nonisolated init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = AgentToolRisk(rawValue: rawValue) ?? .externalSideEffect
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public nonisolated var defaultRequiresConfirmation: Bool {
        switch self {
        case .readOnly:
            return false
        case .network, .writesWorkspace, .externalSideEffect, .modifiesMetadata, .runsCode, .destructive, .credentialAccess:
            return true
        }
    }

    public nonisolated var defaultPermissionKey: String {
        switch self {
        case .readOnly:
            return "tool.read"
        case .network:
            return "tool.network"
        case .writesWorkspace:
            return "tool.write_workspace"
        case .externalSideEffect:
            return "tool.external_side_effect"
        case .modifiesMetadata:
            return "tool.modify_metadata"
        case .runsCode:
            return "tool.run_code"
        case .destructive:
            return "tool.destructive"
        case .credentialAccess:
            return "tool.credential_access"
        }
    }
}

public nonisolated struct AgentToolOutputPolicy: Codable, Hashable, Sendable {
    public var maxCharacters: Int
    public var includeAttachments: Bool
    public var redactSensitiveValues: Bool

    public nonisolated init(
        maxCharacters: Int = 12_000,
        includeAttachments: Bool = false,
        redactSensitiveValues: Bool = true
    ) {
        self.maxCharacters = maxCharacters
        self.includeAttachments = includeAttachments
        self.redactSensitiveValues = redactSensitiveValues
    }

    private enum CodingKeys: String, CodingKey {
        case maxCharacters = "max_characters"
        case includeAttachments = "include_attachments"
        case redactSensitiveValues = "redact_sensitive_values"
    }
}

public nonisolated struct AgentToolDefinition: Codable, Hashable, Sendable {
    public var identifier: String
    public var name: String
    public var displayName: String
    public var summary: String
    public var inputSchema: String
    public var inputSchemaVersion: Int
    public var risk: AgentToolRisk
    public var requiresConfirmation: Bool
    public var permissionKey: String
    public var outputPolicy: AgentToolOutputPolicy
    public var examples: [String]
    public var source: String

    public nonisolated init(
        identifier: String? = nil,
        name: String,
        displayName: String? = nil,
        summary: String,
        inputSchema: String,
        inputSchemaVersion: Int = 1,
        risk: AgentToolRisk,
        requiresConfirmation: Bool? = nil,
        permissionKey: String? = nil,
        outputPolicy: AgentToolOutputPolicy = AgentToolOutputPolicy(),
        examples: [String] = [],
        source: String = "sci-station"
    ) {
        self.identifier = identifier ?? name
        self.name = name
        self.displayName = displayName ?? name
        self.summary = summary
        self.inputSchema = inputSchema
        self.inputSchemaVersion = max(1, inputSchemaVersion)
        self.risk = risk
        self.requiresConfirmation = requiresConfirmation ?? risk.defaultRequiresConfirmation
        self.permissionKey = permissionKey ?? risk.defaultPermissionKey
        self.outputPolicy = outputPolicy
        self.examples = examples
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case name
        case displayName = "display_name"
        case summary
        case inputSchema = "input_schema"
        case inputSchemaVersion = "input_schema_version"
        case risk
        case requiresConfirmation = "requires_confirmation"
        case permissionKey = "permission_key"
        case outputPolicy = "output_policy"
        case examples
        case source
    }

    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let risk = try container.decode(AgentToolRisk.self, forKey: .risk)

        self.identifier = try container.decodeIfPresent(String.self, forKey: .identifier) ?? name
        self.name = name
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? name
        self.summary = try container.decode(String.self, forKey: .summary)
        self.inputSchema = try container.decode(String.self, forKey: .inputSchema)
        self.inputSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .inputSchemaVersion) ?? 1
        self.risk = risk
        self.requiresConfirmation = try container.decodeIfPresent(Bool.self, forKey: .requiresConfirmation) ?? risk.defaultRequiresConfirmation
        self.permissionKey = try container.decodeIfPresent(String.self, forKey: .permissionKey) ?? risk.defaultPermissionKey
        self.outputPolicy = try container.decodeIfPresent(AgentToolOutputPolicy.self, forKey: .outputPolicy) ?? AgentToolOutputPolicy()
        self.examples = try container.decodeIfPresent([String].self, forKey: .examples) ?? []
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "sci-station"
    }
}

public nonisolated enum AgentMode: String, Codable, CaseIterable, Sendable {
    case plan
    case build
    case explore
    case research
    case review
    case summary
}

public nonisolated struct AgentProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var mode: AgentMode
    public var systemPrompt: String
    public var preferredModel: String?
    public var allowedToolIDs: [String]
    public var permissionRuleIDs: [String]
    public var enabledPresetIDs: [String]
    public var iconName: String
    public var colorHex: String
    public var isHidden: Bool

    public nonisolated init(
        id: String,
        name: String,
        mode: AgentMode,
        systemPrompt: String,
        preferredModel: String? = nil,
        allowedToolIDs: [String] = [],
        permissionRuleIDs: [String] = [],
        enabledPresetIDs: [String] = [],
        iconName: String = "sparkles",
        colorHex: String = "#4F46E5",
        isHidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.systemPrompt = systemPrompt
        self.preferredModel = preferredModel
        self.allowedToolIDs = allowedToolIDs
        self.permissionRuleIDs = permissionRuleIDs
        self.enabledPresetIDs = enabledPresetIDs
        self.iconName = iconName
        self.colorHex = colorHex
        self.isHidden = isHidden
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case systemPrompt = "system_prompt"
        case preferredModel = "preferred_model"
        case allowedToolIDs = "allowed_tool_ids"
        case permissionRuleIDs = "permission_rule_ids"
        case enabledPresetIDs = "enabled_preset_ids"
        case iconName = "icon_name"
        case colorHex = "color_hex"
        case isHidden = "is_hidden"
    }
}

public nonisolated struct SubagentProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var purpose: String
    public var mode: AgentMode
    public var allowedToolIDs: [String]
    public var maxContextCharacters: Int

    public nonisolated init(
        id: String,
        name: String,
        purpose: String,
        mode: AgentMode,
        allowedToolIDs: [String] = [],
        maxContextCharacters: Int = 80_000
    ) {
        self.id = id
        self.name = name
        self.purpose = purpose
        self.mode = mode
        self.allowedToolIDs = allowedToolIDs
        self.maxContextCharacters = maxContextCharacters
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case purpose
        case mode
        case allowedToolIDs = "allowed_tool_ids"
        case maxContextCharacters = "max_context_characters"
    }
}

public nonisolated enum AgentPermissionAction: String, Codable, Sendable {
    case allow
    case ask
    case deny
}

public nonisolated enum AgentPermissionScope: String, Codable, Sendable {
    case once
    case session
    case workspace
    case managed
}

public nonisolated struct AgentPermissionRequest: Codable, Hashable, Sendable {
    public var toolName: String?
    public var permissionKey: String?
    public var command: String?
    public var path: String?
    public var risk: AgentToolRisk

    public nonisolated init(
        toolName: String? = nil,
        permissionKey: String? = nil,
        command: String? = nil,
        path: String? = nil,
        risk: AgentToolRisk = .readOnly
    ) {
        self.toolName = toolName
        self.permissionKey = permissionKey
        self.command = command
        self.path = path
        self.risk = risk
    }

    private enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case permissionKey = "permission_key"
        case command
        case path
        case risk
    }
}

public nonisolated struct AgentPermissionDecision: Codable, Hashable, Sendable {
    public var action: AgentPermissionAction
    public var ruleID: String?
    public var scope: AgentPermissionScope
    public var message: String?

    public nonisolated init(
        action: AgentPermissionAction,
        ruleID: String? = nil,
        scope: AgentPermissionScope = .once,
        message: String? = nil
    ) {
        self.action = action
        self.ruleID = ruleID
        self.scope = scope
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case ruleID = "rule_id"
        case scope
        case message
    }
}

public nonisolated struct AgentPermissionRule: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var description: String
    public var action: AgentPermissionAction
    public var scope: AgentPermissionScope
    public var toolNamePattern: String?
    public var permissionKeyPattern: String?
    public var commandPattern: String?
    public var pathPattern: String?
    public var risk: AgentToolRisk?
    public var message: String?
    public var isEnabled: Bool

    public nonisolated init(
        id: String,
        description: String,
        action: AgentPermissionAction,
        scope: AgentPermissionScope = .once,
        toolNamePattern: String? = nil,
        permissionKeyPattern: String? = nil,
        commandPattern: String? = nil,
        pathPattern: String? = nil,
        risk: AgentToolRisk? = nil,
        message: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.description = description
        self.action = action
        self.scope = scope
        self.toolNamePattern = toolNamePattern
        self.permissionKeyPattern = permissionKeyPattern
        self.commandPattern = commandPattern
        self.pathPattern = pathPattern
        self.risk = risk
        self.message = message
        self.isEnabled = isEnabled
    }

    public nonisolated func matches(_ request: AgentPermissionRequest) -> Bool {
        guard isEnabled else {
            return false
        }
        if let risk, risk != request.risk {
            return false
        }
        if let toolNamePattern, !Self.matches(pattern: toolNamePattern, value: request.toolName) {
            return false
        }
        if let permissionKeyPattern, !Self.matches(pattern: permissionKeyPattern, value: request.permissionKey) {
            return false
        }
        if let commandPattern, !Self.matches(pattern: commandPattern, value: request.command) {
            return false
        }
        if let pathPattern, !Self.matches(pattern: pathPattern, value: request.path) {
            return false
        }

        return risk != nil || toolNamePattern != nil || permissionKeyPattern != nil || commandPattern != nil || pathPattern != nil
    }

    private nonisolated static func matches(pattern: String, value: String?) -> Bool {
        guard let value, !value.isEmpty else {
            return false
        }
        if pattern == "*" {
            return true
        }

        do {
            let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return expression.firstMatch(in: value, options: [], range: range) != nil
        } catch {
            return value.localizedCaseInsensitiveContains(pattern)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case description
        case action
        case scope
        case toolNamePattern = "tool_name_pattern"
        case permissionKeyPattern = "permission_key_pattern"
        case commandPattern = "command_pattern"
        case pathPattern = "path_pattern"
        case risk
        case message
        case isEnabled = "is_enabled"
    }
}

public nonisolated struct AgentPermissionEvaluator: Sendable {
    public var rules: [AgentPermissionRule]

    public nonisolated init(rules: [AgentPermissionRule]) {
        self.rules = rules
    }

    public nonisolated func evaluate(_ request: AgentPermissionRequest) -> AgentPermissionDecision {
        if let rule = rules.first(where: { $0.matches(request) }) {
            return AgentPermissionDecision(action: rule.action, ruleID: rule.id, scope: rule.scope, message: rule.message)
        }

        return AgentPermissionDecision(
            action: request.risk.defaultRequiresConfirmation ? .ask : .allow,
            scope: .once,
            message: request.risk.defaultRequiresConfirmation ? "This action requires confirmation." : nil
        )
    }
}

public nonisolated enum AgentHookEventName: String, Codable, CaseIterable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case notification = "Notification"
    case preCompact = "PreCompact"
    case stop = "Stop"
    case subagentStop = "SubagentStop"

    public nonisolated init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "Notify", "notification":
            self = .notification
        case "PreCompaction", "preCompact", "precompact":
            self = .preCompact
        default:
            guard let eventName = AgentHookEventName(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unsupported hook event name: \(rawValue)"
                )
            }
            self = eventName
        }
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public nonisolated struct AgentHookEvent: Codable, Hashable, Sendable {
    public var name: AgentHookEventName
    public var toolName: String?
    public var command: String?
    public var path: String?
    public var prompt: String?
    public var modifiedPaths: [String]
    public var validationRecorded: Bool

    public nonisolated init(
        name: AgentHookEventName,
        toolName: String? = nil,
        command: String? = nil,
        path: String? = nil,
        prompt: String? = nil,
        modifiedPaths: [String] = [],
        validationRecorded: Bool = false
    ) {
        self.name = name
        self.toolName = toolName
        self.command = command
        self.path = path
        self.prompt = prompt
        self.modifiedPaths = modifiedPaths
        self.validationRecorded = validationRecorded
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case toolName = "tool_name"
        case command
        case path
        case prompt
        case modifiedPaths = "modified_paths"
        case validationRecorded = "validation_recorded"
    }
}

public nonisolated struct AgentHookResult: Codable, Hashable, Sendable {
    public var hookID: String
    public var eventName: AgentHookEventName
    public var permissionDecision: AgentPermissionAction?
    public var message: String?
    public var additionalContext: String?

    public nonisolated init(
        hookID: String,
        eventName: AgentHookEventName,
        permissionDecision: AgentPermissionAction? = nil,
        message: String? = nil,
        additionalContext: String? = nil
    ) {
        self.hookID = hookID
        self.eventName = eventName
        self.permissionDecision = permissionDecision
        self.message = message
        self.additionalContext = additionalContext
    }

    private enum CodingKeys: String, CodingKey {
        case hookID = "hook_id"
        case eventName = "event_name"
        case permissionDecision = "permission_decision"
        case message
        case additionalContext = "additional_context"
    }
}

public nonisolated struct AgentHookDefinition: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var eventName: AgentHookEventName
    public var matcher: String?
    public var permissionDecision: AgentPermissionAction?
    public var message: String?
    public var additionalContext: String?
    public var isEnabled: Bool

    public nonisolated init(
        id: String,
        eventName: AgentHookEventName,
        matcher: String? = nil,
        permissionDecision: AgentPermissionAction? = nil,
        message: String? = nil,
        additionalContext: String? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.eventName = eventName
        self.matcher = matcher
        self.permissionDecision = permissionDecision
        self.message = message
        self.additionalContext = additionalContext
        self.isEnabled = isEnabled
    }

    public nonisolated func evaluate(_ event: AgentHookEvent) -> AgentHookResult? {
        guard isEnabled, event.name == eventName, matches(event) else {
            return nil
        }

        return AgentHookResult(
            hookID: id,
            eventName: event.name,
            permissionDecision: permissionDecision,
            message: message,
            additionalContext: additionalContext
        )
    }

    private nonisolated func matches(_ event: AgentHookEvent) -> Bool {
        guard let matcher, !matcher.isEmpty, matcher != "*" else {
            return true
        }

        let haystack = [
            event.toolName,
            event.command,
            event.path,
            event.prompt,
            event.modifiedPaths.joined(separator: "\n")
        ]
        .compactMap { $0 }
        .joined(separator: "\n")

        return AgentPermissionRule(
            id: "hook-pattern",
            description: "Hook pattern",
            action: .ask,
            commandPattern: matcher
        )
        .matches(AgentPermissionRequest(command: haystack))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case eventName = "event_name"
        case matcher
        case permissionDecision = "permission_decision"
        case message
        case additionalContext = "additional_context"
        case isEnabled = "is_enabled"
    }
}

public nonisolated struct AgentHookEngine: Sendable {
    public var hooks: [AgentHookDefinition]

    public nonisolated init(hooks: [AgentHookDefinition]) {
        self.hooks = hooks
    }

    public nonisolated func evaluate(_ event: AgentHookEvent) -> [AgentHookResult] {
        hooks.compactMap { $0.evaluate(event) }
    }
}

public nonisolated struct AgentSafetyPreset: Sendable {
    public nonisolated static func defaultPermissionRules() -> [AgentPermissionRule] {
        [
            AgentPermissionRule(
                id: "deny-recursive-removal",
                description: "Block recursive removal from agent shell calls.",
                action: .deny,
                commandPattern: #"\brm\s+-[A-Za-z]*r[f]?[A-Za-z]*\b"#,
                message: "Recursive removal must be reviewed and run manually."
            ),
            AgentPermissionRule(
                id: "deny-git-reset-hard",
                description: "Block destructive git resets.",
                action: .deny,
                commandPattern: #"\bgit\s+reset\s+--hard\b"#,
                message: "Hard resets can destroy user work."
            ),
            AgentPermissionRule(
                id: "deny-git-clean",
                description: "Block git clean deletes.",
                action: .deny,
                commandPattern: #"\bgit\s+clean\s+-[^&;|]*[fd]"#,
                message: "git clean can delete untracked work."
            ),
            AgentPermissionRule(
                id: "deny-remote-shell-pipe",
                description: "Block piping remote scripts into a shell.",
                action: .deny,
                commandPattern: #"\bcurl\b[^|]*\|\s*(sh|bash)|\bwget\b[^|]*\|\s*(sh|bash)"#,
                message: "Piping remote scripts into a shell is blocked."
            ),
            AgentPermissionRule(
                id: "ask-sensitive-path",
                description: "Review writes to sensitive-looking paths.",
                action: .ask,
                pathPattern: #"(^|/)\.env(\.|$)|credentials?|secrets?|token|keychain"#,
                message: "Sensitive-looking path requires review."
            ),
            AgentPermissionRule(
                id: "deny-credential-path-write",
                description: "Block agent writes to credential directories and dotenv files.",
                action: .deny,
                pathPattern: #"(^|/)(\.ssh|\.aws)(/|$)|(^|/)\.env(\.|$)|keychain|credential"#,
                message: "Credential paths cannot be modified by the agent."
            ),
            AgentPermissionRule(
                id: "ask-external-side-effect",
                description: "Review external side effects.",
                action: .ask,
                risk: .externalSideEffect,
                message: "External side effects require confirmation."
            )
        ]
    }

    public nonisolated static func defaultHooks() -> [AgentHookDefinition] {
        [
            AgentHookDefinition(
                id: "session-start-context",
                eventName: .sessionStart,
                additionalContext: "Use Sci-Station's Swift-native agent core, keep secrets out of workspace files, and preserve existing agent history."
            ),
            AgentHookDefinition(
                id: "user-prompt-secret-block",
                eventName: .userPromptSubmit,
                matcher: #"(sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{8,}|-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----)"#,
                permissionDecision: .deny,
                message: "Prompt appears to contain a secret or private key and was blocked before model submission."
            ),
            AgentHookDefinition(
                id: "pre-tool-sensitive-path-block",
                eventName: .preToolUse,
                matcher: #"(^|/)(\.ssh|\.aws)(/|$)|(^|/)\.env(\.|$)|keychain|credential"#,
                permissionDecision: .deny,
                message: "Writes to credential or dotenv paths are blocked."
            ),
            AgentHookDefinition(
                id: "post-tool-audit-reminder",
                eventName: .postToolUse,
                matcher: #".+"#,
                message: "Record modified paths and keep tool output auditable in the session timeline."
            ),
            AgentHookDefinition(
                id: "stop-validation-reminder",
                eventName: .stop,
                matcher: #".+"#,
                message: "If this task modified code or data, record validation or explain why validation was not run."
            )
        ]
    }
}

public nonisolated struct AgentCommandTemplate: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var slashCommand: String
    public var title: String
    public var promptTemplate: String
    public var requiredSkillIDs: [String]

    public nonisolated init(
        id: String,
        slashCommand: String,
        title: String,
        promptTemplate: String,
        requiredSkillIDs: [String] = []
    ) {
        self.id = id
        self.slashCommand = slashCommand
        self.title = title
        self.promptTemplate = promptTemplate
        self.requiredSkillIDs = requiredSkillIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case slashCommand = "slash_command"
        case title
        case promptTemplate = "prompt_template"
        case requiredSkillIDs = "required_skill_ids"
    }
}

public nonisolated struct AgentSkillManifest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var version: String
    public var referencePaths: [String]

    public nonisolated init(
        id: String,
        name: String,
        description: String,
        version: String = "0.1.0",
        referencePaths: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.referencePaths = referencePaths
    }

    public nonisolated static func parseFrontmatter(from markdown: String) throws -> AgentSkillManifest {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---", let endIndex = lines.dropFirst().firstIndex(of: "---") else {
            throw AgentError.invalidArguments("Skill frontmatter is required.")
        }

        var fields: [String: String] = [:]
        for line in lines[1..<endIndex] {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            fields[String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)] = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let name = fields["name"] ?? ""
        let description = fields["description"] ?? ""
        guard !name.isEmpty, !description.isEmpty else {
            throw AgentError.invalidArguments("Skill frontmatter must include name and description.")
        }

        return AgentSkillManifest(
            id: name,
            name: name,
            description: description,
            version: fields["version"] ?? "0.1.0"
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case version
        case referencePaths = "reference_paths"
    }
}

public nonisolated enum MCPServerTransport: String, Codable, Sendable {
    case localCommand = "local_command"
    case remoteHTTP = "remote_http"
    case remoteSSE = "remote_sse"
}

public nonisolated struct MCPHeaderReference: Codable, Hashable, Sendable {
    public var name: String
    public var valueReference: String

    public nonisolated init(name: String, valueReference: String) {
        self.name = name
        self.valueReference = valueReference
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case valueReference = "value_reference"
    }
}

public nonisolated struct MCPServerConfiguration: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var transport: MCPServerTransport
    public var isEnabled: Bool
    public var command: String?
    public var arguments: [String]
    public var urlString: String?
    public var timeoutSeconds: Double
    public var allowedTools: [String]
    public var headerReferences: [MCPHeaderReference]
    public var secretReferences: [String]

    public nonisolated init(
        id: String,
        displayName: String,
        transport: MCPServerTransport,
        isEnabled: Bool = false,
        command: String? = nil,
        arguments: [String] = [],
        urlString: String? = nil,
        timeoutSeconds: Double = 30,
        allowedTools: [String] = [],
        headerReferences: [MCPHeaderReference] = [],
        secretReferences: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.transport = transport
        self.isEnabled = isEnabled
        self.command = command
        self.arguments = arguments
        self.urlString = urlString
        self.timeoutSeconds = timeoutSeconds
        self.allowedTools = allowedTools
        self.headerReferences = headerReferences
        self.secretReferences = secretReferences
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case transport
        case isEnabled = "is_enabled"
        case command
        case arguments
        case urlString = "url"
        case timeoutSeconds = "timeout_seconds"
        case allowedTools = "allowed_tools"
        case headerReferences = "header_references"
        case secretReferences = "secret_references"
    }
}

public nonisolated struct AgentPluginManifest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var version: String
    public var description: String
    public var commands: [AgentCommandTemplate]
    public var subagents: [SubagentProfile]
    public var skills: [AgentSkillManifest]
    public var hooks: [AgentHookDefinition]
    public var mcpServers: [MCPServerConfiguration]
    public var isEnabledByDefault: Bool

    public nonisolated init(
        id: String,
        name: String,
        version: String = "0.1.0",
        description: String,
        commands: [AgentCommandTemplate] = [],
        subagents: [SubagentProfile] = [],
        skills: [AgentSkillManifest] = [],
        hooks: [AgentHookDefinition] = [],
        mcpServers: [MCPServerConfiguration] = [],
        isEnabledByDefault: Bool = true
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.commands = commands
        self.subagents = subagents
        self.skills = skills
        self.hooks = hooks
        self.mcpServers = mcpServers
        self.isEnabledByDefault = isEnabledByDefault
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case description
        case commands
        case subagents
        case skills
        case hooks
        case mcpServers = "mcp_servers"
        case isEnabledByDefault = "is_enabled_by_default"
    }
}

public nonisolated struct AgentPluginValidationIssue: Codable, Hashable, Sendable {
    public var field: String
    public var message: String

    public nonisolated init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

public nonisolated struct AgentPluginValidator: Sendable {
    public nonisolated init() {}

    public nonisolated func validate(_ manifest: AgentPluginManifest) -> [AgentPluginValidationIssue] {
        var issues: [AgentPluginValidationIssue] = []

        if manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(AgentPluginValidationIssue(field: "id", message: "Plugin id is required."))
        }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(AgentPluginValidationIssue(field: "name", message: "Plugin name is required."))
        }
        if manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(AgentPluginValidationIssue(field: "version", message: "Plugin version is required."))
        }
        for command in manifest.commands where !command.slashCommand.hasPrefix("/") {
            issues.append(AgentPluginValidationIssue(field: "commands.\(command.id).slash_command", message: "Slash commands must start with /."))
        }
        for server in manifest.mcpServers where server.transport == .localCommand && (server.command ?? "").isEmpty {
            issues.append(AgentPluginValidationIssue(field: "mcp_servers.\(server.id).command", message: "Local MCP servers require a command."))
        }
        for server in manifest.mcpServers where server.transport != .localCommand && (server.urlString ?? "").isEmpty {
            issues.append(AgentPluginValidationIssue(field: "mcp_servers.\(server.id).url", message: "Remote MCP servers require a URL."))
        }

        return issues
    }
}

public nonisolated enum AgentSessionEventKind: String, Codable, Sendable {
    case userMessage = "user_message"
    case assistantMessage = "assistant_message"
    case reasoningSummary = "reasoning_summary"
    case toolCallStarted = "tool_call_started"
    case toolCallCompleted = "tool_call_completed"
    case toolCallFailed = "tool_call_failed"
    case permissionRequested = "permission_requested"
    case permissionResolved = "permission_resolved"
    case hookResult = "hook_result"
    case compactionSummary = "compaction_summary"
}

public nonisolated struct AgentSessionEvent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var sessionID: String
    public var threadID: String?
    public var createdAt: Date
    public var kind: AgentSessionEventKind
    public var summary: String
    public var payloadJSON: String?

    public nonisolated init(
        id: String = UUID().uuidString.lowercased(),
        sessionID: String,
        threadID: String? = nil,
        createdAt: Date = Date(),
        kind: AgentSessionEventKind,
        summary: String,
        payloadJSON: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.threadID = threadID
        self.createdAt = createdAt
        self.kind = kind
        self.summary = summary
        self.payloadJSON = payloadJSON
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case threadID = "thread_id"
        case createdAt = "created_at"
        case kind
        case summary
        case payloadJSON = "payload_json"
    }
}

public nonisolated struct AgentToolCall: Codable, Hashable, Sendable {
    public var id: String
    public var toolName: String
    public var argumentsJSON: String

    public nonisolated init(id: String, toolName: String, argumentsJSON: String) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case toolName = "tool_name"
        case argumentsJSON = "arguments_json"
    }
}

public nonisolated struct AgentPlan: Codable, Hashable, Sendable {
    public var title: String?
    public var summary: String
    public var risk: String?
    public var steps: [String]
    public var toolCalls: [AgentToolCall]
    public var finalResponseDraft: String?

    public nonisolated init(
        title: String? = nil,
        summary: String,
        risk: String? = nil,
        steps: [String] = [],
        toolCalls: [AgentToolCall],
        finalResponseDraft: String? = nil
    ) {
        self.title = title
        self.summary = summary
        self.risk = risk
        self.steps = steps
        self.toolCalls = toolCalls
        self.finalResponseDraft = finalResponseDraft
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case summary
        case risk
        case steps
        case toolCalls = "tool_calls"
        case finalResponseDraft = "final_response_draft"
    }

    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.risk = try container.decodeIfPresent(String.self, forKey: .risk)
        self.steps = try container.decodeIfPresent([String].self, forKey: .steps) ?? []
        self.toolCalls = try container.decode([AgentToolCall].self, forKey: .toolCalls)
        self.finalResponseDraft = try container.decodeIfPresent(String.self, forKey: .finalResponseDraft)
    }
}

public nonisolated struct AgentToolResult: Codable, Hashable, Sendable {
    public var callID: String
    public var toolName: String
    public var succeeded: Bool
    public var requiresConfirmation: Bool
    public var message: String
    public var modifiedPaths: [String]
    public var errorMessage: String?

    public nonisolated init(
        callID: String,
        toolName: String,
        succeeded: Bool,
        requiresConfirmation: Bool = false,
        message: String,
        modifiedPaths: [String] = [],
        errorMessage: String? = nil
    ) {
        self.callID = callID
        self.toolName = toolName
        self.succeeded = succeeded
        self.requiresConfirmation = requiresConfirmation
        self.message = message
        self.modifiedPaths = modifiedPaths
        self.errorMessage = errorMessage
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case toolName = "tool_name"
        case succeeded
        case requiresConfirmation = "requires_confirmation"
        case message
        case modifiedPaths = "modified_paths"
        case errorMessage = "error_message"
    }
}

public nonisolated struct AgentRun: Codable, Hashable, Sendable {
    public var id: String
    public var goal: String
    public var createdAt: Date
    public var completedAt: Date?
    public var currentProjectID: String?
    public var mode: AgentRunMode
    public var plan: AgentPlan
    public var toolResults: [AgentToolResult]

    public nonisolated init(
        id: String,
        goal: String,
        createdAt: Date,
        completedAt: Date?,
        mode: AgentRunMode,
        plan: AgentPlan,
        toolResults: [AgentToolResult],
        currentProjectID: String? = nil
    ) {
        self.id = id
        self.goal = goal
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.currentProjectID = currentProjectID
        self.mode = mode
        self.plan = plan
        self.toolResults = toolResults
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case goal
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case currentProjectID = "current_project_id"
        case mode
        case plan
        case toolResults = "tool_results"
    }
}

public nonisolated struct AgentThread: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var projectID: String?
    public var workspaceID: String?
    public var workspaceName: String?
    public var title: String
    public var runIDs: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?

    public nonisolated init(
        id: String,
        projectID: String? = nil,
        workspaceID: String? = nil,
        workspaceName: String? = nil,
        title: String,
        runIDs: [String] = [],
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.title = title
        self.runIDs = runIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    public nonisolated var isArchived: Bool {
        archivedAt != nil
    }

    public nonisolated mutating func appendRunID(_ runID: String, updatedAt: Date) {
        if !runIDs.contains(runID) {
            runIDs.append(runID)
        }
        self.updatedAt = updatedAt
    }

    public nonisolated mutating func rename(to title: String, updatedAt: Date) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Chat" : title
        self.updatedAt = updatedAt
    }

    public nonisolated mutating func archive(at date: Date) {
        archivedAt = date
        updatedAt = date
    }

    public nonisolated mutating func assignWorkspace(id: String?, name: String?) {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if workspaceID == nil {
            workspaceID = id
        }
        if workspaceName == nil, let trimmedName, !trimmedName.isEmpty {
            workspaceName = trimmedName
        }
    }

    public nonisolated func belongsToWorkspace(id: String?) -> Bool {
        guard let id else {
            return false
        }
        return workspaceID == id
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case workspaceID = "workspace_id"
        case workspaceName = "workspace_name"
        case title
        case runIDs = "run_ids"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case archivedAt = "archived_at"
    }
}

public nonisolated struct AgentPromptDraft: Codable, Hashable, Sendable {
    public var projectID: String?
    public var threadID: String?
    public var text: String
    public var updatedAt: Date

    public nonisolated init(projectID: String? = nil, threadID: String? = nil, text: String, updatedAt: Date) {
        self.projectID = projectID
        self.threadID = threadID
        self.text = text
        self.updatedAt = updatedAt
    }

    public nonisolated var key: String {
        Self.key(projectID: projectID, threadID: threadID)
    }

    public nonisolated static func key(projectID: String?, threadID: String?) -> String {
        "\(projectID ?? "global")::\(threadID ?? "default")"
    }

    private enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case threadID = "thread_id"
        case text
        case updatedAt = "updated_at"
    }
}

public nonisolated struct AgentPromptDraftStore: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var drafts: [AgentPromptDraft]

    public nonisolated init(schemaVersion: Int = 1, drafts: [AgentPromptDraft] = []) {
        self.schemaVersion = schemaVersion
        self.drafts = drafts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case drafts
    }
}

public nonisolated enum AgentLoopPolicy: String, Sendable {
    case manualApprovalOnly
    case readOnlyAutoApproveWritesRequireApproval
}

public nonisolated enum AgentInteractionMode: String, CaseIterable, Identifiable, Sendable {
    case conversation
    case plan
    case assistant

    public nonisolated var id: String { rawValue }

    public nonisolated var title: String {
        switch self {
        case .conversation:
            return "对话"
        case .plan:
            return "计划"
        case .assistant:
            return "助理"
        }
    }

    public nonisolated var shortTitle: String {
        switch self {
        case .conversation:
            return "聊天"
        case .plan:
            return "计划"
        case .assistant:
            return "助理"
        }
    }

    public nonisolated var summary: String {
        switch self {
        case .conversation:
            return "可自动读取论文工具并继续推理；写入会暂停等待审批。"
        case .plan:
            return "生成计划，并仅在审批后写入 Markdown 计划文档。"
        case .assistant:
            return "可提出工具调用，任何写入仍需审批。"
        }
    }

    public nonisolated var plannerInstructions: String {
        switch self {
        case .conversation:
            return "Mode: Conversation Loop. Use native tool calls when paper body details are needed. Read-only tools may run automatically; workspace writes must pause for approval. Final answers must be user-facing Markdown in the latest user_goal language."
        case .plan:
            return "Mode: Plan. You may propose steps and, when useful, call only Markdown planning tools to write a plan document. Do not modify papers, todos, settings, or app state. User-facing fields must follow the latest user_goal language."
        case .assistant:
            return "Mode: Assistant. You may propose available tools, but every workspace write still requires user approval before execution. User-facing fields must follow the latest user_goal language."
        }
    }

    public nonisolated var allowedToolNames: Set<String>? {
        switch self {
        case .conversation:
            return nil
        case .plan:
            return ["write_markdown_plan"]
        case .assistant:
            return nil
        }
    }

    public nonisolated var allowsApprovedToolExecution: Bool {
        true
    }

    public nonisolated var allowsPlainTextResponse: Bool {
        self == .conversation
    }
}

public nonisolated struct AgentExecutionOptions: Sendable {
    public var mode: AgentRunMode
    public var approvedToolCallIDs: Set<String>
    public var loopPolicy: AgentLoopPolicy
    public var disabledHookIDs: Set<String>
    public var plannerInstructions: String?
    public var allowedToolNames: Set<String>?
    public var allowsPlainTextResponse: Bool

    public nonisolated init(
        mode: AgentRunMode = .planOnly,
        approvedToolCallIDs: Set<String> = [],
        loopPolicy: AgentLoopPolicy = .manualApprovalOnly,
        disabledHookIDs: Set<String> = [],
        plannerInstructions: String? = nil,
        allowedToolNames: Set<String>? = nil,
        allowsPlainTextResponse: Bool = false
    ) {
        self.mode = mode
        self.approvedToolCallIDs = approvedToolCallIDs
        self.loopPolicy = loopPolicy
        self.disabledHookIDs = disabledHookIDs
        self.plannerInstructions = plannerInstructions
        self.allowedToolNames = allowedToolNames
        self.allowsPlainTextResponse = allowsPlainTextResponse
    }
}

public nonisolated enum AgentPaperContextPolicy: String, Sendable {
    case metadataOnly = "metadata_only"
    case legacyExcerpts = "legacy_excerpts"
}

public nonisolated struct AgentPaperSnapshot: Codable, Hashable, Sendable {
    public var id: String
    public var citekey: String
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var venue: String?
    public var publicationTitle: String?
    public var doi: String?
    public var arxiv: String?
    public var url: String?
    public var language: String?
    public var collectionPath: String?
    public var projectIDs: [String]
    public var coreProjectIDs: [String]
    public var folderPath: String?
    public var paperDirectoryRelativePath: String?
    public var pdfRelativePath: String?
    public var rawMarkdownRelativePath: String?
    public var tags: [String]
    public var categories: [String]
    public var status: ReadingStatus
    public var priority: Priority
    public var abstract: String?
    public var metadataSummary: String?
    public var sourceExcerptKind: String?
    public var sourceExcerpt: String?

    public nonisolated init(
        paper: Paper,
        rawMarkdownRelativePath: String? = nil,
        sourceExcerptKind: String? = nil,
        sourceExcerpt: String? = nil
    ) {
        self.id = paper.id
        self.citekey = paper.citekey
        self.title = paper.title
        self.authors = paper.authors
        self.year = paper.year
        self.venue = paper.venue
        self.publicationTitle = paper.publicationTitle
        self.doi = paper.doi
        self.arxiv = paper.arxiv
        self.url = paper.url
        self.language = paper.language
        self.collectionPath = paper.collectionPath
        self.projectIDs = paper.projectIDs
        self.coreProjectIDs = paper.coreProjectIDs
        self.folderPath = paper.folderPath
        self.paperDirectoryRelativePath = paper.paperDirectoryRelativePath
        self.pdfRelativePath = paper.pdfRelativePath
        self.rawMarkdownRelativePath = rawMarkdownRelativePath
        self.tags = paper.tags
        self.categories = paper.categories
        self.status = paper.status
        self.priority = paper.priority
        self.abstract = paper.abstract
        self.metadataSummary = [
            paper.title.nilIfEmpty,
            paper.authors.isEmpty ? nil : "authors: \(paper.authors.joined(separator: ", "))",
            paper.year.map { "year: \($0)" },
            (paper.publicationTitle ?? paper.venue)?.nilIfEmpty.map { "venue: \($0)" },
            paper.doi?.nilIfEmpty.map { "doi: \($0)" },
            paper.arxiv?.nilIfEmpty.map { "arxiv: \($0)" },
            paper.tags.isEmpty ? nil : "tags: \(paper.tags.joined(separator: ", "))",
            paper.categories.isEmpty ? nil : "categories: \(paper.categories.joined(separator: ", "))",
            "status: \(paper.status.rawValue)",
            "priority: \(paper.priority.rawValue)"
        ]
        .compactMap { $0 }
        .joined(separator: "; ")
        self.sourceExcerptKind = sourceExcerptKind
        self.sourceExcerpt = sourceExcerpt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case citekey
        case title
        case authors
        case year
        case venue
        case publicationTitle = "publication_title"
        case doi
        case arxiv
        case url
        case language
        case collectionPath = "collection_path"
        case projectIDs = "project_ids"
        case coreProjectIDs = "core_project_ids"
        case folderPath = "folder_path"
        case paperDirectoryRelativePath = "paper_directory_relative_path"
        case pdfRelativePath = "pdf_relative_path"
        case rawMarkdownRelativePath = "raw_markdown_relative_path"
        case tags
        case categories
        case status
        case priority
        case abstract
        case metadataSummary = "metadata_summary"
        case sourceExcerptKind = "source_excerpt_kind"
        case sourceExcerpt = "source_excerpt"
    }
}

public nonisolated struct AgentTodoSnapshot: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: TodoStatus
    public var dueDate: Date?
    public var priority: Priority
    public var projectIDs: [String]
    public var tags: [String]
    public var relatedPaperIDs: [String]

    public nonisolated init(todo: TodoItem) {
        self.id = todo.id
        self.title = todo.title
        self.status = todo.status
        self.dueDate = todo.dueDate
        self.priority = todo.priority
        self.projectIDs = todo.projectIDs
        self.tags = todo.tags
        self.relatedPaperIDs = todo.relatedPaperIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case dueDate = "due_date"
        case priority
        case projectIDs = "project_ids"
        case tags
        case relatedPaperIDs = "related_paper_ids"
    }
}

public nonisolated struct AgentResearchProjectSnapshot: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var colorHex: String
    public var iconName: String
    public var isArchived: Bool
    public var paperCount: Int
    public var corePaperCount: Int
    public var openTodoCount: Int

    public nonisolated init(
        project: ResearchProject,
        paperCount: Int = 0,
        corePaperCount: Int = 0,
        openTodoCount: Int = 0
    ) {
        self.id = project.id
        self.name = project.name
        self.description = project.description
        self.colorHex = project.colorHex
        self.iconName = project.iconName
        self.isArchived = project.isArchived
        self.paperCount = paperCount
        self.corePaperCount = corePaperCount
        self.openTodoCount = openTodoCount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case isArchived = "is_archived"
        case paperCount = "paper_count"
        case corePaperCount = "core_paper_count"
        case openTodoCount = "open_todo_count"
    }
}

public nonisolated struct AgentWorkspaceSnapshot: Codable, Hashable, Sendable {
    public var workspaceName: String
    public var rootName: String
    public var rootCompatibility: ResearchRootCompatibility
    public var currentProjectID: String?
    public var currentProject: AgentResearchProjectSnapshot?
    public var projects: [AgentResearchProjectSnapshot]
    public var selectedPaper: AgentPaperSnapshot?
    public var recentPapers: [AgentPaperSnapshot]
    public var projectPapers: [AgentPaperSnapshot]
    public var openTodos: [AgentTodoSnapshot]
    public var projectOpenTodos: [AgentTodoSnapshot]
    public var paperCount: Int
    public var todoCount: Int
    public var paperLibraryRelativePath: String
    public var agentRelativePath: String

    public nonisolated init(
        workspaceName: String,
        selectedPaper: AgentPaperSnapshot?,
        recentPapers: [AgentPaperSnapshot],
        openTodos: [AgentTodoSnapshot],
        paperCount: Int,
        todoCount: Int,
        rootName: String? = nil,
        rootCompatibility: ResearchRootCompatibility = .researchRoot,
        currentProjectID: String? = nil,
        currentProject: AgentResearchProjectSnapshot? = nil,
        projects: [AgentResearchProjectSnapshot] = [],
        projectPapers: [AgentPaperSnapshot] = [],
        projectOpenTodos: [AgentTodoSnapshot] = [],
        paperLibraryRelativePath: String = Paper.globalLibraryRootRelativePath,
        agentRelativePath: String = ".sci-station/agent"
    ) {
        self.workspaceName = workspaceName
        self.rootName = rootName ?? workspaceName
        self.rootCompatibility = rootCompatibility
        self.currentProjectID = currentProjectID
        self.currentProject = currentProject
        self.projects = projects
        self.selectedPaper = selectedPaper
        self.recentPapers = recentPapers
        self.projectPapers = projectPapers
        self.openTodos = openTodos
        self.projectOpenTodos = projectOpenTodos
        self.paperCount = paperCount
        self.todoCount = todoCount
        self.paperLibraryRelativePath = paperLibraryRelativePath
        self.agentRelativePath = agentRelativePath
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceName = "workspace_name"
        case rootName = "root_name"
        case rootCompatibility = "root_compatibility"
        case currentProjectID = "current_project_id"
        case currentProject = "current_project"
        case projects
        case selectedPaper = "selected_paper"
        case recentPapers = "recent_papers"
        case projectPapers = "project_papers"
        case openTodos = "open_todos"
        case projectOpenTodos = "project_open_todos"
        case paperCount = "paper_count"
        case todoCount = "todo_count"
        case paperLibraryRelativePath = "paper_library_relative_path"
        case agentRelativePath = "agent_relative_path"
    }
}

public nonisolated enum AgentError: LocalizedError, Sendable {
    case emptyGoal
    case unknownTool(String)
    case invalidArguments(String)
    case missingSelectedPaper
    case paperNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .emptyGoal:
            return "Agent goal cannot be empty."
        case let .unknownTool(name):
            return "Unknown agent tool: \(name)."
        case let .invalidArguments(message):
            return "Invalid agent tool arguments: \(message)"
        case .missingSelectedPaper:
            return "This agent action needs a selected paper."
        case let .paperNotFound(id):
            return "No paper found with id \(id)."
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}