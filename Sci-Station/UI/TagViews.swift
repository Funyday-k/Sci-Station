import SwiftUI

struct TagChipView: View {
    let tag: TagDefinition

    var body: some View {
        Text(tag.name)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Color(hex: tag.textColorHex ?? defaultTextColorHex))
            .background(Color(hex: tag.colorHex), in: Capsule())
    }

    private var defaultTextColorHex: String {
        Color(hex: tag.colorHex).isDarkColor ? "#F9FAFB" : "#1F2937"
    }
}

struct TagChipGroupView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tags.prefix(3)), id: \.self) { name in
                TagChipView(tag: appModel.tagDefinition(named: name) ?? TagDefinition(name: name, colorHex: "#E5E7EB", textColorHex: "#374151"))
            }

            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TagManagerView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTagName: String?
    @State private var draftName = ""
    @State private var draftColorHex = "#B57EDC"
    @State private var draftTextColorHex = "#4A235A"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage Tags")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                List(selection: $selectedTagName) {
                    ForEach(appModel.tagDefinitions) { tag in
                        TagChipView(tag: tag)
                            .tag(Optional(tag.name))
                    }
                }
                .frame(minWidth: 220)

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Color Hex", text: $draftColorHex)
                        .textFieldStyle(.roundedBorder)

                    TextField("Text Color Hex", text: $draftTextColorHex)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        Button("New") {
                            resetDraft()
                        }

                        Button("Save") {
                            appModel.saveTagDefinition(
                                name: draftName,
                                colorHex: draftColorHex,
                                textColorHex: draftTextColorHex
                            )
                            selectedTagName = draftName
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Delete") {
                            guard let selectedTagName else {
                                return
                            }

                            appModel.deleteTagDefinition(named: selectedTagName)
                            resetDraft()
                        }
                        .disabled(selectedTagName == nil)
                    }

                    TagChipView(tag: TagDefinition(name: draftName.isEmpty ? "Preview" : draftName, colorHex: draftColorHex, textColorHex: draftTextColorHex))

                    Spacer()

                    Button("Done") {
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 420)
        .onChange(of: selectedTagName) { _, newValue in
            guard let newValue,
                  let tag = appModel.tagDefinitions.first(where: { $0.name == newValue }) else {
                return
            }

            draftName = tag.name
            draftColorHex = tag.colorHex
            draftTextColorHex = tag.textColorHex ?? ""
        }
    }

    private func resetDraft() {
        selectedTagName = nil
        draftName = ""
        draftColorHex = "#B57EDC"
        draftTextColorHex = "#4A235A"
    }
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    var isDarkColor: Bool {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB)?.cgColor.components, components.count >= 3 else {
            return false
        }

        let luminance = 0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2]
        return luminance < 0.6
    }
}