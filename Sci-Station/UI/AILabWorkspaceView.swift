import SwiftUI

struct AILabWorkspaceView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AILabCompactHeaderView()

                AgentPanelView(workspace: workspace)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AILabCompactHeaderView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Lab")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Text("Conversation follows the project selected in the Sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Label(appModel.agentConversationTitle, systemImage: "folder")
                Divider()
                    .frame(height: 18)
                Label(appModel.llmConfiguration.model, systemImage: "cpu")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Divider()
                    .frame(height: 18)
                Label(appModel.agentProviderSummary, systemImage: "sparkles")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    appModel.selectSection(.settings)
                } label: {
                    Label("AI Settings", systemImage: "gearshape")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08), in: Capsule())
        }
    }
}

private struct AgentPanelView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    @State private var isContextExpanded = false
    @State private var isAgentDetailsExpanded = false
    @State private var isPlanExpanded = false
    @State private var isPermissionDockExpanded = true
    @State private var isHooksExpanded = false
    @State private var isMCPExpanded = false
    @State private var isPresetExpanded = false
    @State private var isHistoryExpanded = false
    @State private var isBridgeExpanded = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusMessages
                threadStrip
                goalEditor
                actionButtons
                AgentConversationTimelineView(
                    thread: appModel.activeAgentThread,
                    runs: appModel.agentConversationRuns,
                    currentRun: appModel.agentCurrentRun,
                    events: appModel.agentTimelineItems
                )

                DisclosureGroup("Agent Panel Details", isExpanded: $isAgentDetailsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        AgentPlatformStatusView()

                        DisclosureGroup("Preset Manager", isExpanded: $isPresetExpanded) {
                            AgentPresetManagerView()
                        }

                        DisclosureGroup("Hook Activity", isExpanded: $isHooksExpanded) {
                            AgentHookActivityView()
                        }

                        DisclosureGroup("MCP Servers", isExpanded: $isMCPExpanded) {
                            AgentMCPServerStatusView()
                        }

                        DisclosureGroup("Context", isExpanded: $isContextExpanded) {
                            AgentContextSummaryView(snapshot: appModel.agentWorkspaceSnapshot, tools: appModel.agentToolDefinitions)
                        }

                        if let run = appModel.agentCurrentRun {
                            DisclosureGroup("Current Plan", isExpanded: $isPlanExpanded) {
                                AgentPlanSummaryView(run: run)
                            }

                            DisclosureGroup("Permission Dock", isExpanded: $isPermissionDockExpanded) {
                                AgentPermissionDockView(run: run)
                            }
                        }

                        if appModel.agentBridgeExport != nil {
                            DisclosureGroup("Copilot Bridge Export", isExpanded: $isBridgeExpanded) {
                                bridgeExportDetails
                            }
                        }

                        DisclosureGroup("Conversation History", isExpanded: $isHistoryExpanded) {
                            AgentRunHistoryView(
                                currentRuns: appModel.agentConversationRuns,
                                orphanRuns: appModel.agentOrphanRuns
                            )
                        }
                    }
                    .padding(.top, 8)
                }

                if appModel.agentConversationRuns.isEmpty, appModel.agentCurrentRun == nil {
                    ContentUnavailableView(
                        "No Messages Yet",
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text("Enter a prompt above. The conversation uses the project selected in the Sidebar.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $appModel.isShowingAgentThreadRename) {
            AgentThreadRenameSheet()
                .environmentObject(appModel)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent Panel")
                .font(.headline)
                .fontWeight(.semibold)
            Text("Project: \(appModel.agentConversationTitle). Use the Sidebar to switch project conversations.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var threadStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Threads")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
                Text("New Chat is saved after the first successful plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let pendingThread = appModel.pendingAgentThread {
                        threadButton(title: pendingThread.title, subtitle: "Draft", isActive: appModel.activeAgentThreadID == pendingThread.id) {
                            // The pending thread is already the active session-only draft.
                        }
                        .contextMenu {
                            Button("Discard Draft", role: .destructive) {
                                appModel.discardPendingAgentThread()
                            }
                        }
                    }

                    ForEach(appModel.agentThreads) { thread in
                        threadButton(
                            title: thread.title,
                            subtitle: "\(thread.runIDs.count) runs",
                            isActive: appModel.activeAgentThreadID == thread.id
                        ) {
                            appModel.selectAgentThread(thread)
                        }
                        .contextMenu {
                            Button("Rename Thread") {
                                appModel.beginRenameAgentThread(thread)
                            }
                            Button("Archive Thread", role: .destructive) {
                                appModel.archiveAgentThread(thread)
                            }
                        }
                    }

                    if appModel.agentThreads.isEmpty, appModel.pendingAgentThread == nil {
                        Text("No saved threads yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func threadButton(title: String, subtitle: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        if isActive {
            Button(action: action) {
                threadButtonLabel(title: title, subtitle: subtitle)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(action: action) {
                threadButtonLabel(title: title, subtitle: subtitle)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func threadButtonLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 110, alignment: .leading)
    }

    private var goalEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(.headline)
            TextEditor(text: $appModel.agentGoal)
                .font(.body)
                .frame(minHeight: 82)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.18))
                }
            Text("Example: Review this project's open papers and propose the next three safe actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                appModel.generateAgentPlan()
            } label: {
                Label(appModel.isPlanningAgentRun ? "Thinking..." : "Send / Generate Plan", systemImage: "paperplane")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(appModel.isPlanningAgentRun || appModel.isExecutingAgentTools)

            Button {
            } label: {
                Label("Auto Run Loop", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .disabled(true)
            .help("Reserved for a future Codex-style loop. It will only auto-run read-only tools; workspace writes still require approval. Stops will include max rounds, max tool calls, repeated failures, approval waits, and manual stop.")

            Button {
                appModel.executeApprovedAgentTools()
            } label: {
                Label(appModel.isExecutingAgentTools ? "Running..." : "Run Approved Tools", systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)
            .disabled(appModel.agentCurrentRun?.plan.toolCalls.isEmpty ?? true || appModel.isPlanningAgentRun || appModel.isExecutingAgentTools)

            Button {
                appModel.exportAgentCopilotBridge()
            } label: {
                Label(appModel.isExportingAgentBridge ? "Exporting..." : "Export Copilot Bridge", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(appModel.isExportingAgentBridge)

            Button {
                appModel.startNewAgentConversation()
            } label: {
                Label("New Chat", systemImage: "plus.bubble")
            }
            .buttonStyle(.bordered)

            Button {
                appModel.refreshAgentContext()
            } label: {
                Label("Refresh Context", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(appModel.isRefreshingAgentContext)
        }
    }

    @ViewBuilder
    private var bridgeExportDetails: some View {
        if let export = appModel.agentBridgeExport {
            VStack(alignment: .leading, spacing: 4) {
                WorkspacePathRow(label: "Bridge Prompt", value: export.promptRelativePath)
                WorkspacePathRow(label: "Bridge Manifest", value: export.manifestRelativePath)
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let error = appModel.agentErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
        if let message = appModel.agentStatusMessage {
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}

private struct AgentThreadRenameSheet: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Thread")
                .font(.headline)

            TextField("Thread title", text: $appModel.agentThreadRenameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 320)

            HStack {
                Spacer()
                Button("Cancel") {
                    appModel.isShowingAgentThreadRename = false
                    dismiss()
                }
                Button("Rename") {
                    appModel.renamePendingAgentThreadFromDraft()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

private struct AgentConversationTimelineView: View {
    let thread: AgentThread?
    let runs: [AgentRun]
    let currentRun: AgentRun?
    let events: [AgentSessionTimelineItem]

    private var visibleRuns: [AgentRun] {
        if let currentRun, !runs.contains(where: { $0.id == currentRun.id }) {
            return [currentRun] + Array(runs.prefix(4))
        }

        return Array(runs.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Thread Timeline")
                    .font(.headline)
                if let thread {
                    Text(thread.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if events.isEmpty, visibleRuns.isEmpty {
                Text("No messages in this thread yet. Try: Review this project's open papers and propose the next three safe actions.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else if !events.isEmpty {
                ForEach(events) { item in
                    AgentSessionEventRowView(item: item)
                }
            } else {
                ForEach(visibleRuns, id: \.id) { run in
                    AgentConversationRunCard(run: run, isCurrent: currentRun?.id == run.id)
                }
            }
        }
    }
}

private struct AgentSessionEventRowView: View {
    let item: AgentSessionTimelineItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(item.kind == .toolCallFailed ? .red : .primary)
                    .textSelection(.enabled)
                if let payload = item.payloadPreview {
                    Text(payload)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch item.kind {
        case .userMessage:
            return "person.crop.circle"
        case .assistantMessage, .reasoningSummary:
            return "sparkles"
        case .permissionRequested:
            return "questionmark.shield"
        case .permissionResolved:
            return "checkmark.shield"
        case .toolCallStarted:
            return "play.circle"
        case .toolCallCompleted:
            return "checkmark.circle"
        case .toolCallFailed:
            return "exclamationmark.triangle"
        case .hookResult:
            return "link"
        case .compactionSummary:
            return "text.badge.checkmark"
        }
    }

    private var iconColor: Color {
        switch item.kind {
        case .toolCallFailed:
            return .red
        case .permissionRequested:
            return .orange
        case .permissionResolved, .toolCallCompleted:
            return .green
        case .hookResult:
            return .purple
        default:
            return .secondary
        }
    }
}

private struct AgentConversationRunCard: View {
    let run: AgentRun
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Label("You", systemImage: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(run.goal)
                    .font(.callout)
                    .lineLimit(3)
                Spacer(minLength: 0)
                if isCurrent {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Label("Agent", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.plan.title?.nilIfEmpty ?? "Plan")
                        .fontWeight(.semibold)
                    Text(run.plan.summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text("\(run.mode.rawValue) · \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(isCurrent ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct AgentPlatformStatusView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        GroupBox("Agent Platform") {
            VStack(alignment: .leading, spacing: 10) {
                WorkspacePathRow(label: "Core", value: appModel.agentPlatformSummary)
                WorkspacePathRow(label: "Provider", value: appModel.agentProviderSummary)
                WorkspacePathRow(label: "Provider V2", value: appModel.agentProviderV2Summary)
                WorkspacePathRow(label: "Presets", value: appModel.agentPresetSummary)
                WorkspacePathRow(label: "Permissions", value: appModel.agentPermissionSummary)
                WorkspacePathRow(label: "Hooks", value: appModel.agentHookSummary)
                WorkspacePathRow(label: "MCP", value: appModel.agentMCPStatusSummary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct AgentContextSummaryView: View {
    let snapshot: AgentWorkspaceSnapshot?
    let tools: [AgentToolDefinition]

    var body: some View {
        GroupBox("Current Context") {
            VStack(alignment: .leading, spacing: 10) {
                WorkspacePathRow(label: "Root", value: snapshot?.rootName ?? "-")
                WorkspacePathRow(label: "Current Project", value: snapshot?.currentProject?.name ?? "None")
                WorkspacePathRow(label: "Project Papers", value: "\(snapshot?.projectPapers.count ?? 0)")
                WorkspacePathRow(label: "Project Open Todos", value: "\(snapshot?.projectOpenTodos.count ?? 0)")
                WorkspacePathRow(label: "Available Tools", value: tools.map(\.name).joined(separator: ", ").nilIfEmpty ?? "-")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct AgentPlanSummaryView: View {
    let run: AgentRun

    var body: some View {
        GroupBox("Plan") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.plan.title?.nilIfEmpty ?? "Plan Only")
                        .font(.headline)
                    Text(run.plan.summary)
                        .foregroundStyle(.secondary)
                }

                if let risk = run.plan.risk?.nilIfEmpty {
                    Label(risk, systemImage: "exclamationmark.shield")
                        .foregroundStyle(.secondary)
                }

                if !run.plan.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Steps")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        ForEach(Array(run.plan.steps.enumerated()), id: \.offset) { index, step in
                            Text("\(index + 1). \(step)")
                        }
                    }
                }

                if let finalResponse = run.plan.finalResponseDraft?.nilIfEmpty {
                    Text(finalResponse)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct AgentPermissionDockView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let run: AgentRun

    var body: some View {
        GroupBox("Permission Dock") {
            VStack(alignment: .leading, spacing: 12) {
                let items = appModel.agentPermissionDockItems(for: run)
                if items.isEmpty {
                    Text("This plan does not request any tool calls.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        AgentPermissionDockRow(item: item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct AgentPermissionDockRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let item: AgentPermissionDockItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                permissionStateLabel

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.headline)
                    Text(item.summary)
                        .foregroundStyle(.secondary)
                    Text("\(item.permissionKey) / \(item.risk.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.matchedPolicyDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.argumentsPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if !item.pathPreview.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Path Preview")
                        .font(.caption)
                        .fontWeight(.semibold)
                    ForEach(item.pathPreview, id: \.self) { path in
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 22)
            }

            HStack(spacing: 8) {
                Button {
                    appModel.setAgentToolApproval(callID: item.id, isApproved: true)
                } label: {
                    Label("Allow Once", systemImage: "checkmark.shield")
                }
                .controlSize(.small)
                .disabled(item.approvalState == .completed || item.approvalState == .deniedByPolicy)

                Button(role: .destructive) {
                    appModel.setAgentToolDenied(callID: item.id, isDenied: true)
                } label: {
                    Label("Deny", systemImage: "xmark.octagon")
                }
                .controlSize(.small)
                .disabled(item.approvalState == .completed)

                Toggle(
                    "Session Draft",
                    isOn: Binding(
                        get: { appModel.agentToolSessionApprovalDrafts.contains(item.id) },
                        set: { appModel.setAgentSessionApprovalDraft(callID: item.id, isEnabled: $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Spacer(minLength: 0)
            }

            TextField(
                "Correction feedback",
                text: Binding(
                    get: { appModel.agentCorrectionFeedback(callID: item.id) },
                    set: { appModel.updateAgentCorrectionFeedback(callID: item.id, text: $0) }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var permissionStateLabel: some View {
        Label(stateTitle, systemImage: stateIcon)
            .font(.caption)
            .foregroundStyle(stateColor)
            .frame(minWidth: 120, alignment: .leading)
    }

    private var stateTitle: String {
        switch item.approvalState {
        case .autoAllowed:
            return "Auto-allow"
        case .waitingForApproval:
            return "Needs approval"
        case .allowedOnce:
            return "Allow once"
        case .denied:
            return "Denied"
        case .deniedByPolicy:
            return "Policy deny"
        case .sessionApprovalDraft:
            return "Session draft"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }

    private var stateIcon: String {
        switch item.approvalState {
        case .autoAllowed, .allowedOnce, .completed:
            return "checkmark.circle"
        case .waitingForApproval, .sessionApprovalDraft:
            return "questionmark.circle"
        case .denied, .deniedByPolicy, .failed:
            return "exclamationmark.triangle"
        }
    }

    private var stateColor: Color {
        switch item.approvalState {
        case .autoAllowed, .allowedOnce, .completed:
            return .green
        case .waitingForApproval, .sessionApprovalDraft:
            return .orange
        case .denied, .deniedByPolicy, .failed:
            return .red
        }
    }
}

private struct AgentHookActivityView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        GroupBox("Hook Activity") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enabled Hooks")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    ForEach(appModel.agentHookActivitySummary.hooks) { hook in
                        HStack(alignment: .top, spacing: 8) {
                            Toggle(
                                isOn: Binding(
                                    get: { hook.isEnabled && !appModel.agentDisabledHookIDs.contains(hook.id) },
                                    set: { appModel.setAgentHook(hook.id, isEnabled: $0) }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(hook.eventName.rawValue) / \(hook.id)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(hook.message ?? hook.additionalContext ?? hook.matcher ?? "No hook message configured.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Results")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if appModel.agentHookActivitySummary.results.isEmpty {
                        Text("No hook results recorded for the current timeline yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appModel.agentHookActivitySummary.results) { result in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(result.eventName?.rawValue ?? "Hook")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    if let decision = result.permissionDecision {
                                        Text(decision.rawValue)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12), in: Capsule())
                                    }
                                    Spacer(minLength: 0)
                                    Text(result.createdAt.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(result.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if let additionalContext = result.additionalContext {
                                    Text(additionalContext)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct AgentMCPServerStatusView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        GroupBox("MCP Server Status") {
            VStack(alignment: .leading, spacing: 12) {
                WorkspacePathRow(label: "Product Templates", value: ".sci-ai/sci-station/ tracked, no raw secrets")
                WorkspacePathRow(label: "Local Config", value: ".sci-ai/workspace.local/ local-only, ignored by git")

                statusSection(title: "Product Preset", statuses: appModel.agentProductMCPServerStatuses, emptyText: "No product MCP template is available in this root.")
                statusSection(title: "Local Workspace", statuses: appModel.agentLocalMCPServerStatuses, emptyText: "No local workspace MCP config is present.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func statusSection(title: String, statuses: [AgentMCPServerStatus], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            if statuses.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(statuses) { status in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(status.displayName, systemImage: status.isEnabled ? "checkmark.circle" : "pause.circle")
                                .foregroundStyle(status.isEnabled ? .green : .secondary)
                            Spacer(minLength: 0)
                            Text(status.source.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        WorkspacePathRow(label: "Endpoint", value: status.endpointSummary)
                        WorkspacePathRow(label: "Allowed Tools", value: status.allowedTools.joined(separator: ", ").nilIfEmpty ?? "not restricted")
                        WorkspacePathRow(label: "Timeout", value: "\(Int(status.timeoutSeconds))s")
                        WorkspacePathRow(label: "Credential Refs", value: "\(status.credentialReferenceCount)")
                        WorkspacePathRow(label: "Permission Layer", value: status.sideEffectsRequirePermission ? "side-effect tools require approval" : "read-only only")
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct AgentPresetManagerView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        GroupBox("Preset Manager") {
            VStack(alignment: .leading, spacing: 12) {
                if let preset = appModel.agentPresetDetails {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(preset.name) \(preset.version)")
                            .font(.headline)
                        Text(preset.description)
                            .foregroundStyle(.secondary)
                        WorkspacePathRow(label: "Manifest", value: preset.manifestRelativePath)
                    }

                    presetList(title: "Commands", values: preset.commands.map { "\($0.slashCommand) - \($0.title)" })
                    presetList(title: "Skills", values: preset.skills.map { "\($0.id) - \($0.description)" })
                    presetList(title: "Hooks", values: preset.hooks.map { "\($0.eventName.rawValue) - \($0.id)" })
                    presetList(title: "MCP Servers", values: preset.mcpServers.map { "\($0.id) - \($0.endpointSummary)" })

                    if preset.validationIssues.isEmpty {
                        Label("Validation passed", systemImage: "checkmark.seal")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        presetList(title: "Validation Issues", values: preset.validationIssues.map { "\($0.field): \($0.message)" })
                    }
                } else {
                    Text("No tracked research-core preset was found for the current root.")
                        .foregroundStyle(.secondary)
                }

                Text("Local overrides stay in .sci-ai/workspace.local/ or non-sensitive .sci-station/agent/ state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func presetList(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            if values.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct AgentRunHistoryView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let currentRuns: [AgentRun]
    let orphanRuns: [AgentRun]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            historySection(title: "Current Thread Runs", runs: currentRuns, isOrphan: false)

            Divider()

            historySection(title: "Unthreaded Project Runs", runs: orphanRuns, isOrphan: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func historySection(title: String, runs: [AgentRun], isOrphan: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            if runs.isEmpty {
                Text(isOrphan ? "No unthreaded runs for this project." : "No runs in this thread yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(runs, id: \.id) { run in
                    historyRow(run, isOrphan: isOrphan)
                    Divider()
                }
            }
        }
    }

    private func historyRow(_ run: AgentRun, isOrphan: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.goal)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(run.mode.rawValue) · \(status(for: run)) · \(run.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                appModel.openAgentRun(run)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu("More") {
                Button("Duplicate Prompt to New Chat") {
                    appModel.duplicateAgentRunPromptToNewChat(run)
                }

                if isOrphan {
                    Button("Create Thread from Run") {
                        appModel.createAgentThread(from: run)
                    }
                    Button("Add to Current Thread") {
                        appModel.addAgentRunToCurrentThread(run)
                    }
                }
            }
            .menuStyle(.button)
            .controlSize(.small)
        }
    }

    private func status(for run: AgentRun) -> String {
        guard run.mode == .executeApproved else {
            return "Plan only"
        }
        guard !run.toolResults.isEmpty else {
            return "No tools"
        }
        return run.toolResults.allSatisfy(\.succeeded) ? "Succeeded" : "Needs review"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
