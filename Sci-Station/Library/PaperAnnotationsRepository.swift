import Foundation

public actor PaperAnnotationsRepository {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadAnnotations(for paper: Paper, in workspace: ResearchWorkspace) throws -> String {
        let fileURL = paper.annotationsURL(in: workspace)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ""
        }

        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    public func saveAnnotations(_ contents: String, for paper: Paper, in workspace: ResearchWorkspace) throws {
        let fileURL = paper.annotationsURL(in: workspace)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
