import SwiftUI

/// Inspector panel for a selected graph node. Shows metadata and actions.
struct NodeInspectorPanel: View {
    @EnvironmentObject private var appModel: AppViewModel
    let node: GraphNode
    let viewState: GraphViewState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                metadataSection
                Divider()
                actionsSection
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(kindColor)
                    .frame(width: 10, height: 10)
                Text(node.kind.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(node.displayName)
                .font(.headline)
                .lineLimit(3)
        }
    }

    private var kindColor: Color {
        switch node.kind {
        case .paper: return .blue
        case .project: return .purple
        case .concept, .method: return .orange
        case .dataset: return .teal
        case .claim: return .yellow
        case .evidence: return .green
        case .task: return .cyan
        case .artifact: return .indigo
        case .calendarEvent: return .pink
        case .run: return .brown
        case .approval: return .mint
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.subheadline.weight(.semibold))

            if let payload = node.payload.objectValue {
                ForEach(Array(payload.keys.sorted().prefix(8)), id: \.self) { key in
                    if let value = displayValue(payload[key]), !value.isEmpty {
                        HStack(alignment: .top) {
                            Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(value)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if isExternal {
                Label("External paper (not in local library)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.subheadline.weight(.semibold))

            if node.kind == .paper, !isExternal {
                actionButton("Open Paper", systemImage: "doc.text", action: .openPaper(paperID: stableID))
                if let projectID = appModel.selectedProjectSpaceProject?.id {
                    actionButton("Add to Project", systemImage: "folder.badge.plus", action: .addToProject(paperID: stableID, projectID: projectID))
                }
            }

            if isExternal {
                Text("Import this paper to enable actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: NodeAction) -> some View {
        Button {
            appModel.handleGraphNodeAction(action)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var isExternal: Bool {
        node.payload.objectValue?["is_external"] == .bool(true)
    }

    private var stableID: String {
        if node.id.hasPrefix("paper:") {
            return String(node.id.dropFirst("paper:".count))
        }
        return node.id
    }

    private func displayValue(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let s): return s.isEmpty ? nil : s
        case .number(let n): return n
        case .bool(let b): return b ? "Yes" : "No"
        case .null: return nil
        default: return nil
        }
    }
}
