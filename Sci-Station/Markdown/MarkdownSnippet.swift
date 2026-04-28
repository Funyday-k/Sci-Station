import Foundation

public struct MarkdownSnippet: Identifiable, Hashable, Sendable {
    public let trigger: String
    public let title: String
    public let body: String

    public nonisolated init(trigger: String, title: String, body: String) {
        self.trigger = trigger
        self.title = title
        self.body = body
    }

    public nonisolated var id: String {
        trigger
    }
}
