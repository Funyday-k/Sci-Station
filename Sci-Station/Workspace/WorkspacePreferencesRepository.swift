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
        lines.append("pinned_top_level_order:")
        lines.append(contentsOf: preferences.pinnedTopLevelOrder.map { "  - \(quoted($0))" })
        lines.append("project_space_pinned_order:")
        lines.append(contentsOf: preferences.projectSpacePinnedOrder.map { "  - \(quoted($0))" })
        if let lastRoute = preferences.lastRoute {
            lines.append("last_route:")
            lines.append("  top: \(quoted(lastRoute.top.rawValue))")
            lines.append("  project_id: \(lastRoute.projectID.map(quoted) ?? "")")
            lines.append("  project_tab_id: \(lastRoute.projectTabID.map(quoted) ?? "")")
            lines.append("  secondary_selection: \(lastRoute.secondarySelection.map(quoted) ?? "")")
        }
        lines.append("right_rail_mode: \(quoted(preferences.rightRailMode.rawValue))")
        lines.append("global_ai_panel_open: \(preferences.isGlobalAIPanelOpen)")
        lines.append("project_tree_expanded: \(preferences.isProjectTreeExpanded)")
        appendHomeWidgetLayout(preferences.homeWidgetLayout, to: &lines)
        lines.append("pinned_project_ids:")
        lines.append(contentsOf: preferences.pinnedProjectIDs.map { "  - \(quoted($0))" })
        lines.append("sync_todos_to_apple_reminders: \(preferences.syncTodosToAppleReminders)")
        lines.append("app_language: \(quoted(preferences.appLanguage.rawValue))")
        lines.append("agent_chat_font_size: \(preferences.agentChatFontSize)")
        lines.append("agent_runtime_selection: \(quoted(preferences.agentRuntimeSelection.rawValue))")
        lines.append("agent_sidecar_disabled_for_workspace: \(preferences.isSidecarDisabledForWorkspace)")
        lines.append("agent_debug_logging_enabled: \(preferences.agentDebugLoggingEnabled)")
        lines.append("agent_loop_budget:")
        lines.append("  max_steps: \(preferences.agentLoopBudget.maxSteps)")
        lines.append("  max_tool_calls: \(preferences.agentLoopBudget.maxToolCalls)")
        lines.append("  max_context_characters: \(preferences.agentLoopBudget.maxContextCharacters)")
        lines.append("  max_tool_result_characters_per_call: \(preferences.agentLoopBudget.maxToolResultCharactersPerCall)")
        lines.append("  max_accumulated_tool_result_characters: \(preferences.agentLoopBudget.maxAccumulatedToolResultCharacters)")
        lines.append("  auto_approve_read_only: \(preferences.agentLoopBudget.autoApproveReadOnly)")
        lines.append("  allow_provider_native_tools: \(preferences.agentLoopBudget.allowProviderNativeTools)")
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
        var pinnedTopLevelOrder = WorkspacePreferences.defaultPinnedTopLevelOrder
        var projectSpacePinnedOrder: [String] = []
        var lastRoute: WorkspaceRoute?
        var rightRailMode = RightRailMode.inspector
        var isGlobalAIPanelOpen = false
        var isProjectTreeExpanded = true
        var homeWidgetLayout = HomeWidgetLayout.defaultLayout()
        var pinnedProjectIDs: [String] = []
        var syncTodosToAppleReminders = true
        var appLanguage = AppLanguagePreference.system
        var agentChatFontSize = WorkspacePreferences.defaultAgentChatFontSize
        var agentRuntimeSelection = AgentRuntimeSelection.autoFallback
        var isSidecarDisabledForWorkspace = false
        var agentDebugLoggingEnabled = false
        var agentLoopBudget = WorkspacePreferences.defaultAgentLoopBudget
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
            } else if trimmed == "pinned_top_level_order:" {
                let result = parseIndentedArray(from: lines, start: cursor + 1)
                pinnedTopLevelOrder = result.values.isEmpty ? WorkspacePreferences.defaultPinnedTopLevelOrder : result.values
                cursor = result.nextIndex - 1
            } else if trimmed == "project_space_pinned_order:" {
                let result = parseIndentedArray(from: lines, start: cursor + 1)
                projectSpacePinnedOrder = result.values
                cursor = result.nextIndex - 1
            } else if trimmed == "last_route:" {
                let result = parseWorkspaceRoute(from: lines, start: cursor + 1)
                lastRoute = result.value
                cursor = result.nextIndex - 1
            } else if trimmed.hasPrefix("right_rail_mode:") {
                let value = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "right_rail_mode:", with: "").trimmingCharacters(in: .whitespaces)))
                rightRailMode = value.flatMap(RightRailMode.init(rawValue:)) ?? .hidden
            } else if trimmed.hasPrefix("global_ai_panel_open:") {
                let value = trimmed.replacingOccurrences(of: "global_ai_panel_open:", with: "").trimmingCharacters(in: .whitespaces)
                isGlobalAIPanelOpen = Bool(value) ?? false
            } else if trimmed.hasPrefix("project_tree_expanded:") {
                let value = trimmed.replacingOccurrences(of: "project_tree_expanded:", with: "").trimmingCharacters(in: .whitespaces)
                isProjectTreeExpanded = Bool(value) ?? true
            } else if trimmed == "home_widget_layout:" {
                let result = parseHomeWidgetLayout(from: lines, start: cursor + 1)
                homeWidgetLayout = result.value
                cursor = result.nextIndex - 1
            } else if trimmed == "pinned_project_ids:" {
                let result = parseIndentedArray(from: lines, start: cursor + 1)
                pinnedProjectIDs = result.values
                cursor = result.nextIndex - 1
            } else if trimmed.hasPrefix("sync_todos_to_apple_reminders:") {
                let value = trimmed.replacingOccurrences(of: "sync_todos_to_apple_reminders:", with: "").trimmingCharacters(in: .whitespaces)
                syncTodosToAppleReminders = Bool(value) ?? true
            } else if trimmed.hasPrefix("app_language:") {
                let value = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "app_language:", with: "").trimmingCharacters(in: .whitespaces)))
                appLanguage = value.flatMap(AppLanguagePreference.init(rawValue:)) ?? .system
            } else if trimmed.hasPrefix("agent_chat_font_size:") {
                let value = trimmed.replacingOccurrences(of: "agent_chat_font_size:", with: "").trimmingCharacters(in: .whitespaces)
                agentChatFontSize = Double(value) ?? WorkspacePreferences.defaultAgentChatFontSize
            } else if trimmed.hasPrefix("agent_runtime_selection:") {
                let value = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "agent_runtime_selection:", with: "").trimmingCharacters(in: .whitespaces)))
                agentRuntimeSelection = value.flatMap(AgentRuntimeSelection.init(rawValue:)) ?? .autoFallback
            } else if trimmed.hasPrefix("agent_sidecar_disabled_for_workspace:") {
                let value = trimmed.replacingOccurrences(of: "agent_sidecar_disabled_for_workspace:", with: "").trimmingCharacters(in: .whitespaces)
                isSidecarDisabledForWorkspace = Bool(value) ?? false
            } else if trimmed.hasPrefix("agent_debug_logging_enabled:") {
                let value = trimmed.replacingOccurrences(of: "agent_debug_logging_enabled:", with: "").trimmingCharacters(in: .whitespaces)
                agentDebugLoggingEnabled = Bool(value) ?? false
            } else if trimmed == "agent_loop_budget:" {
                let result = parseAgentLoopBudget(from: lines, start: cursor + 1)
                agentLoopBudget = result.value
                cursor = result.nextIndex - 1
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
            pinnedTopLevelOrder: pinnedTopLevelOrder,
            projectSpacePinnedOrder: projectSpacePinnedOrder,
            lastRoute: lastRoute,
            rightRailMode: rightRailMode,
            isGlobalAIPanelOpen: isGlobalAIPanelOpen,
            isProjectTreeExpanded: isProjectTreeExpanded,
            homeWidgetLayout: homeWidgetLayout,
            pinnedProjectIDs: pinnedProjectIDs,
            syncTodosToAppleReminders: syncTodosToAppleReminders,
            appLanguage: appLanguage,
            agentChatFontSize: agentChatFontSize,
            agentRuntimeSelection: agentRuntimeSelection,
            isSidecarDisabledForWorkspace: isSidecarDisabledForWorkspace,
            agentDebugLoggingEnabled: agentDebugLoggingEnabled,
            agentLoopBudget: agentLoopBudget,
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

    private nonisolated func appendHomeWidgetLayout(_ layout: HomeWidgetLayout, to lines: inout [String]) {
        let normalizedLayout = layout.normalized(descriptors: HomeWidgetRegistry.defaultDescriptors, columns: 4)
        lines.append("home_widget_layout:")
        lines.append("  schema_version: \(HomeWidgetLayout.currentSchemaVersion)")
        lines.append("  updated_at: \(quoted(formatDate(normalizedLayout.updatedAt)))")
        lines.append("  items:")
        for item in normalizedLayout.items {
            lines.append("    - widget_id: \(quoted(item.widgetID))")
            lines.append("      size: \(quoted(item.size.rawValue))")
            lines.append("      column: \(item.column)")
            lines.append("      row: \(item.row)")
            lines.append("      is_enabled: \(item.isEnabled)")
        }
    }

    private nonisolated func parseHomeWidgetLayout(from lines: [String], start: Int) -> (value: HomeWidgetLayout, nextIndex: Int) {
        var schemaVersion = HomeWidgetLayout.currentSchemaVersion
        var updatedAt = Date(timeIntervalSince1970: 0)
        var items: [HomeWidgetLayoutItem] = []
        var cursor = start

        while cursor < lines.count, lines[cursor].hasPrefix("  ") {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("schema_version:") {
                let value = trimmed.replacingOccurrences(of: "schema_version:", with: "").trimmingCharacters(in: .whitespaces)
                schemaVersion = Int(value) ?? HomeWidgetLayout.currentSchemaVersion
                cursor += 1
            } else if trimmed.hasPrefix("updated_at:") {
                let value = emptyToNil(unquoted(trimmed.replacingOccurrences(of: "updated_at:", with: "").trimmingCharacters(in: .whitespaces)))
                updatedAt = value.flatMap(parseDate) ?? Date(timeIntervalSince1970: 0)
                cursor += 1
            } else if trimmed == "items:" {
                let result = parseHomeWidgetItems(from: lines, start: cursor + 1)
                items = result.values
                cursor = result.nextIndex
            } else {
                cursor += 1
            }
        }

        let layout = HomeWidgetLayout(schemaVersion: schemaVersion, items: items, updatedAt: updatedAt)
        if items.isEmpty {
            return (HomeWidgetLayout.defaultLayout(), cursor)
        }
        return (layout.normalized(descriptors: HomeWidgetRegistry.defaultDescriptors, columns: 4), cursor)
    }

    private nonisolated func parseHomeWidgetItems(from lines: [String], start: Int) -> (values: [HomeWidgetLayoutItem], nextIndex: Int) {
        var values: [HomeWidgetLayoutItem] = []
        var cursor = start

        while cursor < lines.count, lines[cursor].hasPrefix("    ") {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else {
                break
            }

            var fields: [String: String] = [:]
            let firstField = trimmed.replacingOccurrences(of: "-", with: "", options: [], range: trimmed.startIndex..<trimmed.index(after: trimmed.startIndex)).trimmingCharacters(in: .whitespaces)
            if let pair = parseKeyValue(firstField) {
                fields[pair.key] = pair.value
            }
            cursor += 1

            while cursor < lines.count, lines[cursor].hasPrefix("      ") {
                let itemLine = lines[cursor].trimmingCharacters(in: .whitespaces)
                guard let pair = parseKeyValue(itemLine) else {
                    break
                }
                fields[pair.key] = pair.value
                cursor += 1
            }

            guard let widgetID = fields["widget_id"].map(unquoted),
                  !widgetID.isEmpty else {
                continue
            }
            values.append(HomeWidgetLayoutItem(
                widgetID: widgetID,
                size: fields["size"].map(unquoted).flatMap(HomeWidgetSize.init(rawValue:)) ?? .medium,
                column: fields["column"].flatMap(Int.init) ?? 0,
                row: fields["row"].flatMap(Int.init) ?? 0,
                isEnabled: fields["is_enabled"].flatMap(Bool.init) ?? true
            ))
        }

        return (values, cursor)
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

    private nonisolated func parseAgentLoopBudget(from lines: [String], start: Int) -> (value: AgentLoopOptions, nextIndex: Int) {
        var budget = WorkspacePreferences.defaultAgentLoopBudget
        var cursor = start

        while cursor < lines.count, lines[cursor].hasPrefix("  ") {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                break
            }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "max_steps":
                budget.maxSteps = max(1, Int(value) ?? budget.maxSteps)
            case "max_tool_calls":
                budget.maxToolCalls = max(1, Int(value) ?? budget.maxToolCalls)
            case "max_context_characters":
                budget.maxContextCharacters = max(1_000, Int(value) ?? budget.maxContextCharacters)
            case "max_tool_result_characters_per_call":
                budget.maxToolResultCharactersPerCall = max(1_000, Int(value) ?? budget.maxToolResultCharactersPerCall)
            case "max_accumulated_tool_result_characters":
                budget.maxAccumulatedToolResultCharacters = max(1_000, Int(value) ?? budget.maxAccumulatedToolResultCharacters)
            case "auto_approve_read_only":
                budget.autoApproveReadOnly = Bool(value) ?? budget.autoApproveReadOnly
            case "allow_provider_native_tools":
                budget.allowProviderNativeTools = Bool(value) ?? budget.allowProviderNativeTools
            default:
                break
            }
            cursor += 1
        }

        return (budget, cursor)
    }

    private nonisolated func parseWorkspaceRoute(from lines: [String], start: Int) -> (value: WorkspaceRoute?, nextIndex: Int) {
        var values: [String: String] = [:]
        var cursor = start

        while cursor < lines.count, lines[cursor].hasPrefix("  ") {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                break
            }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = emptyToNil(unquoted(parts[1].trimmingCharacters(in: .whitespaces)))
            values[key] = value
            cursor += 1
        }

        guard let topValue = values["top"], let top = workspaceRouteTop(from: topValue) else {
            return (nil, cursor)
        }

        return (WorkspaceRoute(
            top: top,
            projectID: values["project_id"] ?? nil,
            projectTabID: values["project_tab_id"] ?? nil,
            secondarySelection: values["secondary_selection"] ?? nil
        ), cursor)
    }

    private nonisolated func workspaceRouteTop(from value: String) -> WorkspaceRoute.Top? {
        if let top = WorkspaceRoute.Top(rawValue: value) {
            return top
        }
        switch value {
        case "dashboard":
            return .home
        case "aiLab", "ai_lab", "llmLab", "llm-lab":
            return .aiLab
        default:
            return nil
        }
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

    private nonisolated func parseKeyValue(_ line: String) -> (key: String, value: String)? {
        let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return nil
        }
        return (parts[0].trimmingCharacters(in: .whitespaces), parts[1].trimmingCharacters(in: .whitespaces))
    }

    private nonisolated func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private nonisolated func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
