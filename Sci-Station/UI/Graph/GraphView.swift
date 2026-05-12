import SwiftUI

/// Citation graph view modeled after the reference screenshot: a center paper
/// node with References (left cluster) and Cited-by (right cluster) connected
/// by lines. Each node shows "Author et al. (Year)" label. Metadata is fetched
/// from online APIs (Semantic Scholar / OpenAlex) for external papers.
struct GraphView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var centerPaperIndex: Int = 0
    @State private var citesEdges: [GraphEdge] = []
    @State private var citedByEdges: [GraphEdge] = []
    @State private var nodeMap: [String: GraphNode] = [:]
    @State private var selectedNodeID: String?
    @State private var isLoading = false
    @State private var isFetchingOnline = false
    @State private var onlineMetadata: [String: OnlinePaperMeta] = [:]

    let workspace: ResearchWorkspace

    private var localPapers: [Paper] { appModel.papers }

    private var centerPaper: Paper? {
        guard !localPapers.isEmpty, centerPaperIndex < localPapers.count else { return nil }
        return localPapers[centerPaperIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isLoading {
                loadingView
            } else if let centerPaper {
                GeometryReader { geometry in
                    citationGraphContent(for: centerPaper, size: geometry.size)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadCitations() }
        .onChange(of: centerPaperIndex) { _, _ in Task { await loadCitations() } }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(isFetchingOnline ? "Fetching citation metadata from Semantic Scholar…" : "Loading citation graph…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Citation Graph")
                .font(.headline)

            Spacer()

            if !localPapers.isEmpty {
                HStack(spacing: 6) {
                    Button(action: { if centerPaperIndex > 0 { centerPaperIndex -= 1 } }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(centerPaperIndex == 0)
                    .buttonStyle(.plain)

                    Text("\(centerPaperIndex + 1) / \(localPapers.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button(action: { if centerPaperIndex < localPapers.count - 1 { centerPaperIndex += 1 } }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(centerPaperIndex >= localPapers.count - 1)
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(Array(localPapers.enumerated()), id: \.element.id) { index, paper in
                            Button(paper.displayTitle) { centerPaperIndex = index }
                        }
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
            }

            Text("References: \(citesEdges.count) · Cited-by: \(citedByEdges.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Graph Content (Node-Link Diagram)

    private func citationGraphContent(for paper: Paper, size: CGSize) -> some View {
        let centerX = size.width / 2
        let centerY = size.height / 2
        let leftNodes = citesEdges.prefix(25)
        let rightNodes = citedByEdges.prefix(25)

        return ZStack {
            // Draw edges as lines.
            Canvas { context, canvasSize in
                let cx = canvasSize.width / 2
                let cy = canvasSize.height / 2

                // Left edges (references).
                for (index, _) in leftNodes.enumerated() {
                    let pos = leftNodePosition(index: index, total: leftNodes.count, canvasSize: canvasSize)
                    var path = Path()
                    path.move(to: CGPoint(x: cx, y: cy))
                    path.addLine(to: pos)
                    context.stroke(path, with: .color(.blue.opacity(0.3)), lineWidth: 1)
                }

                // Right edges (cited-by).
                for (index, _) in rightNodes.enumerated() {
                    let pos = rightNodePosition(index: index, total: rightNodes.count, canvasSize: canvasSize)
                    var path = Path()
                    path.move(to: CGPoint(x: cx, y: cy))
                    path.addLine(to: pos)
                    context.stroke(path, with: .color(.green.opacity(0.3)), lineWidth: 1)
                }
            }

            // Center node.
            VStack(spacing: 4) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                Text(shortLabel(for: paper))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 120)
            }
            .position(x: centerX, y: centerY)

            // Left nodes (references).
            ForEach(Array(leftNodes.enumerated()), id: \.element.id) { index, edge in
                let pos = leftNodePosition(index: index, total: leftNodes.count, canvasSize: size)
                let node = nodeMap[edge.to]
                let meta = onlineMetadata[edge.to]
                citationNodeView(node: node, meta: meta, direction: .reference, isSelected: selectedNodeID == edge.to)
                    .position(x: pos.x, y: pos.y)
                    .onTapGesture { selectedNodeID = edge.to }
            }

            // Right nodes (cited-by).
            ForEach(Array(rightNodes.enumerated()), id: \.element.id) { index, edge in
                let pos = rightNodePosition(index: index, total: rightNodes.count, canvasSize: size)
                let node = nodeMap[edge.from]
                let meta = onlineMetadata[edge.from]
                citationNodeView(node: node, meta: meta, direction: .citedBy, isSelected: selectedNodeID == edge.from)
                    .position(x: pos.x, y: pos.y)
                    .onTapGesture { selectedNodeID = edge.from }
            }

            // Column headers.
            if !leftNodes.isEmpty {
                Text("References (\(citesEdges.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .position(x: size.width * 0.2, y: 20)
            }
            if !rightNodes.isEmpty {
                Text("Cited-by (\(citedByEdges.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .position(x: size.width * 0.8, y: 20)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Node Positioning

    private func leftNodePosition(index: Int, total: Int, canvasSize: CGSize) -> CGPoint {
        let spacing = min(canvasSize.height / CGFloat(total + 1), 50)
        let startY = (canvasSize.height - spacing * CGFloat(total - 1)) / 2
        let x = canvasSize.width * 0.2
        let y = startY + spacing * CGFloat(index)
        return CGPoint(x: x, y: y)
    }

    private func rightNodePosition(index: Int, total: Int, canvasSize: CGSize) -> CGPoint {
        let spacing = min(canvasSize.height / CGFloat(total + 1), 50)
        let startY = (canvasSize.height - spacing * CGFloat(total - 1)) / 2
        let x = canvasSize.width * 0.8
        let y = startY + spacing * CGFloat(index)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Citation Node View

    private func citationNodeView(node: GraphNode?, meta: OnlinePaperMeta?, direction: CitationDirection, isSelected: Bool) -> some View {
        let isExternal = node?.payload.objectValue?["is_external"] == .bool(true)
        let color: Color = direction == .reference ? .blue : .green
        let label = nodeLabel(node: node, meta: meta)

        return HStack(spacing: 5) {
            Circle()
                .fill(isExternal ? Color.gray.opacity(0.5) : color.opacity(0.7))
                .frame(width: isSelected ? 14 : 10, height: isSelected ? 14 : 10)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? color.opacity(0.1) : Color.clear)
        )
    }

    private func nodeLabel(node: GraphNode?, meta: OnlinePaperMeta?) -> String {
        // Prefer online metadata.
        if let meta {
            let author = meta.firstAuthor ?? "Unknown"
            let year = meta.year.map { "(\($0))" } ?? ""
            return "\(author) et al. \(year)"
        }
        // Fallback to graph node data.
        guard let node else { return "?" }
        let payload = node.payload.objectValue
        let author = payload?["first_author"]?.stringValue
            ?? payload?["citekey"]?.stringValue?.prefix(12).description
            ?? String(node.displayName.prefix(15))
        let year: String
        if let y = payload?["year"] {
            switch y {
            case .number(let n): year = "(\(n))"
            case .string(let s): year = "(\(s))"
            default: year = ""
            }
        } else { year = "" }
        return "\(author) et al. \(year)"
    }

    private func shortLabel(for paper: Paper) -> String {
        let author = paper.authors.first?.split(separator: " ").last.map(String.init) ?? "Unknown"
        let year = paper.year.map { "(\($0))" } ?? ""
        return "\(author) et al. \(year)"
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No papers in library")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Import papers to see their citation relationships.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadCitations() async {
        guard let paper = centerPaper else { return }
        isLoading = true
        defer { isLoading = false }

        guard let readModel = await appModel.graphReadModel() else { return }

        let paperNodeID = "paper:\(paper.resolvedGraphNodeID)"
        let snapshot = await readModel.snapshot()

        var outgoing: [GraphEdge] = []
        var incoming: [GraphEdge] = []
        var nodes: [String: GraphNode] = [:]

        for (_, edge) in snapshot.edges {
            if edge.kind == .cites {
                if edge.from == paperNodeID {
                    outgoing.append(edge)
                    if let target = snapshot.nodes[edge.to] { nodes[edge.to] = target }
                } else if edge.to == paperNodeID {
                    incoming.append(edge)
                    if let source = snapshot.nodes[edge.from] { nodes[edge.from] = source }
                }
            }
        }

        citesEdges = outgoing
        citedByEdges = incoming
        nodeMap = nodes

        // Fetch online metadata for external nodes.
        await fetchOnlineMetadata(for: nodes)
    }

    private func fetchOnlineMetadata(for nodes: [String: GraphNode]) async {
        let externalNodes = nodes.filter { $0.value.payload.objectValue?["is_external"] == .bool(true) }
        guard !externalNodes.isEmpty else { return }

        isFetchingOnline = true
        defer { isFetchingOnline = false }

        for (id, node) in externalNodes.prefix(30) {
            if onlineMetadata[id] != nil { continue }
            let payload = node.payload.objectValue ?? [:]
            let doi = payload["doi"]?.stringValue
            let arxiv = payload["arxiv"]?.stringValue

            if let meta = await fetchFromSemanticScholar(doi: doi, arxiv: arxiv) {
                onlineMetadata[id] = meta
            } else {
                // Use whatever we have from the graph node.
                onlineMetadata[id] = OnlinePaperMeta(
                    title: payload["title"]?.stringValue,
                    firstAuthor: payload["first_author"]?.stringValue,
                    year: yearFromPayload(payload),
                    venue: nil,
                    citationCount: nil
                )
            }
        }
    }

    private func fetchFromSemanticScholar(doi: String?, arxiv: String?) async -> OnlinePaperMeta? {
        let identifier: String
        if let doi, !doi.isEmpty {
            identifier = doi
        } else if let arxiv, !arxiv.isEmpty {
            identifier = "arXiv:\(arxiv)"
        } else {
            return nil
        }

        let urlString = "https://api.semanticscholar.org/graph/v1/paper/\(identifier)?fields=title,authors,year,venue,citationCount"
        guard let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let title = json["title"] as? String
            let authors = json["authors"] as? [[String: Any]]
            let firstAuthor = authors?.first?["name"] as? String
            let year = json["year"] as? Int
            let venue = json["venue"] as? String
            let citationCount = json["citationCount"] as? Int

            return OnlinePaperMeta(
                title: title,
                firstAuthor: firstAuthor?.split(separator: " ").last.map(String.init),
                year: year,
                venue: venue,
                citationCount: citationCount
            )
        } catch {
            return nil
        }
    }

    private func yearFromPayload(_ payload: [String: JSONValue]) -> Int? {
        guard let y = payload["year"] else { return nil }
        switch y {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s)
        default: return nil
        }
    }
}

// MARK: - Models

struct OnlinePaperMeta {
    var title: String?
    var firstAuthor: String?
    var year: Int?
    var venue: String?
    var citationCount: Int?
}

enum CitationDirection {
    case reference
    case citedBy
}
