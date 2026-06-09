import Foundation

/// Maps the shared `Priority` model onto the Tasks UI's "red flag" metaphor,
/// where importance is shown as up to three red flags (requirement: 最高三个红旗).
///
/// - 1 flag  → `.low`
/// - 2 flags → `.medium`
/// - 3 flags → `.high`
///
/// `.urgent` is retained for Apple Reminders interop and renders as three flags.
public extension Priority {
    /// Number of filled red flags (1...3) used to represent this priority.
    var flagCount: Int {
        switch self {
        case .low:
            return 1
        case .medium:
            return 2
        case .high, .urgent:
            return 3
        }
    }

    /// Priorities the Tasks composer lets the user choose between, in flag order.
    static var flagSelectable: [Priority] {
        [.low, .medium, .high]
    }

    /// Resolves a 1...3 flag count back into a selectable `Priority`.
    static func fromFlagCount(_ count: Int) -> Priority {
        switch max(1, min(3, count)) {
        case 1:
            return .low
        case 2:
            return .medium
        default:
            return .high
        }
    }
}
