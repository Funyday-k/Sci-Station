import Foundation

public nonisolated struct CreateTodoAgentTool: AgentTool {
    private let todoRepository: TodoRepository

    public nonisolated init(todoRepository: TodoRepository) {
        self.todoRepository = todoRepository
    }

    public nonisolated var definition: AgentToolDefinition {
        AgentToolDefinition(
            name: "create_todo",
            summary: "Create a workspace todo item, optionally linked to the selected paper.",
            inputSchema: "{\"title\":\"string\",\"due_date\":\"yyyy-MM-dd optional\",\"priority\":\"low|medium|high|urgent optional\",\"notes\":\"string optional\",\"project_ids\":[\"project id\"],\"tags\":[\"string\"],\"related_paper_ids\":[\"paper id\"]}",
            risk: .writesWorkspace,
            requiresConfirmation: true,
            examples: ["{\"title\":\"Read related work section\",\"priority\":\"high\"}"]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let arguments = try decodeArguments(CreateTodoArguments.self, from: argumentsJSON)
        let trimmedTitle = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw AgentError.invalidArguments("title is required")
        }

        let now = Date()
        let priority = arguments.priority.flatMap(Priority.init(rawValue:)) ?? .medium
        let projectIDs = arguments.projectIDs ?? context.currentProjectID.map { [$0] } ?? []
        let relatedPaperIDs = arguments.relatedPaperIDs ?? context.selectedPaperID.map { [$0] } ?? []
        let todo = TodoItem(
            id: "todo-\(UUID().uuidString.lowercased())",
            title: trimmedTitle,
            status: .open,
            dueDate: try arguments.dueDate.map(parseDay),
            priority: priority,
            projectIDs: projectIDs,
            tags: arguments.tags ?? [],
            relatedPaperIDs: relatedPaperIDs,
            notes: nilIfEmpty(arguments.notes?.trimmingCharacters(in: .whitespacesAndNewlines)),
            externalSource: "sci-station-agent",
            createdAt: now,
            updatedAt: now
        )

        try await todoRepository.upsert(todo, in: context.workspace)

        return AgentToolResult(
            callID: "",
            toolName: definition.name,
            succeeded: true,
            message: "Created todo: \(todo.title)",
            modifiedPaths: ["tasks/todos.yaml"]
        )
    }
}

