import Foundation

nonisolated enum BibTeXEntryKeyError: Error, LocalizedError, Equatable {
    case malformedEntry
    case noBibliographicEntry
    case multipleBibliographicEntries
    case invalidCitekey

    var errorDescription: String? {
        switch self {
        case .malformedEntry: return "Malformed BibTeX entry boundaries or citation key"
        case .noBibliographicEntry: return "No bibliographic entry in provider BibTeX"
        case .multipleBibliographicEntries: return "Multiple bibliographic entries in provider BibTeX"
        case .invalidCitekey: return "Invalid application citation key"
        }
    }
}

/// Locates entry keys without round-tripping field values. The citation graph's
/// tolerant BibtexParser cannot provide source ranges or reject truncated blocks.
/// This scanner validates block boundaries, not the complete BibTeX field grammar.
nonisolated enum BibTeXEntryKeyEditor {
    static func replacingSingleEntryKey(in contents: String, with citekey: String) throws -> String {
        guard !citekey.isEmpty, citekey.allSatisfy(isKeyCharacter) else { throw BibTeXEntryKeyError.invalidCitekey }
        let scanner = Scanner(contents)
        let ranges = try scanner.keyRanges()
        guard let range = ranges.first else { throw BibTeXEntryKeyError.noBibliographicEntry }
        guard ranges.count == 1 else { throw BibTeXEntryKeyError.multipleBibliographicEntries }
        return contents.replacingCharacters(in: range, with: citekey)
    }

    static func entryKeys(in contents: String) throws -> [String] {
        try Scanner(contents).keyRanges().map { String(contents[$0]) }
    }

    private static func isKeyCharacter(_ character: Character) -> Bool {
        !character.isWhitespace && !"{}(),=\"#%\\@".contains(character)
    }

    private struct Scanner {
        let characters: [Character]
        let positions: [String.Index]

        init(_ contents: String) {
            characters = Array(contents)
            positions = Array(contents.indices) + [contents.endIndex]
        }

        func keyRanges() throws -> [Range<String.Index>] {
            var ranges: [Range<String.Index>] = []
            var cursor = 0
            while cursor < characters.count {
                if characters[cursor] == "%" {
                    skipComment(&cursor)
                    continue
                }
                guard characters[cursor] == "@" else {
                    cursor += 1
                    continue
                }
                cursor += 1
                let typeStart = cursor
                while cursor < characters.count, characters[cursor].isLetter { cursor += 1 }
                guard cursor > typeStart else { throw BibTeXEntryKeyError.malformedEntry }
                let type = String(characters[typeStart..<cursor]).lowercased()
                skipTrivia(&cursor)
                guard cursor < characters.count, characters[cursor] == "{" || characters[cursor] == "(" else {
                    throw BibTeXEntryKeyError.malformedEntry
                }
                let end = try blockEnd(openingAt: cursor, isComment: type == "comment")
                if !["comment", "string", "preamble"].contains(type) {
                    cursor += 1
                    skipTrivia(&cursor)
                    let keyStart = cursor
                    while cursor < end, BibTeXEntryKeyEditor.isKeyCharacter(characters[cursor]) { cursor += 1 }
                    let keyEnd = cursor
                    skipTrivia(&cursor)
                    guard keyEnd > keyStart, cursor < end, characters[cursor] == "," else {
                        throw BibTeXEntryKeyError.malformedEntry
                    }
                    ranges.append(positions[keyStart]..<positions[keyEnd])
                }
                cursor = end
            }
            return ranges
        }

        private func blockEnd(openingAt start: Int, isComment: Bool) throws -> Int {
            let braced = characters[start] == "{"
            let outerBraceDepth = braced ? 1 : 0
            var braceDepth = outerBraceDepth
            var parenthesisDepth = braced ? 0 : 1
            var quoted = false
            var cursor = start + 1
            while cursor < characters.count {
                let character = characters[cursor]
                if character == "\\" {
                    cursor += 2
                    continue
                }
                if quoted {
                    if character == "\"" { quoted = false }
                } else if character == "\"", braceDepth == outerBraceDepth, !isComment {
                    quoted = true
                } else if character == "%", braceDepth == outerBraceDepth, !isComment {
                    skipComment(&cursor)
                    continue
                } else if character == "{" {
                    braceDepth += 1
                } else if character == "}" {
                    braceDepth -= 1
                    if braceDepth < 0 { throw BibTeXEntryKeyError.malformedEntry }
                    if braced, braceDepth == 0 { return cursor + 1 }
                } else if !braced, braceDepth == 0 {
                    if character == "(" { parenthesisDepth += 1 }
                    if character == ")" { parenthesisDepth -= 1 }
                    if parenthesisDepth == 0 { return cursor + 1 }
                }
                cursor += 1
            }
            throw BibTeXEntryKeyError.malformedEntry
        }

        private func skipTrivia(_ cursor: inout Int) {
            while cursor < characters.count {
                if characters[cursor].isWhitespace {
                    cursor += 1
                } else if characters[cursor] == "%" {
                    skipComment(&cursor)
                } else {
                    break
                }
            }
        }

        private func skipComment(_ cursor: inout Int) {
            while cursor < characters.count, !characters[cursor].isNewline { cursor += 1 }
        }

    }
}
