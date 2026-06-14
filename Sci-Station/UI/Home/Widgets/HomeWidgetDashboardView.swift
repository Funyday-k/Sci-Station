import AppKit
import Combine
import SwiftUI

// MARK: - Grid constants

private enum HomeWidgetGridConstants {
    /// Vertical/horizontal spacing between tiles.
    static let spacing: CGFloat = 14
    /// Used before the grid has measured its container. The live unit is
    /// derived from submitted column width so a 1×1 tile renders as a square.
    static let fallbackUnitSize: CGFloat = 152
    /// Prevents very narrow windows from collapsing widget cells into unusable
    /// strips before the responsive policy drops to fewer columns.
    static let minimumUnitSize: CGFloat = 96
    /// Outer padding so the grid never butts up against the scroll container.
    static let outerPadding: CGFloat = 0
}

private struct HomeWidgetGridWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Drag controller

/// Coordinates the live, push-aside drag UX in `HomeWidgetDashboardView`.
///
/// As the user drags a widget in edit mode, the controller tracks the source
/// item, the current pointer translation in grid coordinates, and a tentative
/// "preview" layout where the source has been logically inserted before
/// whichever widget the pointer is currently over. Sibling widgets render
/// from the preview layout, so they animate out of the way to make room —
/// matching the iPadOS/macOS Home Screen rearrange feel that the user
/// reported missing on 2026-05-17.
@MainActor
private final class HomeWidgetDragController: ObservableObject {
    @Published var draggedWidgetID: String?
    @Published var translation: CGSize = .zero
    @Published var previewLayout: HomeWidgetLayout?
    /// Snapshot of the layout at drag start. The dragged widget's render
    /// position is anchored to its `baseLayout` cell + translation, while
    /// siblings flow according to `previewLayout`. Without this anchor the
    /// dragged card's `.offset` would compose the gesture translation on top
    /// of an already-shifted preview cell, sending the card flying past the
    /// cursor and making the drop hit-test miss every target — the symptom
    /// the user reported as "snaps back to original spot".
    @Published var baseLayout: HomeWidgetLayout?

    var isDragging: Bool { draggedWidgetID != nil }

    func begin(widgetID: String, baseLayout: HomeWidgetLayout) {
        draggedWidgetID = widgetID
        translation = .zero
        previewLayout = baseLayout
        self.baseLayout = baseLayout
    }

    func update(translation: CGSize, previewLayout: HomeWidgetLayout) {
        self.translation = translation
        self.previewLayout = previewLayout
    }

    func end() {
        draggedWidgetID = nil
        translation = .zero
        previewLayout = nil
        baseLayout = nil
    }

    /// Look up an item in the captured `baseLayout` (i.e. its position at
    /// drag start, BEFORE any preview reorder). Returns nil between drags.
    func baseItem(_ widgetID: String) -> HomeWidgetLayoutItem? {
        baseLayout?.items.first { $0.widgetID == widgetID }
    }
}

// MARK: - Dashboard

