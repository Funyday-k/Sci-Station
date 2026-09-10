import Foundation
import CoreGraphics
import SciStationCore

struct ValidationError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

extension AgentRuntimeEvent {
    var isSidecarStarting: Bool {
        if case .sidecarStarting = self { return true }
        return false
    }

    var isSidecarUnavailable: Bool {
        if case .sidecarUnavailable = self { return true }
        return false
    }

    var isFallbackToLegacyRuntime: Bool {
        if case .fallbackToLegacyRuntime = self { return true }
        return false
    }
}

struct StaticLLMProvider: LLMProvider {
    let response: String

    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        response
    }
}

actor ScriptedChatProvider: LLMProvider, LLMChatProvider {
    private var responses: [LLMProviderResponse]
    private var requests: [LLMProviderRequest] = []

    init(responses: [LLMProviderResponse]) {
        self.responses = responses
    }

    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        responses.first?.message.content ?? ""
    }

    func respond(to request: LLMProviderRequest, configuration: LLMConfiguration, apiKey: String) async throws -> LLMProviderResponse {
        requests.append(request)
        if responses.count > 1 {
            return responses.removeFirst()
        }
        if let response = responses.first {
            return response
        }
        return LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: ""))
    }

    func recordedRequests() -> [LLMProviderRequest] {
        requests
    }
}

actor ScriptedFailingChatProvider: LLMProvider, LLMChatProvider {
    private var steps: [Result<LLMProviderResponse, LLMProviderError>]
    private var requests: [LLMProviderRequest] = []

    init(steps: [Result<LLMProviderResponse, LLMProviderError>]) {
        self.steps = steps
    }

    func complete(prompt: String, configuration: LLMConfiguration, apiKey: String) async throws -> String {
        guard let first = steps.first else {
            return ""
        }
        switch first {
        case let .success(response):
            return response.message.content
        case let .failure(error):
            throw error
        }
    }

    func respond(to request: LLMProviderRequest, configuration: LLMConfiguration, apiKey: String) async throws -> LLMProviderResponse {
        requests.append(request)
        guard !steps.isEmpty else {
            return LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: ""))
        }
        let step = steps.removeFirst()
        switch step {
        case let .success(response):
            return response
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [LLMProviderRequest] {
        requests
    }
}

actor RecordingAgentTool: AgentTool {
    nonisolated let definition: AgentToolDefinition
    private var results: [AgentToolResult]
    private var argumentsLog: [String] = []

    init(definition: AgentToolDefinition, results: [AgentToolResult]) {
        self.definition = definition
        self.results = results
    }

    func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        argumentsLog.append(argumentsJSON)
        if results.count > 1 {
            return results.removeFirst()
        }
        if let result = results.first {
            return result
        }
        return AgentToolResult(callID: "", toolName: definition.name, succeeded: true, message: "Recorded tool result.")
    }

    func invocationCount() -> Int {
        argumentsLog.count
    }

    func invokedArguments() -> [String] {
        argumentsLog
    }
}

actor RecordingPaperImporter: PaperImporter {
    nonisolated let contribution = ImporterContribution(id: "test.importer", title: "Test Importer", inputKinds: ["doi"])
    private var values: [String] = []

    nonisolated func canHandle(_ input: PaperImportInput) -> Bool {
        input.kind == .doi
    }

    func importPaper(_ input: PaperImportInput, context: PluginContext) async throws -> PaperImportResult {
        values.append(input.value)
        let draft = PaperMetadataDraft(
            title: "Imported Paper",
            authors: ["Test Author"],
            year: 2026,
            venue: nil,
            doi: input.value,
            arxiv: nil,
            inspireID: nil,
            url: nil,
            pdfURL: nil,
            abstract: nil,
            categories: [],
            sourceProvider: context.pluginID
        )
        return PaperImportResult(paperID: "paper:\(input.value)", metadata: draft)
    }

    func handledValues() -> [String] {
        values
    }
}

actor RecordingPaperMetadataProvider: PaperMetadataProviderPlugin {
    nonisolated let contribution = MetadataProviderContribution(id: "test.metadata", title: "Test Metadata", supportedIdentifiers: ["doi"])
    private var values: [String] = []

    func lookup(_ query: MetadataLookupQuery, context: PluginContext) async throws -> [PaperMetadataCandidate] {
        values.append(query.value)
        let draft = PaperMetadataDraft(
            title: "Metadata Candidate",
            authors: ["Provider Author"],
            year: 2026,
            venue: nil,
            doi: query.value,
            arxiv: nil,
            inspireID: nil,
            url: nil,
            pdfURL: nil,
            abstract: nil,
            categories: [],
            sourceProvider: context.pluginID
        )
        return [PaperMetadataCandidate(draft: draft, providerID: contribution.id)]
    }

    func lookupValues() -> [String] {
        values
    }
}

