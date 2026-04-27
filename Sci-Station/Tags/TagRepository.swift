import Foundation

public enum TagRepositoryError: LocalizedError {
    case invalidName

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Tag name cannot be empty."
        }
    }
}

public actor TagRepository {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadDefinitions(in workspace: ResearchWorkspace) throws -> [TagDefinition] {
        guard fileManager.fileExists(atPath: workspace.tagsDefinitionURL.path) else {
            return []
        }

        let contents = try String(contentsOf: workspace.tagsDefinitionURL, encoding: .utf8)
        return decode(contents)
    }

    public func upsert(_ definition: TagDefinition, in workspace: ResearchWorkspace) throws {
        let trimmedName = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TagRepositoryError.invalidName
        }

        var definitions = try loadDefinitions(in: workspace)
        let normalizedDefinition = TagDefinition(
            name: trimmedName,
            colorHex: definition.colorHex.trimmingCharacters(in: .whitespacesAndNewlines),
            textColorHex: definition.textColorHex?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if let index = definitions.firstIndex(where: { $0.name == trimmedName }) {
            definitions[index] = normalizedDefinition
        } else {
            definitions.append(normalizedDefinition)
        }

        try saveDefinitions(definitions, in: workspace)
    }

    public func deleteTag(named name: String, in workspace: ResearchWorkspace) throws {
        let filteredDefinitions = try loadDefinitions(in: workspace).filter { $0.name != name }
        try saveDefinitions(filteredDefinitions, in: workspace)
    }

    public func saveDefinitions(_ definitions: [TagDefinition], in workspace: ResearchWorkspace) throws {
        try fileManager.createDirectory(at: workspace.tagsDefinitionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(definitions).write(to: workspace.tagsDefinitionURL, atomically: true, encoding: .utf8)
    }

    private func encode(_ definitions: [TagDefinition]) -> String {
        guard !definitions.isEmpty else {
            return "tags: []\n"
        }

        let sortedDefinitions = definitions.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let body = sortedDefinitions.map { definition in
            var lines = [
                "  - name: \(quoted(definition.name))",
                "    color: \(quoted(definition.colorHex))"
            ]

            if let textColorHex = definition.textColorHex, !textColorHex.isEmpty {
                lines.append("    textColor: \(quoted(textColorHex))")
            }

            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n")

        return "tags:\n\(body)\n"
    }

    private func decode(_ contents: String) -> [TagDefinition] {
        var definitions: [TagDefinition] = []
        var currentName: String?
        var currentColor: String?
        var currentTextColor: String?

        func commitCurrent() {
            guard let currentName, let currentColor else {
                return
            }

            definitions.append(
                TagDefinition(
                    name: currentName,
                    colorHex: currentColor,
                    textColorHex: currentTextColor
                )
            )
        }

        for line in contents.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, trimmedLine != "tags:", trimmedLine != "tags: []" else {
                continue
            }

            if trimmedLine.hasPrefix("- name:") {
                commitCurrent()
                currentName = unquoted(trimmedLine.replacingOccurrences(of: "- name:", with: "").trimmingCharacters(in: .whitespaces))
                currentColor = nil
                currentTextColor = nil
                continue
            }

            if trimmedLine.hasPrefix("color:") {
                currentColor = unquoted(trimmedLine.replacingOccurrences(of: "color:", with: "").trimmingCharacters(in: .whitespaces))
                continue
            }

            if trimmedLine.hasPrefix("textColor:") {
                currentTextColor = unquoted(trimmedLine.replacingOccurrences(of: "textColor:", with: "").trimmingCharacters(in: .whitespaces))
            }
        }

        commitCurrent()
        return definitions
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
}