struct HomeWidgetDashboardView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @StateObject private var dragController = HomeWidgetDragController()
    @State private var gridContainerWidth: CGFloat = 0

    let snapshot: HomeSnapshot

    private static let gridCoordinateSpace: String = "home-widget-grid"

    private var columns: Int {
        max(1, appModel.responsiveShellModel.homeWidgetColumns)
    }

    private var availableDescriptors: [HomeWidgetDescriptor] {
        HomeWidgetRegistry.availableDescriptors(in: appModel.workspaceModuleConfiguration)
    }

    private var normalizedLayout: HomeWidgetLayout {
        appModel.workspacePreferences.homeWidgetLayout.normalized(descriptors: availableDescriptors, columns: columns)
    }

    /// Layout used for rendering — during a drag this reflects the preview
    /// reorder so siblings animate out of the way.
    private var renderLayout: HomeWidgetLayout {
        dragController.previewLayout ?? normalizedLayout
    }

    private var visibleItems: [HomeWidgetLayoutItem] {
        renderLayout.visibleItems(descriptors: availableDescriptors, columns: columns)
    }

    private var totalRows: Int {
        visibleItems
            .map { item in
                let rs = max(1, item.size.rowSpan)
                return item.row + rs
            }
            .max() ?? 0
    }

    private var gridHeight: CGFloat {
        gridHeight(unitSize: gridUnitSize(forWidth: gridContainerWidth, cols: columns))
    }

    private func gridHeight(unitSize: CGFloat) -> CGFloat {
        guard totalRows > 0 else { return 0 }
        return CGFloat(totalRows) * unitSize
            + CGFloat(max(0, totalRows - 1)) * HomeWidgetGridConstants.spacing
    }

    private func gridUnitSize(forWidth width: CGFloat, cols: Int) -> CGFloat {
        let safeColumns = max(1, cols)
        guard width > 1 else { return HomeWidgetGridConstants.fallbackUnitSize }
        let totalSpacing = CGFloat(max(0, safeColumns - 1)) * HomeWidgetGridConstants.spacing
        return max(HomeWidgetGridConstants.minimumUnitSize, (width - totalSpacing) / CGFloat(safeColumns))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            toolbar

            if appModel.isShowingHomeWidgetGallery {
                HomeWidgetGalleryView(columns: columns)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if visibleItems.isEmpty {
                HomeWidgetEmptyState(columns: columns)
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.28), value: appModel.isShowingHomeWidgetGallery)
        .animation(.smooth(duration: 0.28), value: appModel.isEditingHomeLayout)
        .animation(appModel.isEditingHomeLayout ? .smooth(duration: 0.32) : nil, value: visibleItems)
        .onChange(of: appModel.isEditingHomeLayout) { _, isEditing in
            // Cancel any in-flight drag if the user exits edit mode mid-drag.
            if !isEditing {
                dragController.end()
            }
        }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let cols = max(1, columns)
            let unitSize = gridUnitSize(forWidth: proxy.size.width, cols: cols)
            let measuredGridHeight = gridHeight(unitSize: unitSize)

            GlassEffectContainer(spacing: HomeWidgetGridConstants.spacing) {
                ZStack(alignment: .topLeading) {
                    if appModel.isEditingHomeLayout {
                        gridBackdrop(unitSize: unitSize, cols: cols)
                    }

                    ForEach(visibleItems) { item in
                        if let descriptor = HomeWidgetRegistry.descriptor(id: item.widgetID) {
                            let isDragging = dragController.draggedWidgetID == item.widgetID
                            // Anchor the dragged card to its drag-start cell
                            // so `.offset(metrics + translation)` lands on the
                            // cursor exactly. Siblings continue to flow from
                            // the preview layout so they animate out of the
                            // way.
                            let positionItem: HomeWidgetLayoutItem = {
                                if isDragging, let base = dragController.baseItem(item.widgetID) {
                                    return base
                                }
                                return item
                            }()
                            let metrics = cellMetrics(for: positionItem, unitSize: unitSize, cols: cols)
                            HomeWidgetCard(
                                item: item,
                                descriptor: descriptor,
                                columns: cols,
                                cellSize: CGSize(width: metrics.width, height: metrics.height),
                                snapshot: snapshot,
                                isBeingDragged: isDragging,
                                onDragBegan: {
                                    beginDrag(item: item, cols: cols)
                                },
                                onDragChanged: { value in
                                    updateDrag(value: value, unitSize: unitSize, cols: cols)
                                },
                                onDragEnded: { value in
                                    endDrag(value: value, unitSize: unitSize, cols: cols)
                                }
                            )
                            .frame(width: metrics.width, height: metrics.height)
                            .offset(
                                x: metrics.x + (isDragging ? dragController.translation.width : 0),
                                y: metrics.y + (isDragging ? dragController.translation.height : 0)
                            )
                            .zIndex(isDragging ? 10 : 0)
                            .transition(appModel.isEditingHomeLayout ? .scale(scale: 0.96).combined(with: .opacity) : .identity)
                            .accessibilityIdentifier(UITestAccessibilityID.Home.widget(item.widgetID))
                        }
                    }
                }
                .frame(width: proxy.size.width, height: measuredGridHeight, alignment: .topLeading)
            }
        }
        .frame(height: gridHeight)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HomeWidgetGridWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(HomeWidgetGridWidthPreferenceKey.self) { width in
            guard abs(gridContainerWidth - width) > 0.5 else { return }
            gridContainerWidth = width
        }
        .coordinateSpace(name: Self.gridCoordinateSpace)
    }

    /// Capture the current layout as the drag baseline so siblings stay where
    /// they are at gesture start.
    private func beginDrag(item: HomeWidgetLayoutItem, cols: Int) {
        guard appModel.isEditingHomeLayout else { return }
        dragController.begin(widgetID: item.widgetID, baseLayout: normalizedLayout)
    }

    /// On every gesture tick, hit-test the cursor against the un-shifted
    /// `normalizedLayout` and rebuild a preview layout that inserts the
    /// source before that cell's widget. Siblings then animate to their
    /// new slots.
    ///
    /// Uses `value.location` (already in the named "home-widget-grid"
    /// coordinate space) directly instead of recomputing centre from cell
    /// metrics + translation. The metrics-based path is unstable while a
    /// preview is in flight because the dragged card's cell is itself
    /// moving in the preview layout.
    private func updateDrag(
        value: DragGesture.Value,
        unitSize: CGFloat,
        cols: Int
    ) {
        guard let sourceID = dragController.draggedWidgetID else { return }
        let preview = previewLayout(
            sourceID: sourceID,
            cursor: value.location,
            unitSize: unitSize,
            cols: cols
        )
        dragController.update(translation: value.translation, previewLayout: preview)
    }

    /// Commit the preview layout if the drop landed on a different cell;
    /// otherwise just clear the drag state. Uses the same `value.location`
    /// hit-test as `updateDrag` so the on-release commit matches whatever
    /// preview the user was seeing on the last frame, and uses `onto:` so
    /// forward and backward drags BOTH swap into the target's slot.
    private func endDrag(
        value: DragGesture.Value,
        unitSize: CGFloat,
        cols: Int
    ) {
        defer { dragController.end() }
        guard let sourceID = dragController.draggedWidgetID else { return }
        guard let targetID = widgetID(at: value.location, unitSize: unitSize, cols: cols),
              targetID != sourceID else {
            return
        }
        appModel.moveHomeWidget(sourceID, onto: targetID, columns: cols)
    }

    /// Pure helper used by `updateDrag` per-tick. Returns a layout copy with
    /// `sourceID` placed at the slot currently held by whichever widget lies
    /// under `cursor` (i.e. drop-target semantics). If the cursor is outside
    /// the grid or already over the source's own cell, returns the unchanged
    /// `normalizedLayout` so siblings stop animating (calmer feel near the
    /// drag origin).
    private func previewLayout(
        sourceID: String,
        cursor: CGPoint,
        unitSize: CGFloat,
        cols: Int
    ) -> HomeWidgetLayout {
        var preview = normalizedLayout
        if let targetID = widgetID(at: cursor, unitSize: unitSize, cols: cols),
           targetID != sourceID {
            preview.moveWidget(
                sourceID,
                onto: targetID,
                descriptors: availableDescriptors,
                columns: cols
            )
        }
        return preview
    }

    /// Look up the widget whose cell currently contains the given grid point.
    /// Returns nil for empty grid cells / out-of-bounds points.
    private func widgetID(at point: CGPoint, unitSize: CGFloat, cols: Int) -> String? {
        guard point.x >= 0, point.y >= 0 else { return nil }
        let pitchX = unitSize + HomeWidgetGridConstants.spacing
        let pitchY = unitSize + HomeWidgetGridConstants.spacing
        let col = min(cols - 1, max(0, Int(point.x / pitchX)))
        let row = max(0, Int(point.y / pitchY))
        // Use the un-previewed normalized layout for hit testing so the cell
        // we report is stable as the preview animates.
        let candidates = normalizedLayout.visibleItems(descriptors: availableDescriptors, columns: cols)
        for item in candidates {
            let cs = min(cols, max(1, item.size.columnSpan))
            let rs = max(1, item.size.rowSpan)
            if col >= item.column && col < item.column + cs
                && row >= item.row && row < item.row + rs {
                return item.widgetID
            }
        }
        return nil
    }

    /// Faint grid lines that only appear in edit mode so users understand it's a tile grid.
    @ViewBuilder
    private func gridBackdrop(unitSize: CGFloat, cols: Int) -> some View {
        let rows = max(totalRows, 1)
        ZStack(alignment: .topLeading) {
            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<cols, id: \.self) { col in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(0.05),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .frame(width: unitSize, height: unitSize)
                        .offset(
                            x: CGFloat(col) * (unitSize + HomeWidgetGridConstants.spacing),
                            y: CGFloat(row) * (unitSize + HomeWidgetGridConstants.spacing)
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cellMetrics(for item: HomeWidgetLayoutItem, unitSize: CGFloat, cols: Int) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let cs = min(cols, max(1, item.size.columnSpan))
        let rs = max(1, item.size.rowSpan)
        let x = CGFloat(item.column) * (unitSize + HomeWidgetGridConstants.spacing)
        let y = CGFloat(item.row) * (unitSize + HomeWidgetGridConstants.spacing)
        let w = CGFloat(cs) * unitSize + CGFloat(cs - 1) * HomeWidgetGridConstants.spacing
        let h = CGFloat(rs) * unitSize + CGFloat(rs - 1) * HomeWidgetGridConstants.spacing
        return (x, y, w, h)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(appModel.t(.routeHome))
                    .font(.title2.weight(.semibold))
                Text("\(visibleItems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.04)), in: Capsule())
            }

            Spacer(minLength: 0)

            if appModel.isEditingHomeLayout {
                Button {
                    appModel.showHomeWidgetGallery(!appModel.isShowingHomeWidgetGallery)
                } label: {
                    Label(appModel.t(.homeWidgetGallery), systemImage: "rectangle.grid.2x2")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityIdentifier(UITestAccessibilityID.Home.gallery)

                Button {
                    appModel.resetHomeWidgetLayout(columns: columns)
                } label: {
                    Label(appModel.t(.homeResetDefault), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityIdentifier(UITestAccessibilityID.Home.resetDefault)

                Button {
                    appModel.exitHomeLayoutEdit()
                } label: {
                    Label(appModel.t(.homeDoneEditing), systemImage: "checkmark")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .accessibilityIdentifier(UITestAccessibilityID.Home.doneEditing)
            } else {
                Button {
                    appModel.enterHomeLayoutEdit()
                } label: {
                    Label(appModel.t(.homeEditLayout), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .accessibilityIdentifier(UITestAccessibilityID.Home.editLayout)
            }
        }
    }
}

// MARK: - Widget Card

private struct HomeWidgetCard: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    let item: HomeWidgetLayoutItem
    let descriptor: HomeWidgetDescriptor
    let columns: Int
    let cellSize: CGSize
    let snapshot: HomeSnapshot

    /// True while this widget is the one the user is dragging; the parent
    /// dashboard renders the dragged card at the pointer location and
    /// up-shifts its z-index above sibling cards.
    let isBeingDragged: Bool
    let onDragBegan: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    private var effectiveSize: HomeWidgetSize {
        // Clamp visual size to available columns while preserving directional
        // variants. A 1×2 wide widget should not render as a 2×2 medium card
        // just because both consume two columns.
        let cs = min(columns, max(1, item.size.columnSpan))
        if item.size == .tall {
            return .tall
        }
        if item.size == .wide {
            return columns >= 2 ? .wide : .small
        }
        switch cs {
        case 1:
            return .small
        case 2: return .medium
        case 3: return .large
        default: return item.size
        }
    }

    private var accent: Color {
        HomeWidgetPalette.accent(for: descriptor)
    }

    private var tintOpacity: Double {
        if isBeingDragged { return 0.10 }
        if appModel.isEditingHomeLayout { return 0.045 }
        return 0.025
    }

    private var borderOpacity: Double {
        if isBeingDragged { return 0.65 }
        if appModel.isEditingHomeLayout { return 0.25 }
        return 0.0
    }

    private var cardCorner: CGFloat {
        switch effectiveSize {
        case .small, .wide, .tall: return 18
        case .medium: return 22
        case .large: return 26
        }
    }

    private var cardPadding: CGFloat {
        switch effectiveSize {
        case .small, .wide, .tall: return 12
        case .medium: return 16
        case .large: return 18
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacingForSize) {
            header

            HomeWidgetContentView(
                descriptor: descriptor,
                size: effectiveSize,
                snapshot: snapshot
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Suppress inner buttons during edit mode so the entire card can
            // initiate the DragGesture without competing inner button taps.
            .allowsHitTesting(!appModel.isEditingHomeLayout)
            .opacity(appModel.isEditingHomeLayout ? 0.85 : 1.0)
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(
            .regular.tint(appModel.liquidGlassTintColor.opacity(tintOpacity)),
            in: RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.10), Color.white.opacity(0.02)]
                            : [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCorner, style: .continuous)
                .stroke(accent.opacity(borderOpacity), lineWidth: 1.2)
        )
        .overlay(alignment: .topTrailing) {
            // Visible drag affordance + grabbing cursor only while editing.
            if appModel.isEditingHomeLayout {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        accent.opacity(0.10),
                        in: Capsule()
                    )
                    .padding(8)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
        .shadow(
            color: .black.opacity(isBeingDragged ? 0.18 : 0.04),
            radius: isBeingDragged ? 18 : 8,
            x: 0,
            y: isBeingDragged ? 10 : 4
        )
        .scaleEffect(isBeingDragged ? 1.03 : 1.0)
        .animation(.smooth(duration: 0.18), value: isBeingDragged)
        .onHover { hovering in
            updateCursor(hovering: hovering)
        }
        // Custom DragGesture is more reliable than `.onDrag` for SwiftUI views
        // inside a glass-effect ZStack on macOS, and gives us per-frame callbacks
        // so the parent can recompute the live "push aside" preview layout.
        .modifier(EditDragGestureModifier(
            enabled: appModel.isEditingHomeLayout,
            isBeingDragged: isBeingDragged,
            onBegan: onDragBegan,
            onChanged: onDragChanged,
            onEnded: onDragEnded
        ))
        .contextMenu {
            cardContextMenu
        }
    }

    private func updateCursor(hovering: Bool) {
        // Only flip the cursor while editing; outside edit mode the cards behave
        // like normal interactive cards, so the system pointer is correct.
        guard appModel.isEditingHomeLayout else {
            return
        }
        if hovering {
            NSCursor.openHand.push()
        } else {
            NSCursor.pop()
        }
    }

    private var spacingForSize: CGFloat {
        switch effectiveSize {
        case .small, .wide: return 8
        case .tall: return 10
        case .medium: return 12
        case .large: return 14
        }
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        Menu {
            ForEach(HomeWidgetSize.allCases.filter { descriptor.supportedSizes.contains($0) }, id: \.self) { size in
                Button {
                    appModel.resizeHomeWidget(item.widgetID, to: size, columns: columns)
                } label: {
                    Label(size.title(appModel: appModel), systemImage: item.size == size ? "checkmark" : sizeIcon(size))
                }
            }
        } label: {
            Label(item.size.title(appModel: appModel), systemImage: "arrow.up.left.and.arrow.down.right")
        }
        Button {
            appModel.moveHomeWidget(item.widgetID, offset: -1, columns: columns)
        } label: {
            Label(appModel.t(.homeMoveEarlier), systemImage: "chevron.up")
        }
        Button {
            appModel.moveHomeWidget(item.widgetID, offset: 1, columns: columns)
        } label: {
            Label(appModel.t(.homeMoveLater), systemImage: "chevron.down")
        }
        Divider()
        Button(role: .destructive) {
            appModel.toggleHomeWidget(item.widgetID, isEnabled: false, columns: columns)
        } label: {
            Label(appModel.t(.homeHideWidget), systemImage: "eye.slash")
        }
    }

    @ViewBuilder
    private var header: some View {
        if effectiveSize == .small {
            HStack(spacing: 6) {
                iconBadge(size: 22, fontSize: 11, corner: 6)
                Text(appModel.t(descriptor.titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if appModel.isEditingHomeLayout {
                    editControls
                        .transition(.opacity)
                }
            }
        } else {
            HStack(spacing: 10) {
                iconBadge(size: 28, fontSize: 14, corner: 8)
                Text(appModel.t(descriptor.titleKey))
                    .font(headerFont)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if appModel.isEditingHomeLayout {
                    editControls
                        .transition(.opacity)
                }
            }
        }
    }

    private var headerFont: Font {
        switch effectiveSize {
        case .small, .wide, .tall: return .caption.weight(.semibold)
        case .medium: return .headline
        case .large: return .title3.weight(.semibold)
        }
    }

    private func iconBadge(size: CGFloat, fontSize: CGFloat, corner: CGFloat) -> some View {
        Image(systemName: descriptor.systemImage)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(accent.opacity(0.95))
            .frame(width: size, height: size)
            .background(
                accent.opacity(0.10),
                in: RoundedRectangle(cornerRadius: corner, style: .continuous)
            )
    }

    private var editControls: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(HomeWidgetSize.allCases.filter { descriptor.supportedSizes.contains($0) }, id: \.self) { size in
                    Button {
                        appModel.resizeHomeWidget(item.widgetID, to: size, columns: columns)
                    } label: {
                        Label(size.title(appModel: appModel), systemImage: item.size == size ? "checkmark" : sizeIcon(size))
                    }
                }
            } label: {
                Image(systemName: sizeIcon(item.size))
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .help(item.size.title(appModel: appModel))

            Button {
                appModel.toggleHomeWidget(item.widgetID, isEnabled: false, columns: columns)
            } label: {
                Image(systemName: "eye.slash")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .help(appModel.t(.homeHideWidget))
        }
        .controlSize(.small)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.05)), in: Capsule())
    }

    private func sizeIcon(_ size: HomeWidgetSize) -> String {
        switch size {
        case .small: return "square"
        case .wide: return "rectangle"
        case .tall: return "rectangle.portrait"
        case .medium: return "square.grid.2x2"
        case .large: return "square.grid.3x3"
        }
    }

}

// MARK: - Conditional DragGesture modifier

/// Attaches an edit-mode `DragGesture` to a widget card. The gesture only
/// installs while `enabled` is true so non-edit-mode taps reach the inner
/// content buttons unimpeded.
///
/// `coordinateSpace: .named("home-widget-grid")` requires the parent
/// dashboard's grid to declare `.coordinateSpace(name: ...)`; the parent
/// uses the per-tick translation to recompute a live preview layout.
private struct EditDragGestureModifier: ViewModifier {
    let enabled: Bool
    let isBeingDragged: Bool
    let onBegan: () -> Void
    let onChanged: (DragGesture.Value) -> Void
    let onEnded: (DragGesture.Value) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("home-widget-grid"))
                    .onChanged { value in
                        if !isBeingDragged {
                            onBegan()
                        }
                        onChanged(value)
                    }
                    .onEnded(onEnded)
            )
        } else {
            content
        }
    }
}

