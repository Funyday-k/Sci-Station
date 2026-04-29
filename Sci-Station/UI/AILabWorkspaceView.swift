import SwiftUI

struct AILabWorkspaceView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Lab")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("Global AI workspace for LLM settings, paper summaries, plan-only agent runs, approvals, and Copilot Bridge exports.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                    AILabMetricCard(title: "Provider", value: appModel.llmConfiguration.provider.rawValue, systemImage: "network")
                    AILabMetricCard(title: "Model", value: appModel.llmConfiguration.model, systemImage: "cpu")
                    AILabMetricCard(title: "Projects", value: "\(appModel.activeResearchProjects.count)", systemImage: "folder")
                    AILabMetricCard(title: "Papers", value: "\(appModel.papers.count)", systemImage: "books.vertical")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DeepSeek")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Sci-Station uses the OpenAI-compatible endpoint by default. Configure the API key in Settings, then use paper Inspector actions such as Summarize with LLM.")
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Use DeepSeek Flash") {
                                appModel.useDeepSeekDefaults(model: "deepseek-v4-flash")
                                appModel.selectSection(.settings)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Use DeepSeek Pro") {
                                appModel.useDeepSeekDefaults(model: "deepseek-v4-pro")
                                appModel.selectSection(.settings)
                            }
                            .buttonStyle(.bordered)

                            Button("Open Settings") {
                                appModel.selectSection(.settings)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                AgentPanelView(workspace: workspace)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Agent Workspace")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Agent runs and Copilot Bridge files are stored globally under .sci-station/agent so they can work across projects without mixing project data.")
                            .foregroundStyle(.secondary)

                        WorkspacePathRow(label: "Run Log", value: workspace.fileURL(for: ".sci-station/agent/runs.jsonl").path)
                        WorkspacePathRow(label: "Copilot Bridge", value: workspace.directoryURL(for: ".sci-station/agent/copilot-bridge").path)
                        WorkspacePathRow(label: "Current Project", value: appModel.currentResearchProject?.name ?? "None")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AILabMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(title)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AgentPanelView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                header
                AgentContextSummaryView(snapshot: appModel.agentWorkspaceSnapshot, tools: appModel.agentToolDefinitions)
                goalEditor
                actionButtons
                statusMessages

                if let run = appModel.agentCurrentRun {
                    AgentPlanSummaryView(run: run)
                    AgentToolApprovalListView(run: run)
                } else {
                    ContentUnavailableView(
                        "No Agent Plan",
                        systemImage: "wand.and.stars",
                        description: Text("Enter a goal and generate a plan-only run before approving any workspace-writing tools.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                }

                AgentRunHistoryView(runs: appModel.agentRunHistory)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent Panel")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Generate a plan first, approve individual tool calls, then run only the approved workspace-writing actions.")
                .foregroundStyle(.secondary)
        }
    }

    private var goalEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Goal")
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
            Text("Example: Create follow-up todos for this project based on open papers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                appModel.generateAgentPlan()
            } label: {
                Label(appModel.isPlanningAgentRun ? "Generating Plan..." : "Generate Plan Only", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.isPlanningAgentRun || appModel.isExecutingAgentTools)

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
                appModel.refreshAgentContext()
            } label: {
                Label("Refresh Context", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(appModel.isRefreshingAgentContext)
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
        if let export = appModel.agentBridgeExport {
            VStack(alignment: .leading, spacing: 4) {
                WorkspacePathRow(label: "Bridge Prompt", value: export.promptRelativePath)
                WorkspacePathRow(label: "Bridge Manifest", value: export.manifestRelativePath)
            }
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
    let runs: [AgentRun]

    var body: some View {
        GroupBox("Recent Runs") {
            VStack(alignment: .leading, spacing: 8) {
                if runs.isEmpty {
                    Text("No agent run history yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(runs, id: \.id) { run in
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
                            Text(run.currentProjectID ?? "No project")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
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
