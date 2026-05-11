import SwiftUI

struct MarkdownEditorView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @AppStorage("wiki.markdownEditorMode") private var editorModeRawValue = MarkdownEditorMode.source.rawValue
    @State private var isFrontmatterExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let document = appModel.selectedMarkdownDraft {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                        saveStateBadge
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
                        .keyboardShortcut("s", modifiers: [.command])
                }

                    markdownFormattingToolbar

                    frontmatterPanel(for: document)

                editorSurface(for: document)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wiki")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Select a Markdown page to inspect frontmatter, edit content, and save it back to the workspace.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Open Project Overview", action: appModel.openCurrentProjectOverviewPage)
                            .buttonStyle(.borderedProminent)
                        Button("Reload Wiki", action: appModel.reloadWiki)
                            .buttonStyle(.bordered)
                        Button("Open Wiki Folder", action: appModel.openWikiFolder)
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
    }

    private var saveStateBadge: some View {
        let state = appModel.selectedMarkdownSaveState
        let color: Color = switch state {
        case .clean: .green
        case .dirty: .orange
        case .saving: .blue
        case .failed: .red
        }

        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(appModel.selectedMarkdownSaveStateLabel)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .help(appModel.selectedMarkdownSaveErrorMessage ?? appModel.selectedMarkdownSaveStateLabel)
    }

    private var markdownFormattingToolbar: some View {
        HStack(spacing: 6) {
            ForEach(MarkdownFormattingAction.allCases) { action in
                Button {
                    appModel.insertMarkdownFormatting(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.bordered)
                .help(action.title)
                .disabled(appModel.selectedMarkdownDraft == nil)
            }

            Spacer(minLength: 8)
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func frontmatterPanel(for document: MarkdownDocument) -> some View {
        if document.frontmatterEntries.isEmpty {
            Button {
                appModel.addFrontmatterToSelectedMarkdown()
            } label: {
                Label("Add Frontmatter", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else {
            DisclosureGroup(isExpanded: $isFrontmatterExpanded) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(document.frontmatterEntries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.key)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .leading)
                            Text(entry.value)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("Frontmatter", systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.semibold))
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
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