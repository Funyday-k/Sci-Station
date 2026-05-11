// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SciStationCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SciStationCore", targets: ["SciStationCore"]),
        .executable(name: "SciStationCoreTestRunner", targets: ["SciStationCoreTestRunner"])
    ],
    targets: [
        .target(
            name: "SciStationCore",
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
                "Sci_StationApp.swift",
                "UI/AILabWorkspaceView.swift",
                "UI/ChatMarkdownWebView.swift",
                "UI/CollectionManagerView.swift",
                "UI/ColorHex.swift",
                "UI/DashboardViews.swift",
                "UI/Home",
                "UI/IdentifierImportView.swift",
                "UI/LibraryViews.swift",
                "UI/MainShellViews.swift",
                "UI/MarkdownEditorView.swift",
                "UI/MarkdownPageListView.swift",
                "UI/MarkdownPreviewView.swift",
                "UI/MaterialsView.swift",
                "UI/ModuleSettings",
                "UI/PaperMarkdownConversionBadge.swift",
                "UI/ProjectOverviewView.swift",
                "UI/ResearchProjectEditorView.swift",
                "UI/SciStationDesignTokens.swift",
                "UI/SettingsViews.swift",
                "UI/Shell/ProjectSpaceContainer.swift",
                "UI/Shell/ProjectSpaceContentRouter.swift",
                "UI/Shell/AgentThreadSidebarView.swift",
                "UI/Shell/ShellRightRailViews.swift",
                "UI/Shell/TopSidebarView.swift",
                "UI/TagViews.swift",
                "UI/WikiViews.swift",
                "UI/WorkspaceSection.swift"
            ],
            sources: [
                "Workspace",
                "Library",
                "Importer",
                "PDF/Annotations",
                "Markdown",
                "Wiki",
                "Collections",
                "Tags",
                "Tasks",
                "Calendar",
                "Import",
                "MetadataProviders",
                "Localization",
                "LLM",
                "Agent",
                "UI/Shell/ShellModels.swift",
                "UI/Shell/ResponsiveShellPolicy.swift",
                "UI/Shell/TopSidebarBuilder.swift",
                "UI/Shell/ProjectSpaceTabsBuilder.swift",
                "UI/Shell/RoutePersistence.swift"
            ],
            swiftSettings: [
                .unsafeFlags(["-default-isolation", "MainActor"])
            ]
        ),
        .executableTarget(
            name: "SciStationCoreTestRunner",
            dependencies: ["SciStationCore"],
            path: "Tools/SciStationCoreTestRunner",
            swiftSettings: [
                .unsafeFlags(["-default-isolation", "MainActor"])
            ]
        )
    ]
)