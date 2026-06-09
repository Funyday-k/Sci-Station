import SwiftUI

/// A tag-shaped button that opens a popover for multi-selecting task tags and
/// creating new ones (custom name + color), mirroring paper-tag ergonomics.
struct TaskTagPickerField: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Binding var selectedTags: [String]

    @State private var isPresenting = false

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.system(size: 13, weight: .semibold))
                if selectedTags.isEmpty {
                    Text(appModel.localized("标签", "Tags")).font(.callout)
                } else {
                    Text("\(selectedTags.count)")
                        .font(.callout.weight(.semibold))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(selectedTags.isEmpty ? Color.secondary : Color.accentColor)
            .background(Capsule().fill(selectedTags.isEmpty ? SciStationDesign.subtleSurface : Color.accentColor.opacity(0.12)))
            .overlay(Capsule().stroke(selectedTags.isEmpty ? SciStationDesign.hairline : Color.clear, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresenting, arrowEdge: .bottom) {
            TaskTagPickerPopover(selectedTags: $selectedTags)
                .environmentObject(appModel)
        }
    }
}

private struct TaskTagPickerPopover: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Binding var selectedTags: [String]

    @State private var draftName = ""
    @State private var draftColorHex = TaskTagPalette.colors[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appModel.localized("任务标签", "Task Tags"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if appModel.availableTodoTagDefinitions.isEmpty {
                Text(appModel.localized("还没有标签，创建一个吧。", "No tags yet — create one below."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    TaskFlowLayout(spacing: 6) {
                        ForEach(appModel.availableTodoTagDefinitions) { tag in
                            Button {
                                toggle(tag.name)
                            } label: {
                                TodoTagChip(tag: tag, isSelected: selectedTags.contains(tag.name), showsCheck: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }

            Divider()

            Text(appModel.localized("新建标签", "New Tag"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(appModel.localized("标签名称", "Tag name"), text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createTag)
                Button {
                    createTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack(spacing: 6) {
                ForEach(TaskTagPalette.colors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(Color.primary.opacity(draftColorHex == hex ? 0.8 : 0), lineWidth: 2)
                        )
                        .onTapGesture { draftColorHex = hex }
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func toggle(_ name: String) {
        if let index = selectedTags.firstIndex(of: name) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(name)
        }
    }

    private func createTag() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appModel.upsertTodoTag(TagDefinition(name: trimmed, colorHex: draftColorHex))
        if !selectedTags.contains(trimmed) {
            selectedTags.append(trimmed)
        }
        draftName = ""
    }
}

enum TaskTagPalette {
    static let colors: [String] = [
        "#E76F51", "#F4A259", "#E9C46A", "#8AB17D",
        "#2A9D8F", "#4F7CAC", "#6D597A", "#B56576"
    ]
}

#if DEBUG
#Preview("Task Tag Picker") {
    struct Harness: View {
        @State private var tags: [String] = ["writing"]
        var body: some View {
            TaskTagPickerField(selectedTags: $tags)
                .padding(40)
                .environmentObject(AppViewModel())
        }
    }
    return Harness()
}
#endif
