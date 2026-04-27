//
//  ContentView.swift
//  Sci-Station
//
//  Created by Funyday on 2026/4/27.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedSection: $appModel.selectedSection,
                workspace: appModel.currentWorkspace
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } content: {
            WorkspaceContentView(
                workspace: appModel.currentWorkspace,
                selectedSection: appModel.selectedSection,
                isWorking: appModel.isWorking,
                createWorkspace: appModel.createWorkspace,
                openWorkspace: appModel.openWorkspace
            )
        } detail: {
            WorkspaceInspectorView(
                workspace: appModel.currentWorkspace,
                selectedSection: appModel.selectedSection,
                revealInFinder: appModel.revealCurrentWorkspaceInFinder
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Create Workspace", action: appModel.createWorkspace)
                Button("Open Workspace", action: appModel.openWorkspace)

                if appModel.currentWorkspace != nil {
                    Button("Import PDF", action: appModel.importPDF)
                    Button("Open PDF", action: appModel.openSelectedPaperPDF)
                        .disabled(!appModel.canOpenSelectedPaperPDF)
                    Button("Reveal in Finder", action: appModel.revealCurrentWorkspaceInFinder)
                }
            }
        }
        .alert(
            "Workspace Error",
            isPresented: $appModel.isShowingError,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(appModel.errorMessage ?? "An unknown error occurred.")
            }
        )
        .task {
            await appModel.restoreLastWorkspaceIfNeeded()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppViewModel())
    }
}
