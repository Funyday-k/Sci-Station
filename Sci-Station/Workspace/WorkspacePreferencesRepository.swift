import Foundation

public actor WorkspacePreferencesRepository {
    public static let relativePath = "settings/workspace_preferences.yaml"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(in workspace: ResearchWorkspace) throws -> WorkspacePreferences {
        let fileURL = workspace.fileURL(for: Self.relativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return WorkspacePreferences()
        }

        return decode(try String(contentsOf: fileURL, encoding: .utf8))
    }

    public func save(_ preferences: WorkspacePreferences, in workspace: ResearchWorkspace) throws {
        let fileURL = workspace.fileURL(for: Self.relativePath)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(preferences).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private nonisolated func encode(_ preferences: WorkspacePreferences) -> String {
        var lines = [
            "schema_version: \(preferences.schemaVersion)",
            "library_visible_columns:"
        ]
        lines.append(contentsOf: preferences.libraryVisibleColumns.map { "  - \(quoted($0))" })
        lines.append("library_sort_field: \(preferences.librarySortState.field.map { quoted($0.rawValue) } ?? "")")
        lines.append("library_sort_ascending: \(preferences.librarySortState.isAscending)")
        let defaultCollection = preferences.defaultCollectionPath.map(quoted) ?? ""
        let recentSection = preferences.recentSection.map(quoted) ?? ""
        lines.append("default_collection: \(defaultCollection)")
        lines.append("recent_section: \(recentSection)")
        lines.append("sync_todos_to_apple_reminders: \(preferences.syncTodosToAppleReminders)")
        lines.append("app_language: \(quoted(preferences.appLanguage.rawValue))")
        lines.append("agent_chat_font_size: \(preferences.agentChatFontSize)")
        lines.append("mineru_command: \(quoted(preferences.minerUCommand))")
        lines.append("mineru_api_base_url: \(quoted(preferences.minerUAPIBaseURLString))")
        lines.append("mineru_api_language: \(quoted(preferences.minerUAPILanguage))")
        lines.append("mineru_overwrite_existing_markdown: \(preferences.minerUOverwriteExistingMarkdown)")
        if let agentKnowledgePaperIDs = preferences.agentKnowledgePaperIDs {
            lines.append("agent_knowledge_paper_ids:")
            lines.append(contentsOf: agentKnowledgePaperIDs.sorted().map { "  - \(quoted($0))" })
        }
        appendStringArrayMap(preferences.agentDisabledToolNamesByScope, key: "agent_disabled_tool_names_by_scope", to: &lines)
        appendStringArrayMap(preferences.pinnedAgentThreadIDsByProject, key: "pinned_agent_thread_ids_by_project", to: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    private nonisolated func decode(_ contents: String) -> WorkspacePreferences {
        let lines = contents.components(separatedBy: .newlines)
        var schemaVersion = WorkspacePreferences.currentSchemaVersion
        var libraryVisibleColumns: [String] = []
        var librarySortField: LibrarySortField?
        var librarySortAscending = true
        var defaultCollectionPath: String?
        var recentSection: String?
        var syncTodosToAppleReminders = true
        var appLanguage = AppLanguagePreference.system
        var agentChatFontSize = WorkspacePreferences.defaultAgentChatFontSize
        var agentKnowledgePaperIDs: [String]?
        var agentDisabledToolNamesByScope: [String: [String]] = [:]
        var pinnedAgentThreadIDsByProject: [String: [String]] = [:]
        var minerUCommand = "mineru"
        var minerUAPIBaseURLString = "https://mineru.net"
        var minerUAPILanguage = "en"
        var minerUOverwriteExistingMarkdown = true
        var cursor = 0

        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("schema_version:") {
                let value = trimmed.replacingOccurrences(of: "schema_version:", with: "").trimmingCharacters(in: .whitespaces)
                schemaVersion = Int(value) ?? WorkspacePreferences.currentSchemaVersion
            } else if trimmed == "library_visible_columns:" {
                let result = parseIndentedArray(from: lines, start: cursor + 1)
                libraryVisibleColumns = result.values
                cursor = result.nextIndex - 1
            } else if trimmed.hasPrefix("library_sort_field:") {
                let value = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "library_sort_field:", with: "").trimmingCharacters(in: .whitespaces)))
                librarySortField = value.flatMap(LibrarySortField.init(rawValue:))
            } else if trimmed.hasPrefix("library_sort_ascending:") {
                let value = trimmed.replacingOccurrences(of: "library_sort_ascending:", with: "").trimmingCharacters(in: .whitespaces)
                librarySortAscending = Bool(value) ?? true
            } else if trimmed.hasPrefix("default_collection:") {
                defaultCollectionPath = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "default_collection:", with: "").trimmingCharacters(in: .whitespaces)))
            } else if trimmed.hasPrefix("recent_section:") {
                recentSection = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "recent_section:", with: "").trimmingCharacters(in: .whitespaces)))
            } else if trimmed.hasPrefix("sync_todos_to_apple_reminders:") {
                let value = trimmed.replacingOccurrences(of: "sync_todos_to_apple_reminders:", with: "").trimmingCharacters(in: .whitespaces)
                syncTodosToAppleReminders = Bool(value) ?? true
            } else if trimmed.hasPrefix("app_language:") {
                let value = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "app_language:", with: "").trimmingCharacters(in: .whitespaces)))
                appLanguage = value.flatMap(AppLanguagePreference.init(rawValue:)) ?? .system
            } else if trimmed.hasPrefix("agent_chat_font_size:") {
                let value = trimmed.replacingOccurrences(of: "agent_chat_font_size:", with: "").trimmingCharacters(in: .whitespaces)
                agentChatFontSize = Double(value) ?? WorkspacePreferences.defaultAgentChatFontSize
            } else if trimmed.hasPrefix("mineru_command:") {
                minerUCommand = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "mineru_command:", with: "").trimmingCharacters(in: .whitespaces))) ?? "mineru"
            } else if trimmed.hasPrefix("mineru_api_base_url:") {
                minerUAPIBaseURLString = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "mineru_api_base_url:", with: "").trimmingCharacters(in: .whitespaces))) ?? "https://mineru.net"
            } else if trimmed.hasPrefix("mineru_api_language:") {
                minerUAPILanguage = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "mineru_api_language:", with: "").trimmingCharacters(in: .whitespaces))) ?? "en"
            } else if trimmed.hasPrefix("mineru_overwrite_existing_markdown:") {
                let value = trimmed.replacingOccurrences(of: "mineru_overwrite_existing_markdown:", with: "").trimmingCharacters(in: .whitespaces)
                minerUOverwriteExistingMarkdown = Bool(value) ?? true
            } else if trimmed == "agent_knowledge_paper_ids:" {
                let result = parseIndentedArray(from: lines, start: cursor + 1)
                agentKnowledgePaperIDs = result.values
                cursor = result.nextIndex - 1
            } else if trimmed == "agent_disabled_tool_names_by_scope:" {
                let result = parseIndentedStringArrayMap(from: lines, start: cursor + 1)
                agentDisabledToolNamesByScope = result.values
                cursor = result.nextIndex - 1
            } else if trimmed == "pinned_agent_thread_ids_by_project:" {
                let result = parseIndentedStringArrayMap(from: lines, start: cursor + 1)
                pinnedAgentThreadIDsByProject = result.values
                cursor = result.nextIndex - 1
            }
            cursor += 1
        }

        return WorkspacePreferences(
            schemaVersion: schemaVersion,
            libraryVisibleColumns: libraryVisibleColumns,
            librarySortState: LibrarySortState(field: librarySortField, isAscending: librarySortAscending),
            defaultCollectionPath: defaultCollectionPath,
            recentSection: recentSection,
            syncTodosToAppleReminders: syncTodosToAppleReminders,
            appLanguage: appLanguage,
            agentChatFontSize: agentChatFontSize,
            agentKnowledgePaperIDs: agentKnowledgePaperIDs,
            agentDisabledToolNamesByScope: agentDisabledToolNamesByScope,
            pinnedAgentThreadIDsByProject: pinnedAgentThreadIDsByProject,
            minerUCommand: minerUCommand,
            minerUAPIBaseURLString: minerUAPIBaseURLString,
            minerUAPILanguage: minerUAPILanguage,
            minerUOverwriteExistingMarkdown: minerUOverwriteExistingMarkdown
        )
    }

    private nonisolated func appendStringArrayMap(_ map: [String: [String]], key: String, to lines: inout [String]) {
        guard !map.isEmpty else {
            return
        }

        lines.append("\(key):")
        for scope in map.keys.sorted() {
            let values = Array(Set(map[scope] ?? [])).sorted()
            lines.append("  \(quoted(scope)):")
            lines.append(contentsOf: values.map { "    - \(quoted($0))" })
        }
    }

    private nonisolated func parseIndentedStringArrayMap(from lines: [String], start: Int) -> (values: [String: [String]], nextIndex: Int) {
        var values: [String: [String]] = [:]
        var cursor = start

        while cursor < lines.count {
            let line = lines[cursor]
            guard line.hasPrefix("  ") else {
                break
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix(":"), !trimmed.hasPrefix("-") else {
                break
            }

            let key = unquoted(String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces))
            cursor += 1

            var mappedValues: [String] = []
            while cursor < lines.count, lines[cursor].hasPrefix("    ") {
                let item = lines[cursor].trimmingCharacters(in: .whitespaces)
                guard item.hasPrefix("-") else {
                    break
                }
                mappedValues.append(unquoted(item.replacingOccurrences(of: "-", with: "", options: [], range: item.startIndex..<item.index(after: item.startIndex)).trimmingCharacters(in: .whitespaces)))
                cursor += 1
            }
            values[key] = mappedValues
        }

        return (values, cursor)
    }

    private nonisolated func parseIndentedArray(from lines: [String], start: Int) -> (values: [String], nextIndex: Int) {
        var values: [String] = []
        var cursor = start

        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("-") {
                break
            }

            values.append(unquoted(trimmed.replacingOccurrences(of: "-", with: "", options: [], range: trimmed.startIndex..<trimmed.index(after: trimmed.startIndex)).trimmingCharacters(in: .whitespaces)))
            cursor += 1
        }

        return (values, cursor)
    }

    private nonisolated func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
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

    private nonisolated func emptyToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
