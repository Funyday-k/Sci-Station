import Foundation

/// Prepares a clean initial screen for an external XCUITest runner.
/// All interactions and assertions remain in the UI test process.
@MainActor
enum AppUITestHost {
    private static let argument = "--ui-test-host"
    private static let environmentKey = "SCI_STATION_UI_TEST_HOST"
    private static var didPrepare = false

    static func isRequested(processInfo: ProcessInfo = .processInfo) -> Bool {
        processInfo.arguments.contains(argument)
            || processInfo.environment[environmentKey] == "1"
    }

    static func makeAppModel() -> AppViewModel {
        guard isRequested() else { return AppViewModel() }
        let suiteName = "org.scistation.ui-test-host.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated UI test preferences.")
        }
        let service = WorkspaceService(bookmarkStore: WorkspaceBookmarkStore(defaults: defaults))
        return AppViewModel(workspaceService: service, installRuntimeBridges: false)
    }

    @discardableResult
    static func prepareIfRequested(
        appModel: AppViewModel,
        launchCoordinator: SciStationLaunchCoordinator
    ) -> Bool {
        guard isRequested() else { return false }
        guard !didPrepare else { return true }
        didPrepare = true
        appModel.selectSection(.dashboard)
        launchCoordinator.prepareForUITestHost()
        FileHandle.standardOutput.write(Data("SCI_STATION_UI_TEST_HOST_READY\n".utf8))
        return true
    }
}
