import Foundation

public nonisolated enum AgentAnswerQualityIssueCode: String, Codable, Sendable {
    case missingDirectAnswer = "missing_direct_answer"
    case missingEvidence = "missing_evidence"
    case missingSource = "missing_source"
    case missingDisplayMath = "missing_display_math"
    case missingContentExplanation = "missing_content_explanation"
}

public nonisolated struct AgentAnswerQualityIssue: Codable, Hashable, Sendable {
    public var code: AgentAnswerQualityIssueCode
    public var message: String

    public nonisolated init(code: AgentAnswerQualityIssueCode, message: String) {
        self.code = code
        self.message = message
    }
}

public nonisolated struct AgentAnswerQualityReport: Codable, Hashable, Sendable {
    public var issues: [AgentAnswerQualityIssue]

    public nonisolated init(issues: [AgentAnswerQualityIssue]) {
        self.issues = issues
    }

    public nonisolated var passes: Bool {
        issues.isEmpty
    }
}

public nonisolated struct AgentAnswerQualityEvaluator: Sendable {
    public nonisolated init() {}

    public nonisolated func evaluate(goal: String, finalMarkdown: String, toolResults: [AgentToolResult]) -> AgentAnswerQualityReport {
        let intent = AgentPaperIntentRouter().classify(goal)
        let trimmed = finalMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        var issues: [AgentAnswerQualityIssue] = []

        if !hasDirectAnswer(trimmed) {
            issues.append(AgentAnswerQualityIssue(code: .missingDirectAnswer, message: "Final answer is empty or only describes tool execution."))
        }

        let hasEvidence = hasPaperEvidence(toolResults)
        if intent.requiresPaperEvidence, !hasEvidence {
            issues.append(AgentAnswerQualityIssue(code: .missingEvidence, message: "Paper body question has no read/search tool evidence."))
            if !hasMissingContentExplanation(trimmed) {
                issues.append(AgentAnswerQualityIssue(code: .missingContentExplanation, message: "Missing evidence answer should explain that paper body or formula was not read."))
            }
        }

        if intent.kind == .formula {
            if !trimmed.contains("$$") {
                issues.append(AgentAnswerQualityIssue(code: .missingDisplayMath, message: "Formula answers should include display math."))
            }
        }
        if intent.requiresPaperEvidence, hasEvidence, !containsSourceReference(trimmed, toolResults: toolResults) {
            issues.append(AgentAnswerQualityIssue(code: .missingSource, message: "Paper answer or writeback draft should reference the successful paper evidence read."))
        }

        return AgentAnswerQualityReport(issues: issues)
    }

    public nonisolated func missingEvidenceMarkdown(goal: String, toolResults: [AgentToolResult]) -> String {
        let wantsChinese = goal.range(of: #"\p{Han}"#, options: .regularExpression) != nil
        let usedTools = toolResults.map(\.toolName).joined(separator: ", ").nilIfEmpty ?? "none"
        if wantsChinese {
            return """
            我没有读取到足够的论文正文或公式证据，因此不能可靠回答这个问题。

            已使用工具：\(usedTools)

            请先确认目标论文已有 `paper.md`，或选择具体论文后重试。公式类问题需要先通过 `search_papers` / `read_paper_section` 读取到包含公式的章节。
            """
        }
        return """
        I did not read enough paper-body or formula evidence to answer reliably.

        Tools used: \(usedTools)

        Make sure the target paper has `paper.md`, or select a specific paper and retry. Formula questions need a `search_papers` / `read_paper_section` result containing the equation.
        """
    }

    public nonisolated func writebackWarningMarkdown(goal: String, body: String, toolResults: [AgentToolResult]) -> String? {
        let report = evaluate(goal: goal, finalMarkdown: body, toolResults: toolResults)
        if report.issues.contains(where: { $0.code == .missingEvidence }) {
            return missingEvidenceMarkdown(goal: goal, toolResults: toolResults)
        }
        guard report.issues.contains(where: { $0.code == .missingSource }) else { return nil }
        if goal.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
            return "这份笔记草稿没有引用已读取的论文证据，因此尚未提交写回批准。请补充真实来源路径、章节或行号，并核对每项结论。引用定位只能帮助核查，不能自动证明科学结论得到支持。"
        }
        return "This note draft does not reference the paper evidence read, so it was not offered for writeback approval. Add the source path, section or line location and review each conclusion. A source reference helps verification; it does not establish scientific support automatically."
    }

    private nonisolated func hasDirectAnswer(_ finalMarkdown: String) -> Bool {
        guard finalMarkdown.count >= 12 else {
            return false
        }
        let lowercased = finalMarkdown.lowercased()
        if lowercased.contains("tools used") && lowercased.contains("last tool result") {
            return false
        }
        if lowercased.contains("已使用工具") && lowercased.contains("最后一个工具结果") {
            return false
        }
        return true
    }

    private nonisolated func hasPaperEvidence(_ toolResults: [AgentToolResult]) -> Bool {
        toolResults.contains { result in
            guard result.succeeded else {
                return false
            }
            if let object = result.payload?.objectValue {
                let kind = object["kind"]?.stringValue
                if kind == "paper_search" || result.toolName == "search_papers" {
                    return object["matches"]?.arrayValue?.contains { match in
                        guard let fields = match.objectValue else { return false }
                        return hasText(fields["snippet"]?.stringValue) && hasText(fields["source"]?.stringValue)
                    } == true
                }
                if ["paper_read", "paper_section"].contains(kind)
                    || ["read_paper", "read_paper_section"].contains(result.toolName) {
                    return hasText(object["content"]?.stringValue) && hasText(object["source"]?.stringValue)
                }
                return false
            }
            // Older tools used a source header followed by a blank line and the body.
            // A successful read/search status alone does not establish paper evidence.
            guard ["read_paper", "read_paper_section"].contains(result.toolName),
                  result.message.contains("source:"),
                  let separator = result.message.range(of: "\n\n") else { return false }
            return hasText(String(result.message[separator.upperBound...]))
        }
    }

    private nonisolated func hasText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private nonisolated func containsSourceReference(_ finalMarkdown: String, toolResults: [AgentToolResult]) -> Bool {
        let sourceTokens = Set(toolResults.filter { hasPaperEvidence([$0]) }.flatMap(sourceTokens(in:)))
        guard !sourceTokens.isEmpty else {
            return finalMarkdown.contains("paper_id") || finalMarkdown.contains("source") || finalMarkdown.contains("来源")
        }
        return sourceTokens.contains { token in
            token.count >= 3 && finalMarkdown.localizedCaseInsensitiveContains(token)
        }
    }

    private nonisolated func sourceTokens(in result: AgentToolResult) -> [String] {
        var tokens: [String] = []
        if let object = result.payload?.objectValue {
            collectSourceTokens(from: object, into: &tokens)
        }
        for pattern in [#"paper_id:\s*([^\s]+)"#, #"source:\s*([^\s]+)"#] {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(result.message.startIndex..<result.message.endIndex, in: result.message)
            for match in expression.matches(in: result.message, range: range) where match.numberOfRanges > 1 {
                if let valueRange = Range(match.range(at: 1), in: result.message) {
                    tokens.append(String(result.message[valueRange]))
                }
            }
        }
        return tokens
    }

    private nonisolated func collectSourceTokens(from object: [String: JSONValue], into tokens: inout [String]) {
        for key in ["paper_id", "title", "source", "path", "raw_markdown_path"] {
            if let value = object[key]?.stringValue?.nilIfEmpty {
                tokens.append(value)
            }
        }
        if let paper = object["paper"]?.objectValue {
            collectSourceTokens(from: paper, into: &tokens)
        }
        if let matches = object["matches"]?.arrayValue {
            for match in matches {
                if let matchObject = match.objectValue {
                    collectSourceTokens(from: matchObject, into: &tokens)
                }
            }
        }
    }

    private nonisolated func hasMissingContentExplanation(_ finalMarkdown: String) -> Bool {
        let lowercased = finalMarkdown.lowercased()
        return lowercased.contains("没有读取")
            || lowercased.contains("未读取")
            || lowercased.contains("paper.md")
            || lowercased.contains("not read")
            || lowercased.contains("missing")
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}