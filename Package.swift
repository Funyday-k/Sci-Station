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
                "PDF",
                "Resources",
                "Sci_StationApp.swift",
                "UI"
            ],
            sources: ["Workspace", "Library", "Importer", "Markdown", "Wiki", "Collections", "Tags", "Tasks", "Calendar", "Import", "MetadataProviders", "LLM", "Agent"],
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