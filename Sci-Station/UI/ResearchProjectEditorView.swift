import SwiftUI

struct ResearchProjectEditorView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private let colorPresets = ["#A7C7E7", "#B8E0D2", "#F4B6C2", "#CDB4DB", "#F6D186", "#BFC7D5"]
    private let iconPresets = ["folder", "atom", "sparkles", "books.vertical", "chart.xyaxis.line", "brain"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appModel.researchProjectEditorDraft.isNew ? "New Project" : "Edit Project")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Project metadata is stored in the root project registry and in the project's project.yaml file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Project Name", text: $appModel.researchProjectEditorDraft.name)
                    .textFieldStyle(.roundedBorder)

                TextField("Description", text: $appModel.researchProjectEditorDraft.description, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Background Color")
                    .font(.headline)

                HStack(spacing: 8) {
                    ForEach(colorPresets, id: \.self) { colorHex in
                        Button {
                            appModel.researchProjectEditorDraft.colorHex = colorHex
                        } label: {
                            Circle()
                                .fill(Color(hex: colorHex))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(appModel.researchProjectEditorDraft.colorHex == colorHex ? Color.primary : Color.secondary.opacity(0.25), lineWidth: appModel.researchProjectEditorDraft.colorHex == colorHex ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(colorHex)
                    }

                    TextField("#4F7CAC", text: $appModel.researchProjectEditorDraft.colorHex)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack(spacing: 10) {
                    Image(systemName: appModel.researchProjectEditorDraft.iconName.isEmpty ? "folder" : appModel.researchProjectEditorDraft.iconName)
                    Text(appModel.researchProjectEditorDraft.name.isEmpty ? "Project Preview" : appModel.researchProjectEditorDraft.name)
                        .fontWeight(.semibold)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color(hex: appModel.researchProjectEditorDraft.colorHex).opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: appModel.researchProjectEditorDraft.colorHex).opacity(0.65), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.headline)

                HStack(spacing: 8) {
                    ForEach(iconPresets, id: \.self) { iconName in
                        Button {
                            appModel.researchProjectEditorDraft.iconName = iconName
                        } label: {
                            Image(systemName: iconName)
                                .frame(width: 28, height: 28)
                                .foregroundStyle(appModel.researchProjectEditorDraft.iconName == iconName ? Color.accentColor : Color.secondary)
                                .background(appModel.researchProjectEditorDraft.iconName == iconName ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .help(iconName)
                    }

                    TextField("folder", text: $appModel.researchProjectEditorDraft.iconName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button(appModel.researchProjectEditorDraft.isNew ? "Create" : "Save") {
                    appModel.saveResearchProjectDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.researchProjectEditorDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appModel.isSavingResearchProject)
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}