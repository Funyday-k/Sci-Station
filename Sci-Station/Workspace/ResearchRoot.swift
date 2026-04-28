import Foundation

public nonisolated enum ResearchRootCompatibility: String, Codable, Sendable {
    case emptyOrNew
    case researchRoot
    case legacyWorkspace
}

public nonisolated struct ResearchRoot: Identifiable, Equatable, Sendable {
    public struct SeededFile: Sendable {
        public let relativePath: String
        public let contents: String

        public nonisolated init(relativePath: String, contents: String) {
            self.relativePath = relativePath
            self.contents = contents
        }
    }

    public nonisolated static let requiredDirectoryPaths: [String] = [
        "library/papers",
        "library/refs",
        "projects",
        "tasks",
        "settings",
        ".sci-station",
        ".sci-station/agent",
        ".sci-station/agent/copilot-bridge",
        ".sci-station/vscode"
    ]

    public nonisolated static let seededFiles: [SeededFile] = [
        SeededFile(relativePath: "library/refs/library.bib", contents: "% Sci-Station global bibliography\n"),
        SeededFile(relativePath: "library/refs/tags.yaml", contents: "tags: []\n"),
        SeededFile(relativePath: "library/paper_index.yaml", contents: "papers: []\n"),
        SeededFile(relativePath: "tasks/todos.yaml", contents: "todos: []\n"),
        SeededFile(relativePath: "settings/root_preferences.yaml", contents: "schema_version: 1\nactive_project_id: \"\"\n"),
        SeededFile(relativePath: "settings/llm.yaml", contents: "schema_version: 1\n"),
        SeededFile(relativePath: "settings/agent.yaml", contents: "schema_version: 1\nmode: \"plan_only\"\n")
    ]

    public let rootURL: URL

    public nonisolated init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public nonisolated var id: URL {
        rootURL
    }

    public nonisolated var displayName: String {
        rootURL.lastPathComponent
    }

    public nonisolated var projectsURL: URL {
        directoryURL(for: "projects")
    }

    public nonisolated var libraryURL: URL {
        directoryURL(for: "library")
    }

    public nonisolated var globalPapersURL: URL {
        directoryURL(for: "library/papers")
    }

    public nonisolated var settingsURL: URL {
        directoryURL(for: "settings")
    }

    public nonisolated var projectRegistryURL: URL {
        fileURL(for: ".sci-station/project_registry.yaml")
    }

    public nonisolated func directoryURL(for relativePath: String) -> URL {
        resolve(relativePath: relativePath, isDirectory: true)
    }

    public nonisolated func fileURL(for relativePath: String) -> URL {
        resolve(relativePath: relativePath, isDirectory: false)
    }

    public nonisolated func resolve(relativePath: String, isDirectory: Bool) -> URL {
        let components = relativePath.split(separator: "/")

        return components.enumerated().reduce(rootURL) { partialURL, component in
            let isLastComponent = component.offset == components.count - 1
            return partialURL.appendingPathComponent(
                String(component.element),
                isDirectory: isLastComponent ? isDirectory : true
            )
        }
    }

    public nonisolated func missingRequiredItems(using fileManager: FileManager = .default) -> [String] {
        let missingDirectories = Self.requiredDirectoryPaths.filter {
            !fileManager.fileExists(atPath: directoryURL(for: $0).path)
        }
        let missingFiles = Self.seededFiles.map(\.relativePath).filter {
            !fileManager.fileExists(atPath: fileURL(for: $0).path)
        }

        return missingDirectories + missingFiles
    }

    public nonisolated static func compatibility(at rootURL: URL, using fileManager: FileManager = .default) -> ResearchRootCompatibility {
        let root = ResearchRoot(rootURL: rootURL)
        if fileManager.fileExists(atPath: root.projectRegistryURL.path)
            || fileManager.fileExists(atPath: root.directoryURL(for: "library").path)
            || fileManager.fileExists(atPath: root.directoryURL(for: "projects").path) {
            return .researchRoot
        }

        let legacyMarkers = [
            "raw/papers",
            "wiki/projects",
            "refs/library.bib",
            "settings/workspace_preferences.yaml",
            "tasks/todos.yaml"
        ]
        if legacyMarkers.contains(where: { fileManager.fileExists(atPath: root.fileURL(for: $0).path) }) {
            return .legacyWorkspace
        }

        return .emptyOrNew
    }
}

