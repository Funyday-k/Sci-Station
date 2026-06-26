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

    public nonisolated func appendingContext(_ context: String?) -> AgentPromptResolution {
        guard let context = context?.trimmingCharacters(in: .whitespacesAndNewlines), !context.isEmpty else {
            return self
        }
        return AgentPromptResolution(
            surface: surface,
            promptText: "\(promptText)\n\n\(context)",
            activeTemplate: activeTemplate
        )
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

public nonisolated enum AgentPromptPatchDecision: String, Codable, Hashable, Sendable {
    case preview
    case accepted
    case rejected
    case discarded
}

public nonisolated struct AgentPromptPatchProposal: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var templateID: String
    public var title: String
    public var version: String
    public var description: String
    public var surface: AgentPromptSurface
    public var systemPrompt: String?
    public var promptTemplate: String
    public var proposedAt: Date
    public var proposedBy: String
    public var rationale: String
    public var sourceSummary: String?

    public nonisolated init(
        id: String = UUID().uuidString,
        templateID: String,
        title: String,
        version: String = "0.1.0",
        description: String = "",
        surface: AgentPromptSurface,
        systemPrompt: String? = nil,
        promptTemplate: String,
        proposedAt: Date = Date(),
        proposedBy: String = "assistant",
        rationale: String = "",
        sourceSummary: String? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.title = title
        self.version = version
        self.description = description
        self.surface = surface
        self.systemPrompt = systemPrompt
        self.promptTemplate = promptTemplate
        self.proposedAt = proposedAt
        self.proposedBy = proposedBy
        self.rationale = rationale
        self.sourceSummary = sourceSummary
    }

    public nonisolated func draft(isEnabled: Bool = true) -> AgentPromptTemplateOverride {
        AgentPromptTemplateOverride(
            id: templateID,
            title: title,
            version: version,
            description: description,
            surface: surface,
            systemPrompt: systemPrompt,
            promptTemplate: promptTemplate,
            isEnabled: isEnabled
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case templateID = "template_id"
        case title
        case version
        case description
        case surface
        case systemPrompt = "system_prompt"
        case promptTemplate = "prompt_template"
        case proposedAt = "proposed_at"
        case proposedBy = "proposed_by"
        case rationale
        case sourceSummary = "source_summary"
    }
}

public nonisolated struct AgentPromptPatchReview: Codable, Hashable, Sendable {
    public var proposal: AgentPromptPatchProposal
    public var currentTemplate: AgentPromptTemplateOverride?
    public var diffPreview: String
    public var rationale: String
    public var sourceSummary: String?
    public var impactScope: [String]
    public var rollbackHint: AgentRollbackHint?
    public var validationMessage: String?
    public var activeSurfaceMismatch: String?

    public nonisolated init(
        proposal: AgentPromptPatchProposal,
        currentTemplate: AgentPromptTemplateOverride?,
        diffPreview: String,
        rationale: String = "",
        sourceSummary: String? = nil,
        impactScope: [String] = [],
        rollbackHint: AgentRollbackHint? = nil,
        validationMessage: String? = nil,
        activeSurfaceMismatch: String? = nil
    ) {
        self.proposal = proposal
        self.currentTemplate = currentTemplate
        self.diffPreview = diffPreview
        self.rationale = rationale
        self.sourceSummary = sourceSummary
        self.impactScope = impactScope
        self.rollbackHint = rollbackHint
        self.validationMessage = validationMessage
        self.activeSurfaceMismatch = activeSurfaceMismatch
    }

    public nonisolated var canAccept: Bool {
        validationMessage == nil && activeSurfaceMismatch == nil
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

    public nonisolated func reviewPatchProposal(
        _ proposal: AgentPromptPatchProposal,
        profile: AgentWorkspaceProfile
    ) -> AgentPromptPatchReview {
        let current = profile.promptTemplate(id: proposal.templateID)
        let activeForSurface = profile.activePromptTemplate(for: proposal.surface)
        let validationMessage = validatePromptTemplate(proposal.draft(isEnabled: current?.isEnabled ?? true))
        let activeSurfaceMismatch: String?
        if let current, current.surface != proposal.surface {
            activeSurfaceMismatch = "Proposal targets \(proposal.surface.rawValue), but the existing override \(current.id) belongs to \(current.surface.rawValue)."
        } else if let activeID = profile.activePromptTemplateID,
                  let activeTemplate = profile.promptTemplate(id: activeID),
                  activeTemplate.surface != proposal.surface,
                  current == nil {
            activeSurfaceMismatch = "Active override \(activeID) belongs to \(activeTemplate.surface.rawValue); proposal targets \(proposal.surface.rawValue). Accepting would not affect the currently active surface."
        } else {
            activeSurfaceMismatch = nil
        }

        let comparisonBase = current ?? activeForSurface
        return AgentPromptPatchReview(
            proposal: proposal,
            currentTemplate: comparisonBase,
            diffPreview: diffPreview(current: comparisonBase, draft: proposal.draft(isEnabled: current?.isEnabled ?? true)),
            rationale: proposal.rationale.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? defaultRationale(for: proposal, current: current, activeForSurface: activeForSurface),
            sourceSummary: proposal.sourceSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? defaultSourceSummary(proposedBy: proposal.proposedBy),
            impactScope: impactScope(for: proposal, current: current, activeForSurface: activeForSurface, profile: profile),
            rollbackHint: AgentRollbackHint(
                summary: "Accepting writes this workspace prompt override. Reject leaves the stored override unchanged; Restore Default removes the workspace override and falls back to product defaults.",
                targetPaths: [AgentWorkspaceProfileRepository.relativePath]
            ),
            validationMessage: validationMessage,
            activeSurfaceMismatch: activeSurfaceMismatch
        )
    }

    public nonisolated func applyAcceptedPatchProposal(
        _ proposal: AgentPromptPatchProposal,
        to profile: AgentWorkspaceProfile
    ) throws -> AgentWorkspaceProfile {
        let review = reviewPatchProposal(proposal, profile: profile)
        if let validationMessage = review.validationMessage {
            throw AgentError.invalidArguments(validationMessage)
        }
        if let activeSurfaceMismatch = review.activeSurfaceMismatch {
            throw AgentError.invalidArguments(activeSurfaceMismatch)
        }

        var updated = profile
        let wasEnabled = profile.promptTemplate(id: proposal.templateID)?.isEnabled ?? true
        let draft = proposal.draft(isEnabled: wasEnabled)
        if let index = updated.promptTemplates.firstIndex(where: { $0.id == proposal.templateID }) {
            updated.promptTemplates[index] = draft
        } else {
            updated.promptTemplates.append(draft)
        }
        if wasEnabled {
            updated.activePromptTemplateID = proposal.templateID
        }
        return updated
    }

    public nonisolated func validatePromptTemplate(_ template: AgentPromptTemplateOverride) -> String? {
        let systemPrompt = template.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptTemplate = template.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEnabled || !promptTemplate.isEmpty || !(systemPrompt?.isEmpty ?? true) else {
            return "Prompt templates require a prompt body."
        }
        if !promptTemplate.isEmpty, let validationMessage = validatePromptText(promptTemplate) {
            return validationMessage
        }
        if let systemPrompt, !systemPrompt.isEmpty, let validationMessage = validatePromptText(systemPrompt) {
            return validationMessage
        }
        return nil
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

    private nonisolated func impactScope(
        for proposal: AgentPromptPatchProposal,
        current: AgentPromptTemplateOverride?,
        activeForSurface: AgentPromptTemplateOverride?,
        profile: AgentWorkspaceProfile
    ) -> [String] {
        var scope: [String] = [
            "Surface: \(proposal.surface.rawValue)",
            "Template: \(proposal.templateID)"
        ]
        if current != nil {
            scope.append("Workspace override will be updated in \(AgentWorkspaceProfileRepository.relativePath).")
        } else {
            scope.append("New workspace override will be added to \(AgentWorkspaceProfileRepository.relativePath).")
        }
        let willBeActive = (current?.isEnabled ?? true)
            && (profile.activePromptTemplateID == proposal.templateID
                || profile.activePromptTemplateID == nil
                || activeForSurface?.id == proposal.templateID)
        scope.append(willBeActive ? "Runtime impact: future \(proposal.surface.rawValue) runs will use this prompt after acceptance." : "Runtime impact: stored as an override, but it is not the currently active prompt for this surface.")
        scope.append("Approval: preview is read-only; acceptance requires explicit confirmation.")
        return scope
    }

    private nonisolated func defaultRationale(
        for proposal: AgentPromptPatchProposal,
        current: AgentPromptTemplateOverride?,
        activeForSurface: AgentPromptTemplateOverride?
    ) -> String {
        if current == nil, activeForSurface == nil {
            return "Proposes a workspace override for \(proposal.surface.rawValue) where no current override exists."
        }
        if current == nil {
            return "Proposes a new \(proposal.surface.rawValue) override based on the active prompt for that surface."
        }
        return "Proposes explicit workspace changes to \(proposal.templateID) for future \(proposal.surface.rawValue) runs."
    }

    private nonisolated func defaultSourceSummary(proposedBy: String) -> String {
        switch proposedBy {
        case "assistant":
            return "AI-generated proposal; user review and confirmation are required before writing."
        case "settings":
            return "Settings editor draft; user confirmation is required before writing."
        default:
            return "\(proposedBy) proposal; explicit confirmation is required before writing."
        }
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
