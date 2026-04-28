import Foundation

public actor OpenAICompatibleProvider: LLMProvider {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public nonisolated func buildRequest(configuration: LLMConfiguration, apiKey: String, prompt: String) throws -> URLRequest {
        let trimmedBaseURL = configuration.baseURLString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = trimmedBaseURL + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw LLMProviderError.invalidEndpoint(endpoint)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        var payload: [String: Any] = [
            "model": configuration.model,
            "temperature": configuration.temperature,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]
        if let maxTokens = configuration.maxTokens {
            payload["max_tokens"] = maxTokens
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    public func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        let request = try buildRequest(configuration: configuration, apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.malformedResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LLMProviderError.httpError(
                statusCode: httpResponse.statusCode,
                message: apiErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown API error"
            )
        }

        guard let content = try chatCompletionContent(from: data)?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
            throw LLMProviderError.emptyResponse
        }

        return content
    }

    private nonisolated func apiErrorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any] else {
            return nil
        }

        return error["message"] as? String
    }

    private nonisolated func chatCompletionContent(from data: Data) throws -> String? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.malformedResponse
        }

        let choices = root["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String
    }
}
