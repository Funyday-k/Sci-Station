import Foundation

public nonisolated struct SidecarJSONRPCError: Codable, Hashable, Sendable, LocalizedError {
    public var code: Int
    public var message: String

    public nonisolated init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    public nonisolated var errorDescription: String? {
        message
    }
}

public nonisolated struct SidecarJSONRPCMessage: Codable, Hashable, Sendable {
    public var jsonrpc: String
    public var id: String?
    public var method: String?
    public var params: JSONValue?
    public var result: JSONValue?
    public var error: SidecarJSONRPCError?

    public nonisolated init(
        jsonrpc: String = "2.0",
        id: String? = nil,
        method: String? = nil,
        params: JSONValue? = nil,
        result: JSONValue? = nil,
        error: SidecarJSONRPCError? = nil
    ) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
        self.result = result
        self.error = error
    }
}

public nonisolated struct SidecarLaunchConfiguration: Hashable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectoryURL: URL?
    public var handshakeTimeout: TimeInterval
    public var requestTimeout: TimeInterval

    public nonisolated init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        arguments: [String] = ["python3", "-m", "sci_station_agent.main"],
        environment: [String: String] = [:],
        workingDirectoryURL: URL? = nil,
        handshakeTimeout: TimeInterval = 5,
        requestTimeout: TimeInterval = 30
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.workingDirectoryURL = workingDirectoryURL
        self.handshakeTimeout = handshakeTimeout
        self.requestTimeout = requestTimeout
    }
}

public nonisolated struct SidecarInitializationRequest: Codable, Hashable, Sendable {
    public var protocolVersion: String
    public var schemaVersion: Int
    public var appVersion: String
    public var workspaceRoot: String
    public var allowedRoots: [String]
    public var ignoredGlobs: [String]
    public var capabilities: [String: Bool]

    public nonisolated init(
        protocolVersion: String = "1.0",
        schemaVersion: Int = 1,
        appVersion: String = "0.x",
        workspaceRoot: String,
        allowedRoots: [String],
        ignoredGlobs: [String] = ["**/.git/**", "**/.sci-station/agent/runs/**", "**/node_modules/**", "**/.venv/**"],
        capabilities: [String: Bool] = [
            "llmProxy": true,
            "mcpGateway": true,
            "approvalResume": true,
            "ftsIndex": true
        ]
    ) {
        self.protocolVersion = protocolVersion
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.workspaceRoot = workspaceRoot
        self.allowedRoots = allowedRoots
        self.ignoredGlobs = ignoredGlobs
        self.capabilities = capabilities
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case schemaVersion
        case appVersion
        case workspaceRoot
        case allowedRoots
        case ignoredGlobs
        case capabilities
    }
}

public nonisolated struct SidecarInitializedResponse: Codable, Hashable, Sendable {
    public var protocolVersion: String
    public var schemaVersion: Int
    public var sidecarVersion: String
    public var capabilities: [String: Bool]
    public var dependencies: [String: Bool]
    public var workspaceAccepted: Bool

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case schemaVersion
        case sidecarVersion
        case capabilities
        case dependencies
        case workspaceAccepted
    }
}

public nonisolated struct SidecarHealth: Codable, Hashable, Sendable {
    public var status: String
    public var protocolVersion: String?
    public var schemaVersion: Int?
    public var sidecarVersion: String?
    public var dependencies: [String: Bool]

    public nonisolated init(
        status: String,
        protocolVersion: String? = nil,
        schemaVersion: Int? = nil,
        sidecarVersion: String? = nil,
        dependencies: [String: Bool] = [:]
    ) {
        self.status = status
        self.protocolVersion = protocolVersion
        self.schemaVersion = schemaVersion
        self.sidecarVersion = sidecarVersion
        self.dependencies = dependencies
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case protocolVersion
        case schemaVersion
        case sidecarVersion
        case dependencies
    }
}

