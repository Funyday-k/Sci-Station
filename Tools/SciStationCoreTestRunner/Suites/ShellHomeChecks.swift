import Foundation
import CoreGraphics
import SciStationCore

extension CoreVerificationSuite {
    func runShellHome() async {
        await runCheck("homeWidgetLayoutRoundTripsPreferences") { try await homeWidgetLayoutRoundTripsPreferences() }
        await runCheck("homeWidgetLayoutFallsBackWhenInvalid") { try await homeWidgetLayoutFallsBackWhenInvalid() }
        await runCheck("l10nCatalogResolvesChineseAndEnglish") { try l10nCatalogResolvesChineseAndEnglish() }
        await runCheck("l10nCatalogFallsBackWithAuditWarning") { try l10nCatalogFallsBackWithAuditWarning() }
        await runCheck("localizationAuditFlagsHardcodedSwiftUIText") { try localizationAuditFlagsHardcodedSwiftUIText() }
        await runCheck("workspaceContextSnapshotReflectsHomeRoute") { try workspaceContextSnapshotReflectsHomeRoute() }
        await runCheck("workspaceContextSnapshotReflectsProjectPaperSelection") { try workspaceContextSnapshotReflectsProjectPaperSelection() }
        await runCheck("rightRailAutoHidesWhenNoContext") { try rightRailAutoHidesWhenNoContext() }
        await runCheck("responsivePolicyHidesRightRailBelowThreshold") { try responsivePolicyHidesRightRailBelowThreshold() }
        await runCheck("responsivePolicyMovesToolbarActionsToOverflow") { try responsivePolicyMovesToolbarActionsToOverflow() }
        await runCheck("rightRailModePersistsAcrossWorkspaceReload") { try await rightRailModePersistsAcrossWorkspaceReload() }
        await runCheck("homeWidgetRegistryIncludesDefaultWidgets") { try homeWidgetRegistryIncludesDefaultWidgets() }
        await runCheck("homeWidgetRegistryFiltersDisabledModules") { try homeWidgetRegistryFiltersDisabledModules() }
        await runCheck("homeWidgetGridReflowsForTwoColumns") { try homeWidgetGridReflowsForTwoColumns() }
        await runCheck("homeWidgetGridReflowsForSingleColumn") { try homeWidgetGridReflowsForSingleColumn() }
        await runCheck("homeWidgetGridRepackAvoidsOverlap") { try homeWidgetGridRepackAvoidsOverlap() }
        await runCheck("homeWidgetGridUsesGravityPacking") { try homeWidgetGridUsesGravityPacking() }
        await runCheck("homeWidgetResetRestoresDefaultLayout") { try homeWidgetResetRestoresDefaultLayout() }
        await runCheck("homeWidgetDragOntoCommitsInBothDirections") { try homeWidgetDragOntoCommitsInBothDirections() }
        await runCheck("projectSpaceTabsBuilderHonorsAvailableModules") { try projectSpaceTabsBuilderHonorsAvailableModules() }
        await runCheck("projectSpaceTabsBuilderRespectsPinnedOrder") { try projectSpaceTabsBuilderRespectsPinnedOrder() }
        await runCheck("projectSpaceTabsBuilderRemovesDisabledModuleTabs") { try projectSpaceTabsBuilderRemovesDisabledModuleTabs() }
        await runCheck("projectSpaceTabsBuilderKeepsOverviewLeftmost") { try projectSpaceTabsBuilderKeepsOverviewLeftmost() }
        await runCheck("topSidebarBuilderProducesSixFixedItems") { try topSidebarBuilderProducesSixFixedItems() }
        await runCheck("routePersistenceRoundTripsLastRoute") { try await routePersistenceRoundTripsLastRoute() }
        await runCheck("routePersistenceFallsBackWhenProjectMissing") { try routePersistenceFallsBackWhenProjectMissing() }
        await runCheck("routePersistenceFallsBackWhenModuleDisabled") { try routePersistenceFallsBackWhenModuleDisabled() }
        await runCheck("projectSpaceContentRouterMapsAllKnownTabs") { try projectSpaceContentRouterMapsAllKnownTabs() }
        await runCheck("appDebugEventLoggerPersistsRedactedEvents") { try await appDebugEventLoggerPersistsRedactedEvents() }
        await runCheck("appDebugEventNameRegistryCoversAllEmittedEvents") { try appDebugEventNameRegistryCoversAllEmittedEvents() }
        await runCheck("appDebugEventNameRegistryFollowsNamingConvention") { try appDebugEventNameRegistryFollowsNamingConvention() }
        await runCheck("uitestAccessibilityIDFactoriesProduceValidIdentifiers") { try uitestAccessibilityIDFactoriesProduceValidIdentifiers() }
        await runCheck("uitestAccessibilityIDValidatorRejectsIllegalShapes") { try uitestAccessibilityIDValidatorRejectsIllegalShapes() }
        await runCheck("homeAggregatorReturnsEmptyDataForBlankWorkspace") { try await homeAggregatorReturnsEmptyDataForBlankWorkspace() }
        await runCheck("homeAggregatorRespectsCacheTTL") { try await homeAggregatorRespectsCacheTTL() }
        await runCheck("homeAggregatorInvalidatesOnDraftInboxChange") { try await homeAggregatorInvalidatesOnDraftInboxChange() }
        await runCheck("homeAggregatorInvalidatesOnTodoChange") { try await homeAggregatorInvalidatesOnTodoChange() }
        await runCheck("homeAggregatorErrorRecordsDebugEvent") { try await homeAggregatorErrorRecordsDebugEvent() }
        await runCheck("projectStageProviderInfersExplorationForBlankProject") { try projectStageProviderInfersExplorationForBlankProject() }
        await runCheck("projectStageProviderInfersOnHoldAfter21DaysIdle") { try projectStageProviderInfersOnHoldAfter21DaysIdle() }
        await runCheck("projectStageProviderInfersReviewingWhenUnsupportedClaimPresent") { try projectStageProviderInfersReviewingWhenUnsupportedClaimPresent() }
        await runCheck("projectDashboardAggregatorReturnsCorrectStage") { try projectDashboardAggregatorReturnsCorrectStage() }
        await runCheck("projectDashboardAggregatorOrdersArtifactsByCreatedDesc") { try projectDashboardAggregatorOrdersArtifactsByCreatedDesc() }
        await runCheck("homeSnapshotEncodesAndDecodesRoundTrip") { try await homeSnapshotEncodesAndDecodesRoundTrip() }
    }