public nonisolated struct UpdatePaperClassificationAgentTool: AgentTool {
    private let paperRepository: PaperRepository

    public nonisolated init(paperRepository: PaperRepository) {
        self.paperRepository = paperRepository
    }

    public nonisolated var definition: AgentToolDefinition {
        AgentToolDefinition(
            name: "update_paper_classification",
            summary: "Update a paper's tags, categories, project links, reading status, or priority.",
            inputSchema: "{\"paper_id\":\"paper id optional when a paper is selected\",\"tags\":[\"string\"],\"categories\":[\"string\"],\"project_ids\":[\"project id\"],\"core_project_ids\":[\"project id\"],\"add_to_current_project\":true,\"mark_core_in_current_project\":true,\"priority\":\"low|medium|high|urgent optional\",\"status\":\"unread|skimmed|deepRead|summarized|used|rejected optional\"}",
            risk: .writesWorkspace,
            requiresConfirmation: true,
            examples: ["{\"tags\":[\"simulation\",\"dark-matter\"],\"priority\":\"high\"}"]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let arguments = try decodeArguments(UpdatePaperClassificationArguments.self, from: argumentsJSON)
        let paperID = arguments.paperID ?? context.selectedPaperID
        guard let paperID else {
            throw AgentError.missingSelectedPaper
        }

        let papers = try await paperRepository.loadPapers(in: context.workspace)
        guard var paper = papers.first(where: { $0.id == paperID }) else {
            throw AgentError.paperNotFound(paperID)
        }

        if let tags = arguments.tags {
            paper.tags = merged(paper.tags, tags)
        }
        if let categories = arguments.categories {
            paper.categories = merged(paper.categories, categories)
        }
        if let projectIDs = arguments.projectIDs {
            paper.projectIDs = merged(paper.projectIDs, projectIDs)
        }
        if let coreProjectIDs = arguments.coreProjectIDs {
            paper.projectIDs = merged(paper.projectIDs, coreProjectIDs)
            paper.coreProjectIDs = merged(paper.coreProjectIDs, coreProjectIDs)
        }
        if arguments.addToCurrentProject == true, let currentProjectID = context.currentProjectID {
            paper.projectIDs = merged(paper.projectIDs, [currentProjectID])
        }
        if arguments.markCoreInCurrentProject == true, let currentProjectID = context.currentProjectID {
            paper.projectIDs = merged(paper.projectIDs, [currentProjectID])
            paper.coreProjectIDs = merged(paper.coreProjectIDs, [currentProjectID])
        }
        if let priorityValue = arguments.priority {
            guard let priority = Priority(rawValue: priorityValue) else {
                throw AgentError.invalidArguments("Unsupported priority: \(priorityValue)")
            }
            paper.priority = priority
        }
        if let statusValue = arguments.status {
            guard let status = ReadingStatus(rawValue: statusValue) else {
                throw AgentError.invalidArguments("Unsupported status: \(statusValue)")
            }
            paper.status = status
        }

        let savedPaper = try await paperRepository.save(paper, in: context.workspace)
        let metadataPath = savedPaper.paperDirectoryRelativePath + "/meta.yaml"

        return AgentToolResult(
            callID: "",
            toolName: definition.name,
            succeeded: true,
            message: "Updated classification for \(savedPaper.displayTitle).",
            modifiedPaths: [metadataPath]
        )
    }
}

private struct CreateTodoArguments: Decodable {
    var title: String
    var dueDate: String?
    var priority: String?
    var notes: String?
    var projectIDs: [String]?
    var tags: [String]?
    var relatedPaperIDs: [String]?

    private enum CodingKeys: String, CodingKey {
        case title
        case dueDate = "due_date"
        case priority
        case notes
        case projectIDs = "project_ids"
        case tags
        case relatedPaperIDs = "related_paper_ids"
    }
}

private struct UpdatePaperClassificationArguments: Decodable {
    var paperID: String?
    var tags: [String]?
    var categories: [String]?
    var projectIDs: [String]?
    var coreProjectIDs: [String]?
    var addToCurrentProject: Bool?
    var markCoreInCurrentProject: Bool?
    var priority: String?
    var status: String?

    private enum CodingKeys: String, CodingKey {
        case paperID = "paper_id"
        case tags
        case categories
        case projectIDs = "project_ids"
        case coreProjectIDs = "core_project_ids"
        case addToCurrentProject = "add_to_current_project"
        case markCoreInCurrentProject = "mark_core_in_current_project"
        case priority
        case status
    }
}

private func decodeArguments<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    let trimmedJSON = json.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedJSON.isEmpty else {
        throw AgentError.invalidArguments("arguments_json is empty")
    }

    do {
        return try JSONDecoder().decode(type, from: Data(trimmedJSON.utf8))
    } catch {
        throw AgentError.invalidArguments(error.localizedDescription)
    }
}

private func parseDay(_ value: String) throws -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: value) else {
        throw AgentError.invalidArguments("due_date must use yyyy-MM-dd")
    }
    return date
}

private func nilIfEmpty(_ value: String?) -> String? {
    guard let value else {
        return nil
    }
    return value.isEmpty ? nil : value
}

private func merged(_ existing: [String], _ additions: [String]) -> [String] {
    var seen = Set(existing.map { $0.lowercased() })
    var values = existing

    for addition in additions {
        let trimmed = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }
        guard !seen.contains(trimmed.lowercased()) else {
            continue
        }
        values.append(trimmed)
        seen.insert(trimmed.lowercased())
    }

    return values
}