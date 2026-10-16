import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppViewModel {

    var filteredPapers: [Paper] {
        let query = librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let matchingPapers = papers.filter { paper in
            let matchesProject = selectedLibraryProjectID.map { projectID in
                paper.projectIDs.contains(projectID)
            } ?? true
            let matchesCollection = selectedCollectionPath.map { selectedPath in
                guard let collectionPath = paper.collectionPath else {
                    return false
                }

                return collectionPath == selectedPath || collectionPath.hasPrefix(selectedPath + "/")
            } ?? true
            let matchesTag = selectedTagName.map { paper.tags.contains($0) } ?? true
            let matchesQuery = librarySearchService.matches(paper, query: query)

            return matchesProject && matchesCollection && matchesTag && matchesQuery
        }

        return workspacePreferences.librarySortState.sorted(matchingPapers)
    }

    var libraryVisibleColumnStorage: String {
        workspacePreferences.libraryVisibleColumnsStorageValue
    }

    var librarySortState: LibrarySortState {
        workspacePreferences.librarySortState
    }

    var selectedLibraryPapers: [Paper] {
        let selectedIDs = selectedLibraryPaperIDs
        return filteredPapers.filter { selectedIDs.contains($0.id) }
    }

    var selectedLibraryPaperCount: Int {
        selectedLibraryPaperIDs.count
    }

    var hasMultipleLibraryPaperSelection: Bool {
        selectedLibraryPaperIDs.count > 1
    }

    var availableTagDefinitions: [TagDefinition] {
        let existingNames = Set(tagDefinitions.map(\.name))
        let inferredDefinitions = Set(papers.flatMap(\.tags))
            .subtracting(existingNames)
            .sorted()
            .map { Self.inferredTagDefinition(named: $0) }

        return (tagDefinitions + inferredDefinitions)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var selectedDateTodos: [TodoItem] {
        TodoQueries.dueOn(todos, date: selectedDashboardDate)
    }

    var currentProjectTodos: [TodoItem] {
        guard let currentProjectID else {
            return todos
        }

        return todos(for: currentProjectID)
    }

    var currentProjectOpenTodos: [TodoItem] {
        currentProjectTodos.filter(TodoQueries.isOpen)
    }

    var selectedDateWorkspaceEvents: [CalendarEvent] {
        let calendar = Calendar.current
        return calendarEvents
            .filter { calendar.isDate($0.date, inSameDayAs: selectedDashboardDate) }
            .sorted { $0.date < $1.date }
    }

    var activeResearchProjects: [ResearchProject] {
        researchProjects.filter { !$0.isArchived }
    }

    var agentConversationRuns: [AgentRun] {
        guard let thread = activeAgentThread else {
            return agentOrphanRuns
        }

        let runsByID = Dictionary(uniqueKeysWithValues: agentRunHistory.map { ($0.id, $0) })
        return thread.runIDs.compactMap { runsByID[$0] }
    }

    var agentTimelineItems: [AgentSessionTimelineItem] {
        AgentSessionTimelineItem.items(
            from: agentSessionEvents,
            runs: agentConversationRuns + [agentCurrentRun].compactMap { $0 },
            sessionIDs: agentRelevantSessionIDs,
            limit: agentTimelineVisibleLimit
        )
    }

    var agentTimelineEvents: [AgentTimelineEvent] {
        AgentTimelineEvent.events(from: agentTimelineItems)
    }

    var canLoadEarlierAgentTimelineEvents: Bool {
        agentTimelineAllItems.count > agentTimelineItems.count
    }

    var agentTimelineAllItems: [AgentSessionTimelineItem] {
        let sessionIDs = agentRelevantSessionIDs
        guard !sessionIDs.isEmpty else {
            return []
        }
        return AgentSessionTimelineItem.items(
            from: agentSessionEvents,
            runs: agentConversationRuns + [agentCurrentRun].compactMap { $0 },
            sessionIDs: sessionIDs,
            limit: nil
        )
    }

    func loadEarlierAgentTimelineEvents() {
        let previousLimit = agentTimelineVisibleLimit
        let totalCount = agentTimelineAllItems.count
        guard totalCount > previousLimit else {
            return
        }
        agentTimelineVisibleLimit = min(totalCount, previousLimit + 160)
        recordAppDebugEvent("ai.timeline.project", payload: .object([
            "event_count": .number(String(totalCount)),
            "hidden_count": .number(String(max(0, totalCount - agentTimelineVisibleLimit))),
            "visible_limit": .number(String(agentTimelineVisibleLimit))
        ]))
    }

    var agentRelevantSessionIDs: Set<String> {
        var ids = Set(agentConversationRuns.map(\.id))
        if let currentRunID = agentCurrentRun?.id {
            ids.insert(currentRunID)
        }
        if let agentLiveRunID {
            ids.insert(agentLiveRunID)
        }
        return ids
    }

    var agentOrphanRuns: [AgentRun] {
        let threadedRunIDs = Set(allAgentThreads.flatMap(\.runIDs))
        return agentRunHistory.filter { run in
            run.currentProjectID == agentConversationProjectID && !threadedRunIDs.contains(run.id)
        }
    }

    var activeAgentThread: AgentThread? {
        guard let activeAgentThreadID else {
            return agentThreads.first
        }

        return allAgentThreads.first { $0.id == activeAgentThreadID && !$0.isArchived }
            ?? (pendingAgentThread?.id == activeAgentThreadID ? pendingAgentThread : nil)
    }

    var agentThreadFilterLabel: String {
        isAgentThreadWorkspaceFilterEnabled ? "当前工作区" : "全部工作区"
    }

    var agentCurrentWorkspaceThreadCount: Int {
        allAgentThreads.filter { !$0.isArchived && isAgentThreadInCurrentWorkspace($0) }.count
    }

    func isAgentThreadInCurrentWorkspace(_ thread: AgentThread) -> Bool {
        thread.belongsToWorkspace(id: currentAgentWorkspaceID)
    }

    func agentThreadSubtitle(for thread: AgentThread) -> String {
        let runLabel = "\(thread.runIDs.count) runs"
        guard let workspaceName = thread.workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workspaceName.isEmpty else {
            return runLabel
        }
        return "\(runLabel) - \(workspaceName)"
    }

    var agentConversationTitle: String {
        if let title = (pendingAgentThread ?? activeAgentThread)?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return agentThreadContextTitle
    }

    var agentContextUsageRatio: Double {
        let limit = max(1, workspacePreferences.agentLoopBudget.maxContextCharacters)
        let messages = agentConversationMessagesForPrompt(latestGoal: agentPendingUserPrompt ?? agentGoal)
        let used = messages.reduce(0) { $0 + $1.content.count }
        return min(1, Double(used) / Double(limit))
    }

    var agentContextUsageLabel: String {
        "\(Int((agentContextUsageRatio * 100).rounded()))%"
    }

    var agentThreadContextTitle: String {
        if let thread = pendingAgentThread ?? activeAgentThread {
            return agentContextTitle(scope: thread.contextScope ?? AgentContextScope.inferred(projectID: thread.projectID), projectID: thread.projectID)
        }

        return agentNextRunContextTitle
    }

    var agentNextRunContextTitle: String {
        agentContextTitle(scope: agentNextRunContextScope, projectID: agentConversationProjectID)
    }

    var agentContextSelectionToken: String {
        agentConversationProjectID ?? "__workspace__"
    }

    var agentConversationProjectID: ResearchProject.ID? {
        if agentNextRunContextScope == .workspace {
            return nil
        }
        return agentNextRunProjectID
            ?? pendingAgentThread?.projectID
            ?? activeAgentThread?.projectID
            ?? currentProjectID
    }

    func setAgentVisibleMode(_ mode: AgentVisibleMode) {
        let previousMode = agentVisibleMode
        guard previousMode != mode else {
            return
        }

        agentInteractionMode = mode.defaultInteractionMode
        recordAppDebugEvent("ai.mode.change", payload: .object([
            "from": .string(previousMode.rawValue),
            "to": .string(mode.rawValue),
            "thread_id_present": .bool(activeAgentThreadID != nil)
        ]))
    }

    func setAgentContextSelectionToken(_ token: String) {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        recordAppDebugEvent("agent.context_changed", payload: .object([
            "token": .string(token),
            "previous_project_id": .string(agentConversationProjectID ?? "")
        ]))
        if token == "__workspace__" {
            agentNextRunContextScope = .workspace
            agentNextRunProjectID = nil
        } else {
            agentNextRunContextScope = .project
            agentNextRunProjectID = token
        }

        if activeAgentThread == nil, pendingAgentThread == nil {
            activeAgentThreadID = preferredAgentThreadID(projectID: agentConversationProjectID)
            agentGoal = agentGoalDrafts[agentDraftKey(projectID: agentConversationProjectID, threadID: activeAgentThreadID)] ?? ""
            restorePersistedAgentDraft(projectID: agentConversationProjectID, threadID: activeAgentThreadID)
        }

        restoreAgentToolStateForCurrentScope()
        refreshAgentContext()
    }

    func agentContextTitle(scope: AgentContextScope, projectID: ResearchProject.ID?) -> String {
        switch scope {
        case .workspace:
            return "全工作区"
        case .project:
            return projectID.map(projectName(for:)) ?? "全工作区"
        }
    }

    var currentResearchProject: ResearchProject? {
        guard let currentProjectID else {
            return activeResearchProjects.first
        }
        return activeResearchProjects.first { $0.id == currentProjectID } ?? activeResearchProjects.first
    }

    var selectedDateSystemScheduleItems: [SystemScheduleItem] {
        let calendar = Calendar.current
        return systemScheduleItems
            .filter { calendar.isDate($0.displayDate, inSameDayAs: selectedDashboardDate) }
            .sorted { first, second in
                if first.displayDate == second.displayDate {
                    return first.title.localizedStandardCompare(second.title) == .orderedAscending
                }
                return first.displayDate < second.displayDate
            }
    }

    var recentPapers: [Paper] {
        Array(papers.prefix(5))
    }

    func papers(for projectID: ResearchProject.ID) -> [Paper] {
        LibraryDomainUseCases.papers(papers, for: projectID)
    }

    func corePapers(for projectID: ResearchProject.ID) -> [Paper] {
        LibraryDomainUseCases.corePapers(papers, for: projectID)
    }

    func projectPaperLink(for paperID: Paper.ID, projectID: ResearchProject.ID) -> ProjectPaperLink? {
        projectPaperLinks.first { $0.paperID == paperID && $0.projectID == projectID }
    }

    func projectPaperLink(for paper: Paper, projectID: ResearchProject.ID) -> ProjectPaperLink? {
        LibraryDomainUseCases.projectLink(
            paper: paper,
            projectID: projectID,
            links: projectPaperLinks
        )
    }

    func projectPaperLinkSortPrecedes(_ first: Paper, _ second: Paper, projectID: ResearchProject.ID) -> Bool {
        LibraryDomainUseCases.projectLinkSortPrecedes(
            first,
            second,
            projectID: projectID,
            links: projectPaperLinks
        )
    }

    func projectName(for projectID: ResearchProject.ID) -> String {
        WorkspaceDomainUseCases.projectName(projectID, projects: researchProjects)
    }

    func projectNames(for paper: Paper) -> [String] {
        WorkspaceDomainUseCases.projectNames(for: paper, projects: researchProjects)
    }

    func todos(for projectID: ResearchProject.ID) -> [TodoItem] {
        WorkspaceDomainUseCases.todos(todos, for: projectID)
    }

    func openTodos(for projectID: ResearchProject.ID) -> [TodoItem] {
        WorkspaceDomainUseCases.openTodos(todos, for: projectID)
    }

    func coreProjectNames(for paper: Paper) -> [String] {
        WorkspaceDomainUseCases.coreProjectNames(for: paper, projects: researchProjects)
    }

    var recentlyReadPapers: [Paper] {
        Array(
            papers
                .filter { $0.lastReadAt != nil }
                .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
                .prefix(5)
        )
    }

    var libraryScopeSummary: String {
        var components: [String] = []

        if let selectedLibraryProjectID {
            components.append("Project: \(projectName(for: selectedLibraryProjectID))")
        }

        if let selectedCollectionPath {
            components.append("Folder: \(selectedCollectionPath)")
        }

        if let selectedTagName {
            components.append("Tag: \(selectedTagName)")
        }

        return components.isEmpty ? "All Papers" : components.joined(separator: " / ")
    }

    var canOpenSelectedPaperPDF: Bool {
        guard let currentWorkspace, let selectedPaperDraft, let pdfURL = selectedPaperDraft.pdfURL(in: currentWorkspace) else {
            return false
        }

        return FileManager.default.fileExists(atPath: pdfURL.path)
    }

    var canEnterSelectedPaperReader: Bool {
        canOpenSelectedPaperPDF
    }

    var canPreviewLibrarySelection: Bool {
        previewPaperForLibrarySelection() != nil
    }

    var agentProviderSummary: String {
        return "OpenAI-compatible / \(llmConfiguration.model)"
    }

    var agentProviderV2Summary: String {
        "Provider V2 wrapper is available for OpenAI-compatible chat requests; plan generation still uses the stable complete path."
    }

    var usesEnglishInterface: Bool {
        appLanguage == .english
    }

    var appLanguage: AppLanguage {
        AppLanguage(preference: workspacePreferences.appLanguage)
    }

    func t(_ key: L10nKey) -> String {
        L10n.text(key, language: appLanguage)
    }

    func tf(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        String(format: L10n.text(key, language: appLanguage), locale: Locale(identifier: appLanguage.rawValue), arguments: arguments)
    }

    /// Migration helper for UI strings that have not moved to L10nKey yet.
    func localized(_ simplifiedChinese: String, _ english: String) -> String {
        usesEnglishInterface ? english : simplifiedChinese
    }

    func appLanguageLabel(for option: AppLanguagePreference) -> String {
        switch option {
        case .system:
            return localized("跟随系统", "Follow System")
        case .simplifiedChinese:
            return localized("中文", "Chinese")
        case .english:
            return localized("English", "English")
        }
    }

    var agentPlatformSummary: String {
        "ExternalAgentRuntime + Swift ToolHost/MCP gateway core"
    }

    var agentPresetSummary: String {
        if let agentPresetDetails {
            let issueSummary = agentPresetDetails.validationIssues.isEmpty ? "valid" : "\(agentPresetDetails.validationIssues.count) issues"
            return "\(agentPresetDetails.name) \(agentPresetDetails.version); \(agentPresetDetails.commands.count) commands; \(agentPresetDetails.skills.count) skills; \(issueSummary)"
        }

        return "research-core preset not found in the current root"
    }

    var agentPermissionSummary: String {
        let writingTools = agentToolDefinitions.filter(\.requiresConfirmation).count
        let dockItems = agentCurrentRun.map { agentPermissionDockItems(for: $0) } ?? []
        let waitingCount = dockItems.filter { $0.approvalState == .waitingForApproval }.count
        return "allow / ask / deny rules active; \(writingTools) tools require approval; \(waitingCount) waiting; \(agentToolApprovals.count) allow once; \(agentToolDenials.count) denied; read-only tools auto-run"
    }

    var agentHookSummary: String {
        let enabledNames = agentHookActivitySummary.enabledEventNames.map(\.rawValue)
        let resultsCount = agentHookActivitySummary.results.count
        return "\(enabledNames.joined(separator: ", ").nilIfAppEmpty ?? "No hooks enabled"); \(resultsCount) results in current timeline"
    }

    var agentMCPStatusSummary: String {
        let productCount = agentProductMCPServerStatuses.count
        let profileCount = agentWorkspaceProfileMCPServerStatuses.count
        let localCount = agentLocalMCPServerStatuses.count
        return ".sci-ai/sci-station: \(productCount) templates; profile: \(profileCount) managed; .sci-ai/workspace.local: \(localCount) local configs; local gateway tools/list+tools/call; side-effect tools require permissions"
    }

    var agentCollaborationSummary: AgentCollaborationSummary {
        let currentRun = agentCurrentRun
        let runtimeSummary = [
            agentRuntimeSelectionSummary,
            "effective=\(agentRuntimeEffectiveSummary)",
            agentRuntimeFallbackSummary.nilIfAppEmpty.map { "fallback=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        let evidenceSummary: String
        let evidenceTint: String
        let writebackSummary: String
        let writebackTint: String
        let promptSummary: String
        let mcpSummary: String
        var writebackTargets: [AgentWritebackTargetSummary] = []
        var needsApproval = false
        var syntheticEvidenceWarning = false

        if let run = currentRun {
            let toolResults = run.toolResults
            let evidenceCount = toolResults.filter { isEvidenceTool($0.toolName) && $0.succeeded }.count
            syntheticEvidenceWarning = run.provenance?.evidenceProvenance != nil
                ? run.provenance?.evidenceProvenance.map { containsSyntheticEvidence(in: $0) } ?? false
                : false
            if evidenceCount > 0 {
                evidenceSummary = "\(evidenceCount) read/search result\(evidenceCount == 1 ? "" : "s") recorded"
                evidenceTint = "green"
            } else if run.lifecycleState == .waitingForApproval {
                evidenceSummary = "Waiting for approved tools"
                evidenceTint = "orange"
            } else if toolResults.isEmpty {
                evidenceSummary = "No tool evidence recorded yet"
                evidenceTint = "secondary"
            } else {
                evidenceSummary = "No paper/wiki evidence tool succeeded"
                evidenceTint = "secondary"
            }

            let writeCalls = run.plan.toolCalls.filter { isWriteTool($0.toolName) }
            let writeResults = toolResults.filter { isWriteTool($0.toolName) }
            let permissionItems = agentPermissionDockItems(for: run)
            writebackTargets = permissionItems.compactMap { item in
                guard item.risk != .readOnly || item.diffPreview != nil || !item.pathPreview.isEmpty else {
                    return nil
                }
                return AgentWritebackTargetSummary(
                    kind: writebackTargetKind(for: item),
                    targetPath: item.pathPreview.first ?? "workspace",
                    summary: item.summaryPreview ?? item.summary,
                    diffPreview: item.diffPreview,
                    risk: item.risk,
                    approvalState: item.approvalState
                )
            }
            needsApproval = permissionItems.contains { $0.approvalState == .waitingForApproval }

            if writeCalls.isEmpty, writeResults.isEmpty {
                writebackSummary = "No writeback requested"
                writebackTint = "secondary"
            } else if writeResults.contains(where: { !$0.modifiedPaths.isEmpty }) {
                let count = writeResults.flatMap(\.modifiedPaths).count
                writebackSummary = "\(count) path\(count == 1 ? "" : "s") modified after approval"
                writebackTint = "green"
            } else if run.lifecycleState == .waitingForApproval || writeResults.contains(where: \.requiresConfirmation) {
                writebackSummary = "Approval required before writing"
                writebackTint = "orange"
            } else if writeResults.contains(where: { !$0.succeeded }) {
                writebackSummary = "Writeback failed or was denied"
                writebackTint = "red"
            } else {
                writebackSummary = "Writeback planned; no files modified"
                writebackTint = "secondary"
            }

            let surface = run.promptTemplateSurface?.rawValue ?? "default"
            let templateID = run.promptTemplateID ?? "bundled"
            let version = run.promptTemplateVersion ?? "-"
            promptSummary = "\(surface) · \(templateID) @ \(version)"
            mcpSummary = agentMCPStatusSummary
        } else {
            evidenceSummary = "No active run"
            evidenceTint = "secondary"
            writebackSummary = "No active run"
            writebackTint = "secondary"
            promptSummary = "Bundled/default until next run"
            mcpSummary = agentMCPStatusSummary
        }

        return AgentCollaborationSummary(
            runtimeSummary: runtimeSummary,
            evidenceSummary: evidenceSummary,
            evidenceTint: evidenceTint,
            writebackSummary: writebackSummary,
            writebackTint: writebackTint,
            promptSummary: promptSummary,
            mcpSummary: mcpSummary,
            writebackTargets: writebackTargets,
            needsApproval: needsApproval,
            syntheticEvidenceWarning: syntheticEvidenceWarning
        )
    }

    func writebackTargetKind(for item: AgentPermissionDockItem) -> AgentWritebackTargetKind {
        switch item.toolName {
        case "create_todo":
            return .todo
        case "write_markdown_plan":
            return .projectBrief
        case "write_wiki_markdown":
            if item.pathPreview.contains(where: { $0.contains("/papers/") || $0.hasPrefix("wiki/papers/") }) {
                return .wikiPaper
            }
            return .wikiNote
        default:
            if item.pathPreview.contains(where: { $0.hasPrefix("tasks/") }) {
                return .todo
            }
            if item.pathPreview.contains(where: { $0.localizedCaseInsensitiveContains("brief") || $0.localizedCaseInsensitiveContains("plan") }) {
                return .projectBrief
            }
            if item.pathPreview.contains(where: { $0.contains("/papers/") || $0.hasPrefix("wiki/papers/") }) {
                return .wikiPaper
            }
            return .workspaceDraft
        }
    }

    var agentRuntimeSelectionSummary: String {
        workspacePreferences.agentRuntimeSelection.label
    }

    var agentRuntimeEffectiveSummary: String {
        workspacePreferences.agentRuntimeSelection.effectiveRuntime(
            sidecarAvailable: agentSidecarHealthIsAvailable,
            sidecarDisabled: workspacePreferences.isSidecarDisabledForWorkspace
        ).label
    }

    var agentSidecarHealthSummary: String {
        if workspacePreferences.isSidecarDisabledForWorkspace {
            return "disabled for workspace"
        }
        let dependencySummary = agentSidecarHealth.dependencies
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value ? "ok" : "missing")" }
            .joined(separator: ", ")
        return [
            agentSidecarHealth.status,
            agentSidecarHealth.pythonVersion.map { "python \($0)" },
            agentSidecarHealth.sidecarVersion.map { "sidecar \($0)" },
            dependencySummary.nilIfAppEmpty
        ]
        .compactMap { $0 }
        .joined(separator: "; ")
    }

    var agentRuntimeFallbackSummary: String {
        workspacePreferences.agentRuntimeSelection.fallbackReason(
            sidecarAvailable: agentSidecarHealthIsAvailable,
            sidecarDisabled: workspacePreferences.isSidecarDisabledForWorkspace
        ) ?? agentSidecarHealth.fallbackReason ?? agentSidecarHealth.lastCrash ?? "No fallback active."
    }

    func isEvidenceTool(_ toolName: String) -> Bool {
        let normalized = toolName.lowercased()
        return normalized.contains("read")
            || normalized.contains("search")
            || normalized.contains("list_papers")
            || normalized.contains("evidence")
            || normalized.contains("graph")
    }

    func isWriteTool(_ toolName: String) -> Bool {
        let normalized = toolName.lowercased()
        return normalized.contains("write")
            || normalized.contains("save")
            || normalized.contains("create")
            || normalized.contains("append")
    }

    func containsSyntheticEvidence(in value: JSONValue) -> Bool {
        let rendered = value.canonicalJSON.lowercased()
        return rendered.contains("synthetic")
            || rendered.contains("sample_evidence")
            || rendered.contains("sample evidence")
            || rendered.contains("fixture")
    }

    var agentDebugLoggingSummary: String {
        workspacePreferences.agentDebugLoggingEnabled
            ? "enabled; .sci-station/debug/app_events.jsonl"
            : "disabled"
    }

    var agentRetrievalIndexSummary: String {
        "\(agentRetrievalStatusLabel); chunks=\(agentRetrievalIndexStatus.chunkCount); stale=\(agentRetrievalIndexStatus.staleCount)"
    }

    var agentRetrievalStoreSummary: String {
        [
            agentRetrievalIndexStatus.store,
            agentRetrievalIndexStatus.fallbackReason.map { "fallback: \($0)" },
            agentRetrievalIndexStatus.errorMessage.map { "error: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "; ")
    }

    var agentRetrievalModelSummary: String {
        "\(agentRetrievalIndexStatus.provider) / \(agentRetrievalIndexStatus.modelID) / dim \(agentRetrievalIndexStatus.dimension)"
    }

    var agentRetrievalDiagnosticSummary: String {
        var sections = [agentRetrievalIndexStatus.diagnosticText]
        sections.append("runtime_selection=\(agentRuntimeSelectionSummary)")
        sections.append("runtime_effective=\(agentRuntimeEffectiveSummary)")
        sections.append("sidecar_health=\(agentSidecarHealthSummary)")
        sections.append("sidecar_fallback=\(agentRuntimeFallbackSummary)")
        sections.append("selected_source=\(selectedAgentRetrievalSourcePath() ?? "none")")
        if let selectedSourceStatus = selectedAgentRetrievalSourceFileStatus() {
            sections.append(selectedSourceStatus.diagnosticText)
        }
        sections.append("last_provider_failure=\(agentLastProviderFailureSummary)")
        if let agentRetrievalZeroChunkHint {
            sections.append("hint=\(agentRetrievalZeroChunkHint)")
        }
        if let paperMarkdownQualityReport {
            sections.append([
                "paper_md_status=\(paperMarkdownQualityReport.status.rawValue)",
                "paper_md_path=\(paperMarkdownQualityReport.markdownRelativePath)",
                "paper_md_engine=\(paperMarkdownQualityReport.extractionEngine ?? "unknown")",
                "paper_md_abstract=\(paperMarkdownQualityReport.hasAbstractHeading)",
                "paper_md_figures=\(paperMarkdownQualityReport.figureAssetCount)",
                "paper_md_display_math=\(paperMarkdownQualityReport.hasDisplayMath)",
                "paper_md_issues=\(paperMarkdownQualityReport.issues.map(\.code.rawValue).joined(separator: ","))"
            ].joined(separator: "\n"))
        }
        return sections.joined(separator: "\n")
    }

    var redactedAgentRetrievalDiagnosticSummary: String {
        AgentDiagnosticRedactor.redacted(agentRetrievalDiagnosticSummary)
    }

    var agentRetrievalSourceHealthSummary: String {
        let source = selectedAgentRetrievalSourcePath() ?? localized("未选择 source", "No source selected")
        let paperHealth = paperMarkdownQualityReport.map { report in
            report.summary(usesEnglishInterface: usesEnglishInterface)
        } ?? localized("paper.md 尚未检查", "paper.md not checked")
        return "\(source); \(agentRetrievalIndexSummary); \(paperHealth)"
    }

    var agentRetrievalSourceHealthIssueLines: [String] {
        var lines: [String] = []
        if let agentRetrievalZeroChunkHint {
            lines.append(agentRetrievalZeroChunkHint)
        }
        lines.append(contentsOf: paperMarkdownQualityIssueLines.prefix(3))
        return lines
    }

    var agentLastProviderFailureSummary: String {
        let latestFailedRun = ([agentCurrentRun].compactMap { $0 } + agentRunHistory)
            .filter { $0.failureCategory == .providerError || $0.lifecycleState == .failed }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            .first
        guard let latestFailedRun else {
            return "none"
        }
        return [
            latestFailedRun.failureCategory?.rawValue ?? latestFailedRun.lifecycleState.rawValue,
            latestFailedRun.plan.risk?.nilIfAppBlank ?? latestFailedRun.plan.summary.nilIfAppBlank
        ]
        .compactMap { $0 }
        .joined(separator: ": ")
    }

    var agentRetrievalStatusLabel: String {
        switch agentRetrievalIndexStatus.status.uiStatus {
        case .ready:
            return localized("Ready / 已就绪", "Ready")
        case .fallback:
            return localized("Fallback deterministic retrieval / 确定性检索 fallback", "Fallback deterministic retrieval")
        case .error:
            if agentRetrievalIndexStatus.errorMessage?.localizedCaseInsensitiveContains("not indexable") == true {
                return localized("Error not indexable / 不可索引", "Error not indexable")
            }
            return localized("Error / 错误", "Error")
        case .disabled:
            return localized("Disabled FTS-only / 已禁用，仅 FTS", "Disabled FTS-only")
        case .indexing:
            return localized("Indexing / 正在索引", "Indexing")
        case .stale, .migrationRequired:
            return localized("Stale / 需要重建", "Stale")
        }
    }

    var agentRetrievalZeroChunkHint: String? {
        guard agentRetrievalIndexStatus.status.uiStatus != .indexing,
              agentRetrievalIndexStatus.chunkCount == 0 else {
            return nil
        }
        if agentRetrievalIndexStatus.status.uiStatus == .disabled {
            return localized("检索索引已禁用；当前只使用 FTS 文本检索。", "Retrieval indexing is disabled; workflows are using FTS-only text retrieval.")
        }
        if agentRetrievalIndexStatus.errorMessage?.localizedCaseInsensitiveContains("not indexable") == true {
            return localized("chunks=0：选中的 source 不可索引。请确认路径是 paper.md、annotations.md、wiki 或 materials，legacy raw/papers 可直接重建或先迁移。", "chunks=0: the selected source is not indexable. Confirm the path is paper.md, annotations.md, wiki, or materials; legacy raw/papers can be rebuilt directly or migrated first.")
        }
        if let selectedSourceStatus = selectedAgentRetrievalSourceFileStatus() {
            if !selectedSourceStatus.exists {
                return localized("chunks=0：选中的 source 文件不存在，请重新选择论文或重新生成 paper.md。", "chunks=0: the selected source file does not exist; select the paper again or regenerate paper.md.")
            }
            if selectedSourceStatus.isDirectory {
                return localized("chunks=0：选中的 source 是文件夹，不是可索引的 Markdown 文件。", "chunks=0: the selected source is a folder, not an indexable Markdown file.")
            }
            if selectedSourceStatus.byteCount == 0 {
                return localized("chunks=0：选中的 paper.md 存在但为空，请重新转换或修复内容后再 Rebuild Source。", "chunks=0: the selected paper.md exists but is empty; reconvert or fix it before running Rebuild Source.")
            }
            if let lineCount = selectedSourceStatus.lineCount {
                return localized("chunks=0：选中的 paper.md 已存在且非空（\(selectedSourceStatus.byteCount) bytes，\(lineCount) lines），请点击 Rebuild Source 生成本地 fallback chunks。", "chunks=0: the selected paper.md exists and is non-empty (\(selectedSourceStatus.byteCount) bytes, \(lineCount) lines); run Rebuild Source to generate local fallback chunks.")
            }
        }
        return localized("chunks=0：请确认 paper.md 存在且非空，然后运行 Rebuild Source；若是 PDFKit fallback，请用 Check paper.md 查看可读性限制。", "chunks=0: confirm paper.md exists and is not empty, then run Rebuild Source; if it is a PDFKit fallback, use Check paper.md to review readability limits.")
    }

    var paperMarkdownQualitySummary: String {
        guard let paperMarkdownQualityReport else {
            return localized("尚未检查", "Not checked")
        }
        return paperMarkdownQualityReport.summary(usesEnglishInterface: usesEnglishInterface)
    }

    var paperMarkdownQualityIssueLines: [String] {
        paperMarkdownQualityReport?.issueLines(usesEnglishInterface: usesEnglishInterface) ?? []
    }

    var agentSidecarHealthIsAvailable: Bool {
        agentSidecarHealth.status == "ready"
    }

    var agentMCPServerStatuses: [AgentMCPServerStatus] {
        agentProductMCPServerStatuses + agentWorkspaceProfileMCPServerStatuses + agentLocalMCPServerStatuses
    }

    func agentPermissionDockItems(for run: AgentRun) -> [AgentPermissionDockItem] {
        var filteredRun = run
        if let allowedToolNames = run.enabledToolNames.map({ Set($0) }) ?? effectiveAgentAllowedToolNames {
            filteredRun.plan.toolCalls = filteredRun.plan.toolCalls.filter { allowedToolNames.contains($0.toolName) }
        }

        var items = AgentPermissionDockItem.items(
            for: filteredRun,
            toolDefinitions: agentToolDefinitions,
            state: AgentPermissionDockState(
                approvedCallIDs: agentToolApprovals,
                deniedCallIDs: agentToolDenials,
                sessionScopedApprovalDraftCallIDs: agentToolSessionApprovalDrafts,
                correctionFeedbackByCallID: agentToolCorrectionFeedback
            )
        )
        for index in items.indices {
            items[index].moduleScopeDescription = WorkspaceModuleRegistry.moduleScopeDescription(
                for: items[index].targetPaths,
                in: effectiveModuleConfiguration(for: run.projectID ?? run.currentProjectID ?? agentConversationProjectID)
            )
        }
        return items.filter { item in
            switch item.approvalState {
            case .waitingForApproval, .allowedOnce, .denied, .deniedByPolicy, .sessionApprovalDraft:
                return item.sideEffectsRequirePermission || item.decision.action != .allow
            case .autoAllowed, .completed, .failed:
                return false
            }
        }
    }

    var selectedPaperPDFURL: URL? {
        guard let currentWorkspace, let selectedPaperDraft else {
            return nil
        }

        return selectedPaperDraft.pdfURL(in: currentWorkspace)
    }

    var selectedPaperHasUnsavedChanges: Bool {
        guard let selectedPaperDraft,
              let originalPaper = papers.first(where: { $0.id == selectedPaperDraft.id }) else {
            return false
        }

        return selectedPaperDraft != originalPaper
    }

    var deletePendingPaperTitle: String {
        paperPendingDeletion?.displayTitle ?? "the selected paper"
    }

    var deletePendingPaperRelativePath: String {
        paperPendingDeletion?.paperDirectoryRelativePath ?? "the selected paper directory"
    }

    var selectedPaperHasWikiPage: Bool {
        guard let currentWorkspace, let selectedPaperDraft else {
            return false
        }

        return paperHasWikiPage(selectedPaperDraft, in: currentWorkspace)
    }

    var selectedPaperWikiButtonTitle: String {
        selectedPaperHasWikiPage ? "Open Wiki Page" : "Generate Wiki Page"
    }

    var canSaveSelectedMarkdown: Bool {
        currentWorkspace != nil && selectedMarkdownDraft != nil
    }

    var selectedMarkdownSaveStateLabel: String {
        switch selectedMarkdownSaveState {
        case .clean:
            return "Saved"
        case .dirty:
            return "Unsaved"
        case .saving:
            return "Saving"
        case .failed:
            return "Error"
        }
    }

    var selectedMarkdownHasUnsavedChanges: Bool {
        guard let selectedMarkdownDraft,
              let savedDocument = markdownDocuments.first(where: { $0.id == selectedMarkdownDraft.id }) else {
            return false
        }

        return selectedMarkdownDraft.rawContents != savedDocument.rawContents
    }

    var selectedMarkdownBacklinks: [MarkdownDocumentReference] {
        guard let selectedMarkdownDraft else {
            return []
        }

        return backlinkIndex.backlinks(for: selectedMarkdownDraft)
    }

    func tagDefinition(named name: String) -> TagDefinition? {
        availableTagDefinitions.first(where: { $0.name == name })
    }

    static func inferredTagDefinition(named name: String) -> TagDefinition {
        let palette = [
            ("#A7D8F0", "#17465F"),
            ("#BEE7C8", "#1F5130"),
            ("#F7C8D0", "#6B2637"),
            ("#F9D99A", "#62440E"),
            ("#CDBFF5", "#3D2F73"),
            ("#BFE7E2", "#1E5550"),
            ("#F4C7A1", "#6A3A14"),
            ("#D6E3A3", "#48551A")
        ]
        let index = name.unicodeScalars.reduce(0) { partialResult, scalar in
            (partialResult + Int(scalar.value)) % palette.count
        }
        let colors = palette[index]
        return TagDefinition(name: name, colorHex: colors.0, textColorHex: colors.1)
    }

}
