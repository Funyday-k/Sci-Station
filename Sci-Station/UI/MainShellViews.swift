import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppViewModel
    let workspace: ResearchWorkspace?
    @State private var isAllPapersExpanded = true

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SidebarIconButton(
                    systemImage: WorkspaceSection.dashboard.systemImage,
                    isSelected: appModel.selectedSection == .dashboard
                ) {
                    appModel.selectSection(.dashboard)
                }
                .help("Home")

                SidebarIconButton(
                    systemImage: WorkspaceSection.tasks.systemImage,
                    isSelected: appModel.selectedSection == .tasks && appModel.isViewingGlobalTodos
                ) {
                    appModel.selectGlobalTodos()
                }
                .help("All Todos")

                Spacer(minLength: 0)

                if workspace != nil {
                    SidebarIconButton(systemImage: "plus", isSelected: false) {
                        appModel.beginCreatingResearchProject()
                    }
                    .help("New Project")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if workspace == nil {
                        SidebarSectionLabel(title: "Navigate")

                        VStack(spacing: 2) {
                            ForEach(WorkspaceSection.sidebarSections) { section in
                                SidebarActionRow(
                                    title: section.title,
                                    systemImage: section.systemImage,
                                    isSelected: isSelected(section)
                                ) {
                                    appModel.selectSection(section)
                                }
                                .disabled(true)
                            }
                        }
                    } else {
                        SidebarSectionLabel(title: "Projects")

                        if appModel.activeResearchProjects.isEmpty {
                            SidebarActionRow(
                                title: "New Project",
                                systemImage: "plus",
                                isSelected: false
                            ) {
                                appModel.beginCreatingResearchProject()
                            }
                        } else {
                            VStack(spacing: 6) {
                                ForEach(appModel.activeResearchProjects) { project in
                                    SidebarProjectGroup(project: project)
                                }
                            }
                        }

                        SidebarActionRow(
                            title: WorkspaceSection.llmLab.title,
                            systemImage: WorkspaceSection.llmLab.systemImage,
                            isSelected: appModel.selectedSection == .llmLab
                        ) {
                            appModel.selectSection(.llmLab)
                        }
                        .help("Open the global AI Lab")
                    }

                    if workspace != nil {
                        SidebarSectionLabel(title: "Library")

                        VStack(spacing: 2) {
                            HStack(spacing: 6) {
                                Button {
                                    isAllPapersExpanded.toggle()
                                } label: {
                                    Image(systemName: isAllPapersExpanded ? "chevron.down" : "chevron.right")
                                        .font(.caption)
                                        .frame(width: 14, height: 20)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help(isAllPapersExpanded ? "Collapse Library folders" : "Expand Library folders")

                                SidebarActionRow(
                                    title: "All Papers",
                                    systemImage: "books.vertical",
                                    isSelected: appModel.selectedSection == .library && appModel.selectedLibraryProjectID == nil && appModel.selectedCollectionPath == nil && appModel.selectedTagName == nil,
                                    badgeText: "\(appModel.papers.count)"
                                ) {
                                    appModel.selectLibraryScope()
                                }
                                .contextMenu {
                                    Button("Create Folder") {
                                        appModel.createSubfolder(in: nil)
                                    }
                                }
                            }

                            if isAllPapersExpanded {
                                ForEach(rootCollections) { collection in
                                    SidebarCollectionTree(
                                        collection: collection,
                                        allCollections: appModel.collections,
                                        level: 0
                                    )
                                }
                            }
                        }

                        if !appModel.availableTagDefinitions.isEmpty {
                            SidebarSectionLabel(title: "Tags")

                            VStack(spacing: 2) {
                                ForEach(appModel.availableTagDefinitions) { tag in
                                    SidebarTagRow(
                                        tag: tag,
                                        isSelected: appModel.selectedTagName == tag.name
                                    ) {
                                        appModel.selectTag(tag.name)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            Spacer(minLength: 0)

            HStack {
                SidebarIconButton(
                    systemImage: WorkspaceSection.settings.systemImage,
                    isSelected: appModel.selectedSection == .settings
                ) {
                    appModel.selectSection(.settings)
                }
                .help("Settings")

                Text(workspace?.displayName ?? "Sci-Station")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func isSelected(_ section: WorkspaceSection) -> Bool {
        if section == .library {
            return appModel.selectedSection == .library && appModel.selectedLibraryProjectID == nil && appModel.selectedCollectionPath == nil && appModel.selectedTagName == nil
        }

        return appModel.selectedSection == section
    }

    private var rootCollections: [PaperCollection] {
        appModel.collections.filter { $0.parentPath == nil }
    }
}

private struct SidebarCollectionTree: View {
    @EnvironmentObject private var appModel: AppViewModel

    let collection: PaperCollection
    let allCollections: [PaperCollection]
    let level: Int

    private var children: [PaperCollection] {
        allCollections.filter { $0.parentPath == collection.relativePath }
    }

    private var isCollapsed: Bool {
        appModel.collapsedCollectionPaths.contains(collection.relativePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if children.isEmpty {
                    Color.clear
                        .frame(width: 14, height: 20)
                } else {
                    Button {
                        appModel.toggleCollectionCollapse(collection.relativePath)
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption)
                            .frame(width: 14, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(isCollapsed ? "Expand folder" : "Collapse folder")
                }

                Button {
                    appModel.selectCollection(collection.relativePath)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                        Text(collection.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(collection.paperCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(appModel.selectedCollectionPath == collection.relativePath ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Create Subfolder") {
                        appModel.createSubfolder(in: collection.relativePath)
                    }
                }
            }
            .padding(.leading, CGFloat(level * 14))

            if !isCollapsed {
                ForEach(children) { child in
                    SidebarCollectionTree(collection: child, allCollections: allCollections, level: level + 1)
                }
            }
        }
    }
}

private struct SidebarProjectGroup: View {
    @EnvironmentObject private var appModel: AppViewModel

    let project: ResearchProject

    var isCurrentProject: Bool {
        appModel.currentResearchProject?.id == project.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button {
                    appModel.toggleResearchProjectCollapse(project.id)
                } label: {
                    Image(systemName: project.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .frame(width: 14, height: 20)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(project.isCollapsed ? "Expand project" : "Collapse project")

                HStack(spacing: 8) {
                    Image(systemName: project.iconName.isEmpty ? "folder" : project.iconName)
                        .frame(width: 16)
                        .foregroundStyle(isCurrentProject ? Color.accentColor : Color.secondary)
                    Text(project.name)
                        .fontWeight(isCurrentProject ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .background(projectBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isCurrentProject ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    appModel.focusResearchProject(project.id)
                }
                .onTapGesture(count: 2) {
                    appModel.selectResearchProject(project.id, section: .projects)
                }
            }
            .contextMenu {
                Button("Open Project") {
                    appModel.selectResearchProject(project.id, section: .projects)
                }
                Button(project.isCollapsed ? "Expand" : "Collapse") {
                    appModel.toggleResearchProjectCollapse(project.id)
                }
                Divider()
                Button("Edit Project Info") {
                    appModel.beginEditingResearchProject(project.id)
                }
            }

            if !project.isCollapsed {
                VStack(spacing: 1) {
                    ForEach(WorkspaceSection.projectSidebarSections) { section in
                        SidebarActionRow(
                            title: section == .projects ? "Overview" : section.title,
                            systemImage: section.systemImage,
                            isSelected: isSelected(section),
                            badgeText: badgeText(for: section)
                        ) {
                            appModel.selectResearchProject(project.id, section: section)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
    }

    private var projectBackground: Color {
        if isCurrentProject {
            return Color(hex: project.colorHex).opacity(0.35)
        }

        return Color(hex: project.colorHex).opacity(0.14)
    }

    private func isSelected(_ section: WorkspaceSection) -> Bool {
        guard isCurrentProject else {
            return false
        }

        if section == .library {
            return appModel.selectedSection == .library && appModel.selectedLibraryProjectID == project.id && appModel.selectedCollectionPath == nil && appModel.selectedTagName == nil
        }

        return appModel.selectedSection == section
    }

    private func badgeText(for section: WorkspaceSection) -> String? {
        switch section {
        case .library:
            return "\(appModel.papers(for: project.id).count)"
        case .tasks:
            let projectTodos = appModel.todos.filter { todo in
                todo.projectIDs.contains(project.id) || (todo.projectIDs.isEmpty && (isCurrentProject || appModel.activeResearchProjects.count == 1))
            }
            return "\(projectTodos.filter { $0.status != .done && $0.status != .cancelled }.count)"
        default:
            return nil
        }
    }
}

private struct SidebarSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}

private struct SidebarIconButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 34, height: 30)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

private struct SidebarTagRow: View {
    let tag: TagDefinition
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TagChipView(tag: tag)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
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
                } else if selectedSection == .projects {
                    ProjectOverviewView(workspace: workspace)
                } else if selectedSection == .materials {
                    MaterialsView(workspace: workspace)
                } else if selectedSection == .tasks {
                    TasksWorkspaceView(workspace: workspace)
                } else if selectedSection == .llmLab {
                    AILabWorkspaceView(workspace: workspace)
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
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let badgeText {
                Text(badgeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
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
    @EnvironmentObject private var appModel: AppViewModel

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

                            GroupBox("Actions") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Button {
                                        revealInFinder()
                                    } label: {
                                        Label("Reveal in Finder", systemImage: "folder")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }

                            GroupBox("Workspace Summary") {
                                VStack(alignment: .leading, spacing: 8) {
                                    WorkspacePathRow(label: "Papers", value: "\(appModel.papers.count)")
                                    WorkspacePathRow(label: "Collections", value: "\(appModel.collections.count)")
                                    WorkspacePathRow(label: "Tags", value: "\(appModel.availableTagDefinitions.count)")
                                    WorkspacePathRow(label: "Open Todos", value: "\(appModel.todos.filter { $0.status != .done }.count)")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }

                            GroupBox("Workspace") {
                                WorkspacePathRow(label: "Name", value: workspace.displayName)
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
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}