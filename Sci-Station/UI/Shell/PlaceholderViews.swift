import SwiftUI

/// Shared placeholder used by project-space content routers when a given tab
/// is a stub (not yet implemented) or in an error state (missing data, no
/// center node, etc.). Keeping this internal-but-shared avoids each tab from
/// reinventing the same layout, and also means P46 can reuse the same
/// placeholder as the "graph data not built yet" state.
struct ProjectSpacePlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.largeTitle.weight(.semibold))
            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Shared "tab router failed to resolve" view. Shown when a route or tab id
/// falls through the router's switch. Offers a retry that is wired by the
/// caller (typically to reset to the overview tab and log a debug event).
struct ProjectSpaceUnavailableView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
