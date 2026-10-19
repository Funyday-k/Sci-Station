import Foundation
import Testing
@testable import SciStationCore

@Suite("Agent loop")
struct AgentLoopTests {
    @Test("Agent loop budget defaults are expanded")
    func agentLoopBudgetDefaultsAreExpanded() throws {
        let options = AgentLoopOptions()
        try #require(options.maxSteps == 20, "Agent loop should default to 20 model steps.")
        try #require(options.maxToolCalls == 80, "Agent loop should default to a larger tool-call budget.")
        try #require(options.maxContextCharacters == 1_000_000, "Agent loop should default to a 1M context character budget.")
        try #require(options.maxToolResultCharactersPerCall == 384_000, "Agent loop should default to a 384K per-tool output budget.")
        try #require(options.maxAccumulatedToolResultCharacters == 1_000_000, "Agent loop should default to a 1M accumulated tool-result budget.")
        try #require(LLMConfiguration().maxTokens == 384_000, "LLM output should default to 384K max tokens for DeepSeek-class models.")
    }

    @Test("LLM request builds expected payload")
    func llmRequestBuildsExpectedPayload() throws {
        let provider = OpenAICompatibleProvider()
        let configuration = LLMConfiguration(
            provider: .openAICompatible,
            baseURLString: "https://api.example.com/v1",
            model: "test-model",
            temperature: 0.3,
            maxTokens: 256
        )

        let request = try provider.buildRequest(configuration: configuration, apiKey: "secret-key", prompt: "Summarize this paper")
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) }, "Expected request body to be encoded.")
        try #require(request.url?.absoluteString == "https://api.example.com/v1/chat/completions", "Provider should target /chat/completions on the configured base URL.")
        try #require(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key", "Provider should attach the API key as a bearer token.")
        try #require(body.contains("test-model"), "Provider request body should contain the configured model.")
        try #require(body.contains("Summarize this paper"), "Provider request body should contain the prompt content.")
    }
}
