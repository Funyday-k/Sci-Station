import Foundation

/// Centralised namespace of accessibility identifiers used by the AI Usage
/// Test orchestrator (`Proposal-AT.md` §P-AT.1c) and any future XCUITest
/// target.
///
/// **Why this exists**
///
/// SwiftUI views grow accessibility identifiers ad-hoc and the resulting
/// strings drift as features evolve. The Sci-Station AI uitest harness needs
/// a *stable, enumerable* contract so Python scenario YAML files can refer to
/// `library.paper.<id>` / `home.widget.<id>` / `queue.row.<id>` / `sidebar.tab.<top>`
/// without breaking each refactor.
///
/// **Naming convention** (mirrors `AppDebugEventName`):
///   `<domain>.<entity>(.<verb>|.<id>)?`
/// using snake_case tokens and `.` as separator. New identifiers must:
///   1. Be added as a static factory on this enum.
///   2. Pass `UITestAccessibilityID.isValidIdentifier(_:)`.
///   3. Be applied via the `.uitestID(_:)` view modifier defined in
///      `UITestAccessibilityIDViewModifier.swift`.
///
/// See `docs/development/Proposal-AT.md` §P-AT.1c.
public nonisolated enum UITestAccessibilityID {

    // MARK: - Sidebar (top-level navigation)
    public enum Sidebar {
        /// The main top-level routes (Home / Projects / Library / Calendar / AI Lab / Settings).
        /// Suffix matches `WorkspaceRoute.Top.rawValue`.
        public static func tab(_ top: String) -> String { "sidebar.tab.\(top)" }

        public static let projectTreeToggle = "sidebar.project_tree.toggle"
        public static let projectCreateButton = "sidebar.project.create"
    }

    // MARK: - Home widgets
    public enum Home {
        /// The widget container in the Home dashboard. Suffix is the
        /// `HomeWidgetID.rawValue` (e.g. `today`, `active_projects`).
        public static func widget(_ widgetID: String) -> String { "home.widget.\(widgetID)" }
        public static let editLayout = "home.layout.edit"
        public static let doneEditing = "home.layout.done"
        public static let resetDefault = "home.layout.reset"
        public static let gallery = "home.layout.gallery"
    }

    // MARK: - Library
    public enum Library {
        /// A row in the Library list, suffix is the paper's `id` (citekey or fallback).
        public static func paper(_ paperID: String) -> String { "library.paper.\(paperID)" }
        public static let importButton = "library.import.button"
        public static let list = "library.list"
        public static let emptyState = "library.empty_state"
    }

    // MARK: - Reading Queue
    public enum Queue {
        /// A row in the Reading Queue, suffix is the `ResearchQueueEntry.id`.
        public static func row(_ entryID: String) -> String { "queue.row.\(entryID)" }
        public static func moveUp(_ entryID: String) -> String { "queue.row.move_up.\(entryID)" }
        public static func moveDown(_ entryID: String) -> String { "queue.row.move_down.\(entryID)" }
        public static let list = "queue.list"
        public static let emptyState = "queue.empty_state"
    }

    // MARK: - Validation

    /// Lint helper used by tests to ensure identifiers stay machine-readable.
    ///
    /// The grammar is `prefix '.' suffix` where:
    ///
    /// * **prefix** is `<domain> '.' <entity> ('.' <verb>)?` — 2 or 3
    ///   strictly snake_case segments (lowercase ASCII / digits /
    ///   underscores). This is the stable namespace; tests rely on it.
    /// * **suffix** is the data identifier (paper id, widget id, queue
    ///   entry id, …). It MAY contain dots, hyphens and colons because
    ///   real-world IDs do (e.g. `arxiv-2604.22012`,
    ///   `queue:workspace:paper-1`). Suffix must contain at least one
    ///   ASCII alphanumeric and may not start with a separator character.
    ///
    /// Examples
    /// ```
    /// sidebar.tab.library                 -- ok (no suffix)
    /// home.widget.active_projects         -- ok
    /// library.paper.arxiv-2604.22012      -- ok (suffix has '.' '-')
    /// queue.row.queue:workspace:paper-1   -- ok (suffix has ':' '-')
    /// Library.Paper.x                     -- rejected (capital letters)
    /// library..paper                      -- rejected (empty segment)
    /// ```
    public static func isValidIdentifier(_ raw: String) -> Bool {
        guard !raw.isEmpty else { return false }
        let segments = raw.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard segments.count >= 2 else { return false }

        // Identify the prefix length: at most 3 strict snake_case segments.
        // Everything after that becomes the suffix and may contain dots.
        let prefixSegmentAllowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        var prefixLength = 0
        for (index, segment) in segments.enumerated() where index < 3 {
            if segment.isEmpty { return false }
            if segment.contains(where: { !prefixSegmentAllowed.contains($0) }) { break }
            prefixLength = index + 1
        }

        // Need at least <domain>.<entity>.
        guard prefixLength >= 2 else { return false }
        // No suffix is fine, e.g. `library.list`.
        if prefixLength == segments.count { return true }

        let suffix = segments[prefixLength..<segments.count].joined(separator: ".")
        let suffixAllowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-:.")
        guard !suffix.isEmpty else { return false }
        if suffix.first.map({ ":-.".contains($0) }) ?? false { return false }
        if suffix.contains(where: { !suffixAllowed.contains($0) }) { return false }
        return suffix.contains(where: { $0.isLetter || $0.isNumber })
    }
}
