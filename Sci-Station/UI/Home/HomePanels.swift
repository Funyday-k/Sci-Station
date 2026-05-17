import SwiftUI

struct TodayPanelView: View {
    let snapshot: HomeSnapshot
    @ObservedObject var appModel: AppViewModel

    private var data: TodayPanelData { snapshot.today }

    var body: some View {
        HomePanelSection(
            title: appModel.localized("Today", "Today"),
            subtitle: appModel.localized("今日待处理、阅读、deadline 与 AI 草稿。", "Todos, reading, deadlines, and AI drafts for today.")
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], alignment: .leading, spacing: 12) {
                HomeSignalCard(title: appModel.localized("到期待办", "Due Todos"), systemImage: "checklist", count: data.dueTodos.count) {
                    if !snapshot.moduleAvailability.tasksEnabled {
                        ModuleDisabledView(message: appModel.localized("Tasks 模块已关闭。", "Tasks module is disabled.")) {
                            appModel.openSettings(category: .modules)
                        }
                    } else if data.dueTodos.isEmpty {
                        HomeEmptyState(
                            message: appModel.localized("今天没有到期待办。", "No due todos for today."),
                            actionTitle: appModel.localized("创建待办", "Create Todo"),
                            systemImage: "plus"
                        ) {
                            recordAction("create_todo", targetID: "tasks")
                            appModel.selectGlobalTodos()
                        }
                    } else {
                        VStack(spacing: 7) {
                            ForEach(data.dueTodos) { todo in
                                HomeTodoRow(todo: todo) {
                                    recordAction("open_todo", targetID: todo.id)
                                    appModel.selectGlobalTodos()
                                }
                            }
                        }
                    }
                }

                HomeSignalCard(
                    title: appModel.localized("阅读队列", "Reading Queue"),
                    systemImage: "books.vertical",
                    count: data.readingQueueEntries.isEmpty ? data.readingQueue.count : data.readingQueueEntries.count
                ) {
                    if !snapshot.moduleAvailability.libraryEnabled {
                        ModuleDisabledView(message: appModel.localized("Library 模块已关闭。", "Library module is disabled.")) {
                            appModel.openSettings(category: .modules)
                        }
                    } else if !data.readingQueueEntries.isEmpty {
                        VStack(spacing: 7) {
                            ForEach(data.readingQueueEntries.prefix(5)) { entry in
                                HomeQueueEntryRow(entry: entry) {
                                    recordAction("open_queue_entry", targetID: entry.id)
                                    if let paperID = entry.paperID {
                                        appModel.selectPaper(id: paperID)
                                        appModel.selectSection(.library)
                                    } else {
                                        appModel.selectSection(.library)
                                    }
                                }
                            }
                        }
                    } else if data.readingQueue.isEmpty {
                        HomeEmptyState(
                            message: appModel.localized("还没有论文进入阅读队列。", "No papers are queued for reading yet."),
                            actionTitle: appModel.localized("添加论文", "Add Paper"),
                            systemImage: "plus"
                        ) {
                            recordAction("add_paper", targetID: "library")
                            appModel.beginIdentifierImport()
                        }
                    } else {
                        VStack(spacing: 7) {
                            ForEach(data.readingQueue.prefix(5)) { paper in
                                HomePaperRow(paper: paper) {
                                    recordAction("open_paper", targetID: paper.id)
                                    appModel.selectPaper(id: paper.id)
                                    appModel.selectSection(.library)
                                }
                            }
                        }
                    }
                }

                HomeSignalCard(title: appModel.localized("即将到期", "Upcoming Deadlines"), systemImage: "calendar.badge.clock", count: data.upcomingDeadlines.count) {
                    if !snapshot.moduleAvailability.tasksEnabled {
                        ModuleDisabledView(message: appModel.localized("Tasks 模块已关闭。", "Tasks module is disabled.")) {
                            appModel.openSettings(category: .modules)
                        }
                    } else if data.upcomingDeadlines.isEmpty {
                        HomeEmptyState(
                            message: appModel.localized("未来两周没有 deadline。", "No deadlines in the next two weeks."),
                            actionTitle: appModel.localized("打开任务", "Open Tasks"),
                            systemImage: "arrow.up.right"
                        ) {
                            recordAction("open_tasks", targetID: "tasks")
                            appModel.selectGlobalTodos()
                        }
                    } else {
                        VStack(spacing: 7) {
                            ForEach(data.upcomingDeadlines.prefix(5)) { deadline in
                                HomeDeadlineRow(deadline: deadline) {
                                    recordAction("open_deadline", targetID: deadline.id)
                                    appModel.selectGlobalTodos()
                                }
                            }
                        }
                    }
                }

                HomeSignalCard(title: appModel.localized("待审 AI 草稿", "Pending AI Drafts"), systemImage: "tray.and.arrow.down", count: data.pendingDrafts.count) {
                    if !snapshot.moduleAvailability.aiLabEnabled {
                        ModuleDisabledView(message: appModel.localized("AI Lab 模块已关闭。", "AI Lab module is disabled.")) {
                            appModel.openSettings(category: .modules)
                        }
                    } else if data.pendingDrafts.isEmpty {
                        HomeEmptyState(
                            message: appModel.localized("没有等待审批的 AI 草稿。", "No AI drafts are waiting for review."),
                            actionTitle: appModel.localized("打开 AI Lab", "Open AI Lab"),
                            systemImage: "brain"
                        ) {
                            recordAction("open_ai_lab", targetID: "ai-lab")
                            appModel.selectSection(.llmLab)
                        }
                    } else {
                        VStack(spacing: 7) {
                            ForEach(data.pendingDrafts) { draft in
                                HomeDraftRow(draft: draft) {
                                    openDraft(draft)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func openDraft(_ draft: DraftSummary) {
        recordAction("open_draft", targetID: draft.id)
        if appModel.isWorkspaceSectionAvailable(.inbox) {
            appModel.selectSection(.inbox)
        } else {
            appModel.selectSection(.llmLab)
        }
    }

    private func recordAction(_ actionID: String, targetID: String) {
        appModel.recordHomeDebugEvent("home.panel.action", payload: .object([
            "panel": .string("today"),
            "action_id": .string(actionID),
            "target_id": .string(targetID)
        ]))
    }
}

struct ActiveProjectsPanelView: View {
    let projects: [ActiveProjectData]
    let moduleAvailability: HomeModuleAvailability
    @ObservedObject var appModel: AppViewModel

    var body: some View {
        HomePanelSection(
            title: appModel.localized("Active Projects", "Active Projects"),
            subtitle: appModel.localized("阶段、核心论文、近期 artifact 与下个 milestone。", "Stage, core papers, recent artifacts, and next milestones.")
        ) {
            if !moduleAvailability.projectsEnabled {
                ModuleDisabledView(message: appModel.localized("Projects 模块已关闭。", "Projects module is disabled.")) {
                    appModel.openSettings(category: .modules)
                }
            } else if projects.isEmpty {
                HomeEmptyState(
                    message: appModel.localized("还没有 active project。", "No active projects yet."),
                    actionTitle: appModel.localized("创建项目", "Create Project"),
                    systemImage: "plus"
                ) {
                    recordAction("create_project", targetID: "projects")
                    appModel.beginCreatingResearchProject()
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 8) {
                    ForEach(projects) { project in
                        ActiveProjectRow(project: project, appModel: appModel) { actionID, targetID in
                            recordAction(actionID, targetID: targetID)
                        }
                    }
                }
            }
        }
    }

    private func recordAction(_ actionID: String, targetID: String) {
        appModel.recordHomeDebugEvent("home.panel.action", payload: .object([
            "panel": .string("active_projects"),
            "action_id": .string(actionID),
            "target_id": .string(targetID)
        ]))
    }
}

struct AIReviewPanelView: View {
    let aiReview: AIReviewPanelData
    let moduleAvailability: HomeModuleAvailability
    @ObservedObject var appModel: AppViewModel

    var body: some View {
        HomePanelSection(
            title: appModel.localized("AI Review", "AI Review"),
            subtitle: appModel.localized("审批、unsupported claim 与 stale evidence 预警。", "Approval, unsupported claim, and stale evidence queues.")
        ) {
            if !moduleAvailability.aiLabEnabled && !moduleAvailability.draftInboxEnabled {
                ModuleDisabledView(message: appModel.localized("AI Lab / Draft Inbox 模块已关闭。", "AI Lab / Draft Inbox modules are disabled.")) {
                    appModel.openSettings(category: .modules)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], alignment: .leading, spacing: 12) {
                    ReviewColumn(
                        title: appModel.localized("Needs Approval", "Needs Approval"),
                        systemImage: "checkmark.seal",
                        emptyMessage: appModel.localized("没有待审批草稿。", "No drafts need approval."),
                        count: aiReview.needsApproval.count
                    ) {
                        ForEach(aiReview.needsApproval) { draft in
                            HomeDraftRow(draft: draft) {
                                routeAIReview(actionID: "open_needs_approval", targetID: draft.id)
                            }
                        }
                    }

                    ReviewColumn(
                        title: appModel.localized("Unsupported Claims", "Unsupported Claims"),
                        systemImage: "quote.bubble",
                        emptyMessage: appModel.localized("没有 unsupported claim。", "No unsupported claims."),
                        count: aiReview.unsupportedClaims.count
                    ) {
                        ForEach(aiReview.unsupportedClaims) { claim in
                            HomeCountWarningRow(
                                title: claim.title,
                                detail: appModel.localized("\(claim.count) 条 claim 需要证据", "\(claim.count) claims need evidence"),
                                date: claim.createdAt,
                                systemImage: "exclamationmark.bubble"
                            ) {
                                routeAIReview(actionID: "open_unsupported_claim", targetID: claim.id)
                            }
                        }
                    }

                    ReviewColumn(
                        title: appModel.localized("Stale Evidence", "Stale Evidence"),
                        systemImage: "exclamationmark.triangle",
                        emptyMessage: appModel.localized("没有 stale evidence warning。", "No stale evidence warnings."),
                        count: aiReview.staleEvidenceWarnings.count
                    ) {
                        ForEach(aiReview.staleEvidenceWarnings) { warning in
                            HomeCountWarningRow(
                                title: warning.title,
                                detail: appModel.localized("\(warning.count) 条证据需要复核", "\(warning.count) evidence items need review"),
                                date: warning.createdAt,
                                systemImage: "exclamationmark.triangle"
                            ) {
                                routeAIReview(actionID: "open_stale_evidence", targetID: warning.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private func routeAIReview(actionID: String, targetID: String) {
        appModel.recordHomeDebugEvent("home.panel.action", payload: .object([
            "panel": .string("ai_review"),
            "action_id": .string(actionID),
            "target_id": .string(targetID)
        ]))
        if appModel.isWorkspaceSectionAvailable(.inbox) {
            appModel.selectSection(.inbox)
        } else {
            appModel.selectSection(.llmLab)
        }
    }
}

private struct ActiveProjectRow: View {
    let project: ActiveProjectData
    @ObservedObject var appModel: AppViewModel
    let recordAction: (String, String) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                recordAction("open_project", project.projectID)
                appModel.selectResearchProject(project.projectID)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    StageBadge(stage: project.stage, rule: project.stageRule)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(projectSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        HomeMetricPill(label: appModel.localized("Core", "Core"), value: "\(project.coreCount)")
                        HomeMetricPill(label: appModel.localized("Recent", "Recent"), value: "\(project.recentPaperCount)")
                        HomeMetricPill(label: appModel.localized("Gaps", "Gaps"), value: "\(project.openGapsCount)")
                        HomeMetricPill(label: appModel.localized("Open", "Open"), value: "\(project.openTodoCount)")
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                actionButton(systemImage: "doc.text", help: appModel.localized("打开项目笔记", "Open project notes")) {
                    openProjectNotes()
                }
                actionButton(systemImage: "checklist", help: appModel.localized("打开项目任务", "Open project tasks")) {
                    recordAction("open_tasks", project.projectID)
                    appModel.selectResearchProject(project.projectID, section: .tasks)
                }
                actionButton(systemImage: "text.book.closed", help: appModel.localized("打开项目 Wiki", "Open project wiki")) {
                    recordAction("open_wiki", project.projectID)
                    appModel.selectResearchProject(project.projectID, section: .wiki)
                }
                actionButton(systemImage: "brain", help: appModel.localized("打开 AI Lab 草稿", "Open AI Lab drafts")) {
                    recordAction("open_ai_drafts", project.projectID)
                    appModel.selectResearchProject(project.projectID, section: .llmLab)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var projectSubtitle: String {
        if let artifact = project.latestArtifact {
            return appModel.localized("最新 artifact：\(artifact.kind)", "Latest artifact: \(artifact.kind)")
        }
        if let deadline = project.nextDeadline {
            return appModel.localized("下个 deadline：\(deadline.dueDate.formatted(date: .abbreviated, time: .omitted))", "Next deadline: \(deadline.dueDate.formatted(date: .abbreviated, time: .omitted))")
        }
        return appModel.localized("等待下一步研究信号。", "Waiting for the next research signal.")
    }

    private func openProjectNotes() {
        guard let model = appModel.researchProjects.first(where: { $0.id == project.projectID }) else {
            appModel.selectResearchProject(project.projectID)
            return
        }
        recordAction("open_notes", project.projectID)
        appModel.openMarkdownDocument(relativePath: model.relativePath + "/wiki/projects/project_overview.md")
    }

    private func actionButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

struct StageBadge: View {
    let stage: ProjectStage
    let rule: String

    var body: some View {
        Label(stage.label, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .help(rule)
    }

    private var systemImage: String {
        switch stage {
        case .exploration: return "sparkle.magnifyingglass"
        case .planning: return "map"
        case .drafting: return "pencil.and.outline"
        case .reviewing: return "checkmark.seal"
        case .onHold: return "pause.circle"
        }
    }

    private var color: Color {
        switch stage {
        case .exploration: return .blue
        case .planning: return .accentColor
        case .drafting: return .orange
        case .reviewing: return .purple
        case .onHold: return .secondary
        }
    }
}

private struct HomePanelSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeSignalCard<Content: View>: View {
    let title: String
    let systemImage: String
    let count: Int

    let content: Content

    init(title: String, systemImage: String, count: Int, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }

            content
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ReviewColumn<Content: View>: View {
    let title: String
    let systemImage: String
    let emptyMessage: String
    let count: Int
    let content: Content

    init(title: String, systemImage: String, emptyMessage: String, count: Int, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.emptyMessage = emptyMessage
        self.count = count
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if count == 0 {
                Text(emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            } else {
                VStack(spacing: 7) {
                    content
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct HomeTodoRow: View {
    let todo: TodoSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: todo.priority == .urgent ? "exclamationmark.circle.fill" : "circle")
                    .foregroundStyle(todo.priority == .urgent ? .red : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(todo.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(todo.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? todo.priority.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeQueueEntryRow: View {
    let entry: ReadingQueueEntrySummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: statusSystemImage)
                    .foregroundStyle(statusTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private var statusSystemImage: String {
        switch entry.status {
        case .queued: return "tray"
        case .reading: return "book"
        case .finished: return "checkmark.seal"
        case .deferred: return "moon"
        case .dismissed: return "xmark.circle"
        }
    }

    private var statusTint: Color {
        switch entry.status {
        case .queued: return .blue
        case .reading: return .orange
        case .finished: return .green
        case .deferred: return .purple
        case .dismissed: return .secondary
        }
    }

    private var subtitleText: String {
        var parts: [String] = []
        parts.append(entry.status == .reading ? "Reading" : "Queued")
        if let externalKey = entry.externalKey, entry.paperID == nil {
            parts.append("external: \(externalKey)")
        }
        switch entry.source {
        case .recommendation:
            parts.append("from recommendation")
        case .graphTool:
            parts.append("from graph tool")
        case .paperStatus:
            parts.append("paper status sync")
        case .manual:
            break
        }
        return parts.joined(separator: " · ")
    }
}

private struct HomePaperRow: View {
    let paper: PaperSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "doc.richtext")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(paper.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text([paper.authors, paper.status.label].filter { !$0.isEmpty }.joined(separator: " - "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeDeadlineRow: View {
    let deadline: DeadlineSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deadline.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(deadline.dueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeDraftRow: View {
    let draft: DraftSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "doc.badge.clock")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(draft.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeCountWarningRow: View {
    let title: String
    let detail: String
    let date: Date
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(detail + " - " + date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeMetricPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 42)
    }
}

private struct HomeEmptyState: View {
    let message: String
    let actionTitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Label(actionTitle, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModuleDisabledView: View {
    let message: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(message, systemImage: "slash.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(action: action) {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}