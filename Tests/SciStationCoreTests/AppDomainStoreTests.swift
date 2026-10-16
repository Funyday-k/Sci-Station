import Combine
import Foundation
import Testing
@testable import SciStationCore

@Suite("Application domain stores")
@MainActor
struct AppDomainStoreTests {
    @Test("Workspace state transitions and reset stay self-contained")
    func workspaceStoreReset() {
        let store = WorkspaceStore()
        let workspace = ResearchWorkspace(rootURL: URL(fileURLWithPath: "/tmp/sci-station-store-test"))
        let project = ResearchProject(
            id: "project-1",
            name: "Project One",
            relativePath: "projects/project-1"
        )

        store.setWorkspace(workspace)
        store.setProjects([project])
        store.setCurrentProjectID(project.id)

        #expect(store.workspace == workspace)
        #expect(store.projects == [project])
        #expect(store.currentProjectID == project.id)

        store.reset()

        #expect(store.workspace == nil)
        #expect(store.root == nil)
        #expect(store.projects.isEmpty)
        #expect(store.currentProjectID == nil)
    }

    @Test("Library selection reset does not retain stale paper IDs")
    func libraryStoreReset() {
        let store = LibraryStore()
        store.setSelectedPaperIDs(["paper-1", "paper-2"])

        #expect(store.selectedPaperIDs == ["paper-1", "paper-2"])

        store.reset()

        #expect(store.papers.isEmpty)
        #expect(store.projectLinks.isEmpty)
        #expect(store.collections.isEmpty)
        #expect(store.tags.isEmpty)
        #expect(store.selectedPaperIDs.isEmpty)
    }

    @Test("Knowledge reset clears selection and failed save state")
    func knowledgeStoreReset() {
        let store = KnowledgeStore()
        store.setSelection(id: "wiki/concepts/graph.md", draft: nil)
        store.setSaveState(.failed, errorMessage: "disk full")

        #expect(store.selectedDocumentID == "wiki/concepts/graph.md")
        #expect(store.saveState == .failed)
        #expect(store.saveErrorMessage == "disk full")

        store.reset()

        #expect(store.documents.isEmpty)
        #expect(store.selectedDocumentID == nil)
        #expect(store.selectedDraft == nil)
        #expect(store.saveState == .clean)
        #expect(store.saveErrorMessage == nil)
    }

    @Test("Recommendation reset clears transient and persisted presentation state")
    func recommendationStoreReset() {
        let store = RecommendationStore()
        store.setCandidateCount(12)
        store.setRefreshing(true)
        store.setEvaluatingWithAI(true)
        store.setErrorMessage("network error")
        store.setAIEvaluationStatusMessage("waiting")

        store.reset()

        #expect(store.runResult == nil)
        #expect(store.history.isEmpty)
        #expect(store.feedbackByScoreID.isEmpty)
        #expect(store.candidateCount == 0)
        #expect(!store.isRefreshing)
        #expect(!store.isEvaluatingWithAI)
        #expect(store.errorMessage == nil)
        #expect(store.aiEvaluationStatusMessage == nil)
    }

    @Test("Agent reset clears run-facing state and messages")
    func agentStoreReset() {
        let store = AgentStore()
        store.setStatusMessage("running")
        store.setErrorMessage("tool failed")

        store.reset()

        #expect(store.currentRun == nil)
        #expect(store.runHistory.isEmpty)
        #expect(store.threads.isEmpty)
        #expect(store.toolDefinitions.isEmpty)
        #expect(store.statusMessage == nil)
        #expect(store.errorMessage == nil)
    }

    @Test("Focused stores mutate independently without shared facade state")
    func focusedStoresRemainIndependent() {
        let workspaceStore = WorkspaceStore()
        let libraryStore = LibraryStore()
        let knowledgeStore = KnowledgeStore()
        let recommendationStore = RecommendationStore()
        let agentStore = AgentStore()

        workspaceStore.setCurrentProjectID("project-1")
        libraryStore.setSelectedPaperIDs(["paper-1"])
        knowledgeStore.setSelection(id: "wiki/page.md", draft: nil)
        recommendationStore.setCandidateCount(7)
        agentStore.setStatusMessage("running")

        workspaceStore.reset()

        #expect(workspaceStore.currentProjectID == nil)
        #expect(libraryStore.selectedPaperIDs == ["paper-1"])
        #expect(knowledgeStore.selectedDocumentID == "wiki/page.md")
        #expect(recommendationStore.candidateCount == 7)
        #expect(agentStore.statusMessage == "running")
    }

