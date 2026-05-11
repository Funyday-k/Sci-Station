import SwiftUI

struct MarkdownPageListView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var activeOperation: MarkdownFileOperation?
    @State private var operationText = ""
    @State private var isShowingArchiveConfirmation = false

    var body: some View {
        VStack(spacing: 8) {
            fileToolbar

            List(selection: selectionBinding) {
                if appModel.markdownDocuments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No wiki pages yet.")
                            .foregroundStyle(.secondary)
                        Button("Open Project Overview", action: appModel.openCurrentProjectOverviewPage)
                        Button("Open Wiki Folder", action: appModel.openWikiFolder)
                    }
                } else {
                    ForEach(appModel.markdownDocuments) { document in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(document.title)
                                .lineLimit(1)
                            Text(document.relativePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(Optional(document.id))
                        .contextMenu {
                            Button("Rename") { beginOperation(.rename, defaultText: documentFileName(document)) }
                            Button("Move") { beginOperation(.move, defaultText: defaultMoveFolder(document)) }
                            Divider()
                            Button("Archive", role: .destructive) {
                                appModel.selectMarkdownDocument(id: document.id)
                                isShowingArchiveConfirmation = true
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .sheet(item: $activeOperation) { operation in
            MarkdownFileOperationDialog(
                operation: operation,
                text: $operationText,
                cancel: { activeOperation = nil },
                submit: submitOperation
            )
        }
        .confirmationDialog("Archive selected page?", isPresented: $isShowingArchiveConfirmation) {
            Button("Archive", role: .destructive) {
                appModel.archiveSelectedMarkdownDocument()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file will be moved to .sci-station/trash/wiki/ inside the workspace.")
        }
    }

    private var fileToolbar: some View {
        HStack(spacing: 6) {
            Button { beginOperation(.newPage, defaultText: "") } label: {
                toolbarIcon("doc.badge.plus", title: "New Page")
            }
            .help("New Page")

            Button { beginOperation(.newFolder, defaultText: "") } label: {
                toolbarIcon("folder.badge.plus", title: "New Folder")
            }
            .help("New Folder")

            Divider()
                .frame(height: 18)

            Button { beginOperation(.rename, defaultText: selectedDocument.map(documentFileName) ?? "") } label: {
                toolbarIcon("square.and.pencil", title: "Rename")
            }
            .disabled(selectedDocument == nil)
            .help("Rename")

            Button { beginOperation(.move, defaultText: selectedDocument.map(defaultMoveFolder) ?? "") } label: {
                toolbarIcon("arrowshape.turn.up.right", title: "Move")
            }
            .disabled(selectedDocument == nil)
            .help("Move")

            Button { isShowingArchiveConfirmation = true } label: {
                toolbarIcon("trash", title: "Archive")
            }
            .disabled(selectedDocument == nil)
            .help("Archive")

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .controlSize(.regular)
    }

    private func toolbarIcon(_ systemImage: String, title: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 30, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel(title)
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { appModel.selectedMarkdownID },
            set: { appModel.selectMarkdownDocument(id: $0) }
        )
    }

    private var selectedDocument: MarkdownDocument? {
        guard let selectedID = appModel.selectedMarkdownID else { return nil }
        return appModel.markdownDocuments.first { $0.id == selectedID }
    }

    private func beginOperation(_ operation: MarkdownFileOperation, defaultText: String) {
        operationText = defaultText
        activeOperation = operation
    }

    private func submitOperation() {
        let text = operationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let operation = activeOperation else { return }
        activeOperation = nil

        switch operation {
        case .newPage:
            appModel.createMarkdownPage(named: text)
        case .newFolder:
            appModel.createMarkdownFolder(named: text)
        case .rename:
            appModel.renameSelectedMarkdownDocument(to: text)
        case .move:
            appModel.moveSelectedMarkdownDocument(toFolder: text)
        }
    }

    private func documentFileName(_ document: MarkdownDocument) -> String {
        (document.relativePath as NSString).lastPathComponent
    }

    private func defaultMoveFolder(_ document: MarkdownDocument) -> String {
        let folder = (document.relativePath as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "\\", with: "/")
        return folder == "." ? "" : folder
    }
}

private enum MarkdownFileOperation: String, Identifiable {
    case newPage
    case newFolder
    case rename
    case move

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newPage: return "New Page"
        case .newFolder: return "New Folder"
        case .rename: return "Rename Page"
        case .move: return "Move Page"
        }
    }

    var prompt: String {
        switch self {
        case .newPage: return "Page name or path"
        case .newFolder: return "Folder name or path"
        case .rename: return "New file name"
        case .move: return "Destination folder"
        }
    }
}

private struct MarkdownFileOperationDialog: View {
    let operation: MarkdownFileOperation
    @Binding var text: String
    let cancel: () -> Void
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(operation.title)
                .font(.headline)
            TextField(operation.prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                Button("Apply", action: submit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
    }
}