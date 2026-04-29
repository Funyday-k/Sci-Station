import Foundation

public actor LibraryBulkEditService {
    private let paperRepository: PaperRepository
    private let movePaperToCollectionService: MovePaperToCollectionService

    public init(
        paperRepository: PaperRepository,
        movePaperToCollectionService: MovePaperToCollectionService? = nil
    ) {
        self.paperRepository = paperRepository
        self.movePaperToCollectionService = movePaperToCollectionService ?? MovePaperToCollectionService(paperRepository: paperRepository)
    }

    public func setStatus(_ status: ReadingStatus, for paperIDs: Set<Paper.ID>, in workspace: ResearchWorkspace) async throws -> [Paper] {
        try await updatePapers(for: paperIDs, in: workspace) { paper in
            paper.status = status
        }
    }

    public func setPriority(_ priority: Priority, for paperIDs: Set<Paper.ID>, in workspace: ResearchWorkspace) async throws -> [Paper] {
        try await updatePapers(for: paperIDs, in: workspace) { paper in
            paper.priority = priority
        }
    }

    public func setRating(_ rating: Int?, for paperIDs: Set<Paper.ID>, in workspace: ResearchWorkspace) async throws -> [Paper] {
        try await updatePapers(for: paperIDs, in: workspace) { paper in
            paper.rating = rating
        }
    }

    public func addTags(_ tags: [String], for paperIDs: Set<Paper.ID>, in workspace: ResearchWorkspace) async throws -> [Paper] {
        let normalizedTags = uniqueOrdered(tags)
        guard !normalizedTags.isEmpty else {
            return []
        }

        return try await updatePapers(for: paperIDs, in: workspace) { paper in
            paper.tags = uniqueOrdered(paper.tags + normalizedTags)
        }
    }

    public func removeTags(_ tags: [String], for paperIDs: Set<Paper.ID>, in workspace: ResearchWorkspace) async throws -> [Paper] {
        let tagsToRemove = Set(uniqueOrdered(tags))
        guard !tagsToRemove.isEmpty else {
            return []
        }

        return try await updatePapers(for: paperIDs, in: workspace) { paper in
            paper.tags = paper.tags.filter { !tagsToRemove.contains($0) }
        }
    }

    public func moveToCollection(_ collectionPath: String, for paperIDs: Set<Paper.ID>, in workspace: ResearchWorkspace) async throws -> [Paper] {
        let normalizedPath = normalizedCollectionPath(collectionPath)
        let papers = try await paperRepository.loadPapers(in: workspace)
        let targets = papers.filter { paperIDs.contains($0.id) }
        var movedPapers: [Paper] = []

        for paper in targets {
            guard (paper.collectionPath ?? "") != normalizedPath else {
                movedPapers.append(paper)
                continue
            }

            let movedPaper = try await movePaperToCollectionService.move(paper, to: normalizedPath, in: workspace)
            movedPapers.append(movedPaper)
        }

        return movedPapers
    }

    private func updatePapers(
        for paperIDs: Set<Paper.ID>,
        in workspace: ResearchWorkspace,
        mutate: (inout Paper) -> Void
    ) async throws -> [Paper] {
        guard !paperIDs.isEmpty else {
            return []
        }

        let papers = try await paperRepository.loadPapers(in: workspace)
        let targets = papers.filter { paperIDs.contains($0.id) }
        var savedPapers: [Paper] = []

        for var paper in targets {
            mutate(&paper)
            savedPapers.append(try await paperRepository.save(paper, in: workspace))
        }

        return savedPapers
    }

    private func normalizedCollectionPath(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return normalized.isEmpty ? "Uncategorized" : normalized
    }
}

public nonisolated func uniqueOrdered(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !seen.contains(trimmed) else {
            continue
        }
        seen.insert(trimmed)
        result.append(trimmed)
    }
    return result
}