    func homeWidgetLayoutRoundTripsPreferences() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("HomeWidgetPreferencesWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var preferences = try await repository.load(in: workspace)
        preferences.homeWidgetLayout.resizeWidget(HomeWidgetID.today, to: .medium, descriptors: HomeWidgetRegistry.defaultDescriptors, columns: 2)
        preferences.homeWidgetLayout.moveWidget(HomeWidgetID.aiReview, before: HomeWidgetID.today, descriptors: HomeWidgetRegistry.defaultDescriptors, columns: 2)
        preferences.homeWidgetLayout.setWidget(HomeWidgetID.calendar, isEnabled: false, descriptors: HomeWidgetRegistry.defaultDescriptors, columns: 2)
        try await repository.save(preferences, in: workspace)

        let loaded = try await repository.load(in: workspace)
        let loadedItems = Dictionary(uniqueKeysWithValues: loaded.homeWidgetLayout.items.map { ($0.widgetID, $0) })
        try expect(loadedItems[HomeWidgetID.today]?.size == .medium, "Home widget preferences should preserve resized widgets.")
        try expect(loadedItems[HomeWidgetID.calendar]?.isEnabled == false, "Home widget preferences should preserve disabled widgets.")
        let loadedOrder = loaded.homeWidgetLayout.items.map(\.widgetID)
        let aiIndex = loadedOrder.firstIndex(of: HomeWidgetID.aiReview) ?? Int.max
        let todayIndex = loadedOrder.firstIndex(of: HomeWidgetID.today) ?? Int.max
        try expect(aiIndex < todayIndex, "Home widget preferences should preserve explicit relative ordering.")
    }

