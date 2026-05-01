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
                .onOpenURL { url in
                    appModel.handleIncomingURL(url)
                }
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandMenu("Workspace") {
                Button("Create Workspace", action: appModel.createWorkspace)
                Button("New Project", action: appModel.beginCreatingResearchProject)
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(appModel.currentWorkspace == nil)
                Button("Open Workspace", action: appModel.openWorkspace)
                    .keyboardShortcut("o", modifiers: [.command])

                if appModel.currentWorkspace != nil {
                    Divider()
                    Button("Reveal Workspace in Finder", action: appModel.revealCurrentWorkspaceInFinder)
                    Button("Workspace Settings") {
                        appModel.selectSection(.settings)
                    }
                }
            }

            CommandMenu("Paper") {
                Button("Import PDF", action: appModel.importPDF)
                    .disabled(appModel.currentWorkspace == nil)

                Button("Add by Identifier") {
                    appModel.beginIdentifierImport()
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

            CommandMenu("View") {
                Button("Search") {
                    appModel.focusSearchForCurrentSection()
                }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(appModel.currentWorkspace == nil)

                Button("Find Next") {
                    appModel.requestPDFReaderFindNext()
                }
                .keyboardShortcut("g", modifiers: [.command])
                .disabled(appModel.selectedSection != .pdfReader)

                Button("Find Previous") {
                    appModel.requestPDFReaderFindPrevious()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(appModel.selectedSection != .pdfReader)

                Divider()

                Button("Show Inspector", action: appModel.focusInspector)
                    .keyboardShortcut("i", modifiers: [.command])
                    .disabled(appModel.currentWorkspace == nil)
            }

            CommandMenu("Wiki") {
                Button("Save Wiki Page", action: appModel.saveSelectedMarkdownChanges)
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
