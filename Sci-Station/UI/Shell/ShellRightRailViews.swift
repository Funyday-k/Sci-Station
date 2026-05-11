import SwiftUI

struct ShellRightRailView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace?

    @ViewBuilder
    var body: some View {
        if let workspace {
            Group {
                switch appModel.effectiveRightRailMode {
                case .inspector:
                    ContextInspectorRail(workspace: workspace)
                case .ai:
                    GlobalAISidePanel(workspace: workspace, context: appModel.currentWorkspaceContextSnapshot)
                case .hidden:
                    CollapsedShellRailRestoreButton(
                        showAI: { appModel.openGlobalAIPanel(source: "collapsed_rail") },
                        showInspector: { appModel.showContextInspector(source: "collapsed_rail") }
                    )
                }
            }
            .background(ShellRailBackground())
        } else {
            EmptyRightRailView()
        }
    }
}

struct ContextInspectorRail: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        VStack(spacing: 0) {
            ShellRailHeader(
                title: inspectorTitle,
                subtitle: appModel.currentWorkspaceContextSnapshot.displayTitle,
                close: { appModel.hideRightRail(source: "inspector_close") },
                openAI: { appModel.openGlobalAIPanel(source: "inspector_header") }
            )

            Divider()

            inspectorBody
        }
    }

    @ViewBuilder
    private var inspectorBody: some View {
        if shouldShowPaperInspector {
            PaperInspectorView(workspace: workspace)
        } else if shouldShowWikiInspector {
            WikiInspectorView(workspace: workspace)
        } else if appModel.selectedSection == .pdfReader || appModel.currentWorkspaceContextSnapshot.projectTabID == "pdf-reader" {
            PDFReaderRailPlaceholder()
        } else {
            ContextActionsRail(workspace: workspace)
        }
    }

    private var inspectorTitle: String {
        if shouldShowPaperInspector { return "Paper Inspector" }
        if shouldShowWikiInspector { return "Wiki Inspector" }
        if appModel.selectedSection == .pdfReader || appModel.currentWorkspaceContextSnapshot.projectTabID == "pdf-reader" { return "PDF Context" }
        return "Context"
    }

    private var shouldShowPaperInspector: Bool {
        appModel.selectedSection == .library || appModel.currentWorkspaceContextSnapshot.projectTabID == "papers"
    }

    private var shouldShowWikiInspector: Bool {
        appModel.selectedSection == .wiki || appModel.currentWorkspaceContextSnapshot.projectTabID == "wiki"
    }
}

struct GlobalAISidePanel: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    let context: WorkspaceContextSnapshot

    var body: some View {
        VStack(spacing: 0) {
            ShellRailHeader(
                title: "AI",
                subtitle: context.displayTitle,
                close: { appModel.hideRightRail(source: "ai_panel_close") },
                openAI: nil
            )

            GlobalAIContextActionBar(context: context)

            AgentPanelView(workspace: workspace, isCompact: true)
        }
    }
}

private struct ShellRailHeader: View {
    let title: String
    let subtitle: String
    let close: () -> Void
    let openAI: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if let openAI {
                Button(action: openAI) {
                    Label("AI", systemImage: "sparkles")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Open AI")
            }
            Button(action: close) {
                Label("Hide", systemImage: "sidebar.right")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Hide rail")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct ContextActionsRail: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                compactContextBlock

                Button {
                    appModel.openGlobalAIPanel(source: "context_action")
                } label: {
                    Label("Ask About View", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button {
                    appModel.refreshCurrentWorkspaceView()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                if appModel.selectedSection == .projects {
                    Button {
                        appModel.beginCreatingResearchProject()
                    } label: {
                        Label("New Project", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                if appModel.selectedSection == .calendar || appModel.selectedSection == .tasks {
                    Button {
                        appModel.selectGlobalTodos()
                    } label: {
                        Label("All Todos", systemImage: "checklist")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    appModel.revealCurrentWorkspaceInFinder()
                } label: {
                    Label("Reveal Workspace", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var compactContextBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appModel.currentWorkspaceContextSnapshot.topLevelSectionID)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(appModel.currentWorkspaceContextSnapshot.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(workspace.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PDFReaderRailPlaceholder: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(appModel.selectedPaperDraft?.displayTitle ?? "PDF Reader", systemImage: "doc.viewfinder")
                .font(.headline)
                .lineLimit(3)

            Button {
                appModel.focusSearchForCurrentSection()
            } label: {
                Label("Search PDF", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                appModel.openGlobalAIPanel(source: "pdf_context")
            } label: {
                Label("Ask About PDF", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Text("Annotation rail reserved for P43.7")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct GlobalAIContextActionBar: View {
    @EnvironmentObject private var appModel: AppViewModel

    let context: WorkspaceContextSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedTextPreview = context.selectedTextPreview {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected text from page \(context.pdfPageIndex.map(String.init) ?? "-")")
                        .font(.caption.weight(.semibold))
                    Text(selectedTextPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        appModel.agentGoal = "Ask about this view.\n\n\(promptContext)"
                    } label: {
                        Label("Ask", systemImage: "bubble.left.and.text.bubble.right")
                    }

                    Button {
                        appModel.agentGoal = "Summarize the current selection.\n\n\(promptContext)"
                    } label: {
                        Label("Summarize", systemImage: "text.quote")
                    }
                    .disabled(context.selectedTextPreview == nil)

                    Button {
                        appModel.agentGoal = "Draft a todo from the current selection. Do not write it yet.\n\n\(promptContext)"
                    } label: {
                        Label("Todo Draft", systemImage: "checklist")
                    }
                    .disabled(context.selectedTextPreview == nil)
                }
                .font(.caption)
                .buttonStyle(.glass)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background {
            Color(nsColor: .windowBackgroundColor).opacity(0.68)
            Color.secondary.opacity(0.045)
        }
    }

    private var promptContext: String {
        var lines = ["Context: \(context.displayTitle)"]
        if let page = context.pdfPageIndex {
            lines.append("PDF page: \(page)")
        }
        if let path = context.selectedPaperMarkdownPath {
            lines.append("paper.md path: \(path)")
        }
        if let selectedText = context.selectedTextPreview {
            lines.append("Selected text preview:\n\(selectedText)")
        }
        return lines.joined(separator: "\n")
    }
}

private struct CollapsedShellRailRestoreButton: View {
    let showAI: () -> Void
    let showInspector: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: showAI) {
                Label("AI", systemImage: "sparkles")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Open AI")

            Button(action: showInspector) {
                Label("Inspector", systemImage: "sidebar.right")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Show inspector")

            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyRightRailView: View {
    var body: some View {
        ShellRailBackground()
    }
}

private struct ShellRailBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Color.secondary.opacity(0.055)
        }
    }
}