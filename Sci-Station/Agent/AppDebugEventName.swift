import Foundation

/// Centralised registry of debug event names emitted via `AppDebugEventLogger`.
///
/// All new events should be added here so that:
/// 1. Typos are caught at compile time when call sites use the typed enum.
/// 2. Tests can assert against an allow-list (see
///    `appDebugEventNameRegistryCoversAllEmittedEvents` in
///    `Tools/SciStationCoreTestRunner/main.swift`).
/// 3. Tooling — including the AI Usage Test orchestrator (`Proposal-AT.md`,
///    `AgentRuntime/sci_station_agent/uitest/`) — can enumerate all known
///    events for dashboards, scenario assertions and filters.
///
/// Naming convention: `<domain>.<entity>.<verb>` using `snake_case` for
/// multi-word tokens and `.` as the separator. New events MUST follow this
/// convention so that the orchestrator's lint test stays green.
///
/// See docs/development/comment.md §8.1 and docs/development/Proposal-AT.md §P-AT.1.
public enum AppDebugEventName: String, Codable, CaseIterable, Sendable {
    // MARK: - Route persistence
    case routePersist = "route.persist"
    case routePersistFallback = "route.persist.fallback"
    case routePersistError = "route.persist.error"

    // MARK: - Project space / shell
    case projectSpaceTabChange = "project_space.tab_change"
    case projectSpaceBuilderWarn = "project_space.builder_warn"
    case shellRightRailChange = "shell.right_rail.change"
    case shellAIPanelOpen = "shell.ai_panel.open"
    case shellResponsivePolicyApply = "shell.responsive_policy.apply"
    case toolbarPolicyResolve = "toolbar.policy.resolve"
    case sidebarRender = "sidebar.render"

    // MARK: - Project lifecycle
    case projectArchiveRequested = "project.archive.requested"
    case projectDeleteRequested = "project.delete.requested"

    // MARK: - Wiki / Markdown
    case wikiFileCreate = "wiki.file.create"
    case wikiFileRename = "wiki.file.rename"
    case wikiFileArchive = "wiki.file.archive"
    case markdownEditorSaveState = "markdown.editor.save_state"
    case paperMarkdownOpenDirect = "paper_markdown.open_direct"

    // MARK: - Agent
    case agentPromptSubmitted = "agent.prompt_submitted"
    case agentRunCompleted = "agent.run_completed"
    case agentRunFailed = "agent.run_failed"
    case agentRunCancelled = "agent.run_cancelled"
    case agentRunOpened = "agent.run_opened"
    case agentRuntimeSelectionChanged = "agent.runtime_selection_changed"
    case agentStopRequested = "agent.stop_requested"
    case agentContextChanged = "agent.context_changed"
    case agentThreadStarted = "agent.thread_started"
    case agentThreadSelected = "agent.thread_selected"
    case agentThreadArchived = "agent.thread_archived"
    case agentThreadDraftDiscarded = "agent.thread_draft_discarded"
    case agentArchivedThreadSelectionBlocked = "agent.archived_thread_selection_blocked"
    case agentToolsExecutionStarted = "agent.tools_execution_started"
    case agentToolsExecutionCompleted = "agent.tools_execution_completed"
    case agentToolsExecutionFailed = "agent.tools_execution_failed"
    case agentToolsResumeCompleted = "agent.tools_resume_completed"
    case agentToolGraphQuery = "agent.tool.graph_query"
    case agentToolGraphResultSize = "agent.tool.graph_result_size"
    case agentToolGraphError = "agent.tool.graph_error"
    case agentToolGraphInsightDraft = "agent.tool.graph_insight_draft"
    case agentToolGraphBlockedByModule = "agent.tool.graph_blocked_by_module"
    case agentIntentGraphRouted = "agent.intent.graph_routed"

    // MARK: - AI Lab UX / permissions
    case aiModeChange = "ai.mode.change"
    case aiTimelineProject = "ai.timeline.project"
    case aiToolsetUnavailable = "ai.toolset.unavailable"
    case aiPermissionInlineDecision = "ai.permission.inline_decision"
    case aiDraftReviewRewriteRequested = "ai.draft_review.rewrite_requested"

    // MARK: - Appearance / localization
    case appearanceLiquidGlassTintChange = "appearance.liquid_glass_tint.change"
    case l10nLanguageChange = "l10n.language.change"

