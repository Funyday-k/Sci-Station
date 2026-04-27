import Foundation

public struct FrontmatterParseResult: Sendable {
    public let frontmatter: [String: FrontmatterValue]
    public let body: String

    public nonisolated init(frontmatter: [String: FrontmatterValue], body: String) {
        self.frontmatter = frontmatter
        self.body = body
    }
}

public struct FrontmatterParser {
    public nonisolated init() {}

    public nonisolated func parse(_ contents: String) -> FrontmatterParseResult {
        let normalizedContents = contents.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalizedContents.components(separatedBy: "\n")

        guard lines.first == "---" else {
            return FrontmatterParseResult(frontmatter: [:], body: normalizedContents)
        }

        var frontmatter: [String: FrontmatterValue] = [:]
        var index = 1
        var foundClosingDelimiter = false

        while index < lines.count {
            let line = lines[index]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine == "---" {
                foundClosingDelimiter = true
                index += 1
                break
            }

            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                index += 1
                continue
            }

            guard let colonIndex = trimmedLine.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let key = String(trimmedLine[..<colonIndex])
            let remainder = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            if remainder == "[]" {
                frontmatter[key] = .array([])
                index += 1
                continue
            }

            if !remainder.isEmpty {
                frontmatter[key] = .string(unquote(remainder))
                index += 1
                continue
            }

            var items: [String] = []
            var cursor = index + 1

            while cursor < lines.count {
                let childLine = lines[cursor]
                let childTrimmedLine = childLine.trimmingCharacters(in: .whitespaces)

                if childTrimmedLine.isEmpty {
                    cursor += 1
                    continue
                }

                guard indentation(of: childLine) > indentation(of: line), childTrimmedLine.hasPrefix("- ") else {
                    break
                }

                items.append(unquote(String(childTrimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                cursor += 1
            }

            if !items.isEmpty {
                frontmatter[key] = .array(items)
                index = cursor
                continue
            }

            frontmatter[key] = .string("")
            index += 1
        }

        guard foundClosingDelimiter else {
            return FrontmatterParseResult(frontmatter: [:], body: normalizedContents)
        }

        var body = lines.suffix(from: index).joined(separator: "\n")
        while body.hasPrefix("\n") {
            body.removeFirst()
        }

        return FrontmatterParseResult(frontmatter: frontmatter, body: body)
    }

    private nonisolated func indentation(of line: String) -> Int {
        line.prefix(while: { $0 == " " || $0 == "\t" }).count
    }

    private nonisolated func unquote(_ value: String) -> String {
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