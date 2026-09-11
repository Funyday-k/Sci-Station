import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppViewModel {
    func saveLLMSettings(apiKey: String = "") {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                try await llmConfigurationStore.save(llmConfiguration, in: currentWorkspace)
                let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedKey.isEmpty {
                    _ = try await credentialBroker.save(
                        trimmedKey,
                        for: .llmAPIKey,
                        account: currentWorkspace.rootURL.path
                    )
                    hasLLMAPIKey = true
                    hasLoadedSensitiveAIKeys = true
                }
                llmConnectionStatusMessage = "LLM settings saved."
            } catch {
                present(error)
            }
        }
    }

    func updateLLMConfiguration(_ mutate: (inout LLMConfiguration) -> Void) {
        mutate(&llmConfiguration)
    }

    func useDeepSeekDefaults(model: String = "deepseek-v4-flash") {
        updateLLMConfiguration { configuration in
            configuration.provider = .openAICompatible
            configuration.baseURLString = "https://api.deepseek.com"
            configuration.model = model
            configuration.temperature = 0.2
            configuration.maxTokens = 384_000
        }
    }

    func useDeepSeekModel(_ option: DeepSeekModelOption) {
        useDeepSeekDefaults(model: option.id)
    }

    func testLLMConnection(apiKey: String = "") {
        guard let currentWorkspace else {
            llmConnectionStatusMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }

        isTestingLLMConnection = true
        llmConnectionStatusMessage = nil

        Task {
            defer {
                isTestingLLMConnection = false
            }

            do {
                let transientKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedKey = transientKey.isEmpty
                    ? try await resolvedLLMAPIKey(for: currentWorkspace)
                    : transientKey
                guard !resolvedKey.isEmpty else {
                    throw AgentPanelValidationError.missingAPIKey
                }
                let response = try await openAIProvider.complete(
                    prompt: "Reply with OK.",
                    configuration: llmConfiguration,
                    apiKey: resolvedKey
                )
                llmConnectionStatusMessage = response.isEmpty ? "Connection test returned an empty response." : "Connection OK"
            } catch {
                present(error)
            }
        }
    }

    func generateSelectedPaperSummary() {
        guard let currentWorkspace, let selectedPaperDraft else {
            return
        }

        isGeneratingSummary = true

        Task {
            defer {
                isGeneratingSummary = false
            }

            do {
                let summary = try await paperSummaryService.summarize(
                    selectedPaperDraft,
                    in: currentWorkspace,
                    configuration: llmConfiguration,
                    apiKey: try await resolvedLLMAPIKey(for: currentWorkspace),
                    workspaceProfile: agentWorkspaceProfile
                )
                summaryPreviewText = summary
                isShowingSummaryPreview = true
            } catch {
                present(error)
            }
        }
    }

    func refreshAgentContext() {
        guard let currentWorkspace else {
            return
        }

        isRefreshingAgentContext = true
        agentContextRefreshTask?.cancel()
        agentContextRefreshTask = Task {
            defer {
                isRefreshingAgentContext = false
            }
            guard !Task.isCancelled else {
                return
            }
            await refreshAgentState(in: currentWorkspace)
        }
    }

    func setAgentToolApproval(callID: String, isApproved: Bool) {
        if isApproved {
            agentToolApprovals.insert(callID)
            agentToolDenials.remove(callID)
            recordAppDebugEvent("ai.permission.inline_decision", payload: .object([
                "tool_call_id": .string(callID),
                "decision": .string("allow"),
                "risk": .string(agentPermissionRiskDescription(callID: callID))
            ]))
        } else {
            agentToolApprovals.remove(callID)
        }
    }

    func setAgentToolDenied(callID: String, isDenied: Bool) {
        if isDenied {
            agentToolDenials.insert(callID)
            agentToolApprovals.remove(callID)
            agentToolSessionApprovalDrafts.remove(callID)
            recordAppDebugEvent("ai.permission.inline_decision", payload: .object([
                "tool_call_id": .string(callID),
                "decision": .string("deny"),
                "risk": .string(agentPermissionRiskDescription(callID: callID))
            ]))
        } else {
            agentToolDenials.remove(callID)
        }
    }

    func requestAgentToolRewrite(callID: String) {
        let feedback = localized(
            "请根据当前对话重写这个草稿，保留来源依据，并先解释目标路径与主要改动。",
            "Please rewrite this draft from the current conversation, preserve source evidence, and explain the target path and main changes first."
        )
        agentToolCorrectionFeedback[callID] = feedback
        agentToolDenials.insert(callID)
        agentToolApprovals.remove(callID)
        agentToolSessionApprovalDrafts.remove(callID)
        agentStatusMessage = localized("已标记为需要 AI 重写。", "Marked for AI rewrite.")
        recordAppDebugEvent("ai.draft_review.rewrite_requested", payload: .object([
            "tool_call_id": .string(callID),
            "reason_present": .bool(true)
        ]))
    }

    func agentPermissionRiskDescription(callID: String) -> String {
        guard let currentRun = agentCurrentRun,
              let item = agentPermissionDockItems(for: currentRun).first(where: { $0.id == callID }) else {
            return "unknown"
        }
        return item.risk.rawValue
    }

    func setAgentSessionApprovalDraft(callID: String, isEnabled: Bool) {
        if isEnabled {
            agentToolSessionApprovalDrafts.insert(callID)
            agentToolDenials.remove(callID)
        } else {
            agentToolSessionApprovalDrafts.remove(callID)
        }
    }

    func saveAgentToolCallDraft(callID: String) {
        guard let currentWorkspace else {
            agentErrorMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }
        guard let currentRun = agentCurrentRun,
              let call = currentRun.plan.toolCalls.first(where: { $0.id == callID }),
              let draft = markdownWritebackDraft(for: call, in: currentRun, workspace: currentWorkspace) else {
            agentErrorMessage = localized("没有可保存的 Markdown 草稿。", "No Markdown draft is available to save.")
            return
        }

        Task {
            do {
                let document = try await markdownRepository.saveContents(
                    draft.contents,
                    relativePath: draft.draftPath,
                    in: currentWorkspace
                )
                agentToolSessionApprovalDrafts.insert(callID)
                agentToolDenials.remove(callID)
                agentToolApprovals.remove(callID)
                let message = localized(
                    "已保存草稿：\(document.relativePath)。原目标 \(draft.targetPath) 尚未写入。",
                    "Saved draft: \(document.relativePath). Original target \(draft.targetPath) was not written."
                )
                agentStatusMessage = message
                let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
                let event = AgentSessionEvent(
                    sessionID: currentRun.id,
                    kind: .permissionResolved,
                    summary: message,
                    payloadJSON: JSONValue.object([
                        "action": .string("save_draft_only"),
                        "draft_path": .string(document.relativePath),
                        "target_path": .string(draft.targetPath),
                        "tool_call_id": .string(callID),
                        "tool_name": .string(call.toolName)
                    ]).canonicalJSON
                )
                try await agentSessionEventLogger.append(event, in: root)
                agentSessionEvents.append(event)
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: document.relativePath
                )
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func agentCorrectionFeedback(callID: String) -> String {
        agentToolCorrectionFeedback[callID] ?? ""
    }

    func updateAgentCorrectionFeedback(callID: String, text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            agentToolCorrectionFeedback[callID] = nil
        } else {
            agentToolCorrectionFeedback[callID] = text
        }
    }

    func setAgentHook(_ hookID: String, isEnabled: Bool) {
        if isEnabled {
            agentDisabledHookIDs.remove(hookID)
        } else {
            agentDisabledHookIDs.insert(hookID)
        }
        rebuildAgentHookActivitySummary()
    }

    func setAgentTool(_ toolName: String, isEnabled: Bool) {
        guard agentToolDefinitions.contains(where: { $0.name == toolName }) else {
            return
        }

        if isEnabled {
            agentDisabledToolNames.remove(toolName)
        } else {
            agentDisabledToolNames.insert(toolName)
        }
        persistAgentToolStateForCurrentScope()
    }

    func setAllAgentTools(isEnabled: Bool) {
        agentDisabledToolNames = isEnabled ? [] : Set(agentToolDefinitions.map(\.name))
        persistAgentToolStateForCurrentScope()
    }

    func updateMinerUCommand(_ command: String) {
        updateWorkspacePreferences { preferences in
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.minerUCommand = trimmed.isEmpty ? "mineru" : trimmed
        }
    }

    func updateAppLanguagePreference(_ preference: AppLanguagePreference) {
        let previousPreference = workspacePreferences.appLanguage
        Task { @MainActor [weak self] in
            self?.updateWorkspacePreferences { preferences in
                preferences.appLanguage = preference
            }
            self?.recordAppDebugEvent("l10n.language.change", payload: .object([
                "from": .string(previousPreference.rawValue),
                "to": .string(preference.rawValue)
            ]))
        }
    }

    var liquidGlassTintColor: Color {
        Self.color(for: workspacePreferences.liquidGlassTint)
    }

    func liquidGlassTintLabel(for preference: LiquidGlassTintPreference) -> String {
        switch preference {
        case .system:
            return localized("系统强调色", "System Accent")
        case .blue:
            return localized("雾蓝", "Mist Blue")
        case .mint:
            return localized("薄荷", "Mint")
        case .lavender:
            return localized("淡紫", "Lavender")
        case .rose:
            return localized("浅玫瑰", "Soft Rose")
        case .amber:
            return localized("浅琥珀", "Soft Amber")
        case .graphite:
            return localized("石墨", "Graphite")
        }
    }

    func updateLiquidGlassTintPreference(_ preference: LiquidGlassTintPreference) {
        updateWorkspacePreferences { preferences in
            preferences.liquidGlassTint = preference
        }
        recordAppDebugEvent("appearance.liquid_glass_tint.change", payload: .object([
            "tint": .string(preference.rawValue)
        ]))
    }

    static func color(for preference: LiquidGlassTintPreference) -> Color {
        switch preference {
        case .system:
            return .accentColor
        case .blue:
            return Color(red: 0.36, green: 0.55, blue: 0.82)
        case .mint:
            return Color(red: 0.34, green: 0.66, blue: 0.57)
        case .lavender:
            return Color(red: 0.58, green: 0.50, blue: 0.78)
        case .rose:
            return Color(red: 0.78, green: 0.45, blue: 0.55)
        case .amber:
            return Color(red: 0.78, green: 0.58, blue: 0.28)
        case .graphite:
            return Color(red: 0.48, green: 0.51, blue: 0.55)
        }
    }

    func updateAgentChatFontSize(_ fontSize: Double) {
        updateWorkspacePreferences { preferences in
            preferences.agentChatFontSize = fontSize
        }
    }

    func updateAgentLoopBudget(_ mutate: (inout AgentLoopOptions) -> Void) {
        updateWorkspacePreferences { preferences in
            mutate(&preferences.agentLoopBudget)
        }
    }

    func resetAgentLoopBudget() {
        updateWorkspacePreferences { preferences in
            preferences.agentLoopBudget = WorkspacePreferences.defaultAgentLoopBudget
        }
        agentStatusMessage = "AI Lab tool budget reset to defaults."
    }

    func updateAgentRuntimeSelection(_ selection: AgentRuntimeSelection) {
        updateWorkspacePreferences { preferences in
            preferences.agentRuntimeSelection = selection
            if selection == .langGraphSidecar || selection == .autoFallback {
                preferences.isSidecarDisabledForWorkspace = false
            }
        }
        recordAppDebugEvent("agent.runtime_selection_changed", payload: .object([
            "selection": .string(selection.rawValue)
        ]))
        agentStatusMessage = "AI Lab runtime set to \(selection.label)."
    }

    func setAgentDebugLoggingEnabled(_ isEnabled: Bool) {
        updateWorkspacePreferences { preferences in
            preferences.agentDebugLoggingEnabled = isEnabled
        }
        recordAppDebugEvent(AppDebugEventName.debugModeChanged.rawValue, payload: .object([
            "enabled": .bool(isEnabled)
        ]), force: true)
        agentStatusMessage = isEnabled
            ? "Debug mode enabled. App input, output, and AI Lab operations will be logged locally."
            : "Debug mode disabled. Existing local debug logs were kept."
    }

    func restartAgentSidecar() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        Task {
            agentSidecarHealth = await sidecarCoordinator.restart(for: currentResearchRoot)
            agentStatusMessage = agentSidecarHealth.status == "ready"
                ? "Sidecar restarted and health is ready."
                : "Sidecar restart failed or is unavailable."
        }
    }

    func openAgentRunDirectory() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        let runID = agentCurrentRun?.id
        let relativePath = [AgentRunDirectoryStore.runsRelativePath, runID].compactMap { $0 }.joined(separator: "/")
        NSWorkspace.shared.activateFileViewerSelecting([currentResearchRoot.directoryURL(for: relativePath)])
    }

    func openAgentDebugLogDirectory() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        let directory = currentResearchRoot.directoryURL(for: ".sci-station/debug")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        recordAppDebugEvent(AppDebugEventName.debugLogOpened.rawValue)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func exportAgentDebugBundle() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        guard let run = agentCurrentRun else {
            agentErrorMessage = "No completed or active run is selected for debug export."
            return
        }
        Task {
            do {
                let store = AgentRunDirectoryStore()
                _ = try await store.saveReplay(runID: run.id, in: currentResearchRoot)
                let preview = try await store.debugBundlePreview(runID: run.id, in: currentResearchRoot)
                let confirmed = await MainActor.run { self.confirmAgentDebugBundleExport(preview) }
                guard confirmed else {
                    agentStatusMessage = "Debug bundle export cancelled."
                    return
                }
                let bundleURL = try await store.saveDebugBundle(runID: run.id, in: currentResearchRoot)
                NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
                agentStatusMessage = "Debug bundle exported: \(bundleURL.lastPathComponent). Manifest excludes API keys, paths, .env files, and Keychain data."
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    /// User-facing scrubbed diagnostics export. Collects app/OS/config context
    /// plus recent debug events, runs everything through the path-aware redactor
    /// (home dir, absolute paths, API keys, tokens), and writes a plain-text file
    /// the tester can attach to a beta bug report.
    func exportDiagnosticsReport() {
        Task {
            let report = await buildDiagnosticsReport()
            await MainActor.run {
                let panel = NSSavePanel()
                panel.title = self.localized("导出诊断包", "Export Diagnostics")
                panel.prompt = self.localized("导出", "Export")
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = "sci-station-diagnostics.txt"
                panel.allowedContentTypes = [.plainText]
                guard panel.runModal() == .OK, let destinationURL = panel.url else {
                    self.showShellStatus(self.localized("诊断导出已取消。", "Diagnostics export cancelled."))
                    return
                }
                do {
                    try Data(report.utf8).write(to: destinationURL, options: .atomic)
                    NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                    self.showShellStatus(self.localized(
                        "已导出脱敏诊断包（不含绝对路径与密钥）。",
                        "Exported scrubbed diagnostics (no absolute paths or secrets)."
                    ))
                } catch {
                    self.present(error)
                }
            }
        }
    }

    func buildDiagnosticsReport() async -> String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        let prefs = workspacePreferences

        var lines: [String] = []
        lines.append("Sci-Station Diagnostics")
        lines.append("generated_at: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("app_version: \(version) (\(build))")
        lines.append("os: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("language: \(prefs.appLanguage.rawValue)")
        lines.append("agent_runtime: \(prefs.agentRuntimeSelection.rawValue)")
        lines.append("agent_debug_logging: \(prefs.agentDebugLoggingEnabled)")
        lines.append("workspace_open: \(currentWorkspace != nil)")
        lines.append("modules: \(workspaceModuleStatusSummary)")
        lines.append("")
        lines.append("== Recent debug events (scrubbed) ==")
        if let root = currentResearchRoot {
            let logger = AppDebugEventLogger()
            if let events = try? await logger.events(in: root, limit: 100) {
                let encoder = AgentRunDirectoryStore.encoder()
                for event in events {
                    if let data = try? encoder.encode(event), let line = String(data: data, encoding: .utf8) {
                        lines.append(line)
                    }
                }
            } else {
                lines.append("(no debug events available)")
            }
        } else {
            lines.append("(no workspace open)")
        }

        let raw = lines.joined(separator: "\n") + "\n"
        // Defense in depth: scrub the entire report even though events are
        // already redacted at write time.
        return AgentRunDirectoryStore.redactPathLikeTextPublic(raw)
    }

    func confirmAgentDebugBundleExport(_ preview: AgentDebugBundlePreview) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Export Debug Bundle"
        alert.informativeText = [
            "Run ID: \(preview.runID)",
            "Included files:\n\(preview.includedFiles.isEmpty ? "- none" : preview.includedFiles.map { "- \($0)" }.joined(separator: "\n"))",
            "Excluded patterns:\n\(preview.excludedPatterns.map { "- \($0)" }.joined(separator: "\n"))",
            preview.privacyNotice
        ].joined(separator: "\n\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Export")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func refreshAgentRetrievalIndexStatus() {
        guard let currentResearchRoot else {
            agentRetrievalIndexStatus = .disabled()
            return
        }
        Task {
            agentRetrievalIndexStatus = await agentEmbeddingIndexController.status(in: currentResearchRoot)
        }
    }

    func rebuildAgentRetrievalCurrentProject() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        agentRetrievalIndexStatus = AgentEmbeddingIndexStatusSnapshot(status: .indexing, store: agentRetrievalIndexStatus.store)
        Task {
            agentRetrievalIndexStatus = await agentEmbeddingIndexController.rebuildCurrentProject(in: currentResearchRoot, projectID: currentProjectID)
            agentStatusMessage = "Retrieval index rebuild finished: \(agentRetrievalIndexSummary)."
        }
    }

    func rebuildAgentRetrievalSelectedSource() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        guard let relativePath = selectedAgentRetrievalSourcePath() else {
            agentErrorMessage = "No selected paper or wiki source is available for retrieval rebuild."
            return
        }
        agentRetrievalIndexStatus = AgentEmbeddingIndexStatusSnapshot(status: .indexing, store: agentRetrievalIndexStatus.store)
        Task {
            agentRetrievalIndexStatus = await agentEmbeddingIndexController.rebuildSelectedSource(relativePath, in: currentResearchRoot)
            let suffix = agentRetrievalIndexStatus.zeroChunkGuidance.map { " \($0)" } ?? ""
            agentStatusMessage = "Retrieval source rebuild finished for \(relativePath): \(agentRetrievalIndexSummary).\(suffix)"
        }
    }

    func checkSelectedPaperMarkdownQuality() {
        guard let currentWorkspace else {
            agentErrorMessage = localized("没有打开的工作区。", "No workspace is open.")
            return
        }
        guard let paper = selectedPaperDraft else {
            agentErrorMessage = localized("请先选择一篇论文，再检查 paper.md。", "Select a paper before checking paper.md.")
            return
        }

        isCheckingPaperMarkdownQuality = true
        Task {
            defer {
                isCheckingPaperMarkdownQuality = false
            }
            let report = paperMarkdownQualityInspector.inspect(paper, in: currentWorkspace)
            paperMarkdownQualityReport = report
            agentStatusMessage = localized(
                "paper.md 检查完成：\(report.summary(usesEnglishInterface: false))",
                "paper.md check finished: \(report.summary(usesEnglishInterface: true))"
            )
        }
    }

    func openAgentRetrievalIndexDirectory() {
        guard let currentResearchRoot else {
            agentErrorMessage = "No workspace root is open."
            return
        }
        let url = currentResearchRoot.directoryURL(for: AgentEmbeddingIndexController.indexRelativePath)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyAgentRetrievalDiagnostic() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(redactedAgentRetrievalDiagnosticSummary, forType: .string)
        agentStatusMessage = "Redacted retrieval diagnostic copied."
    }

    func openSelectedPaperMarkdown() {
        guard let selectedPaperDraft else {
            agentErrorMessage = localized("请先选择一篇论文。", "Select a paper first.")
            return
        }
        openPaperMarkdown(selectedPaperDraft)
    }

    func openLegacyPaperMigrationReport() {
        guard let currentWorkspace,
              let relativePath = legacyPaperMigrationReport?.reportRelativePath?.nilIfAppBlank else {
            agentErrorMessage = localized("当前没有可打开的迁移报告。", "No migration report is available to open.")
            return
        }
        NSWorkspace.shared.open(currentWorkspace.fileURL(for: relativePath))
    }

    func selectedAgentRetrievalSourcePath() -> String? {
        if let selectedPaperDraft {
            return paperMarkdownPath(for: selectedPaperDraft)
        }
        if let selectedMarkdownDraft {
            return selectedMarkdownDraft.relativePath
        }
        return nil
    }

    func disableSidecarForWorkspace() {
        updateWorkspacePreferences { preferences in
            preferences.isSidecarDisabledForWorkspace = true
            preferences.agentRuntimeSelection = .swiftLoop
        }
        agentStatusMessage = "LangGraph sidecar disabled for this workspace."
    }

    func updateMinerUAPIBaseURL(_ baseURLString: String) {
        updateWorkspacePreferences { preferences in
            let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.minerUAPIBaseURLString = trimmed.isEmpty ? "https://mineru.net" : trimmed
        }
    }

    func updateMinerUAPILanguage(_ language: String) {
        updateWorkspacePreferences { preferences in
            let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
            preferences.minerUAPILanguage = trimmed.isEmpty ? "en" : trimmed
        }
    }

    func setMinerUOverwriteExistingMarkdown(_ shouldOverwrite: Bool) {
        updateWorkspacePreferences { preferences in
            preferences.minerUOverwriteExistingMarkdown = shouldOverwrite
        }
    }

    func saveMinerUMarkdownConversionSettings(token: String = "") {
        guard let currentWorkspace else {
            return
        }

        Task {
            do {
                let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedToken.isEmpty {
                    _ = try await credentialBroker.save(
                        trimmedToken,
                        for: .minerUAPIToken,
                        account: minerUAPITokenAccount(for: currentWorkspace)
                    )
                    hasMinerUAPIToken = true
                }
                hasLoadedSensitiveAIKeys = true
                workspaceSettingsStatusMessage = localized("MinerU API 设置已保存。", "MinerU API settings saved.")
            } catch {
                present(error)
            }
        }
    }

    func agentToolDefinition(for call: AgentToolCall) -> AgentToolDefinition? {
        agentToolDefinitions.first { $0.name == call.toolName }
    }

    func isAgentThreadPinned(_ threadID: AgentThread.ID) -> Bool {
        pinnedAgentThreadIDs.contains(threadID)
    }

    func toggleAgentThreadPin(_ thread: AgentThread) {
        if pinnedAgentThreadIDs.contains(thread.id) {
            pinnedAgentThreadIDs.remove(thread.id)
            agentStatusMessage = "已取消置顶 \(thread.title)。"
        } else {
            pinnedAgentThreadIDs.insert(thread.id)
            agentStatusMessage = "已置顶 \(thread.title)。"
        }
        persistPinnedAgentThreadsForCurrentProject()
    }

    func confirmArchiveAgentThread(_ thread: AgentThread) {
        agentThreadPendingArchive = thread
        isShowingAgentThreadArchiveConfirmation = true
    }

    func archiveConfirmedAgentThread() {
        guard let thread = agentThreadPendingArchive else {
            isShowingAgentThreadArchiveConfirmation = false
            return
        }

        pinnedAgentThreadIDs.remove(thread.id)
        persistPinnedAgentThreadsForCurrentProject()
        agentThreadPendingArchive = nil
        isShowingAgentThreadArchiveConfirmation = false
        archiveAgentThread(thread)
    }

    func cancelAgentGeneration() {
        guard isPlanningAgentRun else {
            return
        }

        let prompt = agentPendingUserPrompt
        let partialResponse = agentStreamingResponseText
        let runContextProjectID = agentConversationProjectID
        let runtimeSelector = workspacePreferences.agentRuntimeSelection.rawValue
        let enabledToolNamesSnapshot = effectiveAgentAllowedToolNames?.sorted() ?? agentEnabledToolNames.sorted()
        let retryOfRunID = agentRetrySourceRunID
        let promptResolution = agentPromptLibraryResolver.resolve(
            surface: agentCurrentRun?.promptTemplateSurface ?? .toolLoop,
            profile: agentWorkspaceProfile,
            basePrompt: prompt ?? ""
        )
        agentPlanningTask?.cancel()
        agentPlanningTask = nil
        agentRetrySourceRunID = nil
        isPlanningAgentRun = false
        agentPendingUserPrompt = nil
        publishAgentStreamingResponseNow()
        agentStatusMessage = "已停止 AI 输出。"
        agentErrorMessage = nil
        recordAppDebugEvent("agent.stop_requested", payload: .object([
            "prompt": .string(prompt ?? ""),
            "partial_assistant_response": .string(partialResponse ?? ""),
            "retry_of_run_id": .string(retryOfRunID ?? "")
        ]))

        if let prompt, let currentWorkspace {
            Task {
                await recordAgentCancelledRun(
                    prompt: prompt,
                    message: "用户已停止本次 AI 输出。",
                    partialAssistantResponse: partialResponse,
                    in: currentWorkspace,
                    currentProjectID: runContextProjectID,
                    runtimeSelector: runtimeSelector,
                    enabledToolNames: enabledToolNamesSnapshot,
                    promptResolution: promptResolution,
                    retryOfRunID: retryOfRunID
                )
            }
        }
    }

    func convertSelectedAgentKnowledgePapersToMarkdown() {
        guard let currentWorkspace else {
            agentErrorMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }

        requestMarkdownConversion(for: selectedAgentKnowledgePapers, in: currentWorkspace, statusSurface: .agent)
    }

    func convertPaperToMarkdown(_ paper: Paper) {
        guard let currentWorkspace else {
            workspaceSettingsStatusMessage = localized("请先打开工作区。", "Open a workspace first.")
            return
        }

        requestMarkdownConversion(for: [paper], in: currentWorkspace, statusSurface: .workspace)
    }

    func convertLibrarySelectionToMarkdown() {
        guard let currentWorkspace else {
            workspaceSettingsStatusMessage = localized("请先打开工作区。", "Open a workspace first.")
            return
        }

        requestMarkdownConversion(for: selectedLibraryPapers, in: currentWorkspace, statusSurface: .workspace)
    }

    func confirmMarkdownOverwriteConversion() {
        guard let request = pendingMarkdownConversionRequest else {
            isShowingMarkdownOverwriteConfirmation = false
            return
        }

        pendingMarkdownConversionRequest = nil
        isShowingMarkdownOverwriteConfirmation = false
        startMarkdownConversion(
            for: request.papers,
            in: request.workspace,
            statusSurface: request.statusSurface,
            forceOverwriteExistingMarkdown: true
        )
    }

    func cancelMarkdownOverwriteConversion() {
        pendingMarkdownConversionRequest = nil
        isShowingMarkdownOverwriteConfirmation = false
    }

    func paperMarkdownConversionState(for paper: Paper) -> PaperMarkdownConversionState {
        guard let currentWorkspace else {
            return .notConverted
        }
        if let state = paperMarkdownConversionStates[paper.id] {
            return state
        }
        guard paperPDFExists(paper, in: currentWorkspace) else {
            return .noPDF
        }
        guard paperHasExtractedMarkdown(paper, in: currentWorkspace) else {
            return .notConverted
        }

        let metadata = paperMarkdownConversionMetadata(paper, in: currentWorkspace)
        if metadata?.extractionEngine == "pdfkit_fallback" {
            return .fallback
        }
        return .succeeded
    }

    func paperMarkdownConversionMessage(for paper: Paper) -> String? {
        if let message = paperMarkdownConversionMessages[paper.id] {
            return message
        }
        guard let currentWorkspace,
              let fallbackReason = paperMarkdownConversionMetadata(paper, in: currentWorkspace)?.fallbackReason,
              !fallbackReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return fallbackReason
    }

    func requestMarkdownConversion(
        for requestedPapers: [Paper],
        in workspace: ResearchWorkspace,
        statusSurface: MarkdownConversionStatusSurface
    ) {
        let uniquePapers = uniquePapersByID(requestedPapers)
        let existingMarkdownPapers = uniquePapers.filter { paperHasExtractedMarkdown($0, in: workspace) }
        guard existingMarkdownPapers.isEmpty else {
            pendingMarkdownConversionRequest = PendingMarkdownConversionRequest(
                papers: uniquePapers,
                workspace: workspace,
                statusSurface: statusSurface,
                existingMarkdownCount: existingMarkdownPapers.count
            )
            isShowingMarkdownOverwriteConfirmation = true
            return
        }

        startMarkdownConversion(for: uniquePapers, in: workspace, statusSurface: statusSurface)
    }

    func markdownConversionSummaryMessage(
        convertedCount: Int,
        fallbackCount: Int,
        failedCount: Int,
        skippedNoPDFCount: Int,
        skippedExistingMarkdownCount: Int
    ) -> String {
        var chineseParts = ["已转换 \(convertedCount) 篇论文"]
        var englishParts = ["Converted \(convertedCount) paper(s)"]
        if fallbackCount > 0 {
            chineseParts.append("\(fallbackCount) 篇使用 PDFKit fallback")
            englishParts.append("\(fallbackCount) used PDFKit fallback")
        }
        if failedCount > 0 {
            chineseParts.append("\(failedCount) 篇失败")
            englishParts.append("\(failedCount) failed")
        }
        if skippedNoPDFCount > 0 {
            chineseParts.append("\(skippedNoPDFCount) 篇无 PDF 已跳过")
            englishParts.append("\(skippedNoPDFCount) skipped without PDF")
        }
        if skippedExistingMarkdownCount > 0 {
            chineseParts.append("\(skippedExistingMarkdownCount) 篇已有 Markdown 已跳过")
            englishParts.append("\(skippedExistingMarkdownCount) skipped with existing Markdown")
        }
        return localized(chineseParts.joined(separator: "；") + "。", englishParts.joined(separator: "; ") + ".")
    }

    func startMarkdownConversion(
        for requestedPapers: [Paper],
        in workspace: ResearchWorkspace,
        statusSurface: MarkdownConversionStatusSurface,
        forceOverwriteExistingMarkdown: Bool? = nil
    ) {
        let uniquePapers = uniquePapersByID(requestedPapers)
        let convertiblePapers = uniquePapers.filter { paperPDFExists($0, in: workspace) }
        let skippedNoPDFPapers = uniquePapers.filter { !paperPDFExists($0, in: workspace) }
        for paper in skippedNoPDFPapers {
            paperMarkdownConversionStates[paper.id] = .noPDF
            paperMarkdownConversionMessages[paper.id] = localized("这篇论文没有可转换的 PDF。", "This paper does not have a convertible PDF.")
        }

        guard !convertiblePapers.isEmpty else {
            let message = localized("请选择至少一篇带 PDF 的论文。", "Select at least one paper with a PDF.")
            switch statusSurface {
            case .agent:
                agentErrorMessage = message
            case .workspace:
                workspaceSettingsStatusMessage = message
            }
            return
        }

        for paper in convertiblePapers {
            paperMarkdownConversionStates[paper.id] = .converting
            paperMarkdownConversionMessages[paper.id] = nil
        }

        if statusSurface == .agent {
            isConvertingAgentKnowledgeMarkdown = true
            agentErrorMessage = nil
            agentStatusMessage = nil
        } else {
            workspaceSettingsStatusMessage = localized(
                "正在转换 \(convertiblePapers.count) 篇论文为 Markdown...",
                "Converting \(convertiblePapers.count) paper(s) to Markdown..."
            )
        }

        let preferences = workspacePreferences
        Task {
            defer {
                if statusSurface == .agent {
                    isConvertingAgentKnowledgeMarkdown = false
                }
            }

            do {
                let apiToken = try await resolvedMinerUAPIToken(for: workspace)
                let service = PaperMarkdownConversionService()
                let results = try await service.convert(
                    convertiblePapers,
                    in: workspace,
                    configuration: PaperMarkdownConversionConfiguration(
                        minerUAPIToken: apiToken,
                        minerUAPIBaseURLString: preferences.minerUAPIBaseURLString,
                        minerUAPILanguage: preferences.minerUAPILanguage,
                        minerUCommand: preferences.minerUCommand,
                        overwriteExistingMarkdown: forceOverwriteExistingMarkdown ?? preferences.minerUOverwriteExistingMarkdown
                    )
                )
                let convertedCount = results.filter { $0.didWriteMarkdown && $0.extractionEngine == "mineru_api" }.count
                let fallbackCount = results.filter { $0.didWriteMarkdown && $0.extractionEngine == "pdfkit_fallback" }.count
                let skippedExistingMarkdownCount = results.filter { $0.errorMessage == "paper.md already exists; overwrite is disabled." }.count
                let failedCount = results.filter { result in
                    !result.didWriteMarkdown
                        && result.errorMessage != nil
                        && result.errorMessage != "paper.md already exists; overwrite is disabled."
                }.count
                for result in results {
                    paperMarkdownConversionStates[result.paperID] = paperMarkdownConversionState(for: result)
                    paperMarkdownConversionMessages[result.paperID] = result.fallbackReason ?? result.errorMessage
                }

                let message = markdownConversionSummaryMessage(
                    convertedCount: convertedCount,
                    fallbackCount: fallbackCount,
                    failedCount: failedCount,
                    skippedNoPDFCount: skippedNoPDFPapers.count,
                    skippedExistingMarkdownCount: skippedExistingMarkdownCount
                )
                switch statusSurface {
                case .agent:
                    agentStatusMessage = message
                case .workspace:
                    workspaceSettingsStatusMessage = message
                }
                await refreshAgentState(in: workspace)
                try await loadMarkdownDocuments(in: workspace, selecting: selectedMarkdownID)
            } catch {
                for paper in convertiblePapers {
                    paperMarkdownConversionStates[paper.id] = .failed
                    paperMarkdownConversionMessages[paper.id] = error.localizedDescription
                }
                switch statusSurface {
                case .agent:
                    agentErrorMessage = error.localizedDescription
                case .workspace:
                    workspaceSettingsStatusMessage = error.localizedDescription
                }
            }
        }
    }

    func uniquePapersByID(_ papers: [Paper]) -> [Paper] {
        var seen: Set<Paper.ID> = []
        var result: [Paper] = []
        for paper in papers where !seen.contains(paper.id) {
            seen.insert(paper.id)
            result.append(paper)
        }
        return result
    }

    func resetAgentPermissionDockState() {
        agentToolApprovals = []
        agentToolDenials = []
        agentToolSessionApprovalDrafts = []
        agentToolCorrectionFeedback = [:]
    }

    func recordAgentInlineFailure(
        prompt: String,
        message: String,
        partialAssistantResponse: String?,
        in workspace: ResearchWorkspace,
        currentProjectID: ResearchProject.ID?,
        runtimeSelector: String?,
        enabledToolNames: [String],
        promptResolution: AgentPromptResolution,
        failureCategory: AgentRunFailureCategory = .unknown,
        retryOfRunID: String? = nil
    ) async {
        let root = currentResearchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
        do {
            let failedRun = try await agentService.recordFailedRun(
                goal: prompt,
                message: message,
                partialAssistantResponse: partialAssistantResponse,
                in: root,
                currentProjectID: currentProjectID,
                runtimeSelector: runtimeSelector,
                enabledToolNames: enabledToolNames,
                promptResolution: promptResolution,
                failureCategory: failureCategory,
                retryOfRunID: retryOfRunID
            )
            agentCurrentRun = failedRun
            try await attachRunToActiveThread(failedRun, in: workspace)
            resetAgentPermissionDockState()
            await refreshAgentState(in: workspace)
        } catch {
            agentErrorMessage = "\(message) 保存错误状态失败：\(error.localizedDescription)"
        }
    }

    func recordAgentCancelledRun(
        prompt: String,
        message: String,
        partialAssistantResponse: String?,
        in workspace: ResearchWorkspace,
        currentProjectID: ResearchProject.ID?,
        runtimeSelector: String?,
        enabledToolNames: [String],
        promptResolution: AgentPromptResolution,
        retryOfRunID: String? = nil
    ) async {
        let root = currentResearchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
        do {
            let cancelledRun = try await agentService.recordCancelledRun(
                goal: prompt,
                message: message,
                partialAssistantResponse: partialAssistantResponse,
                in: root,
                currentProjectID: currentProjectID,
                runtimeSelector: runtimeSelector,
                enabledToolNames: enabledToolNames,
                promptResolution: promptResolution,
                retryOfRunID: retryOfRunID
            )
            agentCurrentRun = cancelledRun
            try await attachRunToActiveThread(cancelledRun, in: workspace)
            resetAgentPermissionDockState()
            await refreshAgentState(in: workspace)
        } catch {
            agentErrorMessage = "\(message) 保存停止状态失败：\(error.localizedDescription)"
        }
    }

    func startNewAgentConversation() {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        let now = Date()
        let contextProjectID = agentConversationProjectID
        let thread = AgentThread(
            id: "agent-thread-\(UUID().uuidString.lowercased())",
            projectID: contextProjectID,
            contextScope: agentNextRunContextScope,
            workspaceID: currentAgentWorkspaceID,
            workspaceName: currentAgentWorkspaceName,
            runtimeSelector: workspacePreferences.agentRuntimeSelection.rawValue,
            createdFromRoute: "ai_lab",
            title: agentNextRunContextTitle,
            createdAt: now,
            updatedAt: now
        )
        pendingAgentThread = thread
        pendingAgentThreadsByProject[agentProjectDraftKey(contextProjectID)] = thread
        activeAgentThreadID = thread.id
        agentGoal = ""
        agentCurrentRun = nil
        resetAgentStreamingPreview()
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        restoreAgentToolStateForCurrentScope()
        agentStatusMessage = "已开始新的 \(agentNextRunContextTitle) 对话。"
        agentErrorMessage = nil
        recordAppDebugEvent("agent.thread_started", payload: .object([
            "thread_id": .string(thread.id),
            "project_id": .string(contextProjectID ?? ""),
            "scope": .string(agentNextRunContextScope.rawValue)
        ]), threadID: thread.id)
    }

    func discardPendingAgentThread() {
        guard let pendingAgentThread else {
            return
        }

        let projectID = pendingAgentThread.projectID
        pendingAgentThreadsByProject[agentProjectDraftKey(projectID)] = nil
        agentGoalDrafts[agentDraftKey(projectID: projectID, threadID: pendingAgentThread.id)] = nil
        self.pendingAgentThread = nil
        activeAgentThreadID = preferredAgentThreadID(projectID: projectID)
        agentGoal = agentGoalDrafts[agentDraftKey(projectID: projectID, threadID: activeAgentThreadID)] ?? ""
        agentCurrentRun = nil
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        agentStatusMessage = "Discarded the empty draft chat."
        agentErrorMessage = nil
        recordAppDebugEvent("agent.thread_draft_discarded", payload: .object([
            "thread_id": .string(pendingAgentThread.id),
            "project_id": .string(projectID ?? "")
        ]), threadID: pendingAgentThread.id)

        if let currentWorkspace {
            let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
            Task {
                try? await agentService.removeDraft(projectID: projectID, threadID: pendingAgentThread.id, in: root)
            }
        }
    }

    func selectAgentThread(_ thread: AgentThread) {
        guard !thread.isArchived else {
            agentStatusMessage = "该对话已归档，不能作为当前对话打开。"
            activeAgentThreadID = preferredAgentThreadID(projectID: thread.projectID)
            pendingAgentThread = nil
            recordAppDebugEvent("agent.archived_thread_selection_blocked", payload: .object([
                "thread_id": .string(thread.id),
                "title": .string(thread.title)
            ]), threadID: thread.id)
            return
        }
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        activeAgentThreadID = thread.id
        pendingAgentThread = nil
        agentNextRunContextScope = thread.contextScope ?? AgentContextScope.inferred(projectID: thread.projectID)
        agentNextRunProjectID = thread.projectID
        let runsByID = Dictionary(uniqueKeysWithValues: agentRunHistory.map { ($0.id, $0) })
        agentCurrentRun = thread.runIDs.reversed().compactMap { runsByID[$0] }.first
        agentGoal = agentGoalDrafts[agentDraftKey(projectID: thread.projectID, threadID: thread.id)] ?? ""
        restorePersistedAgentDraft(projectID: thread.projectID, threadID: thread.id)
        resetAgentStreamingPreview()
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        restoreAgentToolStateForCurrentScope()
        let workspaceSuffix = thread.workspaceName.map { "（\($0)）" } ?? ""
        agentStatusMessage = "已打开 \(thread.title)\(workspaceSuffix)。"
        agentErrorMessage = nil
        recordAppDebugEvent("agent.thread_selected", payload: .object([
            "thread_id": .string(thread.id),
            "title": .string(thread.title),
            "project_id": .string(thread.projectID ?? ""),
            "run_ids": jsonStringArray(thread.runIDs)
        ]), threadID: thread.id)
    }

    func openAgentRun(_ run: AgentRun) {
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        agentNextRunContextScope = run.contextScope ?? AgentContextScope.inferred(projectID: run.projectID ?? run.currentProjectID)
        agentNextRunProjectID = run.projectID ?? run.currentProjectID
        activeAgentThreadID = allAgentThreads.first { !$0.isArchived && $0.runIDs.contains(run.id) }?.id
        pendingAgentThread = nil
        agentCurrentRun = run
        agentGoal = run.goal
        resetAgentStreamingPreview()
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        agentStatusMessage = "Opened a previous \(agentConversationTitle) run."
        agentErrorMessage = nil
        recordAppDebugEvent("agent.run_opened", payload: .object([
            "run_id": .string(run.id),
            "goal": .string(run.goal),
            "bound_thread_id": .string(activeAgentThreadID ?? "")
        ]), runID: run.id)
        refreshAgentContext()
    }

    func beginRenameAgentThread(_ thread: AgentThread) {
        agentThreadPendingRename = thread
        agentThreadRenameDraft = thread.title
        isShowingAgentThreadRename = true
    }

    func renamePendingAgentThreadFromDraft() {
        guard let agentThreadPendingRename, let currentWorkspace else {
            isShowingAgentThreadRename = false
            return
        }

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        var thread = agentThreadPendingRename
        thread.rename(to: agentThreadRenameDraft, updatedAt: Date())
        isShowingAgentThreadRename = false
        self.agentThreadPendingRename = nil

        Task {
            do {
                try await agentService.upsertThread(thread, in: root)
                agentStatusMessage = "Renamed thread to \(thread.title)."
                await refreshAgentState(in: currentWorkspace)
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func archiveAgentThread(_ thread: AgentThread) {
        guard let currentWorkspace else {
            return
        }

        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        var archivedThread = thread
        archivedThread.archive(at: Date())

        Task {
            do {
                try await agentService.upsertThread(archivedThread, in: root)
                if activeAgentThreadID == thread.id {
                    activeAgentThreadID = nil
                    pendingAgentThread = nil
                    agentCurrentRun = nil
                    agentGoal = ""
                }
                agentStatusMessage = "Archived \(thread.title)."
                recordAppDebugEvent("agent.thread_archived", payload: .object([
                    "thread_id": .string(thread.id),
                    "title": .string(thread.title),
                    "run_ids": jsonStringArray(thread.runIDs)
                ]), threadID: thread.id)
                await refreshAgentState(in: currentWorkspace)
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func createAgentThread(from run: AgentRun) {
        guard let currentWorkspace else {
            return
        }
        guard run.currentProjectID == agentConversationProjectID else {
            agentErrorMessage = "Only runs from the current project conversation can be organized into a thread."
            return
        }

        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        let now = Date()
        let thread = AgentThread(
            id: "agent-thread-\(UUID().uuidString.lowercased())",
            projectID: run.currentProjectID,
            contextScope: run.contextScope ?? AgentContextScope.inferred(projectID: run.currentProjectID),
            workspaceID: currentAgentWorkspaceID,
            workspaceName: currentAgentWorkspaceName,
            runtimeSelector: run.runtimeSelector,
            createdFromRoute: run.createdFromRoute ?? "ai_lab",
            title: Self.agentThreadTitle(for: run),
            runIDs: [run.id],
            createdAt: now,
            updatedAt: now
        )

        Task {
            do {
                try await agentService.upsertThread(thread, in: root)
                activeAgentThreadID = thread.id
                pendingAgentThread = nil
                agentCurrentRun = run
                agentGoal = agentGoalDrafts[agentDraftKey(projectID: thread.projectID, threadID: thread.id)] ?? ""
                agentStatusMessage = "Created \(thread.title) from history."
                await refreshAgentState(in: currentWorkspace)
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func addAgentRunToCurrentThread(_ run: AgentRun) {
        guard let currentWorkspace, var thread = activeAgentThread else {
            agentErrorMessage = "Open a thread before adding a history run."
            return
        }
        guard thread.workspaceID == nil || thread.belongsToWorkspace(id: currentAgentWorkspaceID) else {
            agentErrorMessage = "This thread belongs to another workspace. Start a new chat in the current workspace before adding runs."
            return
        }
        guard run.currentProjectID == agentConversationProjectID, thread.projectID == run.currentProjectID else {
            agentErrorMessage = "Only runs from the current project conversation can be added to this thread."
            return
        }

        let root = currentResearchRoot ?? ResearchRoot(rootURL: currentWorkspace.rootURL)
        thread.appendRunID(run.id, updatedAt: Date())

        Task {
            do {
                try await agentService.upsertThread(thread, in: root)
                agentStatusMessage = "Added history run to \(thread.title)."
                await refreshAgentState(in: currentWorkspace)
            } catch {
                agentErrorMessage = error.localizedDescription
            }
        }
    }

    func duplicateAgentRunPromptToNewChat(_ run: AgentRun) {
        startNewAgentConversation()
        agentGoal = run.goal
        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        agentStatusMessage = "Copied the previous prompt into a new chat."
    }

    func retryAgentRun(_ run: AgentRun) {
        guard run.isRetryable else {
            agentErrorMessage = "这个 run 当前不是可重试状态。"
            return
        }
        guard !isPlanningAgentRun else {
            agentErrorMessage = "当前 AI 正在运行，请先停止或等待完成。"
            return
        }

        saveAgentDraftForCurrentConversation()
        persistAgentDraftForCurrentConversation()
        agentNextRunContextScope = run.contextScope ?? AgentContextScope.inferred(projectID: run.projectID ?? run.currentProjectID)
        agentNextRunProjectID = run.projectID ?? run.currentProjectID
        if let thread = allAgentThreads.first(where: { $0.runIDs.contains(run.id) && !$0.isArchived }) {
            activeAgentThreadID = thread.id
            pendingAgentThread = nil
        }
        agentGoal = run.goal
        agentRetrySourceRunID = run.id
        resetAgentStreamingPreview()
        resetAgentPermissionDockState()
        agentStatusMessage = "正在重试上一条失败请求。"
        agentErrorMessage = nil
        generateAgentPlan()
    }

    func duplicateAgentThreadPromptToNewChat(_ thread: AgentThread) {
        guard let runID = thread.runIDs.last,
              let run = agentRunHistory.first(where: { $0.id == runID }) else {
            agentErrorMessage = "No prompt found for this chat yet."
            return
        }

        duplicateAgentRunPromptToNewChat(run)
    }

    func resetAgentDraftIfConversationChanged(to projectID: ResearchProject.ID?) {
        guard activeAgentThread == nil, pendingAgentThread == nil else {
            return
        }
        guard agentCurrentRun?.currentProjectID != projectID else {
            return
        }

        agentNextRunContextScope = projectID == nil ? .workspace : .project
        agentNextRunProjectID = projectID
        if let pendingThread = pendingAgentThreadsByProject[agentProjectDraftKey(projectID)] {
            pendingAgentThread = pendingThread
            activeAgentThreadID = pendingThread.id
        } else {
            pendingAgentThread = nil
            activeAgentThreadID = preferredAgentThreadID(projectID: projectID)
        }
        agentGoal = agentGoalDrafts[agentDraftKey(projectID: projectID, threadID: activeAgentThreadID)] ?? ""
        restorePersistedAgentDraft(projectID: projectID, threadID: activeAgentThreadID)
        agentCurrentRun = nil
        resetAgentStreamingPreview()
        resetAgentPermissionDockState()
        rebuildAgentHookActivitySummary()
        restorePinnedAgentThreadsForCurrentProject()
        restoreAgentToolStateForCurrentScope()
        agentStatusMessage = nil
        agentErrorMessage = nil
    }

    func generateAgentPlan() {
        if isPlanningAgentRun {
            cancelAgentGeneration()
            return
        }

        guard let currentWorkspace else {
            agentErrorMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }

        let trimmedGoal = agentGoal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedGoal.isEmpty else {
            agentErrorMessage = AgentPanelValidationError.emptyGoal.localizedDescription
            return
        }

        if let warning = agentToolAvailabilityWarning {
            agentErrorMessage = warning
            recordAppDebugEvent("ai.toolset.unavailable", payload: .object([
                "visible_mode": .string(agentVisibleMode.rawValue),
                "enabled_tool_count": .number(String(agentEnabledToolNames.count)),
                "available_tool_count": .number(String(agentToolDefinitions.count))
            ]))
            return
        }

        let conversationHistory = agentConversationMessagesForPrompt(latestGoal: trimmedGoal)
        let allowedToolNames = effectiveAgentAllowedToolNames
        let interactionMode = agentInteractionMode
        let usesToolLoopRuntime = interactionMode.usesToolLoopRuntime
        let runContextProjectID = agentConversationProjectID
        let runtimeSelection = workspacePreferences.agentRuntimeSelection
        let enabledToolNamesSnapshot = allowedToolNames?.sorted() ?? agentEnabledToolNames.sorted()
        let retryOfRunID = agentRetrySourceRunID
        let promptResolution = agentPromptLibraryResolver.resolve(
            surface: .toolLoop,
            profile: agentWorkspaceProfile,
            basePrompt: trimmedGoal
        )
        agentRetrySourceRunID = nil
        let executionOptions = AgentExecutionOptions(
            mode: .planOnly,
            loopPolicy: usesToolLoopRuntime ? .readOnlyAutoApproveWritesRequireApproval : .manualApprovalOnly,
            runtimeSelection: runtimeSelection,
            isSidecarDisabledForWorkspace: workspacePreferences.isSidecarDisabledForWorkspace,
            disabledHookIDs: agentDisabledHookIDs,
            plannerInstructions: interactionMode.plannerInstructions,
            allowedToolNames: allowedToolNames,
            enabledWorkflowIDs: enabledAgentWorkflowIDs,
            allowsPlainTextResponse: interactionMode.allowsPlainTextResponse,
            loopOptions: workspacePreferences.agentLoopBudget,
            retryOfRunID: retryOfRunID
        )
        let responseDeltaHandler = usesToolLoopRuntime ? makeAgentStreamingDeltaHandler() : nil

        isPlanningAgentRun = true
        agentPendingUserPrompt = trimmedGoal
        recordAppDebugEvent("agent.prompt_submitted", payload: .object([
            "prompt": .string(trimmedGoal),
            "interaction_mode": .string(interactionMode.rawValue),
            "runtime_selection": .string(runtimeSelection.rawValue),
            "project_id": .string(runContextProjectID ?? ""),
            "selected_paper_id": .string(selectedPaperID ?? ""),
            "allowed_tool_names": jsonStringArray(allowedToolNames?.sorted() ?? []),
            "enabled_tool_names": jsonStringArray(enabledToolNamesSnapshot),
            "conversation_history_messages": .number(String(conversationHistory.count)),
            "conversation_history_characters": .number(String(conversationHistory.reduce(0) { $0 + $1.content.count }))
        ]))
        resetAgentStreamingPreview()
        startAgentLiveEventRefresh(in: currentWorkspace)
        agentGoal = ""
        persistAgentDraftForCurrentConversation()
        agentErrorMessage = nil
        agentStatusMessage = nil

        agentPlanningTask?.cancel()
        agentPlanningTask = Task {
            defer {
                stopAgentLiveEventRefresh(clearRunID: true)
                isPlanningAgentRun = false
                agentPendingUserPrompt = nil
                agentPlanningTask = nil
            }

            do {
                try Task.checkCancellation()
                let apiKey = try await resolvedLLMAPIKey(for: currentWorkspace)
                guard !apiKey.isEmpty else {
                    throw AgentPanelValidationError.missingAPIKey
                }
                try Task.checkCancellation()

                let run = try await agentService.run(
                    goal: trimmedGoal,
                    in: currentWorkspace,
                    root: currentResearchRoot,
                    projects: researchProjects,
                    currentProjectID: runContextProjectID,
                    selectedPaperID: selectedPaperID,
                    includedPaperIDs: agentKnowledgePaperIDsForContext,
                    conversationHistory: conversationHistory,
                    configuration: llmConfiguration,
                    apiKey: apiKey,
                    options: AgentExecutionOptions(
                        mode: executionOptions.mode,
                        approvedToolCallIDs: executionOptions.approvedToolCallIDs,
                        loopPolicy: executionOptions.loopPolicy,
                        runtimeSelection: executionOptions.runtimeSelection,
                        isSidecarDisabledForWorkspace: executionOptions.isSidecarDisabledForWorkspace,
                        disabledHookIDs: executionOptions.disabledHookIDs,
                        plannerInstructions: executionOptions.plannerInstructions,
                        allowedToolNames: executionOptions.allowedToolNames,
                        enabledWorkflowIDs: executionOptions.enabledWorkflowIDs,
                        allowsPlainTextResponse: executionOptions.allowsPlainTextResponse,
                        loopOptions: executionOptions.loopOptions,
                        retryOfRunID: executionOptions.retryOfRunID,
                        promptResolution: promptResolution
                    ),
                    workspaceProfile: agentWorkspaceProfile,
                    responseDeltaHandler: responseDeltaHandler,
                    sessionEventHandler: makeAgentSessionEventHandler()
                )
                try Task.checkCancellation()
                agentCurrentRun = run
                resetAgentStreamingPreview()
                try await attachRunToActiveThread(run, in: currentWorkspace)
                resetAgentPermissionDockState()
                let isWaitingForApproval = usesToolLoopRuntime && run.lifecycleState == .waitingForApproval
                agentStatusMessage = isWaitingForApproval
                    ? "等待批准工具调用。输入草稿已保留。"
                    : (usesToolLoopRuntime
                        ? "已根据所选 AI 知识库生成回复。"
                        : "计划已生成。运行前请审查允许写入工作区的工具。")
                recordAgentRunDebugOutput(run, event: "agent.run_completed")
                await refreshAgentState(in: currentWorkspace)
            } catch is CancellationError {
                agentStatusMessage = "已停止 AI 输出。"
                agentErrorMessage = nil
                recordAppDebugEvent("agent.run_cancelled", payload: .object([
                    "prompt": .string(trimmedGoal),
                    "partial_assistant_response": .string(agentStreamingResponseText ?? "")
                ]))
            } catch {
                let message = error.localizedDescription
                let failureCategory: AgentRunFailureCategory = (error is AgentPlanParserError) ? .malformedResponse : .providerError
                agentErrorMessage = message
                recordAppDebugEvent("agent.run_failed", payload: .object([
                    "prompt": .string(trimmedGoal),
                    "error": .string(message),
                    "partial_assistant_response": .string(agentStreamingResponseText ?? "")
                ]))
                await recordAgentInlineFailure(
                    prompt: trimmedGoal,
                    message: message,
                    partialAssistantResponse: agentStreamingResponseText,
                    in: currentWorkspace,
                    currentProjectID: runContextProjectID,
                    runtimeSelector: runtimeSelection.rawValue,
                    enabledToolNames: enabledToolNamesSnapshot,
                    promptResolution: promptResolution,
                    failureCategory: failureCategory,
                    retryOfRunID: retryOfRunID
                )
            }
        }
    }

    func executeApprovedAgentTools() {
        guard let currentWorkspace else {
            agentErrorMessage = AgentPanelValidationError.missingWorkspace.localizedDescription
            return
        }
        guard let currentRun = agentCurrentRun else {
            agentErrorMessage = AgentPanelValidationError.missingPlan.localizedDescription
            return
        }
        guard agentInteractionMode.allowsApprovedToolExecution else {
            agentErrorMessage = "Conversation mode cannot execute tools. Switch to Plan or Assistant mode."
            return
        }

        let goal = agentGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? currentRun.goal : agentGoal
        let runContextProjectID = currentRun.projectID ?? currentRun.currentProjectID ?? agentConversationProjectID
        isExecutingAgentTools = true
        agentErrorMessage = nil
        agentStatusMessage = nil
        recordAppDebugEvent("agent.tools_execution_started", payload: .object([
            "run_id": .string(currentRun.id),
            "goal": .string(goal),
            "approved_tool_call_ids": jsonStringArray(Array(agentToolApprovals).sorted()),
            "denied_tool_call_ids": jsonStringArray(Array(agentToolDenials).sorted())
        ]), runID: currentRun.id)
        startAgentLiveEventRefresh(in: currentWorkspace, liveRunID: currentRun.id)

        Task {
            defer {
                stopAgentLiveEventRefresh(clearRunID: true)
                isExecutingAgentTools = false
            }

            do {
                if agentInteractionMode == .conversation {
                    let dockItems = agentPermissionDockItems(for: currentRun)
                    let approvedCall = currentRun.plan.toolCalls.first { agentToolApprovals.contains($0.id) }
                    let deniedCall = currentRun.plan.toolCalls.first { agentToolDenials.contains($0.id) }
                    guard let selectedCall = approvedCall ?? deniedCall else {
                        agentErrorMessage = "请先允许或拒绝待审批工具。"
                        return
                    }
                    let selectedItem = dockItems.first { $0.id == selectedCall.id }
                    let action: AgentHumanDecisionAction
                    if approvedCall != nil {
                        action = .allowOnce
                    } else if selectedItem?.risk == .writesWorkspace || selectedItem?.risk == .externalSideEffect {
                        action = .denyAndStop
                    } else {
                        action = .denyAndContinue
                    }
                    let resumedRun = try await agentService.resumePendingToolCall(
                        runID: currentRun.id,
                        action: action,
                        feedback: agentToolCorrectionFeedback[selectedCall.id],
                        in: currentWorkspace,
                        root: currentResearchRoot,
                        currentProjectID: runContextProjectID,
                        selectedPaperID: selectedPaperID,
                        includedPaperIDs: agentKnowledgePaperIDsForContext,
                        allowedToolNames: effectiveAgentAllowedToolNames,
                        disabledHookIDs: agentDisabledHookIDs,
                        loopOptions: workspacePreferences.agentLoopBudget,
                        configuration: llmConfiguration,
                        apiKey: try await resolvedLLMAPIKey(for: currentWorkspace),
                        responseDeltaHandler: makeAgentStreamingDeltaHandler()
                    )
                    agentCurrentRun = resumedRun
                    try await attachRunToActiveThread(resumedRun, in: currentWorkspace)
                    resetAgentPermissionDockState()
                    agentStatusMessage = resumedRun.completedAt == nil ? "等待下一步工具审批。" : "已从审批点继续生成回复。"
                    try await loadWorkspaceData(
                        in: currentWorkspace,
                        selectingPaper: selectedPaperID,
                        selectingMarkdown: selectedMarkdownID
                    )
                    recordAgentRunDebugOutput(resumedRun, event: "agent.tools_resume_completed")
                    return
                }

                let executedRun = try await agentService.executeApprovedPlan(
                    goal: goal,
                    plan: currentRun.plan,
                    in: currentWorkspace,
                    root: currentResearchRoot,
                    currentProjectID: runContextProjectID,
                    selectedPaperID: selectedPaperID,
                    includedPaperIDs: agentKnowledgePaperIDsForContext,
                    allowedToolNames: effectiveAgentAllowedToolNames,
                    approvedToolCallIDs: agentToolApprovals,
                    deniedToolCallIDs: agentToolDenials,
                    correctionFeedbackByCallID: agentToolCorrectionFeedback,
                    disabledHookIDs: agentDisabledHookIDs
                )
                agentCurrentRun = executedRun
                try await attachRunToActiveThread(executedRun, in: currentWorkspace)
                agentStatusMessage = "Approved tools finished. Workspace data has been refreshed."
                recordAgentRunDebugOutput(executedRun, event: "agent.tools_execution_completed")
                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperID,
                    selectingMarkdown: selectedMarkdownID
                )
            } catch {
                agentErrorMessage = error.localizedDescription
                recordAppDebugEvent("agent.tools_execution_failed", payload: .object([
                    "run_id": .string(currentRun.id),
                    "error": .string(error.localizedDescription)
                ]), runID: currentRun.id)
            }
        }
    }

    func applySummaryPreview(mode: LLMWritebackMode) {
        guard let currentWorkspace, let selectedPaperDraft, let summaryPreviewText else {
            return
        }

        Task {
            do {
                let targetURL = wikiPageURL(for: selectedPaperDraft, in: currentWorkspace)
                let writebackResult = try await llmWritebackService.write(
                    summaryPreviewText,
                    to: targetURL,
                    mode: mode,
                    paper: selectedPaperDraft,
                    in: currentWorkspace
                )

                if writebackResult.didModifyWiki {
                    var updatedPaper = selectedPaperDraft
                    updatedPaper.status = .summarized
                    _ = try await paperRepository.save(updatedPaper, in: currentWorkspace)
                }

                try await loadWorkspaceData(
                    in: currentWorkspace,
                    selectingPaper: selectedPaperDraft.id,
                    selectingMarkdown: currentWorkspace.relativePath(to: writebackResult.writtenURL)
                )
                self.summaryPreviewText = nil
                isShowingSummaryPreview = false
            } catch {
                present(error)
            }
        }
    }

}
