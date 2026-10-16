import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
extension AppViewModel {
    func loadRecommendationHistory(limit: Int = 20) {
        guard let workspace = currentWorkspace else {
            return
        }

        Task {
            do {
                recommendationHistory = try await recommendationPipeline.loadHistory(workspace: workspace, limit: limit)
            } catch {
                recordAppDebugEvent("recommendation.error", payload: .object([
                    "phase": .string("history_load"),
                    "reason": .string(error.localizedDescription)
                ]))
            }
        }
    }

    func selectRecommendationHistory(_ result: RecommendationRunResult) {
        recommendationRunResult = result
        recommendationCandidateCount = result.candidateCount
        recommendationErrorMessage = nil
        recommendationAIEvaluationStatusMessage = nil
        Task {
            await refreshRecommendationFeedbackState(for: result)
        }
    }

    func refreshArxivRecommendations(project: ResearchProject?, query: String, categories: [String], topK: Int, includeCrossList: Bool = true, aiModel: String = "deepseek-v4-flash", referencePaperIDs: Set<Paper.ID> = []) {
        guard let workspace = currentWorkspace else {
            return
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategories = categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let categoriesForRequest = resolvedCategories.isEmpty ? defaultArxivRecommendationCategories(in: workspace) : resolvedCategories
        let requestedTopK = min(max(topK, 1), 100)
        let selectedAIModel = aiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "deepseek-v4-flash" : aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let referencePapers = recommendationReferencePapers(ids: referencePaperIDs)
        let referenceIDs = referencePapers.map(\.id)
        let referenceIDSet = Set(referenceIDs)
        let weightedKeywords = WeightedKeyword.parse(trimmedQuery)
        let request = PaperRecommendationRequest(
            arxivCategories: categoriesForRequest,
            includeCrossList: includeCrossList,
            keywords: weightedKeywords,
            seedPaperIDs: referenceIDs,
            projectID: project?.id,
            limit: requestedTopK,
            aiModel: selectedAIModel
        )
        isRefreshingRecommendations = true
        recommendationErrorMessage = nil
        recommendationAIEvaluationStatusMessage = nil

        Task {
            defer {
                isRefreshingRecommendations = false
            }
            do {
                var config = arxivOnlyRecommendationConfig(in: workspace, topK: requestedTopK)
                let search = try await fetchArxivRecommendationCandidates(
                    query: trimmedQuery,
                    categories: categoriesForRequest,
                    topK: requestedTopK,
                    config: config,
                    workspace: workspace,
                    project: project,
                    referencePapers: referencePapers,
                    includeCrossList: request.includeCrossList,
                    aiModel: selectedAIModel
                )
                config.maxDailyCandidates = min(max(config.maxDailyCandidates, requestedTopK * 5), 100)
                let existingHistory = (try? await recommendationPipeline.loadHistory(workspace: workspace, limit: 200)) ?? recommendationHistory
                let feedbackRecords = (try? await recommendationFeedbackStore.load(in: workspace)) ?? []
                let feedbackProfile = RecommendationFeedbackStore.profile(
                    records: feedbackRecords,
                    scores: existingHistory.flatMap(\.scores),
                    projectID: project?.id
                )
                let context = RecommendationContext(
                    projectID: project?.id,
                    corePaperIDs: referenceIDSet,
                    openGapKeywords: recommendationKeywords(query: trimmedQuery, project: project, categories: categoriesForRequest),
                    weightedKeywords: weightedKeywords,
                    interestPapers: referencePapers,
                    seedPapers: referencePapers,
                    projectContextTexts: recommendationProjectContextTexts(project: project),
                    feedbackProfile: feedbackProfile,
                    evaluatedAt: Date()
                )
                let result = try await recommendationPipeline.run(
                    workspace: workspace,
                    papers: [],
                    dailyFeedCandidates: search.candidates,
                    graph: nil,
                    context: context,
                    config: config,
                    trigger: .manual,
                    locale: appLanguage == .english ? .en : .zh,
                    force: true,
                    query: trimmedQuery,
                    categories: categoriesForRequest,
                    referencePaperIDs: referenceIDs,
                    keywords: weightedKeywords,
                    includeCrossList: request.includeCrossList,
                    aiModel: selectedAIModel,
                    sourceDate: search.sourceDate,
                    sourceNote: search.sourceNote
                )
                recommendationCandidateCount = search.candidates.count
                if var result {
                    recommendationRunResult = result
                    await refreshRecommendationFeedbackState(for: result)
                    if result.scores.isEmpty {
                        recommendationAIEvaluationStatusMessage = localized(
                            "本次 AI/arXiv 搜索没有可显示推荐。候选 \(result.candidateCount) 篇，来源：\(search.sourceNote)。",
                            "No displayable recommendations for this AI/arXiv search. \(result.candidateCount) candidates, source: \(search.sourceNote)."
                        )
                        showShellStatus(localized("AI/arXiv 本次没有返回可显示推荐。", "AI/arXiv returned no displayable recommendations."))
                    } else {
                        showShellStatus(localized("已获取 \(result.scores.count) 条 AI 辅助推荐。", "Fetched \(result.scores.count) AI-assisted recommendations."))
                    }
                    recommendationHistory = try await recommendationPipeline.loadHistory(workspace: workspace, limit: 20)
                    if !result.scores.isEmpty {
                        isEvaluatingRecommendationsWithAI = true
                        do {
                            result.aiEvaluation = try await evaluateRecommendationsWithAI(result, model: selectedAIModel, workspace: workspace)
                            try await recommendationPipeline.persistSnapshot(result, workspace: workspace)
                            recommendationRunResult = result
                            await refreshRecommendationFeedbackState(for: result)
                            recommendationHistory = try await recommendationPipeline.loadHistory(workspace: workspace, limit: 20)
                            recommendationAIEvaluationStatusMessage = localized("AI 已完成推荐评价。", "AI evaluation completed.")
                        } catch {
                            recommendationAIEvaluationStatusMessage = localized("AI 评价暂不可用：\(error.localizedDescription)", "AI evaluation unavailable: \(error.localizedDescription)")
                        }
                        isEvaluatingRecommendationsWithAI = false
                    }
                } else {
                    showShellStatus(localized("arXiv 推荐没有变化。", "arXiv recommendations are unchanged."))
                }
                recordAppDebugEvent("recommendation.arxiv_refresh", payload: .object([
                    "candidate_count": .number(String(search.candidates.count)),
                    "top_k": .number(String(result?.scores.count ?? 0)),
                    "reference_paper_count": .number(String(referenceIDs.count)),
                    "include_cross_list": .bool(request.includeCrossList),
                    "source_note": .string(search.sourceNote),
                    "scope": .string(project.map { "project:\($0.id)" } ?? "workspace")
                ]))
            } catch {
                isEvaluatingRecommendationsWithAI = false
                recommendationErrorMessage = error.localizedDescription
                recordAppDebugEvent("recommendation.error", payload: .object([
                    "phase": .string("arxiv_refresh"),
                    "reason": .string(error.localizedDescription)
                ]))
                present(error)
            }
        }
    }

    func addRecommendationToLibrary(_ score: RecommendationScore, scope: RecommendationTarget) {
        guard let workspace = currentWorkspace else {
            recommendationErrorMessage = RecommendationReadingTodoError.missingWorkspace.localizedDescription
            return
        }
        guard !recommendationLibraryImportScoreIDs.contains(score.id) else {
            return
        }
        recommendationLibraryImportScoreIDs.insert(score.id)

        Task {
            defer { recommendationLibraryImportScoreIDs.remove(score.id) }
            do {
                let paper = try await importRecommendationCandidateToLibrary(score.candidate, scope: scope, in: workspace)
                try await loadWorkspaceData(in: workspace, selectingPaper: paper.id, selectingMarkdown: selectedMarkdownID)
                recordRecommendationFeedback(.save, for: score, scope: scope)
                showShellStatus(localized("已加入论文库，并自动添加 arXiv 推荐标签。", "Added to Library with the arXiv recommendation tag."))
            } catch {
                recommendationErrorMessage = localized("无法加入论文库：\(error.localizedDescription)", "Could not add to Library: \(error.localizedDescription)")
                recordAppDebugEvent("recommendation.push.error", payload: .object([
                    "phase": .string("library_import"),
                    "score_id": .string(score.id),
                    "scope": .string(scope.identifier),
                    "reason": .string(error.localizedDescription)
                ]))
                present(error)
            }
        }
    }

    func addRecommendationToReadingTodo(_ score: RecommendationScore, scope: RecommendationTarget) {
        guard let workspace = currentWorkspace else {
            recommendationErrorMessage = RecommendationReadingTodoError.missingWorkspace.localizedDescription
            return
        }
        guard !recommendationReadingTodoImportScoreIDs.contains(score.id) else {
            return
        }
        recommendationReadingTodoImportScoreIDs.insert(score.id)

        Task {
            defer { recommendationReadingTodoImportScoreIDs.remove(score.id) }
            do {
                let paper = try await importRecommendationCandidateToLibrary(score.candidate, scope: scope, in: workspace)
                try await upsertReadingTodo(for: paper, score: score, scope: scope, in: workspace)
                try await loadWorkspaceData(in: workspace, selectingPaper: paper.id, selectingMarkdown: selectedMarkdownID)
                recordRecommendationFeedback(.save, for: score, scope: scope)
                showShellStatus(localized("已创建阅读 Todo，可在任务页继续安排阅读。", "Created a reading todo; continue from Tasks."))
            } catch {
                recommendationErrorMessage = localized("无法创建阅读 Todo：\(error.localizedDescription)", "Could not create reading todo: \(error.localizedDescription)")
                recordAppDebugEvent("recommendation.push.error", payload: .object([
                    "phase": .string("reading_todo_import"),
                    "score_id": .string(score.id),
                    "scope": .string(scope.identifier),
                    "reason": .string(error.localizedDescription)
                ]))
                present(error)
            }
        }
    }

    func addRecommendationToReadingList(_ score: RecommendationScore, scope: RecommendationTarget) {
        addRecommendationToReadingTodo(score, scope: scope)
    }

    func recommendationFeedbackType(for score: RecommendationScore) -> RecommendationFeedbackType? {
        recommendationFeedbackByScoreID[score.id]
    }

    func isAddingRecommendationToLibrary(_ score: RecommendationScore) -> Bool {
        recommendationLibraryImportScoreIDs.contains(score.id)
    }

    func isAddingRecommendationToReadingTodo(_ score: RecommendationScore) -> Bool {
        recommendationReadingTodoImportScoreIDs.contains(score.id)
    }

    func recordRecommendationFeedback(_ type: RecommendationFeedbackType, for score: RecommendationScore, scope: RecommendationTarget? = nil) {
        guard let workspace = currentWorkspace else {
            return
        }
        let runID = recommendationRunResult?.id ?? score.id
        let projectID = scope?.projectIDForRecommendationFeedback ?? recommendationRunResult?.contextProjectID ?? currentProjectID
        Task {
            do {
                try await recommendationFeedbackStore.record(
                    candidate: score.candidate,
                    type: type,
                    projectID: projectID,
                    recommendationRunID: runID,
                    in: workspace
                )
                recommendationFeedbackByScoreID[score.id] = type
                recordAppDebugEvent("recommendation.feedback", payload: .object([
                    "score_id": .string(score.id),
                    "feedback_type": .string(type.rawValue),
                    "run_id": .string(runID),
                    "project_id_present": .bool(projectID != nil)
                ]))
            } catch {
                recommendationErrorMessage = localized("保存推荐反馈失败：\(error.localizedDescription)", "Failed to save recommendation feedback: \(error.localizedDescription)")
                recordAppDebugEvent("recommendation.error", payload: .object([
                    "phase": .string("feedback_save"),
                    "score_id": .string(score.id),
                    "reason": .string(error.localizedDescription)
                ]))
            }
        }
    }

    func openRecommendationReadingTodo() {
        selectProjectSpaceTab("tasks")
    }

    func archiveRecommendationHistory(_ result: RecommendationRunResult) {
        guard let workspace = currentWorkspace else {
            return
        }
        Task {
            do {
                try await recommendationPipeline.archiveSnapshot(id: result.id, workspace: workspace)
                recommendationHistory = try await recommendationPipeline.loadHistory(workspace: workspace, limit: 20)
                if recommendationRunResult?.id == result.id {
                    recommendationRunResult = recommendationHistory.first
                }
                showShellStatus(localized("历史推荐已归档。", "Recommendation history archived."))
                recordAppDebugEvent("recommendation.archive", payload: .object([
                    "snapshot_id": .string(result.id)
                ]))
            } catch {
                recommendationErrorMessage = localized("归档历史推荐失败：\(error.localizedDescription)", "Failed to archive recommendation history: \(error.localizedDescription)")
                recordAppDebugEvent("recommendation.error", payload: .object([
                    "phase": .string("archive"),
                    "snapshot_id": .string(result.id),
                    "reason": .string(error.localizedDescription)
                ]))
                present(error)
            }
        }
    }

    func isRecommendationInReadingList(_ score: RecommendationScore, scope: RecommendationTarget) -> Bool {
        let keys = recommendationCandidateKeys(score.candidate)
        return todos.contains { todo in
            guard todo.kind == .reading, todoMatchesScope(todo, scope: scope) else {
                return false
            }
            let paperKeys = todo.relatedPaperIDs.flatMap { paperID -> [String] in
                [paperID, "paper:\(paperID)"]
            }
            let externalKeys = [todo.externalIdentifier, Optional(todo.id)]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            return !keys.isDisjoint(with: Set(paperKeys.map { $0.lowercased() } + externalKeys))
        }
    }

    func isRecommendationInLibrary(_ score: RecommendationScore) -> Bool {
        existingPaper(matchingRecommendationCandidate: score.candidate) != nil
    }

    func importRecommendationCandidateToLibrary(_ candidate: RecommendationCandidate, scope: RecommendationTarget, in workspace: ResearchWorkspace) async throws -> Paper {
        if var existing = existingPaper(matchingRecommendationCandidate: candidate) {
            existing = applyRecommendationLibraryMetadata(to: existing, candidate: candidate, scope: scope)
            return try await paperRepository.save(existing, in: workspace)
        }

        guard let importIdentifier = recommendationImportIdentifier(for: candidate) else {
            throw RecommendationReadingTodoError.missingImportIdentifier
        }

        let collectionPath = selectedCollectionPath ?? workspacePreferences.defaultCollectionPath ?? "Uncategorized"
        var importedPaper = try await remoteImportService.importItem(
            from: importIdentifier,
            draftPreview: recommendationMetadataDraft(for: candidate),
            into: workspace,
            existingPapers: papers,
            collectionPath: collectionPath,
            tags: [Self.arxivRecommendationTag]
        )
        importedPaper = applyRecommendationLibraryMetadata(to: importedPaper, candidate: candidate, scope: scope)
        return try await paperRepository.save(importedPaper, in: workspace)
    }

    func applyRecommendationLibraryMetadata(to paper: Paper, candidate: RecommendationCandidate, scope: RecommendationTarget) -> Paper {
        var updatedPaper = paper
        updatedPaper.tags = uniqueOrdered(updatedPaper.tags + [Self.arxivRecommendationTag])
        if let projectID = scope.projectID, !updatedPaper.projectIDs.contains(projectID) {
            updatedPaper.projectIDs.append(projectID)
        }
        if updatedPaper.abstract == nil {
            updatedPaper.abstract = candidate.abstractText
        }
        if updatedPaper.pdfURL == nil {
            updatedPaper.pdfURL = candidate.pdfURL
        }
        if updatedPaper.url == nil {
            updatedPaper.url = candidate.sourceURL
        }
        if updatedPaper.categories.isEmpty {
            updatedPaper.categories = candidate.categories
        }
        return updatedPaper
    }

    func recommendationMetadataDraft(for candidate: RecommendationCandidate) -> PaperMetadataDraft? {
        let arxivID = PaperIdentityGenerator.normalizedArxiv(candidate.externalKey) ?? PaperIdentityGenerator.normalizedArxiv(candidate.canonicalID)
        let sourceURL = candidate.sourceURL ?? arxivID.map { "https://arxiv.org/abs/\($0)" }
        let pdfURL = candidate.pdfURL ?? arxivID.map { "https://arxiv.org/pdf/\($0).pdf" }
        return PaperMetadataDraft(
            title: candidate.displayTitle,
            authors: candidate.authors,
            year: candidate.publishedYear,
            venue: candidate.sourceName ?? "arXiv",
            doi: nil,
            arxiv: arxivID,
            inspireID: nil,
            url: sourceURL,
            pdfURL: pdfURL,
            abstract: candidate.abstractText,
            categories: candidate.categories,
            sourceProvider: "recommendation-arxiv"
        )
    }

    func recommendationImportIdentifier(for candidate: RecommendationCandidate) -> String? {
        [candidate.externalKey, candidate.sourceURL, candidate.pdfURL, Optional(candidate.canonicalID)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty }
            .first
    }

    func existingPaper(matchingRecommendationCandidate candidate: RecommendationCandidate) -> Paper? {
        if let paperID = candidate.paperID, let paper = papers.first(where: { $0.id == paperID }) {
            return paper
        }
        let arxivID = PaperIdentityGenerator.normalizedArxiv(candidate.externalKey) ?? PaperIdentityGenerator.normalizedArxiv(candidate.canonicalID)
        if let arxivID, let paper = papers.first(where: { PaperIdentityGenerator.normalizedArxiv($0.arxiv) == arxivID || $0.resolvedGraphNodeID == "arxiv:\(arxivID)" }) {
            return paper
        }
        return nil
    }

    func upsertReadingTodo(for paper: Paper, score: RecommendationScore, scope: RecommendationTarget, in workspace: ResearchWorkspace) async throws {
        let now = Date()
        let projectIDs = scope.projectID.map { [$0] } ?? []
        let loadedTodos = try await todoRepository.loadTodos(in: workspace)
        var todo = loadedTodos.first { existing in
            existing.id == readingTodoID(for: paper.id, scope: scope)
                || (existing.kind == .reading && existing.relatedPaperIDs.contains(paper.id) && todoMatchesScope(existing, scope: scope))
        } ?? TodoItem(
            id: readingTodoID(for: paper.id, scope: scope),
            title: localized("阅读：\(paper.displayTitle)", "Read: \(paper.displayTitle)"),
            kind: .reading,
            status: .open,
            dueDate: nil,
            priority: .medium,
            projectIDs: projectIDs,
            tags: [Self.arxivRecommendationTag],
            relatedPaperIDs: [paper.id],
            notes: score.reason,
            externalSource: "sci_station_recommendation",
            externalIdentifier: score.candidate.externalKey ?? score.candidate.canonicalID,
            createdAt: now,
            updatedAt: now
        )

        todo.kind = .reading
        todo.projectIDs = uniqueOrdered(todo.projectIDs + projectIDs)
        todo.tags = uniqueOrdered(todo.tags + [Self.arxivRecommendationTag])
        todo.relatedPaperIDs = uniqueOrdered(todo.relatedPaperIDs + [paper.id])
        todo.notes = todo.notes ?? score.reason
        todo.externalSource = todo.externalSource ?? "sci_station_recommendation"
        todo.externalIdentifier = todo.externalIdentifier ?? score.candidate.externalKey ?? score.candidate.canonicalID
        todo.updatedAt = now
        try await todoRepository.upsert(todo, in: workspace)
    }

    func readingTodoID(for paperID: Paper.ID, scope: RecommendationTarget) -> String {
        "todo-reading-\(sanitizedTodoIDComponent(scope.identifier))-\(sanitizedTodoIDComponent(paperID))"
    }

    func sanitizedTodoIDComponent(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        .reduce(into: "") { $0.append($1) }
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    func todoMatchesScope(_ todo: TodoItem, scope: RecommendationTarget) -> Bool {
        switch scope {
        case .workspace:
            return todo.projectIDs.isEmpty
        case .project(let projectID):
            return todo.projectIDs.contains(projectID)
        }
    }

    func arxivOnlyRecommendationConfig(in workspace: ResearchWorkspace, topK: Int) -> RecommendationConfig {
        var config = (try? RecommendationConfigStore().load(in: workspace)) ?? RecommendationConfig()
        config.topK = min(max(topK, 1), 100)
        config.externalNetworkEnabled = true
        config.weights = RecommendationWeights(
            citedByCore: 0,
            libraryInterestSimilarity: 0.10,
            keywordRelevance: 0.20,
            seedSimilarity: 0.25,
            projectContextSimilarity: 0.15,
            recency: 0.15,
            novelty: 0.10,
            quality: 0.05,
            aiScore: 0.10,
            feedback: 0.05,
            openGapCoverage: 0.10,
            authorOverlapWithCore: 0.10,
            duplicatePenalty: 0.90
        )
        return config
    }

    func fetchArxivRecommendationCandidates(
        query: String,
        categories: [String],
        topK: Int,
        config: RecommendationConfig,
        workspace: ResearchWorkspace,
        project: ResearchProject?,
        referencePapers: [Paper],
        includeCrossList: Bool,
        aiModel: String
    ) async throws -> (candidates: [RecommendationCandidate], sourceDate: Date, sourceNote: String) {
        let maxResults = min(max(config.maxDailyCandidates, topK * 5), 100)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var strategies: [RecommendationAISearchStrategy] = []
        var statusNotes: [String] = []
        let apiKey: String
        do {
            apiKey = try await resolvedLLMAPIKey(for: workspace)
        } catch {
            apiKey = ""
            statusNotes.append(localized("AI API Key 暂不可用：\(error.localizedDescription)", "AI API key unavailable: \(error.localizedDescription)"))
            recordAppDebugEvent("recommendation.ai_search.error", payload: .object([
                "phase": .string("api_key"),
                "reason": .string(error.localizedDescription)
            ]))
        }
        if !apiKey.isEmpty {
            recommendationAIEvaluationStatusMessage = localized(
                "正在把项目、关键词和 \(referencePapers.count) 篇参考论文提交给 AI 生成 arXiv 搜索策略…",
                "Submitting the project, keywords, and \(referencePapers.count) reference papers to AI for arXiv search planning…"
            )
            do {
                let aiStrategies = try await recommendationAISearchStrategies(
                    query: trimmedQuery,
                    categories: categories,
                    project: project,
                    referencePapers: referencePapers,
                    includeCrossList: includeCrossList,
                    topK: topK,
                    model: aiModel,
                    apiKey: apiKey
                )
                strategies.append(contentsOf: aiStrategies)
                if !aiStrategies.isEmpty {
                    statusNotes.append(localized("AI 已生成 \(aiStrategies.count) 个搜索策略", "AI generated \(aiStrategies.count) search strategies"))
                }
            } catch {
                statusNotes.append(localized("AI 搜索策略不可用：\(error.localizedDescription)", "AI search planning unavailable: \(error.localizedDescription)"))
                recordAppDebugEvent("recommendation.ai_search.error", payload: .object([
                    "phase": .string("strategy"),
                    "reason": .string(error.localizedDescription)
                ]))
            }
        } else {
            statusNotes.append(localized("未配置 AI API Key，已回退到直接 arXiv 搜索", "No AI API key configured; falling back to direct arXiv search"))
        }

        if !trimmedQuery.isEmpty {
            strategies.append(RecommendationAISearchStrategy(query: trimmedQuery, categories: categories, source: "manual"))
        }
        strategies.append(RecommendationAISearchStrategy(query: "", categories: categories, source: "category"))

        var candidatesByKey: [String: RecommendationCandidate] = [:]
        var usedStrategies: [RecommendationAISearchStrategy] = []
        for strategy in uniqueRecommendationSearchStrategies(strategies) {
            let request = ArxivRecommendationRequest(
                query: strategy.query,
                categories: strategy.categories.isEmpty ? categories : strategy.categories,
                maxResults: maxResults
            )
            let candidates: [RecommendationCandidate]
            do {
                let client = arxivRecommendationClient
                candidates = try await recommendationWithTimeout(seconds: 20) {
                    try await client.fetch(request)
                }
            } catch {
                statusNotes.append(localized("一个 arXiv 搜索已跳过：\(error.localizedDescription)", "Skipped one arXiv search: \(error.localizedDescription)"))
                recordAppDebugEvent("recommendation.error", payload: .object([
                    "phase": .string("arxiv_fetch"),
                    "reason": .string(error.localizedDescription)
                ]))
                continue
            }
            if !candidates.isEmpty {
                usedStrategies.append(strategy)
            }
            for candidate in candidates {
                let key = candidate.externalKey ?? candidate.paperID ?? candidate.canonicalID
                if candidatesByKey[key] == nil {
                    candidatesByKey[key] = candidate
                }
            }
            if candidatesByKey.count >= maxResults {
                break
            }
        }

        let candidates = RecommendationPipeline.filterCategoryBoundary(
            Array(candidatesByKey.values),
            selectedCategories: categories,
            includeCrossList: includeCrossList
        )
            .sorted { lhs, rhs in
                if lhs.publishedAt == rhs.publishedAt {
                    return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
                }
                return (lhs.publishedAt ?? .distantPast) > (rhs.publishedAt ?? .distantPast)
            }
            .prefix(maxResults)
            .map { $0 }
        let strategySummary = usedStrategies
            .prefix(3)
            .map { strategy in
                strategy.query.isEmpty ? strategy.categories.prefix(4).joined(separator: " · ") : strategy.query
            }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        if candidates.isEmpty {
            return (
                [],
                Date(),
                (statusNotes + [localized("arXiv 没有返回候选论文。请减少关键词或更换领域。", "arXiv returned no candidate papers. Try fewer keywords or different fields.")]).joined(separator: "；")
            )
        }
        return (
            candidates,
            Date(),
            (statusNotes + [localized("arXiv 返回 \(candidates.count) 篇候选", "arXiv returned \(candidates.count) candidates"), strategySummary]).filter { !$0.isEmpty }.joined(separator: "；")
        )
    }

    func recommendationAISearchStrategies(
        query: String,
        categories: [String],
        project: ResearchProject?,
        referencePapers: [Paper],
        includeCrossList: Bool,
        topK: Int,
        model: String,
        apiKey: String
    ) async throws -> [RecommendationAISearchStrategy] {
        let resolvedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedAPIKey.isEmpty else {
            throw RecommendationAIEvaluationError.missingAPIKey
        }
        var configuration = llmConfiguration
        configuration.model = model
        configuration.temperature = 0.15
        configuration.maxTokens = 1600
        let requestConfiguration = configuration
        let prompt = recommendationAISearchPrompt(
            query: query,
            categories: categories,
            project: project,
            referencePapers: referencePapers,
            includeCrossList: includeCrossList,
            topK: topK
        )
        let provider = openAIProvider
        let response = try await recommendationWithTimeout(seconds: 20) {
            try await provider.complete(
                prompt: prompt,
                configuration: requestConfiguration,
                apiKey: resolvedAPIKey
            )
        }
        return parseRecommendationAISearchStrategies(response, fallbackCategories: categories)
    }

    func recommendationAISearchPrompt(
        query: String,
        categories: [String],
        project: ResearchProject?,
        referencePapers: [Paper],
        includeCrossList: Bool,
        topK: Int
    ) -> String {
        let projectText = project.map { project in
            """
            Name: \(project.name)
            Description: \(project.description)
            """
        } ?? "No active project."
        let references = referencePapers.prefix(8).map { paper in
            """
            ID: \(paper.id)
            Title: \(paper.displayTitle)
            Authors: \(paper.authors.prefix(8).joined(separator: ", "))
            Year: \(paper.year.map(String.init) ?? "")
            Categories: \(paper.categories.joined(separator: ", "))
            Abstract: \(limitedRecommendationText(paper.abstract, maxCharacters: 900))
            """
        }
        .joined(separator: "\n\n")
        let referenceText = references.isEmpty ? "No reference papers selected." : references
        return """
        You are an AI literature search planner for arXiv. The app will execute your searches against the arXiv API and then recommend papers to the user.

        Return strict JSON only:
        {"searches":[{"query":"2 to 6 English keywords, no boolean operators","categories":["arXiv category ids"],"reason":"short reason"}]}

        Requirements:
        - Generate 3 to 5 complementary arXiv searches for finding recommendation candidates.
        - Use the selected reference papers as the main relevance signal.
        - Keep queries broad enough to return papers. Do not use full titles as queries.
        - Treat the selected arXiv categories as a hard boundary. Only return categories from the selected list.
        - include_cross_list is \(includeCrossList ? "true" : "false"): if false, candidates must have one selected category as their primary arXiv category.
        - The user asked for \(topK) recommendations.

        User query:
        \(query.isEmpty ? "(empty)" : query)

        Selected arXiv categories:
        \(categories.joined(separator: ", "))

        Project:
        \(projectText)

        Reference papers submitted by the user:
        \(referenceText)
        """
    }

    func parseRecommendationAISearchStrategies(_ response: String, fallbackCategories: [String]) -> [RecommendationAISearchStrategy] {
        let jsonText = recommendationEvaluationJSONText(from: response.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let rawSearches = object["searches"] as? [[String: Any]]
            ?? object["queries"] as? [[String: Any]]
            ?? []
        return rawSearches.compactMap { item in
            let query = ((item["query"] as? String) ?? (item["keywords"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawCategories = recommendationStringList(from: item["categories"])
                .prefix(6)
                .map { $0 }
            let allowed = Set(fallbackCategories.map { $0.lowercased() })
            let categories = rawCategories.filter { allowed.contains($0.lowercased()) }
            let resolvedCategories = categories.isEmpty ? fallbackCategories : categories
            guard !query.isEmpty || !resolvedCategories.isEmpty else {
                return nil
            }
            return RecommendationAISearchStrategy(
                query: String(query.prefix(120)),
                categories: resolvedCategories,
                source: "ai"
            )
        }
        .prefix(5)
        .map { $0 }
    }

    func uniqueRecommendationSearchStrategies(_ strategies: [RecommendationAISearchStrategy]) -> [RecommendationAISearchStrategy] {
        var seen: Set<String> = []
        var unique: [RecommendationAISearchStrategy] = []
        for strategy in strategies {
            let query = strategy.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let categories = strategy.categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !query.isEmpty || !categories.isEmpty else {
                continue
            }
            let key = ([query.lowercased()] + categories.map { $0.lowercased() }.sorted()).joined(separator: "|")
            if seen.insert(key).inserted {
                unique.append(RecommendationAISearchStrategy(query: query, categories: categories, source: strategy.source))
            }
        }
        return unique
    }

    func recommendationStringList(from value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let string = value as? String {
            return string
                .components(separatedBy: CharacterSet(charactersIn: ",;|"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    func limitedRecommendationText(_ value: String?, maxCharacters: Int) -> String {
        guard let value else {
            return ""
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxCharacters {
            return trimmed
        }
        return String(trimmed.prefix(maxCharacters))
    }

    func startOfUTCRecommendationDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: date)
    }

    func utcRecommendationDay(offset: Int, from date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(byAdding: .day, value: offset, to: date) ?? date.addingTimeInterval(Double(offset) * 86_400)
    }

    func defaultArxivRecommendationCategories(in workspace: ResearchWorkspace) -> [String] {
        let config = (try? RecommendationConfigStore().load(in: workspace)) ?? RecommendationConfig()
        let arxivCategories = config.dailySources.first { $0.kind == .arxiv }?.categories ?? []
        return arxivCategories.isEmpty ? ["cs.AI", "cs.CL", "cs.CV", "cs.LG"] : arxivCategories
    }

    func recommendationKeywords(query: String, project: ResearchProject?, categories: [String]) -> [String] {
        let text = query.isEmpty ? (project?.name ?? "") : query
        let tokens = RecommendationTextSimilarity.tokens(text)
        return (tokens + categories.map { $0.lowercased() }).filter { !$0.isEmpty }
    }

    func recommendationProjectContextTexts(project: ResearchProject?) -> [String] {
        var texts: [String] = []
        if let project {
            texts.append([project.name, project.description, project.defaultTags.joined(separator: " ")].joined(separator: " "))
            texts.append(contentsOf: papers(for: project.id).prefix(20).map(RecommendationScorer.paperText(_:)))
        } else {
            texts.append(contentsOf: papers.prefix(20).map(RecommendationScorer.paperText(_:)))
        }
        return texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func refreshRecommendationFeedbackState(for result: RecommendationRunResult) async {
        guard let workspace = currentWorkspace else {
            recommendationFeedbackByScoreID = [:]
            return
        }
        do {
            let records = try await recommendationFeedbackStore.load(in: workspace)
            recommendationFeedbackByScoreID = recommendationFeedbackState(records: records, result: result)
        } catch {
            recommendationFeedbackByScoreID = [:]
            recordAppDebugEvent("recommendation.error", payload: .object([
                "phase": .string("feedback_load"),
                "run_id": .string(result.id),
                "reason": .string(error.localizedDescription)
            ]))
        }
    }

    func recommendationFeedbackState(records: [RecommendationFeedbackRecord], result: RecommendationRunResult) -> [String: RecommendationFeedbackType] {
        var state: [String: RecommendationFeedbackType] = [:]
        let sortedRecords = records.sorted { $0.createdAt < $1.createdAt }
        for score in result.scores {
            let keys = RecommendationFeedbackStore.candidateKeys(score.candidate)
            if let record = sortedRecords.last(where: { keys.contains($0.paperKey) && ($0.projectID == nil || $0.projectID == result.contextProjectID) }) {
                state[score.id] = record.feedbackType
            }
        }
        return state
    }

    func recommendationReferencePapers(ids: Set<Paper.ID>) -> [Paper] {
        papers.filter { ids.contains($0.id) }
    }

    func recommendationCandidateKeys(_ candidate: RecommendationCandidate) -> Set<String> {
        Set([candidate.paperID, candidate.externalKey, Optional(candidate.canonicalID)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { key in [key, "external:\(key)", "paper:\(key)"] })
    }

    func evaluateRecommendationsWithAI(_ result: RecommendationRunResult, model: String, workspace: ResearchWorkspace) async throws -> RecommendationAIEvaluation {
        let apiKey = try await resolvedLLMAPIKey(for: workspace)
        guard !apiKey.isEmpty else {
            throw RecommendationAIEvaluationError.missingAPIKey
        }
        var configuration = llmConfiguration
        configuration.model = model
        configuration.temperature = 0.2
        configuration.maxTokens = 3200
        let requestConfiguration = configuration
        let prompt = recommendationAIEvaluationPrompt(for: result)
        let provider = openAIProvider
        let response = try await recommendationWithTimeout(seconds: 45) {
            try await provider.complete(
                prompt: prompt,
                configuration: requestConfiguration,
                apiKey: apiKey
            )
        }
        return parseRecommendationAIEvaluationResponse(response, model: model, result: result)
    }

    func recommendationAIEvaluationPrompt(for result: RecommendationRunResult) -> String {
        let language = appLanguage == .english ? "English" : "Chinese"
        let referencePapers = result.referencePaperIDs.compactMap { referenceID in
            self.papers.first(where: { $0.id == referenceID })
        }
        let references = referencePapers.prefix(8).map { paper in
            """
            ID: \(paper.id)
            Title: \(paper.displayTitle)
            Authors: \(paper.authors.prefix(8).joined(separator: ", "))
            Year: \(paper.year.map(String.init) ?? "")
            Categories: \(paper.categories.joined(separator: ", "))
            Abstract: \(limitedRecommendationText(paper.abstract, maxCharacters: 900))
            """
        }
        .joined(separator: "\n\n")
        let candidatePapers = result.scores.map { score in
            """
            ID: \(score.id)
            External key: \(score.candidate.externalKey ?? "")
            Canonical key: \(score.candidate.canonicalID)
            Title: \(score.candidate.displayTitle)
            Abstract: \(score.candidate.abstractText ?? "")
            """
        }
        .joined(separator: "\n\n")
        return """
        You are evaluating individual paper recommendations for a research workflow. Use the user query, selected reference papers, and each candidate paper title and abstract.
        Do not write an overall evaluation. Return strict JSON only with this shape:
        {"reviews":[{"id":"copy the exact candidate ID","relevance":0.0,"novelty":0.0,"method_soundness":0.0,"usefulness":0.0,"risk":0.0,"summary":"one sentence in \(language)","recommendation_comment":"one decision-oriented comment in \(language)","suitable_for":["short use case"],"possible_weaknesses":["short weakness"]}]}

        Requirements:
        - Return one review for each candidate paper.
        - The id field must exactly copy the candidate ID line, not the arXiv URL and not a rewritten title.
        - Keep every text field concise.

        User query:
        \(result.query.isEmpty ? "(empty)" : result.query)

        Categories:
        \(result.categories.joined(separator: ", "))

        Reference papers submitted by the user:
        \(references.isEmpty ? "No reference papers selected." : references)

        Candidate papers:
        \(candidatePapers)
        """
    }

    func parseRecommendationAIEvaluationResponse(_ response: String, model: String, result: RecommendationRunResult) -> RecommendationAIEvaluation {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText = recommendationEvaluationJSONText(from: trimmed)
        let idAliasMap = recommendationScoreIDAliasMap(result)
        var overall = ""
        var commentsByID: [String: String] = [:]
        var reviewsByID: [String: RecommendationAIReview] = [:]
        if let data = jsonText.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            overall = (object["overall"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty ?? ""
            if let comments = object["comments"] as? [[String: Any]] {
                for comment in comments {
                    guard let rawID = (comment["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let text = (comment["comment"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let id = idAliasMap[recommendationNormalizedAIIdentifier(rawID)],
                          !text.isEmpty else {
                        continue
                    }
                    commentsByID[id] = text
                }
            }
            if let reviews = object["reviews"] as? [[String: Any]] {
                for review in reviews {
                    guard let rawID = (review["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let id = idAliasMap[recommendationNormalizedAIIdentifier(rawID)] else {
                        continue
                    }
                    let parsed = RecommendationAIReview(
                        relevance: recommendationDouble(from: review["relevance"]),
                        novelty: recommendationDouble(from: review["novelty"]),
                        methodSoundness: recommendationDouble(from: review["method_soundness"] ?? review["methodSoundness"]),
                        usefulness: recommendationDouble(from: review["usefulness"]),
                        risk: recommendationDouble(from: review["risk"]),
                        summary: ((review["summary"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        recommendationComment: ((review["recommendation_comment"] as? String) ?? (review["comment"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        suitableFor: recommendationStringList(from: review["suitable_for"]),
                        possibleWeaknesses: recommendationStringList(from: review["possible_weaknesses"])
                    )
                    reviewsByID[id] = parsed
                    if commentsByID[id] == nil {
                        commentsByID[id] = parsed.recommendationComment.nilIfAppEmpty ?? parsed.summary
                    }
                }
            }
        } else {
            overall = trimmed.hasPrefix("{") || trimmed.hasPrefix("[") ? "" : trimmed
        }
        return RecommendationAIEvaluation(model: model, overall: overall, commentsByScoreID: commentsByID, reviewsByScoreID: reviewsByID, generatedAt: Date())
    }

    func recommendationScoreIDAliasMap(_ result: RecommendationRunResult) -> [String: String] {
        var aliases: [String: String] = [:]
        for score in result.scores {
            let rawKeys = [
                score.id,
                score.candidate.canonicalID,
                score.candidate.externalKey,
                score.candidate.paperID,
                score.candidate.sourceURL
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfAppEmpty }
            for key in rawKeys {
                let normalized = recommendationNormalizedAIIdentifier(key)
                aliases[normalized] = score.id
                if normalized.hasPrefix("external:") {
                    aliases[String(normalized.dropFirst("external:".count))] = score.id
                }
                if normalized.hasPrefix("paper:") {
                    aliases[String(normalized.dropFirst("paper:".count))] = score.id
                }
                if normalized.hasPrefix("arxiv:") {
                    aliases["external:\(normalized)"] = score.id
                    aliases[String(normalized.dropFirst("arxiv:".count))] = score.id
                }
            }
        }
        return aliases
    }

    func recommendationNormalizedAIIdentifier(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return ""
        }
        if let url = URL(string: trimmed),
           let last = url.pathComponents.last?.trimmingCharacters(in: .whitespacesAndNewlines),
           !last.isEmpty {
            if url.host?.contains("arxiv.org") == true {
                return "arxiv:\(last.replacingOccurrences(of: ".pdf", with: ""))"
            }
            return last
        }
        return trimmed
    }

    func recommendationDouble(from value: Any?) -> Double {
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let string = value as? String, let double = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return double
        }
        return 0
    }

    func recommendationEvaluationJSONText(from response: String) -> String {
        if let open = response.firstIndex(of: "{"),
           let close = response.lastIndex(of: "}"),
           open <= close {
            return String(response[open...close])
        }
        return response
    }

}
