import SwiftUI

/// Force-directed graph canvas view. Retained for the "Theme Clusters" and
/// "Evidence Support" views which still benefit from a network layout.
/// The primary "Paper Neighborhood" view now uses the bipartite citation
/// layout in GraphView.swift instead.
struct GraphCanvasView: View {
    let subgraph: GraphSubgraph
    let positions: [String: GraphLayoutPoint]
    @Binding var selectedNodeID: String?
    let zoom: Double

    var body: some View {
        // Placeholder — the force-directed canvas is available for future
        // views (Theme Clusters, Evidence Support, Artifact Lineage) but
        // the primary citation view no longer uses it.
        Text("Network view available for cluster/lineage modes.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
