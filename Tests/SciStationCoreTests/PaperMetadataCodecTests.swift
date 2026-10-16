import Foundation
import Testing
@testable import SciStationCore

@Suite("Paper metadata YAML")
struct PaperMetadataCodecTests {
    @Test("Complex standards-compliant YAML decodes without lossy fallbacks")
    func complexYAMLDecodes() throws {
        let contents = """
        defaults: &defaults
          status: unread
          priority: medium
        <<: *defaults
        id: sample-2026
        citekey: sample2026yaml
        title: 'YAML: external tools # compatible'
        authors: ["Ada Lovelace", 'Grace Hopper']
        year: 2026
        abstract: |-
          First line.
          Second line: # retained.
        tags: [yaml, metadata]
        use_for: []
        reading:
          added: 2026-08-06
          last_page: 17
          last_scale: 1.25
        references:
          - doi: "10.1000/example"
            evidence:
              pages: [4, 9]
              verified: true
        """

        let paper = try PaperMetadataCodec().decodeThrowing(
            contents,
            directoryRelativePath: "library/papers/sample-2026",
            fallbackTitle: "Fallback",
            createdAt: nil,
            updatedAt: nil
        )

        #expect(paper.title == "YAML: external tools # compatible")
        #expect(paper.authors == ["Ada Lovelace", "Grace Hopper"])
        #expect(paper.year == 2026)
        #expect(paper.abstract == "First line.\nSecond line: # retained.")
        #expect(paper.tags == ["yaml", "metadata"])
        #expect(paper.status == .unread)
        #expect(paper.priority == .medium)
        #expect(paper.lastReadPage == 17)
        #expect(paper.lastReadScale == 1.25)
    }

    @Test("Encoding preserves unknown nested metadata semantically")
    func unknownMetadataSurvivesRoundTrip() throws {
        let existing = """
        id: sample-2026
        citekey: sample2026yaml
        title: Original
        authors: [Ada]
        status: unread
        priority: medium
        reading:
          added: 2026-08-06
          custom:
            reviewed: true
        references:
          - doi: 10.1000/example
            evidence:
              pages: [4, 9]
              verified: true
        custom_field:
          enabled: false
          threshold: 0.75
        """
        let codec = PaperMetadataCodec()
        var paper = try codec.decodeThrowing(
            existing,
            directoryRelativePath: "library/papers/sample-2026",
            fallbackTitle: "Fallback",
            createdAt: nil,
            updatedAt: nil
        )
        paper.title = "Updated"

        let encoded = try codec.encodeThrowing(paper, preserving: existing)
        let mapping = try StandardsYAMLDecoder.decodeMapping(encoded)
        let reference = try #require(mapping["references"]?.arrayElements?.first?.objectValue)
        let evidence = try #require(reference["evidence"]?.objectValue)
        let customField = try #require(mapping["custom_field"]?.objectValue)
        let reading = try #require(mapping["reading"]?.objectValue)

        #expect(mapping["title"]?.stringValue == "Updated")
        #expect(reference["doi"]?.stringValue == "10.1000/example")
        #expect(evidence["pages"]?.arrayElements == [.integer(4), .integer(9)])
        #expect(evidence["verified"]?.boolValue == true)
        #expect(customField["enabled"]?.boolValue == false)
        #expect(customField["threshold"]?.floatingPointValue == 0.75)
        #expect(reading["custom"]?.objectValue?["reviewed"]?.boolValue == true)
    }

    @Test("Malformed metadata is observable to persistence callers")
    func malformedMetadataThrows() {
        #expect(throws: (any Error).self) {
            try PaperMetadataCodec().decodeThrowing(
                "title: [unterminated",
                directoryRelativePath: "library/papers/broken",
                fallbackTitle: "Broken",
                createdAt: nil,
                updatedAt: nil
            )
        }
        #expect(throws: (any Error).self) {
            try PaperMetadataCodec().encodeThrowing(
                samplePaper(),
                preserving: "title: [unterminated"
            )
        }
    }

    @Test("Stable graph identifiers are emitted and decoded")
    func graphNodeIDRoundTrip() throws {
        let codec = PaperMetadataCodec()
        let encoded = try codec.encodeThrowing(samplePaper())
        #expect(encoded.contains("graph_node_id: \"arxiv:2608.01234\""))
        #expect(try codec.decodedGraphNodeIDThrowing(from: encoded) == "arxiv:2608.01234")
    }

    private func samplePaper() -> Paper {
        let now = Date(timeIntervalSince1970: 1_775_606_400)
        return Paper(
            id: "sample-2026",
            citekey: "sample2026yaml",
            title: "YAML metadata",
            authors: ["Ada Lovelace"],
            year: 2026,
            venue: nil,
            doi: nil,
            arxiv: "2608.01234v1",
            url: nil,
            pdfRelativePath: nil,
            tags: ["yaml"],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: now,
            updatedAt: now,
            paperDirectoryRelativePath: "library/papers/sample-2026",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
    }
}
