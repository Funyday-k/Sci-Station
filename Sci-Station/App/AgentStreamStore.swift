import Combine
import Foundation

/// Focused store for the highest-frequency Agent streaming state, extracted
/// from `AppViewModel` as part of Performance Phase 3.
///
/// The partial streaming response text is replaced on every streaming render
/// tick while a run is generating. While it lived on `AppViewModel`, each tick
/// fired the app-wide `AppViewModel.objectWillChange`, invalidating unrelated
/// observers (Library, Sidebar, Settings, ...). Hosting it on a small dedicated
/// `ObservableObject` keeps that churn local to the AI Lab views, which observe
/// this store directly.
@MainActor
public final class AgentStreamStore: ObservableObject {
    @Published public var streamingResponseText: String?

    public init() {}
}
