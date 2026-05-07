import Foundation

public nonisolated enum PaperMarkdownQualitySeverity: String, Codable, Hashable, Sendable {
    case info
    case warning
    case error
}

public nonisolated enum PaperMarkdownQualityStatus: String, Codable, Hashable, Sendable {
    case ready
    case warning
    case error
}

public nonisolated enum PaperMarkdownQualityIssueCode: String, Codable, Hashable, Sendable {
    case missingMarkdown = "missing_markdown"
    case emptyMarkdown = "empty_markdown"
    case unknownExtractionEngine = "unknown_extraction_engine"
    case pdfKitFallback = "pdfkit_fallback"
    case missingAbstractHeading = "missing_abstract_heading"
    case missingDisplayMath = "missing_display_math"
    case missingFigureAsset = "missing_figure_asset"
}

public nonisolated struct PaperMarkdownQualityIssue: Identifiable, Codable, Hashable, Sendable {
    public var code: PaperMarkdownQualityIssueCode
    public var severity: PaperMarkdownQualitySeverity
    public var titleChinese: String
    public var titleEnglish: String
    public var detailChinese: String
    public var detailEnglish: String

    public nonisolated var id: String {
        code.rawValue + ":" + detailEnglish
    }

    public nonisolated init(
        code: PaperMarkdownQualityIssueCode,
        severity: PaperMarkdownQualitySeverity,
        titleChinese: String,
        titleEnglish: String,
        detailChinese: String,
        detailEnglish: String
    ) {
        self.code = code
        self.severity = severity
        self.titleChinese = titleChinese
        self.titleEnglish = titleEnglish
        self.detailChinese = detailChinese
        self.detailEnglish = detailEnglish
    }

    public nonisolated func title(usesEnglishInterface: Bool) -> String {
        usesEnglishInterface ? titleEnglish : titleChinese
    }

    public nonisolated func detail(usesEnglishInterface: Bool) -> String {
        usesEnglishInterface ? detailEnglish : detailChinese
    }
}

public nonisolated struct PaperMarkdownQualityReport: Codable, Hashable, Sendable {
    public var paperID: String
    public var title: String
    public var markdownRelativePath: String
    public var exists: Bool
    public var isEmpty: Bool
    public var extractionEngine: String?
    public var fallbackReason: String?
    public var hasAbstractHeading: Bool
    public var hasFigureReferences: Bool
    public var hasDisplayMath: Bool
    public var figureAssetCount: Int
    public var missingFigureAssetReferences: [String]
    public var issues: [PaperMarkdownQualityIssue]

    public nonisolated init(
        paperID: String,
        title: String,
        markdownRelativePath: String,
        exists: Bool,
        isEmpty: Bool,
        extractionEngine: String? = nil,
        fallbackReason: String? = nil,
        hasAbstractHeading: Bool = false,
        hasFigureReferences: Bool = false,
        hasDisplayMath: Bool = false,
        figureAssetCount: Int = 0,
        missingFigureAssetReferences: [String] = [],
        issues: [PaperMarkdownQualityIssue] = []
    ) {
        self.paperID = paperID
        self.title = title
        self.markdownRelativePath = markdownRelativePath
        self.exists = exists
        self.isEmpty = isEmpty
        self.extractionEngine = extractionEngine
        self.fallbackReason = fallbackReason
        self.hasAbstractHeading = hasAbstractHeading
        self.hasFigureReferences = hasFigureReferences
        self.hasDisplayMath = hasDisplayMath
        self.figureAssetCount = figureAssetCount
        self.missingFigureAssetReferences = missingFigureAssetReferences
        self.issues = issues
    }

    public nonisolated var status: PaperMarkdownQualityStatus {
        if issues.contains(where: { $0.severity == .error }) {
            return .error
        }
        if issues.contains(where: { $0.severity == .warning }) {
            return .warning
        }
        return .ready
    }

    public nonisolated func summary(usesEnglishInterface: Bool) -> String {
        let statusText: String
        switch status {
        case .ready:
            statusText = usesEnglishInterface ? "Ready" : "可读取"
        case .warning:
            statusText = usesEnglishInterface ? "Warning" : "有警告"
        case .error:
            statusText = usesEnglishInterface ? "Error" : "有错误"
        }

        let engine = extractionEngine?.nilIfBlank ?? (usesEnglishInterface ? "unknown engine" : "未知引擎")
        let abstractText = hasAbstractHeading ? (usesEnglishInterface ? "abstract yes" : "摘要 yes") : (usesEnglishInterface ? "abstract no" : "摘要 no")
        let mathText = hasDisplayMath ? (usesEnglishInterface ? "display math yes" : "公式块 yes") : (usesEnglishInterface ? "display math no" : "公式块 no")
        return "\(statusText); engine=\(engine); \(abstractText); figures=\(figureAssetCount); \(mathText)"
    }

    public nonisolated func issueLines(usesEnglishInterface: Bool) -> [String] {
        issues.map { issue in
            let prefix: String
            switch issue.severity {
            case .info:
                prefix = usesEnglishInterface ? "Info" : "提示"
            case .warning:
                prefix = usesEnglishInterface ? "Warning" : "警告"
            case .error:
                prefix = usesEnglishInterface ? "Error" : "错误"
            }
            return "\(prefix): \(issue.title(usesEnglishInterface: usesEnglishInterface)) - \(issue.detail(usesEnglishInterface: usesEnglishInterface))"
        }
    }
}

