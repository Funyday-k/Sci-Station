import Foundation

public actor OpenAICompatibleProvider {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public nonisolated func buildRequest(configuration: LLMConfiguration, apiKey: String, prompt: String) throws -> URLRequest {
        let endpoint = configuration.baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            throw CocoaError(.fileNoSuchFile)
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
        let (data, _) = try await session.data(for: request)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = jsonObject?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String ?? ""
    }
}