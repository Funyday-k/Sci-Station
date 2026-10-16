import Foundation
import Testing
@testable import SciStationCore

@Suite("Markdown domain")
struct MarkdownDomainTests {
    @Test("Standards-compliant frontmatter fixture preserves YAML semantics")
    func frontmatterCompatibilityFixture() throws {
        let contents = try fixture(named: "frontmatter-compatibility.md")
        let result = try FrontmatterParser().parseThrowing(contents)

        #expect(result.frontmatter["title"]?.stringValue == "Graph: retrieval #1")
        #expect(result.frontmatter["published"]?.stringValue == "2026-08-05")
        #expect(result.frontmatter["reviewed"]?.stringValue == "true")
        #expect(result.frontmatter["reviewed"]?.boolValue == true)
        #expect(result.frontmatter["tags"]?.arrayValue == ["rag", "knowledge graph", "citation:analysis"])
        #expect(result.frontmatter["summary"]?.stringValue == "First line keeps its newline.\n---\nSecond line keeps the # character.\n")
        #expect(result.frontmatter["empty_value"] == .null)
        #expect(result.frontmatter["copied"] == result.frontmatter["defaults"])
        #expect(result.frontmatter["defaults"]?.objectValue?["flags"]?.objectValue?["archived"]?.boolValue == false)
        #expect(result.body.hasPrefix("# Compatibility Fixture"))
    }

