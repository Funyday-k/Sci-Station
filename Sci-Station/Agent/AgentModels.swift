import Foundation

public nonisolated enum AgentRunMode: String, Codable, Sendable {
    case planOnly
    case executeApproved
}

public nonisolated enum AgentToolRisk: String, Codable, Sendable {
    case readOnly
    case writesWorkspace
    case externalSideEffect
}

public nonisolated struct AgentToolDefinition: Codable, Hashable, Sendable {
    public var name: String
    public var summary: String
    public var inputSchema: String
    public var risk: AgentToolRisk
    public var requiresConfirmation: Bool
    public var examples: [String]

    public nonisolated init(
        name: String,
        summary: String,
        inputSchema: String,
        risk: AgentToolRisk,
        requiresConfirmation: Bool,
        examples: [String] = []
    ) {
        self.name = name
        self.summary = summary
        self.inputSchema = inputSchema
        self.risk = risk
        self.requiresConfirmation = requiresConfirmation
        self.examples = examples
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case summary
        case inputSchema = "input_schema"
        case risk
        case requiresConfirmation = "requires_confirmation"
        case examples
    }
}

public nonisolated struct AgentToolCall: Codable, Hashable, Sendable {
    public var id: String
    public var toolName: String
    public var argumentsJSON: String

    public nonisolated init(id: String, toolName: String, argumentsJSON: String) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case toolName = "tool_name"
        case argumentsJSON = "arguments_json"
    }
}

public nonisolated struct AgentPlan: Codable, Hashable, Sendable {
    public var summary: String
    public var toolCalls: [AgentToolCall]
    public var finalResponseDraft: String?

    public nonisolated init(summary: String, toolCalls: [AgentToolCall], finalResponseDraft: String? = nil) {
        self.summary = summary
        self.toolCalls = toolCalls
        self.finalResponseDraft = finalResponseDraft
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case toolCalls = "tool_calls"
        case finalResponseDraft = "final_response_draft"
    }
}

public nonisolated struct AgentToolResult: Codable, Hashable, Sendable {
    public var callID: String
    public var toolName: String
    public var succeeded: Bool
    public var requiresConfirmation: Bool
    public var message: String
    public var modifiedPaths: [String]
    public var errorMessage: String?

    public nonisolated init(
        callID: String,
        toolName: String,
        succeeded: Bool,
        requiresConfirmation: Bool = false,
        message: String,
        modifiedPaths: [String] = [],
        errorMessage: String? = nil
    ) {
        self.callID = callID
        self.toolName = toolName
        self.succeeded = succeeded
        self.requiresConfirmation = requiresConfirmation
        self.message = message
        self.modifiedPaths = modifiedPaths
        self.errorMessage = errorMessage
    }

    private enum CodingKeys: String, CodingKey {
        case callID = "call_id"
        case toolName = "tool_name"
        case succeeded
        case requiresConfirmation = "requires_confirmation"
        case message
        case modifiedPaths = "modified_paths"
        case errorMessage = "error_message"
    }
}

public nonisolated struct AgentRun: Codable, Hashable, Sendable {
    public var id: String
    public var goal: String
    public var createdAt: Date
    public var completedAt: Date?
    public var mode: AgentRunMode
    public var plan: AgentPlan
    public var toolResults: [AgentToolResult]

    public nonisolated init(
        id: String,
        goal: String,
        createdAt: Date,
        completedAt: Date?,
        mode: AgentRunMode,
        plan: AgentPlan,
        toolResults: [AgentToolResult]
    ) {
        self.id = id
        self.goal = goal
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.mode = mode
        self.plan = plan
        self.toolResults = toolResults
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case goal
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case mode
        case plan
        case toolResults = "tool_results"
    }
}

public nonisolated struct AgentExecutionOptions: Sendable {
    public var mode: AgentRunMode
    public var approvedToolCallIDs: Set<String>

    public nonisolated init(mode: AgentRunMode = .planOnly, approvedToolCallIDs: Set<String> = []) {
        self.mode = mode
        self.approvedToolCallIDs = approvedToolCallIDs
    }
}

public nonisolated struct AgentPaperSnapshot: Codable, Hashable, Sendable {
    public var id: String
    public var citekey: String
    public var title: String
    public var authors: [String]
    public var year: Int?
    public var collectionPath: String?
    public var projectIDs: [String]
    public var coreProjectIDs: [String]
    public var folderPath: String?
    public var tags: [String]
    public var categories: [String]
    public var status: ReadingStatus
    public var priority: Priority
    public var abstract: String?

    public nonisolated init(paper: Paper) {
        self.id = paper.id
        self.citekey = paper.citekey
        self.title = paper.title
        self.authors = paper.authors
        self.year = paper.year
        self.collectionPath = paper.collectionPath
        self.projectIDs = paper.projectIDs
        self.coreProjectIDs = paper.coreProjectIDs
        self.folderPath = paper.folderPath
        self.tags = paper.tags
        self.categories = paper.categories
        self.status = paper.status
        self.priority = paper.priority
        self.abstract = paper.abstract
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case citekey
        case title
        case authors
        case year
        case collectionPath = "collection_path"
        case projectIDs = "project_ids"
        case coreProjectIDs = "core_project_ids"
        case folderPath = "folder_path"
        case tags
        case categories
        case status
        case priority
        case abstract
    }
}

public nonisolated struct AgentTodoSnapshot: Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: TodoStatus
    public var dueDate: Date?
    public var priority: Priority
    public var tags: [String]
    public var relatedPaperIDs: [String]

    public nonisolated init(todo: TodoItem) {
        self.id = todo.id
        self.title = todo.title
        self.status = todo.status
        self.dueDate = todo.dueDate
        self.priority = todo.priority
        self.tags = todo.tags
        self.relatedPaperIDs = todo.relatedPaperIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case status
        case dueDate = "due_date"
        case priority
        case tags
        case relatedPaperIDs = "related_paper_ids"
    }
}

public nonisolated struct AgentWorkspaceSnapshot: Codable, Hashable, Sendable {
    public var workspaceName: String
    public var selectedPaper: AgentPaperSnapshot?
    public var recentPapers: [AgentPaperSnapshot]
    public var openTodos: [AgentTodoSnapshot]
    public var paperCount: Int
    public var todoCount: Int

    public nonisolated init(
        workspaceName: String,
        selectedPaper: AgentPaperSnapshot?,
        recentPapers: [AgentPaperSnapshot],
        openTodos: [AgentTodoSnapshot],
        paperCount: Int,
        todoCount: Int
    ) {
        self.workspaceName = workspaceName
        self.selectedPaper = selectedPaper
        self.recentPapers = recentPapers
        self.openTodos = openTodos
        self.paperCount = paperCount
        self.todoCount = todoCount
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceName = "workspace_name"
        case selectedPaper = "selected_paper"
        case recentPapers = "recent_papers"
        case openTodos = "open_todos"
        case paperCount = "paper_count"
        case todoCount = "todo_count"
    }
}

public nonisolated enum AgentError: LocalizedError, Sendable {
    case emptyGoal
    case unknownTool(String)
    case invalidArguments(String)
    case missingSelectedPaper
    case paperNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .emptyGoal:
            return "Agent goal cannot be empty."
        case let .unknownTool(name):
            return "Unknown agent tool: \(name)."
        case let .invalidArguments(message):
            return "Invalid agent tool arguments: \(message)"
        case .missingSelectedPaper:
            return "This agent action needs a selected paper."
        case let .paperNotFound(id):
            return "No paper found with id \(id)."
        }
    }
}