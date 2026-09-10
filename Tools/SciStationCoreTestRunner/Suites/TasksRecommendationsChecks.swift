import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runTasksRecommendations() async {
        await runCheck("todoRepositoryCreatesCompletesAndDeletesTodos") { try await todoRepositoryCreatesCompletesAndDeletesTodos() }
        await runCheck("recommendationConfigYAMLRoundTripsDailySourceSettings") { try recommendationConfigYAMLRoundTripsDailySourceSettings() }
        await runCheck("dailyFeedCandidateImporterMapsExternalArxivCandidates") { try dailyFeedCandidateImporterMapsExternalArxivCandidates() }
        await runCheck("recommendationScorerRanksByLibraryInterest") { try await recommendationScorerRanksByLibraryInterest() }
        await runCheck("recommendationPipelineWritesSnapshot") { try await recommendationPipelineWritesSnapshot() }
        await runCheck("recommendationPipelineHonorsCategoryHardBoundary") { try recommendationPipelineHonorsCategoryHardBoundary() }
        await runCheck("recommendationScorerV2SignalsKeywordSeedAndRecency") { try await recommendationScorerV2SignalsKeywordSeedAndRecency() }
        await runCheck("recommendationFeedbackStorePersistsJSONLAndBuildsProfile") { try await recommendationFeedbackStorePersistsJSONLAndBuildsProfile() }
        await runCheck("recommendationPipelineMMRDiversifiesNearDuplicateResults") { try recommendationPipelineMMRDiversifiesNearDuplicateResults() }
        await runCheck("recommendationRunResultDecodesLegacySnapshotWithV2Defaults") { try recommendationRunResultDecodesLegacySnapshotWithV2Defaults() }
        await runCheck("todoQueriesDeriveDateProjectSortAndOpenCount") { try todoQueriesDeriveDateProjectSortAndOpenCount() }
        await runCheck("todoDatePresetResolvesRelativeDates") { try todoDatePresetResolvesRelativeDates() }
        await runCheck("todoPriorityFlagMappingRoundTrips") { try todoPriorityFlagMappingRoundTrips() }
        await runCheck("todoRepositoryPersistsDateRange") { try await todoRepositoryPersistsDateRange() }
        await runCheck("todoTagRepositoryRoundTripsDefinitions") { try await todoTagRepositoryRoundTripsDefinitions() }
    }

    func todoRepositoryCreatesCompletesAndDeletesTodos() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(
            fileManager: .default,
            bookmarkStore: bookmarkStore
        )
        let repository = TodoRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("TodoWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let todo = TodoItem(
            id: "todo-001",
            title: "Read dark matter capture review",
            status: .open,
            dueDate: Date(timeIntervalSince1970: 1_777_680_000),
            priority: .urgent,
            projectIDs: ["project-alpha"],
            tags: ["Dark-Matter"],
            relatedPaperIDs: ["garani2024dark"],
            notes: "Check bibliography and equations.",
            externalSource: "apple_reminders",
            externalIdentifier: "reminder-abc",
            externalUpdatedAt: Date(timeIntervalSince1970: 1_777_600_000),
            completedAt: nil,
            dueTime: "09:30",
            createdAt: Date(timeIntervalSince1970: 1_777_593_600),
            updatedAt: Date(timeIntervalSince1970: 1_777_593_600)
        )

        try await repository.upsert(todo, in: workspace)

        var savedTodos = try await repository.loadTodos(in: workspace)
        try expect(savedTodos.count == 1, "Saving a todo should persist it to tasks/todos.yaml.")
        try expect(savedTodos.first?.priority == .urgent, "Todo repository should preserve priority.")
        try expect(savedTodos.first?.projectIDs == ["project-alpha"], "Todo repository should preserve project ids.")
        try expect(savedTodos.first?.notes == "Check bibliography and equations.", "Todo repository should preserve notes.")
        try expect(savedTodos.first?.relatedPaperIDs == ["garani2024dark"], "Todo repository should preserve related paper ids.")
        try expect(savedTodos.first?.externalSource == "apple_reminders", "Todo repository should preserve external source.")
        try expect(savedTodos.first?.externalIdentifier == "reminder-abc", "Todo repository should preserve external identifier.")
        try expect(savedTodos.first?.dueTime == "09:30", "Todo repository should preserve due time.")

        var completedTodo = try require(savedTodos.first, "Expected the saved todo to be loadable.")
        completedTodo.status = .done
        completedTodo.updatedAt = Date(timeIntervalSince1970: 1_777_680_000)
        try await repository.upsert(completedTodo, in: workspace)

        savedTodos = try await repository.loadTodos(in: workspace)
        try expect(savedTodos.first?.status == .done, "Updating a todo should replace the stored todo instead of duplicating it.")

        try await repository.delete(todoID: todo.id, in: workspace)
        let remainingTodos = try await repository.loadTodos(in: workspace)
        try expect(remainingTodos.isEmpty, "Deleting a todo should remove it from tasks/todos.yaml.")

                let legacyContents = """
                todos:
                    - id: "legacy-todo"
                        title: "Legacy task"
                        status: open
                        due:
                        priority: medium
                        tags: []
                        related_papers: []
                        created: 2026-04-28
                        updated: 2026-04-28
                """
                try legacyContents.write(to: workspace.fileURL(for: "tasks/todos.yaml"), atomically: true, encoding: .utf8)
                let legacyTodos = try await repository.loadTodos(in: workspace)
                try expect(legacyTodos.first?.projectIDs == [], "Todo repository should treat legacy todos without project_ids as unassigned.")
    }

    // MARK: - Tasks (TodoQueries)

    func recommendationConfigYAMLRoundTripsDailySourceSettings() throws {
        var config = RecommendationConfig()
        config.cadence = .daily
        config.scope = .workspace
        config.topK = 7
        config.externalNetworkEnabled = true
        config.maxDailyCandidates = 42
        config.weights.libraryInterestSimilarity = 0.55
        config.dailySources = [
            RecommendationDailySourceConfig(kind: .arxiv, enabled: true, categories: ["cs.AI", "cs.CL"], includeCrossList: true),
            RecommendationDailySourceConfig(kind: .biorxiv, enabled: false, categories: ["neuroscience"])
        ]

        let yaml = RecommendationConfigStore.encode(config)
        let decoded = try RecommendationConfigStore.decode(yaml)

        try expect(decoded.cadence == .daily, "Recommendation config should preserve cadence.")
        try expect(decoded.scope == .workspace, "Recommendation config should preserve scope.")
        try expect(decoded.topK == 7, "Recommendation config should preserve top_k.")
        try expect(decoded.externalNetworkEnabled, "Recommendation config should preserve external network opt-in.")
        try expect(decoded.maxDailyCandidates == 42, "Recommendation config should preserve max_daily_candidates.")
        try expect(decoded.weights.libraryInterestSimilarity == 0.55, "Recommendation config should preserve library-interest weight.")
        try expect(decoded.dailySources.first?.kind == .arxiv && decoded.dailySources.first?.enabled == true, "Daily source config should preserve arxiv enabled state.")
        try expect(decoded.dailySources.first?.categories == ["cs.AI", "cs.CL"], "Daily source config should preserve categories.")
        try expect(decoded.dailySources.first?.includeCrossList == true, "Daily source config should preserve include_cross_list.")
    }

    func dailyFeedCandidateImporterMapsExternalArxivCandidates() throws {
        let jsonl = """
        {"source":"arxiv","id":"2604.22012v1","title":"Graph Retrieval for Scientific Agents","authors":["Ada Lovelace","Grace Hopper"],"abstract":"Graph retrieval agents use literature libraries for recommendations.","published":"2026-04-20T00:00:00Z","categories":["cs.AI","cs.CL"],"url":"https://arxiv.org/abs/2604.22012","pdf_url":"https://arxiv.org/pdf/2604.22012.pdf"}
        """
        let candidates = try DailyFeedCandidateImporter().parseJSONLines(jsonl)
        let candidate = try require(candidates.first, "Importer should return one candidate.")

        try expect(candidate.canonicalID == "external:arxiv:2604.22012", "Importer should canonicalize arXiv external keys without version suffix.")
        try expect(candidate.externalKey == "arxiv:2604.22012", "Importer should preserve arXiv external_key.")
        try expect(candidate.publishedYear == 2026, "Importer should derive published year.")
        try expect(candidate.sourceTags == [.dailyFeed], "Importer should mark daily feed source.")
        try expect(candidate.abstractText?.contains("Graph retrieval") == true, "Importer should keep abstract in memory for scoring.")
    }

    func recommendationScorerRanksByLibraryInterest() async throws {
        var corePaper = samplePaper(id: "core-graph")
        corePaper.title = "Graph Retrieval Agents"
        corePaper.abstract = "Graph retrieval agents build literature maps for scientific recommendation."
        corePaper.tags = ["graph", "retrieval", "agents"]
        corePaper.coreProjectIDs = ["proj"]

        let matchingCandidate = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.22012",
            externalKey: "arxiv:2604.22012",
            displayTitle: "Graph Retrieval Agents for Literature Recommendation",
            authors: ["Ada Lovelace"],
            publishedYear: 2026,
            sourceTags: [.dailyFeed],
            categories: ["cs.AI"],
            abstractText: "Graph retrieval agents rank papers from a user library."
        )
        let unrelatedCandidate = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.00001",
            externalKey: "arxiv:2604.00001",
            displayTitle: "A Marine Biology Survey",
            publishedYear: 2026,
            sourceTags: [.dailyFeed],
            abstractText: "Coral reef ecology and ocean temperatures."
        )
        let context = RecommendationContext(
            projectID: "proj",
            corePaperIDs: ["core-graph"],
            openGapKeywords: ["retrieval"],
            interestPapers: [corePaper],
            evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
        let ranked = await RecommendationScorer().score([unrelatedCandidate, matchingCandidate], context: context, locale: .zh)

        try expect(ranked.first?.id == matchingCandidate.id, "Scorer should rank the candidate matching recent library interests first.")
        try expect(ranked.first?.features.libraryInterestSimilarity ?? 0 > 0, "Matching candidate should have nonzero library-interest similarity.")
        try expect(ranked.first?.reason.contains("匹配近期文献兴趣") == true, "Reason builder should localize the top signal in Chinese.")
    }

    func recommendationPipelineWritesSnapshot() async throws {
        let (rootURL, workspace) = try makeWorkspaceFixture("RecommendationPipelineWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        var interestPaper = samplePaper(id: "interest")
        interestPaper.title = "Graph Retrieval Agents"
        interestPaper.abstract = "Graph retrieval agents build literature maps for recommendation."
        interestPaper.updatedAt = Date(timeIntervalSince1970: 1_777_500_000)
        let daily = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.22012",
            externalKey: "arxiv:2604.22012",
            displayTitle: "Graph Retrieval Agents for Daily Literature",
            publishedYear: 2026,
            sourceTags: [.dailyFeed],
            sourceURL: "https://arxiv.org/abs/2604.22012",
            pdfURL: "https://arxiv.org/pdf/2604.22012.pdf",
            categories: ["cs.AI"],
            abstractText: "Graph retrieval agents rank daily arXiv papers from a local library."
        )
        let config = RecommendationConfig(topK: 1)
        let context = RecommendationContext(
            interestPapers: [interestPaper],
            evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
        let fixedDate = Date(timeIntervalSince1970: 1_777_700_000)
        let pipeline = RecommendationPipeline(dateProvider: { fixedDate })

        let result = try await pipeline.run(
            workspace: workspace,
            papers: [],
            dailyFeedCandidates: [daily],
            context: context,
            config: config,
            trigger: .manual,
            locale: .en
        )
        let run = try require(result, "Pipeline should produce a first recommendation run.")
        let skipped = try await pipeline.run(
            workspace: workspace,
            papers: [],
            dailyFeedCandidates: [daily],
            context: context,
            config: config,
            trigger: .manual,
            locale: .en
        )

        try expect(run.scores.count == 1, "Pipeline should keep topK scored recommendations.")
        try expect(skipped == nil, "Pipeline should skip the same candidate hash within 30 minutes.")
        let snapshotURL = workspace.fileURL(for: "\(RecommendationPipeline.notesRelativeDirectory)/\(run.id).json")
        let historyURL = workspace.fileURL(for: RecommendationPipeline.historyRelativePath)
        try expect(FileManager.default.fileExists(atPath: snapshotURL.path), "Pipeline should write a snapshot JSON file.")
        try expect(FileManager.default.fileExists(atPath: historyURL.path), "Pipeline should append recommendation history.")

        let payload = RecommendationPipeline.recommendationNotePayload(for: run, target: .workspace)
        let payloadObject = try jsonObject(payload, "Recommendation note payload should be an object.")
        let candidates = payloadObject["candidates"]?.arrayValue ?? []
        let firstCandidate = try jsonObject(candidates.first, "Payload should contain a candidate object.")
        try expect(payloadObject["kind"]?.stringValue == "recommendation_note", "Payload kind should match the recommendation note contract.")
        try expect(payloadObject["scope"]?.stringValue == "workspace", "Payload should include scope.")
        try expect(firstCandidate["external_key"]?.stringValue == "arxiv:2604.22012", "Payload should preserve external_key.")
        try expect(firstCandidate["display_title"]?.stringValue == "Graph Retrieval Agents for Daily Literature", "Payload should preserve display_title.")
    }

    func recommendationPipelineHonorsCategoryHardBoundary() throws {
        let crossListed = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.00002",
            externalKey: "arxiv:2604.00002",
            displayTitle: "Cross-listed Optimization Paper",
            categories: ["cs.AI", "math.OC"],
            primaryCategory: "cs.AI"
        )
        let primaryMatch = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.00003",
            externalKey: "arxiv:2604.00003",
            displayTitle: "Primary Optimization Paper",
            categories: ["math.OC", "cs.AI"],
            primaryCategory: "math.OC"
        )

        let crossListOn = RecommendationPipeline.filterCategoryBoundary(
            [crossListed, primaryMatch],
            selectedCategories: ["math.OC"],
            includeCrossList: true
        )
        let crossListOff = RecommendationPipeline.filterCategoryBoundary(
            [crossListed, primaryMatch],
            selectedCategories: ["math.OC"],
            includeCrossList: false
        )

        try expect(Set(crossListOn.map(\.id)) == Set([crossListed.id, primaryMatch.id]), "Cross-list mode should allow any selected category match.")
        try expect(crossListOff.map(\.id) == [primaryMatch.id], "Primary-only mode should reject cross-listed non-primary matches.")
    }

    func recommendationScorerV2SignalsKeywordSeedAndRecency() async throws {
        var seed = samplePaper(id: "seed-diffusion")
        seed.title = "Diffusion Planning Agents"
        seed.abstract = "Diffusion planning agents optimize long horizon scientific workflows."
        seed.updatedAt = Date(timeIntervalSince1970: 1_777_500_000)

        let candidate = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.00004",
            externalKey: "arxiv:2604.00004",
            displayTitle: "Diffusion Planning Agents for Scientific Workflows",
            authors: ["Ada Lovelace"],
            sourceTags: [.dailyFeed],
            categories: ["cs.AI"],
            abstractText: "Diffusion planning agents optimize experiments and scientific workflows with long horizon decisions.",
            publishedAt: Date(timeIntervalSince1970: 1_777_590_000)
        )
        let context = RecommendationContext(
            corePaperIDs: [seed.id],
            openGapKeywords: ["diffusion", "planning"],
            weightedKeywords: [WeightedKeyword(text: "diffusion planning", weight: 2)],
            interestPapers: [seed],
            seedPapers: [seed],
            projectContextTexts: ["scientific workflow planning agents"],
            noveltyReferenceTexts: ["older graph retrieval survey"],
            evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )

        let score = await RecommendationScorer().scoreOne(candidate, context: context)

        try expect(score.features.keywordRelevance > 0.8, "V2 scorer should reward weighted keyword phrase matches.")
        try expect(score.features.seedSimilarity > 0.4, "V2 scorer should compute seed-paper similarity.")
        try expect(score.features.projectContextSimilarity > 0, "V2 scorer should use project context text.")
        try expect(score.features.recency > 0.8, "V2 recency should use publishedAt day-level decay.")
        try expect(score.total > 0.5, "V2 normalized total should remain strong for matched recommendations.")
    }

    func recommendationFeedbackStorePersistsJSONLAndBuildsProfile() async throws {
        let (rootURL, workspace) = try makeWorkspaceFixture("RecommendationFeedbackWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let candidate = RecommendationCandidate(
            canonicalID: "external:arxiv:2604.00005",
            externalKey: "arxiv:2604.00005",
            displayTitle: "Graph Retrieval Feedback Paper",
            categories: ["cs.AI"],
            abstractText: "Graph retrieval recommendations adapt to local feedback."
        )
        let store = RecommendationFeedbackStore(dateProvider: { Date(timeIntervalSince1970: 1_777_600_000) })
        try await store.record(candidate: candidate, type: .like, projectID: "proj", recommendationRunID: "run-1", in: workspace)
        let records = try await store.load(in: workspace)
        let score = RecommendationScore(
            id: candidate.id,
            candidate: candidate,
            features: RecommendationFeatureBreakdown(),
            total: 0.8,
            evaluatedAt: Date(timeIntervalSince1970: 1_777_600_000)
        )
        let profile = RecommendationFeedbackStore.profile(records: records, scores: [score], projectID: "proj")

        try expect(records.count == 1, "Feedback store should persist JSONL records.")
        try expect(records.first?.feedbackType == .like, "Feedback store should preserve feedback type.")
        try expect(profile.positiveTexts.first?.contains("Graph Retrieval Feedback") == true, "Feedback profile should include positive candidate text.")
        try expect(profile.feedbackByPaperKey["arxiv:2604.00005"] == .like, "Feedback profile should index latest feedback by paper key.")
    }

    func recommendationPipelineMMRDiversifiesNearDuplicateResults() throws {
        let first = recommendationScoreForMMR(
            id: "external:arxiv:2604.00006",
            title: "Graph Retrieval Agents for Literature Maps",
            abstract: "Graph retrieval agents build literature maps.",
            total: 0.90
        )
        let duplicate = recommendationScoreForMMR(
            id: "external:arxiv:2604.00007",
            title: "Graph Retrieval Agents for Literature Mapping",
            abstract: "Graph retrieval agents build literature maps.",
            total: 0.89
        )
        let diverse = recommendationScoreForMMR(
            id: "external:arxiv:2604.00008",
            title: "Quantum Control for Detector Calibration",
            abstract: "Quantum control calibrates detector systems.",
            total: 0.88
        )

        let reranked = RecommendationPipeline.rerankByMMR([first, duplicate, diverse], limit: 2, lambda: 0.5)

        try expect(reranked.map(\.id) == [first.id, diverse.id], "MMR should prefer a slightly lower-scored diverse paper over a near duplicate.")
        try expect(reranked[0].rank == 1 && reranked[1].rank == 2, "MMR reranking should rewrite display ranks.")
    }

    func recommendationRunResultDecodesLegacySnapshotWithV2Defaults() throws {
        let json = """
        {
          "id": "rec-legacy",
          "trigger": "manual",
          "context_project_id": "proj",
          "generated_at": "2026-04-20T00:00:00Z",
          "candidate_count": 1,
          "scores": [
            {
              "id": "external:arxiv:2604.00009",
              "candidate": {
                "canonical_id": "external:arxiv:2604.00009",
                "external_key": "arxiv:2604.00009",
                "display_title": "Legacy Recommendation Paper",
                "categories": ["cs.AI"],
                "source_tags": ["daily_feed"]
              },
              "features": {
                "library_interest_similarity": 0.5,
                "recency": 1.0,
                "open_gap_coverage": 0.25,
                "author_overlap_with_core": 0.0,
                "queue_pressure_penalty": 0.0
              },
              "total": 0.7,
              "rank": 1,
              "reason": "legacy",
              "reason_keys": ["library_interest_similarity"],
              "evaluated_at": "2026-04-20T00:00:00Z"
            }
          ],
          "query": "diffusion planning",
          "categories": ["cs.AI"],
          "source_note": "legacy"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(RecommendationRunResult.self, from: Data(json.utf8))

        try expect(result.keywords.map(\.text) == ["diffusion planning"], "Legacy snapshots should synthesize V2 weighted keywords from query.")
        try expect(result.includeCrossList == true, "Legacy snapshots should default include_cross_list to true.")
        try expect(result.scores.first?.candidate.primaryCategory == "cs.AI", "Legacy candidates should fall back to the first category as primary.")
        try expect(result.scores.first?.features.seedSimilarity == 0, "Legacy feature breakdown should decode missing V2 fields as zero.")
    }

    func todoQueriesDeriveDateProjectSortAndOpenCount() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = try require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)), "Should build the reference day.")
        let otherDay = try require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 9)), "Should build the next day.")

        func makeTodo(
            _ id: String,
            status: TodoStatus = .open,
            due: Date? = nil,
            priority: Priority = .medium,
            projects: [String] = [],
            title: String = "T"
        ) -> TodoItem {
            TodoItem(
                id: id,
                title: title,
                kind: .general,
                status: status,
                dueDate: due,
                priority: priority,
                projectIDs: projects,
                tags: [],
                relatedPaperIDs: [],
                notes: nil,
                createdAt: day,
                updatedAt: day
            )
        }

        let todayHigh = makeTodo("today-high", due: day, priority: .high)
        let todayLow = makeTodo("today-low", due: day, priority: .low)
        let tomorrow = makeTodo("tomorrow", due: otherDay, priority: .urgent)
        let undated = makeTodo("undated", due: nil, priority: .urgent)

        let dueToday = TodoQueries.dueOn([todayLow, undated, tomorrow, todayHigh], date: day, calendar: calendar)
        try expect(dueToday.map(\.id) == ["today-high", "today-low"], "dueOn should keep same-day todos sorted by priority rank.")

        let projA = makeTodo("proj-a", projects: ["alpha"])
        let projB = makeTodo("proj-b", projects: ["beta"])
        try expect(TodoQueries.forProject([projA, projB], projectID: "alpha").map(\.id) == ["proj-a"], "forProject should filter by project membership.")

        let done = makeTodo("done", status: .done, due: day)
        let cancelled = makeTodo("cancelled", status: .cancelled, due: day)
        let inProgress = makeTodo("in-progress", status: .inProgress, due: day)
        let mixed = [todayHigh, done, cancelled, inProgress]
        try expect(TodoQueries.openCount(mixed) == 2, "openCount should count only non-done, non-cancelled todos.")
        try expect(TodoQueries.isCompleted(done) && TodoQueries.isCompleted(cancelled), "Done and cancelled are completed.")
        try expect(TodoQueries.isOpen(inProgress) && TodoQueries.isOpen(todayHigh), "Open and in-progress are open.")

        let sorted = mixed.sorted(by: TodoQueries.listSort)
        try expect(sorted.map(\.id) == ["cancelled", "done", "in-progress", "today-high"], "listSort should order by status (cancelled<done<inProgress<open) first.")

        try expect(TodoQueries.priorityRank(.urgent) < TodoQueries.priorityRank(.high), "Urgent outranks high.")
        try expect(TodoQueries.priorityRank(.high) < TodoQueries.priorityRank(.medium), "High outranks medium.")
        try expect(TodoQueries.priorityRank(.medium) < TodoQueries.priorityRank(.low), "Medium outranks low.")
    }

    func todoDatePresetResolvesRelativeDates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let base = try require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)), "Should build the base day.")

        let today = TodoDatePreset.today.date(from: base, calendar: calendar)
        try expect(calendar.isDate(today, inSameDayAs: calendar.startOfDay(for: base)), "today preset should resolve to the start of the base day.")

        let tomorrow = TodoDatePreset.tomorrow.date(from: base, calendar: calendar)
        try expect(calendar.dateComponents([.day], from: today, to: tomorrow).day == 1, "tomorrow preset should be exactly one day after today.")

        let weekend = TodoDatePreset.thisWeekend.date(from: base, calendar: calendar)
        try expect(calendar.component(.weekday, from: weekend) == 7, "thisWeekend preset should resolve to a Saturday.")
        try expect(weekend >= today, "thisWeekend preset should not be before today.")

        let nextWeek = TodoDatePreset.nextWeek.date(from: base, calendar: calendar)
        try expect(calendar.component(.weekday, from: nextWeek) == 2, "nextWeek preset should resolve to a Monday.")
        try expect(nextWeek > today, "nextWeek preset should be strictly after today.")
    }

    func todoPriorityFlagMappingRoundTrips() throws {
        try expect(Priority.low.flagCount == 1, "Low priority should render as one flag.")
        try expect(Priority.medium.flagCount == 2, "Medium priority should render as two flags.")
        try expect(Priority.high.flagCount == 3, "High priority should render as three flags.")
        try expect(Priority.urgent.flagCount == 3, "Urgent priority should render as three flags (kept for Reminders interop).")

        try expect(Priority.fromFlagCount(1) == .low, "One flag should map to low.")
        try expect(Priority.fromFlagCount(2) == .medium, "Two flags should map to medium.")
        try expect(Priority.fromFlagCount(3) == .high, "Three flags should map to high.")
        try expect(Priority.fromFlagCount(0) == .low, "fromFlagCount should clamp below-range counts to low.")
        try expect(Priority.fromFlagCount(9) == .high, "fromFlagCount should clamp above-range counts to high.")
        try expect(Priority.flagSelectable == [.low, .medium, .high], "flagSelectable should expose the three composer priorities in flag order.")
    }

    func todoRepositoryPersistsDateRange() async throws {
        let (rootURL, workspace) = try makeWorkspaceFixture("TodoDateRangeWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let repository = TodoRepository()
        let calendar = Calendar(identifier: .gregorian)
        let start = try require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 10)), "Should build the range start.")
        let due = try require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14)), "Should build the range end.")
        let todo = TodoItem(
            id: "range-001",
            title: "Sprint reading block",
            kind: .reading,
            status: .open,
            startDate: start,
            dueDate: due,
            priority: .high,
            projectIDs: ["alpha"],
            tags: ["sprint"],
            relatedPaperIDs: ["garani2024dark"],
            notes: nil,
            createdAt: start,
            updatedAt: start
        )

        try await repository.upsert(todo, in: workspace)
        let loaded = try await repository.loadTodos(in: workspace)
        let reloaded = try require(loaded.first, "The persisted ranged todo should be loadable.")

        let reloadedStart = try require(reloaded.startDate, "TodoRepository should persist startDate.")
        let reloadedDue = try require(reloaded.dueDate, "TodoRepository should persist dueDate.")
        try expect(calendar.isDate(reloadedStart, inSameDayAs: start), "startDate day should round-trip through YAML.")
        try expect(calendar.isDate(reloadedDue, inSameDayAs: due), "dueDate day should round-trip through YAML.")
        try expect(reloaded.hasDateRange, "A multi-day todo should report hasDateRange == true.")
        try expect(reloaded.kind == .reading, "Todo kind should round-trip.")
        try expect(reloaded.tags == ["sprint"], "Tags should round-trip alongside the date range.")
    }

    func todoTagRepositoryRoundTripsDefinitions() async throws {
        let (rootURL, workspace) = try makeWorkspaceFixture("TodoTagWorkspace")
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        let repository = TodoTagRepository()
        let initialDefinitions = try await repository.loadDefinitions(in: workspace)
        try expect(initialDefinitions.isEmpty, "A fresh workspace should have no task tags.")

        try await repository.upsert(TagDefinition(name: "writing", colorHex: "#F4A259"), in: workspace)
        try await repository.upsert(TagDefinition(name: "urgent", colorHex: "#E76F51", textColorHex: "#FFFFFF"), in: workspace)

        var definitions = try await repository.loadDefinitions(in: workspace)
        try expect(definitions.map(\.name) == ["urgent", "writing"], "Task tags should load sorted by name.")
        try expect(definitions.first(where: { $0.name == "urgent" })?.textColorHex == "#FFFFFF", "Task tag custom text color should persist.")

        try await repository.upsert(TagDefinition(name: "writing", colorHex: "#112233"), in: workspace)
        definitions = try await repository.loadDefinitions(in: workspace)
        try expect(definitions.count == 2, "Upserting an existing task tag should not duplicate it.")
        try expect(definitions.first(where: { $0.name == "writing" })?.colorHex == "#112233", "Upserting should update the existing task tag color.")

        try await repository.deleteTag(named: "urgent", in: workspace)
        definitions = try await repository.loadDefinitions(in: workspace)
        try expect(definitions.map(\.name) == ["writing"], "Deleting a task tag should remove it from tasks/todo_tags.yaml.")
    }

    // MARK: - Task and Recommendation Fixtures
}
