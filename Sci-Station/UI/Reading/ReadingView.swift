import AppKit
import SwiftUI

struct ReadingView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject

    @State private var selectedScopeIdentifier: String
    @State private var selectedMode: ReadingMode = .list
    @State private var selectedPlanID: String?
    @State private var statusFilter: ReadingStatusFilter = .activeOnly
    @State private var sourceFilter: ReadingSourceFilter = .all
    @State private var isShowingLibraryPicker = false

    init(workspace: ResearchWorkspace, project: ResearchProject) {
        self.workspace = workspace
        self.project = project
        _selectedScopeIdentifier = State(initialValue: QueueScope.project(project.id).identifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            toolbar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isShowingLibraryPicker) {
            ReadingAddFromLibrarySheet(workspace: workspace, scope: selectedQueueScope, isPresented: $isShowingLibraryPicker)
                .environmentObject(appModel)
                .frame(minWidth: 640, minHeight: 520)
        }
        .onAppear {
            if appModel.currentProjectID != project.id {
                appModel.focusResearchProject(project.id)
            }
            ensureScopeStillValid()
            ensurePlanSelection()
        }
        .onChange(of: appModel.researchQueueScopes) { _, _ in
            ensureScopeStillValid()
        }
        .onChange(of: appModel.readingPlanScopes) { _, _ in
            ensurePlanSelection()
        }
        .onChange(of: selectedScopeIdentifier) { _, _ in
            selectedPlanID = nil
            ensurePlanSelection()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(appModel.localized("Reading", "Reading"), systemImage: ProjectSpaceTabIcon.systemImage(for: "reading"))
                    .font(.largeTitle.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    appModel.selectProjectSpaceTab("recommendations")
                } label: {
                    Label(appModel.localized("arXiv 推荐", "arXiv Recommendations"), systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                Button {
                    appModel.generateReadingPlan(scope: selectedPlanScope)
                    selectedMode = .weeklyPlan
                } label: {
                    Label(appModel.localized("生成本周计划", "Generate This Week"), systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
            Text(appModel.localized(
                "统一管理待读论文、阅读状态和本周阅读安排。arXiv 推荐会直接加入这里，不再维护独立的 Queue / Reading Plan 入口。",
                "Manage papers to read, reading state, and this week's plan in one place. arXiv recommendations land here directly instead of a separate Queue / Reading Plan flow."
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
                ForEach(availableQueueScopes, id: \.identifier) { scope in
                    Text(scopeLabel(for: scope)).tag(scope.identifier)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Picker(appModel.localized("视图", "View"), selection: $selectedMode) {
                ForEach(ReadingMode.allCases, id: \.self) { mode in
                    Text(mode.label(appModel: appModel)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            if selectedMode == .list {
                Picker(appModel.localized("状态", "Status"), selection: $statusFilter) {
                    ForEach(ReadingStatusFilter.allCases, id: \.self) { filter in
                        Text(filter.label(appModel: appModel)).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)

                Picker(appModel.localized("来源", "Source"), selection: $sourceFilter) {
                    ForEach(ReadingSourceFilter.allCases, id: \.self) { filter in
                        Text(filter.label(appModel: appModel)).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            } else if let activePlan {
                Label(planProgressText(activePlan), systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(appModel.localized("暂无激活计划", "No active plan"), systemImage: "circle.dashed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                isShowingLibraryPicker = true
            } label: {
                Label(appModel.localized("从论文库添加…", "Add from Library…"), systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedMode {
        case .list:
            readingListContent
        case .weeklyPlan:
            weeklyPlanContent
        }
    }

    @ViewBuilder
    private var readingListContent: some View {
        if entriesForCurrentScope.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Label(appModel.localized("Reading 为空", "Reading is empty"), systemImage: "tray")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(appModel.localized("从论文库添加论文，或打开 arXiv 推荐把新论文加入 Reading。", "Add papers from the Library, or open arXiv Recommendations to add new papers to Reading."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        isShowingLibraryPicker = true
                    } label: {
                        Label(appModel.localized("从论文库添加…", "Add from Library…"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        appModel.selectProjectSpaceTab("recommendations")
                    } label: {
                        Label(appModel.localized("打开 arXiv 推荐", "Open arXiv Recommendations"), systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.top, 24)
        } else if filteredEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(appModel.localized("没有条目匹配当前筛选", "No entries match the active filters"), systemImage: "line.3.horizontal.decrease.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button {
                    statusFilter = .activeOnly
                    sourceFilter = .all
                } label: {
                    Label(appModel.localized("重置筛选", "Reset filters"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 420, alignment: .leading)
            .padding(.top, 18)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        ReadingEntryRow(
                            entry: entry,
                            isFirst: filteredEntries.first?.id == entry.id,
                            isLast: filteredEntries.last?.id == entry.id,
                            onOpen: { open(entry) },
                            onMoveUp: { appModel.moveResearchQueueEntry(id: entry.id, in: selectedQueueScope, offset: -1) },
                            onMoveDown: { appModel.moveResearchQueueEntry(id: entry.id, in: selectedQueueScope, offset: 1) },
                            onStatusChange: { appModel.updateResearchQueueEntryStatus(id: entry.id, status: $0) },
                            onRemove: { appModel.removeResearchQueueEntry(id: entry.id) }
                        )
                        Divider()
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var weeklyPlanContent: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(appModel.localized("本周计划", "Weekly Plans"))
                        .font(.headline)
                    Spacer(minLength: 0)
                    Text("\(plans.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if plans.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(appModel.localized("还没有计划。", "No plans yet."))
                            .font(.callout.weight(.medium))
                        Text(appModel.localized("Reading 中的 queued / reading 条目会被选入本周计划。", "Queued / reading items in Reading are selected for this week's plan."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            appModel.generateReadingPlan(scope: selectedPlanScope)
                        } label: {
                            Label(appModel.localized("生成草稿", "Generate Draft"), systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(plans) { plan in
                                Button {
                                    selectedPlanID = plan.id
                                } label: {
                                    ReadingPlanListCard(plan: plan, isSelected: selectedPlan?.id == plan.id)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 340, maxHeight: .infinity, alignment: .top)

            Divider()

            planDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var planDetail: some View {
        if let selectedPlan {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    selectedPlanHeader(selectedPlan)
                    if selectedPlan.slots.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(appModel.localized("Reading 中暂无可计划条目", "No Reading items available"), systemImage: "tray")
                                .font(.headline)
                            Text(appModel.localized("计划会选取 queued / reading 状态的论文。请先加入 Reading。", "Plans select queued or reading items. Add papers to Reading first."))
                                .foregroundStyle(.secondary)
                            Button {
                                selectedMode = .list
                            } label: {
                                Label(appModel.localized("前往 Reading", "Go to Reading"), systemImage: "book")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        VStack(spacing: 10) {
                            ForEach(selectedPlan.slots.sorted(by: slotSort)) { slot in
                                ReadingPlanSlotCard(slot: slot, plan: selectedPlan, onOpen: { open(slot) }) { status in
                                    appModel.updateReadingPlanSlotStatus(planID: selectedPlan.id, slotID: slot.id, status: status)
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label(appModel.localized("选择或生成一个计划", "Select or generate a plan"), systemImage: "list.bullet.rectangle")
                    .font(.title3.weight(.semibold))
                Text(appModel.localized("Reading 现在同时承载清单与计划，避免 Queue 和 Reading Plan 分裂。", "Reading now owns both the list and the plan, avoiding split Queue and Reading Plan flows."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    appModel.generateReadingPlan(scope: selectedPlanScope)
                } label: {
                    Label(appModel.localized("生成本周计划", "Generate This Week"), systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.top, 18)
        }
    }

    private func selectedPlanHeader(_ plan: ReadingPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.weekStart.formatted(date: .abbreviated, time: .omitted))
                            .font(.title2.weight(.semibold))
                        Text(planStatusLabel(plan.status))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(planStatusTint(plan.status).opacity(0.16), in: Capsule())
                            .foregroundStyle(planStatusTint(plan.status))
                    }
                    Text(planProgressText(plan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if plan.status != .active {
                    Button {
                        appModel.activateReadingPlan(planID: plan.id, scope: plan.scope)
                    } label: {
                        Label(appModel.localized("激活", "Activate"), systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if plan.status != .archived {
                    Button {
                        appModel.archiveReadingPlan(planID: plan.id, scope: plan.scope)
                    } label: {
                        Label(appModel.localized("归档", "Archive"), systemImage: "archivebox")
                    }
                    .buttonStyle(.bordered)
                }
            }
            ProgressView(value: Double(plan.completedSlotCount), total: Double(max(plan.slots.count, 1)))
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var availableQueueScopes: [QueueScope] {
        appModel.availableResearchQueueScopes
    }

    private var selectedQueueScope: QueueScope {
        QueueScope(identifier: selectedScopeIdentifier) ?? .project(project.id)
    }

    private var selectedPlanScope: ReadingPlanScope {
        ReadingPlanScope(queueScope: selectedQueueScope)
    }

    private var entriesForCurrentScope: [ResearchQueueEntry] {
        appModel.researchQueueEntries(in: selectedQueueScope)
    }

    private var filteredEntries: [ResearchQueueEntry] {
        entriesForCurrentScope.filter { entry in
            statusFilter.matches(entry.status) && sourceFilter.matches(entry.source)
        }
    }

    private var plans: [ReadingPlan] {
        appModel.readingPlans(in: selectedPlanScope)
    }

    private var selectedPlan: ReadingPlan? {
        if let selectedPlanID, let plan = plans.first(where: { $0.id == selectedPlanID }) {
            return plan
        }
        return activePlan ?? plans.first
    }

    private var activePlan: ReadingPlan? {
        plans.first { $0.status == .active }
    }

    private func scopeLabel(for scope: QueueScope) -> String {
        switch scope {
        case .workspace:
            return appModel.localized("工作区", "Workspace")
        case .project:
            return project.name
        }
    }

    private func ensureScopeStillValid() {
        guard !availableQueueScopes.isEmpty else {
            selectedScopeIdentifier = QueueScope.workspace.identifier
            return
        }
        if availableQueueScopes.contains(where: { $0.identifier == selectedScopeIdentifier }) {
            return
        }
        if let projectScope = availableQueueScopes.first(where: {
            if case .project = $0 { return true }
            return false
        }) {
            selectedScopeIdentifier = projectScope.identifier
        } else {
            selectedScopeIdentifier = availableQueueScopes.first?.identifier ?? QueueScope.workspace.identifier
        }
    }

    private func ensurePlanSelection() {
        if let selectedPlanID, plans.contains(where: { $0.id == selectedPlanID }) {
            return
        }
        selectedPlanID = activePlan?.id ?? plans.first?.id
    }

    private func planProgressText(_ plan: ReadingPlan) -> String {
        let totalMinutes = plan.slots.reduce(0) { $0 + max(0, $1.estimatedMinutes) }
        return appModel.localized(
            "\(plan.completedSlotCount)/\(plan.slots.count) 完成 · \(totalMinutes) 分钟",
            "\(plan.completedSlotCount)/\(plan.slots.count) finished · \(totalMinutes) min"
        )
    }

    private func open(_ entry: ResearchQueueEntry) {
        if let paperID = entry.paperID {
            appModel.selectPaper(id: paperID)
        } else if let urlString = entry.externalKey?.readingArxivURLString, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func open(_ slot: ReadingPlanSlot) {
        if let paperID = slot.paperID {
            appModel.selectPaper(id: paperID)
        } else if let urlString = slot.externalKey?.readingArxivURLString, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            selectedMode = .list
        }
    }

    private func slotSort(_ lhs: ReadingPlanSlot, _ rhs: ReadingPlanSlot) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.createdAt < rhs.createdAt
    }

    private func planStatusLabel(_ status: ReadingPlanStatus) -> String {
        switch status {
        case .draft: return appModel.localized("草稿", "Draft")
        case .active: return appModel.localized("已激活", "Active")
        case .archived: return appModel.localized("已归档", "Archived")
        }
    }

    private func planStatusTint(_ status: ReadingPlanStatus) -> Color {
        switch status {
        case .draft: return .secondary
        case .active: return .green
        case .archived: return .purple
        }
    }
}

private enum ReadingMode: Hashable, CaseIterable {
    case list
    case weeklyPlan

    func label(appModel: AppViewModel) -> String {
        switch self {
        case .list: return appModel.localized("阅读清单", "Reading List")
        case .weeklyPlan: return appModel.localized("本周计划", "Weekly Plan")
        }
    }
}

private enum ReadingStatusFilter: Hashable, CaseIterable {
    case activeOnly
    case all
    case queued
    case reading
    case finished
    case deferred
    case dismissed

    func label(appModel: AppViewModel) -> String {
        switch self {
        case .activeOnly: return appModel.localized("活跃", "Active")
        case .all: return appModel.localized("全部状态", "All statuses")
        case .queued: return appModel.localized("待读", "Queued")
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

private enum ReadingSourceFilter: Hashable, CaseIterable {
    case all
    case manual
    case recommendation
    case graphTool
    case paperStatus

    func label(appModel: AppViewModel) -> String {
        switch self {
        case .all: return appModel.localized("全部来源", "All sources")
        case .manual: return appModel.localized("手动", "Manual")
        case .recommendation: return appModel.localized("arXiv 推荐", "arXiv Recommendation")
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

private struct ReadingEntryRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let entry: ResearchQueueEntry
    let isFirst: Bool
    let isLast: Bool
    let onOpen: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onStatusChange: (QueueStatus) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(statusLabel(entry.status), systemImage: statusSystemImage(entry.status))
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusTint(entry.status).opacity(0.18), in: Capsule())
                .foregroundStyle(statusTint(entry.status))
                .frame(minWidth: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Button(action: onOpen) {
                    Text(entry.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    Text(sourceLabel(entry.source))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                    if let externalKey = entry.externalKey, entry.paperID == nil {
                        Text(externalKey)
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
                    }
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(isFirst)

                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.borderless)
                .disabled(isLast)

                Menu {
                    Section(appModel.localized("状态", "Status")) {
                        statusButton(.queued, title: appModel.localized("标为待读", "Mark queued"), systemImage: "tray")
                        statusButton(.reading, title: appModel.localized("标为阅读中", "Mark reading"), systemImage: "book")
                        statusButton(.finished, title: appModel.localized("标为已完成", "Mark finished"), systemImage: "checkmark.seal")
                        statusButton(.deferred, title: appModel.localized("暂缓", "Defer"), systemImage: "moon")
                        statusButton(.dismissed, title: appModel.localized("忽略", "Dismiss"), systemImage: "xmark.circle")
                    }
                    Divider()
                    Button(role: .destructive, action: onRemove) {
                        Label(appModel.localized("从 Reading 移除", "Remove from Reading"), systemImage: "trash")
                    }
                    Divider()
                    Button(action: onOpen) {
                        Label(appModel.localized("打开", "Open"), systemImage: "arrow.up.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
    }

    private func statusButton(_ status: QueueStatus, title: String, systemImage: String) -> some View {
        Button {
            onStatusChange(status)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .disabled(entry.status == status)
    }

    private func statusLabel(_ status: QueueStatus) -> String {
        switch status {
        case .queued: return appModel.localized("待读", "Queued")
        case .reading: return appModel.localized("阅读中", "Reading")
        case .finished: return appModel.localized("已完成", "Finished")
        case .deferred: return appModel.localized("暂缓", "Deferred")
        case .dismissed: return appModel.localized("已忽略", "Dismissed")
        }
    }

    private func statusSystemImage(_ status: QueueStatus) -> String {
        switch status {
        case .queued: return "tray"
        case .reading: return "book"
        case .finished: return "checkmark.seal"
        case .deferred: return "moon"
        case .dismissed: return "xmark.circle"
        }
    }

    private func statusTint(_ status: QueueStatus) -> Color {
        switch status {
        case .queued: return .blue
        case .reading: return .orange
        case .finished: return .green
        case .deferred: return .purple
        case .dismissed: return .secondary
        }
    }

    private func sourceLabel(_ source: QueueSource) -> String {
        switch source {
        case .manual: return appModel.localized("手动", "Manual")
        case .recommendation: return appModel.localized("arXiv 推荐", "arXiv Recommendation")
        case .graphTool: return appModel.localized("图谱工具", "Graph tool")
        case .paperStatus: return appModel.localized("论文状态同步", "Paper status sync")
        }
    }
}

private struct ReadingPlanListCard: View {
    let plan: ReadingPlan
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(plan.weekStart.formatted(date: .abbreviated, time: .omitted))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(plan.status.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            HStack(spacing: 8) {
                Text("\(plan.completedSlotCount)/\(plan.slots.count)")
                    .font(.caption.monospacedDigit())
                Text("\(plan.slots.reduce(0) { $0 + $1.estimatedMinutes })m")
                    .font(.caption.monospacedDigit())
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 0.8)
        )
    }
}

private struct ReadingPlanSlotCard: View {
    @EnvironmentObject private var appModel: AppViewModel
    let slot: ReadingPlanSlot
    let plan: ReadingPlan
    let onOpen: () -> Void
    let onStatus: (ReadingPlanSlotStatus) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSystemImage)
                .font(.title3)
                .foregroundStyle(statusTint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Button(action: onOpen) {
                    Text(slot.displayTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    slotAction(title: appModel.localized("开始", "Reading"), systemImage: "book", status: .reading)
                    slotAction(title: appModel.localized("完成", "Done"), systemImage: "checkmark", status: .finished)
                    slotAction(title: appModel.localized("跳过", "Skip"), systemImage: "forward", status: .skipped)
                    slotAction(title: appModel.localized("结转", "Carry"), systemImage: "arrow.uturn.forward", status: .carriedOver)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func slotAction(title: String, systemImage: String, status: ReadingPlanSlotStatus) -> some View {
        Button {
            onStatus(status)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(slot.status == status)
    }

    private var detailText: String {
        [slot.plannedDay, slotStatusLabel, "\(slot.estimatedMinutes)m"].compactMap { $0 }.joined(separator: " · ")
    }

    private var slotStatusLabel: String {
        switch slot.status {
        case .planned: return appModel.localized("计划中", "Planned")
        case .reading: return appModel.localized("阅读中", "Reading")
        case .finished: return appModel.localized("已完成", "Finished")
        case .skipped: return appModel.localized("已跳过", "Skipped")
        case .carriedOver: return appModel.localized("结转", "Carried")
        }
    }

    private var statusSystemImage: String {
        switch slot.status {
        case .planned: return "circle"
        case .reading: return "book.fill"
        case .finished: return "checkmark.circle.fill"
        case .skipped: return "forward.circle"
        case .carriedOver: return "arrow.uturn.forward.circle"
        }
    }

    private var statusTint: Color {
        switch slot.status {
        case .planned: return .secondary
        case .reading: return .orange
        case .finished: return .green
        case .skipped: return .purple
        case .carriedOver: return .blue
        }
    }
}

private struct ReadingAddFromLibrarySheet: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let scope: QueueScope
    @Binding var isPresented: Bool

    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(appModel.localized("添加到 Reading", "Add to Reading"))
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
                    let alreadyAdded = isPaperInReading(paper.id)
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
                        if alreadyAdded {
                            Label(appModel.localized("已添加", "Added"), systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                appModel.addPaperToResearchQueue(paperID: paper.id, displayTitle: paper.displayTitle, scope: scope)
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

    private var filteredPapers: [Paper] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return appModel.papers
        }
        return appModel.papers.filter { paper in
            paper.displayTitle.lowercased().contains(trimmed) || paper.authorsDisplay.lowercased().contains(trimmed)
        }
    }

    private func isPaperInReading(_ paperID: String) -> Bool {
        appModel.researchQueueEntries(in: scope).contains { entry in
            entry.paperID == paperID
        }
    }
}

private extension String {
    var readingArxivURLString: String? {
        let lowered = lowercased()
        guard lowered.hasPrefix("arxiv:") else {
            return nil
        }
        let id = String(dropFirst("arxiv:".count))
        return "https://arxiv.org/abs/\(id)"
    }
}
