import Foundation
import Testing
@testable import SciStationCore

@Suite("Core behavior")
struct CoreBehaviorTests {
    @Test("Workspace paths normalize safe separators")
    func workspacePathNormalization() throws {
        let path = try WorkspaceRelativePath("projects\\demo/notes.md")
        #expect(path.rawValue == "projects/demo/notes.md")
    }

    @Test("Workspace paths reject traversal")
    func workspacePathTraversalIsRejected() {
        #expect(throws: WorkspaceFileSystemError.self) {
            try WorkspaceRelativePath("projects/../../Secrets")
        }
        #expect(throws: WorkspaceFileSystemError.self) {
            try Paper.directoryRelativePath(for: "paper-id", collectionPath: "../../Outside")
        }
    }

    @Test("Identifier parser normalizes DOI and arXiv versions")
    func identifierNormalization() {
        let parser = IdentifierParser()
        #expect(parser.parse("https://doi.org/10.1000/ABC.123").normalizedValue == "10.1000/abc.123")

        let detected = parser.detectPaperIdentifiers(in: "arXiv:2101.12345v3")
        #expect(detected.arxiv == "2101.12345")
        #expect(detected.arxivVersion == "3")
    }

    @Test("Batch imports preserve order while removing duplicates")
    func batchImportDeduplication() {
        let values = BatchImportInputParser().parse("alpha, beta\nalpha;gamma")
        #expect(values == ["alpha", "beta", "gamma"])
    }

    @Test("Responsive buckets cover compact Apple Silicon windows")
    func responsiveBuckets() {
        #expect(ResponsiveShellPolicy.bucket(for: 700) == .narrow)
        #expect(ResponsiveShellPolicy.bucket(for: 800) == .compact)
        #expect(ResponsiveShellPolicy.bucket(for: 1100) == .regular)
        #expect(ResponsiveShellPolicy.bucket(for: 1500) == .expanded)
        #expect(ResponsiveShellPolicy.homeWidgetColumns(for: 700) == 1)
        #expect(ResponsiveShellPolicy.homeWidgetColumns(for: 800) == 2)
    }

    @Test("Starting a workspace session cancels the previous generation")
    func workspaceSessionCancellation() async throws {
        let coordinator = WorkspaceSessionCoordinator()
        var completed: [UInt64] = []

        coordinator.start { generation in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, coordinator.isCurrent(generation) else { return }
            completed.append(generation)
        }
        coordinator.start { generation in
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled, coordinator.isCurrent(generation) else { return }
            completed.append(generation)
        }

        try await Task.sleep(for: .milliseconds(120))
        #expect(completed.count == 1)
        #expect(completed.first == 2)
    }
}
