import Foundation

public actor MarkdownSnippetRepository {
    public static let relativePath = "settings/markdown_snippets.yaml"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(in workspace: ResearchWorkspace) throws -> [MarkdownSnippet] {
        let fileURL = workspace.fileURL(for: Self.relativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Self.defaultSnippets
        }

        let snippets = decode(try String(contentsOf: fileURL, encoding: .utf8))
        return snippets.isEmpty ? Self.defaultSnippets : snippets
    }

    public nonisolated static let defaultSnippets: [MarkdownSnippet] = [
        MarkdownSnippet(
            trigger: ";h2",
            title: "Heading 2",
            body: "## ${cursor}"
        ),
        MarkdownSnippet(
            trigger: ";eq",
            title: "Display Equation",
            body: "$$\n${cursor}\n$$"
        ),
        MarkdownSnippet(
            trigger: ";fig",
            title: "Figure Reference",
            body: "![${cursor}](../figures/)"
        ),
        MarkdownSnippet(
            trigger: ";todo",
            title: "Todo Item",
            body: "- [ ] ${cursor}"
        ),
        MarkdownSnippet(
            trigger: ";paper",
            title: "Paper Note",
            body: "## Why It Matters\n\n${cursor}\n\n## Method\n\n\n## Limits\n"
        )
    ]

    private nonisolated func decode(_ contents: String) -> [MarkdownSnippet] {
        let lines = contents.components(separatedBy: .newlines)
        var snippets: [MarkdownSnippet] = []
        var cursor = 0

        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- trigger:") else {
                cursor += 1
                continue
            }

            var trigger = unquoted(trimmed.replacingOccurrences(of: "- trigger:", with: "").trimmingCharacters(in: .whitespaces))
            var title = trigger
            var body = ""
            cursor += 1

            while cursor < lines.count {
                let line = lines[cursor]
                let nestedTrimmed = line.trimmingCharacters(in: .whitespaces)
                if nestedTrimmed.hasPrefix("- trigger:") {
                    break
                }

                if nestedTrimmed.hasPrefix("title:") {
                    title = unquoted(nestedTrimmed.replacingOccurrences(of: "title:", with: "").trimmingCharacters(in: .whitespaces))
                    cursor += 1
                    continue
                }

                if nestedTrimmed.hasPrefix("body: |") {
                    let result = parseBlock(from: lines, start: cursor + 1)
                    body = result.body
                    cursor = result.nextIndex
                    continue
                }

                cursor += 1
            }

            trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trigger.isEmpty, !body.isEmpty {
                snippets.append(MarkdownSnippet(trigger: trigger, title: title, body: body))
            }
        }

        return snippets
    }

    private nonisolated func parseBlock(from lines: [String], start: Int) -> (body: String, nextIndex: Int) {
        var bodyLines: [String] = []
        var cursor = start

        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- trigger:") {
                break
            }

            if line.hasPrefix("      ") {
                bodyLines.append(String(line.dropFirst(6)))
            } else if trimmed.isEmpty {
                bodyLines.append("")
            } else if line.hasPrefix("    ") {
                bodyLines.append(String(line.dropFirst(4)))
            } else {
                break
            }
            cursor += 1
        }

        return (bodyLines.joined(separator: "\n").trimmingCharacters(in: .newlines), cursor)
    }

    private nonisolated func unquoted(_ value: String) -> String {
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
