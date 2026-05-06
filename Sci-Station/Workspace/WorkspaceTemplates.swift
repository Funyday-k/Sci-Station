import Foundation

public nonisolated struct WorkspaceModulePermissionScope: Codable, Hashable, Sendable {
    public var readPaths: [String]
    public var writePaths: [String]
    public var requiresApprovalForWrites: Bool

    public nonisolated init(readPaths: [String] = [], writePaths: [String] = [], requiresApprovalForWrites: Bool = true) {
        self.readPaths = readPaths
        self.writePaths = writePaths
        self.requiresApprovalForWrites = requiresApprovalForWrites
    }

    private enum CodingKeys: String, CodingKey {
        case readPaths = "read_paths"
        case writePaths = "write_paths"
        case requiresApprovalForWrites = "requires_approval_for_writes"
    }
}

public nonisolated struct WorkspaceModule: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var version: String
    public var enabled: Bool
    public var directories: [String]
    public var routes: [String]
    public var workflows: [String]
    public var permissionScope: WorkspaceModulePermissionScope

    public nonisolated init(
        id: String,
        title: String,
        version: String = "0.1.0",
        enabled: Bool = true,
        directories: [String] = [],
        routes: [String] = [],
        workflows: [String] = [],
        permissionScope: WorkspaceModulePermissionScope = WorkspaceModulePermissionScope()
    ) {
        self.id = id
        self.title = title
        self.version = version
        self.enabled = enabled
        self.directories = directories
        self.routes = routes
        self.workflows = workflows
        self.permissionScope = permissionScope
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case version
        case enabled
        case directories
        case routes
        case workflows
        case permissionScope = "permission_scope"
    }
}

public nonisolated struct WorkspaceTemplate: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var version: String
    public var enabledModuleIDs: [String]
    public var previewDirectories: [String]
    public var settingsFiles: [String]

    public nonisolated init(
        id: String,
        title: String,
        version: String = "0.1.0",
        enabledModuleIDs: [String],
        previewDirectories: [String] = [],
        settingsFiles: [String] = [WorkspaceTemplateRepository.templateRelativePath, WorkspaceTemplateRepository.modulesRelativePath]
    ) {
        self.id = id
        self.title = title
        self.version = version
        self.enabledModuleIDs = enabledModuleIDs
        self.previewDirectories = previewDirectories
        self.settingsFiles = settingsFiles
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case version
        case enabledModuleIDs = "enabled_module_ids"
        case previewDirectories = "preview_directories"
        case settingsFiles = "settings_files"
    }
}

public nonisolated enum WorkspaceModuleRegistry {
    public static let builtInModules: [WorkspaceModule] = [
        WorkspaceModule(
            id: "paper-library",
            title: "Paper Library",
            directories: ["library/papers", "library/refs"],
            routes: ["/library"],
            workflows: ["paper_reading", "related_work"],
            permissionScope: WorkspaceModulePermissionScope(readPaths: ["library/papers", "library/refs"], writePaths: ["library/papers", "library/refs"])
        ),
        WorkspaceModule(
            id: "wiki",
            title: "Wiki",
            directories: ["wiki", "projects/*/wiki"],
            routes: ["/wiki"],
            workflows: ["write_markdown_plan", "related_work", "gap_planning"],
            permissionScope: WorkspaceModulePermissionScope(readPaths: ["wiki", "projects/*/wiki"], writePaths: ["wiki", "projects/*/wiki"])
        ),
        WorkspaceModule(
            id: "projects",
            title: "Projects",
            directories: ["projects"],
            routes: ["/projects"],
            workflows: ["project_planning", "gap_planning"],
            permissionScope: WorkspaceModulePermissionScope(readPaths: ["projects"], writePaths: ["projects"])
        ),
        WorkspaceModule(
            id: "materials",
            title: "Materials",
            directories: ["materials", "data", "code", "figures", "outputs", "prompts", "scripts"],
            routes: ["/materials"],
            workflows: ["material_review"],
            permissionScope: WorkspaceModulePermissionScope(readPaths: ["materials", "data", "code", "figures", "outputs", "prompts", "scripts"], writePaths: ["materials", "data", "code", "figures", "outputs", "prompts", "scripts"])
        ),
        WorkspaceModule(
            id: "tasks",
            title: "Tasks",
            directories: ["tasks"],
            routes: ["/tasks"],
            workflows: ["todo_draft", "gap_planning"],
            permissionScope: WorkspaceModulePermissionScope(readPaths: ["tasks"], writePaths: ["tasks"])
        ),
        WorkspaceModule(
            id: "calendar",
            title: "Calendar",
            directories: ["tasks"],
            routes: ["/calendar"],
            workflows: ["calendar_review"],
            permissionScope: WorkspaceModulePermissionScope(readPaths: ["tasks"], writePaths: ["tasks"])
        ),
        WorkspaceModule(
            id: "pdf-reader",
            title: "PDF Reader",
            directories: ["library/papers"],
            routes: ["/pdf-reader"],
            workflows: ["paper_reading"],
            permissionScope: WorkspaceModulePermissionScope(readPaths: ["library/papers"], writePaths: ["library/papers"])
        ),
        WorkspaceModule(
            id: "ai-lab",
            title: "AI Lab",
            directories: [".sci-station/agent", "settings"],
            routes: ["/ai-lab"],
            workflows: ["paper_reading", "related_work", "gap_planning"],
            permissionScope: WorkspaceModulePermissionScope(readPaths: ["library/papers", "wiki", "projects", "materials", "tasks"], writePaths: ["wiki", "projects/*/wiki", "tasks"])
        )
    ]

    public static func modules(for template: WorkspaceTemplate) -> [WorkspaceModule] {
        let enabled = Set(template.enabledModuleIDs)
        return builtInModules.map { module in
            var updated = module
            updated.enabled = enabled.contains(module.id)
            return updated
        }
    }

    public static func module(id: String) -> WorkspaceModule? {
        builtInModules.first { $0.id == id }
    }
}

