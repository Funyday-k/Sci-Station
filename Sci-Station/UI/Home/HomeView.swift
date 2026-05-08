import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    @State private var aggregator = HomeAggregator()
    @State private var snapshot: HomeSnapshot?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        content
            .task(id: workspace.id) {
                await reloadHome(invalidating: false, reason: "appear")
            }
            .onChange(of: appModel.todos) { _, _ in
                Task { await reloadHome(invalidating: true, reason: "todo_change") }
            }
            .onChange(of: appModel.papers) { _, _ in
                Task { await reloadHome(invalidating: true, reason: "paper_change") }
            }
            .onChange(of: appModel.researchProjects) { _, _ in
                Task { await reloadHome(invalidating: true, reason: "project_change") }
            }
            .onChange(of: appModel.markdownDocuments) { _, _ in
                Task { await reloadHome(invalidating: true, reason: "wiki_change") }
            }
            .onChange(of: appModel.agentRunHistory) { _, _ in
                Task { await reloadHome(invalidating: true, reason: "draft_change") }
            }
            .onChange(of: appModel.agentCurrentRun) { _, _ in
                Task { await reloadHome(invalidating: true, reason: "draft_change") }
            }
            .onChange(of: appModel.agentSessionEvents) { _, _ in
                Task { await reloadHome(invalidating: true, reason: "agent_event_change") }
            }
            .onChange(of: appModel.agentRetrievalIndexStatus) { _, _ in
                Task { await reloadHome(invalidating: true, reason: "retrieval_change") }
            }
            .onChange(of: appModel.workspaceModuleConfiguration) { _, _ in
                Task { await reloadHome(invalidating: true, reason: "module_config_change") }
            }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                primaryContent
                secondaryContent
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var primaryContent: some View {
        if let errorMessage {
            HomeUnavailableView(
                title: appModel.localized("Home 暂时不可用", "Home temporarily unavailable"),
                message: errorMessage,
                retryTitle: appModel.localized("重试", "Retry")
            ) {
                Task { await reloadHome(invalidating: true, reason: "retry") }
            }
        } else if let snapshot {
            homePanels(for: snapshot)
        } else {
            loadingState
        }
    }

    private func homePanels(for snapshot: HomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            TodayPanelView(snapshot: snapshot, appModel: appModel)
            ActiveProjectsPanelView(projects: snapshot.activeProjects, moduleAvailability: snapshot.moduleAvailability, appModel: appModel)
            AIReviewPanelView(aiReview: snapshot.aiReview, moduleAvailability: snapshot.moduleAvailability, appModel: appModel)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(appModel.localized("正在构建 Home 快照...", "Building Home snapshot..."))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 18)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(workspace.displayName)
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(appModel.localized("今天的研究主控台", "Today's research command center"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    Task { await reloadHome(invalidating: true, reason: "manual_refresh") }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(appModel.localized("刷新 Home 快照", "Refresh Home snapshot"))
                .disabled(isLoading)
            }

            HStack(spacing: 8) {
                HomeBadge(systemImage: "square.grid.2x2", text: appModel.workspaceModuleStatusSummary)
                HomeBadge(systemImage: workflowReady ? "checkmark.seal" : "exclamationmark.triangle", text: workflowReadyText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var secondaryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appModel.localized("次要视图", "Secondary Views"))
                .font(.title2)
                .fontWeight(.semibold)

            DashboardCalendarView(selectedDate: Binding(
                get: { appModel.selectedDashboardDate },
                set: { appModel.selectDashboardDate($0) }
            ))
            .frame(maxWidth: .infinity, alignment: .topLeading)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], alignment: .leading, spacing: 16) {
                DashboardPaperList(title: appModel.localized("最近添加", "Recently Added"), papers: appModel.recentPapers)
                DashboardPaperList(title: appModel.localized("最近阅读", "Recently Read"), papers: appModel.recentlyReadPapers)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workflowReady: Bool {
        !appModel.enabledAgentWorkflowIDs.isEmpty
    }

    private var workflowReadyText: String {
        workflowReady
            ? appModel.localized("Workflow Ready", "Workflow Ready")
            : appModel.localized("无可用工作流", "No workflows available")
    }

    @MainActor
    private func reloadHome(invalidating: Bool, reason: String) async {
        if invalidating {
            await aggregator.invalidate(reason: reason)
            appModel.recordHomeDebugEvent("home.cache.invalidate", payload: .object([
                "reason": .string(reason)
            ]))
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let nextSnapshot = try await aggregator.snapshot(input: aggregationInput)
            snapshot = nextSnapshot
            errorMessage = nil
            appModel.recordHomeDebugEvent("home.aggregate", payload: nextSnapshot.debugPayload)
        } catch {
            snapshot = nil
            errorMessage = error.localizedDescription
            appModel.recordHomeDebugEvent("home.aggregate.error", payload: .object([
                "panel": .string("home"),
                "reason": .string(error.localizedDescription)
            ]))
        }
    }

    private var aggregationInput: HomeAggregationInput {
        HomeAggregationInput(
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
}

struct HomeBadge: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct HomeUnavailableView: View {
    let title: String
    let message: String
    let retryTitle: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Label(retryTitle, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}