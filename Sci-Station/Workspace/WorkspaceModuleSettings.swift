import Darwin
import Foundation

public nonisolated enum ModuleSettingsError: LocalizedError, Equatable, Sendable {
    case unknown(String)
    case dependencyMissing(missing: [String])
    case pendingPermission
    case repairFailed(path: String, reason: String)
    case overrideConflict(projectID: String, moduleID: String)
    case persistFailed(String)
    case unsafePath(String)

    public nonisolated var errorDescription: String? {
        switch self {
        case let .unknown(id):
            return "Unknown workspace module: \(id)."
        case let .dependencyMissing(missing):
            return "Enable required dependencies first: \(missing.sorted().joined(separator: ", "))."
        case .pendingPermission:
            return "This repair is waiting for permission approval."
        case let .repairFailed(path, reason):
            return "Could not repair \(path): \(reason)"
        case let .overrideConflict(projectID, moduleID):
            return "Project \(projectID) has a conflicting override for module \(moduleID)."
        case let .persistFailed(reason):
            return "Could not save workspace module settings: \(reason)"
        case let .unsafePath(path):
            return "Unsafe workspace-relative path: \(path)"
        }
    }
}

public nonisolated enum WorkspaceModuleSettingsMutation {
    public static func pinnedOrder(in configuration: WorkspaceModuleConfiguration) -> [String] {
        configuration.modules.filter(\.pinned).map(\.id)
    }

    public static func setModule(_ id: String, enabled: Bool, in configuration: WorkspaceModuleConfiguration) throws -> WorkspaceModuleConfiguration {
        var updatedConfiguration = configuration
        guard let index = updatedConfiguration.modules.firstIndex(where: { $0.id == id }) else {
            throw ModuleSettingsError.unknown(id)
        }

        if enabled {
            let enabledIDs = updatedConfiguration.enabledModuleIDs
            let missingDependencies = updatedConfiguration.modules[index].dependencies.filter { !enabledIDs.contains($0) }
            if !missingDependencies.isEmpty {
                throw ModuleSettingsError.dependencyMissing(missing: missingDependencies.sorted())
            }
        }

        updatedConfiguration.modules[index].enabled = enabled
        return WorkspaceModuleRegistry.mergedConfiguration(from: updatedConfiguration)
    }

    public static func enableModuleAndDependencies(_ id: String, in configuration: WorkspaceModuleConfiguration) throws -> (configuration: WorkspaceModuleConfiguration, enabledChain: [String]) {
        var updatedConfiguration = configuration
        var enabledChain: [String] = []
        var visiting: Set<String> = []
        var visited: Set<String> = []

        func enable(_ moduleID: String) throws {
            if visited.contains(moduleID) {
                return
            }
            if visiting.contains(moduleID) {
                throw ModuleSettingsError.overrideConflict(projectID: "workspace", moduleID: moduleID)
            }
            guard let index = updatedConfiguration.modules.firstIndex(where: { $0.id == moduleID }) else {
                throw ModuleSettingsError.unknown(moduleID)
            }

            visiting.insert(moduleID)
            for dependency in updatedConfiguration.modules[index].dependencies {
                try enable(dependency)
            }
            visiting.remove(moduleID)
            visited.insert(moduleID)

            if !updatedConfiguration.modules[index].enabled {
                updatedConfiguration.modules[index].enabled = true
                enabledChain.append(moduleID)
            }
        }

        try enable(id)
        return (WorkspaceModuleRegistry.mergedConfiguration(from: updatedConfiguration), enabledChain)
    }

    public static func togglePin(_ id: String, in configuration: WorkspaceModuleConfiguration) throws -> WorkspaceModuleConfiguration {
        var updatedConfiguration = configuration
        guard let index = updatedConfiguration.modules.firstIndex(where: { $0.id == id }) else {
            throw ModuleSettingsError.unknown(id)
        }
        updatedConfiguration.modules[index].pinned.toggle()
        return WorkspaceModuleRegistry.mergedConfiguration(from: updatedConfiguration)
    }

    public static func movePin(_ id: String, newIndex: Int, in configuration: WorkspaceModuleConfiguration) throws -> WorkspaceModuleConfiguration {
        guard configuration.modules.contains(where: { $0.id == id }) else {
            throw ModuleSettingsError.unknown(id)
        }

        var pinnedIDs = configuration.modules.filter(\.pinned).map(\.id)
        guard let currentIndex = pinnedIDs.firstIndex(of: id) else {
            return configuration
        }

        let boundedIndex = max(0, min(newIndex, pinnedIDs.count - 1))
        pinnedIDs.remove(at: currentIndex)
        pinnedIDs.insert(id, at: boundedIndex)

        let modulesByID = Dictionary(uniqueKeysWithValues: configuration.modules.map { ($0.id, $0) })
        let pinnedModules = pinnedIDs.compactMap { modulesByID[$0] }
        let unpinnedModules = configuration.modules.filter { !pinnedIDs.contains($0.id) }
        return WorkspaceModuleRegistry.mergedConfiguration(from: WorkspaceModuleConfiguration(
            schemaVersion: configuration.schemaVersion,
            modules: pinnedModules + unpinnedModules
        ))
    }
}

public nonisolated struct WorkspaceModuleOverrideEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var enabled: Bool

    public nonisolated init(id: String, enabled: Bool) {
        self.id = id
        self.enabled = enabled
    }
}

public nonisolated struct WorkspaceModuleOverride: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var projectID: String
    public var moduleOverrides: [WorkspaceModuleOverrideEntry]
    public var lastUpdatedAt: Date

    public nonisolated init(
        schemaVersion: Int = WorkspaceModuleSchema.currentVersion,
        projectID: String,
        moduleOverrides: [WorkspaceModuleOverrideEntry] = [],
        lastUpdatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.projectID = projectID
        self.moduleOverrides = moduleOverrides
        self.lastUpdatedAt = lastUpdatedAt
    }

    public nonisolated func override(for moduleID: String) -> Bool? {
        moduleOverrides.first { $0.id == moduleID }?.enabled
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case moduleOverrides = "module_overrides"
        case lastUpdatedAt = "last_updated_at"
    }
}

public nonisolated enum ModuleOverrideMerger {
    public static func effectiveConfiguration(
        workspace: WorkspaceModuleConfiguration,
        override: WorkspaceModuleOverride?
    ) -> WorkspaceModuleConfiguration {
        guard let override else {
            return workspace
        }

        let overrideMap = Dictionary(uniqueKeysWithValues: override.moduleOverrides.map { ($0.id, $0.enabled) })
        var mergedModules = workspace.modules
        for index in mergedModules.indices where WorkspaceModuleRegistry.module(id: mergedModules[index].id) != nil {
            if let overrideEnabled = overrideMap[mergedModules[index].id] {
                mergedModules[index].enabled = overrideEnabled
            }
        }
        return WorkspaceModuleConfiguration(schemaVersion: workspace.schemaVersion, modules: mergedModules)
    }
}

