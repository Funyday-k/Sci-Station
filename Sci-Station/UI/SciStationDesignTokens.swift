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

extension View {
    func sciStationPanel(
        radius: CGFloat = SciStationDesign.compactCornerRadius,
        tint: Color = SciStationDesign.panelTint,
        border: Color = SciStationDesign.hairline
    ) -> some View {
        modifier(SciStationPanelStyle(radius: radius, tint: tint, border: border))
    }
}