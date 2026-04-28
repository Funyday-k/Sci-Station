import Foundation

public actor AgentWorkspaceContextBuilder {
    private let paperRepository: PaperRepository
    private let todoRepository: TodoRepository

    public init(paperRepository: PaperRepository = PaperRepository(), todoRepository: TodoRepository = TodoRepository()) {
        self.paperRepository = paperRepository
        self.todoRepository = todoRepository
    }

    public func snapshot(
        in workspace: ResearchWorkspace,
        selectedPaperID: String? = nil,
        paperLimit: Int = 20,
        todoLimit: Int = 20
    ) async throws -> AgentWorkspaceSnapshot {
        let papers = try await paperRepository.loadPapers(in: workspace)
        let todos = try await todoRepository.loadTodos(in: workspace)
        let selectedPaper = selectedPaperID
            .flatMap { id in papers.first(where: { $0.id == id }) }
            .map(AgentPaperSnapshot.init)
        let recentPapers = papers
            .prefix(max(0, paperLimit))
            .map(AgentPaperSnapshot.init)
        let openTodos = todos
            .filter { $0.status != .done && $0.status != .cancelled }
            .prefix(max(0, todoLimit))
            .map(AgentTodoSnapshot.init)

        return AgentWorkspaceSnapshot(
            workspaceName: workspace.displayName,
            selectedPaper: selectedPaper,
            recentPapers: Array(recentPapers),
            openTodos: Array(openTodos),
            paperCount: papers.count,
            todoCount: todos.count
        )
    }
}