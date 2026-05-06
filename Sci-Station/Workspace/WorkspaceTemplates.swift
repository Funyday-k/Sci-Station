import Foundation

public nonisolated enum WorkspaceModuleSchema {
    public static let currentVersion = 1

    public static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }
        let allowedScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_.")
        return value.unicodeScalars.allSatisfy { allowedScalars.contains($0) }
    }

    public static func isValidRoutePath(_ value: String) -> Bool {
        value.hasPrefix("/") && !value.contains(" ") && !value.contains("..")
    }

    public static func isSafeRelativePathPattern(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return false
        }
        if trimmedValue.hasPrefix("/") || trimmedValue.hasPrefix("~") || trimmedValue.contains("..") || trimmedValue.contains("\\") {
            return false
        }
        return true
    }
}

public nonisolated struct WorkspaceModuleDirectory: Codable, Hashable, Sendable {
    public var path: String
    public var required: Bool
    public var repairable: Bool

    public nonisolated init(path: String, required: Bool = false, repairable: Bool = true) {
        self.path = path
        self.required = required
        self.repairable = repairable
    }
}

public nonisolated struct WorkspaceModuleRoute: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var path: String

    public nonisolated init(id: String, path: String) {
        self.id = id
        self.path = path
    }
}

public nonisolated struct WorkspaceModuleProjectTab: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String

    public nonisolated init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public nonisolated struct WorkspaceModulePermissions: Codable, Hashable, Sendable {
    public var writePaths: [String]

    public nonisolated init(writePaths: [String] = []) {
        self.writePaths = writePaths
    }

    private enum CodingKeys: String, CodingKey {
        case writePaths = "write_paths"
    }
}

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
    public var version: Int
    public var enabled: Bool
    public var pinned: Bool
    public var dependencies: [String]
    public var directories: [WorkspaceModuleDirectory]
    public var routes: [WorkspaceModuleRoute]
    public var projectTabs: [WorkspaceModuleProjectTab]
    public var workflows: [String]
    public var artifactKinds: [String]
    public var approvalScopes: [String]
    public var permissions: WorkspaceModulePermissions

    public nonisolated init(
        id: String,
        title: String,
        version: Int = 1,
        enabled: Bool = true,
        pinned: Bool = false,
        dependencies: [String] = [],
        directories: [WorkspaceModuleDirectory] = [],
        routes: [WorkspaceModuleRoute] = [],
        projectTabs: [WorkspaceModuleProjectTab] = [],
        workflows: [String] = [],
        artifactKinds: [String] = [],
        approvalScopes: [String] = [],
        permissions: WorkspaceModulePermissions = WorkspaceModulePermissions()
    ) {
        self.id = id
        self.title = title
        self.version = max(1, version)
        self.enabled = enabled
        self.pinned = pinned
        self.dependencies = dependencies
        self.directories = directories
        self.routes = routes
        self.projectTabs = projectTabs
        self.workflows = workflows
        self.artifactKinds = artifactKinds
        self.approvalScopes = approvalScopes
        self.permissions = permissions
    }

    public nonisolated var permissionScope: WorkspaceModulePermissionScope {
        WorkspaceModulePermissionScope(readPaths: [], writePaths: permissions.writePaths, requiresApprovalForWrites: true)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case version
        case enabled
        case pinned
        case dependencies
        case directories
        case routes
        case projectTabs = "project_tabs"
        case workflows
        case artifactKinds = "artifact_kinds"
        case approvalScopes = "approval_scopes"
        case permissions
    }
}

public nonisolated struct WorkspaceModuleConfiguration: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var modules: [WorkspaceModule]

    public nonisolated init(schemaVersion: Int = WorkspaceModuleSchema.currentVersion, modules: [WorkspaceModule] = []) {
        self.schemaVersion = schemaVersion
        self.modules = modules
    }

    public nonisolated var enabledModuleIDs: Set<String> {
        Set(modules.filter(\.enabled).map(\.id))
    }

    public nonisolated func module(id: String) -> WorkspaceModule? {
        modules.first { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case modules
    }
}

public nonisolated enum WorkspaceModuleWarningSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public nonisolated struct WorkspaceModuleWarning: Identifiable, Hashable, Sendable {
    public var id: String
    public var moduleID: String?
    public var severity: WorkspaceModuleWarningSeverity
    public var message: String

    public nonisolated init(id: String, moduleID: String?, severity: WorkspaceModuleWarningSeverity = .warning, message: String) {
        self.id = id
        self.moduleID = moduleID
        self.severity = severity
        self.message = message
    }
}

public nonisolated struct WorkspaceModuleDirectoryStatus: Identifiable, Hashable, Sendable {
    public var id: String { "\(moduleID):\(path)" }
    public var moduleID: String
    public var moduleTitle: String
    public var path: String
    public var required: Bool
    public var repairable: Bool
    public var exists: Bool

    public nonisolated init(moduleID: String, moduleTitle: String, path: String, required: Bool, repairable: Bool, exists: Bool) {
        self.moduleID = moduleID
        self.moduleTitle = moduleTitle
        self.path = path
        self.required = required
        self.repairable = repairable
        self.exists = exists
    }
}

