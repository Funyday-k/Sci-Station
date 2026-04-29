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
    @State private var isToolsExpanded = false
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
                    currentRun: appModel.agentCurrentRun
                )

                DisclosureGroup("Agent Panel Details", isExpanded: $isAgentDetailsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        DisclosureGroup("Context", isExpanded: $isContextExpanded) {
                            AgentContextSummaryView(snapshot: appModel.agentWorkspaceSnapshot, tools: appModel.agentToolDefinitions)
                        }

                        if let run = appModel.agentCurrentRun {
                            DisclosureGroup("Current Plan", isExpanded: $isPlanExpanded) {
                                AgentPlanSummaryView(run: run)
                            }

                            DisclosureGroup("Tool Calls / Approvals", isExpanded: $isToolsExpanded) {
                                AgentToolApprovalListView(run: run)
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

            if visibleRuns.isEmpty {
                Text("No messages in this thread yet. Try: Review this project's open papers and propose the next three safe actions.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(visibleRuns, id: \.id) { run in
                    AgentConversationRunCard(run: run, isCurrent: currentRun?.id == run.id)
                }
            }
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

private struct AgentToolApprovalListView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let run: AgentRun

    var body: some View {
        GroupBox("Tool Calls") {
            VStack(alignment: .leading, spacing: 12) {
                if run.plan.toolCalls.isEmpty {
                    Text("This plan does not request any tool calls.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(run.plan.toolCalls, id: \.id) { call in
                        AgentToolCallRow(
                            call: call,
                            definition: appModel.agentToolDefinition(for: call),
                            result: run.toolResults.first { $0.callID == call.id }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

private struct AgentToolCallRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let call: AgentToolCall
    let definition: AgentToolDefinition?
    let result: AgentToolResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if definition?.requiresConfirmation == true {
                    Toggle(
                        "Approve",
                        isOn: Binding(
                            get: { appModel.agentToolApprovals.contains(call.id) },
                            set: { appModel.setAgentToolApproval(callID: call.id, isApproved: $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                } else {
                    Label("No approval needed", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(call.toolName)
                        .font(.headline)
                    if let definition {
                        Text(definition.summary)
                            .foregroundStyle(.secondary)
                    }
                    Text(call.argumentsJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if let result {
                VStack(alignment: .leading, spacing: 4) {
                    Label(result.succeeded ? "Succeeded" : "Not Run / Failed", systemImage: result.succeeded ? "checkmark.circle" : "exclamationmark.circle")
                    Text(result.message)
                        .foregroundStyle(.secondary)
                    if let error = result.errorMessage?.nilIfEmpty {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                    if !result.modifiedPaths.isEmpty {
                        Text("Modified: \(result.modifiedPaths.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
