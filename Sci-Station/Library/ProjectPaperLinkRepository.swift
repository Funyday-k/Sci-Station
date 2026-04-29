import Foundation

public nonisolated struct ProjectPaperLink: Identifiable, Codable, Hashable, Sendable {
    public var projectID: String
    public var paperID: String
    public var isCore: Bool
    public var folderPath: String?
    public var useFor: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public nonisolated var id: String {
        "\(projectID)::\(paperID)"
    }

    public nonisolated init(
        projectID: String,
        paperID: String,
        isCore: Bool = false,
        folderPath: String? = nil,
        useFor: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.projectID = projectID
        self.paperID = paperID
        self.isCore = isCore
        self.folderPath = folderPath
        self.useFor = useFor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case paperID = "paper_id"
        case isCore = "is_core"
        case folderPath = "folder_path"
        case useFor = "use_for"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public actor ProjectPaperLinkRepository {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(in workspace: ResearchWorkspace) throws -> [ProjectPaperLink] {
        let fileURL = workspace.projectPaperLinksURL
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        return decode(try String(contentsOf: fileURL, encoding: .utf8))
    }

    public func save(_ links: [ProjectPaperLink], in workspace: ResearchWorkspace) throws {
        let fileURL = workspace.projectPaperLinksURL
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(links).write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func links(forPaperID paperID: String, in workspace: ResearchWorkspace) throws -> [ProjectPaperLink] {
        try load(in: workspace)
            .filter { $0.paperID == paperID }
            .sorted { $0.projectID.localizedStandardCompare($1.projectID) == .orderedAscending }
    }

    public func links(forProjectID projectID: String, in workspace: ResearchWorkspace) throws -> [ProjectPaperLink] {
        try load(in: workspace)
            .filter { $0.projectID == projectID }
            .sorted { $0.paperID.localizedStandardCompare($1.paperID) == .orderedAscending }
    }

    public func replaceLinks(for paper: Paper, in workspace: ResearchWorkspace) throws {
        let now = Date()
        let existingLinks = try load(in: workspace)
        let existingForPaper = Dictionary(uniqueKeysWithValues: existingLinks
            .filter { $0.paperID == paper.id }
            .map { ($0.projectID, $0) })
        var nextLinks = existingLinks.filter { $0.paperID != paper.id }

        for projectID in uniqueOrdered(paper.projectIDs + paper.coreProjectIDs) {
            let existingLink = existingForPaper[projectID]
            nextLinks.append(
                ProjectPaperLink(
                    projectID: projectID,
                    paperID: paper.id,
                    isCore: paper.coreProjectIDs.contains(projectID),
                    folderPath: paper.folderPath,
                    useFor: paper.useFor,
                    createdAt: existingLink?.createdAt ?? now,
                    updatedAt: now
                )
            )
        }

        try save(nextLinks, in: workspace)
    }

    public func removeLinks(forPaperID paperID: String, in workspace: ResearchWorkspace) throws {
        let nextLinks = try load(in: workspace).filter { $0.paperID != paperID }
        try save(nextLinks, in: workspace)
    }

    private func encode(_ links: [ProjectPaperLink]) -> String {
        let sortedLinks = links.sorted { lhs, rhs in
            if lhs.projectID == rhs.projectID {
                return lhs.paperID.localizedStandardCompare(rhs.paperID) == .orderedAscending
            }
            return lhs.projectID.localizedStandardCompare(rhs.projectID) == .orderedAscending
        }

        guard !sortedLinks.isEmpty else {
            return "links: []\n"
        }

        var lines = ["links:"]
        let timestampFormatter = makeTimestampFormatter()
        for link in sortedLinks {
            lines.append("  - project_id: \(quoted(link.projectID))")
            lines.append("    paper_id: \(quoted(link.paperID))")
            lines.append("    is_core: \(link.isCore)")
            lines.append("    folder_path: \(link.folderPath.map(quoted) ?? "")")
            if link.useFor.isEmpty {
                lines.append("    use_for: []")
            } else {
                lines.append("    use_for:")
                lines.append(contentsOf: link.useFor.map { "      - \(quoted($0))" })
            }
            lines.append("    created_at: \(timestampFormatter.string(from: link.createdAt))")
            lines.append("    updated_at: \(timestampFormatter.string(from: link.updatedAt))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func decode(_ contents: String) -> [ProjectPaperLink] {
        let lines = contents.components(separatedBy: .newlines)
        var links: [ProjectPaperLink] = []
        var cursor = 0

        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- project_id:") {
                let result = decodeLink(from: lines, start: cursor)
                if let link = result.link {
                    links.append(link)
                }
                cursor = result.nextIndex
            } else {
                cursor += 1
            }
        }

        return links
    }

    private func decodeLink(from lines: [String], start: Int) -> (link: ProjectPaperLink?, nextIndex: Int) {
        var projectID = unquoted(value(after: "- project_id:", in: lines[start].trimmingCharacters(in: .whitespaces)))
        var paperID = ""
        var isCore = false
        var folderPath: String?
        var useFor: [String] = []
        var createdAt = Date()
        var updatedAt = Date()
        var cursor = start + 1

        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- project_id:") {
                break
            }

            if trimmed.hasPrefix("project_id:") {
                projectID = unquoted(value(after: "project_id:", in: trimmed))
            } else if trimmed.hasPrefix("paper_id:") {
                paperID = unquoted(value(after: "paper_id:", in: trimmed))
            } else if trimmed.hasPrefix("is_core:") {
                isCore = Bool(value(after: "is_core:", in: trimmed)) ?? false
            } else if trimmed.hasPrefix("folder_path:") {
                folderPath = emptyToNil(unquoted(value(after: "folder_path:", in: trimmed)))
            } else if trimmed == "use_for:" {
                let result = parseArray(from: lines, start: cursor + 1)
                useFor = result.values
                cursor = result.nextIndex - 1
            } else if trimmed.hasPrefix("created_at:") {
                createdAt = parseTimestamp(value(after: "created_at:", in: trimmed)) ?? createdAt
            } else if trimmed.hasPrefix("updated_at:") {
                updatedAt = parseTimestamp(value(after: "updated_at:", in: trimmed)) ?? updatedAt
            }

            cursor += 1
        }

        guard !projectID.isEmpty, !paperID.isEmpty else {
            return (nil, cursor)
        }

        return (
            ProjectPaperLink(
                projectID: projectID,
                paperID: paperID,
                isCore: isCore,
                folderPath: folderPath,
                useFor: useFor,
                createdAt: createdAt,
                updatedAt: updatedAt
            ),
            cursor
        )
    }

    private func parseArray(from lines: [String], start: Int) -> (values: [String], nextIndex: Int) {
        var values: [String] = []
        var cursor = start
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else {
                break
            }
            values.append(unquoted(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            cursor += 1
        }
        return (values, cursor)
    }

    private func uniqueOrdered(_ values: [String]) -> [String] {
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

    private func value(after prefix: String, in line: String) -> String {
        line.replacingOccurrences(of: prefix, with: "").trimmingCharacters(in: .whitespaces)
    }

    private func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private func parseTimestamp(_ value: String) -> Date? {
        makeTimestampFormatter().date(from: value)
    }

    private func quoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }
        let startIndex = value.index(after: value.startIndex)
        let endIndex = value.index(before: value.endIndex)
        return value[startIndex..<endIndex]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func emptyToNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}