import OSLog
import SwiftUI

private let homePerformanceLogger = Logger(subsystem: "Lingyu-Xia.Sci-Station", category: "Performance")

struct HomeView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    @State private var aggregator = HomeAggregator()
    @State private var snapshot: HomeSnapshot?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var reloadTask: Task<Void, Never>?
    @State private var pendingInvalidationReasons: Set<String> = []

    var body: some View {
        contentWithPrimaryWatchers
            .onChange(of: appModel.homeAggregationRevision) { _, _ in
                scheduleReload(reason: "home_model_change")
            }
    }

    private var contentWithPrimaryWatchers: some View {
        content
            .task(id: workspace.id) {
                await reloadHome(invalidating: false, reason: "appear")
            }
            .onDisappear {
                reloadTask?.cancel()
                reloadTask = nil
                pendingInvalidationReasons.removeAll()
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
    private func scheduleReload(reason: String) {
        pendingInvalidationReasons.insert(reason)
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else {
                return
            }
            let reasons = pendingInvalidationReasons.sorted()
            pendingInvalidationReasons.removeAll()
            await reloadHome(invalidating: true, reason: reasons.isEmpty ? reason : reasons.joined(separator: ","))
        }
    }

    @MainActor
    private func reloadHome(invalidating: Bool, reason: String) async {
        let startedAt = Date()
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
        let durationMS = Date().timeIntervalSince(startedAt) * 1000
        homePerformanceLogger.debug("home.reload invalidating=\(invalidating, privacy: .public) reason=\(reason, privacy: .public) duration_ms=\(durationMS, privacy: .public)")
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
            retrievalIndexStatus: appModel.agentRetrievalIndexStatus,
            moduleConfiguration: appModel.workspaceModuleConfiguration,
            queueEntries: Array(appModel.researchQueueScopes.values.joined()),
            activeReadingPlan: appModel.activeReadingPlanSummaryForHome
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
