import SwiftUI

struct AgentThreadSidebarView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    @Binding var isCollapsed: Bool
    @State private var searchText = ""
    @State private var showsArchived = false

    private var filteredThreads: [AgentThread] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let baseThreads = showsArchived ? appModel.allAgentThreads : appModel.agentThreads
        let workspaceFilteredThreads = appModel.isAgentThreadWorkspaceFilterEnabled
            ? baseThreads.filter(appModel.isAgentThreadInCurrentWorkspace)
            : baseThreads

        guard !query.isEmpty else {
            return workspaceFilteredThreads
        }
        return workspaceFilteredThreads.filter { thread in
            thread.title.lowercased().contains(query) || appModel.agentThreadSubtitle(for: thread).lowercased().contains(query)
        }
    }

    var body: some View {
        if isCollapsed {
            collapsedBody
        } else {
            expandedBody
        }
    }

    private var collapsedBody: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCollapsed = false
                }
            } label: {
                Label("Chats", systemImage: "sidebar.left")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Show chats")

            Button {
                appModel.startNewAgentConversation()
            } label: {
                Label("New Chat", systemImage: "plus.bubble")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("New Chat")

            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chats")
                        .font(.headline)
                Text("\(appModel.agentThreads.count) active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCollapsed = true
                    }
                } label: {
                    Label("Collapse", systemImage: "sidebar.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Collapse chats")
            }

            TextField("Search chats", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Toggle("Current workspace", isOn: $appModel.isAgentThreadWorkspaceFilterEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)

            Toggle("Archived", isOn: $showsArchived)
                .toggleStyle(.checkbox)
                .font(.caption)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if let pendingThread = appModel.pendingAgentThread, !showsArchived {
                        AgentThreadSidebarRow(
                            title: pendingThread.title,
                            subtitle: "Draft",
                            isActive: appModel.activeAgentThreadID == pendingThread.id,
                            isArchived: false,
                            open: {},
                            pin: nil,
                            archive: { appModel.discardPendingAgentThread() }
                        )
                    }

                    ForEach(filteredThreads) { thread in
                        AgentThreadSidebarRow(
                            title: thread.title,
                            subtitle: appModel.agentThreadSubtitle(for: thread),
                            isActive: appModel.activeAgentThreadID == thread.id,
                            isArchived: thread.isArchived,
                            open: {
                                appModel.selectAgentThread(thread)
                            },
                            pin: nil,
                            archive: {
                                appModel.confirmArchiveAgentThread(thread)
                            }
                        )
                        .contextMenu {
                            if !thread.isArchived {
                                Button("Open") { appModel.selectAgentThread(thread) }
                                Button("Rename") { appModel.beginRenameAgentThread(thread) }
                                Button("Archive", role: .destructive) { appModel.confirmArchiveAgentThread(thread) }
                            }
                        }
                    }

                    if filteredThreads.isEmpty, appModel.pendingAgentThread == nil {
                        ContentUnavailableView("No Chats", systemImage: "bubble.left", description: Text(appModel.agentThreadFilterLabel))
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .confirmationDialog(
            "Archive this chat?",
            isPresented: $appModel.isShowingAgentThreadArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                appModel.archiveConfirmedAgentThread()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(appModel.agentThreadPendingArchive?.title ?? "Archived chats are hidden from the active list.")
        }
    }
}

private struct AgentThreadSidebarRow: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    let isArchived: Bool
    let open: () -> Void
    let pin: (() -> Void)?
    let archive: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: isArchived ? "archivebox" : "bubble.left")
                    .frame(width: 16)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(isActive ? .semibold : .regular))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let pin, !isArchived {
                    Button(action: pin) {
                        Label("Pin", systemImage: "pin")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering ? 1 : 0)
                }

                if !isArchived {
                    Button(action: archive) {
                        Label("Archive", systemImage: "archivebox")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovering ? 1 : 0)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isArchived)
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isActive { return Color.accentColor.opacity(0.12) }
        return isHovering ? Color.secondary.opacity(0.08) : Color.clear
    }
}
