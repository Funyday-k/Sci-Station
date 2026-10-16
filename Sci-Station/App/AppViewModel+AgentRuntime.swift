import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppViewModel {
    func refreshAgentState(in workspace: ResearchWorkspace, restoreDraft: Bool = true) async {
        do {
            let root = currentResearchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
            try await refreshAgentWorkspaceProfile(in: root)
            agentWorkspaceSnapshot = try await agentService.snapshot(
                in: workspace,
                root: root,
                projects: researchProjects,
                currentProjectID: agentConversationProjectID,
                selectedPaperID: selectedPaperID,
                includedPaperIDs: agentKnowledgePaperIDsForContext
            )
            agentToolDefinitions = await agentService.toolDefinitions(
                in: root,
                workspaceProfile: agentWorkspaceProfile
            )
            agentMCPRuntimeStatuses = await agentService.mcpRuntimeStatuses(
                in: root,
                workspaceProfile: agentWorkspaceProfile
            )
            agentRunHistory = try await agentService.recentRuns(in: root, limit: 1000)
            allAgentThreads = try await agentService.allThreads(in: root)
            applyAgentThreadFilterForCurrentScope()
            if restoreDraft {
                restorePersistedAgentDraft(projectID: agentConversationProjectID, threadID: activeAgentThreadID)
            }
            restorePinnedAgentThreadsForCurrentProject()
            restoreAgentToolStateForCurrentScope()
            agentSessionEvents = try await agentService.sessionEvents(in: root, limit: nil)
            try await refreshAgentRuntimeSummaries(in: root)
            rebuildAgentHookActivitySummary()
            agentSidecarHealth = workspacePreferences.isSidecarDisabledForWorkspace
                ? SidecarHealth(status: "disabled", fallbackReason: "Sidecar disabled for this workspace.")
                : await sidecarCoordinator.refreshHealth()
        } catch {
            agentErrorMessage = error.localizedDescription
        }
    }

    func refreshAgentRuntimeSummaries(in root: ResearchRoot) async throws {
        let runtimeLoader = AgentRuntimeConfigurationLoader()
        agentPresetDetails = try runtimeLoader.loadProductPreset(in: root)
        agentProductMCPServerStatuses = agentPresetDetails?.mcpServers ?? []
        agentLocalMCPServerStatuses = try runtimeLoader.loadLocalMCPServerStatuses(in: root)
    }

    func startAgentLiveEventRefresh(in workspace: ResearchWorkspace, liveRunID: String? = nil) {
        agentLiveEventRefreshTask?.cancel()
        agentLiveRunID = liveRunID
        let root = currentResearchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
        let baselineEventIDs = Set(agentSessionEvents.map(\.id))
        agentLiveEventRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                do {
                    let events = try await self.agentService.sessionEvents(in: root, limit: nil)
                    await MainActor.run {
                        self.mergeAgentLiveSessionEvents(events, baselineEventIDs: baselineEventIDs)
                    }
                } catch {
                    // Best-effort UI refresh; the final run refresh remains authoritative.
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    func stopAgentLiveEventRefresh(clearRunID: Bool) {
        agentLiveEventRefreshTask?.cancel()
        agentLiveEventRefreshTask = nil
        if clearRunID {
            agentLiveRunID = nil
        }
    }

    func makeAgentSessionEventHandler() -> (@Sendable (AgentSessionEvent) async -> Void) {
        { [weak self] event in
            guard let self else {
                return
            }
            await MainActor.run {
                self.appendAgentLiveSessionEvent(event)
            }
        }
    }

    func appendAgentLiveSessionEvent(_ event: AgentSessionEvent) {
        mergeAgentLiveSessionEvents([event], baselineEventIDs: [])
        agentLiveRunID = event.sessionID
    }

    func mergeAgentLiveSessionEvents(_ events: [AgentSessionEvent], baselineEventIDs: Set<String>) {
        guard !events.isEmpty else {
            return
        }
        var eventsByID: [String: AgentSessionEvent] = [:]
        for event in agentSessionEvents {
            eventsByID[event.id] = event
        }
        for event in events {
            eventsByID[event.id] = event
        }
        let sortedEvents = eventsByID.values.sorted(by: agentSessionEventSort)

        if agentLiveRunID == nil,
           let liveEvent = events.sorted(by: { $0.createdAt < $1.createdAt }).first(where: { event in
               !baselineEventIDs.contains(event.id) && event.kind != .hookResult
           }) {
            agentLiveRunID = liveEvent.sessionID
        }
        guard sortedEvents != agentSessionEvents else {
            return
        }
        agentSessionEvents = sortedEvents
        rebuildAgentHookActivitySummary()
    }

    nonisolated func agentSessionEventSort(_ first: AgentSessionEvent, _ second: AgentSessionEvent) -> Bool {
        if first.createdAt != second.createdAt {
            return first.createdAt < second.createdAt
        }
        if first.sessionID != second.sessionID {
            return first.sessionID.localizedStandardCompare(second.sessionID) == .orderedAscending
        }
        let firstPriority = agentSessionEventSortPriority(first.kind)
        let secondPriority = agentSessionEventSortPriority(second.kind)
        if firstPriority != secondPriority {
            return firstPriority < secondPriority
        }
        return first.id.localizedStandardCompare(second.id) == .orderedAscending
    }

    nonisolated func agentSessionEventSortPriority(_ kind: AgentSessionEventKind) -> Int {
        switch kind {
        case .userMessage:
            return 0
        case .reasoningSummary:
            return 10
        case .assistantMessage:
            return 20
        case .toolCallStarted:
            return 30
        case .toolCallCompleted, .toolCallFailed:
            return 40
        case .artifactDraft, .permissionRequested:
            return 50
        case .permissionResolved:
            return 60
        case .runCancelled:
            return 70
        case .hookResult, .compactionSummary:
            return 90
        }
    }

    var agentRuntimeHookDefinitions: [AgentHookDefinition] {
        var hooks = agentPresetDetails?.hooks ?? []
        for defaultHook in AgentSafetyPreset.defaultHooks() where !hooks.contains(where: { $0.id == defaultHook.id }) {
            hooks.append(defaultHook)
        }
        return hooks.isEmpty ? AgentSafetyPreset.defaultHooks() : hooks
    }

    func rebuildAgentHookActivitySummary() {
        let sessionIDs = agentRelevantSessionIDs
        let visibleEvents = agentSessionEvents.filter { event in
            sessionIDs.isEmpty || sessionIDs.contains(event.sessionID)
        }
        agentHookActivitySummary = AgentHookActivitySummary(
            hooks: agentRuntimeHookDefinitions,
            events: visibleEvents,
            disabledHookIDs: agentDisabledHookIDs
        )
    }

    func attachRunToActiveThread(_ run: AgentRun, in workspace: ResearchWorkspace) async throws {
        let root = currentResearchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
        let now = Date()
        let workspaceID = currentAgentWorkspaceID
        let workspaceName = currentAgentWorkspaceName
        let reusableThread = activeAgentThread.flatMap { thread -> AgentThread? in
            guard thread.workspaceID == nil || thread.belongsToWorkspace(id: workspaceID) else {
                return nil
            }
            return thread
        }
        var thread = reusableThread ?? AgentThread(
            id: "agent-thread-\(UUID().uuidString.lowercased())",
            projectID: run.currentProjectID,
            contextScope: run.contextScope ?? AgentContextScope.inferred(projectID: run.currentProjectID),
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            runtimeSelector: run.runtimeSelector,
            createdFromRoute: run.createdFromRoute ?? "ai_lab",
            title: Self.agentThreadTitle(for: run),
            createdAt: now,
            updatedAt: now
        )
        thread.assignWorkspace(id: workspaceID, name: workspaceName)

        if Self.isDefaultAgentThreadTitle(thread.title) {
            thread.title = Self.agentThreadTitle(for: run)
        }
        thread.appendRunID(run.id, updatedAt: now)

        try await agentService.upsertThread(thread, in: root)
        pendingAgentThreadsByProject[agentProjectDraftKey(run.currentProjectID)] = nil
        pendingAgentThread = nil
        activeAgentThreadID = thread.id
        allAgentThreads = try await agentService.allThreads(in: root)
        applyAgentThreadFilterForCurrentScope()
        persistAgentDraftForCurrentConversation()
    }

    var currentAgentWorkspaceID: String? {
        guard let currentWorkspace else {
            return nil
        }
        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        return AgentThreadRepository.workspaceID(for: root)
    }

    var currentAgentWorkspaceName: String? {
        currentResearchRoot?.displayName ?? currentWorkspace?.displayName
    }

    func applyAgentThreadFilterForCurrentScope() {
        let workspaceID = currentAgentWorkspaceID
        agentThreads = allAgentThreads
            .filter { !$0.isArchived }
            .filter { thread in
                !isAgentThreadWorkspaceFilterEnabled || thread.belongsToWorkspace(id: workspaceID)
            }
            .sorted { first, second in
                if first.updatedAt == second.updatedAt {
                    return first.id < second.id
                }
                return first.updatedAt > second.updatedAt
            }

        if let pendingAgentThread,
           isAgentThreadWorkspaceFilterEnabled,
           !pendingAgentThread.belongsToWorkspace(id: workspaceID) {
            self.pendingAgentThread = nil
        }

        if let activeAgentThreadID,
           !agentThreads.contains(where: { $0.id == activeAgentThreadID }),
           pendingAgentThread?.id != activeAgentThreadID {
            self.activeAgentThreadID = preferredAgentThreadID(projectID: agentConversationProjectID)
        } else if activeAgentThreadID == nil {
            activeAgentThreadID = preferredAgentThreadID(projectID: agentConversationProjectID)
        }
    }

    func preferredAgentThreadID(projectID: ResearchProject.ID?) -> AgentThread.ID? {
        let workspaceID = currentAgentWorkspaceID
        return agentThreads.first { $0.belongsToWorkspace(id: workspaceID) && $0.projectID == projectID }?.id
            ?? agentThreads.first { $0.belongsToWorkspace(id: workspaceID) }?.id
            ?? agentThreads.first { $0.projectID == projectID }?.id
            ?? agentThreads.first?.id
    }

    var agentDraftProjectIDForCurrentConversation: ResearchProject.ID? {
        pendingAgentThread?.projectID ?? activeAgentThread?.projectID ?? agentConversationProjectID
    }

    func saveAgentDraftForCurrentConversation() {
        agentGoalDrafts[agentDraftKey(projectID: agentDraftProjectIDForCurrentConversation, threadID: activeAgentThreadID)] = agentGoal
    }

    func appendAgentStreamingResponseDelta(_ delta: String) {
        guard !delta.isEmpty else {
            return
        }
        agentStreamingRawResponseText += delta
        scheduleAgentStreamingResponseRender()
    }

    func resetAgentStreamingPreview() {
        agentStreamingRenderGeneration += 1
        agentStreamingRenderTask?.cancel()
        agentStreamingRenderTask = nil
        agentStreamingRawResponseText = ""
        enqueueAgentStreamingResponseText(nil)
    }

    func scheduleAgentStreamingResponseRender() {
        guard agentStreamingRenderTask == nil else {
            return
        }

        let generation = agentStreamingRenderGeneration
        agentStreamingRenderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.agentStreamingRenderGeneration == generation else {
                        return
                    }
                    self.agentStreamingRenderTask = nil
                    self.publishAgentStreamingResponseNow(invalidatingPendingRender: false)
                }
            }
        }
    }

    func publishAgentStreamingResponseNow(invalidatingPendingRender: Bool = true) {
        if invalidatingPendingRender {
            agentStreamingRenderGeneration += 1
        }
        agentStreamingRenderTask?.cancel()
        agentStreamingRenderTask = nil
        let visibleText = AgentVisibleResponseExtractor.visibleText(from: agentStreamingRawResponseText)
        enqueueAgentStreamingResponseText(visibleText)
    }

    func enqueueAgentStreamingResponseText(_ text: String?) {
        let normalizedText = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfAppEmpty
        agentStreamingPendingResponseText = normalizedText

        guard !agentStreamingResponseCommitScheduled else {
            return
        }

        agentStreamingResponseCommitScheduled = true
        DispatchQueue.main.async { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.agentStreamingResponseCommitScheduled = false
                let nextText = self.agentStreamingPendingResponseText
                self.agentStreamingPendingResponseText = nil
                guard self.agentStreamingResponseText != nextText else {
                    return
                }
                self.agentStreamStore.streamingResponseText = nextText
            }
        }
    }

    func markdownWritebackDraft(
        for call: AgentToolCall,
        in run: AgentRun,
        workspace: ResearchWorkspace
    ) -> AgentMarkdownWritebackDraft? {
        guard call.toolName == "write_markdown_plan" || call.toolName == "write_wiki_markdown" else {
            return nil
        }

        let title = stringArgument("title", in: call.argumentsJSON)?.nilIfAppEmpty ?? run.plan.title ?? "Markdown draft"
        let body = stringArgument("body", in: call.argumentsJSON)?.nilIfAppEmpty
            ?? run.plan.finalResponseDraft?.nilIfAppEmpty
            ?? run.plan.summary
        let targetPath = stringArgument("relative_path", in: call.argumentsJSON)?.nilIfAppEmpty
            ?? "wiki/plans/\(slug(from: title)).md"
        let normalizedTargetPath = targetPath.replacingOccurrences(of: "\\", with: "/")
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let bodyContents = body.hasPrefix("# ") ? body : "# \(title)\n\n\(body)"
        let contents = """
        ---
        title: "\(escapedYAMLScalar(title))"
        draft_for: "\(escapedYAMLScalar(normalizedTargetPath))"
        source_run_id: "\(run.id)"
        source_tool_call_id: "\(call.id)"
        source_tool_name: "\(call.toolName)"
        created_at: "\(createdAt)"
        status: draft_only
        ---

        > Draft-only save from AI Lab. The original target `\(normalizedTargetPath)` has not been written.

        \(bodyContents.trimmingCharacters(in: .whitespacesAndNewlines))
        """
        return AgentMarkdownWritebackDraft(
            targetPath: normalizedTargetPath,
            draftPath: uniqueDraftPath(for: normalizedTargetPath, title: title, workspace: workspace),
            contents: contents + "\n"
        )
    }

    func uniqueDraftPath(for targetPath: String, title: String, workspace: ResearchWorkspace) -> String {
        let targetBase = targetPath.split(separator: "/").last.map(String.init)?
            .replacingOccurrences(of: ".md", with: "")
            .nilIfAppEmpty
        let base = slug(from: targetBase ?? title)
        let candidate = "wiki/drafts/\(base).draft.md"
        guard FileManager.default.fileExists(atPath: workspace.fileURL(for: candidate).path) else {
            return candidate
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        return "wiki/drafts/\(base)-\(timestamp).draft.md"
    }

    func escapedYAMLScalar(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func stringArgument(_ key: String, in rawJSON: String) -> String? {
        guard let data = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object[key] as? String
    }

    func slug(from title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let lowercased = title.lowercased()
        var output = ""
        var previousWasDash = false
        for scalar in lowercased.unicodeScalars {
            if allowed.contains(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                output.append("-")
                previousWasDash = true
            }
        }
        let slug = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "markdown-draft" : slug
    }

    func limitedText(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }
        return String(text.prefix(maxCharacters)) + "..."
    }

    func makeAgentStreamingDeltaHandler() -> (@Sendable (String) async -> Void) {
        { [weak self] delta in
            await self?.appendAgentStreamingResponseDelta(delta)
        }
    }

    func persistAgentToolStateForCurrentScope() {
        let scopeKey = agentToolPreferenceScopeKey(projectID: agentConversationProjectID, threadID: activeAgentThreadID)
        let disabledToolNames = agentDisabledToolNames.sorted()
        updateWorkspacePreferences { preferences in
            if disabledToolNames.isEmpty {
                preferences.agentDisabledToolNamesByScope[scopeKey] = nil
            } else {
                preferences.agentDisabledToolNamesByScope[scopeKey] = disabledToolNames
            }
        }
    }

    func restoreAgentToolStateForCurrentScope() {
        let scopeKey = agentToolPreferenceScopeKey(projectID: agentConversationProjectID, threadID: activeAgentThreadID)
        agentDisabledToolNames = Set(workspacePreferences.agentDisabledToolNamesByScope[scopeKey] ?? [])
    }

    func persistPinnedAgentThreadsForCurrentProject() {
        let projectKey = agentProjectPreferenceKey(agentConversationProjectID)
        let pinnedIDs = pinnedAgentThreadIDs.sorted()
        updateWorkspacePreferences { preferences in
            if pinnedIDs.isEmpty {
                preferences.pinnedAgentThreadIDsByProject[projectKey] = nil
            } else {
                preferences.pinnedAgentThreadIDsByProject[projectKey] = pinnedIDs
            }
        }
    }

    func restorePinnedAgentThreadsForCurrentProject() {
        let projectKey = agentProjectPreferenceKey(agentConversationProjectID)
        let visibleThreadIDs = Set(agentThreads.map(\.id))
        pinnedAgentThreadIDs = Set(workspacePreferences.pinnedAgentThreadIDsByProject[projectKey] ?? [])
            .intersection(visibleThreadIDs)
    }

    func agentToolPreferenceScopeKey(projectID: ResearchProject.ID?, threadID: AgentThread.ID?) -> String {
        "project:\(agentProjectPreferenceKey(projectID))|thread:\(threadID ?? "__project__")"
    }

    func agentProjectPreferenceKey(_ projectID: ResearchProject.ID?) -> String {
        projectID ?? "__global__"
    }

    func agentDraftKey(projectID: ResearchProject.ID?, threadID: AgentThread.ID?) -> String {
        AgentPromptDraft.key(projectID: projectID, threadID: threadID)
    }

    func persistAgentDraftForCurrentConversation() {
        persistAgentDraft(projectID: agentDraftProjectIDForCurrentConversation, threadID: activeAgentThreadID, text: agentGoal)
    }

    func persistAgentDraft(projectID: ResearchProject.ID?, threadID: AgentThread.ID?, text: String) {
        agentGoalDrafts[agentDraftKey(projectID: projectID, threadID: threadID)] = text
        guard let currentWorkspace else {
            return
        }

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            try? await agentService.saveDraft(text, projectID: projectID, threadID: threadID, in: root)
        }
    }

    func scheduleAgentDraftPersistence() {
        let projectID = agentDraftProjectIDForCurrentConversation
        let threadID = activeAgentThreadID
        let text = agentGoal

        agentDraftSaveTask?.cancel()
        agentDraftSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.persistAgentDraft(projectID: projectID, threadID: threadID, text: text)
            }
        }
    }

    func restorePersistedAgentDraft(projectID: ResearchProject.ID?, threadID: AgentThread.ID?) {
        if let threadID,
           allAgentThreads.contains(where: { $0.id == threadID && $0.isArchived }) {
            return
        }
        let key = agentDraftKey(projectID: projectID, threadID: threadID)
        if let draft = agentGoalDrafts[key] {
            agentGoal = draft
            return
        }
        guard let currentWorkspace else {
            return
        }

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        Task {
            do {
                guard let draft = try await agentService.draft(projectID: projectID, threadID: threadID, in: root) else {
                    return
                }
                guard agentConversationProjectID == projectID, activeAgentThreadID == threadID else {
                    return
                }
                agentGoalDrafts[key] = draft
                agentGoal = draft
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func agentConversationMessagesForPrompt(latestGoal: String? = nil, limit: Int = 6) -> [LLMChatMessage] {
        var messages = agentConversationRuns
            .suffix(limit)
            .flatMap { run -> [LLMChatMessage] in
                if shouldSkipRunInAgentConversationHistory(run) {
                    return []
                }
                let assistantText = [
                    run.plan.finalResponseDraft?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty,
                    run.plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty
                ]
                .compactMap { $0 }
                .first ?? "Plan generated."

                return [
                    LLMChatMessage(role: .user, content: run.goal),
                    LLMChatMessage(role: .assistant, content: limitedText(assistantText, maxCharacters: 2_000))
                ]
            }
        if let latestGoal,
           isContinuationPrompt(latestGoal),
           let evidenceSummary = agentContinuationEvidenceSummary() {
            messages.append(LLMChatMessage(role: .user, content: evidenceSummary))
        }
        return messages
    }

    func shouldSkipRunInAgentConversationHistory(_ run: AgentRun) -> Bool {
        if run.failureCategory == .cancelledByUser {
            return true
        }
        let text = [
            run.plan.finalResponseDraft?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty,
            run.plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        let failurePrefixes = [
            "模型没有返回最终回复",
            "The model did not return a final response",
            "Sidecar run completed without a visible response"
        ]
        return failurePrefixes.contains { text.hasPrefix($0) }
    }

    func isContinuationPrompt(_ goal: String) -> Bool {
        let normalized = goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return false
        }
        let compact = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return [
            "继续",
            "接着",
            "继续说",
            "继续写",
            "go on",
            "continue",
            "keep going"
        ].contains { compact == $0 || compact.hasPrefix($0 + " ") }
    }

    func agentContinuationEvidenceSummary() -> String? {
        guard let run = agentConversationRuns.reversed().first(where: { !$0.toolResults.isEmpty }) else {
            return nil
        }
        let resultLines = run.toolResults.suffix(8).enumerated().map { index, result in
            continuationEvidenceLine(index: index + 1, result: result)
        }
        .joined(separator: "\n")
        guard !resultLines.isEmpty else {
            return nil
        }
        return """
        Continuation context from the previous Sci-Station run.
        The latest user prompt is a continuation request. Reuse this compact evidence summary before deciding to re-read full papers; only call read_paper again if the user asks for new sections or this summary is insufficient.

        previous_run_goal:
        \(run.goal)

        previous_tool_evidence:
        \(resultLines)
        """
    }

    func continuationEvidenceLine(index: Int, result: AgentToolResult) -> String {
        let payload = result.payload?.objectValue
        let paperID = payload?["paper_id"]?.stringValue
            ?? payload?["paper"]?.objectValue?["id"]?.stringValue
        let source = payload?["source"]?.stringValue
            ?? payload?["paper"]?.objectValue?["raw_markdown_path"]?.stringValue
        let heading = payload?["heading"]?.stringValue
        let targetPath = payload?["target_path"]?.stringValue
        let summary = [
            paperID.map { "paper_id=\($0)" },
            source.map { "source=\($0)" },
            heading.map { "heading=\($0)" },
            targetPath.map { "target=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        return "- #\(index) \(result.toolName) \(result.succeeded ? "succeeded" : "failed")\(summary.isEmpty ? "" : " (\(summary))"): \(limitedText(result.message, maxCharacters: 500))"
    }

    func agentProjectDraftKey(_ projectID: ResearchProject.ID?) -> String {
        projectID ?? "global"
    }

    nonisolated static func agentThreadTitle(for run: AgentRun) -> String {
        let planTitle = run.plan.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let planTitle, !isDefaultAgentThreadTitle(planTitle) {
            return planTitle
        }

        let trimmedGoal = run.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedGoal.count > 48 else {
            return trimmedGoal.isEmpty ? "New Chat" : trimmedGoal
        }

        return String(trimmedGoal.prefix(45)) + "..."
    }

    nonisolated static func isDefaultAgentThreadTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty
            || normalized == "new chat"
            || normalized == "新对话"
            || normalized == "全工作区"
            || normalized == "对话回复"
            || normalized == "ai 回复"
            || normalized == "ai reply"
            || normalized == "conversation reply"
    }

}
