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
        // Normalise tabs in indentation context to a single space so downstream
        // indent checks are stable. We still keep a round-trippable copy for
        // future Yams migration; this pre-processing only affects parsing.
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
            if remainder == "{}" {
                frontmatter[key] = .object([:])
                index += 1
                continue
            }

            if !remainder.isEmpty {
                frontmatter[key] = parseScalarValue(remainder)
                index += 1
                continue
            }

            // No scalar on this line. Look ahead for a child block. Children
            // may be list entries (`- value` or `- key:` for list-of-object),
            // or `key: value` scalars that together form a nested object.
            let parentIndent = indentation(of: line)
            let childCandidate = nextNonEmptyLine(after: index, in: lines)
            guard childCandidate < lines.count,
                  indentation(of: lines[childCandidate]) > parentIndent else {
                frontmatter[key] = .null
                index += 1
                continue
            }

            let firstChildTrimmed = lines[childCandidate].trimmingCharacters(in: .whitespaces)
            if firstChildTrimmed.hasPrefix("- ") || firstChildTrimmed == "-" {
                let parse = parseListBlock(
                    startingAt: childCandidate,
                    in: lines,
                    parentIndent: parentIndent
                )
                frontmatter[key] = .array(parse.values)
                index = parse.nextIndex
            } else {
                let parse = parseObjectBlock(
                    startingAt: childCandidate,
                    in: lines,
                    parentIndent: parentIndent
                )
                frontmatter[key] = .object(parse.values)
                index = parse.nextIndex
            }
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

    private nonisolated func parseListBlock(
        startingAt start: Int,
        in lines: [String],
        parentIndent: Int
    ) -> (values: [FrontmatterValue], nextIndex: Int) {
        var items: [FrontmatterValue] = []
        var cursor = start

        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                cursor += 1
                continue
            }

            let lineIndent = indentation(of: line)
            guard lineIndent > parentIndent, trimmed.hasPrefix("-") else {
                break
            }

            let afterDash = trimmed.count > 1
                ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                : ""

            if afterDash.isEmpty {
                // `-` on its own: a list-of-object entry with child lines at a
                // deeper indent.
                let nested = parseObjectBlock(
                    startingAt: cursor + 1,
                    in: lines,
                    parentIndent: lineIndent
                )
                items.append(.object(nested.values))
                cursor = nested.nextIndex
                continue
            }

            // Does this entry look like `- key: value`? If so, treat it as the
            // first child of an object whose remaining keys sit at the next
            // indent level.
            if let colonIndex = afterDash.firstIndex(of: ":") {
                let firstKey = String(afterDash[..<colonIndex])
                let firstValue = String(afterDash[afterDash.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                if !firstKey.isEmpty, firstKey.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
                    var objectChildren: [String: FrontmatterValue] = [:]
                    objectChildren[firstKey] = firstValue.isEmpty ? .null : parseScalarValue(firstValue)
                    let continued = parseObjectBlock(
                        startingAt: cursor + 1,
                        in: lines,
                        parentIndent: lineIndent
                    )
                    for (key, value) in continued.values {
                        objectChildren[key] = value
                    }
                    items.append(.object(objectChildren))
                    cursor = continued.nextIndex
                    continue
                }
            }

            items.append(parseScalarValue(afterDash))
            cursor += 1
        }

        return (items, cursor)
    }

    private nonisolated func parseObjectBlock(
        startingAt start: Int,
        in lines: [String],
        parentIndent: Int
    ) -> (values: [String: FrontmatterValue], nextIndex: Int) {
        var values: [String: FrontmatterValue] = [:]
        var cursor = start

        while cursor < lines.count {
            let line = lines[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                cursor += 1
                continue
            }

            let lineIndent = indentation(of: line)
            guard lineIndent > parentIndent else {
                break
            }

            guard let colonIndex = trimmed.firstIndex(of: ":") else {
                break
            }
            let key = String(trimmed[..<colonIndex])
            let remainder = String(trimmed[trimmed.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            if remainder == "[]" {
                values[key] = .array([])
                cursor += 1
                continue
            }
            if remainder == "{}" {
                values[key] = .object([:])
                cursor += 1
                continue
            }
            if !remainder.isEmpty {
                values[key] = parseScalarValue(remainder)
                cursor += 1
                continue
            }

            // Look ahead for a deeper nested block.
            let childCandidate = nextNonEmptyLine(after: cursor, in: lines)
            guard childCandidate < lines.count,
                  indentation(of: lines[childCandidate]) > lineIndent else {
                values[key] = .null
                cursor += 1
                continue
            }
            let firstChildTrimmed = lines[childCandidate].trimmingCharacters(in: .whitespaces)
            if firstChildTrimmed.hasPrefix("-") {
                let nested = parseListBlock(startingAt: childCandidate, in: lines, parentIndent: lineIndent)
                values[key] = .array(nested.values)
                cursor = nested.nextIndex
            } else {
                let nested = parseObjectBlock(startingAt: childCandidate, in: lines, parentIndent: lineIndent)
                values[key] = .object(nested.values)
                cursor = nested.nextIndex
            }
        }

        return (values, cursor)
    }

    private nonisolated func parseScalarValue(_ raw: String) -> FrontmatterValue {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .null }
        let lowered = trimmed.lowercased()
        if lowered == "null" || lowered == "~" { return .null }
        return .string(unquote(trimmed))
    }

    private nonisolated func nextNonEmptyLine(after index: Int, in lines: [String]) -> Int {
        var cursor = index + 1
        while cursor < lines.count {
            if !lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty {
                return cursor
            }
            cursor += 1
        }
        return cursor
    }

    private nonisolated func indentation(of line: String) -> Int {
        // Treat tabs as a single indent unit for stability. This mirrors how
        // lenient YAML parsers resolve indent levels for file handling; for
        // strict YAML semantics we will eventually migrate to Yams.
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    private nonisolated func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }

        let startIndex = value.index(after: value.startIndex)
        let endIndex = value.index(before: value.endIndex)
        return value[startIndex..<endIndex]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
