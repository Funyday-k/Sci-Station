//
//  Sci_StationApp.swift
//  Sci-Station
//
//  Created by Funyday on 2026/4/27.
//

import SwiftUI

@main
struct Sci_StationApp: App {
    @StateObject private var appModel = AppViewModel()
    @StateObject private var launchCoordinator = SciStationLaunchCoordinator()

    init() {
        SciStationWindowRestoration.clearMainWindowState()
        _ = SidecarRuntimeSmokeTest.startIfRequested()
    }

    var body: some Scene {
        let isRunningUISmokeTest = AppUISmokeTest.startIfRequested(
            appModel: appModel,
            launchCoordinator: launchCoordinator
        )

        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(appModel.workspaceStore)
                .environmentObject(appModel.libraryStore)
                .environmentObject(appModel.knowledgeStore)
                .environmentObject(appModel.recommendationStore)
                .environmentObject(appModel.agentStore)
                .environmentObject(appModel.navigationStore)
                .environmentObject(appModel.graphStore)
                .environmentObject(launchCoordinator)
                .onAppear {
                    guard !isRunningUISmokeTest else { return }
                    launchCoordinator.start()
                }
        }
        .defaultSize(width: 1180, height: 740)
        .restorationBehavior(.disabled)
        .commands {
            SciStationCommands(
                appModel: appModel,
                libraryStore: appModel.libraryStore,
                knowledgeStore: appModel.knowledgeStore
            )
        }

        Settings {
            SettingsSceneView()
                .environmentObject(appModel)
                .environmentObject(appModel.workspaceStore)
                .environmentObject(appModel.libraryStore)
                .environmentObject(appModel.knowledgeStore)
                .environmentObject(appModel.recommendationStore)
                .environmentObject(appModel.agentStore)
                .environmentObject(appModel.navigationStore)
                .environmentObject(appModel.graphStore)
        }

        Window(appModel.t(.aiManagementTitle), id: "ai-management") {
            AIManagementPanelView(workspace: appModel.currentWorkspace)
                .environmentObject(appModel)
                .environmentObject(appModel.workspaceStore)
                .environmentObject(appModel.libraryStore)
                .environmentObject(appModel.knowledgeStore)
                .environmentObject(appModel.recommendationStore)
                .environmentObject(appModel.agentStore)
                .environmentObject(appModel.navigationStore)
                .environmentObject(appModel.graphStore)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 1120, height: 780)
        .restorationBehavior(.disabled)
    }
}
