import Foundation

public protocol LLMProvider: Sendable {
    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String
}

public enum LLMProviderError: LocalizedError, Sendable {
    case invalidEndpoint(String)
    case httpError(statusCode: Int, message: String)
    case malformedResponse
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case let .invalidEndpoint(endpoint):
            return "Invalid LLM endpoint: \(endpoint)."
        case let .httpError(statusCode, message):
            return "LLM request failed with HTTP \(statusCode): \(message)"
        case .malformedResponse:
            return "LLM provider returned a malformed response."
        case .emptyResponse:
            return "LLM provider returned an empty response."
        }
    }
}
