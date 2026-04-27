import SwiftUI

struct MarkdownEditorView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let document = appModel.selectedMarkdownDraft {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                        Text(document.relativePath)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    if appModel.isSavingSelectedMarkdown {
                        ProgressView("Saving…")
                    }

                    Button("Save", action: appModel.saveSelectedMarkdownChanges)
                        .buttonStyle(.borderedProminent)
                        .disabled(!appModel.canSaveSelectedMarkdown)
                }

                TextEditor(
                    text: Binding(
                        get: { appModel.selectedMarkdownDraft?.rawContents ?? "" },
                        set: { appModel.updateSelectedMarkdownContents($0) }
                    )
                )
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}