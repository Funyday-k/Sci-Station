import AppKit
import SwiftUI

struct IdentifierImportView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add by Identifier or Link")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Paste one or many DOI, arXiv IDs, INSPIRE URLs, PDF URLs or normal page URLs. Preview resolves the first item; import processes all parsed entries.")
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $appModel.identifierImportInput)
                    .font(.callout.monospaced())
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100, maxHeight: 140)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                if appModel.identifierImportInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Paste one or many links, DOIs, or arXiv IDs")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                }
            }

            Text(batchSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField("Collection", text: $appModel.identifierImportCollectionPath)
                    .textFieldStyle(.roundedBorder)
                TextField("Tags", text: $appModel.identifierImportTagsText, prompt: Text("Comma-separated"))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button(appModel.identifierImportInputs.count > 1 ? "Preview First" : "Preview Metadata", action: appModel.previewIdentifierImport)
                    .buttonStyle(.bordered)
                    .disabled(appModel.identifierImportInputs.isEmpty)

                Button(importButtonTitle) {
                    appModel.performIdentifierImport()
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.identifierImportInputs.isEmpty)

                Button("Close") {
                    dismiss()
                }
            }

            if appModel.isResolvingIdentifierImport || appModel.isPerformingIdentifierImport {
                ProgressView(appModel.isPerformingIdentifierImport ? "Importing…" : "Resolving metadata…")
            }

            if let statusMessage = appModel.identifierImportStatusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
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

    private var batchSummary: String {
        let count = appModel.identifierImportInputs.count
        switch count {
        case 0:
            return "No import targets parsed yet."
        case 1:
            return "1 import target parsed."
        default:
            return "\(count) import targets parsed."
        }
    }

    private var importButtonTitle: String {
        let count = appModel.identifierImportInputs.count
        return count > 1 ? "Import All (\(count))" : "Import"
    }
}