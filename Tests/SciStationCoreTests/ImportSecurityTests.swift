import CoreGraphics
import Foundation
import Testing
@testable import SciStationCore

@Suite("Import security")
struct ImportSecurityTests {
    @Test("PDF signature validation rejects disguised HTML")
    func pdfSignatureValidationRejectsHTML() throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("payload.pdf")
        try Data("<html>not a pdf</html>".utf8).write(to: fileURL)

        #expect(try DownloadService.hasPDFSignature(at: fileURL) == false)
    }

    @Test("HTTP validation rejects error responses and non-PDF MIME types")
    func httpValidationRejectsInvalidResponses() throws {
        let url = try #require(URL(string: "https://example.invalid/paper.pdf"))
        let missingResponse = URLResponse(
            url: url,
            mimeType: "application/pdf",
            expectedContentLength: 10,
            textEncodingName: nil
        )
        #expect(throws: PDFDownloadError.invalidHTTPResponse) {
            try DownloadService.validate(response: missingResponse, maximumDownloadBytes: 1_024)
        }

        let notFound = try #require(HTTPURLResponse(
            url: url,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/pdf"]
        ))
        #expect(throws: PDFDownloadError.httpStatus(404)) {
            try DownloadService.validate(response: notFound, maximumDownloadBytes: 1_024)
        }

        let html = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html", "Content-Length": "10"]
        ))
        #expect(throws: PDFDownloadError.unexpectedMIMEType("text/html")) {
            try DownloadService.validate(response: html, maximumDownloadBytes: 1_024)
        }
    }

    @Test("Invalid PDFs are rejected before workspace state is created")
    func invalidPDFDoesNotCreatePartialPaper() async throws {
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let workspaceURL = directoryURL.appendingPathComponent("Workspace", isDirectory: true)
        let sourceURL = directoryURL.appendingPathComponent("fake.pdf")
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Data("not a pdf".utf8).write(to: sourceURL)

        let workspace = ResearchWorkspace(rootURL: workspaceURL)
        let importer = PDFImportService(repository: PaperRepository())
        await #expect(throws: PDFImportError.self) {
            try await importer.importPDF(from: sourceURL, into: workspace, existingPapers: [])
        }

        #expect(!FileManager.default.fileExists(atPath: workspace.globalPapersURL.path))
        #expect(!FileManager.default.fileExists(
            atPath: workspaceURL.appendingPathComponent(".sci-station/import-staging").path
        ))
    }

    @Test("PDF import rolls back after paper metadata commit fails")
    func metadataCommitFailureRollsBackImport() async throws {
        try await assertImportRollsBack(when: .paperMetadata)
    }

    @Test("PDF import rolls back after project-link commit fails")
    func projectLinkCommitFailureRollsBackImport() async throws {
        try await assertImportRollsBack(when: .projectLinks)
    }

    @Test("PDF import rolls back after bibliography commit fails")
    func bibliographyCommitFailureRollsBackImport() async throws {
        try await assertImportRollsBack(when: .bibliography)
    }

    @Test("Failed PDF import preserves a concurrent successful import")
    func failedImportPreservesConcurrentCommit() async throws {
        let fileManager = FileManager.default
        let directoryURL = temporaryDirectory()
        defer { try? fileManager.removeItem(at: directoryURL) }

        let workspaceURL = directoryURL.appendingPathComponent("Workspace", isDirectory: true)
        let failingSourceURL = directoryURL.appendingPathComponent("failing.pdf", isDirectory: false)
        let successfulSourceURL = directoryURL.appendingPathComponent("successful.pdf", isDirectory: false)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try writeValidPDF(to: failingSourceURL)
        try writeValidPDF(to: successfulSourceURL)

        let workspace = ResearchWorkspace(rootURL: workspaceURL)
        try fileManager.createDirectory(
            at: workspace.projectPaperLinksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("links: []\n".utf8).write(to: workspace.projectPaperLinksURL, options: .atomic)
        try fileManager.createDirectory(
            at: workspace.globalLibraryBibURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("% concurrent-import-sentinel\n".utf8).write(
            to: workspace.globalLibraryBibURL,
            options: .atomic
        )

        let failingMetadata = metadataDraft(
            title: "Failing Concurrent Import",
            author: "Ada Lovelace"
        )
        let successfulMetadata = metadataDraft(
            title: "Successful Concurrent Import",
            author: "Grace Hopper"
        )
        let failingPaperID = PaperIdentityGenerator.paperID(
            title: failingMetadata.title,
            authors: failingMetadata.authors,
            year: failingMetadata.year,
            existing: []
        )
        let failingDirectoryURL = workspace.directoryURL(for: try Paper.directoryRelativePath(
            for: failingPaperID,
            collectionPath: "Uncategorized"
        ))
        let repository = PaperRepository(fileManager: fileManager)
        let barrier = CommitStageBarrier()
        let failingImporter = PDFImportService(
            fileManager: fileManager,
            repository: repository,
            commitStageHook: { committedStage in
                guard committedStage == .bibliography else {
                    return
                }
                await barrier.reachAndWait()
                throw InjectedCommitFailure(stage: committedStage)
            }
        )
        let successfulImporter = PDFImportService(fileManager: fileManager, repository: repository)

        let failingTask = Task {
            try await failingImporter.importPDF(
                from: failingSourceURL,
                into: workspace,
                existingPapers: [],
                metadataOverride: failingMetadata,
                projectIDs: ["project-failing"]
            )
        }

        await barrier.waitUntilReached()
        let successfulPaper = try await successfulImporter.importPDF(
            from: successfulSourceURL,
            into: workspace,
            existingPapers: [],
            metadataOverride: successfulMetadata,
            projectIDs: ["project-successful"]
        )
        await barrier.release()

        do {
            _ = try await failingTask.value
            Issue.record("Expected the concurrent import to fail at the bibliography hook.")
        } catch let error as PDFImportError {
            guard case .commitFailed = error else {
                Issue.record("Expected PDFImportError.commitFailed, got \(error).")
                return
            }
        } catch {
            Issue.record("Expected PDFImportError.commitFailed, got \(error).")
        }

        let loadedPapers = try await repository.loadPapers(in: workspace)
        #expect(loadedPapers.map(\.id) == [successfulPaper.id])
        #expect(!fileManager.fileExists(atPath: failingDirectoryURL.path))
        #expect(fileManager.fileExists(
            atPath: workspace.directoryURL(for: successfulPaper.paperDirectoryRelativePath).path
        ))

        let links = try await ProjectPaperLinkRepository(fileManager: fileManager).load(in: workspace)
        #expect(links.map(\.paperID) == [successfulPaper.id])
        #expect(links.map(\.projectID) == ["project-successful"])

        let bibliography = try String(contentsOf: workspace.globalLibraryBibURL, encoding: .utf8)
        let failingCitekey = PaperIdentityGenerator.citekey(
            title: failingMetadata.title,
            authors: failingMetadata.authors,
            year: failingMetadata.year,
            existing: []
        )
        #expect(!bibliography.contains("{\(failingCitekey),"))
        #expect(bibliography.contains("{\(successfulPaper.citekey),"))
        #expect(!fileManager.fileExists(
            atPath: workspaceURL.appendingPathComponent(".sci-station/import-staging").path
        ))
    }

    @Test("Staging-root cleanup failures are reported after rollback")
    func stagingRootCleanupFailureIsObservable() async throws {
        let fileManager = StagingCleanupFailingFileManager()
        let directoryURL = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let workspaceURL = directoryURL.appendingPathComponent("Workspace", isDirectory: true)
        let sourceURL = directoryURL.appendingPathComponent("cleanup-failure.pdf", isDirectory: false)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try writeValidPDF(to: sourceURL)

        let workspace = ResearchWorkspace(rootURL: workspaceURL)
        let stagingRootURL = workspaceURL.appendingPathComponent(
            ".sci-station/import-staging",
            isDirectory: true
        )
        fileManager.failingRemovalPath = stagingRootURL.path
        let metadata = metadataDraft(title: "Cleanup Failure Fixture", author: "Katherine Johnson")
        let paperID = PaperIdentityGenerator.paperID(
            title: metadata.title,
            authors: metadata.authors,
            year: metadata.year,
            existing: []
        )
        let paperDirectoryURL = workspace.directoryURL(for: try Paper.directoryRelativePath(
            for: paperID,
            collectionPath: "Uncategorized"
        ))
        let importer = PDFImportService(
            fileManager: fileManager,
            repository: PaperRepository(fileManager: fileManager)
        )

        do {
            _ = try await importer.importPDF(
                from: sourceURL,
                into: workspace,
                existingPapers: [],
                metadataOverride: metadata,
                projectIDs: ["project-cleanup"]
            )
            Issue.record("Expected staging-root cleanup to fail.")
        } catch let error as PDFImportError {
            guard case let .commitFailed(message) = error else {
                Issue.record("Expected PDFImportError.commitFailed, got \(error).")
                return
            }
            #expect(message.contains("staging-root cleanup failed"))
        } catch {
            Issue.record("Expected PDFImportError.commitFailed, got \(error).")
        }

        #expect(!fileManager.fileExists(atPath: paperDirectoryURL.path))
        #expect(!fileManager.fileExists(atPath: workspace.projectPaperLinksURL.path))
        #expect(!fileManager.fileExists(atPath: workspace.globalLibraryBibURL.path))
        #expect(fileManager.fileExists(atPath: stagingRootURL.path))
    }

    private func assertImportRollsBack(when failureStage: PDFImportCommitStage) async throws {
        let fileManager = FileManager.default
        let directoryURL = temporaryDirectory()
        defer { try? fileManager.removeItem(at: directoryURL) }

        let workspaceURL = directoryURL.appendingPathComponent("Workspace", isDirectory: true)
        let sourceURL = directoryURL.appendingPathComponent("rollback-fixture.pdf", isDirectory: false)
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try writeValidPDF(to: sourceURL)

        let workspace = ResearchWorkspace(rootURL: workspaceURL)
        let projectLinksSentinel = Data("links: []\n# project-links-sentinel\n".utf8)
        let bibliographySentinel = Data("% bibliography-sentinel\n".utf8)
        try fileManager.createDirectory(
            at: workspace.projectPaperLinksURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try projectLinksSentinel.write(to: workspace.projectPaperLinksURL, options: .atomic)
        try fileManager.createDirectory(
            at: workspace.globalLibraryBibURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bibliographySentinel.write(to: workspace.globalLibraryBibURL, options: .atomic)

        let metadata = metadataDraft(title: "Transactional Import Fixture", author: "Ada Lovelace")
        let expectedPaperID = PaperIdentityGenerator.paperID(
            title: metadata.title,
            authors: metadata.authors,
            year: metadata.year,
            existing: []
        )
        let expectedRelativePath = try Paper.directoryRelativePath(
            for: expectedPaperID,
            collectionPath: "Uncategorized"
        )
        let expectedPaperDirectoryURL = workspace.directoryURL(for: expectedRelativePath)
        let repository = PaperRepository(fileManager: fileManager)
        let importer = PDFImportService(
            fileManager: fileManager,
            repository: repository,
            commitStageHook: { committedStage in
                guard committedStage == failureStage else {
                    return
                }
                throw InjectedCommitFailure(stage: committedStage)
            }
        )

        do {
            _ = try await importer.importPDF(
                from: sourceURL,
                into: workspace,
                existingPapers: [],
                metadataOverride: metadata,
                projectIDs: ["project-1"]
            )
            Issue.record("Expected the injected \(failureStage) commit failure.")
        } catch let error as PDFImportError {
            guard case let .commitFailed(message) = error else {
                Issue.record("Expected PDFImportError.commitFailed, got \(error).")
                return
            }
            #expect(message.contains("Injected \(failureStage) commit failure"))
        } catch {
            Issue.record("Expected PDFImportError.commitFailed, got \(error).")
        }

        #expect(try Data(contentsOf: workspace.projectPaperLinksURL) == projectLinksSentinel)
        #expect(try Data(contentsOf: workspace.globalLibraryBibURL) == bibliographySentinel)
        #expect(!fileManager.fileExists(atPath: expectedPaperDirectoryURL.path))
        #expect(!fileManager.fileExists(atPath: workspace.globalPapersURL.path))
        #expect(!fileManager.fileExists(
            atPath: workspaceURL.appendingPathComponent(".sci-station/import-staging").path
        ))
        #expect(try await repository.loadPapers(in: workspace).isEmpty)
    }

    private func metadataDraft(title: String, author: String) -> PaperMetadataDraft {
        PaperMetadataDraft(
            title: title,
            authors: [author],
            year: 2026,
            venue: "Test Journal",
            doi: nil,
            arxiv: nil,
            inspireID: nil,
            url: nil,
            pdfURL: nil,
            abstract: "Rollback fixture",
            categories: ["testing"],
            sourceProvider: "test"
        )
    }

    private func writeValidPDF(to url: URL) throws {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw FixtureError.couldNotCreatePDFConsumer
        }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw FixtureError.couldNotCreatePDFContext
        }

        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(mediaBox)
        context.endPDFPage()
        context.closePDF()

        let pdfData = data as Data
        guard pdfData.starts(with: Data("%PDF-".utf8)), pdfData.count > 100 else {
            throw FixtureError.invalidPDFData
        }
        try pdfData.write(to: url, options: .atomic)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SciStationImportTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private struct InjectedCommitFailure: LocalizedError {
    let stage: PDFImportCommitStage

    var errorDescription: String? {
        "Injected \(stage) commit failure"
    }
}

private enum FixtureError: Error {
    case couldNotCreatePDFConsumer
    case couldNotCreatePDFContext
    case invalidPDFData
}

private actor CommitStageBarrier {
    private var didReach = false
    private var didRelease = false
    private var reachedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func reachAndWait() async {
        didReach = true
        reachedContinuation?.resume()
        reachedContinuation = nil

        guard !didRelease else {
            return
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilReached() async {
        guard !didReach else {
            return
        }
        await withCheckedContinuation { continuation in
            reachedContinuation = continuation
        }
    }

    func release() {
        didRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class StagingCleanupFailingFileManager: FileManager {
    var failingRemovalPath: String?

    override func removeItem(at url: URL) throws {
        if url.path == failingRemovalPath {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.removeItem(at: url)
    }
}
