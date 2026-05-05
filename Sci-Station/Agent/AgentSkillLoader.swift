import Foundation

public nonisolated enum AgentSkillTrustLevel: String, Codable, Sendable {
    case trusted
    case untrusted
}

public nonisolated enum AgentSkillSource: String, Codable, Sendable {
    case appBundled = "app_bundled"
    case userGlobal = "user_global"
    case workspace
}

public nonisolated struct AgentSkillMetadata: Codable, Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var version: String
    public var author: String
    public var capabilities: [String]
    public var risk: AgentToolRisk
    public var allowedTools: [String]
    public var skillFileURL: URL
    public var source: AgentSkillSource
    public var trustLevel: AgentSkillTrustLevel

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case version
        case author
        case capabilities
        case risk
        case allowedTools = "allowed_tools"
        case skillFileURL = "skill_file_url"
        case source
        case trustLevel = "trust_level"
    }
}

public nonisolated struct AgentSkillSelection: Codable, Hashable, Sendable, Identifiable {
    public var id: String { metadata.id }
    public var metadata: AgentSkillMetadata
    public var body: String?
    public var resources: [String]

    public nonisolated init(metadata: AgentSkillMetadata, body: String? = nil, resources: [String] = []) {
        self.metadata = metadata
        self.body = body
        self.resources = resources
    }
}

public actor AgentSkillLoader {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadMetadata(searchRoots: [URL]) throws -> [AgentSkillMetadata] {
        try searchRoots.flatMap { rootURL in
            try skillFiles(under: rootURL).map { skillURL in
                try metadata(from: skillURL, source: source(for: rootURL), trustLevel: trustLevel(for: rootURL))
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func selectSkills(for prompt: String, from metadata: [AgentSkillMetadata]) throws -> [AgentSkillSelection] {
        let normalizedPrompt = prompt.lowercased()
        return try metadata.compactMap { item in
            let keywords = ([item.name, item.description] + item.capabilities).map { $0.lowercased() }
            guard keywords.contains(where: { keyword in normalizedPrompt.contains(keyword) }) else {
                return nil
            }
            return AgentSkillSelection(
                metadata: item,
                body: try body(from: item.skillFileURL),
                resources: resources(for: item.skillFileURL.deletingLastPathComponent())
            )
        }
    }

    public nonisolated static func defaultSearchRoots(workspaceRoot: URL? = nil) -> [URL] {
        var roots = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills", isDirectory: true)
        ]
        if let workspaceRoot {
            roots.append(workspaceRoot.appendingPathComponent(".claude/skills", isDirectory: true))
            roots.append(workspaceRoot.appendingPathComponent("Sci-Station/.claude/skills", isDirectory: true))
        }
        return roots
    }

    private func skillFiles(under rootURL: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }
        let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var urls: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let relativePath = url.standardizedFileURL.path.replacingOccurrences(of: rootURL.standardizedFileURL.path + "/", with: "")
            let components = relativePath.split(separator: "/").map(String.init)
            if components.contains("references") || components.contains("scripts") {
                continue
            }
            if url.lastPathComponent == "SKILL.md" || (url.pathExtension == "md" && components.count <= 2) {
                urls.append(url)
            }
        }
        return urls
    }

    private func metadata(from skillURL: URL, source: AgentSkillSource, trustLevel: AgentSkillTrustLevel) throws -> AgentSkillMetadata {
        let markdown = try String(contentsOf: skillURL, encoding: .utf8)
        let frontmatter = try frontmatterFields(in: markdown)
        let name = frontmatter["name"] ?? skillURL.deletingPathExtension().lastPathComponent
        let description = frontmatter["description"] ?? ""
        guard !name.isEmpty, !description.isEmpty else {
            throw AgentError.invalidArguments("Skill metadata requires name and description: \(skillURL.path)")
        }
        return AgentSkillMetadata(
            name: name,
            description: description,
            version: frontmatter["version"] ?? "0.1.0",
            author: frontmatter["author"] ?? "unknown",
            capabilities: listField("capabilities", in: frontmatter),
            risk: frontmatter["risk"].flatMap(AgentToolRisk.init(rawValue:)) ?? .readOnly,
            allowedTools: listField("allowed_tools", in: frontmatter),
            skillFileURL: skillURL,
            source: source,
            trustLevel: trustLevel
        )
    }

    private func body(from skillURL: URL) throws -> String {
        let markdown = try String(contentsOf: skillURL, encoding: .utf8)
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---", let endIndex = lines.dropFirst().firstIndex(of: "---") else {
            return markdown
        }
        return lines.dropFirst(endIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resources(for skillDirectory: URL) -> [String] {
        ["references", "scripts"].flatMap { folder -> [String] in
            let url = skillDirectory.appendingPathComponent(folder, isDirectory: true)
            guard let contents = try? fileManager.contentsOfDirectory(atPath: url.path) else {
                return []
            }
            return contents.sorted().map { folder + "/" + $0 }
        }
    }

    private nonisolated func frontmatterFields(in markdown: String) throws -> [String: String] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---", let endIndex = lines.dropFirst().firstIndex(of: "---") else {
            throw AgentError.invalidArguments("Skill frontmatter is required.")
        }
        var fields: [String: String] = [:]
        for line in lines[1..<endIndex] {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            fields[String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)] = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return fields
    }

    private nonisolated func listField(_ key: String, in fields: [String: String]) -> [String] {
        fields[key]?
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty } ?? []
    }

    private nonisolated func source(for rootURL: URL) -> AgentSkillSource {
        let path = rootURL.standardizedFileURL.path
        if path.contains("/Sci-Station/.claude/skills") {
            return .appBundled
        }
        if path.contains("/.claude/skills") && path.contains(NSHomeDirectory()) {
            return .userGlobal
        }
        return .workspace
    }

    private nonisolated func trustLevel(for rootURL: URL) -> AgentSkillTrustLevel {
        source(for: rootURL) == .workspace ? .untrusted : .trusted
    }
}