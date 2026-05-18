import AppKit
import SwiftUI

/// Sci-Station launch splash. Uses the native iOS 26 / macOS 26 Liquid Glass
/// API so the panel actually refracts whatever is behind the splash window
/// instead of looking like a flat translucent plate. The morph from a small
/// circular seed into the wider rounded-rectangle panel is driven by a
/// single SwiftUI frame + `AnimatableRoundedRect` cornerRadius animation
/// – no view-tree diff, no matched-geometry pipeline – which is the
/// cheapest path SwiftUI can take and therefore the smoothest.
struct SciStationLaunchAnimationView: View {
    @State private var isExpanded = false
    @State private var titleVisible = false

    private let seedSize: CGFloat = 122
    private let panelWidth: CGFloat = 460
    private let panelHeight: CGFloat = 134
    /// Final rounded-rectangle radius for the panel state. Matches Apple's
    /// docs example "second style" (`.rect(cornerRadius: 16)`-ish look).
    private let panelCornerRadius: CGFloat = 28

    /// Outer canvas: enough room around the final panel for the soft white
    /// ambient halo + dark drop shadow to bleed without ever reaching the
    /// splash window's edge.
    private var canvasSize: CGSize {
        CGSize(width: panelWidth + 120, height: panelHeight + 120)
    }

    /// SwiftUI animates this scalar through `AnimatableRoundedRect`'s
    /// `animatableData`, so the cornerRadius interpolates frame-by-frame
    /// from a perfect circle (seedSize / 2) to the final rounded-rectangle
    /// radius alongside the frame morph.
    private var currentCornerRadius: CGFloat {
        isExpanded ? panelCornerRadius : seedSize / 2
    }

    var body: some View {
        ZStack {
            // A *single* Color.clear surface whose frame and cornerRadius
            // animate together. `AnimatableRoundedRect` keeps the shape
            // morphing smoothly from a circle into the rounded-rectangle
            // panel.
            //
            // `.glassEffect(.clear, ...)` is Apple's high-transmission
            // Liquid Glass variant – no opaque base layer, the desktop
            // really does come through and refract. The visible structure
            // is provided by the soft white halo + ambient drop shadow,
            // so we don't need any background tint or dimming layer.
            GlassEffectContainer(spacing: 0) {
                Color.clear
                    .frame(
                        width: isExpanded ? panelWidth : seedSize,
                        height: isExpanded ? panelHeight : seedSize
                    )
                    .glassEffect(.clear, in: AnimatableRoundedRect(cornerRadius: currentCornerRadius))
                    .shadow(color: .white.opacity(0.34), radius: 22, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.22), radius: 38, x: 0, y: 14)
            }

            // Title sits as a sibling so it never gets truncated inside the
            // morphing surface. drawingGroup() rasterizes the SnellRoundhand
            // glyph cache + drop shadow once on the GPU so opacity tweens
            // are a cheap Metal blend.
            Text("Sci-Station")
                .font(.custom("SnellRoundhand-Bold", size: 52))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.32), radius: 5, x: 0, y: 1)
                .drawingGroup()
                .opacity(titleVisible ? 1 : 0)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .onAppear {
            // Brief seed dwell so the user reads "circle → grows into
            // panel" as a story, not a single frame jump. The spring with
            // damping 0.86 gives a slight settle without overshoot for an
            // organic, fluid morph.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 240_000_000)
                withAnimation(.spring(response: 0.58, dampingFraction: 0.86)) {
                    isExpanded = true
                    titleVisible = true
                }
            }
        }
    }
}

/// Custom rounded-rectangle Shape that exposes its cornerRadius through
/// `animatableData`, so SwiftUI's animation pipeline can interpolate it
/// frame-by-frame inside a `withAnimation` block. We need this because
/// the `.rect(cornerRadius:)` factory yields a `RoundedRectangle` whose
/// radius is fixed at view-build time and won't tween.
private struct AnimatableRoundedRect: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        return Path(roundedRect: rect, cornerRadius: clamped)
    }
}

struct SciStationLaunchAnimationView_Previews: PreviewProvider {
    static var previews: some View {
        SciStationLaunchAnimationView()
            .frame(width: 600, height: 280)
            .background(Color.gray.opacity(0.25))
    }
}