public nonisolated struct ResearchProject: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var colorHex: String
    public var iconName: String
    public var relativePath: String
    public var defaultTags: [String]
    public var isArchived: Bool
    public var isCollapsed: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public nonisolated init(
        id: String,
        name: String,
        description: String = "",
        colorHex: String = "#4F7CAC",
        iconName: String = "folder",
        relativePath: String,
        defaultTags: [String] = [],
        isArchived: Bool = false,
        isCollapsed: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.colorHex = colorHex
        self.iconName = iconName
        self.relativePath = relativePath
        self.defaultTags = defaultTags
        self.isArchived = isArchived
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case colorHex = "color_hex"
        case iconName = "icon_name"
        case relativePath = "relative_path"
        case defaultTags = "default_tags"
        case isArchived = "is_archived"
        case isCollapsed = "is_collapsed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public nonisolated struct ProjectRegistry: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var lastOpenedProjectID: String?
    public var projects: [ResearchProject]

    public nonisolated init(schemaVersion: Int = 1, lastOpenedProjectID: String? = nil, projects: [ResearchProject] = []) {
        self.schemaVersion = schemaVersion
        self.lastOpenedProjectID = lastOpenedProjectID
        self.projects = projects
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case lastOpenedProjectID = "last_opened_project_id"
        case projects
    }
}

public nonisolated enum ProjectRegistryError: LocalizedError, Sendable {
    case projectNameRequired
    case projectNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .projectNameRequired:
            return "Project name is required."
        case let .projectNotFound(id):
            return "No project found with id \(id)."
        }
    }
}

