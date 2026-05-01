import SwiftUI

struct PaperMarkdownConversionBadge: View {
    let state: PaperMarkdownConversionState
    var message: String?

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundStyle, in: Capsule())
            .help(message ?? title)
    }

    private var title: String {
        switch state {
        case .noPDF:
            return "无 PDF"
        case .notConverted:
            return "未转换"
        case .converting:
            return "转换中"
        case .succeeded:
            return "已转换"
        case .fallback:
            return "已回退"
        case .failed:
            return "转换失败"
        }
    }

    private var systemImage: String {
        switch state {
        case .noPDF:
            return "doc.badge.questionmark"
        case .notConverted:
            return "circle"
        case .converting:
            return "arrow.triangle.2.circlepath"
        case .succeeded:
            return "checkmark.circle"
        case .fallback:
            return "exclamationmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var foregroundStyle: Color {
        switch state {
        case .noPDF, .notConverted:
            return .secondary
        case .converting:
            return .blue
        case .succeeded:
            return .green
        case .fallback:
            return .orange
        case .failed:
            return .red
        }
    }

    private var backgroundStyle: Color {
        switch state {
        case .noPDF, .notConverted:
            return Color.secondary.opacity(0.12)
        case .converting:
            return Color.blue.opacity(0.12)
        case .succeeded:
            return Color.green.opacity(0.12)
        case .fallback:
            return Color.orange.opacity(0.12)
        case .failed:
            return Color.red.opacity(0.12)
        }
    }
}
