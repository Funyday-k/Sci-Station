import Foundation
import Testing
@testable import SciStationCore

@Suite("BibTeX export keys")
struct BibTeXExportTests {
    @Test("Provider keys follow the paper key without rewriting any field or reference")
    func providerKeyNormalization() throws {
        let source = #"""
        @article{provider-key,
          title = {A {Protected} title: García and \{literal\}},
          author = {Ada and Grace},
          crossref = {provider-key},
          custom = {Keep provider-key and @article{embedded, text} exactly}
        }
        """#
        let paper = try paper(bibtex: source)
        let expected = source.replacingOccurrences(of: "@article{provider-key,", with: "@article{local2024,")
        #expect(BibTeXFormatter.bibTeX(for: paper) == expected)
        #expect(paper.bibtex == source)
    }

    @Test("An already matching key leaves the provider entry unchanged")
    func matchingKey() throws {
        let source = "@misc{local2024, title={Exact provider field}, custom={opaque}}"
        #expect(BibTeXFormatter.bibTeX(for: try paper(bibtex: source)) == source)
    }

    @Test("Macros, preambles, comments and quoted parentheses survive exact key replacement")
    func directivesAndParentheses() throws {
        let source = #"""
        % @book{fake-comment-key, ignored}
        @comment{An unpaired " quote and @article{ignored, nested}}
        @string{journalAbbreviation = "A@B (journal)"}
        @preamble{"Keep this prefix"}
        @article ( provider-key % preserve this header comment
        , title = "A (quoted) title with \"quotes\"", journal = journalAbbreviation,
          crossref = {provider-key}, custom = {A nested {value} with )}
        )
        """#
        let expected = source.replacingOccurrences(of: "@article ( provider-key", with: "@article ( local2024")
        #expect(try BibTeXEntryKeyEditor.replacingSingleEntryKey(in: source, with: "local2024") == expected)
        #expect(try BibTeXEntryKeyEditor.entryKeys(in: expected) == ["local2024"])
        #expect(BibTeXFormatter.bibTeX(for: try paper(bibtex: source)) == expected)
    }

    @Test("Ambiguous multiple entries use an explicit metadata fallback and retain the raw source")
    func multipleEntriesFallback() throws {
        let source = "@misc{first, title={First}}\n@misc{second, title={Second}}"
        let paper = try paper(bibtex: source)
        let exported = BibTeXFormatter.bibTeX(for: paper)
        #expect(exported.contains("% Sci-Station: Multiple bibliographic entries"))
        #expect(exported.contains("title = {Metadata title}"))
        #expect(try BibTeXEntryKeyEditor.entryKeys(in: exported) == ["local2024"])
        #expect(paper.bibtex == source)
    }

    @Test("Malformed and directive-only provider input produces a visible fallback", arguments: [
        "@article{provider, title={Unclosed}",
        "@article{, title={No key}}",
        "@article{provider}",
        "@article(provider, title=\"Unclosed)",
        "@string{only = {A macro}}"
    ])
    func malformedProviderFallback(source: String) throws {
        let paper = try paper(bibtex: source)
        #expect(throws: BibTeXEntryKeyError.self) {
            try BibTeXEntryKeyEditor.replacingSingleEntryKey(in: source, with: paper.citekey)
        }
        let exported = BibTeXFormatter.bibTeX(for: paper)
        #expect(exported.hasPrefix("% Sci-Station:"))
        #expect(exported.contains("generated from paper metadata."))
        #expect(try BibTeXEntryKeyEditor.entryKeys(in: exported) == [paper.citekey])
        #expect(paper.bibtex == source)
    }

    @Test("Repeated appends deduplicate the normalized key in parenthesized provider entries")
    func repeatedAppend() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let paper = try paper(bibtex: "@misc(provider-key, title={Provider title}, custom={Retained})")
        let repository = PaperRepository()
        try await repository.appendBibliographyStub(for: paper, in: fixture)
        let first = try Data(contentsOf: fixture.globalLibraryBibURL)
        try await repository.appendBibliographyStub(for: paper, in: fixture)
        let reopened = PaperRepository()
        try await reopened.appendBibliographyStub(for: paper, in: fixture)
        #expect(try Data(contentsOf: fixture.globalLibraryBibURL) == first)
        let contents = try String(contentsOf: fixture.globalLibraryBibURL, encoding: .utf8)
        #expect(try BibTeXEntryKeyEditor.entryKeys(in: contents) == ["local2024"])
        #expect(contents.contains("custom={Retained}"))
    }

    @Test("Keys mentioned only in comments and field values do not prevent appending")
    func commentsDoNotDeduplicate() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try "% @article{local2024, not a real entry}\n@misc{other, note={Reference {local2024, in text}}}\n"
            .write(to: fixture.globalLibraryBibURL, atomically: true, encoding: .utf8)
        try await PaperRepository().appendBibliographyStub(for: paper(bibtex: nil), in: fixture)
        let contents = try String(contentsOf: fixture.globalLibraryBibURL, encoding: .utf8)
        #expect(try BibTeXEntryKeyEditor.entryKeys(in: contents) == ["other", "local2024"])
    }

    @Test("Damaged existing bibliography is rejected without overwriting its bytes")
    func malformedBibliographyIsPreserved() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let malformed = Data("@article{existing, title={Unclosed}".utf8)
        try malformed.write(to: fixture.globalLibraryBibURL)
        let paper = try paper(bibtex: nil)
        await #expect(throws: BibTeXEntryKeyError.self) {
            try await PaperRepository().appendBibliographyStub(for: paper, in: fixture)
        }
        #expect(try Data(contentsOf: fixture.globalLibraryBibURL) == malformed)
        let invalidUTF8 = Data([0xFF, 0xFE, 0xAA])
        try invalidUTF8.write(to: fixture.globalLibraryBibURL)
        await #expect(throws: (any Error).self) {
            try await PaperRepository().appendBibliographyStub(for: paper, in: fixture)
        }
        #expect(try Data(contentsOf: fixture.globalLibraryBibURL) == invalidUTF8)
    }

    private func paper(bibtex: String?) throws -> Paper {
        var paper = try PaperMetadataCodec().decodeThrowing(
            "id: public-bibtex-fixture\ncitekey: local2024\ntitle: Metadata title\nauthors: [Ada]\nyear: 2024\n",
            directoryRelativePath: "library/papers/public-bibtex-fixture", fallbackTitle: "Fallback", createdAt: nil, updatedAt: nil
        )
        paper.bibtex = bibtex
        return paper
    }

    private func fixture() throws -> ResearchWorkspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SciStationBibTeXTests-\(UUID().uuidString)")
        let workspace = ResearchWorkspace(rootURL: root)
        try FileManager.default.createDirectory(at: workspace.globalLibraryBibURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return workspace
    }
}