public actor ProjectRegistryRepository {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(in root: ResearchRoot) throws -> ProjectRegistry {
        let fileURL = root.projectRegistryURL
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ProjectRegistry()
        }

        return decode(try String(contentsOf: fileURL, encoding: .utf8))
    }

    public func save(_ registry: ProjectRegistry, in root: ResearchRoot) throws {
        try fileManager.createDirectory(at: root.projectRegistryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(registry).write(to: root.projectRegistryURL, atomically: true, encoding: .utf8)
    }

    @discardableResult
    public func ensureDefaultProject(in root: ResearchRoot, named name: String, compatibility: ResearchRootCompatibility) throws -> ProjectRegistry {
        var registry = try load(in: root)
        if registry.projects.isEmpty {
            let id = uniqueProjectID(from: name.isEmpty ? "main" : name, existingIDs: [])
            let project = ResearchProject(
                id: id,
                name: name.isEmpty ? "Main Project" : name,
                description: compatibility == .legacyWorkspace
                    ? "Default project shell for an existing single-workspace library. Existing files stay in place until migration."
                    : "Default project for this research root.",
                relativePath: "projects/\(id)",
                defaultTags: compatibility == .legacyWorkspace ? ["legacy-workspace"] : []
            )
            registry.projects = [project]
            registry.lastOpenedProjectID = project.id
        } else if registry.lastOpenedProjectID == nil {
            registry.lastOpenedProjectID = registry.projects.first?.id
        }

        for project in registry.projects {
            try ensureProjectStructure(for: project, in: root)
        }
        try save(registry, in: root)
        return registry
    }

    public func createProject(
        named name: String,
        description: String = "",
        colorHex: String = "#4F7CAC",
        iconName: String = "folder",
        in root: ResearchRoot
    ) throws -> ResearchProject {
        var registry = try load(in: root)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProjectRegistryError.projectNameRequired
        }

        let id = uniqueProjectID(from: trimmedName, existingIDs: registry.projects.map(\.id))
        let project = ResearchProject(
            id: id,
            name: trimmedName,
            description: description,
            colorHex: colorHex,
            iconName: iconName,
            relativePath: "projects/\(id)"
        )
        try ensureProjectStructure(for: project, in: root)
        registry.projects.append(project)
        registry.lastOpenedProjectID = project.id
        try save(registry, in: root)
        return project
    }

    public func updateProject(_ project: ResearchProject, in root: ResearchRoot) throws -> ProjectRegistry {
        var registry = try load(in: root)
        guard let index = registry.projects.firstIndex(where: { $0.id == project.id }) else {
            throw ProjectRegistryError.projectNotFound(project.id)
        }

        var updatedProject = project
        updatedProject.name = updatedProject.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updatedProject.name.isEmpty else {
            throw ProjectRegistryError.projectNameRequired
        }
        updatedProject.updatedAt = Date()

        registry.projects[index] = updatedProject
        if registry.lastOpenedProjectID == nil || registry.projects.contains(where: { $0.id == registry.lastOpenedProjectID }) == false {
            registry.lastOpenedProjectID = registry.projects.first(where: { !$0.isArchived })?.id ?? registry.projects.first?.id
        }
        try ensureProjectStructure(for: updatedProject, in: root)
        try save(registry, in: root)
        return registry
    }

    public func setProjectCollapsed(_ projectID: ResearchProject.ID, isCollapsed: Bool, in root: ResearchRoot) throws -> ProjectRegistry {
        var registry = try load(in: root)
        guard let index = registry.projects.firstIndex(where: { $0.id == projectID }) else {
            throw ProjectRegistryError.projectNotFound(projectID)
        }

        registry.projects[index].isCollapsed = isCollapsed
        try save(registry, in: root)
        return registry
    }

    private func ensureProjectStructure(for project: ResearchProject, in root: ResearchRoot) throws {
        let projectURL = root.directoryURL(for: project.relativePath)
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        for relativePath in ["wiki", "tasks", "data", "code", "figures", "outputs"] {
            try fileManager.createDirectory(at: projectURL.appendingPathComponent(relativePath, isDirectory: true), withIntermediateDirectories: true)
        }

        let sharedResearchURL = projectURL.appendingPathComponent("shared_research.md", isDirectory: false)
        if !fileManager.fileExists(atPath: sharedResearchURL.path) {
            try "# Shared Research Context\n\nUse this file to capture project-specific research context.\n".write(to: sharedResearchURL, atomically: true, encoding: .utf8)
        }

        let projectFileURL = projectURL.appendingPathComponent("project.yaml", isDirectory: false)
        try encodeProject(project).write(to: projectFileURL, atomically: true, encoding: .utf8)
    }

    private func uniqueProjectID(from name: String, existingIDs: [String]) -> String {
        let base = slug(from: name).isEmpty ? "project" : slug(from: name)
        var candidate = base
        var suffix = 2
        let existing = Set(existingIDs)
        while existing.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func slug(from value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let scalars = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
    }

    private func encode(_ registry: ProjectRegistry) -> String {
        let lastOpenedProjectID = registry.lastOpenedProjectID.map(quoted) ?? ""
        var lines = [
            "schema_version: \(registry.schemaVersion)",
            "last_opened_project_id: \(lastOpenedProjectID)",
            "projects:"
        ]

        if registry.projects.isEmpty {
            return "schema_version: \(registry.schemaVersion)\nlast_opened_project_id: \(lastOpenedProjectID)\nprojects: []\n"
        }

        for project in registry.projects {
            lines.append(contentsOf: encodeProjectLines(project, indentation: "  - ", continuationIndentation: "    "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func encodeProject(_ project: ResearchProject) -> String {
        encodeProjectLines(project, indentation: "", continuationIndentation: "").joined(separator: "\n") + "\n"
    }

    private func encodeProjectLines(_ project: ResearchProject, indentation: String, continuationIndentation: String) -> [String] {
        let timestampFormatter = makeTimestampFormatter()
        var lines = [
            "\(indentation)id: \(quoted(project.id))",
            "\(continuationIndentation)name: \(quoted(project.name))",
            "\(continuationIndentation)description: \(quoted(project.description))",
            "\(continuationIndentation)color_hex: \(quoted(project.colorHex))",
            "\(continuationIndentation)icon_name: \(quoted(project.iconName))",
            "\(continuationIndentation)relative_path: \(quoted(project.relativePath))"
        ]

        if project.defaultTags.isEmpty {
            lines.append("\(continuationIndentation)default_tags: []")
        } else {
            lines.append("\(continuationIndentation)default_tags:")
            lines.append(contentsOf: project.defaultTags.map { "\(continuationIndentation)  - \(quoted($0))" })
        }

        lines.append("\(continuationIndentation)is_archived: \(project.isArchived)")
        lines.append("\(continuationIndentation)is_collapsed: \(project.isCollapsed)")
        lines.append("\(continuationIndentation)created_at: \(timestampFormatter.string(from: project.createdAt))")
        lines.append("\(continuationIndentation)updated_at: \(timestampFormatter.string(from: project.updatedAt))")
        return lines
    }

    private func decode(_ contents: String) -> ProjectRegistry {
        let lines = contents.components(separatedBy: .newlines)
        var schemaVersion = 1
        var lastOpenedProjectID: String?
        var projects: [ResearchProject] = []
        var cursor = 0

        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("schema_version:") {
                schemaVersion = Int(value(after: "schema_version:", in: trimmed)) ?? 1
            } else if trimmed.hasPrefix("last_opened_project_id:") {
                lastOpenedProjectID = emptyToNil(unquoted(value(after: "last_opened_project_id:", in: trimmed)))
            } else if trimmed.hasPrefix("- id:") {
                let result = decodeProject(from: lines, start: cursor)
                projects.append(result.project)
                cursor = result.nextIndex - 1
            }
            cursor += 1
        }

        return ProjectRegistry(schemaVersion: schemaVersion, lastOpenedProjectID: lastOpenedProjectID, projects: projects)
    }

    private func decodeProject(from lines: [String], start: Int) -> (project: ResearchProject, nextIndex: Int) {
        var id = unquoted(value(after: "- id:", in: lines[start].trimmingCharacters(in: .whitespaces)))
        var name = id
        var description = ""
        var colorHex = "#4F7CAC"
        var iconName = "folder"
        var relativePath = id.isEmpty ? "projects/project" : "projects/\(id)"
        var defaultTags: [String] = []
        var isArchived = false
        var isCollapsed = false
        var createdAt = Date()
        var updatedAt = Date()
        var cursor = start + 1

        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- id:") {
                break
            }
            if trimmed.hasPrefix("id:") {
                id = unquoted(value(after: "id:", in: trimmed))
            } else if trimmed.hasPrefix("name:") {
                name = unquoted(value(after: "name:", in: trimmed))
            } else if trimmed.hasPrefix("description:") {
                description = unquoted(value(after: "description:", in: trimmed))
            } else if trimmed.hasPrefix("color_hex:") {
                colorHex = unquoted(value(after: "color_hex:", in: trimmed))
            } else if trimmed.hasPrefix("icon_name:") {
                iconName = unquoted(value(after: "icon_name:", in: trimmed))
            } else if trimmed.hasPrefix("relative_path:") {
                relativePath = unquoted(value(after: "relative_path:", in: trimmed))
            } else if trimmed == "default_tags:" {
                let result = parseIndentedArray(from: lines, start: cursor + 1)
                defaultTags = result.values
                cursor = result.nextIndex - 1
            } else if trimmed.hasPrefix("is_archived:") {
                isArchived = Bool(value(after: "is_archived:", in: trimmed)) ?? false
            } else if trimmed.hasPrefix("is_collapsed:") {
                isCollapsed = Bool(value(after: "is_collapsed:", in: trimmed)) ?? false
            } else if trimmed.hasPrefix("created_at:") {
                createdAt = parseTimestamp(value(after: "created_at:", in: trimmed)) ?? createdAt
            } else if trimmed.hasPrefix("updated_at:") {
                updatedAt = parseTimestamp(value(after: "updated_at:", in: trimmed)) ?? updatedAt
            }
            cursor += 1
        }

        return (
            ResearchProject(
                id: id,
                name: name,
                description: description,
                colorHex: colorHex,
                iconName: iconName,
                relativePath: relativePath,
                defaultTags: defaultTags,
                isArchived: isArchived,
                isCollapsed: isCollapsed,
                createdAt: createdAt,
                updatedAt: updatedAt
            ),
            cursor
        )
    }

    private func parseIndentedArray(from lines: [String], start: Int) -> (values: [String], nextIndex: Int) {
        var values: [String] = []
        var cursor = start
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else {
                break
            }
            values.append(unquoted(trimmed.replacingOccurrences(of: "-", with: "", options: [], range: trimmed.startIndex..<trimmed.index(after: trimmed.startIndex)).trimmingCharacters(in: .whitespaces)))
            cursor += 1
        }
        return (values, cursor)
    }

    private func value(after prefix: String, in line: String) -> String {
        line.replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespaces)
    }

    private func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private func parseTimestamp(_ value: String) -> Date? {
        makeTimestampFormatter().date(from: value)
    }

    private func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }
        let startIndex = value.index(after: value.startIndex)
        let endIndex = value.index(before: value.endIndex)
        return value[startIndex..<endIndex]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}