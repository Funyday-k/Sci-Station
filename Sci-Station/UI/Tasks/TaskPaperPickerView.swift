import SwiftUI

/// Paper selection sheet for reading tasks. Defaults to the current project's
/// papers, with a scope toggle to browse the whole library and a search field.
struct TaskPaperPickerView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedPaperIDs: [String]
    let defaultProjectID: String?

    @State private var searchText = ""
    @State private var limitToProject: Bool

    init(selectedPaperIDs: Binding<[String]>, defaultProjectID: String?) {
        self._selectedPaperIDs = selectedPaperIDs
        self.defaultProjectID = defaultProjectID
        self._limitToProject = State(initialValue: defaultProjectID != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if filteredPapers.isEmpty {
                emptyState
            } else {
                paperList
            }
            Divider()
            footer
        }
        .frame(minWidth: 460, minHeight: 460)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Label(appModel.localized("选择论文", "Select Papers"), systemImage: "book")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(appModel.localized("搜索标题或作者", "Search title or author"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(SciStationDesign.subtleSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if defaultProjectID != nil {
                Picker("", selection: $limitToProject) {
                    Text(appModel.localized("本项目", "This Project")).tag(true)
                    Text(appModel.localized("全部论文", "All Papers")).tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(14)
    }

    private var paperList: some View {
        List {
            ForEach(filteredPapers, id: \.id) { paper in
                Button {
                    toggle(paper.id)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selectedPaperIDs.contains(paper.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedPaperIDs.contains(paper.id) ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paper.displayTitle)
                                .fontWeight(.medium)
                                .lineLimit(2)
                            Text(paper.authorsDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(appModel.localized("没有匹配的论文", "No matching papers"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(appModel.localized("已选 \(selectedPaperIDs.count) 篇", "\(selectedPaperIDs.count) selected"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appModel.localized("完成", "Done")) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    private var filteredPapers: [Paper] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return appModel.papers.filter { paper in
            let matchesProject = !limitToProject || (defaultProjectID.map { paper.projectIDs.contains($0) } ?? true)
            let matchesQuery = query.isEmpty
                || paper.displayTitle.lowercased().contains(query)
                || paper.authorsDisplay.lowercased().contains(query)
            return matchesProject && matchesQuery
        }
    }

    private func toggle(_ id: String) {
        if let index = selectedPaperIDs.firstIndex(of: id) {
            selectedPaperIDs.remove(at: index)
        } else {
            selectedPaperIDs.append(id)
        }
    }
}
