import Foundation

public actor WorkspaceBookmarkStore {
    private enum Keys {
        static let recentWorkspaceBookmark = "SciStation.recentWorkspaceBookmark"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func saveBookmarkData(_ data: Data) {
        defaults.set(data, forKey: Keys.recentWorkspaceBookmark)
    }

    public func restoreBookmarkURL() throws -> URL? {
        guard let bookmarkData = defaults.data(forKey: Keys.recentWorkspaceBookmark) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            let refreshedData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(refreshedData, forKey: Keys.recentWorkspaceBookmark)
        }

        return url
    }
}