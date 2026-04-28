import AppKit
import SwiftUI

struct ProjectOverviewView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    private let projectOverviewPath = "wiki/projects/project_overview.md"
    private let corePapersPath = "wiki/projects/core_papers.md"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ProjectMetricCard(title: "Papers", value: "\(appModel.papers.count)", systemImage: "books.vertical")
                    ProjectMetricCard(title: "Core", value: "\(corePapers.count)", systemImage: "star")
                    ProjectMetricCard(title: "Project Docs", value: "\(projectDocuments.count)", systemImage: "doc.text")
                    ProjectMetricCard(title: "Open Tasks", value: "\(openTodosCount)", systemImage: "checklist")
                }

                projectBriefSection

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16)], alignment: .leading, spacing: 16) {
                    corePapersSection
                    projectDocumentsSection
                }

                workflowSection
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project Overview")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Research all-in-one workspace for proposal, literature, data, code, figures, outputs, and tasks.")
                .foregroundStyle(.secondary)
        }
    }

    private var projectBriefSection: some View {
        GroupBox("Project Brief") {
            VStack(alignment: .leading, spacing: 12) {
                if let document = projectOverviewDocument {
                    Text(excerpt(from: document.body, fallback: document.title, limit: 720))
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No project overview document has been loaded yet.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button {
                        appModel.openMarkdownDocument(relativePath: projectOverviewPath)
                    } label: {
                        Label("Open Project Brief", systemImage: "doc.text")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        appModel.openMarkdownDocument(relativePath: corePapersPath)
                    } label: {
                        Label("Open Core Papers Doc", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var corePapersSection: some View {
        GroupBox("Core Papers") {
            VStack(alignment: .leading, spacing: 12) {
                if corePapers.isEmpty {
                    Text("No papers imported yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(corePapers) { paper in
                        ProjectPaperSummaryRow(paper: paper, workspace: workspace)
                        if paper.id != corePapers.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var projectDocumentsSection: some View {
        GroupBox("Project Documents") {
            VStack(alignment: .leading, spacing: 10) {
                if projectDocuments.isEmpty {
                    Text("No project documents yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projectDocuments) { document in
                        Button {
                            appModel.openMarkdownDocument(relativePath: document.relativePath)
                        } label: {
                            Label(document.title, systemImage: document.relativePath == projectOverviewPath ? "doc.text" : "doc.plaintext")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var workflowSection: some View {
        GroupBox("Research Workflow") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                ProjectWorkflowTile(title: "Proposal", detail: "wiki/projects", systemImage: "doc.text") {
                    appModel.openMarkdownDocument(relativePath: projectOverviewPath)
                }
                ProjectWorkflowTile(title: "Core Papers", detail: "raw/papers + refs", systemImage: "books.vertical") {
                    appModel.selectSection(.library)
                }
                ProjectWorkflowTile(title: "Data", detail: "data + wiki/datasets", systemImage: "externaldrive") {
                    openFolder(workspace.dataURL)
                }
                ProjectWorkflowTile(title: "Code Reading", detail: "code", systemImage: "chevron.left.forwardslash.chevron.right") {
                    openFolder(workspace.codeURL)
                }
                ProjectWorkflowTile(title: "Figures", detail: "figures", systemImage: "photo.on.rectangle") {
                    openFolder(workspace.figuresURL)
                }
                ProjectWorkflowTile(title: "Outputs", detail: "outputs", systemImage: "doc.richtext") {
                    openFolder(workspace.outputsURL)
                }
                ProjectWorkflowTile(title: "Tasks", detail: "tasks/todos.yaml", systemImage: "checklist") {
                    appModel.selectSection(.tasks)
                }
                ProjectWorkflowTile(title: "Shared Context", detail: "shared_research.md", systemImage: "square.stack.3d.up") {
                    NSWorkspace.shared.open(workspace.sharedResearchURL)
                }
            }
        }
    }

    private var projectOverviewDocument: MarkdownDocument? {
        appModel.markdownDocuments.first { $0.relativePath == projectOverviewPath }
    }

    private var projectDocuments: [MarkdownDocument] {
        appModel.markdownDocuments
            .filter { $0.relativePath.hasPrefix("wiki/projects/") }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var corePapers: [Paper] {
        let candidates = appModel.papers.filter(isCorePaper)
        let source = candidates.isEmpty ? appModel.papers : candidates
        return Array(source.sorted(by: corePaperSort).prefix(6))
    }

    private var openTodosCount: Int {
        appModel.todos.filter { $0.status != .done }.count
    }

    private func isCorePaper(_ paper: Paper) -> Bool {
        let markers = (paper.tags + paper.useFor).map { $0.lowercased() }
        return markers.contains { marker in
            marker.contains("core") || marker.contains("foundation") || marker.contains("key") || marker.contains("proposal") || marker.contains("核心")
        } || paper.priority == .urgent || paper.priority == .high || (paper.rating ?? 0) >= 4
    }

    private func corePaperSort(_ first: Paper, _ second: Paper) -> Bool {
        let firstScore = corePaperScore(first)
        let secondScore = corePaperScore(second)
        if firstScore == secondScore {
            return first.updatedAt > second.updatedAt
        }
        return firstScore > secondScore
    }

    private func corePaperScore(_ paper: Paper) -> Int {
        var score = 0
        if isCorePaper(paper) { score += 10 }
        if paper.tags.contains(where: { $0.localizedCaseInsensitiveContains("core") || $0.contains("核心") }) { score += 5 }
        if paper.priority == .urgent { score += 4 }
        if paper.priority == .high { score += 3 }
        score += paper.rating ?? 0
        return score
    }

    private func excerpt(from body: String, fallback: String, limit: Int) -> String {
        let cleaned = body
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = cleaned.isEmpty ? fallback : cleaned
        guard text.count > limit else {
            return text
        }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

private struct ProjectPaperSummaryRow: View {
    @EnvironmentObject private var appModel: AppViewModel

    let paper: Paper
    let workspace: ResearchWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(paper.displayTitle)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                Text(paper.authorsDisplay)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(summaryText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 10) {
                if !paper.tags.isEmpty {
                    TagChipGroupView(tags: paper.tags)
                }
                Spacer(minLength: 0)
                Button("Library") {
                    appModel.selectPaper(id: paper.id)
                    appModel.selectSection(.library)
                }
                .buttonStyle(.link)

                Button("Read") {
                    appModel.openPaperReader(paper)
                }
                .buttonStyle(.link)
                .disabled(!appModel.canOpenPDF(for: paper))
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryText: String {
        if let abstract = paper.abstract?.trimmingCharacters(in: .whitespacesAndNewlines), !abstract.isEmpty {
            return clipped(abstract, limit: 260)
        }
        let parts = [paper.publicationDisplay, paper.yearText, paper.doi, paper.arxiv]
            .compactMap { value -> String? in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value != "-" else {
                    return nil
                }
                return value
            }
        return parts.isEmpty ? "No summary saved yet." : parts.joined(separator: "  ·  ")
    }

    private func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

private struct ProjectMetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        GroupBox {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(title)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProjectWorkflowTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
