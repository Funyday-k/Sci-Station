import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppViewModel
    let workspace: ResearchWorkspace?

    var body: some View {
        List {
            Section(workspace?.displayName ?? "Sci-Station") {
                ForEach(WorkspaceSection.allCases) { section in
                    SidebarActionRow(
                        title: section.title,
                        systemImage: section.systemImage,
                        isSelected: isSelected(section)
                    ) {
                        if section == .pdfReader {
                            appModel.openSelectedPaperReader()
                        } else {
                            appModel.selectSection(section)
                        }
                    }
                    .disabled(workspace == nil || (section == .pdfReader && !appModel.canEnterSelectedPaperReader))
                }
            }

            if workspace != nil {
                Section("Collections") {
                    SidebarActionRow(
                        title: "All Papers",
                        systemImage: "books.vertical",
                        isSelected: appModel.selectedSection == .library && appModel.selectedCollectionPath == nil && appModel.selectedTagName == nil,
                        badgeText: "\(appModel.papers.count)"
                    ) {
                        appModel.selectLibraryScope()
                    }

                    ForEach(appModel.collections) { collection in
                        SidebarActionRow(
                            title: collection.relativePath,
                            systemImage: "folder",
                            isSelected: appModel.selectedCollectionPath == collection.relativePath,
                            badgeText: "\(collection.paperCount)"
                        ) {
                            appModel.selectCollection(collection.relativePath)
                        }
                    }
                }

                Section("Tags") {
                    ForEach(appModel.availableTagDefinitions) { tag in
                        Button {
                            appModel.selectTag(tag.name)
                        } label: {
                            HStack(spacing: 8) {
                                TagChipView(tag: tag)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func isSelected(_ section: WorkspaceSection) -> Bool {
        if section == .library {
            return appModel.selectedSection == .library && appModel.selectedCollectionPath == nil && appModel.selectedTagName == nil
        }

        return appModel.selectedSection == section
    }
}

struct WorkspaceContentView: View {
    let workspace: ResearchWorkspace?
    let selectedSection: WorkspaceSection?
    let isWorking: Bool
    let createWorkspace: () -> Void
    let openWorkspace: () -> Void

    var body: some View {
        Group {
            if let workspace {
                if selectedSection == .dashboard {
                    DashboardView(workspace: workspace)
                } else if selectedSection == .library {
                    LibraryListView(workspace: workspace)
                } else if selectedSection == .settings {
                    SettingsView(workspace: workspace)
                } else if selectedSection == .wiki {
                    WikiWorkspaceView(workspace: workspace)
                } else if selectedSection == .tasks {
                    TasksWorkspaceView(workspace: workspace)
                } else {
                    WorkspaceSectionOverview(
                        workspace: workspace,
                        section: selectedSection ?? .library,
                        isWorking: isWorking
                    )
                }
            } else {
                EmptyWorkspaceView(
                    isWorking: isWorking,
                    createWorkspace: createWorkspace,
                    openWorkspace: openWorkspace
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct SidebarActionRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var badgeText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                Spacer(minLength: 8)
                if let badgeText {
                    Text(badgeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceSectionOverview: View {
    let workspace: ResearchWorkspace
    let section: WorkspaceSection
    let isWorking: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    Text(section.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if isWorking {
                    ProgressView("Preparing workspace…")
                }

                GroupBox("Workspace Snapshot") {
                    VStack(alignment: .leading, spacing: 12) {
                        WorkspacePathRow(label: "Root", value: workspace.rootURL.path)
                        WorkspacePathRow(label: "Shared Context", value: workspace.sharedResearchURL.path)
                        WorkspacePathRow(label: "Bibliography", value: workspace.libraryBibURL.path)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("Core Directories") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(workspace.quickAccessLocations, id: \.name) { location in
                            WorkspacePathRow(label: location.name, value: location.url.path)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("MVP Status") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前优先级已经切到 Markdown 知识闭环：导入论文后补齐 paper.md、生成 wiki/papers 模板，并在应用内编辑知识页。")
                        Text("Wiki Inspector 已支持 frontmatter、outgoing links 和 backlinks。Graph、LLM Provider 和更深的 PDF 联动仍在后续阶段。")
                            .foregroundStyle(.secondary)
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

struct WorkspaceInspectorView: View {
    let workspace: ResearchWorkspace?
    let selectedSection: WorkspaceSection?
    let revealInFinder: () -> Void

    var body: some View {
        Group {
            if let workspace {
                if selectedSection == .library {
                    PaperInspectorView(workspace: workspace)
                } else if selectedSection == .wiki {
                    WikiInspectorView(workspace: workspace)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Inspector")
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text(selectedSection?.title ?? "Workspace")
                                    .foregroundStyle(.secondary)
                            }

                            GroupBox("Quick Actions") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Button("Reveal Workspace in Finder", action: revealInFinder)
                                    Text("Recent workspace restore uses a security-scoped bookmark so the app can reopen the same root on next launch.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }

                            GroupBox("Required Structure") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(ResearchWorkspace.requiredDirectoryPaths, id: \.self) { path in
                                        Text(path)
                                            .font(.system(.body, design: .monospaced))
                                    }

                                    Divider()

                                    ForEach(ResearchWorkspace.seededFiles.map(\.relativePath), id: \.self) { path in
                                        Text(path)
                                            .font(.system(.body, design: .monospaced))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }

                            GroupBox("Workspace") {
                                WorkspacePathRow(label: "Name", value: workspace.displayName)
                                WorkspacePathRow(label: "Path", value: workspace.rootURL.path)
                            }
                        }
                        .padding(20)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inspector")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Create or open a ResearchWorkspace to see paths, actions, and validation details here.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
            }
        }
    }
}

private struct EmptyWorkspaceView: View {
    let isWorking: Bool
    let createWorkspace: () -> Void
    let openWorkspace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sci-Station")
                .font(.system(size: 42, weight: .bold, design: .rounded))

            Text("Local-first research workstation for PDFs, Markdown knowledge pages, and LLM-assisted synthesis.")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Create Workspace", action: createWorkspace)
                    .buttonStyle(.borderedProminent)
                Button("Open Existing Workspace", action: openWorkspace)
                    .buttonStyle(.bordered)
            }

            if isWorking {
                ProgressView("Preparing workspace…")
            }

            GroupBox("Workspace Layout") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ResearchWorkspace.requiredDirectoryPaths, id: \.self) { path in
                        Text(path)
                            .font(.system(.body, design: .monospaced))
                    }

                    Divider()

                    ForEach(ResearchWorkspace.seededFiles.map(\.relativePath), id: \.self) { path in
                        Text(path)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WorkspacePathRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
        }
    }
}