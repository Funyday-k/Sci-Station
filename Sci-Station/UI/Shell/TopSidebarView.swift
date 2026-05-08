import SwiftUI

struct TopSidebarView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace?

    var body: some View {
        VStack(spacing: 12) {
            header

            VStack(spacing: 3) {
                ForEach(appModel.topSidebarItems) { item in
                    TopSidebarRow(
                        item: item,
                        isSelected: isSelected(item)
                    ) {
                        appModel.selectTopLevelRoute(item.top)
                    }
                    .draggable(item.id)
                    .dropDestination(for: String.self) { droppedIDs, _ in
                        guard let droppedID = droppedIDs.first else { return false }
                        appModel.moveTopSidebarItem(droppedID, before: item.id)
                        return true
                    }
                }
            }
            .padding(.horizontal, 10)

            if workspace != nil {
                Button {
                    appModel.beginCreatingResearchProject()
                } label: {
                    Label("New Project", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(.horizontal, 18)
                .help("Create a research project")
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(workspace?.displayName ?? "Sci-Station")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(appModel.workspaceModuleStatusSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .task {
            appModel.recordSidebarRender()
        }
        .onChange(of: appModel.workspacePreferences.pinnedTopLevelOrder) { _, _ in
            appModel.recordSidebarRender()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title3)
                .frame(width: 30, height: 30)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sci-Station")
                    .font(.headline)
                Text("Research Shell")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private func isSelected(_ item: TopSidebarItem) -> Bool {
        if item.top == .projects {
            return appModel.selectedSection == .projects
        }
        return appModel.selectedSection == workspaceSection(for: item.top)
    }

    private func workspaceSection(for top: WorkspaceRoute.Top) -> WorkspaceSection {
        switch top {
        case .home:
            return .dashboard
        case .projects:
            return .projects
        case .library:
            return .library
        case .calendar:
            return .calendar
        case .aiLab:
            return .llmLab
        case .settings:
            return .settings
        }
    }
}

private struct TopSidebarRow: View {
    let item: TopSidebarItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if item.isPinFixed {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(item.title)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isSelected)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        }
        return isHovering ? Color.secondary.opacity(0.08) : Color.clear
    }
}