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
                    PDFReaderWorkspaceView(workspace: appModel.currentWorkspace)
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
                    WorkspaceInspectorView(
                        workspace: appModel.currentWorkspace,
                        selectedSection: appModel.selectedSection,
                        revealInFinder: appModel.revealCurrentWorkspaceInFinder
                    )
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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

                if appModel.currentWorkspace != nil, appModel.selectedSection != .pdfReader {
                    Button {
                        appModel.selectGlobalTodos()
                    } label: {
                        Label("All Todos", systemImage: "checklist")
                    }
                    Button("Add by Identifier") {
                        appModel.beginIdentifierImport()
                    }
                    Button("Import PDF", action: appModel.importPDF)
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
        }
        .onChange(of: appModel.selectedSection) { _, selectedSection in
            if selectedSection == .pdfReader {
                readerColumnVisibility = .detailOnly
            }
        }
        .onChange(of: appModel.inspectorFocusRequest) { _, _ in
            mainColumnVisibility = .all
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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppViewModel())
    }
}