public nonisolated enum WorkspaceTemplateRegistry {
    public static let minimal = WorkspaceTemplate(
        id: "minimal-workspace",
        title: "Minimal Workspace",
        enabledModuleIDs: ["wiki", "projects", "tasks", "ai-lab"],
        previewDirectories: ["projects", "wiki", "tasks", "settings", ".sci-station/agent"]
    )

    public static let literatureReview = WorkspaceTemplate(
        id: "literature-review",
        title: "Literature Review",
        enabledModuleIDs: WorkspaceModuleRegistry.builtInModules.map(\.id),
        previewDirectories: ["library/papers", "library/refs", "projects", "wiki", "tasks", "materials", "settings", ".sci-station/agent"]
    )

    public static let builtInTemplates = [minimal, literatureReview]

    public static func template(id: String?) -> WorkspaceTemplate {
        guard let id else { return literatureReview }
        return builtInTemplates.first { $0.id == id } ?? literatureReview
    }
}

public nonisolated struct WorkspaceTemplateRepository {
    public static let templateRelativePath = "settings/workspace_template.yaml"
    public static let modulesRelativePath = "settings/workspace_modules.yaml"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func ensureTemplateConfiguration(_ template: WorkspaceTemplate, in root: ResearchRoot) throws {
        try ensureDirectories(for: template, in: root)
        let modules = WorkspaceModuleRegistry.modules(for: template)
        try writeIfMissing(templateYAML(template), to: root.fileURL(for: Self.templateRelativePath))
        try writeIfMissing(modulesYAML(modules), to: root.fileURL(for: Self.modulesRelativePath))
    }

    public func overwriteTemplateConfiguration(_ template: WorkspaceTemplate, in root: ResearchRoot) throws {
        try ensureDirectories(for: template, in: root)
        let modules = WorkspaceModuleRegistry.modules(for: template)
        try write(templateYAML(template), to: root.fileURL(for: Self.templateRelativePath))
        try write(modulesYAML(modules), to: root.fileURL(for: Self.modulesRelativePath))
    }

    public func preview(for template: WorkspaceTemplate) -> [String] {
        Array(Set(template.previewDirectories + template.settingsFiles)).sorted()
    }

    private func ensureDirectories(for template: WorkspaceTemplate, in root: ResearchRoot) throws {
        let modules = WorkspaceModuleRegistry.modules(for: template).filter(\.enabled)
        let directories = Set(template.previewDirectories + modules.flatMap(\.directories))
        for directory in directories where !directory.contains("*") && !directory.hasSuffix(".yaml") {
            try fileManager.createDirectory(at: root.directoryURL(for: directory), withIntermediateDirectories: true)
        }
        try fileManager.createDirectory(at: root.directoryURL(for: "settings"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.directoryURL(for: ".sci-station/agent"), withIntermediateDirectories: true)
    }

    private func writeIfMissing(_ contents: String, to url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            return
        }
        try write(contents, to: url)
    }

    private func write(_ contents: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private nonisolated func templateYAML(_ template: WorkspaceTemplate) -> String {
        var lines = [
            "schema_version: 0",
            "id: \(quoted(template.id))",
            "title: \(quoted(template.title))",
            "version: \(quoted(template.version))",
            "enabled_module_ids:"
        ]
        lines.append(contentsOf: template.enabledModuleIDs.map { "  - \(quoted($0))" })
        lines.append("preview_directories:")
        lines.append(contentsOf: template.previewDirectories.map { "  - \(quoted($0))" })
        lines.append("settings_files:")
        lines.append(contentsOf: template.settingsFiles.map { "  - \(quoted($0))" })
        return lines.joined(separator: "\n") + "\n"
    }

    private nonisolated func modulesYAML(_ modules: [WorkspaceModule]) -> String {
        var lines = ["schema_version: 0", "modules:"]
        for module in modules {
            lines.append("  - id: \(quoted(module.id))")
            lines.append("    title: \(quoted(module.title))")
            lines.append("    version: \(quoted(module.version))")
            lines.append("    enabled: \(module.enabled)")
            appendArray(module.directories, key: "directories", to: &lines, indentation: "    ")
            appendArray(module.routes, key: "routes", to: &lines, indentation: "    ")
            appendArray(module.workflows, key: "workflows", to: &lines, indentation: "    ")
            lines.append("    permission_scope:")
            appendArray(module.permissionScope.readPaths, key: "read_paths", to: &lines, indentation: "      ")
            appendArray(module.permissionScope.writePaths, key: "write_paths", to: &lines, indentation: "      ")
            lines.append("      requires_approval_for_writes: \(module.permissionScope.requiresApprovalForWrites)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private nonisolated func appendArray(_ values: [String], key: String, to lines: inout [String], indentation: String) {
        lines.append("\(indentation)\(key):")
        if values.isEmpty {
            lines.append("\(indentation)  []")
        } else {
            lines.append(contentsOf: values.map { "\(indentation)  - \(quoted($0))" })
        }
    }

    private nonisolated func quoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}