private enum HomeWidgetPalette {
    static func accent(for descriptor: HomeWidgetDescriptor) -> Color {
        switch descriptor.id {
        case HomeWidgetID.today:
            return .orange
        case HomeWidgetID.activeProjects:
            return .accentColor
        case HomeWidgetID.aiReview:
            return .purple
        case HomeWidgetID.calendar:
            return .red
        case HomeWidgetID.recentPapers:
            return .indigo
        case HomeWidgetID.readingPlan:
            return .teal
        case HomeWidgetID.projectHealth:
            return .green
        case HomeWidgetID.quickActions:
            return .yellow
        default:
            return .accentColor
        }
    }
}

// MARK: - Gallery

private struct HomeWidgetGalleryView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let columns: Int

    private var layout: HomeWidgetLayout {
        appModel.workspacePreferences.homeWidgetLayout.normalized(descriptors: HomeWidgetRegistry.defaultDescriptors, columns: columns)
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(HomeWidgetRegistry.defaultDescriptors) { descriptor in
                galleryRow(for: descriptor)
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.045)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }

    private func galleryRow(for descriptor: HomeWidgetDescriptor) -> some View {
        let isAvailable = descriptor.isAvailable(in: appModel.workspaceModuleConfiguration)
        let isEnabled = layout.items.first { $0.widgetID == descriptor.id }?.isEnabled == true
        let accent = HomeWidgetPalette.accent(for: descriptor)
        return HStack(spacing: 10) {
            Image(systemName: descriptor.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isAvailable ? accent.opacity(0.9) : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    (isAvailable ? accent : .secondary).opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(appModel.t(descriptor.titleKey))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(isAvailable ? categoryTitle(descriptor.category) : appModel.tf(.homeWidgetUnavailableModulesFormat, descriptor.requiredModuleIDs.joined(separator: ", ")))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Toggle(isOn: Binding(
                get: { isEnabled && isAvailable },
                set: { appModel.toggleHomeWidget(descriptor.id, isEnabled: $0, columns: columns) }
            )) {
                Text(isEnabled ? appModel.t(.homeWidgetEnabled) : appModel.t(.homeWidgetDisabled))
            }
            .labelsHidden()
            .disabled(!isAvailable)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.035)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
    }

    private func categoryTitle(_ category: HomeWidgetCategory) -> String {
        switch category {
        case .research:
            return appModel.t(.homeWidgetCategoryResearch)
        case .ai:
            return appModel.t(.homeWidgetCategoryAI)
        case .calendar:
            return appModel.t(.homeWidgetCategoryCalendar)
        case .library:
            return appModel.t(.homeWidgetCategoryLibrary)
        case .project:
            return appModel.t(.homeWidgetCategoryProject)
        }
    }
}

