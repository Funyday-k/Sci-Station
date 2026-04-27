import Foundation

public actor LLMConfigurationStore {
    public init() {}

    public func load(in workspace: ResearchWorkspace) throws -> LLMConfiguration {
        let fileURL = workspace.fileURL(for: "settings.yaml")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LLMConfiguration()
        }

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        var provider = LLMProviderKind.openAICompatible
        var baseURLString = LLMConfiguration().baseURLString
        var model = LLMConfiguration().model
        var temperature = LLMConfiguration().temperature
        var maxTokens = LLMConfiguration().maxTokens

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("provider:") {
                provider = LLMProviderKind(rawValue: scalarValue(from: trimmed)) ?? .openAICompatible
            } else if trimmed.hasPrefix("base_url:") {
                baseURLString = scalarValue(from: trimmed)
            } else if trimmed.hasPrefix("model:") {
                model = scalarValue(from: trimmed)
            } else if trimmed.hasPrefix("temperature:") {
                temperature = Double(scalarValue(from: trimmed)) ?? LLMConfiguration().temperature
            } else if trimmed.hasPrefix("max_tokens:") {
                maxTokens = Int(scalarValue(from: trimmed))
            }
        }

        return LLMConfiguration(
            provider: provider,
            baseURLString: baseURLString,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    public func save(_ configuration: LLMConfiguration, in workspace: ResearchWorkspace) throws {
        let fileURL = workspace.fileURL(for: "settings.yaml")
        let contents = """
        llm:
          provider: \(configuration.provider.rawValue)
          base_url: \(quoted(configuration.baseURLString))
          model: \(quoted(configuration.model))
          temperature: \(configuration.temperature)
          max_tokens: \(configuration.maxTokens.map(String.init) ?? "")
        """
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func scalarValue(from line: String) -> String {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            return ""
        }

        return String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
    }

    private func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}