import Combine
import Foundation

/// Focused store for the Home and Project Dashboard reload signals, extracted
/// from `AppViewModel` as the first step of Performance Phase 3.
///
/// These revision tokens are bumped frequently whenever workspace data changes
/// (todos, drafts, queue, artifacts, ...). While they lived on `AppViewModel`,
/// every bump fired the app-wide `AppViewModel.objectWillChange`, invalidating
/// unrelated observers (Library, Settings, Shell, ...). Hosting them on a small
/// dedicated `ObservableObject` keeps that churn local to the Home / Dashboard
/// views, which subscribe to the published tokens directly.
@MainActor
public final class HomeDashboardStore: ObservableObject {
    @Published public private(set) var homeAggregationRevision = 0
    @Published public private(set) var projectDashboardRevision = 0

    public init() {}

    /// Signal that Home aggregation inputs changed and the snapshot should reload.
    public func markHomeAggregationChanged() {
        homeAggregationRevision &+= 1
    }

    /// Signal that Project Dashboard inputs changed. A dashboard change also
    /// affects the Home snapshot, so this bumps both tokens.
    public func markProjectDashboardChanged() {
        projectDashboardRevision &+= 1
        homeAggregationRevision &+= 1
    }
}
