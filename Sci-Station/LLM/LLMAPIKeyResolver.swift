import Foundation

public nonisolated enum LLMAPIKeyResolver {
    public static func resolve(inMemory: String, persisted: String?) -> String {
        let trimmedInMemory = inMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInMemory.isEmpty {
            return trimmedInMemory
        }

        return persisted?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
