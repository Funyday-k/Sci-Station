import Foundation

public actor RecommendationCandidateGatherer {
    public init() {}

    public func gather(
        papers: [Paper],
        queueEntries: [ResearchQueueEntry] = [],
        dailyFeedCandidates: [RecommendationCandidate] = [],
        graph: GraphReadModel? = nil,
        context: RecommendationContext,
        config: RecommendationConfig = RecommendationConfig()
    ) async -> [RecommendationCandidate] {
        var candidatesByID: [String: RecommendationCandidate] = [:]

        for candidate in gatherLibraryRecent(papers: papers, context: context, config: config) {
            merge(candidate, into: &candidatesByID)
        }
        for candidate in gatherQueueTail(entries: queueEntries) {
            merge(candidate, into: &candidatesByID)
        }
        for candidate in dailyFeedCandidates.prefix(config.maxDailyCandidates) {
            var normalized = candidate
            normalized.sourceTags.insert(.dailyFeed)
            merge(normalized, into: &candidatesByID)
        }
        if let graph {
            for candidate in await gatherGraphOneHop(papers: papers, graph: graph, context: context) {
                merge(candidate, into: &candidatesByID)
            }
        }

        return candidatesByID.values.sorted {
            if $0.sourceTags.contains(.dailyFeed) != $1.sourceTags.contains(.dailyFeed) {
                return $0.sourceTags.contains(.dailyFeed)
            }
            return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
        }
    }

    public func gatherLibraryRecent(
        papers: [Paper],
        context: RecommendationContext,
        config: RecommendationConfig = RecommendationConfig()
    ) -> [RecommendationCandidate] {
        let cutoff = context.evaluatedAt.addingTimeInterval(-Double(config.libraryRecentDays) * 24 * 60 * 60)
        return papers
            .filter { paper in
                switch config.scope {
                case .activeProjectOnly:
                    guard let projectID = context.projectID else { return true }
                    return paper.projectIDs.contains(projectID) || paper.coreProjectIDs.contains(projectID)
                case .allProjects:
                    return !paper.projectIDs.isEmpty || !paper.coreProjectIDs.isEmpty
                case .workspace:
                    return true
                }
            }
            .filter { $0.createdAt >= cutoff || $0.updatedAt >= cutoff }
            .map { paper in
                var candidate = Self.candidate(from: paper)
                candidate.sourceTags.insert(.libraryRecent)
                candidate.addedToLibraryAt = paper.createdAt
                return candidate
            }
    }

    public func gatherQueueTail(entries: [ResearchQueueEntry]) -> [RecommendationCandidate] {
        entries
            .filter { $0.status == .queued || $0.status == .deferred }
            .sorted { lhs, rhs in
                if lhs.lastTouchedAt != rhs.lastTouchedAt {
                    return lhs.lastTouchedAt < rhs.lastTouchedAt
                }
                return lhs.order < rhs.order
            }
            .map { entry in
                RecommendationCandidate(
                    canonicalID: Self.canonicalID(paperID: entry.paperID, externalKey: entry.externalKey, fallback: entry.id),
                    paperID: entry.paperID,
                    externalKey: entry.externalKey,
                    displayTitle: entry.displayTitle,
                    sourceTags: [.queueTail]
                )
            }
    }

    public func gatherGraphOneHop(
        papers: [Paper],
        graph: GraphReadModel,
        context: RecommendationContext
    ) async -> [RecommendationCandidate] {
        guard !context.corePaperIDs.isEmpty else {
            return []
        }

        let papersByGraphNode = Dictionary(uniqueKeysWithValues: papers.map { ($0.resolvedGraphNodeID, $0) })
        var candidatesByID: [String: RecommendationCandidate] = [:]

        for coreID in context.corePaperIDs.sorted() {
            let corePaper = papers.first { $0.id == coreID }
            let coreNodeID = corePaper?.resolvedGraphNodeID ?? "paper:\(coreID)"
            let edges = await graph.neighbors(of: coreNodeID, depth: 1, kinds: [.cites, .extends, .relatedTo])
            for edge in edges {
                let otherNodeID = edge.from == coreNodeID ? edge.to : edge.from
                guard otherNodeID.hasPrefix("paper:") else {
                    continue
                }
                if otherNodeID == coreNodeID {
                    continue
                }
                if let paper = papersByGraphNode[otherNodeID], context.corePaperIDs.contains(paper.id) {
                    continue
                }
                var candidate: RecommendationCandidate
                if let paper = papersByGraphNode[otherNodeID] {
                    candidate = Self.candidate(from: paper)
                } else {
                    let node = await graph.node(id: otherNodeID)
                    candidate = RecommendationCandidate(
                        canonicalID: Self.externalCanonicalID(forGraphNodeID: otherNodeID),
                        externalKey: Self.externalKey(forGraphNodeID: otherNodeID),
                        displayTitle: node?.displayName ?? otherNodeID,
                        publishedYear: node?.payload.objectValue?["year"]?.stringValue.flatMap(Int.init),
                        sourceName: "graph"
                    )
                }
                candidate.sourceTags.insert(.graphOneHop)
                candidate.citedByCorePaperIDs.insert(coreID)
                merge(candidate, into: &candidatesByID)
            }
        }

        return Array(candidatesByID.values)
    }

    public nonisolated static func candidate(from paper: Paper) -> RecommendationCandidate {
        RecommendationCandidate(
            canonicalID: "paper:\(paper.id)",
            paperID: paper.id,
            externalKey: externalKey(from: paper),
            displayTitle: paper.displayTitle,
            authors: paper.authors,
            publishedYear: paper.year,
            sourceName: paper.venue ?? paper.publicationTitle,
            sourceURL: paper.url,
            pdfURL: paper.pdfURL,
            categories: paper.categories,
            addedToLibraryAt: paper.createdAt,
            abstractText: paper.abstract
        )
    }

    public nonisolated static func canonicalID(paperID: String?, externalKey: String?, fallback: String) -> String {
        if let paperID = paperID?.trimmingCharacters(in: .whitespacesAndNewlines), !paperID.isEmpty {
            return "paper:\(paperID)"
        }
        if let externalKey = externalKey?.trimmingCharacters(in: .whitespacesAndNewlines), !externalKey.isEmpty {
            return "external:\(externalKey.lowercased())"
        }
        return "external:\(fallback.lowercased())"
    }

    private nonisolated static func externalKey(from paper: Paper) -> String? {
        if let arxiv = PaperIdentityGenerator.normalizedArxiv(paper.arxiv) {
            return "arxiv:\(arxiv)"
        }
        if let doi = PaperIdentityGenerator.normalizedDOI(paper.doi) {
            return "doi:\(doi)"
        }
        if let inspireID = paper.inspireID?.trimmingCharacters(in: .whitespacesAndNewlines), !inspireID.isEmpty {
            return "inspire:\(inspireID.lowercased())"
        }
        return nil
    }

    private nonisolated static func externalCanonicalID(forGraphNodeID nodeID: String) -> String {
        "external:\(externalKey(forGraphNodeID: nodeID))"
    }

    private nonisolated static func externalKey(forGraphNodeID nodeID: String) -> String {
        if nodeID.hasPrefix("paper:") {
            return String(nodeID.dropFirst("paper:".count)).lowercased()
        }
        return nodeID.lowercased()
    }

    private nonisolated func merge(_ candidate: RecommendationCandidate, into candidatesByID: inout [String: RecommendationCandidate]) {
        if var existing = candidatesByID[candidate.canonicalID] {
            existing.sourceTags.formUnion(candidate.sourceTags)
            existing.citedByCorePaperIDs.formUnion(candidate.citedByCorePaperIDs)
            if existing.paperID == nil { existing.paperID = candidate.paperID }
            if existing.externalKey == nil { existing.externalKey = candidate.externalKey }
            if existing.authors.isEmpty { existing.authors = candidate.authors }
            if existing.publishedYear == nil { existing.publishedYear = candidate.publishedYear }
            if existing.sourceName == nil { existing.sourceName = candidate.sourceName }
            if existing.sourceURL == nil { existing.sourceURL = candidate.sourceURL }
            if existing.pdfURL == nil { existing.pdfURL = candidate.pdfURL }
            if existing.categories.isEmpty { existing.categories = candidate.categories }
            if existing.addedToLibraryAt == nil { existing.addedToLibraryAt = candidate.addedToLibraryAt }
            if existing.abstractText == nil { existing.abstractText = candidate.abstractText }
            candidatesByID[candidate.canonicalID] = existing
        } else {
            candidatesByID[candidate.canonicalID] = candidate
        }
    }
}
