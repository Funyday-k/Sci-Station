import SwiftUI

struct TagChipView: View {
    let tag: TagDefinition

    var body: some View {
        Text(tag.name)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Color(hex: tag.textColorHex ?? defaultTextColorHex))
            .background(Color(hex: tag.colorHex).opacity(0.42), in: Capsule())
    }

    private var defaultTextColorHex: String {
        "#1F2937"
    }
}

struct TagChipGroupView: View {
    @EnvironmentObject private var appModel: AppViewModel

    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tags.prefix(3)), id: \.self) { name in
                TagChipView(tag: appModel.tagDefinition(named: name) ?? TagDefinition(name: name, colorHex: "#A7D8F0", textColorHex: "#17465F"))
            }

            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TagCompletionField: View {
    @EnvironmentObject private var appModel: AppViewModel

    let title: String
    @Binding var text: String
    var prompt: Text? = nil
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let prompt {
                TextField(title, text: $text, prompt: prompt)
                    .onSubmit(onSubmit)
            } else {
                TextField(title, text: $text)
                    .onSubmit(onSubmit)
            }

            if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            insert(suggestion)
                        } label: {
                            Text(suggestion)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.bordered)
                        .help("Use tag \(suggestion)")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var suggestions: [String] {
        let fragment = currentFragment.lowercased()
        guard !fragment.isEmpty else {
            return []
        }
        let existingTags = appModel.availableTagDefinitions.map(\.name)
        let usedTags = Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        return existingTags
            .filter { tagName in
                !usedTags.contains(tagName.lowercased()) || tagName.lowercased() == fragment
            }
            .map { tagName in
                (tagName, tagScore(tagName.lowercased(), fragment: fragment))
            }
            .filter { $0.1 < Int.max }
            .sorted { first, second in
                if first.1 == second.1 {
                    return first.0.localizedStandardCompare(second.0) == .orderedAscending
                }
                return first.1 < second.1
            }
            .prefix(5)
            .map(\.0)
    }

    private var currentFragment: String {
        text.split(separator: ",", omittingEmptySubsequences: false)
            .last
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }

    private func tagScore(_ tag: String, fragment: String) -> Int {
        guard !fragment.isEmpty else {
            return tag.count + 20
        }
        if tag == fragment {
            return 0
        }
        if tag.hasPrefix(fragment) {
            return 1 + tag.count - fragment.count
        }
        if tag.contains(fragment) {
            return 20 + tag.count - fragment.count
        }
        let distance = levenshteinDistance(tag, fragment)
        return distance <= max(2, fragment.count / 2) ? 40 + distance : Int.max
    }

    private func insert(_ suggestion: String) {
        var parts = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if parts.isEmpty {
            text = suggestion
            return
        }

        parts[parts.count - 1] = " " + suggestion
        text = parts.joined(separator: ",").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func levenshteinDistance(_ first: String, _ second: String) -> Int {
        let firstCharacters = Array(first)
        let secondCharacters = Array(second)
        if firstCharacters.isEmpty {
            return secondCharacters.count
        }
        if secondCharacters.isEmpty {
            return firstCharacters.count
        }
        var previousRow = Array(0...secondCharacters.count)

        for firstIndex in 1...firstCharacters.count {
            var currentRow = [firstIndex]
            for secondIndex in 1...secondCharacters.count {
                let cost = firstCharacters[firstIndex - 1] == secondCharacters[secondIndex - 1] ? 0 : 1
                currentRow.append(min(
                    previousRow[secondIndex] + 1,
                    currentRow[secondIndex - 1] + 1,
                    previousRow[secondIndex - 1] + cost
                ))
            }
            previousRow = currentRow
        }

        return previousRow.last ?? 0
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