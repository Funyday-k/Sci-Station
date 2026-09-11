import Testing
@testable import SciStationCore

@Suite("Credential broker")
struct CredentialBrokerTests {
    @Test("Credential status and resolution never require app-wide plaintext state")
    func statusAndResolution() async throws {
        let store = InMemoryCredentialStore()
        let broker = CredentialBroker(store: store)
        let account = "workspace/test#llm"

        let empty = try await broker.status(for: .llmAPIKey, account: account)
        #expect(empty.isConfigured == false)

        _ = try await broker.save("  secret-value  ", for: .llmAPIKey, account: account)
        let configured = try await broker.status(for: .llmAPIKey, account: account)
        #expect(configured.isConfigured)
        #expect(try await broker.resolve(for: .llmAPIKey, account: account) == "secret-value")

        _ = try await broker.save("", for: .llmAPIKey, account: account)
        let stillConfigured = try await broker.status(for: .llmAPIKey, account: account)
        #expect(stillConfigured.isConfigured)

        _ = try await broker.delete(for: .llmAPIKey, account: account)
        #expect(try await broker.status(for: .llmAPIKey, account: account).isConfigured == false)
    }

    @Test("Credential kinds are isolated and legacy MinerU accounts migrate")
    func kindsAreIsolatedAndLegacyValuesMigrate() async throws {
        let store = InMemoryCredentialStore()
        let broker = CredentialBroker(store: store)
        let account = "workspace/test"

        try await store.save(apiKey: "legacy-mineru", for: "\(account)#mineru-api")
        #expect(try await broker.resolve(for: .minerUAPIToken, account: account) == "legacy-mineru")
        #expect(try await broker.resolve(for: .llmAPIKey, account: account).isEmpty)

        _ = try await broker.save("llm-value", for: .llmAPIKey, account: account)
        _ = try await broker.save("miner-value", for: .minerUAPIToken, account: account)
        #expect(try await broker.resolve(for: .llmAPIKey, account: account) == "llm-value")
        #expect(try await broker.resolve(for: .minerUAPIToken, account: account) == "miner-value")

        _ = try await broker.delete(for: .minerUAPIToken, account: account)
        #expect(try await broker.resolve(for: .minerUAPIToken, account: account).isEmpty)
        #expect(try await broker.resolve(for: .llmAPIKey, account: account) == "llm-value")
    }
}
