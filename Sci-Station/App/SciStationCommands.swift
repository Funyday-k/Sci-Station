import SwiftUI

struct SciStationCommands: Commands {
    @ObservedObject var appModel: AppViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var knowledgeStore: KnowledgeStore

    var body: some Commands {
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

            Button(appModel.t(.menuOpenInReader)) {
                if let paper = appModel.selectedPaperDraft {
                    appModel.openPaperReader(paper)
                }
            }
            .disabled(appModel.selectedPaperDraft == nil || !appModel.canEnterSelectedPaperReader)

            Button(appModel.t(.menuOpenExternalPDF), action: appModel.openSelectedPaperPDF)
                .disabled(!appModel.canOpenSelectedPaperPDF)

            Button(appModel.t(.menuPreviewPDF), action: appModel.previewLibrarySelection)
                .keyboardShortcut(.space, modifiers: [])
                .disabled(appModel.selectedSection != .library || !appModel.canPreviewLibrarySelection)

            Button(appModel.t(.menuRevealPaperInFinder), action: appModel.revealSelectedPaperInFinder)
                .disabled(appModel.selectedPaperDraft == nil)

            Button(appModel.t(.menuCopyCitation), action: appModel.copySelectedPaperCitation)
                .disabled(appModel.selectedPaperDraft == nil && libraryStore.selectedPaperIDs.isEmpty)

            Button(appModel.t(.menuCopyBibTeX), action: appModel.copySelectedPaperBibTeX)
                .disabled(appModel.selectedPaperDraft == nil && libraryStore.selectedPaperIDs.isEmpty)

            Button(appModel.t(.menuExportBibTeX), action: appModel.exportSelectedPaperBibTeX)
                .disabled(appModel.selectedPaperDraft == nil && libraryStore.selectedPaperIDs.isEmpty)

            Divider()

            Button(appModel.t(.menuDeleteSelectedPaper)) {
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
                .disabled(
                    appModel.selectedSection != .wiki
                        || appModel.currentWorkspace == nil
                        || knowledgeStore.selectedDraft == nil
                )
        }
    }
}
