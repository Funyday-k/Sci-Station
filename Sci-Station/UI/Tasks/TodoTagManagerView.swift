import SwiftUI

/// Centralized management for task tags (name + custom colors), mirroring the
/// paper `TagManagerView` so task tags work "just like" paper tags.
struct TodoTagManagerView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTagName: String?
    @State private var draftName = ""
    @State private var draftColorHex = TaskTagPalette.colors[0]
    @State private var draftTextColorHex = "#1F2937"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(appModel.localized("管理任务标签", "Manage Task Tags"), systemImage: "tag")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 16) {
                tagList
                editor
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
        .onChange(of: selectedTagName) { _, newValue in
            guard let newValue,
                  let tag = appModel.availableTodoTagDefinitions.first(where: { $0.name == newValue }) else {
                return
            }
            draftName = tag.name
            draftColorHex = tag.colorHex
            draftTextColorHex = tag.textColorHex ?? "#1F2937"
        }
    }

    private var tagList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appModel.availableTodoTagDefinitions.isEmpty {
                Text(appModel.localized("还没有任务标签。", "No task tags yet."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedTagName) {
                    ForEach(appModel.availableTodoTagDefinitions) { tag in
                        TodoTagChip(tag: tag)
                            .tag(Optional(tag.name))
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 240)
        .frame(maxHeight: .infinity)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(appModel.localized("标签名称", "Tag name"), text: $draftName)
                .textFieldStyle(.roundedBorder)

            Text(appModel.localized("背景色", "Background color"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            colorSwatches(selection: $draftColorHex)

            TextField(appModel.localized("背景色 Hex", "Background hex"), text: $draftColorHex)
                .textFieldStyle(.roundedBorder)
            TextField(appModel.localized("文字色 Hex", "Text hex"), text: $draftTextColorHex)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 6) {
                Text(appModel.localized("预览", "Preview"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TodoTagChip(tag: TagDefinition(
                    name: draftName.isEmpty ? appModel.localized("示例", "Sample") : draftName,
                    colorHex: draftColorHex,
                    textColorHex: draftTextColorHex
                ))
            }

            HStack(spacing: 10) {
                Button {
                    resetDraft()
                } label: {
                    Label(appModel.localized("新建", "New"), systemImage: "plus")
                }
                Button {
                    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    appModel.upsertTodoTag(TagDefinition(name: trimmed, colorHex: draftColorHex, textColorHex: draftTextColorHex))
                    selectedTagName = trimmed
                } label: {
                    Label(appModel.localized("保存", "Save"), systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(role: .destructive) {
                    guard let selectedTagName else { return }
                    appModel.deleteTodoTag(named: selectedTagName)
                    resetDraft()
                } label: {
                    Label(appModel.localized("删除", "Delete"), systemImage: "trash")
                }
                .disabled(selectedTagName == nil)
            }
            .controlSize(.small)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func colorSwatches(selection: Binding<String>) -> some View {
        HStack(spacing: 6) {
            ForEach(TaskTagPalette.colors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.primary.opacity(selection.wrappedValue == hex ? 0.8 : 0), lineWidth: 2))
                    .onTapGesture { selection.wrappedValue = hex }
            }
        }
    }

    private func resetDraft() {
        selectedTagName = nil
        draftName = ""
        draftColorHex = TaskTagPalette.colors[0]
        draftTextColorHex = "#1F2937"
    }
}

#if DEBUG
#Preview("Todo Tag Manager") {
    TodoTagManagerView()
        .environmentObject(AppViewModel())
}
#endif