public nonisolated struct PaperMarkdownQualityInspector {
    private let fileManager: FileManager

    public nonisolated init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func inspect(_ paper: Paper, in workspace: ResearchWorkspace) -> PaperMarkdownQualityReport {
        let markdownRelativePath = paper.paperDirectoryRelativePath + "/paper.md"
        let markdownURL = paper.rawMarkdownURL(in: workspace)
        guard fileManager.fileExists(atPath: markdownURL.path) else {
            return PaperMarkdownQualityReport(
                paperID: paper.id,
                title: paper.displayTitle,
                markdownRelativePath: markdownRelativePath,
                exists: false,
                isEmpty: true,
                issues: [
                    issue(
                        .missingMarkdown,
                        .error,
                        zh: "缺少 paper.md",
                        en: "Missing paper.md",
                        zhDetail: "请先用 MinerU / PDFKit 转换 PDF，或手动补充 paper.md 后再重建索引。",
                        enDetail: "Convert the PDF with MinerU / PDFKit, or add paper.md manually before rebuilding the index."
                    )
                ]
            )
        }

        let contents = (try? String(contentsOf: markdownURL, encoding: .utf8)) ?? ""
        let parsed = FrontmatterParser().parse(contents)
        let extractionEngine = parsed.frontmatter["extraction_engine"]?.stringValue?.nilIfBlank
        let fallbackReason = parsed.frontmatter["fallback_reason"]?.stringValue?.nilIfBlank
        let body = parsed.body
        let isEmpty = contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAbstractHeading = Self.hasAbstractHeading(in: body)
        let hasDisplayMath = Self.hasDisplayMath(in: body)
        let figureReferences = Self.localFigureReferences(in: body)
        let figureAssetCount = Self.figureAssetCount(in: markdownURL.deletingLastPathComponent(), fileManager: fileManager)
        let missingFigureReferences = figureReferences.filter { reference in
            let resolved = workspace.resolve(relativePath: reference, from: markdownURL.deletingLastPathComponent(), isDirectory: false)
            return !fileManager.fileExists(atPath: resolved.path)
        }

        var issues: [PaperMarkdownQualityIssue] = []
        if isEmpty {
            issues.append(issue(
                .emptyMarkdown,
                .error,
                zh: "paper.md 为空",
                en: "paper.md is empty",
                zhDetail: "空文件不能生成检索 chunks；请重新转换或补充正文。",
                enDetail: "An empty file cannot produce retrieval chunks; reconvert it or add body text."
            ))
        }
        if extractionEngine == nil {
            issues.append(issue(
                .unknownExtractionEngine,
                .warning,
                zh: "抽取引擎未知",
                en: "Unknown extraction engine",
                zhDetail: "frontmatter 中没有 extraction_engine，无法判断这是 MinerU、PDFKit fallback 还是手工 Markdown。",
                enDetail: "The frontmatter has no extraction_engine, so Sci-Station cannot tell whether this came from MinerU, PDFKit fallback, or manual Markdown."
            ))
        }
        if extractionEngine == "pdfkit_fallback" {
            issues.append(issue(
                .pdfKitFallback,
                .warning,
                zh: "PDFKit fallback 可读性有限",
                en: "PDFKit fallback has limited readability",
                zhDetail: "图片、扫描页、复杂公式、图表和表格可能不可读；建议配置 MinerU 或补充 annotations。\(fallbackReason.map { " 原因：\($0)" } ?? "")",
                enDetail: "Images, scanned pages, complex formulas, charts, and tables may be incomplete; configure MinerU or add annotations.\(fallbackReason.map { " Reason: \($0)" } ?? "")"
            ))
        }
        if !hasAbstractHeading {
            issues.append(issue(
                .missingAbstractHeading,
                .warning,
                zh: "未检测到 Abstract / 摘要标题",
                en: "No Abstract / 摘要 heading detected",
                zhDetail: "摘要问题会回退到第一页正文；如有摘要，请补充 `## Abstract` 或 `## 摘要`。",
                enDetail: "Abstract questions will fall back to page 1; add `## Abstract` or `## 摘要` when an abstract exists."
            ))
        }
        if !hasDisplayMath {
            issues.append(issue(
                .missingDisplayMath,
                .info,
                zh: "未检测到 display math",
                en: "No display math detected",
                zhDetail: "如果论文包含关键公式，请检查 PDF 转换结果或在 annotations 中补充公式。",
                enDetail: "If the paper has important formulas, check the PDF conversion output or add formulas in annotations."
            ))
        }
        if !missingFigureReferences.isEmpty {
            issues.append(issue(
                .missingFigureAsset,
                .warning,
                zh: "存在缺失的图片资源",
                en: "Missing figure assets",
                zhDetail: missingFigureReferences.joined(separator: ", "),
                enDetail: missingFigureReferences.joined(separator: ", ")
            ))
        }

        return PaperMarkdownQualityReport(
            paperID: paper.id,
            title: paper.displayTitle,
            markdownRelativePath: markdownRelativePath,
            exists: true,
            isEmpty: isEmpty,
            extractionEngine: extractionEngine,
            fallbackReason: fallbackReason,
            hasAbstractHeading: hasAbstractHeading,
            hasFigureReferences: !figureReferences.isEmpty,
            hasDisplayMath: hasDisplayMath,
            figureAssetCount: figureAssetCount,
            missingFigureAssetReferences: missingFigureReferences,
            issues: issues
        )
    }

    private nonisolated static func hasAbstractHeading(in markdown: String) -> Bool {
        markdown.components(separatedBy: .newlines).contains { line in
            guard let title = markdownHeadingTitle(in: line) else {
                return false
            }
            let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return normalized == "abstract" || normalized == "摘要"
        }
    }

    private nonisolated static func hasDisplayMath(in markdown: String) -> Bool {
        markdown.contains("$$")
            || markdown.contains("\\[")
            || markdown.range(of: #"\\begin\{(equation|align|gather|multline)\*?\}"#, options: .regularExpression) != nil
    }

    private nonisolated static func localFigureReferences(in markdown: String) -> [String] {
        let patterns = [
            #"!\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)"#,
            #"<img\s+[^>]*src=[\"']([^\"']+)[\"']"#
        ]
        var references: [String] = []
        let searchRange = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            for match in expression.matches(in: markdown, range: searchRange) where match.numberOfRanges > 1 {
                guard let range = Range(match.range(at: 1), in: markdown) else {
                    continue
                }
                let reference = String(markdown[range]).removingPercentEncoding ?? String(markdown[range])
                if isLocalFigureReference(reference) {
                    references.append(reference)
                }
            }
        }
        return Array(Set(references)).sorted()
    }

    private nonisolated static func isLocalFigureReference(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        guard !lowercased.hasPrefix("http://"),
              !lowercased.hasPrefix("https://"),
              !lowercased.hasPrefix("data:"),
              !value.hasPrefix("/") else {
            return false
        }
        return lowercased.hasPrefix("figures/")
            || lowercased.hasPrefix("images/")
            || ["png", "jpg", "jpeg", "webp", "gif", "svg"].contains(URL(fileURLWithPath: lowercased).pathExtension)
    }

    private nonisolated static func figureAssetCount(in paperDirectoryURL: URL, fileManager: FileManager) -> Int {
        let figuresURL = paperDirectoryURL.appendingPathComponent("figures", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: figuresURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var count = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                count += 1
            }
        }
        return count
    }

    private nonisolated static func markdownHeadingTitle(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else {
            return nil
        }
        let level = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else {
            return nil
        }
        let title = trimmed.dropFirst(level).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : String(title)
    }

    private nonisolated func issue(
        _ code: PaperMarkdownQualityIssueCode,
        _ severity: PaperMarkdownQualitySeverity,
        zh: String,
        en: String,
        zhDetail: String,
        enDetail: String
    ) -> PaperMarkdownQualityIssue {
        PaperMarkdownQualityIssue(
            code: code,
            severity: severity,
            titleChinese: zh,
            titleEnglish: en,
            detailChinese: zhDetail,
            detailEnglish: enDetail
        )
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}