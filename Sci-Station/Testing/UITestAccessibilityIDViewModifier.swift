import SwiftUI

public extension View {
    /// Applies the given accessibility identifier and forces SwiftUI to
    /// surface it as an accessibility element so XCUITest / Accessibility
    /// API drivers can locate it. Using this modifier instead of the bare
    /// `.accessibilityIdentifier(_:)` ensures the AI uitest harness can
    /// always find the element even when the underlying control would be
    /// excluded from the accessibility tree (e.g. decorative HStacks).
    ///
    /// Validates the identifier in DEBUG builds; release builds skip the
    /// check for performance.
    @ViewBuilder
    func uitestID(_ identifier: String) -> some View {
        #if DEBUG
        let _: Void = {
            assert(
                UITestAccessibilityID.isValidIdentifier(identifier),
                "Invalid uitest identifier '\(identifier)'. See UITestAccessibilityID.isValidIdentifier."
            )
        }()
        #endif
        self
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }
}
