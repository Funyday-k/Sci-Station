import Foundation

public nonisolated struct AgentCopilotBridgeExport: Codable, Hashable, Sendable {
    public var id: String
    public var createdAt: Date
    public var promptRelativePath: String
    public var manifestRelativePath: String

    public nonisolated init(id: String, createdAt: Date, promptRelativePath: String, manifestRelativePath: String) {
        self.id = id
        self.createdAt = createdAt
        self.promptRelativePath = promptRelativePath
        self.manifestRelativePath = manifestRelativePath
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case promptRelativePath = "prompt_relative_path"
        case manifestRelativePath = "manifest_relative_path"
    }
}

public actor AgentCopilotBridgeExporter {
    private let promptBuilder: AgentPromptBuilder
    private let fileManager: FileManager

    public init(promptBuilder: AgentPromptBuilder = AgentPromptBuilder(), fileManager: FileManager = .default) {
        self.promptBuilder = promptBuilder
        self.fileManager = fileManager
    }

    public func export(
        goal: String,
        workspaceSnapshot: AgentWorkspaceSnapshot,
        tools: [AgentToolDefinition],
        in workspace: ResearchWorkspace
    ) throws -> AgentCopilotBridgeExport {
        let id = "copilot-bridge-\(UUID().uuidString.lowercased())"
        let directoryURL = workspace.directoryURL(for: ".sci-station/agent/copilot-bridge")
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let promptRelativePath = ".sci-station/agent/copilot-bridge/\(id).prompt.md"
        let manifestRelativePath = ".sci-station/agent/copilot-bridge/\(id).json"
        let prompt = try promptBuilder.buildPrompt(goal: goal, workspaceSnapshot: workspaceSnapshot, tools: tools)
        let promptFile = """
        ---
        description: "Plan a Sci-Station in-app agent task"
        agent: "agent"
        ---
        \(prompt)
        """
        try promptFile.write(to: workspace.fileURL(for: promptRelativePath), atomically: true, encoding: .utf8)

        let export = AgentCopilotBridgeExport(
            id: id,
            createdAt: Date(),
            promptRelativePath: promptRelativePath,
            manifestRelativePath: manifestRelativePath
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)
        try data.write(to: workspace.fileURL(for: manifestRelativePath), options: .atomic)
        return export
    }
}