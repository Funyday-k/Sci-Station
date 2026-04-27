import Foundation

public enum FrontmatterValue: Hashable, Sendable {
    case string(String)
    case array([String])

    public nonisolated var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }

        return value
    }

    public nonisolated var arrayValue: [String]? {
        guard case let .array(value) = self else {
            return nil
        }

        return value
    }

    public nonisolated var displayString: String {
        switch self {
        case let .string(value):
            return value.isEmpty ? "-" : value
        case let .array(value):
            return value.isEmpty ? "[]" : value.joined(separator: ", ")
        }
    }
}

public struct MarkdownFrontmatterEntry: Identifiable, Hashable, Sendable {
    public let key: String
    public let value: String

    public nonisolated init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    public nonisolated var id: String {
        key
    }
}

public struct WikiLink: Identifiable, Hashable, Sendable {
    public let target: String
    public let originalText: String

    public nonisolated init(target: String, originalText: String) {
        self.target = target
        self.originalText = originalText
    }

    public nonisolated var id: String {
        originalText
    }

    public nonisolated var normalizedTarget: String {
        Self.normalizePageKey(target)
    }

    public nonisolated static func normalizePageKey(_ value: String) -> String {
        let withoutExtension = value.replacingOccurrences(of: ".md", with: "")
        let normalizedSeparators = withoutExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        let filteredScalars = normalizedSeparators.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }
        let filtered = String(String.UnicodeScalarView(filteredScalars))

        return filtered
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

public struct MarkdownDocumentReference: Identifiable, Sendable {
    public let relativePath: String
    public let title: String

    public nonisolated init(relativePath: String, title: String) {
        self.relativePath = relativePath
        self.title = title
    }

    public nonisolated var id: String {
        relativePath
    }
}

public struct MarkdownDocument: Identifiable, Hashable, Sendable {
    public let fileURL: URL
    public let relativePath: String
    public let category: String
    public let title: String
    public let frontmatter: [String: FrontmatterValue]
    public let body: String
    public var rawContents: String
    public let outgoingLinks: [WikiLink]
    public let pageKeys: [String]

    public nonisolated init(
        fileURL: URL,
        relativePath: String,
        category: String,
        title: String,
        frontmatter: [String: FrontmatterValue],
        body: String,
        rawContents: String,
        outgoingLinks: [WikiLink],
        pageKeys: [String]
    ) {
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.category = category
        self.title = title
        self.frontmatter = frontmatter
        self.body = body
        self.rawContents = rawContents
        self.outgoingLinks = outgoingLinks
        self.pageKeys = pageKeys
    }

    public nonisolated var id: String {
        relativePath
    }

    public nonisolated var frontmatterEntries: [MarkdownFrontmatterEntry] {
        frontmatter.keys.sorted().map { key in
            MarkdownFrontmatterEntry(key: key, value: frontmatter[key]?.displayString ?? "-")
        }
    }
}