public nonisolated enum SidecarJSONCodec {
    public nonisolated static func jsonValue<T: Encodable>(from value: T) throws -> JSONValue {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONValue.fromJSONObject(object)
    }

    public nonisolated static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue?) throws -> T {
        guard let value else {
            throw SidecarJSONRPCError(code: -32602, message: "Missing JSON-RPC value.")
        }
        let data = try encoder.encode(value)
        return try decoder.decode(T.self, from: data)
    }

    public nonisolated static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public actor SidecarConnection {
    public typealias HostRequestHandler = @Sendable (String, JSONValue?) async throws -> JSONValue
    public typealias NotificationHandler = @Sendable (String, JSONValue?) async -> Void
    public typealias TerminationHandler = @Sendable (Int32) async -> Void

    private let process: Process
    private let inputHandle: FileHandle
    private let outputHandle: FileHandle
    private let errorHandle: FileHandle
    private var requestCounter: Int = 0
    private var readBuffer = Data()
    private var isDrainingOutput = false
    private var stderrBuffer = Data()
    private var pendingResponses: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var hostRequestHandler: HostRequestHandler?
    private var notificationHandler: NotificationHandler?
    private var terminationHandler: TerminationHandler?

    public init(
        process: Process,
        inputHandle: FileHandle,
        outputHandle: FileHandle,
        errorHandle: FileHandle,
        hostRequestHandler: HostRequestHandler? = nil,
        notificationHandler: NotificationHandler? = nil,
        terminationHandler: TerminationHandler? = nil
    ) {
        self.process = process
        self.inputHandle = inputHandle
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
        self.hostRequestHandler = hostRequestHandler
        self.notificationHandler = notificationHandler
        self.terminationHandler = terminationHandler
    }

    public func updateHandlers(
        hostRequestHandler: HostRequestHandler? = nil,
        notificationHandler: NotificationHandler? = nil,
        terminationHandler: TerminationHandler? = nil
    ) {
        if let hostRequestHandler {
            self.hostRequestHandler = hostRequestHandler
        }
        if let notificationHandler {
            self.notificationHandler = notificationHandler
        }
        if let terminationHandler {
            self.terminationHandler = terminationHandler
        }
    }

    public func startReading() {
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.consumeOutput(data) }
        }
        errorHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.consumeError(data) }
        }
    }

    public func stop() {
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        try? inputHandle.close()
        try? outputHandle.close()
        try? errorHandle.close()
    }

    public func isRunning() -> Bool {
        process.isRunning
    }

    public func stderrText() -> String {
        String(data: stderrBuffer, encoding: .utf8) ?? ""
    }

    public func processTerminated(exitCode: Int32) async {
        for continuation in pendingResponses.values {
            continuation.resume(throwing: SidecarJSONRPCError(code: -32001, message: "Sidecar process exited with status \(exitCode)."))
        }
        pendingResponses.removeAll()
        if exitCode != 0, let terminationHandler {
            await terminationHandler(exitCode)
        }
    }

    public func sendRequest(method: String, params: JSONValue? = nil, timeout: TimeInterval) async throws -> JSONValue {
        requestCounter += 1
        let id = "swift-\(requestCounter)-\(UUID().uuidString.lowercased())"
        return try await withThrowingTaskGroup(of: JSONValue.self) { group in
            group.addTask { try await self.performRequest(id: id, method: method, params: params) }
            if timeout > 0 {
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    await self.failPendingResponse(id: id, error: SidecarJSONRPCError(code: -32000, message: "Sidecar request timed out: \(method)"))
                    throw SidecarJSONRPCError(code: -32000, message: "Sidecar request timed out: \(method)")
                }
            }
            guard let result = try await group.next() else {
                throw SidecarJSONRPCError(code: -32002, message: "Sidecar request finished without a response.")
            }
            group.cancelAll()
            return result
        }
    }

    private func performRequest(id: String, method: String, params: JSONValue?) async throws -> JSONValue {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
            pendingResponses[id] = continuation
            do {
                try writeMessage(SidecarJSONRPCMessage(id: id, method: method, params: params))
            } catch {
                pendingResponses.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func failPendingResponse(id: String, error: Error) {
        pendingResponses.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func consumeOutput(_ data: Data) async {
        readBuffer.append(data)
        guard !isDrainingOutput else { return }
        isDrainingOutput = true
        defer { isDrainingOutput = false }
        while let newlineIndex = readBuffer.firstIndex(of: 10) {
            let line = readBuffer[..<newlineIndex]
            readBuffer.removeSubrange(readBuffer.startIndex...newlineIndex)
            guard !line.isEmpty else { continue }
            do {
                let message = try decodeMessage(from: Data(line))
                await handleMessage(message)
            } catch {
                continue
            }
        }
    }

    private func consumeError(_ data: Data) {
        stderrBuffer.append(data)
        if stderrBuffer.count > 64_000 {
            stderrBuffer.removeFirst(stderrBuffer.count - 64_000)
        }
    }

    private func handleMessage(_ message: SidecarJSONRPCMessage) async {
        if let id = message.id, message.method == nil {
            if let error = message.error {
                pendingResponses.removeValue(forKey: id)?.resume(throwing: error)
            } else {
                pendingResponses.removeValue(forKey: id)?.resume(returning: message.result ?? .object([:]))
            }
            return
        }

        guard let method = message.method else {
            return
        }
        if let id = message.id {
            let params = message.params
            guard let hostRequestHandler else {
                sendErrorResponse(id: id, code: -32601, message: "No Swift host handler registered for \(method).")
                return
            }
            Task {
                do {
                    let result = try await hostRequestHandler(method, params)
                    self.sendResponse(id: id, result: result)
                } catch {
                    self.sendErrorResponse(id: id, code: -32603, message: error.localizedDescription)
                }
            }
        } else {
            let params = message.params
            if let notificationHandler {
                await notificationHandler(method, params)
            }
        }
    }

    private func decodeMessage(from data: Data) throws -> SidecarJSONRPCMessage {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let dictionary = object as? [String: Any] else {
            throw SidecarJSONRPCError(code: -32700, message: "JSON-RPC message must be an object.")
        }
        let error: SidecarJSONRPCError?
        if let errorObject = dictionary["error"] as? [String: Any] {
            let code = (errorObject["code"] as? NSNumber)?.intValue ?? -32603
            let message = errorObject["message"] as? String ?? "Sidecar request failed."
            error = SidecarJSONRPCError(code: code, message: message)
        } else {
            error = nil
        }
        return try SidecarJSONRPCMessage(
            jsonrpc: dictionary["jsonrpc"] as? String ?? "2.0",
            id: dictionary["id"].flatMap { value in
                if value is NSNull { return nil }
                if let string = value as? String { return string }
                if let number = value as? NSNumber { return number.stringValue }
                return nil
            },
            method: dictionary["method"] as? String,
            params: dictionary["params"].map(JSONValue.fromJSONObject),
            result: dictionary["result"].map(JSONValue.fromJSONObject),
            error: error
        )
    }

    private func sendResponse(id: String, result: JSONValue) {
        try? writeMessage(SidecarJSONRPCMessage(id: id, result: result))
    }

    private func sendErrorResponse(id: String, code: Int, message: String) {
        try? writeMessage(SidecarJSONRPCMessage(id: id, error: SidecarJSONRPCError(code: code, message: message)))
    }

    private func writeMessage(_ message: SidecarJSONRPCMessage) throws {
        let data = try SidecarJSONCodec.encoder.encode(message)
        guard var line = String(data: data, encoding: .utf8) else {
            throw SidecarJSONRPCError(code: -32603, message: "Could not encode JSON-RPC message.")
        }
        line.append("\n")
        try inputHandle.write(contentsOf: Data(line.utf8))
    }
}

public actor SidecarProcessSupervisor {
    private let configuration: SidecarLaunchConfiguration
    private var connection: SidecarConnection?

    public init(configuration: SidecarLaunchConfiguration = SidecarLaunchConfiguration()) {
        self.configuration = configuration
    }

    public func start(
        initialization: SidecarInitializationRequest,
        hostRequestHandler: SidecarConnection.HostRequestHandler? = nil,
        notificationHandler: SidecarConnection.NotificationHandler? = nil,
        terminationHandler: SidecarConnection.TerminationHandler? = nil
    ) async throws -> SidecarConnection {
        try await stop()

        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        process.currentDirectoryURL = configuration.workingDirectoryURL
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in configuration.environment {
            environment[key] = value
        }
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let sidecarConnection = SidecarConnection(
            process: process,
            inputHandle: inputPipe.fileHandleForWriting,
            outputHandle: outputPipe.fileHandleForReading,
            errorHandle: errorPipe.fileHandleForReading,
            hostRequestHandler: hostRequestHandler,
            notificationHandler: notificationHandler,
            terminationHandler: terminationHandler
        )
        process.terminationHandler = { process in
            Task { await sidecarConnection.processTerminated(exitCode: process.terminationStatus) }
        }

        try process.run()
        await sidecarConnection.startReading()
        connection = sidecarConnection

        do {
            let initializedValue = try await sidecarConnection.sendRequest(
                method: "sidecar.initialize",
                params: try SidecarJSONCodec.jsonValue(from: initialization),
                timeout: configuration.handshakeTimeout
            )
            let initialized = try SidecarJSONCodec.decode(SidecarInitializedResponse.self, from: initializedValue)
            guard initialized.protocolVersion == initialization.protocolVersion, initialized.schemaVersion == initialization.schemaVersion else {
                await sidecarConnection.stop()
                connection = nil
                throw SidecarJSONRPCError(code: -32010, message: "Sidecar protocol/schema mismatch.")
            }

            let healthValue = try await sidecarConnection.sendRequest(method: "sidecar.health", params: .object([:]), timeout: configuration.handshakeTimeout)
            let health = try SidecarJSONCodec.decode(SidecarHealth.self, from: healthValue)
            guard health.status == "ready" else {
                await sidecarConnection.stop()
                connection = nil
                throw SidecarJSONRPCError(code: -32011, message: "Sidecar health check did not become ready.")
            }
            return sidecarConnection
        } catch {
            await sidecarConnection.stop()
            connection = nil
            throw error
        }
    }

    public func stop() async throws {
        if let connection {
            await connection.stop()
            self.connection = nil
        }
    }

    public func restart(
        initialization: SidecarInitializationRequest,
        hostRequestHandler: SidecarConnection.HostRequestHandler? = nil,
        notificationHandler: SidecarConnection.NotificationHandler? = nil,
        terminationHandler: SidecarConnection.TerminationHandler? = nil
    ) async throws -> SidecarConnection {
        try await stop()
        return try await start(
            initialization: initialization,
            hostRequestHandler: hostRequestHandler,
            notificationHandler: notificationHandler,
            terminationHandler: terminationHandler
        )
    }

    public func health() async -> SidecarHealth {
        guard let connection else {
            return SidecarHealth(status: "unavailable")
        }
        do {
            let value = try await connection.sendRequest(method: "sidecar.health", params: .object([:]), timeout: configuration.requestTimeout)
            return try SidecarJSONCodec.decode(SidecarHealth.self, from: value)
        } catch {
            return SidecarHealth(status: "unavailable")
        }
    }
}