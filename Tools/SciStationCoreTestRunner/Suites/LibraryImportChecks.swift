import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runLibraryImport() async {
        await runCheck("librarySortStateSortsPapers") { try librarySortStateSortsPapers() }
        await runCheck("libraryBulkEditServiceUpdatesSelectedPapers") { try await libraryBulkEditServiceUpdatesSelectedPapers() }
        await runCheck("batchImportInputParserSplitsMultipleIdentifiers") { try batchImportInputParserSplitsMultipleIdentifiers() }
        await runCheck("paperImportPipelineDispatchesImporterAndMetadataProvider") { try await paperImportPipelineDispatchesImporterAndMetadataProvider() }
        await runCheck("citekeyGenerationUsesAuthorYearKeyword") { try citekeyGenerationUsesAuthorYearKeyword() }
        await runCheck("metadataCodecRoundTripKeepsEditableFields") { try metadataCodecRoundTripKeepsEditableFields() }
        await runCheck("metadataCodecPreservesUnknownFields") { try metadataCodecPreservesUnknownFields() }
        await runCheck("metadataCodecEmitsGraphNodeID") { try metadataCodecEmitsGraphNodeID() }
        await runCheck("paperRepositorySaveAndLoadRoundTripsPaper") { try await paperRepositorySaveAndLoadRoundTripsPaper() }
        await runCheck("paperRepositoryKeepsLegacyRawPapersLoadable") { try await paperRepositoryKeepsLegacyRawPapersLoadable() }
        await runCheck("legacyPaperMigrationPlanDetectsRawPaperConflicts") { try await legacyPaperMigrationPlanDetectsRawPaperConflicts() }
        await runCheck("legacyPaperMigrationCopyWritesReportAndPrefersGlobalPaper") { try await legacyPaperMigrationCopyWritesReportAndPrefersGlobalPaper() }
        await runCheck("projectPaperLinkRepositoryRoundTripsAndOverlaysPaperMetadata") { try await projectPaperLinkRepositoryRoundTripsAndOverlaysPaperMetadata() }
        await runCheck("projectPaperLinkRepositoryEditsSingleLinksAndLoadsLegacyYAML") { try await projectPaperLinkRepositoryEditsSingleLinksAndLoadsLegacyYAML() }
        await runCheck("paperRepositoryKeepsLegacyProjectMetadataWithoutLinks") { try await paperRepositoryKeepsLegacyProjectMetadataWithoutLinks() }
        await runCheck("paperRepositoryDeletesPaperDirectory") { try await paperRepositoryDeletesPaperDirectory() }
        await runCheck("librarySearchMatchesExtendedMetadata") { try librarySearchMatchesExtendedMetadata() }
        await runCheck("paperAnnotationsRepositoryRoundTripsAnnotations") { try await paperAnnotationsRepositoryRoundTripsAnnotations() }
        await runCheck("pdfAnnotationStoreRejectsPathTraversal") { try await pdfAnnotationStoreRejectsPathTraversal() }
        await runCheck("paperRepositoryLoadsNestedCollectionPapers") { try await paperRepositoryLoadsNestedCollectionPapers() }
        await runCheck("tagRepositoryUpsertsAndDeletesDefinitions") { try await tagRepositoryUpsertsAndDeletesDefinitions() }
        await runCheck("arxivRecommendationParserMapsAtomFeedCandidates") { try arxivRecommendationParserMapsAtomFeedCandidates() }
        await runCheck("identifierParserRecognizesSupportedKinds") { try identifierParserRecognizesSupportedKinds() }
        await runCheck("metadataProviderBuildsStableLookupURLs") { try metadataProviderBuildsStableLookupURLs() }
        await runCheck("arxivEntryParserExtractsMetadataDraft") { try arxivEntryParserExtractsMetadataDraft() }
        await runCheck("inspireMetadataMapperExtractsMetadataDraft") { try inspireMetadataMapperExtractsMetadataDraft() }
        await runCheck("inspireMetadataMapperExtractsCitationGraphFields") { try inspireMetadataMapperExtractsCitationGraphFields() }
        await runCheck("paperSummaryPromptBuilderIncludesContext") { try paperSummaryPromptBuilderIncludesContext() }
        await runCheck("paperMarkdownQualityInspectorDetectsPDFKitFallback") { try await paperMarkdownQualityInspectorDetectsPDFKitFallback() }
        await runCheck("paperReadingWorkflowProducesEvidenceBackedDraft") { try paperReadingWorkflowProducesEvidenceBackedDraft() }
        await runCheck("paperLibraryModuleDoesNotExposeRetiredReadingArtifacts") { try paperLibraryModuleDoesNotExposeRetiredReadingArtifacts() }
        await runCheck("pdfImportCreatesLibraryMarkdownAndFigures") { try await pdfImportCreatesLibraryMarkdownAndFigures() }
        await runCheck("minerUAPIConversionCopiesImageAssets") { try await minerUAPIConversionCopiesImageAssets() }
        await runCheck("movePaperToCollectionUpdatesMetadataAndPath") { try await movePaperToCollectionUpdatesMetadataAndPath() }
        await runCheck("paperMarkdownDirectLoadMergesIntoDocumentList") { try await paperMarkdownDirectLoadMergesIntoDocumentList() }
    }

    func librarySortStateSortsPapers() throws {
        var older = samplePaper(id: "older")
        older.title = "Beta Paper"
        older.authors = ["Zed Author"]
        older.year = 2020
        older.updatedAt = Date(timeIntervalSince1970: 10)
        older.rating = 2
        older.priority = .low
        older.status = .used

        var newer = samplePaper(id: "newer")
        newer.title = "Alpha Paper"
        newer.authors = ["Amy Author"]
        newer.year = 2024
        newer.updatedAt = Date(timeIntervalSince1970: 20)
        newer.rating = 5
        newer.priority = .urgent
        newer.status = .unread

        let originalOrder = [older, newer]
        try expect(LibrarySortState().sorted(originalOrder).map(\.id) == ["older", "newer"], "Empty Library sort state should preserve original order.")
        try expect(LibrarySortState(field: .title, isAscending: true).sorted(originalOrder).map(\.id) == ["newer", "older"], "Title sort should order papers alphabetically.")
        try expect(LibrarySortState(field: .year, isAscending: false).sorted(originalOrder).map(\.id) == ["newer", "older"], "Year descending sort should put newer papers first.")
        try expect(LibrarySortState(field: .updated, isAscending: false).sorted(originalOrder).map(\.id) == ["newer", "older"], "Updated descending sort should put recently updated papers first.")
        try expect(LibrarySortState(field: .rating, isAscending: false).sorted(originalOrder).map(\.id) == ["newer", "older"], "Rating descending sort should put higher rated papers first.")
        try expect(LibrarySortState(field: .priority, isAscending: true).sorted(originalOrder).map(\.id) == ["newer", "older"], "Priority sort should use reading priority order.")
        try expect(LibrarySortState(field: .status, isAscending: true).sorted(originalOrder).map(\.id) == ["newer", "older"], "Status sort should use reading status order.")
    }

    func libraryBulkEditServiceUpdatesSelectedPapers() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let service = LibraryBulkEditService(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LibraryBulkEditWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let firstPaper = try await repository.save(samplePaper(id: "bulk-first"), in: workspace)
        let secondPaper = try await repository.save(samplePaper(id: "bulk-second"), in: workspace)
        let targetIDs: Set<Paper.ID> = [firstPaper.id, secondPaper.id]

        _ = try await service.setStatus(.deepRead, for: targetIDs, in: workspace)
        _ = try await service.setPriority(.urgent, for: targetIDs, in: workspace)
        _ = try await service.setRating(5, for: targetIDs, in: workspace)
        _ = try await service.addTags(["dm", "dm", "capture"], for: targetIDs, in: workspace)
        _ = try await service.removeTags(["graph"], for: targetIDs, in: workspace)

        let loadedPapers = try await repository.loadPapers(in: workspace).filter { targetIDs.contains($0.id) }
        try expect(loadedPapers.count == 2, "Bulk edit should keep both target papers loadable.")
        try expect(loadedPapers.allSatisfy { $0.status == .deepRead }, "Bulk edit should update status for all selected papers.")
        try expect(loadedPapers.allSatisfy { $0.priority == .urgent }, "Bulk edit should update priority for all selected papers.")
        try expect(loadedPapers.allSatisfy { $0.rating == 5 }, "Bulk edit should update rating for all selected papers.")
        try expect(loadedPapers.allSatisfy { $0.tags.contains("dm") && $0.tags.contains("capture") }, "Bulk edit should add tags to all selected papers.")
        try expect(loadedPapers.allSatisfy { Set($0.tags).count == $0.tags.count }, "Bulk edit should not create duplicate tags.")
        try expect(loadedPapers.allSatisfy { !$0.tags.contains("graph") }, "Bulk edit should remove requested tags.")
    }

    func batchImportInputParserSplitsMultipleIdentifiers() throws {
        let parser = BatchImportInputParser()
        let parsedInputs = parser.parse("""
        https://arxiv.org/abs/2401.12345, https://doi.org/10.1234/example
        inspire:2811054; https://example.org/paper.pdf https://arxiv.org/abs/2401.12345
        """)

        try expect(
            parsedInputs == [
                "https://arxiv.org/abs/2401.12345",
                "https://doi.org/10.1234/example",
                "inspire:2811054",
                "https://example.org/paper.pdf"
            ],
            "Batch parser should split common pasted separators and remove duplicates."
        )
    }

    func paperImportPipelineDispatchesImporterAndMetadataProvider() async throws {
        let importer = RecordingPaperImporter()
        let provider = RecordingPaperMetadataProvider()
        let pipeline = PaperImportPipeline(importers: [importer], metadataProviders: [provider])
        let context = PluginContext(pluginID: "sci.test")
        let input = PaperImportInput(kind: .doi, value: "10.1234/example")
        let result = try await pipeline.importPaper(input, context: context)
        let candidates = try await pipeline.lookupMetadata(
            MetadataLookupQuery(identifierKind: "doi", value: "10.1234/example"),
            context: context
        )
        let handledValues = await importer.handledValues()
        let lookupValues = await provider.lookupValues()

        try expect(result.paperID == "paper:10.1234/example", "PaperImportPipeline should dispatch to the first matching importer.")
        try expect(result.metadata?.doi == "10.1234/example", "PaperImportPipeline should preserve importer metadata output.")
        try expect(candidates.map(\.providerID) == ["test.metadata"], "PaperImportPipeline should dispatch metadata lookup providers.")
        try expect(candidates.first?.draft.title == "Metadata Candidate", "PaperImportPipeline should return provider candidates.")
        try expect(handledValues == ["10.1234/example"], "Paper importer should observe the requested input value.")
        try expect(lookupValues == ["10.1234/example"], "Metadata provider should observe the requested lookup value.")
    }

    func citekeyGenerationUsesAuthorYearKeyword() throws {
        let citekey = PaperIdentityGenerator.citekey(
            title: "Graph-based Retrieval Augmented Generation",
            authors: ["John Smith"],
            year: 2024,
            existing: []
        )

        try expect(citekey == "smith2024graph", "Citekey generation should follow firstAuthorYearKeyword.")
    }

    func metadataCodecRoundTripKeepsEditableFields() throws {
        let codec = PaperMetadataCodec()
        let createdAt = Date(timeIntervalSince1970: 1_714_176_000)
        let updatedAt = Date(timeIntervalSince1970: 1_714_262_400)
        let originalPaper = Paper(
            id: "smith2024-graph-rag",
            citekey: "smith2024graph",
            title: "Graph-based Retrieval Augmented Generation",
            authors: ["John Smith", "Alice Wang"],
            year: 2024,
            venue: "arXiv",
            doi: nil,
            arxiv: "2401.12345",
            inspireID: "2811054",
            url: "https://arxiv.org/abs/2401.12345",
            pdfURL: "https://arxiv.org/pdf/2401.12345.pdf",
            abstract: "A graph-based RAG pipeline.",
            categories: ["cs.CL"],
            bibtex: """
            @article{smith2024graph,
                title = {Graph-based Retrieval Augmented Generation},
                author = {John Smith and Alice Wang},
                year = {2024}
            }
            """,
            collectionPath: "Dark-Matter/WIMPs",
            pdfRelativePath: "paper.pdf",
            tags: ["rag", "graph-rag"],
            status: .summarized,
            priority: .high,
            rating: 4,
            useFor: ["related-work", "method-design"],
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastReadAt: Date(timeIntervalSince1970: 1_714_348_800),
            lastReadPage: 12,
            paperDirectoryRelativePath: "raw/papers/Dark-Matter/WIMPs/smith2024-graph-rag",
            notesSummaryRelativePath: "../../../../../wiki/papers/smith2024graph.md",
            annotationsRelativePath: "annotations.md"
        )

        let encoded = codec.encode(originalPaper)
        let decoded = codec.decode(
            encoded,
            directoryRelativePath: originalPaper.directoryRelativePath,
            fallbackTitle: "Fallback Title",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        try expect(decoded.id == originalPaper.id, "Decoded paper id should match the encoded id.")
        try expect(decoded.citekey == originalPaper.citekey, "Decoded citekey should match the encoded citekey.")
        try expect(decoded.title == originalPaper.title, "Decoded title should match the encoded title.")
        try expect(decoded.authors == originalPaper.authors, "Decoded authors should match the encoded authors.")
        try expect(decoded.year == originalPaper.year, "Decoded year should match the encoded year.")
        try expect(decoded.inspireID == originalPaper.inspireID, "Decoded INSPIRE id should match the encoded INSPIRE id.")
        try expect(decoded.pdfURL == originalPaper.pdfURL, "Decoded pdf_url should match the encoded pdf_url.")
        try expect(decoded.abstract == originalPaper.abstract, "Decoded abstract should match the encoded abstract.")
        try expect(decoded.categories == originalPaper.categories, "Decoded categories should match the encoded categories.")
        try expect(decoded.bibtex == originalPaper.bibtex, "Decoded BibTeX should match the encoded BibTeX.")
        try expect(decoded.collectionPath == originalPaper.collectionPath, "Decoded collection_path should match the encoded collection path.")
        try expect(decoded.tags == originalPaper.tags, "Decoded tags should match the encoded tags.")
        try expect(decoded.status == originalPaper.status, "Decoded status should match the encoded status.")
        try expect(decoded.priority == originalPaper.priority, "Decoded priority should match the encoded priority.")
        try expect(decoded.rating == originalPaper.rating, "Decoded rating should match the encoded rating.")
        try expect(decoded.useFor == originalPaper.useFor, "Decoded use_for should match the encoded use_for values.")
        try expect(decoded.lastReadAt == originalPaper.lastReadAt, "Decoded last_read_at should match the encoded reading state.")
        try expect(decoded.lastReadPage == originalPaper.lastReadPage, "Decoded last_page should match the encoded reading progress.")
        try expect(decoded.notesSummaryRelativePath == originalPaper.notesSummaryRelativePath, "Decoded summary path should match the encoded summary path.")
    }

    func metadataCodecPreservesUnknownFields() throws {
        let codec = PaperMetadataCodec()
        let rawWithReferences = """
        id: smith2024
        citekey: smith2024graph
        title: "Graph RAG"
        authors:
          - "Smith"
        year: 2024
        status: unread
        priority: medium
        rating:
        use_for: []
        references:
          - doi: "10.1000/ref.1"
            title: "Ref One"
          - arxiv: "2101.00001"
            title: "Ref Two"
        custom_field: "do not drop me"
        reading:
          added: 2024-01-01
          first_read:
          deep_read:
          custom_reading_note: "round trip"
        links:
          semantic_scholar:
          github:
          project_page:
        notes:
          summary_file:
          custom_notes_field: "preserved"
        """

        let decoded = codec.decode(
            rawWithReferences,
            directoryRelativePath: "library/papers/Uncategorized/smith2024",
            fallbackTitle: "Fallback",
            createdAt: nil,
            updatedAt: nil
        )
        let reEncoded = codec.encode(decoded, preserving: rawWithReferences)

        try expect(reEncoded.contains("references:"), "Unknown references: block should be preserved across round-trip.")
        try expect(reEncoded.contains("doi: \"10.1000/ref.1\""), "Unknown references children should be preserved verbatim.")
        try expect(reEncoded.contains("arxiv: \"2101.00001\""), "Unknown references children should be preserved verbatim.")
        try expect(reEncoded.contains("custom_field: \"do not drop me\""), "Unknown top-level scalar should be preserved.")
        try expect(reEncoded.contains("custom_reading_note: \"round trip\""), "Unknown child key under reading: should be preserved.")
        try expect(reEncoded.contains("custom_notes_field: \"preserved\""), "Unknown child key under notes: should be preserved.")
    }

    func metadataCodecEmitsGraphNodeID() throws {
        let codec = PaperMetadataCodec()
        let now = Date()
        let paper = Paper(
            id: "smith2024",
            citekey: "smith2024graph",
            title: "Graph RAG",
            authors: ["Smith"],
            year: 2024,
            venue: nil,
            doi: nil,
            arxiv: "2401.12345v1",
            url: nil,
            pdfRelativePath: nil,
            tags: [],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: now,
            updatedAt: now,
            paperDirectoryRelativePath: "library/papers/Uncategorized/smith2024",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
        let encoded = codec.encode(paper)
        try expect(encoded.contains("graph_node_id: \"arxiv:2401.12345\""), "Encoder should emit a stable graph_node_id derived from arXiv.")
        try expect(codec.decodedGraphNodeID(from: encoded) == "arxiv:2401.12345", "decodedGraphNodeID helper should return the persisted value.")
    }

    func paperRepositorySaveAndLoadRoundTripsPaper() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("RepositoryWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = Paper(
            id: "lee2022knowledge-graph-rag",
            citekey: "lee2022knowledge",
            title: "Knowledge Graph Retrieval for RAG",
            authors: ["Min Lee"],
            year: 2022,
            venue: "ACL",
            doi: nil,
            arxiv: nil,
            url: nil,
            pdfRelativePath: "paper.pdf",
            tags: ["rag", "knowledge-graph"],
            status: .skimmed,
            priority: .medium,
            rating: 3,
            useFor: ["related-work"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            paperDirectoryRelativePath: "library/papers/Uncategorized/lee2022knowledge-graph-rag",
            notesSummaryRelativePath: "../../../../wiki/papers/lee2022knowledge.md",
            annotationsRelativePath: "annotations.md"
        )

        _ = try await repository.save(paper, in: workspace)
        let loadedPapers = try await repository.loadPapers(in: workspace)
        let loadedPaper = try require(
            loadedPapers.first(where: { $0.id == paper.id }),
            "Expected repository.loadPapers to return the saved paper."
        )

        try expect(loadedPaper.title == paper.title, "Loaded paper title should match the saved title.")
        try expect(loadedPaper.authors == paper.authors, "Loaded authors should match the saved authors.")
        try expect(loadedPaper.tags == paper.tags, "Loaded tags should match the saved tags.")
        try expect(loadedPaper.status == paper.status, "Loaded status should match the saved status.")
        try expect(loadedPaper.priority == paper.priority, "Loaded priority should match the saved priority.")
        try expect(loadedPaper.rating == paper.rating, "Loaded rating should match the saved rating.")
        try expect(
            loadedPaper.notesSummaryRelativePath == paper.notesSummaryRelativePath,
            "Loaded summary path should match the saved summary path."
        )
        try expect(
            loadedPaper.collectionPath == "Uncategorized",
            "Loaded collection path should be derived from the nested paper directory."
        )
    }

    func paperRepositoryKeepsLegacyRawPapersLoadable() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyRawPaperWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var legacyPaper = samplePaper(id: "legacy-raw-paper")
        legacyPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-raw-paper"
        legacyPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: legacyPaper.citekey,
            paperDirectoryRelativePath: legacyPaper.paperDirectoryRelativePath
        )

        _ = try await repository.save(legacyPaper, in: workspace)
        let loadedPaper = try require(
            try await repository.loadPapers(in: workspace).first(where: { $0.id == legacyPaper.id }),
            "Expected repository to keep legacy raw/papers metadata loadable."
        )

        try expect(loadedPaper.paperDirectoryRelativePath.hasPrefix("raw/papers/"), "Legacy paper paths should remain in raw/papers.")
        try expect(loadedPaper.collectionPath == "Legacy", "Legacy raw/papers collections should still be derived correctly.")
    }

    func legacyPaperMigrationPlanDetectsRawPaperConflicts() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let migrationService = LegacyPaperMigrationService()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyMigrationPlanWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)

        var readyPaper = samplePaper(id: "legacy-ready-paper")
        readyPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-ready-paper"
        readyPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: readyPaper.citekey,
            paperDirectoryRelativePath: readyPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(readyPaper, in: workspace)

        var conflictPaper = samplePaper(id: "legacy-conflict-paper")
        conflictPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-conflict-paper"
        conflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: conflictPaper.citekey,
            paperDirectoryRelativePath: conflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(conflictPaper, in: workspace)

        var globalConflictPaper = conflictPaper
        globalConflictPaper.paperDirectoryRelativePath = "library/papers/Legacy/legacy-conflict-paper"
        globalConflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: globalConflictPaper.citekey,
            paperDirectoryRelativePath: globalConflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(globalConflictPaper, in: workspace)

        let plan = try await migrationService.makePlan(in: workspace)
        let readyItem = try require(
            plan.items.first(where: { $0.paperID == readyPaper.id }),
            "Expected migration plan to include a ready legacy paper."
        )
        let conflictItem = try require(
            plan.items.first(where: { $0.paperID == conflictPaper.id }),
            "Expected migration plan to include a conflicting legacy paper."
        )

        try expect(plan.legacyPaperCount == 2, "Migration plan should count legacy raw/papers metadata files.")
        try expect(plan.readyCount == 1, "Migration plan should count ready-to-copy legacy papers.")
        try expect(plan.conflictCount == 1, "Migration plan should count conflicting legacy papers.")
        try expect(readyItem.status == .readyToCopy, "A legacy paper without a target conflict should be ready to copy.")
        try expect(readyItem.targetRelativePath == "library/papers/Legacy/legacy-ready-paper", "Migration plan should preserve collection paths under library/papers.")
        try expect(conflictItem.status == .conflict, "A legacy paper with a global duplicate should be marked as a conflict.")
        try expect(conflictItem.conflicts.contains(.targetDirectoryExists), "Migration plan should flag existing target directories.")
        try expect(conflictItem.conflicts.contains(.duplicatePaperIDInGlobalLibrary), "Migration plan should flag duplicate global paper ids.")
    }

    func legacyPaperMigrationCopyWritesReportAndPrefersGlobalPaper() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let migrationService = LegacyPaperMigrationService()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyMigrationCopyWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)

        var readyPaper = samplePaper(id: "legacy-copy-ready-paper")
        readyPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-copy-ready-paper"
        readyPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: readyPaper.citekey,
            paperDirectoryRelativePath: readyPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(readyPaper, in: workspace)

        var conflictPaper = samplePaper(id: "legacy-copy-conflict-paper")
        conflictPaper.paperDirectoryRelativePath = "raw/papers/Legacy/legacy-copy-conflict-paper"
        conflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: conflictPaper.citekey,
            paperDirectoryRelativePath: conflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(conflictPaper, in: workspace)

        var globalConflictPaper = conflictPaper
        globalConflictPaper.paperDirectoryRelativePath = "library/papers/Legacy/legacy-copy-conflict-paper"
        globalConflictPaper.notesSummaryRelativePath = Paper.summaryRelativePath(
            for: globalConflictPaper.citekey,
            paperDirectoryRelativePath: globalConflictPaper.paperDirectoryRelativePath
        )
        _ = try await paperRepository.save(globalConflictPaper, in: workspace)

        let report = try await migrationService.copyReadyItems(in: workspace)
        let reportRelativePath = try require(report.reportRelativePath, "Migration report should include its relative path.")
        let reportURL = workspace.fileURL(for: reportRelativePath)
        let copiedDirectoryURL = workspace.directoryURL(for: "library/papers/Legacy/legacy-copy-ready-paper")
        let legacyDirectoryURL = workspace.directoryURL(for: "raw/papers/Legacy/legacy-copy-ready-paper")
        let loadedPapers = try await paperRepository.loadPapers(in: workspace)
        let loadedReadyPapers = loadedPapers.filter { $0.id == readyPaper.id }
        let loadedReadyPaper = try require(loadedReadyPapers.first, "Expected copied paper to be loadable.")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedReport = try decoder.decode(LegacyPaperMigrationReport.self, from: Data(contentsOf: reportURL))

        try expect(report.copiedCount == 1, "Copy migration should copy ready legacy papers.")
        try expect(report.skippedCount == 1, "Copy migration should skip conflicting legacy papers.")
        try expect(report.failedCount == 0, "Copy migration should not fail ready papers in the happy path.")
        try expect(FileManager.default.fileExists(atPath: reportURL.path), "Copy migration should write a JSON report.")
        try expect(decodedReport.items.count == 2, "Written migration report should include every planned legacy item.")
        try expect(FileManager.default.fileExists(atPath: copiedDirectoryURL.path), "Copy migration should create the global library paper directory.")
        try expect(FileManager.default.fileExists(atPath: legacyDirectoryURL.path), "Copy migration should keep the legacy raw/papers directory in place.")
        try expect(loadedReadyPapers.count == 1, "PaperRepository should not return duplicate ids after migration copy.")
        try expect(loadedReadyPaper.paperDirectoryRelativePath == "library/papers/Legacy/legacy-copy-ready-paper", "PaperRepository should prefer the global library copy after migration.")
        try expect(loadedReadyPaper.notesSummaryRelativePath == Paper.summaryRelativePath(for: loadedReadyPaper.citekey, paperDirectoryRelativePath: loadedReadyPaper.paperDirectoryRelativePath), "Copied metadata should be normalized to the new library path.")
    }

    func projectPaperLinkRepositoryRoundTripsAndOverlaysPaperMetadata() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let linkRepository = ProjectPaperLinkRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ProjectPaperLinkWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "linked-paper"), in: workspace)
        try await linkRepository.save([
            ProjectPaperLink(
                projectID: "project-alpha",
                paperID: paper.id,
                isCore: true,
                folderPath: "Project-Folder",
                useFor: ["method-design"],
                isPinned: true,
                sortOrder: 3
            )
        ], in: workspace)

        let loadedLinks = try await linkRepository.links(forPaperID: paper.id, in: workspace)
        let loadedPaper = try require(
            try await paperRepository.loadPapers(in: workspace).first(where: { $0.id == paper.id }),
            "Expected project links to overlay loaded paper metadata."
        )

        try expect(loadedLinks.count == 1, "Project-paper link repository should load saved links.")
        try expect(loadedPaper.projectIDs == ["project-alpha"], "Loaded paper should expose project ids from the link repository.")
        try expect(loadedPaper.coreProjectIDs == ["project-alpha"], "Loaded paper should expose core project ids from the link repository.")
        try expect(loadedPaper.folderPath == "Project-Folder", "Loaded paper should expose the project folder from the link repository.")
        try expect(loadedPaper.useFor.contains("method-design"), "Loaded paper should merge project use cases from the link repository.")
        try expect(loadedLinks.first?.isPinned == true, "Project-paper link repository should round-trip pinned state.")
        try expect(loadedLinks.first?.sortOrder == 3, "Project-paper link repository should round-trip sort order.")
    }

    func projectPaperLinkRepositoryEditsSingleLinksAndLoadsLegacyYAML() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let linkRepository = ProjectPaperLinkRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ProjectPaperLinkEditWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        try FileManager.default.createDirectory(at: workspace.projectPaperLinksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        links:
          - project_id: "project-alpha"
            paper_id: "paper-alpha"
            is_core: true
            folder_path: "Reading"
            use_for:
              - "background"
            created_at: 2026-04-29T00:00:00Z
            updated_at: 2026-04-29T00:00:00Z
        """.write(to: workspace.projectPaperLinksURL, atomically: true, encoding: .utf8)

        let legacyLink = try require(
            try await linkRepository.link(forPaperID: "paper-alpha", projectID: "project-alpha", in: workspace),
            "Expected legacy project-paper link YAML to load without pin/order fields."
        )
        try expect(legacyLink.isPinned == false, "Legacy project-paper links should default to unpinned.")
        try expect(legacyLink.sortOrder == nil, "Legacy project-paper links should default to no explicit sort order.")

        let pinnedLink = try await linkRepository.setPinned(true, projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let orderedLink = try await linkRepository.updateSortOrder(2, projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let useForLink = try await linkRepository.updateUseFor(["method", "method", "comparison"], projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let folderLink = try await linkRepository.updateFolderPath("  Methods/Core  ", projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        _ = try await linkRepository.setCore(false, projectID: "project-alpha", paperID: "paper-alpha", in: workspace)

        let editedLink = try require(
            try await linkRepository.link(forPaperID: "paper-alpha", projectID: "project-alpha", in: workspace),
            "Expected single-link edit APIs to keep the edited link loadable."
        )
        let encodedYAML = try String(contentsOf: workspace.projectPaperLinksURL, encoding: .utf8)

        try expect(pinnedLink.isPinned, "setPinned should return the updated pinned link.")
        try expect(orderedLink.sortOrder == 2, "updateSortOrder should return the updated sort order.")
        try expect(useForLink.useFor == ["method", "comparison"], "updateUseFor should normalize duplicate project usage values.")
        try expect(folderLink.folderPath == "Methods/Core", "updateFolderPath should trim project folder paths.")
        try expect(editedLink.isCore == false, "setCore should update the existing link.")
        try expect(editedLink.isPinned == true, "Edited link should persist pinned state.")
        try expect(editedLink.sortOrder == 2, "Edited link should persist sort order.")
        try expect(encodedYAML.contains("is_pinned: true"), "Encoded project-paper links should include pinned state.")
        try expect(encodedYAML.contains("sort_order: 2"), "Encoded project-paper links should include sort order.")

        let remainingLinks = try await linkRepository.remove(projectID: "project-alpha", paperID: "paper-alpha", in: workspace)
        let removedLink = try await linkRepository.link(forPaperID: "paper-alpha", projectID: "project-alpha", in: workspace)
        try expect(remainingLinks.isEmpty, "Removing a project-paper link should return no remaining links for that paper.")
        try expect(removedLink == nil, "Removed project-paper link should not load again.")
    }

    func paperRepositoryKeepsLegacyProjectMetadataWithoutLinks() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let linkRepository = ProjectPaperLinkRepository()
        let paperRepository = PaperRepository(projectPaperLinkRepository: linkRepository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("LegacyProjectMetadataWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var paper = samplePaper(id: "legacy-project-paper")
        paper.projectIDs = ["legacy-project"]
        paper.coreProjectIDs = ["legacy-project"]

        let savedPaper = try await paperRepository.save(paper, in: workspace)
        try await linkRepository.save([], in: workspace)

        let loadedPaper = try require(
            try await paperRepository.loadPapers(in: workspace).first(where: { $0.id == savedPaper.id }),
            "Expected legacy project metadata paper to remain loadable without relationship links."
        )

        try expect(loadedPaper.projectIDs == ["legacy-project"], "Legacy project_ids metadata should still bridge when no relationship links exist.")
        try expect(loadedPaper.coreProjectIDs == ["legacy-project"], "Legacy core_project_ids metadata should still bridge when no relationship links exist.")
    }

    func paperRepositoryDeletesPaperDirectory() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("DeletePaperWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await repository.save(samplePaper(id: "delete-test-paper"), in: workspace)
        let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)

        try expect(FileManager.default.fileExists(atPath: paperDirectoryURL.path), "Saved paper directory should exist before deletion.")

        try await repository.delete(paper, in: workspace)
        let loadedPapers = try await repository.loadPapers(in: workspace)

        try expect(!FileManager.default.fileExists(atPath: paperDirectoryURL.path), "Deleting a paper should remove its paper directory.")
        try expect(loadedPapers.isEmpty, "Deleted papers should no longer appear in repository loads.")
    }

    func librarySearchMatchesExtendedMetadata() throws {
        var paper = samplePaper(id: "search-paper")
        paper.doi = "10.1234/searchable"
        paper.abstract = "This abstract discusses solar capture."
        paper.bibtex = """
        @article{smith2024graph,
          title = {Graph RAG},
          keyword = {neutrino telescope}
        }
        """

        let service = LibrarySearchService()

        try expect(service.matches(paper, query: "10.1234"), "Library search should match DOI.")
        try expect(service.matches(paper, query: "solar capture"), "Library search should match abstracts.")
        try expect(service.matches(paper, query: "neutrino telescope"), "Library search should match BibTeX contents.")
        try expect(service.matchingIDs(in: [paper], query: "2401.12345") == [paper.id], "Library search should return matching paper ids.")
    }

    func paperAnnotationsRepositoryRoundTripsAnnotations() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let paperRepository = PaperRepository()
        let annotationsRepository = PaperAnnotationsRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AnnotationsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "annotations-paper"), in: workspace)
        try await annotationsRepository.saveAnnotations("# Notes\n\nImportant reading note.", for: paper, in: workspace)
        let loadedAnnotations = try await annotationsRepository.loadAnnotations(for: paper, in: workspace)

        try expect(loadedAnnotations.contains("Important reading note."), "Paper annotations repository should round-trip annotations.md contents.")
    }

    func pdfAnnotationStoreRejectsPathTraversal() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: WorkspaceBookmarkStore(defaults: defaults))
        let store = PDFAnnotationStore()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PDFTraversalWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var paper = samplePaper(id: "bad-path-paper")
        paper.paperDirectoryRelativePath = "library/papers/../escape"

        do {
            _ = try await store.loadAnnotations(for: paper, in: workspace)
            throw ValidationError(message: "PDFAnnotationStore should reject paper directory path traversal.")
        } catch PDFAnnotationStoreError.invalidPaperDirectory {
        }
    }

    func paperRepositoryLoadsNestedCollectionPapers() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("NestedCollectionsWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let nestedPaper = Paper(
            id: "garani2024dark",
            citekey: "garani2024dark",
            title: "Dark Matter Capture Review",
            authors: ["Jakob Garani"],
            year: 2024,
            venue: "arXiv",
            doi: nil,
            arxiv: "2401.12345",
            url: "https://arxiv.org/abs/2401.12345",
            pdfRelativePath: "paper.pdf",
            tags: ["dark-matter"],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: Date(timeIntervalSince1970: 1_714_176_000),
            updatedAt: Date(timeIntervalSince1970: 1_714_176_000),
            paperDirectoryRelativePath: "library/papers/Dark-Matter/Solar-Capture/garani2024dark",
            notesSummaryRelativePath: "../../../../../wiki/papers/garani2024dark.md",
            annotationsRelativePath: "annotations.md"
        )

        let savedPaper = try await repository.save(nestedPaper, in: workspace)
        let paperDirectoryURL = workspace.directoryURL(for: savedPaper.paperDirectoryRelativePath)
        let pdfURL = paperDirectoryURL.appendingPathComponent("paper.pdf")
        try writeValidPDF(to: pdfURL)
        let metadataURL = paperDirectoryURL.appendingPathComponent("meta.yaml")
        let staleMetadata = try String(contentsOf: metadataURL, encoding: .utf8)
            .replacingOccurrences(of: "collection_path: \"Dark-Matter/Solar-Capture\"", with: "collection_path: \"Old-Folder\"")
        try staleMetadata.write(to: metadataURL, atomically: true, encoding: .utf8)

        let loadedPaper = try require(
            try await repository.loadPapers(in: workspace).first(where: { $0.id == savedPaper.id }),
            "Expected repository to find meta.yaml inside nested collection folders."
        )

        try expect(
            loadedPaper.paperDirectoryRelativePath == nestedPaper.paperDirectoryRelativePath,
            "Repository should preserve nested paper directory paths."
        )
        try expect(
            loadedPaper.collectionPath == "Dark-Matter/Solar-Capture",
            "Repository should derive the full nested collection path from the directory layout."
        )
    }

    func tagRepositoryUpsertsAndDeletesDefinitions() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = TagRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("TagWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)

        try await repository.upsert(
            TagDefinition(name: "Theory", colorHex: "#B57EDC", textColorHex: "#4A235A"),
            in: workspace
        )
        try await repository.upsert(
            TagDefinition(name: "Experiment", colorHex: "#85C1E9", textColorHex: "#154360"),
            in: workspace
        )
        try await repository.upsert(
            TagDefinition(name: "Theory", colorHex: "#C39BD3", textColorHex: "#45235A"),
            in: workspace
        )

        let savedDefinitions = try await repository.loadDefinitions(in: workspace)
        try expect(savedDefinitions.count == 2, "Upserting a tag twice should replace the existing definition instead of duplicating it.")
        try expect(savedDefinitions.first(where: { $0.name == "Theory" })?.colorHex == "#C39BD3", "Upsert should update an existing tag color.")

        try await repository.deleteTag(named: "Experiment", in: workspace)
        let remainingDefinitions = try await repository.loadDefinitions(in: workspace)
        try expect(remainingDefinitions.map(\.name) == ["Theory"], "Deleting a tag should remove it from refs/tags.yaml.")
    }

    func arxivRecommendationParserMapsAtomFeedCandidates() throws {
        let atom = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>http://arxiv.org/abs/2604.22012v1</id>
            <updated>2026-04-21T00:00:00Z</updated>
            <published>2026-04-20T00:00:00Z</published>
            <title>Graph Retrieval for Scientific Agents</title>
            <summary>Graph retrieval agents use arXiv recommendations.</summary>
            <author><name>Ada Lovelace</name></author>
            <author><name>Grace Hopper</name></author>
            <category term="cs.AI"/>
            <category term="cs.CL"/>
          </entry>
        </feed>
        """
        let candidate = try require(ArxivRecommendationParser.parseAtom(atom).first, "arXiv Atom parser should return one candidate.")

        try expect(candidate.canonicalID == "external:arxiv:2604.22012", "arXiv Atom parser should canonicalize versioned ids.")
        try expect(candidate.externalKey == "arxiv:2604.22012", "arXiv Atom parser should emit arXiv external keys.")
        try expect(candidate.sourceName == "arXiv", "arXiv Atom parser should label candidates as arXiv.")
        try expect(candidate.sourceURL == "https://arxiv.org/abs/2604.22012", "arXiv Atom parser should produce abs URLs.")
        try expect(candidate.pdfURL == "https://arxiv.org/pdf/2604.22012.pdf", "arXiv Atom parser should produce pdf URLs.")
        try expect(candidate.authors == ["Ada Lovelace", "Grace Hopper"], "arXiv Atom parser should preserve author order.")
        try expect(candidate.categories == ["cs.AI", "cs.CL"], "arXiv Atom parser should preserve categories.")
        try expect(candidate.abstractText?.contains("arXiv recommendations") == true, "arXiv Atom parser should preserve summaries.")
    }

        func identifierParserRecognizesSupportedKinds() throws {
                let parser = IdentifierParser()

                try expect(parser.parse("2401.12345").kind == .arxiv, "Parser should recognize bare arXiv ids.")
                try expect(parser.parse("arXiv:2604.22012").normalizedValue == "2604.22012", "Parser should normalize prefixed arXiv ids.")
                try expect(parser.parse("arXiv 2604.22012").normalizedValue == "2604.22012", "Parser should normalize arXiv ids with a space prefix.")
                try expect(parser.parse("https://arxiv.org/abs/2401.12345").normalizedValue == "2401.12345", "Parser should normalize arXiv URLs to ids.")
                try expect(parser.parse("10.48550/arXiv.2401.12345").kind == .doi, "Parser should recognize DOI inputs.")
                try expect(parser.parse("https://doi.org/10.48550/arXiv.2604.22012").kind == .doi, "Parser should recognize doi.org arXiv DOI links as DOI inputs.")
                try expect(parser.extractArxivID(from: "10.48550/arXiv.2604.22012") == "2604.22012", "Parser should detect arXiv ids embedded in arXiv DOI strings.")
                try expect(parser.parse("https://inspirehep.net/literature/2811054").kind == .inspire, "Parser should recognize INSPIRE literature URLs.")
                try expect(parser.parse("https://example.com/paper.pdf").kind == .pdfURL, "Parser should recognize PDF URLs.")
                try expect(parser.parse("https://example.com/article").kind == .url, "Parser should recognize normal web URLs.")
        }

            func metadataProviderBuildsStableLookupURLs() throws {
                let arxivURL = try ArxivMetadataProvider.apiURL(for: "2604.22012")
                let arxivComponents = try require(URLComponents(url: arxivURL, resolvingAgainstBaseURL: false), "Expected arXiv lookup URL components.")
                let arxivQueryItems = arxivComponents.queryItems ?? []

                try expect(arxivComponents.host == "export.arxiv.org", "arXiv lookup should use the export API host.")
                try expect(arxivComponents.path == "/api/query", "arXiv lookup should target the API query path.")
                try expect(arxivQueryItems.first(where: { $0.name == "search_query" })?.value == "id:2604.22012", "arXiv lookup should preserve id: search queries.")

                let doiURL = try DOIMetadataProvider.crossrefWorksURL(for: "10.48550/arXiv.2604.22012")
                try expect(
                    doiURL.absoluteString == "https://api.crossref.org/works/10.48550%2FarXiv.2604.22012",
                    "Crossref lookup should percent-encode DOI path separators."
                )
            }

        func arxivEntryParserExtractsMetadataDraft() throws {
                let parser = ArxivEntryParser()
                let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <feed xmlns="http://www.w3.org/2005/Atom">
                    <entry>
                        <id>https://arxiv.org/abs/2401.12345v1</id>
                        <updated>2024-01-20T00:00:00Z</updated>
                        <published>2024-01-10T00:00:00Z</published>
                        <title> Dark Matter Capture Review </title>
                        <summary> Overview of dark matter capture. </summary>
                        <author><name>Jane Doe</name><arxiv:affiliation>Example Institute</arxiv:affiliation></author>
                        <author><name>John Roe</name></author>
                        <link href="https://arxiv.org/abs/2401.12345v1" rel="alternate" type="text/html"/>
                        <link href="https://arxiv.org/pdf/2401.12345v1.pdf" rel="related" type="application/pdf" title="pdf"/>
                        <category term="hep-ph"/>
                    </entry>
                </feed>
                """

                let draft = try parser.parse(Data(xml.utf8))
                try expect(draft.title == "Dark Matter Capture Review", "arXiv parser should trim entry titles.")
                try expect(draft.authors == ["Jane Doe", "John Roe"], "arXiv parser should extract author names.")
                try expect(draft.pdfURL == "https://arxiv.org/pdf/2401.12345v1.pdf", "arXiv parser should extract pdf links.")
                try expect(draft.categories == ["hep-ph"], "arXiv parser should extract category terms.")
        }

        func inspireMetadataMapperExtractsMetadataDraft() throws {
                let mapper = InspireMetadataMapper()
                let json = """
                {
                    "metadata": {
                        "titles": [{"title": "Solar Dark Matter Limits"}],
                        "abstracts": [{"value": "An INSPIRE abstract."}],
                        "authors": [{"full_name": "Alice Smith"}],
                        "arxiv_eprints": [{"value": "2401.12345"}],
                        "dois": [{"value": "10.1234/example"}],
                        "documents": [{"url": "https://example.com/paper.pdf"}],
                        "publication_info": [{"year": 2024}],
                        "inspire_categories": [{"term": "Phenomenology"}]
                    }
                }
                """

                let draft = try mapper.map(data: Data(json.utf8), recordID: "2811054")
                try expect(draft.title == "Solar Dark Matter Limits", "INSPIRE mapper should extract titles.")
                try expect(draft.arxiv == "2401.12345", "INSPIRE mapper should extract linked arXiv ids.")
                try expect(draft.pdfURL == "https://arxiv.org/pdf/2401.12345.pdf", "INSPIRE mapper should prefer arXiv PDF links when available.")
                try expect(draft.inspireID == "2811054", "INSPIRE mapper should preserve the record id.")
        }

        func inspireMetadataMapperExtractsCitationGraphFields() throws {
                let mapper = InspireMetadataMapper()
                let json = """
                {
                    "id": "1517248",
                    "metadata": {
                        "control_number": 1517248,
                        "titles": [{"title": "Dark matter in the Sun"}],
                        "abstracts": [{"value": "Solar dark matter scattering."}],
                        "authors": [{"full_name": "Garani, Raghuveer"}],
                        "arxiv_eprints": [{"value": "1702.02768"}],
                        "dois": [{"value": "10.1088/1475-7516/2017/05/007"}],
                        "publication_info": [{"year": 2017, "journal_title": "JCAP"}],
                        "inspire_categories": [{"term": "Phenomenology"}],
                        "citation_count": 103,
                        "reference_count": 197,
                        "references": [
                            {"record": {"$ref": "https://inspirehep.net/api/literature/812742"}},
                            {"record": {"$ref": "https://inspirehep.net/api/literature/812742"}},
                            {"recid": 930231}
                        ]
                    }
                }
                """

                let data = Data(json.utf8)
                let paper = try mapper.mapCitationPaper(data: data, fallbackRecordID: "1517248")
                let references = try mapper.referenceRecordIDs(data: data)
                try expect(paper.inspireID == "1517248", "INSPIRE citation paper should use control_number as id.")
                try expect(paper.firstAuthorLastName == "Garani", "INSPIRE citation paper should expose a compact first author label.")
                try expect(paper.citationCount == 103, "INSPIRE citation paper should extract citation_count.")
                try expect(paper.referenceCount == 197, "INSPIRE citation paper should extract reference_count.")
                try expect(references == ["812742", "930231"], "INSPIRE references should extract unique referenced record ids in order.")
        }

            func paperSummaryPromptBuilderIncludesContext() throws {
                var paper = samplePaper(id: "summary-context-paper")
                paper.doi = "10.1234/example"
                paper.abstract = "A compact abstract for testing prompt context."
                paper.tags = ["dark-matter", "review"]

                let prompt = PaperSummaryPromptBuilder().buildPrompt(
                    for: paper,
                    rawMarkdown: "# Raw Text\n\nImportant equation and method details.",
                    annotations: "# Annotations\n\nCheck the simulation setup.",
                    existingWiki: "# Existing Wiki\n\nPrior manual notes."
                )

                try expect(prompt.contains("10.1234/example"), "Prompt should include DOI metadata.")
                try expect(prompt.contains("Important equation and method details."), "Prompt should include raw markdown or extracted text.")
                try expect(prompt.contains("Check the simulation setup."), "Prompt should include annotations.")
                try expect(prompt.contains("Prior manual notes."), "Prompt should include existing wiki content.")
                try expect(prompt.contains("不要编造"), "Prompt should explicitly forbid invented claims.")
            }

    func paperMarkdownQualityInspectorDetectsPDFKitFallback() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let paperRepository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PaperMarkdownQualityWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await paperRepository.save(samplePaper(id: "pdfkit-quality-paper"), in: workspace)
        let markdown = """
        ---
        extraction_engine: pdfkit_fallback
        fallback_reason: "MinerU API token is missing."
        ---

        # Demo Paper

        ## 摘要

        这是一段中文摘要。

        ![Figure](figures/missing-chart.png)

        $$
        E = mc^2
        $$
        """
        try markdown.write(to: paper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

        let report = PaperMarkdownQualityInspector().inspect(paper, in: workspace)
        let issueCodes = Set(report.issues.map(\.code))

        try expect(report.status == .warning, "PDFKit fallback reports should warn rather than fail when paper.md is readable.")
        try expect(report.extractionEngine == "pdfkit_fallback", "Quality inspector should expose extraction engine metadata.")
        try expect(report.hasAbstractHeading, "Quality inspector should recognize Chinese 摘要 headings as Abstract.")
        try expect(report.hasDisplayMath, "Quality inspector should detect display math blocks.")
        try expect(report.hasFigureReferences, "Quality inspector should detect figure references.")
        try expect(issueCodes.contains(.pdfKitFallback), "Quality inspector should warn about PDFKit fallback limitations.")
        try expect(issueCodes.contains(.missingFigureAsset), "Quality inspector should warn about missing local figure assets.")
        try expect(report.issueLines(usesEnglishInterface: false).contains { $0.contains("PDFKit fallback 可读性有限") }, "Quality issue lines should include Chinese copy.")
        try expect(report.issueLines(usesEnglishInterface: true).contains { $0.contains("PDFKit fallback has limited readability") }, "Quality issue lines should include English copy.")
    }

    func paperReadingWorkflowProducesEvidenceBackedDraft() throws {
        let evidence = sampleEvidenceRefs(prefix: "paper")
        let draft = AgentArtifactDraft(
            runID: "paper-reading-run",
            kind: "paper_reading_note",
            proposedPath: "wiki/papers/demo.md",
            title: "Paper Note",
            content: "# Paper Note\n\n## TL;DR\n- Claim. [evidence:\(evidence[0].id)]\n\n## Contributions\n- Claim. [evidence:\(evidence[1].id)]\n- Claim. [evidence:\(evidence[2].id)]\n- Claim. [evidence:\(evidence[3].id)]\n\n## Method\n- Claim. [evidence:\(evidence[4].id)]\n- Claim. [evidence:\(evidence[5].id)]\n\n## Experiments\n## Limitations\n## Open Questions\n## Relevance to Current Project\n## Follow-up Todos\n## Evidence\n",
            evidenceRefs: evidence,
            risk: .readOnly
        )

        try expect(draft.content.contains("## TL;DR"), "Paper reading draft should include the production note structure.")
        try expect(draft.content.contains("## Follow-up Todos"), "Paper reading draft should include follow-up todos.")
        try expect(draft.evidenceRefs.count >= 6, "Paper reading draft should carry evidence refs for claims.")
    }

    func paperLibraryModuleDoesNotExposeRetiredReadingArtifacts() throws {
        let module = try require(WorkspaceModuleRegistry.module(id: "paper-library"), "paper-library module must remain in the built-in registry.")
        try expect(!module.artifactKinds.contains("reading_queue_entry"), "paper-library should no longer declare the retired reading_queue_entry artifact kind.")
        try expect(!module.workflows.contains("reading_queue_curate"), "paper-library should no longer declare the retired reading_queue_curate workflow.")
        try expect(!module.workflows.contains("weekly_reading_plan"), "paper-library should no longer declare the retired weekly_reading_plan workflow.")
        try expect(!module.permissions.writePaths.contains("library/queue.yaml"), "paper-library should no longer permit writes to the retired library/queue.yaml.")
        try expect(!module.permissions.writePaths.contains("projects/*/queue.yaml"), "paper-library should no longer permit writes to the retired projects/*/queue.yaml.")
        try expect(!module.projectTabs.contains(where: { $0.id == "reading" }), "paper-library should no longer contribute Reading after it is merged into Tasks.")
        try expect(!module.projectTabs.contains(where: { $0.id == "queue" }), "paper-library should no longer contribute a separate Queue project-space tab.")
        try expect(!module.projectTabs.contains(where: { $0.id == "reading-plan" }), "paper-library should no longer contribute a separate Reading Plan project-space tab.")

        let descriptor = WorkspaceModuleRegistry.artifactKindDescriptor(for: "reading_queue_entry", in: WorkspaceModuleRegistry.defaultConfiguration())
        try expect(!descriptor.isKnown, "The retired reading_queue_entry artifact kind should no longer resolve to any module.")
    }

    func pdfImportCreatesLibraryMarkdownAndFigures() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let importer = PDFImportService(repository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("ImportWorkspace", isDirectory: true)
        let sourcePDFURL = temporaryDirectoryURL().appendingPathComponent("Example-2024.pdf", isDirectory: false)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: sourcePDFURL.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        try writeValidPDF(to: sourcePDFURL)

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let importedPaper = try await importer.importPDF(from: sourcePDFURL, into: workspace, existingPapers: [])
        let paperDirectoryURL = workspace.directoryURL(for: importedPaper.directoryRelativePath)
        let paperMarkdownURL = paperDirectoryURL.appendingPathComponent("paper.md", isDirectory: false)
        let figuresURL = paperDirectoryURL.appendingPathComponent("figures", isDirectory: true)

        try expect(importedPaper.collectionPath == "Uncategorized", "Imported papers should default into the Uncategorized collection.")
        try expect(importedPaper.paperDirectoryRelativePath.hasPrefix("library/papers/"), "Imported papers should be stored in the global library.")
        try expect(FileManager.default.fileExists(atPath: paperDirectoryURL.appendingPathComponent("paper.pdf").path), "Imported paper should include paper.pdf.")
        try expect(FileManager.default.fileExists(atPath: paperMarkdownURL.path), "Imported paper should include paper.md.")
        try expect(FileManager.default.fileExists(atPath: figuresURL.path), "Imported paper should include a figures directory.")

        let rawMarkdown = try String(contentsOf: paperMarkdownURL, encoding: .utf8)
        try expect(rawMarkdown.contains("type: raw-paper"), "paper.md should contain raw-paper frontmatter.")
        try expect(rawMarkdown.contains("status: not_extracted"), "paper.md should record extraction status.")
    }

    func minerUAPIConversionCopiesImageAssets() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MinerUAssetWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
            MinerUAPIMockURLProtocol.zipData = Data()
            MinerUAPIMockURLProtocol.requestLog = []
            MinerUAPIMockURLProtocol.uploadContentTypeHeaders = []
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paper = try await repository.save(samplePaper(id: "mineru-images-paper"), in: workspace)
        let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
        try FileManager.default.createDirectory(at: paperDirectoryURL, withIntermediateDirectories: true)
        try writeValidPDF(to: paperDirectoryURL.appendingPathComponent("paper.pdf"))

        MinerUAPIMockURLProtocol.zipData = try zipData(entries: [
            (
                "full.md",
                Data(
                    """
                    # MinerU Output

                    ![Figure](images/figure-1.png)

                    <img src="images/figure-2.webp" alt="Second">
                    """.utf8
                )
            ),
            ("images/figure-1.png", Data([0x89, 0x50, 0x4E, 0x47])),
            ("images/figure-2.webp", Data("WEBP".utf8))
        ])
        MinerUAPIMockURLProtocol.requestLog = []

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MinerUAPIMockURLProtocol.self]
        let service = PaperMarkdownConversionService(session: URLSession(configuration: sessionConfiguration))
        let results = try await service.convert(
            [paper],
            in: workspace,
            configuration: PaperMarkdownConversionConfiguration(
                minerUAPIToken: "test-token",
                minerUAPIBaseURLString: "https://mineru.test",
                overwriteExistingMarkdown: true,
                pollIntervalSeconds: 1,
                pollTimeoutSeconds: 5
            )
        )

        let result = try require(results.first, "MinerU conversion should return a result.")
        try expect(result.didWriteMarkdown, result.errorMessage ?? "MinerU conversion should write paper.md.")

        let paperMarkdownURL = paper.rawMarkdownURL(in: workspace)
        let markdown = try String(contentsOf: paperMarkdownURL, encoding: .utf8)
        try expect(markdown.contains("extraction_engine: mineru_api"), "MinerU conversion should record the API extraction engine.")
        try expect(markdown.contains("![Figure](figures/mineru/images/figure-1.png)"), "Markdown image links should point to copied MinerU assets.")
        try expect(markdown.contains("<img src=\"figures/mineru/images/figure-2.webp\""), "HTML image links should point to copied MinerU assets.")
        try expect(
            FileManager.default.fileExists(atPath: paperDirectoryURL.appendingPathComponent("figures/mineru/images/figure-1.png").path),
            "MinerU PNG assets should be copied into the paper figures directory."
        )
        try expect(
            FileManager.default.fileExists(atPath: paperDirectoryURL.appendingPathComponent("figures/mineru/images/figure-2.webp").path),
            "MinerU WebP assets should be copied into the paper figures directory."
        )
        try expect(
            MinerUAPIMockURLProtocol.requestLog.contains("PUT upload.test/upload/mineru-images-paper.pdf"),
            "MinerU conversion should upload the PDF to the signed upload URL."
        )
        try expect(
            MinerUAPIMockURLProtocol.uploadContentTypeHeaders == [nil],
            "MinerU signed URL upload should not include a Content-Type header."
        )
    }

    func movePaperToCollectionUpdatesMetadataAndPath() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = PaperRepository()
        let moveService = MovePaperToCollectionService(paperRepository: repository)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("MovePaperWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let originalPaper = try await repository.save(samplePaper(id: "move-test-paper"), in: workspace)
        let originalDirectoryURL = workspace.directoryURL(for: originalPaper.paperDirectoryRelativePath)
        try writeValidPDF(to: originalDirectoryURL.appendingPathComponent("paper.pdf"))

        let movedPaper = try await moveService.move(originalPaper, to: "Dark-Matter/WIMPs", in: workspace)

        try expect(
            movedPaper.paperDirectoryRelativePath == "library/papers/Dark-Matter/WIMPs/move-test-paper",
            "Moving a paper should update its nested directory path."
        )
        try expect(movedPaper.collectionPath == "Dark-Matter/WIMPs", "Moving a paper should update collection_path.")
        try expect(
            movedPaper.notesSummaryRelativePath == "../../../../../wiki/papers/smith2024graph.md",
            "Moving a paper should recompute the summary relative path from the new folder depth."
        )

        let movedMetadata = try String(
            contentsOf: workspace.directoryURL(for: movedPaper.paperDirectoryRelativePath).appendingPathComponent("meta.yaml"),
            encoding: .utf8
        )
        try expect(movedMetadata.contains("collection_path: \"Dark-Matter/WIMPs\""), "Moved metadata should persist the new collection_path.")
    }

    func paperMarkdownDirectLoadMergesIntoDocumentList() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: WorkspaceBookmarkStore(defaults: defaults))
        let repository = MarkdownRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("PaperMarkdownDirectLoadWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let paperMarkdownPath = "library/papers/Uncategorized/direct-paper/paper.md"
        let paperMarkdownURL = workspace.fileURL(for: paperMarkdownPath)
        try FileManager.default.createDirectory(at: paperMarkdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# Direct Paper\n".write(to: paperMarkdownURL, atomically: true, encoding: .utf8)

        var documents = try await repository.loadDocuments(in: workspace)
        try expect(!documents.contains(where: { $0.relativePath == paperMarkdownPath }), "paper.md outside wiki should not be part of the default wiki scan.")
        let directDocument = try await repository.loadDocument(relativePath: paperMarkdownPath, in: workspace)
        if !documents.contains(where: { $0.id == directDocument.id }) {
            documents.append(directDocument)
        }

        try expect(documents.contains(where: { $0.relativePath == paperMarkdownPath }), "Direct paper.md load should be mergeable into the active document list without changing wiki scan semantics.")
    }
}