private struct HomeWidgetEmptyState: View {
    @EnvironmentObject private var appModel: AppViewModel
    let columns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(appModel.t(.homeNoEnabledWidgets), systemImage: "rectangle.grid.1x2")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    appModel.showHomeWidgetGallery(true)
                    appModel.enterHomeLayoutEdit()
                } label: {
                    Label(appModel.t(.homeWidgetGallery), systemImage: "rectangle.grid.2x2")
                }
                .buttonStyle(.glass)
                Button {
                    appModel.resetHomeWidgetLayout(columns: columns)
                } label: {
                    Label(appModel.t(.homeResetDefault), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular.tint(appModel.liquidGlassTintColor.opacity(0.04)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }
}

// MARK: - Content router (size-aware)

private struct HomeWidgetContentView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let descriptor: HomeWidgetDescriptor
    let size: HomeWidgetSize
    let snapshot: HomeSnapshot

    var body: some View {
        Group {
            switch descriptor.id {
            case HomeWidgetID.today:
                TodayWidgetContent(snapshot: snapshot, size: size)
            case HomeWidgetID.activeProjects:
                ActiveProjectsWidgetContent(projects: snapshot.activeProjects, size: size)
            case HomeWidgetID.aiReview:
                AIReviewWidgetContent(aiReview: snapshot.aiReview, size: size)
            case HomeWidgetID.calendar:
                CalendarWidgetContent(size: size)
            case HomeWidgetID.recentPapers:
                RecentPapersWidgetContent(size: size)
            case HomeWidgetID.readingPlan:
                ReadingPlanWidgetContent(papers: snapshot.today.readingQueue, size: size)
            case HomeWidgetID.projectHealth:
                ProjectHealthWidgetContent(snapshot: snapshot, size: size)
            case HomeWidgetID.quickActions:
                QuickActionsWidgetContent(size: size)
            default:
                EmptyView()
            }
        }
        .clipped()
    }
}

// MARK: - Today

private struct TodayWidgetContent: View {
    @EnvironmentObject private var appModel: AppViewModel
    let snapshot: HomeSnapshot
    let size: HomeWidgetSize

