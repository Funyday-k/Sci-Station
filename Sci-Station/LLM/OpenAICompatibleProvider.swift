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

    public nonisolated func buildChatRequest(
        configuration: LLMConfiguration,
        apiKey: String,
        providerRequest: LLMProviderRequest,
        stream: Bool = false
    ) throws -> URLRequest {
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
            "model": providerRequest.options.model ?? configuration.model,
            "temperature": providerRequest.options.temperature ?? configuration.temperature,
            "messages": providerRequest.messages.map(Self.messagePayload(from:))
        ]
        if let maxTokens = providerRequest.options.maxTokens ?? configuration.maxTokens {
            payload["max_tokens"] = maxTokens
        }
        if !providerRequest.tools.isEmpty {
            payload["tools"] = providerRequest.tools.map(Self.toolPayload(from:))
        }
        if stream {
            payload["stream"] = true
        }
        for (key, value) in providerRequest.options.providerOptions {
            payload[key] = value
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    public func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        try Task.checkCancellation()
        let request = try buildRequest(configuration: configuration, apiKey: apiKey, prompt: prompt)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

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

    public func respond(to request: LLMProviderRequest, configuration: LLMConfiguration, apiKey: String) async throws -> LLMProviderResponse {
        try Task.checkCancellation()
        let urlRequest = try buildChatRequest(configuration: configuration, apiKey: apiKey, providerRequest: request)
        let (data, response) = try await session.data(for: urlRequest)
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.malformedResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LLMProviderError.httpError(
                statusCode: httpResponse.statusCode,
                message: apiErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown API error"
            )
        }

        let parsedMessage = try chatCompletionMessage(from: data)
        guard !parsedMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !parsedMessage.toolCalls.isEmpty else {
            throw LLMProviderError.emptyResponse
        }

        return LLMProviderResponse(
            message: LLMChatMessage(role: .assistant, content: parsedMessage.content),
            toolCalls: parsedMessage.toolCalls,
            rawResponse: String(data: data, encoding: .utf8)
        )
    }

    private nonisolated func apiErrorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any] else {
            return nil
        }

        return error["message"] as? String
    }

    private nonisolated func chatCompletionContent(from data: Data) throws -> String? {
        try chatCompletionMessage(from: data).content.nilIfEmpty
    }

    private nonisolated func chatCompletionMessage(from data: Data) throws -> (content: String, toolCalls: [AgentToolCall]) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.malformedResponse
        }

        let choices = root["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? ""
        let toolCalls = (message?["tool_calls"] as? [[String: Any]])?.compactMap(Self.agentToolCall(from:)) ?? []
        return (content, toolCalls)
    }

    private nonisolated static func messagePayload(from message: LLMChatMessage) -> [String: Any] {
        var payload: [String: Any] = [
            "role": message.role.rawValue,
            "content": message.content
        ]
        if let name = message.name {
            payload["name"] = name
        }
        if let toolCallID = message.toolCallID {
            payload["tool_call_id"] = toolCallID
        }
        return payload
    }

    private nonisolated static func toolPayload(from tool: LLMToolSpecification) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": schemaObject(from: tool.inputSchemaJSON)
            ]
        ]
    }

    private nonisolated static func schemaObject(from schemaJSON: String) -> Any {
        guard let data = schemaJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return ["type": "object"]
        }
        return object
    }

    private nonisolated static func agentToolCall(from payload: [String: Any]) -> AgentToolCall? {
        let function = payload["function"] as? [String: Any]
        guard let toolName = function?["name"] as? String else {
            return nil
        }
        return AgentToolCall(
            id: payload["id"] as? String ?? "tool-call-\(UUID().uuidString.lowercased())",
            toolName: toolName,
            argumentsJSON: function?["arguments"] as? String ?? "{}"
        )
    }
}

extension OpenAICompatibleProvider: LLMChatProvider {}

extension OpenAICompatibleProvider: LLMStreamingChatProvider {
    public nonisolated func streamResponse(
        to request: LLMProviderRequest,
        configuration: LLMConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<LLMProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try Task.checkCancellation()
                    let urlRequest = try buildChatRequest(
                        configuration: configuration,
                        apiKey: apiKey,
                        providerRequest: request,
                        stream: true
                    )
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    try Task.checkCancellation()

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMProviderError.malformedResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        throw LLMProviderError.httpError(statusCode: httpResponse.statusCode, message: "Streaming request failed.")
                    }

                    var accumulated = ""
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else {
                            continue
                        }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                        if payload == "[DONE]" {
                            break
                        }
                        guard let data = payload.data(using: .utf8),
                              let delta = Self.streamDeltaContent(from: data),
                              !delta.isEmpty else {
                            continue
                        }
                        accumulated += delta
                        continuation.yield(.messageDelta(delta))
                    }

                    continuation.yield(.completed(LLMProviderResponse(
                        message: LLMChatMessage(role: .assistant, content: accumulated),
                        rawResponse: accumulated
                    )))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private nonisolated static func streamDeltaContent(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return nil
        }

        if let delta = firstChoice["delta"] as? [String: Any] {
            return delta["content"] as? String
        }
        if let message = firstChoice["message"] as? [String: Any] {
            return message["content"] as? String
        }
        return nil
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
