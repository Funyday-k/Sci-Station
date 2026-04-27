import Foundation

public struct TagDefinition: Identifiable, Codable, Hashable, Sendable {
    public var id: String {
        name
    }

    public var name: String
    public var colorHex: String
    public var textColorHex: String?

    public nonisolated init(name: String, colorHex: String, textColorHex: String? = nil) {
        self.name = name
        self.colorHex = colorHex
        self.textColorHex = textColorHex
    }
}