import Foundation

/// Centralised registry of debug event names emitted via `AppDebugEventLogger`.
///
/// All new events should be added here so that:
/// 1. Typos are caught at compile time.
/// 2. Tests can assert against an allow-list.
/// 3. Tooling can enumerate all known events for dashboards / filters.
///
/// Naming convention: `<domain>.<entity>.<verb>` using `snake_case` for
/// multi-word tokens and `.` as the separator.
///
/// See DOC/comment.md §8.1.
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

    // MARK: - Agent
    case agentPromptSubmitted = "agent.prompt_submitted"
    case agentRunCompleted = "agent.run_completed"
    case agentRunFailed = "agent.run_failed"
    case agentToolGraphQuery = "agent.tool.graph_query"

    // MARK: - Graph (P44–P47)
    case graphIndexerRebuildStarted = "graph.indexer.rebuild_started"
    case graphIndexerRebuildCompleted = "graph.indexer.rebuild_completed"
    case graphIndexerIncrementalUpdate = "graph.indexer.incremental_update"
    case citationEdgeUpsert = "citation.edge_upsert"
    case citationEdgeRemove = "citation.edge_remove"
    case graphNodeCreated = "graph.node.created"
    case graphNodeRemoved = "graph.node.removed"

    // MARK: - Workspace / schema
    case workspaceSchemaMigrate = "workspace.schema.migrate"
    case workspaceModuleToggle = "workspace.module.toggle"
}
