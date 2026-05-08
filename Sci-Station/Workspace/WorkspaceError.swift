import Foundation

public enum WorkspaceError: LocalizedError {
    case invalidRootURL
    case incompatibleCreationTarget(String)
    case missingRequiredItems([String])

    public var errorDescription: String? {
        switch self {
        case .invalidRootURL:
            return "The selected location is not a valid local folder."
        case let .incompatibleCreationTarget(message):
            return message
        case let .missingRequiredItems(items):
            let formattedItems = items.joined(separator: ", ")
            return "The selected folder is not a valid ResearchWorkspace. Missing: \(formattedItems)."
        }
    }
}