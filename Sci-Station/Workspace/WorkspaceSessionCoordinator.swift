import Foundation

/// Owns the lifecycle of the single workspace-opening task.
///
/// Opening a second workspace invalidates and cancels the previous generation.
/// Callers should check `isCurrent(_:)` around externally visible state changes;
/// this prevents a slow load from an old research root from publishing into the
/// newly selected session.
@MainActor
public final class WorkspaceSessionCoordinator {
    public typealias Generation = UInt64

    private var task: Task<Void, Never>?
    private var generation: Generation = 0

    public init() {}

    @discardableResult
    public func start(
        operation: @escaping @MainActor (_ generation: Generation) async -> Void
    ) -> Generation {
        task?.cancel()
        generation &+= 1
        let activeGeneration = generation
        task = Task { @MainActor in
            await operation(activeGeneration)
        }
        return activeGeneration
    }

    public func isCurrent(_ candidate: Generation) -> Bool {
        candidate == generation && !(task?.isCancelled ?? true)
    }

    public func finish(_ candidate: Generation) {
        guard candidate == generation else { return }
        task = nil
    }

    public func cancel() {
        task?.cancel()
        task = nil
        generation &+= 1
    }

    deinit {
        task?.cancel()
    }
}
