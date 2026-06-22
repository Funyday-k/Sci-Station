import Foundation

public nonisolated enum AgentPromptSurface: String, Codable, CaseIterable, Sendable {
    case planner
    case toolLoop = "tool_loop"
    case paperSummary = "paper_summary"
}

public nonisolated struct AgentResolvedPromptTemplate: Codable, Hashable, Sendable {
    public var templateID: String
    public var title: String
    public var version: String
    public var surface: AgentPromptSurface
    public var bodyHash: String
    public var systemPrompt: String?
    public var promptTemplate: String

    public nonisolated init(
        templateID: String,
        title: String,
        version: String,
        surface: AgentPromptSurface,
        bodyHash: String,
        systemPrompt: String?,
        promptTemplate: String
    ) {
        self.templateID = templateID
        self.title = title
        self.version = version
        self.surface = surface
        self.bodyHash = bodyHash
        self.systemPrompt = systemPrompt
        self.promptTemplate = promptTemplate
    }
}

public nonisolated extension AgentPromptTemplateOverride {
    var contentHash: String {
        let fields = [
            id,
            title,
            description,
            surface.rawValue,
            systemPrompt ?? "",
            promptTemplate,
            isEnabled ? "1" : "0"
        ]
        .joined(separator: "\u{1f}")

        var hash: UInt64 = 0xcbf29ce484222325
        for byte in fields.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

public nonisolated struct AgentPromptResolution: Codable, Hashable, Sendable {
    public var surface: AgentPromptSurface
    public var promptText: String
    public var activeTemplate: AgentResolvedPromptTemplate?

    public nonisolated init(surface: AgentPromptSurface, promptText: String, activeTemplate: AgentResolvedPromptTemplate? = nil) {
        self.surface = surface
        self.promptText = promptText
        self.activeTemplate = activeTemplate
    }

    public nonisolated var templateID: String? { activeTemplate?.templateID }
    public nonisolated var templateVersion: String? { activeTemplate?.version }
    public nonisolated var templateHash: String? { activeTemplate?.bodyHash }

    public nonisolated var summary: String {
        guard let activeTemplate else {
            return "\(surface.rawValue): default"
        }
        return "\(surface.rawValue): \(activeTemplate.templateID)@\(activeTemplate.version) #\(activeTemplate.bodyHash)"
    }
}

public nonisolated struct AgentPromptSnapshot: Codable, Hashable, Sendable {
    public var runID: String
    public var surface: AgentPromptSurface
    public var templateID: String?
    public var templateVersion: String?
    public var templateHash: String?
    public var resolvedAt: Date

    public nonisolated init(
        runID: String,
        surface: AgentPromptSurface,
        templateID: String?,
        templateVersion: String?,
        templateHash: String?,
        resolvedAt: Date = Date()
    ) {
        self.runID = runID
        self.surface = surface
        self.templateID = templateID
        self.templateVersion = templateVersion
        self.templateHash = templateHash
        self.resolvedAt = resolvedAt
    }

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case surface
        case templateID = "template_id"
        case templateVersion = "template_version"
        case templateHash = "template_hash"
        case resolvedAt = "resolved_at"
    }
}

public nonisolated struct AgentPromptLibraryResolver: Sendable {
    public nonisolated init() {}

    public nonisolated func validatePromptText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard !Self.containsSecretLikeText(trimmed) else {
            return "Prompt body appears to contain a secret or private key."
        }
        return nil
    }

    public nonisolated func resolve(
        surface: AgentPromptSurface,
        profile: AgentWorkspaceProfile,
        basePrompt: String
    ) -> AgentPromptResolution {
        guard let template = activeTemplate(for: surface, profile: profile) else {
            return AgentPromptResolution(surface: surface, promptText: basePrompt)
        }

        var segments: [String] = []
        if let systemPrompt = template.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !systemPrompt.isEmpty {
            segments.append(systemPrompt)
        }
        if let promptTemplate = template.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            segments.append(promptTemplate)
        }
        segments.append(basePrompt)

        let promptText = """
        prompt_library_override:
        template_id: \(template.id)
        title: \(template.title)
        version: \(template.version)
        surface: \(template.surface.rawValue)
        body_hash: \(template.contentHash)

        \(segments.joined(separator: "\n\n"))
        """

        return AgentPromptResolution(
            surface: surface,
            promptText: promptText,
            activeTemplate: AgentResolvedPromptTemplate(
                templateID: template.id,
                title: template.title,
                version: template.version,
                surface: template.surface,
                bodyHash: template.contentHash,
                systemPrompt: template.systemPrompt,
                promptTemplate: template.promptTemplate
            )
        )
    }

    public nonisolated func snapshot(
        runID: String,
        surface: AgentPromptSurface,
        resolution: AgentPromptResolution
    ) -> AgentPromptSnapshot {
        AgentPromptSnapshot(
            runID: runID,
            surface: surface,
            templateID: resolution.templateID,
            templateVersion: resolution.templateVersion,
            templateHash: resolution.templateHash
        )
    }

    public nonisolated func diffPreview(current: AgentPromptTemplateOverride?, draft: AgentPromptTemplateOverride) -> String {
        let currentLines = normalizedLines(from: renderedTemplateBody(current))
        let draftLines = normalizedLines(from: renderedTemplateBody(draft))
        guard currentLines != draftLines else {
            return "No changes."
        }

        let output = diffLines(old: currentLines, new: draftLines)
        return output.isEmpty ? "No changes." : output.joined(separator: "\n")
    }

    public nonisolated func renderedTemplateBody(_ template: AgentPromptTemplateOverride?) -> String {
        guard let template else {
            return ""
        }
        var parts: [String] = []
        if let systemPrompt = template.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !systemPrompt.isEmpty {
            parts.append(systemPrompt)
        }
        if let promptTemplate = template.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            parts.append(promptTemplate)
        }
        return parts.joined(separator: "\n\n")
    }

    public nonisolated func validateBody(_ body: String) -> Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validatePromptText(body) == nil
    }

    private nonisolated func activeTemplate(for surface: AgentPromptSurface, profile: AgentWorkspaceProfile) -> AgentPromptTemplateOverride? {
        guard let activeID = profile.activePromptTemplateID,
              let template = profile.promptTemplate(id: activeID),
              template.isEnabled,
              template.surface == surface else {
            return nil
        }
        return template
    }

    private nonisolated func normalizedLines(from value: String) -> [String] {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private nonisolated func diffLines(old: [String], new: [String]) -> [String] {
        let limit = min(old.count, new.count)
        var lines: [String] = []
        for index in 0..<limit {
            let left = old[index]
            let right = new[index]
            if left != right {
                lines.append("- \(left)")
                lines.append("+ \(right)")
            }
        }
        if old.count > limit {
            lines.append(contentsOf: old[limit...].map { "- \($0)" })
        }
        if new.count > limit {
            lines.append(contentsOf: new[limit...].map { "+ \($0)" })
        }
        return lines
    }

    public nonisolated static func containsSecretLikeText(_ text: String) -> Bool {
        let patterns = [
            #"sk-[A-Za-z0-9_-]{16,}"#,
            #"ghp_[A-Za-z0-9_]{20,}"#,
            #"AKIA[0-9A-Z]{16}"#,
            #"eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{8,}"#,
            #"-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----"#
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
