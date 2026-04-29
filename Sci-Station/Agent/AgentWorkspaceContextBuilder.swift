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
        root: ResearchRoot? = nil,
        projects: [ResearchProject] = [],
        currentProjectID: ResearchProject.ID? = nil,
        selectedPaperID: String? = nil,
        paperLimit: Int = 20,
        todoLimit: Int = 20
    ) async throws -> AgentWorkspaceSnapshot {
        let papers = try await paperRepository.loadPapers(in: workspace)
        let todos = try await todoRepository.loadTodos(in: workspace)
        let researchRoot = root ?? ResearchRoot(rootURL: workspace.rootURL)
        let rootCompatibility = ResearchRoot.compatibility(at: researchRoot.rootURL)
        let activeProjects = projects.filter { !$0.isArchived }
        let currentProject = currentProjectID
            .flatMap { projectID in activeProjects.first(where: { $0.id == projectID }) }
        let projectPapers = currentProjectID.map { projectID in
            papers.filter { $0.projectIDs.contains(projectID) }
        } ?? []
        let projectOpenTodos = currentProjectID.map { projectID in
            todos.filter { todo in
                todo.status != .done
                    && todo.status != .cancelled
                    && (todo.projectIDs.contains(projectID) || (todo.projectIDs.isEmpty && activeProjects.count <= 1))
            }
        } ?? []
        let projectSnapshots = activeProjects.map { project in
            let projectPaperCount = papers.filter { $0.projectIDs.contains(project.id) }.count
            let projectCorePaperCount = papers.filter { $0.coreProjectIDs.contains(project.id) }.count
            let projectTodoCount = todos.filter { todo in
                todo.status != .done
                    && todo.status != .cancelled
                    && (todo.projectIDs.contains(project.id) || (todo.projectIDs.isEmpty && activeProjects.count <= 1))
            }.count
            return AgentResearchProjectSnapshot(
                project: project,
                paperCount: projectPaperCount,
                corePaperCount: projectCorePaperCount,
                openTodoCount: projectTodoCount
            )
        }
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
            todoCount: todos.count,
            rootName: researchRoot.displayName,
            rootCompatibility: rootCompatibility,
            currentProjectID: currentProjectID,
            currentProject: currentProject.map { project in
                AgentResearchProjectSnapshot(
                    project: project,
                    paperCount: projectPapers.count,
                    corePaperCount: projectPapers.filter { $0.coreProjectIDs.contains(project.id) }.count,
                    openTodoCount: projectOpenTodos.count
                )
            },
            projects: projectSnapshots,
            projectPapers: Array(projectPapers.prefix(max(0, paperLimit)).map(AgentPaperSnapshot.init)),
            projectOpenTodos: Array(projectOpenTodos.prefix(max(0, todoLimit)).map(AgentTodoSnapshot.init))
        )
    }
}