final class MinerUAPIMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var zipData = Data()
    nonisolated(unsafe) static var requestLog: [String] = []
    nonisolated(unsafe) static var uploadContentTypeHeaders: [String?] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let method = request.httpMethod ?? "GET"
        let host = url.host ?? ""
        let requestKey = "\(method) \(host)\(url.path)"
        Self.requestLog.append(requestKey)

        let statusCode: Int
        let contentType: String
        let data: Data

        switch requestKey {
        case "POST mineru.test/api/v4/file-urls/batch":
            statusCode = 200
            contentType = "application/json"
            data = Data(
                """
                {
                  "code": 0,
                  "msg": "ok",
                  "data": {
                    "batch_id": "batch-1",
                    "file_urls": ["https://upload.test/upload/mineru-images-paper.pdf"]
                  }
                }
                """.utf8
            )
        case "PUT upload.test/upload/mineru-images-paper.pdf":
            Self.uploadContentTypeHeaders.append(request.value(forHTTPHeaderField: "Content-Type"))
            statusCode = request.value(forHTTPHeaderField: "Content-Type") == nil ? 204 : 415
            contentType = "text/plain"
            data = Data()
        case "GET mineru.test/api/v4/extract-results/batch/batch-1":
            statusCode = 200
            contentType = "application/json"
            data = Data(
                """
                {
                  "code": 0,
                  "msg": "ok",
                  "data": {
                    "extract_result": [
                      {
                        "file_name": "mineru-images-paper.pdf",
                        "data_id": "mineru-images-paper",
                        "state": "done",
                        "full_zip_url": "https://download.test/mineru.zip"
                      }
                    ]
                  }
                }
                """.utf8
            )
        case "GET download.test/mineru.zip":
            statusCode = 200
            contentType = "application/zip"
            data = Self.zipData
        default:
            statusCode = 404
            contentType = "text/plain"
            data = Data("not found: \(requestKey)".utf8)
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class RemoteMCPMockURLProtocol: URLProtocol {
    enum FailureMode: Equatable {
        case none
        case httpStatus(Int)
    }

    nonisolated(unsafe) static var methods: [String] = []
    nonisolated(unsafe) static var authorizationHeaders: [String?] = []
    nonisolated(unsafe) static var failureMode: FailureMode = .none

    static func reset() {
        methods = []
        authorizationHeaders = []
        failureMode = .none
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let bodyData = Self.requestBodyData(from: request)
        let body = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) as? [String: Any] } ?? [:]
        let method = body["method"] as? String ?? "unknown"
        Self.methods.append(method)
        Self.authorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization"))

        if case let .httpStatus(statusCode) = Self.failureMode {
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let data = Data(#"{"error":"mock remote MCP failure"}"#.utf8)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let idValue = body["id"] as? String
        let data: Data
        let statusCode = 200
        let contentType = request.value(forHTTPHeaderField: "Accept")?.contains("text/event-stream") == true
            ? "text/event-stream"
            : "application/json"

        switch method {
        case "initialize":
            data = Self.responseData(
                id: idValue,
                result: [
                    "protocolVersion": "2025-06-18",
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "remote-mcp", "version": "1.0.0"]
                ],
                contentType: contentType
            )
        case "notifications/initialized":
            data = Data()
        case "ping":
            data = Self.responseData(id: idValue, result: [:], contentType: contentType)
        case "tools/list":
            data = Self.responseData(
                id: idValue,
                result: [
                    "tools": [[
                        "name": "lookup",
                        "title": "Remote Lookup",
                        "description": "Lookup remote indexed evidence.",
                        "inputSchema": [
                            "type": "object",
                            "properties": ["query": ["type": "string"]]
                        ]
                    ]]
                ],
                contentType: contentType
            )
        case "tools/call":
            let params = body["params"] as? [String: Any]
            let arguments = params?["arguments"] as? [String: Any]
            let query = arguments?["query"] as? String ?? ""
            data = Self.responseData(
                id: idValue,
                result: [
                    "content": [[
                        "type": "text",
                        "text": "remote:\(query)"
                    ]],
                    "structuredContent": ["query": query],
                    "isError": false
                ],
                contentType: contentType
            )
        default:
            data = Self.responseData(
                id: idValue,
                error: ["code": -32601, "message": "Unsupported mock MCP method \(method)."],
                contentType: contentType
            )
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func responseData(
        id: String?,
        result: Any? = nil,
        error: [String: Any]? = nil,
        contentType: String
    ) -> Data {
        var object: [String: Any] = ["jsonrpc": "2.0"]
        if let id {
            object["id"] = id
        }
        if let error {
            object["error"] = error
        } else {
            object["result"] = result ?? [:]
        }
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard contentType.contains("text/event-stream"),
              let json = String(data: data, encoding: .utf8) else {
            return data
        }
        return Data("event: message\ndata: \(json)\n\n".utf8)
    }

    private static func requestBodyData(from request: URLRequest) -> Data? {
        if let data = request.httpBody {
            return data
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            if readCount > 0 {
                data.append(buffer, count: readCount)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}
