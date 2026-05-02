import Foundation
import PDFKit

public actor AgentWorkspaceContextBuilder {
    private let paperRepository: PaperRepository
    private let todoRepository: TodoRepository
    private nonisolated static let defaultMarkdownExcerptCharacters = 10_000
    private nonisolated static let knowledgeMarkdownExcerptCharacters = 120_000
    private nonisolated static let defaultPDFExcerptCharacters = 8_000

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
        includedPaperIDs: Set<String>? = nil,
        paperContextPolicy: AgentPaperContextPolicy = .metadataOnly,
        paperLimit: Int = 20,
        todoLimit: Int = 20
    ) async throws -> AgentWorkspaceSnapshot {
        let allPapers = try await paperRepository.loadPapers(in: workspace)
        let papers = includedPaperIDs.map { paperIDs in
            allPapers.filter { paperIDs.contains($0.id) }
        } ?? allPapers
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
            .map {
                paperSnapshot(
                    for: $0,
                    in: workspace,
                    policy: paperContextPolicy,
                    usesKnowledgeExcerpt: true
                )
            }
        let recentPapers = papers
            .prefix(max(0, paperLimit))
            .map { paper in
                paperSnapshot(
                    for: paper,
                    in: workspace,
                    policy: paperContextPolicy,
                    usesKnowledgeExcerpt: includedPaperIDs?.contains(paper.id) == true || selectedPaperID == paper.id
                )
            }
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
            projectPapers: Array(projectPapers.prefix(max(0, paperLimit)).map { paper in
                paperSnapshot(
                    for: paper,
                    in: workspace,
                    policy: paperContextPolicy,
                    usesKnowledgeExcerpt: includedPaperIDs?.contains(paper.id) == true || selectedPaperID == paper.id
                )
            }),
            projectOpenTodos: Array(projectOpenTodos.prefix(max(0, todoLimit)).map(AgentTodoSnapshot.init))
        )
    }

    private nonisolated func paperSnapshot(
        for paper: Paper,
        in workspace: ResearchWorkspace,
        policy: AgentPaperContextPolicy,
        usesKnowledgeExcerpt: Bool = false
    ) -> AgentPaperSnapshot {
        switch policy {
        case .metadataOnly:
            return metadataOnlyPaperSnapshot(for: paper, in: workspace)
        case .legacyExcerpts:
            return excerptPaperSnapshot(for: paper, in: workspace, usesKnowledgeExcerpt: usesKnowledgeExcerpt)
        }
    }

    private nonisolated func metadataOnlyPaperSnapshot(for paper: Paper, in workspace: ResearchWorkspace) -> AgentPaperSnapshot {
        let markdownURL = paper.rawMarkdownURL(in: workspace)
        let rawMarkdownRelativePath = FileManager.default.fileExists(atPath: markdownURL.path)
            ? paper.paperDirectoryRelativePath + "/paper.md"
            : nil

        return AgentPaperSnapshot(
            paper: paper,
            rawMarkdownRelativePath: rawMarkdownRelativePath,
            sourceExcerptKind: nil,
            sourceExcerpt: nil
        )
    }

    private nonisolated func excerptPaperSnapshot(for paper: Paper, in workspace: ResearchWorkspace, usesKnowledgeExcerpt: Bool = false) -> AgentPaperSnapshot {
        let markdownCharacterLimit = usesKnowledgeExcerpt ? Self.knowledgeMarkdownExcerptCharacters : Self.defaultMarkdownExcerptCharacters
        let pdfCharacterLimit = usesKnowledgeExcerpt ? Self.knowledgeMarkdownExcerptCharacters : Self.defaultPDFExcerptCharacters
        let markdownURL = paper.rawMarkdownURL(in: workspace)
        if let markdown = try? String(contentsOf: markdownURL, encoding: .utf8),
           !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AgentPaperSnapshot(
                paper: paper,
                rawMarkdownRelativePath: paper.paperDirectoryRelativePath + "/paper.md",
                sourceExcerptKind: "paper.md",
                sourceExcerpt: limited(markdown, maximumCharacters: markdownCharacterLimit)
            )
        }

        if let pdfURL = paper.pdfURL(in: workspace),
           let pdfText = extractedPDFText(from: pdfURL, maximumCharacters: pdfCharacterLimit),
           !pdfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AgentPaperSnapshot(
                paper: paper,
                rawMarkdownRelativePath: nil,
                sourceExcerptKind: "pdf_text_fallback",
                sourceExcerpt: limited(pdfText, maximumCharacters: pdfCharacterLimit)
            )
        }

        return AgentPaperSnapshot(paper: paper)
    }

    private nonisolated func extractedPDFText(from pdfURL: URL, maximumCharacters: Int) -> String? {
        guard let document = PDFDocument(url: pdfURL) else {
            return nil
        }

        var pageTexts: [String] = []
        var collectedLength = 0
        for pageIndex in 0..<document.pageCount {
            guard let pageText = document.page(at: pageIndex)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pageText.isEmpty else {
                continue
            }

            pageTexts.append("### Page \(pageIndex + 1)\n\(pageText)")
            collectedLength += pageText.count
            if collectedLength >= maximumCharacters {
                break
            }
        }

        return pageTexts.joined(separator: "\n\n")
    }

    private nonisolated func limited(_ value: String, maximumCharacters: Int) -> String {
        guard value.count > maximumCharacters else {
            return value
        }

        let endIndex = value.index(value.startIndex, offsetBy: maximumCharacters)
        return String(value[..<endIndex]) + "\n\n[Excerpt truncated by Sci-Station.]"
    }
}