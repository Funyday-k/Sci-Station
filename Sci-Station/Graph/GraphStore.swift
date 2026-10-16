import Combine
import Foundation

struct GraphFailureDiagnostic: Equatable, Sendable {
    let message: String
    let failureReason: String?
    let recoverySuggestion: String
    let errorType: String
    let technicalDetails: String
    let occurredAt: Date

    init(error: Error, occurredAt: Date = Date()) {
        let localizedError = error as? LocalizedError
        message = error.localizedDescription
        failureReason = localizedError?.failureReason
        recoverySuggestion = localizedError?.recoverySuggestion
            ?? "Retry graph initialization. If the problem continues, inspect the diagnostic details."
        errorType = String(reflecting: type(of: error))
        technicalDetails = String(reflecting: error)
        self.occurredAt = occurredAt
    }
}

@MainActor
final class GraphStore: ObservableObject {
    enum State: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed(GraphFailureDiagnostic)
    }

    typealias LoadOperation = @MainActor () async throws -> GraphRepository

    struct Snapshot {
        let state: State
        let repository: GraphRepository?
        let loadOperation: LoadOperation?
    }

    private struct Storage {
        let state: State
        let repository: GraphRepository?
        let revision: Int
    }

    @Published private var storage = Storage(state: .idle, repository: nil, revision: 0)

    private var loadOperation: LoadOperation?
    private var loadGeneration = 0

    var state: State {
        storage.state
    }

    var repository: GraphRepository? {
        storage.repository
    }

    var revision: Int {
        storage.revision
    }

    var diagnostic: GraphFailureDiagnostic? {
        guard case let .failed(diagnostic) = state else {
            return nil
        }
        return diagnostic
    }

    var canRetry: Bool {
        guard case .failed = state else {
            return false
        }
        return loadOperation != nil
    }

    func load(using operation: @escaping LoadOperation) async {
        loadOperation = operation
        await performLoad(using: operation)
    }

    func retry() async {
        guard canRetry, let loadOperation else {
            return
        }
        await performLoad(using: loadOperation)
    }

    func readModel() -> GraphReadModel? {
        repository.map(GraphReadModel.init(repository:))
    }

    func snapshot() -> Snapshot {
        Snapshot(state: state, repository: repository, loadOperation: loadOperation)
    }

    func restore(_ snapshot: Snapshot) {
        loadGeneration += 1
        loadOperation = snapshot.loadOperation
        publish(state: snapshot.state, repository: snapshot.repository)
    }

    func reset() async {
        loadGeneration += 1
        let previousRepository = repository
        loadOperation = nil
        publish(state: .idle, repository: nil)
        await previousRepository?.close()
    }

    private func performLoad(using operation: LoadOperation) async {
        loadGeneration += 1
        let generation = loadGeneration
        let previousRepository = repository
        publish(state: .loading, repository: nil)
        await previousRepository?.close()

        guard generation == loadGeneration else {
            return
        }
        guard !Task.isCancelled else {
            finishCancellation(generation: generation)
            return
        }

        do {
            let loadedRepository = try await operation()
            guard generation == loadGeneration else {
                await loadedRepository.close()
                return
            }
            guard !Task.isCancelled else {
                await loadedRepository.close()
                guard generation == loadGeneration else {
                    return
                }
                finishCancellation(generation: generation)
                return
            }
            publish(state: .ready, repository: loadedRepository)
        } catch {
            guard generation == loadGeneration else {
                return
            }
            if error is CancellationError || Task.isCancelled {
                finishCancellation(generation: generation)
            } else {
                publish(state: .failed(GraphFailureDiagnostic(error: error)), repository: nil)
            }
        }
    }

    private func finishCancellation(generation: Int) {
        guard generation == loadGeneration else {
            return
        }
        loadOperation = nil
        publish(state: .idle, repository: nil)
    }

    private func publish(state: State, repository: GraphRepository?) {
        storage = Storage(state: state, repository: repository, revision: storage.revision &+ 1)
    }
}
