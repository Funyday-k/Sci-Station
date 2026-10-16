import Foundation

/// Deterministically builds the complete graph expected by the workspace and
/// commits it as one reconciliation transaction. Source enumeration order and
/// incremental node skips therefore cannot change relationship state.
public actor GraphIndexer {
    private let repository: GraphRepository
    private let paperRepository: PaperRepository
    private let projectRegistryRepository: ProjectRegistryRepository
    private let wikiLinkParser: WikiLinkParser
    private let markdownRepository: MarkdownRepository
    private let todoRepository: TodoRepository
    private let citationWarningStore: CitationResolutionStore
    private let debug: AppDebugEventLogger?

    public init(
        repository: GraphRepository,
        paperRepository: PaperRepository = PaperRepository(),
        projectRegistryRepository: ProjectRegistryRepository = ProjectRegistryRepository(),
        wikiLinkParser: WikiLinkParser = WikiLinkParser(),
        markdownRepository: MarkdownRepository = MarkdownRepository(),
        todoRepository: TodoRepository = TodoRepository(),
        citationWarningStore: CitationResolutionStore = CitationResolutionStore(),
        debug: AppDebugEventLogger? = nil
    ) {
        self.repository = repository
        self.paperRepository = paperRepository
        self.projectRegistryRepository = projectRegistryRepository
        self.wikiLinkParser = wikiLinkParser
        self.markdownRepository = markdownRepository
        self.todoRepository = todoRepository
        self.citationWarningStore = citationWarningStore
        self.debug = debug
    }

    /// Runs a full source-to-state rebuild. `force` is retained for callers
    /// and telemetry; reconciliation itself is always authoritative and
    /// canonical hashes make unchanged rows cheap no-op upserts.
    public func run(in workspace: ResearchWorkspace, root: ResearchRoot, force: Bool = false) async throws {
        await emit("graph.indexer.rebuild_started", payload: .object(["force": .bool(force)]), in: root)
        let start = Date()
        let previous = await repository.snapshot()
        let expected = try await buildExpectedState(
            workspace: workspace,
            root: root,
            previous: previous,
            indexedAt: start
        )
        let result = try await repository.reconcile(expected)
        _ = try await repository.compactIfNeeded()
        let finalSnapshot = await repository.snapshot()
        await emit(
            "graph.indexer.rebuild_finished",
            payload: .object([
                "duration_ms": .number(String(format: "%.1f", Date().timeIntervalSince(start) * 1_000)),
                "count_nodes": .number(String(finalSnapshot.nodes.count)),
                "count_edges": .number(String(finalSnapshot.edges.count)),
                "count_occurrences": .number(String(finalSnapshot.citationOccurrences.count)),
                "upserted_nodes": .number(String(result.insertedOrUpdatedNodes)),
                "upserted_edges": .number(String(result.insertedOrUpdatedEdges)),
                "deleted_nodes": .number(String(result.deletedNodes)),
                "deleted_edges": .number(String(result.deletedEdges)),
                "force": .bool(force)
            ]),
            in: root
        )
    }

    /// Internal seam used by tests and migration tooling to inspect the
    /// authoritative state before it is persisted.
    func expectedState(
        workspace: ResearchWorkspace,
        root: ResearchRoot,
        previous: GraphSnapshot? = nil,
        indexedAt: Date = Date()
    ) async throws -> GraphExpectedState {
        let previousSnapshot: GraphSnapshot
        if let previous {
            previousSnapshot = previous
        } else {
            previousSnapshot = await repository.snapshot()
        }
        return try await buildExpectedState(
            workspace: workspace,
            root: root,
            previous: previousSnapshot,
            indexedAt: indexedAt
        )
    }

    private func buildExpectedState(
        workspace: ResearchWorkspace,
        root: ResearchRoot,
        previous: GraphSnapshot,
        indexedAt: Date
    ) async throws -> GraphExpectedState {
        try Task.checkCancellation()
        async let papersTask = paperRepository.loadPapers(in: workspace)
        async let registryTask = projectRegistryRepository.load(in: root)
        async let globalDocumentsTask = markdownRepository.loadDocuments(in: workspace)
        async let todosTask = todoRepository.loadTodos(in: workspace)
        let (papers, registry, globalDocuments, todos) = try await (
            papersTask,
            registryTask,
            globalDocumentsTask,
            todosTask
        )
        var documents = globalDocuments
        for project in registry.projects.sorted(by: { $0.id < $1.id }) {
            try Task.checkCancellation()
            documents.append(contentsOf: try await markdownRepository.loadDocuments(in: workspace, project: project))
        }
        documents.sort { $0.relativePath < $1.relativePath }

        var nodes: [String: GraphNode] = [:]
        var edges: [String: GraphEdge] = [:]
        var occurrences: [String: GraphCitationOccurrence] = [:]
        var anchors: [String: GraphSourceAnchor] = [:]
        var mentionAccumulators: [String: MentionAccumulator] = [:]

        let sortedProjects = registry.projects.sorted { $0.id < $1.id }
        for project in sortedProjects {
            try Task.checkCancellation()
            let nodeID = "project:\(project.id)"
            let hash = GraphIdentifier.canonicalHash(of: project)
            nodes[nodeID] = makeNode(
                id: nodeID,
                kind: .project,
                displayName: project.name,
                payload: .object([
                    "description": .string(project.description),
                    "is_archived": .bool(project.isArchived),
                    "color_hex": .string(project.colorHex),
                    "relative_path": .string(project.relativePath)
                ]),
                sourceHash: hash,
                sourceCreatedAt: project.createdAt,
                sourceUpdatedAt: project.updatedAt,
                previous: previous,
                indexedAt: indexedAt
            )
        }

        let sortedPapers = papers.sorted { $0.resolvedGraphNodeID < $1.resolvedGraphNodeID }
        var paperNodeByCitekey: [String: String] = [:]
        for paper in sortedPapers {
            try Task.checkCancellation()
            let stableID = paper.resolvedGraphNodeID
            GraphIdentifier.assertStableIDIsClean(stableID)
            let nodeID = "paper:\(stableID)"
            paperNodeByCitekey[paper.citekey.lowercased()] = nodeID
            let hash = GraphIdentifier.canonicalHash(of: paper)
            nodes[nodeID] = makeNode(
                id: nodeID,
                kind: .paper,
                displayName: paper.title,
                payload: .object([
                    "year": paper.year.map { .number(String($0)) } ?? .null,
                    "doi": paper.doi.map(JSONValue.string) ?? .null,
                    "arxiv": paper.arxiv.map(JSONValue.string) ?? .null,
                    "citekey": .string(paper.citekey),
                    "status": .string(paper.status.rawValue),
                    "project_ids": .array(paper.projectIDs.sorted().map(JSONValue.string))
                ]),
                sourceHash: hash,
                sourceCreatedAt: paper.createdAt,
                sourceUpdatedAt: paper.updatedAt,
                previous: previous,
                indexedAt: indexedAt
            )
            for projectID in paper.projectIDs.sorted() {
                let projectNodeID = "project:\(projectID)"
                guard nodes[projectNodeID] != nil else {
                    throw GraphIndexError.missingProjectReference(paperID: paper.id, projectID: projectID)
                }
                let edgeID = GraphEdge.computeID(from: nodeID, kind: .belongsTo, to: projectNodeID)
                edges[edgeID] = makeEdge(
                    id: edgeID,
                    kind: .belongsTo,
                    from: nodeID,
                    to: projectNodeID,
                    payload: .object(["source": .string("paper.project_ids")]),
                    sourceHash: sourceHash(.object([
                        "paper": .string(nodeID),
                        "project": .string(projectNodeID)
                    ])),
                    sourceCreatedAt: previous.edge(id: edgeID)?.createdAt ?? paper.createdAt,
                    sourceUpdatedAt: paper.updatedAt,
                    previous: previous,
                    indexedAt: indexedAt
                )
            }
        }

        for todo in todos.sorted(by: { $0.id < $1.id }) {
            try Task.checkCancellation()
            let nodeID = "task:\(todo.id)"
            let hash = GraphIdentifier.canonicalHash(of: todo)
            nodes[nodeID] = makeNode(
                id: nodeID,
                kind: .task,
                displayName: todo.title,
                payload: .object([
                    "status": .string(todo.status.rawValue),
                    "priority": .string(todo.priority.rawValue),
                    "project_ids": .array(todo.projectIDs.sorted().map(JSONValue.string))
                ]),
                sourceHash: hash,
                sourceCreatedAt: todo.createdAt,
                sourceUpdatedAt: todo.updatedAt,
                previous: previous,
                indexedAt: indexedAt
            )
            for projectID in todo.projectIDs.sorted() {
                let projectNodeID = "project:\(projectID)"
                guard nodes[projectNodeID] != nil else {
                    throw GraphIndexError.missingProjectReference(paperID: todo.id, projectID: projectID)
                }
                let edgeID = GraphEdge.computeID(from: nodeID, kind: .belongsTo, to: projectNodeID)
                edges[edgeID] = makeEdge(
                    id: edgeID,
                    kind: .belongsTo,
                    from: nodeID,
                    to: projectNodeID,
                    payload: .object(["source": .string("todo.project_ids")]),
                    sourceHash: sourceHash(.object([
                        "task": .string(nodeID),
                        "project": .string(projectNodeID)
                    ])),
                    sourceCreatedAt: previous.edge(id: edgeID)?.createdAt ?? todo.createdAt,
                    sourceUpdatedAt: todo.updatedAt,
                    previous: previous,
                    indexedAt: indexedAt
                )
            }
        }

        let workspaceScope = "workspace:\(root.rootURL.standardizedFileURL.path)"
        let wikiDescriptors = buildWikiDescriptors(
            documents: documents,
            registry: registry,
            workspaceScope: workspaceScope
        )
        var wikiLookup: [WikiLookupKey: String] = [:]
        for descriptor in wikiDescriptors {
            try Task.checkCancellation()
            let modifiedAt = (try? descriptor.document.fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? descriptor.document.fileURL.resourceValuesSafeModificationDate
                ?? indexedAt
            let hash = sourceHash(.object([
                "relative_path": .string(descriptor.document.relativePath),
                "title": .string(descriptor.document.title),
                "category": .string(descriptor.document.category),
                "raw_contents": .string(descriptor.document.rawContents),
                "outgoing_links": .array(descriptor.document.outgoingLinks.map { .string($0.originalText) })
            ]))
            nodes[descriptor.nodeID] = makeNode(
                id: descriptor.nodeID,
                kind: descriptor.kind,
                displayName: descriptor.document.title,
                payload: .object([
                    "relative_path": .string(descriptor.document.relativePath),
                    "scope": .string(descriptor.scope),
                    "is_placeholder": .bool(false)
                ]),
                sourceHash: hash,
                sourceCreatedAt: modifiedAt,
                sourceUpdatedAt: modifiedAt,
                previous: previous,
                indexedAt: indexedAt
            )
            for key in descriptor.lookupKeys {
                wikiLookup[key] = descriptor.nodeID
            }
        }

        let paperLookupByCitekey = paperNodeByCitekey
        for document in documents.sorted(by: { $0.relativePath < $1.relativePath }) {
            try Task.checkCancellation()
            guard let sourceNodeID = sourceNodeID(
                for: document,
                descriptors: wikiDescriptors,
                paperByCitekey: paperLookupByCitekey
            ) else { continue }
            let sourceScope = wikiDescriptors.first(where: { $0.document.relativePath == document.relativePath })?.scope
                ?? workspaceScope
            for (index, link) in document.outgoingLinks.enumerated() {
                guard let namespace = link.namespace?.lowercased(),
                      namespace == "concept" || namespace == "method" else { continue }
                let kind = GraphNodeKind(rawValue: namespace) ?? .concept
                let key = WikiLookupKey(kind: kind, scope: sourceScope, label: normalizedWikiLabel(link.target))
                let fallbackKey = WikiLookupKey(kind: kind, scope: workspaceScope, label: normalizedWikiLabel(link.target))
                let targetNodeID = wikiLookup[key] ?? wikiLookup[fallbackKey] ?? makePlaceholderWikiNode(
                    kind: kind,
                    target: link.target,
                    scope: sourceScope,
                    nodes: &nodes,
                    previous: previous,
                    indexedAt: indexedAt
                )
                let edgeID = GraphEdge.computeID(from: sourceNodeID, kind: .mentions, to: targetNodeID)
                var accumulator = mentionAccumulators[edgeID] ?? MentionAccumulator(
                    id: edgeID,
                    from: sourceNodeID,
                    to: targetNodeID,
                    createdAt: previous.edge(id: edgeID)?.createdAt ?? indexedAt
                )
                accumulator.paths.insert(document.relativePath)
                accumulator.links.insert("\(index):\(link.originalText)")
                mentionAccumulators[edgeID] = accumulator
            }
        }
        for accumulator in mentionAccumulators.values {
            let paths = accumulator.paths.sorted()
            let links = accumulator.links.sorted()
            edges[accumulator.id] = makeEdge(
                id: accumulator.id,
                kind: .mentions,
                from: accumulator.from,
                to: accumulator.to,
                payload: .object([
                    "source_paths": .array(paths.map(JSONValue.string)),
                    "link_occurrences": .array(links.map(JSONValue.string))
                ]),
                sourceHash: sourceHash(.object([
                    "from": .string(accumulator.from),
                    "to": .string(accumulator.to),
                    "paths": .array(paths.map(JSONValue.string)),
                    "links": .array(links.map(JSONValue.string))
                ])),
                sourceCreatedAt: accumulator.createdAt,
                sourceUpdatedAt: indexedAt,
                previous: previous,
                indexedAt: indexedAt
            )
        }

        try await appendCitationState(
            papers: sortedPapers,
            workspace: workspace,
            root: root,
            nodes: &nodes,
            edges: &edges,
            occurrences: &occurrences,
            anchors: &anchors,
            previous: previous,
            indexedAt: indexedAt
        )

        return GraphExpectedState(
            nodes: nodes,
            edges: edges,
            citationOccurrences: occurrences,
            sourceAnchors: anchors
        )
    }

    private func appendCitationState(
        papers: [Paper],
        workspace: ResearchWorkspace,
        root: ResearchRoot,
        nodes: inout [String: GraphNode],
        edges: inout [String: GraphEdge],
        occurrences: inout [String: GraphCitationOccurrence],
        anchors: inout [String: GraphSourceAnchor],
        previous: GraphSnapshot,
        indexedAt: Date
    ) async throws {
        let localIndex = LocalPaperIndex(papers: papers)
        let resolver = ReferenceResolver()
        let extractor = MarkdownReferencesExtractor()
        let normalizer = ReferenceTextNormalizer()
        let parser = BibtexParser()
        let bibURL = workspace.globalLibraryBibURL
        if FileManager.default.fileExists(atPath: bibURL.path) {
            _ = parser.parse((try? String(contentsOf: bibURL, encoding: .utf8)) ?? "")
        }

        var edgeOccurrences: [String: [GraphCitationOccurrence]] = [:]
        var externalReferences: [String: (reference: CitationReference, source: ExternalSource)] = [:]

        for paper in papers.sorted(by: { $0.resolvedGraphNodeID < $1.resolvedGraphNodeID }) {
            try Task.checkCancellation()
            let sourceNodeID = "paper:\(paper.resolvedGraphNodeID)"
            var references: [CitationReference] = []
            let markdownURL = paper.rawMarkdownURL(in: workspace)
            if FileManager.default.fileExists(atPath: markdownURL.path) {
                let markdown = (try? String(contentsOf: markdownURL, encoding: .utf8)) ?? ""
                for (index, rawReference) in extractor.extract(from: markdown).enumerated() {
                    let normalized = normalizer.normalize(rawReference)
                    references.append(CitationReference(
                        sourcePaperID: paper.id,
                        evidenceSource: .paperMarkdown,
                        rawText: rawReference,
                        doi: normalized.doi,
                        arxivID: normalized.arxivID,
                        normalizedTitle: normalized.title,
                        firstAuthorLastName: normalized.firstAuthorLastName,
                        year: normalized.year,
                        sourceRelativePath: workspace.relativePath(to: markdownURL),
                        locator: "references[\(index)]",
                        occurrenceIndex: index
                    ))
                }
            }

            let metaURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
                .appendingPathComponent("meta.yaml", isDirectory: false)
            if FileManager.default.fileExists(atPath: metaURL.path) {
                let metaContents = (try? String(contentsOf: metaURL, encoding: .utf8)) ?? ""
                for (index, metaReference) in try MetaYamlReferenceReader.readThrowing(from: metaContents).enumerated() {
                    references.append(CitationReference(
                        sourcePaperID: paper.id,
                        evidenceSource: .metaYaml,
                        rawText: metaReference.title ?? metaReference.doi ?? metaReference.arxiv ?? "unknown",
                        doi: metaReference.doi,
                        arxivID: metaReference.arxiv,
                        normalizedTitle: metaReference.title.map(TitleNormalizer.normalize),
                        firstAuthorLastName: metaReference.authors?.first.flatMap { $0.split(separator: " ").last.map(String.init) },
                        year: metaReference.year,
                        sourceRelativePath: workspace.relativePath(to: metaURL),
                        locator: "references[\(index)]",
                        occurrenceIndex: index
                    ))
                }
            }

            for resolved in references.map({ resolver.resolve($0, localIndex: localIndex) }) {
                let targetNodeID: String
                switch resolved.outcome {
                case .matchedLocal(let localID):
                    targetNodeID = "paper:\(localID)"
                case .matchedExternal(let externalID, let source):
                    targetNodeID = externalID
                    if shouldPreferExternal(resolved.reference, over: externalReferences[externalID]?.reference) {
                        externalReferences[externalID] = (resolved.reference, source)
                    }
                case .unresolved(let reason):
                    try await citationWarningStore.append(
                        CitationResolutionWarning(
                            sourcePaperID: resolved.reference.sourcePaperID,
                            rawText: String(resolved.reference.rawText.prefix(200)),
                            reason: reason,
                            lastSeenAt: indexedAt
                        ),
                        in: root
                    )
                    await emit(
                        "citation.resolve_unmatched",
                        payload: .object([
                            "source_paper_id": .string(resolved.reference.sourcePaperID),
                            "reason": .string(reason)
                        ]),
                        in: root
                    )
                    continue
                }

                let edgeID = GraphEdge.computeID(from: sourceNodeID, kind: .cites, to: targetNodeID)
                let referenceHash = resolved.reference.computeHash()
                let occurrenceID = "citation_occurrence:\(GraphIdentifier.sourceHash(from: [edgeID, referenceHash]))"
                let anchorID = resolved.reference.sourceRelativePath.map {
                    "source_anchor:\(GraphIdentifier.sourceHash(from: [sourceNodeID, $0, resolved.reference.locator ?? ""]))"
                }
                if let sourceRelativePath = resolved.reference.sourceRelativePath,
                   let anchorID {
                    anchors[anchorID] = GraphSourceAnchor(
                        id: anchorID,
                        sourceNodeID: sourceNodeID,
                        relativePath: sourceRelativePath,
                        locator: resolved.reference.locator ?? "unknown",
                        excerpt: String(resolved.reference.rawText.prefix(500)),
                        sourceHash: referenceHash
                    )
                }
                let occurrence = GraphCitationOccurrence(
                    id: occurrenceID,
                    edgeID: edgeID,
                    sourceNodeID: sourceNodeID,
                    targetNodeID: targetNodeID,
                    evidenceSource: resolved.reference.evidenceSource.rawValue,
                    bibtexKey: resolved.reference.bibtexKey,
                    rawText: String(resolved.reference.rawText.prefix(2_000)),
                    ordinal: resolved.reference.occurrenceIndex,
                    sourceHash: referenceHash,
                    anchorID: anchorID
                )
                occurrences[occurrence.id] = occurrence
                edgeOccurrences[edgeID, default: []].append(occurrence)
            }
        }

        for (externalID, item) in externalReferences {
            let reference = item.reference
            let source = item.source
            let displayName: String
            switch source {
            case .doi: displayName = reference.doi ?? "External (DOI)"
            case .arxiv: displayName = reference.arxivID ?? "External (arXiv)"
            case .titleHash: displayName = reference.normalizedTitle ?? "External Paper"
            }
            let hash = sourceHash(.object([
                "id": .string(externalID),
                "source": .string(source.rawValue),
                "doi": reference.doi.map(JSONValue.string) ?? .null,
                "arxiv": reference.arxivID.map(JSONValue.string) ?? .null,
                "title": reference.normalizedTitle.map(JSONValue.string) ?? .null,
                "first_author": reference.firstAuthorLastName.map(JSONValue.string) ?? .null,
                "year": reference.year.map { .number(String($0)) } ?? .null
            ]))
            nodes[externalID] = makeNode(
                id: externalID,
                kind: .paper,
                displayName: displayName,
                payload: .object([
                    "is_external": .bool(true),
                    "source": .string(source.rawValue),
                    "doi": reference.doi.map(JSONValue.string) ?? .null,
                    "arxiv": reference.arxivID.map(JSONValue.string) ?? .null,
                    "title": reference.normalizedTitle.map(JSONValue.string) ?? .null,
                    "first_author": reference.firstAuthorLastName.map(JSONValue.string) ?? .null,
                    "year": reference.year.map { .number(String($0)) } ?? .null
                ]),
                sourceHash: hash,
                sourceCreatedAt: previous.node(id: externalID)?.createdAt ?? indexedAt,
                sourceUpdatedAt: indexedAt,
                previous: previous,
                indexedAt: indexedAt
            )
        }

        for (edgeID, edgeItems) in edgeOccurrences {
            guard let first = edgeItems.first else { continue }
            let sorted = edgeItems.sorted { $0.id < $1.id }
            let sourceHashValue = sourceHash(.array(sorted.map { .string($0.sourceHash) }))
            edges[edgeID] = makeEdge(
                id: edgeID,
                kind: .cites,
                from: first.sourceNodeID,
                to: first.targetNodeID,
                payload: .object([
                    "occurrence_count": .number(String(sorted.count)),
                    "evidence_sources": .array(Array(Set(sorted.map(\.evidenceSource))).sorted().map(JSONValue.string))
                ]),
                sourceHash: sourceHashValue,
                sourceCreatedAt: previous.edge(id: edgeID)?.createdAt ?? indexedAt,
                sourceUpdatedAt: indexedAt,
                previous: previous,
                indexedAt: indexedAt
            )
        }
    }

    private func buildWikiDescriptors(
        documents: [MarkdownDocument],
        registry: ProjectRegistry,
        workspaceScope: String
    ) -> [WikiDescriptor] {
        documents.compactMap { document in
            guard let kind = inferNodeKind(from: document) else { return nil }
            let scope = projectScope(for: document.relativePath, registry: registry) ?? workspaceScope
            let nodeID = GraphIdentifier.scopedEntityID(kind: kind, name: document.title, scope: scope)
            let labels = Set([
                normalizedWikiLabel(document.title),
                normalizedWikiLabel(URL(fileURLWithPath: document.relativePath).deletingPathExtension().lastPathComponent)
            ] + document.pageKeys.map(normalizedWikiLabel)).filter { !$0.isEmpty }
            return WikiDescriptor(
                document: document,
                kind: kind,
                scope: scope,
                nodeID: nodeID,
                lookupKeys: labels.map { WikiLookupKey(kind: kind, scope: scope, label: $0) }
            )
        }.sorted { $0.document.relativePath < $1.document.relativePath }
    }

    private func makePlaceholderWikiNode(
        kind: GraphNodeKind,
        target: String,
        scope: String,
        nodes: inout [String: GraphNode],
        previous: GraphSnapshot,
        indexedAt: Date
    ) -> String {
        let nodeID = GraphIdentifier.scopedEntityID(kind: kind, name: target, scope: scope)
        guard nodes[nodeID] == nil else { return nodeID }
        let hash = sourceHash(.object([
            "kind": .string(kind.rawValue),
            "target": .string(target),
            "scope": .string(scope),
            "placeholder": .bool(true)
        ]))
        nodes[nodeID] = makeNode(
            id: nodeID,
            kind: kind,
            displayName: target,
            payload: .object([
                "relative_path": .null,
                "scope": .string(scope),
                "is_placeholder": .bool(true)
            ]),
            sourceHash: hash,
            sourceCreatedAt: previous.node(id: nodeID)?.createdAt ?? indexedAt,
            sourceUpdatedAt: indexedAt,
            previous: previous,
            indexedAt: indexedAt
        )
        return nodeID
    }

    private func sourceNodeID(
        for document: MarkdownDocument,
        descriptors: [WikiDescriptor],
        paperByCitekey: [String: String]
    ) -> String? {
        if let descriptor = descriptors.first(where: { $0.document.relativePath == document.relativePath }) {
            return descriptor.nodeID
        }
        if let citekey = document.frontmatter["citekey"]?.stringValue?.lowercased(),
           let paperID = paperByCitekey[citekey] {
            return paperID
        }
        if document.relativePath.lowercased().split(separator: "/").contains("papers") {
            let filename = URL(fileURLWithPath: document.relativePath).deletingPathExtension().lastPathComponent.lowercased()
            return paperByCitekey[filename]
        }
        return nil
    }

    private func inferNodeKind(from document: MarkdownDocument) -> GraphNodeKind? {
        let parts = document.relativePath.lowercased().split(separator: "/")
        for (index, part) in parts.enumerated() where part == "wiki" {
            let next = parts.index(after: index)
            guard next < parts.endIndex else { continue }
            switch parts[next] {
            case "concept", "concepts": return .concept
            case "method", "methods": return .method
            default: continue
            }
        }
        return nil
    }

    private func projectScope(for relativePath: String, registry: ProjectRegistry) -> String? {
        registry.projects
            .filter { relativePath == $0.relativePath || relativePath.hasPrefix($0.relativePath + "/") }
            .sorted { $0.relativePath.count > $1.relativePath.count }
            .first.map { "project:\($0.id)" }
    }

    private func normalizedWikiLabel(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    private func makeNode(
        id: String,
        kind: GraphNodeKind,
        displayName: String,
        payload: JSONValue,
        sourceHash: String,
        sourceCreatedAt: Date,
        sourceUpdatedAt: Date,
        previous: GraphSnapshot,
        indexedAt: Date
    ) -> GraphNode {
        GraphNode(
            id: id,
            kind: kind,
            displayName: displayName,
            payload: payload,
            createdAt: previous.node(id: id)?.createdAt ?? sourceCreatedAt,
            updatedAt: sourceUpdatedAt,
            sourceHash: sourceHash,
            lastIndexedAt: previous.node(id: id)?.sourceHash == sourceHash
                ? previous.node(id: id)?.lastIndexedAt ?? indexedAt
                : indexedAt
        )
    }

    private func makeEdge(
        id: String,
        kind: GraphEdgeKind,
        from: String,
        to: String,
        payload: JSONValue,
        sourceHash: String,
        sourceCreatedAt: Date,
        sourceUpdatedAt: Date,
        previous: GraphSnapshot,
        indexedAt: Date
    ) -> GraphEdge {
        GraphEdge(
            id: id,
            kind: kind,
            from: from,
            to: to,
            payload: payload,
            createdAt: previous.edge(id: id)?.createdAt ?? sourceCreatedAt,
            updatedAt: sourceUpdatedAt,
            sourceHash: sourceHash,
            lastIndexedAt: previous.edge(id: id)?.sourceHash == sourceHash
                ? previous.edge(id: id)?.lastIndexedAt ?? indexedAt
                : indexedAt
        )
    }

    private func sourceHash(_ value: JSONValue) -> String {
        GraphIdentifier.canonicalHash(of: value)
    }

    private func shouldPreferExternal(
        _ candidate: CitationReference,
        over current: CitationReference?
    ) -> Bool {
        guard let current else { return true }
        let candidateScore = [candidate.doi, candidate.arxivID, candidate.normalizedTitle, candidate.firstAuthorLastName, candidate.year.map(String.init)].compactMap { $0 }.count
        let currentScore = [current.doi, current.arxivID, current.normalizedTitle, current.firstAuthorLastName, current.year.map(String.init)].compactMap { $0 }.count
        if candidateScore != currentScore { return candidateScore > currentScore }
        return candidate.computeHash() < current.computeHash()
    }

    private func emit(_ event: String, payload: JSONValue, in root: ResearchRoot) async {
        guard let debug else { return }
        try? await debug.append(AppDebugEvent(event: event, payload: payload), in: root)
    }
}

private struct WikiLookupKey: Hashable {
    let kind: GraphNodeKind
    let scope: String
    let label: String
}

private struct WikiDescriptor {
    let document: MarkdownDocument
    let kind: GraphNodeKind
    let scope: String
    let nodeID: String
    let lookupKeys: [WikiLookupKey]
}

private struct MentionAccumulator {
    let id: String
    let from: String
    let to: String
    let createdAt: Date
    var paths: Set<String> = []
    var links: Set<String> = []
}

public nonisolated enum GraphIndexError: Error, LocalizedError, Sendable {
    case missingProjectReference(paperID: String, projectID: String)

    public var errorDescription: String? {
        switch self {
        case let .missingProjectReference(paperID, projectID):
            return "Graph source \(paperID) references missing project \(projectID)."
        }
    }
}

private extension URL {
    var resourceValuesSafeModificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
    }
}
