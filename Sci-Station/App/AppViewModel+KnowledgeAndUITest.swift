import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppViewModel {
    func loadMarkdownSnippets(in workspace: ResearchWorkspace) async throws {
        markdownSnippets = try await markdownSnippetRepository.load(in: workspace)
            .sorted { lhs, rhs in
                lhs.trigger.localizedStandardCompare(rhs.trigger) == .orderedAscending
            }
    }

    func expandedMarkdownContentsIfNeeded(_ contents: String) -> String {
        for snippet in markdownSnippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            guard contents.hasSuffix(snippet.trigger) else {
                continue
            }

            let prefix = contents.dropLast(snippet.trigger.count)
            return String(prefix) + preparedSnippetBody(snippet.body)
        }

        return contents
    }

    func preparedSnippetBody(_ body: String) -> String {
        body.replacingOccurrences(of: "${cursor}", with: "")
    }

    func loadMarkdownDocuments(in workspace: ResearchWorkspace, selecting markdownID: String?) async throws {
        var loadedDocuments = try await markdownRepository.loadDocuments(in: workspace, project: currentResearchProject)
        if let markdownID,
           !loadedDocuments.contains(where: { $0.id == markdownID }),
           let externalDocument = try? await markdownRepository.loadDocument(relativePath: markdownID, in: workspace) {
            loadedDocuments.append(externalDocument)
        }
        markdownDocuments = loadedDocuments
        backlinkIndex = BacklinkIndex(documents: loadedDocuments)

        let nextSelectionID = markdownID ?? selectedMarkdownID ?? loadedDocuments.first?.id
        selectedMarkdownID = nextSelectionID
        selectedMarkdownDraft = loadedDocuments.first(where: { $0.id == nextSelectionID })
        updateSelectedMarkdownSaveState(.clean)
    }

    func mergeMarkdownDocument(_ document: MarkdownDocument) {
        if let index = markdownDocuments.firstIndex(where: { $0.id == document.id }) {
            markdownDocuments[index] = document
        } else {
            markdownDocuments.append(document)
        }
        backlinkIndex = BacklinkIndex(documents: markdownDocuments)
    }

    func updateSelectedMarkdownSaveState(_ state: MarkdownSaveState, errorMessage: String? = nil) {
        guard selectedMarkdownSaveState != state || selectedMarkdownSaveErrorMessage != errorMessage else {
            return
        }

        selectedMarkdownSaveState = state
        selectedMarkdownSaveErrorMessage = errorMessage
        recordAppDebugEvent("markdown.editor.save_state", payload: .object([
            "state": .string(state.rawValue),
            "relative_path": .string(selectedMarkdownDraft?.relativePath ?? ""),
            "error_present": .bool(errorMessage != nil)
        ]))
    }

    func paperMarkdownPath(for paper: Paper) -> String {
        paper.paperDirectoryRelativePath + "/paper.md"
    }

    func currentWikiRootRelativePath() -> String {
        if let project = currentResearchProject {
            return project.relativePath + "/wiki"
        }
        return "wiki"
    }

    func wikiManagedRelativePath(from input: String, defaultFileName: String) -> String {
        var normalized = input
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.isEmpty {
            normalized = defaultFileName
        }
        if !normalized.contains("/") && (normalized as NSString).pathExtension.isEmpty {
            normalized = wikiPathSlug(from: normalized) + ".md"
        } else if (normalized as NSString).pathExtension.isEmpty {
            normalized += ".md"
        }
        if normalized.hasPrefix("wiki/") || normalized.hasPrefix("projects/") {
            return normalized
        }
        return currentWikiRootRelativePath() + "/" + normalized
    }

    func wikiManagedFolderPath(from input: String, defaultFolderName: String) -> String {
        var normalized = input
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.isEmpty {
            normalized = defaultFolderName
        }
        if !normalized.contains("/") {
            normalized = wikiPathSlug(from: normalized)
        }
        if normalized.hasPrefix("wiki/") || normalized.hasPrefix("projects/") {
            return normalized
        }
        return currentWikiRootRelativePath() + "/" + normalized
    }

    func markdownTitle(from input: String) -> String {
        let lastComponent = input
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init) ?? "Untitled"
        let title = (lastComponent as NSString).deletingPathExtension
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Untitled" : title.capitalized
    }

    func wikiPathSlug(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let filtered = String(value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : " "
        })
        let slug = filtered
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "_" })
            .joined(separator: "-")
        return slug.isEmpty ? "untitled" : slug
    }

    func pdfAnnotationDebugPayload(_ annotation: PDFAnnotationRecord) -> JSONValue {
        .object([
            "annotation_id": .string(annotation.id),
            "paper_id": .string(annotation.paperID),
            "kind": .string(annotation.kind.rawValue),
            "page_index": .string(String(annotation.pageIndex)),
            "bounds_count": .string(String(annotation.bounds.count)),
            "fingerprint": .string(annotation.duplicateFingerprint),
            "selected_text_preview_present": .bool(!annotation.selectedTextPreview.isEmpty),
            "note_present": .bool(annotation.noteText?.isEmpty == false)
        ])
    }

    func selectedAgentRetrievalSourceFileStatus() -> AgentRetrievalSelectedSourceFileStatus? {
        guard let currentResearchRoot, let relativePath = selectedAgentRetrievalSourcePath() else {
            return nil
        }
        let fileURL = currentResearchRoot.fileURL(for: relativePath)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
        guard exists else {
            return AgentRetrievalSelectedSourceFileStatus(relativePath: relativePath, exists: false, isDirectory: false, byteCount: 0, lineCount: nil)
        }
        let attributes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let lineCount: Int?
        if !isDirectory.boolValue, let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
            lineCount = contents.components(separatedBy: .newlines).count
        } else {
            lineCount = nil
        }
        return AgentRetrievalSelectedSourceFileStatus(
            relativePath: relativePath,
            exists: true,
            isDirectory: isDirectory.boolValue,
            byteCount: byteCount,
            lineCount: lineCount
        )
    }

    func paperHasWikiPage(_ paper: Paper, in workspace: ResearchWorkspace) -> Bool {
        FileManager.default.fileExists(atPath: wikiPageURL(for: paper, in: workspace).path)
    }

    func paperWikiStatusText(for paper: Paper, in workspace: ResearchWorkspace) -> String {
        paperHasWikiPage(paper, in: workspace) ? "Ready" : "Missing"
    }

    func wikiPageURL(for paper: Paper, in workspace: ResearchWorkspace) -> URL {
        if let summaryURL = paper.summaryURL(in: workspace) {
            return summaryURL
        }

        return workspace.fileURL(for: "wiki/papers/\(paper.citekey).md")
    }

    nonisolated static func joinedBibTeX(for papers: [Paper]) -> String {
        papers
            .map(BibTeXFormatter.bibTeX(for:))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n") + "\n"
    }

    nonisolated static func citationText(for paper: Paper) -> String {
        let authors = paper.authorsDisplay
        let year = paper.year.map { "(\($0))" } ?? "(n.d.)"
        let venue = (paper.publicationTitle ?? paper.venue)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = venue.map { " \($0)." } ?? ""
        return "\(authors) \(year). \(paper.displayTitle).\(suffix)"
    }

    static func selectCreateWorkspaceURL(suggestedName: String = "ResearchWorkspace") -> URL? {
        let panel = NSSavePanel()
        panel.title = "Create Research Workspace"
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty ?? "ResearchWorkspace"
        panel.directoryURL = defaultPanelDirectoryURL()

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    static func selectOpenWorkspaceURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open Research Workspace"
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = defaultPanelDirectoryURL()

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

    static func selectPDFURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import PDF"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = defaultPanelDirectoryURL()

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url
    }

