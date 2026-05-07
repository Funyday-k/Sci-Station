import Foundation

public nonisolated struct OpenAICompatibleStreamDeltaParser: Sendable {
    public nonisolated init() {}

    public nonisolated static func contentDelta(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return nil
        }

        if let delta = firstChoice["delta"] as? [String: Any] {
            return (delta["content"] as? String)?.nilIfEmpty
        }
        if let message = firstChoice["message"] as? [String: Any] {
            return (message["content"] as? String)?.nilIfEmpty
        }
        return nil
    }

    public nonisolated static func reasoningContentDelta(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let firstChoice = choices.first else {
            return nil
        }

        if let delta = firstChoice["delta"] as? [String: Any] {
            return (delta["reasoning_content"] as? String)?.nilIfEmpty
        }
        if let message = firstChoice["message"] as? [String: Any] {
            return (message["reasoning_content"] as? String)?.nilIfEmpty
        }
        return nil
    }
}

private nonisolated struct OpenAICompatibleStreamingToolCallAccumulator: Sendable {
    private struct PartialCall: Sendable {
        var id: String?
        var name: String?
        var arguments: String
    }

    private var partials: [Int: PartialCall] = [:]

    mutating func mergeDelta(from data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let toolCalls = delta["tool_calls"] as? [[String: Any]] else {
            return
        }

        for payload in toolCalls {
            let index = payload["index"] as? Int ?? 0
            var partial = partials[index] ?? PartialCall(id: nil, name: nil, arguments: "")
            if let id = payload["id"] as? String, !id.isEmpty {
                partial.id = id
            }
            if let function = payload["function"] as? [String: Any] {
                if let name = function["name"] as? String, !name.isEmpty {
                    partial.name = name
                }
                if let arguments = function["arguments"] as? String, !arguments.isEmpty {
                    partial.arguments += arguments
                }
            }
            partials[index] = partial
        }
    }

    func toolCalls() -> [AgentToolCall] {
        partials.keys.sorted().compactMap { index in
            guard let partial = partials[index], let name = partial.name, !name.isEmpty else {
                return nil
            }
            return AgentToolCall(
                id: partial.id ?? "tool-call-\(UUID().uuidString.lowercased())",
                toolName: name,
                argumentsJSON: partial.arguments.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "{}"
            )
        }
    }
}

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
        let providerRequest = try LLMProviderRequestSanitizer.sanitized(providerRequest, configuration: configuration)
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
            payload["tool_choice"] = "auto"
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

        let parsedMessage = try Self.parseChatCompletionMessage(from: data)
        guard !parsedMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !parsedMessage.toolCalls.isEmpty else {
            throw LLMProviderError.emptyResponse
        }

        return LLMProviderResponse(
            message: parsedMessage,
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
        try Self.parseChatCompletionMessage(from: data).content.nilIfEmpty
    }

    public nonisolated static func parseChatCompletionMessage(from data: Data) throws -> LLMChatMessage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMProviderError.malformedResponse
        }

        let choices = root["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String ?? ""
        let reasoningContent = (message?["reasoning_content"] as? String)?.nilIfEmpty
        let toolCalls = (message?["tool_calls"] as? [[String: Any]])?.compactMap(Self.agentToolCall(from:)) ?? []
        return LLMChatMessage(role: .assistant, content: content, reasoningContent: reasoningContent, toolCalls: toolCalls)
    }

    private nonisolated static func messagePayload(from message: LLMChatMessage) -> [String: Any] {
        var payload: [String: Any] = [
            "role": message.role.rawValue,
            "content": message.content
        ]
        if message.role == .assistant,
           let reasoningContent = message.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reasoningContent.isEmpty {
            payload["reasoning_content"] = reasoningContent
        }
        if let name = message.name {
            payload["name"] = name
        }
        if let toolCallID = message.toolCallID {
            payload["tool_call_id"] = toolCallID
        }
        if message.role == .assistant, !message.toolCalls.isEmpty {
            payload["tool_calls"] = message.toolCalls.map(Self.toolCallPayload(from:))
        }
        return payload
    }

    private nonisolated static func toolCallPayload(from call: AgentToolCall) -> [String: Any] {
        [
            "id": call.id,
            "type": "function",
            "function": [
                "name": call.toolName,
                "arguments": call.argumentsJSON
            ]
        ]
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

    private nonisolated static func schemaObject(from schemaJSON: String) -> [String: Any] {
        let fallback: [String: Any] = [
            "type": "object",
            "properties": [:]
        ]
        guard let data = schemaJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return fallback
        }
        guard let dictionary = object as? [String: Any] else {
            return fallback
        }
        return normalizedObjectSchema(from: dictionary)
    }

    private nonisolated static func normalizedObjectSchema(from dictionary: [String: Any]) -> [String: Any] {
        if (dictionary["type"] as? String) == "object" {
            var schema = dictionary
            if schema["properties"] == nil {
                schema["properties"] = [:]
            }
            return schema
        }

        if dictionary["properties"] != nil {
            var schema = dictionary
            schema["type"] = "object"
            return schema
        }

        var properties: [String: Any] = [:]
        var required: [String] = []
        for key in dictionary.keys.sorted() {
            guard let value = dictionary[key] else {
                continue
            }
            properties[key] = inferredSchemaProperty(from: value)
            if isRequiredShorthandValue(value) {
                required.append(key)
            }
        }

        var schema: [String: Any] = [
            "type": "object",
            "properties": properties
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return schema
    }

    private nonisolated static func inferredSchemaProperty(from value: Any) -> [String: Any] {
        if let nested = value as? [String: Any] {
            if nested["type"] != nil || nested["properties"] != nil {
                return normalizedObjectSchema(from: nested)
            }
            return normalizedObjectSchema(from: nested)
        }

        if let array = value as? [Any] {
            let itemSchema = array.first.map { inferredSchemaProperty(from: $0) } ?? ["type": "string"]
            return [
                "type": "array",
                "items": itemSchema
            ]
        }

        if let string = value as? String {
            return inferredSchemaProperty(fromDescription: string)
        }

        if value is Bool {
            return ["type": "boolean"]
        }
        if value is Int {
            return ["type": "integer"]
        }
        if value is Double || value is Float {
            return ["type": "number"]
        }

        return ["type": "string"]
    }

    private nonisolated static func inferredSchemaProperty(fromDescription description: String) -> [String: Any] {
        let lowercased = description.lowercased()
        var schema: [String: Any]

        if lowercased.contains("bool") || lowercased.contains("true") || lowercased.contains("false") {
            schema = ["type": "boolean"]
        } else if lowercased.contains("integer") || lowercased.contains("int") {
            schema = ["type": "integer"]
        } else if lowercased.contains("number") || lowercased.contains("float") || lowercased.contains("double") {
            schema = ["type": "number"]
        } else {
            schema = ["type": "string"]
        }

        if lowercased.contains("yyyy") || lowercased.contains("date") {
            schema["format"] = "date"
        }
        if description.contains("|") {
            let values = description
                .replacingOccurrences(of: " optional", with: "", options: [.caseInsensitive])
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.contains(" ") }
            if !values.isEmpty {
                schema["enum"] = values
            }
        }
        if lowercased.contains("optional") || lowercased != "string" {
            schema["description"] = description
        }
        return schema
    }

    private nonisolated static func isRequiredShorthandValue(_ value: Any) -> Bool {
        guard let string = value as? String else {
            return !(value is NSNull)
        }
        return !string.lowercased().contains("optional")
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
                    var accumulatedReasoningContent = ""
                    var toolCallAccumulator = OpenAICompatibleStreamingToolCallAccumulator()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else {
                            continue
                        }
                        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                        if payload == "[DONE]" {
                            break
                        }
                        guard let data = payload.data(using: .utf8) else {
                            continue
                        }
                        toolCallAccumulator.mergeDelta(from: data)
                        if let reasoningDelta = OpenAICompatibleStreamDeltaParser.reasoningContentDelta(from: data), !reasoningDelta.isEmpty {
                            accumulatedReasoningContent += reasoningDelta
                        }
                        guard let delta = OpenAICompatibleStreamDeltaParser.contentDelta(from: data), !delta.isEmpty else {
                            continue
                        }
                        accumulated += delta
                        continuation.yield(.messageDelta(delta))
                    }

                    let toolCalls = toolCallAccumulator.toolCalls()
                    continuation.yield(.completed(LLMProviderResponse(
                        message: LLMChatMessage(
                            role: .assistant,
                            content: accumulated,
                            reasoningContent: accumulatedReasoningContent.nilIfEmpty,
                            toolCalls: toolCalls
                        ),
                        toolCalls: toolCalls,
                        rawResponse: accumulated
                    )))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
