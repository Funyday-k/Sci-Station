import SwiftUI

struct MarkdownEditorView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @AppStorage("wiki.markdownEditorMode") private var editorModeRawValue = MarkdownEditorMode.source.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let document = appModel.selectedMarkdownDraft {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                        Text(document.relativePath)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Picker("Mode", selection: editorModeBinding) {
                        ForEach(MarkdownEditorMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)

                    Menu {
                        ForEach(appModel.markdownSnippets) { snippet in
                            Button("\(snippet.trigger)  \(snippet.title)") {
                                appModel.insertMarkdownSnippet(snippet)
                            }
                        }

                        Divider()

                        Button("Open Snippets File") {
                            appModel.openMarkdownSnippetsFile()
                        }
                    } label: {
                        Label("Snippets", systemImage: "text.badge.plus")
                    }
                    .menuStyle(.button)

                    if appModel.isSavingSelectedMarkdown {
                        ProgressView("Saving…")
                    }

                    Button("Save", action: appModel.saveSelectedMarkdownChanges)
                        .buttonStyle(.borderedProminent)
                        .disabled(!appModel.canSaveSelectedMarkdown)
                }

                editorSurface(for: document)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wiki")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Select a Markdown page to inspect frontmatter, edit content, and save it back to the workspace.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
    }

    private var editorMode: MarkdownEditorMode {
        MarkdownEditorMode(rawValue: editorModeRawValue) ?? .source
    }

    private var editorModeBinding: Binding<MarkdownEditorMode> {
        Binding(
            get: { editorMode },
            set: { editorModeRawValue = $0.rawValue }
        )
    }

    @ViewBuilder
    private func editorSurface(for document: MarkdownDocument) -> some View {
        Group {
            switch editorMode {
            case .source:
                sourceEditor
            case .preview:
                MarkdownPreviewView(markdown: document.rawContents, baseURL: document.fileURL.deletingLastPathComponent())
            case .split:
                HStack(spacing: 0) {
                    sourceEditor
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    MarkdownPreviewView(markdown: document.rawContents, baseURL: document.fileURL.deletingLastPathComponent())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu {
            Button("Source Only") { editorModeRawValue = MarkdownEditorMode.source.rawValue }
            Button("Preview Only") { editorModeRawValue = MarkdownEditorMode.preview.rawValue }
            Button("Split Source / Preview") { editorModeRawValue = MarkdownEditorMode.split.rawValue }
        }
    }

    private var sourceEditor: some View {
        TextEditor(
            text: Binding(
                get: { appModel.selectedMarkdownDraft?.rawContents ?? "" },
                set: { appModel.updateSelectedMarkdownContents($0) }
            )
        )
        .font(.system(.body, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum MarkdownEditorMode: String, CaseIterable, Identifiable {
    case source
    case preview
    case split

    var id: String { rawValue }

    var label: String {
        switch self {
        case .source:
            return "Source"
        case .preview:
            return "Preview"
        case .split:
            return "Split"
        }
    }

    var systemImage: String {
        switch self {
        case .source:
            return "chevron.left.forwardslash.chevron.right"
        case .preview:
            return "doc.richtext"
        case .split:
            return "rectangle.split.2x1"
        }
    }
}