import SwiftUI

struct ModuleSettingsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace
    @StateObject private var viewModel = ModuleSettingsViewModel()
    @State private var isResetConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Label(viewModel.statusSummary, systemImage: "switch.2")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    isResetConfirmationPresented = true
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .disabled(viewModel.isPersisting)
                .help("Reset modules to the current workspace template defaults")
            }

            if viewModel.isPersisting {
                ProgressView()
                    .controlSize(.small)
            }

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.configuration.modules) { module in
                    ModuleCardView(module: module, viewModel: viewModel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            viewModel.configure(appModel: appModel, root: ResearchRoot(rootURL: workspace.rootURL))
        }
        .onChange(of: appModel.workspaceModuleConfiguration) { _, _ in
            viewModel.sync(from: appModel)
        }
        .onChange(of: appModel.workspaceModuleOverrides) { _, _ in
            viewModel.sync(from: appModel)
        }
        .onChange(of: appModel.activeResearchProjects) { _, _ in
            viewModel.sync(from: appModel)
        }
        .alert("Repair Directory", isPresented: Binding(
            get: { viewModel.pendingRepairStatus != nil },
            set: { isPresented in
                if !isPresented { viewModel.pendingRepairStatus = nil }
            }
        )) {
            Button("Repair") {
                guard let status = viewModel.pendingRepairStatus else { return }
                viewModel.pendingRepairStatus = nil
                Task { await viewModel.repairDirectory(status, approved: true) }
            }
            Button("Cancel", role: .cancel) {
                if let status = viewModel.pendingRepairStatus {
                    Task { await viewModel.repairDirectory(status, approved: false) }
                }
                viewModel.pendingRepairStatus = nil
            }
        } message: {
            Text(viewModel.pendingRepairStatus.map { "Create missing workspace directory: \($0.path)" } ?? "Create missing workspace directory.")
        }
        .alert("Reset Module Settings", isPresented: $isResetConfirmationPresented) {
            Button("Reset", role: .destructive) {
                Task { await viewModel.resetToTemplateDefault() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore enabled and pinned module choices from the workspace template.")
        }
        .alert("Module Settings", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

private struct ModuleCardView: View {
    let module: WorkspaceModule
    @ObservedObject var viewModel: ModuleSettingsViewModel

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { viewModel.expandedModuleIDs.contains(module.id) },
            set: { isExpanded in
                if isExpanded {
                    viewModel.expandedModuleIDs.insert(module.id)
                } else {
                    viewModel.expandedModuleIDs.remove(module.id)
                }
            }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if !missingDependencies.isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        Label("Missing dependencies: \(missingDependencies.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer(minLength: 0)
                        Button {
                            Task { await viewModel.enableDependencies(for: module.id) }
                        } label: {
                            Label("Enable Dependencies", systemImage: "link.badge.plus")
                        }
                        .controlSize(.small)
                    }
                }

                ModuleDetailRow(label: "Dependencies", values: module.dependencies)
                ModuleDetailRow(label: "Routes", values: module.routes.map { "\($0.id) \($0.path)" })
                ModuleDetailRow(label: "Project Tabs", values: module.projectTabs.map { "\($0.id): \($0.title)" })
                ModuleDetailRow(label: "Workflows", values: module.workflows)
                ModuleDetailRow(label: "Artifact Kinds", values: module.artifactKinds)
                ModuleDetailRow(label: "Approval Scopes", values: module.approvalScopes)
                ModuleDetailRow(label: "Write Paths", values: module.permissions.writePaths)
                ModuleDirectoriesView(module: module, viewModel: viewModel)
                ModuleProjectOverridesView(module: module, viewModel: viewModel)

                if let warnings = viewModel.warningsByModuleID[module.id], !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Warnings")
                            .font(.caption.weight(.semibold))
                        ForEach(warnings) { warning in
                            Label(warning.message, systemImage: warning.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(warning.severity == .error ? .red : .orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { module.enabled },
                    set: { enabled in
                        Task {
                            if enabled {
                                await viewModel.enableModule(id: module.id)
                            } else {
                                await viewModel.disableModule(id: module.id)
                            }
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(module.title)
                                .font(.headline)
                            ModuleStatusBadge(module: module, isAvailable: viewModel.availableModules.contains { $0.id == module.id })
                        }
                        Text(module.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(viewModel.isPersisting)

                Spacer(minLength: 0)

                if module.pinned {
                    Button {
                        Task { await viewModel.movePin(id: module.id, offset: -1) }
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.pinnedOrder.first == module.id || viewModel.isPersisting)
                    .help("Move pinned module up")

                    Button {
                        Task { await viewModel.movePin(id: module.id, offset: 1) }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.pinnedOrder.last == module.id || viewModel.isPersisting)
                    .help("Move pinned module down")
                }

                Button {
                    Task { await viewModel.togglePin(id: module.id) }
                } label: {
                    Image(systemName: module.pinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isPersisting)
                .help(module.pinned ? "Unpin from sidebar priority" : "Pin to sidebar priority")
            }
            .contentShape(Rectangle())
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14))
        }
    }

    private var missingDependencies: [String] {
        viewModel.warningDependencies(for: module)
    }
}

private struct ModuleStatusBadge: View {
    let module: WorkspaceModule
    let isAvailable: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
    }

    private var title: String {
        if module.enabled && isAvailable { return "enabled" }
        if module.enabled { return "dependency hidden" }
        return "disabled"
    }

    private var systemImage: String {
        if module.enabled && isAvailable { return "checkmark.circle" }
        if module.enabled { return "exclamationmark.triangle" }
        return "circle"
    }

    private var color: Color {
        if module.enabled && isAvailable { return .green }
        if module.enabled { return .orange }
        return .secondary
    }
}

private struct ModuleDetailRow: View {
    let label: String
    let values: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .frame(width: 108, alignment: .leading)
            Text(values.isEmpty ? "none" : values.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(values.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ModuleDirectoriesView: View {
    let module: WorkspaceModule
    @ObservedObject var viewModel: ModuleSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Directories")
                .font(.caption.weight(.semibold))
            let statusesByPath = Dictionary(uniqueKeysWithValues: (viewModel.directoryStatusesByModuleID[module.id] ?? []).map { ($0.path, $0) })
            ForEach(module.directories, id: \.path) { directory in
                let status = statusesByPath[directory.path]
                HStack(spacing: 8) {
                    Image(systemName: status?.exists == true ? "folder" : (directory.required ? "folder.badge.questionmark" : "folder"))
                        .foregroundStyle(status?.exists == true || !directory.required ? Color.secondary : Color.orange)
                    Text(directory.path)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(directory.required ? "required" : "optional")
                        .font(.caption2)
                        .foregroundStyle(directory.required && status?.exists == false ? .orange : .secondary)
                    Spacer(minLength: 0)
                    if let status, !status.exists, status.required, status.repairable {
                        Button {
                            viewModel.pendingRepairStatus = status
                        } label: {
                            Label("Repair", systemImage: "wrench.and.screwdriver")
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

private struct ModuleProjectOverridesView: View {
    let module: WorkspaceModule
    @ObservedObject var viewModel: ModuleSettingsViewModel

    var body: some View {
        if !viewModel.projects.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Project Overrides")
                    .font(.caption.weight(.semibold))
                ForEach(viewModel.projects) { project in
                    HStack(spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { viewModel.projectEffectiveEnabled(projectID: project.id, moduleID: module.id) },
                            set: { enabled in
                                Task { await viewModel.projectOverride(projectID: project.id, moduleID: module.id, enabled: enabled) }
                            }
                        )) {
                            Text(project.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(viewModel.isPersisting)

                        if let override = viewModel.projectOverrideValue(projectID: project.id, moduleID: module.id) {
                            Text(override ? "override on" : "override off")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button {
                                Task { await viewModel.clearProjectOverride(projectID: project.id, moduleID: module.id) }
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(viewModel.isPersisting)
                            .help("Clear project override")
                        } else {
                            Text("workspace default")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}