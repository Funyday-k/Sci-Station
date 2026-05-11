import AppKit
import PDFKit
import SwiftUI

struct MaterialsView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    @State private var materials: [WorkspaceMaterial] = []
    @State private var selectedMaterialID: WorkspaceMaterial.ID?
    @State private var previewText = ""
    @State private var statusMessage: String?
    @State private var isLoading = false
    @State private var isPreparingPythonRun = false
    @State private var pythonRuntimeMode: PythonRuntimeMode = .system
    @State private var selectedPythonExecutablePath: String?

    private let repository = WorkspaceMaterialRepository()
    private let vscodeBridgeService = VSCodeBridgeService()

    var body: some View {
        HStack(spacing: 0) {
            materialsList
                .frame(minWidth: 290, idealWidth: 340, maxWidth: 420)

            Divider()

            materialPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            loadPythonEnvironmentSelection()
            await reloadMaterials()
        }
        .onChange(of: selectedMaterialID) { _, _ in
            loadPreviewText()
        }
        .onChange(of: appModel.currentProjectID) { _, _ in
            Task { await reloadMaterials() }
        }
    }

    private var materialsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Materials")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                    Text("\(materials.count) files in \(appModel.currentResearchProject?.name ?? workspace.displayName)")
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    Task { await reloadMaterials() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload materials")
                .accessibilityLabel("Reload materials")
            }

            if !materials.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        openInVSCode(materialsRootURL)
                    } label: {
                        Label("Project", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        NSWorkspace.shared.open(materialsRootURL)
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }

            List(selection: $selectedMaterialID) {
                if materials.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No materials yet.", systemImage: "shippingbox")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("Add datasets, notes, scripts, or exports to the materials folder for this project.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Button {
                                NSWorkspace.shared.open(materialsRootURL)
                            } label: {
                                Label("Open Folder", systemImage: "folder")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                openInVSCode(materialsRootURL)
                            } label: {
                                Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(groupedMaterials, id: \.category) { group in
                        Section(group.category.capitalized) {
                            ForEach(group.items) { material in
                                MaterialRow(material: material)
                                    .tag(Optional(material.id))
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var materialPreview: some View {
        if isLoading {
            ProgressView("Loading materials...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let selectedMaterial {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedMaterial.displayName)
                            .font(.title)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(selectedMaterial.relativePath)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)

                    Button {
                        openInVSCode(selectedMaterial.fileURL)
                    } label: {
                        Label("VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        NSWorkspace.shared.open(selectedMaterial.fileURL)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([selectedMaterial.fileURL])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }

                if selectedMaterial.kind == .python {
                    pythonRunControls(for: selectedMaterial)
                }

                GroupBox {
                    previewBody(for: selectedMaterial)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Materials")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Select a data, code, figure, or output file for the active project.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Reveal Folder") {
                        NSWorkspace.shared.open(materialsRootURL)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Open Workspace in VS Code") {
                        openInVSCode(materialsRootURL)
                    }
                    .buttonStyle(.bordered)
                    Button("Refresh") {
                        Task { await reloadMaterials() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
        }
    }

    @ViewBuilder
    private func previewBody(for material: WorkspaceMaterial) -> some View {
        switch material.kind {
        case .markdown:
            MarkdownPreviewView(markdown: previewText, baseURL: material.fileURL.deletingLastPathComponent())
        case .python, .text:
            ScrollView {
                Text(previewText.isEmpty ? "No preview available." : previewText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        case .image:
            if let image = NSImage(contentsOf: material.fileURL) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(14)
                }
            } else {
                unavailablePreview("Image preview unavailable.")
            }
        case .pdf:
            MaterialPDFPreview(url: material.fileURL)
        case .data, .other:
            unavailablePreview("Preview this file in its default app or VS Code.")
        }
    }

    private var selectedMaterial: WorkspaceMaterial? {
        materials.first { $0.id == selectedMaterialID }
    }

    private var groupedMaterials: [(category: String, items: [WorkspaceMaterial])] {
        Dictionary(grouping: materials, by: \.category)
            .map { (category: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                lhs.category.localizedStandardCompare(rhs.category) == .orderedAscending
            }
    }

    private var materialsRootURL: URL {
        if let project = appModel.currentResearchProject {
            return workspace.directoryURL(for: project.relativePath)
        }

        return workspace.rootURL
    }

    private func reloadMaterials() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedMaterials = try await repository.loadMaterials(in: workspace, project: appModel.currentResearchProject)
            materials = loadedMaterials
            var selectionStillExists = false
            if let selectedID = selectedMaterialID {
                for material in loadedMaterials where material.id == selectedID {
                    selectionStillExists = true
                    break
                }
            }
            if selectionStillExists == false {
                selectedMaterialID = loadedMaterials.first?.id
            }
            loadPreviewText()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadPreviewText() {
        guard let selectedMaterial else {
            previewText = ""
            return
        }

        guard selectedMaterial.kind == .text || selectedMaterial.kind == .markdown || selectedMaterial.kind == .python else {
            previewText = ""
            return
        }

        guard selectedMaterial.byteCount <= 1_500_000 else {
            previewText = "File is too large for inline preview. Open it in VS Code or the default app."
            return
        }

        do {
            previewText = try String(contentsOf: selectedMaterial.fileURL, encoding: .utf8)
        } catch {
            previewText = "Preview unavailable: \(error.localizedDescription)"
        }
    }

    private func openInVSCode(_ url: URL) {
        openInVSCode([url])
    }

    private func openInVSCode(_ urls: [URL], successMessage: String = "Opened in VS Code.") {
        let workspace = NSWorkspace.shared
        let bundleIdentifiers = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.vscodium",
            "com.visualstudio.code.oss"
        ]

        if let appURL = bundleIdentifiers.compactMap({ workspace.urlForApplication(withBundleIdentifier: $0) }).first {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            workspace.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
                DispatchQueue.main.async {
                    statusMessage = error?.localizedDescription ?? successMessage
                }
            }
            return
        }

        guard let url = urls.first else {
            return
        }

        if let encodedPath = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let vscodeURL = URL(string: "vscode://file\(encodedPath)") {
            workspace.open(vscodeURL)
            statusMessage = "Sent to VS Code URL handler."
            return
        }

        workspace.open(url)
        statusMessage = "VS Code not found; opened with the default app."
    }

    private func pythonRunControls(for material: WorkspaceMaterial) -> some View {
        GroupBox("Python") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Picker("Runtime", selection: $pythonRuntimeMode) {
                        ForEach(PythonRuntimeMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 440)

                    Spacer(minLength: 0)

                    if isPreparingPythonRun {
                        ProgressView()
                            .scaleEffect(0.72)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        preparePythonRunInVSCode(for: material)
                    } label: {
                        Label("Run in VS Code", systemImage: "play.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparingPythonRun)

                    Button {
                        runPythonInTerminal(material)
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        createWorkspaceVirtualEnvironment()
                    } label: {
                        Label("Create .venv", systemImage: "shippingbox")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        selectPythonVirtualEnvironment()
                    } label: {
                        Label("Select Venv", systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.bordered)
                }

                Text(pythonRuntimeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var pythonRuntimeSummary: String {
        switch pythonRuntimeMode {
        case .system:
            return "Using system python3."
        case .workspaceVenv:
            return FileManager.default.isExecutableFile(atPath: workspacePythonExecutableURL.path)
                ? "Using \(workspace.relativePath(to: workspacePythonExecutableURL))."
                : "Workspace .venv is selected; create it before running if it does not exist yet."
        case .selectedVenv:
            return selectedPythonExecutablePath.map { "Using \($0)." } ?? "Select a virtual environment folder first."
        }
    }

    private var workspacePythonExecutableURL: URL {
        workspace.fileURL(for: ".venv/bin/python")
    }

    private var pythonEnvironmentConfigURL: URL {
        workspace.fileURL(for: ".sci-station/python_environment.txt")
    }

    private func currentPythonCommand() -> String {
        pythonRuntimeMode.pythonCommand(in: workspace, selectedPythonPath: selectedPythonExecutablePath)
    }

    private func preparePythonRunInVSCode(for material: WorkspaceMaterial) {
        isPreparingPythonRun = true

        Task {
            defer {
                isPreparingPythonRun = false
            }

            do {
                try await vscodeBridgeService.preparePythonRunTask(
                    for: material,
                    in: workspace,
                    runtimeMode: pythonRuntimeMode,
                    selectedPythonPath: selectedPythonExecutablePath
                )
                openInVSCode(
                    [workspace.rootURL, material.fileURL],
                    successMessage: "Prepared VS Code Python task and opened workspace."
                )
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func runPythonInTerminal(_ material: WorkspaceMaterial) {
        let command = "cd \(shellQuoted(material.fileURL.deletingLastPathComponent().path)) && \(shellQuoted(currentPythonCommand())) \(shellQuoted(material.fileURL.path))"
        do {
            try openTerminalScript(command: command, scriptName: "run_python")
            statusMessage = "Opened Python run in Terminal."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func createWorkspaceVirtualEnvironment() {
        let venvPath = workspace.directoryURL(for: ".venv").path
        let command = "cd \(shellQuoted(workspace.rootURL.path)) && /usr/bin/python3 -m venv \(shellQuoted(venvPath))"
        do {
            try openTerminalScript(command: command, scriptName: "create_workspace_venv")
            pythonRuntimeMode = .workspaceVenv
            selectedPythonExecutablePath = workspacePythonExecutableURL.path
            try savePythonEnvironmentSelection(path: workspacePythonExecutableURL.path)
            statusMessage = "Creating workspace .venv in Terminal."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func selectPythonVirtualEnvironment() {
        let panel = NSOpenPanel()
        panel.title = "Select Python virtual environment"
        panel.message = "Choose a virtual environment folder that contains bin/python."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = workspace.rootURL

        guard panel.runModal() == .OK, let selectedDirectoryURL = panel.url else {
            return
        }

        let pythonURL = selectedDirectoryURL.appendingPathComponent("bin/python", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            statusMessage = "Selected folder does not contain an executable bin/python."
            return
        }

        do {
            selectedPythonExecutablePath = pythonURL.path
            pythonRuntimeMode = .selectedVenv
            try savePythonEnvironmentSelection(path: pythonURL.path)
            statusMessage = "Selected Python virtual environment."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadPythonEnvironmentSelection() {
        let configuredPath = (try? String(contentsOf: pythonEnvironmentConfigURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configuredPath, !configuredPath.isEmpty else {
            if FileManager.default.isExecutableFile(atPath: workspacePythonExecutableURL.path) {
                pythonRuntimeMode = .workspaceVenv
                selectedPythonExecutablePath = workspacePythonExecutableURL.path
            }
            return
        }

        selectedPythonExecutablePath = configuredPath
        pythonRuntimeMode = configuredPath == workspacePythonExecutableURL.path ? .workspaceVenv : .selectedVenv
    }

    private func savePythonEnvironmentSelection(path: String) throws {
        try FileManager.default.createDirectory(
            at: pythonEnvironmentConfigURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try path.write(to: pythonEnvironmentConfigURL, atomically: true, encoding: .utf8)
    }

    private func openTerminalScript(command: String, scriptName: String) throws {
        let runsDirectoryURL = workspace.directoryURL(for: ".sci-station/runs")
        try FileManager.default.createDirectory(at: runsDirectoryURL, withIntermediateDirectories: true)

        let timestamp = Int(Date().timeIntervalSince1970)
        let scriptURL = runsDirectoryURL.appendingPathComponent("\(scriptName)_\(timestamp).command")
        let script = """
        #!/bin/zsh
        \(command)
        exitCode=$?
        echo ""
        echo "Process finished with exit code $exitCode."
        echo "Press Return to close."
        read -r _
        exit $exitCode
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        NSWorkspace.shared.open(scriptURL)
    }

    private func shellQuoted(_ value: String) -> String {
        let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escapedValue)'"
    }

    private func unavailablePreview(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MaterialRow: View {
    let material: WorkspaceMaterial

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: material.systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(material.displayName)
                    .lineLimit(1)
                Text(material.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct MaterialPDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

private extension WorkspaceMaterial {
    var systemImage: String {
        switch kind {
        case .markdown:
            return "doc.richtext"
        case .python:
            return "terminal"
        case .text:
            return "doc.text"
        case .image:
            return "photo"
        case .pdf:
            return "doc.viewfinder"
        case .data:
            return "tablecells"
        case .other:
            return "doc"
        }
    }
}
