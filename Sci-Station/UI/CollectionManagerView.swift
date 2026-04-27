import SwiftUI

struct CollectionManagerView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCollectionPath: String?
    @State private var newCollectionPath = ""
    @State private var renameValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage Collections")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                List(selection: $selectedCollectionPath) {
                    ForEach(appModel.collections) { collection in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(collection.relativePath)
                                Text("\(collection.paperCount) papers")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(Optional(collection.relativePath))
                    }
                }
                .frame(minWidth: 260)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("New collection path", text: $newCollectionPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Create Collection") {
                        appModel.createCollection(relativePath: newCollectionPath)
                        newCollectionPath = ""
                    }
                    .buttonStyle(.borderedProminent)

                    Divider()

                    TextField("Rename selected collection", text: $renameValue)
                        .textFieldStyle(.roundedBorder)
                        .disabled(selectedCollectionPath == nil)

                    HStack(spacing: 10) {
                        Button("Rename") {
                            appModel.renameSelectedCollection(to: renameValue)
                        }
                        .disabled(selectedCollectionPath == nil || renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Delete") {
                            appModel.deleteSelectedCollection()
                            selectedCollectionPath = nil
                            renameValue = ""
                        }
                        .disabled(selectedCollectionPath == nil)
                    }

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 420)
        .onChange(of: selectedCollectionPath) { _, newValue in
            if let newValue {
                appModel.selectCollection(newValue)
            } else {
                appModel.clearLibraryFilters()
            }
            renameValue = newValue?.split(separator: "/").last.map(String.init) ?? ""
        }
    }
}