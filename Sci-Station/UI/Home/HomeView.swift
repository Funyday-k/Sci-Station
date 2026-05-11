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
            VStack(alignment: .leading, spacing: 28) {
                hero
                primaryContent
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HomeAuroraBackground().ignoresSafeArea())
    }

    @ViewBuilder
    private var primaryContent: some View {
        if let errorMessage {
            HomeUnavailableView(
                title: appModel.t(.homeTemporarilyUnavailable),
                message: errorMessage,
                retryTitle: appModel.t(.homeRetry)
            ) {
                Task { await reloadHome(invalidating: true, reason: "retry") }
            }
        } else if let snapshot {
            HomeWidgetDashboardView(snapshot: snapshot)
        } else {
            loadingState
        }
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(appModel.t(.homeLoadingSnapshot))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.04)), in: Capsule())
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                    Text(appModel.t(.routeHome))
                        .foregroundStyle(.primary)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.045)), in: Capsule())

                Text(workspace.displayName)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.primary, Color.primary.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(appModel.t(.homeDashboardSubtitle))
                    .font(.title3)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    HomeBadge(
                        systemImage: "square.grid.2x2",
                        text: appModel.workspaceModuleStatusSummary,
                        tint: .accentColor
                    )
                    HomeBadge(
                        systemImage: workflowReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        text: workflowReadyText,
                        tint: workflowReady ? .green : .orange
                    )
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button {
                Task { await reloadHome(invalidating: true, reason: "manual_refresh") }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(isLoading ? 360 : 0))
                    .animation(
                        isLoading
                            ? .linear(duration: 1.2).repeatForever(autoreverses: false)
                            : .default,
                        value: isLoading
                    )
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(appModel.t(.homeRefreshSnapshot))
            .disabled(isLoading)
        }
        .padding(.top, 4)
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
    @EnvironmentObject private var appModel: AppViewModel

    let systemImage: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint.opacity(0.85))
            Text(text)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.04)), in: Capsule())
    }
}

struct HomeUnavailableView: View {
    let title: String
    let message: String
    let retryTitle: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Label(retryTitle, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glass)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.orange.opacity(0.06)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }
}

/// Soft aurora-style backdrop that gives Liquid Glass surfaces something to refract.
/// Kept intentionally low-saturation so cards read as the primary content.
struct HomeAuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            appModel.liquidGlassTintColor.opacity(colorScheme == .dark ? 0.055 : 0.035)
            Color.white.opacity(colorScheme == .dark ? 0.015 : 0.045)
        }
    }
}