    @Test("Navigation reset clears project routes and restores stable shell defaults")
    func navigationStoreReset() {
        let store = NavigationStore()
        store.selectedSection = .library
        store.selectedProjectID = "project-1"
        store.selectedProjectTabID = "wiki"
        store.isViewingGlobalTodos = true
        store.selectedSettingsCategory = .developer
        store.updateWindow(width: 760, isNarrow: true)

        store.reset()

        #expect(store.selectedSection == .projects)
        #expect(store.selectedProjectID == nil)
        #expect(store.selectedProjectTabID == ProjectSpaceTabsBuilder.overviewTabID)
        #expect(!store.isViewingGlobalTodos)
        #expect(store.selectedSettingsCategory == .workspace)
        #expect(store.shellWindowWidth == 1_440)
        #expect(!store.isShellNarrowWidth)
    }

    @Test("Top-level navigation mapping is deterministic and reversible")
    func topLevelNavigationMapping() {
        for top in WorkspaceRoute.Top.allCases {
            let section = WorkspaceNavigationPolicy.section(for: top)
            #expect(WorkspaceNavigationPolicy.topRoute(for: section) == top)
            #expect(
                WorkspaceNavigationPolicy.recentSectionValue(for: WorkspaceRoute(top: top))
                    == section.rawValue
            )
        }
    }

    @Test("Route policy preserves project, library, task, and agent context")
    func routePolicyPreservesContext() {
        let projectRoute = WorkspaceNavigationPolicy.route(
            selectedSection: .wiki,
            selectedProjectID: nil,
            selectedProjectTabID: ProjectSpaceTabsBuilder.overviewTabID,
            currentProjectID: "project-1",
            librarySecondarySelection: nil,
            isViewingGlobalTodos: false,
            agentProjectID: nil
        )
        #expect(projectRoute == WorkspaceRoute(top: .projects, projectID: "project-1", projectTabID: "wiki"))

        let libraryRoute = WorkspaceNavigationPolicy.route(
            selectedSection: .library,
            selectedProjectID: nil,
            selectedProjectTabID: ProjectSpaceTabsBuilder.overviewTabID,
            currentProjectID: nil,
            librarySecondarySelection: "collection/review",
            isViewingGlobalTodos: false,
            agentProjectID: nil
        )
        #expect(libraryRoute == WorkspaceRoute(top: .library, secondarySelection: "collection/review"))

        let todoRoute = WorkspaceNavigationPolicy.route(
            selectedSection: .tasks,
            selectedProjectID: nil,
            selectedProjectTabID: ProjectSpaceTabsBuilder.overviewTabID,
            currentProjectID: nil,
            librarySecondarySelection: nil,
            isViewingGlobalTodos: true,
            agentProjectID: nil
        )
        #expect(todoRoute == WorkspaceRoute(top: .calendar, secondarySelection: "global_todos"))

        let agentRoute = WorkspaceNavigationPolicy.route(
            selectedSection: .llmLab,
            selectedProjectID: nil,
            selectedProjectTabID: ProjectSpaceTabsBuilder.overviewTabID,
            currentProjectID: nil,
            librarySecondarySelection: nil,
            isViewingGlobalTodos: false,
            agentProjectID: "project-2"
        )
        #expect(agentRoute == WorkspaceRoute(top: .aiLab, projectID: "project-2"))
    }

    @Test("Legacy section restoration uses project context only when required")
    func legacyRouteMapping() {
        #expect(
            WorkspaceNavigationPolicy.legacyRoute(
                recentSection: WorkspaceSection.wiki.rawValue,
                currentProjectID: "project-1"
            ) == WorkspaceRoute(top: .projects, projectID: "project-1", projectTabID: "wiki")
        )
        #expect(
            WorkspaceNavigationPolicy.legacyRoute(
                recentSection: WorkspaceSection.library.rawValue,
                currentProjectID: "project-1"
            ) == WorkspaceRoute(top: .library)
        )
        #expect(
            WorkspaceNavigationPolicy.legacyRoute(recentSection: "unknown", currentProjectID: nil) == .home
        )
    }

    @Test("Library use cases derive membership and legacy links without the app facade")
    func libraryUseCases() {
        let member = makePaper(
            id: "paper-1",
            citekey: "author2026paper",
            title: "Paper One",
            projectIDs: ["project-1"],
            coreProjectIDs: ["project-1"]
        )
        let outsider = makePaper(id: "paper-2", citekey: "author2026other", title: "Paper Two")

        #expect(LibraryDomainUseCases.papers([member, outsider], for: "project-1") == [member])
        #expect(LibraryDomainUseCases.corePapers([member, outsider], for: "project-1") == [member])
        #expect(
            LibraryDomainUseCases.projectLink(
                paper: member,
                projectID: "project-1",
                links: []
            )?.isCore == true
        )
        #expect(
            LibraryDomainUseCases.projectLink(
                paper: outsider,
                projectID: "project-1",
                links: []
            ) == nil
        )
    }

    @Test("Workspace use cases resolve names and open todos independently")
    func workspaceUseCases() {
        let project = ResearchProject(
            id: "project-1",
            name: "Project One",
            relativePath: "projects/project-1"
        )
        let paper = makePaper(
            id: "paper-1",
            citekey: "author2026paper",
            title: "Paper One",
            projectIDs: [project.id],
            coreProjectIDs: [project.id]
        )
        let open = makeTodo(id: "todo-open", title: "Open", projectID: project.id)
        let done = makeTodo(id: "todo-done", title: "Done", status: .done, projectID: project.id)

        #expect(WorkspaceDomainUseCases.projectNames(for: paper, projects: [project]) == [project.name])
        #expect(WorkspaceDomainUseCases.coreProjectNames(for: paper, projects: [project]) == [project.name])
        #expect(WorkspaceDomainUseCases.todos([open, done], for: project.id).count == 2)
        #expect(WorkspaceDomainUseCases.openTodos([open, done], for: project.id) == [open])
    }

    @Test("Failed staged loading never publishes the candidate session or write root")
    func failedWorkspaceLoadKeepsPreviousSessionUnobserved() async {
        await assertFailedStagedWorkspaceLoad(throwing: WorkspaceLoadFixtureError.damagedMetadata)
    }

    @Test("Cancelled staged loading never publishes the candidate session or write root")
    func cancelledWorkspaceLoadKeepsPreviousSessionUnobserved() async {
        await assertFailedStagedWorkspaceLoad(throwing: CancellationError())
    }

    private func assertFailedStagedWorkspaceLoad(throwing expectedError: any Error) async {
        let workspaceStore = WorkspaceStore()
        let libraryStore = LibraryStore()
        let knowledgeStore = KnowledgeStore()
        let recommendationStore = RecommendationStore()
        let agentStore = AgentStore()
        let navigationStore = NavigationStore()
        let workspaceA = ResearchWorkspace(rootURL: URL(fileURLWithPath: "/tmp/sci-station-workspace-a"))
        let rootA = ResearchRoot(rootURL: workspaceA.rootURL)
        let projectA = ResearchProject(id: "project-a", name: "Project A", relativePath: "projects/project-a")
        let workspaceB = ResearchWorkspace(rootURL: URL(fileURLWithPath: "/tmp/sci-station-workspace-b"))
        let rootB = ResearchRoot(rootURL: workspaceB.rootURL)
        let projectB = ResearchProject(id: "project-b", name: "Project B", relativePath: "projects/project-b")

        workspaceStore.setWorkspace(workspaceA)
        workspaceStore.setRoot(rootA)
        workspaceStore.setProjects([projectA])
        workspaceStore.setCurrentProjectID(projectA.id)
        libraryStore.setSelectedPaperIDs(["paper-a"])
        knowledgeStore.setSelection(id: "wiki/a.md", draft: nil)
        recommendationStore.setCandidateCount(3)
        agentStore.setStatusMessage("workspace-a")
        navigationStore.selectedSection = .library
        navigationStore.selectedProjectID = projectA.id
        var writeRoot = rootA.rootURL
        var publishedWorkspaceValues: [ResearchWorkspace?] = []
        var storeChangeCount = 0
        var observations = Set<AnyCancellable>()
        workspaceStore.$workspace
            .sink { publishedWorkspaceValues.append($0) }
            .store(in: &observations)
        for publisher in [
            workspaceStore.objectWillChange,
            libraryStore.objectWillChange,
            knowledgeStore.objectWillChange,
            recommendationStore.objectWillChange,
            agentStore.objectWillChange,
            navigationStore.objectWillChange
        ] {
            publisher
                .sink { storeChangeCount += 1 }
                .store(in: &observations)
        }

        do {
            let loadedState: LoadedWorkspaceState<AppDomainStoresSnapshot> = try await WorkspaceStateLoader.load(
                workspace: workspaceB,
                operation: {
                    let stagedWorkspaceStore = WorkspaceStore()
                    let stagedLibraryStore = LibraryStore()
                    let stagedKnowledgeStore = KnowledgeStore()
                    let stagedRecommendationStore = RecommendationStore()
                    let stagedAgentStore = AgentStore()
                    let stagedNavigationStore = NavigationStore()

                    stagedWorkspaceStore.setWorkspace(workspaceB)
                    stagedWorkspaceStore.setRoot(rootB)
                    stagedWorkspaceStore.setProjects([projectB])
                    stagedWorkspaceStore.setCurrentProjectID(projectB.id)
                    stagedLibraryStore.setSelectedPaperIDs(["paper-b"])
                    stagedKnowledgeStore.setSelection(id: "wiki/b.md", draft: nil)
                    stagedRecommendationStore.setCandidateCount(99)
                    stagedAgentStore.setStatusMessage("workspace-b")
                    stagedNavigationStore.selectedSection = .settings
                    stagedNavigationStore.selectedProjectID = projectB.id

                    _ = AppDomainStoresSnapshot(
                        workspaceStore: stagedWorkspaceStore,
                        libraryStore: stagedLibraryStore,
                        knowledgeStore: stagedKnowledgeStore,
                        recommendationStore: stagedRecommendationStore,
                        agentStore: stagedAgentStore,
                        navigationStore: stagedNavigationStore
                    )
                    throw expectedError
                }
            )
            loadedState.state.restore(
                workspaceStore: workspaceStore,
                libraryStore: libraryStore,
                knowledgeStore: knowledgeStore,
                recommendationStore: recommendationStore,
                agentStore: agentStore,
                navigationStore: navigationStore
            )
            writeRoot = loadedState.workspace.rootURL
            Issue.record("Expected workspace loading to fail.")
        } catch {
            if expectedError is CancellationError {
                #expect(error is CancellationError)
            } else {
                #expect(error is WorkspaceLoadFixtureError)
            }
        }

        #expect(workspaceStore.workspace == workspaceA)
        #expect(workspaceStore.root?.rootURL == rootA.rootURL)
        #expect(workspaceStore.projects == [projectA])
        #expect(workspaceStore.currentProjectID == projectA.id)
        #expect(libraryStore.selectedPaperIDs == ["paper-a"])
        #expect(knowledgeStore.selectedDocumentID == "wiki/a.md")
        #expect(recommendationStore.candidateCount == 3)
        #expect(agentStore.statusMessage == "workspace-a")
        #expect(navigationStore.selectedSection == .library)
        #expect(navigationStore.selectedProjectID == projectA.id)
        #expect(writeRoot == rootA.rootURL)
        #expect(publishedWorkspaceValues == [workspaceA])
        #expect(storeChangeCount == 0)
        _ = observations
    }

    private func makePaper(
        id: String,
        citekey: String,
        title: String,
        projectIDs: [String] = [],
        coreProjectIDs: [String] = []
    ) -> Paper {
        let timestamp = Date(timeIntervalSince1970: 1_775_606_400)
        return Paper(
            id: id,
            citekey: citekey,
            title: title,
            authors: ["Ada Lovelace"],
            year: 2026,
            venue: nil,
            doi: nil,
            arxiv: nil,
            url: nil,
            projectIDs: projectIDs,
            coreProjectIDs: coreProjectIDs,
            pdfRelativePath: nil,
            tags: [],
            status: .unread,
            priority: .medium,
            rating: nil,
            useFor: [],
            createdAt: timestamp,
            updatedAt: timestamp,
            paperDirectoryRelativePath: "library/papers/\(id)",
            notesSummaryRelativePath: nil,
            annotationsRelativePath: "annotations.md"
        )
    }

    private func makeTodo(
        id: String,
        title: String,
        status: TodoStatus = .open,
        projectID: String
    ) -> TodoItem {
        let timestamp = Date(timeIntervalSince1970: 1_775_606_400)
        return TodoItem(
            id: id,
            title: title,
            status: status,
            dueDate: nil,
            projectIDs: [projectID],
            tags: [],
            relatedPaperIDs: [],
            notes: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }
}

private enum WorkspaceLoadFixtureError: Error {
    case damagedMetadata
}
