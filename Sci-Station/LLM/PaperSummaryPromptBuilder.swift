import Foundation

public struct PaperSummaryPromptBuilder {
    public nonisolated init() {}

    public nonisolated func buildPrompt(
        for paper: Paper,
        rawMarkdown: String,
        annotations: String,
        existingWiki: String?,
        workspaceProfile: AgentWorkspaceProfile = AgentWorkspaceProfile()
    ) -> String {
        let basePrompt = """
        你是 Sci-Station 中的科研论文阅读助手。请把输入内容整理为可直接写入 wiki/papers 的 Markdown 学术笔记。

        要求：
        - 不要编造论文中没有出现的信息。
        - 如果证据不足，请明确写“未在当前材料中找到”。
        - 保留重要公式、实验设置、数据集、假设和限制。
        - 输出只使用 Markdown 正文，不要包裹代码块。

        Paper metadata:
        - Title: \(paper.title)
        - Authors: \(paper.authors.joined(separator: ", "))
        - Year: \(paper.year.map(String.init) ?? "Unknown")
        - Venue: \(paper.venue ?? "Unknown")
        - DOI: \(paper.doi ?? "Unknown")
        - arXiv: \(paper.arxiv ?? "Unknown")
        - URL: \(paper.url ?? "Unknown")
        - Tags: \(paper.tags.joined(separator: ", "))
        - Abstract: \(paper.abstract ?? "")

        Raw markdown and extracted paper text:
        \(rawMarkdown)

        Annotations:
        \(annotations)

        Existing wiki content:
        \(existingWiki ?? "")

        请输出以下段落：
        ## TL;DR
        ## 研究问题
        ## 方法概述
        ## 关键贡献
        ## 实验与证据
        ## 局限性
        ## 与已有工作的关系
        ## 可复现性检查
        ## 对我研究的启发
        ## 可能研究空白
        """
        let structuredPrompt = """
        Paper metadata:
        - Title: \(paper.title)
        - Authors: \(paper.authors.joined(separator: ", "))
        - Year: \(paper.year.map(String.init) ?? "Unknown")
        - Venue: \(paper.venue ?? "Unknown")
        - DOI: \(paper.doi ?? "Unknown")
        - arXiv: \(paper.arxiv ?? "Unknown")
        - URL: \(paper.url ?? "Unknown")
        - Tags: \(paper.tags.joined(separator: ", "))
        - Abstract: \(paper.abstract ?? "")

        Raw markdown and extracted paper text:
        \(rawMarkdown)

        Annotations:
        \(annotations)

        Existing wiki content:
        \(existingWiki ?? "")

        \(basePrompt)
        """

        return AgentPromptLibraryResolver().resolve(
            surface: .paperSummary,
            profile: workspaceProfile,
            basePrompt: structuredPrompt
        ).promptText
    }
}
