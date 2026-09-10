import Foundation
import Testing
@testable import SciStationCore

@Suite("Citation graph compatibility builder")
struct CitationGraphBuilderTests {
    @Test("Replacing citations is atomic, occurrence-aware, and clears zero-reference state")
    func replacementPreservesOccurrencesAndClearsRemovedEvidence() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SciStationCitationBuilderTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let root = ResearchRoot(rootURL: rootURL)
        let repository = GraphRepository()
        try await repository.open(in: root)
        defer { Task { await repository.close() } }

        let source = Self.node("paper:source")
        let target = Self.node("paper:target")
        _ = try await repository.reconcile(GraphExpectedState(
            nodes: [source.id: source, target.id: target],
            edges: [:]
        ))

        let references = [
            Self.reference(locator: "references/1", occurrenceIndex: 1),
            Self.reference(locator: "references/2", occurrenceIndex: 2)
        ].map {
            ResolvedReference(reference: $0, outcome: .matchedLocal(paperGraphNodeID: "target"))
        }
        let builder = CitationGraphBuilder(repository: repository)

        try await builder.updateCitations(
            for: "source",
            references: references,
            in: root
        )

        let populated = await repository.snapshot()
        let edge = try #require(populated.edges.values.first { $0.kind == .cites })
        #expect(edge.from == source.id)
        #expect(edge.to == target.id)
        #expect(populated.edges.count == 1)
        #expect(populated.citationOccurrences.count == 2)
        #expect(populated.sourceAnchors.count == 2)
        #expect(Set(populated.citationOccurrences.values.map(\.edgeID)) == Set([edge.id]))

        try await builder.updateCitations(for: "source", references: [], in: root)

        let cleared = await repository.snapshot()
        #expect(cleared.nodes[source.id] != nil)
        #expect(cleared.nodes[target.id] != nil)
        #expect(cleared.edges.isEmpty)
        #expect(cleared.citationOccurrences.isEmpty)
        #expect(cleared.sourceAnchors.isEmpty)
    }

    private static func node(_ id: String) -> GraphNode {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return GraphNode(
            id: id,
            kind: .paper,
            displayName: id,
            createdAt: date,
            updatedAt: date,
            sourceHash: "hash:\(id)",
            lastIndexedAt: date
        )
    }

    private static func reference(locator: String, occurrenceIndex: Int) -> CitationReference {
        CitationReference(
            sourcePaperID: "source",
            evidenceSource: .paperMarkdown,
            bibtexKey: "target2026",
            rawText: "Target et al. (2026)",
            normalizedTitle: "target paper",
            sourceRelativePath: "library/papers/source/paper.md",
            locator: locator,
            occurrenceIndex: occurrenceIndex
        )
    }
}
