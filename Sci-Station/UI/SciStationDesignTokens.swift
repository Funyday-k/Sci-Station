import SwiftUI

enum SciStationDesign {
    static let compactCornerRadius: CGFloat = 8
    static let rowCornerRadius: CGFloat = 7

    static var panelTint: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.72)
    }

    static var subtleSurface: Color {
        Color.primary.opacity(0.028)
    }

    static var groupedSurface: Color {
        Color.secondary.opacity(0.045)
    }

    static var hoverSurface: Color {
        Color.primary.opacity(0.045)
    }

    static var hairline: Color {
        Color(nsColor: .separatorColor).opacity(0.76)
    }

    static func projectSurface(hex: String, isSelected: Bool) -> Color {
        Color(hex: hex).opacity(isSelected ? 0.14 : 0.065)
    }
}

// MARK: - Additive token scales (Phase 0 design system)
//
// These namespaces standardize spacing, corner radii, semantic colors and
// typography roles so views can stop hand-coding magic opacities and radii.
// They are additive: existing `SciStationDesign` members above are unchanged.

extension SciStationDesign {
    /// 4pt-based spacing scale.
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Unified corner radii (replaces ad-hoc 6/7/8/12 usage over time).
    enum Radius {
        static let control: CGFloat = 6
        static let row: CGFloat = rowCornerRadius
        static let compact: CGFloat = compactCornerRadius
        static let card: CGFloat = 12
    }

    /// Semantic colors. Backed by `NSColor` system colors so they adapt to
    /// light/dark automatically and match platform conventions.
    enum Semantic {
        static let success = Color(nsColor: .systemGreen)
        static let warning = Color(nsColor: .systemOrange)
        static let danger = Color(nsColor: .systemRed)
        static let info = Color(nsColor: .systemBlue)
        static let accent = Color.accentColor

        /// A low-contrast tinted surface for badges/cards, derived from a role color.
        static func surface(_ color: Color, opacity: Double = 0.12) -> Color {
            color.opacity(opacity)
        }
    }

    /// Typography roles. Centralizes the small set of fonts used across panels.
    enum Typography {
        static let sectionTitle = Font.headline.weight(.semibold)
        static let cardTitle = Font.subheadline.weight(.semibold)
        static let body = Font.body
        static let metadata = Font.caption
        static let metadataStrong = Font.caption.weight(.medium)
        static let badge = Font.caption2.weight(.semibold)
    }
}

struct SciStationPanelStyle: ViewModifier {
    var radius: CGFloat = SciStationDesign.compactCornerRadius
    var tint: Color = SciStationDesign.panelTint
    var border: Color = SciStationDesign.hairline

    func body(content: Content) -> some View {
        content
            .background(tint, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(border, lineWidth: 0.7)
            }
    }
}

/// Stable, back-deployable replacement for per-view `glassEffect` calls.
///
/// Applying many dynamic glass effects inside draggable/resizable grids can make
/// SwiftUI rebuild the visual-effect graph several times in a frame. A material
/// surface preserves the native macOS appearance while avoiding that update loop
/// and respecting Reduce Transparency on every supported macOS release.
private struct SciStationGlassSurfaceModifier<S: Shape>: ViewModifier {
    let tint: Color
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay {
                shape.fill(tint)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func sciStationPanel(
        radius: CGFloat = SciStationDesign.compactCornerRadius,
        tint: Color = SciStationDesign.panelTint,
        border: Color = SciStationDesign.hairline
    ) -> some View {
        modifier(SciStationPanelStyle(radius: radius, tint: tint, border: border))
    }

    func sciStationGlassSurface<S: Shape>(
        tint: Color = .clear,
        in shape: S
    ) -> some View {
        modifier(SciStationGlassSurfaceModifier(tint: tint, shape: shape))
    }
}
