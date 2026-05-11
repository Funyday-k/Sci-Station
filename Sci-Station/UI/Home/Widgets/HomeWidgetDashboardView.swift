import SwiftUI
import UniformTypeIdentifiers

// MARK: - Grid constants

private enum HomeWidgetGridConstants {
    /// Vertical/horizontal spacing between tiles.
    static let spacing: CGFloat = 14
    /// Vertical extent of one grid row. Cells are not perfectly square because the
    /// available width varies, but this gives small tiles a comfortable footprint.
    static let rowHeight: CGFloat = 152
    /// Outer padding so the grid never butts up against the scroll container.
    static let outerPadding: CGFloat = 0
}

// MARK: - Dashboard

struct HomeWidgetDashboardView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let snapshot: HomeSnapshot

    private var columns: Int {
        max(1, appModel.responsiveShellModel.homeWidgetColumns)
    }

    private var availableDescriptors: [HomeWidgetDescriptor] {
        HomeWidgetRegistry.availableDescriptors(in: appModel.workspaceModuleConfiguration)
    }

    private var normalizedLayout: HomeWidgetLayout {
        appModel.workspacePreferences.homeWidgetLayout.normalized(descriptors: availableDescriptors, columns: columns)
    }

    private var visibleItems: [HomeWidgetLayoutItem] {
        normalizedLayout.visibleItems(descriptors: availableDescriptors, columns: columns)
    }

    private var totalRows: Int {
        visibleItems
            .map { item in
                let rs = max(1, min(columns * 4, item.size.rowSpan))
                return item.row + rs
            }
            .max() ?? 0
    }

    private var gridHeight: CGFloat {
        guard totalRows > 0 else { return 0 }
        return CGFloat(totalRows) * HomeWidgetGridConstants.rowHeight
            + CGFloat(max(0, totalRows - 1)) * HomeWidgetGridConstants.spacing
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
        .animation(.smooth(duration: 0.32), value: visibleItems)
    }

    private var grid: some View {
        GeometryReader { proxy in
            let cols = max(1, columns)
            let totalSpacing = CGFloat(max(0, cols - 1)) * HomeWidgetGridConstants.spacing
            let columnWidth = max(40, (proxy.size.width - totalSpacing) / CGFloat(cols))

            GlassEffectContainer(spacing: HomeWidgetGridConstants.spacing) {
                ZStack(alignment: .topLeading) {
                    if appModel.isEditingHomeLayout {
                        gridBackdrop(columnWidth: columnWidth, cols: cols)
                    }

                    ForEach(visibleItems) { item in
                        if let descriptor = HomeWidgetRegistry.descriptor(id: item.widgetID) {
                            let metrics = cellMetrics(for: item, columnWidth: columnWidth, cols: cols)
                            HomeWidgetCard(
                                item: item,
                                descriptor: descriptor,
                                columns: cols,
                                cellSize: CGSize(width: metrics.width, height: metrics.height),
                                snapshot: snapshot
                            )
                            .frame(width: metrics.width, height: metrics.height)
                            .offset(x: metrics.x, y: metrics.y)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                        }
                    }
                }
                .frame(width: proxy.size.width, height: gridHeight, alignment: .topLeading)
            }
        }
        .frame(height: gridHeight)
    }

    /// Faint grid lines that only appear in edit mode so users understand it's a tile grid.
    @ViewBuilder
    private func gridBackdrop(columnWidth: CGFloat, cols: Int) -> some View {
        let rows = max(totalRows, 1)
        ZStack(alignment: .topLeading) {
            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<cols, id: \.self) { col in
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(0.05),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .frame(width: columnWidth, height: HomeWidgetGridConstants.rowHeight)
                        .offset(
                            x: CGFloat(col) * (columnWidth + HomeWidgetGridConstants.spacing),
                            y: CGFloat(row) * (HomeWidgetGridConstants.rowHeight + HomeWidgetGridConstants.spacing)
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cellMetrics(for item: HomeWidgetLayoutItem, columnWidth: CGFloat, cols: Int) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let cs = min(cols, max(1, item.size.columnSpan))
        let rs = max(1, item.size.rowSpan)
        let x = CGFloat(item.column) * (columnWidth + HomeWidgetGridConstants.spacing)
        let y = CGFloat(item.row) * (HomeWidgetGridConstants.rowHeight + HomeWidgetGridConstants.spacing)
        let w = CGFloat(cs) * columnWidth + CGFloat(cs - 1) * HomeWidgetGridConstants.spacing
        let h = CGFloat(rs) * HomeWidgetGridConstants.rowHeight + CGFloat(rs - 1) * HomeWidgetGridConstants.spacing
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
                    .glassEffect(.regular, in: Capsule())
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

                Button {
                    appModel.resetHomeWidgetLayout(columns: columns)
                } label: {
                    Label(appModel.t(.homeResetDefault), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                Button {
                    appModel.exitHomeLayoutEdit()
                } label: {
                    Label(appModel.t(.homeDoneEditing), systemImage: "checkmark")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
            } else {
                Button {
                    appModel.enterHomeLayoutEdit()
                } label: {
                    Label(appModel.t(.homeEditLayout), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Widget Card

private struct HomeWidgetCard: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var isDropTarget = false

    let item: HomeWidgetLayoutItem
    let descriptor: HomeWidgetDescriptor
    let columns: Int
    let cellSize: CGSize
    let snapshot: HomeSnapshot

    private var effectiveSize: HomeWidgetSize {
        // Clamp visual size to available columns so a "wide" (4×4) widget in a 2-col
        // layout renders its "medium" variant instead of squishing 4-col content.
        let cs = min(columns, max(1, item.size.columnSpan))
        switch cs {
        case 1: return .small
        case 2: return .medium
        case 3: return .large
        default: return item.size
        }
    }

    private var accent: Color {
        HomeWidgetPalette.accent(for: descriptor)
    }

    private var tintOpacity: Double {
        if isDropTarget { return 0.12 }
        if appModel.isEditingHomeLayout { return 0.06 }
        if isHovering { return 0.045 }
        return 0.025
    }

    private var borderOpacity: Double {
        if isDropTarget { return 0.55 }
        if appModel.isEditingHomeLayout { return 0.25 }
        return 0.0
    }

    private var cardCorner: CGFloat {
        switch effectiveSize {
        case .small: return 18
        case .medium: return 22
        case .large, .wide: return 26
        }
    }

    private var cardPadding: CGFloat {
        switch effectiveSize {
        case .small: return 12
        case .medium: return 16
        case .large: return 18
        case .wide: return 20
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
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(
            .regular.tint(accent.opacity(tintOpacity)),
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
        .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
        .shadow(color: .black.opacity(isHovering ? 0.07 : 0.04), radius: isHovering ? 12 : 8, x: 0, y: isHovering ? 6 : 4)
        .animation(.smooth(duration: 0.22), value: isHovering)
        .animation(.smooth(duration: 0.18), value: isDropTarget)
        .onHover { hovering in
            isHovering = hovering
        }
        // NSItemProvider-based drag is the most reliable on macOS.
        // Only active in edit mode so accidental drags can't happen during normal use.
        .draggableIf(appModel.isEditingHomeLayout, widgetID: item.widgetID, descriptor: descriptor, accent: accent, appModel: appModel)
        .onDrop(of: [.plainText, .utf8PlainText], isTargeted: $isDropTarget) { providers in
            handleDrop(providers: providers)
        }
        .contextMenu {
            cardContextMenu
        }
    }

    private var spacingForSize: CGFloat {
        switch effectiveSize {
        case .small: return 8
        case .medium: return 12
        case .large: return 14
        case .wide: return 16
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
        case .small: return .caption.weight(.semibold)
        case .medium: return .headline
        case .large: return .title3.weight(.semibold)
        case .wide: return .title2.weight(.semibold)
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
        .glassEffect(.regular, in: Capsule())
    }

    private func sizeIcon(_ size: HomeWidgetSize) -> String {
        switch size {
        case .small: return "square"
        case .medium: return "square.grid.2x2"
        case .large: return "square.grid.3x3"
        case .wide: return "square.grid.4x3.fill"
        }
    }

    @MainActor
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let targetID = item.widgetID
        let targetColumns = columns
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let sourceID = (reading as? NSString) as String? else { return }
                Task { @MainActor in
                    guard sourceID != targetID else { return }
                    appModel.moveHomeWidget(sourceID, before: targetID, columns: targetColumns)
                }
            }
            return true
        }
        return false
    }
}

// MARK: - Conditional draggable helper

private extension View {
    @ViewBuilder
    func draggableIf(_ condition: Bool, widgetID: String, descriptor: HomeWidgetDescriptor, accent: Color, appModel: AppViewModel) -> some View {
        if condition {
            self.onDrag {
                let provider = NSItemProvider(object: widgetID as NSString)
                provider.suggestedName = appModel.t(descriptor.titleKey)
                return provider
            } preview: {
                HomeWidgetDragPreview(descriptor: descriptor, accent: accent, appModel: appModel)
            }
        } else {
            self
        }
    }
}

private struct HomeWidgetDragPreview: View {
    let descriptor: HomeWidgetDescriptor
    let accent: Color
    let appModel: AppViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: descriptor.systemImage)
                .foregroundStyle(accent)
            Text(appModel.t(descriptor.titleKey))
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(accent.opacity(0.10)), in: Capsule())
        .overlay(
            Capsule().stroke(accent.opacity(0.30), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .frame(width: 220)
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                systemImage: "checklist"
            )
        case .medium:
            VStack(alignment: .leading, spacing: 10) {
                HomeWidgetMetricStrip(metrics: todayMetrics(maxCount: 2))
                ForEach(snapshot.today.dueTodos.prefix(2)) { todo in
                    HomeWidgetTextRow(title: todo.title, detail: todoDetail(todo), systemImage: "circle") {
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
                            HomeWidgetTextRow(title: todo.title, detail: todoDetail(todo), systemImage: "circle") {
                                appModel.selectGlobalTodos()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        case .wide:
            VStack(alignment: .leading, spacing: 14) {
                HomeWidgetMetricStrip(metrics: todayMetrics(maxCount: 4))
                HomeWidgetSectionList(title: appModel.t(.routeTasks), systemImage: "checklist") {
                    if snapshot.today.dueTodos.isEmpty {
                        Text(appModel.t(.homeReadingPlanEmpty))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.today.dueTodos.prefix(8)) { todo in
                            HomeWidgetTextRow(title: todo.title, detail: todoDetail(todo), systemImage: "circle") {
                                appModel.selectGlobalTodos()
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func todoDetail(_ todo: TodoSummary) -> String {
        todo.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? todo.priority.label
    }

    private func todayMetrics(maxCount: Int) -> [HomeWidgetMetric] {
        let all = [
            HomeWidgetMetric(systemImage: "checklist", title: appModel.t(.routeTasks), count: snapshot.today.dueTodos.count, tint: .orange),
            HomeWidgetMetric(systemImage: "books.vertical", title: appModel.t(.homeWidgetReadingPlan), count: snapshot.today.readingQueue.count, tint: .teal),
            HomeWidgetMetric(systemImage: "calendar.badge.clock", title: appModel.t(.homeWidgetCalendar), count: snapshot.today.upcomingDeadlines.count, tint: .red),
            HomeWidgetMetric(systemImage: "tray.and.arrow.down", title: appModel.t(.homeWidgetAIReview), count: snapshot.today.pendingDrafts.count, tint: .purple)
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
                systemImage: "folder"
            )
        case .medium:
            projectsList(limit: 3)
        case .large:
            projectsList(limit: 6)
        case .wide:
            projectsList(limit: 10)
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
                systemImage: "checkmark.seal"
            )
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
        case .large, .wide:
            VStack(alignment: .leading, spacing: 12) {
                HomeWidgetMetricStrip(metrics: aiMetrics)
                ForEach(aiReview.needsApproval.prefix(size == .wide ? 6 : 4)) { draft in
                    HomeWidgetTextRow(title: draft.title, detail: draft.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "doc.badge.clock") {
                        appModel.selectSection(appModel.isWorkspaceSectionAvailable(.inbox) ? .inbox : .llmLab)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var aiMetrics: [HomeWidgetMetric] {
        [
            HomeWidgetMetric(systemImage: "checkmark.seal", title: appModel.localized("待审核", "Approval"), count: aiReview.needsApproval.count, tint: .green),
            HomeWidgetMetric(systemImage: "quote.bubble", title: appModel.localized("无支持证据", "Claims"), count: aiReview.unsupportedClaims.count, tint: .purple),
            HomeWidgetMetric(systemImage: "exclamationmark.triangle", title: appModel.localized("证据陈旧", "Evidence"), count: aiReview.staleEvidenceWarnings.count, tint: .orange)
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
        case .medium:
            CompactMonthGrid(showsSelection: false, density: .compact)
        case .large:
            CompactMonthGrid(showsSelection: true, density: .comfortable)
        case .wide:
            DashboardCalendarView(selectedDate: Binding(
                get: { appModel.selectedDashboardDate },
                set: { appModel.selectDashboardDate($0) }
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let cellHeight: CGFloat = 14
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
                Circle().fill(Color.red)
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

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(alignment: .leading, spacing: density == .compact ? 6 : 8) {
            header
            weekdayRow
            datesGrid
            if density == .comfortable {
                selectionFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            ForEach(weekdaySymbols, id: \.self) { symbol in
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
            ZStack {
                if isSelected {
                    Circle().fill(Color.red)
                } else if isToday && !isSelected {
                    Circle().stroke(Color.red.opacity(0.55), lineWidth: 1)
                }
                Text("\(dayNumber)")
                    .font(.system(size: density == .compact ? 10 : 12, weight: isToday || isSelected ? .semibold : .regular))
                    .foregroundStyle(textColor)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: density == .compact ? 18 : 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!showsSelection)
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

        let totalCells = density == .compact ? 35 : 42
        return (0..<totalCells).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: gridStart)
        }
    }
}

// MARK: - Recent Papers

private struct RecentPapersWidgetContent: View {
    @EnvironmentObject private var appModel: AppViewModel
    let size: HomeWidgetSize

    var body: some View {
        switch size {
        case .small:
            HomeBigNumber(
                count: appModel.recentPapers.count,
                caption: appModel.t(.homeWidgetRecentPapers),
                tint: .indigo,
                systemImage: "doc.richtext"
            )
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
            VStack(alignment: .leading, spacing: 16) {
                HomeWidgetSectionList(title: appModel.t(.homeRecentlyAdded), systemImage: "plus") {
                    paperRows(appModel.recentPapers.prefix(5))
                }
                HomeWidgetSectionList(title: appModel.t(.homeRecentlyRead), systemImage: "clock") {
                    paperRows(appModel.recentlyReadPapers.prefix(5))
                }
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
            HomeBigNumber(
                count: papers.count,
                caption: appModel.t(.homeWidgetReadingPlan),
                tint: .teal,
                systemImage: "books.vertical"
            )
        case .medium:
            list(limit: 3)
        case .large:
            list(limit: 6)
        case .wide:
            list(limit: 10)
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
                systemImage: "waveform.path.ecg"
            )
        case .medium:
            VStack(alignment: .leading, spacing: 10) {
                HomeWidgetMetricStrip(metrics: metrics(prefix: 2))
                HomeWidgetMetricStrip(metrics: metrics(suffix: 2))
                Spacer(minLength: 0)
            }
        case .large, .wide:
            VStack(alignment: .leading, spacing: 12) {
                Text(appModel.tf(.homeProjectHealthSummaryFormat, snapshot.activeProjects.count, paperCount, openTodoCount, reviewCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HomeWidgetMetricStrip(metrics: metrics(prefix: 4))
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
            HomeWidgetMetric(systemImage: "folder", title: appModel.t(.routeProjects), count: snapshot.activeProjects.count, tint: .accentColor),
            HomeWidgetMetric(systemImage: "doc.richtext", title: appModel.t(.routePapers), count: paperCount, tint: .indigo),
            HomeWidgetMetric(systemImage: "checklist", title: appModel.t(.routeTasks), count: openTodoCount, tint: .orange),
            HomeWidgetMetric(systemImage: "brain", title: appModel.t(.routeAILab), count: reviewCount, tint: .purple)
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
        case .medium, .large, .wide:
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

    var body: some View {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

private struct HomeWidgetMetric: Hashable {
    let systemImage: String
    let title: String
    let count: Int
    let tint: Color
}

private struct HomeWidgetMetricStrip: View {
    let metrics: [HomeWidgetMetric]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(metrics, id: \.title) { metric in
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
                    Color.primary.opacity(0.025),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                )
            }
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
        case .medium:
            return appModel.t(.homeWidgetSizeMedium)
        case .large:
            return appModel.t(.homeWidgetSizeLarge)
        case .wide:
            return appModel.t(.homeWidgetSizeWide)
        }
    }
}
