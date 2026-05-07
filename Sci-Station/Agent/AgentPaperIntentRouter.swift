import Foundation

public nonisolated enum AgentPaperIntentKind: String, Codable, Sendable {
    case none
    case paperListing = "paper_listing"
    case paperBodyQA = "paper_body_qa"
    case formula = "formula"
    case sectionSummary = "section_summary"
    case citationLookup = "citation_lookup"
    case writeback = "writeback"
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
        case .paperListing, .none:
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
        let mentionsBodyQA = mentionsFormula || containsAny(lowercased, ["method", "methods", "claim", "claims", "section", "正文", "方法", "结论", "摘要", "章节", "引用", "source", "citation", "来源"])
        let mentionsWrite = containsAny(lowercased, ["write", "save", "append", "写入", "保存", "生成 wiki", "写到 wiki", "todo", "artifact"])
        let mentionsListing = containsAny(lowercased, ["list", "show", "what papers", "列", "都有什么", "有哪些"])

        if mentionsWrite && mentionsPaper {
            return AgentPaperIntent(kind: .writeback, ordinalIndex: ordinalIndex, query: searchQuery(from: trimmed, formula: mentionsFormula), sectionHint: sectionHint(in: trimmed))
        }
        if mentionsFormula {
            return AgentPaperIntent(kind: .formula, ordinalIndex: ordinalIndex, query: searchQuery(from: trimmed, formula: true), sectionHint: sectionHint(in: trimmed))
        }
        if containsAny(lowercased, ["citation", "source", "引用", "来源"]) && mentionsPaper {
            return AgentPaperIntent(kind: .citationLookup, ordinalIndex: ordinalIndex, query: searchQuery(from: trimmed, formula: false), sectionHint: sectionHint(in: trimmed))
        }
        if containsAny(lowercased, ["section", "章节", "summary", "summarize", "总结", "概括"]) && mentionsPaper {
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
        case .paperListing, .none:
            return intent.query?.nilIfEmpty ?? "paper"
        }
    }

    private nonisolated func searchQuery(from goal: String, formula: Bool) -> String {
        let compact = goal
            .replacingOccurrences(of: "第一篇", with: "")
            .replacingOccurrences(of: "第一个", with: "")
            .replacingOccurrences(of: "first paper", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if formula, compact.range(of: "蒸发率", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return "蒸发率 evaporation rate formula equation"
        }
        if formula, compact.range(of: "evaporation", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return "evaporation rate formula equation"
        }
        return compact.nilIfEmpty ?? (formula ? "formula equation" : goal)
    }

    private nonisolated func sectionHint(in goal: String) -> String? {
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

    private nonisolated static func ordinalIndex(in lowercased: String) -> Int? {
        if lowercased.contains("第一篇") || lowercased.contains("第一个") || lowercased.contains("first paper") || lowercased.contains("1st paper") {
            return 0
        }
        if lowercased.contains("第二篇") || lowercased.contains("第二个") || lowercased.contains("second paper") || lowercased.contains("2nd paper") {
            return 1
        }
        return nil
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}