    var body: some View {
        switch size {
        case .small:
            HomeBigNumber(
                count: snapshot.today.dueTodos.count,
                caption: appModel.t(.routeTasks),
                tint: .orange,
                systemImage: "checklist",
                action: { appModel.selectGlobalTodos() }
            )
        case .tall:
            VStack(alignment: .leading, spacing: 8) {
                HomeWidgetTallCount(
                    count: snapshot.today.dueTodos.count,
                    caption: appModel.t(.routeTasks),
                    tint: .orange,
                    systemImage: "checklist"
                )
                if snapshot.today.dueTodos.isEmpty {
                    Text(appModel.t(.homeReadingPlanEmpty))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.today.dueTodos.prefix(3)) { todo in
                        HomeTodoWidgetRow(todo: todo) {
                            appModel.selectGlobalTodos()
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        case .medium:
            VStack(alignment: .leading, spacing: 10) {
                HomeWidgetMetricStrip(metrics: todayMetrics(maxCount: 2))
                ForEach(snapshot.today.dueTodos.prefix(2)) { todo in
                    HomeTodoWidgetRow(todo: todo) {
                        appModel.selectGlobalTodos()
                    }
                }
                Spacer(minLength: 0)
            }
        case .large:
            VStack(alignment: .leading, spacing: 12) {
                HomeWidgetMetricStrip(metrics: todayMetrics(maxCount: 4))
                HomeWidgetSectionList(title: appModel.t(.routeTasks), systemImage: "checklist") {
                    if snapshot.today.dueTodos.isEmpty {
                        Text(appModel.t(.homeReadingPlanEmpty))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.today.dueTodos.prefix(4)) { todo in
                            HomeTodoWidgetRow(todo: todo) {
                                appModel.selectGlobalTodos()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        case .wide:
            VStack(alignment: .leading, spacing: 8) {
                HomeWidgetMetricStrip(metrics: todayMetrics(maxCount: 2))
                if let todo = snapshot.today.dueTodos.first {
                    HomeTodoWidgetRow(todo: todo) {
                        appModel.selectGlobalTodos()
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func todayMetrics(maxCount: Int) -> [HomeWidgetMetric] {
        let all = [
            HomeWidgetMetric(systemImage: "checklist", title: appModel.t(.routeTasks), count: snapshot.today.dueTodos.count, tint: .orange, destination: .tasks),
            HomeWidgetMetric(systemImage: "books.vertical", title: appModel.t(.homeWidgetReadingPlan), count: snapshot.today.readingQueue.count, tint: .teal, destination: .library),
            HomeWidgetMetric(systemImage: "calendar.badge.clock", title: appModel.t(.homeWidgetCalendar), count: snapshot.today.upcomingDeadlines.count, tint: .red, destination: .calendar),
            HomeWidgetMetric(systemImage: "tray.and.arrow.down", title: appModel.t(.homeWidgetAIReview), count: snapshot.today.pendingDrafts.count, tint: .purple, destination: .aiReview)
        ]
        return Array(all.prefix(maxCount))
    }
}

// MARK: - Active Projects

private struct ActiveProjectsWidgetContent: View {
    @EnvironmentObject private var appModel: AppViewModel
    let projects: [ActiveProjectData]
    let size: HomeWidgetSize

    var body: some View {
        switch size {
        case .small:
            HomeBigNumber(
                count: projects.count,
                caption: appModel.t(.routeProjects),
                tint: .accentColor,
                systemImage: "folder",
                action: { appModel.selectSection(.projects) }
            )
        case .tall:
            VStack(alignment: .leading, spacing: 8) {
                HomeWidgetTallCount(
                    count: projects.count,
                    caption: appModel.t(.routeProjects),
                    tint: .accentColor,
                    systemImage: "folder"
                )
                projectsList(limit: 4)
            }
        case .medium:
            projectsList(limit: 3)
        case .large:
            projectsList(limit: 6)
        case .wide:
            projectsList(limit: 2)
        }
    }

    @ViewBuilder
    private func projectsList(limit: Int) -> some View {
        if projects.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(appModel.t(.projectsEmptyTitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    appModel.beginCreatingResearchProject()
                } label: {
                    Label(appModel.t(.toolbarNewProject), systemImage: "plus")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(projects.prefix(limit)) { project in
                    Button {
                        appModel.selectResearchProject(project.projectID)
                    } label: {
                        HStack(spacing: 10) {
                            StageBadge(stage: project.stage, rule: project.stageRule)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.title)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text("Core \(project.coreCount) · Open \(project.openTodoCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - AI Review

private struct AIReviewWidgetContent: View {
    @EnvironmentObject private var appModel: AppViewModel
    let aiReview: AIReviewPanelData
    let size: HomeWidgetSize

    var body: some View {
        switch size {
        case .small:
            HomeBigNumber(
                count: aiReview.needsApproval.count,
                caption: appModel.localized("待审核", "Approval"),
                tint: .purple,
                systemImage: "checkmark.seal",
                action: { appModel.selectSection(appModel.isWorkspaceSectionAvailable(.inbox) ? .inbox : .llmLab) }
            )
        case .tall:
            VStack(alignment: .leading, spacing: 8) {
                HomeWidgetTallCount(
                    count: aiReview.needsApproval.count,
                    caption: appModel.localized("待审核", "Approval"),
                    tint: .purple,
                    systemImage: "checkmark.seal"
                )
                if aiReview.needsApproval.isEmpty {
                    Text(appModel.t(.homeReadingPlanEmpty))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(aiReview.needsApproval.prefix(3)) { draft in
                        HomeWidgetTextRow(title: draft.title, detail: draft.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "doc.badge.clock") {
                            appModel.selectSection(appModel.isWorkspaceSectionAvailable(.inbox) ? .inbox : .llmLab)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        case .medium:
            VStack(alignment: .leading, spacing: 10) {
                HomeWidgetMetricStrip(metrics: aiMetrics)
                if let first = aiReview.needsApproval.first {
                    HomeWidgetTextRow(title: first.title, detail: first.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "doc.badge.clock") {
                        appModel.selectSection(appModel.isWorkspaceSectionAvailable(.inbox) ? .inbox : .llmLab)
                    }
                }
                Spacer(minLength: 0)
            }
        case .large:
            VStack(alignment: .leading, spacing: 12) {
                HomeWidgetMetricStrip(metrics: aiMetrics)
                ForEach(aiReview.needsApproval.prefix(4)) { draft in
                    HomeWidgetTextRow(title: draft.title, detail: draft.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "doc.badge.clock") {
                        appModel.selectSection(appModel.isWorkspaceSectionAvailable(.inbox) ? .inbox : .llmLab)
                    }
                }
                Spacer(minLength: 0)
            }
        case .wide:
            VStack(alignment: .leading, spacing: 8) {
                HomeWidgetMetricStrip(metrics: Array(aiMetrics.prefix(2)))
                Spacer(minLength: 0)
            }
        }
    }

    private var aiMetrics: [HomeWidgetMetric] {
        [
            HomeWidgetMetric(systemImage: "checkmark.seal", title: appModel.localized("待审核", "Approval"), count: aiReview.needsApproval.count, tint: .green, destination: .aiReview),
            HomeWidgetMetric(systemImage: "quote.bubble", title: appModel.localized("无支持证据", "Claims"), count: aiReview.unsupportedClaims.count, tint: .purple, destination: .aiLab),
            HomeWidgetMetric(systemImage: "exclamationmark.triangle", title: appModel.localized("证据陈旧", "Evidence"), count: aiReview.staleEvidenceWarnings.count, tint: .orange, destination: .aiLab)
        ]
    }
}

// MARK: - Calendar (per-size variants)

private struct CalendarWidgetContent: View {
    @EnvironmentObject private var appModel: AppViewModel
    let size: HomeWidgetSize

    var body: some View {
        switch size {
        case .small:
            MiniCalendarIcon()
        case .tall:
            // Calendar opted out of `.tall`, but keep an exhaustive switch
            // safe so adding it back in the future doesn't crash.
            MiniCalendarIcon()
        case .medium:
            CompactMonthGrid(showsSelection: true, density: .compact, showsAgenda: true, agendaLimit: 2)
        case .large:
            CompactMonthGrid(showsSelection: true, density: .comfortable, showsAgenda: true, agendaLimit: 4)
        case .wide:
            CompactMonthGrid(showsSelection: true, density: .compact, showsAgenda: true, agendaLimit: 1)
        }
    }
}

/// macOS-Calendar-icon style: tiny month grid with today highlighted, no events / nav.
private struct MiniCalendarIcon: View {
    @Environment(\.locale) private var locale
    private let now: Date = Date()
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(monthName)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.red)
                if !lunarInfo.isEmpty {
                    Text("|")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(lunarInfo)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                // Weekday symbols repeat ("S" Sunday + Saturday, "T" Tuesday
                // + Thursday) so `\.self` triggers the SwiftUI duplicate-ID
                // warning. Index-based identity is unambiguous here because
                // the array always has exactly 7 entries.
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let cellHeight: CGFloat = 12
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7),
                spacing: 1
            ) {
                ForEach(monthDates, id: \.self) { date in
                    dateCell(date: date, cellHeight: cellHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func dateCell(date: Date, cellHeight: CGFloat) -> some View {
        let isInMonth = calendar.isDate(date, equalTo: now, toGranularity: .month)
        let isToday = calendar.isDateInToday(date)
        let day = calendar.component(.day, from: date)
        let textColor: Color = {
            if !isInMonth { return .secondary.opacity(0.35) }
            if isToday { return .white }
            return .primary
        }()
        ZStack {
            if isToday {
                Circle()
                    .fill(Color.red.opacity(0.88))
                    .frame(width: 12, height: 12)
            }
            Text("\(day)")
                .font(.system(size: 8, weight: isToday ? .bold : .regular))
                .foregroundStyle(textColor)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: cellHeight)
    }

    private var monthName: String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("MMMM")
        return f.string(from: now)
    }

    private var lunarInfo: String {
        var cal = Calendar(identifier: .chinese)
        cal.locale = Locale(identifier: locale.identifier)
        let f = DateFormatter()
        f.locale = locale
        f.calendar = cal
        f.dateStyle = .long
        // Only show lunar info for Chinese locale.
        guard locale.language.languageCode?.identifier == "zh" else {
            return ""
        }
        return f.string(from: now)
    }

    private var weekdaySymbols: [String] {
        var cal = calendar
        cal.locale = locale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let firstWeekday = cal.firstWeekday
        return Array(symbols[(firstWeekday - 1)...] + symbols[..<(firstWeekday - 1)])
    }

    private var monthDates: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return [] }
        let firstWeekday = calendar.firstWeekday
        let monthStart = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: monthStart)
        let leadingDays = (weekdayOfFirst - firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart

        // 5 weeks * 7 days = 35 cells — fits in a 1×1 tile.
        return (0..<35).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }
}

private enum CalendarDensity {
    case compact
    case comfortable
}

/// A simplified month grid used at medium / large sizes.
private struct CompactMonthGrid: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.locale) private var locale
    @State private var displayedMonth: Date = Date()

    let showsSelection: Bool
    let density: CalendarDensity
    let showsAgenda: Bool
    let agendaLimit: Int

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 6 : 8) {
            header
            weekdayRow
            datesGrid
            if showsAgenda {
                selectedAgenda
            } else if density == .comfortable {
                selectionFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            appModel.refreshSystemSchedule(around: displayedMonth)
        }
        .onChange(of: displayedMonth) { _, newMonth in
            appModel.refreshSystemSchedule(around: newMonth)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(monthTitle)
                .font(density == .compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)

            Button {
                let today = calendar.startOfDay(for: Date())
                displayedMonth = today
                appModel.selectDashboardDate(today)
            } label: {
                Text(appModel.localized("今天", "Today"))
                    .font(.caption2.weight(.medium))
            }
            .buttonStyle(.borderless)

            Button {
                displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            // See note in the medium-calendar variant: weekday symbols repeat
            // so we identify by index instead of the symbol string itself.
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var datesGrid: some View {
        let dates = monthDates
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(dates, id: \.self) { date in
                dateCell(date: date)
            }
        }
    }

    @ViewBuilder
    private func dateCell(date: Date) -> some View {
        let isInMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(date)
        let isSelected = showsSelection && calendar.isDate(date, inSameDayAs: appModel.selectedDashboardDate)
        let dayNumber = calendar.component(.day, from: date)
        let items = calendarItems(for: date)

        let textColor: Color = {
            if !isInMonth { return .secondary.opacity(0.45) }
            if isSelected { return .white }
            if isToday { return .red }
            return .primary
        }()

        Button {
            if showsSelection {
                appModel.selectDashboardDate(date)
            }
        } label: {
            VStack(spacing: density == .compact ? 1 : 2) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.red.opacity(0.88))
                            .frame(width: dayCircleDiameter, height: dayCircleDiameter)
                    } else if isToday && !isSelected {
                        Circle()
                            .stroke(Color.red.opacity(0.55), lineWidth: 1)
                            .frame(width: dayCircleDiameter, height: dayCircleDiameter)
                    }
                    Text("\(dayNumber)")
                        .font(.system(size: density == .compact ? 10 : 12, weight: isToday || isSelected ? .semibold : .regular))
                        .foregroundStyle(textColor)
                        .monospacedDigit()
                }
                .frame(width: dayCircleDiameter, height: dayCircleDiameter)
                .frame(maxWidth: .infinity)

                eventDots(items)
            }
            .frame(maxWidth: .infinity, minHeight: dayCellHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!showsSelection)
    }

    @ViewBuilder
    private func eventDots(_ items: [HomeCalendarAgendaItem]) -> some View {
        if items.isEmpty {
            Color.clear.frame(height: eventDotSize)
        } else {
            HStack(spacing: 2) {
                ForEach(Array(items.prefix(3))) { item in
                    Circle()
                        .fill(item.tint.opacity(0.88))
                        .frame(width: eventDotSize, height: eventDotSize)
                }
            }
            .frame(height: eventDotSize)
        }
    }

    private var selectedAgenda: some View {
        let items = calendarItems(for: appModel.selectedDashboardDate)
        return VStack(alignment: .leading, spacing: density == .compact ? 4 : 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.circle")
                    .foregroundStyle(Color.red.opacity(0.78))
                Text(footerText)
                    .font(density == .compact ? .caption.weight(.medium) : .callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if items.count > agendaLimit {
                    Text("+\(items.count - agendaLimit)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if items.isEmpty {
                Text(appModel.localized("暂无日程", "No schedule"))
                    .font(density == .compact ? .caption : .callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: density == .compact ? 3 : 5) {
                    ForEach(Array(items.prefix(agendaLimit))) { item in
                        HomeCalendarAgendaRow(item: item, density: density)
                    }
                }
            }
        }
        .padding(.top, density == .compact ? 1 : 3)
    }

    private var selectionFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.circle")
                .foregroundStyle(.red.opacity(0.85))
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var footerText: String {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .long
        return f.string(from: appModel.selectedDashboardDate)
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("yMMMM")
        return f.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        var cal = calendar
        cal.locale = locale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let firstWeekday = cal.firstWeekday
        let rotated = Array(symbols[(firstWeekday - 1)...] + symbols[..<(firstWeekday - 1)])
        return rotated
    }

    private var monthDates: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }
        let firstWeekday = calendar.firstWeekday
        let monthStart = monthInterval.start

        let weekdayOfFirst = calendar.component(.weekday, from: monthStart)
        let leadingDays = (weekdayOfFirst - firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart

        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    private var dayCellHeight: CGFloat {
        density == .compact ? 24 : 32
    }

    private var dayCircleDiameter: CGFloat {
        density == .compact ? 16 : 20
    }

    private var eventDotSize: CGFloat {
        density == .compact ? 3 : 4
    }

    private func calendarItems(for date: Date) -> [HomeCalendarAgendaItem] {
        let todoItems = appModel.todos.compactMap { todo -> HomeCalendarAgendaItem? in
            guard let dueDate = todo.dueDate, calendar.isDate(dueDate, inSameDayAs: date) else {
                return nil
            }
            return HomeCalendarAgendaItem(
                id: "todo-\(todo.id)",
                title: todo.title,
                detail: todo.status == .done ? appModel.localized("已完成", "Done") : todo.priority.label,
                systemImage: "checklist",
                tint: color(for: todo.priority),
                sortDate: dueDate,
                sortPriority: prioritySortValue(for: todo.priority)
            )
        }

        let workspaceItems = appModel.calendarEvents.compactMap { event -> HomeCalendarAgendaItem? in
            guard calendar.isDate(event.date, inSameDayAs: date) else {
                return nil
            }
            return HomeCalendarAgendaItem(
                id: "workspace-\(event.id)",
                title: event.title,
                detail: event.category,
                systemImage: "calendar",
                tint: event.colorHex.map(Color.init(hex:)) ?? .accentColor,
                sortDate: event.date,
                sortPriority: 10
            )
        }

        let systemItems = appModel.systemScheduleItems.compactMap { item -> HomeCalendarAgendaItem? in
            guard calendar.isDate(item.displayDate, inSameDayAs: date) else {
                return nil
            }
            return HomeCalendarAgendaItem(
                id: "system-\(item.id)",
                title: item.title,
                detail: [item.kind.label, item.categoryName].filter { !$0.isEmpty }.joined(separator: " / "),
                systemImage: item.kind.systemImage,
                tint: color(for: item),
                sortDate: item.displayDate,
                sortPriority: item.isHoliday ? 5 : (item.kind == .event ? 20 : 30)
            )
        }

        return (todoItems + workspaceItems + systemItems).sorted { first, second in
            if first.sortDate == second.sortDate {
                return first.sortPriority < second.sortPriority
            }
            return first.sortDate < second.sortDate
        }
    }

    private func color(for priority: Priority) -> Color {
        switch priority {
        case .low:
            return .gray
        case .medium:
            return .accentColor
        case .high:
            return .orange
        case .urgent:
            return .red
        }
    }

    private func color(for item: SystemScheduleItem) -> Color {
        if let colorHex = item.calendarColorHex {
            return Color(hex: colorHex)
        }
        if item.isHoliday {
            return .red
        }
        return item.kind == .event ? .blue : .orange
    }

    private func prioritySortValue(for priority: Priority) -> Int {
        switch priority {
        case .urgent:
            return 0
        case .high:
            return 1
        case .medium:
            return 2
        case .low:
            return 3
        }
    }
}

private struct HomeCalendarAgendaItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let sortDate: Date
    let sortPriority: Int
}

private struct HomeCalendarAgendaRow: View {
    let item: HomeCalendarAgendaItem
    let density: CalendarDensity

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.systemImage)
                .font(.system(size: density == .compact ? 9 : 10, weight: .semibold))
                .foregroundStyle(item.tint.opacity(0.9))
                .frame(width: density == .compact ? 14 : 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: density == .compact ? 11 : 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !item.detail.isEmpty && density == .comfortable {
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: density == .compact ? 17 : 22, alignment: .leading)
    }
}

// MARK: - Recent Papers

private struct RecentPapersWidgetContent: View {
    @EnvironmentObject private var appModel: AppViewModel
    let size: HomeWidgetSize

    var body: some View {
        switch size {
        case .small:
            HomeSmallList(
                count: appModel.recentPapers.count,
                caption: appModel.t(.homeWidgetRecentPapers),
                tint: .indigo,
                systemImage: "doc.richtext",
                firstLine: appModel.recentPapers.first?.displayTitle,
                action: { appModel.selectSection(.library) }
            )
        case .tall:
            VStack(alignment: .leading, spacing: 8) {
                HomeWidgetTallCount(
                    count: appModel.recentPapers.count,
                    caption: appModel.t(.homeWidgetRecentPapers),
                    tint: .indigo,
                    systemImage: "doc.richtext"
                )
                paperRows(appModel.recentPapers.prefix(3))
                Spacer(minLength: 0)
            }
        case .medium:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(appModel.recentPapers.prefix(3))) { paper in
                    HomeWidgetTextRow(title: paper.displayTitle, detail: paper.authorsDisplay, systemImage: "doc.richtext") {
                        appModel.selectPaper(id: paper.id)
                        appModel.selectSection(.library)
                    }
                }
                Spacer(minLength: 0)
            }
        case .large:
            VStack(alignment: .leading, spacing: 14) {
                HomeWidgetSectionList(title: appModel.t(.homeRecentlyAdded), systemImage: "plus") {
                    paperRows(appModel.recentPapers.prefix(3))
                }
                HomeWidgetSectionList(title: appModel.t(.homeRecentlyRead), systemImage: "clock") {
                    paperRows(appModel.recentlyReadPapers.prefix(3))
                }
                Spacer(minLength: 0)
            }
        case .wide:
            VStack(alignment: .leading, spacing: 6) {
                paperRows(appModel.recentPapers.prefix(2))
                Spacer(minLength: 0)
            }
        }
    }

    private func paperRows(_ papers: ArraySlice<Paper>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if papers.isEmpty {
                Button {
                    appModel.beginIdentifierImport()
                } label: {
                    Label(appModel.t(.toolbarAddByIdentifier), systemImage: "plus")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            } else {
                ForEach(Array(papers)) { paper in
                    HomeWidgetTextRow(title: paper.displayTitle, detail: paper.authorsDisplay, systemImage: "doc.richtext") {
                        appModel.selectPaper(id: paper.id)
                        appModel.selectSection(.library)
                    }
                }
            }
        }
    }
}

// MARK: - Reading Plan

private struct ReadingPlanWidgetContent: View {
    @EnvironmentObject private var appModel: AppViewModel
    let papers: [PaperSummary]
    let size: HomeWidgetSize

    var body: some View {
        switch size {
        case .small:
            HomeSmallList(
                count: papers.count,
                caption: appModel.t(.homeWidgetReadingPlan),
                tint: .teal,
                systemImage: "books.vertical",
                firstLine: papers.first?.title,
                action: { appModel.selectSection(.library) }
            )
        case .tall:
            VStack(alignment: .leading, spacing: 8) {
                HomeWidgetTallCount(
                    count: papers.count,
                    caption: appModel.t(.homeWidgetReadingPlan),
                    tint: .teal,
                    systemImage: "books.vertical"
                )
                list(limit: 4)
            }
        case .medium:
            list(limit: 3)
        case .large:
            list(limit: 6)
        case .wide:
            list(limit: 2)
        }
    }

    @ViewBuilder
    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if papers.isEmpty {
                Text(appModel.t(.homeReadingPlanEmpty))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(papers.prefix(limit)) { paper in
                    HomeWidgetTextRow(
                        title: paper.title,
                        detail: [paper.authors, paper.status.label].filter { !$0.isEmpty }.joined(separator: " · "),
                        systemImage: "books.vertical"
                    ) {
                        appModel.selectPaper(id: paper.id)
                        appModel.selectSection(.library)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Project Health

private struct ProjectHealthWidgetContent: View {
    @EnvironmentObject private var appModel: AppViewModel
    let snapshot: HomeSnapshot
    let size: HomeWidgetSize

    private var paperCount: Int {
        snapshot.activeProjects.reduce(0) { $0 + $1.recentPaperCount }
    }
    private var openTodoCount: Int {
        snapshot.activeProjects.reduce(0) { $0 + $1.openTodoCount }
    }
    private var reviewCount: Int {
        snapshot.aiReview.needsApproval.count + snapshot.aiReview.unsupportedClaims.count + snapshot.aiReview.staleEvidenceWarnings.count
    }

    var body: some View {
        switch size {
        case .small:
            HomeBigNumber(
                count: snapshot.activeProjects.count,
                caption: appModel.t(.routeProjects),
                tint: .green,
                systemImage: "waveform.path.ecg",
                action: { appModel.selectSection(.projects) }
            )
        case .tall:
            // Project Health opted out of `.tall`; fall back to medium.
            VStack(alignment: .leading, spacing: 10) {
                HomeWidgetMetricStrip(metrics: metrics(prefix: 2))
                HomeWidgetMetricStrip(metrics: metrics(suffix: 2))
                Spacer(minLength: 0)
            }
        case .medium:
            VStack(alignment: .leading, spacing: 10) {
                HomeWidgetMetricStrip(metrics: metrics(prefix: 2))
                HomeWidgetMetricStrip(metrics: metrics(suffix: 2))
                Spacer(minLength: 0)
            }
        case .large:
            VStack(alignment: .leading, spacing: 12) {
                Text(appModel.tf(.homeProjectHealthSummaryFormat, snapshot.activeProjects.count, paperCount, openTodoCount, reviewCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HomeWidgetMetricStrip(metrics: metrics(prefix: 4))
                Spacer(minLength: 0)
            }
        case .wide:
            VStack(alignment: .leading, spacing: 8) {
                HomeWidgetMetricStrip(metrics: metrics(prefix: 2))
                Spacer(minLength: 0)
            }
        }
    }

    private func metrics(prefix: Int) -> [HomeWidgetMetric] {
        Array(allMetrics.prefix(prefix))
    }
    private func metrics(suffix: Int) -> [HomeWidgetMetric] {
        Array(allMetrics.suffix(suffix))
    }

    private var allMetrics: [HomeWidgetMetric] {
        [
            HomeWidgetMetric(systemImage: "folder", title: appModel.t(.routeProjects), count: snapshot.activeProjects.count, tint: .accentColor, destination: .projects),
            HomeWidgetMetric(systemImage: "doc.richtext", title: appModel.t(.routePapers), count: paperCount, tint: .indigo, destination: .library),
            HomeWidgetMetric(systemImage: "checklist", title: appModel.t(.routeTasks), count: openTodoCount, tint: .orange, destination: .tasks),
            HomeWidgetMetric(systemImage: "brain", title: appModel.t(.routeAILab), count: reviewCount, tint: .purple, destination: .aiLab)
        ]
    }
}

// MARK: - Quick Actions

private struct QuickActionsWidgetContent: View {
    @EnvironmentObject private var appModel: AppViewModel
    let size: HomeWidgetSize

    var body: some View {
        switch size {
        case .small:
            VStack(spacing: 6) {
                actionTile(title: appModel.t(.routeAILab), systemImage: "brain", tint: .purple) {
                    appModel.selectSection(.llmLab)
                }
                actionTile(title: appModel.t(.homeQuickActionOpenLibrary), systemImage: "doc.richtext", tint: .indigo) {
                    appModel.selectSection(.library)
                }
                Spacer(minLength: 0)
            }
        case .tall:
            VStack(spacing: 7) {
                actionRow(title: appModel.t(.homeQuickActionOpenLibrary), systemImage: "doc.richtext", tint: .indigo) {
                    appModel.selectSection(.library)
                }
                actionRow(title: appModel.t(.homeQuickActionOpenWiki), systemImage: "text.book.closed", tint: .blue) {
                    appModel.selectSection(.wiki)
                }
                actionRow(title: appModel.t(.routeAILab), systemImage: "brain", tint: .purple) {
                    appModel.selectSection(.llmLab)
                }
                Spacer(minLength: 0)
            }
        case .wide:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    actionTile(title: appModel.t(.homeQuickActionOpenLibrary), systemImage: "doc.richtext", tint: .indigo) {
                        appModel.selectSection(.library)
                    }
                    actionTile(title: appModel.t(.routeAILab), systemImage: "brain", tint: .purple) {
                        appModel.selectSection(.llmLab)
                    }
                }
                Spacer(minLength: 0)
            }
        case .medium, .large:
            VStack(spacing: 7) {
                actionRow(title: appModel.t(.homeQuickActionOpenLibrary), systemImage: "doc.richtext", tint: .indigo) {
                    appModel.selectSection(.library)
                }
                actionRow(title: appModel.t(.homeQuickActionOpenWiki), systemImage: "text.book.closed", tint: .blue) {
                    appModel.selectSection(.wiki)
                }
                actionRow(title: appModel.t(.homeQuickActionOpenCalendar), systemImage: "calendar", tint: .red) {
                    appModel.selectSection(.calendar)
                }
                actionRow(title: appModel.t(.routeAILab), systemImage: "brain", tint: .purple) {
                    appModel.selectSection(.llmLab)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func actionRow(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.95))
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        )
    }

    private func actionTile(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.95))
                    .frame(width: 20, height: 20)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

// MARK: - Reusable widget primitives

private struct HomeBigNumber: View {
    let count: Int
    let caption: String
    let tint: Color
    let systemImage: String
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(caption)")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint.opacity(0.95))
                Text(caption)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

/// 1×1 (small) variant for list-style widgets. Like `HomeBigNumber` but with
/// a single representative line under the count, so the user can tell at a
/// glance which paper / queue item is on top — addresses the 2026-05-17
/// "1×1 needs more content" feedback.
private struct HomeSmallList: View {
    let count: Int
    let caption: String
    let tint: Color
    let systemImage: String
    let firstLine: String?
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(caption)")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(count)")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(caption)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            if let firstLine, !firstLine.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.95))
                    Text(firstLine)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            } else {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Compact header for `.tall` (2×1) widget variants. Shows the count and
/// caption in a single row so the remaining height can be used for a 3-4
/// item list.
private struct HomeWidgetTallCount: View {
    let count: Int
    let caption: String
    let tint: Color
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(count)")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint.opacity(0.95))
            Text(caption)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private enum HomeWidgetDestination: Hashable {
    case projects
    case library
    case tasks
    case calendar
    case aiLab
    case aiReview
}

private struct HomeWidgetMetric: Hashable {
    let systemImage: String
    let title: String
    let count: Int
    let tint: Color
    var destination: HomeWidgetDestination? = nil
}

private struct HomeWidgetMetricStrip: View {
    @EnvironmentObject private var appModel: AppViewModel

    let metrics: [HomeWidgetMetric]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(metrics, id: \.title) { metric in
                metricTile(metric)
            }
        }
    }

    private func metricTile(_ metric: HomeWidgetMetric) -> some View {
        Group {
            if let destination = metric.destination {
                Button {
                    open(destination)
                } label: {
                    metricContent(metric)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(metric.title)")
            } else {
                metricContent(metric)
            }
        }
    }

    private func metricContent(_ metric: HomeWidgetMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(metric.tint.opacity(0.9))
                    .frame(width: 16, height: 16)
                    .background(
                        metric.tint.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                Text(metric.title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if metric.destination != nil {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text("\(metric.count)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            SciStationDesign.subtleSurface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(SciStationDesign.hairline.opacity(0.45), lineWidth: 0.5)
        )
    }

    private func open(_ destination: HomeWidgetDestination) {
        switch destination {
        case .projects:
            appModel.selectSection(.projects)
        case .library:
            appModel.selectSection(.library)
        case .tasks:
            appModel.selectGlobalTodos()
        case .calendar:
            appModel.selectSection(.calendar)
        case .aiLab:
            appModel.selectSection(.llmLab)
        case .aiReview:
            appModel.selectSection(appModel.isWorkspaceSectionAvailable(.inbox) ? .inbox : .llmLab)
        }
    }
}

private struct HomeWidgetSectionList<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

/// Icon-forward todo row for the Today widget: kind glyph + title + red flags,
/// with a compact date/range and colored tag chips beneath.
private struct HomeTodoWidgetRow: View {
    let todo: TodoSummary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: todo.kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(todo.kind == .reading ? Color.blue : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(todo.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        TodoPriorityFlagsBadge(priority: todo.priority)
                        Spacer(minLength: 0)
                        if let dateText = HomeTodoDateText.text(for: todo) {
                            Text(dateText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if !todo.tags.isEmpty {
                        TodoTagChipGroup(tags: todo.tags, limit: 3)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Color.primary.opacity(isHovering ? 0.04 : 0),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct HomeWidgetTextRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 14)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Color.primary.opacity(isHovering ? 0.04 : 0),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private extension HomeWidgetSize {
    func title(appModel: AppViewModel) -> String {
        switch self {
        case .small:
            return appModel.t(.homeWidgetSizeSmall)
        case .tall:
            return appModel.t(.homeWidgetSizeTall)
        case .medium:
            return appModel.t(.homeWidgetSizeMedium)
        case .large:
            return appModel.t(.homeWidgetSizeLarge)
        case .wide:
            return appModel.t(.homeWidgetSizeWide)
        }
    }
}
