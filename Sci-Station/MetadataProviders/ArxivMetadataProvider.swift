import Foundation

public enum ArxivMetadataProviderError: LocalizedError {
    case invalidIdentifier(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case let .invalidIdentifier(identifier):
            return "Invalid arXiv metadata request: \(identifier)."
        case .invalidResponse:
            return "Failed to fetch arXiv metadata."
        }
    }
}

public actor ArxivMetadataProvider {
    private let session: URLSession
    private let parser: ArxivEntryParser

    public init(session: URLSession = .shared, parser: ArxivEntryParser = ArxivEntryParser()) {
        self.session = session
        self.parser = parser
    }

    public func fetchMetadata(for arxivID: String) async throws -> PaperMetadataDraft {
        var lastError: Error?

        for host in ["export.arxiv.org", "arxiv.org"] {
            do {
                let url = try Self.apiURL(for: arxivID, host: host)
                let (data, response) = try await session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw ArxivMetadataProviderError.invalidResponse
                }

                var draft = try parser.parse(data)
                draft.bibtex = try? await fetchBibTeX(for: draft.arxiv ?? arxivID)
                return draft
            } catch {
                lastError = error
            }
        }

        do {
            var draft = try await fetchMetadataFromAbstractPage(for: arxivID)
            draft.bibtex = try? await fetchBibTeX(for: draft.arxiv ?? arxivID)
            return draft
        } catch {
            lastError = error
        }

        throw lastError ?? ArxivMetadataProviderError.invalidResponse
    }

    public nonisolated static func apiURL(for arxivID: String, host: String = "export.arxiv.org") throws -> URL {
        let normalizedID = arxivID.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/query"
        components.queryItems = [
            URLQueryItem(name: "search_query", value: "id:\(normalizedID)"),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "max_results", value: "1")
        ]

        guard let url = components.url else {
            throw ArxivMetadataProviderError.invalidIdentifier(arxivID)
        }

        return url
    }

    public func fetchBibTeX(for arxivID: String) async throws -> String {
        let normalizedID = arxivID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://arxiv.org/bibtex/\(normalizedID)") else {
            throw ArxivMetadataProviderError.invalidIdentifier(arxivID)
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let bibtex = String(data: data, encoding: .utf8) else {
            throw ArxivMetadataProviderError.invalidResponse
        }

        return bibtex.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchMetadataFromAbstractPage(for arxivID: String) async throws -> PaperMetadataDraft {
        let normalizedID = arxivID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: "https://arxiv.org/abs/\(normalizedID)") else {
            throw ArxivMetadataProviderError.invalidIdentifier(arxivID)
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw ArxivMetadataProviderError.invalidResponse
        }

        return PaperMetadataDraft(
            title: metaContent(named: "citation_title", in: html) ?? "arXiv \(normalizedID)",
            authors: metaContents(named: "citation_author", in: html),
            year: metaContent(named: "citation_date", in: html).flatMap { Int($0.prefix(4)) },
            venue: "arXiv",
            doi: metaContent(named: "citation_doi", in: html),
            arxiv: normalizedID,
            inspireID: nil,
            url: "https://arxiv.org/abs/\(normalizedID)",
            pdfURL: metaContent(named: "citation_pdf_url", in: html) ?? "https://arxiv.org/pdf/\(normalizedID).pdf",
            abstract: abstractText(in: html),
            categories: [],
            sourceProvider: "arxiv-page",
            itemType: "preprint",
            publicationTitle: "arXiv",
            publishedDate: metaContent(named: "citation_date", in: html),
            archive: "arXiv",
            archiveLocation: normalizedID
        )
    }

    private nonisolated func metaContent(named name: String, in html: String) -> String? {
        metaContents(named: name, in: html).first
    }

    private nonisolated func metaContents(named name: String, in html: String) -> [String] {
        let pattern = #"<meta\s+name=["']\#(name)["']\s+content=["']([^"']*)["'][^>]*>"#
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?
            .matches(in: html, range: range) ?? []

        return matches.compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: html) else {
                return nil
            }

            return decodedHTML(String(html[matchRange]))
        }
    }

    private nonisolated func abstractText(in html: String) -> String? {
        let pattern = #"<blockquote[^>]*class=["']abstract[^"']*["'][^>]*>([\s\S]*?)</blockquote>"#
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            .firstMatch(in: html, range: range),
            let matchRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        let withoutTags = String(html[matchRange])
            .replacingOccurrences(of: "<span[^>]*>Abstract:\\s*</span>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return withoutTags.isEmpty ? nil : decodedHTML(withoutTags)
    }

    private nonisolated func decodedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}