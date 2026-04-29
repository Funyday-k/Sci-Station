import Foundation

public actor GitHubCopilotConfigurationStore {
    public static let relativePath = "settings/github_copilot.yaml"

    public init() {}

    public func load(in workspace: ResearchWorkspace) throws -> GitHubCopilotConfiguration {
        let fileURL = workspace.fileURL(for: Self.relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return GitHubCopilotConfiguration()
        }

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        var configuration = GitHubCopilotConfiguration()

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("enabled:") {
                configuration.isEnabled = Bool(scalarValue(from: trimmed)) ?? false
            } else if trimmed.hasPrefix("client_id:") {
                configuration.clientID = scalarValue(from: trimmed)
            } else if trimmed.hasPrefix("callback_url:") {
                configuration.callbackURLString = scalarValue(from: trimmed)
            } else if trimmed.hasPrefix("required_org:") {
                configuration.requiredOrganization = emptyToNil(scalarValue(from: trimmed))
            } else if trimmed.hasPrefix("model:") {
                configuration.model = emptyToNil(scalarValue(from: trimmed)) ?? "gpt-4.1"
            }
        }

        return configuration
    }

    public func save(_ configuration: GitHubCopilotConfiguration, in workspace: ResearchWorkspace) throws {
        let fileURL = workspace.fileURL(for: Self.relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let requiredOrganization = configuration.requiredOrganization.map(quoted) ?? ""
        let contents = """
        github_copilot:
          enabled: \(configuration.isEnabled)
          client_id: \(quoted(configuration.clientID))
          callback_url: \(quoted(configuration.callbackURLString))
          required_org: \(requiredOrganization)
          model: \(quoted(configuration.model))
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private nonisolated func scalarValue(from line: String) -> String {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            return ""
        }

        return String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
    }

    private nonisolated func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private nonisolated func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

