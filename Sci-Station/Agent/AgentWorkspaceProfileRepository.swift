import Foundation

public actor AgentWorkspaceProfileRepository {
    public static let relativePath = ".sci-station/agent/profile.json"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
}
