import Foundation

public enum LLMProviderKind: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai-compatible"
}

public struct LLMConfiguration: Codable, Hashable, Sendable {
    public var provider: LLMProviderKind
    public var baseURLString: String
    public var model: String
    public var temperature: Double
    public var maxTokens: Int?

    public nonisolated init(
        provider: LLMProviderKind = .openAICompatible,
        baseURLString: String = "https://api.deepseek.com",
        model: String = "deepseek-v4-flash",
        temperature: Double = 0.2,
        maxTokens: Int? = 384_000
    ) {
        self.provider = provider
        self.baseURLString = baseURLString
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}