public actor WorkspaceModuleOverrideRepository {
    private let fileManager: FileManager
    private let dateProvider: @Sendable () -> Date

    public init(fileManager: FileManager = .default, dateProvider: @escaping @Sendable () -> Date = { Date() }) {
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    public nonisolated static func relativePath(for projectID: String) -> String {
        "projects/\(safeProjectID(projectID))/settings/workspace_modules.override.yaml"
    }

    public func loadOverride(projectID: String, in root: ResearchRoot) throws -> WorkspaceModuleOverride? {
        let fileURL = root.fileURL(for: Self.relativePath(for: projectID))
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return decode(try String(contentsOf: fileURL, encoding: .utf8), fallbackProjectID: projectID)
    }

    public func saveOverride(_ override: WorkspaceModuleOverride, in root: ResearchRoot) throws {
        let fileURL = root.fileURL(for: Self.relativePath(for: override.projectID))
        if override.moduleOverrides.isEmpty {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            return
        }

        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(override).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func setOverride(projectID: String, moduleID: String, enabled: Bool?, in root: ResearchRoot) throws -> WorkspaceModuleOverride? {
        guard WorkspaceModuleRegistry.module(id: moduleID) != nil else {
            throw ModuleSettingsError.unknown(moduleID)
        }

        var override = (try loadOverride(projectID: projectID, in: root)) ?? WorkspaceModuleOverride(projectID: projectID)
        override.moduleOverrides.removeAll { $0.id == moduleID }
        if let enabled {
            override.moduleOverrides.append(WorkspaceModuleOverrideEntry(id: moduleID, enabled: enabled))
        }
        override.moduleOverrides.sort { $0.id < $1.id }
        override.lastUpdatedAt = dateProvider()
        try saveOverride(override, in: root)
        return override.moduleOverrides.isEmpty ? nil : override
    }

    private nonisolated func encode(_ override: WorkspaceModuleOverride) -> String {
        var lines = [
            "schema_version: \(WorkspaceModuleSchema.currentVersion)",
            "project_id: \(quoted(override.projectID))",
            "module_overrides:"
        ]
        if override.moduleOverrides.isEmpty {
            lines.append("  []")
        } else {
            for entry in override.moduleOverrides.sorted(by: { $0.id < $1.id }) {
                lines.append("  - id: \(quoted(entry.id))")
                lines.append("    enabled: \(entry.enabled)")
            }
        }
        lines.append("last_updated_at: \(quoted(Self.formatDate(override.lastUpdatedAt)))")
        return lines.joined(separator: "\n") + "\n"
    }

    private nonisolated func decode(_ contents: String, fallbackProjectID: String) -> WorkspaceModuleOverride {
        let lines = contents.components(separatedBy: .newlines)
        var schemaVersion = WorkspaceModuleSchema.currentVersion
        var projectID = fallbackProjectID
        var moduleOverrides: [WorkspaceModuleOverrideEntry] = []
        var lastUpdatedAt = Date(timeIntervalSince1970: 0)
        var cursor = 0

        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("schema_version:") {
                schemaVersion = Int(value(after: "schema_version:", in: trimmed)) ?? WorkspaceModuleSchema.currentVersion
            } else if trimmed.hasPrefix("project_id:") {
                projectID = unquoted(value(after: "project_id:", in: trimmed)).moduleSettingsNilIfEmpty ?? fallbackProjectID
            } else if trimmed == "module_overrides:" {
                let result = parseOverrideEntries(from: lines, start: cursor + 1, parentIndentation: indentation(of: line))
                moduleOverrides = result.entries
                cursor = result.nextIndex - 1
            } else if trimmed.hasPrefix("last_updated_at:") {
                let rawValue = unquoted(value(after: "last_updated_at:", in: trimmed))
                lastUpdatedAt = Self.parseDate(rawValue) ?? lastUpdatedAt
            }
            cursor += 1
        }

        return WorkspaceModuleOverride(
            schemaVersion: max(schemaVersion, WorkspaceModuleSchema.currentVersion),
            projectID: projectID,
            moduleOverrides: moduleOverrides,
            lastUpdatedAt: lastUpdatedAt
        )
    }

    private nonisolated func parseOverrideEntries(from lines: [String], start: Int, parentIndentation: Int) -> (entries: [WorkspaceModuleOverrideEntry], nextIndex: Int) {
        var entries: [WorkspaceModuleOverrideEntry] = []
        var cursor = start
        while cursor < lines.count, indentation(of: lines[cursor]) > parentIndentation {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- id:") {
                let itemIndentation = indentation(of: line)
                var id = unquoted(value(after: "- id:", in: trimmed))
                var enabled = true
                cursor += 1
                while cursor < lines.count, indentation(of: lines[cursor]) > itemIndentation {
                    let child = lines[cursor].trimmingCharacters(in: .whitespaces)
                    if child.hasPrefix("id:") {
                        id = unquoted(value(after: "id:", in: child))
                    } else if child.hasPrefix("enabled:") {
                        enabled = Bool(value(after: "enabled:", in: child)) ?? true
                    }
                    cursor += 1
                }
                if !id.isEmpty {
                    entries.append(WorkspaceModuleOverrideEntry(id: id, enabled: enabled))
                }
                continue
            }
            cursor += 1
        }
        return (entries, cursor)
    }

    private nonisolated static func safeProjectID(_ projectID: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let replacement = UnicodeScalar("-")
        let safeScalars = String.UnicodeScalarView(projectID.unicodeScalars.map { allowed.contains($0) ? $0 : replacement })
        return String(safeScalars).trimmingCharacters(in: CharacterSet(charactersIn: "-. ")).moduleSettingsNilIfEmpty ?? "project"
    }

    private nonisolated static func formatDate(_ date: Date) -> String {
        makeDateFormatter().string(from: date)
    }

    private nonisolated static func parseDate(_ value: String) -> Date? {
        makeDateFormatter().date(from: value)
    }

    private nonisolated static func makeDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

public actor WorkspaceModuleConfigurationStore {
    public nonisolated struct FileSignature: Equatable, Sendable {
        public var modificationTime: TimeInterval
        public var fileSize: Int
    }

    private nonisolated static let didChangeNotification = Notification.Name("SciStationWorkspaceModuleConfigurationDidChange")

    private let fileManager: FileManager
    private nonisolated let repository: WorkspaceTemplateRepository

    public init(fileManager: FileManager = .default, repository: WorkspaceTemplateRepository? = nil) {
        self.fileManager = fileManager
        self.repository = repository ?? WorkspaceTemplateRepository(fileManager: fileManager)
    }

    public func load(in root: ResearchRoot) throws -> WorkspaceModuleConfiguration {
        try repository.loadConfiguration(in: root)
    }

    public func save(_ configuration: WorkspaceModuleConfiguration, in root: ResearchRoot) throws {
        let mergedConfiguration = WorkspaceModuleRegistry.mergedConfiguration(from: configuration)
        let fileURL = root.fileURL(for: WorkspaceTemplateRepository.modulesRelativePath)
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let temporaryURL = directoryURL.appendingPathComponent(".workspace_modules.yaml.\(UUID().uuidString).tmp", isDirectory: false)
        try repository.configurationYAML(mergedConfiguration).write(to: temporaryURL, atomically: true, encoding: .utf8)
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporaryURL, backupItemName: nil, options: .usingNewMetadataOnly)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: fileURL.path)
    }

    public nonisolated func subscribeChanges(in root: ResearchRoot) -> AsyncStream<WorkspaceModuleConfiguration> {
        let fileURL = root.fileURL(for: WorkspaceTemplateRepository.modulesRelativePath)
        let directoryURL = fileURL.deletingLastPathComponent()
        let repository = self.repository

        return AsyncStream { continuation in
            let descriptor = open(directoryURL.path, O_EVTONLY)
            guard descriptor >= 0 else {
                continuation.finish()
                return
            }

            let queue = DispatchQueue(label: "sci-station.workspace-modules.watch")
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .delete, .rename],
                queue: queue
            )
            var lastSignature = Self.fileSignature(for: fileURL)

            func publishIfChanged(force: Bool = false) {
                let nextSignature = Self.fileSignature(for: fileURL)
                guard nextSignature != nil else {
                    return
                }
                if !force, nextSignature == lastSignature {
                    return
                }
                lastSignature = nextSignature
                if let configuration = try? repository.loadConfiguration(in: root) {
                    continuation.yield(configuration)
                }
            }

            source.setEventHandler {
                publishIfChanged()
            }
            let observer = NotificationCenter.default.addObserver(
                forName: Self.didChangeNotification,
                object: nil,
                queue: nil
            ) { notification in
                guard notification.object as? String == fileURL.path else {
                    return
                }
                queue.async {
                    publishIfChanged(force: true)
                }
            }
            source.setCancelHandler {
                NotificationCenter.default.removeObserver(observer)
                close(descriptor)
            }
            continuation.onTermination = { _ in
                source.cancel()
            }
            source.resume()
        }
    }

    public nonisolated static func fileSignature(for fileURL: URL) -> FileSignature? {
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return nil
        }
        return FileSignature(
            modificationTime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            fileSize: values.fileSize ?? 0
        )
    }
}

