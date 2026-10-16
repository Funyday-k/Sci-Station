import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppViewModel {
    func reloadLibrary() {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func refreshLegacyPaperMigrationPlan() {
        guard let currentWorkspace else {
            return
        }

        isLoadingLegacyPaperMigrationPlan = true
        Task {
            defer {
                isLoadingLegacyPaperMigrationPlan = false
            }

            do {
                try await loadLegacyPaperMigrationPlan(in: currentWorkspace)
                if legacyPaperMigrationPlan.hasLegacyPapers {
                    workspaceSettingsStatusMessage = localized(
                        "Legacy 扫描发现 \(legacyPaperMigrationPlan.legacyPaperCount) 个 raw/papers 项。",
                        "Legacy scan found \(legacyPaperMigrationPlan.legacyPaperCount) raw/papers items."
                    )
                } else {
                    workspaceSettingsStatusMessage = localized(
                        "未发现 legacy raw/papers 项。",
                        "No legacy raw/papers items found."
                    )
                }
            } catch {
                present(error)
            }
        }
    }

    func copyReadyLegacyPapers() {
        guard let currentWorkspace, legacyPaperMigrationPlan.readyCount > 0 else {
            return
        }

        isRunningLegacyPaperMigration = true
        Task {
            defer {
                isRunningLegacyPaperMigration = false
            }

            do {
                let report = try await legacyPaperMigrationService.copyReadyItems(in: currentWorkspace)
                legacyPaperMigrationReport = report
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                workspaceSettingsStatusMessage = localized(
                    "已复制 \(report.copiedCount) 篇 legacy 论文；跳过 \(report.skippedCount)，失败 \(report.failedCount)。报告：\(report.reportRelativePath ?? "未写入")。",
                    "Copied \(report.copiedCount) legacy papers. Skipped \(report.skippedCount), failed \(report.failedCount). Report: \(report.reportRelativePath ?? "not written")."
                )
            } catch {
                present(error)
            }
        }
    }

    func reloadWiki() {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: selectedMarkdownID)
            } catch {
                present(error)
            }
        }
    }

    func importPDF() {
        guard let currentWorkspace, let pdfURL = Self.selectPDFURL() else {
            return
        }

        importPDF(from: pdfURL, into: currentWorkspace)
    }

    func importPDFFromGlobalMenu() {
        guard currentWorkspace != nil else {
            return
        }
        ensurePaperImportContextForGlobalMenu()
        importPDF()
    }

    func prepareIdentifierImport(initialInput: String? = nil) {
        identifierImportInput = initialInput ?? ""
        identifierImportCollectionPath = selectedCollectionPath ?? workspacePreferences.defaultCollectionPath ?? "Uncategorized"
        identifierImportTagsText = ""
        identifierImportPreview = nil
        identifierImportStatusMessage = nil
    }

    func beginIdentifierImport(with initialInput: String? = nil) {
        prepareIdentifierImport(initialInput: initialInput)
        isShowingIdentifierImport = true
    }

    func beginIdentifierImportFromGlobalMenu() {
        guard currentWorkspace != nil else {
            return
        }
        ensurePaperImportContextForGlobalMenu()
        beginIdentifierImport()
    }

    func resetIdentifierImportForm() {
        prepareIdentifierImport()
    }

    func previewIdentifierImport() {
        guard let input = identifierImportInputs.first else {
            identifierImportPreview = nil
            return
        }

        identifierImportStatusMessage = nil

        isResolvingIdentifierImport = true

        Task {
            defer {
                isResolvingIdentifierImport = false
            }

            do {
                identifierImportPreview = try await remoteImportService.preview(for: input)
            } catch {
                present(error)
            }
        }
    }

    func performIdentifierImport(onSuccess: (() -> Void)? = nil) {
        guard let currentWorkspace else {
            return
        }

        let importInputs = identifierImportInputs
        guard !importInputs.isEmpty else {
            return
        }

        identifierImportStatusMessage = nil

        isPerformingIdentifierImport = true

        Task {
            defer {
                isPerformingIdentifierImport = false
            }

            do {
                let importCollectionPath = identifierImportCollectionPath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty ?? "Uncategorized"
                let importTags = commaSeparatedValues(from: identifierImportTagsText)
                var existingPapers = papers
                var importedPaperID: Paper.ID?
                var importedPapers: [Paper] = []
                var failedInputs: [(String, Error)] = []

                for input in importInputs {
                    do {
                        var importedPaper = try await remoteImportService.importItem(
                            from: input,
                            draftPreview: importInputs.count == 1 ? identifierImportPreview : nil,
                            into: currentWorkspace,
                            existingPapers: existingPapers,
                            collectionPath: importCollectionPath,
                            tags: importTags
                        )
                        if let selectedLibraryProjectID,
                           !importedPaper.projectIDs.contains(selectedLibraryProjectID) {
                            importedPaper.projectIDs.append(selectedLibraryProjectID)
                            importedPaper = try await paperRepository.save(importedPaper, in: currentWorkspace)
                        }
                        existingPapers.append(importedPaper)
                        importedPaperID = importedPaper.id
                        importedPapers.append(importedPaper)
                    } catch {
                        failedInputs.append((input, error))
                    }
                }

                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: importedPaperID ?? selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                selectedSection = .library
                selectedProjectSpaceProjectID = nil
                persistWorkspaceRoute(WorkspaceRoute(top: .library))
                if !importedPapers.isEmpty {
                    startMarkdownConversion(for: importedPapers, in: currentWorkspace, statusSurface: .workspace)
                }

                let importedCount = importInputs.count - failedInputs.count
                if failedInputs.isEmpty {
                    identifierImportStatusMessage = importedCount > 1 ? "Imported \(importedCount) papers." : "Imported 1 paper."
                    isShowingIdentifierImport = false
                    identifierImportPreview = nil
                    identifierImportInput = ""
                    identifierImportTagsText = ""
                    onSuccess?()
                } else {
                    identifierImportInput = failedInputs.map { $0.0 }.joined(separator: "\n")
                    identifierImportPreview = nil
                    let failedSummary = failedInputs
                        .prefix(3)
                        .map { failedInput in "\(failedInput.0): \(failedInput.1.localizedDescription)" }
                        .joined(separator: " | ")
                    identifierImportStatusMessage = "Imported \(importedCount) of \(importInputs.count). Failed: \(failedSummary)"
                }
            } catch {
                present(error)
            }
        }
    }

    func openSelectedPaperReader() {
        guard canEnterSelectedPaperReader else {
            return
        }

        selectedSection = .pdfReader
    }

    func handlePDFDrop(providers: [NSItemProvider]) -> Bool {
        guard let currentWorkspace else {
            return false
        }

        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        let typeIdentifier = provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            ? UTType.pdf.identifier
            : UTType.fileURL.identifier
        provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { fileURL, isInPlace, _ in
            guard let fileURL else {
                return
            }

            let importURL: URL
            let shouldRemoveTemporaryFile: Bool
            if isInPlace {
                importURL = fileURL
                shouldRemoveTemporaryFile = false
            } else {
                let pathExtension = fileURL.pathExtension.isEmpty ? "pdf" : fileURL.pathExtension
                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(pathExtension)
                do {
                    if FileManager.default.fileExists(atPath: temporaryURL.path) {
                        try FileManager.default.removeItem(at: temporaryURL)
                    }
                    try FileManager.default.copyItem(at: fileURL, to: temporaryURL)
                } catch {
                    return
                }
                importURL = temporaryURL
                shouldRemoveTemporaryFile = true
            }

            Task { @MainActor in
                defer {
                    if shouldRemoveTemporaryFile {
                        try? FileManager.default.removeItem(at: importURL)
                    }
                }
                self.importPDF(from: importURL, into: currentWorkspace)
            }
        }

        return true
    }

    func selectPaper(id: Paper.ID?) {
        selectedLibraryPaperIDs = id.map { [$0] } ?? []
        applySelectedPaper(id: id)
    }

    func updateLibrarySelection(_ selection: Set<Paper.ID>) {
        selectedLibraryPaperIDs = selection
        if selection.count == 1 {
            applySelectedPaper(id: selection.first)
        } else {
            selectedPaperID = nil
            selectedPaperDraft = nil
            selectedPaperAnnotationsDraft = ""
            paperMarkdownQualityReport = nil
        }
    }

    func clearLibrarySelection() {
        updateLibrarySelection([])
    }

    func previewLibrarySelection() {
        guard let paper = previewPaperForLibrarySelection() else {
            libraryBatchStatusMessage = "No selected paper has a PDF to preview."
            return
        }

        openPaperPDF(paper)
    }

    func previewPaper(_ paper: Paper) {
        guard canOpenPDF(for: paper) else {
            libraryBatchStatusMessage = "No PDF is available for \(paper.displayTitle)."
            return
        }

        openPaperPDF(paper)
    }

    func applySelectedPaper(id: Paper.ID?) {
        selectedPaperID = id
        selectedPaperDraft = papers.first(where: { $0.id == id })
        paperMarkdownQualityReport = nil
        selectedPDFAnnotations = []
        selectedPDFSelectionPreview = nil
        selectedPDFSelectionPageIndex = nil
        guard let currentWorkspace else {
            selectedPaperAnnotationsDraft = ""
            return
        }

        Task {
            do {
                try await loadSelectedPaperAnnotations(in: currentWorkspace)
                try await loadSelectedPDFAnnotations(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func updateSelectedPaper(_ mutate: (inout Paper) -> Void) {
        guard var draft = selectedPaperDraft else {
            return
        }

        mutate(&draft)
        selectedPaperDraft = draft
    }

    func discardSelectedPaperChanges() {
        selectPaper(id: selectedPaperID)
    }

    func canOpenPDF(for paper: Paper) -> Bool {
        guard let currentWorkspace else { return false }
        return localPDFURL(for: paper, in: currentWorkspace) != nil || remotePDFURL(for: paper) != nil
    }

    func openPaperReader(_ paper: Paper) {
        let returnRoute = currentWorkspaceRoute
        selectPaper(id: paper.id)
        guard let currentWorkspace else { return }

        if localPDFURL(for: paper, in: currentWorkspace) != nil {
            activatePaperReader(returnRoute: returnRoute)
            return
        }

        guard remotePDFURL(for: paper) != nil else {
            libraryBatchStatusMessage = localized("没有可打开的 PDF。", "No PDF is available to open.")
            return
        }

        Task {
            do {
                showShellStatus(localized("正在下载 PDF…", "Downloading PDF…"))
                let updatedPaper = try await ensureLocalPDFAvailable(for: paper, in: currentWorkspace)
                selectPaper(id: updatedPaper.id)
                activatePaperReader(returnRoute: returnRoute)
                showShellStatus(localized("PDF 已下载并打开。", "PDF downloaded and opened."))
            } catch {
                libraryBatchStatusMessage = localized("无法打开 PDF：\(error.localizedDescription)", "Could not open PDF: \(error.localizedDescription)")
                present(error)
            }
        }
    }

    func activatePaperReader(returnRoute: WorkspaceRoute) {
        paperReaderReturnRoute = returnRoute
        selectedSection = .pdfReader
        showContextInspector(source: "paper_reader_open")
        persistWorkspaceRoute(currentWorkspaceRoute)
    }

    func localPDFURL(for paper: Paper, in workspace: ResearchWorkspace) -> URL? {
        guard let pdfURL = paper.pdfURL(in: workspace), FileManager.default.fileExists(atPath: pdfURL.path) else {
            return nil
        }
        return pdfURL
    }

    func remotePDFURL(for paper: Paper) -> URL? {
        guard let value = paper.pdfURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    func ensureLocalPDFAvailable(for paper: Paper, in workspace: ResearchWorkspace) async throws -> Paper {
        if localPDFURL(for: paper, in: workspace) != nil {
            return paper
        }
        guard let remoteURL = remotePDFURL(for: paper) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let downloadedURL = try await pdfDownloadService.downloadPDF(from: remoteURL)
        var updatedPaper = papers.first(where: { $0.id == paper.id }) ?? paper
        let directoryURL = workspace.directoryURL(for: updatedPaper.paperDirectoryRelativePath)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let targetURL = directoryURL.appendingPathComponent("paper.pdf", isDirectory: false)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.moveItem(at: downloadedURL, to: targetURL)
        updatedPaper.pdfRelativePath = "paper.pdf"
        updatedPaper.updatedAt = Date()
        let savedPaper = try await paperRepository.save(updatedPaper, in: workspace)
        try await loadWorkspaceData(in: workspace, selectingPaper: savedPaper.id, selectingMarkdown: selectedMarkdownID)
        return savedPaper
    }

    func returnFromPaperReader() {
        if let returnRoute = paperReaderReturnRoute {
            paperReaderReturnRoute = nil
            applyWorkspaceRoute(returnRoute)
            return
        }

        if let projectID = selectedProjectSpaceProjectID ?? currentProjectID,
           activeResearchProjects.contains(where: { $0.id == projectID }) {
            selectResearchProject(projectID, section: .library)
            return
        }

        selectSection(.library)
    }

    func openEvidenceSource(_ jump: AgentEvidenceSourceJump) {
        if let page = jump.pdfPage,
           let sourceID = jump.sourceID,
           let paper = papers.first(where: { $0.id == sourceID || $0.paperDirectoryRelativePath.contains(sourceID) }) {
            selectedLibraryPaperIDs = [paper.id]
            selectedPaperID = paper.id
            var draft = paper
            draft.lastReadPage = page
            selectedPaperDraft = draft
            selectedSection = .pdfReader
            agentStatusMessage = "Opened PDF Reader at page \(page) for \(jump.lineTargetDescription)."
            return
        }

        guard let url = jump.sourceURL else {
            agentErrorMessage = jump.warning ?? "Evidence source is unavailable."
            return
        }

        if NSWorkspace.shared.open(url) {
            agentStatusMessage = "Opened source target: \(jump.lineTargetDescription)."
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            agentStatusMessage = "Could not open the line target directly; revealed source file for \(jump.lineTargetDescription)."
        }
    }

    func saveSelectedPaperChanges() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        isSavingSelectedPaper = true
        Task {
            defer {
                isSavingSelectedPaper = false
            }

            do {
                let savedPaper = try await paperRepository.save(selectedPaperDraft, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: savedPaper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func openSelectedPaperPDF() {
        guard let selectedPaperDraft else {
            return
        }

        openPaperPDF(selectedPaperDraft)
    }

    func openPaperPDF(_ paper: Paper) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                let pdfURL: URL
                if let localURL = localPDFURL(for: paper, in: currentWorkspace) {
                    pdfURL = localURL
                } else {
                    let updatedPaper = try await ensureLocalPDFAvailable(for: paper, in: currentWorkspace)
                    guard let localURL = localPDFURL(for: updatedPaper, in: currentWorkspace) else {
                        return
                    }
                    pdfURL = localURL
                }
                try await pdfOpeningService.openPDF(at: pdfURL, page: nil)
            } catch {
                present(error)
            }
        }
    }

    func previewPaperForLibrarySelection() -> Paper? {
        if let selectedPaperDraft, canOpenPDF(for: selectedPaperDraft) {
            return selectedPaperDraft
        }

        return selectedLibraryPapers.first { canOpenPDF(for: $0) }
    }

    func requestDeleteSelectedPaper() {
        guard let selectedPaperDraft else {
            return
        }

        requestDeletePaper(selectedPaperDraft)
    }

    func requestDeletePaper(_ paper: Paper) {
        paperPendingDeletion = paper
        isShowingPaperDeleteConfirmation = true
    }

    func exportBibTeX(for paper: Paper) {
        let bibtex = BibTeXFormatter.bibTeX(for: paper)
        bibTeXExportText = bibtex
        bibTeXExportFileName = "\(paper.citekey).bib"

        copyBibTeX(for: paper)
        isShowingBibTeXExport = true
    }

    func copyBibTeX(for paper: Paper) {
        let bibtex = BibTeXFormatter.bibTeX(for: paper)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bibtex, forType: .string)
    }

    func copyCitation(for paper: Paper) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.citationText(for: paper), forType: .string)
    }

    func exportSelectedPaperBibTeX() {
        if selectedLibraryPapers.count > 1 {
            exportBibTeXForLibrarySelection()
            return
        }

        guard let selectedPaperDraft else {
            return
        }

        exportBibTeX(for: selectedPaperDraft)
    }

    func copySelectedPaperBibTeX() {
        if selectedLibraryPapers.count > 1 {
            copyBibTeXForLibrarySelection()
            return
        }

        guard let selectedPaperDraft else {
            return
        }

        copyBibTeX(for: selectedPaperDraft)
    }

    func copySelectedPaperCitation() {
        let papersToCopy = selectedLibraryPapers.count > 1 ? selectedLibraryPapers : selectedPaperDraft.map { [$0] } ?? []
        guard !papersToCopy.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(papersToCopy.map(Self.citationText(for:)).joined(separator: "\n"), forType: .string)
    }

    func copyBibTeXForLibrarySelection() {
        let papersToCopy = selectedLibraryPapers
        guard !papersToCopy.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.joinedBibTeX(for: papersToCopy), forType: .string)
    }

    func exportBibTeXForLibrarySelection() {
        let papersToExport = selectedLibraryPapers
        guard !papersToExport.isEmpty else {
            return
        }

        bibTeXExportText = Self.joinedBibTeX(for: papersToExport)
        bibTeXExportFileName = papersToExport.count == 1 ? "\(papersToExport[0].citekey).bib" : "selected-\(papersToExport.count)-references.bib"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bibTeXExportText, forType: .string)
        isShowingBibTeXExport = true
    }

    func dismissBibTeXExport() {
        isShowingBibTeXExport = false
    }

    func setStatusForLibrarySelection(_ status: ReadingStatus) {
        runLibrarySelectionBatchEdit(summary: "Set status to \(status.label)") { ids, workspace in
            try await self.libraryBulkEditService.setStatus(status, for: ids, in: workspace)
        }
    }

    func setPriorityForLibrarySelection(_ priority: Priority) {
        runLibrarySelectionBatchEdit(summary: "Set priority to \(priority.label)") { ids, workspace in
            try await self.libraryBulkEditService.setPriority(priority, for: ids, in: workspace)
        }
    }

    func setRatingForLibrarySelection(_ rating: Int?) {
        let summary = rating.map { "Set rating to \($0)" } ?? "Clear rating"
        runLibrarySelectionBatchEdit(summary: summary) { ids, workspace in
            try await self.libraryBulkEditService.setRating(rating, for: ids, in: workspace)
        }
    }

    func moveLibrarySelection(to collectionPath: String) {
        runLibrarySelectionBatchEdit(summary: "Move to \(collectionPath)") { ids, workspace in
            try await self.libraryBulkEditService.moveToCollection(collectionPath, for: ids, in: workspace)
        }
    }

    func addTagsToLibrarySelection(_ tagsText: String? = nil) {
        let tags = commaSeparatedValues(from: tagsText ?? libraryBatchTagText)
        guard !tags.isEmpty else {
            libraryBatchStatusMessage = "Enter at least one tag to add."
            return
        }

        runLibrarySelectionBatchEdit(summary: "Add tags \(tags.joined(separator: ", "))") { ids, workspace in
            try await self.libraryBulkEditService.addTags(tags, for: ids, in: workspace)
        }
    }

    func removeTagsFromLibrarySelection(_ tagsText: String? = nil) {
        let tags = commaSeparatedValues(from: tagsText ?? libraryBatchTagText)
        guard !tags.isEmpty else {
            libraryBatchStatusMessage = "Enter at least one tag to remove."
            return
        }

        runLibrarySelectionBatchEdit(summary: "Remove tags \(tags.joined(separator: ", "))") { ids, workspace in
            try await self.libraryBulkEditService.removeTags(tags, for: ids, in: workspace)
        }
    }

    func runLibrarySelectionBatchEdit(
        summary: String,
        operation: @escaping @Sendable (Set<Paper.ID>, ResearchWorkspace) async throws -> [Paper]
    ) {
        guard let currentWorkspace else {
            return
        }

        let selectedIDs = selectedLibraryPaperIDs
        guard !selectedIDs.isEmpty else {
            libraryBatchStatusMessage = "Select papers before running a batch action."
            return
        }

        libraryBatchStatusMessage = "\(summary) for \(selectedIDs.count) selected papers..."
        Task {
            do {
                let updatedPapers = try await operation(selectedIDs, currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                selectedLibraryPaperIDs = selectedIDs.intersection(Set(papers.map(\.id)))
                if selectedLibraryPaperIDs.count == 1 {
                    applySelectedPaper(id: selectedLibraryPaperIDs.first)
                } else {
                    selectedPaperID = nil
                    selectedPaperDraft = nil
                    selectedPaperAnnotationsDraft = ""
                }
                libraryBatchStatusMessage = "\(summary) completed for \(updatedPapers.count) papers."
            } catch {
                present(error)
            }
        }
    }

    func saveExportedBibTeXToFile() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = bibTeXExportFileName
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [UTType(filenameExtension: "bib") ?? .plainText]

        guard savePanel.runModal() == .OK,
              let destinationURL = savePanel.url else {
            return
        }

        do {
            try bibTeXExportText.write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            present(error)
        }
    }

    func cancelPaperDeletion() {
        isShowingPaperDeleteConfirmation = false
        paperPendingDeletion = nil
    }

    func confirmDeletePendingPaper() {
        guard let currentWorkspace, let paper = paperPendingDeletion else {
            cancelPaperDeletion()
            return
        }

        isShowingPaperDeleteConfirmation = false
        paperPendingDeletion = nil
        selectedPaperID = nil
        selectedLibraryPaperIDs = []
        selectedPaperDraft = nil

        Task {
            do {
                try await paperRepository.delete(paper, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: nil,
                    selectingMarkdown: selectedMarkdownID
                )
                selectedSection = .library
                selectedProjectSpaceProjectID = nil
                persistWorkspaceRoute(WorkspaceRoute(top: .library))
            } catch {
                present(error)
            }
        }
    }

    func saveSelectedPaperReadingState(lastPage: Int, scaleFactor: Double?) {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        Task {
            do {
                let savedPaper = try await pdfReadingStateService.save(
                    lastPage: lastPage,
                    scaleFactor: scaleFactor,
                    for: selectedPaperDraft,
                    in: currentWorkspace
                )
                papers = papers.map { $0.id == savedPaper.id ? savedPaper : $0 }
                self.selectedPaperDraft = savedPaper
            } catch {
                present(error)
            }
        }
    }

    func saveSelectedPaperAnnotations() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        isSavingSelectedPaperAnnotations = true
        let contents = selectedPaperAnnotationsDraft
        Task {
            defer {
                isSavingSelectedPaperAnnotations = false
            }

            do {
                try await paperAnnotationsRepository.saveAnnotations(contents, for: selectedPaperDraft, in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func reloadSelectedPDFAnnotations() {
        guard let currentWorkspace else {
            selectedPDFAnnotations = []
            return
        }

        Task {
            do {
                try await loadSelectedPDFAnnotations(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func updatePDFSelection(preview: String?, pageIndex: Int?) {
        selectedPDFSelectionPreview = preview.map { limitedText($0, maxCharacters: 800) }
        selectedPDFSelectionPageIndex = pageIndex
    }

    func createPDFAnnotation(_ annotation: PDFAnnotationRecord) {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        var annotation = annotation
        if annotation.selectionFingerprint?.isEmpty != false {
            annotation.selectionFingerprint = annotation.duplicateFingerprint
        }

        if annotation.kind != .note,
           selectedPDFAnnotations.contains(where: { existing in
               existing.kind == annotation.kind && existing.duplicateFingerprint == annotation.duplicateFingerprint
           }) {
            recordAppDebugEvent("pdf.annotation.duplicate_skipped", payload: pdfAnnotationDebugPayload(annotation))
            return
        }

        Task {
            do {
                selectedPDFAnnotations = deduplicatedPDFAnnotations(try await pdfAnnotationStore.upsertAnnotation(annotation, for: selectedPaperDraft, in: currentWorkspace))
                recordAppDebugEvent("pdf.annotation.create", payload: pdfAnnotationDebugPayload(annotation))
            } catch {
                present(error)
            }
        }
    }

    func updatePDFAnnotationNote(id: PDFAnnotationRecord.ID, noteText: String) {
        guard let currentWorkspace, let selectedPaperDraft,
              let index = selectedPDFAnnotations.firstIndex(where: { $0.id == id }) else {
            return
        }

        var annotation = selectedPDFAnnotations[index]
        annotation.noteText = noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : noteText
        annotation.updatedAt = Date()
        selectedPDFAnnotations[index] = annotation

        Task {
            do {
                selectedPDFAnnotations = deduplicatedPDFAnnotations(try await pdfAnnotationStore.upsertAnnotation(annotation, for: selectedPaperDraft, in: currentWorkspace))
                recordAppDebugEvent("pdf.annotation.update", payload: pdfAnnotationDebugPayload(annotation))
            } catch {
                present(error)
            }
        }
    }

    func deletePDFAnnotation(id: PDFAnnotationRecord.ID) {
        guard let currentWorkspace, let selectedPaperDraft,
              let annotation = selectedPDFAnnotations.first(where: { $0.id == id }) else {
            return
        }

        selectedPDFAnnotations.removeAll { $0.id == id }
        Task {
            do {
                selectedPDFAnnotations = deduplicatedPDFAnnotations(try await pdfAnnotationStore.deleteAnnotation(id: id, for: selectedPaperDraft, in: currentWorkspace))
                recordAppDebugEvent("pdf.annotation.delete", payload: pdfAnnotationDebugPayload(annotation))
            } catch {
                present(error)
            }
        }
    }

    func movePDFAnnotationNote(id: PDFAnnotationRecord.ID, pageIndex: Int, x: Double, y: Double) {
        guard let currentWorkspace, let selectedPaperDraft,
              let index = selectedPDFAnnotations.firstIndex(where: { $0.id == id && $0.kind == .note }) else {
            return
        }

        var annotation = selectedPDFAnnotations[index]
        annotation.pageIndex = pageIndex
        annotation.bounds = [PDFAnnotationBounds(
            pageIndex: pageIndex,
            x: x,
            y: y,
            width: 24,
            height: 24
        )]
        annotation.updatedAt = Date()
        selectedPDFAnnotations[index] = annotation

        Task {
            do {
                selectedPDFAnnotations = deduplicatedPDFAnnotations(try await pdfAnnotationStore.upsertAnnotation(annotation, for: selectedPaperDraft, in: currentWorkspace))
                recordAppDebugEvent("pdf.annotation.update", payload: pdfAnnotationDebugPayload(annotation))
            } catch {
                present(error)
            }
        }
    }

}
