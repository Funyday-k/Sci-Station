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

    public func recentRuns(in workspace: ResearchWorkspace, limit: Int = 5) throws -> [AgentRun] {
        try recentRuns(logURL: workspace.fileURL(for: ".sci-station/agent/runs.jsonl"), limit: limit)
    }

    public func recentRuns(in root: ResearchRoot, limit: Int = 5) throws -> [AgentRun] {
        try recentRuns(logURL: root.fileURL(for: ".sci-station/agent/runs.jsonl"), limit: limit)
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

    private func recentRuns(logURL: URL, limit: Int) throws -> [AgentRun] {
        guard limit > 0, fileManager.fileExists(atPath: logURL.path) else {
            return []
        }

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let validRuns = contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> AgentRun? in
                try? decoder.decode(AgentRun.self, from: Data(line.utf8))
            }

        return Array(validRuns.suffix(limit).reversed())
    }
}