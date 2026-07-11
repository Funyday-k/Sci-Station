import Foundation

/// Builds and maintains the research graph by scanning known stores (papers,
/// projects, wiki, tasks, etc.) and upserting nodes/edges into the
/// `GraphRepository`.
///
/// The indexer is incremental by default: it computes a `sourceHash` for each
/// entity and skips upserts when the hash matches the existing node. A
/// `force: true` run ignores hashes and rewrites everything.
///
/// Current scope: paper, project, wiki concept/method, task nodes,
/// belongs_to / mentions edges, and citation edges. Artifact, evidence,
/// run, approval, and calendar nodes are reserved graph kinds and are not
/// indexed by this actor yet.
public actor GraphIndexer {
    private let repository: GraphRepository
    private let paperRepository: PaperRepository
    private let projectRegistryRepository: ProjectRegistryRepository
    private let wikiLinkParser: WikiLinkParser
    private let markdownRepository: MarkdownRepository
    private let todoRepository: TodoRepository
    private let debug: AppDebugEventLogger?

    public init(
        repository: GraphRepository,
        paperRepository: PaperRepository = PaperRepository(),
        projectRegistryRepository: ProjectRegistryRepository = ProjectRegistryRepository(),
        wikiLinkParser: WikiLinkParser = WikiLinkParser(),
        markdownRepository: MarkdownRepository = MarkdownRepository(),
        todoRepository: TodoRepository = TodoRepository(),
        debug: AppDebugEventLogger? = nil
    ) {
        self.repository = repository
        self.paperRepository = paperRepository
        self.projectRegistryRepository = projectRegistryRepository
        self.wikiLinkParser = wikiLinkParser
        self.markdownRepository = markdownRepository
        self.todoRepository = todoRepository
        self.debug = debug
    }

    /// Runs the full indexing pipeline. When `force` is false, entities whose
    /// `sourceHash` matches the existing graph node are skipped.
    public func run(in workspace: ResearchWorkspace, root: ResearchRoot, force: Bool = false) async throws {
        await emit("graph.indexer.rebuild_started", payload: .object(["force": .bool(force)]), in: root)
        let start = Date()
        let snapshot = await repository.snapshot()

        try await indexPapers(workspace: workspace, root: root, snapshot: snapshot, force: force)
        try await indexProjects(root: root, snapshot: snapshot, force: force)
        try await indexWikiConceptMethods(workspace: workspace, root: root, snapshot: snapshot, force: force)
        try await indexTasks(workspace: workspace, root: root, snapshot: snapshot, force: force)
        try await indexCitationEdges(workspace: workspace, root: root, snapshot: snapshot, force: force)
        // Reserved graph kinds for future indexers:
        // try await indexArtifactsAndEvidence(...)
        // try await indexCalendarEvents(...)
        // try await indexRunsAndApprovals(...)

        _ = try await repository.compactIfNeeded()

        let finalSnapshot = await repository.snapshot()
        let duration = Date().timeIntervalSince(start) * 1000
        await emit(
            "graph.indexer.rebuild_finished",
            payload: .object([
                "duration_ms": .number(String(format: "%.1f", duration)),
                "count_nodes": .number(String(finalSnapshot.nodes.count)),
                "count_edges": .number(String(finalSnapshot.edges.count)),
                "force": .bool(force)
            ]),
            in: root
        )
    }

    // MARK: - Papers

    private func indexPapers(workspace: ResearchWorkspace, root: ResearchRoot, snapshot: GraphSnapshot, force: Bool) async throws {
        let papers = try await paperRepository.loadPapers(in: workspace)
        for paper in papers {
            try Task.checkCancellation()
            let stableID = paper.resolvedGraphNodeID
            GraphIdentifier.assertStableIDIsClean(stableID)
            let nodeID = "paper:\(stableID)"
            let hash = GraphIdentifier.sourceHash(from: [
                paper.id, paper.title, paper.authors.joined(separator: ";"),
                paper.year.map(String.init) ?? "",
                paper.doi ?? "", paper.arxiv ?? ""
            ])

            if !force, let existing = snapshot.node(id: nodeID), existing.sourceHash == hash {
                await emit(
                    "graph.indexer.incremental_skip",
                    payload: .object(["node_id": .string(nodeID), "source_hash": .string(hash)]),
                    in: root
                )
                continue
            }

            let existingCreatedAt = snapshot.node(id: nodeID)?.createdAt ?? Date()
            try await repository.upsertNode(GraphNode(
                id: nodeID,
                kind: .paper,
                displayName: paper.title,
                payload: .object([
                    "year": paper.year.map { .number(String($0)) } ?? .null,
                    "doi": paper.doi.map { .string($0) } ?? .null,
                    "arxiv": paper.arxiv.map { .string($0) } ?? .null,
                    "citekey": .string(paper.citekey),
                    "status": .string(paper.status.rawValue)
                ]),
                createdAt: existingCreatedAt,
                updatedAt: Date(),
                sourceHash: hash,
                lastIndexedAt: Date()
            ))

            // belongs_to edges for each linked project.
            for projectID in paper.projectIDs {
                let edgeID = GraphEdge.computeID(from: nodeID, kind: .belongsTo, to: "project:\(projectID)")
                try await repository.upsertEdge(GraphEdge(
                    id: edgeID,
                    kind: .belongsTo,
                    from: nodeID,
                    to: "project:\(projectID)",
                    createdAt: existingCreatedAt,
                    updatedAt: Date(),
                    sourceHash: hash,
                    lastIndexedAt: Date()
                ))
            }
        }
    }

    // MARK: - Projects

    private func indexProjects(root: ResearchRoot, snapshot: GraphSnapshot, force: Bool) async throws {
        let registry = try await projectRegistryRepository.load(in: root)
        for project in registry.projects {
            try Task.checkCancellation()
            let nodeID = "project:\(project.id)"
            let hash = GraphIdentifier.sourceHash(from: [
                project.id, project.name, project.description,
                project.isArchived ? "archived" : "active"
            ])

            if !force, let existing = snapshot.node(id: nodeID), existing.sourceHash == hash {
                await emit(
                    "graph.indexer.incremental_skip",
                    payload: .object(["node_id": .string(nodeID), "source_hash": .string(hash)]),
                    in: root
                )
                continue
            }

            let existingCreatedAt = snapshot.node(id: nodeID)?.createdAt ?? project.createdAt
            try await repository.upsertNode(GraphNode(
                id: nodeID,
                kind: .project,
                displayName: project.name,
                payload: .object([
                    "description": .string(project.description),
                    "is_archived": .bool(project.isArchived),
                    "color_hex": .string(project.colorHex)
                ]),
                createdAt: existingCreatedAt,
                updatedAt: project.updatedAt,
                sourceHash: hash,
                lastIndexedAt: Date()
            ))
        }
    }

    // MARK: - Wiki Concept / Method

    private func indexWikiConceptMethods(workspace: ResearchWorkspace, root: ResearchRoot, snapshot: GraphSnapshot, force: Bool) async throws {
        let documents = try await markdownRepository.loadDocuments(in: workspace)
        for document in documents {
            try Task.checkCancellation()

            // Detect concept/method nodes from wiki page titles stored under
            // `wiki/concepts/` or `wiki/methods/` directories.
            let inferredKind = inferNodeKind(from: document)
            if let kind = inferredKind {
                let slug = GraphIdentifier.slug(from: document.title)
                guard !slug.isEmpty else { continue }
                let nodeID = "\(kind.rawValue):\(slug)"
                let hash = GraphIdentifier.sourceHash(from: [
                    document.relativePath, document.title, document.body.prefix(200).description
                ])

                if !force, let existing = snapshot.node(id: nodeID), existing.sourceHash == hash {
                    continue
                }

                let existingCreatedAt = snapshot.node(id: nodeID)?.createdAt ?? Date()
                try await repository.upsertNode(GraphNode(
                    id: nodeID,
                    kind: kind,
                    displayName: document.title,
                    payload: .object([
                        "relative_path": .string(document.relativePath)
                    ]),
                    createdAt: existingCreatedAt,
                    updatedAt: Date(),
                    sourceHash: hash,
                    lastIndexedAt: Date()
                ))
            }

            // Scan outgoing wiki links for `[[concept:X]]` / `[[method:Y]]`
            // and produce `mentions` edges from the document's inferred node
            // (if it has one) or from a paper node (if the document lives
            // under `wiki/papers/`).
            let sourceNodeID = sourceNode(for: document, snapshot: snapshot)
            guard let sourceNodeID else { continue }

            for link in document.outgoingLinks {
                guard let ns = link.namespace,
                      (ns == "concept" || ns == "method") else { continue }
                let targetSlug = GraphIdentifier.slug(from: link.target)
                guard !targetSlug.isEmpty else { continue }
                let targetNodeID = "\(ns):\(targetSlug)"
                let edgeID = GraphEdge.computeID(from: sourceNodeID, kind: .mentions, to: targetNodeID)
                try await repository.upsertEdge(GraphEdge(
                    id: edgeID,
                    kind: .mentions,
                    from: sourceNodeID,
                    to: targetNodeID,
                    createdAt: Date(),
                    updatedAt: Date(),
                    sourceHash: nil,
                    lastIndexedAt: Date()
                ))
            }
        }
    }

    private func inferNodeKind(from document: MarkdownDocument) -> GraphNodeKind? {
        let parts = document.relativePath.lowercased().split(separator: "/")
        guard parts.count >= 2 else { return nil }
        // Look for `wiki/concepts/` or `projects/*/wiki/concepts/` patterns.
        for (index, part) in parts.enumerated() where part == "wiki" {
            let nextIndex = parts.index(after: index)
            guard nextIndex < parts.endIndex else { continue }
            switch parts[nextIndex] {
            case "concepts", "concept":
                return .concept
            case "methods", "method":
                return .method
            default:
                continue
            }
        }
        return nil
    }

    private func sourceNode(for document: MarkdownDocument, snapshot: GraphSnapshot) -> String? {
        let parts = document.relativePath.lowercased().split(separator: "/")
        // If the document is a concept/method page, use its own node id.
        if let kind = inferNodeKind(from: document) {
            let slug = GraphIdentifier.slug(from: document.title)
            return slug.isEmpty ? nil : "\(kind.rawValue):\(slug)"
        }
        // If the document is under `wiki/papers/<citekey>.md`, try to resolve
        // to a paper node.
        if parts.contains("papers") {
            let filename = document.relativePath.split(separator: "/").last?
                .replacingOccurrences(of: ".md", with: "") ?? ""
            let candidateID = "paper:citekey:\(filename.lowercased())"
            if snapshot.node(id: candidateID) != nil { return candidateID }
            // Try to find by iterating nodes (small scale).
            for (id, node) in snapshot.nodes where node.kind == .paper {
                if let citekey = node.payload.objectValue?["citekey"]?.stringValue,
                   citekey.lowercased() == filename.lowercased() {
                    return id
                }
            }
        }
        return nil
    }

    // MARK: - Tasks

    private func indexTasks(workspace: ResearchWorkspace, root: ResearchRoot, snapshot: GraphSnapshot, force: Bool) async throws {
        let todos = try await todoRepository.loadTodos(in: workspace)
        for todo in todos {
            try Task.checkCancellation()
            let nodeID = "task:\(todo.id)"
            let hash = GraphIdentifier.sourceHash(from: [
                todo.id, todo.title, todo.status.rawValue
            ])

            if !force, let existing = snapshot.node(id: nodeID), existing.sourceHash == hash {
                continue
            }

            let existingCreatedAt = snapshot.node(id: nodeID)?.createdAt ?? todo.createdAt
            try await repository.upsertNode(GraphNode(
                id: nodeID,
                kind: .task,
                displayName: todo.title,
                payload: .object([
                    "status": .string(todo.status.rawValue),
                    "priority": .string(todo.priority.rawValue)
                ]),
                createdAt: existingCreatedAt,
                updatedAt: todo.updatedAt,
                sourceHash: hash,
                lastIndexedAt: Date()
            ))

            // belongs_to edge if the todo has a project.
            for projectID in todo.projectIDs {
                let edgeID = GraphEdge.computeID(from: nodeID, kind: .belongsTo, to: "project:\(projectID)")
                try await repository.upsertEdge(GraphEdge(
                    id: edgeID,
                    kind: .belongsTo,
                    from: nodeID,
                    to: "project:\(projectID)",
                    createdAt: existingCreatedAt,
                    updatedAt: todo.updatedAt,
                    sourceHash: hash,
                    lastIndexedAt: Date()
                ))
            }
        }
    }

    // MARK: - Citation Edges

    private func indexCitationEdges(workspace: ResearchWorkspace, root: ResearchRoot, snapshot: GraphSnapshot, force: Bool) async throws {
        let papers = try await paperRepository.loadPapers(in: workspace)
        let localIndex = LocalPaperIndex(papers: papers)
        let bibtexParser = BibtexParser()
        let referencesExtractor = MarkdownReferencesExtractor()
        let textNormalizer = ReferenceTextNormalizer()
        let resolver = ReferenceResolver()
        let builder = CitationGraphBuilder(repository: repository, debug: debug)

        // 1. Parse library.bib (shared across all papers).
        let bibURL = workspace.globalLibraryBibURL
        var bibtexEntries: [BibtexEntry] = []
        if FileManager.default.fileExists(atPath: bibURL.path) {
            let bibContents = (try? String(contentsOf: bibURL, encoding: .utf8)) ?? ""
            let bibHash = GraphIdentifier.sourceHash(from: [bibContents])
            if force || snapshot.node(id: "paper:\(papers.first?.resolvedGraphNodeID ?? "")")?.sourceHash != bibHash {
                bibtexEntries = bibtexParser.parse(bibContents)
                await emit(
                    "citation.parse.bibtex",
                    payload: .object([
                        "entries_count": .number(String(bibtexEntries.count)),
                        "skipped_count": .number("0")
                    ]),
                    in: root
                )
            }
        }

        // Build a lookup from bibtex key to entry for matching papers.
        let _ = Dictionary(uniqueKeysWithValues: bibtexEntries.map { ($0.key, $0) })

        // 2. For each paper, collect references from all sources and resolve.
        for paper in papers {
            try Task.checkCancellation()
            let graphNodeID = paper.resolvedGraphNodeID
            var references: [CitationReference] = []

            // 2a. BibTeX entries that match this paper's citekey (the paper
            //     itself is the citing paper; its BibTeX entry's references
            //     are what it cites). Actually, BibTeX entries represent
            //     individual papers — the *library.bib* contains entries for
            //     all papers. The citation relationship comes from the paper's
            //     own References section or meta.yaml references field.
            //     So we skip BibTeX-as-source for now and use it only for
            //     resolving targets.

            // 2b. paper.md References section.
            let markdownURL = paper.rawMarkdownURL(in: workspace)
            if FileManager.default.fileExists(atPath: markdownURL.path) {
                let markdown = (try? String(contentsOf: markdownURL, encoding: .utf8)) ?? ""
                let rawRefs = referencesExtractor.extract(from: markdown)
                for rawRef in rawRefs {
                    let (doi, arxivID, title, firstAuthor, year) = textNormalizer.normalize(rawRef)
                    references.append(CitationReference(
                        sourcePaperID: paper.id,
                        evidenceSource: .paperMarkdown,
                        rawText: rawRef,
                        doi: doi,
                        arxivID: arxivID,
                        normalizedTitle: title,
                        firstAuthorLastName: firstAuthor,
                        year: year
                    ))
                }
                if !rawRefs.isEmpty {
                    await emit(
                        "citation.parse.markdown",
                        payload: .object([
                            "paper_id": .string(paper.id),
                            "refs_count": .number(String(rawRefs.count))
                        ]),
                        in: root
                    )
                }
            }

            // 2c. meta.yaml `references:` field.
            let metaURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
                .appendingPathComponent("meta.yaml", isDirectory: false)
            if FileManager.default.fileExists(atPath: metaURL.path) {
                let metaContents = (try? String(contentsOf: metaURL, encoding: .utf8)) ?? ""
                let metaRefs = MetaYamlReferenceReader.read(from: metaContents)
                for metaRef in metaRefs {
                    references.append(CitationReference(
                        sourcePaperID: paper.id,
                        evidenceSource: .metaYaml,
                        rawText: metaRef.title ?? metaRef.doi ?? metaRef.arxiv ?? "unknown",
                        doi: metaRef.doi,
                        arxivID: metaRef.arxiv,
                        normalizedTitle: metaRef.title.map(TitleNormalizer.normalize),
                        firstAuthorLastName: metaRef.authors?.first.flatMap { author in
                            author.split(separator: " ").last.map(String.init)
                        },
                        year: metaRef.year
                    ))
                }
            }

            // 2d. BibTeX cross-references: if the paper's own BibTeX entry
            //     contains a `crossref` field, or if we can match bibtex keys
            //     mentioned in the paper.md inline citations.
            //     Current scope: explicit References section, not inline \cite.

            guard !references.isEmpty else { continue }

            // Resolve and write edges.
            let resolved = references.map { resolver.resolve($0, localIndex: localIndex) }
            try await builder.updateCitations(
                for: graphNodeID,
                references: resolved,
                in: root
            )
        }
    }

    // MARK: - Debug

    private func emit(_ event: String, payload: JSONValue, in root: ResearchRoot) async {
        guard let debug else { return }
        try? await debug.append(AppDebugEvent(event: event, payload: payload), in: root)
    }
}