    // MARK: - Debug logging
    case debugModeChanged = "debug.mode.changed"
    case debugLogOpened = "debug.log.opened"

    // MARK: - Home / Project Dashboard
    case homeAggregate = "home.aggregate"
    case homeAggregateError = "home.aggregate.error"
    case homeCacheInvalidate = "home.cache.invalidate"
    case homePanelAction = "home.panel.action"
    case homeWidgetGallery = "home.widget.gallery"
    case homeWidgetLayoutEnterEdit = "home.widget.layout_enter_edit"
    case homeWidgetLayoutExitEdit = "home.widget.layout_exit_edit"
    case homeWidgetMove = "home.widget.move"
    case homeWidgetResize = "home.widget.resize"
    case homeWidgetToggle = "home.widget.toggle"
    case homeWidgetResetDefault = "home.widget.reset_default"
    case projectDashboardRender = "project_dashboard.render"
    case projectDashboardStageInferred = "project_dashboard.stage_inferred"

    // MARK: - PDF annotations
    case pdfAnnotationCreate = "pdf.annotation.create"
    case pdfAnnotationUpdate = "pdf.annotation.update"
    case pdfAnnotationDelete = "pdf.annotation.delete"
    case pdfAnnotationDuplicateSkipped = "pdf.annotation.duplicate_skipped"

    case recommendationArxivRefresh = "recommendation.arxiv_refresh"
    case recommendationArchive = "recommendation.archive"
    case recommendationAISearchError = "recommendation.ai_search.error"
    case recommendationError = "recommendation.error"
    case recommendationFeedback = "recommendation.feedback"
    case recommendationPushError = "recommendation.push.error"

    // MARK: - Module Settings
    case moduleSettingsToggle = "module_settings.toggle"
    case moduleSettingsToggleChain = "module_settings.toggle_chain"
    case moduleSettingsPin = "module_settings.pin"

    // MARK: - Graph (P44–P47)
    case graphIndexerRebuildStarted = "graph.indexer.rebuild_started"
    case graphIndexerRebuildCompleted = "graph.indexer.rebuild_completed"
    case graphIndexerRebuildFinished = "graph.indexer.rebuild_finished"
    case graphIndexerIncrementalUpdate = "graph.indexer.incremental_update"
    case graphIndexerIncrementalSkip = "graph.indexer.incremental_skip"
    case graphRepositoryLoaded = "graph.repository.loaded"
    case graphRepositoryWrite = "graph.repository.write"
    case graphRepositoryCompact = "graph.repository.compact"
    case graphRepositoryCompactError = "graph.repository.compact.error"
    case graphRepositoryReplaySkip = "graph.repository.replay_skip"
    case citationEdgeUpsert = "citation.edge_upsert"
    case citationEdgeRemove = "citation.edge_remove"
    case citationEdgeTombstone = "citation.edge_tombstone"
    case citationParseBibtex = "citation.parse.bibtex"
    case citationParseMarkdown = "citation.parse.markdown"
    case citationResolveUnmatched = "citation.resolve_unmatched"
    case graphNodeCreated = "graph.node.created"
    case graphNodeRemoved = "graph.node.removed"

    // MARK: - Workspace / schema
    case workspaceSchemaMigrate = "workspace.schema.migrate"
    case workspaceModuleToggle = "workspace.module.toggle"

    // MARK: - UI Test Bridge (Debug builds only; see P-AT.1e)
    case uitestBridgeCommandReceived = "uitest.bridge.command_received"
    case uitestBridgeCommandCompleted = "uitest.bridge.command_completed"
    case uitestBridgeCommandFailed = "uitest.bridge.command_failed"
    case uitestBridgeStarted = "uitest.bridge.started"
    case uitestBridgeStopped = "uitest.bridge.stopped"
}

public extension AppDebugEventName {
    /// Validates an event name follows the `<domain>.<entity>(.<verb>)?` snake_case
    /// convention. Used by the registry lint test and by the AI Usage Test
    /// orchestrator when ingesting unknown events from older logs.
    static func isValidEventName(_ raw: String) -> Bool {
        guard !raw.isEmpty else { return false }
        let segments = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, segments.count <= 4 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        for segment in segments {
            guard !segment.isEmpty else { return false }
            if segment.contains(where: { !allowed.contains($0) }) { return false }
            if segment.first == "_" || segment.last == "_" { return false }
        }
        return true
    }
}
