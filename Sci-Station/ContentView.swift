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
    @EnvironmentObject private var launchCoordinator: SciStationLaunchCoordinator
    @AppStorage("sciStation.shellRightRailWidth") private var shellRightRailWidth = 360.0
    @State private var mainColumnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var readerColumnVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        let shellState = appModel.shellRenderState
        GeometryReader { proxy in
            Group {
                if shellState.selectedSection == .pdfReader, shellState.currentWorkspace != nil {
                    NavigationSplitView(columnVisibility: $readerColumnVisibility) {
                        SidebarView(workspace: shellState.currentWorkspace)
                            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
                    } detail: {
                        HStack(spacing: 0) {
                            PDFReaderWorkspaceView(workspace: shellState.currentWorkspace)

                            if shouldShowRightRail(shellState) {
                                Divider()
                                resizableRightRail(shellState)
                            }
                        }
                    }
                } else if !shouldShowRightRail(shellState) {
                    NavigationSplitView(columnVisibility: $mainColumnVisibility) {
                        SidebarView(workspace: shellState.currentWorkspace)
                            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
                    } detail: {
                        workspaceContent(shellState)
                    }
                } else {
                    NavigationSplitView(columnVisibility: $mainColumnVisibility) {
                        SidebarView(workspace: shellState.currentWorkspace)
                            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
                    } content: {
                        workspaceContent(shellState)
                    } detail: {
                        resizableRightRail(shellState)
                        .navigationSplitViewColumnWidth(
                            min: rightRailColumnWidth(shellState).min,
                            ideal: rightRailColumnWidth(shellState).ideal,
                            max: rightRailColumnWidth(shellState).max
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(minWidth: 700, minHeight: 480)
        .background(alignment: .topLeading) {
            SciStationMainWindowGate(isLaunching: launchCoordinator.isLaunching)
                .frame(width: 0, height: 0)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(shellState.toolbarModel.primaryActions) { action in
                    toolbarControl(for: action, source: .primary, shellState: shellState)
                }

                if !shellState.toolbarModel.overflowActions.isEmpty, shellState.currentWorkspace != nil {
                    Menu {
                        ForEach(shellState.toolbarModel.overflowActions) { action in
                            toolbarOverflowControl(for: action, shellState: shellState)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help(appModel.t(.menuView))
                }
            }

            if shellState.selectedSection == .pdfReader, let paperTitle = shellState.selectedPaperTitle {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(paperTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(shellState.selectedPaperAuthors ?? "")
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
            appModel.recordToolbarPolicyChange(appModel.shellRenderState.toolbarModel)
            launchCoordinator.markAppPreparationFinished()
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
        .onChange(of: shellState.selectedSection) { _, selectedSection in
            if selectedSection == .pdfReader {
                readerColumnVisibility = .detailOnly
            }
            appModel.applyRightRailRouteSuggestion()
        }
        .onChange(of: shellState.selectedProjectSpaceTabID) { _, _ in
            appModel.applyRightRailRouteSuggestion()
        }
        .onChange(of: shellState.context) { _, _ in
            appModel.recordGlobalAIContextUpdate()
        }
        .onChange(of: shellState.toolbarModel) { _, model in
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

    private func workspaceContent(_ shellState: AppShellRenderState) -> some View {
        WorkspaceContentView(
            workspace: shellState.currentWorkspace,
            selectedSection: shellState.selectedSection,
            isWorking: shellState.isWorking,
            createWorkspace: appModel.createWorkspace,
            openWorkspace: appModel.openWorkspace
        )
        .navigationSplitViewColumnWidth(min: 360, ideal: 700)
    }

    private func resizableRightRail(_ shellState: AppShellRenderState) -> some View {
        ResizableRightRailColumn(
            width: $shellRightRailWidth,
            minWidth: rightRailColumnWidth(shellState).min,
            idealWidth: rightRailColumnWidth(shellState).ideal,
            maxWidth: rightRailColumnWidth(shellState).max,
            isResizable: shouldShowRightRail(shellState),
            usesFixedWidth: shellState.selectedSection == .pdfReader
        ) {
            ShellRightRailView(
                workspace: shellState.currentWorkspace,
                mode: shellState.effectiveRightRailMode,
                context: shellState.context,
                selectedSection: shellState.selectedSection
            )
        }
    }

    private func rightRailColumnWidth(_ shellState: AppShellRenderState) -> (min: CGFloat, ideal: CGFloat, max: CGFloat) {
        switch shellState.effectiveRightRailMode {
        case .hidden:
            return (0, 0, 0)
        case .inspector:
            let ideal = min(max(CGFloat(shellRightRailWidth), 240), 560)
            return (200, ideal, 560)
        case .ai:
            let ideal = min(max(CGFloat(shellRightRailWidth), 280), 640)
            return (240, ideal, 640)
        }
    }

    private func shouldShowRightRail(_ shellState: AppShellRenderState) -> Bool {
        guard shellState.effectiveRightRailMode != .hidden else {
            return false
        }
        if shellState.selectedProjectSpaceTabID == "recommendations", shellState.shellWindowWidth < 1280 {
            return false
        }
        return true
    }

    private func toolbarDispatcher(_ shellState: AppShellRenderState) -> AppToolbarCommandDispatcher {
        AppToolbarCommandDispatcher(appModel: appModel, effectiveRightRailMode: shellState.effectiveRightRailMode)
    }

    @ViewBuilder
    private func toolbarControl(for action: ToolbarAction, source: AppToolbarCommandDispatcher.Source, shellState: AppShellRenderState) -> some View {
        if action.id == .workspaceMenu {
            workspaceToolbarMenu(title: action.title, systemImage: action.systemImage, hasWorkspace: shellState.currentWorkspace != nil)
        } else if shellState.currentWorkspace != nil {
            Button {
                toolbarDispatcher(shellState).perform(action.commandID, source: source)
            } label: {
                Label(action.title, systemImage: toolbarDispatcher(shellState).systemImage(for: action))
            }
            .disabled(toolbarDispatcher(shellState).isDisabled(action.id))
            .help(toolbarDispatcher(shellState).help(for: action.id, fallbackTitle: action.title))
        }
    }

    private func workspaceToolbarMenu(title: String, systemImage: String, hasWorkspace: Bool) -> some View {
        Menu {
            Button(appModel.t(.toolbarCreateWorkspace), action: appModel.createWorkspace)
            Button(appModel.t(.toolbarOpenWorkspace), action: appModel.openWorkspace)

            if hasWorkspace {
                Divider()
                Button(appModel.t(.toolbarRevealInFinder), action: appModel.revealCurrentWorkspaceInFinder)
                Button(appModel.t(.toolbarSettings)) {
                    appModel.selectSection(.settings)
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func toolbarOverflowControl(for action: ToolbarAction, shellState: AppShellRenderState) -> some View {
        Button {
            toolbarDispatcher(shellState).perform(action.commandID, source: .overflow)
        } label: {
            Label(action.title, systemImage: toolbarDispatcher(shellState).systemImage(for: action))
        }
        .disabled(toolbarDispatcher(shellState).isDisabled(action.id))
    }
}

private struct ResizableRightRailColumn<Content: View>: View {
    @Binding var width: Double
    let minWidth: CGFloat
    let idealWidth: CGFloat
    let maxWidth: CGFloat
    let isResizable: Bool
    let usesFixedWidth: Bool
    let content: Content

    @State private var dragStartWidth: Double?
    private let handleWidth: CGFloat = 8

    init(
        width: Binding<Double>,
        minWidth: CGFloat,
        idealWidth: CGFloat,
        maxWidth: CGFloat,
        isResizable: Bool,
        usesFixedWidth: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self._width = width
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.isResizable = isResizable
        self.usesFixedWidth = usesFixedWidth
        self.content = content()
    }

    var body: some View {
        Group {
            if usesFixedWidth {
                fixedWidthBody
            } else {
                flexibleWidthBody
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.18), value: isResizable)
        .onAppear(perform: clampStoredWidth)
        .onChange(of: isResizable) { _, _ in clampStoredWidth() }
        .onChange(of: idealWidth) { _, _ in clampStoredWidth() }
    }

    private var fixedWidthBody: some View {
        HStack(spacing: 0) {
            if isResizable {
                resizeHandle
            }

            content
                .frame(width: CGFloat(clampedWidth))
        }
        .frame(width: CGFloat(clampedWidth) + (isResizable ? handleWidth : 0))
    }

    private var flexibleWidthBody: some View {
        HStack(spacing: 0) {
            if isResizable {
                resizeHandle
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: minWidth + (isResizable ? handleWidth : 0),
               idealWidth: idealWidth + (isResizable ? handleWidth : 0),
               maxWidth: maxWidth + (isResizable ? handleWidth : 0),
               maxHeight: .infinity)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: handleWidth)
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
            .environmentObject(SciStationLaunchCoordinator())
    }
}