    @Test("Shared YAML decoder handles realistic meta references")
    func metaReferenceCompatibilityFixture() throws {
        let contents = try fixture(named: "meta-references-compatibility.yaml")
        let mapping = try StandardsYAMLDecoder.decodeMapping(contents)
        let references = try #require(mapping["references"]?.arrayElements)
        #expect(references.count == 2)

        let first = try #require(references[0].objectValue)
        #expect(first["doi"]?.stringValue == "10.1000/example:one")
        #expect(first["title"]?.stringValue == "A title: with punctuation # intact")
        #expect(first["authors"]?.arrayValue == ["Ada Lovelace", "Grace Hopper"])
        #expect(first["year"]?.stringValue == "2025")
        #expect(first["year"]?.integerValue == 2025)

        let second = try #require(references[1].objectValue)
        #expect(second["arxiv_id"]?.stringValue == "2608.01234")
        #expect(second["title"]?.stringValue == "A folded title spanning two lines")
        #expect(second["authors"]?.arrayValue == ["Katherine Johnson", "Dorothy Vaughan"])

        let decodedReferences = try MetaYamlReferenceReader.readThrowing(from: contents)
        #expect(decodedReferences == [
            MetaYamlReference(
                doi: "10.1000/example:one",
                title: "A title: with punctuation # intact",
                authors: ["Ada Lovelace", "Grace Hopper"],
                year: 2025
            ),
            MetaYamlReference(
                arxiv: "2608.01234",
                title: "A folded title spanning two lines",
                authors: ["Katherine Johnson", "Dorothy Vaughan"]
            )
        ])
    }

    @Test("Malformed frontmatter is observable to validation callers")
    func malformedFrontmatterThrows() {
        #expect(throws: (any Error).self) {
            try FrontmatterParser().parseThrowing(
                """
                ---
                title: [unterminated
                ---
                Body
                """
            )
        }
    }

    @Test("Compatibility parser preserves body when YAML is malformed")
    func malformedFrontmatterFallbackPreservesBody() {
        let result = FrontmatterParser().parse(
            """
            ---
            title: [unterminated
            ---

            Body remains readable.
            """
        )
        #expect(result.frontmatter.isEmpty)
        #expect(result.body == "Body remains readable.")
    }

    @Test("Documents without a closing delimiter remain plain Markdown")
    func unclosedFrontmatterIsPlainMarkdown() throws {
        let contents = "---\ntitle: Draft\nBody"
        let result = try FrontmatterParser().parseThrowing(contents)
        #expect(result.frontmatter.isEmpty)
        #expect(result.body == contents)
    }

    @Test("Wiki links normalize aliases and anchors")
    func wikiLinkTargets() {
        let links = WikiLinkParser().parse(
            "See [[Retrieval Augmented Generation]] and [[Knowledge Graph|KG]] plus [[RAG#Overview]]."
        )
        #expect(links.map(\.target) == ["Retrieval Augmented Generation", "Knowledge Graph", "RAG"])
    }

    @Test("Wiki links retain namespaces and deduplicate targets")
    func wikiLinkNamespaces() {
        let links = WikiLinkParser().parse(
            """
            See [[concept:dark-matter]], [[method:Glauber|Glauber method]], and [[Legacy Page]].
            Also [[concept:dark-matter#overview]].
            """
        )
        #expect(links.count == 3)
        #expect(links[0].namespace == "concept" && links[0].target == "dark-matter")
        #expect(links[1].namespace == "method" && links[1].target == "Glauber")
        #expect(links[2].namespace == nil && links[2].target == "Legacy Page")
        #expect(links[0].normalizedTarget == "concept/dark matter")
    }

    @Test("Backlinks resolve legacy links")
    func legacyBacklinks() throws {
        let target = document(
            path: "wiki/concepts/rag.md",
            title: "Retrieval Augmented Generation",
            pageKeys: [WikiLink.normalizePageKey("Retrieval Augmented Generation"), WikiLink.normalizePageKey("rag")]
        )
        let source = document(
            path: "wiki/papers/smith2024graph.md",
            title: "Graph-based Retrieval Augmented Generation",
            outgoingLinks: [WikiLink(target: "Retrieval Augmented Generation", originalText: "[[Retrieval Augmented Generation]]")],
            pageKeys: [WikiLink.normalizePageKey("Graph-based Retrieval Augmented Generation")]
        )

        let backlink = try #require(BacklinkIndex(documents: [target, source]).backlinks(for: target).first)
        #expect(backlink.relativePath == source.relativePath)
    }

    @Test("Backlinks resolve namespaced links")
    func namespacedBacklinks() throws {
        let concept = document(
            path: "wiki/concepts/dark-matter.md",
            title: "Dark Matter",
            pageKeys: [
                WikiLink.normalizePageKey("Dark Matter"),
                "concept/" + WikiLink.normalizePageKey("Dark Matter"),
                "wiki/" + WikiLink.normalizePageKey("Dark Matter")
            ]
        )
        let source = document(
            path: "wiki/papers/garani2017.md",
            title: "Dark matter in the Sun",
            outgoingLinks: [
                WikiLink(target: "Dark Matter", originalText: "[[concept:Dark Matter]]", namespace: "concept")
            ],
            pageKeys: [WikiLink.normalizePageKey("Dark matter in the Sun")]
        )

        let backlink = try #require(BacklinkIndex(documents: [concept, source]).backlinks(for: concept).first)
        #expect(backlink.relativePath == source.relativePath)
    }

    @Test("Markdown save states round-trip through Codable")
    func markdownSaveStateRoundTrip() throws {
        let states: [MarkdownSaveState] = [.clean, .dirty, .saving, .clean, .failed]
        let decoded = try JSONDecoder().decode([MarkdownSaveState].self, from: JSONEncoder().encode(states))
        #expect(decoded == states)
    }

    private func fixture(named name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func document(
        path: String,
        title: String,
        outgoingLinks: [WikiLink] = [],
        pageKeys: [String]
    ) -> MarkdownDocument {
        MarkdownDocument(
            fileURL: URL(fileURLWithPath: "/tmp").appendingPathComponent(path),
            relativePath: path,
            category: "test",
            title: title,
            frontmatter: [:],
            body: "# \(title)",
            rawContents: "# \(title)",
            outgoingLinks: outgoingLinks,
            pageKeys: pageKeys
        )
    }
}
