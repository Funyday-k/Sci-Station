import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppViewModel {
    func updateSummaryPreviewText(_ newValue: String) {
        summaryPreviewText = newValue
    }

    func createCollection(relativePath: String) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                let collection = try await collectionRepository.createCollection(at: relativePath, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                selectCollection(collection.relativePath)
            } catch {
                present(error)
            }
        }
    }

    func createSubfolder(in parentPath: String?) {
        let trimmedParentPath = parentPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty
        let basePath = [trimmedParentPath, "New Folder"].compactMap { $0 }.joined(separator: "/")
        let existingPaths = Set(collections.map(\.relativePath))
        var candidate = basePath
        var suffix = 2
        while existingPaths.contains(candidate) {
            candidate = [trimmedParentPath, "New Folder \(suffix)"].compactMap { $0 }.joined(separator: "/")
            suffix += 1
        }
        createCollection(relativePath: candidate)
    }

    func renameSelectedCollection(to newName: String) {
        guard let currentWorkspace, let selectedCollectionPath else {
            return
        }

        Task {
            do {
                let collection = try await collectionRepository.renameCollection(
                    at: selectedCollectionPath,
                    to: newName,
                    in: currentWorkspace
                )
                let movedPapers = try await paperRepository.loadPapers(in: currentWorkspace)
                    .filter { paper in
                        paper.collectionPath == collection.relativePath
                            || paper.collectionPath?.hasPrefix(collection.relativePath + "/") == true
                    }
                for paper in movedPapers {
                    _ = try await paperRepository.save(paper, in: currentWorkspace)
                }
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                selectCollection(collection.relativePath)
            } catch {
                present(error)
            }
        }
    }

    func deleteSelectedCollection() {
        guard let currentWorkspace, let selectedCollectionPath else {
            return
        }

        Task {
            do {
                try await collectionRepository.deleteCollection(at: selectedCollectionPath, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                clearLibraryFilters()
            } catch {
                present(error)
            }
        }
    }

    func moveSelectedPaper(to collectionPath: String) {
        guard let selectedPaperDraft else {
            return
        }

        movePaper(selectedPaperDraft, to: collectionPath)
    }

    func movePaper(_ paper: Paper, to collectionPath: String) {
        guard let currentWorkspace else {
            return
        }

        let normalizedPath = collectionPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if (paper.collectionPath ?? "") == normalizedPath {
            return
        }

        Task {
            do {
                let movedPaper = try await movePaperToCollectionService.move(
                    paper,
                    to: collectionPath,
                    in: currentWorkspace
                )
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: movedPaper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func togglePaperProject(_ paper: Paper, projectID: ResearchProject.ID) {
        setPaperProjectMembership(paper, projectID: projectID, isMember: projectPaperLink(for: paper, projectID: projectID) == nil)
    }

    func togglePaperCoreProject(_ paper: Paper, projectID: ResearchProject.ID) {
        let isCore = projectPaperLink(for: paper, projectID: projectID)?.isCore == true
        setPaperProjectCore(paper, projectID: projectID, isCore: !isCore)
    }

    func setPaperProjectMembership(_ paper: Paper, projectID: ResearchProject.ID, isMember: Bool) {
        guard let currentWorkspace else {
            return
        }

        let existingLink = projectPaperLink(for: paper, projectID: projectID)

        Task {
            do {
                if isMember {
                    let link = existingLink ?? ProjectPaperLink(projectID: projectID, paperID: paper.id)
                    _ = try await projectPaperLinkRepository.upsert(link, in: currentWorkspace)
                } else {
                    _ = try await projectPaperLinkRepository.remove(projectID: projectID, paperID: paper.id, in: currentWorkspace)
                }
                try await syncPaperProjectMetadataMirror(forPaperID: paper.id, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: paper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func setPaperProjectCore(_ paper: Paper, projectID: ResearchProject.ID, isCore: Bool) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                _ = try await projectPaperLinkRepository.setCore(isCore, projectID: projectID, paperID: paper.id, in: currentWorkspace)
                try await syncPaperProjectMetadataMirror(forPaperID: paper.id, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: paper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func setPaperProjectPinned(_ paper: Paper, projectID: ResearchProject.ID, isPinned: Bool) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                _ = try await projectPaperLinkRepository.setPinned(isPinned, projectID: projectID, paperID: paper.id, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: paper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func updatePaperProjectUseFor(_ paper: Paper, projectID: ResearchProject.ID, text: String) {
        guard let currentWorkspace else {
            return
        }

        let useFor = commaSeparatedValues(from: text)
        Task {
            do {
                _ = try await projectPaperLinkRepository.updateUseFor(useFor, projectID: projectID, paperID: paper.id, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: paper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func updatePaperProjectFolderPath(_ paper: Paper, projectID: ResearchProject.ID, folderPath: String) {
        guard let currentWorkspace else {
            return
        }

        let trimmedFolderPath = folderPath.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty
        Task {
            do {
                _ = try await projectPaperLinkRepository.updateFolderPath(trimmedFolderPath, projectID: projectID, paperID: paper.id, in: currentWorkspace)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: paper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func syncPaperProjectMetadataMirror(forPaperID paperID: Paper.ID, in workspace: ResearchWorkspace) async throws {
        let links = try await projectPaperLinkRepository.links(forPaperID: paperID, in: workspace)
        guard var paper = selectedPaperDraft?.id == paperID ? selectedPaperDraft : papers.first(where: { $0.id == paperID }) else {
            return
        }

        paper.projectIDs = uniqueOrdered(links.map(\.projectID))
        paper.coreProjectIDs = uniqueOrdered(links.filter(\.isCore).map(\.projectID))
        _ = try await paperRepository.saveMetadataMirror(paper, in: workspace)
    }

    func savePaperClassification(_ paper: Paper, in workspace: ResearchWorkspace) {
        Task {
            do {
                let savedPaper = try await paperRepository.save(paper, in: workspace)
                try await loadWorkspaceData(
                    in: workspace,
                    selectingPaper: savedPaper.id,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                present(error)
            }
        }
    }

    func saveTagDefinition(name: String, colorHex: String, textColorHex: String?) {
        guard let currentWorkspace else {
            return
        }

        let definition = TagDefinition(
            name: name,
            colorHex: colorHex,
            textColorHex: textColorHex?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty
        )

        Task {
            do {
                try await tagRepository.upsert(definition, in: currentWorkspace)
                try await loadTags(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func deleteTagDefinition(named name: String) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await tagRepository.deleteTag(named: name, in: currentWorkspace)
                try await loadTags(in: currentWorkspace)
                if selectedTagName == name {
                    selectedTagName = nil
                }
            } catch {
                present(error)
            }
        }
    }

    func selectDashboardDate(_ date: Date) {
        selectedDashboardDate = Calendar.current.startOfDay(for: date)
        if systemCalendarAccessState.canReadSchedule {
            refreshSystemSchedule(around: selectedDashboardDate)
        }
    }

    func requestSystemCalendarAccess() {
        isLoadingSystemSchedule = true

        Task {
            defer {
                isLoadingSystemSchedule = false
            }

            do {
                systemCalendarAccessState = try await systemCalendarService.requestAccess()
                if systemCalendarAccessState.canReadSchedule {
                    try await loadSystemSchedule(around: selectedDashboardDate)
                }
            } catch {
                systemCalendarAccessState = systemCalendarService.accessState
                present(error)
            }
        }
    }

    func refreshSystemSchedule(around referenceDate: Date? = nil) {
        systemCalendarAccessState = systemCalendarService.accessState
        guard systemCalendarAccessState.canReadSchedule else {
            return
        }

        isLoadingSystemSchedule = true

        Task {
            defer {
                isLoadingSystemSchedule = false
            }

            do {
                try await loadSystemSchedule(around: referenceDate ?? selectedDashboardDate)
            } catch {
                present(error)
            }
        }
    }

    func addTodo(
        title: String,
        startDate: Date? = nil,
        dueDate: Date?,
        kind: TodoKind = .general,
        priority: Priority = .medium,
        notes: String? = nil,
        projectIDs: [ResearchProject.ID]? = nil,
        tags: [String]? = nil,
        relatedPaperIDs: [String]? = nil
    ) {
        guard let currentWorkspace else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        let now = Date()
        let resolvedTags = tags ?? selectedTagName.map { [$0] } ?? []
        let resolvedPaperIDs = relatedPaperIDs ?? selectedPaperDraft.map { [$0.id] } ?? []
        var todo = TodoItem(
            id: "todo-\(UUID().uuidString.lowercased())",
            title: trimmedTitle,
            kind: kind,
            status: .open,
            startDate: startDate.map { Calendar.current.startOfDay(for: $0) },
            dueDate: dueDate.map { Calendar.current.startOfDay(for: $0) },
            priority: priority,
            projectIDs: projectIDs ?? currentProjectID.map { [$0] } ?? [],
            tags: resolvedTags,
            relatedPaperIDs: resolvedPaperIDs,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty,
            createdAt: now,
            updatedAt: now
        )

        Task {
            do {
                try await todoRepository.upsert(todo, in: currentWorkspace)
                if addTodosToAppleReminders {
                    todo = try await createAppleReminderIfNeeded(for: todo, in: currentWorkspace)
                }
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func updateTodo(
        _ todo: TodoItem,
        title: String,
        kind: TodoKind? = nil,
        status: TodoStatus,
        startDate: Date? = nil,
        dueDate: Date?,
        priority: Priority,
        notes: String?,
        projectIDs: [ResearchProject.ID]? = nil,
        tags: [String]? = nil,
        relatedPaperIDs: [String]? = nil
    ) {
        guard let currentWorkspace else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        var updatedTodo = todo
        updatedTodo.title = trimmedTitle
        updatedTodo.kind = kind ?? updatedTodo.kind
        updatedTodo.status = status
        updatedTodo.startDate = startDate.map { Calendar.current.startOfDay(for: $0) }
        updatedTodo.dueDate = dueDate.map { Calendar.current.startOfDay(for: $0) }
        updatedTodo.priority = priority
        updatedTodo.projectIDs = projectIDs ?? updatedTodo.projectIDs
        updatedTodo.tags = tags ?? updatedTodo.tags
        updatedTodo.relatedPaperIDs = relatedPaperIDs ?? updatedTodo.relatedPaperIDs
        updatedTodo.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty
        updatedTodo.completedAt = status == .done ? (todo.completedAt ?? Date()) : nil
        updatedTodo.updatedAt = Date()

        Task {
            do {
                try await todoRepository.upsert(updatedTodo, in: currentWorkspace)
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func toggleTodo(_ todo: TodoItem) {
        guard let currentWorkspace else {
            return
        }

        var updatedTodo = todo
        updatedTodo.status = todo.status == .done ? .open : .done
        updatedTodo.completedAt = updatedTodo.status == .done ? Date() : nil
        updatedTodo.updatedAt = Date()

        Task {
            do {
                try await todoRepository.upsert(updatedTodo, in: currentWorkspace)
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func publishTodoToAppleReminders(_ todo: TodoItem) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                _ = try await createAppleReminderIfNeeded(for: todo, in: currentWorkspace)
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func deleteTodo(_ todo: TodoItem) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await todoRepository.delete(todoID: todo.id, in: currentWorkspace)
                try await loadTodos(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func openOrGenerateSelectedPaperWikiPage() {
        if selectedPaperHasWikiPage {
            openSelectedPaperWikiPage()
        } else {
            generateSelectedPaperWikiPage()
        }
    }

    func selectMarkdownDocument(id: String?) {
        guard id != selectedMarkdownID else {
            return
        }

        if selectedMarkdownHasUnsavedChanges {
            pendingMarkdownSelectionID = id
            isShowingUnsavedMarkdownConfirmation = true
            return
        }

        applyMarkdownSelection(id)
    }

    func confirmDiscardUnsavedMarkdownSelection() {
        let nextSelectionID = pendingMarkdownSelectionID
        pendingMarkdownSelectionID = nil
        isShowingUnsavedMarkdownConfirmation = false
        if let nextSelectionID,
           !markdownDocuments.contains(where: { $0.id == nextSelectionID }) {
            selectedMarkdownID = nil
            selectedMarkdownDraft = nil
            updateSelectedMarkdownSaveState(.clean)
            openMarkdownDocument(relativePath: nextSelectionID)
            return
        }
        applyMarkdownSelection(nextSelectionID)
    }

    func cancelDiscardUnsavedMarkdownSelection() {
        pendingMarkdownSelectionID = nil
        isShowingUnsavedMarkdownConfirmation = false
    }

    func applyMarkdownSelection(_ id: String?) {
        selectedMarkdownID = id
        selectedMarkdownDraft = markdownDocuments.first(where: { $0.id == id })
        updateSelectedMarkdownSaveState(.clean)
    }

    func openMarkdownDocument(relativePath: String) {
        selectedSection = .wiki

        if markdownDocuments.contains(where: { $0.relativePath == relativePath }) {
            selectMarkdownDocument(id: relativePath)
            return
        }

        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                let directDocument = try await markdownRepository.loadDocument(relativePath: relativePath, in: currentWorkspace)
                mergeMarkdownDocument(directDocument)
                selectedMarkdownID = directDocument.id
                selectedMarkdownDraft = directDocument
                updateSelectedMarkdownSaveState(.clean)
                recordAppDebugEvent("paper_markdown.open_direct", payload: .object([
                    "relative_path": .string(directDocument.relativePath),
                    "is_paper_markdown": .bool(directDocument.relativePath.hasSuffix("/paper.md"))
                ]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: directDocument.id)
            } catch {
                present(error)
            }
        }
    }

    func openWorkspaceRelativePath(_ relativePath: String) {
        let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty,
              !normalizedPath.hasPrefix("/"),
              !normalizedPath.contains(".."),
              let currentWorkspace else {
            return
        }

        if normalizedPath.hasSuffix(".md") {
            openMarkdownDocument(relativePath: normalizedPath)
            return
        }

        let fileURL = currentWorkspace.fileURL(for: normalizedPath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.open(fileURL)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL.deletingLastPathComponent()])
        }
    }

    func openPaperMarkdown(_ paper: Paper) {
        openMarkdownDocument(relativePath: paperMarkdownPath(for: paper))
    }

    func openCurrentProjectOverviewPage() {
        guard let project = currentResearchProject else {
            selectedSection = .wiki
            return
        }

        openMarkdownDocument(relativePath: project.relativePath + "/wiki/projects/project_overview.md")
    }

    func updateSelectedMarkdownContents(_ newValue: String) {
        guard var draft = selectedMarkdownDraft else {
            return
        }

        draft.rawContents = expandedMarkdownContentsIfNeeded(newValue)
        selectedMarkdownDraft = draft
        updateSelectedMarkdownSaveState(selectedMarkdownHasUnsavedChanges ? .dirty : .clean)
    }

    func insertMarkdownSnippet(_ snippet: MarkdownSnippet) {
        guard var draft = selectedMarkdownDraft else {
            return
        }

        let snippetBody = preparedSnippetBody(snippet.body)
        let currentContents = draft.rawContents.trimmingCharacters(in: .newlines)
        draft.rawContents = currentContents.isEmpty
            ? snippetBody
            : currentContents + "\n\n" + snippetBody
        selectedMarkdownDraft = draft
        updateSelectedMarkdownSaveState(.dirty)
    }

    func insertMarkdownFormatting(_ action: MarkdownFormattingAction) {
        guard var draft = selectedMarkdownDraft else {
            return
        }

        let insertion = action.insertionText
        let currentContents = draft.rawContents.trimmingCharacters(in: .newlines)
        draft.rawContents = currentContents.isEmpty
            ? insertion
            : currentContents + "\n\n" + insertion
        selectedMarkdownDraft = draft
        updateSelectedMarkdownSaveState(.dirty)
    }

    func addFrontmatterToSelectedMarkdown() {
        guard var draft = selectedMarkdownDraft else {
            return
        }
        guard !draft.rawContents.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("---") else {
            return
        }

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : draft.title
        draft.rawContents = """
        ---
        title: "\(title)"
        tags: []
        ---

        \(draft.rawContents)
        """
        selectedMarkdownDraft = draft
        updateSelectedMarkdownSaveState(.dirty)
    }

    func openMarkdownSnippetsFile() {
        guard let currentWorkspace else {
            return
        }

        NSWorkspace.shared.open(currentWorkspace.markdownSnippetsURL)
    }

    func openWikiFolder() {
        guard let currentWorkspace else {
            return
        }

        if let project = currentResearchProject {
            NSWorkspace.shared.open(currentWorkspace.directoryURL(for: project.relativePath + "/wiki"))
        } else {
            NSWorkspace.shared.open(currentWorkspace.directoryURL(for: "wiki"))
        }
    }

    func createMarkdownPage(named name: String) {
        guard let currentWorkspace else {
            return
        }

        let relativePath = wikiManagedRelativePath(from: name, defaultFileName: "untitled.md")
        let title = markdownTitle(from: name)
        let contents = "# \(title)\n"
        Task {
            do {
                let document = try await markdownRepository.createDocument(relativePath: relativePath, contents: contents, in: currentWorkspace)
                recordAppDebugEvent("wiki.file.create", payload: .object(["relative_path": .string(document.relativePath)]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: document.id)
            } catch {
                present(error)
            }
        }
    }

    func createMarkdownFolder(named name: String) {
        guard let currentWorkspace else {
            return
        }

        let relativePath = wikiManagedFolderPath(from: name, defaultFolderName: "notes")
        Task {
            do {
                let createdPath = try await markdownRepository.createFolder(relativePath: relativePath, in: currentWorkspace)
                recordAppDebugEvent("wiki.file.create", payload: .object([
                    "relative_path": .string(createdPath),
                    "kind": .string("folder")
                ]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: selectedMarkdownID)
            } catch {
                present(error)
            }
        }
    }

    func renameSelectedMarkdownDocument(to newFileName: String) {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            return
        }

        let oldPath = selectedMarkdownDraft.relativePath
        Task {
            do {
                let document = try await markdownRepository.renameDocument(relativePath: oldPath, toFileName: newFileName, in: currentWorkspace)
                recordAppDebugEvent("wiki.file.rename", payload: .object([
                    "from": .string(oldPath),
                    "to": .string(document.relativePath)
                ]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: document.id)
            } catch {
                present(error)
            }
        }
    }

    func moveSelectedMarkdownDocument(toFolder folderPath: String) {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            return
        }

        let oldPath = selectedMarkdownDraft.relativePath
        let fileName = (oldPath as NSString).lastPathComponent
        let destinationFolder = wikiManagedFolderPath(from: folderPath, defaultFolderName: "notes")
        let destinationPath = (destinationFolder as NSString).appendingPathComponent(fileName)
            .replacingOccurrences(of: "\\", with: "/")
        Task {
            do {
                let document = try await markdownRepository.moveDocument(from: oldPath, to: destinationPath, in: currentWorkspace)
                recordAppDebugEvent("wiki.file.rename", payload: .object([
                    "from": .string(oldPath),
                    "to": .string(document.relativePath),
                    "operation": .string("move")
                ]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: document.id)
            } catch {
                present(error)
            }
        }
    }

    func archiveSelectedMarkdownDocument() {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            return
        }

        let archivedPath = selectedMarkdownDraft.relativePath
        let remainingIDs = markdownDocuments.map(\.id).filter { $0 != selectedMarkdownDraft.id }
        Task {
            do {
                let trashPath = try await markdownRepository.archiveDocument(relativePath: archivedPath, in: currentWorkspace)
                recordAppDebugEvent("wiki.file.archive", payload: .object([
                    "relative_path": .string(archivedPath),
                    "trash_path": .string(trashPath)
                ]))
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: remainingIDs.first)
            } catch {
                present(error)
            }
        }
    }

    func saveSelectedMarkdownChanges() {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            return
        }

        isSavingSelectedMarkdown = true
        updateSelectedMarkdownSaveState(.saving)
        Task {
            defer {
                isSavingSelectedMarkdown = false
            }

            do {
                _ = try await markdownRepository.saveContents(
                    selectedMarkdownDraft.rawContents,
                    relativePath: selectedMarkdownDraft.relativePath,
                    in: currentWorkspace
                )
                try await loadMarkdownDocuments(in: currentWorkspace, selecting: selectedMarkdownDraft.relativePath)
                updateSelectedMarkdownSaveState(.clean)
            } catch {
                updateSelectedMarkdownSaveState(.failed, errorMessage: error.localizedDescription)
                present(error)
            }
        }
    }

    func runWorkspaceTask(
        compatibilityHint: ResearchRootCompatibility? = nil,
        operation: @escaping @Sendable () async throws -> ResearchWorkspace
    ) {
        isWorking = true

        workspaceSessionCoordinator.start { [weak self] generation in
            guard let self else { return }
            defer {
                if self.workspaceSessionCoordinator.isCurrent(generation) {
                    self.isWorking = false
                    self.workspaceSessionCoordinator.finish(generation)
                }
            }

            do {
                let workspace = try await operation()
                try Task.checkCancellation()
                guard self.workspaceSessionCoordinator.isCurrent(generation) else { return }

                try await self.loadWorkspaceData(
                    in: workspace,
                    selectingPaper: nil,
                    selectingMarkdown: nil,
                    rootCompatibility: compatibilityHint
                )
                try Task.checkCancellation()
                guard self.workspaceSessionCoordinator.isCurrent(generation) else { return }

                if self.selectedSection == nil {
                    self.selectedSection = .projects
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.workspaceSessionCoordinator.isCurrent(generation) else { return }
                self.present(error)
            }
        }
    }

    func present(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    func importPDF(from pdfURL: URL, into workspace: ResearchWorkspace) {
        isImportingPDF = true
        let existingPapers = papers

        Task {
            defer {
                isImportingPDF = false
            }

            do {
                let importedPaper = try await pdfImportService.importPDF(
                    from: pdfURL,
                    into: workspace,
                    existingPapers: existingPapers,
                    collectionPath: selectedCollectionPath ?? workspacePreferences.defaultCollectionPath ?? "Uncategorized",
                    projectIDs: selectedLibraryProjectID.map { [$0] } ?? []
                )
                try await loadWorkspaceData(
                    in: workspace,
                    selectingPaper: importedPaper.id,
                    selectingMarkdown: selectedMarkdownID
                )
                selectedSection = .library
                selectedProjectSpaceProjectID = nil
                persistWorkspaceRoute(WorkspaceRoute(top: .library))
                startMarkdownConversion(for: [importedPaper], in: workspace, statusSurface: .workspace)
            } catch {
                present(error)
            }
        }
    }

    func commaSeparatedValues(from value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func uniqueOrdered(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty, !seen.contains(trimmedValue) else {
                continue
            }
            seen.insert(trimmedValue)
            result.append(trimmedValue)
        }
        return result
    }

    func generateSelectedPaperWikiPage() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        isGeneratingWikiPage = true
        Task {
            defer {
                isGeneratingWikiPage = false
            }

            do {
                let result = try await wikiPageGenerator.generatePaperWikiPage(
                    for: selectedPaperDraft,
                    in: currentWorkspace
                )
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: result.paper.id,
                    selectingMarkdown: currentWorkspace.relativePath(to: result.fileURL)
                )
                selectedSection = .wiki
            } catch {
                present(error)
            }
        }
    }

    func openSelectedPaperWikiPage() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        openMarkdownDocument(relativePath: currentWorkspace.relativePath(to: wikiPageURL(for: selectedPaperDraft, in: currentWorkspace)))
    }

    func loadWorkspaceData(
        in workspace: ResearchWorkspace,
        selectingPaper paperID: Paper.ID?,
        selectingMarkdown markdownID: String?,
        rootCompatibility: ResearchRootCompatibility? = nil
    ) async throws {
        let previousSnapshot = captureWorkspaceSessionSnapshot()
        let loadedState = try await stageWorkspaceLoad(
            in: workspace,
            selectingPaper: paperID,
            selectingMarkdown: markdownID,
            rootCompatibility: rootCompatibility
        )
        await restoreWorkspaceSessionSnapshot(
            loadedState.state,
            closeReplacedGraph: false
        )
        await finalizeCommittedWorkspaceLoad(loadedState.workspace, replacing: previousSnapshot)
    }

    func loadWorkspaceDataUncommitted(
        in workspace: ResearchWorkspace,
        selectingPaper paperID: Paper.ID?,
        selectingMarkdown markdownID: String?,
        rootCompatibility: ResearchRootCompatibility?
    ) async throws {
        try Task.checkCancellation()
        try await loadResearchRoot(in: workspace, compatibility: rootCompatibility)
        try Task.checkCancellation()
        try await loadWorkspacePreferences(in: workspace)
        try Task.checkCancellation()
        try await loadLibrary(in: workspace, selecting: paperID)
        try Task.checkCancellation()
        try await loadLegacyPaperMigrationPlan(in: workspace)
        try Task.checkCancellation()
        try await loadCollections(in: workspace)
        try Task.checkCancellation()
        try await loadTags(in: workspace)
        try Task.checkCancellation()
        try await loadTodos(in: workspace)
        try Task.checkCancellation()
        try await loadCalendarEvents(in: workspace)
        try Task.checkCancellation()
        systemCalendarAccessState = systemCalendarService.accessState
        if systemCalendarAccessState.canReadSchedule {
            try await loadSystemSchedule(
                around: selectedDashboardDate,
                workspace: workspace,
                synchronizeMappedTodos: false
            )
        }
        try Task.checkCancellation()
        try await loadLLMSettings(in: workspace)
        try Task.checkCancellation()
        try await loadMarkdownSnippets(in: workspace)
        try Task.checkCancellation()
        try await loadMarkdownDocuments(in: workspace, selecting: markdownID)
        try Task.checkCancellation()
        await refreshAgentState(in: workspace, restoreDraft: false)
        try Task.checkCancellation()
        await initializeGraphRepository(in: workspace)
    }

    func loadResearchRoot(in workspace: ResearchWorkspace, compatibility: ResearchRootCompatibility?) async throws {
        let root = ResearchRoot(rootURL: workspace.rootURL)
        currentResearchRoot = root

        let moduleConfiguration = try await workspaceModuleConfigurationStore.load(in: root)
        applyWorkspaceModuleConfiguration(moduleConfiguration, in: root)
        normalizeSelectedSectionForModuleAvailability()

        let registry = try await projectRegistryRepository.load(in: root)
        researchProjects = registry.projects
        currentProjectID = registry.lastOpenedProjectID ?? registry.projects.first?.id
        workspaceModuleOverrides = await loadProjectModuleOverrides(for: registry.projects, in: root)
        normalizeSelectedSectionForModuleAvailability()

        if compatibility == .legacyWorkspace || registry.projects.contains(where: { $0.defaultTags.contains("legacy-workspace") }) {
            rootCompatibilityMessage = "Opened an existing single-workspace library as a research root. Sci-Station created a default project shell without moving your files."
        } else {
            rootCompatibilityMessage = nil
        }
        agentRetrievalIndexStatus = await agentEmbeddingIndexController.status(in: root)
    }

}
