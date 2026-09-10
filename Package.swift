// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SciStationCore",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "SciStationCore", targets: ["SciStationCore"]),
        .executable(name: "SciStationCoreTestRunner", targets: ["SciStationCoreTestRunner"]),
        .executable(name: "SciStationUIProbe", targets: ["SciStationUIProbe"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
    ],
    targets: [
        .target(
            name: "SciStationCore",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sci-Station",
            exclude: [
                "App",
                "Assets.xcassets",
                "ContentView.swift",
                "PDF/EmbeddedPDFReaderView.swift",
                "PDF/PDFDocumentService.swift",
                "PDF/PDFOpeningService.swift",
                "PDF/PDFReaderViewModel.swift",
                "PDF/PDFReadingStateService.swift",
                "Resources",
                "SidecarRuntime.entitlements",
                "Sci_StationApp.swift",
                "UI/AILabWorkspaceView.swift",
                "UI/ChatMarkdownWebView.swift",
                "UI/CollectionManagerView.swift",
                "UI/ColorHex.swift",
                "UI/Components",
                "UI/DashboardViews.swift",
                "UI/Home",
                "UI/IdentifierImportView.swift",
                "UI/LaunchAnimationView.swift",
                "UI/LibraryViews.swift",
                "UI/MainShellViews.swift",
                "UI/MarkdownEditorView.swift",
                "UI/MarkdownPageListView.swift",
                "UI/MarkdownPreviewView.swift",
                "UI/MaterialsView.swift",
                "UI/ModuleSettings",
                "UI/PaperMarkdownConversionBadge.swift",
                "UI/ProjectOverviewView.swift",
                "UI/Previews",
                "UI/Recommendation",
                "UI/ResearchProjectEditorView.swift",
                "UI/SciStationDesignTokens.swift",
                "UI/SettingsViews.swift",
                "UI/Shell/ProjectSpaceContainer.swift",
                "UI/Shell/ProjectSpaceContentRouter.swift",
                "UI/Shell/PlaceholderViews.swift",
                "UI/Shell/AgentThreadSidebarView.swift",
                "UI/Shell/ShellRightRailViews.swift",
                "UI/Shell/TopSidebarView.swift",
                "UI/TagViews.swift",
                "UI/Tasks",
                "UI/WikiViews.swift",
                "Sci-Station.entitlements",
                "UI/Graph"
            ],
            sources: [
                "Workspace",
                "Persistence",
                "PluginKit",
                "Library",
                "Importer",
                "PDF/Annotations",
                "Markdown",
                "Wiki",
                "Collections",
                "Tags",
                "Tasks",
                "Calendar",
                "Recommendation",
                "Import",
                "MetadataProviders",
                "Localization",
                "LLM",
                "Agent",
                "Graph",
                "UI/Shell/ShellModels.swift",
                "UI/Shell/ResponsiveShellPolicy.swift",
                "UI/Shell/TopSidebarBuilder.swift",
                "UI/Shell/ProjectSpaceTabsBuilder.swift",
                "UI/Shell/ProjectSpaceTabIcon.swift",
                "UI/Shell/ToolbarCommandCatalog.swift",
                "UI/Shell/RoutePersistence.swift",
                "UI/WorkspaceSection.swift",
                "Testing"
            ]
        ),
        .executableTarget(
            name: "SciStationCoreTestRunner",
            dependencies: ["SciStationCore"],
            path: "Tools/SciStationCoreTestRunner"
        ),
        .executableTarget(
            name: "SciStationUIProbe",
            path: "Tools/SciStationUIProbe"
        ),
        .testTarget(
            name: "SciStationCoreTests",
            dependencies: ["SciStationCore"],
            path: "Tests/SciStationCoreTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
