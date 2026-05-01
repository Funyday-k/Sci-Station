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
    @State private var isInspectorCollapsed = false

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
                    if isInspectorCollapsed {
                        CollapsedInspectorRestoreButton {
                            isInspectorCollapsed = false
                        }
                        .navigationSplitViewColumnWidth(min: 44, ideal: 48, max: 52)
                    } else {
                        VStack(spacing: 0) {
                            HStack {
                                Spacer(minLength: 0)
                                Button {
                                    isInspectorCollapsed = true
                                } label: {
                                    Label("Collapse Inspector", systemImage: "sidebar.right")
                                        .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.borderless)
                                .help("Collapse Inspector")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                            Divider()

                            WorkspaceInspectorView(
                                workspace: appModel.currentWorkspace,
                                selectedSection: appModel.selectedSection,
                                revealInFinder: appModel.revealCurrentWorkspaceInFinder
                            )
                        }
                        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
                    }
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

private struct CollapsedInspectorRestoreButton: View {
    let action: () -> Void

    var body: some View {
        VStack {
            Button(action: action) {
                Label("Show Inspector", systemImage: "sidebar.right")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Show Inspector")
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppViewModel())
    }
}
