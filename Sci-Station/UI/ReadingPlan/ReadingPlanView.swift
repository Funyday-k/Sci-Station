import SwiftUI

struct ReadingPlanView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let project: ResearchProject

    @State private var selectedScopeIdentifier: String
    @State private var selectedPlanID: String?

    init(workspace: ResearchWorkspace, project: ResearchProject) {
        self.workspace = workspace
        self.project = project
        _selectedScopeIdentifier = State(initialValue: ReadingPlanScope.project(project.id).identifier)
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
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if appModel.currentProjectID != project.id {
                appModel.focusResearchProject(project.id)
            }
            ensureSelection()
        }
        .onChange(of: appModel.readingPlanScopes) { _, _ in
            ensureSelection()
        }
        .onChange(of: selectedScopeIdentifier) { _, _ in
            selectedPlanID = nil
            ensureSelection()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(
                    appModel.localized("阅读计划", "Reading Plan"),
                    systemImage: ProjectSpaceTabIcon.systemImage(for: "reading-plan")
                )
                .font(.largeTitle.weight(.semibold))
                Spacer(minLength: 0)
                Button {
                    appModel.generateReadingPlan(scope: selectedScope)
                } label: {
                    Label(appModel.localized("生成本周计划", "Generate This Week"), systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
            Text(appModel.localized(
                "从研究队列生成本周阅读计划，激活后会同步到 Home 和 Project Dashboard。当前工作区：\(workspace.displayName)。",
                "Generate a weekly plan from the research queue. Active plans appear on Home and Project Dashboard. Workspace: \(workspace.displayName)."
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
            .frame(maxWidth: 280)

            if let activePlan = activePlan {
                Label(activePlanProgressText(activePlan), systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(appModel.localized("暂无激活计划", "No active plan"), systemImage: "circle.dashed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                appModel.selectProjectSpaceTab("queue")
            } label: {
                Label(appModel.localized("打开 Queue", "Open Queue"), systemImage: "tray.full")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.bottom, 8)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 18) {
            planList
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 340, maxHeight: .infinity, alignment: .top)
            Divider()
            planDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, 14)
    }

    private var planList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(appModel.localized("计划", "Plans"))
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
                    Text(appModel.localized("先在 Queue 中加入论文，再生成本周计划。", "Add papers to Queue, then generate this week's plan."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        appModel.generateReadingPlan(scope: selectedScope)
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
                                ReadingPlanListRow(plan: plan, isSelected: selectedPlanID == plan.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var planDetail: some View {
        if let selectedPlan {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    selectedPlanHeader(selectedPlan)
                    if selectedPlan.slots.isEmpty {
                        emptyPlanState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(selectedPlan.slots.sorted(by: slotSort)) { slot in
                                ReadingPlanSlotRow(
                                    slot: slot,
                                    plan: selectedPlan,
                                    onOpen: { open(slot) },
                                    onStatus: { status in
                                        appModel.updateReadingPlanSlotStatus(planID: selectedPlan.id, slotID: slot.id, status: status)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 18)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label(appModel.localized("选择或生成一个计划", "Select or generate a plan"), systemImage: "list.bullet.rectangle")
                    .font(.title3.weight(.semibold))
                Text(appModel.localized("P50 当前切片使用确定性规则从 P48 Queue 生成计划，不依赖 P49 UI 或 AI 权限。", "This P50 slice uses deterministic generation from P48 Queue and does not depend on P49 UI or AI permissions."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    appModel.generateReadingPlan(scope: selectedScope)
                } label: {
                    Label(appModel.localized("生成本周计划", "Generate This Week"), systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func selectedPlanHeader(_ plan: ReadingPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.weekStart.formatted(date: .abbreviated, time: .omitted))
                            .font(.title2.weight(.semibold))
                        ReadingPlanStatusBadge(status: plan.status)
                    }
                    Text(activePlanProgressText(plan))
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
            ReadingPlanProgressBar(plan: plan)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyPlanState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(appModel.localized("Queue 中暂无可计划条目", "No queue entries available"), systemImage: "tray")
                .font(.headline)
            Text(appModel.localized("计划会选取 queued / reading 状态的论文。请先把论文加入项目 Queue。", "Plans select queued or reading entries. Add papers to the project queue first."))
                .foregroundStyle(.secondary)
            Button {
                appModel.selectProjectSpaceTab("queue")
            } label: {
                Label(appModel.localized("前往 Queue", "Go to Queue"), systemImage: "tray.full")
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var availableScopes: [ReadingPlanScope] {
        [.project(project.id), .workspace]
    }

    private var selectedScope: ReadingPlanScope {
        ReadingPlanScope(identifier: selectedScopeIdentifier) ?? .project(project.id)
    }

    private var plans: [ReadingPlan] {
        appModel.readingPlans(in: selectedScope)
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

    private func ensureSelection() {
        if let selectedPlanID, plans.contains(where: { $0.id == selectedPlanID }) {
            return
        }
        selectedPlanID = activePlan?.id ?? plans.first?.id
    }

    private func scopeLabel(for scope: ReadingPlanScope) -> String {
        switch scope {
        case .workspace:
            return appModel.localized("Workspace", "Workspace")
        case .project:
            return project.name
        }
    }

    private func activePlanProgressText(_ plan: ReadingPlan) -> String {
        let totalMinutes = plan.slots.reduce(0) { $0 + max(0, $1.estimatedMinutes) }
        return appModel.localized(
            "\(plan.completedSlotCount)/\(plan.slots.count) 完成 · \(totalMinutes) 分钟",
            "\(plan.completedSlotCount)/\(plan.slots.count) finished · \(totalMinutes) min"
        )
    }

    private func open(_ slot: ReadingPlanSlot) {
        if let paperID = slot.paperID {
            appModel.selectPaper(id: paperID)
            appModel.selectResearchProject(project.id, section: .library)
        } else {
            appModel.selectProjectSpaceTab("queue")
        }
    }

    private func slotSort(_ lhs: ReadingPlanSlot, _ rhs: ReadingPlanSlot) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.createdAt < rhs.createdAt
    }
}

private struct ReadingPlanListRow: View {
    let plan: ReadingPlan
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(plan.weekStart.formatted(date: .abbreviated, time: .omitted))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                ReadingPlanStatusBadge(status: plan.status)
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

private struct ReadingPlanSlotRow: View {
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
                    ReadingPlanSlotAction(title: appModel.localized("开始", "Reading"), systemImage: "book", isActive: slot.status == .reading) {
                        onStatus(.reading)
                    }
                    ReadingPlanSlotAction(title: appModel.localized("完成", "Done"), systemImage: "checkmark", isActive: slot.status == .finished) {
                        onStatus(.finished)
                    }
                    ReadingPlanSlotAction(title: appModel.localized("跳过", "Skip"), systemImage: "forward", isActive: slot.status == .skipped) {
                        onStatus(.skipped)
                    }
                    ReadingPlanSlotAction(title: appModel.localized("结转", "Carry"), systemImage: "arrow.uturn.forward", isActive: slot.status == .carriedOver) {
                        onStatus(.carriedOver)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var detailText: String {
        [slot.plannedDay, slot.status.label, "\(slot.estimatedMinutes)m"].compactMap { $0 }.joined(separator: " · ")
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

private struct ReadingPlanSlotAction: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isActive ? .accentColor : .secondary)
    }
}

private struct ReadingPlanProgressBar: View {
    let plan: ReadingPlan

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(Color.green.opacity(0.75))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 8)
    }

    private var progress: Double {
        guard !plan.slots.isEmpty else { return 0 }
        return Double(plan.completedSlotCount) / Double(plan.slots.count)
    }
}

private struct ReadingPlanStatusBadge: View {
    let status: ReadingPlanStatus

    var body: some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch status {
        case .draft: return .orange
        case .active: return .green
        case .archived: return .secondary
        }
    }
}

private extension ReadingPlanStatus {
    var label: String {
        switch self {
        case .draft: return "Draft"
        case .active: return "Active"
        case .archived: return "Archived"
        }
    }
}

private extension ReadingPlanSlotStatus {
    var label: String {
        switch self {
        case .planned: return "Planned"
        case .reading: return "Reading"
        case .finished: return "Finished"
        case .skipped: return "Skipped"
        case .carriedOver: return "Carried over"
        }
    }
}
