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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(launchCoordinator)
                .onAppear(perform: launchCoordinator.start)
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandMenu(appModel.t(.toolbarWorkspace)) {
                Button(appModel.t(.toolbarCreateWorkspace), action: appModel.createWorkspace)
                Button(appModel.t(.toolbarNewProject), action: appModel.beginCreatingResearchProject)
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(appModel.currentWorkspace == nil)
                Button(appModel.t(.toolbarOpenWorkspace), action: appModel.openWorkspace)
                    .keyboardShortcut("o", modifiers: [.command])

                if appModel.currentWorkspace != nil {
                    Divider()
                    Button(appModel.t(.toolbarRevealInFinder), action: appModel.revealCurrentWorkspaceInFinder)
                    Button(appModel.t(.toolbarSettings)) {
                        appModel.selectSection(.settings)
                    }
                }
            }

            CommandMenu(appModel.t(.routePapers)) {
                Button(appModel.t(.toolbarImportPDF), action: appModel.importPDFFromGlobalMenu)
                    .disabled(appModel.currentWorkspace == nil)

                Button(appModel.t(.toolbarAddByIdentifier)) {
                    appModel.beginIdentifierImportFromGlobalMenu()
                }
                    .disabled(appModel.currentWorkspace == nil)

                Divider()

                Button("Open in Reader") {
                    if let paper = appModel.selectedPaperDraft {
                        appModel.openPaperReader(paper)
                    }
                }
                .disabled(appModel.selectedPaperDraft == nil || !appModel.canEnterSelectedPaperReader)

                Button("Open External PDF", action: appModel.openSelectedPaperPDF)
                    .disabled(!appModel.canOpenSelectedPaperPDF)

                Button("Preview PDF", action: appModel.previewLibrarySelection)
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(appModel.selectedSection != .library || !appModel.canPreviewLibrarySelection)

                Button("Reveal Paper in Finder", action: appModel.revealSelectedPaperInFinder)
                    .disabled(appModel.selectedPaperDraft == nil)

                Button("Copy Citation", action: appModel.copySelectedPaperCitation)
                    .disabled(appModel.selectedPaperDraft == nil && appModel.selectedLibraryPaperCount == 0)

                Button("Copy BibTeX", action: appModel.copySelectedPaperBibTeX)
                    .disabled(appModel.selectedPaperDraft == nil && appModel.selectedLibraryPaperCount == 0)

                Button("Export BibTeX", action: appModel.exportSelectedPaperBibTeX)
                    .disabled(appModel.selectedPaperDraft == nil && appModel.selectedLibraryPaperCount == 0)

                Divider()

                Button("Delete Selected Paper") {
                    appModel.requestDeleteSelectedPaper()
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(appModel.selectedPaperDraft == nil)
            }

            CommandMenu(appModel.t(.menuView)) {
                Button(appModel.t(.toolbarSearch)) {
                    appModel.focusSearchForCurrentSection()
                }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(appModel.currentWorkspace == nil)

                Button(appModel.t(.toolbarNext)) {
                    appModel.requestPDFReaderFindNext()
                }
                .keyboardShortcut("g", modifiers: [.command])
                .disabled(appModel.selectedSection != .pdfReader)

                Button(appModel.t(.toolbarPrevious)) {
                    appModel.requestPDFReaderFindPrevious()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(appModel.selectedSection != .pdfReader)

                Divider()

                Button(appModel.t(.toolbarShowInspector), action: appModel.focusInspector)
                    .keyboardShortcut("i", modifiers: [.command])
                    .disabled(appModel.currentWorkspace == nil)
            }

            CommandMenu(appModel.t(.routeWiki)) {
                Button(appModel.t(.toolbarSave), action: appModel.saveSelectedMarkdownChanges)
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(appModel.selectedSection != .wiki || !appModel.canSaveSelectedMarkdown)
            }
        }

        Settings {
            SettingsSceneView()
                .environmentObject(appModel)
        }
    }
}
