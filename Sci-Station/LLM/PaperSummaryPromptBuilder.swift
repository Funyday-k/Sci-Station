import Foundation

public struct PaperSummaryPromptBuilder {
    public nonisolated init() {}

    public nonisolated func buildPrompt(
        for paper: Paper,
        rawMarkdown: String,
        annotations: String,
        existingWiki: String?
    ) -> String {
        """
        You are helping summarize a research paper into concise academic notes.

        Paper metadata:
        - Title: \(paper.title)
        - Authors: \(paper.authors.joined(separator: ", "))
        - Year: \(paper.year.map(String.init) ?? "Unknown")
        - Venue: \(paper.venue ?? "Unknown")
        - Abstract: \(paper.abstract ?? "")

        Raw markdown:
        \(rawMarkdown)

        Annotations:
        \(annotations)

        Existing wiki content:
        \(existingWiki ?? "")

        Produce Markdown with these sections:
        ## TL;DR
        ## Research Question
        ## Method
        ## Key Findings
        ## Limitations
        ## Notes for My Research
        """
    }
}