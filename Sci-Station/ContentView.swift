//
//  ContentView.swift
//  Sci-Station
//
//  Created by Funyday on 2026/4/27.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var mainColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var readerColumnVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        Group {
            if appModel.selectedSection == .pdfReader, appModel.currentWorkspace != nil {
                NavigationSplitView(columnVisibility: $readerColumnVisibility) {
                    SidebarView(workspace: appModel.currentWorkspace)
                        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
                } detail: {
                    HStack(spacing: 0) {
                        PDFReaderWorkspaceView(workspace: appModel.currentWorkspace)

                        Divider()

                        ShellRightRailView(workspace: appModel.currentWorkspace)
                            .frame(width: rightRailColumnWidth.ideal)
                    }
                }
            } else {
                NavigationSplitView(columnVisibility: $mainColumnVisibility) {
                    SidebarView(workspace: appModel.currentWorkspace)
                        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
                } content: {
                    WorkspaceContentView(
                        workspace: appModel.currentWorkspace,
                        selectedSection: appModel.selectedSection,
                        isWorking: appModel.isWorking,
                        createWorkspace: appModel.createWorkspace,
                        openWorkspace: appModel.openWorkspace
                    )
                    .navigationSplitViewColumnWidth(min: 560, ideal: 760)
                } detail: {
                    ShellRightRailView(workspace: appModel.currentWorkspace)
                        .navigationSplitViewColumnWidth(
                            min: rightRailColumnWidth.min,
                            ideal: rightRailColumnWidth.ideal,
                            max: rightRailColumnWidth.max
                        )
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if hasToolbarAction(.workspaceMenu) {
                    Menu {
                        Button("Create Workspace", action: appModel.createWorkspace)
                        Button("Open Workspace", action: appModel.openWorkspace)

                        if appModel.currentWorkspace != nil {
                            Divider()
                            Button("Reveal in Finder", action: appModel.revealCurrentWorkspaceInFinder)
                            Button("Settings") {
                                appModel.selectSection(.settings)
                            }
                        }
                    } label: {
                        Label("Workspace", systemImage: "folder")
                    }
                }

                if hasToolbarAction(.aiPanel), appModel.currentWorkspace != nil {
                    Button {
                        appModel.openGlobalAIPanel(source: "toolbar")
                    } label: {
                        Label("AI", systemImage: "sparkles")
                    }
                    .help("Open AI")
                }

                if hasToolbarAction(.inspector), appModel.currentWorkspace != nil {
                    Button {
                        appModel.showContextInspector(source: "toolbar")
                    } label: {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                    .help("Show inspector")
                }

                if hasToolbarAction(.refresh), appModel.currentWorkspace != nil {
                    Button {
                        appModel.refreshCurrentWorkspaceView()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh")
                }

                if hasToolbarAction(.newProject), appModel.currentWorkspace != nil {
                    Button {
                        appModel.beginCreatingResearchProject()
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                }

                if hasToolbarAction(.allTodos), appModel.currentWorkspace != nil {
                    Button {
                        appModel.selectGlobalTodos()
                    } label: {
                        Label("All Todos", systemImage: "checklist")
                    }
                }

                if hasToolbarAction(.addByIdentifier), appModel.currentWorkspace != nil {
                    Button("Add by Identifier") {
                        appModel.beginIdentifierImport()
                    }
                }

                if hasToolbarAction(.importPDF), appModel.currentWorkspace != nil {
                    Button("Import PDF", action: appModel.importPDF)
                }

                if hasToolbarAction(.pdfSearch), appModel.currentWorkspace != nil {
                    Button {
                        appModel.focusSearchForCurrentSection()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }

                if hasToolbarAction(.pdfFindPrevious), appModel.currentWorkspace != nil {
                    Button {
                        appModel.requestPDFReaderFindPrevious()
                    } label: {
                        Label("Previous", systemImage: "chevron.up")
                    }
                }

                if hasToolbarAction(.pdfFindNext), appModel.currentWorkspace != nil {
                    Button {
                        appModel.requestPDFReaderFindNext()
                    } label: {
                        Label("Next", systemImage: "chevron.down")
                    }
                }

                if hasToolbarAction(.pdfAnnotationPlaceholder), appModel.currentWorkspace != nil {
                    Button {
                        appModel.showContextInspector(source: "pdf_annotation_toolbar")
                    } label: {
                        Label("Annotations", systemImage: "highlighter")
                    }
                }

                if hasToolbarAction(.wikiNewPage), appModel.currentWorkspace != nil {
                    Button {
                        appModel.createMarkdownPage(named: "untitled-\(Int(Date().timeIntervalSince1970))")
                    } label: {
                        Label("New Page", systemImage: "doc.badge.plus")
                    }
                }

                if hasToolbarAction(.wikiSave), appModel.currentWorkspace != nil {
                    Button {
                        appModel.saveSelectedMarkdownChanges()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!appModel.canSaveSelectedMarkdown)
                }

                if hasToolbarAction(.wikiPreviewMode), appModel.currentWorkspace != nil {
                    Button {} label: {
                        Label("Preview", systemImage: "eye")
                    }
                    .disabled(true)
                }
            }

            if appModel.selectedSection == .pdfReader, let paper = appModel.selectedPaperDraft {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(paper.displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(paper.authorsDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 620)
                }
            }
        }
        .alert(
            "Sci-Station Error",
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
            appModel.applyRightRailRouteSuggestion()
            appModel.recordToolbarPolicyChange(appModel.toolbarModel)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        appModel.updateShellWindowWidth(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        appModel.updateShellWindowWidth(width)
                    }
            }
        }
        .onChange(of: appModel.selectedSection) { _, selectedSection in
            if selectedSection == .pdfReader {
                readerColumnVisibility = .detailOnly
            }
            appModel.applyRightRailRouteSuggestion()
        }
        .onChange(of: appModel.selectedProjectSpaceTabID) { _, _ in
            appModel.applyRightRailRouteSuggestion()
        }
        .onChange(of: appModel.currentWorkspaceContextSnapshot) { _, _ in
            appModel.recordGlobalAIContextUpdate()
        }
        .onChange(of: appModel.toolbarModel) { _, model in
            appModel.recordToolbarPolicyChange(model)
        }
        .onChange(of: appModel.inspectorFocusRequest) { _, _ in
            mainColumnVisibility = .all
            appModel.showContextInspector(source: "command")
        }
        .sheet(isPresented: $appModel.isShowingIdentifierImport) {
            IdentifierImportView()
                .environmentObject(appModel)
        }
        .sheet(isPresented: $appModel.isShowingSummaryPreview) {
            LLMSummaryPreviewView()
                .environmentObject(appModel)
        }
        .sheet(isPresented: $appModel.isShowingBibTeXExport) {
            BibTeXExportView()
                .environmentObject(appModel)
        }
        .sheet(isPresented: $appModel.isShowingResearchProjectEditor) {
            ResearchProjectEditorView()
                .environmentObject(appModel)
        }
        .sheet(isPresented: $appModel.isShowingWorkspaceCreationWizard) {
            WorkspaceCreationWizardView()
                .environmentObject(appModel)
        }
    }

    private var rightRailColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        switch appModel.effectiveRightRailMode {
        case .hidden:
            return (44, 48, 52)
        case .inspector:
            return (260, 310, 380)
        case .ai:
            return (340, 400, 480)
        }
    }

    private func hasToolbarAction(_ id: ToolbarActionID) -> Bool {
        appModel.toolbarModel.contains(id)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppViewModel())
    }
}
