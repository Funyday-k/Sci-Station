import Combine
import Foundation
import Testing
@testable import SciStationCore

@Suite("Graph store")
@MainActor
struct GraphStoreTests {
    @Test("Graph failures retain diagnostics and retry the same load operation")
    func failureAndRetry() async {
        let store = GraphStore()
        var attempts = 0

        #expect(store.state == .idle)
        #expect(store.repository == nil)
        #expect(!store.canRetry)

        await store.load {
            attempts += 1
            if attempts == 1 {
                throw GraphStoreFixtureError.initializationFailed
            }
            return GraphRepository()
        }

        guard case let .failed(diagnostic) = store.state else {
            Issue.record("Expected a failed graph state.")
            return
        }
        #expect(diagnostic.message == "Graph fixture initialization failed.")
        #expect(diagnostic.failureReason == "The fixture database could not be opened.")
        #expect(diagnostic.recoverySuggestion == "Retry the fixture load.")
        #expect(diagnostic.errorType.contains("GraphStoreFixtureError"))
        #expect(diagnostic.technicalDetails.contains("initializationFailed"))
        #expect(store.repository == nil)
        #expect(store.canRetry)
        #expect(attempts == 1)

        await Task.yield()
        guard case .failed = store.state else {
            Issue.record("Failure state changed before retry started.")
            return
        }

        await store.retry()

        #expect(store.state == .ready)
        #expect(store.repository != nil)
        #expect(store.diagnostic == nil)
        #expect(!store.canRetry)
        #expect(attempts == 2)
        await store.reset()
    }

    @Test("Replacing and resetting graph loads close prior repositories")
    func replacementClosesRepositories() async throws {
        let fixture = try GraphStoreFixture()
        defer { fixture.cleanup() }
        let firstRepository = try await fixture.openRepository(named: "first")
        let secondRepository = try await fixture.openRepository(named: "second")
        let store = GraphStore()

        await store.load { firstRepository }
        #expect(store.state == .ready)

        await store.load { secondRepository }
        #expect(store.state == .ready)
        #expect(store.repository === secondRepository)
        await expectNotOpen(firstRepository)

        await store.reset()
        #expect(store.state == .idle)
        #expect(store.repository == nil)
        #expect(!store.canRetry)
        await expectNotOpen(secondRepository)
    }

    @Test("A stale graph load closes its repository without replacing the latest result")
    func staleLoadIsDisposed() async throws {
        let fixture = try GraphStoreFixture()
        defer { fixture.cleanup() }
        let staleRepository = try await fixture.openRepository(named: "stale")
        let currentRepository = try await fixture.openRepository(named: "current")
        let barrier = GraphStoreLoadBarrier()
        let store = GraphStore()

        let staleTask = Task { @MainActor in
            await store.load {
                await barrier.reachAndWait()
                return staleRepository
            }
        }

        await barrier.waitUntilReached()
        #expect(store.state == .loading)

        await store.load { currentRepository }
        #expect(store.state == .ready)
        #expect(store.repository === currentRepository)

        await barrier.release()
        await staleTask.value

        #expect(store.state == .ready)
        #expect(store.repository === currentRepository)
        await expectNotOpen(staleRepository)

        try await currentRepository.upsertNode(Self.node("paper:current"))
        await store.reset()
    }

    @Test("Cancelling a non-cooperative graph load disposes its repository")
    func cancelledLoadIsDisposed() async throws {
        let fixture = try GraphStoreFixture()
        defer { fixture.cleanup() }
        let cancelledRepository = try await fixture.openRepository(named: "cancelled")
        let barrier = GraphStoreLoadBarrier()
        let store = GraphStore()

        let loadTask = Task { @MainActor in
            await store.load {
                await barrier.reachAndWait()
                return cancelledRepository
            }
        }

        await barrier.waitUntilReached()
        #expect(store.state == .loading)

        loadTask.cancel()
        await barrier.release()
        await loadTask.value

        #expect(store.state == .idle)
        #expect(store.repository == nil)
        #expect(!store.canRetry)
        await expectNotOpen(cancelledRepository)
    }

    @Test("Graph state and repository publish as one valid snapshot")
    func stateAndRepositoryPublishAtomically() async throws {
        let fixture = try GraphStoreFixture()
        defer { fixture.cleanup() }
        let firstRepository = try await fixture.openRepository(named: "atomic-first")
        let secondRepository = try await fixture.openRepository(named: "atomic-second")
        let barrier = GraphStoreLoadBarrier()
        let store = GraphStore()
        var observedInvalidSnapshot = false
        let observation = store.objectWillChange.sink {
            if store.state == .ready, store.repository == nil {
                observedInvalidSnapshot = true
            }
        }

        await store.load { firstRepository }
        let replacementTask = Task { @MainActor in
            await store.load {
                await barrier.reachAndWait()
                return secondRepository
            }
        }
        await barrier.waitUntilReached()

        #expect(store.state == .loading)
        #expect(store.repository == nil)
        #expect(!observedInvalidSnapshot)

        await barrier.release()
        await replacementTask.value
        #expect(store.state == .ready)
        #expect(store.repository === secondRepository)
        #expect(!observedInvalidSnapshot)

        withExtendedLifetime(observation) {}
        await store.reset()
    }

    @Test("Restoring a ready repository advances the observable graph revision")
    func readyRestoreAdvancesRevision() async throws {
        let fixture = try GraphStoreFixture()
        defer { fixture.cleanup() }
        let firstRepository = try await fixture.openRepository(named: "revision-first")
        let secondRepository = try await fixture.openRepository(named: "revision-second")
        let store = GraphStore()

        await store.load { firstRepository }
        let firstReadyRevision = store.revision

        store.restore(GraphStore.Snapshot(
            state: .ready,
            repository: secondRepository,
            loadOperation: nil
        ))

        #expect(store.state == .ready)
        #expect(store.repository === secondRepository)
        #expect(store.revision != firstReadyRevision)

        await firstRepository.close()
        await store.reset()
    }

    private func expectNotOpen(_ repository: GraphRepository) async {
        do {
            try await repository.upsertNode(Self.node("paper:closed-\(UUID().uuidString)"))
            Issue.record("Expected the graph repository to be closed.")
        } catch GraphError.notOpen {
            // Expected.
        } catch {
            Issue.record("Unexpected graph repository error: \(error)")
        }
    }

    private static func node(_ id: String) -> GraphNode {
        let now = Date()
        return GraphNode(
            id: id,
            kind: .paper,
            displayName: id,
            createdAt: now,
            updatedAt: now,
            sourceHash: nil,
            lastIndexedAt: now
        )
    }
}

private enum GraphStoreFixtureError: LocalizedError {
    case initializationFailed

    var errorDescription: String? { "Graph fixture initialization failed." }
    var failureReason: String? { "The fixture database could not be opened." }
    var recoverySuggestion: String? { "Retry the fixture load." }
}

private struct GraphStoreFixture {
    let directoryURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SciStationGraphStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func openRepository(named name: String) async throws -> GraphRepository {
        let rootURL = directoryURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let repository = GraphRepository()
        try await repository.open(in: ResearchRoot(rootURL: rootURL))
        return repository
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private actor GraphStoreLoadBarrier {
    private var didReach = false
    private var didRelease = false
    private var reachedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func reachAndWait() async {
        didReach = true
        reachedContinuation?.resume()
        reachedContinuation = nil

        guard !didRelease else {
            return
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilReached() async {
        guard !didReach else {
            return
        }
        await withCheckedContinuation { continuation in
            reachedContinuation = continuation
        }
    }

    func release() {
        didRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
