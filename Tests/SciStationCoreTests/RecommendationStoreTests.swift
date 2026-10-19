import Combine
import Foundation
import Testing
@testable import SciStationCore

@Suite("Recommendation presentation state")
@MainActor
struct RecommendationStoreTests {
    @Test("History selection clears messages while retaining feedback and active work")
    func selectHistory() {
        let store = RecommendationStore()
        let result = makeResult(id: "selected", candidateCount: 7)
        store.setFeedback(["previous-score": .like])
        store.setErrorMessage("previous failure")
        store.setAIEvaluationStatusMessage("previous evaluation")
        store.setRefreshing(true)
        store.setEvaluatingWithAI(true)

        store.selectHistory(result)

        #expect(store.runResult == result)
        #expect(store.candidateCount == 7)
        #expect(store.errorMessage == nil)
        #expect(store.aiEvaluationStatusMessage == nil)
        #expect(store.feedbackByScoreID == ["previous-score": .like])
        #expect(store.isRefreshing)
        #expect(store.isEvaluatingWithAI)
    }

    @Test("Archive replaces only the selected run and preserves the existing presentation policy")
    func archiveHistory() {
        let store = RecommendationStore()
        let selected = makeResult(id: "selected", candidateCount: 7)
        let remaining = makeResult(id: "remaining", candidateCount: 3)
        store.selectHistory(selected)
        store.recordFeedback(.save, scoreID: "score")
        store.setErrorMessage("existing error")

        store.applyArchivedHistory([selected], archivedID: remaining.id)
        #expect(store.runResult == selected)
        #expect(store.history == [selected])

        store.applyArchivedHistory([remaining], archivedID: selected.id)
        #expect(store.runResult == remaining)
        #expect(store.history == [remaining])
        #expect(store.candidateCount == 7)
        #expect(store.feedbackByScoreID == ["score": .save])
        #expect(store.errorMessage == "existing error")

        store.applyArchivedHistory([], archivedID: remaining.id)
        #expect(store.runResult == nil)
        #expect(store.history.isEmpty)
    }

    @Test("Refresh clears prior messages without discarding visible results")
    func beginRefresh() {
        let store = RecommendationStore()
        let result = makeResult(id: "previous", candidateCount: 4)
        store.selectHistory(result)
        store.setHistory([result])
        store.setErrorMessage("network failure")
        store.setAIEvaluationStatusMessage("unavailable")

        store.beginRefresh()

        #expect(store.isRefreshing)
        #expect(!store.isEvaluatingWithAI)
        #expect(store.errorMessage == nil)
        #expect(store.aiEvaluationStatusMessage == nil)
        #expect(store.runResult == result)
        #expect(store.history == [result])
        #expect(store.candidateCount == 4)
    }

    @Test("Import admission deduplicates per destination and remains outside workspace snapshots")
    func importAdmissionAndRestoration() {
        let store = RecommendationStore()
        let selected = makeResult(id: "selected", candidateCount: 9)
        store.selectHistory(selected)
        let snapshot = store.snapshot()
        let navigation = NavigationStore()
        var navigationChanges = 0
        var recommendationChanges = 0
        let navigationObservation = navigation.objectWillChange.sink { navigationChanges += 1 }
        let recommendationObservation = store.objectWillChange.sink { recommendationChanges += 1 }

        #expect(store.beginImport(scoreID: "score", destination: .library))
        #expect(recommendationChanges == 1)
        #expect(!store.beginImport(scoreID: "score", destination: .library))
        let beforeReadingImport = recommendationChanges
        #expect(store.beginImport(scoreID: "score", destination: .readingTodo))
        #expect(recommendationChanges == beforeReadingImport + 1)
        #expect(store.beginImport(scoreID: "other", destination: .library))
        store.selectHistory(makeResult(id: "temporary", candidateCount: 1))
        store.restore(snapshot)

        #expect(store.runResult == selected)
        #expect(store.libraryImportScoreIDs == ["score", "other"])
        #expect(store.readingTodoImportScoreIDs == ["score"])
        store.reset()
        #expect(store.runResult == nil)
        #expect(!store.beginImport(scoreID: "score", destination: .library))
        let beforeLibraryFinish = recommendationChanges
        store.finishImport(scoreID: "score", destination: .library)
        #expect(recommendationChanges == beforeLibraryFinish + 1)
        #expect(store.libraryImportScoreIDs == ["other"])
        #expect(store.readingTodoImportScoreIDs == ["score"])
        #expect(store.beginImport(scoreID: "score", destination: .library))
        let beforeReadingFinish = recommendationChanges
        store.finishImport(scoreID: "score", destination: .readingTodo)
        #expect(recommendationChanges == beforeReadingFinish + 1)
        #expect(store.readingTodoImportScoreIDs.isEmpty)
        #expect(navigationChanges == 0)
        #expect(recommendationChanges > 0)
        withExtendedLifetime((navigationObservation, recommendationObservation)) {}
    }

    @Test("Feedback uses latest matching alias and global or matching project records")
    func feedbackProjection() {
        let score = RecommendationScore(
            id: "score", candidate: RecommendationCandidate(
                canonicalID: "arxiv:2601.00001", paperID: "local-paper",
                externalKey: "2601.00001", displayTitle: "Labeled test fixture"
            ), features: RecommendationFeatureBreakdown(), total: 1,
            evaluatedAt: Date(timeIntervalSince1970: 1)
        )
        let missing = RecommendationScore(
            id: "missing", candidate: RecommendationCandidate(
                canonicalID: "unmatched", displayTitle: "Unmatched test fixture"
            ), features: RecommendationFeatureBreakdown(), total: 0,
            evaluatedAt: Date(timeIntervalSince1970: 1)
        )
        var result = makeResult(id: "run", candidateCount: 2)
        result.contextProjectID = "project-a"
        result.scores = [score, missing]
        let records = [
            feedback(key: "external:2601.00001", project: "project-b", type: .ignore, time: 40),
            feedback(key: "paper:local-paper", project: "project-a", type: .save, time: 30),
            feedback(key: "arxiv:2601.00001", project: nil, type: .like, time: 10),
            feedback(key: "2601.00001", project: nil, type: .dislike, time: 20)
        ]

        #expect(RecommendationFeedbackStore.feedbackState(records: records, result: result) == ["score": .save])
        result.contextProjectID = nil
        #expect(RecommendationFeedbackStore.feedbackState(records: records, result: result) == ["score": .dislike])
        #expect(RecommendationFeedbackStore.feedbackState(records: [], result: result).isEmpty)
    }

    private func makeResult(id: String, candidateCount: Int) -> RecommendationRunResult {
        RecommendationRunResult(
            id: id, trigger: .manual, contextProjectID: nil,
            generatedAt: Date(timeIntervalSince1970: 1), candidateCount: candidateCount, scores: []
        )
    }

    private func feedback(
        key: String, project: String?, type: RecommendationFeedbackType, time: TimeInterval
    ) -> RecommendationFeedbackRecord {
        RecommendationFeedbackRecord(
            paperKey: key, projectID: project, feedbackType: type,
            recommendationRunID: "historical-run", createdAt: Date(timeIntervalSince1970: time)
        )
    }
}
