import Foundation

public protocol APIKeyStore: Sendable {
    func save(apiKey: String, for account: String) async throws
    func loadAPIKey(for account: String) async throws -> String?
    func deleteAPIKey(for account: String) async throws
}
