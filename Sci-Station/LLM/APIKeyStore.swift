import Foundation

protocol APIKeyStore {
    func save(apiKey: String, for account: String) async throws
    func loadAPIKey(for account: String) async throws -> String?
}