import SwiftUI

struct SidebarView: View {
    @Binding var selectedSection: WorkspaceSection?
    let workspace: ResearchWorkspace?

    var body: some View {
        List(selection: $selectedSection) {
            Section(workspace?.displayName ?? "Sci-Station") {
                ForEach(WorkspaceSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(Optional(section))
                        .disabled(workspace == nil)
                }
            }
        }
        .listStyle(.sidebar)
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
                if selectedSection == .library {
                    LibraryListView(workspace: workspace)
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
                        Text("Step 1 is now focused on workspace creation, validation, and recent workspace restore.")
                        Text("The next slice will add paper models, meta.yaml read/write, and PDF import into raw/papers.")
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