public nonisolated struct WorkspaceModuleArtifactKindDescriptor: Identifiable, Hashable, Sendable {
    public var id: String { kind }
    public var kind: String
    public var title: String
    public var moduleID: String?
    public var moduleTitle: String?
    public var isKnown: Bool

    public nonisolated init(kind: String, title: String, moduleID: String?, moduleTitle: String?, isKnown: Bool) {
        self.kind = kind
        self.title = title
        self.moduleID = moduleID
        self.moduleTitle = moduleTitle
        self.isKnown = isKnown
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
    public static let defaultEnabledModuleIDs: Set<String> = [
        "projects",
        "paper-library",
        "wiki",
        "materials",
        "tasks",
        "calendar",
        "pdf-reader",
        "ai-lab"
    ]

    public static let workflowRequirements: [String: Set<String>] = [
        "paper_reading": ["ai-lab", "paper-library", "pdf-reader"],
        "related_work": ["ai-lab", "paper-library", "wiki"],
        "gap_planning": ["ai-lab", "wiki", "tasks", "projects"],
        "write_markdown_plan": ["wiki"],
        "project_planning": ["projects", "wiki"],
        "material_review": ["materials"],
        "todo_draft": ["tasks", "ai-lab"],
        "calendar_review": ["calendar", "tasks"],
        "paper_to_code_checklist": ["code", "ai-lab"],
        "experiment_planning": ["experiments", "ai-lab"],
        "run_log_summary": ["experiments", "ai-lab"],
        "citation_graph_review": ["citation-graph"],
        "research_queue_update": ["recommendation"],
        "outline_to_manuscript": ["writing", "ai-lab"],
        "claim_citation_check": ["writing", "paper-library", "ai-lab"],
        "definition_extraction": ["theory-notes", "paper-library"],
        "theorem_dependency_map": ["theory-notes", "wiki"]
    ]

    public static let builtInModules: [WorkspaceModule] = [
        module(
            id: "projects",
            title: "Projects",
            directories: [directory("projects", required: true)],
            routes: [route("projects", "/projects")],
            projectTabs: [tab("overview", "Overview")],
            workflows: ["project_planning", "gap_planning"],
            artifactKinds: ["research_plan"],
            approvalScopes: ["artifact_save", "wiki_write"],
            writePaths: ["projects/*/wiki/", ".sci-station/project_registry.yaml"]
        ),
        module(
            id: "paper-library",
            title: "Paper Library",
            directories: [directory("library/papers", required: true), directory("library/refs", required: true)],
            routes: [route("library", "/library")],
            projectTabs: [tab("papers", "Papers")],
            workflows: ["paper_reading", "related_work"],
            artifactKinds: ["paper_reading_note", "related_work"],
            approvalScopes: ["artifact_save", "wiki_write"],
            writePaths: ["library/papers/", "library/refs/"]
        ),
        module(
            id: "wiki",
            title: "Wiki",
            dependencies: ["projects"],
            directories: [directory("wiki"), directory("projects/*/wiki/", required: true)],
            routes: [route("wiki", "/wiki")],
            projectTabs: [tab("wiki", "Wiki")],
            workflows: ["write_markdown_plan", "related_work", "gap_planning"],
            artifactKinds: ["wiki_note", "related_work", "research_plan"],
            approvalScopes: ["artifact_save", "wiki_write"],
            writePaths: ["wiki/", "projects/*/wiki/"]
        ),
        module(
            id: "materials",
            title: "Materials",
            dependencies: ["projects"],
            directories: [directory("materials"), directory("data"), directory("code"), directory("figures"), directory("outputs"), directory("prompts"), directory("scripts")],
            routes: [route("materials", "/materials")],
            projectTabs: [tab("materials", "Materials")],
            workflows: ["material_review"],
            artifactKinds: ["material_note"],
            approvalScopes: ["artifact_save"],
            writePaths: ["materials/", "data/", "code/", "figures/", "outputs/", "prompts/", "scripts/"]
        ),
        module(
            id: "tasks",
            title: "Tasks",
            dependencies: ["projects"],
            directories: [directory("tasks", required: true)],
            routes: [route("tasks", "/tasks")],
            projectTabs: [tab("tasks", "Tasks")],
            workflows: ["todo_draft", "gap_planning"],
            artifactKinds: ["todo_draft", "research_plan"],
            approvalScopes: ["artifact_save", "todo_create"],
            writePaths: ["tasks/"]
        ),
        module(
            id: "calendar",
            title: "Calendar",
            dependencies: ["tasks"],
            directories: [directory("tasks", required: true)],
            routes: [route("calendar", "/calendar")],
            projectTabs: [tab("calendar", "Calendar")],
            workflows: ["calendar_review"],
            artifactKinds: ["calendar_plan"],
            approvalScopes: ["todo_create"],
            writePaths: ["tasks/calendar.yaml"]
        ),
        module(
            id: "pdf-reader",
            title: "PDF Reader",
            dependencies: ["paper-library"],
            directories: [directory("library/papers", required: true)],
            routes: [route("pdf-reader", "/pdf-reader")],
            projectTabs: [tab("pdf-reader", "PDF")],
            workflows: ["paper_reading"],
            artifactKinds: ["paper_reading_note"],
            approvalScopes: ["artifact_save"],
            writePaths: ["library/papers/"]
        ),
        module(
            id: "ai-lab",
            title: "AI Lab",
            dependencies: ["projects"],
            directories: [directory(".sci-station/agent", required: true), directory("settings", required: true)],
            routes: [route("ai-lab", "/ai-lab")],
            projectTabs: [tab("ai-drafts", "AI Drafts")],
            workflows: ["paper_reading", "related_work", "gap_planning", "todo_draft"],
            artifactKinds: ["paper_reading_note", "related_work", "research_plan", "todo_draft"],
            approvalScopes: ["artifact_save", "wiki_write", "todo_create"],
            writePaths: ["wiki/", "projects/*/wiki/", "tasks/", ".sci-station/agent/drafts/"]
        ),
        module(
            id: "code",
            title: "Code Research",
            enabled: false,
            dependencies: ["projects", "wiki", "ai-lab"],
            directories: [directory("projects/*/code/"), directory("code")],
            routes: [route("code", "/code")],
            projectTabs: [tab("code", "Code")],
            workflows: ["paper_to_code_checklist"],
            artifactKinds: ["code_reading_note"],
            approvalScopes: ["artifact_save", "wiki_write"],
            writePaths: ["projects/*/wiki/", "projects/*/code/"]
        ),
        module(
            id: "datasets",
            title: "Datasets",
            enabled: false,
            dependencies: ["projects", "materials"],
            directories: [directory("projects/*/data/"), directory("data")],
            routes: [route("datasets", "/datasets")],
            projectTabs: [tab("data", "Data")],
            workflows: ["dataset_review"],
            artifactKinds: ["dataset_note"],
            approvalScopes: ["artifact_save", "wiki_write"],
            writePaths: ["projects/*/wiki/", "projects/*/data/", "data/"]
        ),
        module(
            id: "experiments",
            title: "Experiments",
            enabled: false,
            dependencies: ["projects", "code", "datasets", "ai-lab"],
            directories: [directory("projects/*/experiments/"), directory("projects/*/outputs/"), directory("outputs")],
            routes: [route("experiments", "/experiments")],
            projectTabs: [tab("experiments", "Experiments")],
            workflows: ["experiment_planning", "run_log_summary"],
            artifactKinds: ["experiment_plan", "experiment_report", "run_log_summary"],
            approvalScopes: ["artifact_save", "wiki_write", "todo_create"],
            writePaths: ["projects/*/wiki/", "projects/*/tasks/", "projects/*/outputs/", "outputs/"]
        ),
        module(
            id: "citation-graph",
            title: "Citation Graph",
            enabled: false,
            dependencies: ["paper-library", "wiki"],
            directories: [directory(".sci-station/graph")],
            routes: [route("graph", "/graph")],
            projectTabs: [tab("graph", "Graph")],
            workflows: ["citation_graph_review"],
            artifactKinds: ["graph_insight"],
            approvalScopes: ["artifact_save"],
            writePaths: [".sci-station/graph/", "projects/*/wiki/"]
        ),
        module(
            id: "recommendation",
            title: "Recommendation",
            enabled: false,
            dependencies: ["paper-library", "citation-graph", "ai-lab"],
            directories: [directory(".sci-station/recommendations")],
            routes: [route("recommendation", "/recommendations")],
            projectTabs: [tab("recommendations", "Recommendations")],
            workflows: ["research_queue_update"],
            artifactKinds: ["recommendation_note", "weekly_review"],
            approvalScopes: ["artifact_save", "todo_create"],
            writePaths: [".sci-station/recommendations/", "tasks/"]
        ),
        module(
            id: "writing",
            title: "Writing",
            enabled: false,
            dependencies: ["projects", "wiki", "paper-library", "ai-lab"],
            directories: [directory("projects/*/writing/")],
            routes: [route("writing", "/writing")],
            projectTabs: [tab("writing", "Writing")],
            workflows: ["outline_to_manuscript", "claim_citation_check"],
            artifactKinds: ["writing_revision", "reviewer_response"],
            approvalScopes: ["artifact_save", "wiki_write"],
            writePaths: ["projects/*/wiki/", "projects/*/writing/"]
        ),
        module(
            id: "theory-notes",
            title: "Theory Notes",
            enabled: false,
            dependencies: ["projects", "wiki", "paper-library"],
            directories: [directory("projects/*/theory/"), directory("wiki/theory")],
            routes: [route("theory-notes", "/theory-notes")],
            projectTabs: [tab("theory", "Theory")],
            workflows: ["definition_extraction", "theorem_dependency_map"],
            artifactKinds: ["definition_note", "theorem_note", "proof_sketch", "open_problem_note"],
            approvalScopes: ["artifact_save", "wiki_write"],
            writePaths: ["projects/*/wiki/", "projects/*/theory/", "wiki/theory/"]
        )
    ]

    public static func modules(for template: WorkspaceTemplate) -> [WorkspaceModule] {
        let enabledModuleIDs = Set(template.enabledModuleIDs)
        return builtInModules.map { module in
            var updatedModule = module
            updatedModule.enabled = enabledModuleIDs.contains(module.id)
            return updatedModule
        }
    }

    public static func defaultConfiguration(enabledModuleIDs: Set<String>? = nil) -> WorkspaceModuleConfiguration {
        let enabledIDs = enabledModuleIDs ?? defaultEnabledModuleIDs
        return WorkspaceModuleConfiguration(modules: builtInModules.map { module in
            var updatedModule = module
            updatedModule.enabled = enabledIDs.contains(module.id)
            return updatedModule
        })
    }

    public static func configuration(for template: WorkspaceTemplate) -> WorkspaceModuleConfiguration {
        WorkspaceModuleConfiguration(modules: modules(for: template))
    }

    public static func mergedConfiguration(from storedConfiguration: WorkspaceModuleConfiguration) -> WorkspaceModuleConfiguration {
        let storedModulesByID = Dictionary(uniqueKeysWithValues: storedConfiguration.modules.map { ($0.id, $0) })
        let mergedModules = builtInModules.map { builtInModule in
            var module = builtInModule
            if let storedModule = storedModulesByID[builtInModule.id] {
                module.enabled = storedModule.enabled
                module.pinned = storedModule.pinned
            }
            return module
        }
        return WorkspaceModuleConfiguration(schemaVersion: WorkspaceModuleSchema.currentVersion, modules: mergedModules)
    }

    public static func module(id: String) -> WorkspaceModule? {
        builtInModules.first { $0.id == id }
    }

    public static func availableModules(in configuration: WorkspaceModuleConfiguration) -> [WorkspaceModule] {
        let enabledIDs = configuration.enabledModuleIDs
        return configuration.modules.filter { module in
            module.enabled && module.dependencies.allSatisfy { enabledIDs.contains($0) }
        }
    }

    public static func availableRoutes(in configuration: WorkspaceModuleConfiguration) -> [WorkspaceModuleRoute] {
        availableModules(in: configuration).flatMap(\.routes)
    }

    public static func availableProjectTabs(in configuration: WorkspaceModuleConfiguration) -> [WorkspaceModuleProjectTab] {
        availableModules(in: configuration).flatMap(\.projectTabs)
    }

    public static func availableWorkflows(in configuration: WorkspaceModuleConfiguration) -> [String] {
        let enabledIDs = configuration.enabledModuleIDs
        let declaredWorkflows = availableModules(in: configuration).flatMap(\.workflows)
        let filteredWorkflows = declaredWorkflows.filter { workflowID in
            guard let requirements = workflowRequirements[workflowID] else {
                return true
            }
            return requirements.isSubset(of: enabledIDs)
        }
        return Array(Set(filteredWorkflows)).sorted()
    }

    public static func artifactKindDescriptors(in configuration: WorkspaceModuleConfiguration) -> [WorkspaceModuleArtifactKindDescriptor] {
        availableModules(in: configuration)
            .flatMap { module in
                module.artifactKinds.map { kind in
                    WorkspaceModuleArtifactKindDescriptor(
                        kind: kind,
                        title: artifactKindTitle(kind),
                        moduleID: module.id,
                        moduleTitle: module.title,
                        isKnown: true
                    )
                }
            }
            .uniquedByKind()
            .sorted { $0.kind < $1.kind }
    }

    public static func artifactKindDescriptor(for kind: String, in configuration: WorkspaceModuleConfiguration) -> WorkspaceModuleArtifactKindDescriptor {
        artifactKindDescriptors(in: configuration).first { $0.kind == kind } ?? WorkspaceModuleArtifactKindDescriptor(
            kind: kind,
            title: artifactKindTitle(kind),
            moduleID: nil,
            moduleTitle: nil,
            isKnown: false
        )
    }

    public static func warnings(for configuration: WorkspaceModuleConfiguration) -> [WorkspaceModuleWarning] {
        let builtInModulesByID = Dictionary(uniqueKeysWithValues: builtInModules.map { ($0.id, $0) })
        let configuredIDs = Set(configuration.modules.map(\.id))
        let enabledIDs = configuration.enabledModuleIDs
        var warnings: [WorkspaceModuleWarning] = []

        for module in configuration.modules {
            if !WorkspaceModuleSchema.isValidIdentifier(module.id) {
                warnings.append(WorkspaceModuleWarning(id: "invalid-module-id:\(module.id)", moduleID: module.id, severity: .error, message: "Module id '\(module.id)' is not a stable serializable identifier."))
            }

            guard let builtInModule = builtInModulesByID[module.id] else {
                warnings.append(WorkspaceModuleWarning(id: "unknown-module:\(module.id)", moduleID: module.id, message: "Unknown workspace module '\(module.id)' is ignored because P39 only supports built-in modules."))
                continue
            }

            if module.version != builtInModule.version {
                warnings.append(WorkspaceModuleWarning(id: "module-version:\(module.id)", moduleID: module.id, message: "Module '\(module.id)' uses config version \(module.version), registry version \(builtInModule.version)."))
            }

            for dependency in module.dependencies where !configuredIDs.contains(dependency) {
                warnings.append(WorkspaceModuleWarning(id: "missing-dependency:\(module.id):\(dependency)", moduleID: module.id, message: "Module '\(module.id)' depends on missing module '\(dependency)'."))
            }

            for dependency in module.dependencies where module.enabled && configuredIDs.contains(dependency) && !enabledIDs.contains(dependency) {
                warnings.append(WorkspaceModuleWarning(id: "disabled-dependency:\(module.id):\(dependency)", moduleID: module.id, message: "Module '\(module.id)' depends on disabled module '\(dependency)'; related routes and workflows are hidden."))
            }

            warnings.append(contentsOf: validationWarnings(for: module))
        }

        return warnings.sorted { $0.id < $1.id }
    }

    public static func directoryStatuses(for configuration: WorkspaceModuleConfiguration, in root: ResearchRoot, using fileManager: FileManager = .default) -> [WorkspaceModuleDirectoryStatus] {
        availableModules(in: configuration).flatMap { module in
            module.directories.map { directory in
                let exists: Bool
                if directory.path.contains("*") {
                    exists = false
                } else {
                    var isDirectory: ObjCBool = false
                    exists = fileManager.fileExists(atPath: root.directoryURL(for: directory.path).path, isDirectory: &isDirectory) && isDirectory.boolValue
                }
                return WorkspaceModuleDirectoryStatus(
                    moduleID: module.id,
                    moduleTitle: module.title,
                    path: directory.path,
                    required: directory.required,
                    repairable: directory.repairable,
                    exists: exists
                )
            }
        }
    }

    public static func moduleScopeDescription(for targetPaths: [String], in configuration: WorkspaceModuleConfiguration) -> String? {
        let modules = availableModules(in: configuration).filter { module in
            guard !module.approvalScopes.isEmpty, !module.permissions.writePaths.isEmpty else {
                return false
            }
            guard !targetPaths.isEmpty else {
                return module.approvalScopes.contains("artifact_save")
            }
            return targetPaths.contains { targetPath in
                module.permissions.writePaths.contains { pattern in
                    path(pattern: pattern, matches: targetPath)
                }
            }
        }

        let parts = modules.map { module in
            "\(module.title): \(module.approvalScopes.joined(separator: ", "))"
        }

        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    public static func path(pattern: String, matches targetPath: String) -> Bool {
        let normalizedPattern = normalizePath(pattern)
        let normalizedTarget = normalizePath(targetPath)
        guard normalizedPattern.contains("*") else {
            return normalizedTarget == normalizedPattern || normalizedTarget.hasPrefix(normalizedPattern + "/")
        }
        let pieces = normalizedPattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        guard let firstPiece = pieces.first, normalizedTarget.hasPrefix(firstPiece) else {
            return false
        }
        guard let lastPiece = pieces.last, !lastPiece.isEmpty else {
            return true
        }
        return normalizedTarget.hasSuffix(lastPiece) || normalizedTarget.contains(lastPiece)
    }

    public static func artifactKindTitle(_ kind: String) -> String {
        kind.split(separator: "_").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private static func validationWarnings(for module: WorkspaceModule) -> [WorkspaceModuleWarning] {
        var warnings: [WorkspaceModuleWarning] = []
        for route in module.routes {
            if !WorkspaceModuleSchema.isValidIdentifier(route.id) || !WorkspaceModuleSchema.isValidRoutePath(route.path) {
                warnings.append(WorkspaceModuleWarning(id: "invalid-route:\(module.id):\(route.id)", moduleID: module.id, severity: .error, message: "Module '\(module.id)' has invalid route '\(route.id)' -> '\(route.path)'."))
            }
        }
        for tab in module.projectTabs where !WorkspaceModuleSchema.isValidIdentifier(tab.id) {
            warnings.append(WorkspaceModuleWarning(id: "invalid-project-tab:\(module.id):\(tab.id)", moduleID: module.id, severity: .error, message: "Module '\(module.id)' has invalid project tab id '\(tab.id)'."))
        }
        for directory in module.directories where !WorkspaceModuleSchema.isSafeRelativePathPattern(directory.path) {
            warnings.append(WorkspaceModuleWarning(id: "invalid-directory:\(module.id):\(directory.path)", moduleID: module.id, severity: .error, message: "Module '\(module.id)' has unsafe directory path '\(directory.path)'."))
        }
        for workflow in module.workflows where !WorkspaceModuleSchema.isValidIdentifier(workflow) {
            warnings.append(WorkspaceModuleWarning(id: "invalid-workflow:\(module.id):\(workflow)", moduleID: module.id, severity: .error, message: "Module '\(module.id)' has invalid workflow id '\(workflow)'."))
        }
        for artifactKind in module.artifactKinds where !WorkspaceModuleSchema.isValidIdentifier(artifactKind) {
            warnings.append(WorkspaceModuleWarning(id: "invalid-artifact-kind:\(module.id):\(artifactKind)", moduleID: module.id, severity: .error, message: "Module '\(module.id)' has invalid artifact kind '\(artifactKind)'."))
        }
        for approvalScope in module.approvalScopes where !WorkspaceModuleSchema.isValidIdentifier(approvalScope) {
            warnings.append(WorkspaceModuleWarning(id: "invalid-approval-scope:\(module.id):\(approvalScope)", moduleID: module.id, severity: .error, message: "Module '\(module.id)' has invalid approval scope '\(approvalScope)'."))
        }
        for writePath in module.permissions.writePaths where !WorkspaceModuleSchema.isSafeRelativePathPattern(writePath) {
            warnings.append(WorkspaceModuleWarning(id: "invalid-write-path:\(module.id):\(writePath)", moduleID: module.id, severity: .error, message: "Module '\(module.id)' has unsafe permission write path '\(writePath)'."))
        }
        return warnings
    }

    private static func module(
        id: String,
        title: String,
        enabled: Bool? = nil,
        dependencies: [String] = [],
        directories: [WorkspaceModuleDirectory],
        routes: [WorkspaceModuleRoute],
        projectTabs: [WorkspaceModuleProjectTab] = [],
        workflows: [String] = [],
        artifactKinds: [String] = [],
        approvalScopes: [String] = [],
        writePaths: [String] = []
    ) -> WorkspaceModule {
        WorkspaceModule(
            id: id,
            title: title,
            enabled: enabled ?? defaultEnabledModuleIDs.contains(id),
            dependencies: dependencies,
            directories: directories,
            routes: routes,
            projectTabs: projectTabs,
            workflows: workflows,
            artifactKinds: artifactKinds,
            approvalScopes: approvalScopes,
            permissions: WorkspaceModulePermissions(writePaths: writePaths)
        )
    }

    private static func directory(_ path: String, required: Bool = false, repairable: Bool = true) -> WorkspaceModuleDirectory {
        WorkspaceModuleDirectory(path: path, required: required, repairable: repairable)
    }

    private static func route(_ id: String, _ path: String) -> WorkspaceModuleRoute {
        WorkspaceModuleRoute(id: id, path: path)
    }

    private static func tab(_ id: String, _ title: String) -> WorkspaceModuleProjectTab {
        WorkspaceModuleProjectTab(id: id, title: title)
    }

    private static func normalizePath(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).replacingOccurrences(of: "//", with: "/")
    }
}

public nonisolated enum WorkspaceTemplateRegistry {
    public static let minimal = WorkspaceTemplate(
        id: "minimal-workspace",
        title: "Minimal Workspace",
        enabledModuleIDs: ["projects", "wiki", "tasks", "calendar", "ai-lab"],
        previewDirectories: ["projects", "wiki", "tasks", "settings", ".sci-station/agent"]
    )

    public static let literatureReview = WorkspaceTemplate(
        id: "literature-review",
        title: "Literature Review",
        enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.sorted(),
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
        try writeIfMissing(templateYAML(template), to: root.fileURL(for: Self.templateRelativePath))
        try ensureModulesConfiguration(template, in: root)
    }

    public func overwriteTemplateConfiguration(_ template: WorkspaceTemplate, in root: ResearchRoot) throws {
        try ensureDirectories(for: template, in: root)
        try write(templateYAML(template), to: root.fileURL(for: Self.templateRelativePath))
        try write(configurationYAML(WorkspaceModuleRegistry.configuration(for: template)), to: root.fileURL(for: Self.modulesRelativePath))
    }

    public func loadConfiguration(in root: ResearchRoot) throws -> WorkspaceModuleConfiguration {
        let fileURL = root.fileURL(for: Self.modulesRelativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return WorkspaceModuleRegistry.defaultConfiguration()
        }

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return WorkspaceModuleRegistry.mergedConfiguration(from: try decodeConfiguration(contents))
    }

    public func saveConfiguration(_ configuration: WorkspaceModuleConfiguration, in root: ResearchRoot) throws {
        try write(configurationYAML(WorkspaceModuleRegistry.mergedConfiguration(from: configuration)), to: root.fileURL(for: Self.modulesRelativePath))
    }

    public func preview(for template: WorkspaceTemplate) -> [String] {
        Array(Set(template.previewDirectories + template.settingsFiles)).sorted()
    }

    public nonisolated func configurationYAML(_ configuration: WorkspaceModuleConfiguration) -> String {
        var lines = ["schema_version: \(WorkspaceModuleSchema.currentVersion)", "modules:"]
        for module in configuration.modules {
            lines.append("  - id: \(quoted(module.id))")
            lines.append("    title: \(quoted(module.title))")
            lines.append("    version: \(module.version)")
            lines.append("    enabled: \(module.enabled)")
            lines.append("    pinned: \(module.pinned)")
            appendArray(module.dependencies, key: "dependencies", to: &lines, indentation: "    ")
            appendDirectories(module.directories, to: &lines)
            appendRoutes(module.routes, key: "routes", to: &lines)
            appendProjectTabs(module.projectTabs, to: &lines)
            appendArray(module.workflows, key: "workflows", to: &lines, indentation: "    ")
            appendArray(module.artifactKinds, key: "artifact_kinds", to: &lines, indentation: "    ")
            appendArray(module.approvalScopes, key: "approval_scopes", to: &lines, indentation: "    ")
            lines.append("    permissions:")
            appendArray(module.permissions.writePaths, key: "write_paths", to: &lines, indentation: "      ")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public nonisolated func decodeConfiguration(_ contents: String) throws -> WorkspaceModuleConfiguration {
        let lines = contents.components(separatedBy: .newlines)
        let schemaVersion = parsedSchemaVersion(from: lines)
        let modules = parseModuleBlocks(from: lines).compactMap(parseModule)
        let fallbackModules = modules.isEmpty ? WorkspaceModuleRegistry.builtInModules : modules
        return WorkspaceModuleConfiguration(schemaVersion: max(schemaVersion, WorkspaceModuleSchema.currentVersion), modules: fallbackModules)
    }

    private func ensureDirectories(for template: WorkspaceTemplate, in root: ResearchRoot) throws {
        let modules = WorkspaceModuleRegistry.modules(for: template).filter(\.enabled)
        let directories = Set(template.previewDirectories + modules.flatMap { module in module.directories.map(\.path) })
        for directory in directories where !directory.contains("*") && !directory.hasSuffix(".yaml") {
            try fileManager.createDirectory(at: root.directoryURL(for: directory), withIntermediateDirectories: true)
        }
        try fileManager.createDirectory(at: root.directoryURL(for: "settings"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.directoryURL(for: ".sci-station/agent"), withIntermediateDirectories: true)
    }

    private func ensureModulesConfiguration(_ template: WorkspaceTemplate, in root: ResearchRoot) throws {
        let fileURL = root.fileURL(for: Self.modulesRelativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            try write(configurationYAML(WorkspaceModuleRegistry.configuration(for: template)), to: fileURL)
            return
        }

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let schemaVersion = parsedSchemaVersion(from: contents.components(separatedBy: .newlines))
        if schemaVersion < WorkspaceModuleSchema.currentVersion {
            let decodedConfiguration = (try? decodeConfiguration(contents)) ?? WorkspaceModuleRegistry.configuration(for: template)
            let enabledIDs = decodedConfiguration.modules.filter(\.enabled).map(\.id)
            let migratedConfiguration = WorkspaceModuleRegistry.defaultConfiguration(enabledModuleIDs: Set(enabledIDs.isEmpty ? template.enabledModuleIDs : enabledIDs))
            try write(configurationYAML(migratedConfiguration), to: fileURL)
        }
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

    private nonisolated func appendDirectories(_ directories: [WorkspaceModuleDirectory], to lines: inout [String]) {
        lines.append("    directories:")
        if directories.isEmpty {
            lines.append("      []")
            return
        }
        for directory in directories {
            lines.append("      - path: \(quoted(directory.path))")
            lines.append("        required: \(directory.required)")
            lines.append("        repairable: \(directory.repairable)")
        }
    }

    private nonisolated func appendRoutes(_ routes: [WorkspaceModuleRoute], key: String, to lines: inout [String]) {
        lines.append("    \(key):")
        if routes.isEmpty {
            lines.append("      []")
            return
        }
        for route in routes {
            lines.append("      - id: \(quoted(route.id))")
            lines.append("        path: \(quoted(route.path))")
        }
    }

    private nonisolated func appendProjectTabs(_ tabs: [WorkspaceModuleProjectTab], to lines: inout [String]) {
        lines.append("    project_tabs:")
        if tabs.isEmpty {
            lines.append("      []")
            return
        }
        for tab in tabs {
            lines.append("      - id: \(quoted(tab.id))")
            lines.append("        title: \(quoted(tab.title))")
        }
    }

    private nonisolated func appendArray(_ values: [String], key: String, to lines: inout [String], indentation: String) {
        lines.append("\(indentation)\(key):")
        if values.isEmpty {
            lines.append("\(indentation)  []")
        } else {
            lines.append(contentsOf: values.map { "\(indentation)  - \(quoted($0))" })
        }
    }

    private nonisolated func parseModuleBlocks(from lines: [String]) -> [[String]] {
        var blocks: [[String]] = []
        var currentBlock: [String] = []

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("- id:"), indentation(of: line) <= 2 {
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock)
                }
                currentBlock = [line]
            } else if !currentBlock.isEmpty {
                currentBlock.append(line)
            }
        }

        if !currentBlock.isEmpty {
            blocks.append(currentBlock)
        }
        return blocks
    }

    private nonisolated func parseModule(_ block: [String]) -> WorkspaceModule? {
        var moduleID = ""
        var title = ""
        var version = 1
        var enabled = true
        var pinned = false
        var dependencies: [String] = []
        var directories: [WorkspaceModuleDirectory] = []
        var routes: [WorkspaceModuleRoute] = []
        var projectTabs: [WorkspaceModuleProjectTab] = []
        var workflows: [String] = []
        var artifactKinds: [String] = []
        var approvalScopes: [String] = []
        var writePaths: [String] = []
        var cursor = 0

        while cursor < block.count {
            let line = block[cursor]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("- id:") {
                moduleID = unquoted(value(after: "- id:", in: trimmedLine))
            } else if trimmedLine.hasPrefix("title:") {
                title = unquoted(value(after: "title:", in: trimmedLine))
            } else if trimmedLine.hasPrefix("version:") {
                version = parsedVersion(value(after: "version:", in: trimmedLine))
            } else if trimmedLine.hasPrefix("enabled:") {
                enabled = Bool(value(after: "enabled:", in: trimmedLine)) ?? true
            } else if trimmedLine.hasPrefix("pinned:") {
                pinned = Bool(value(after: "pinned:", in: trimmedLine)) ?? false
            } else if trimmedLine == "dependencies:" {
                let result = parseStringArray(from: block, start: cursor + 1, parentIndentation: indentation(of: line))
                dependencies = result.values
                cursor = result.nextIndex - 1
            } else if trimmedLine == "directories:" {
                let result = parseDirectories(from: block, start: cursor + 1, parentIndentation: indentation(of: line))
                directories = result.values
                cursor = result.nextIndex - 1
            } else if trimmedLine == "routes:" {
                let result = parseRoutes(from: block, start: cursor + 1, parentIndentation: indentation(of: line))
                routes = result.values
                cursor = result.nextIndex - 1
            } else if trimmedLine == "project_tabs:" {
                let result = parseProjectTabs(from: block, start: cursor + 1, parentIndentation: indentation(of: line))
                projectTabs = result.values
                cursor = result.nextIndex - 1
            } else if trimmedLine == "workflows:" {
                let result = parseStringArray(from: block, start: cursor + 1, parentIndentation: indentation(of: line))
                workflows = result.values
                cursor = result.nextIndex - 1
            } else if trimmedLine == "artifact_kinds:" {
                let result = parseStringArray(from: block, start: cursor + 1, parentIndentation: indentation(of: line))
                artifactKinds = result.values
                cursor = result.nextIndex - 1
            } else if trimmedLine == "approval_scopes:" {
                let result = parseStringArray(from: block, start: cursor + 1, parentIndentation: indentation(of: line))
                approvalScopes = result.values
                cursor = result.nextIndex - 1
            } else if trimmedLine == "permissions:" || trimmedLine == "permission_scope:" {
                let result = parsePermissions(from: block, start: cursor + 1, parentIndentation: indentation(of: line))
                writePaths = result.writePaths
                cursor = result.nextIndex - 1
            }
            cursor += 1
        }

        guard !moduleID.isEmpty else {
            return nil
        }

        let builtInModule = WorkspaceModuleRegistry.module(id: moduleID)
        return WorkspaceModule(
            id: moduleID,
            title: title.nilIfEmpty ?? builtInModule?.title ?? moduleID,
            version: version,
            enabled: enabled,
            pinned: pinned,
            dependencies: dependencies.isEmpty ? builtInModule?.dependencies ?? [] : dependencies,
            directories: directories.isEmpty ? builtInModule?.directories ?? [] : directories,
            routes: routes.isEmpty ? builtInModule?.routes ?? [] : routes,
            projectTabs: projectTabs.isEmpty ? builtInModule?.projectTabs ?? [] : projectTabs,
            workflows: workflows.isEmpty ? builtInModule?.workflows ?? [] : workflows,
            artifactKinds: artifactKinds.isEmpty ? builtInModule?.artifactKinds ?? [] : artifactKinds,
            approvalScopes: approvalScopes.isEmpty ? builtInModule?.approvalScopes ?? [] : approvalScopes,
            permissions: WorkspaceModulePermissions(writePaths: writePaths.isEmpty ? builtInModule?.permissions.writePaths ?? [] : writePaths)
        )
    }

    private nonisolated func parseDirectories(from lines: [String], start: Int, parentIndentation: Int) -> (values: [WorkspaceModuleDirectory], nextIndex: Int) {
        var directories: [WorkspaceModuleDirectory] = []
        var cursor = start
        while cursor < lines.count, indentation(of: lines[cursor]) > parentIndentation {
            let line = lines[cursor]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("- path:") {
                let itemIndentation = indentation(of: line)
                var path = unquoted(value(after: "- path:", in: trimmedLine))
                var required = false
                var repairable = true
                cursor += 1
                while cursor < lines.count, indentation(of: lines[cursor]) > itemIndentation {
                    let child = lines[cursor].trimmingCharacters(in: .whitespaces)
                    if child.hasPrefix("required:") {
                        required = Bool(value(after: "required:", in: child)) ?? false
                    } else if child.hasPrefix("repairable:") {
                        repairable = Bool(value(after: "repairable:", in: child)) ?? true
                    } else if child.hasPrefix("path:") {
                        path = unquoted(value(after: "path:", in: child))
                    }
                    cursor += 1
                }
                directories.append(WorkspaceModuleDirectory(path: path, required: required, repairable: repairable))
                continue
            } else if trimmedLine.hasPrefix("- ") {
                let path = unquoted(String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                directories.append(WorkspaceModuleDirectory(path: path, required: false, repairable: true))
            }
            cursor += 1
        }
        return (directories, cursor)
    }

    private nonisolated func parseRoutes(from lines: [String], start: Int, parentIndentation: Int) -> (values: [WorkspaceModuleRoute], nextIndex: Int) {
        var routes: [WorkspaceModuleRoute] = []
        var cursor = start
        while cursor < lines.count, indentation(of: lines[cursor]) > parentIndentation {
            let line = lines[cursor]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("- id:") {
                let itemIndentation = indentation(of: line)
                var routeID = unquoted(value(after: "- id:", in: trimmedLine))
                var path = ""
                cursor += 1
                while cursor < lines.count, indentation(of: lines[cursor]) > itemIndentation {
                    let child = lines[cursor].trimmingCharacters(in: .whitespaces)
                    if child.hasPrefix("id:") {
                        routeID = unquoted(value(after: "id:", in: child))
                    } else if child.hasPrefix("path:") {
                        path = unquoted(value(after: "path:", in: child))
                    }
                    cursor += 1
                }
                if !routeID.isEmpty && !path.isEmpty {
                    routes.append(WorkspaceModuleRoute(id: routeID, path: path))
                }
                continue
            } else if trimmedLine.hasPrefix("- ") {
                let path = unquoted(String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                routes.append(WorkspaceModuleRoute(id: path.replacingOccurrences(of: "/", with: "").nilIfEmpty ?? path, path: path))
            }
            cursor += 1
        }
        return (routes, cursor)
    }

    private nonisolated func parseProjectTabs(from lines: [String], start: Int, parentIndentation: Int) -> (values: [WorkspaceModuleProjectTab], nextIndex: Int) {
        var tabs: [WorkspaceModuleProjectTab] = []
        var cursor = start
        while cursor < lines.count, indentation(of: lines[cursor]) > parentIndentation {
            let line = lines[cursor]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("- id:") {
                let itemIndentation = indentation(of: line)
                var tabID = unquoted(value(after: "- id:", in: trimmedLine))
                var title = ""
                cursor += 1
                while cursor < lines.count, indentation(of: lines[cursor]) > itemIndentation {
                    let child = lines[cursor].trimmingCharacters(in: .whitespaces)
                    if child.hasPrefix("id:") {
                        tabID = unquoted(value(after: "id:", in: child))
                    } else if child.hasPrefix("title:") {
                        title = unquoted(value(after: "title:", in: child))
                    }
                    cursor += 1
                }
                if !tabID.isEmpty {
                    tabs.append(WorkspaceModuleProjectTab(id: tabID, title: title.nilIfEmpty ?? tabID))
                }
                continue
            } else if trimmedLine.hasPrefix("- ") {
                let title = unquoted(String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                tabs.append(WorkspaceModuleProjectTab(id: title.lowercased().replacingOccurrences(of: " ", with: "-"), title: title))
            }
            cursor += 1
        }
        return (tabs, cursor)
    }

    private nonisolated func parsePermissions(from lines: [String], start: Int, parentIndentation: Int) -> (writePaths: [String], nextIndex: Int) {
        var writePaths: [String] = []
        var cursor = start
        while cursor < lines.count, indentation(of: lines[cursor]) > parentIndentation {
            let line = lines[cursor]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine == "write_paths:" {
                let result = parseStringArray(from: lines, start: cursor + 1, parentIndentation: indentation(of: line))
                writePaths = result.values
                cursor = result.nextIndex
                continue
            }
            cursor += 1
        }
        return (writePaths, cursor)
    }

    private nonisolated func parseStringArray(from lines: [String], start: Int, parentIndentation: Int) -> (values: [String], nextIndex: Int) {
        var values: [String] = []
        var cursor = start
        while cursor < lines.count, indentation(of: lines[cursor]) > parentIndentation {
            let trimmedLine = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("- ") {
                values.append(unquoted(String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            }
            cursor += 1
        }
        return (values, cursor)
    }

    private nonisolated func parsedSchemaVersion(from lines: [String]) -> Int {
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("schema_version:") {
                return Int(value(after: "schema_version:", in: trimmedLine)) ?? 0
            }
        }
        return 0
    }

    private nonisolated func parsedVersion(_ rawValue: String) -> Int {
        if let integerVersion = Int(rawValue) {
            return max(1, integerVersion)
        }
        return 1
    }

    private nonisolated func value(after prefix: String, in line: String) -> String {
        line.replacingOccurrences(of: prefix, with: "", options: [], range: line.startIndex..<line.index(line.startIndex, offsetBy: prefix.count))
            .trimmingCharacters(in: .whitespaces)
    }

    private nonisolated func indentation(of line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).count
    }

    private nonisolated func quoted(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private nonisolated func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }

        let startIndex = value.index(after: value.startIndex)
        let endIndex = value.index(before: value.endIndex)
        return value[startIndex..<endIndex]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

private extension Array where Element == WorkspaceModuleArtifactKindDescriptor {
    nonisolated func uniquedByKind() -> [WorkspaceModuleArtifactKindDescriptor] {
        var seenKinds: Set<String> = []
        var descriptors: [WorkspaceModuleArtifactKindDescriptor] = []
        for descriptor in self where !seenKinds.contains(descriptor.kind) {
            seenKinds.insert(descriptor.kind)
            descriptors.append(descriptor)
        }
        return descriptors
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}