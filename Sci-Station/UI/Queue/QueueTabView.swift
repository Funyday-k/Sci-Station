import SwiftUI

/// Project-space tab that surfaces the Research Queue (P48). The view reads
/// from `AppViewModel.researchQueueScopes` and routes mutations back through
/// the model's queue helpers. Scope picker lets the user switch between the
/// workspace queue and the current project's queue without losing context.
/// See `DOC/Proposal48.md` §4.6.
struct QueueTabView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject?

    @State private var selectedScopeIdentifier: String
    @State private var statusFilter: StatusFilter = .activeOnly
    @State private var sourceFilter: SourceFilter = .all
    @State private var isShowingLibraryPicker = false
    /// SwiftUI lazily evaluates `.sheet` content, but on first navigation to
    /// this tab the picker's heavy `List` was building during the slide-in
    /// animation, causing a brief white-screen flash. Defer construction until
    /// the user actually opens the picker.

    init(workspace: ResearchWorkspace, project: ResearchProject?) {
        self.workspace = workspace
        self.project = project
        if let project {
            _selectedScopeIdentifier = State(initialValue: QueueScope.project(project.id).identifier)
        } else {
            _selectedScopeIdentifier = State(initialValue: QueueScope.workspace.identifier)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        // Explicit window-coloured backdrop so the tab no longer briefly
        // shows the bare SwiftUI clear background while navigating in.
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Only refocus when the project actually changed — calling
            // `focusResearchProject` unconditionally on every tab visit
            // rebuilds the agent context and re-persists drafts, which
            // contributed to the "队列界面卡住" lag reported on 2026-05-17.
            if let project, appModel.currentProjectID != project.id {
                appModel.focusResearchProject(project.id)
            }
            ensureScopeStillValid()
        }
        .onChange(of: appModel.currentProjectID) { _, _ in
            ensureScopeStillValid()
        }
        .sheet(isPresented: $isShowingLibraryPicker) {
            QueueAddFromLibrarySheet(
                workspace: workspace,
                scope: selectedScope,
                isPresented: $isShowingLibraryPicker
            )
            .environmentObject(appModel)
            .frame(minWidth: 520, minHeight: 480)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(
                    appModel.localized("研究队列", "Research Queue"),
                    systemImage: ProjectSpaceTabIcon.systemImage(for: "queue")
                )
                .font(.largeTitle.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    isShowingLibraryPicker = true
                } label: {
                    Label(
                        appModel.localized("从论文库添加…", "Add from Library…"),
                        systemImage: "plus"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            Text(appModel.localized(
                "面向工作区与当前项目的长期阅读队列。手动添加直接入队；AI 建议仍需在 Draft Inbox 审批推荐笔记后才会进入队列。",
                "Long-lived reading queue for the workspace and current project. Manual edits never enter Draft Inbox; AI suggestions still flow through the recommendation note approval."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 12)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Picker(appModel.localized("范围", "Scope"), selection: $selectedScopeIdentifier) {
                ForEach(availableScopes, id: \.identifier) { scope in
                    Text(scopeLabel(for: scope)).tag(scope.identifier)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Picker(appModel.localized("状态", "Status"), selection: $statusFilter) {
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    Text(filter.label(appModel: appModel)).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220)

            Picker(appModel.localized("来源", "Source"), selection: $sourceFilter) {
                ForEach(SourceFilter.allCases, id: \.self) { filter in
                    Text(filter.label(appModel: appModel)).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220)

            Spacer(minLength: 0)

            Text(rowCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if entriesForCurrentScope.isEmpty {
            onboardingState
        } else if filteredEntries.isEmpty {
            filterEmptyState
        } else {
            entryList
        }
    }

    private var entryList: some View {
        // ScrollView + LazyVStack instead of `List` — `List` on macOS wraps
        // NSCollectionView which is expensive to instantiate (perceived as
        // a freeze on first tab open). The queue uses simple row layouts
        // and benefits from lazy on-demand rendering.
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredEntries) { entry in
                    QueueEntryRow(
                        entry: entry,
                        isFirst: filteredEntries.first?.id == entry.id,
                        isLast: filteredEntries.last?.id == entry.id,
                        onMoveUp: { appModel.moveResearchQueueEntry(id: entry.id, in: selectedScope, offset: -1) },
                        onMoveDown: { appModel.moveResearchQueueEntry(id: entry.id, in: selectedScope, offset: 1) },
                        onStatusChange: { newStatus in
                            appModel.updateResearchQueueEntryStatus(id: entry.id, status: newStatus)
                        },
                        onRemove: { appModel.removeResearchQueueEntry(id: entry.id) }
                    )
                    .accessibilityIdentifier(UITestAccessibilityID.Queue.row(entry.id))
                    Divider()
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier(UITestAccessibilityID.Queue.list)
    }

    private var onboardingState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                appModel.localized("队列为空", "Queue is empty"),
                systemImage: "tray"
            )
            .font(.title2.weight(.semibold))
            .foregroundStyle(.secondary)
            Text(appModel.localized(
                "从论文库 / 图谱添加论文以开始阅读队列。手动添加会直接入队；AI 推荐论文需先在 Draft Inbox 审批推荐笔记。",
                "Add a paper from Library / Graph to start your queue. Manual additions land here immediately; AI-suggested papers arrive after you approve a recommendation note in Draft Inbox."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                isShowingLibraryPicker = true
            } label: {
                Label(
                    appModel.localized("从论文库添加…", "Add from Library…"),
                    systemImage: "plus"
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.top, 24)
    }

    private var filterEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                appModel.localized("没有条目匹配当前筛选", "No entries match the active filters"),
                systemImage: "line.3.horizontal.decrease.circle"
            )
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            Button {
                statusFilter = .activeOnly
                sourceFilter = .all
            } label: {
                Label(
                    appModel.localized("重置筛选", "Reset filters"),
                    systemImage: "arrow.counterclockwise"
                )
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(.top, 18)
    }

    private var availableScopes: [QueueScope] {
        appModel.availableResearchQueueScopes
    }

    private var selectedScope: QueueScope {
        QueueScope(identifier: selectedScopeIdentifier) ?? .workspace
    }

    private var entriesForCurrentScope: [ResearchQueueEntry] {
        appModel.researchQueueEntries(in: selectedScope)
    }

    private var filteredEntries: [ResearchQueueEntry] {
        entriesForCurrentScope.filter { entry in
            statusFilter.matches(entry.status) && sourceFilter.matches(entry.source)
        }
    }

    private var rowCountText: String {
        let total = entriesForCurrentScope.count
        let visible = filteredEntries.count
        if total == visible {
            return appModel.localized("共 \(total) 条", "\(total) entries")
        }
        return appModel.localized("\(visible) / \(total) 条", "\(visible) of \(total) entries")
    }

    private func scopeLabel(for scope: QueueScope) -> String {
        switch scope {
        case .workspace:
            return appModel.localized("工作区", "Workspace")
        case .project:
            return appModel.localized("项目", "Project")
        }
    }

    private func ensureScopeStillValid() {
        guard !availableScopes.contains(where: { $0.identifier == selectedScopeIdentifier }) else {
            return
        }
        // When the user switches between projects we want the queue tab to
        // follow them into the new project's queue, not silently fall back to
        // the workspace queue. Prefer the project scope when available.
        if let projectScope = availableScopes.first(where: {
            if case .project = $0 { return true }
            return false
        }) {
            selectedScopeIdentifier = projectScope.identifier
        } else {
            selectedScopeIdentifier = availableScopes.first?.identifier ?? QueueScope.workspace.identifier
        }
    }
}

private enum StatusFilter: Hashable, CaseIterable {
    case activeOnly
    case all
    case queued
    case reading
    case finished
    case deferred
    case dismissed

    func label(appModel: AppViewModel) -> String {
        switch self {
        case .activeOnly: return appModel.localized("活跃（队列中 + 阅读中）", "Active (queued + reading)")
        case .all: return appModel.localized("全部状态", "All statuses")
        case .queued: return appModel.localized("队列中", "Queued")
        case .reading: return appModel.localized("阅读中", "Reading")
        case .finished: return appModel.localized("已完成", "Finished")
        case .deferred: return appModel.localized("暂缓", "Deferred")
        case .dismissed: return appModel.localized("已忽略", "Dismissed")
        }
    }

    func matches(_ status: QueueStatus) -> Bool {
        switch self {
        case .activeOnly:
            return status == .queued || status == .reading
        case .all:
            return true
        case .queued:
            return status == .queued
        case .reading:
            return status == .reading
        case .finished:
            return status == .finished
        case .deferred:
            return status == .deferred
        case .dismissed:
            return status == .dismissed
        }
    }
}

private enum SourceFilter: Hashable, CaseIterable {
    case all
    case manual
    case recommendation
    case graphTool
    case paperStatus

    func label(appModel: AppViewModel) -> String {
        switch self {
        case .all: return appModel.localized("全部来源", "All sources")
        case .manual: return appModel.localized("手动", "Manual")
        case .recommendation: return appModel.localized("AI 推荐", "Recommendation")
        case .graphTool: return appModel.localized("图谱工具", "Graph tool")
        case .paperStatus: return appModel.localized("论文状态同步", "Paper status sync")
        }
    }

    func matches(_ source: QueueSource) -> Bool {
        switch self {
        case .all: return true
        case .manual: return source == .manual
        case .recommendation: return source == .recommendation
        case .graphTool: return source == .graphTool
        case .paperStatus: return source == .paperStatus
        }
    }
}

private struct QueueEntryRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let entry: ResearchQueueEntry
    let isFirst: Bool
    let isLast: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onStatusChange: (QueueStatus) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            statusBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)

                metadataRow
            }

            Spacer(minLength: 12)

            controls
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            openInLibraryOrReader()
        }
    }

    private var statusBadge: some View {
        Label(entry.status.label(appModel: appModel), systemImage: entry.status.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(entry.status.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(entry.status.tint)
            .frame(minWidth: 86, alignment: .leading)
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            Text(entry.source.label(appModel: appModel))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(.secondary)

            if entry.paperID == nil, let key = entry.externalKey {
                Text(appModel.localized("外部: \(key)", "external: \(key)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let paperID = entry.paperID {
                Text(paperID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let note = entry.noteSummary, !note.isEmpty {
                Text("· \(note)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button(action: onMoveUp) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .help(appModel.localized("上移", "Move up"))
            .accessibilityIdentifier(UITestAccessibilityID.Queue.moveUp(entry.id))

            Button(action: onMoveDown) {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .help(appModel.localized("下移", "Move down"))
            .accessibilityIdentifier(UITestAccessibilityID.Queue.moveDown(entry.id))

            Menu {
                Section(appModel.localized("状态", "Status")) {
                    statusButton(.queued, label: appModel.localized("标为队列中", "Mark queued"), systemImage: "tray")
                    statusButton(.reading, label: appModel.localized("标为阅读中", "Mark started (reading)"), systemImage: "book")
                    statusButton(.finished, label: appModel.localized("标为已完成", "Mark finished"), systemImage: "checkmark.seal")
                    statusButton(.deferred, label: appModel.localized("暂缓", "Defer"), systemImage: "moon")
                    statusButton(.dismissed, label: appModel.localized("忽略", "Dismiss"), systemImage: "xmark.circle")
                }
                Divider()
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label(appModel.localized("从队列中移除", "Remove from queue"), systemImage: "trash")
                }
                if entry.paperID != nil {
                    Divider()
                    Button {
                        openInLibraryOrReader()
                    } label: {
                        Label(appModel.localized("在论文库中打开", "Open in Library"), systemImage: "books.vertical")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(appModel.localized("状态与操作", "Status and actions"))
        }
    }

    @ViewBuilder
    private func statusButton(_ status: QueueStatus, label: String, systemImage: String) -> some View {
        Button {
            onStatusChange(status)
        } label: {
            Label(label, systemImage: systemImage)
        }
        .disabled(entry.status == status)
    }

    private func openInLibraryOrReader() {
        guard let paperID = entry.paperID else { return }
        appModel.selectPaper(id: paperID)
    }
}

private struct QueueAddFromLibrarySheet: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let scope: QueueScope
    @Binding var isPresented: Bool

    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(appModel.localized("添加到\(scopeTitle)", "Add to \(scopeTitle)"))
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                Button(appModel.localized("完成", "Done")) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }

            TextField(appModel.localized("搜索标题或作者", "Search title or author"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            if appModel.papers.isEmpty {
                ContentUnavailableView(
                    appModel.localized("工作区中暂无论文", "No papers in this workspace"),
                    systemImage: "books.vertical",
                    description: Text(appModel.localized("请先在论文库中导入论文。", "Import papers from the Library first."))
                )
            } else {
                List(filteredPapers) { paper in
                    let alreadyInQueue = isPaperInQueue(paper.id)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(paper.displayTitle)
                                .font(.callout)
                                .lineLimit(2)
                            Text(paper.authorsDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if alreadyInQueue {
                            Label(appModel.localized("已添加", "Added"), systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                appModel.addPaperToResearchQueue(
                                    paperID: paper.id,
                                    displayTitle: paper.displayTitle,
                                    scope: scope
                                )
                            } label: {
                                Label(appModel.localized("添加", "Add"), systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .padding(20)
    }

    private var scopeTitle: String {
        switch scope {
        case .workspace:
            return appModel.localized("工作区队列", "Workspace Queue")
        case .project(let projectID):
            if let project = appModel.researchProjects.first(where: { $0.id == projectID }) {
                return appModel.localized("\(project.name) 队列", "\(project.name) Queue")
            }
            return appModel.localized("项目队列", "Project Queue")
        }
    }

    private var filteredPapers: [Paper] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let papers = appModel.papers
        guard !trimmed.isEmpty else {
            return papers
        }
        return papers.filter { paper in
            if paper.displayTitle.lowercased().contains(trimmed) { return true }
            if paper.authorsDisplay.lowercased().contains(trimmed) { return true }
            return false
        }
    }

    private func isPaperInQueue(_ paperID: String) -> Bool {
        appModel.researchQueueEntries(in: scope).contains { entry in
            entry.paperID == paperID
        }
    }
}

private extension QueueStatus {
    func label(appModel: AppViewModel) -> String {
        switch self {
        case .queued: return appModel.localized("队列中", "Queued")
        case .reading: return appModel.localized("阅读中", "Reading")
        case .finished: return appModel.localized("已完成", "Finished")
        case .deferred: return appModel.localized("暂缓", "Deferred")
        case .dismissed: return appModel.localized("已忽略", "Dismissed")
        }
    }

    var systemImage: String {
        switch self {
        case .queued: return "tray"
        case .reading: return "book"
        case .finished: return "checkmark.seal"
        case .deferred: return "moon"
        case .dismissed: return "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .queued: return .blue
        case .reading: return .orange
        case .finished: return .green
        case .deferred: return .purple
        case .dismissed: return .secondary
        }
    }
}

private extension QueueSource {
    func label(appModel: AppViewModel) -> String {
        switch self {
        case .manual: return appModel.localized("手动", "Manual")
        case .recommendation: return appModel.localized("AI 推荐", "Recommendation")
        case .graphTool: return appModel.localized("图谱工具", "Graph tool")
        case .paperStatus: return appModel.localized("论文状态同步", "Paper status sync")
        }
    }
}