    func homeWidgetLayoutFallsBackWhenInvalid() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("InvalidHomeWidgetPreferencesWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        let preferencesURL = workspace.fileURL(for: WorkspacePreferencesRepository.relativePath)
        try FileManager.default.createDirectory(at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        schema_version: 4
        home_widget_layout:
          schema_version: 1
          updated_at: "not-a-date"
          items:
            - widget_id: "unknown_widget"
              size: "giant"
              column: -4
              row: -2
              is_enabled: true
        """.write(to: preferencesURL, atomically: true, encoding: .utf8)

        let loaded = try await repository.load(in: workspace)
        let ids = loaded.homeWidgetLayout.items.map(\.widgetID)
        try expect(ids.contains(HomeWidgetID.today), "Invalid Home widget preferences should fall back to known default widgets.")
        try expect(!ids.contains("unknown_widget"), "Invalid Home widget preferences should drop unknown widget ids.")
    }

    func l10nCatalogResolvesChineseAndEnglish() throws {
        try expect(L10n.text(.toolbarImportPDF, language: .english) == "Import PDF", "English catalog should resolve Import PDF.")
        try expect(L10n.text(.toolbarImportPDF, language: .simplifiedChinese) == "导入 PDF", "Chinese catalog should resolve Import PDF.")
        try expect(L10n.text(.projectArchiveAction, language: .simplifiedChinese) == "归档项目", "Chinese catalog should resolve destructive project actions.")
        try expect(L10n.missingKeys(language: .english).isEmpty, "English localization catalog should cover all keys.")
        try expect(L10n.missingKeys(language: .simplifiedChinese).isEmpty, "Chinese localization catalog should cover all keys.")
    }

    func l10nCatalogFallsBackWithAuditWarning() throws {
        let result = L10n.resolve(rawKey: "missing.demo.key", language: .simplifiedChinese)

        try expect(result.usedFallback, "Raw missing localization keys should report fallback usage.")
        try expect(result.text == "missing.demo.key", "Raw missing localization keys should fall back to the key string.")
    }

    func localizationAuditFlagsHardcodedSwiftUIText() throws {
        let source = #"""
        VStack {
            Text("Import PDF")
            Label("folder", systemImage: "folder")
            Button(appModel.t(.toolbarImportPDF)) {}
        }
        """#
        let findings = LocalizationAudit.findings(in: source, filePath: "SampleView.swift")

        try expect(findings.contains { $0.literal == "Import PDF" }, "Localization audit should flag user-visible hardcoded English.")
        try expect(!findings.contains { $0.literal == "folder" }, "Localization audit should allow system image names and simple symbols.")
        try expect(!findings.contains { $0.literal == "toolbarImportPDF" }, "Localization audit should not flag L10n key references as literals.")
    }

    func workspaceContextSnapshotReflectsHomeRoute() throws {
        let snapshot = WorkspaceContextSnapshot(topLevelSectionID: WorkspaceRoute.Top.home.rawValue)

        try expect(snapshot.topLevelSectionID == "home", "Home context snapshots should preserve the top-level route id.")
        try expect(snapshot.displayTitle == "home", "Home context snapshots should use the top-level route as the fallback display title.")
    }

    func workspaceContextSnapshotReflectsProjectPaperSelection() throws {
        let snapshot = WorkspaceContextSnapshot(
            topLevelSectionID: WorkspaceRoute.Top.projects.rawValue,
            projectID: "project-a",
            projectTitle: "Dark Matter Maps",
            projectTabID: "papers",
            selectedPaperID: "paper-1",
            selectedPaperTitle: "A Compact Paper"
        )

        try expect(snapshot.projectID == "project-a", "Project snapshots should preserve the project id.")
        try expect(snapshot.projectTabID == "papers", "Project snapshots should preserve the active project tab.")
        try expect(snapshot.displayTitle == "Paper: A Compact Paper", "Paper selections should take precedence in context display titles.")
    }

    func rightRailAutoHidesWhenNoContext() throws {
        let homeRoute = WorkspaceRoute(top: .home)
        let homeContext = WorkspaceContextSnapshot(topLevelSectionID: "home")
        let libraryRoute = WorkspaceRoute(top: .library)
        let libraryContext = WorkspaceContextSnapshot(topLevelSectionID: "library")
        let projectsRoute = WorkspaceRoute(top: .projects, projectID: "proj-1", projectTabID: "reading")
        let projectsContext = WorkspaceContextSnapshot(topLevelSectionID: "projects", projectID: "proj-1", projectTabID: "reading")

        // 2026-05-17 UI Bug Bash: the right rail policy is now fully sticky —
        // suggestedMode echoes preferredMode back so user-driven toggles win.
        // Route-based hints have been moved to `defaultMode(for:)`, which is
        // only consulted when seeding an untouched workspace's initial state.
        try expect(RightRailPolicy.suggestedMode(route: homeRoute, context: homeContext, preferredMode: .inspector) == .inspector, "User-pinned inspector mode must survive a Home route refresh.")
        try expect(RightRailPolicy.suggestedMode(route: libraryRoute, context: libraryContext, preferredMode: .hidden) == .hidden, "User-hidden right rail must stay hidden across route changes (sticky preference).")
        try expect(RightRailPolicy.suggestedMode(route: projectsRoute, context: projectsContext, preferredMode: .inspector) == .inspector, "User-opened inspector must stay open on routes that previously hinted .hidden (Reading tab regression).")
        try expect(RightRailPolicy.suggestedMode(route: homeRoute, context: homeContext, preferredMode: .ai) == .ai, "An open AI rail should stay open across route context updates.")

        // `defaultMode(for:)` keeps the legacy auto-hide intent for workspace
        // bootstrap, but it is now opt-in for callers that want a fresh
        // workspace to start with a context-aware default.
        try expect(RightRailPolicy.defaultMode(route: homeRoute, context: homeContext) == .hidden, "Home default mode should still be .hidden so a fresh workspace doesn't open with an empty inspector.")
        try expect(RightRailPolicy.defaultMode(route: libraryRoute, context: libraryContext) == .inspector, "Library default mode should still seed the paper inspector for a fresh workspace.")
    }

    func responsivePolicyHidesRightRailBelowThreshold() throws {
        let context = WorkspaceContextSnapshot(topLevelSectionID: "library")
        let model = ResponsiveShellPolicy.resolve(
            width: 900,
            route: WorkspaceRoute(top: .library),
            context: context,
            preferredRightRailMode: .inspector
        )

        try expect(model.bucket == .compact, "Responsive shell policy should classify 900pt as compact.")
        try expect(model.effectiveRightRailMode == .hidden, "Responsive shell policy should hide the right rail below 1000pt.")
        try expect(model.homeWidgetColumns == 2, "Responsive shell policy should use two Home widget columns for compact widths.")
        try expect(model.shouldCollapseProjectTree, "Responsive shell policy should collapse project tree in compact widths.")

        let regularModel = ResponsiveShellPolicy.resolve(
            width: 1100,
            route: WorkspaceRoute(top: .home),
            context: WorkspaceContextSnapshot(topLevelSectionID: "home"),
            preferredRightRailMode: .hidden
        )
        try expect(regularModel.bucket == .regular, "Responsive shell policy should classify 1100pt as regular.")
        try expect(regularModel.homeWidgetColumns == 4, "Regular and expanded Home widget layouts should use the four-unit grid, not a three-column split.")
    }

    func responsivePolicyMovesToolbarActionsToOverflow() throws {
        let model = ToolbarPolicy.resolve(
            route: WorkspaceRoute(top: .library),
            context: WorkspaceContextSnapshot(topLevelSectionID: "library")
        )
        let narrowModel = ResponsiveShellPolicy.toolbarModel(model, width: 720)

        try expect(narrowModel.pageActions.isEmpty, "Narrow responsive policy should move page toolbar actions out of the primary group.")
        try expect(narrowModel.overflowActions.contains(where: { $0.id == .addByIdentifier }), "Narrow responsive policy should keep page actions reachable from overflow.")
        try expect(narrowModel.globalActions.contains(where: { $0.id == .workspaceMenu }), "Narrow responsive policy should keep global actions visible.")
    }

    func rightRailModePersistsAcrossWorkspaceReload() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let repository = WorkspacePreferencesRepository()
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("RightRailPreferencesWorkspace", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var preferences = try await repository.load(in: workspace)
        preferences.rightRailMode = .ai
        preferences.isGlobalAIPanelOpen = true
        preferences.isProjectTreeExpanded = false
        preferences.pinnedProjectIDs = ["project-a", "project-b"]
        try await repository.save(preferences, in: workspace)

        let loaded = try await repository.load(in: workspace)
        try expect(loaded.rightRailMode == .ai, "Workspace preferences should persist the right rail mode.")
        try expect(loaded.isGlobalAIPanelOpen, "Workspace preferences should persist AI panel open state.")
        try expect(!loaded.isProjectTreeExpanded, "Workspace preferences should persist project tree expansion state.")
        try expect(loaded.pinnedProjectIDs == ["project-a", "project-b"], "Workspace preferences should persist pinned project ids.")
    }

    func homeWidgetRegistryIncludesDefaultWidgets() throws {
        let ids = Set(HomeWidgetRegistry.defaultDescriptors.map(\.id))
        let expectedIDs: Set<String> = [
            HomeWidgetID.today,
            HomeWidgetID.activeProjects,
            HomeWidgetID.aiReview,
            HomeWidgetID.calendar,
            HomeWidgetID.recentPapers,
            HomeWidgetID.readingPlan,
            HomeWidgetID.projectHealth,
            HomeWidgetID.quickActions
        ]

        try expect(ids == expectedIDs, "Home widget registry should include every default dashboard widget.")
        try expect(HomeWidgetRegistry.defaultDescriptors.allSatisfy { !$0.supportedSizes.isEmpty }, "Home widget descriptors should declare supported sizes.")
        try expect(HomeWidgetRegistry.defaultDescriptors.allSatisfy { $0.supportedSizes == Set(HomeWidgetSize.allCases) }, "Every Home widget should support all five dashboard sizes.")
        try expect(HomeWidgetSize.small.rowSpan == 1 && HomeWidgetSize.small.columnSpan == 1, "Small widget size should be 1×1.")
        try expect(HomeWidgetSize.wide.rowSpan == 1 && HomeWidgetSize.wide.columnSpan == 2, "Wide widget size should be 1×2.")
        try expect(HomeWidgetSize.tall.rowSpan == 2 && HomeWidgetSize.tall.columnSpan == 1, "Tall widget size should be 2×1.")
        try expect(HomeWidgetSize.medium.rowSpan == 2 && HomeWidgetSize.medium.columnSpan == 2, "Medium widget size should be 2×2.")
        try expect(HomeWidgetSize.large.rowSpan == 3 && HomeWidgetSize.large.columnSpan == 3, "Large widget size should be 3×3.")
    }

    func homeWidgetRegistryFiltersDisabledModules() throws {
        let configuration = WorkspaceModuleRegistry.defaultConfiguration(enabledModuleIDs: ["projects"])
        let availableIDs = Set(HomeWidgetRegistry.availableDescriptors(in: configuration).map(\.id))

        try expect(availableIDs.contains(HomeWidgetID.activeProjects), "Project widgets should remain available when Projects is enabled.")
        try expect(availableIDs.contains(HomeWidgetID.quickActions), "Quick Actions should remain available without module dependencies.")
        try expect(!availableIDs.contains(HomeWidgetID.calendar), "Calendar widget should hide when Calendar module is disabled.")
        try expect(!availableIDs.contains(HomeWidgetID.aiReview), "AI Review widget should hide when AI Lab module is disabled.")
    }

    func homeWidgetGridReflowsForTwoColumns() throws {
        let layout = HomeWidgetLayout.defaultLayout(columns: 2)
        let descriptorsByID = Dictionary(uniqueKeysWithValues: HomeWidgetRegistry.defaultDescriptors.map { ($0.id, $0) })
        let cells = HomeWidgetGridPlanner.cells(items: layout.items, descriptorsByID: descriptorsByID, columns: 2)

        try expect(!cells.isEmpty, "Home widget planner should emit cells for default layout.")
        try expect(cells.allSatisfy { $0.item.column + $0.columnSpan <= 2 }, "Home widget planner should clamp cells inside two columns.")
        try expect(!HomeWidgetGridPlanner.hasOverlap(items: layout.items, descriptorsByID: descriptorsByID, columns: 2), "Two-column Home widget layout should not overlap.")
    }

    func homeWidgetGridReflowsForSingleColumn() throws {
        let layout = HomeWidgetLayout.defaultLayout(columns: 1)
        let descriptorsByID = Dictionary(uniqueKeysWithValues: HomeWidgetRegistry.defaultDescriptors.map { ($0.id, $0) })
        let cells = HomeWidgetGridPlanner.cells(items: layout.items, descriptorsByID: descriptorsByID, columns: 1)

        try expect(cells.allSatisfy { $0.item.column == 0 && $0.columnSpan == 1 }, "Single-column Home widget layout should stack every widget in column zero.")
        try expect(!HomeWidgetGridPlanner.hasOverlap(items: layout.items, descriptorsByID: descriptorsByID, columns: 1), "Single-column Home widget layout should not overlap.")
    }

    func homeWidgetGridRepackAvoidsOverlap() throws {
        let descriptors = HomeWidgetRegistry.defaultDescriptors
        let descriptorsByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let collidingLayout = HomeWidgetLayout(items: [
            HomeWidgetLayoutItem(widgetID: HomeWidgetID.today, size: .wide, column: 0, row: 0),
            HomeWidgetLayoutItem(widgetID: HomeWidgetID.activeProjects, size: .wide, column: 0, row: 0),
            HomeWidgetLayoutItem(widgetID: HomeWidgetID.aiReview, size: .medium, column: 0, row: 0)
        ])
        let normalized = collidingLayout.normalized(descriptors: descriptors, columns: 4)

        try expect(!HomeWidgetGridPlanner.hasOverlap(items: normalized.items, descriptorsByID: descriptorsByID, columns: 4), "Home widget planner should repack colliding items without overlap.")
        try expect(normalized.items.count == descriptors.count, "Home widget normalization should backfill missing default descriptors.")
    }

    func homeWidgetGridUsesGravityPacking() throws {
        let descriptors = HomeWidgetRegistry.defaultDescriptors
        let descriptorsByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let layout = HomeWidgetLayout(items: [
            HomeWidgetLayoutItem(widgetID: HomeWidgetID.today, size: .tall),
            HomeWidgetLayoutItem(widgetID: HomeWidgetID.activeProjects, size: .wide),
            HomeWidgetLayoutItem(widgetID: HomeWidgetID.aiReview, size: .small),
            HomeWidgetLayoutItem(widgetID: HomeWidgetID.quickActions, size: .medium)
        ]).normalized(descriptors: descriptors, columns: 4)

        let items = Dictionary(uniqueKeysWithValues: layout.items.map { ($0.widgetID, $0) })
        try expect(items[HomeWidgetID.today]?.column == 0 && items[HomeWidgetID.today]?.row == 0, "First tall widget should drop into the first column.")
        try expect(items[HomeWidgetID.activeProjects]?.column == 1 && items[HomeWidgetID.activeProjects]?.row == 0, "Wide widget should drop beside the tall widget when columns 1-2 are lower.")
        try expect(items[HomeWidgetID.aiReview]?.column == 3 && items[HomeWidgetID.aiReview]?.row == 0, "Small widget should fill the remaining low column before stacking below taller columns.")
        try expect(!HomeWidgetGridPlanner.hasOverlap(items: layout.items, descriptorsByID: descriptorsByID, columns: 4), "Gravity-packed widgets should not overlap.")
    }

    func homeWidgetResetRestoresDefaultLayout() throws {
        let descriptors = HomeWidgetRegistry.defaultDescriptors
        var layout = HomeWidgetLayout.defaultLayout(descriptors: descriptors, columns: 4)
        layout.moveWidget(HomeWidgetID.quickActions, before: HomeWidgetID.today, descriptors: descriptors, columns: 4)
        layout.setWidget(HomeWidgetID.calendar, isEnabled: false, descriptors: descriptors, columns: 4)
        layout.reset(descriptors: descriptors, columns: 4)

        let defaultLayout = HomeWidgetLayout.defaultLayout(descriptors: descriptors, columns: 4)
        try expect(layout.items.map(\.widgetID) == defaultLayout.items.map(\.widgetID), "Reset should restore Home widget default order.")
        try expect(layout.items.allSatisfy(\.isEnabled), "Reset should re-enable default Home widgets.")
    }

    /// 2026-05-17 UI Bug Bash Round 3 regression. The user reported that
    /// dragging a Home widget briefly settled into the new spot and then
    /// snapped back. Two model-side bugs were responsible:
    ///
    /// 1. `repack` re-sorted `items` by `(row, column)` BEFORE laying them
    ///    out, but at the moment `moveWidget(_:before:)` calls `repack` the
    ///    items still carry their pre-move positions, so the sort silently
    ///    restored the original order — every drag was a no-op once persisted
    ///    (verified in `~/Documents/ResearchWorkspace/.sci-station/debug/app_events.jsonl`
    ///    at 2026-05-17T09:13:18Z).
    ///
    /// 2. `moveWidget(_:before:)` was asymmetric — for forward drags
    ///    (`sourceIndex < targetIndex`) inserting "immediately before target"
    ///    only nudges the source one slot, never landing on the target's
    ///    tile. The dashboard now calls the unified `onto:` variant which
    ///    swaps source into target's slot regardless of drag direction.
    ///
    /// Both regressions covered here against `cols = 4` (typical expanded
    /// dashboard width) so a future refactor that re-introduces the position
    /// sort will fail the same scenarios the user manually hit.

    func homeWidgetDragOntoCommitsInBothDirections() throws {
        let descriptors = HomeWidgetRegistry.defaultDescriptors

        // Backward drag: aiReview (idx 2) → onto activeProjects (idx 1).
        // The user's actual logged action; before the fix this came back as
        // a no-op because repack's positionSort restored the old order.
        var backward = HomeWidgetLayout.defaultLayout(descriptors: descriptors, columns: 4)
        backward.moveWidget(HomeWidgetID.aiReview, onto: HomeWidgetID.activeProjects, descriptors: descriptors, columns: 4)
        let backwardOrder = backward.items.map(\.widgetID)
        let aiIdxBackward = backwardOrder.firstIndex(of: HomeWidgetID.aiReview) ?? Int.max
        let activeIdxBackward = backwardOrder.firstIndex(of: HomeWidgetID.activeProjects) ?? Int.max
        try expect(aiIdxBackward < activeIdxBackward, "Backward drag (aiReview onto activeProjects) must land aiReview at activeProjects's slot.")

        // Forward drag: today (idx 0) → onto aiReview (idx 2). Before the
        // `onto:` semantic this only moved today by one slot; after the fix
        // today must land at aiReview's exact slot.
        var forward = HomeWidgetLayout.defaultLayout(descriptors: descriptors, columns: 4)
        forward.moveWidget(HomeWidgetID.today, onto: HomeWidgetID.aiReview, descriptors: descriptors, columns: 4)
        let forwardOrder = forward.items.map(\.widgetID)
        let todayIdxForward = forwardOrder.firstIndex(of: HomeWidgetID.today) ?? Int.max
        let aiIdxForward = forwardOrder.firstIndex(of: HomeWidgetID.aiReview) ?? Int.max
        try expect(todayIdxForward > aiIdxForward, "Forward drag (today onto aiReview) must place today AFTER aiReview in the order, swapping into aiReview's slot.")

        // Repacking the layout (e.g. via `setWidget`) MUST NOT silently
        // restore the pre-move order. This was the second model bug — the
        // `repack` helper used to sort by `(row, column)` first, undoing the
        // move once items were laid out. The post-fix invariant: the user's
        // intended array order survives any subsequent normalize / repack.
        forward.setWidget(HomeWidgetID.calendar, isEnabled: false, descriptors: descriptors, columns: 4)
        let postRepackOrder = forward.items.filter(\.isEnabled).map(\.widgetID)
        let todayIdxAfter = postRepackOrder.firstIndex(of: HomeWidgetID.today) ?? Int.max
        let aiIdxAfter = postRepackOrder.firstIndex(of: HomeWidgetID.aiReview) ?? Int.max
        try expect(todayIdxAfter > aiIdxAfter, "Subsequent repack (via setWidget) must NOT restore the pre-move order — the user's drag must persist across normalization.")
    }

    func projectSpaceTabsBuilderHonorsAvailableModules() throws {
        let tabs = ProjectSpaceTabsBuilder.tabs(
            for: "project-a",
            configuration: WorkspaceModuleRegistry.defaultConfiguration(),
            pinnedOrder: []
        )
        let ids = tabs.map(\.id)

        try expect(ids.contains("overview"), "ProjectSpace tabs should include Overview from the projects module.")
        try expect(ids.contains("papers"), "ProjectSpace tabs should include Papers from the paper-library module.")
    try expect(!ids.contains("reading"), "ProjectSpace tabs should not expose Reading after it is merged into Tasks.")
        try expect(ids.contains("recommendations"), "ProjectSpace tabs should include arXiv Recommendations from the recommendation module.")
    try expect(tabs.first(where: { $0.id == "recommendations" })?.title == "论文推荐", "Recommendation project tab should use the Chinese title.")
        try expect(!ids.contains("queue"), "ProjectSpace tabs should not expose Queue as a separate tab after Reading consolidation.")
        try expect(!ids.contains("reading-plan"), "ProjectSpace tabs should not expose Reading Plan as a separate tab after Reading consolidation.")
        try expect(ids.contains("wiki"), "ProjectSpace tabs should include Wiki from the wiki module.")
        try expect(ids.contains("tasks"), "ProjectSpace tabs should include Tasks from the tasks module.")
        try expect(ids.contains("calendar"), "ProjectSpace tabs should include Calendar from the calendar module.")
        try expect(ids.contains("ai-drafts"), "ProjectSpace tabs should include AI Workflows from the AI Lab module.")
    }

    func projectSpaceTabsBuilderRespectsPinnedOrder() throws {
        let tabs = ProjectSpaceTabsBuilder.tabs(
            for: "project-a",
            configuration: WorkspaceModuleRegistry.defaultConfiguration(),
            pinnedOrder: ["wiki", "papers"]
        )
        let ids = tabs.map(\.id)

        try expect(ids.prefix(3) == ["overview", "wiki", "papers"], "Pinned ProjectSpace tabs should follow Overview while preserving its fixed leftmost position.")
    }

    func projectSpaceTabsBuilderRemovesDisabledModuleTabs() throws {
        var configuration = WorkspaceModuleRegistry.defaultConfiguration()
        for index in configuration.modules.indices where configuration.modules[index].id == "wiki" {
            configuration.modules[index].enabled = false
        }

        let ids = ProjectSpaceTabsBuilder.tabs(for: "project-a", configuration: configuration, pinnedOrder: []).map(\.id)
        try expect(!ids.contains("wiki"), "Disabling the wiki module should remove the Wiki ProjectSpace tab.")
    }

    func projectSpaceTabsBuilderKeepsOverviewLeftmost() throws {
        let tabs = ProjectSpaceTabsBuilder.tabs(
            for: "project-a",
            configuration: WorkspaceModuleRegistry.defaultConfiguration(),
            pinnedOrder: ["tasks", "overview", "calendar"]
        )
        try expect(tabs.first?.id == "overview", "Overview should remain the leftmost ProjectSpace tab.")
    }

    func topSidebarBuilderProducesSixFixedItems() throws {
        let items = TopSidebarBuilder.items(pinnedOrder: ["settings", "library", "home"])
        let ids = items.map(\.id)

        try expect(Set(ids) == Set(["home", "projects", "library", "calendar", "ai-lab", "settings"]), "Top sidebar should contain exactly the six P43 top-level items.")
        try expect(ids.count == 6, "Top sidebar should not duplicate fixed items.")
        try expect(items.last?.id == "settings", "Settings should remain in the fixed top-level set.")
    }

    func routePersistenceRoundTripsLastRoute() async throws {
        let suiteName = "SciStationCoreTestRunner.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suiteName), "Failed to create isolated UserDefaults suite.")
        let bookmarkStore = WorkspaceBookmarkStore(defaults: defaults)
        let workspaceService = WorkspaceService(fileManager: .default, bookmarkStore: bookmarkStore)
        let workspaceRoot = temporaryDirectoryURL().appendingPathComponent("RoutePersistenceWorkspace", isDirectory: true)
        let repository = WorkspacePreferencesRepository()

        defer {
            try? FileManager.default.removeItem(at: workspaceRoot.deletingLastPathComponent())
            defaults.removePersistentDomain(forName: suiteName)
        }

        let workspace = try await workspaceService.createWorkspace(at: workspaceRoot)
        var preferences = try await repository.load(in: workspace)
        let route = WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "wiki", secondarySelection: nil)
        preferences.lastRoute = route
        try await repository.save(preferences, in: workspace)

        let loaded = try await repository.load(in: workspace)
        try expect(loaded.lastRoute == route, "WorkspacePreferences should round-trip the last ProjectSpace route.")
    }

    func routePersistenceFallsBackWhenProjectMissing() throws {
        let result = RoutePersistence.restoreResult(
            candidate: WorkspaceRoute(top: .projects, projectID: "missing", projectTabID: "wiki"),
            activeProjectIDs: ["project-a"],
            configuration: WorkspaceModuleRegistry.defaultConfiguration()
        )

        try expect(result.route == WorkspaceRoute(top: .projects), "Missing project routes should fall back to the project list.")
        try expect(result.fallbackReason == .projectMissing, "Missing project routes should report project_missing.")
    }

    func routePersistenceFallsBackWhenModuleDisabled() throws {
        let result = RoutePersistence.restoreResult(
            candidate: WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "graph"),
            activeProjectIDs: ["project-a"],
            configuration: WorkspaceModuleRegistry.defaultConfiguration(
                enabledModuleIDs: WorkspaceModuleRegistry.defaultEnabledModuleIDs.subtracting(["citation-graph"])
            )
        )

        try expect(result.route == WorkspaceRoute(top: .projects, projectID: "project-a", projectTabID: "overview"), "Disabled module routes should fall back to ProjectSpace Overview.")
        try expect(result.fallbackReason == .moduleDisabled, "Disabled module routes should report module_disabled.")
    }

    func projectSpaceContentRouterMapsAllKnownTabs() throws {
        for tabID in ProjectSpaceTabsBuilder.defaultOrder {
            try expect(!ProjectSpaceTabsBuilder.systemImage(for: tabID).isEmpty, "ProjectSpace tab \(tabID) should have a router/icon mapping.")
        }
    }

    func appDebugEventLoggerPersistsRedactedEvents() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("AppDebugEventWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let logger = AppDebugEventLogger()
        try await logger.append(AppDebugEvent(
            event: "agent.prompt_submitted",
            workspaceID: "workspace-1",
            projectID: "project-1",
            threadID: "thread-1",
            runID: "run-1",
            payload: .object([
                "api_key": .string("sk-secret"),
                "prompt": .string("read /private/tmp/paper.md")
            ])
        ), in: root)

        let events = try await logger.events(in: root)
        let firstPayload = try require(events.first?.payload.objectValue, "Debug event should persist a structured payload.")
        try expect(events.count == 1, "Debug event logger should replay persisted events.")
        try expect(firstPayload["api_key"] == .string("[REDACTED]"), "Debug event logger should redact API keys.")
        try expect(firstPayload["prompt"] == .string("read [PATH]"), "Debug event logger should redact private paths.")
        try expect(FileManager.default.fileExists(atPath: root.fileURL(for: AppDebugEventLogger.relativePath).path), "Debug event logger should write a workspace-local JSONL file.")
    }

    /// The AI Usage Test orchestrator treats
    /// `AppDebugEventName.allCases` as the source-of-truth registry of every
    /// debug event the App may emit. The hard-coded list below is the set of
    /// event names that current call sites in the codebase emit. If you add
    /// a new `recordAppDebugEvent("...")` / `AppDebugEvent(event: ...)` /
    /// `emit("...")` call site, you MUST:
    ///   1. Add a matching case to `AppDebugEventName`.
    ///   2. Append the raw value to the `emittedEventAllowList` below.
    ///
    /// Keeping these two surfaces aligned guarantees the Python uitest
    /// orchestrator can enumerate every event it might see in
    /// `app_events.jsonl` and that nothing slips through without review.

    func appDebugEventNameRegistryCoversAllEmittedEvents() throws {
        let registered = Set(AppDebugEventName.allCases.map(\.rawValue))
        let emittedEventAllowList: [String] = [
            // Route persistence
            "route.persist", "route.persist.fallback", "route.persist.error",
            // Project space / shell
            "project_space.tab_change", "project_space.builder_warn",
            "shell.right_rail.change", "shell.ai_panel.open", "shell.responsive_policy.apply",
            "toolbar.policy.resolve", "sidebar.render",
            // Project lifecycle
            "project.archive.requested", "project.delete.requested",
            // Wiki / Markdown
            "wiki.file.create", "wiki.file.rename", "wiki.file.archive",
            "markdown.editor.save_state", "paper_markdown.open_direct",
            // Agent
            "agent.prompt_submitted", "agent.run_completed", "agent.run_failed",
            "agent.run_cancelled", "agent.run_opened", "agent.runtime_selection_changed",
            "agent.stop_requested", "agent.context_changed",
            "agent.thread_started", "agent.thread_selected", "agent.thread_archived",
            "agent.thread_draft_discarded", "agent.archived_thread_selection_blocked",
            "agent.tools_execution_started", "agent.tools_execution_completed",
            "agent.tools_execution_failed", "agent.tools_resume_completed",
            "agent.tool.graph_query", "agent.tool.graph_result_size", "agent.tool.graph_error",
            "agent.tool.graph_insight_draft", "agent.tool.graph_blocked_by_module",
            "agent.intent.graph_routed",
            // AI Lab UX / permissions
            "ai.mode.change", "ai.timeline.project", "ai.toolset.unavailable",
            "ai.permission.inline_decision", "ai.draft_review.rewrite_requested",
            // Appearance / l10n
            "appearance.liquid_glass_tint.change", "l10n.language.change",
            // Debug
            "debug.mode.changed", "debug.log.opened",
            // Home / Project Dashboard
            "home.aggregate", "home.aggregate.error", "home.cache.invalidate",
            "home.panel.action", "home.widget.gallery",
            "home.widget.layout_enter_edit", "home.widget.layout_exit_edit",
            "home.widget.move", "home.widget.resize", "home.widget.toggle",
            "home.widget.reset_default",
            "project_dashboard.render", "project_dashboard.stage_inferred",
            // PDF annotations
            "pdf.annotation.create", "pdf.annotation.update",
            "pdf.annotation.delete", "pdf.annotation.duplicate_skipped",
            "recommendation.arxiv_refresh", "recommendation.archive",
            "recommendation.ai_search.error", "recommendation.error",
            "recommendation.feedback", "recommendation.push.error",
            // Module settings
            "module_settings.toggle", "module_settings.toggle_chain", "module_settings.pin",
            // Graph
            "graph.indexer.rebuild_started", "graph.indexer.rebuild_finished",
            "graph.indexer.incremental_skip",
            "graph.repository.loaded", "graph.repository.write",
            "graph.repository.compact", "graph.repository.compact.error",
            "graph.repository.replay_skip",
            "citation.edge_upsert", "citation.edge_tombstone",
            "citation.parse.bibtex", "citation.parse.markdown", "citation.resolve_unmatched"
        ]

        let missing = emittedEventAllowList.filter { !registered.contains($0) }
        try expect(
            missing.isEmpty,
            "AppDebugEventName is missing case(s) for emitted event(s): \(missing.sorted().joined(separator: ", ")). " +
            "Add them to Sci-Station/Agent/AppDebugEventName.swift so the AI uitest orchestrator can enumerate them."
        )

        // Sanity: the registry must not shrink unexpectedly. We bake in the
        // approximate floor so accidental case deletions are caught.
        try expect(
            AppDebugEventName.allCases.count >= emittedEventAllowList.count,
            "AppDebugEventName.allCases.count (\(AppDebugEventName.allCases.count)) dropped below the emitted-event allow-list size (\(emittedEventAllowList.count))."
        )
    }

    /// Lint: every registered event name must follow the
    /// `<domain>.<entity>(.<verb>)?` snake_case convention so the orchestrator
    /// can pattern-match domain/entity buckets when grouping scenarios.

    func appDebugEventNameRegistryFollowsNamingConvention() throws {
        for event in AppDebugEventName.allCases {
            try expect(
                AppDebugEventName.isValidEventName(event.rawValue),
                "AppDebugEventName.\(event) raw value '\(event.rawValue)' violates snake_case <domain>.<entity>(.<verb>)? convention."
            )
        }

        let rawValues = AppDebugEventName.allCases.map(\.rawValue)
        try expect(
            Set(rawValues).count == rawValues.count,
            "AppDebugEventName raw values must be unique; found duplicates."
        )
    }

    /// `UITestAccessibilityID` is a thin namespace, but the AI uitest
    /// orchestrator depends on every factory output being machine-readable.
    /// This test covers the four high-traffic surfaces used by UI tests so
    /// future refactors that drop the strict format fail loudly.

    func uitestAccessibilityIDFactoriesProduceValidIdentifiers() throws {
        let identifiers: [String] = [
            UITestAccessibilityID.App.mainWindowRoot,
            UITestAccessibilityID.Sidebar.tab("library"),
            UITestAccessibilityID.Sidebar.tab("settings"),
            UITestAccessibilityID.Sidebar.projectTreeToggle,
            UITestAccessibilityID.Sidebar.projectCreateButton,
            UITestAccessibilityID.Home.widget("today"),
            UITestAccessibilityID.Home.widget("active_projects"),
            UITestAccessibilityID.Library.list,
            UITestAccessibilityID.Library.importButton,
            UITestAccessibilityID.Library.paper("arxiv-2604.22012"),
            UITestAccessibilityID.Workspace.section("dashboard"),
            UITestAccessibilityID.Workspace.section("library")
        ]
        for identifier in identifiers {
            try expect(
                UITestAccessibilityID.isValidIdentifier(identifier),
                "UITestAccessibilityID factory produced invalid identifier: '\(identifier)'."
            )
        }
    }

    func uitestAccessibilityIDValidatorRejectsIllegalShapes() throws {
        let illegal: [String] = [
            "",
            "no_dot",
            "Library.Paper",            // capital letters
            "library..paper",            // empty segment
            ".leading.dot",
            "trailing.dot.",
            "library paper",             // space in non-terminal
            "library.pa per",            // space in terminal
            "library.paper.\u{4F60}\u{597D}" // non-ASCII (中文)
        ]
        for raw in illegal {
            try expect(
                !UITestAccessibilityID.isValidIdentifier(raw),
                "UITestAccessibilityID validator should reject malformed identifier: '\(raw)'."
            )
        }
    }

    /// The orchestrator parses ``swiftui_warnings.log`` by splitting on
    /// newlines and then tabs, so the formatter must emit exactly five
    /// tab-separated fields per record. This test pins the contract.

    func homeAggregatorReturnsEmptyDataForBlankWorkspace() async throws {
        let aggregator = HomeAggregator()
        let snapshot = try await aggregator.snapshot(input: HomeAggregationInput(workspaceID: "blank-workspace"), now: Date(timeIntervalSince1970: 1_777_600_000))

        try expect(snapshot.today.dueTodos.isEmpty, "Blank workspace should have no due todos.")
        try expect(snapshot.today.readingPapers.isEmpty, "Blank workspace should have no reading papers.")
        try expect(snapshot.activeProjects.isEmpty, "Blank workspace should have no active projects.")
        try expect(snapshot.aiReview.needsApproval.isEmpty, "Blank workspace should have no pending AI drafts.")
    }

    func homeAggregatorRespectsCacheTTL() async throws {
        let aggregator = HomeAggregator(cacheTTL: 60)
        let input = HomeAggregationInput(workspaceID: "ttl-workspace")
        let first = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_000))
        let second = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_010))
        let third = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_070))

        try expect(first.builtAt == second.builtAt, "HomeAggregator should return cached snapshots inside the TTL.")
        try expect(third.builtAt != first.builtAt, "HomeAggregator should rebuild snapshots after the TTL expires.")
    }

    func homeAggregatorInvalidatesOnDraftInboxChange() async throws {
        let aggregator = HomeAggregator(cacheTTL: 60)
        let input = HomeAggregationInput(workspaceID: "draft-invalidation-workspace")
        let first = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_000))
        await aggregator.invalidate(reason: "draft_change")
        let second = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_005))

        try expect(first.builtAt != second.builtAt, "Draft inbox invalidation should force a Home snapshot rebuild inside the TTL.")
    }

    func homeAggregatorInvalidatesOnTodoChange() async throws {
        let aggregator = HomeAggregator(cacheTTL: 60)
        let input = HomeAggregationInput(workspaceID: "todo-invalidation-workspace")
        let first = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_000))
        await aggregator.invalidate(reason: "todo_change")
        let second = try await aggregator.snapshot(input: input, now: Date(timeIntervalSince1970: 1_777_600_006))

        try expect(first.builtAt != second.builtAt, "Todo invalidation should force a Home snapshot rebuild inside the TTL.")
    }

    func homeAggregatorErrorRecordsDebugEvent() async throws {
        let rootURL = temporaryDirectoryURL().appendingPathComponent("HomeAggregatorErrorWorkspace", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let root = ResearchRoot(rootURL: rootURL)
        let logger = AppDebugEventLogger()
        let aggregator = HomeAggregator(debugLogger: logger, debugRoot: root)

        do {
            _ = try await aggregator.snapshot(input: HomeAggregationInput(workspaceID: "error-workspace", failureReason: "forced failure"))
            try expect(false, "HomeAggregator should throw when its input forces a failure.")
        } catch {
            let events = try await logger.events(in: root)
            try expect(events.contains { $0.event == "home.aggregate.error" }, "HomeAggregator should record home.aggregate.error when build fails.")
        }
    }

    func projectStageProviderInfersExplorationForBlankProject() throws {
        let decision = ProjectStageProvider().stage(for: ProjectStageSignal(projectID: "blank"), today: Date(timeIntervalSince1970: 1_777_600_000))
        try expect(decision.stage == .exploration, "Blank project should infer exploration stage.")
    }

    func projectStageProviderInfersOnHoldAfter21DaysIdle() throws {
        let today = Date(timeIntervalSince1970: 1_777_600_000)
        let oldActivity = today.addingTimeInterval(-22 * 86_400)
        let decision = ProjectStageProvider().stage(for: ProjectStageSignal(projectID: "idle", papersCount: 8, wikiPageCount: 4, lastActivityAt: oldActivity), today: today)
        try expect(decision.stage == .onHold, "Projects idle for more than 21 days should infer on_hold.")
    }

    func projectStageProviderInfersReviewingWhenUnsupportedClaimPresent() throws {
        let decision = ProjectStageProvider().stage(for: ProjectStageSignal(projectID: "review", papersCount: 8, unsupportedClaimCount: 2), today: Date(timeIntervalSince1970: 1_777_600_000))
        try expect(decision.stage == .reviewing, "Unsupported claims should infer reviewing stage.")
    }

    func projectDashboardAggregatorReturnsCorrectStage() throws {
        let project = sampleResearchProject(id: "project-stage")
        let papers = (0..<5).map { index -> Paper in
            var paper = samplePaper(id: "stage-paper-\(index)")
            paper.projectIDs = [project.id]
            paper.coreProjectIDs = index < 2 ? [project.id] : []
            return paper
        }
        let run = sampleAgentRun(
            id: "stage-run",
            projectID: project.id,
            createdAt: Date(timeIntervalSince1970: 1_777_600_000),
            toolResults: [try artifactToolResult(runID: "stage-run", kind: "research_plan", createdAt: Date(timeIntervalSince1970: 1_777_600_000))]
        )
        let input = ProjectDashboardAggregationInput(
            workspaceID: "project-dashboard-stage",
            project: project,
            papers: papers,
            todos: [],
            markdownDocuments: [sampleMarkdownDocument(relativePath: "wiki/gaps/project-stage-gap.md", title: "Open Gap")],
            agentRuns: [run],
            unsupportedClaims: []
        )

        let snapshot = try require(ProjectDashboardSnapshotBuilder().build(input: input, now: Date(timeIntervalSince1970: 1_777_600_010)), "Project dashboard snapshot should build for selected project.")
        try expect(snapshot.stage == .planning, "Project dashboard should infer planning when papers, research plan, and open gaps are present.")
    }

    func projectDashboardAggregatorOrdersArtifactsByCreatedDesc() throws {
        let project = sampleResearchProject(id: "project-artifacts")
        let olderRun = sampleAgentRun(
            id: "older-run",
            projectID: project.id,
            createdAt: Date(timeIntervalSince1970: 1_777_500_000),
            toolResults: [try artifactToolResult(runID: "older-run", kind: "research_plan", createdAt: Date(timeIntervalSince1970: 1_777_500_000), title: "Older Artifact")]
        )
        let newerRun = sampleAgentRun(
            id: "newer-run",
            projectID: project.id,
            createdAt: Date(timeIntervalSince1970: 1_777_600_000),
            toolResults: [try artifactToolResult(runID: "newer-run", kind: "related_work", createdAt: Date(timeIntervalSince1970: 1_777_600_000), title: "Newer Artifact")]
        )
        let input = ProjectDashboardAggregationInput(
            workspaceID: "project-dashboard-artifacts",
            project: project,
            agentRuns: [olderRun, newerRun]
        )

        let snapshot = try require(ProjectDashboardSnapshotBuilder().build(input: input, now: Date(timeIntervalSince1970: 1_777_600_010)), "Project dashboard snapshot should build for artifact ordering.")
        try expect(Array(snapshot.recentArtifacts.map(\.title).prefix(2)) == ["Newer Artifact", "Older Artifact"], "Project dashboard should order recent artifacts newest first.")
    }

    func homeSnapshotEncodesAndDecodesRoundTrip() async throws {
        let project = sampleResearchProject(id: "roundtrip-project")
        var paper = samplePaper(id: "roundtrip-paper")
        paper.projectIDs = [project.id]
        let todo = sampleTodo(id: "roundtrip-todo", title: "Read queue", projectID: project.id, dueDate: Date(timeIntervalSince1970: 1_777_600_000))
        let run = sampleAgentRun(id: "roundtrip-run", projectID: project.id, createdAt: Date(timeIntervalSince1970: 1_777_599_000), lifecycleState: .waitingForApproval)
        let snapshot = try await HomeAggregator().snapshot(input: HomeAggregationInput(
            workspaceID: "roundtrip-workspace",
            currentProjectID: project.id,
            projects: [project],
            papers: [paper],
            todos: [todo],
            agentRuns: [run]
        ), now: Date(timeIntervalSince1970: 1_777_600_000))

        let data = try AgentRunDirectoryStore.encoder().encode(snapshot)
        let decoded = try AgentRunDirectoryStore.decoder().decode(HomeSnapshot.self, from: data)
        try expect(decoded == snapshot, "HomeSnapshot should encode and decode without losing panel data.")
    }
}
