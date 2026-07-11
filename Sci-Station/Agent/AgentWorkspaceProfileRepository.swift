import Foundation

public actor AgentWorkspaceProfileRepository {
    public static let relativePath = ".sci-station/agent/profile.json"

    private let fileManager: FileManager
    private let promptLibraryResolver: AgentPromptLibraryResolver

    public init(
        fileManager: FileManager = .default,
        promptLibraryResolver: AgentPromptLibraryResolver = AgentPromptLibraryResolver()
    ) {
        self.fileManager = fileManager
        self.promptLibraryResolver = promptLibraryResolver
    }

    public func load(in root: ResearchRoot) throws -> AgentWorkspaceProfile {
        let fileURL = root.fileURL(for: Self.relativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return AgentWorkspaceProfile()
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AgentWorkspaceProfile.self, from: data)
    }

    public func save(_ profile: AgentWorkspaceProfile, in root: ResearchRoot) throws {
        let fileURL = root.fileURL(for: Self.relativePath)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(to: fileURL, options: .atomic)
    }

    public func upsertPromptTemplate(_ promptTemplate: AgentPromptTemplateOverride, in root: ResearchRoot) throws {
        var profile = try load(in: root)
        if let existingIndex = profile.promptTemplates.firstIndex(where: { $0.id == promptTemplate.id }) {
            profile.promptTemplates[existingIndex] = promptTemplate
        } else {
            profile.promptTemplates.append(promptTemplate)
        }
        if profile.activePromptTemplateID == nil, promptTemplate.isEnabled {
            profile.activePromptTemplateID = promptTemplate.id
        }
        try save(profile, in: root)
    }

    public func removePromptTemplate(id: String, in root: ResearchRoot) throws {
        var profile = try load(in: root)
        profile.promptTemplates.removeAll { $0.id == id }
        if profile.activePromptTemplateID == id {
            profile.activePromptTemplateID = profile.enabledPromptTemplates.first?.id
        }
        try save(profile, in: root)
    }

    public func restoreDefaultPromptTemplate(id: String, in root: ResearchRoot) throws {
        var profile = try load(in: root)
        profile.promptTemplates.removeAll { $0.id == id }
        if profile.activePromptTemplateID == id {
            profile.activePromptTemplateID = nil
        }
        try save(profile, in: root)
    }

    public func acceptPromptPatchProposal(_ proposal: AgentPromptPatchProposal, in root: ResearchRoot) throws {
        let profile = try load(in: root)
        let updatedProfile = try promptLibraryResolver.applyAcceptedPatchProposal(proposal, to: profile)
        try save(updatedProfile, in: root)
    }

    public func setActivePromptTemplate(id: String?, in root: ResearchRoot) throws {
        var profile = try load(in: root)
        profile.activePromptTemplateID = id
        try save(profile, in: root)
    }

    public func setPromptTemplateEnabled(id: String, isEnabled: Bool, in root: ResearchRoot) throws {
        var profile = try load(in: root)
        guard let index = profile.promptTemplates.firstIndex(where: { $0.id == id }) else {
            return
        }
        profile.promptTemplates[index].isEnabled = isEnabled
        if !isEnabled, profile.activePromptTemplateID == id {
            profile.activePromptTemplateID = profile.enabledPromptTemplates.first(where: { $0.id != id })?.id
        }
        if isEnabled, profile.activePromptTemplateID == nil {
            profile.activePromptTemplateID = id
        }
        try save(profile, in: root)
    }

    public func setPromptTemplateBody(
        id: String,
        title: String,
        version: String,
        description: String,
        surface: AgentPromptSurface,
        systemPrompt: String?,
        promptTemplate: String,
        isEnabled: Bool,
        in root: ResearchRoot
    ) throws {
        var profile = try load(in: root)
        if let validationMessage = promptLibraryResolver.validatePromptText(promptTemplate) {
            throw AgentError.invalidArguments(validationMessage)
        }
        if let systemPrompt, let validationMessage = promptLibraryResolver.validatePromptText(systemPrompt) {
            throw AgentError.invalidArguments(validationMessage)
        }
        let updated = AgentPromptTemplateOverride(
            id: id,
            title: title,
            version: version,
            description: description,
            surface: surface,
            systemPrompt: systemPrompt,
            promptTemplate: promptTemplate,
            isEnabled: isEnabled
        )
        if let index = profile.promptTemplates.firstIndex(where: { $0.id == id }) {
            profile.promptTemplates[index] = updated
        } else {
            profile.promptTemplates.append(updated)
        }
        if isEnabled, profile.activePromptTemplateID == nil {
            profile.activePromptTemplateID = id
        }
        try save(profile, in: root)
    }

    public func setSkillEnabled(
        skillID: String,
        displayName: String? = nil,
        isEnabled: Bool,
        trustLevel: AgentSkillTrustLevel? = nil,
        allowedToolIDs: [String]? = nil,
        in root: ResearchRoot
    ) throws {
        var profile = try load(in: root)
        let existing = profile.skillToggle(id: skillID)
        let toggle = AgentSkillToggle(
            skillID: skillID,
            displayName: displayName ?? existing?.displayName,
            isEnabled: isEnabled,
            trustLevel: trustLevel ?? existing?.trustLevel ?? .untrusted,
            allowedToolIDs: allowedToolIDs ?? existing?.allowedToolIDs ?? []
        )
        if let existingIndex = profile.skillToggles.firstIndex(where: { $0.skillID == skillID }) {
            profile.skillToggles[existingIndex] = toggle
        } else {
            profile.skillToggles.append(toggle)
        }
        try save(profile, in: root)
    }

    public func setSkillTrust(
        skillID: String,
        displayName: String? = nil,
        trustLevel: AgentSkillTrustLevel,
        isEnabled: Bool? = nil,
        in root: ResearchRoot
    ) throws {
        var profile = try load(in: root)
        let existing = profile.skillToggle(id: skillID)
        let toggle = AgentSkillToggle(
            skillID: skillID,
            displayName: displayName ?? existing?.displayName,
            isEnabled: isEnabled ?? existing?.isEnabled ?? false,
            trustLevel: trustLevel,
            allowedToolIDs: existing?.allowedToolIDs ?? []
        )
        if let existingIndex = profile.skillToggles.firstIndex(where: { $0.skillID == skillID }) {
            profile.skillToggles[existingIndex] = toggle
        } else {
            profile.skillToggles.append(toggle)
        }
        try save(profile, in: root)
    }

    public func setSkillToggle(_ toggle: AgentSkillToggle, in root: ResearchRoot) throws {
        var profile = try load(in: root)
        if let existingIndex = profile.skillToggles.firstIndex(where: { $0.skillID == toggle.skillID }) {
            profile.skillToggles[existingIndex] = toggle
        } else {
            profile.skillToggles.append(toggle)
        }
        try save(profile, in: root)
    }

    public func upsertMCPServer(_ server: MCPServerConfiguration, in root: ResearchRoot) throws {
        var profile = try load(in: root)
        if let existingIndex = profile.mcpServers.firstIndex(where: { $0.id == server.id }) {
            profile.mcpServers[existingIndex] = server
        } else {
            profile.mcpServers.append(server)
        }
        try save(profile, in: root)
    }

    public func removeMCPServer(id: String, in root: ResearchRoot) throws {
        var profile = try load(in: root)
        profile.mcpServers.removeAll { $0.id == id }
        try save(profile, in: root)
    }
}
