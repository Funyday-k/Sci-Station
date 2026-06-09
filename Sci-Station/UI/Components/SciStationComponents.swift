import SwiftUI

struct SciBadge: View {
    let title: String
    var systemImage: String?
    var color: Color

    init(_ title: String, systemImage: String? = nil, color: Color = .secondary) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(title)
            }
        }
        .font(SciStationDesign.Typography.badge)
        .padding(.horizontal, 6)
        .padding(.vertical, SciStationDesign.Spacing.xxs)
        .foregroundStyle(color)
        .background(SciStationDesign.Semantic.surface(color), in: Capsule())
    }
}

struct SciSectionCard<Content: View>: View {
    var title: String?
    var systemImage: String?
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        spacing: CGFloat = SciStationDesign.Spacing.sm,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .font(SciStationDesign.Typography.cardTitle)
                } else {
                    Text(title)
                        .font(SciStationDesign.Typography.cardTitle)
                }
            }
            content()
        }
        .padding(SciStationDesign.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: SciStationDesign.Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SciStationDesign.Radius.card, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }
}

struct SciEmptyState: View {
    let title: String
    var message: String?
    var systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        title: String,
        message: String? = nil,
        systemImage: String = "tray",
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: SciStationDesign.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(SciStationDesign.Typography.cardTitle)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(SciStationDesign.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button {
                    action()
                } label: {
                    Text(actionTitle)
                }
                .controlSize(.small)
                .padding(.top, SciStationDesign.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SciStationDesign.Spacing.xl)
    }
}

struct SciActionButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            action()
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

#if DEBUG
#Preview("Sci-Station Components") {
    ScrollView {
        VStack(alignment: .leading, spacing: SciStationDesign.Spacing.lg) {
            HStack(spacing: SciStationDesign.Spacing.sm) {
                SciBadge("Default")
                SciBadge("Success", systemImage: "checkmark.circle", color: SciStationDesign.Semantic.success)
                SciBadge("Warning", systemImage: "exclamationmark.triangle", color: SciStationDesign.Semantic.warning)
                SciBadge("Danger", systemImage: "xmark.octagon", color: SciStationDesign.Semantic.danger)
                SciBadge("Info", systemImage: "info.circle", color: SciStationDesign.Semantic.info)
            }

            SciSectionCard(title: "Section Card", systemImage: "square.grid.2x2") {
                Text("A reusable titled card with a bordered surface, used to group panel content.")
                    .font(SciStationDesign.Typography.body)
                HStack(spacing: SciStationDesign.Spacing.sm) {
                    SciActionButton("Primary", systemImage: "plus") {}
                    SciActionButton("Delete", systemImage: "trash", role: .destructive) {}
                }
            }

            SciSectionCard {
                SciEmptyState(
                    title: "Nothing here yet",
                    message: "Empty-state placeholder with an optional call to action.",
                    systemImage: "tray",
                    actionTitle: "Create"
                ) {}
            }
        }
        .padding(SciStationDesign.Spacing.lg)
    }
    .frame(width: 520, height: 480)
}
#endif
