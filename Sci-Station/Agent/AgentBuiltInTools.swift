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
        if let allowedPaperIDs = context.allowedPaperIDs,
           relatedPaperIDs.contains(where: { !allowedPaperIDs.contains($0) }) {
            throw AgentError.invalidArguments("related_paper_ids contains a paper outside the AI knowledge selection")
        }
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
        if let allowedPaperIDs = context.allowedPaperIDs,
           !allowedPaperIDs.contains(paperID) {
            throw AgentError.invalidArguments("paper_id is outside the AI knowledge selection")
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

public nonisolated struct ListPapersAgentTool: AgentTool {
    private let paperRepository: PaperRepository

    public nonisolated init(paperRepository: PaperRepository) {
        self.paperRepository = paperRepository
    }

    public nonisolated var definition: AgentToolDefinition {
        AgentToolDefinition(
            name: "list_papers",
            displayName: "List Papers",
            summary: "List candidate papers by project, tag, paper id, or text query before reading content.",
            inputSchema: #"{"project_id":"string optional","paper_id":"string optional","tag":"string optional","query":"string optional","limit":20}"#,
            risk: .readOnly,
            requiresConfirmation: false,
            permissionKey: "paper.read",
            outputPolicy: AgentToolOutputPolicy(maxCharacters: 16_000),
            examples: [#"{"query":"evaporation rate","limit":10}"#]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let arguments = try decodeArguments(ListPapersArguments.self, from: argumentsJSON)
        let papers = try await filteredPapers(
            repository: paperRepository,
            context: context,
            projectID: arguments.projectID,
            paperID: arguments.paperID,
            tag: arguments.tag,
            query: arguments.query,
            limit: arguments.limit
        )
        let lines = papers.map { paper in
            let hasMarkdown = FileManager.default.fileExists(atPath: paper.rawMarkdownURL(in: context.workspace).path)
            let tags = paper.tags.isEmpty ? "-" : paper.tags.joined(separator: ", ")
            return "- paper_id: \(paper.id)\n  title: \(paper.displayTitle)\n  authors: \(paper.authorsDisplay)\n  year: \(paper.yearText)\n  path: \(paper.paperDirectoryRelativePath)\n  has_paper_md: \(hasMarkdown)\n  tags: \(tags)"
        }
        let message = (["Found \(papers.count) paper(s)."] + lines).joined(separator: "\n")
        return AgentToolResult(callID: "", toolName: definition.name, succeeded: true, message: message)
    }
}

public nonisolated struct ReadPaperAgentTool: AgentTool {
    private let paperRepository: PaperRepository

    public nonisolated init(paperRepository: PaperRepository) {
        self.paperRepository = paperRepository
    }

    public nonisolated var definition: AgentToolDefinition {
        AgentToolDefinition(
            name: "read_paper",
            displayName: "Read Paper",
            summary: "Read a converted paper.md by paper id or relative path with optional page or line range.",
            inputSchema: #"{"paper_id":"string optional; defaults to selected paper","relative_path":"paper.md relative path optional","page":1,"page_size":8000,"start_line":1,"end_line":80}"#,
            risk: .readOnly,
            requiresConfirmation: false,
            permissionKey: "paper.read",
            outputPolicy: AgentToolOutputPolicy(maxCharacters: 18_000),
            examples: [#"{"paper_id":"paper-123","page":1,"page_size":6000}"#]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let arguments = try decodeArguments(ReadPaperArguments.self, from: argumentsJSON)
        let resolved = try await resolvedMarkdown(
            repository: paperRepository,
            context: context,
            paperID: arguments.paperID,
            relativePath: arguments.relativePath
        )

        let content: String
        let rangeLabel: String
        if let startLine = arguments.startLine ?? arguments.start_line,
           let endLine = arguments.endLine ?? arguments.end_line {
            let slice = lineSlice(resolved.contents, startLine: startLine, endLine: endLine)
            content = slice.text
            rangeLabel = "lines \(slice.startLine)-\(slice.endLine)"
        } else {
            let pageSize = min(max(arguments.pageSize ?? arguments.page_size ?? 8_000, 1_000), 18_000)
            let page = max(arguments.page ?? 1, 1)
            let pageSlice = characterPage(resolved.contents, page: page, pageSize: pageSize)
            content = pageSlice.text
            rangeLabel = "page \(pageSlice.page)/\(pageSlice.pageCount), chars \(pageSlice.startOffset)-\(pageSlice.endOffset)"
        }

        let message = """
        paper_id: \(resolved.paper.id)
        title: \(resolved.paper.displayTitle)
        source: \(resolved.relativePath)
        range: \(rangeLabel)

        \(content)
        """
        return AgentToolResult(callID: "", toolName: definition.name, succeeded: true, message: message)
    }
}

public nonisolated struct ReadPaperSectionAgentTool: AgentTool {
    private let paperRepository: PaperRepository

    public nonisolated init(paperRepository: PaperRepository) {
        self.paperRepository = paperRepository
    }

    public nonisolated var definition: AgentToolDefinition {
        AgentToolDefinition(
            name: "read_paper_section",
            displayName: "Read Paper Section",
            summary: "Read a paper.md section by Markdown heading path, or by explicit line range.",
            inputSchema: #"{"paper_id":"string optional; defaults to selected paper","relative_path":"paper.md relative path optional","heading":"section heading or heading path","start_line":1,"end_line":80,"max_characters":12000}"#,
            risk: .readOnly,
            requiresConfirmation: false,
            permissionKey: "paper.read",
            outputPolicy: AgentToolOutputPolicy(maxCharacters: 16_000),
            examples: [#"{"paper_id":"paper-123","heading":"5 Evaporation Rate"}"#]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let arguments = try decodeArguments(ReadPaperSectionArguments.self, from: argumentsJSON)
        let resolved = try await resolvedMarkdown(
            repository: paperRepository,
            context: context,
            paperID: arguments.paperID,
            relativePath: arguments.relativePath
        )
        let maxCharacters = min(max(arguments.maxCharacters ?? arguments.max_characters ?? 12_000, 1_000), 20_000)

        let section: PaperSectionSlice
        if let startLine = arguments.startLine ?? arguments.start_line,
           let endLine = arguments.endLine ?? arguments.end_line {
            let slice = lineSlice(resolved.contents, startLine: startLine, endLine: endLine)
            section = PaperSectionSlice(
                heading: "line range",
                startLine: slice.startLine,
                endLine: slice.endLine,
                text: limitedToolOutput(slice.text, maximumCharacters: maxCharacters).text,
                wasTruncated: slice.text.count > maxCharacters
            )
        } else if let heading = arguments.heading?.trimmingCharacters(in: .whitespacesAndNewlines), !heading.isEmpty {
            section = try markdownSection(resolved.contents, heading: heading, maxCharacters: maxCharacters)
        } else {
            throw AgentError.invalidArguments("heading or start_line/end_line is required")
        }

        let truncation = section.wasTruncated ? "\n[Section truncated by Sci-Station.]" : ""
        let message = """
        paper_id: \(resolved.paper.id)
        title: \(resolved.paper.displayTitle)
        source: \(resolved.relativePath)
        heading: \(section.heading)
        lines: \(section.startLine)-\(section.endLine)

        \(section.text)\(truncation)
        """
        return AgentToolResult(callID: "", toolName: definition.name, succeeded: true, message: message)
    }
}

public nonisolated struct SearchPapersAgentTool: AgentTool {
    private let paperRepository: PaperRepository

    public nonisolated init(paperRepository: PaperRepository) {
        self.paperRepository = paperRepository
    }

    public nonisolated var definition: AgentToolDefinition {
        AgentToolDefinition(
            name: "search_papers",
            displayName: "Search Papers",
            summary: "Search converted paper.md files and return line-anchored snippets with current headings.",
            inputSchema: #"{"query":"string","paper_ids":["paper id"],"project_id":"string optional","tag":"string optional","limit":20,"context_lines":2,"case_sensitive":false}"#,
            risk: .readOnly,
            requiresConfirmation: false,
            permissionKey: "paper.read",
            outputPolicy: AgentToolOutputPolicy(maxCharacters: 18_000),
            examples: [#"{"query":"evaporation rate","limit":8}"#]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let arguments = try decodeArguments(SearchPapersArguments.self, from: argumentsJSON)
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AgentError.invalidArguments("query is required")
        }
        let papers = try await filteredPapers(
            repository: paperRepository,
            context: context,
            projectID: arguments.projectID,
            paperID: nil,
            tag: arguments.tag,
            query: nil,
            limit: nil
        )
        let allowedIDs = Set(arguments.paperIDs ?? arguments.paper_ids ?? [])
        let searchablePapers = allowedIDs.isEmpty ? papers : papers.filter { allowedIDs.contains($0.id) }
        let limit = min(max(arguments.limit ?? 20, 1), 50)
        let contextLines = min(max(arguments.contextLines ?? arguments.context_lines ?? 2, 0), 5)
        var matches: [String] = []

        for paper in searchablePapers where matches.count < limit {
            guard let markdown = try? markdownContents(for: paper, in: context.workspace) else {
                continue
            }
            matches.append(contentsOf: searchMarkdown(
                markdown.contents,
                query: query,
                paper: paper,
                relativePath: markdown.relativePath,
                limit: limit - matches.count,
                contextLines: contextLines,
                caseSensitive: arguments.caseSensitive ?? arguments.case_sensitive ?? false
            ))
        }

        let message = matches.isEmpty
            ? "No matches for \"\(query)\" in converted paper.md files."
            : (["Found \(matches.count) match(es) for \"\(query)\"."] + matches).joined(separator: "\n\n")
        return AgentToolResult(callID: "", toolName: definition.name, succeeded: true, message: message)
    }
}

public nonisolated struct WriteMarkdownPlanAgentTool: AgentTool {
    private let markdownRepository: MarkdownRepository

    public nonisolated init(markdownRepository: MarkdownRepository) {
        self.markdownRepository = markdownRepository
    }

    public nonisolated var definition: AgentToolDefinition {
        AgentToolDefinition(
            name: "write_markdown_plan",
            summary: "Create or replace a Markdown planning document under wiki/plans.",
            inputSchema: "{\"title\":\"string\",\"body\":\"markdown string\",\"relative_path\":\"wiki/plans/name.md optional\"}",
            risk: .writesWorkspace,
            requiresConfirmation: true,
            examples: ["{\"title\":\"Paper reading plan\",\"body\":\"# Plan\\n\\n- Read selected papers\"}"]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let arguments = try decodeArguments(WriteMarkdownPlanArguments.self, from: argumentsJSON)
        let title = arguments.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = arguments.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw AgentError.invalidArguments("title is required")
        }
        guard !body.isEmpty else {
            throw AgentError.invalidArguments("body is required")
        }

        let relativePath = try resolvedPlanPath(title: title, proposedPath: arguments.relativePath)
        let contents = body.hasPrefix("# ") ? body + "\n" : "# \(title)\n\n\(body)\n"
        let document = try await markdownRepository.saveContents(contents, relativePath: relativePath, in: context.workspace)

        return AgentToolResult(
            callID: "",
            toolName: definition.name,
            succeeded: true,
            message: "Saved Markdown plan: \(document.title)",
            modifiedPaths: [document.relativePath]
        )
    }

    private nonisolated func resolvedPlanPath(title: String, proposedPath: String?) throws -> String {
        if let proposedPath = proposedPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !proposedPath.isEmpty {
            guard proposedPath.hasPrefix("wiki/plans/"),
                  proposedPath.hasSuffix(".md"),
                  !proposedPath.contains(".."),
                  !proposedPath.hasPrefix("/") else {
                throw AgentError.invalidArguments("relative_path must be under wiki/plans and end with .md")
            }
            return proposedPath
        }

        return "wiki/plans/\(slug(from: title)).md"
    }

    private nonisolated func slug(from title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let lowercased = title.lowercased()
        var output = ""
        var previousWasDash = false

        for scalar in lowercased.unicodeScalars {
            if allowed.contains(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                output.append("-")
                previousWasDash = true
            }
        }

        let slug = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "plan-\(UUID().uuidString.lowercased())" : slug
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

private struct WriteMarkdownPlanArguments: Decodable {
    var title: String
    var body: String
    var relativePath: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case body
        case relativePath = "relative_path"
    }
}

private nonisolated struct ListPapersArguments: Decodable {
    var projectID: String?
    var paperID: String?
    var tag: String?
    var query: String?
    var limit: Int?

    private enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case paperID = "paper_id"
        case tag
        case query
        case limit
    }
}

private nonisolated struct ReadPaperArguments: Decodable {
    var paperID: String?
    var relativePath: String?
    var page: Int?
    var pageSize: Int?
    var page_size: Int?
    var startLine: Int?
    var start_line: Int?
    var endLine: Int?
    var end_line: Int?

    private enum CodingKeys: String, CodingKey {
        case paperID = "paper_id"
        case relativePath = "relative_path"
        case page
        case pageSize
        case page_size
        case startLine
        case start_line
        case endLine
        case end_line
    }
}

private nonisolated struct ReadPaperSectionArguments: Decodable {
    var paperID: String?
    var relativePath: String?
    var heading: String?
    var startLine: Int?
    var start_line: Int?
    var endLine: Int?
    var end_line: Int?
    var maxCharacters: Int?
    var max_characters: Int?

    private enum CodingKeys: String, CodingKey {
        case paperID = "paper_id"
        case relativePath = "relative_path"
        case heading
        case startLine
        case start_line
        case endLine
        case end_line
        case maxCharacters
        case max_characters
    }
}

private nonisolated struct SearchPapersArguments: Decodable {
    var query: String
    var paperIDs: [String]?
    var paper_ids: [String]?
    var projectID: String?
    var tag: String?
    var limit: Int?
    var contextLines: Int?
    var context_lines: Int?
    var caseSensitive: Bool?
    var case_sensitive: Bool?

    private enum CodingKeys: String, CodingKey {
        case query
        case paperIDs
        case paper_ids
        case projectID = "project_id"
        case tag
        case limit
        case contextLines
        case context_lines
        case caseSensitive
        case case_sensitive
    }
}

private nonisolated struct ResolvedPaperMarkdown {
    var paper: Paper
    var relativePath: String
    var contents: String
}

private nonisolated struct PaperLineSlice {
    var startLine: Int
    var endLine: Int
    var text: String
}

private nonisolated struct PaperPageSlice {
    var page: Int
    var pageCount: Int
    var startOffset: Int
    var endOffset: Int
    var text: String
}

private nonisolated struct PaperSectionSlice {
    var heading: String
    var startLine: Int
    var endLine: Int
    var text: String
    var wasTruncated: Bool
}

private func filteredPapers(
    repository: PaperRepository,
    context: AgentToolContext,
    projectID: String?,
    paperID: String?,
    tag: String?,
    query: String?,
    limit: Int?
) async throws -> [Paper] {
    var papers = try await repository.loadPapers(in: context.workspace)
    if let allowedPaperIDs = context.allowedPaperIDs, !allowedPaperIDs.isEmpty {
        papers = papers.filter { allowedPaperIDs.contains($0.id) }
    }
    if let paperID = paperID?.trimmingCharacters(in: .whitespacesAndNewlines), !paperID.isEmpty {
        papers = papers.filter { matchesPaper($0, identifier: paperID) }
    }
    if let projectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? context.currentProjectID {
        papers = papers.filter { $0.projectIDs.contains(projectID) || $0.coreProjectIDs.contains(projectID) }
    }
    if let tag = tag?.trimmingCharacters(in: .whitespacesAndNewlines), !tag.isEmpty {
        papers = papers.filter { paper in
            paper.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
        }
    }
    if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
        papers = papers.filter { paperMatchesQuery($0, query: query) }
    }
    return Array(papers.prefix(min(max(limit ?? 20, 1), 50)))
}

private func resolvedMarkdown(
    repository: PaperRepository,
    context: AgentToolContext,
    paperID: String?,
    relativePath: String?
) async throws -> ResolvedPaperMarkdown {
    let papers = try await repository.loadPapers(in: context.workspace)
    let allowedPapers = context.allowedPaperIDs.map { allowedIDs in
        papers.filter { allowedIDs.contains($0.id) }
    } ?? papers
    let identifier = paperID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ?? relativePath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ?? context.selectedPaperID
    guard let identifier else {
        throw AgentError.missingSelectedPaper
    }
    guard let paper = allowedPapers.first(where: { matchesPaper($0, identifier: identifier) }) else {
        throw AgentError.paperNotFound(identifier)
    }
    return try markdownContents(for: paper, in: context.workspace)
}

private func markdownContents(for paper: Paper, in workspace: ResearchWorkspace) throws -> ResolvedPaperMarkdown {
    let url = paper.rawMarkdownURL(in: workspace)
    let standardizedRoot = workspace.rootURL.standardizedFileURL.path
    let standardizedPath = url.standardizedFileURL.path
    guard standardizedPath == standardizedRoot || standardizedPath.hasPrefix(standardizedRoot + "/") else {
        throw AgentError.invalidArguments("paper.md resolves outside the workspace")
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw AgentError.invalidArguments("paper.md is not available for paper_id \(paper.id). Convert or import Markdown first.")
    }
    let contents = try String(contentsOf: url, encoding: .utf8)
    return ResolvedPaperMarkdown(
        paper: paper,
        relativePath: paper.paperDirectoryRelativePath + "/paper.md",
        contents: contents
    )
}

private func matchesPaper(_ paper: Paper, identifier: String) -> Bool {
    let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    return paper.id == normalized
        || paper.citekey == normalized
        || paper.paperDirectoryRelativePath == normalized
        || "\(paper.paperDirectoryRelativePath)/paper.md" == normalized
}

private func paperMatchesQuery(_ paper: Paper, query: String) -> Bool {
    let haystack = [
        paper.id,
        paper.citekey,
        paper.displayTitle,
        paper.authorsDisplay,
        paper.yearText,
        paper.tags.joined(separator: " "),
        paper.categories.joined(separator: " "),
        paper.paperDirectoryRelativePath
    ].joined(separator: "\n")
    return haystack.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
}

private func lineSlice(_ contents: String, startLine: Int, endLine: Int) -> PaperLineSlice {
    let lines = contents.components(separatedBy: .newlines)
    let lower = min(max(startLine, 1), max(lines.count, 1))
    let upper = min(max(endLine, lower), max(lines.count, lower))
    let text = lines[(lower - 1)..<upper].joined(separator: "\n")
    return PaperLineSlice(startLine: lower, endLine: upper, text: text)
}

private func characterPage(_ contents: String, page: Int, pageSize: Int) -> PaperPageSlice {
    let pageCount = max(Int(ceil(Double(max(contents.count, 1)) / Double(pageSize))), 1)
    let resolvedPage = min(max(page, 1), pageCount)
    let startOffset = (resolvedPage - 1) * pageSize
    let endOffset = min(startOffset + pageSize, contents.count)
    let startIndex = contents.index(contents.startIndex, offsetBy: startOffset)
    let endIndex = contents.index(contents.startIndex, offsetBy: endOffset)
    return PaperPageSlice(
        page: resolvedPage,
        pageCount: pageCount,
        startOffset: startOffset,
        endOffset: endOffset,
        text: String(contents[startIndex..<endIndex])
    )
}

private func markdownSection(_ contents: String, heading: String, maxCharacters: Int) throws -> PaperSectionSlice {
    let lines = contents.components(separatedBy: .newlines)
    let wanted = normalizedHeading(heading)
    var headingStack: [String] = []
    var matchedStartIndex: Int?
    var matchedLevel: Int?
    var matchedHeading = heading

    for (index, line) in lines.enumerated() {
        guard let parsed = parsedHeading(line) else {
            continue
        }
        if headingStack.count >= parsed.level {
            headingStack = Array(headingStack.prefix(parsed.level - 1))
        }
        headingStack.append(parsed.title)
        let path = headingStack.joined(separator: " / ")
        if normalizedHeading(parsed.title) == wanted || normalizedHeading(path) == wanted {
            matchedStartIndex = index
            matchedLevel = parsed.level
            matchedHeading = path
            break
        }
    }

    guard let startIndex = matchedStartIndex, let level = matchedLevel else {
        throw AgentError.invalidArguments("No Markdown heading matched \"\(heading)\".")
    }

    var endIndex = lines.count
    if startIndex + 1 < lines.count {
        for index in (startIndex + 1)..<lines.count {
            if let parsed = parsedHeading(lines[index]), parsed.level <= level {
                endIndex = index
                break
            }
        }
    }

    let text = lines[startIndex..<endIndex].joined(separator: "\n")
    let limited = limitedToolOutput(text, maximumCharacters: maxCharacters)
    return PaperSectionSlice(
        heading: matchedHeading,
        startLine: startIndex + 1,
        endLine: endIndex,
        text: limited.text,
        wasTruncated: limited.wasTruncated
    )
}

private func searchMarkdown(
    _ contents: String,
    query: String,
    paper: Paper,
    relativePath: String,
    limit: Int,
    contextLines: Int,
    caseSensitive: Bool
) -> [String] {
    let lines = contents.components(separatedBy: .newlines)
    var currentHeading = "Document"
    var matches: [String] = []
    let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]

    for (index, line) in lines.enumerated() {
        if let parsed = parsedHeading(line) {
            currentHeading = parsed.title
        }
        guard line.range(of: query, options: options) != nil else {
            continue
        }
        let start = max(index - contextLines, 0)
        let end = min(index + contextLines, lines.count - 1)
        let snippet = lines[start...end].joined(separator: "\n")
        matches.append("""
        paper_id: \(paper.id)
        title: \(paper.displayTitle)
        source: \(relativePath)#L\(index + 1)
        heading: \(currentHeading)
        ```markdown
        \(snippet)
        ```
        """)
        if matches.count >= limit {
            break
        }
    }
    return matches
}

private func parsedHeading(_ line: String) -> (level: Int, title: String)? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("#") else {
        return nil
    }
    let level = trimmed.prefix { $0 == "#" }.count
    guard (1...6).contains(level) else {
        return nil
    }
    let title = trimmed.dropFirst(level).trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? nil : (level, title)
}

private func normalizedHeading(_ value: String) -> String {
    value
        .replacingOccurrences(of: " / ", with: "/")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}

private func limitedToolOutput(_ value: String, maximumCharacters: Int) -> (text: String, wasTruncated: Bool) {
    guard value.count > maximumCharacters else {
        return (value, false)
    }
    let endIndex = value.index(value.startIndex, offsetBy: maximumCharacters)
    return (String(value[..<endIndex]), true)
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

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}