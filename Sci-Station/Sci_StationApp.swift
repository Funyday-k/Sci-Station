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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandMenu("Workspace") {
                Button("Create Workspace", action: appModel.createWorkspace)
                Button("Open Workspace", action: appModel.openWorkspace)

                if appModel.currentWorkspace != nil {
                    Divider()
                    Button("Reveal Workspace in Finder", action: appModel.revealCurrentWorkspaceInFinder)
                    Button("Workspace Settings") {
                        appModel.selectSection(.settings)
                    }
                }
            }

            CommandMenu("Paper") {
                Button("Delete Selected Paper") {
                    appModel.requestDeleteSelectedPaper()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(appModel.selectedPaperDraft == nil)
            }
        }
    }
}
