#if DEBUG
import Darwin
import Foundation

nonisolated struct UITestBridgeConfiguration: Sendable {
    let socketURL: URL

    static func fromProcessInfo(_ processInfo: ProcessInfo = .processInfo) -> UITestBridgeConfiguration? {
        let arguments = processInfo.arguments
        let environment = processInfo.environment
        guard arguments.contains("--uitest-bridge") || environment["SCI_STATION_TEST_BRIDGE_SOCKET"] != nil else {
            return nil
        }
        if let value = environment["SCI_STATION_TEST_BRIDGE_SOCKET"], !value.isEmpty {
            return UITestBridgeConfiguration(socketURL: URL(fileURLWithPath: value))
        }
        if let index = arguments.firstIndex(of: "--uitest-bridge-socket"), arguments.indices.contains(arguments.index(after: index)) {
            return UITestBridgeConfiguration(socketURL: URL(fileURLWithPath: arguments[arguments.index(after: index)]))
        }
        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("sci-station-uitest-\(getuid()).sock", isDirectory: false)
        return UITestBridgeConfiguration(socketURL: fallback)
    }
}

nonisolated struct UITestBridgeCommand: Sendable {
    let name: String
    let args: [String: JSONValue]
}

nonisolated struct UITestBridgeCommandResult: Sendable {
    var fields: [String: JSONValue] = [:]
}

nonisolated enum UITestBridgeServerError: LocalizedError {
    case socketPathTooLong(String)
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case invalidRequest
    case unknownCommand(String)

    var errorDescription: String? {
        switch self {
        case .socketPathTooLong(let path):
            return "UI test bridge socket path is too long: \(path)"
        case .socketFailed(let code):
            return "UI test bridge socket() failed with errno \(code)."
        case .bindFailed(let code):
            return "UI test bridge bind() failed with errno \(code)."
        case .listenFailed(let code):
            return "UI test bridge listen() failed with errno \(code)."
        case .invalidRequest:
            return "Invalid UI test bridge request."
        case .unknownCommand(let command):
            return "Unknown UI test bridge command: \(command)"
        }
    }
}

nonisolated final class UITestBridgeServer: @unchecked Sendable {
    let socketURL: URL

    private let handler: @MainActor @Sendable (UITestBridgeCommand) async throws -> UITestBridgeCommandResult
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var acceptTask: Task<Void, Never>?

    init(
        socketURL: URL,
        handler: @escaping @MainActor @Sendable (UITestBridgeCommand) async throws -> UITestBridgeCommandResult
    ) {
        self.socketURL = socketURL
        self.handler = handler
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        if listenFD >= 0 {
            return
        }

        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: socketURL.path) {
            try? FileManager.default.removeItem(at: socketURL)
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UITestBridgeServerError.socketFailed(errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd)
            throw UITestBridgeServerError.socketPathTooLong(path)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            _ = path.withCString { pointer in
                buffer.baseAddress?.copyMemory(from: pointer, byteCount: path.utf8.count)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            Darwin.close(fd)
            throw UITestBridgeServerError.bindFailed(code)
        }

        guard Darwin.listen(fd, 8) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw UITestBridgeServerError.listenFailed(code)
        }

        listenFD = fd
        acceptTask = Task.detached(priority: .utility) { [weak self] in
            await self?.acceptLoop(fd: fd)
        }
    }

    func stop() {
        lock.lock()
        let fd = listenFD
        listenFD = -1
        let task = acceptTask
        acceptTask = nil
        lock.unlock()

        task?.cancel()
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
        try? FileManager.default.removeItem(at: socketURL)
    }

    private func acceptLoop(fd: Int32) async {
        while !Task.isCancelled {
            let clientFD = Darwin.accept(fd, nil, nil)
            if clientFD < 0 {
                if errno == EBADF || errno == EINVAL || Task.isCancelled {
                    break
                }
                continue
            }
            await handleClient(fd: clientFD)
        }
    }

    private func handleClient(fd: Int32) async {
        defer { Darwin.close(fd) }
        guard let line = readLine(fd: fd), let data = line.data(using: .utf8) else {
            writeResponse(["ok": JSONValue.bool(false), "error": .string(UITestBridgeServerError.invalidRequest.localizedDescription)], fd: fd)
            return
        }
        do {
            let json = try JSONDecoder().decode(UITestBridgeWireRequest.self, from: data)
            let command = UITestBridgeCommand(name: json.command, args: json.args ?? [:])
            let result = try await handler(command)
            writeResponse(["ok": .bool(true), "result": .object(result.fields)], fd: fd)
        } catch {
            writeResponse(["ok": .bool(false), "error": .string(error.localizedDescription)], fd: fd)
        }
    }

    private func readLine(fd: Int32) -> String? {
        var data = Data()
        var byte: UInt8 = 0
        while data.count < 1_048_576 {
            let count = Darwin.recv(fd, &byte, 1, 0)
            if count <= 0 {
                break
            }
            if byte == 0x0A {
                break
            }
            data.append(byte)
        }
        guard !data.isEmpty else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func writeResponse(_ object: [String: JSONValue], fd: Int32) {
        do {
            let data = try JSONEncoder().encode(object)
            _ = data.withUnsafeBytes { buffer in
                Darwin.send(fd, buffer.baseAddress, data.count, 0)
            }
            var newline: UInt8 = 0x0A
            _ = Darwin.send(fd, &newline, 1, 0)
        } catch {
            let fallback = "{\"ok\":false,\"error\":\"response encoding failed\"}\n"
            _ = fallback.withCString { pointer in
                Darwin.send(fd, pointer, strlen(pointer), 0)
            }
        }
    }
}

private nonisolated struct UITestBridgeWireRequest: Decodable {
    let command: String
    let args: [String: JSONValue]?

    private enum CodingKeys: String, CodingKey {
        case command
        case cmd
        case args
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decodeIfPresent(String.self, forKey: .command)
            ?? container.decodeIfPresent(String.self, forKey: .cmd)
            ?? ""
        args = try container.decodeIfPresent([String: JSONValue].self, forKey: .args)
    }
}
#endif