public nonisolated enum WorkspaceModuleDirectoryRepairOutcome: Equatable, Sendable {
    case created(paths: [String])
    case skippedWildcard(path: String)
    case denied(path: String, reason: String)
    case failed(path: String, reason: String)

    public nonisolated var debugOutcome: String {
        switch self {
        case .created:
            return "created"
        case .skippedWildcard:
            return "skipped_wildcard"
        case .denied:
            return "denied"
        case .failed:
            return "failed"
        }
    }
}

public struct WorkspaceModuleDirectoryRepairer {
    public typealias ApprovalHandler = @Sendable (AgentPermissionRequest) async -> AgentPermissionDecision

    private let fileManager: FileManager
    private let approvalHandler: ApprovalHandler

    public init(
        fileManager: FileManager = .default,
        approvalHandler: @escaping ApprovalHandler = { request in
            AgentPermissionEvaluator(rules: AgentSafetyPreset.defaultPermissionRules()).evaluate(request)
        }
    ) {
        self.fileManager = fileManager
        self.approvalHandler = approvalHandler
    }

    public func repair(
        _ status: WorkspaceModuleDirectoryStatus,
        in root: ResearchRoot,
        activeProjects: [ResearchProject] = []
    ) async -> WorkspaceModuleDirectoryRepairOutcome {
        guard status.repairable else {
            return .denied(path: status.path, reason: "Directory is not marked repairable.")
        }
        guard let module = WorkspaceModuleRegistry.module(id: status.moduleID) else {
            return .failed(path: status.path, reason: ModuleSettingsError.unknown(status.moduleID).localizedDescription)
        }

        let pathsToCreate = expandedRepairPaths(for: status.path, activeProjects: activeProjects)
        guard !pathsToCreate.isEmpty else {
            return .skippedWildcard(path: status.path)
        }

        for path in pathsToCreate {
            guard WorkspaceModuleSchema.isSafeRelativePathPattern(path), !path.contains("*") else {
                return .failed(path: path, reason: ModuleSettingsError.unsafePath(path).localizedDescription)
            }
            guard module.permissions.writePaths.contains(where: { WorkspaceModuleRegistry.path(pattern: $0, matches: path) }) else {
                return .denied(path: path, reason: "Path is outside module write permissions.")
            }
        }

        let decision = await approvalHandler(AgentPermissionRequest(
            toolName: "module_settings.repair_directory",
            permissionKey: AgentToolRisk.writesWorkspace.defaultPermissionKey,
            command: "create_directory",
            path: status.path,
            risk: .writesWorkspace
        ))
        guard decision.action == .allow else {
            return .denied(path: status.path, reason: decision.message ?? "Permission was not approved.")
        }

        do {
            for path in pathsToCreate {
                try fileManager.createDirectory(at: root.directoryURL(for: path), withIntermediateDirectories: true)
            }
            return .created(paths: pathsToCreate)
        } catch {
            return .failed(path: status.path, reason: error.localizedDescription)
        }
    }

    private nonisolated func expandedRepairPaths(for path: String, activeProjects: [ResearchProject]) -> [String] {
        guard path.contains("*") else {
            return [normalizedDirectoryPath(path)]
        }

        guard path.contains("projects/*/"), !activeProjects.isEmpty else {
            return []
        }

        let suffix = path.replacingOccurrences(of: "projects/*/", with: "")
        return activeProjects.map { project in
            normalizedDirectoryPath(project.relativePath + "/" + suffix)
        }
    }

    private nonisolated func normalizedDirectoryPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }
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

private nonisolated func value(after prefix: String, in line: String) -> String {
    line.replacingOccurrences(of: prefix, with: "", options: [], range: line.startIndex..<line.index(line.startIndex, offsetBy: prefix.count))
        .trimmingCharacters(in: .whitespaces)
}

private nonisolated func indentation(of line: String) -> Int {
    line.prefix(while: { $0 == " " || $0 == "\t" }).count
}

private extension String {
    nonisolated var moduleSettingsNilIfEmpty: String? {
        isEmpty ? nil : self
    }
}