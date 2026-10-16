import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppViewModel {
    func saveWorkspaceModuleConfiguration(_ configuration: WorkspaceModuleConfiguration) async throws {
        guard let root = currentResearchRoot ?? currentWorkspace.map({ ResearchRoot(rootURL: $0.rootURL) }) else {
            throw ModuleSettingsError.persistFailed("No workspace is open.")
        }
        do {
            try await workspaceModuleConfigurationStore.save(configuration, in: root)
            applyWorkspaceModuleConfiguration(configuration, in: root)
        } catch {
            throw ModuleSettingsError.persistFailed(error.localizedDescription)
        }
    }

    func resetWorkspaceModulesToTemplateDefault() async throws {
        guard let root = currentResearchRoot ?? currentWorkspace.map({ ResearchRoot(rootURL: $0.rootURL) }) else {
            throw ModuleSettingsError.persistFailed("No workspace is open.")
        }
        let template = (try? WorkspaceTemplateRepository().loadTemplate(in: root)) ?? WorkspaceTemplateRegistry.literatureReview
        let beforeModules = workspaceModuleConfiguration.modules.filter(\.enabled).map(\.id).sorted()
        let configuration = WorkspaceModuleRegistry.configuration(for: template)
        try await saveWorkspaceModuleConfiguration(configuration)
        recordModuleSettingsDebugEvent("module_settings.reset_to_template", payload: .object([
            "template_id": .string(template.id),
            "before_modules": jsonStringArray(beforeModules),
            "after_modules": jsonStringArray(configuration.modules.filter(\.enabled).map(\.id).sorted())
        ]))
    }

    @discardableResult
    func setProjectModuleOverride(projectID: ResearchProject.ID, moduleID: String, enabled: Bool?) async throws -> WorkspaceModuleOverride? {
        guard let root = currentResearchRoot ?? currentWorkspace.map({ ResearchRoot(rootURL: $0.rootURL) }) else {
            throw ModuleSettingsError.persistFailed("No workspace is open.")
        }
        let override = try await workspaceModuleOverrideRepository.setOverride(projectID: projectID, moduleID: moduleID, enabled: enabled, in: root)
        if let override {
            workspaceModuleOverrides[projectID] = override
        } else {
            workspaceModuleOverrides.removeValue(forKey: projectID)
        }
        normalizeSelectedSectionForModuleAvailability()
        recordModuleSettingsDebugEvent("module_settings.override_apply", payload: .object([
            "project_id": .string(projectID),
            "id": .string(moduleID),
            "enabled": .bool(enabled ?? (workspaceModuleConfiguration.module(id: moduleID)?.enabled ?? false)),
            "fallback_to_workspace": .bool(enabled == nil),
            "cleared": .bool(enabled == nil)
        ]))
        return override
    }

    func repairWorkspaceModuleDirectory(_ status: WorkspaceModuleDirectoryStatus, approved: Bool) async -> WorkspaceModuleDirectoryRepairOutcome {
        guard let root = currentResearchRoot ?? currentWorkspace.map({ ResearchRoot(rootURL: $0.rootURL) }) else {
            return .failed(path: status.path, reason: "No workspace is open.")
        }

        let repairer = WorkspaceModuleDirectoryRepairer { request in
            AgentPermissionDecision(
                action: approved ? .allow : .deny,
                scope: .once,
                message: approved ? "Approved from Module Settings." : "Denied from Module Settings."
            )
        }
        let outcome = await repairer.repair(status, in: root, activeProjects: activeResearchProjects)
        workspaceModuleDirectoryStatuses = WorkspaceModuleRegistry.directoryStatuses(for: workspaceModuleConfiguration, in: root)
        recordModuleSettingsDebugEvent("module_settings.repair", payload: .object([
            "module_id": .string(status.moduleID),
            "path": .string(status.path),
            "outcome": .string(outcome.debugOutcome),
            "reason": .string(moduleDirectoryRepairReason(outcome))
        ]))
        return outcome
    }

    func recordModuleSettingsDebugEvent(_ event: String, payload: JSONValue = .object([:])) {
        recordAppDebugEvent(event, payload: payload, force: true)
    }

    func recordHomeDebugEvent(_ event: String, payload: JSONValue = .object([:])) {
        recordAppDebugEvent(event, payload: payload)
    }

    func recordShellDebugEvent(_ event: String, payload: JSONValue = .object([:])) {
        recordAppDebugEvent(event, payload: payload)
    }

    func applyWorkspaceModuleConfiguration(_ configuration: WorkspaceModuleConfiguration, in root: ResearchRoot) {
        let mergedConfiguration = WorkspaceModuleRegistry.mergedConfiguration(from: configuration)
        workspaceModuleConfiguration = mergedConfiguration
        workspaceModuleWarnings = WorkspaceModuleRegistry.warnings(for: mergedConfiguration)
        workspaceModuleDirectoryStatuses = WorkspaceModuleRegistry.directoryStatuses(for: mergedConfiguration, in: root)
        normalizeSelectedSectionForModuleAvailability()
    }

    func observeWorkspaceModuleConfigurationChanges(in root: ResearchRoot) {
        workspaceModuleConfigurationWatchTask?.cancel()
        workspaceModuleConfigurationWatchTask = Task { [weak self] in
            guard let self else { return }
            for await configuration in workspaceModuleConfigurationStore.subscribeChanges(in: root) {
                await MainActor.run {
                    self.applyWorkspaceModuleConfiguration(configuration, in: root)
                }
            }
        }
    }

    func loadProjectModuleOverrides(for projects: [ResearchProject], in root: ResearchRoot) async -> [String: WorkspaceModuleOverride] {
        var overrides: [String: WorkspaceModuleOverride] = [:]
        for project in projects {
            if let override = try? await workspaceModuleOverrideRepository.loadOverride(projectID: project.id, in: root) {
                overrides[project.id] = override
            }
        }
        return overrides
    }

    func moduleDirectoryRepairReason(_ outcome: WorkspaceModuleDirectoryRepairOutcome) -> String {
        switch outcome {
        case let .created(paths):
            return paths.joined(separator: ", ")
        case let .skippedWildcard(path):
            return "Skipped wildcard path \(path) because no active project instance was available."
        case let .denied(_, reason), let .failed(_, reason):
            return reason
        }
    }

    func loadLibrary(in workspace: ResearchWorkspace, selecting paperID: Paper.ID?) async throws {
        projectPaperLinks = try await projectPaperLinkRepository.load(in: workspace)
        let loadedPapers = try await paperRepository.loadPapers(in: workspace)
        papers = loadedPapers

        let nextSelectionID = paperID ?? selectedPaperID ?? loadedPapers.first?.id
        let nextSelectedPaper = loadedPapers.first(where: { $0.id == nextSelectionID })
        selectedPaperID = nextSelectedPaper?.id
        selectedLibraryPaperIDs = nextSelectedPaper.map { [$0.id] } ?? []
        selectedPaperDraft = nextSelectedPaper
        reconcileAgentKnowledgeSelectionWithLoadedPapers()
        try await loadSelectedPaperAnnotations(in: workspace)
    }

    func loadLegacyPaperMigrationPlan(in workspace: ResearchWorkspace) async throws {
        legacyPaperMigrationPlan = try await legacyPaperMigrationService.makePlan(in: workspace)
    }

    func loadWorkspacePreferences(in workspace: ResearchWorkspace) async throws {
        workspacePreferences = try await workspacePreferencesRepository.load(in: workspace)
        addTodosToAppleReminders = workspacePreferences.syncTodosToAppleReminders
        restoreWorkspaceRouteFromPreferences()
        normalizeSelectedSectionForModuleAvailability()
        restorePinnedAgentThreadsForCurrentProject()
        restoreAgentToolStateForCurrentScope()
    }

    func fallbackWorkspaceSection() -> WorkspaceSection {
        visibleWorkspaceSidebarSections.first ?? .dashboard
    }

    func fallbackProjectSection() -> WorkspaceSection {
        fallbackProjectSection(for: currentProjectID)
    }

    func fallbackProjectSection(for projectID: ResearchProject.ID?) -> WorkspaceSection {
        visibleProjectSidebarSections(for: projectID).first ?? fallbackWorkspaceSection()
    }

    func normalizeSelectedSectionForModuleAvailability() {
        if let selectedSection, !isWorkspaceSectionAvailable(selectedSection) {
            self.selectedSection = fallbackWorkspaceSection()
        }
        normalizeProjectSpaceSelectionForAvailability()
        if isViewingGlobalTodos && !isWorkspaceSectionAvailable(.tasks) {
            isViewingGlobalTodos = false
        }
        if !isWorkspaceSectionAvailable(.library) {
            selectedLibraryProjectID = nil
            selectedCollectionPath = nil
            selectedTagName = nil
        }
    }

    func normalizeProjectSpaceSelectionForAvailability() {
        guard let projectID = selectedProjectSpaceProjectID else {
            return
        }

        guard activeResearchProjects.contains(where: { $0.id == projectID }) else {
            selectedProjectSpaceProjectID = nil
            selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.overviewTabID
            selectedSection = .projects
            showShellStatus(localized("项目已不存在，已回到项目列表。", "Project no longer exists; returned to the project list."))
            recordShellDebugEvent("route.persist.fallback", payload: .object([
                "reason": .string(RoutePersistenceFallbackReason.projectMissing.rawValue)
            ]))
            return
        }

        let availableTabs = projectSpaceTabs(for: projectID)
        if ProjectSpaceTabsBuilder.retiredReadingTabIDs.contains(selectedProjectSpaceTabID),
           availableTabs.contains(where: { $0.id == ProjectSpaceTabsBuilder.mergedReadingTabID }) {
            selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.mergedReadingTabID
            return
        }
        if !availableTabs.contains(where: { $0.id == selectedProjectSpaceTabID }) {
            let hiddenTabID = selectedProjectSpaceTabID
            selectedProjectSpaceTabID = ProjectSpaceTabsBuilder.overviewTabID
            recordShellDebugEvent("project_space.builder_warn", payload: .object([
                "project_id": .string(projectID),
                "hidden_tabs": jsonStringArray([hiddenTabID]),
                "reason": .string("module_disabled")
            ]))
            recordShellDebugEvent("route.persist.fallback", payload: .object([
                "reason": .string(RoutePersistenceFallbackReason.moduleDisabled.rawValue)
            ]))
        }
    }

    func restoreWorkspaceRouteFromPreferences() {
        let candidate = workspacePreferences.lastRoute ?? legacyRouteFromRecentSection()
        let result = RoutePersistence.restoreResult(
            candidate: candidate,
            activeProjectIDs: Set(activeResearchProjects.map(\.id)),
            configuration: effectiveModuleConfiguration(for: candidate.projectID ?? currentProjectID)
        )
        applyRestoredRoute(result.route)
        if let fallbackReason = result.fallbackReason {
            recordShellDebugEvent("route.persist.fallback", payload: .object([
                "reason": .string(fallbackReason.rawValue)
            ]))
        }
    }

    func applyRestoredRoute(_ route: WorkspaceRoute) {
        selectedSection = WorkspaceNavigationPolicy.section(for: route.top)
        isViewingGlobalTodos = route.secondarySelection == "global_todos"
        selectedProjectSpaceProjectID = nil

        switch route.top {
        case .home, .settings:
            break
        case .projects:
            if let projectID = route.projectID, activeResearchProjects.contains(where: { $0.id == projectID }) {
                currentProjectID = projectID
                selectedProjectSpaceProjectID = projectID
                let availableTabIDs = Set(projectSpaceTabs(for: projectID).map(\.id))
                let restoredTabID = route.projectTabID ?? ProjectSpaceTabsBuilder.overviewTabID
                let migratedTabID = ProjectSpaceTabsBuilder.retiredReadingTabIDs.contains(restoredTabID) ? ProjectSpaceTabsBuilder.mergedReadingTabID : restoredTabID
                selectedProjectSpaceTabID = availableTabIDs.contains(migratedTabID) ? migratedTabID : ProjectSpaceTabsBuilder.overviewTabID
                if selectedProjectSpaceTabID == "papers" {
                    selectedLibraryProjectID = projectID
                    selectedCollectionPath = nil
                    selectedTagName = nil
                }
            }
        case .library:
            selectedLibraryProjectID = nil
            selectedCollectionPath = nil
            selectedTagName = nil
        case .calendar:
            break
        case .aiLab:
            break
        }
    }

    func legacyRouteFromRecentSection() -> WorkspaceRoute {
        WorkspaceNavigationPolicy.legacyRoute(
            recentSection: workspacePreferences.recentSection,
            currentProjectID: currentProjectID
        )
    }

    func persistWorkspaceRoute(_ route: WorkspaceRoute) {
        if workspacePreferences.lastRoute == route,
           workspacePreferences.recentSection == WorkspaceNavigationPolicy.recentSectionValue(for: route) {
            return
        }
        updateWorkspacePreferences { preferences in
            preferences.lastRoute = route
            preferences.recentSection = WorkspaceNavigationPolicy.recentSectionValue(for: route)
        }
        recordShellDebugEvent("route.persist", payload: .object([
            "top": .string(route.top.rawValue),
            "project_id_present": .bool(route.projectID != nil),
            "tab_id": .string(route.projectTabID ?? "")
        ]))
    }

    func ensurePaperImportContextForGlobalMenu() {
        guard !ToolbarPolicy.showsPaperImportActions(route: currentWorkspaceRoute, context: currentWorkspaceContextSnapshot) else {
            return
        }
        selectLibraryScope()
        showShellStatus(localized("已切换到 Library，可继续导入论文。", "Switched to Library for paper import."))
    }

    func currentWorkspaceContextDebugPayload(reason: String) -> JSONValue {
        let snapshot = currentWorkspaceContextSnapshot
        return .object([
            "reason": .string(reason),
            "top": .string(snapshot.topLevelSectionID),
            "project_id_present": .bool(snapshot.projectID != nil),
            "project_tab_id": .string(snapshot.projectTabID ?? ""),
            "selected_paper_id_present": .bool(snapshot.selectedPaperID != nil),
            "selected_paper_title": .string(snapshot.selectedPaperTitle ?? ""),
            "selected_paper_markdown_path": .string(snapshot.selectedPaperMarkdownPath ?? ""),
            "selected_markdown_path": .string(snapshot.selectedMarkdownPath ?? ""),
            "selected_todo_id_present": .bool(snapshot.selectedTodoID != nil),
            "pdf_page_index": .string(snapshot.pdfPageIndex.map(String.init) ?? ""),
            "selected_text_preview_present": .bool(snapshot.selectedTextPreview != nil)
        ])
    }

    func calendarDayRange(for date: Date) -> DateInterval? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    func showShellStatus(_ message: String) {
        shellStatusMessage = message
        shellStatusDismissTask?.cancel()
        shellStatusDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if self?.shellStatusMessage == message {
                    self?.shellStatusMessage = nil
                }
            }
        }
    }

    func reconcileAgentKnowledgeSelectionWithLoadedPapers() {
        let availablePaperIDs = Set(papers.map(\.id))
        if let storedPaperIDs = workspacePreferences.agentKnowledgePaperIDs {
            selectedAgentKnowledgePaperIDs = Set(storedPaperIDs).intersection(availablePaperIDs)
        } else {
            selectedAgentKnowledgePaperIDs = availablePaperIDs
        }
    }

    func loadSelectedPaperAnnotations(in workspace: ResearchWorkspace) async throws {
        guard let selectedPaperDraft else {
            selectedPaperAnnotationsDraft = ""
            return
        }

        selectedPaperAnnotationsDraft = try await paperAnnotationsRepository.loadAnnotations(for: selectedPaperDraft, in: workspace)
    }

    func loadSelectedPDFAnnotations(in workspace: ResearchWorkspace) async throws {
        guard let selectedPaperDraft else {
            selectedPDFAnnotations = []
            return
        }

        selectedPDFAnnotations = deduplicatedPDFAnnotations(try await pdfAnnotationStore.loadAnnotations(for: selectedPaperDraft, in: workspace))
    }

    func deduplicatedPDFAnnotations(_ annotations: [PDFAnnotationRecord]) -> [PDFAnnotationRecord] {
        var seenFingerprints = Set<String>()
        return annotations.filter { annotation in
            guard annotation.kind != .note else {
                return true
            }
            return seenFingerprints.insert(annotation.duplicateFingerprint).inserted
        }
    }

    func applyWorkspaceRoute(_ route: WorkspaceRoute) {
        applyRestoredRoute(route)
        persistWorkspaceRoute(route)
        applyRightRailRouteSuggestion()
        refreshAgentContext()
    }

    func loadCollections(in workspace: ResearchWorkspace) async throws {
        collections = try await collectionRepository.loadCollections(in: workspace)

        if let selectedCollectionPath,
           !collections.contains(where: { $0.relativePath == selectedCollectionPath }) {
            self.selectedCollectionPath = nil
        }
    }

    func loadTags(in workspace: ResearchWorkspace) async throws {
        tagDefinitions = try await tagRepository.loadDefinitions(in: workspace)

        if let selectedTagName,
           !availableTagDefinitions.contains(where: { $0.name == selectedTagName }) {
            self.selectedTagName = nil
        }
    }

    func loadTodos(in workspace: ResearchWorkspace) async throws {
        todos = try await todoRepository.loadTodos(in: workspace)
        todoTagDefinitions = try await todoTagRepository.loadDefinitions(in: workspace)
    }

    /// All task tag definitions, augmented with any inferred tags found on
    /// existing todos that lack an explicit definition (so colors stay stable).
    var availableTodoTagDefinitions: [TagDefinition] {
        let existingNames = Set(todoTagDefinitions.map(\.name))
        let inferred = Set(todos.flatMap(\.tags))
            .subtracting(existingNames)
            .map { Self.inferredTagDefinition(named: $0) }
        return (todoTagDefinitions + inferred)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func todoTagDefinition(named name: String) -> TagDefinition? {
        availableTodoTagDefinitions.first(where: { $0.name == name })
    }

    func upsertTodoTag(_ definition: TagDefinition) {
        guard let currentWorkspace else {
            return
        }
        Task {
            do {
                try await todoTagRepository.upsert(definition, in: currentWorkspace)
                todoTagDefinitions = try await todoTagRepository.loadDefinitions(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func deleteTodoTag(named name: String) {
        guard let currentWorkspace else {
            return
        }
        Task {
            do {
                try await todoTagRepository.deleteTag(named: name, in: currentWorkspace)
                todoTagDefinitions = try await todoTagRepository.loadDefinitions(in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func loadCalendarEvents(in workspace: ResearchWorkspace) async throws {
        calendarEvents = try await calendarRepository.loadEvents(in: workspace)
    }

    func loadSystemSchedule(
        around referenceDate: Date,
        workspace: ResearchWorkspace? = nil,
        synchronizeMappedTodos: Bool = true
    ) async throws {
        let range = systemScheduleRange(around: referenceDate)
        systemScheduleItems = try await systemCalendarService.loadItems(from: range.start, to: range.end)
        if synchronizeMappedTodos, let workspace = workspace ?? currentWorkspace {
            try await syncMappedTodos(with: systemScheduleItems, in: workspace)
        }
    }

    func createAppleReminderIfNeeded(for todo: TodoItem, in workspace: ResearchWorkspace) async throws -> TodoItem {
        if !systemCalendarService.canCreateReminders {
            systemCalendarAccessState = try await systemCalendarService.requestAccess()
        }

        guard systemCalendarService.canCreateReminders else {
            throw SystemCalendarServiceError.accessDenied
        }

        if todo.externalSource == "apple_reminders", todo.externalIdentifier != nil {
            return todo
        }

        var mappedTodo = todo
        if let reminder = try await systemCalendarService.createReminder(
            title: todo.title,
            dueDate: todo.dueDate,
            notes: todo.notes
        ) {
            mappedTodo.externalSource = "apple_reminders"
            mappedTodo.externalIdentifier = reminder.id
            mappedTodo.externalUpdatedAt = Date()
            mappedTodo.updatedAt = Date()
            try await todoRepository.upsert(mappedTodo, in: workspace)
            systemScheduleItems.append(reminder)
            systemScheduleItems.sort { $0.displayDate < $1.displayDate }
        }

        systemCalendarAccessState = systemCalendarService.accessState
        return mappedTodo
    }

    func syncMappedTodos(with items: [SystemScheduleItem], in workspace: ResearchWorkspace) async throws {
        var didUpdateTodos = false
        let calendar = Calendar.current

        for todo in todos where todo.externalSource == "apple_reminders" {
            guard let externalIdentifier = todo.externalIdentifier,
                  let item = items.first(where: { $0.id == externalIdentifier || "reminder-\(externalIdentifier)" == $0.id }) else {
                continue
            }

            var syncedTodo = todo
            syncedTodo.title = item.title
            syncedTodo.dueDate = calendar.startOfDay(for: item.displayDate)
            syncedTodo.notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty ?? syncedTodo.notes
            syncedTodo.status = item.isCompleted ? .done : syncedTodo.status
            syncedTodo.completedAt = item.isCompleted ? (syncedTodo.completedAt ?? Date()) : syncedTodo.completedAt
            syncedTodo.externalUpdatedAt = Date()
            syncedTodo.updatedAt = Date()

            if syncedTodo != todo {
                try await todoRepository.upsert(syncedTodo, in: workspace)
                didUpdateTodos = true
            }
        }

        if didUpdateTodos {
            try await loadTodos(in: workspace)
        }
    }

    func updateWorkspacePreferences(_ mutate: (inout WorkspacePreferences) -> Void) {
        var preferences = workspacePreferences
        mutate(&preferences)
        guard preferences != workspacePreferences else {
            return
        }
        workspacePreferences = preferences
        persistWorkspacePreferences(preferences)
    }

    func persistWorkspacePreferences(_ preferences: WorkspacePreferences) {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await workspacePreferencesRepository.save(preferences, in: currentWorkspace)
            } catch {
                present(error)
            }
        }
    }

    func recordAppDebugEvent(
        _ event: String,
        payload: JSONValue = .object([:]),
        runID: String? = nil,
        threadID: String? = nil,
        force: Bool = false
    ) {
        let bridgeForced: Bool
        #if DEBUG
        bridgeForced = uiTestBridgeForceDebugLogging
        #else
        bridgeForced = false
        #endif
        guard force || bridgeForced || workspacePreferences.agentDebugLoggingEnabled else {
            return
        }
        guard let currentWorkspace else {
            return
        }

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        let debugEvent = AppDebugEvent(
            event: event,
            workspaceID: currentAgentWorkspaceID,
            projectID: agentConversationProjectID,
            threadID: threadID ?? activeAgentThreadID,
            runID: runID ?? agentCurrentRun?.id,
            payload: payload
        )

        Task {
            try? await appDebugEventLogger.append(debugEvent, in: root)
        }
    }

    func recordAgentRunDebugOutput(_ run: AgentRun, event: String) {
        var payload: [String: JSONValue] = [
            "run_id": .string(run.id),
            "goal": .string(run.goal),
            "mode": .string(run.mode.rawValue),
            "summary": .string(run.plan.summary),
            "tool_results": .array(run.toolResults.map { result in
                var fields: [String: JSONValue] = [
                    "call_id": .string(result.callID),
                    "tool_name": .string(result.toolName),
                    "succeeded": .bool(result.succeeded),
                    "requires_confirmation": .bool(result.requiresConfirmation),
                    "message": .string(result.message),
                    "modified_paths": jsonStringArray(result.modifiedPaths)
                ]
                if let errorMessage = result.errorMessage {
                    fields["error_message"] = .string(errorMessage)
                }
                if let payload = result.payload {
                    fields["payload"] = payload
                }
                return .object(fields)
            })
        ]
        if let finalResponseDraft = run.plan.finalResponseDraft {
            payload["final_response"] = .string(finalResponseDraft)
        }
        if let runtimeSelector = run.runtimeSelector {
            payload["runtime_selector"] = .string(runtimeSelector)
        }
        if let enabledToolNames = run.enabledToolNames {
            payload["enabled_tool_names"] = jsonStringArray(enabledToolNames)
        }
        recordAppDebugEvent(event, payload: .object(payload), runID: run.id)
    }

    func jsonStringArray(_ values: [String]) -> JSONValue {
        .array(values.map { .string($0) })
    }

    func systemScheduleRange(around referenceDate: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) else {
            let start = calendar.date(byAdding: .day, value: -45, to: referenceDate) ?? referenceDate
            let end = calendar.date(byAdding: .day, value: 45, to: referenceDate) ?? referenceDate
            return (start, end)
        }

        let start = calendar.date(byAdding: .day, value: -7, to: monthInterval.start) ?? monthInterval.start
        let end = calendar.date(byAdding: .day, value: 7, to: monthInterval.end) ?? monthInterval.end
        return (start, end)
    }

    func loadLLMSettings(in workspace: ResearchWorkspace) async throws {
        llmConfiguration = try await llmConfigurationStore.load(in: workspace)
        hasLLMAPIKey = false
        hasMinerUAPIToken = false
        hasLoadedSensitiveAIKeys = false
    }

    func loadSensitiveAIKeysIfNeeded() {
        guard let workspace = currentWorkspace, !hasLoadedSensitiveAIKeys else {
            return
        }

        Task {
            do {
                let llmStatus = try await credentialBroker.status(
                    for: .llmAPIKey,
                    account: workspace.rootURL.path
                )
                let minerStatus = try await credentialBroker.status(
                    for: .minerUAPIToken,
                    account: minerUAPITokenAccount(for: workspace)
                )
                hasLLMAPIKey = llmStatus.isConfigured
                hasMinerUAPIToken = minerStatus.isConfigured
                hasLoadedSensitiveAIKeys = true
            } catch {
                present(error)
            }
        }
    }

    func deleteLLMAPIKey() {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                _ = try await credentialBroker.delete(
                    for: .llmAPIKey,
                    account: currentWorkspace.rootURL.path
                )
                hasLLMAPIKey = false
                hasLoadedSensitiveAIKeys = true
                llmConnectionStatusMessage = localized("LLM API Key 已清除。", "LLM API key cleared.")
            } catch {
                present(error)
            }
        }
    }

    func deleteMinerUAPIToken() {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                _ = try await credentialBroker.delete(
                    for: .minerUAPIToken,
                    account: minerUAPITokenAccount(for: currentWorkspace)
                )
                hasMinerUAPIToken = false
                hasLoadedSensitiveAIKeys = true
                workspaceSettingsStatusMessage = localized("MinerU API Token 已清除。", "MinerU API token cleared.")
            } catch {
                present(error)
            }
        }
    }

    func resolvedLLMAPIKey(for workspace: ResearchWorkspace) async throws -> String {
        try await credentialBroker.resolve(for: .llmAPIKey, account: workspace.rootURL.path)
    }

    func resolvedMinerUAPIToken(for workspace: ResearchWorkspace) async throws -> String {
        try await credentialBroker.resolve(
            for: .minerUAPIToken,
            account: minerUAPITokenAccount(for: workspace)
        )
    }

    func minerUAPITokenAccount(for workspace: ResearchWorkspace) -> String {
        workspace.rootURL.path
    }

    func refreshAgentWorkspaceProfile(in root: ResearchRoot) async throws {
        let profile = try await agentWorkspaceProfileRepository.load(in: root)
        applyAgentWorkspaceProfile(profile)
    }

    func applyAgentWorkspaceProfile(_ profile: AgentWorkspaceProfile) {
        agentWorkspaceProfile = profile
        let validationIssues = AgentWorkspaceProfileValidator().validate(profile)
        let summary = AgentWorkspaceProfileSummary(profile: profile, validationIssues: validationIssues)
        agentWorkspaceProfileSummary = summary
        agentWorkspaceProfileMCPServerStatuses = summary.mcpServers
        agentPromptResolutionSummaries = AgentPromptSurface.allCases.map { surface in
            agentPromptLibraryResolver.resolve(surface: surface, profile: profile, basePrompt: "").summary
        }
    }

    func updateAgentWorkspaceProfile(_ mutate: (inout AgentWorkspaceProfile) -> Void) {
        guard let currentWorkspace else {
            return
        }

        var updatedProfile = agentWorkspaceProfile
        mutate(&updatedProfile)
        guard updatedProfile != agentWorkspaceProfile else {
            return
        }

        agentWorkspaceProfile = updatedProfile

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                try await agentWorkspaceProfileRepository.save(updatedProfile, in: root)
                try await refreshAgentWorkspaceProfile(in: root)
            } catch {
                present(error)
            }
        }
    }

    func saveAgentPromptTemplate(
        id: String,
        title: String,
        version: String = "0.1.0",
        description: String,
        surface: AgentPromptSurface,
        systemPrompt: String?,
        promptTemplate: String,
        isEnabled: Bool
    ) {
        guard let currentWorkspace else {
            return
        }
        if let validationMessage = agentPromptLibraryResolver.validatePromptText(promptTemplate) {
            present(AgentError.invalidArguments(validationMessage))
            return
        }
        if let systemPrompt, let validationMessage = agentPromptLibraryResolver.validatePromptText(systemPrompt) {
            present(AgentError.invalidArguments(validationMessage))
            return
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                try await agentWorkspaceProfileRepository.setPromptTemplateBody(
                    id: id,
                    title: title,
                    version: version,
                    description: description,
                    surface: surface,
                    systemPrompt: systemPrompt,
                    promptTemplate: promptTemplate,
                    isEnabled: isEnabled,
                    in: root
                )
                try await refreshAgentWorkspaceProfile(in: root)
            } catch {
                present(error)
            }
        }
    }

    func acceptAgentPromptPatchProposal(_ proposal: AgentPromptPatchProposal) {
        guard let currentWorkspace else {
            return
        }
        let review = agentPromptLibraryResolver.reviewPatchProposal(proposal, profile: agentWorkspaceProfile)
        guard review.canAccept else {
            present(AgentError.invalidArguments(review.validationMessage ?? review.activeSurfaceMismatch ?? "Prompt patch cannot be accepted."))
            return
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                try await agentWorkspaceProfileRepository.acceptPromptPatchProposal(proposal, in: root)
                try await refreshAgentWorkspaceProfile(in: root)
            } catch {
                present(error)
            }
        }
    }

    func prepareAgentSkillImport(from sourceURL: URL) {
        guard let currentWorkspace else {
            return
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                let plan = try await agentSkillLoader.installPlan(
                    for: sourceURL,
                    workspaceRoot: root.rootURL,
                    shouldEnableAfterImport: true
                )
                await MainActor.run {
                    pendingSkillImportPlan = plan
                    isShowingSkillImport = true
                }
            } catch {
                await MainActor.run {
                    present(error)
                }
            }
        }
    }

    func chooseAgentSkillMarkdownForImport() {
        guard let sourceURL = Self.selectSkillMarkdownURL() else {
            return
        }
        prepareAgentSkillImport(from: sourceURL)
    }

    func confirmAgentSkillImport() {
        guard let plan = pendingSkillImportPlan, let currentWorkspace else {
            return
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                try FileManager.default.createDirectory(at: plan.destinationSkillURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: plan.destinationSkillURL.path) {
                    try FileManager.default.removeItem(at: plan.destinationSkillURL)
                }
                try FileManager.default.copyItem(at: plan.sourceSkillURL, to: plan.destinationSkillURL)
                try await agentWorkspaceProfileRepository.setSkillEnabled(
                    skillID: plan.skillID,
                    displayName: plan.skillID,
                    isEnabled: plan.shouldEnableAfterImport,
                    trustLevel: .untrusted,
                    allowedToolIDs: plan.allowedTools,
                    in: root
                )
                try await refreshAgentWorkspaceProfile(in: root)
                await MainActor.run {
                    pendingSkillImportPlan = nil
                    isShowingSkillImport = false
                }
            } catch {
                await MainActor.run {
                    present(error)
                }
            }
        }
    }

    static func selectSkillMarkdownURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Skill"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.directoryURL = defaultPanelDirectoryURL()

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    func createAgentMCPServer() {
        let suffix = String(UUID().uuidString.lowercased().prefix(8))
        saveAgentMCPServer(MCPServerConfiguration(
            id: "mcp-\(suffix)",
            displayName: "MCP \(suffix)",
            transport: .localCommand,
            isEnabled: false,
            command: "",
            timeoutSeconds: 30
        ))
    }

    func saveAgentMCPServer(_ server: MCPServerConfiguration) {
        guard let currentWorkspace else {
            return
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                try await agentWorkspaceProfileRepository.upsertMCPServer(server, in: root)
                try await refreshAgentWorkspaceProfile(in: root)
                try await refreshAgentRuntimeSummaries(in: root)
            } catch {
                present(error)
            }
        }
    }

    func removeAgentMCPServer(id: String) {
        guard let currentWorkspace else {
            return
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                try await agentWorkspaceProfileRepository.removeMCPServer(id: id, in: root)
                try await refreshAgentWorkspaceProfile(in: root)
                try await refreshAgentRuntimeSummaries(in: root)
            } catch {
                present(error)
            }
        }
    }

    func createAgentPromptTemplate(surface: AgentPromptSurface = .planner) {
        let templateID = "prompt-\(UUID().uuidString.lowercased())"
        saveAgentPromptTemplate(
            id: templateID,
            title: "New Prompt",
            version: "0.1.0",
            description: "",
            surface: surface,
            systemPrompt: nil,
            promptTemplate: "",
            isEnabled: false
        )
    }

    func setActiveAgentPromptTemplate(id: String?) {
        guard let currentWorkspace else {
            return
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                try await agentWorkspaceProfileRepository.setActivePromptTemplate(id: id, in: root)
                try await refreshAgentWorkspaceProfile(in: root)
            } catch {
                present(error)
            }
        }
    }

    func setAgentPromptTemplateEnabled(id: String, isEnabled: Bool) {
        guard let currentWorkspace else {
            return
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                try await agentWorkspaceProfileRepository.setPromptTemplateEnabled(id: id, isEnabled: isEnabled, in: root)
                try await refreshAgentWorkspaceProfile(in: root)
            } catch {
                present(error)
            }
        }
    }

    func removeAgentPromptTemplate(id: String) {
        guard let currentWorkspace else {
            return
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                try await agentWorkspaceProfileRepository.removePromptTemplate(id: id, in: root)
                try await refreshAgentWorkspaceProfile(in: root)
            } catch {
                present(error)
            }
        }
    }

    func copyAgentPromptTemplateBody(id: String) {
        guard let template = agentWorkspaceProfile.promptTemplate(id: id) else {
            return
        }

        let body = agentPromptLibraryResolver.renderedTemplateBody(template)
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            agentStatusMessage = "Prompt template body is empty."
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        agentStatusMessage = "Copied prompt template body."
    }

    func promptTemplateDiffPreview(id: String) -> String? {
        guard let template = agentWorkspaceProfile.promptTemplate(id: id) else {
            return nil
        }

        guard let currentTemplate = agentWorkspaceProfile.activePromptTemplate(for: template.surface),
              currentTemplate.id != template.id else {
            return nil
        }

        return agentPromptLibraryResolver.diffPreview(current: currentTemplate, draft: template)
    }

    func restoreDefaultAgentPromptTemplate(id: String) {
        guard let currentWorkspace else {
            return
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                try await agentWorkspaceProfileRepository.restoreDefaultPromptTemplate(id: id, in: root)
                try await refreshAgentWorkspaceProfile(in: root)
            } catch {
                present(error)
            }
        }
    }

}
