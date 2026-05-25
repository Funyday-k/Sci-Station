import Foundation

@MainActor
struct AppToolbarCommandDispatcher {
    private struct Handler: @unchecked Sendable {
        let perform: @MainActor (Source) -> Void
    }

    enum Source: Sendable {
        case primary
        case overflow

        var rightRailSource: String {
            switch self {
            case .primary:
                return "toolbar"
            case .overflow:
                return "toolbar_overflow"
            }
        }

        var pdfAnnotationSource: String {
            switch self {
            case .primary:
                return "pdf_annotation_toolbar"
            case .overflow:
                return "pdf_annotation_toolbar_overflow"
            }
        }

        var commandParameter: String {
            switch self {
            case .primary:
                return "primary"
            case .overflow:
                return "overflow"
            }
        }
    }

    let appModel: AppViewModel
    let effectiveRightRailMode: RightRailMode

    private var handlersByCommandID: [String: Handler] {
        [
            commandID(.aiPanel): Handler { source in
                appModel.toggleRightRailMode(.ai, source: source.rightRailSource)
            },
            commandID(.inspector): Handler { source in
                appModel.toggleRightRailMode(.inspector, source: source.rightRailSource)
            },
            commandID(.refresh): Handler { _ in
                appModel.refreshCurrentWorkspaceView()
            },
            commandID(.newProject): Handler { _ in
                appModel.beginCreatingResearchProject()
            },
            commandID(.allTodos): Handler { _ in
                appModel.selectGlobalTodos()
            },
            commandID(.addByIdentifier): Handler { _ in
                appModel.beginIdentifierImport()
            },
            commandID(.importPDF): Handler { _ in
                appModel.importPDF()
            },
            commandID(.pdfSearch): Handler { _ in
                appModel.focusSearchForCurrentSection()
            },
            commandID(.pdfFindPrevious): Handler { _ in
                appModel.requestPDFReaderFindPrevious()
            },
            commandID(.pdfFindNext): Handler { _ in
                appModel.requestPDFReaderFindNext()
            },
            commandID(.pdfAnnotationPlaceholder): Handler { source in
                appModel.showContextInspector(source: source.pdfAnnotationSource)
            },
            commandID(.wikiNewPage): Handler { _ in
                appModel.createMarkdownPage(named: "untitled-\(Int(Date().timeIntervalSince1970))")
            },
            commandID(.wikiSave): Handler { _ in
                appModel.saveSelectedMarkdownChanges()
            }
        ]
    }

    func perform(_ actionID: ToolbarActionID, source: Source) {
        perform(ToolbarCommandCatalog.commandID(for: actionID), source: source)
    }

    func perform(_ commandID: String, source: Source) {
        guard handlersByCommandID[commandID] != nil else {
            return
        }
        Task { @MainActor in
            await execute(commandID, source: source)
        }
    }

    func isDisabled(_ actionID: ToolbarActionID) -> Bool {
        switch actionID {
        case .wikiPreviewMode:
            return true
        case .wikiSave:
            return !appModel.canSaveSelectedMarkdown
        default:
            return false
        }
    }

    func systemImage(for action: ToolbarAction) -> String {
        if action.id == .inspector, effectiveRightRailMode == .inspector {
            return "sidebar.trailing"
        }
        return action.systemImage
    }

    func help(for actionID: ToolbarActionID, fallbackTitle: String) -> String {
        switch actionID {
        case .aiPanel:
            return effectiveRightRailMode == .ai
                ? appModel.localized("收起 AI", "Hide AI")
                : appModel.t(.toolbarOpenAI)
        case .inspector:
            return effectiveRightRailMode == .inspector
                ? appModel.localized("收起检查器", "Hide inspector")
                : appModel.t(.toolbarShowInspector)
        case .refresh:
            return fallbackTitle
        default:
            return fallbackTitle
        }
    }

    private func commandID(_ actionID: ToolbarActionID) -> String {
        ToolbarCommandCatalog.commandID(for: actionID)
    }

    private func execute(_ commandID: String, source: Source) async {
        let registry = CommandRegistry()
        for (registeredCommandID, handler) in handlersByCommandID {
            let contribution = CommandContribution(
                id: registeredCommandID,
                title: registeredCommandID,
                placement: .toolbar
            )
            try? await registry.register(contribution, pluginID: "sci.app.toolbar") { _ in
                await MainActor.run {
                    handler.perform(source)
                }
                return CommandExecutionResult()
            }
        }
        _ = try? await registry.execute(
            id: commandID,
            services: appModel.hostServices,
            parameters: ["source": .string(source.commandParameter)]
        )
    }
}
