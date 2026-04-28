import Foundation

public struct BatchImportInputParser: Sendable {
    public nonisolated init() {}

    public nonisolated func parse(_ input: String) -> [String] {
        input
            .components(separatedBy: CharacterSet(charactersIn: "\n\r\t ,;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: []) { values, value in
                if !values.contains(value) {
                    values.append(value)
                }
            }
    }
}
