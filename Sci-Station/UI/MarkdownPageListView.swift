import SwiftUI

struct MarkdownPageListView: View {
    @EnvironmentObject private var appModel: AppViewModel

    var body: some View {
        List(selection: selectionBinding) {
            if appModel.markdownDocuments.isEmpty {
                Text("No wiki pages yet.")
                    .foregroundStyle(.secondary)
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
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { appModel.selectedMarkdownID },
            set: { appModel.selectMarkdownDocument(id: $0) }
        )
    }
}