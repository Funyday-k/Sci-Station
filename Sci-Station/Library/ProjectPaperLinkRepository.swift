import Foundation

public nonisolated struct ProjectPaperLink: Identifiable, Codable, Hashable, Sendable {
    public var projectID: String
    public var paperID: String
    public var isCore: Bool
    public var folderPath: String?
    public var useFor: [String]
    public var isPinned: Bool
    public var sortOrder: Int?
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
        isPinned: Bool = false,
        sortOrder: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.projectID = projectID
        self.paperID = paperID
        self.isCore = isCore
        self.folderPath = folderPath
        self.useFor = useFor
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case paperID = "paper_id"
        case isCore = "is_core"
        case folderPath = "folder_path"
        case useFor = "use_for"
        case isPinned = "is_pinned"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct ProjectPaperLinkMutationReceipt: Sendable {
    let projectID: String
    let paperID: String
    let previousEntry: FrontmatterValue?
    let committedEntry: FrontmatterValue?
    let revision: UInt64
}

nonisolated enum ProjectPaperLinkCompensationError: Error, LocalizedError {
    case changedSinceCommit

    var errorDescription: String? {
        "The association changed after this operation committed; its newer state was preserved."
    }
}

public actor ProjectPaperLinkRepository {
    private let fileManager: FileManager
    private var mutationRevisions: [URL: [ProjectPaperLink.ID: UInt64]] = [:]

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(in workspace: ResearchWorkspace) throws -> [ProjectPaperLink] {
        let fileURL = workspace.projectPaperLinksURL
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        return try decode(String(contentsOf: fileURL, encoding: .utf8))
    }

    public func save(_ links: [ProjectPaperLink], in workspace: ResearchWorkspace) throws {
        let previous = try load(in: workspace)
        try persist(links, in: workspace)
        for link in previous + links { recordMutation(projectID: link.projectID, paperID: link.paperID, in: workspace) }
    }

    private func persist(_ links: [ProjectPaperLink], in workspace: ResearchWorkspace) throws {
        let fileURL = workspace.projectPaperLinksURL
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = fileManager.fileExists(atPath: fileURL.path)
            ? try String(contentsOf: fileURL, encoding: .utf8) : nil
        let contents = try encodePreservingExtensions(links, existingContents: existing)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Read and mutate in one actor turn so stale UI link snapshots cannot
    /// overwrite pinned state, notes or another association update.
    func apply(
        _ mutation: PaperProjectMutation,
        projectID: String,
        paperID: String,
        in workspace: ResearchWorkspace
    ) throws -> ProjectPaperLinkMutationReceipt {
        try Task.checkCancellation()
        let previousEntry = try metadataEntry(projectID: projectID, paperID: paperID, in: workspace)
        let existing = try link(forPaperID: paperID, projectID: projectID, in: workspace)
        var link = existing ?? ProjectPaperLink(projectID: projectID, paperID: paperID)
        let removesMembership: Bool
        switch mutation {
        case .membership(false): removesMembership = true
        case .toggleMembership: removesMembership = existing != nil
        default: removesMembership = false
        }
        if removesMembership {
            try remove(projectID: projectID, paperID: paperID, in: workspace)
        } else {
            switch mutation {
            case .membership, .toggleMembership: break
            case let .core(value): link.isCore = value
            case .toggleCore: link.isCore.toggle()
            case let .pinned(value): link.isPinned = value
            case let .useFor(value): link.useFor = value
            case let .folderPath(value): link.folderPath = value
            }
            try upsert(link, in: workspace)
        }
        return ProjectPaperLinkMutationReceipt(
            projectID: projectID, paperID: paperID, previousEntry: previousEntry,
            committedEntry: try metadataEntry(projectID: projectID, paperID: paperID, in: workspace),
            revision: mutationRevision(projectID: projectID, paperID: paperID, in: workspace)
        )
    }

    /// Restore only this association if nobody has changed its committed entry.
    /// Preserve the current document's other links and root extensions, and the
    /// original entry's unknown fields. No full-file snapshot is replayed.
    func compensate(_ receipt: ProjectPaperLinkMutationReceipt, in workspace: ResearchWorkspace) throws {
        let fileURL = workspace.projectPaperLinksURL
        var mapping = try StandardsYAMLDecoder.decodeMapping(String(contentsOf: fileURL, encoding: .utf8))
        var entries = mapping["links"]?.arrayElements ?? []
        let matches: (FrontmatterValue) -> Bool = {
            $0.objectValue?["project_id"]?.stringValue == receipt.projectID
                && $0.objectValue?["paper_id"]?.stringValue == receipt.paperID
        }
        guard mutationRevision(projectID: receipt.projectID, paperID: receipt.paperID, in: workspace) == receipt.revision,
              entries.first(where: matches) == receipt.committedEntry else {
            throw ProjectPaperLinkCompensationError.changedSinceCommit
        }
        entries.removeAll(where: matches)
        if let previousEntry = receipt.previousEntry { entries.append(previousEntry) }
        mapping["links"] = .array(entries)
        try StandardsYAMLEncoder.encodeMapping(mapping).write(to: fileURL, atomically: true, encoding: .utf8)
        recordMutation(projectID: receipt.projectID, paperID: receipt.paperID, in: workspace)
    }

    private func mutationRevision(projectID: String, paperID: String, in workspace: ResearchWorkspace) -> UInt64 {
        mutationRevisions[workspace.rootURL.standardizedFileURL]?["\(projectID)::\(paperID)"] ?? 0
    }

    private func recordMutation(projectID: String, paperID: String, in workspace: ResearchWorkspace) {
        let revision = mutationRevision(projectID: projectID, paperID: paperID, in: workspace)
        mutationRevisions[workspace.rootURL.standardizedFileURL, default: [:]]["\(projectID)::\(paperID)"] = revision &+ 1
    }

    private func metadataEntry(projectID: String, paperID: String, in workspace: ResearchWorkspace) throws -> FrontmatterValue? {
        let fileURL = workspace.projectPaperLinksURL
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let mapping = try StandardsYAMLDecoder.decodeMapping(String(contentsOf: fileURL, encoding: .utf8))
        return mapping["links"]?.arrayElements?.first {
            $0.objectValue?["project_id"]?.stringValue == projectID && $0.objectValue?["paper_id"]?.stringValue == paperID
        }
    }

    public func links(forPaperID paperID: String, in workspace: ResearchWorkspace) throws -> [ProjectPaperLink] {
        try load(in: workspace)
            .filter { $0.paperID == paperID }
            .sorted(by: projectThenPaperSort)
    }

    public func links(forProjectID projectID: String, in workspace: ResearchWorkspace) throws -> [ProjectPaperLink] {
        try load(in: workspace)
            .filter { $0.projectID == projectID }
            .sorted(by: projectThenPaperSort)
    }

    public func link(forPaperID paperID: String, projectID: String, in workspace: ResearchWorkspace) throws -> ProjectPaperLink? {
        try load(in: workspace).first { $0.paperID == paperID && $0.projectID == projectID }
    }

    @discardableResult
    public func upsert(_ link: ProjectPaperLink, in workspace: ResearchWorkspace) throws -> ProjectPaperLink {
        var links = try load(in: workspace)
        let now = Date()
        var normalizedLink = normalized(link)

        if let index = links.firstIndex(where: { $0.paperID == normalizedLink.paperID && $0.projectID == normalizedLink.projectID }) {
            normalizedLink.createdAt = links[index].createdAt
            normalizedLink.updatedAt = now
            links[index] = normalizedLink
        } else {
            normalizedLink.createdAt = now
            normalizedLink.updatedAt = now
            links.append(normalizedLink)
        }

        try persist(links, in: workspace)
        recordMutation(projectID: normalizedLink.projectID, paperID: normalizedLink.paperID, in: workspace)
        return normalizedLink
    }

    @discardableResult
    public func remove(projectID: String, paperID: String, in workspace: ResearchWorkspace) throws -> [ProjectPaperLink] {
        let nextLinks = try load(in: workspace).filter { !($0.projectID == projectID && $0.paperID == paperID) }
        try persist(nextLinks, in: workspace)
        recordMutation(projectID: projectID, paperID: paperID, in: workspace)
        return nextLinks.filter { $0.paperID == paperID }.sorted(by: projectThenPaperSort)
    }

    @discardableResult
    public func setCore(_ isCore: Bool, projectID: String, paperID: String, in workspace: ResearchWorkspace) throws -> ProjectPaperLink {
        try update(projectID: projectID, paperID: paperID, in: workspace) { link in
            link.isCore = isCore
        }
    }

    @discardableResult
    public func updateUseFor(_ useFor: [String], projectID: String, paperID: String, in workspace: ResearchWorkspace) throws -> ProjectPaperLink {
        try update(projectID: projectID, paperID: paperID, in: workspace) { link in
            link.useFor = uniqueOrdered(useFor)
        }
    }

    @discardableResult
    public func updateFolderPath(_ folderPath: String?, projectID: String, paperID: String, in workspace: ResearchWorkspace) throws -> ProjectPaperLink {
        try update(projectID: projectID, paperID: paperID, in: workspace) { link in
            link.folderPath = emptyToNil(folderPath)
        }
    }

    @discardableResult
    public func setPinned(_ isPinned: Bool, projectID: String, paperID: String, in workspace: ResearchWorkspace) throws -> ProjectPaperLink {
        try update(projectID: projectID, paperID: paperID, in: workspace) { link in
            link.isPinned = isPinned
        }
    }

    @discardableResult
    public func updateSortOrder(_ sortOrder: Int?, projectID: String, paperID: String, in workspace: ResearchWorkspace) throws -> ProjectPaperLink {
        try update(projectID: projectID, paperID: paperID, in: workspace) { link in
            link.sortOrder = sortOrder
        }
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
                    isPinned: existingLink?.isPinned ?? false,
                    sortOrder: existingLink?.sortOrder,
                    createdAt: existingLink?.createdAt ?? now,
                    updatedAt: now
                )
            )
        }

        try persist(nextLinks, in: workspace)
        for link in existingLinks + nextLinks where link.paperID == paper.id {
            recordMutation(projectID: link.projectID, paperID: paper.id, in: workspace)
        }
    }

    public func removeLinks(forPaperID paperID: String, in workspace: ResearchWorkspace) throws {
        let existing = try load(in: workspace)
        let nextLinks = existing.filter { $0.paperID != paperID }
        try persist(nextLinks, in: workspace)
        for link in existing where link.paperID == paperID {
            recordMutation(projectID: link.projectID, paperID: paperID, in: workspace)
        }
    }

    private func encodePreservingExtensions(_ links: [ProjectPaperLink], existingContents: String?) throws -> String {
        guard let existingContents else { return encode(links) }
        var mapping = try StandardsYAMLDecoder.decodeMapping(existingContents)
        let existingLinks = mapping["links"]?.arrayElements ?? []
        let encoded = try StandardsYAMLDecoder.decodeMapping(encode(links))
        mapping["links"] = .array((encoded["links"]?.arrayElements ?? []).map { value in
            guard let fields = value.objectValue else { return value }
            let existing = existingLinks.first { candidate in
                candidate.objectValue?["project_id"] == fields["project_id"]
                    && candidate.objectValue?["paper_id"] == fields["paper_id"]
            }
            var preserved = existing?.objectValue ?? [:]
            preserved.merge(fields) { _, current in current }
            return .object(preserved)
        })
        return try StandardsYAMLEncoder.encodeMapping(mapping)
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
            lines.append("    is_pinned: \(link.isPinned)")
            lines.append("    sort_order: \(link.sortOrder.map(String.init) ?? "")")
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

    private func decode(_ contents: String) throws -> [ProjectPaperLink] {
        let mapping = try StandardsYAMLDecoder.decodeMapping(contents)
        return (mapping["links"]?.arrayElements ?? []).compactMap { value -> ProjectPaperLink? in
            guard let fields = value.objectValue,
                  let projectID = fields["project_id"]?.stringValue, !projectID.isEmpty,
                  let paperID = fields["paper_id"]?.stringValue, !paperID.isEmpty else { return nil }
            return ProjectPaperLink(
                projectID: projectID,
                paperID: paperID,
                isCore: fields["is_core"]?.boolValue ?? false,
                folderPath: emptyToNil(fields["folder_path"]?.stringValue),
                useFor: fields["use_for"]?.arrayElements?.compactMap(\.stringValue) ?? [],
                isPinned: fields["is_pinned"]?.boolValue ?? false,
                sortOrder: fields["sort_order"]?.integerValue,
                createdAt: fields["created_at"]?.stringValue.flatMap(parseTimestamp) ?? Date(),
                updatedAt: fields["updated_at"]?.stringValue.flatMap(parseTimestamp) ?? Date()
            )
        }
    }

    private func update(
        projectID: String,
        paperID: String,
        in workspace: ResearchWorkspace,
        mutate: (inout ProjectPaperLink) -> Void
    ) throws -> ProjectPaperLink {
        let existingLink = try link(forPaperID: paperID, projectID: projectID, in: workspace)
        var link = existingLink ?? ProjectPaperLink(projectID: projectID, paperID: paperID)
        mutate(&link)
        return try upsert(link, in: workspace)
    }

    private func normalized(_ link: ProjectPaperLink) -> ProjectPaperLink {
        var normalizedLink = link
        normalizedLink.projectID = link.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedLink.paperID = link.paperID.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedLink.folderPath = emptyToNil(link.folderPath)
        normalizedLink.useFor = uniqueOrdered(link.useFor)
        return normalizedLink
    }

    private func projectThenPaperSort(_ lhs: ProjectPaperLink, _ rhs: ProjectPaperLink) -> Bool {
        if lhs.projectID == rhs.projectID {
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            if lhs.sortOrder != rhs.sortOrder {
                switch (lhs.sortOrder, rhs.sortOrder) {
                case let (lhsOrder?, rhsOrder?):
                    return lhsOrder < rhsOrder
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
            }
            return lhs.paperID.localizedStandardCompare(rhs.paperID) == .orderedAscending
        }
        return lhs.projectID.localizedStandardCompare(rhs.projectID) == .orderedAscending
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

    private func emptyToNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}