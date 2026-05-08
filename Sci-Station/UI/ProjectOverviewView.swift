import AppKit
import SwiftUI

struct ProjectOverviewView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let workspace: ResearchWorkspace

    private var projectOverviewPath: String {
        projectWikiPath("projects/project_overview.md")
    }

    private var corePapersPath: String {
        projectWikiPath("projects/core_papers.md")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                ProjectDashboardPanel(workspace: workspace)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ProjectMetricCard(title: "Papers", value: "\(projectPapers.count)", systemImage: "books.vertical")
                    ProjectMetricCard(title: "Core", value: "\(corePapers.count)", systemImage: "star")
                    ProjectMetricCard(title: "Project Docs", value: "\(projectDocuments.count)", systemImage: "doc.text")
                    ProjectMetricCard(title: "Open Tasks", value: "\(openTodosCount)", systemImage: "checklist")
                }

                projectBriefSection
                projectContentGrid
                aiKnowledgeSection

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
            Text(appModel.currentResearchProject?.name ?? "No Project Selected")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Research all-in-one workspace for proposal, literature, data, code, figures, outputs, and tasks.")
                .foregroundStyle(.secondary)
        }
    }

    private var projectBriefSection: some View {
        GroupBox("Project Brief") {
            VStack(alignment: .leading, spacing: 12) {
                if let document = projectOverviewDocument {
                    MarkdownPreviewView(markdown: document.rawContents, baseURL: document.fileURL.deletingLastPathComponent())
                        .frame(minHeight: 220, maxHeight: 340)
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

    private var projectContentGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 420), spacing: 16, alignment: .top),
                GridItem(.flexible(minimum: 300), spacing: 16, alignment: .top)
            ],
            alignment: .leading,
            spacing: 16
        ) {
            corePapersSection
            projectDocumentsSection
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
                ProjectWorkflowTile(title: "Core Papers", detail: "library/papers + refs", systemImage: "books.vertical") {
                    if let projectID = appModel.currentProjectID {
                        appModel.selectResearchProject(projectID, section: .library)
                    } else {
                        appModel.selectSection(.library)
                    }
                }
                ProjectWorkflowTile(title: "Data", detail: "data + wiki/datasets", systemImage: "externaldrive") {
                    appModel.selectSection(.materials)
                }
                ProjectWorkflowTile(title: "Code Reading", detail: "code", systemImage: "chevron.left.forwardslash.chevron.right") {
                    appModel.selectSection(.materials)
                }
                ProjectWorkflowTile(title: "Figures", detail: "figures", systemImage: "photo.on.rectangle") {
                    appModel.selectSection(.materials)
                }
                ProjectWorkflowTile(title: "Outputs", detail: "outputs", systemImage: "doc.richtext") {
                    appModel.selectSection(.materials)
                }
                ProjectWorkflowTile(title: "Tasks", detail: "tasks/todos.yaml", systemImage: "checklist") {
                    appModel.selectSection(.tasks)
                }
                ProjectWorkflowTile(title: "Shared Context", detail: "shared_research.md", systemImage: "square.stack.3d.up") {
                    NSWorkspace.shared.open(projectSharedResearchURL)
                }
            }
        }
    }

    private var aiKnowledgeSection: some View {
        GroupBox("AI Knowledge Workspace") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], alignment: .leading, spacing: 12) {
                ProjectWorkflowTile(title: "Paper Notes", detail: "wiki/papers", systemImage: "doc.richtext") {
                    appModel.selectSection(.wiki)
                }
                ProjectWorkflowTile(title: "Concepts", detail: "wiki/concepts", systemImage: "lightbulb") {
                    appModel.selectSection(.wiki)
                }
                ProjectWorkflowTile(title: "Methods", detail: "wiki/methods", systemImage: "square.stack.3d.up") {
                    appModel.selectSection(.wiki)
                }
                ProjectWorkflowTile(title: "Research Gaps", detail: "wiki/gaps", systemImage: "scope") {
                    appModel.selectSection(.wiki)
                }
                ProjectWorkflowTile(title: "AI Lab", detail: "prompts + summaries", systemImage: "brain") {
                    appModel.selectSection(.llmLab)
                }
            }
        }
    }

    private var projectOverviewDocument: MarkdownDocument? {
        appModel.markdownDocuments.first { $0.relativePath == projectOverviewPath }
    }

    private var projectDocuments: [MarkdownDocument] {
        appModel.markdownDocuments
            .filter { $0.relativePath.hasPrefix(projectWikiPath("projects/")) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var projectSharedResearchURL: URL {
        if let project = appModel.currentResearchProject {
            return workspace.fileURL(for: project.relativePath + "/shared_research.md")
        }

        return workspace.sharedResearchURL
    }

    private func projectWikiPath(_ suffix: String) -> String {
        if let project = appModel.currentResearchProject {
            return project.relativePath + "/wiki/" + suffix
        }

        return "wiki/" + suffix
    }

    private var corePapers: [Paper] {
        let candidates = projectPapers.filter(isCorePaper)
        return Array(candidates.sorted(by: corePaperSort).prefix(6))
    }

    private var projectPapers: [Paper] {
        guard let projectID = appModel.currentProjectID else {
            return []
        }

        return appModel.papers(for: projectID)
    }

    private var openTodosCount: Int {
        guard let projectID = appModel.currentProjectID else {
            return 0
        }

        return appModel.todos.filter { $0.projectIDs.contains(projectID) && $0.status != .done }.count
    }

    private func isCorePaper(_ paper: Paper) -> Bool {
        guard let projectID = appModel.currentProjectID else {
            return false
        }

        return paper.coreProjectIDs.contains(projectID)
    }

    private func corePaperSort(_ first: Paper, _ second: Paper) -> Bool {
        if let projectID = appModel.currentProjectID,
           appModel.projectPaperLinkSortPrecedes(first, second, projectID: projectID) {
            return true
        }
        if let projectID = appModel.currentProjectID,
           appModel.projectPaperLinkSortPrecedes(second, first, projectID: projectID) {
            return false
        }

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
        if paper.priority == .urgent { score += 4 }
        if paper.priority == .high { score += 3 }
        score += paper.rating ?? 0
        return score
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
                    if let projectID = appModel.currentProjectID {
                        appModel.selectResearchProject(projectID, section: .library)
                    } else {
                        appModel.selectSection(.library)
                    }
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
