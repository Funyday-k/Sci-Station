import Foundation

public actor AgentRunLogger {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func append(_ run: AgentRun, in workspace: ResearchWorkspace) throws {
        try append(run, logURL: workspace.fileURL(for: ".sci-station/agent/runs.jsonl"))
    }

    public func append(_ run: AgentRun, in root: ResearchRoot) throws {
        try append(run, logURL: root.fileURL(for: ".sci-station/agent/runs.jsonl"))
    }

    private func append(_ run: AgentRun, logURL: URL) throws {
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(run)
        guard let line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }

        if fileManager.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}