import Foundation

public nonisolated enum AgentPaperIntentKind: String, Codable, Sendable {
    case none
    case paperListing = "paper_listing"
    case paperBodyQA = "paper_body_qa"
    case formula = "formula"
    case sectionSummary = "section_summary"
    case citationLookup = "citation_lookup"
    case writeback = "writeback"
    case continuation
}

public nonisolated struct AgentPaperIntent: Codable, Hashable, Sendable {
    public var kind: AgentPaperIntentKind
    public var ordinalIndex: Int?
    public var query: String?
    public var sectionHint: String?

    public nonisolated init(
        kind: AgentPaperIntentKind = .none,
        ordinalIndex: Int? = nil,
        query: String? = nil,
        sectionHint: String? = nil
    ) {
        self.kind = kind
        self.ordinalIndex = ordinalIndex
        self.query = query
        self.sectionHint = sectionHint
    }

    public nonisolated var requiresPaperEvidence: Bool {
        switch kind {
        case .paperBodyQA, .formula, .sectionSummary, .citationLookup, .writeback:
            return true
        case .paperListing, .continuation, .none:
            return false
        }
    }
}

public nonisolated struct AgentPaperIntentRouter: Sendable {
    public nonisolated init() {}

    public nonisolated func classify(_ goal: String) -> AgentPaperIntent {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AgentPaperIntent()
        }
        let lowercased = trimmed.lowercased()
        let ordinalIndex = Self.ordinalIndex(in: lowercased)
        let mentionsPaper = containsAny(lowercased, ["paper", "papers", "论文", "文章", "文献"])
        let mentionsFormula = containsAny(lowercased, ["formula", "equation", "公式", "方程", "蒸发率", "evaporation rate"])
        let mentionsAbstract = containsAny(lowercased, ["abstract", "摘要"])
        let mentionsBodyQA = mentionsFormula || mentionsAbstract || containsAny(lowercased, ["method", "methods", "claim", "claims", "section", "正文", "方法", "结论", "章节", "引用", "source", "citation", "来源"])
        let mentionsWrite = containsAny(lowercased, ["write", "save", "append", "写入", "写进", "写到", "放进", "保存", "生成 wiki", "写到 wiki", "todo", "artifact"])
        let mentionsListing = containsAny(lowercased, ["list", "show", "what papers", "列", "都有什么", "有哪些"])

        if isContinuation(lowercased) {
            return AgentPaperIntent(kind: .continuation, ordinalIndex: nil, query: nil, sectionHint: nil)
        }
        if mentionsWrite && mentionsPaper {
            return AgentPaperIntent(kind: .writeback, ordinalIndex: ordinalIndex, query: searchQuery(from: trimmed, formula: mentionsFormula), sectionHint: sectionHint(in: trimmed))
        }
        if mentionsFormula {
            return AgentPaperIntent(kind: .formula, ordinalIndex: ordinalIndex, query: searchQuery(from: trimmed, formula: true), sectionHint: sectionHint(in: trimmed))
        }
        if containsAny(lowercased, ["citation", "source", "引用", "来源"]) && mentionsPaper {
            return AgentPaperIntent(kind: .citationLookup, ordinalIndex: ordinalIndex, query: searchQuery(from: trimmed, formula: false), sectionHint: sectionHint(in: trimmed))
        }
        if (mentionsAbstract || containsAny(lowercased, ["section", "章节", "summary", "summarize", "总结", "概括"])) && mentionsPaper {
            return AgentPaperIntent(kind: .sectionSummary, ordinalIndex: ordinalIndex, query: searchQuery(from: trimmed, formula: false), sectionHint: sectionHint(in: trimmed))
        }
        if mentionsBodyQA && mentionsPaper {
            return AgentPaperIntent(kind: .paperBodyQA, ordinalIndex: ordinalIndex, query: searchQuery(from: trimmed, formula: false), sectionHint: sectionHint(in: trimmed))
        }
        if mentionsListing && mentionsPaper {
            return AgentPaperIntent(kind: .paperListing, ordinalIndex: ordinalIndex, query: nil, sectionHint: nil)
        }
        return AgentPaperIntent()
    }

    public nonisolated func shouldPreflight(_ intent: AgentPaperIntent, availableToolNames: Set<String>) -> Bool {
        guard intent.kind != .none else {
            return false
        }
        if intent.kind == .continuation {
            return false
        }
        if intent.kind == .paperListing {
            return availableToolNames.contains("list_papers")
        }
        return availableToolNames.contains("list_papers") || availableToolNames.contains("search_papers") || availableToolNames.contains("read_paper") || availableToolNames.contains("read_paper_section")
    }

    public nonisolated func searchArgumentsJSON(for intent: AgentPaperIntent, paperID: String?) -> String {
        var fields: [String: JSONValue] = [
            "query": .string(intent.query?.nilIfEmpty ?? defaultQuery(for: intent)),
            "limit": .number("8"),
            "context_lines": .number("2")
        ]
        if let paperID = paperID?.nilIfEmpty {
            fields["paper_ids"] = .array([.string(paperID)])
        }
        return JSONValue.object(fields).canonicalJSON
    }

    public nonisolated func defaultQuery(for intent: AgentPaperIntent) -> String {
        switch intent.kind {
        case .formula:
            return "formula equation evaporation rate"
        case .sectionSummary:
            return intent.sectionHint?.nilIfEmpty ?? "summary section method result"
        case .citationLookup:
            return "citation source quote"
        case .writeback, .paperBodyQA:
            return intent.query?.nilIfEmpty ?? "method result conclusion"
        case .paperListing, .continuation, .none:
            return intent.query?.nilIfEmpty ?? "paper"
        }
    }

    private nonisolated func searchQuery(from goal: String, formula: Bool) -> String {
        let compact = removingOrdinalReferences(from: goal)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if formula, compact.range(of: "蒸发率", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return "蒸发率 evaporation rate formula equation"
        }
        if formula, compact.range(of: "evaporation", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return "evaporation rate formula equation"
        }
        if compact.range(of: "abstract", options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || compact.range(of: "摘要", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return "Abstract 摘要 summary"
        }
        return compact.nilIfEmpty ?? (formula ? "formula equation" : goal)
    }

    private nonisolated func removingOrdinalReferences(from goal: String) -> String {
        let patterns = [
            #"第\s*([一二三四五六七八九十]|[1-9]|10)\s*(篇|个|份)\s*(文章|论文|文献)?"#,
            #"\b(the\s+)?(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|1st|2nd|3rd|4th|5th|6th|7th|8th|9th|10th)\s+(paper|papers|article|articles|document|documents)\b"#
        ]
        return patterns.reduce(goal) { partial, pattern in
            partial.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private nonisolated func sectionHint(in goal: String) -> String? {
        if goal.range(of: "abstract", options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || goal.range(of: "摘要", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return "Abstract"
        }
        let patterns = [
            #"section\s+([A-Za-z0-9 .:_-]{2,80})"#,
            #"章节\s*([\p{Han}A-Za-z0-9 .:_-]{2,80})"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(goal.startIndex..<goal.endIndex, in: goal)
            guard let match = expression.firstMatch(in: goal, range: range), match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: goal) else {
                continue
            }
            return String(goal[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        return nil
    }

    private nonisolated func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0.lowercased()) }
    }

    private nonisolated func isContinuation(_ lowercased: String) -> Bool {
        let compact = lowercased
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return [
            "继续",
            "接着",
            "继续说",
            "继续写",
            "go on",
            "continue",
            "keep going"
        ].contains { compact == $0 || compact.hasPrefix($0 + " ") }
    }

    private nonisolated static func ordinalIndex(in lowercased: String) -> Int? {
        let chineseOrdinalPattern = #"第\s*([一二三四五六七八九十]|[1-9]|10)\s*(篇|个|份)"#
        if let expression = try? NSRegularExpression(pattern: chineseOrdinalPattern, options: [.caseInsensitive]) {
            let range = NSRange(lowercased.startIndex..<lowercased.endIndex, in: lowercased)
            if let match = expression.firstMatch(in: lowercased, range: range), match.numberOfRanges > 1,
               let valueRange = Range(match.range(at: 1), in: lowercased),
               let index = ordinalTokenIndex(String(lowercased[valueRange])) {
                return index
            }
        }

        let englishOrdinalPattern = #"\b(the\s+)?(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|1st|2nd|3rd|4th|5th|6th|7th|8th|9th|10th)\s+(paper|papers|article|articles|document|documents)\b"#
        if let expression = try? NSRegularExpression(pattern: englishOrdinalPattern, options: [.caseInsensitive]) {
            let range = NSRange(lowercased.startIndex..<lowercased.endIndex, in: lowercased)
            if let match = expression.firstMatch(in: lowercased, range: range), match.numberOfRanges > 2,
               let valueRange = Range(match.range(at: 2), in: lowercased),
               let index = ordinalTokenIndex(String(lowercased[valueRange])) {
                return index
            }
        }
        return nil
    }

    private nonisolated static func ordinalTokenIndex(_ token: String) -> Int? {
        switch token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "一", "1", "first", "1st":
            return 0
        case "二", "2", "second", "2nd":
            return 1
        case "三", "3", "third", "3rd":
            return 2
        case "四", "4", "fourth", "4th":
            return 3
        case "五", "5", "fifth", "5th":
            return 4
        case "六", "6", "sixth", "6th":
            return 5
        case "七", "7", "seventh", "7th":
            return 6
        case "八", "8", "eighth", "8th":
            return 7
        case "九", "9", "ninth", "9th":
            return 8
        case "十", "10", "tenth", "10th":
            return 9
        default:
            return nil
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}