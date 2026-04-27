import SwiftUI

struct IdentifierImportView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add by Identifier or Link")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Paste a DOI, arXiv ID, INSPIRE URL, PDF URL or normal page URL. Preview resolves metadata before import.")
                .foregroundStyle(.secondary)

            TextField("Identifier or Link", text: $appModel.identifierImportInput)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                TextField("Collection", text: $appModel.identifierImportCollectionPath)
                    .textFieldStyle(.roundedBorder)
                TextField("Tags", text: $appModel.identifierImportTagsText, prompt: Text("Comma-separated"))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button("Preview Metadata", action: appModel.previewIdentifierImport)
                    .buttonStyle(.bordered)

                Button("Import", action: appModel.performIdentifierImport)
                    .buttonStyle(.borderedProminent)

                Button("Close") {
                    dismiss()
                }
            }

            if appModel.isResolvingIdentifierImport || appModel.isPerformingIdentifierImport {
                ProgressView(appModel.isPerformingIdentifierImport ? "Importing…" : "Resolving metadata…")
            }

            GroupBox("Preview") {
                if let preview = appModel.identifierImportPreview {
                    VStack(alignment: .leading, spacing: 10) {
                        WorkspacePathRow(label: "Title", value: preview.title)
                        WorkspacePathRow(label: "Authors", value: preview.authors.isEmpty ? "-" : preview.authors.joined(separator: ", "))
                        WorkspacePathRow(label: "Year", value: preview.year.map(String.init) ?? "-")
                        WorkspacePathRow(label: "DOI", value: preview.doi ?? "-")
                        WorkspacePathRow(label: "arXiv", value: preview.arxiv ?? "-")
                        WorkspacePathRow(label: "INSPIRE", value: preview.inspireID ?? "-")
                        WorkspacePathRow(label: "URL", value: preview.url ?? "-")
                        WorkspacePathRow(label: "PDF URL", value: preview.pdfURL ?? "-")
                        WorkspacePathRow(label: "Source", value: preview.sourceProvider)
                        if let abstract = preview.abstract, !abstract.isEmpty {
                            Text(abstract)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No preview yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 460)
    }
}