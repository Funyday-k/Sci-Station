import Foundation

public enum FrontmatterValue: Hashable, Sendable {
    case string(String)
    case array([FrontmatterValue])
    case object([String: FrontmatterValue])
    case null

    public nonisolated var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }

        return value
    }

    /// Returns a `[String]` if the value is an array of string scalars.
    /// Non-string entries are filtered; callers that need mixed content should
    /// use `arrayElements` instead.
    public nonisolated var arrayValue: [String]? {
        guard case let .array(value) = self else {
            return nil
        }

        return value.compactMap { element in
            if case let .string(string) = element {
                return string
            }
            return nil
        }
    }

    /// Returns the raw `FrontmatterValue` array, preserving object/null entries.
    public nonisolated var arrayElements: [FrontmatterValue]? {
        guard case let .array(value) = self else {
            return nil
        }
        return value
    }

    public nonisolated var objectValue: [String: FrontmatterValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    public nonisolated var displayString: String {
        switch self {
        case let .string(value):
            return value.isEmpty ? "-" : value
        case let .array(value):
            if value.isEmpty { return "[]" }
            return value.map(\.displayString).joined(separator: ", ")
        case let .object(value):
            if value.isEmpty { return "{}" }
            let rendered = value.keys.sorted().map { key in
                "\(key): \(value[key]?.displayString ?? "-")"
            }
            return "{ " + rendered.joined(separator: ", ") + " }"
        case .null:
            return "-"
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
    /// Optional namespace (e.g. `concept`, `method`, `project`, `paper`).
    /// `nil` implies the default `wiki` namespace.
    public let namespace: String?
    public let target: String
    public let originalText: String

    public nonisolated init(target: String, originalText: String, namespace: String? = nil) {
        self.namespace = namespace?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .asNonEmpty
        self.target = target
        self.originalText = originalText
    }

    public nonisolated var id: String {
        originalText
    }

    /// Combined namespace-aware key used by the backlink index.
    /// Legacy links without a namespace collapse into `wiki/<normalized>` so
    /// existing pages continue to resolve.
    public nonisolated var normalizedTarget: String {
        let ns = namespace ?? "wiki"
        return ns + "/" + Self.normalizePageKey(target)
    }

    /// Legacy target that ignored namespaces. Kept for backwards-compatible
    /// callers; prefer `normalizedTarget` for new code.
    public nonisolated var legacyNormalizedTarget: String {
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

private extension String {
    nonisolated var asNonEmpty: String? {
        isEmpty ? nil : self
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

public nonisolated enum MarkdownSaveState: String, Codable, Hashable, Sendable {
    case clean
    case dirty
    case saving
    case failed
}

public nonisolated enum MarkdownFormattingAction: String, CaseIterable, Identifiable, Hashable, Sendable {
    case heading
    case bold
    case italic
    case codeBlock
    case link
    case wikiLink
    case taskCheckbox
    case table

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heading: return "Heading"
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .codeBlock: return "Code"
        case .link: return "Link"
        case .wikiLink: return "Wikilink"
        case .taskCheckbox: return "Task"
        case .table: return "Table"
        }
    }

    public var systemImage: String {
        switch self {
        case .heading: return "textformat.size"
        case .bold: return "bold"
        case .italic: return "italic"
        case .codeBlock: return "chevron.left.forwardslash.chevron.right"
        case .link: return "link"
        case .wikiLink: return "link.badge.plus"
        case .taskCheckbox: return "checklist"
        case .table: return "tablecells"
        }
    }

    public var insertionText: String {
        switch self {
        case .heading:
            return "## Heading"
        case .bold:
            return "**bold text**"
        case .italic:
            return "_italic text_"
        case .codeBlock:
            return "```\ncode\n```"
        case .link:
            return "[label](https://example.com)"
        case .wikiLink:
            return "[[Page Title]]"
        case .taskCheckbox:
            return "- [ ] Task"
        case .table:
            return """
            | Column | Notes |
            |---|---|
            | Item | Detail |
            """
        }
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