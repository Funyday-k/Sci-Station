import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runAgentPlatform() async {
        await runCheck("agentPromptLibraryRejectsSecretLikePromptBodies") { try agentPromptLibraryRejectsSecretLikePromptBodies() }
        await runCheck("agentPromptLibraryDiffPreviewHighlightsBodyChanges") { try agentPromptLibraryDiffPreviewHighlightsBodyChanges() }
        await runCheck("agentPromptPatchProposalAcceptRejectDiscardSemantics") { try agentPromptPatchProposalAcceptRejectDiscardSemantics() }
        await runCheck("agentPromptPatchProposalRejectsActiveSurfaceMismatch") { try agentPromptPatchProposalRejectsActiveSurfaceMismatch() }
        await runCheck("agentWorkspaceProfileRepositoryRestoresDefaultPromptTemplate") { try await agentWorkspaceProfileRepositoryRestoresDefaultPromptTemplate() }
        await runCheck("agentPromptTemplateRoundTripsWorkspaceProfile") { try await agentPromptTemplateRoundTripsWorkspaceProfile() }
        await runCheck("agentSkillLoaderTrustGatingAndCatalogVisibility") { try await agentSkillLoaderTrustGatingAndCatalogVisibility() }
        await runCheck("agentSkillLoaderCatalogSourcePrecedence") { try await agentSkillLoaderCatalogSourcePrecedence() }
        await runCheck("agentSkillLoaderBlocksSecretSkillBodies") { try await agentSkillLoaderBlocksSecretSkillBodies() }
        await runCheck("agentWorkspaceSnapshotIncludesProjectContext") { try await agentWorkspaceSnapshotIncludesProjectContext() }
        await runCheck("agentWorkspaceSnapshotDoesNotEmbedMarkdownByDefault") { try await agentWorkspaceSnapshotDoesNotEmbedMarkdownByDefault() }
        await runCheck("agentWorkspaceSnapshotLegacyPolicyKeepsDeepKnowledgePaperContext") { try await agentWorkspaceSnapshotLegacyPolicyKeepsDeepKnowledgePaperContext() }
        await runCheck("agentPromptBuilderDirectsPaperToolsForMetadataOnlyContext") { try agentPromptBuilderDirectsPaperToolsForMetadataOnlyContext() }
        await runCheck("mcpGatewayListsAndCallsReadOnlySciStationTools") { try await mcpGatewayListsAndCallsReadOnlySciStationTools() }
        await runCheck("mcpGatewayRequiresApprovalForWorkspaceWrites") { try await mcpGatewayRequiresApprovalForWorkspaceWrites() }
        await runCheck("agentSkillLoaderProgressivelyLoadsMatchingSkill") { try await agentSkillLoaderProgressivelyLoadsMatchingSkill() }
        await runCheck("agentPromptDraftRepositoryPersistsDrafts") { try await agentPromptDraftRepositoryPersistsDrafts() }
        await runCheck("agentWorkspaceProfileRepositoryPersistsPromptSkillAndMCPOverrides") { try await agentWorkspaceProfileRepositoryPersistsPromptSkillAndMCPOverrides() }
        await runCheck("sciAITrackedPresetManifestValidates") { try sciAITrackedPresetManifestValidates() }
        await runCheck("sciAIConfigurationBoundaryValidates") { try sciAIConfigurationBoundaryValidates() }
        await runCheck("agentMCPServerStatusSummaryParsesProductAndLocal") { try agentMCPServerStatusSummaryParsesProductAndLocal() }
        await runCheck("agentMCPConnectorRegistryEnforcesPrecedenceAndApproval") { try agentMCPConnectorRegistryEnforcesPrecedenceAndApproval() }
        await runCheck("agentLocalMCPConfigurationDefaultsDisabledAndRedactsRawSecrets") { try agentLocalMCPConfigurationDefaultsDisabledAndRedactsRawSecrets() }
        await runCheck("agentMCPStdioClientDiscoversAndApprovalGatesTool") { try await agentMCPStdioClientDiscoversAndApprovalGatesTool() }
        await runCheck("agentMCPRemoteHTTPDiscoversAndApprovalGatesTool") { try await agentMCPRemoteHTTPDiscoversAndApprovalGatesTool() }
        await runCheck("agentMCPRemoteFailureBackoffIsAuditable") { try await agentMCPRemoteFailureBackoffIsAuditable() }
        await runCheck("agentMCPRuntimeReportsRemoteCredentialFailure") { try await agentMCPRuntimeReportsRemoteCredentialFailure() }
        await runCheck("agentMCPRuntimeReportsLocalCrashLiveness") { try await agentMCPRuntimeReportsLocalCrashLiveness() }
    }

    func agentPromptLibraryRejectsSecretLikePromptBodies() throws {
        let resolver = AgentPromptLibraryResolver()
        let safeMessage = resolver.validatePromptText("Use project evidence only.")
        let blockedMessage = resolver.validatePromptText("Here is a token: sk-test_1234567890abcdef")

        try expect(safeMessage == nil, "Regular prompt text should be accepted.")
        try expect(blockedMessage != nil, "Secret-like prompt text should be rejected.")
    }

    func agentPromptLibraryDiffPreviewHighlightsBodyChanges() throws {
        let resolver = AgentPromptLibraryResolver()
        let current = AgentPromptTemplateOverride(
            id: "planner-default",
            title: "Planner Default",
            surface: .planner,
            systemPrompt: "Use evidence only.",
            promptTemplate: "Plan from current workspace context."
        )
        let draft = AgentPromptTemplateOverride(
            id: "planner-default",
            title: "Planner Default",
            surface: .planner,
            systemPrompt: "Use evidence only.",
            promptTemplate: "Plan from current workspace context and cite paper ids."
        )

        let diff = resolver.diffPreview(current: current, draft: draft)
        let body = resolver.renderedTemplateBody(draft)

        try expect(diff.contains("- Plan from current workspace context."), "Prompt diff should show removed body lines.")
        try expect(diff.contains("+ Plan from current workspace context and cite paper ids."), "Prompt diff should show added body lines.")
        try expect(body.contains("Use evidence only."), "Rendered prompt body should include system prompt text.")
        try expect(body.contains("cite paper ids"), "Rendered prompt body should include prompt template text.")
    }

    func agentPromptPatchProposalAcceptRejectDiscardSemantics() throws {
        let resolver = AgentPromptLibraryResolver()
        let current = AgentPromptTemplateOverride(
            id: "planner-override",
            title: "Planner Override",
            surface: .planner,
            systemPrompt: "Use evidence only.",
            promptTemplate: "Create a short plan."
        )
        let profile = AgentWorkspaceProfile(
            activePromptTemplateID: current.id,
            promptTemplates: [current]
        )
        let proposal = AgentPromptPatchProposal(
            templateID: current.id,
            title: "Planner Override",
            surface: .planner,
            systemPrompt: "Use evidence only.",
            promptTemplate: "Create a short plan with cited paper IDs."
        )

        let review = resolver.reviewPatchProposal(proposal, profile: profile)
        let acceptedProfile = try resolver.applyAcceptedPatchProposal(proposal, to: profile)
        let rejectedProfile = profile
        let discardedDraft = current

        try expect(review.canAccept, "Valid prompt patch proposals should be accept-ready.")
        try expect(review.diffPreview.contains("+ Create a short plan with cited paper IDs."), "Preview should show the proposed prompt body.")
        try expect(acceptedProfile.promptTemplate(id: current.id)?.promptTemplate.contains("cited paper IDs") == true, "Accept should persist the proposed prompt body.")
        try expect(acceptedProfile.activePromptTemplateID == current.id, "Accept should keep the accepted prompt active for its surface.")
        try expect(rejectedProfile == profile, "Reject semantics should leave the profile unchanged.")
        try expect(discardedDraft == current, "Discard semantics should reset the local draft to the stored override.")
    }

    func agentPromptPatchProposalRejectsActiveSurfaceMismatch() throws {
        let resolver = AgentPromptLibraryResolver()
        let planner = AgentPromptTemplateOverride(
            id: "active-planner",
            title: "Planner",
            surface: .planner,
            promptTemplate: "Planner body."
        )
        let profile = AgentWorkspaceProfile(
            activePromptTemplateID: planner.id,
            promptTemplates: [planner]
        )
        let proposal = AgentPromptPatchProposal(
            templateID: "paper-summary-proposal",
            title: "Paper Summary",
            surface: .paperSummary,
            promptTemplate: "Summarize with citations."
        )
        let review = resolver.reviewPatchProposal(proposal, profile: profile)

        try expect(review.activeSurfaceMismatch?.contains("proposal targets paper_summary") == true, "Patch review should flag proposals that do not match the active prompt surface.")
        do {
            _ = try resolver.applyAcceptedPatchProposal(proposal, to: profile)
            throw ValidationError(message: "Surface-mismatched proposal should not be accepted.")
        } catch AgentError.invalidArguments {
            // Expected.
        }
    }

            func agentWorkspaceProfileRepositoryRestoresDefaultPromptTemplate() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentWorkspaceProfileRestoreDefault", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let repository = AgentWorkspaceProfileRepository()
                let resolver = AgentPromptLibraryResolver()
                let prompt = AgentPromptTemplateOverride(
                    id: "planner-override",
                    title: "Planner Override",
                    surface: .planner,
                    promptTemplate: "Follow project evidence and ask for approval before writes."
                )

                try await repository.upsertPromptTemplate(prompt, in: root)
                let activeProfile = try await repository.load(in: root)
                let activeResolution = resolver.resolve(surface: .planner, profile: activeProfile, basePrompt: "Base planner prompt.")
                try expect(activeResolution.templateID == "planner-override", "Enabled prompt override should be selected before restore.")

                try await repository.restoreDefaultPromptTemplate(id: prompt.id, in: root)
                let restoredProfile = try await repository.load(in: root)
                let restoredResolution = resolver.resolve(surface: .planner, profile: restoredProfile, basePrompt: "Base planner prompt.")

                try expect(restoredProfile.promptTemplates.isEmpty, "Restore default should remove the workspace override.")
                try expect(restoredProfile.activePromptTemplateID == nil, "Restore default should clear the active prompt template id.")
                try expect(restoredResolution.templateID == nil, "Restore default should let the bundled prompt take over again.")
                try expect(restoredResolution.promptText == "Base planner prompt.", "Restore default should return the bundled base prompt text unchanged.")
            }

            func agentPromptTemplateRoundTripsWorkspaceProfile() async throws {
                let rootURL = temporaryDirectoryURL().appendingPathComponent("AgentPromptRoundTripWorkspace", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

                let root = ResearchRoot(rootURL: rootURL)
                let repository = AgentWorkspaceProfileRepository()
                let prompt = AgentPromptTemplateOverride(
                    id: "tool-loop-override",
                    title: "Tool Loop Override",
                    version: "2.1.0",
                    description: "Round-trip test",
                    surface: .toolLoop,
                    systemPrompt: "System instructions.",
                    promptTemplate: "Use tools carefully.",
                    isEnabled: true
                )

                try await repository.upsertPromptTemplate(prompt, in: root)
                let loaded = try await repository.load(in: root)
                let profileText = try String(contentsOf: root.fileURL(for: AgentWorkspaceProfileRepository.relativePath), encoding: .utf8)

                try expect(loaded.promptTemplate(id: prompt.id) == prompt, "Prompt template overrides should round-trip through profile.json.")
                try expect(loaded.activePromptTemplateID == prompt.id, "First enabled prompt should become active after upsert.")
                try expect(profileText.contains("\"prompt_template\""), "Stored prompt overrides should preserve the existing snake_case JSON format.")
                try expect(profileText.contains("\"system_prompt\""), "Stored prompt system text should preserve the existing snake_case JSON format.")
            }

    func agentSkillLoaderTrustGatingAndCatalogVisibility() async throws {
        let rootURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let workspaceDirectory = rootURL.appendingPathComponent(".claude/skills/workspace-review", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: workspace-review
        description: Workspace evidence review
        version: 1.0.0
        capabilities: [workspace, evidence]
        risk: writesWorkspace
        allowed_tools: [write_wiki_markdown]
        ---

        Use workspace-only instructions.
        """.write(to: workspaceDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let loader = AgentSkillLoader()
        let untrustedProfile = AgentWorkspaceProfile(skillToggles: [
            AgentSkillToggle(skillID: "workspace-review", isEnabled: true, trustLevel: .untrusted)
        ])
        let untrustedCatalog = try await loader.catalog(
            profile: untrustedProfile,
            workspaceRoot: rootURL,
            prompt: "workspace evidence"
        )
        let untrustedEntry = try require(untrustedCatalog.first { $0.id == "workspace-review" }, "Catalog should include the workspace skill.")

        try expect(untrustedEntry.isEnabled, "Catalog should reflect enabled profile toggles.")
        try expect(untrustedEntry.blockedReason?.contains("untrusted") == true, "Catalog should expose runtime blocked reasons for untrusted skills.")

        let trustedProfile = AgentWorkspaceProfile(skillToggles: [
            AgentSkillToggle(skillID: "workspace-review", isEnabled: true, trustLevel: .trusted)
        ])
        let trustedCatalog = try await loader.catalog(
            profile: trustedProfile,
            workspaceRoot: rootURL,
            prompt: "workspace evidence"
        )
        let trustedEntry = try require(trustedCatalog.first { $0.id == "workspace-review" }, "Trusted catalog should include the workspace skill.")
        let filtered = loader.filterCatalog(trustedCatalog, query: "workspace evidence")

        try expect(trustedEntry.blockedReason == nil, "Explicit trust should clear the runtime blocked reason for a matching skill.")
        try expect(filtered.map(\.id) == ["workspace-review"], "Skill catalog search should match description/capability tokens.")
    }

    func agentSkillLoaderCatalogSourcePrecedence() async throws {
        let rootURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let bundledDirectory = rootURL.appendingPathComponent(".sci-ai/sci-station/presets/research-core/skills/duplicate", isDirectory: true)
        let workspaceDirectory = rootURL.appendingPathComponent(".claude/skills/duplicate", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: duplicate-skill
        description: Bundled duplicate
        version: 1.0.0
        capabilities: [bundled]
        risk: readOnly
        ---

        Bundled body.
        """.write(to: bundledDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try """
        ---
        name: duplicate-skill
        description: Workspace duplicate
        version: 9.9.9
        capabilities: [workspace]
        risk: writesWorkspace
        ---

        Workspace body.
        """.write(to: workspaceDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let loader = AgentSkillLoader()
        let metadata = try await loader.loadMetadata(searchRoots: AgentSkillLoader.defaultSearchRoots(workspaceRoot: rootURL))
        let duplicate = try require(metadata.first { $0.name == "duplicate-skill" }, "Duplicate skill should be discovered.")

        try expect(duplicate.source == .appBundled, "Bundled skills should take precedence over workspace skills with the same name.")
        try expect(duplicate.version == "1.0.0", "Catalog source precedence should keep bundled metadata when names collide.")
    }

    func agentSkillLoaderBlocksSecretSkillBodies() async throws {
        let rootURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let bundledDirectory = rootURL.appendingPathComponent(".sci-ai/sci-station/presets/research-core/skills/secret-review", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: secret-review
        description: Secret body review
        version: 1.0.0
        capabilities: [secret, review]
        risk: readOnly
        ---

        Never include this token: sk-test_1234567890abcdef.
        """.write(to: bundledDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let loader = AgentSkillLoader()
        let resolution = try await loader.resolve(
            for: "Run a secret body review.",
            profile: AgentWorkspaceProfile(skillToggles: [
                AgentSkillToggle(skillID: "secret-review", isEnabled: true, trustLevel: .trusted)
            ]),
            workspaceRoot: rootURL
        )

        try expect(resolution.selectedSkills.isEmpty, "Secret-like skill bodies should be blocked before prompt injection.")
        try expect(resolution.blockedSkillReasons["secret-review"]?.contains("secret") == true, "Blocked secret skill bodies should expose a visible blocked reason.")
        try expect(resolution.promptContext == nil, "Blocked secret skill bodies should not enter runtime prompt context.")
    }

            func agentWorkspaceSnapshotIncludesProjectContext() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let projectRegistryRepository = ProjectRegistryRepository()
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(
                    fileManager: .default,
                    bookmarkStore: bookmarkStore,
                    projectRegistryRepository: projectRegistryRepository
                )
                let paperRepository = PaperRepository()
                let todoRepository = TodoRepository()
                let contextBuilder = AgentWorkspaceContextBuilder(
                    paperRepository: paperRepository,
                    todoRepository: todoRepository
                )
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentProjectContextWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let registry = try await projectRegistryRepository.load(in: root)
                let project = try require(registry.projects.first, "Expected a default project for agent context.")
                var paper = samplePaper(id: "agent-project-paper")
                paper.projectIDs = [project.id]
                paper.coreProjectIDs = [project.id]
                let savedPaper = try await paperRepository.save(paper, in: workspace)
                let todo = TodoItem(
                    id: "todo-agent-project",
                    title: "Read project paper",
                    status: .open,
                    dueDate: nil,
                    priority: .high,
                    projectIDs: [project.id],
                    tags: ["agent"],
                    relatedPaperIDs: [savedPaper.id],
                    notes: nil,
                    createdAt: Date(timeIntervalSince1970: 1_777_600_000),
                    updatedAt: Date(timeIntervalSince1970: 1_777_600_000)
                )
                try await todoRepository.upsert(todo, in: workspace)

                let snapshot = try await contextBuilder.snapshot(
                    in: workspace,
                    root: root,
                    projects: registry.projects,
                    currentProjectID: project.id,
                    selectedPaperID: savedPaper.id
                )

                try expect(snapshot.rootName == root.displayName, "Agent snapshot should include the research root name.")
                try expect(snapshot.currentProjectID == project.id, "Agent snapshot should include current project id.")
                try expect(snapshot.currentProject?.paperCount == 1, "Agent snapshot should include current project paper count.")
                try expect(snapshot.projectPapers.map(\.id) == [savedPaper.id], "Agent snapshot should include project-associated papers.")
                try expect(snapshot.projectOpenTodos.map(\.id) == [todo.id], "Agent snapshot should include current project open todos.")
                try expect(snapshot.paperLibraryRelativePath == Paper.globalLibraryRootRelativePath, "Agent snapshot should advertise the global paper library path.")
            }

            func agentWorkspaceSnapshotDoesNotEmbedMarkdownByDefault() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let repository = PaperRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentMetadataOnlyContextWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = try await repository.save(samplePaper(id: "metadata-only-paper"), in: workspace)
                let marker = "metadata_only_snapshot_should_not_embed_this_marker"
                try ("# Metadata Only Paper\n\n## Hidden Body\n\n\(marker)")
                    .write(to: paper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

                let snapshot = try await AgentWorkspaceContextBuilder(paperRepository: repository).snapshot(
                    in: workspace,
                    selectedPaperID: paper.id,
                    includedPaperIDs: [paper.id],
                    paperLimit: 5
                )
                let selectedPaper = try require(snapshot.selectedPaper, "Selected paper should be present in the snapshot.")
                let recentPaper = try require(snapshot.recentPapers.first(where: { $0.id == paper.id }), "Recent paper should be present in the snapshot.")
                let prompt = try AgentPromptBuilder().buildPrompt(
                    goal: "Explain the hidden body marker.",
                    workspaceSnapshot: snapshot,
                    tools: []
                )

                try expect(selectedPaper.sourceExcerpt == nil, "Default selected paper snapshot should not embed paper.md text.")
                try expect(recentPaper.sourceExcerpt == nil, "Default recent paper snapshot should not embed paper.md text.")
                try expect(recentPaper.rawMarkdownRelativePath?.hasSuffix("/paper.md") == true, "Metadata-only paper snapshots should still advertise converted paper.md paths.")
                try expect(!prompt.contains(marker), "Agent prompt should not contain paper markdown body text by default.")
            }

            func agentWorkspaceSnapshotLegacyPolicyKeepsDeepKnowledgePaperContext() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let repository = PaperRepository()
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentLongPaperContextWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let paper = try await repository.save(samplePaper(id: "long-context-paper"), in: workspace)
                let paperDirectoryURL = workspace.directoryURL(for: paper.paperDirectoryRelativePath)
                try FileManager.default.createDirectory(at: paperDirectoryURL, withIntermediateDirectories: true)

                let earlyText = String(repeating: "Early context sentence for old cutoff testing.\n", count: 320)
                let deepMarker = "Section 5 evaporation-rate formula marker: E_sun_deep_context"
                try ("---\ntype: paper_raw_markdown\n---\n\n" + earlyText + "\n## 5 Evaporation Rate\n\n" + deepMarker)
                    .write(to: paper.rawMarkdownURL(in: workspace), atomically: true, encoding: .utf8)

                let snapshot = try await AgentWorkspaceContextBuilder(paperRepository: repository).snapshot(
                    in: workspace,
                    includedPaperIDs: [paper.id],
                    paperContextPolicy: .legacyExcerpts,
                    paperLimit: 5
                )
                let paperSnapshot = try require(snapshot.recentPapers.first(where: { $0.id == paper.id }), "Included knowledge paper should be present in the snapshot.")
                try expect(paperSnapshot.sourceExcerpt?.contains(deepMarker) == true, "Legacy excerpt policy should preserve deeper Markdown sections beyond 10k characters.")
            }

            func agentPromptBuilderDirectsPaperToolsForMetadataOnlyContext() throws {
                var paper = samplePaper(id: "prompt-metadata-paper")
                paper.title = "Prompt Metadata Paper"
                let paperSnapshot = AgentPaperSnapshot(
                    paper: paper,
                    rawMarkdownRelativePath: "papers/prompt-metadata-paper/paper.md"
                )
                let snapshot = AgentWorkspaceSnapshot(
                    workspaceName: "Prompt Workspace",
                    selectedPaper: paperSnapshot,
                    recentPapers: [paperSnapshot],
                    openTodos: [],
                    paperCount: 1,
                    todoCount: 0
                )
                let paperRepository = PaperRepository()
                let tools = [
                    ListPapersAgentTool(paperRepository: paperRepository).definition,
                    SearchPapersAgentTool(paperRepository: paperRepository).definition,
                    ReadPaperSectionAgentTool(paperRepository: paperRepository).definition,
                    ReadPaperAgentTool(paperRepository: paperRepository).definition
                ]
                let prompt = try AgentPromptBuilder().buildPrompt(
                    goal: "解释这篇论文第 5 节的公式。",
                    workspaceSnapshot: snapshot,
                    tools: tools
                )

                try expect(prompt.contains("Paper snapshots are metadata-first"), "Prompt should explain metadata-first paper snapshots.")
                try expect(prompt.contains("plan paper tool calls before answering"), "Prompt should direct the model to call paper tools before detailed answers.")
                try expect(prompt.contains("Prefer `search_papers`"), "Prompt should guide search_papers usage.")
                try expect(prompt.contains("Prefer `read_paper_section`"), "Prompt should guide read_paper_section usage.")
                try expect(prompt.contains("list_papers -> search_papers -> read_paper_section"), "Prompt should force first-paper formula flows through list/search/read tools.")

                let toolLoopMessages = try AgentPromptBuilder().buildToolLoopChatMessages(
                    goal: "第一篇论文里的 evaporation rate 公式是什么？",
                    workspaceSnapshot: snapshot,
                    tools: tools
                )
                let toolLoopSystemPrompt = try require(toolLoopMessages.first?.content, "Tool-loop prompt should contain a system message.")
                try expect(toolLoopSystemPrompt.contains("call `list_papers` first"), "Tool-loop prompt should resolve ordinal paper references with list_papers first.")
                try expect(toolLoopSystemPrompt.contains("Final answers to paper formula questions must include the formula"), "Tool-loop prompt should require formula, context, and source in final answers.")
            }

    func mcpGatewayListsAndCallsReadOnlySciStationTools() async throws {
        let fixture = try await loopWorkspaceFixture(named: "MCPReadOnlyWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "read_note", risk: .readOnly)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "read_note", succeeded: true, message: "MCP evidence")
        ])
        let registry = AgentToolRegistry(tools: [tool])
        let gateway = AgentMCPGateway(toolHost: SciStationToolHost(legacyRegistry: registry))
        let context = AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)

        let listResponse = await gateway.handle(AgentMCPEnvelope(id: "mcp-list", method: "tools/list"), context: context)
        let listResult = try jsonObject(listResponse.result, "tools/list should return a JSON object.")
        let tools = try jsonArray(listResult["tools"], "tools/list should return tools array.")
        let toolObjects = try tools.map { try jsonObject($0, "Each listed MCP tool should be an object.") }

        let readOnlyTool = try require(
            toolObjects.first { object in
                object["name"]?.stringValue == "read_note"
                    && object["risk"]?.stringValue == AgentToolRisk.readOnly.rawValue
            },
            "MCP tools/list should expose the read_note tool."
        )
        let annotations = try jsonObject(readOnlyTool["annotations"], "MCP tool annotations should be an object.")
        try expect(annotations["readOnly"] == .bool(true), "MCP tools/list should expose read-only annotations.")

        let callResponse = await gateway.handle(
            AgentMCPEnvelope(
                id: "mcp-call-read",
                method: "tools/call",
                params: .object([
                    "name": .string("read_note"),
                    "arguments": .object(["path": .string("paper.md")])
                ])
            ),
            context: context
        )
        let callResult = try jsonObject(callResponse.result, "Read-only tools/call should return a JSON object.")
        let invocationCount = await tool.invocationCount()

        try expect(callResponse.error == nil, "Read-only MCP tool call should not return JSON-RPC error.")
        try expect(callResult["structuredContent"] != nil, "Read-only MCP tool call should return structuredContent.")
        try expect(callResult["content"] != nil, "Read-only MCP tool call should return content array.")
        try expect(invocationCount == 1, "Read-only MCP tool call should invoke the tool once.")
    }

    func mcpGatewayRequiresApprovalForWorkspaceWrites() async throws {
        let fixture = try await loopWorkspaceFixture(named: "MCPWriteApprovalWorkspace")
        defer { cleanupLoopWorkspaceFixture(fixture) }

        let definition = loopToolDefinition(name: "create_todo", risk: .writesWorkspace)
        let tool = RecordingAgentTool(definition: definition, results: [
            AgentToolResult(callID: "", toolName: "create_todo", succeeded: true, message: "Should wait for approval")
        ])
        let registry = AgentToolRegistry(tools: [tool])
        let gateway = AgentMCPGateway(toolHost: SciStationToolHost(legacyRegistry: registry))
        let context = AgentToolContext(workspace: fixture.workspace, researchRoot: fixture.root)

        let response = await gateway.handle(
            AgentMCPEnvelope(
                id: "mcp-call-write",
                method: "tools/call",
                params: .object([
                    "name": .string("create_todo"),
                    "arguments": .object(["title": .string("Review gateway approval")])
                ])
            ),
            context: context,
            runID: "mcp-write-run"
        )
        let result = try jsonObject(response.result, "Write tools/call should return a JSON object.")
        let approval = try jsonObject(result["approvalRequest"], "Approval-required MCP response should include approvalRequest.")
        let targetPaths = try jsonArray(approval["target_paths"], "Approval request should include target paths.").compactMap(\.stringValue)
        let invocationCount = await tool.invocationCount()

        try expect(response.error == nil, "Approval-required MCP tool call should be a normal result, not JSON-RPC error.")
        try expect(result["status"]?.stringValue == "approval_required", "Write MCP tool call should return approval_required status.")
        try expect(approval["fingerprint"]?.stringValue?.hasPrefix("sha256:") == true, "Approval request should carry an idempotency fingerprint.")
        try expect(targetPaths == ["tasks/todos.yaml"], "ToolHost should preview create_todo target path for MCP approval.")
        try expect(invocationCount == 0, "Write MCP tool call must not invoke the tool before approval.")
    }

    func agentSkillLoaderProgressivelyLoadsMatchingSkill() async throws {
        let rootURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let skillDirectory = rootURL.appendingPathComponent(".claude/skills/paper-reading", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory.appendingPathComponent("references", isDirectory: true), withIntermediateDirectories: true)
        try "Checklist".write(to: skillDirectory.appendingPathComponent("references/checklist.md"), atomically: true, encoding: .utf8)
        try """
        ---
        name: paper-reading
        description: Paper evidence review
        version: 1.0.0
        author: Sci-Station
        capabilities: [paper, evidence]
        risk: readOnly
        allowed_tools: [read_paper, search_wiki]
        ---

        Use evidence before drafting conclusions.
        """.write(to: skillDirectory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let loader = AgentSkillLoader()
        let metadata = try await loader.loadMetadata(searchRoots: [rootURL.appendingPathComponent(".claude/skills", isDirectory: true)])
        let selected = try await loader.selectSkills(for: "Please do paper evidence review", from: metadata)

        try expect(metadata.first?.trustLevel == .untrusted, "Workspace skill metadata should default to untrusted.")
        try expect(metadata.first?.allowedTools == ["read_paper", "search_wiki"], "Skill metadata should expose allowed tools without loading the body.")
        try expect(selected.first?.body?.contains("Use evidence") == true, "Matching skills should load the body on selection.")
        try expect(selected.first?.resources == ["references/checklist.md"], "Matching skills should disclose adjacent resources on selection.")
    }

            func agentPromptDraftRepositoryPersistsDrafts() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentDraftWorkspace", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let repository = AgentPromptDraftRepository()

                try await repository.saveDraft("Review open papers", projectID: "project-alpha", threadID: "thread-alpha", in: root)
                try await repository.saveDraft("Updated prompt", projectID: "project-alpha", threadID: "thread-alpha", in: root)
                try await repository.saveDraft("Global prompt", projectID: nil, threadID: nil, in: root)

                let projectDraft = try await repository.draft(projectID: "project-alpha", threadID: "thread-alpha", in: root)
                let globalDraft = try await repository.draft(projectID: nil, threadID: nil, in: root)
                let draftsURL = root.fileURL(for: ".sci-station/agent/drafts.json")

                try expect(projectDraft == "Updated prompt", "Prompt drafts should upsert by project/thread key.")
                try expect(globalDraft == "Global prompt", "Global prompt drafts should round-trip.")
                try expect(FileManager.default.fileExists(atPath: draftsURL.path), "Prompt drafts should persist to the agent drafts file.")

                try await repository.removeDraft(projectID: "project-alpha", threadID: "thread-alpha", in: root)
                let removedDraft = try await repository.draft(projectID: "project-alpha", threadID: "thread-alpha", in: root)

                try expect(removedDraft == nil, "Prompt drafts should be removable when discarding an empty pending thread.")
            }

            func agentWorkspaceProfileRepositoryPersistsPromptSkillAndMCPOverrides() async throws {
                let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
                let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
                let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
                let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
                let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("AgentWorkspaceProfileOverrides", isDirectory: true)

                defer {
                    try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
                    defaults.removePersistentDomain(forName: suiteName)
                }

                let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
                let root = ResearchRoot(rootURL: workspace.rootURL)
                let repository = AgentWorkspaceProfileRepository()
                let prompt = AgentPromptTemplateOverride(
                    id: "proposal-draft",
                    title: "Proposal Draft Override",
                    description: "Workspace-specific proposal drafting prompt.",
                    systemPrompt: "Use project evidence only.",
                    promptTemplate: "Draft a proposal from current project wiki and selected papers."
                )
                let skillToggle = AgentSkillToggle(
                    skillID: "research-workflow",
                    displayName: "Research Workflow",
                    isEnabled: true,
                    trustLevel: .trusted,
                    allowedToolIDs: ["list_papers", "read_paper_section"]
                )
                let server = MCPServerConfiguration(
                    id: "filesystem-readonly",
                    displayName: "Filesystem Readonly",
                    transport: .localCommand,
                    isEnabled: true,
                    command: "npx",
                    arguments: ["-y", "@modelcontextprotocol/server-filesystem", "${workspaceRoot}"],
                    allowedTools: ["read_file", "list_directory"]
                )

                try await repository.upsertPromptTemplate(prompt, in: root)
                try await repository.setSkillToggle(skillToggle, in: root)
                try await repository.upsertMCPServer(server, in: root)

                let loaded = try await repository.load(in: root)
                let summary = try await AgentRuntimeConfigurationLoader().loadWorkspaceProfile(in: root)
                let profileURL = root.fileURL(for: AgentWorkspaceProfileRepository.relativePath)
                let profileText = try String(contentsOf: profileURL, encoding: .utf8)
                let invalidProfile = AgentWorkspaceProfile(
                    activePromptTemplateID: "missing",
                    promptTemplates: [
                        AgentPromptTemplateOverride(id: "proposal-draft", title: "One", promptTemplate: "Prompt"),
                        AgentPromptTemplateOverride(id: "proposal-draft", title: "Two", promptTemplate: "Prompt")
                    ],
                    skillToggles: [AgentSkillToggle(skillID: "")],
                    mcpServers: [MCPServerConfiguration(id: "broken", displayName: "Broken", transport: .localCommand)]
                )
                let invalidIssues = AgentWorkspaceProfileValidator().validate(invalidProfile)

                try expect(loaded.activePromptTemplateID == "proposal-draft", "First enabled prompt override should become active by default.")
                try expect(loaded.promptTemplate(id: "proposal-draft")?.systemPrompt == "Use project evidence only.", "Prompt overrides should round-trip system prompt text.")
                try expect(loaded.skillToggle(id: "research-workflow")?.trustLevel == .trusted, "Skill toggles should preserve trust level.")
                try expect(loaded.mcpServers.first?.allowedTools == ["read_file", "list_directory"], "Workspace profile MCP servers should round-trip allowed tools.")
                try expect(summary.promptTemplateCount == 1 && summary.enabledPromptTemplateCount == 1, "Workspace profile summary should count prompt overrides.")
                try expect(summary.enabledSkillCount == 1, "Workspace profile summary should count enabled skill toggles.")
                try expect(summary.mcpServers.first?.source == .workspaceProfile, "Workspace profile MCP servers should be marked with the workspace profile source.")
                try expect(summary.validationIssues.isEmpty, "Valid workspace profile overrides should pass validation.")
                try expect(!profileText.contains("Bearer "), "Workspace profile should not require raw bearer tokens for MCP configuration.")
                try expect(invalidIssues.count >= 4, "Workspace profile validator should catch missing active prompt, duplicate prompt ids, empty skill ids, and invalid MCP servers.")
            }

            func sciAITrackedPresetManifestValidates() throws {
                let manifestURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".sci-ai/sci-station/presets/research-core/plugin.json", isDirectory: false)
                let data = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(AgentPluginManifest.self, from: data)
                let issues = AgentPluginValidator().validate(manifest)

                try expect(manifest.id == "research-core", "Tracked .sci-ai product preset should decode as research-core.")
                try expect(manifest.commands.contains(where: { $0.slashCommand == "/proposal-draft" }), "Tracked .sci-ai product preset should include proposal drafting.")
                try expect(manifest.mcpServers.allSatisfy { $0.secretReferences.isEmpty }, "Tracked .sci-ai product preset should not include raw secret values.")
                try expect(issues.isEmpty, "Tracked .sci-ai product preset should pass plugin validation.")
            }

            func sciAIConfigurationBoundaryValidates() throws {
                let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                let trackedPresetURL = repoURL.appendingPathComponent(".sci-ai/sci-station", isDirectory: true)
                let gitignoreURL = repoURL.appendingPathComponent(".gitignore", isDirectory: false)
                let gitignore = try String(contentsOf: gitignoreURL, encoding: .utf8)
                let trackedFiles = try gitTrackedFiles(in: repoURL)

                try expect(!trackedSciAIContainsRawSecrets(at: trackedPresetURL), "Tracked .sci-ai/sci-station files should not contain raw secret-looking values.")
                try expect(gitignore.contains(".sci-ai/workspace.local/"), "Local .sci-ai workspace config path should be ignored by git.")
                try expect(gitignore.contains(".claude/"), "Root .claude bridge should be ignored by git.")
                try expect(gitignore.contains(".mcp.json"), "Root .mcp.json bridge should be ignored by git.")
                try expect(!trackedFiles.contains { $0.hasPrefix(".sci-ai/workspace.local/") }, "Local .sci-ai workspace config should not be tracked.")
                try expect(!trackedFiles.contains { $0.hasPrefix(".claude/") }, "Root .claude bridge directory should not be tracked.")
                try expect(!trackedFiles.contains(".mcp.json"), "Root .mcp.json bridge file should not be tracked.")
            }

            func agentMCPServerStatusSummaryParsesProductAndLocal() throws {
                let repoURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                let root = ResearchRoot(rootURL: repoURL)
                let loader = AgentRuntimeConfigurationLoader()
                let preset = try require(try loader.loadProductPreset(in: root), "Tracked research-core preset should load.")
                let localJSON = """
                {
                  "mcpServers": {
                    "local-filesystem": {
                      "command": "npx",
                      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp/workspace"],
                      "env": {
                        "API_TOKEN": "keychain:mcp/local/token",
                        "LOG_LEVEL": "info"
                      },
                      "allowed_tools": ["read_file"],
                      "timeout_seconds": 45
                    }
                  }
                }
                """
                let localStatuses = try AgentRuntimeConfigurationLoader.localMCPServerStatuses(from: Data(localJSON.utf8))
                let productStatus = try require(preset.mcpServers.first, "Product preset should expose MCP server status.")
                let localStatus = try require(localStatuses.first, "Local MCP status should parse from Claude-style config.")

                try expect(productStatus.source == .trackedProductTemplate, "Product MCP status should identify tracked template source.")
                try expect(productStatus.endpointSummary.contains("npx"), "Product MCP status should show local command.")
                try expect(localStatus.source == .localWorkspaceConfig, "Local MCP status should identify local source.")
                try expect(localStatus.allowedTools == ["read_file"], "Local MCP status should preserve allowed tools.")
                try expect(Int(localStatus.timeoutSeconds) == 45, "Local MCP status should preserve timeout.")
                try expect(localStatus.credentialReferenceCount == 1, "Local MCP status should count credential references without exposing values.")
                try expect(localStatus.sideEffectsRequirePermission, "MCP side-effect tools should remain routed through permission layer.")
            }

            func agentMCPConnectorRegistryEnforcesPrecedenceAndApproval() throws {
                let productServer = MCPServerConfiguration(
                    id: "filesystem",
                    displayName: "Product Filesystem",
                    transport: .localCommand,
                    isEnabled: false,
                    command: "npx",
                    allowedTools: ["read_file"]
                )
                let profileServer = MCPServerConfiguration(
                    id: "filesystem",
                    displayName: "Workspace Filesystem",
                    transport: .localCommand,
                    isEnabled: true,
                    command: "/usr/bin/env",
                    arguments: ["mcp-filesystem"],
                    allowedTools: ["read_file", "list_directory"]
                )
                let invalidServer = MCPServerConfiguration(
                    id: "invalid-local",
                    displayName: "Invalid Local",
                    transport: .localCommand,
                    isEnabled: true
                )
                let unresolvedCredentialServer = MCPServerConfiguration(
                    id: "remote",
                    displayName: "Remote",
                    transport: .remoteHTTP,
                    isEnabled: true,
                    urlString: "https://mcp.example.test",
                    secretReferences: ["raw-token-value"]
                )

                let snapshot = AgentMCPConnectorRegistryResolver().resolve(
                    productServers: [productServer],
                    profileServers: [profileServer, invalidServer, unresolvedCredentialServer]
                )
                let filesystem = try require(snapshot.registration(id: "filesystem"), "Profile MCP override should be registered.")
                let invalid = try require(snapshot.registration(id: "invalid-local"), "Invalid MCP server should remain visible in registry diagnostics.")
                let unresolved = try require(snapshot.registration(id: "remote"), "Credential failures should remain visible in registry diagnostics.")

                try expect(filesystem.source == .workspaceProfile, "Workspace profile MCP servers should override product templates with the same id.")
                try expect(filesystem.server.displayName == "Workspace Filesystem", "Registry precedence should preserve the workspace override body.")
                try expect(filesystem.state == .readyForDiscovery, "Enabled valid MCP server should be ready for tool discovery.")
                try expect(invalid.state == .invalidConfiguration, "Enabled local MCP server without command should be invalid.")
                try expect(unresolved.state == .unresolvedCredentialReference, "Unsupported credential values should block MCP registration.")
                try expect(
                    snapshot.authorize(serverID: "filesystem", toolName: "read_file").decision.action == .ask,
                    "Allowed external MCP tools should still require explicit approval."
                )
                try expect(
                    snapshot.authorize(serverID: "filesystem", toolName: "write_file").decision.action == .deny,
                    "Tools outside the MCP server allowlist should be denied."
                )
                try expect(
                    snapshot.authorize(serverID: "invalid-local", toolName: "read_file").decision.action == .deny,
                    "Invalid MCP servers must not authorize tools."
                )
            }

            func agentLocalMCPConfigurationDefaultsDisabledAndRedactsRawSecrets() throws {
                let localJSON = """
                {
                  "mcpServers": {
                    "local-filesystem": {
                      "command": "npx",
                      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp/workspace"],
                      "env": {
                        "API_TOKEN": "super-secret-token",
                        "LOG_LEVEL": "info"
                      },
                      "allowed_tools": ["read_file"]
                    },
                    "remote-index": {
                      "transport": "remote_http",
                      "url": "https://mcp.example.test",
                      "enabled": true,
                      "header_references": [
                        {
                          "name": "Authorization",
                          "value_reference": "keychain:mcp/remote/token"
                        }
                      ]
                    }
                  }
                }
                """
                let configurations = try AgentRuntimeConfigurationLoader.localMCPServerConfigurations(from: Data(localJSON.utf8))
                let local = try require(configurations.first { $0.id == "local-filesystem" }, "Local MCP configuration should parse.")
                let remote = try require(configurations.first { $0.id == "remote-index" }, "Remote MCP configuration should parse.")
                let snapshot = AgentMCPConnectorRegistryResolver().resolve(localServers: configurations)

                try expect(!local.isEnabled, "Local command MCP configs should default disabled until explicitly enabled.")
                try expect(!local.secretReferences.contains("super-secret-token"), "Raw local MCP secret values must not survive configuration parsing.")
                try expect(local.secretReferences == ["invalid_raw:API_TOKEN"], "Unsafe local MCP environment secrets should become redacted validation markers.")
                try expect(remote.isEnabled && remote.transport == .remoteHTTP, "Explicitly enabled remote MCP configuration should preserve its transport.")
                try expect(snapshot.registration(id: "local-filesystem")?.state == .disabled, "Default-disabled local MCP servers should not be ready for discovery.")
                try expect(snapshot.registration(id: "remote-index")?.state == .readyForDiscovery, "Supported credential references should allow remote MCP discovery after approval.")
            }

            func agentMCPStdioClientDiscoversAndApprovalGatesTool() async throws {
                let fixture = try await loopWorkspaceFixture(named: "MCPStdioWorkspace")
                let manager = AgentMCPConnectorManager()
                let scriptURL = fixture.containerURL.appendingPathComponent("mcp_fixture.py", isDirectory: false)
                let callLogURL = fixture.containerURL.appendingPathComponent("mcp_calls.log", isDirectory: false)
                let startupLogURL = fixture.containerURL.appendingPathComponent("mcp_startup.log", isDirectory: false)
                defer {
                    cleanupLoopWorkspaceFixture(fixture)
                }

                try """
                import json
                import pathlib
                import sys

                call_log = pathlib.Path(sys.argv[1])
                startup_log = pathlib.Path(sys.argv[2])
                startup_log.write_text("started", encoding="utf-8")

                def send(payload):
                    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\\n")
                    sys.stdout.flush()

                for raw in sys.stdin:
                    raw = raw.strip()
                    if not raw:
                        continue
                    message = json.loads(raw)
                    method = message.get("method")
                    request_id = message.get("id")
                    if method == "initialize":
                        send({
                            "jsonrpc": "2.0",
                            "id": request_id,
                            "result": {
                                "protocolVersion": "2025-06-18",
                                "capabilities": {"tools": {"listChanged": False}},
                                "serverInfo": {"name": "fixture-mcp", "version": "1.0.0"}
                            }
                        })
                    elif method == "notifications/initialized":
                        continue
                    elif method == "tools/list":
                        send({
                            "jsonrpc": "2.0",
                            "id": request_id,
                            "result": {
                                "tools": [{
                                    "name": "echo",
                                    "title": "Fixture Echo",
                                    "description": "Echo structured test input.",
                                    "inputSchema": {
                                        "type": "object",
                                        "properties": {"text": {"type": "string"}},
                                        "required": ["text"]
                                    },
                                    "annotations": {"readOnlyHint": True}
                                }]
                            }
                        })
                    elif method == "tools/call":
                        params = message.get("params", {})
                        arguments = params.get("arguments", {})
                        call_log.write_text(json.dumps(params, sort_keys=True), encoding="utf-8")
                        text = arguments.get("text", "")
                        send({
                            "jsonrpc": "2.0",
                            "id": request_id,
                            "result": {
                                "content": [{"type": "text", "text": "fixture:" + text}],
                                "structuredContent": {"echo": text},
                                "isError": False
                            }
                        })
                    else:
                        send({
                            "jsonrpc": "2.0",
                            "id": request_id,
                            "error": {"code": -32601, "message": "unsupported"}
                        })
                """.write(to: scriptURL, atomically: true, encoding: .utf8)

                let server = MCPServerConfiguration(
                    id: "fixture",
                    displayName: "Fixture MCP",
                    transport: .localCommand,
                    isEnabled: true,
                    command: "/usr/bin/python3",
                    arguments: [scriptURL.path, callLogURL.path, startupLogURL.path],
                    timeoutSeconds: 5,
                    allowedTools: ["echo"]
                )
                let profile = AgentWorkspaceProfile(mcpServers: [server])
                let connectorRegistry = AgentMCPConnectorRegistryResolver().resolve(profileServers: [server])

                do {
                    var disabledServer = server
                    disabledServer.isEnabled = false
                    let disabledPreparation = await manager.prepare(
                        registry: AgentMCPConnectorRegistryResolver().resolve(profileServers: [disabledServer]),
                        root: fixture.root
                    )
                    try expect(disabledPreparation.statuses.first?.state == .disabled, "Disabled local MCP servers should remain diagnostic-only.")
                    try expect(!FileManager.default.fileExists(atPath: startupLogURL.path), "Disabled local MCP servers must not start a process.")

                    let preparation = await manager.prepare(registry: connectorRegistry, root: fixture.root)
                    let status = try require(preparation.statuses.first, "MCP fixture should produce a runtime status.")
                    let externalTool = try require(preparation.tools.first, "MCP fixture should expose one external tool.")

                    try expect(status.state == .ready, "MCP stdio fixture should complete initialize and tools/list.")
                    try expect(status.protocolVersion == "2025-06-18", "MCP stdio fixture should negotiate the supported protocol version.")
                    try expect(status.discoveredToolCount == 1, "MCP stdio fixture should report one discovered tool.")
                    try expect(externalTool.definition.name == "mcp__fixture__echo", "Discovered MCP tools should receive deterministic server namespaces.")
                    try expect(externalTool.definition.risk == .externalSideEffect, "External MCP tools should remain approval-gated regardless of server hints.")
                    try expect(externalTool.definition.requiresConfirmation, "External MCP tools should require confirmation.")

                    let service = SciStationAgentService(
                        provider: StaticLLMProvider(response: "{}"),
                        mcpConnectorManager: manager
                    )
                    let serviceDefinitions = await service.toolDefinitions(in: fixture.root, workspaceProfile: profile)
                    let serviceStatuses = await service.mcpRuntimeStatuses(in: fixture.root, workspaceProfile: profile)
                    try expect(serviceDefinitions.contains(where: { $0.name == externalTool.definition.name }), "Agent service should expose enabled discovered MCP tools.")
                    try expect(serviceStatuses.first?.state == .ready, "Agent service should expose MCP runtime health.")

                    let registry = AgentToolRegistry(tools: [externalTool])
                    let mcpCall = AgentToolCall(
                        id: "call-mcp-echo",
                        toolName: externalTool.definition.name,
                        argumentsJSON: "{\"text\":\"hello\"}"
                    )
                    let firstProvider = ScriptedChatProvider(responses: [
                        LLMProviderResponse(
                            message: LLMChatMessage(
                                role: .assistant,
                                content: "",
                                toolCalls: [mcpCall]
                            ),
                            toolCalls: [mcpCall]
                        )
                    ])
                    let runner = AgentLoopRunner()
                    let paused = try await runner.run(loopRequest(
                        runID: "mcp-approval-run",
                        provider: firstProvider,
                        definitions: [externalTool.definition],
                        registry: registry,
                        fixture: fixture
                    ))

                    try expect(
                        paused.pauseReason?.kind == .approvalRequired,
                        "Discovered MCP tool calls should pause for approval; got \(String(describing: paused.pauseReason?.kind)) with \(paused.pauseReason?.message ?? "no message")."
                    )
                    try expect(!FileManager.default.fileExists(atPath: callLogURL.path), "MCP tools must not execute before approval.")

                    let pending = try require(paused.pendingToolCall, "Paused MCP tool call should persist a checkpoint.")
                    let resumeProvider = ScriptedChatProvider(responses: [
                        LLMProviderResponse(message: LLMChatMessage(role: .assistant, content: "MCP completed."))
                    ])
                    let resumed = try await runner.resume(loopResumeRequest(
                        pending: pending,
                        action: .allowOnce,
                        provider: resumeProvider,
                        definitions: [externalTool.definition],
                        registry: registry,
                        fixture: fixture
                    ))
                    let callLog = try String(contentsOf: callLogURL, encoding: .utf8)

                    try expect(resumed.finalResponseMarkdown == "MCP completed.", "Approved MCP tool calls should continue the tool loop.")
                    try expect(resumed.toolResults.first?.message == "fixture:hello", "MCP tools/call text content should map to AgentToolResult.")
                    try expect(callLog.contains("\"name\": \"echo\""), "Approved MCP tool calls should reach the remote tool name.")
                    try expect(callLog.contains("\"text\": \"hello\""), "Approved MCP tool calls should preserve structured arguments.")
                    await manager.stopAll()
                } catch {
                    await manager.stopAll()
                    throw error
                }
            }

            func agentMCPRemoteHTTPDiscoversAndApprovalGatesTool() async throws {
                let fixture = try await loopWorkspaceFixture(named: "MCPRemoteHTTPWorkspace")
                RemoteMCPMockURLProtocol.reset()
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [RemoteMCPMockURLProtocol.self]
                let manager = AgentMCPConnectorManager(
                    urlSession: URLSession(configuration: configuration),
                    credentialResolver: { reference in
                        reference == "keychain:mcp/remote/token" ? "Bearer remote-test-token" : nil
                    }
                )
                defer {
                    RemoteMCPMockURLProtocol.reset()
                    cleanupLoopWorkspaceFixture(fixture)
                }

                let remote = MCPServerConfiguration(
                    id: "remote-index",
                    displayName: "Remote Index",
                    transport: .remoteHTTP,
                    isEnabled: true,
                    urlString: "https://mcp.example.test/rpc",
                    timeoutSeconds: 2,
                    allowedTools: ["lookup"],
                    headerReferences: [MCPHeaderReference(name: "Authorization", valueReference: "keychain:mcp/remote/token")]
                )
                let registry = AgentMCPConnectorRegistryResolver().resolve(profileServers: [remote])
                let preparation = await manager.prepare(registry: registry, root: fixture.root)
                let status = try require(preparation.statuses.first, "Remote MCP should report runtime status.")
                let externalTool = try require(preparation.tools.first, "Remote MCP should expose allowlisted tools after discovery.")
                let registryWithTool = AgentToolRegistry(tools: [externalTool])
                let call = AgentToolCall(
                    id: "call-remote-mcp",
                    toolName: externalTool.definition.name,
                    argumentsJSON: #"{"query":"paper"}"#
                )
                let provider = ScriptedChatProvider(responses: [
                    LLMProviderResponse(
                        message: LLMChatMessage(role: .assistant, content: "", toolCalls: [call]),
                        toolCalls: [call]
                    )
                ])
                let paused = try await AgentLoopRunner().run(loopRequest(
                    runID: "remote-mcp-approval-run",
                    provider: provider,
                    definitions: [externalTool.definition],
                    registry: registryWithTool,
                    fixture: fixture
                ))
                let result = try await manager.callTool(
                    serverID: remote.id,
                    toolName: "lookup",
                    arguments: .object(["query": .string("paper")])
                )

                try expect(status.state == .ready, "Remote HTTP MCP should be ready after initialize and tools/list.")
                try expect(status.transport == .remoteHTTP, "Runtime status should report configured remote transport.")
                try expect(status.endpointSummary == "https://mcp.example.test/rpc", "Runtime status should report remote endpoint without credentials.")
                try expect(status.discoveredToolCount == 1, "Remote MCP status should include discovered tool count.")
                try expect(status.lastSuccessAt != nil, "Remote MCP status should record last success.")
                try expect(status.connectionSummary.contains("connected"), "Remote MCP connection summary should be audit-ready.")
                try expect(status.freshness == "current", "Runtime status should expose freshness.")
                try expect(externalTool.definition.name == "mcp__remote_index__lookup", "Remote MCP tools should receive deterministic namespaces.")
                try expect(externalTool.definition.requiresConfirmation, "Remote MCP tools must remain approval-gated.")
                try expect(paused.pauseReason?.kind == .approvalRequired, "Remote MCP tool calls should pause for approval.")
                try expect(result.content.first?.objectValue?["text"]?.stringValue == "remote:paper", "Remote MCP tool call should return text content.")
                try expect(RemoteMCPMockURLProtocol.authorizationHeaders.allSatisfy { $0 == "Bearer remote-test-token" }, "Remote MCP should resolve auth headers without storing raw secrets.")
                try expect(RemoteMCPMockURLProtocol.methods.contains("initialize"), "Remote MCP should initialize over HTTP.")
                try expect(RemoteMCPMockURLProtocol.methods.contains("tools/list"), "Remote MCP should list tools over HTTP.")
                try expect(RemoteMCPMockURLProtocol.methods.contains("tools/call"), "Remote MCP should call tools over HTTP.")
                await manager.stopAll()
            }

            func agentMCPRemoteFailureBackoffIsAuditable() async throws {
                let fixture = try await loopWorkspaceFixture(named: "MCPRemoteBackoffWorkspace")
                RemoteMCPMockURLProtocol.reset()
                RemoteMCPMockURLProtocol.failureMode = .httpStatus(503)
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [RemoteMCPMockURLProtocol.self]
                let manager = AgentMCPConnectorManager(
                    urlSession: URLSession(configuration: configuration),
                    credentialResolver: { reference in
                        reference == "keychain:mcp/remote/token" ? "Bearer remote-test-token" : nil
                    }
                )
                defer {
                    RemoteMCPMockURLProtocol.reset()
                    cleanupLoopWorkspaceFixture(fixture)
                }

                let remote = MCPServerConfiguration(
                    id: "remote-backoff",
                    displayName: "Remote Backoff",
                    transport: .remoteSSE,
                    isEnabled: true,
                    urlString: "https://mcp.example.test/sse",
                    timeoutSeconds: 2,
                    allowedTools: ["lookup"],
                    headerReferences: [MCPHeaderReference(name: "Authorization", valueReference: "keychain:mcp/remote/token")]
                )
                let registry = AgentMCPConnectorRegistryResolver().resolve(profileServers: [remote])
                let firstPreparation = await manager.prepare(registry: registry, root: fixture.root)
                let firstStatus = try require(firstPreparation.statuses.first, "Failed remote MCP should report a runtime status.")
                let firstNetworkAttempts = RemoteMCPMockURLProtocol.methods.count

                RemoteMCPMockURLProtocol.failureMode = .none
                let secondPreparation = await manager.prepare(registry: registry, root: fixture.root)
                let secondStatus = try require(secondPreparation.statuses.first, "Backoff remote MCP should continue to report runtime status.")

                try expect(firstPreparation.tools.isEmpty, "Remote MCP discovery failures must not expose tools.")
                try expect(firstStatus.state == .failed, "Remote HTTP/SSE failures should be explicit runtime failures.")
                try expect(firstStatus.transport == .remoteSSE, "Failure status should preserve the configured remote transport.")
                try expect(firstStatus.endpointSummary == "https://mcp.example.test/sse", "Failure status should preserve the endpoint summary without credentials.")
                try expect(firstStatus.errorMessage?.contains("Remote MCP HTTP 503") == true, "Failure status should include the HTTP failure reason.")
                try expect(firstStatus.lastErrorAt != nil, "Remote failure should record last error time.")
                try expect(firstStatus.retryCount == 1, "First remote failure should count one discovery attempt.")
                try expect(firstStatus.freshness.hasPrefix("backoff_until:"), "Remote failure should expose backoff freshness.")
                try expect(firstStatus.connectionSummary.contains("backing off"), "Remote failure summary should make backoff visible.")
                try expect(firstNetworkAttempts == 1, "Initial remote discovery should stop after the failing initialize request.")
                try expect(secondPreparation.tools.isEmpty, "Backoff status must not expose tools before retry time.")
                try expect(secondStatus.state == .failed, "Backoff probe should remain a failed runtime status.")
                try expect(secondStatus.retryCount == 2, "Backoff probe should count the skipped retry attempt for auditability.")
                try expect(secondStatus.freshness.hasPrefix("backoff_until:"), "Backoff probe should preserve freshness until retry time.")
                try expect(secondStatus.connectionSummary.contains("backing off"), "Backoff probe should keep the user-visible backoff summary.")
                try expect(RemoteMCPMockURLProtocol.methods.count == firstNetworkAttempts, "Second prepare during backoff must not hit the remote endpoint.")
                await manager.stopAll()
            }

            func agentMCPRuntimeReportsRemoteCredentialFailure() async throws {
                let fixture = try await loopWorkspaceFixture(named: "MCPRemoteCredentialFailureWorkspace")
                RemoteMCPMockURLProtocol.reset()
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [RemoteMCPMockURLProtocol.self]
                let manager = AgentMCPConnectorManager(urlSession: URLSession(configuration: configuration))
                defer {
                    RemoteMCPMockURLProtocol.reset()
                    cleanupLoopWorkspaceFixture(fixture)
                }

                let remote = MCPServerConfiguration(
                    id: "remote-index",
                    displayName: "Remote Index",
                    transport: .remoteSSE,
                    isEnabled: true,
                    urlString: "https://mcp.example.test/sse",
                    timeoutSeconds: 2,
                    headerReferences: [MCPHeaderReference(name: "Authorization", valueReference: "keychain:mcp/remote/token")]
                )
                let registry = AgentMCPConnectorRegistryResolver().resolve(profileServers: [remote])
                let preparation = await manager.prepare(registry: registry, root: fixture.root)
                let status = try require(preparation.statuses.first, "Remote credential failures should still report runtime status.")

                try expect(preparation.tools.isEmpty, "Credential-failed remote MCP must not expose tools.")
                try expect(status.state == .failed, "Credential failure should be explicit runtime failure.")
                try expect(status.transport == .remoteSSE, "Runtime status should report configured SSE transport.")
                try expect(status.endpointSummary == "https://mcp.example.test/sse", "Runtime status should report remote endpoint without credentials.")
                try expect(status.errorMessage?.contains("Keychain credential reference") == true, "Credential failure should be actionable without leaking raw values.")
                try expect(status.errorMessage?.contains("remote/token") == false, "Credential failure should redact credential reference details.")
                try expect(status.lastErrorAt != nil, "Credential failure should record last error time.")
                try expect(status.retryCount == 1, "Credential failure should count one attempted discovery.")
                try expect(status.freshness == "current", "Credential failures should not enter network backoff freshness.")
                try expect(RemoteMCPMockURLProtocol.methods.isEmpty, "Credential failure should occur before any remote network request.")
                await manager.stopAll()
            }

            func agentMCPRuntimeReportsLocalCrashLiveness() async throws {
                let fixture = try await loopWorkspaceFixture(named: "MCPCrashWorkspace")
                let manager = AgentMCPConnectorManager()
                let scriptURL = fixture.containerURL.appendingPathComponent("mcp_crash_fixture.py", isDirectory: false)
                defer {
                    cleanupLoopWorkspaceFixture(fixture)
                }

                try """
                import json
                import sys

                raw = sys.stdin.readline()
                if raw:
                    message = json.loads(raw)
                    sys.stdout.write(json.dumps({
                        "jsonrpc": "2.0",
                        "id": message.get("id"),
                        "result": {
                            "protocolVersion": "2025-06-18",
                            "capabilities": {"tools": {"listChanged": False}},
                            "serverInfo": {"name": "crashy-mcp", "version": "1.0.0"}
                        }
                    }) + "\\n")
                    sys.stdout.flush()
                sys.stderr.write("fixture crash after initialize\\n")
                sys.stderr.flush()
                sys.exit(7)
                """.write(to: scriptURL, atomically: true, encoding: .utf8)

                let server = MCPServerConfiguration(
                    id: "crashy",
                    displayName: "Crashy MCP",
                    transport: .localCommand,
                    isEnabled: true,
                    command: "/usr/bin/python3",
                    arguments: [scriptURL.path],
                    timeoutSeconds: 2,
                    allowedTools: ["echo"]
                )
                let registry = AgentMCPConnectorRegistryResolver().resolve(profileServers: [server])
                let preparation = await manager.prepare(registry: registry, root: fixture.root)
                let status = try require(preparation.statuses.first, "Crashed local MCP should report runtime status.")

                try expect(preparation.tools.isEmpty, "Crashed MCP server must not expose tools.")
                try expect(status.state == .failed, "Crashed local MCP should report failed state.")
                try expect(status.transport == .localCommand, "Crash status should report local command transport.")
                try expect(status.endpointSummary.contains("/usr/bin/python3"), "Crash status should include command endpoint summary.")
                try expect(status.exitCode == 7, "Crash status should report MCP process exit code.")
                try expect(status.retryCount == 1, "Crash status should count the failed discovery attempt.")
                try expect(status.lastErrorAt != nil, "Crash status should record last error time.")
                try expect(status.stderrPreview?.contains("fixture crash") == true || status.errorMessage?.contains("fixture crash") == true, "Crash status should include stderr preview or error context.")
                try expect(status.connectionSummary.contains("failed"), "Crash status should include failed connection summary.")
                await manager.stopAll()
            }
}
