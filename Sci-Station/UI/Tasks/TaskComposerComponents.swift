import SwiftUI

// MARK: - Priority red flags

/// Importance shown as up to three red flags. Interactive when `selection` is
/// bound; tapping a flag sets the priority to that flag count (1...3).
struct TodoPriorityFlagsView: View {
    @Binding var priority: Priority
    var isInteractive: Bool = true

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { index in
                let filled = index <= priority.flagCount
                Image(systemName: filled ? "flag.fill" : "flag")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(filled ? Color.red : Color.secondary.opacity(0.45))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isInteractive else { return }
                        if priority.flagCount == index {
                            // Tapping the last filled flag clears back to a single flag.
                            priority = .low
                        } else {
                            priority = Priority.fromFlagCount(index)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Priority"))
        .accessibilityValue(Text("\(priority.flagCount) flags"))
    }
}

/// Read-only flags for rows/cards.
struct TodoPriorityFlagsBadge: View {
    let priority: Priority

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<priority.flagCount, id: \.self) { _ in
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.red)
            }
        }
    }
}

// MARK: - Task tag chips

struct TodoTagChip: View {
    let tag: TagDefinition
    var isSelected: Bool = false
    var showsCheck: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if showsCheck {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: tag.colorHex) : Color.secondary.opacity(0.5))
            }
            Text(tag.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(Color(hex: tag.textColorHex ?? "#1F2937"))
        .background(Color(hex: tag.colorHex).opacity(isSelected ? 0.55 : 0.34), in: Capsule())
        .overlay(
            Capsule().stroke(Color(hex: tag.colorHex).opacity(isSelected ? 0.9 : 0), lineWidth: 1)
        )
    }
}

/// Read-only group of tag chips used in rows/cards.
struct TodoTagChipGroup: View {
    @EnvironmentObject private var appModel: AppViewModel
    let tags: [String]
    var limit: Int = 3

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tags.prefix(limit)), id: \.self) { name in
                TodoTagChip(tag: appModel.todoTagDefinition(named: name) ?? TagDefinition(name: name, colorHex: "#A7D8F0", textColorHex: "#17465F"))
            }
            if tags.count > limit {
                Text("+\(tags.count - limit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Lightweight wrapping layout for chips

struct TaskFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth, currentRowWidth > 0 {
                totalHeight += rowHeight + spacing
                rows.append(0)
                currentRowWidth = 0
                rowHeight = 0
            }
            currentRowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? currentRowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Task kind selector (icon-forward)

struct TaskKindSelector: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Binding var kind: TodoKind

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TodoKind.allCases, id: \.self) { option in
                let isSelected = kind == option
                Button {
                    withAnimation(.snappy(duration: 0.15)) { kind = option }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                        Text(appModel.localized(option.label, option.englishLabel))
                            .font(.callout.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : SciStationDesign.subtleSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1.2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#if DEBUG
#Preview("Task Components") {
    struct Harness: View {
        @State private var priority = Priority.medium
        @State private var kind = TodoKind.general
        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                TaskKindSelector(kind: $kind)
                TodoPriorityFlagsView(priority: $priority)
                TaskFlowLayout {
                    TodoTagChip(tag: TagDefinition(name: "writing", colorHex: "#F4A259"), isSelected: true, showsCheck: true)
                    TodoTagChip(tag: TagDefinition(name: "urgent", colorHex: "#E76F51"), showsCheck: true)
                    TodoTagChip(tag: TagDefinition(name: "lit-review", colorHex: "#8AB17D"), showsCheck: true)
                }
            }
            .padding(24)
            .frame(width: 460)
            .environmentObject(AppViewModel())
        }
    }
    return Harness()
}
#endif
