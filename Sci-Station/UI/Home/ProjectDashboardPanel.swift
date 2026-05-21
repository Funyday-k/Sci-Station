import SwiftUI

struct ProjectDashboardPanel: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    @State private var aggregator = ProjectDashboardAggregator()
    @State private var snapshot: ProjectDashboardSnapshot?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appModel.localized("Project Dashboard", "Project Dashboard"))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(appModel.localized("阶段、缺口、artifact、deadline 与阅读计划。", "Stage, gaps, artifacts, deadlines, and reading plan."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await reload(invalidating: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(appModel.localized("刷新 Project Dashboard", "Refresh Project Dashboard"))
            }

            if let errorMessage {
                HomeUnavailableView(
                    title: appModel.localized("Project Dashboard 暂时不可用", "Project Dashboard temporarily unavailable"),
                    message: errorMessage,
                    retryTitle: appModel.localized("重试", "Retry")
                ) {
                    Task { await reload(invalidating: true) }
                }
            } else if let snapshot {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                    ProjectDashboardCard(title: appModel.localized("Project Stage", "Project Stage"), systemImage: "gauge.with.dots.needle.33percent") {
                        VStack(alignment: .leading, spacing: 8) {
                            StageBadge(stage: snapshot.stage, rule: snapshot.stageRule)
                            Text(snapshot.stageRule)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ProjectDashboardCard(title: appModel.localized("Core Papers", "Core Papers"), systemImage: "star") {
                        if snapshot.corePapers.isEmpty {
                            ProjectDashboardEmptyText(appModel.localized("还没有核心论文。", "No core papers yet."))
                        } else {
                            VStack(spacing: 7) {
                                ForEach(snapshot.corePapers.prefix(4)) { paper in
                                    ProjectDashboardButtonRow(title: paper.title, detail: paper.authors, systemImage: "doc.richtext") {
                                        recordAction("open_core_paper", targetID: paper.id)
                                        appModel.selectPaper(id: paper.id)
                                        appModel.selectResearchProject(snapshot.projectID, section: .library)
                                    }
                                }
                            }
                        }
                    }

                    ProjectDashboardCard(title: appModel.localized("Open Gaps", "Open Gaps"), systemImage: "scope") {
                        if snapshot.openGaps.isEmpty {
                            ProjectDashboardEmptyText(appModel.localized("没有登记的 research gap。", "No research gaps are registered."))
                        } else {
                            VStack(spacing: 7) {
                                ForEach(snapshot.openGaps.prefix(4)) { gap in
                                    ProjectDashboardButtonRow(title: gap.title, detail: gap.relativePath ?? "", systemImage: "questionmark.bubble") {
                                        recordAction("open_gap", targetID: gap.id)
                                        if let relativePath = gap.relativePath {
                                            appModel.openMarkdownDocument(relativePath: relativePath)
                                        } else {
                                            appModel.selectResearchProject(snapshot.projectID, section: .wiki)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ProjectDashboardCard(title: appModel.localized("Recent Artifacts", "Recent Artifacts"), systemImage: "shippingbox") {
                        if snapshot.recentArtifacts.isEmpty {
                            ProjectDashboardEmptyText(appModel.localized("暂无近期 artifact。", "No recent artifacts yet."))
                        } else {
                            VStack(spacing: 7) {
                                ForEach(snapshot.recentArtifacts) { artifact in
                                    ProjectDashboardButtonRow(
                                        title: artifact.title,
                                        detail: artifact.kind + " - " + artifact.savedAt.formatted(date: .abbreviated, time: .omitted),
                                        systemImage: artifact.status == "needs_review" ? "doc.badge.clock" : "doc.text"
                                    ) {
                                        recordAction("open_artifact", targetID: artifact.id)
                                        if let targetPath = artifact.targetPath {
                                            appModel.openWorkspaceRelativePath(targetPath)
                                        } else {
                                            appModel.selectResearchProject(snapshot.projectID, section: .llmLab)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ProjectDashboardCard(title: appModel.localized("Next Deadline", "Next Deadline"), systemImage: "calendar.badge.clock") {
                        if let deadline = snapshot.nextDeadline {
                            ProjectDashboardButtonRow(
                                title: deadline.title,
                                detail: deadline.dueDate.formatted(date: .abbreviated, time: .omitted),
                                systemImage: "calendar"
                            ) {
                                recordAction("open_next_deadline", targetID: deadline.id)
                                appModel.selectResearchProject(snapshot.projectID, section: .tasks)
                            }
                        } else {
                            ProjectDashboardEmptyText(appModel.localized("没有即将到期的项目任务。", "No upcoming project tasks."))
                        }
                    }

                    ProjectDashboardCard(title: appModel.localized("Reading", "Reading"), systemImage: "book") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let plan = snapshot.activeReadingPlan {
                                ProjectDashboardReadingPlanSummary(plan: plan)
                            }
                            if snapshot.readingQueuePreview.isEmpty {
                                Text(appModel.localized("还没有论文进入 Reading。从 Library 添加，或打开 arXiv 推荐。", "Add a paper from Library, or open arXiv Recommendations."))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(snapshot.readingQueuePreview) { entry in
                                    Button {
                                        recordAction("open_queue_entry", targetID: entry.id)
                                        if let paperID = entry.paperID {
                                            appModel.selectPaper(id: paperID)
                                        }
                                        appModel.selectProjectSpaceTab("reading")
                                    } label: {
                                        ProjectDashboardQueueRow(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Button {
                                recordAction("open_reading", targetID: snapshot.projectID)
                                appModel.selectProjectSpaceTab("reading")
                            } label: {
                                Label(appModel.localized("打开 Reading", "Open Reading"), systemImage: "book")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            } else {
                HomeEmptyProjectDashboard(appModel: appModel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: appModel.currentProjectID ?? "__none__") {
            await reload(invalidating: true)
        }
        .onChange(of: appModel.papers) { _, _ in
            Task { await reload(invalidating: true) }
        }
        .onChange(of: appModel.todos) { _, _ in
            Task { await reload(invalidating: true) }
        }
        .onChange(of: appModel.markdownDocuments) { _, _ in
            Task { await reload(invalidating: true) }
        }
        .onChange(of: appModel.agentRunHistory) { _, _ in
            Task { await reload(invalidating: true) }
        }
        .onChange(of: appModel.agentCurrentRun) { _, _ in
            Task { await reload(invalidating: true) }
        }
        .onChange(of: appModel.researchQueueScopes) { _, _ in
            Task { await reload(invalidating: true) }
        }
        .onChange(of: appModel.readingPlanScopes) { _, _ in
            Task { await reload(invalidating: true) }
        }
    }

    @MainActor
    private func reload(invalidating: Bool) async {
        if invalidating {
            await aggregator.invalidate(reason: "project_dashboard_change")
        }

        do {
            let input = ProjectDashboardAggregationInput(
                workspaceID: workspace.id.path,
                project: appModel.currentResearchProject,
                papers: appModel.papers,
                todos: appModel.todos,
                markdownDocuments: appModel.markdownDocuments,
                agentRuns: agentRunsForAggregation,
                unsupportedClaims: unsupportedClaimsForAggregation,
                queueEntries: Array(appModel.researchQueueScopes.values.joined()),
                activeReadingPlan: appModel.currentProjectID.map { appModel.activeReadingPlanSummary(in: .project($0)) } ?? nil
            )
            let nextSnapshot = try await aggregator.snapshot(input: input)
            snapshot = nextSnapshot
            errorMessage = nil
            if let nextSnapshot {
                appModel.recordHomeDebugEvent("project_dashboard.render", payload: nextSnapshot.debugPayload)
                appModel.recordHomeDebugEvent("project_dashboard.stage_inferred", payload: .object([
                    "project_id": .string(nextSnapshot.projectID),
                    "stage": .string(nextSnapshot.stage.rawValue),
                    "rule": .string(nextSnapshot.stageRule)
                ]))
            }
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
        }
    }

    private var agentRunsForAggregation: [AgentRun] {
        guard let currentRun = appModel.agentCurrentRun else {
            return appModel.agentRunHistory
        }
        if appModel.agentRunHistory.contains(where: { $0.id == currentRun.id }) {
            return appModel.agentRunHistory
        }
        return [currentRun] + appModel.agentRunHistory
    }

    private var unsupportedClaimsForAggregation: [ClaimSummary] {
        let input = HomeAggregationInput(
            workspaceID: workspace.id.path,
            currentProjectID: appModel.currentProjectID,
            projects: appModel.researchProjects,
            papers: appModel.papers,
            todos: appModel.todos,
            markdownDocuments: appModel.markdownDocuments,
            agentRuns: agentRunsForAggregation,
            sessionEvents: appModel.agentSessionEvents,
            retrievalIndexStatus: appModel.agentRetrievalIndexStatus,
            moduleConfiguration: appModel.workspaceModuleConfiguration
        )
        return (try? HomeSnapshotBuilder().build(input: input).aiReview.unsupportedClaims) ?? []
    }

    private func recordAction(_ actionID: String, targetID: String) {
        appModel.recordHomeDebugEvent("home.panel.action", payload: .object([
            "panel": .string("project_dashboard"),
            "action_id": .string(actionID),
            "target_id": .string(targetID)
        ]))
    }
}

private struct ProjectDashboardQueueRow: View {
    let entry: ReadingQueueEntrySummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: statusSystemImage)
                .foregroundStyle(statusTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitleText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusSystemImage: String {
        switch entry.status {
        case .queued: return "tray"
        case .reading: return "book"
        case .finished: return "checkmark.seal"
        case .deferred: return "moon"
        case .dismissed: return "xmark.circle"
        }
    }

    private var statusTint: Color {
        switch entry.status {
        case .queued: return .blue
        case .reading: return .orange
        case .finished: return .green
        case .deferred: return .purple
        case .dismissed: return .secondary
        }
    }

    private var subtitleText: String {
        var parts: [String] = []
        parts.append(entry.status == .reading ? "Reading" : "Queued")
        if let externalKey = entry.externalKey, entry.paperID == nil {
            parts.append("external: \(externalKey)")
        }
        switch entry.source {
        case .recommendation: parts.append("from recommendation")
        case .graphTool: parts.append("from graph tool")
        case .paperStatus: parts.append("paper status sync")
        case .manual: break
        }
        return parts.joined(separator: " · ")
    }
}

private struct ProjectDashboardReadingPlanSummary: View {
    let plan: ReadingPlanSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(plan.completedSlotCount)/\(plan.totalSlotCount)")
                    .font(.headline.monospacedDigit())
                Text("finished")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(plan.estimatedMinutes)m")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(plan.slots.prefix(3)) { slot in
                HStack(spacing: 6) {
                    Image(systemName: slot.status == .finished ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(slot.status == .finished ? .green : .secondary)
                    Text(slot.displayTitle)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct ProjectDashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .lineLimit(1)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ProjectDashboardButtonRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectDashboardEmptyText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HomeEmptyProjectDashboard: View {
    @ObservedObject var appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appModel.localized("请选择或创建一个项目。", "Select or create a project."))
                .foregroundStyle(.secondary)
            Button {
                appModel.beginCreatingResearchProject()
            } label: {
                Label(appModel.localized("创建项目", "Create Project"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}