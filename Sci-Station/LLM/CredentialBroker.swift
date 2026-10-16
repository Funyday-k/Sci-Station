import Foundation

/// The only capability that application state needs from a credential store.
/// Callers receive a value for the duration of one operation; the broker never
/// publishes or caches plaintext credentials.
public actor CredentialBroker {
    public enum Kind: String, Codable, Hashable, Sendable {
        case llmAPIKey = "llm_api_key"
        case minerUAPIToken = "mineru_api_token"
    }

    public struct Status: Codable, Hashable, Sendable {
        public let kind: Kind
        public let isConfigured: Bool
        public let checkedAt: Date

        public init(kind: Kind, isConfigured: Bool, checkedAt: Date = Date()) {
            self.kind = kind
            self.isConfigured = isConfigured
            self.checkedAt = checkedAt
        }
    }

    private let store: any APIKeyStore

    public init(store: any APIKeyStore = KeychainAPIKeyStore()) {
        self.store = store
    }

    public func status(for kind: Kind, account: String) async throws -> Status {
        let value = try await storedValue(for: kind, account: account)
        let configured = !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return Status(kind: kind, isConfigured: configured)
    }

    @discardableResult
    public func save(_ value: String, for kind: Kind, account: String) async throws -> Status {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try await status(for: kind, account: account)
        }
        let normalizedAccount = normalizedAccount(for: kind, account: account)
        try await store.save(apiKey: trimmed, for: storageAccount(for: kind, account: normalizedAccount))
        try await deleteLegacyValues(for: kind, account: normalizedAccount)
        return Status(kind: kind, isConfigured: true)
    }

    public func resolve(for kind: Kind, account: String) async throws -> String {
        try await storedValue(for: kind, account: account)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @discardableResult
    public func delete(for kind: Kind, account: String) async throws -> Status {
        let normalizedAccount = normalizedAccount(for: kind, account: account)
        try await store.deleteAPIKey(for: storageAccount(for: kind, account: normalizedAccount))
        try await deleteLegacyValues(for: kind, account: normalizedAccount)
        return Status(kind: kind, isConfigured: false)
    }

    private func storedValue(for kind: Kind, account: String) async throws -> String? {
        let normalizedAccount = normalizedAccount(for: kind, account: account)
        let currentAccount = storageAccount(for: kind, account: normalizedAccount)
        if let currentValue = try await store.loadAPIKey(for: currentAccount) {
            return currentValue
        }

        for legacyAccount in legacyAccounts(for: kind, account: normalizedAccount) {
            guard let legacyValue = try await store.loadAPIKey(for: legacyAccount) else {
                continue
            }
            try await store.save(apiKey: legacyValue, for: currentAccount)
            try await store.deleteAPIKey(for: legacyAccount)
            return legacyValue
        }
        return nil
    }

    private func deleteLegacyValues(for kind: Kind, account: String) async throws {
        for legacyAccount in legacyAccounts(for: kind, account: account) {
            try await store.deleteAPIKey(for: legacyAccount)
        }
    }

    private func normalizedAccount(for kind: Kind, account: String) -> String {
        let legacyMinerUSuffix = "#mineru-api"
        if kind == .minerUAPIToken, account.hasSuffix(legacyMinerUSuffix) {
            return String(account.dropLast(legacyMinerUSuffix.count))
        }
        return account
    }

    private func storageAccount(for kind: Kind, account: String) -> String {
        "sci-station:\(kind.rawValue):\(account)"
    }

    private func legacyAccounts(for kind: Kind, account: String) -> [String] {
        switch kind {
        case .llmAPIKey:
            return [account]
        case .minerUAPIToken:
            return ["\(account)#mineru-api"]
        }
    }
}

/// Deterministic store used by tests and previews. It intentionally exposes
/// no inspection API beyond the same broker operations as Keychain.
public actor InMemoryCredentialStore: APIKeyStore {
    private var values: [String: String] = [:]

    public init() {}

    public func save(apiKey: String, for account: String) async throws {
        values[account] = apiKey
    }

    public func loadAPIKey(for account: String) async throws -> String? {
        values[account]
    }

    public func deleteAPIKey(for account: String) async throws {
        values[account] = nil
    }
}