#if DEBUG
    func installUITestBridgeIfRequested() {
        guard let configuration = UITestBridgeConfiguration.fromProcessInfo() else {
            return
        }
        let server = UITestBridgeServer(socketURL: configuration.socketURL) { [weak self] command in
            guard let self else {
                throw UITestBridgeCommandError.unavailable
            }
            return try await self.handleUITestBridgeCommand(command)
        }
        do {
            try server.start()
            uiTestBridgeServer = server
            uiTestBridgeForceDebugLogging = true
            if let currentWorkspace {
                _ = SwiftUIRuntimeWarningCapture.shared.install(rootURL: currentWorkspace.rootURL)
            }
        } catch {
            NSLog("Sci-Station UI test bridge failed to start: %@", String(describing: error))
        }
    }

    func handleUITestBridgeCommand(_ command: UITestBridgeCommand) async throws -> UITestBridgeCommandResult {
        recordUITestBridgeEvent(.uitestBridgeCommandReceived, command: command.name)
        do {
            let result: UITestBridgeCommandResult
            switch command.name {
            case "ping":
                result = UITestBridgeCommandResult(fields: [
                    "socket_path": .string(uiTestBridgeServer?.socketURL.path ?? ""),
                    "workspace_open": .bool(currentWorkspace != nil),
                    "selected_section": .string(selectedSection?.rawValue ?? "")
                ])
            case "workspace.open":
                let path = try bridgeString(command.args, keys: ["path", "root", "root_path"])
                let workspace = try await openWorkspaceForUITestBridge(rootURL: URL(fileURLWithPath: NSString(string: path).expandingTildeInPath))
                result = UITestBridgeCommandResult(fields: [
                    "workspace_id": .string(workspace.id.path),
                    "root_path": .string(workspace.rootURL.path)
                ])
            case "route.select":
                let sectionRaw = try bridgeString(command.args, keys: ["section", "route"])
                guard let section = WorkspaceSection(rawValue: sectionRaw) else {
                    throw UITestBridgeCommandError.invalidArgument("section", sectionRaw)
                }
                selectSection(section)
                result = UITestBridgeCommandResult(fields: [
                    "selected_section": .string(selectedSection?.rawValue ?? section.rawValue)
                ])
            case "project.select_first":
                result = try selectFirstProjectForUITestBridge()
            case "project.tab.select":
                result = try selectProjectTabForUITestBridge(args: command.args)
            case "home.layout.enter_edit":
                selectSection(.dashboard)
                enterHomeLayoutEdit()
                result = UITestBridgeCommandResult(fields: [
                    "selected_section": .string(selectedSection?.rawValue ?? ""),
                    "is_editing": .bool(isEditingHomeLayout)
                ])
            case "home.layout.exit_edit":
                exitHomeLayoutEdit()
                result = UITestBridgeCommandResult(fields: [
                    "is_editing": .bool(isEditingHomeLayout)
                ])
            case "library.import.attachFixturePDF":
                result = try await importFixturePDFForUITestBridge(args: command.args)
            case "wiki.page.create":
                result = try await createWikiPageForUITestBridge(args: command.args)
            case "wiki.page.rename_selected":
                result = try await renameSelectedWikiPageForUITestBridge(args: command.args)
            case "agent.prompt.set":
                result = try await setAgentPromptForUITestBridge(args: command.args)
            default:
                throw UITestBridgeCommandError.unknownCommand(command.name)
            }
            recordUITestBridgeEvent(.uitestBridgeCommandCompleted, command: command.name)
            return result
        } catch {
            recordUITestBridgeEvent(.uitestBridgeCommandFailed, command: command.name, error: error.localizedDescription)
            throw error
        }
    }

    func openWorkspaceForUITestBridge(rootURL: URL) async throws -> ResearchWorkspace {
        isWorking = true
        defer { isWorking = false }
        let compatibility = ResearchRoot.compatibility(at: rootURL)
        let workspace = try await workspaceService.openWorkspace(at: rootURL)
        try await loadWorkspaceData(
            in: workspace,
            selectingPaper: nil,
            selectingMarkdown: nil,
            rootCompatibility: compatibility
        )
        if selectedSection == nil {
            selectedSection = .projects
        }
        return workspace
    }

    func selectFirstProjectForUITestBridge() throws -> UITestBridgeCommandResult {
        guard let project = activeResearchProjects.first ?? researchProjects.first else {
            throw UITestBridgeCommandError.missingArgument("project")
        }
        selectResearchProject(project.id, section: .projects)
        return UITestBridgeCommandResult(fields: [
            "project_id": .string(project.id),
            "selected_section": .string(selectedSection?.rawValue ?? ""),
            "project_tab_id": .string(selectedProjectSpaceTabID)
        ])
    }

    func selectProjectTabForUITestBridge(args: [String: JSONValue]) throws -> UITestBridgeCommandResult {
        if selectedProjectSpaceProjectID == nil {
            _ = try selectFirstProjectForUITestBridge()
        }
        let tabID = try bridgeString(args, keys: ["tab_id", "tab", "id"])
        selectProjectSpaceTab(tabID)
        return UITestBridgeCommandResult(fields: [
            "project_id": .string(selectedProjectSpaceProjectID ?? ""),
            "project_tab_id": .string(selectedProjectSpaceTabID)
        ])
    }

    func importFixturePDFForUITestBridge(args: [String: JSONValue]) async throws -> UITestBridgeCommandResult {
        let sourceURL = try fixturePDFURLForUITestBridge(args: args)
        let collectionPath = bridgeOptionalString(args, keys: ["collection_path", "collection"]) ?? selectedCollectionPath ?? workspacePreferences.defaultCollectionPath ?? "Uncategorized"
        let importedPaper = try await importPDFForUITestBridge(from: sourceURL, collectionPath: collectionPath)
        let fields: [String: JSONValue] = [
            "paper_id": .string(importedPaper.id),
            "title": .string(importedPaper.displayTitle),
            "pdf_path": .string(sourceURL.path)
        ]
        return UITestBridgeCommandResult(fields: fields)
    }

    func importPDFForUITestBridge(from pdfURL: URL, collectionPath: String) async throws -> Paper {
        guard let currentWorkspace else {
            throw UITestBridgeCommandError.missingWorkspace
        }
        isImportingPDF = true
        defer { isImportingPDF = false }
        let importedPaper = try await pdfImportService.importPDF(
            from: pdfURL,
            into: currentWorkspace,
            existingPapers: papers,
            collectionPath: collectionPath,
            projectIDs: selectedLibraryProjectID.map { [$0] } ?? []
        )
        try await loadWorkspaceData(
            in: currentWorkspace,
            selectingPaper: importedPaper.id,
            selectingMarkdown: selectedMarkdownID
        )
        selectedSection = .library
        selectedProjectSpaceProjectID = nil
        persistWorkspaceRoute(WorkspaceRoute(top: .library))
        startMarkdownConversion(for: [importedPaper], in: currentWorkspace, statusSurface: .workspace)
        return importedPaper
    }

    func createWikiPageForUITestBridge(args: [String: JSONValue]) async throws -> UITestBridgeCommandResult {
        guard let currentWorkspace else {
            throw UITestBridgeCommandError.missingWorkspace
        }
        let name = bridgeOptionalString(args, keys: ["name", "title"]) ?? "UITest Smoke Page"
        let relativePath = bridgeOptionalString(args, keys: ["relative_path", "path"])
            ?? wikiManagedRelativePath(from: name, defaultFileName: "uitest_smoke_page.md")
        let contents = bridgeOptionalString(args, keys: ["contents", "body"])
            ?? "# \(markdownTitle(from: name))\n"
        let document: MarkdownDocument
        do {
            document = try await markdownRepository.createDocument(relativePath: relativePath, contents: contents, in: currentWorkspace)
        } catch MarkdownRepositoryError.destinationAlreadyExists(_) {
            document = try await markdownRepository.loadDocument(relativePath: relativePath, in: currentWorkspace)
        }
        recordAppDebugEvent("wiki.file.create", payload: .object(["relative_path": .string(document.relativePath)]))
        try await loadMarkdownDocuments(in: currentWorkspace, selecting: document.id)
        selectedSection = .wiki
        return UITestBridgeCommandResult(fields: [
            "relative_path": .string(document.relativePath),
            "selected_markdown_id": .string(selectedMarkdownID ?? "")
        ])
    }

    func renameSelectedWikiPageForUITestBridge(args: [String: JSONValue]) async throws -> UITestBridgeCommandResult {
        guard let currentWorkspace, let selectedMarkdownDraft else {
            throw UITestBridgeCommandError.missingArgument("selected markdown")
        }
        let newFileName = try bridgeString(args, keys: ["new_file_name", "file_name", "name"])
        let oldPath = selectedMarkdownDraft.relativePath
        let document = try await markdownRepository.renameDocument(relativePath: oldPath, toFileName: newFileName, in: currentWorkspace)
        recordAppDebugEvent("wiki.file.rename", payload: .object([
            "from": .string(oldPath),
            "to": .string(document.relativePath)
        ]))
        try await loadMarkdownDocuments(in: currentWorkspace, selecting: document.id)
        selectedSection = .wiki
        return UITestBridgeCommandResult(fields: [
            "from": .string(oldPath),
            "to": .string(document.relativePath)
        ])
    }

    func setAgentPromptForUITestBridge(args: [String: JSONValue]) async throws -> UITestBridgeCommandResult {
        guard let currentWorkspace else {
            throw UITestBridgeCommandError.missingWorkspace
        }
        let text = try bridgeString(args, keys: ["text", "prompt", "goal"])
        selectSection(.llmLab)
        if bridgeBool(args, key: "new_thread", defaultValue: true) {
            startNewAgentConversation()
        }
        agentGoal = text
        let projectID = agentDraftProjectIDForCurrentConversation
        let threadID = activeAgentThreadID
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        try await agentService.saveDraft(text, projectID: projectID, threadID: threadID, in: root)
        agentGoalDrafts[agentDraftKey(projectID: projectID, threadID: threadID)] = text
        return UITestBridgeCommandResult(fields: [
            "project_id": .string(projectID ?? ""),
            "thread_id": .string(threadID ?? ""),
            "text_length": .number(String(text.count))
        ])
    }

    func fixturePDFURLForUITestBridge(args: [String: JSONValue]) throws -> URL {
        if let path = bridgeOptionalString(args, keys: ["fixture_path", "path", "pdf_path"]) {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw UITestBridgeCommandError.invalidArgument("fixture_path", path)
            }
            return url
        }
        let fixtureID = bridgeOptionalString(args, keys: ["fixture_id", "id"]) ?? "fixture"
        let sanitized = fixtureID
            .map { character -> Character in
                character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "-"
            }
        let fileName = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "-_")).nilIfAppBlank ?? "fixture"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sci-station-uitest-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName, isDirectory: false).appendingPathExtension("pdf")
        if !FileManager.default.fileExists(atPath: url.path) {
            try minimalFixturePDF(named: fileName).write(to: url, options: .atomic)
        }
        return url
    }

    func minimalFixturePDF(named title: String) -> Data {
        let escapedTitle = title.replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        let text = """
        %PDF-1.1
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >> endobj
        4 0 obj << /Length 64 >> stream
        BT /F1 12 Tf 72 720 Td (Sci-Station UI test fixture: \(escapedTitle)) Tj ET
        endstream endobj
        trailer << /Root 1 0 R >>
        %%EOF
        """
        return Data(text.utf8)
    }

    func recordUITestBridgeEvent(_ event: AppDebugEventName, command: String, error: String? = nil) {
        var payload: [String: JSONValue] = ["command": .string(command)]
        if let error {
            payload["error"] = .string(error)
        }
        recordAppDebugEvent(event.rawValue, payload: .object(payload), force: true)
    }

    func bridgeString(_ args: [String: JSONValue], keys: [String]) throws -> String {
        guard let value = bridgeOptionalString(args, keys: keys) else {
            throw UITestBridgeCommandError.missingArgument(keys.joined(separator: " / "))
        }
        return value
    }

    func bridgeOptionalString(_ args: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = args[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
            if case let .number(value)? = args[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func bridgeStringArray(_ args: [String: JSONValue], key: String) -> [String] {
        guard let values = args[key]?.arrayValue else {
            return []
        }
        return values.compactMap { value in
            value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppBlank
        }
    }

    func bridgeBool(_ args: [String: JSONValue], key: String, defaultValue: Bool) -> Bool {
        switch args[key] {
        case .bool(let value):
            return value
        case .string(let value):
            return ["1", "true", "yes"].contains(value.lowercased())
        default:
            return defaultValue
        }
    }

    enum UITestBridgeCommandError: LocalizedError {
        case unavailable
        case missingWorkspace
        case missingArgument(String)
        case invalidArgument(String, String)
        case unknownCommand(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "UI test bridge is unavailable."
            case .missingWorkspace:
                return "Open a workspace before using this UI test bridge command."
            case .missingArgument(let name):
                return "Missing UI test bridge argument: \(name)."
            case .invalidArgument(let name, let value):
                return "Invalid UI test bridge argument \(name): \(value)."
            case .unknownCommand(let command):
                return "Unknown UI test bridge command: \(command)."
            }
        }
    }
#endif

    static func defaultPanelDirectoryURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

}

extension String {
    var nilIfAppEmpty: String? {
        isEmpty ? nil : self
    }

    var nilIfAppBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
