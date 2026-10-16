import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppViewModel {
    func selectSection(_ section: WorkspaceSection) {
        if section.inProjectSpaceOnly, let projectID = currentProjectID {
            selectResearchProject(projectID, section: section)
            return
        }

        let targetSection = isWorkspaceSectionAvailable(section) ? section : fallbackWorkspaceSection()
        selectedSection = targetSection
        selectedProjectSpaceProjectID = nil
        isViewingGlobalTodos = false
        persistWorkspaceRoute(WorkspaceRoute(top: WorkspaceNavigationPolicy.topRoute(for: targetSection)))
        if targetSection == .library {
            selectedLibraryProjectID = nil
            selectedCollectionPath = nil
            selectedTagName = nil
        }
    }

    func selectTopLevelRoute(_ top: WorkspaceRoute.Top) {
        selectSection(WorkspaceNavigationPolicy.section(for: top))
    }

    func openSettings(category: SettingsCategory) {
        selectedSettingsCategory = category
        if category == .aiLab {
            openAIManagementPanel()
        } else {
            selectSection(.settings)
        }
    }

    func openAIManagementPanel() {
        selectedSettingsCategory = .aiLab
        isShowingAIManagementPanel = true
    }

    func consumeAIManagementPanelRequest() {
        isShowingAIManagementPanel = false
    }

    func selectLibraryScope() {
        guard isWorkspaceSectionAvailable(.library) else {
            selectSection(fallbackWorkspaceSection())
            return
        }
        selectedSection = .library
        selectedProjectSpaceProjectID = nil
        isViewingGlobalTodos = false
        selectedLibraryProjectID = nil
        selectedCollectionPath = nil
        selectedTagName = nil
        persistWorkspaceRoute(WorkspaceRoute(top: .library))
    }

    func selectCollection(_ relativePath: String) {
        guard isWorkspaceSectionAvailable(.library) else {
            selectSection(fallbackWorkspaceSection())
            return
        }
        selectedSection = .library
        selectedProjectSpaceProjectID = nil
        isViewingGlobalTodos = false
        selectedLibraryProjectID = nil
        selectedCollectionPath = relativePath
        selectedTagName = nil
        persistWorkspaceRoute(WorkspaceRoute(top: .library, secondarySelection: relativePath))
    }

    func selectTag(_ name: String) {
        guard isWorkspaceSectionAvailable(.library) else {
            selectSection(fallbackWorkspaceSection())
            return
        }
        selectedSection = .library
        selectedProjectSpaceProjectID = nil
        isViewingGlobalTodos = false
        selectedLibraryProjectID = nil
        selectedTagName = name
        selectedCollectionPath = nil
        persistWorkspaceRoute(WorkspaceRoute(top: .library, secondarySelection: name))
    }

    func clearLibraryFilters() {
        selectedCollectionPath = nil
        selectedTagName = nil
        selectedLibraryProjectID = nil
        librarySearchText = ""
    }

    func focusSearchForCurrentSection() {
        if selectedSection == .pdfReader {
            pdfReaderSearchFocusRequest += 1
            return
        }

        guard isWorkspaceSectionAvailable(.library) else {
            return
        }
        selectedSection = .library
        librarySearchFocusRequest += 1
    }

    func requestPDFReaderFindNext() {
        pdfReaderFindNextRequest += 1
    }

    func requestPDFReaderFindPrevious() {
        pdfReaderFindPreviousRequest += 1
    }

    func requestPDFReaderGoToPage(_ pageIndex: Int) {
        pdfReaderRequestedPageIndex = max(0, pageIndex)
        pdfReaderGoToPageRequest += 1
    }

    func focusInspector() {
        inspectorFocusRequest += 1
    }

    func toggleCollectionCollapse(_ relativePath: String) {
        if collapsedCollectionPaths.contains(relativePath) {
            collapsedCollectionPaths.remove(relativePath)
        } else {
            collapsedCollectionPaths.insert(relativePath)
        }
    }

    func restoreLastWorkspaceIfNeeded() async {
        guard currentWorkspace == nil else {
            return
        }

        guard let restoredWorkspace = await workspaceService.restoreLastWorkspace() else {
            return
        }

        do {
            try await loadWorkspaceData(in: restoredWorkspace, selectingPaper: nil, selectingMarkdown: nil)
            try Task.checkCancellation()
        } catch {
            present(error)
        }
    }

    func createWorkspace() {
        beginWorkspaceCreation(template: WorkspaceTemplateRegistry.literatureReview)
    }

    /// One-click sample workspace for first-run onboarding: pick an empty folder,
    /// then create a workspace pre-seeded with example research content.
    func createSampleWorkspace() {
        guard let destinationURL = Self.selectCreateWorkspaceURL(suggestedName: "Sci-Station Sample") else {
            return
        }

        let compatibility = ResearchRoot.compatibility(at: destinationURL)
        runWorkspaceTask(compatibilityHint: compatibility) {
            try await self.workspaceService.createSampleWorkspace(at: destinationURL)
        }
    }

    func createWorkspace(template: WorkspaceTemplate) {
        beginWorkspaceCreation(template: template)
    }

    func beginWorkspaceCreation(template: WorkspaceTemplate = WorkspaceTemplateRegistry.literatureReview) {
        workspaceCreationDraft = WorkspaceCreationWizard.draft(selecting: template)
        isShowingWorkspaceCreationWizard = true
    }

    func updateWorkspaceCreationName(_ name: String) {
        workspaceCreationDraft.workspaceName = name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let targetURL = workspaceCreationDraft.targetURL else {
            return
        }

        workspaceCreationDraft.targetURL = targetURL
            .deletingLastPathComponent()
            .appendingPathComponent(trimmedName, isDirectory: true)
    }

    func updateWorkspaceCreationTemplate(_ templateID: String) {
        let option = WorkspaceCreationWizard.templateOption(id: templateID)
        guard option.isSelectable, let template = option.template else {
            return
        }
        workspaceCreationDraft.templateID = template.id
        workspaceCreationDraft.enabledModuleIDs = Set(template.enabledModuleIDs)
    }

    func setWorkspaceCreationPrivacyAcknowledged(_ value: Bool) {
        workspaceCreationDraft.privacyAcknowledged = value
    }

    func chooseWorkspaceCreationDestination() {
        guard let destinationURL = Self.selectCreateWorkspaceURL(suggestedName: workspaceCreationDraft.workspaceName) else {
            return
        }

        workspaceCreationDraft.targetURL = destinationURL
        workspaceCreationDraft.workspaceName = destinationURL.lastPathComponent
    }

    func completeWorkspaceCreation() {
        let validation = workspaceCreationTargetValidation
        guard validation.canCreate, let destinationURL = workspaceCreationDraft.targetURL else {
            present(WorkspaceError.incompatibleCreationTarget(validation.message))
            return
        }

        guard workspaceCreationDraft.privacyAcknowledged else {
            present(WorkspaceError.incompatibleCreationTarget("Confirm the privacy and AI setup boundary before creating the workspace."))
            return
        }

        let template = WorkspaceCreationWizard.template(for: workspaceCreationDraft)
        let compatibility = validation.compatibility ?? ResearchRoot.compatibility(at: destinationURL)
        isShowingWorkspaceCreationWizard = false
        runWorkspaceTask(compatibilityHint: compatibility) {
            try await self.workspaceService.createWorkspace(at: destinationURL, template: template)
        }
    }

    func workspaceTemplatePreviewSummary(for template: WorkspaceTemplate) -> String {
        WorkspaceTemplateRepository().preview(for: template).joined(separator: ", ")
    }

    func openWorkspace() {
        guard let destinationURL = Self.selectOpenWorkspaceURL() else {
            return
        }

        let compatibility = ResearchRoot.compatibility(at: destinationURL)
        runWorkspaceTask(compatibilityHint: compatibility) {
            try await self.workspaceService.openWorkspace(at: destinationURL)
        }
    }

    func selectResearchProject(_ projectID: ResearchProject.ID, section: WorkspaceSection = .projects) {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        let targetSection = isWorkspaceProjectTabAvailable(section, projectID: projectID) ? section : fallbackProjectSection(for: projectID)
        let targetTabID = WorkspaceNavigationPolicy.projectTabID(for: targetSection)
        currentProjectID = projectID
        selectedProjectSpaceProjectID = projectID
        selectedProjectSpaceTabID = targetTabID
        selectedSection = .projects
        resetAgentDraftIfConversationChanged(to: projectID)
        isViewingGlobalTodos = false
        if targetTabID == "papers" {
            selectedLibraryProjectID = projectID
            selectedCollectionPath = nil
            selectedTagName = nil
        }

        persistLastOpenedProject(projectID)
        persistWorkspaceRoute(WorkspaceRoute(top: .projects, projectID: projectID, projectTabID: targetTabID))
        refreshAgentContext()

        if targetTabID == "wiki", let currentWorkspace {
            Task {
                do {
                    try await loadMarkdownDocuments(in: currentWorkspace, selecting: nil)
                } catch {
                    present(error)
                }
            }
        }
    }

    func focusResearchProject(_ projectID: ResearchProject.ID) {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        currentProjectID = projectID
        resetAgentDraftIfConversationChanged(to: projectID)
        persistLastOpenedProject(projectID)
        refreshAgentContext()
    }

    func selectGlobalTodos() {
        guard isWorkspaceSectionAvailable(.tasks) else {
            selectSection(fallbackWorkspaceSection())
            return
        }
        selectedSection = .tasks
        selectedProjectSpaceProjectID = nil
        isViewingGlobalTodos = true
        selectedLibraryProjectID = nil
        selectedCollectionPath = nil
        selectedTagName = nil
        persistWorkspaceRoute(WorkspaceRoute(top: .calendar, secondarySelection: "global_todos"))
    }

    func selectProjectSpaceTab(_ tabID: String) {
        guard let projectID = selectedProjectSpaceProjectID ?? currentProjectID else {
            selectTopLevelRoute(.projects)
            return
        }

        let requestedTabID = ProjectSpaceTabsBuilder.retiredReadingTabIDs.contains(tabID) ? ProjectSpaceTabsBuilder.mergedReadingTabID : tabID
        let availableTabs = projectSpaceTabs(for: projectID)
        let resolvedTabID: String
        if availableTabs.contains(where: { $0.id == requestedTabID }) {
            resolvedTabID = requestedTabID
        } else {
            resolvedTabID = ProjectSpaceTabsBuilder.overviewTabID
            recordShellDebugEvent("project_space.builder_warn", payload: .object([
                "project_id": .string(projectID),
                "hidden_tabs": jsonStringArray([requestedTabID]),
                "reason": .string("module_disabled")
            ]))
        }

        if selectedSection == .projects,
           selectedProjectSpaceProjectID == projectID,
           selectedProjectSpaceTabID == resolvedTabID {
            return
        }

        let previousFocusedProjectID = currentProjectID
        let previousTabID = selectedProjectSpaceTabID
        currentProjectID = projectID
        selectedProjectSpaceProjectID = projectID
        selectedProjectSpaceTabID = resolvedTabID
        selectedSection = .projects
        isViewingGlobalTodos = false

        if resolvedTabID == "papers" {
            selectedLibraryProjectID = projectID
            selectedCollectionPath = nil
            selectedTagName = nil
        }

        if previousFocusedProjectID != projectID {
            persistLastOpenedProject(projectID)
        }
        persistWorkspaceRoute(WorkspaceRoute(top: .projects, projectID: projectID, projectTabID: resolvedTabID))
        recordShellDebugEvent("project_space.tab_change", payload: .object([
            "project_id": .string(projectID),
            "from_tab": .string(previousTabID),
            "to_tab": .string(resolvedTabID),
            "available_tabs": jsonStringArray(availableTabs.map(\.id))
        ]))

        if resolvedTabID == "wiki", let currentWorkspace {
            Task {
                do {
                    try await loadMarkdownDocuments(in: currentWorkspace, selecting: nil)
                } catch {
                    present(error)
                }
            }
        }
        if previousFocusedProjectID != projectID || resolvedTabID == "ai-drafts" {
            refreshAgentContext()
        }
    }

    func moveTopSidebarItem(_ itemID: String, before targetID: String) {
        guard itemID != targetID, itemID != WorkspaceRoute.Top.settings.rawValue else {
            return
        }
        let movableIDs = TopSidebarBuilder.items(pinnedOrder: workspacePreferences.pinnedTopLevelOrder)
            .filter { !$0.isPinFixed }
            .map(\.id)
        guard movableIDs.contains(itemID) else {
            return
        }

        var nextOrder = movableIDs.filter { $0 != itemID }
        let insertionIndex = nextOrder.firstIndex(of: targetID) ?? nextOrder.count
        nextOrder.insert(itemID, at: insertionIndex)
        updateWorkspacePreferences { preferences in
            preferences.pinnedTopLevelOrder = nextOrder + [WorkspaceRoute.Top.settings.rawValue]
        }
        recordSidebarRender()
    }

    func moveProjectSpaceTab(_ tabID: String, before targetID: String) {
        guard tabID != targetID, let projectID = selectedProjectSpaceProjectID else {
            return
        }
        let tabs = projectSpaceTabs(for: projectID)
        guard tabs.contains(where: { $0.id == tabID && !$0.isPinFixed }) else {
            return
        }
        let movableIDs = tabs.filter { !$0.isPinFixed }.map(\.id)
        var nextOrder = movableIDs.filter { $0 != tabID }
        let insertionIndex = nextOrder.firstIndex(of: targetID) ?? nextOrder.count
        nextOrder.insert(tabID, at: insertionIndex)
        updateWorkspacePreferences { preferences in
            preferences.projectSpacePinnedOrder = nextOrder
        }
    }

    /// Called on route / tab changes. The right rail mode itself is now a
    /// sticky user preference (set via the toolbar Inspector / AI buttons)
    /// and is no longer auto-flipped here. The only remaining job is to keep
    /// the global AI panel's context summary in sync when the rail is in AI
    /// mode — previously the route-driven flip handled that as a side effect.
    func applyRightRailRouteSuggestion() {
        if workspacePreferences.rightRailMode == .ai {
            recordGlobalAIContextUpdate(reason: "route_change")
        }
    }

    func setRightRailMode(_ mode: RightRailMode, source: String = "manual") {
        let previousMode = workspacePreferences.rightRailMode
        updateWorkspacePreferences { preferences in
            preferences.rightRailMode = mode
            preferences.isGlobalAIPanelOpen = mode == .ai
        }
        recordShellDebugEvent("shell.right_rail.change", payload: .object([
            "from": .string(previousMode.rawValue),
            "to": .string(mode.rawValue),
            "source": .string(source),
            "top": .string(currentWorkspaceRoute.top.rawValue),
            "project_id_present": .bool(currentWorkspaceContextSnapshot.projectID != nil),
            "tab_id": .string(currentWorkspaceContextSnapshot.projectTabID ?? "")
        ]))
    }

    func openGlobalAIPanel(source: String = "toolbar") {
        setRightRailMode(.ai, source: source)
        recordShellDebugEvent("shell.ai_panel.open", payload: currentWorkspaceContextDebugPayload(reason: source))
        recordGlobalAIContextUpdate(reason: source)
    }

    func showContextInspector(source: String = "toolbar") {
        setRightRailMode(.inspector, source: source)
    }

    func hideRightRail(source: String = "manual") {
        setRightRailMode(.hidden, source: source)
    }

    /// Toggle a specific right-rail mode. If the rail is already showing the
    /// requested mode, the rail collapses; otherwise it switches to that mode.
    /// This is what the toolbar Inspector / AI buttons drive so that a single
    /// click in either direction reaches the user's intent without having to
    /// hunt for a close button inside the rail itself.
    func toggleRightRailMode(_ mode: RightRailMode, source: String = "toolbar") {
        guard mode != .hidden else {
            hideRightRail(source: source)
            return
        }
        if effectiveRightRailMode == mode {
            hideRightRail(source: "\(source)_toggle_off")
        } else {
            setRightRailMode(mode, source: source)
        }
    }

    func recordGlobalAIContextUpdate(reason: String = "context_update") {
        guard workspacePreferences.rightRailMode == .ai else {
            return
        }
        recordShellDebugEvent("shell.ai_panel.context_update", payload: currentWorkspaceContextDebugPayload(reason: reason))
    }

    func recordToolbarPolicyChange(_ model: ToolbarModel) {
        let actionCount = model.globalActions.count + model.pageActions.count + model.overflowActions.count
        recordShellDebugEvent("toolbar.policy.resolve", payload: .object([
            "top": .string(currentWorkspaceRoute.top.rawValue),
            "tab_id": .string(currentWorkspaceContextSnapshot.projectTabID ?? ""),
            "action_count": .number(String(actionCount)),
            "hidden_action_count": .number("0"),
            "global_actions": jsonStringArray(model.globalActions.map { $0.id.rawValue }),
            "page_actions": jsonStringArray(model.pageActions.map { $0.id.rawValue }),
            "overflow_actions": jsonStringArray(model.overflowActions.map { $0.id.rawValue })
        ]))
    }

    func refreshCurrentWorkspaceView() {
        switch selectedSection {
        case .wiki:
            reloadWiki()
        case .llmLab:
            refreshAgentContext()
        case .calendar, .tasks:
            refreshSystemSchedule(around: selectedDashboardDate)
        case .library:
            reloadLibrary()
        default:
            guard let currentWorkspace else {
                return
            }
            Task {
                do {
                    try await loadWorkspaceData(in: currentWorkspace, selectingPaper: selectedPaperID, selectingMarkdown: selectedMarkdownID)
                } catch {
                    present(error)
                }
            }
        }
    }

    // MARK: - Graph UI

    func initializeGraphRepository(in workspace: ResearchWorkspace) async {
        let root = ResearchRoot(rootURL: workspace.rootURL)
        let debugLogger = appDebugEventLogger
        let registryRepository = projectRegistryRepository

        await graphStore.load {
            let repo = GraphRepository(debug: debugLogger)
            do {
                try await repo.open(in: root)
                let indexer = GraphIndexer(
                    repository: repo,
                    paperRepository: PaperRepository(),
                    projectRegistryRepository: registryRepository,
                    markdownRepository: MarkdownRepository(),
                    todoRepository: TodoRepository(),
                    debug: debugLogger
                )
                try await indexer.run(in: workspace, root: root, force: false)
                return repo
            } catch {
                await repo.close()
                throw error
            }
        }

        if let diagnostic = graphStore.diagnostic {
            recordShellDebugEvent("graph.repository.initialization_failed", payload: .object([
                "error_type": .string(diagnostic.errorType),
                "message": .string(diagnostic.message),
                "failure_reason": .string(diagnostic.failureReason ?? "")
            ]))
        }
    }

    func showGraphActionPlaceholder(reason: String) {
        recordShellDebugEvent("graph.ui.action", payload: .object([
            "action": .string("pending_implementation"),
            "reason": .string(reason)
        ]))
    }

    func handleGraphNodeAction(_ action: NodeAction) {
        switch action {
        case .openPaper(let paperID):
            selectPaper(id: paperID)
        case .openWikiPage(let path):
            openMarkdownDocument(relativePath: path)
        case .addToProject, .markAsCore, .createTodo:
            // Graph write actions are not enabled in this build. Log the
            // intent so the UI can stay responsive without mutating data.
            recordShellDebugEvent("graph.ui.action", payload: .object([
                "action": .string("write_action_pending"),
                "node_action": .string(String(describing: action))
            ]))
        case .generateReadingOrder(let centerPaperID):
            startGraphInsightAgentRun(
                actionName: "generate_reading_order",
                preferredToolName: GraphAgentTools.generateReadingPath,
                prompt: "Use the graph_insight workflow. Call \(GraphAgentTools.generateReadingPath) for center_paper_id \(centerPaperID), then explain the recommended reading order with graph evidence."
            )
        case .explainConnection(let fromID, let toID):
            startGraphInsightAgentRun(
                actionName: "explain_connection",
                preferredToolName: GraphAgentTools.findBridgePapers,
                prompt: "Use the graph_insight workflow. Call \(GraphAgentTools.findBridgePapers) with from_paper_id \(fromID) and to_paper_id \(toID), then explain the connection with graph evidence."
            )
        case .findBridgePapers(let fromID, let toID):
            startGraphInsightAgentRun(
                actionName: "find_bridge_papers",
                preferredToolName: GraphAgentTools.findBridgePapers,
                prompt: "Use the graph_insight workflow. Call \(GraphAgentTools.findBridgePapers) with from_paper_id \(fromID) and to_paper_id \(toID), then summarize the bridge papers and evidence."
            )
        }
    }

    func startGraphInsightAgentRun(actionName: String, preferredToolName: String, prompt: String) {
        guard currentWorkspace != nil else {
            agentErrorMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }
        guard enabledAgentWorkflowIDs.contains("graph_insight") else {
            agentErrorMessage = "Citation Graph module is required for graph insights."
            recordAppDebugEvent(AppDebugEventName.agentToolGraphBlockedByModule.rawValue, payload: .object([
                "action": .string(actionName),
                "workflow": .string("graph_insight")
            ]))
            return
        }

        let projectID = currentProjectID
        setAgentVisibleMode(.agent)
        if let projectID {
            setAgentContextSelectionToken(projectID)
        } else {
            setAgentContextSelectionToken("__workspace__")
        }
        selectSection(.llmLab)
        startNewAgentConversation()
        agentGoal = prompt
        recordAppDebugEvent(AppDebugEventName.agentIntentGraphRouted.rawValue, payload: .object([
            "action": .string(actionName),
            "tool": .string(preferredToolName),
            "workflow": .string("graph_insight"),
            "project_id": .string(projectID ?? "")
        ]))
        generateAgentPlan()
    }

    func importGraphExternalPaper(from identifier: String) async throws -> Paper {
        guard let currentWorkspace else {
            throw GraphExternalPaperImportError.missingWorkspace
        }

        if let existing = existingPaper(matchingGraphImportIdentifier: identifier) {
            selectPaper(id: existing.id)
            return existing
        }

        let collectionPath = selectedCollectionPath ?? workspacePreferences.defaultCollectionPath ?? "Uncategorized"
        var importedPaper = try await remoteImportService.importItem(
            from: identifier,
            draftPreview: nil,
            into: currentWorkspace,
            existingPapers: papers,
            collectionPath: collectionPath,
            tags: []
        )

        if let selectedLibraryProjectID,
           !importedPaper.projectIDs.contains(selectedLibraryProjectID) {
            importedPaper.projectIDs.append(selectedLibraryProjectID)
            importedPaper = try await paperRepository.save(importedPaper, in: currentWorkspace)
        }

        try await loadWorkspaceData(
            in: currentWorkspace,
            selectingPaper: importedPaper.id,
            selectingMarkdown: selectedMarkdownID
        )
        startMarkdownConversion(for: [importedPaper], in: currentWorkspace, statusSurface: .workspace)
        return importedPaper
    }

    func existingPaper(matchingGraphImportIdentifier identifier: String) -> Paper? {
        let parsed = IdentifierParser().parse(identifier)
        switch parsed.kind {
        case .inspire:
            let inspireID = parsed.normalizedValue
            return papers.first { paper in
                PaperIdentityGenerator.normalizedInspire(paper.inspireID) == inspireID || paper.resolvedGraphNodeID == "inspire:\(inspireID)"
            }
        case .doi:
            guard let doi = PaperIdentityGenerator.normalizedDOI(parsed.normalizedValue) else { return nil }
            return papers.first { PaperIdentityGenerator.normalizedDOI($0.doi) == doi }
        case .arxiv:
            guard let arxiv = PaperIdentityGenerator.normalizedArxiv(parsed.normalizedValue) else { return nil }
            return papers.first { PaperIdentityGenerator.normalizedArxiv($0.arxiv) == arxiv || $0.resolvedGraphNodeID == "arxiv:\(arxiv)" }
        case .pdfURL, .url, .unknown:
            return nil
        }
    }

    func updateShellWindowWidth(_ width: CGFloat) {
        let nextWidth = Double(width)
        let previousModel = responsiveShellModel
        let nextModel = ResponsiveShellPolicy.resolve(
            width: nextWidth,
            route: currentWorkspaceRoute,
            context: currentWorkspaceContextSnapshot,
            preferredRightRailMode: workspacePreferences.rightRailMode
        )
        let nextIsNarrow = nextModel.bucket == .compact || nextModel.bucket == .narrow
        guard shellWindowWidth != nextWidth || isShellNarrowWidth != nextIsNarrow else {
            return
        }
        shellWindowWidth = nextWidth
        isShellNarrowWidth = nextIsNarrow
        recordShellDebugEvent("shell.responsive_policy.apply", payload: .object([
            "from_bucket": .string(previousModel.bucket.rawValue),
            "to_bucket": .string(nextModel.bucket.rawValue),
            "width": .number(String(nextWidth)),
            "home_widget_columns": .number(String(nextModel.homeWidgetColumns)),
            "toolbar_overflow": .bool(nextModel.shouldMoveToolbarPageActionsToOverflow),
            "from": .string(workspacePreferences.rightRailMode.rawValue),
            "to": .string(nextModel.effectiveRightRailMode.rawValue),
            "source": .string("window_width"),
            "is_narrow": .bool(nextIsNarrow)
        ]))
    }

    func enterHomeLayoutEdit() {
        isEditingHomeLayout = true
        recordHomeDebugEvent("home.widget.layout_enter_edit")
    }

    func exitHomeLayoutEdit() {
        isEditingHomeLayout = false
        isShowingHomeWidgetGallery = false
        recordHomeDebugEvent("home.widget.layout_exit_edit")
    }

    func showHomeWidgetGallery(_ isShowing: Bool) {
        isShowingHomeWidgetGallery = isShowing
        recordHomeDebugEvent("home.widget.gallery", payload: .object([
            "is_showing": .bool(isShowing)
        ]))
    }

    func moveHomeWidget(_ widgetID: String, offset: Int, columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.moveWidget(
                widgetID,
                offset: offset,
                descriptors: HomeWidgetRegistry.defaultDescriptors,
                columns: columns
            )
        }
        recordHomeDebugEvent("home.widget.move", payload: .object([
            "widget_id": .string(widgetID),
            "offset": .number(String(offset)),
            "columns": .number(String(columns))
        ]))
    }

    func moveHomeWidget(_ sourceWidgetID: String, before targetWidgetID: String, columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.moveWidget(
                sourceWidgetID,
                before: targetWidgetID,
                descriptors: HomeWidgetRegistry.defaultDescriptors,
                columns: columns
            )
        }
        recordHomeDebugEvent("home.widget.move", payload: .object([
            "widget_id": .string(sourceWidgetID),
            "before": .string(targetWidgetID),
            "columns": .number(String(columns))
        ]))
    }

    /// Drop-target move: place source widget at the slot currently held by
    /// target. Used by the dashboard drag handler so forward and backward
    /// drags both end up swapping into the target's tile.
    func moveHomeWidget(_ sourceWidgetID: String, onto targetWidgetID: String, columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.moveWidget(
                sourceWidgetID,
                onto: targetWidgetID,
                descriptors: HomeWidgetRegistry.defaultDescriptors,
                columns: columns
            )
        }
        recordHomeDebugEvent("home.widget.move", payload: .object([
            "widget_id": .string(sourceWidgetID),
            "onto": .string(targetWidgetID),
            "columns": .number(String(columns))
        ]))
    }

    func resizeHomeWidget(_ widgetID: String, to size: HomeWidgetSize, columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.resizeWidget(
                widgetID,
                to: size,
                descriptors: HomeWidgetRegistry.defaultDescriptors,
                columns: columns
            )
        }
        recordHomeDebugEvent("home.widget.resize", payload: .object([
            "widget_id": .string(widgetID),
            "size": .string(size.rawValue),
            "columns": .number(String(columns))
        ]))
    }

    func toggleHomeWidget(_ widgetID: String, isEnabled: Bool, columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.setWidget(
                widgetID,
                isEnabled: isEnabled,
                descriptors: HomeWidgetRegistry.defaultDescriptors,
                columns: columns
            )
        }
        recordHomeDebugEvent("home.widget.toggle", payload: .object([
            "widget_id": .string(widgetID),
            "is_enabled": .bool(isEnabled),
            "columns": .number(String(columns))
        ]))
    }

    func resetHomeWidgetLayout(columns: Int) {
        updateWorkspacePreferences { preferences in
            preferences.homeWidgetLayout.reset(descriptors: HomeWidgetRegistry.defaultDescriptors, columns: columns)
        }
        recordHomeDebugEvent("home.widget.reset_default", payload: .object([
            "columns": .number(String(columns))
        ]))
    }

    func toggleProjectTreeExpansion() {
        updateWorkspacePreferences { preferences in
            preferences.isProjectTreeExpanded.toggle()
        }
        recordShellDebugEvent("sidebar.project_tree.toggle", payload: .object([
            "is_expanded": .bool(workspacePreferences.isProjectTreeExpanded)
        ]))
    }

    func isResearchProjectPinned(_ projectID: ResearchProject.ID) -> Bool {
        workspacePreferences.pinnedProjectIDs.contains(projectID)
    }

    func toggleResearchProjectPin(_ project: ResearchProject) {
        updateWorkspacePreferences { preferences in
            if preferences.pinnedProjectIDs.contains(project.id) {
                preferences.pinnedProjectIDs.removeAll { $0 == project.id }
            } else {
                preferences.pinnedProjectIDs.append(project.id)
            }
        }
        recordShellDebugEvent("sidebar.project_tree.toggle", payload: .object([
            "project_id": .string(project.id),
            "pin_state": .bool(isResearchProjectPinned(project.id))
        ]))
    }

    func confirmArchiveResearchProject(_ project: ResearchProject) {
        projectPendingDeletion = project
        projectPendingLifecycleAction = .archive
        isShowingProjectDeleteConfirmation = true
        recordShellDebugEvent("project.archive.requested", payload: .object([
            "project_id_hash": .string(project.id.stableHashForDebug),
            "relative_path_present": .bool(!project.relativePath.isEmpty)
        ]))
    }

    func confirmTrashResearchProject(_ project: ResearchProject) {
        projectPendingDeletion = project
        projectPendingLifecycleAction = .deleteToTrash
        isShowingProjectDeleteConfirmation = true
        recordShellDebugEvent("project.delete.requested", payload: .object([
            "project_id_hash": .string(project.id.stableHashForDebug),
            "mode": .string(ProjectLifecycleAction.deleteToTrash.rawValue)
        ]))
    }

    func confirmDeleteResearchProject(_ project: ResearchProject) {
        confirmArchiveResearchProject(project)
    }

    func cancelDeleteResearchProject() {
        projectPendingDeletion = nil
        projectPendingLifecycleAction = .archive
        isShowingProjectDeleteConfirmation = false
    }

    func confirmDeletePendingResearchProject() {
        guard let project = projectPendingDeletion, let currentResearchRoot else {
            cancelDeleteResearchProject()
            return
        }

        projectPendingDeletion = nil
        isShowingProjectDeleteConfirmation = false
        let action = projectPendingLifecycleAction
        projectPendingLifecycleAction = .archive

        Task {
            do {
                let result: ProjectLifecycleResult
                switch action {
                case .archive:
                    result = try await projectRegistryRepository.archiveProject(project.id, in: currentResearchRoot)
                case .deleteToTrash:
                    result = try await projectRegistryRepository.deleteProjectToTrash(project.id, in: currentResearchRoot)
                }

                researchProjects = result.registry.projects
                updateWorkspacePreferences { preferences in
                    preferences.pinnedProjectIDs.removeAll { $0 == project.id }
                }

                if selectedProjectSpaceProjectID == project.id || currentProjectID == project.id {
                    selectedProjectSpaceProjectID = nil
                    currentProjectID = activeResearchProjects.first?.id
                    selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.overviewTabID
                    selectedSection = .projects
                    selectedLibraryProjectID = nil
                    persistWorkspaceRoute(WorkspaceRoute(top: .projects))
                }

                switch action {
                case .archive:
                    showShellStatus(tf(.projectArchiveStatusFormat, project.name))
                    recordShellDebugEvent("project.archive.confirmed", payload: .object([
                        "project_id_hash": .string(project.id.stableHashForDebug)
                    ]))
                case .deleteToTrash:
                    showShellStatus(tf(.projectTrashStatusFormat, project.name))
                    recordShellDebugEvent("project.delete.confirmed", payload: .object([
                        "project_id_hash": .string(project.id.stableHashForDebug),
                        "mode": .string(ProjectLifecycleAction.deleteToTrash.rawValue)
                    ]))
                }
            } catch {
                present(error)
            }
        }
    }

    func restoreResearchProject(_ project: ResearchProject) {
        guard let currentResearchRoot else {
            return
        }

        Task {
            do {
                let result = try await projectRegistryRepository.restoreProject(project.id, in: currentResearchRoot)
                researchProjects = result.registry.projects
                showShellStatus(tf(.projectRestoreStatusFormat, result.project.name))
                recordShellDebugEvent("project.restore.confirmed", payload: .object([
                    "project_id_hash": .string(project.id.stableHashForDebug)
                ]))
            } catch {
                present(error)
            }
        }
    }

    func recordSidebarRender() {
        let items = topSidebarItems
        recordShellDebugEvent("sidebar.render", payload: .object([
            "top_items": jsonStringArray(items.map(\.id)),
            "pinned_order": jsonStringArray(workspacePreferences.pinnedTopLevelOrder)
        ]))
    }

    func persistLastOpenedProject(_ projectID: ResearchProject.ID) {
        guard let currentResearchRoot else {
            return
        }

        Task {
            do {
                var registry = try await projectRegistryRepository.load(in: currentResearchRoot)
                registry.lastOpenedProjectID = projectID
                try await projectRegistryRepository.save(registry, in: currentResearchRoot)
            } catch {
                present(error)
            }
        }
    }

    func beginCreatingResearchProject() {
        researchProjectEditorDraft = ResearchProjectEditorDraft()
        isShowingResearchProjectEditor = true
    }

    func beginEditingResearchProject(_ projectID: ResearchProject.ID) {
        guard let project = researchProjects.first(where: { $0.id == projectID }) else {
            present(ProjectRegistryError.projectNotFound(projectID))
            return
        }

        researchProjectEditorDraft = ResearchProjectEditorDraft(project: project)
        isShowingResearchProjectEditor = true
    }

    func toggleResearchProjectCollapse(_ projectID: ResearchProject.ID) {
        guard let index = researchProjects.firstIndex(where: { $0.id == projectID }) else {
            return
        }

        let isCollapsed = !researchProjects[index].isCollapsed
        researchProjects[index].isCollapsed = isCollapsed

        guard let currentResearchRoot else {
            return
        }

        Task {
            do {
                let registry = try await projectRegistryRepository.setProjectCollapsed(projectID, isCollapsed: isCollapsed, in: currentResearchRoot)
                researchProjects = registry.projects
            } catch {
                present(error)
            }
        }
    }

    func saveResearchProjectDraft() {
        guard let currentResearchRoot else {
            return
        }

        let draft = researchProjectEditorDraft
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            present(ProjectRegistryError.projectNameRequired)
            return
        }

        isSavingResearchProject = true
        Task {
            defer {
                isSavingResearchProject = false
            }

            do {
                if let projectID = draft.id {
                    guard var project = researchProjects.first(where: { $0.id == projectID }) else {
                        throw ProjectRegistryError.projectNotFound(projectID)
                    }

                    project.name = name
                    project.description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    project.colorHex = draft.colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "#4F7CAC" : draft.colorHex
                    project.iconName = draft.iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "folder" : draft.iconName
                    let registry = try await projectRegistryRepository.updateProject(project, in: currentResearchRoot)
                    researchProjects = registry.projects
                } else {
                    let project = try await projectRegistryRepository.createProject(
                        named: name,
                        description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                        colorHex: draft.colorHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "#4F7CAC" : draft.colorHex,
                        iconName: draft.iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "folder" : draft.iconName,
                        in: currentResearchRoot
                    )
                    let registry = try await projectRegistryRepository.load(in: currentResearchRoot)
                    researchProjects = registry.projects
                    currentProjectID = project.id
                    selectedProjectSpaceProjectID = project.id
                    selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.overviewTabID
                    selectedSection = .projects
                    persistWorkspaceRoute(WorkspaceRoute(top: .projects, projectID: project.id, projectTabID: ProjectSpaceTabsBuilder.overviewTabID))
                }

                isShowingResearchProjectEditor = false
            } catch {
                present(error)
            }
        }
    }

    func revealCurrentWorkspaceInFinder() {
        guard let currentWorkspace else {
            return
        }

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentWorkspace.rootURL.path)
    }

    func revealSelectedPaperInFinder() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        revealPaperInFinder(selectedPaperDraft, in: currentWorkspace)
    }

    func revealPaperInFinder(_ paper: Paper) {
        guard let currentWorkspace else {
            return
        }

        revealPaperInFinder(paper, in: currentWorkspace)
    }

    func revealPaperInFinder(_ paper: Paper, in workspace: ResearchWorkspace) {
        let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: paperDirectoryURL.path)
    }

    func clearRecentWorkspaceBookmark() {
        Task {
            await workspaceService.clearRecentWorkspaceBookmark()
            workspaceSettingsStatusMessage = "Recent workspace bookmark cleared. The current workspace stays open for this session."
        }
    }

    func renameCurrentWorkspace(to newName: String) {
        guard let workspaceToRename = currentWorkspace else {
            return
        }

        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != workspaceToRename.displayName else {
            return
        }

        let sourceURL = workspaceToRename.rootURL.standardizedFileURL
        let targetURL = sourceURL.deletingLastPathComponent().appendingPathComponent(trimmedName, isDirectory: true)
        guard sourceURL != targetURL else {
            return
        }

        isWorking = true
        Task {
            defer {
                isWorking = false
            }

            do {
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    throw CocoaError(.fileWriteFileExists)
                }
                try FileManager.default.moveItem(at: sourceURL, to: targetURL)
                let workspace = try await workspaceService.openWorkspace(at: targetURL)
                try await loadWorkspaceData(
                    in: workspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
                workspaceSettingsStatusMessage = "Workspace renamed to \(trimmedName)."
            } catch {
                present(error)
            }
        }
    }

    func updateDefaultCollectionPath(_ value: String) {
        updateWorkspacePreferences { preferences in
            preferences.defaultCollectionPath = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty
        }
    }

    func updateAddTodosToAppleReminders(_ isEnabled: Bool) {
        addTodosToAppleReminders = isEnabled
        updateWorkspacePreferences { preferences in
            preferences.syncTodosToAppleReminders = isEnabled
        }
    }

    func updateLibraryVisibleColumns(storageValue: String) {
        updateWorkspacePreferences { preferences in
            preferences.updateLibraryVisibleColumns(from: storageValue)
        }
    }

    func updateLibrarySort(field: LibrarySortField, isAscending: Bool) {
        updateWorkspacePreferences { preferences in
            preferences.librarySortState = LibrarySortState(field: field, isAscending: isAscending)
        }
    }

    func clearLibrarySort() {
        updateWorkspacePreferences { preferences in
            preferences.librarySortState = LibrarySortState()
        }
    }

    func resetLibraryVisibleColumns() {
        updateWorkspacePreferences { preferences in
            preferences.libraryVisibleColumns = WorkspacePreferences.defaultLibraryVisibleColumns
        }
    }

    func showAgentKnowledgeLibrary() {
        isShowingAgentKnowledgeLibrary = true
    }

    func agentKnowledgePaperHasPDF(_ paper: Paper) -> Bool {
        guard let currentWorkspace, let pdfURL = paper.pdfURL(in: currentWorkspace) else {
            return false
        }

        return FileManager.default.fileExists(atPath: pdfURL.path)
    }

    func agentKnowledgePaperHasMarkdown(_ paper: Paper) -> Bool {
        guard let currentWorkspace else {
            return false
        }

        return paperHasExtractedMarkdown(paper, in: currentWorkspace)
    }

    func paperPDFExists(_ paper: Paper, in workspace: ResearchWorkspace) -> Bool {
        guard let pdfURL = paper.pdfURL(in: workspace) else {
            return false
        }

        return FileManager.default.fileExists(atPath: pdfURL.path)
    }

    func paperHasExtractedMarkdown(_ paper: Paper, in workspace: ResearchWorkspace) -> Bool {
        let markdownURL = paper.rawMarkdownURL(in: workspace)
        guard FileManager.default.fileExists(atPath: markdownURL.path),
              let contents = try? String(contentsOf: markdownURL, encoding: .utf8) else {
            return false
        }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && !trimmed.contains("status: not_extracted")
            && !trimmed.localizedCaseInsensitiveContains("PDF text has not been extracted yet")
    }

    func paperMarkdownConversionMetadata(_ paper: Paper, in workspace: ResearchWorkspace) -> PaperMarkdownConversionMetadata? {
        let markdownURL = paper.rawMarkdownURL(in: workspace)
        guard let contents = try? String(contentsOf: markdownURL, encoding: .utf8) else {
            return nil
        }

        let frontmatter = FrontmatterParser().parse(contents).frontmatter
        return PaperMarkdownConversionMetadata(
            extractionEngine: frontmatter["extraction_engine"]?.stringValue,
            fallbackReason: frontmatter["fallback_reason"]?.stringValue
        )
    }

    func paperMarkdownConversionState(for result: PaperMarkdownConversionResult) -> PaperMarkdownConversionState {
        guard result.didWriteMarkdown else {
            return .failed
        }

        if result.extractionEngine == "pdfkit_fallback" {
            return .fallback
        }
        return .succeeded
    }

    func setAgentKnowledgePaper(_ paperID: Paper.ID, isSelected: Bool) {
        let availablePaperIDs = Set(papers.map(\.id))
        guard availablePaperIDs.contains(paperID) else {
            return
        }

        if isSelected {
            selectedAgentKnowledgePaperIDs.insert(paperID)
        } else {
            selectedAgentKnowledgePaperIDs.remove(paperID)
        }

        persistAgentKnowledgeSelectionAsCustom()
        refreshAgentContext()
    }

    func selectAllAgentKnowledgePapers() {
        selectedAgentKnowledgePaperIDs = Set(papers.map(\.id))
        updateWorkspacePreferences { preferences in
            preferences.agentKnowledgePaperIDs = nil
        }
        refreshAgentContext()
    }

    func clearAgentKnowledgePapers() {
        selectedAgentKnowledgePaperIDs = []
        updateWorkspacePreferences { preferences in
            preferences.agentKnowledgePaperIDs = []
        }
        refreshAgentContext()
    }

    func persistAgentKnowledgeSelectionAsCustom() {
        let selectedIDs = selectedAgentKnowledgePaperIDs.sorted()
        updateWorkspacePreferences { preferences in
            preferences.agentKnowledgePaperIDs = selectedIDs
        }
    }

}
