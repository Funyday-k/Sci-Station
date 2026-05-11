//
//  ContentView.swift
//  Sci-Station
//
//  Created by Funyday on 2026/4/27.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @AppStorage("sciStation.shellRightRailWidth") private var shellRightRailWidth = 360.0
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

                        resizableRightRail
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
                    resizableRightRail
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
                if isPrimaryToolbarAction(.workspaceMenu) {
                    Menu {
                        Button(appModel.t(.toolbarCreateWorkspace), action: appModel.createWorkspace)
                        Button(appModel.t(.toolbarOpenWorkspace), action: appModel.openWorkspace)

                        if appModel.currentWorkspace != nil {
                            Divider()
                            Button(appModel.t(.toolbarRevealInFinder), action: appModel.revealCurrentWorkspaceInFinder)
                            Button(appModel.t(.toolbarSettings)) {
                                appModel.selectSection(.settings)
                            }
                        }
                    } label: {
                        Label(toolbarTitle(.workspaceMenu), systemImage: "folder")
                    }
                }

                if isPrimaryToolbarAction(.aiPanel), appModel.currentWorkspace != nil {
                    Button {
                        appModel.openGlobalAIPanel(source: "toolbar")
                    } label: {
                            Label(toolbarTitle(.aiPanel), systemImage: "sparkles")
                    }
                        .help(appModel.t(.toolbarOpenAI))
                }

                if isPrimaryToolbarAction(.inspector), appModel.currentWorkspace != nil {
                    Button {
                        appModel.showContextInspector(source: "toolbar")
                    } label: {
                            Label(toolbarTitle(.inspector), systemImage: "sidebar.right")
                    }
                        .help(appModel.t(.toolbarShowInspector))
                }

                if isPrimaryToolbarAction(.refresh), appModel.currentWorkspace != nil {
                    Button {
                        appModel.refreshCurrentWorkspaceView()
                    } label: {
                            Label(toolbarTitle(.refresh), systemImage: "arrow.clockwise")
                    }
                        .help(toolbarTitle(.refresh))
                }

                if isPrimaryToolbarAction(.newProject), appModel.currentWorkspace != nil {
                    Button {
                        appModel.beginCreatingResearchProject()
                    } label: {
                            Label(toolbarTitle(.newProject), systemImage: "plus")
                    }
                }

                if isPrimaryToolbarAction(.allTodos), appModel.currentWorkspace != nil {
                    Button {
                        appModel.selectGlobalTodos()
                    } label: {
                            Label(toolbarTitle(.allTodos), systemImage: "checklist")
                    }
                }

                if isPrimaryToolbarAction(.addByIdentifier), appModel.currentWorkspace != nil {
                        Button(toolbarTitle(.addByIdentifier)) {
                        appModel.beginIdentifierImport()
                    }
                }

                if isPrimaryToolbarAction(.importPDF), appModel.currentWorkspace != nil {
                        Button(toolbarTitle(.importPDF), action: appModel.importPDF)
                }

                if isPrimaryToolbarAction(.pdfSearch), appModel.currentWorkspace != nil {
                    Button {
                        appModel.focusSearchForCurrentSection()
                    } label: {
                            Label(toolbarTitle(.pdfSearch), systemImage: "magnifyingglass")
                    }
                }

                if isPrimaryToolbarAction(.pdfFindPrevious), appModel.currentWorkspace != nil {
                    Button {
                        appModel.requestPDFReaderFindPrevious()
                    } label: {
                            Label(toolbarTitle(.pdfFindPrevious), systemImage: "chevron.up")
                    }
                }

                if isPrimaryToolbarAction(.pdfFindNext), appModel.currentWorkspace != nil {
                    Button {
                        appModel.requestPDFReaderFindNext()
                    } label: {
                            Label(toolbarTitle(.pdfFindNext), systemImage: "chevron.down")
                    }
                }

                if isPrimaryToolbarAction(.pdfAnnotationPlaceholder), appModel.currentWorkspace != nil {
                    Button {
                        appModel.showContextInspector(source: "pdf_annotation_toolbar")
                    } label: {
                            Label(toolbarTitle(.pdfAnnotationPlaceholder), systemImage: "highlighter")
                    }
                }

                if isPrimaryToolbarAction(.wikiNewPage), appModel.currentWorkspace != nil {
                    Button {
                        appModel.createMarkdownPage(named: "untitled-\(Int(Date().timeIntervalSince1970))")
                    } label: {
                            Label(toolbarTitle(.wikiNewPage), systemImage: "doc.badge.plus")
                    }
                }

                if isPrimaryToolbarAction(.wikiSave), appModel.currentWorkspace != nil {
                    Button {
                        appModel.saveSelectedMarkdownChanges()
                    } label: {
                            Label(toolbarTitle(.wikiSave), systemImage: "square.and.arrow.down")
                    }
                    .disabled(!appModel.canSaveSelectedMarkdown)
                }

                if isPrimaryToolbarAction(.wikiPreviewMode), appModel.currentWorkspace != nil {
                    Button {} label: {
                            Label(toolbarTitle(.wikiPreviewMode), systemImage: "eye")
                    }
                    .disabled(true)
                }

                if !appModel.toolbarModel.overflowActions.isEmpty, appModel.currentWorkspace != nil {
                    Menu {
                        ForEach(appModel.toolbarModel.overflowActions) { action in
                            Button {
                                performToolbarAction(action.id)
                            } label: {
                                Label(action.title, systemImage: toolbarSystemImage(action.id))
                            }
                            .disabled(action.id == .wikiPreviewMode || (action.id == .wikiSave && !appModel.canSaveSelectedMarkdown))
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help(appModel.t(.menuView))
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
            appModel.t(.appErrorTitle),
            isPresented: $appModel.isShowingError,
            actions: {
                Button(appModel.t(.appOK), role: .cancel) {}
            },
            message: {
                Text(appModel.errorMessage ?? appModel.t(.appUnknownError))
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

    private var resizableRightRail: some View {
        ResizableRightRailColumn(
            width: $shellRightRailWidth,
            minWidth: rightRailColumnWidth.min,
            idealWidth: rightRailColumnWidth.ideal,
            maxWidth: rightRailColumnWidth.max,
            isResizable: appModel.effectiveRightRailMode != .hidden
        ) {
            ShellRightRailView(workspace: appModel.currentWorkspace)
        }
    }

    private var rightRailColumnWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        switch appModel.effectiveRightRailMode {
        case .hidden:
            return (44, 48, 52)
        case .inspector:
            let ideal = min(max(CGFloat(shellRightRailWidth), 300), 640)
            return (280, ideal, 640)
        case .ai:
            let ideal = min(max(CGFloat(shellRightRailWidth), 340), 680)
            return (320, ideal, 680)
        }
    }

    private func isPrimaryToolbarAction(_ id: ToolbarActionID) -> Bool {
        appModel.toolbarModel.globalActions.contains(where: { $0.id == id })
            || appModel.toolbarModel.pageActions.contains(where: { $0.id == id })
    }

    private func toolbarTitle(_ id: ToolbarActionID) -> String {
        appModel.toolbarModel.action(id)?.title ?? id.rawValue
    }

    private func toolbarSystemImage(_ id: ToolbarActionID) -> String {
        switch id {
        case .workspaceMenu:
            return "folder"
        case .aiPanel:
            return "sparkles"
        case .inspector:
            return "sidebar.right"
        case .refresh:
            return "arrow.clockwise"
        case .newProject:
            return "plus"
        case .allTodos:
            return "checklist"
        case .addByIdentifier:
            return "number"
        case .importPDF:
            return "doc.badge.plus"
        case .pdfSearch:
            return "magnifyingglass"
        case .pdfFindPrevious:
            return "chevron.up"
        case .pdfFindNext:
            return "chevron.down"
        case .pdfAnnotationPlaceholder:
            return "highlighter"
        case .wikiNewPage:
            return "doc.badge.plus"
        case .wikiSave:
            return "square.and.arrow.down"
        case .wikiPreviewMode:
            return "eye"
        }
    }

    private func performToolbarAction(_ id: ToolbarActionID) {
        switch id {
        case .workspaceMenu:
            break
        case .aiPanel:
            appModel.openGlobalAIPanel(source: "toolbar_overflow")
        case .inspector:
            appModel.showContextInspector(source: "toolbar_overflow")
        case .refresh:
            appModel.refreshCurrentWorkspaceView()
        case .newProject:
            appModel.beginCreatingResearchProject()
        case .allTodos:
            appModel.selectGlobalTodos()
        case .addByIdentifier:
            appModel.beginIdentifierImport()
        case .importPDF:
            appModel.importPDF()
        case .pdfSearch:
            appModel.focusSearchForCurrentSection()
        case .pdfFindPrevious:
            appModel.requestPDFReaderFindPrevious()
        case .pdfFindNext:
            appModel.requestPDFReaderFindNext()
        case .pdfAnnotationPlaceholder:
            appModel.showContextInspector(source: "pdf_annotation_toolbar_overflow")
        case .wikiNewPage:
            appModel.createMarkdownPage(named: "untitled-\(Int(Date().timeIntervalSince1970))")
        case .wikiSave:
            appModel.saveSelectedMarkdownChanges()
        case .wikiPreviewMode:
            break
        }
    }
}

private struct ResizableRightRailColumn<Content: View>: View {
    @Binding var width: Double
    let minWidth: CGFloat
    let idealWidth: CGFloat
    let maxWidth: CGFloat
    let isResizable: Bool
    let content: Content

    @State private var dragStartWidth: Double?

    init(
        width: Binding<Double>,
        minWidth: CGFloat,
        idealWidth: CGFloat,
        maxWidth: CGFloat,
        isResizable: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self._width = width
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.isResizable = isResizable
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            if isResizable {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 6)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragStartWidth == nil {
                                    dragStartWidth = clampedWidth
                                }
                                let proposed = (dragStartWidth ?? clampedWidth) - value.translation.width
                                width = min(max(proposed, Double(minWidth)), Double(maxWidth))
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            }

            content
                .frame(width: CGFloat(clampedWidth))
        }
        .frame(width: CGFloat(clampedWidth) + (isResizable ? 6 : 0))
        .onAppear(perform: clampStoredWidth)
        .onChange(of: isResizable) { _, _ in clampStoredWidth() }
        .onChange(of: idealWidth) { _, _ in clampStoredWidth() }
    }

    private var clampedWidth: Double {
        if !isResizable {
            return Double(idealWidth)
        }
        return min(max(width, Double(minWidth)), Double(maxWidth))
    }

    private func clampStoredWidth() {
        guard isResizable else { return }
        width = clampedWidth
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppViewModel())
    }
}
