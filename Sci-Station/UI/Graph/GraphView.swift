import Foundation
import SwiftUI

struct GraphView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var centerPaperIndex: Int = 0
    @State private var seedItems: [CitationSeed] = []
    @State private var citesEdges: [GraphEdge] = []
    @State private var citedByEdges: [GraphEdge] = []
    @State private var nodeMap: [String: GraphNode] = [:]
    @State private var seedGraphNodes: [String: GraphNode] = [:]
    @State private var selectedNodeID: String?
    @State private var isLoading = false
    @State private var graphSource: CitationGraphSource = .local
    @State private var statusMessage: String?
    @State private var importStatusMessage: String?
    @State private var isImportingNodeID: String?
    @State private var isGraphOptionsPresented = false
    @State private var displayedNodesPerSide: Double = 25
    @State private var nodeVisualScale: Double = 0.90

    let workspace: ResearchWorkspace

    private static let maxNodesPerSide = 80
    private static let maxSeedCount = 6
    private static let seedStripHeight: CGFloat = 86

    private let inspireProvider = InspireMetadataProvider()

    private var localPapers: [Paper] { appModel.papers }

    private var nodeDisplayLimit: Int {
        min(Self.maxNodesPerSide, max(8, Int(displayedNodesPerSide.rounded())))
    }

    private var nodeScale: CGFloat {
        CGFloat(nodeVisualScale)
    }

    private var centerPaper: Paper? {
        guard !localPapers.isEmpty, centerPaperIndex < localPapers.count else { return nil }
        return localPapers[centerPaperIndex]
    }

    private var activeSeeds: [CitationSeed] {
        if !seedItems.isEmpty { return seedItems }
        return centerPaper.map { [CitationSeed(paper: $0)] } ?? []
    }

    private var orderedSeedNodes: [GraphNode] {
        activeSeeds.compactMap { seedGraphNodes[$0.nodeID] }
    }

    private var selectedNode: GraphNode? {
        guard let selectedNodeID else { return nil }
        return seedGraphNodes[selectedNodeID] ?? nodeMap[selectedNodeID]
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isLoading {
                loadingView
            } else if !activeSeeds.isEmpty {
                GeometryReader { geometry in
                    let detailWidth = selectedNode == nil ? 0 : min(320, max(240, geometry.size.width * 0.30))
                    HStack(spacing: 0) {
                        citationGraphContent(
                            size: CGSize(width: max(0, geometry.size.width - detailWidth), height: geometry.size.height)
                        )
                        if let selectedNode {
                            Divider()
                            nodeDetailPanel(selectedNode)
                                .frame(width: detailWidth)
                        }
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadCitations() }
        .onChange(of: centerPaperIndex) { _, _ in
            guard seedItems.isEmpty else { return }
            Task { await loadCitations() }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(graphSource == .inspire ? "Fetching citation metadata from INSPIRE..." : "Loading citation graph...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Citation Graph")
                .font(.headline)

            sourceBadge

            Spacer()

            Button {
                isGraphOptionsPresented.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isGraphOptionsPresented, arrowEdge: .bottom) {
                graphOptionsPopover
            }
            .help("Graph options")

            if !localPapers.isEmpty {
                HStack(spacing: 6) {
                    Button(action: { if centerPaperIndex > 0 { centerPaperIndex -= 1 } }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(centerPaperIndex == 0)
                    .buttonStyle(.plain)
                    .help("Previous library paper")

                    Text("\(centerPaperIndex + 1) / \(localPapers.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button(action: { if centerPaperIndex < localPapers.count - 1 { centerPaperIndex += 1 } }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(centerPaperIndex >= localPapers.count - 1)
                    .buttonStyle(.plain)
                    .help("Next library paper")

                    Menu {
                        ForEach(Array(localPapers.enumerated()), id: \.element.id) { index, paper in
                            Button(paper.displayTitle) { centerPaperIndex = index }
                        }
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                    .help("Choose center paper")
                }

                Menu {
                    ForEach(localPapers, id: \.id) { paper in
                        Button(paper.displayTitle) { addSeed(CitationSeed(paper: paper)) }
                            .disabled(activeSeeds.contains { $0.localPaperID == paper.id } || activeSeeds.count >= Self.maxSeedCount)
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .disabled(activeSeeds.count >= Self.maxSeedCount)
                .help("Add seed paper")

                if !seedItems.isEmpty {
                    Button {
                        seedItems.removeAll()
                        selectedNodeID = nil
                        Task { await loadCitations() }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset seeds")
                }
            }

            Text("Seeds: \(activeSeeds.count) · Nodes: \(nodeDisplayLimit) · References: \(citesEdges.count) · Cited-by: \(citedByEdges.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button {
                Task { await loadCitations() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload citation graph")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var graphOptionsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Graph Options")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Nodes per side")
                    Spacer()
                    Text("\(nodeDisplayLimit)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $displayedNodesPerSide, in: 8...Double(Self.maxNodesPerSide), step: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Node size")
                    Spacer()
                    Text("\(Int((nodeVisualScale * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $nodeVisualScale, in: 0.65...1.15, step: 0.05)
            }

            Button {
                Task { await loadCitations() }
            } label: {
                Label("Reload with Limit", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)
        }
        .font(.caption)
        .padding(16)
        .frame(width: 280)
    }

    private var sourceBadge: some View {
        Label(graphSource.title, systemImage: graphSource.systemImage)
            .font(.caption)
            .foregroundStyle(graphSource.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(graphSource.color.opacity(0.10))
            )
    }

    private func citationGraphContent(size: CGSize) -> some View {
        let referenceItems = plotItems(for: .reference)
        let citedByItems = plotItems(for: .citedBy)
        let referenceMetrics = plotMetrics(for: referenceItems)
        let citedByMetrics = plotMetrics(for: citedByItems)
        let seedNodes = orderedSeedNodes
        let seedPositions = Dictionary(uniqueKeysWithValues: seedNodes.enumerated().map { index, node in
            (node.id, seedPosition(index: index, total: seedNodes.count, canvasSize: size))
        })
        let referencePositions = Dictionary(uniqueKeysWithValues: referenceItems.enumerated().map { index, item in
            (item.nodeID, plotPosition(for: item, index: index, metrics: referenceMetrics, side: .reference, canvasSize: size))
        })
        let citedByPositions = Dictionary(uniqueKeysWithValues: citedByItems.enumerated().map { index, item in
            (item.nodeID, plotPosition(for: item, index: index, metrics: citedByMetrics, side: .citedBy, canvasSize: size))
        })

        return ZStack {
            Canvas { context, canvasSize in
                drawPlotBand(
                    context: &context,
                    rect: plotRect(for: .reference, canvasSize: canvasSize),
                    metrics: referenceMetrics,
                    title: "References (\(citesEdges.count))",
                    color: .blue
                )
                drawPlotBand(
                    context: &context,
                    rect: plotRect(for: .citedBy, canvasSize: canvasSize),
                    metrics: citedByMetrics,
                    title: "Cited-by (\(citedByEdges.count))",
                    color: .orange
                )

                for item in referenceItems {
                    guard let from = seedPositions[item.edge.from], let to = referencePositions[item.nodeID] else { continue }
                    drawEdge(context: &context, from: from, to: to, color: .blue)
                }

                for item in citedByItems {
                    guard let from = citedByPositions[item.nodeID], let to = seedPositions[item.edge.to] else { continue }
                    drawEdge(context: &context, from: from, to: to, color: .orange)
                }
            }

            ForEach(seedNodes, id: \.id) { node in
                if let position = seedPositions[node.id] {
                    seedNodeView(node, isSelected: selectedNodeID == node.id)
                        .position(position)
                        .onTapGesture { selectedNodeID = node.id }
                }
            }

            ForEach(referenceItems) { item in
                if let position = referencePositions[item.nodeID] {
                    citationNodeView(node: item.node, direction: .reference, isSelected: selectedNodeID == item.nodeID)
                        .position(position)
                        .onTapGesture { selectedNodeID = item.nodeID }
                }
            }

            ForEach(citedByItems) { item in
                if let position = citedByPositions[item.nodeID] {
                    citationNodeView(node: item.node, direction: .citedBy, isSelected: selectedNodeID == item.nodeID)
                        .position(position)
                        .onTapGesture { selectedNodeID = item.nodeID }
                }
            }

            VStack {
                Spacer()
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.bottom, Self.seedStripHeight + 4)
                }
                seedStrip
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var seedStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Seeds (\(activeSeeds.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(activeSeeds) { seed in
                        seedChip(seed)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: Self.seedStripHeight, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func seedChip(_ seed: CitationSeed) -> some View {
        let node = seedGraphNodes[seed.nodeID]
        return HStack(spacing: 8) {
            Circle()
                .fill(Color.purple.opacity(0.75))
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(seed.shortTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(seedSubtitle(for: node))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !seedItems.isEmpty {
                Button {
                    removeSeed(seed)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Remove seed")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 260, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.purple.opacity(0.20), lineWidth: 1)
        )
        .onTapGesture { selectedNodeID = seed.nodeID }
    }

    private func plotItems(for direction: CitationDirection) -> [CitationPlotItem] {
        let seedIDs = Set(seedGraphNodes.keys)
        let edges = direction == .reference ? citesEdges : citedByEdges
        var seenNodeIDs: Set<String> = []
        var items: [CitationPlotItem] = []

        for edge in edges {
            let nodeID = direction == .reference ? edge.to : edge.from
            guard !seedIDs.contains(nodeID), !seenNodeIDs.contains(nodeID), let node = nodeMap[nodeID] else { continue }
            seenNodeIDs.insert(nodeID)
            items.append(CitationPlotItem(direction: direction, edge: edge, nodeID: nodeID, node: node))
        }

        return Array(items.sorted(by: comparePlotItems).prefix(nodeDisplayLimit))
    }

    private func comparePlotItems(_ lhs: CitationPlotItem, _ rhs: CitationPlotItem) -> Bool {
        let leftYear = yearValue(for: lhs.node) ?? Int.max
        let rightYear = yearValue(for: rhs.node) ?? Int.max
        if leftYear != rightYear { return leftYear < rightYear }

        let leftCitations = citationCount(for: lhs.node) ?? -1
        let rightCitations = citationCount(for: rhs.node) ?? -1
        if leftCitations != rightCitations { return leftCitations > rightCitations }

        return lhs.node.displayName.localizedCaseInsensitiveCompare(rhs.node.displayName) == .orderedAscending
    }

    private func plotMetrics(for items: [CitationPlotItem]) -> CitationPlotMetrics {
        let currentYear = Calendar.current.component(.year, from: Date())
        let years = items.compactMap { yearValue(for: $0.node) }
        let rawMinYear = years.min() ?? currentYear - 5
        let rawMaxYear = years.max() ?? currentYear
        let minYear = rawMinYear == rawMaxYear ? rawMinYear - 1 : rawMinYear
        let maxYear = rawMinYear == rawMaxYear ? rawMaxYear + 1 : rawMaxYear
        let citationCounts = items.compactMap { citationCount(for: $0.node) }
        let minCitations = max(0, citationCounts.min() ?? 0)
        let maxCitations = max(minCitations, citationCounts.max() ?? minCitations)
        return CitationPlotMetrics(minYear: minYear, maxYear: maxYear, minCitations: minCitations, maxCitations: maxCitations)
    }

    private func plotRect(for direction: CitationDirection, canvasSize: CGSize) -> CGRect {
        let marginX: CGFloat = 24
        let centerGap: CGFloat = min(116, max(72, canvasSize.width * 0.13))
        let top: CGFloat = 58
        let bottom: CGFloat = Self.seedStripHeight + 28
        let availableWidth = max(180, canvasSize.width - marginX * 2 - centerGap)
        let width = availableWidth / 2
        let height = max(120, canvasSize.height - top - bottom)

        switch direction {
        case .reference:
            return CGRect(x: marginX, y: top, width: width, height: height)
        case .citedBy:
            return CGRect(x: canvasSize.width - marginX - width, y: top, width: width, height: height)
        }
    }

    private func plotPosition(
        for item: CitationPlotItem,
        index: Int,
        metrics: CitationPlotMetrics,
        side: CitationDirection,
        canvasSize: CGSize
    ) -> CGPoint {
        let rect = plotRect(for: side, canvasSize: canvasSize)
        let year = yearValue(for: item.node) ?? metrics.midYear
        let yearRange = max(1, metrics.maxYear - metrics.minYear)
        let xNormalized = CGFloat(year - metrics.minYear) / CGFloat(yearRange)
        let citations = citationCount(for: item.node) ?? metrics.minCitations
        let yNormalized = citationNormalizedValue(citations, minCitations: metrics.minCitations, maxCitations: metrics.maxCitations)
        let baseX = rect.minX + xNormalized * rect.width
        let baseY = rect.maxY - yNormalized * rect.height
        let jitter = deterministicJitter(for: item.nodeID, index: index)
        let horizontalInset = max(18, 46 * nodeScale)
        let verticalInset = max(10, 13 * nodeScale)
        return CGPoint(
            x: min(max(baseX + jitter.x, rect.minX + horizontalInset), rect.maxX - horizontalInset),
            y: min(max(baseY + jitter.y, rect.minY + verticalInset), rect.maxY - verticalInset)
        )
    }

    private func seedPosition(index: Int, total: Int, canvasSize: CGSize) -> CGPoint {
        let availableHeight = max(80, canvasSize.height - Self.seedStripHeight - 130)
        let spacing = min(58, availableHeight / CGFloat(max(total, 1)))
        let startY = canvasSize.height / 2 - spacing * CGFloat(max(total - 1, 0)) / 2
        return CGPoint(x: canvasSize.width / 2, y: startY + spacing * CGFloat(index))
    }

    private func deterministicJitter(for id: String, index: Int) -> CGPoint {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let x = CGFloat(Int(hash % 17) - 8)
        let y = CGFloat(Int((hash >> 8) % 13) - 6)
        let rowOffset = CGFloat((index % 3) - 1) * 4
        return CGPoint(x: x, y: y + rowOffset)
    }

    private func drawPlotBand(
        context: inout GraphicsContext,
        rect: CGRect,
        metrics: CitationPlotMetrics,
        title: String,
        color: Color
    ) {
        context.fill(Path(roundedRect: rect.insetBy(dx: -10, dy: -16), cornerRadius: 8), with: .color(color.opacity(0.055)))
        context.stroke(Path(rect), with: .color(Color.secondary.opacity(0.18)), lineWidth: 1)

        for year in metrics.yearTicks {
            let x = rect.minX + CGFloat(year - metrics.minYear) / CGFloat(max(1, metrics.maxYear - metrics.minYear)) * rect.width
            var path = Path()
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.stroke(path, with: .color(Color.secondary.opacity(0.10)), lineWidth: 1)
            context.draw(
                Text(String(year)).font(.caption2).foregroundStyle(.secondary),
                at: CGPoint(x: x, y: rect.maxY + 14),
                anchor: .center
            )
        }

        for citation in metrics.citationTicks {
            let y = rect.maxY - citationNormalizedValue(citation, minCitations: metrics.minCitations, maxCitations: metrics.maxCitations) * rect.height
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.stroke(path, with: .color(Color.secondary.opacity(0.10)), lineWidth: 1)
            context.draw(
                Text(shortCitationLabel(citation)).font(.caption2).foregroundStyle(.secondary),
                at: CGPoint(x: rect.maxX + 8, y: y),
                anchor: .leading
            )
        }

        context.draw(
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color),
            at: CGPoint(x: rect.midX, y: rect.minY - 22),
            anchor: .center
        )
        context.draw(
            Text("Year").font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: rect.midX, y: rect.maxY + 31),
            anchor: .center
        )
        context.draw(
            Text("Citations (log)").font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: rect.minX - 4, y: rect.minY - 8),
            anchor: .trailing
        )
    }

    private func drawEdge(context: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        var path = Path()
        path.move(to: from)
        let controlX = (from.x + to.x) / 2
        path.addCurve(
            to: to,
            control1: CGPoint(x: controlX, y: from.y),
            control2: CGPoint(x: controlX, y: to.y)
        )
        context.stroke(path, with: .color(color.opacity(0.24)), lineWidth: 1)
    }

    private func seedNodeView(_ node: GraphNode, isSelected: Bool) -> some View {
        HStack(spacing: max(4, 6 * nodeScale)) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.16))
                    .frame(width: max(20, 28 * nodeScale), height: max(20, 28 * nodeScale))
                Circle()
                    .fill(Color.purple.opacity(0.82))
                    .frame(width: max(12, 16 * nodeScale), height: max(12, 16 * nodeScale))
            }
            Text(nodeLabel(node: node))
                .font(.system(size: max(8, 10 * nodeScale), weight: .semibold))
                .lineLimit(1)
                .frame(width: max(72, 104 * nodeScale), alignment: .leading)
        }
        .padding(.horizontal, max(6, 8 * nodeScale))
        .padding(.vertical, max(4, 5 * nodeScale))
        .background(
            Capsule()
                .fill(isSelected ? Color.purple.opacity(0.12) : Color(nsColor: .windowBackgroundColor).opacity(0.82))
        )
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.purple.opacity(0.58) : Color.purple.opacity(0.18), lineWidth: 1)
        )
        .help(nodeTooltip(for: node))
    }

    private func citationNodeView(node: GraphNode, direction: CitationDirection, isSelected: Bool) -> some View {
        let isExternal = isExternalNode(node)
        let accent = nodeColor(for: node, direction: direction)
        let label = nodeLabel(node: node)
        let diameter = nodeBubbleDiameter(for: node) * nodeScale
        let labelWidth = max(58, 78 * nodeScale)
        let labelFontSize = max(7, 9 * nodeScale)

        return HStack(spacing: max(3, 4 * nodeScale)) {
            ZStack {
                Circle()
                    .fill(isExternal ? accent.opacity(0.62) : accent.opacity(0.86))
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? accent.opacity(0.95) : Color.white.opacity(0.60), lineWidth: isSelected ? 2 : 1)
                    )
                if !isExternal {
                    Image(systemName: "checkmark")
                        .font(.system(size: max(5, 6 * nodeScale), weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: max(14, 20 * nodeScale), height: max(14, 20 * nodeScale))

            Text(label)
                .font(.system(size: labelFontSize, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isExternal ? .secondary : accent)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
        }
        .padding(.horizontal, isSelected ? 5 : 0)
        .padding(.vertical, isSelected ? 3 : 0)
        .background {
            if isSelected {
                Capsule().fill(accent.opacity(0.12))
            }
        }
        .contentShape(Rectangle())
        .help(nodeTooltip(for: node))
    }

    private func nodeBubbleDiameter(for node: GraphNode) -> CGFloat {
        let citations = Double(citationCount(for: node) ?? 0)
        return 7 + min(12, CGFloat(log10(citations + 1)) * 4)
    }

    private func nodeColor(for node: GraphNode, direction: CitationDirection) -> Color {
        if !isExternalNode(node) { return .green }
        return direction == .reference ? .blue : .orange
    }

    private func nodeLabel(node: GraphNode) -> String {
        let payload = node.payload.objectValue
        let author = payload?["first_author"]?.stringValue
            ?? payload?["citekey"]?.stringValue?.prefix(12).description
            ?? String(node.displayName.prefix(15))
        let trimmedAuthor = author.replacingOccurrences(of: " et al.", with: "")
        let base = trimmedAuthor.count > 13 ? String(trimmedAuthor.prefix(12)) + "." : trimmedAuthor
        let label = yearValue(for: node).map { "\(base) \($0)" } ?? base
        return label.count > 22 ? String(label.prefix(19)) + "..." : label
    }

    private func citationCountText(for node: GraphNode?) -> String? {
        guard let node, let count = citationCount(for: node) else { return nil }
        return "\(count) citations"
    }

    private func nodeTooltip(for node: GraphNode) -> String {
        var parts = [node.displayName]
        if let year = yearValue(for: node) { parts.append("Year: \(year)") }
        if let citations = citationCountText(for: node) { parts.append(citations) }
        if !isExternalNode(node) { parts.append("In local library") }
        return parts.joined(separator: "\n")
    }

    private func seedSubtitle(for node: GraphNode?) -> String {
        guard let node else { return "pending" }
        let refs = stringValue(node.payload.objectValue?["reference_count"]) ?? "-"
        let cites = stringValue(node.payload.objectValue?["citation_count"]) ?? "-"
        return "refs: \(refs) · cited-by: \(cites)"
    }

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

    private func loadCitations() async {
        let seeds = activeSeeds
        guard !seeds.isEmpty else { return }

        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        let localSnapshot = await appModel.graphReadModel()?.snapshot()
        var mergedSeedNodes: [String: GraphNode] = [:]
        var mergedNodes: [String: GraphNode] = [:]
        var outgoingEdges: [String: GraphEdge] = [:]
        var incomingEdges: [String: GraphEdge] = [:]
        var usedInspire = false
        var failedInspireCount = 0

        for seed in seeds {
            if let result = await inspireCitationResult(for: seed) {
                usedInspire = true
                merge(result, seedNodes: &mergedSeedNodes, nodes: &mergedNodes, outgoing: &outgoingEdges, incoming: &incomingEdges)
            } else if let result = localSnapshot.flatMap({ localCitationResult(for: seed, snapshot: $0) }) {
                failedInspireCount += 1
                merge(result, seedNodes: &mergedSeedNodes, nodes: &mergedNodes, outgoing: &outgoingEdges, incoming: &incomingEdges)
            } else {
                failedInspireCount += 1
            }
        }

        for seedID in mergedSeedNodes.keys {
            mergedNodes.removeValue(forKey: seedID)
        }

        seedGraphNodes = mergedSeedNodes
        nodeMap = mergedNodes
        citesEdges = sortedEdges(Array(outgoingEdges.values), direction: .reference, nodes: mergedNodes)
        citedByEdges = sortedEdges(Array(incomingEdges.values), direction: .citedBy, nodes: mergedNodes)
        graphSource = usedInspire ? .inspire : .local

        if failedInspireCount > 0 {
            statusMessage = usedInspire
                ? "Some seeds could not be resolved on INSPIRE; local edges are shown where available."
                : "No INSPIRE records found; showing local citation edges."
        }

        if let selectedNodeID, mergedSeedNodes[selectedNodeID] != nil || mergedNodes[selectedNodeID] != nil {
            return
        }
        selectedNodeID = seeds.compactMap { mergedSeedNodes[$0.nodeID]?.id }.first ?? mergedNodes.keys.sorted().first
    }

    private func inspireCitationResult(for seed: CitationSeed) async -> CitationSeedResult? {
        guard let recordID = await resolveInspireRecordID(for: seed) else { return nil }

        do {
            let graph = try await inspireProvider.fetchCitationGraph(for: recordID, limit: nodeDisplayLimit)
            return makeInspireResult(seed: seed, graph: graph, recordID: recordID)
        } catch {
            return nil
        }
    }

    private func resolveInspireRecordID(for seed: CitationSeed) async -> String? {
        if let inspireID = seed.inspireID {
            return PaperIdentityGenerator.normalizedInspire(inspireID) ?? inspireID
        }

        if let paper = paper(for: seed) {
            if let recordID = PaperIdentityGenerator.normalizedInspire(paper.inspireID) {
                return recordID
            }
            if paper.resolvedGraphNodeID.hasPrefix("inspire:") {
                return PaperIdentityGenerator.normalizedInspire(paper.resolvedGraphNodeID)
            }
            return try? await inspireProvider.resolveRecordID(doi: paper.doi, arxiv: paper.arxiv)
        }

        return try? await inspireProvider.resolveRecordID(doi: seed.doi, arxiv: seed.arxiv)
    }

    private func makeInspireResult(seed: CitationSeed, graph: InspireCitationGraph, recordID: String) -> CitationSeedResult {
        let now = Date()
        let seedNode = seedGraphNode(for: seed, recordID: recordID, supplement: graph.center, now: now)
        var nodes: [String: GraphNode] = [:]
        var outgoing: [GraphEdge] = []
        var incoming: [GraphEdge] = []

        for paper in graph.references {
            let node = graphNode(for: paper, now: now)
            nodes[node.id] = node
            outgoing.append(GraphEdge(
                kind: .cites,
                from: seedNode.id,
                to: node.id,
                payload: .object(["source": .string("inspire"), "inspire_id": .string(paper.inspireID)]),
                createdAt: now,
                updatedAt: now,
                sourceHash: "inspire:\(recordID)",
                lastIndexedAt: now
            ))
        }

        for paper in graph.citedBy {
            let node = graphNode(for: paper, now: now)
            nodes[node.id] = node
            incoming.append(GraphEdge(
                kind: .cites,
                from: node.id,
                to: seedNode.id,
                payload: .object(["source": .string("inspire"), "inspire_id": .string(paper.inspireID)]),
                createdAt: now,
                updatedAt: now,
                sourceHash: "inspire:\(recordID)",
                lastIndexedAt: now
            ))
        }

        return CitationSeedResult(seedNode: seedNode, nodes: nodes, outgoing: outgoing, incoming: incoming)
    }

    private func localCitationResult(for seed: CitationSeed, snapshot: GraphSnapshot) -> CitationSeedResult? {
        guard let paper = paper(for: seed) else { return nil }

        let paperNodeID = "paper:\(paper.resolvedGraphNodeID)"
        let seedNode = snapshot.nodes[paperNodeID] ?? seedGraphNode(for: seed, recordID: nil, supplement: nil, now: Date())
        var nodes: [String: GraphNode] = [:]
        var outgoing: [GraphEdge] = []
        var incoming: [GraphEdge] = []

        for (_, edge) in snapshot.edges where edge.kind == .cites {
            if edge.from == paperNodeID {
                outgoing.append(edge)
                if let target = snapshot.nodes[edge.to] { nodes[edge.to] = target }
            } else if edge.to == paperNodeID {
                incoming.append(edge)
                if let source = snapshot.nodes[edge.from] { nodes[edge.from] = source }
            }
        }

        return CitationSeedResult(seedNode: seedNode, nodes: nodes, outgoing: outgoing, incoming: incoming)
    }

    private func merge(
        _ result: CitationSeedResult,
        seedNodes: inout [String: GraphNode],
        nodes: inout [String: GraphNode],
        outgoing: inout [String: GraphEdge],
        incoming: inout [String: GraphEdge]
    ) {
        seedNodes[result.seedNode.id] = result.seedNode
        for (id, node) in result.nodes where seedNodes[id] == nil {
            nodes[id] = node
        }
        for edge in result.outgoing { outgoing[edge.id] = edge }
        for edge in result.incoming { incoming[edge.id] = edge }
    }

    private func sortedEdges(_ edges: [GraphEdge], direction: CitationDirection, nodes: [String: GraphNode]) -> [GraphEdge] {
        edges.sorted { lhs, rhs in
            let leftNode = nodes[direction == .reference ? lhs.to : lhs.from]
            let rightNode = nodes[direction == .reference ? rhs.to : rhs.from]
            let leftYear = leftNode.flatMap(yearValue) ?? Int.max
            let rightYear = rightNode.flatMap(yearValue) ?? Int.max
            if leftYear != rightYear { return leftYear < rightYear }
            let leftCitations = leftNode.flatMap(citationCount) ?? -1
            let rightCitations = rightNode.flatMap(citationCount) ?? -1
            return leftCitations > rightCitations
        }
    }

    private func seedGraphNode(for seed: CitationSeed, recordID: String?, supplement: InspireCitationPaper?, now: Date) -> GraphNode {
        if let paper = paper(for: seed) {
            return seedGraphNode(for: paper, recordID: recordID, supplement: supplement, now: now)
        }

        if let supplement {
            let node = graphNode(for: supplement, now: now)
            return GraphNode(
                id: seed.nodeID,
                kind: .paper,
                displayName: node.displayName,
                payload: node.payload,
                createdAt: node.createdAt,
                updatedAt: node.updatedAt,
                sourceHash: node.sourceHash,
                lastIndexedAt: now
            )
        }

        return GraphNode(
            id: seed.nodeID,
            kind: .paper,
            displayName: seed.title,
            payload: .object([
                "is_external": .bool(true),
                "source": .string("inspire"),
                "inspire_id": recordID.map { .string($0) } ?? .null,
                "doi": seed.doi.map { .string($0) } ?? .null,
                "arxiv": seed.arxiv.map { .string($0) } ?? .null,
                "title": .string(seed.title),
                "first_author": .string(seed.shortTitle)
            ]),
            createdAt: now,
            updatedAt: now,
            sourceHash: nil,
            lastIndexedAt: now
        )
    }

    private func seedGraphNode(for paper: Paper, recordID: String?, supplement: InspireCitationPaper?, now: Date) -> GraphNode {
        var payload: [String: JSONValue] = [
            "is_external": .bool(false),
            "paper_id": .string(paper.id),
            "citekey": .string(paper.citekey),
            "status": .string(paper.status.rawValue),
            "title": .string(paper.title),
            "first_author": .string(paper.authors.first?.split(separator: " ").last.map(String.init) ?? "Unknown")
        ]
        payload["year"] = paper.year.map { .number(String($0)) } ?? supplement?.year.map { .number(String($0)) } ?? .null
        payload["doi"] = paper.doi.map { .string($0) } ?? supplement?.doi.map { .string($0) } ?? .null
        payload["arxiv"] = paper.arxiv.map { .string($0) } ?? supplement?.arxiv.map { .string($0) } ?? .null
        payload["inspire_id"] = recordID.map { .string($0) } ?? supplement?.inspireID.nilIfEmpty.map { .string($0) } ?? .null
        payload["venue"] = paper.publicationDisplay == "-" ? supplement?.venue.map { .string($0) } ?? .null : .string(paper.publicationDisplay)
        payload["citation_count"] = supplement?.citationCount.map { .number(String($0)) } ?? .null
        payload["reference_count"] = supplement?.referenceCount.map { .number(String($0)) } ?? .null

        return GraphNode(
            id: "paper:\(paper.resolvedGraphNodeID)",
            kind: .paper,
            displayName: paper.title,
            payload: .object(payload),
            createdAt: paper.createdAt,
            updatedAt: paper.updatedAt,
            sourceHash: nil,
            lastIndexedAt: now
        )
    }

    private func graphNode(for paper: InspireCitationPaper, now: Date) -> GraphNode {
        let localPaper = localPaper(matching: paper)
        let nodeID = localPaper.map { "paper:\($0.resolvedGraphNodeID)" } ?? "paper:external:inspire:\(paper.inspireID)"
        return GraphNode(
            id: nodeID,
            kind: .paper,
            displayName: localPaper?.title ?? paper.title,
            payload: .object(payload(for: paper, localPaper: localPaper)),
            createdAt: localPaper?.createdAt ?? now,
            updatedAt: localPaper?.updatedAt ?? now,
            sourceHash: nil,
            lastIndexedAt: now
        )
    }

    private func payload(for paper: InspireCitationPaper, localPaper: Paper?) -> [String: JSONValue] {
        var payload: [String: JSONValue] = [
            "is_external": .bool(localPaper == nil),
            "source": .string("inspire"),
            "inspire_id": .string(paper.inspireID),
            "title": .string(paper.title),
            "authors": .array(paper.authors.map { .string($0) }),
            "first_author": .string(paper.firstAuthorLastName ?? "Unknown"),
            "url": .string(paper.url ?? "https://inspirehep.net/literature/\(paper.inspireID)")
        ]
        payload["year"] = paper.year.map { .number(String($0)) } ?? .null
        payload["venue"] = paper.venue.map { .string($0) } ?? .null
        payload["doi"] = paper.doi.map { .string($0) } ?? .null
        payload["arxiv"] = paper.arxiv.map { .string($0) } ?? .null
        payload["abstract"] = paper.abstract.map { .string($0) } ?? .null
        payload["categories"] = .array(paper.categories.map { .string($0) })
        payload["citation_count"] = paper.citationCount.map { .number(String($0)) } ?? .null
        payload["reference_count"] = paper.referenceCount.map { .number(String($0)) } ?? .null
        if let localPaper {
            payload["paper_id"] = .string(localPaper.id)
            payload["citekey"] = .string(localPaper.citekey)
            payload["status"] = .string(localPaper.status.rawValue)
        }
        return payload
    }

    private func localPaper(matching paper: InspireCitationPaper) -> Paper? {
        let inspire = PaperIdentityGenerator.normalizedInspire(paper.inspireID)
        let doi = PaperIdentityGenerator.normalizedDOI(paper.doi)
        let arxiv = PaperIdentityGenerator.normalizedArxiv(paper.arxiv)

        return localPapers.first { candidate in
            if let inspire,
               PaperIdentityGenerator.normalizedInspire(candidate.inspireID) == inspire || candidate.resolvedGraphNodeID == "inspire:\(inspire)" {
                return true
            }
            if let doi, PaperIdentityGenerator.normalizedDOI(candidate.doi) == doi {
                return true
            }
            if let arxiv, PaperIdentityGenerator.normalizedArxiv(candidate.arxiv) == arxiv {
                return true
            }
            return false
        }
    }

    private func addSeed(_ seed: CitationSeed) {
        if seedItems.isEmpty, let centerPaper {
            seedItems = [CitationSeed(paper: centerPaper)]
        }
        guard !seedItems.contains(seed), seedItems.count < Self.maxSeedCount else { return }
        seedItems.append(seed)
        selectedNodeID = seed.nodeID
        Task { await loadCitations() }
    }

    private func removeSeed(_ seed: CitationSeed) {
        seedItems.removeAll { $0 == seed }
        selectedNodeID = nil
        Task { await loadCitations() }
    }

    private func paper(for seed: CitationSeed) -> Paper? {
        guard let localPaperID = seed.localPaperID else { return nil }
        return localPapers.first { $0.id == localPaperID }
    }

    private func nodeDetailPanel(_ node: GraphNode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isExternalNode(node) ? "network" : "doc.text.fill")
                        .foregroundStyle(isExternalNode(node) ? .secondary : Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.displayName)
                            .font(.headline)
                            .lineLimit(4)
                        Text(isExternalNode(node) ? "INSPIRE record" : "In library")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Metadata")
                        .font(.subheadline.weight(.semibold))
                    ForEach(metadataRows(for: node), id: \.0) { key, value in
                        HStack(alignment: .top, spacing: 8) {
                            Text(key)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 84, alignment: .leading)
                            Text(value)
                                .font(.caption)
                                .textSelection(.enabled)
                                .lineLimit(4)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.subheadline.weight(.semibold))

                    if let seed = CitationSeed(node: node), !activeSeeds.contains(seed) {
                        Button {
                            addSeed(seed)
                        } label: {
                            Label("Add as Seed", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(activeSeeds.count >= Self.maxSeedCount)
                    }

                    if let paperID = localPaperID(for: node) {
                        Button {
                            appModel.handleGraphNodeAction(.openPaper(paperID: paperID))
                        } label: {
                            Label("Open Paper", systemImage: "doc.text")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if let identifier = importIdentifier(for: node) {
                        Button {
                            Task { await importNode(node, identifier: identifier) }
                        } label: {
                            HStack {
                                if isImportingNodeID == node.id {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "tray.and.arrow.down")
                                }
                                Text(isImportingNodeID == node.id ? "Adding..." : "Add to Library")
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isImportingNodeID != nil)
                    }

                    if let urlString = node.payload.objectValue?["url"]?.stringValue,
                       let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label("Open INSPIRE", systemImage: "safari")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let importStatusMessage {
                        Text(importStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func importNode(_ node: GraphNode, identifier: String) async {
        isImportingNodeID = node.id
        importStatusMessage = nil
        defer { isImportingNodeID = nil }

        do {
            let paper = try await appModel.importGraphExternalPaper(from: identifier)
            selectedNodeID = "paper:\(paper.resolvedGraphNodeID)"
            await loadCitations()
            selectedNodeID = "paper:\(paper.resolvedGraphNodeID)"
            importStatusMessage = "Added \"\(paper.displayTitle)\" to library."
        } catch {
            importStatusMessage = error.localizedDescription
        }
    }

    private func metadataRows(for node: GraphNode) -> [(String, String)] {
        let payload = node.payload.objectValue ?? [:]
        var rows: [(String, String)] = []
        appendRow("Authors", authorsText(from: payload), to: &rows)
        appendRow("Year", stringValue(payload["year"]), to: &rows)
        appendRow("Venue", stringValue(payload["venue"]), to: &rows)
        appendRow("DOI", stringValue(payload["doi"]), to: &rows)
        appendRow("arXiv", stringValue(payload["arxiv"]), to: &rows)
        appendRow("INSPIRE", stringValue(payload["inspire_id"]), to: &rows)
        appendRow("Citations", stringValue(payload["citation_count"]), to: &rows)
        appendRow("References", stringValue(payload["reference_count"]), to: &rows)
        appendRow("Status", stringValue(payload["status"]), to: &rows)
        return rows
    }

    private func appendRow(_ key: String, _ value: String?, to rows: inout [(String, String)]) {
        guard let value, !value.isEmpty, value != "-" else { return }
        rows.append((key, value))
    }

    private func authorsText(from payload: [String: JSONValue]) -> String? {
        if let authors = payload["authors"]?.arrayValue?.compactMap(\.stringValue), !authors.isEmpty {
            return authors.prefix(4).joined(separator: ", ") + (authors.count > 4 ? " et al." : "")
        }
        return payload["first_author"]?.stringValue
    }

    private func importIdentifier(for node: GraphNode) -> String? {
        guard isExternalNode(node), let payload = node.payload.objectValue else { return nil }
        if let inspireID = payload["inspire_id"]?.stringValue, !inspireID.isEmpty {
            return "inspire:\(inspireID)"
        }
        if let doi = payload["doi"]?.stringValue, !doi.isEmpty {
            return doi
        }
        if let arxiv = payload["arxiv"]?.stringValue, !arxiv.isEmpty {
            return "arXiv:\(arxiv)"
        }
        return nil
    }

    private func localPaperID(for node: GraphNode) -> String? {
        if let paperID = node.payload.objectValue?["paper_id"]?.stringValue {
            return paperID
        }
        guard node.id.hasPrefix("paper:") else { return nil }
        let stableID = String(node.id.dropFirst("paper:".count))
        return localPapers.first { $0.id == stableID || $0.resolvedGraphNodeID == stableID }?.id
    }

    private func yearValue(for node: GraphNode) -> Int? {
        guard let value = node.payload.objectValue?["year"] else { return nil }
        switch value {
        case .number(let value), .string(let value): return Int(value)
        default: return nil
        }
    }

    private func citationCount(for node: GraphNode) -> Int? {
        guard let value = node.payload.objectValue?["citation_count"] else { return nil }
        switch value {
        case .number(let value), .string(let value): return Int(value)
        default: return nil
        }
    }

    private func citationNormalizedValue(_ citations: Int, minCitations: Int, maxCitations: Int) -> CGFloat {
        guard maxCitations > minCitations else { return 0 }
        let lowerValue = log(Double(max(minCitations, 0)) + 1)
        let upperValue = log(Double(max(maxCitations, 0)) + 1)
        guard upperValue > lowerValue else { return 0 }

        let value = log(Double(max(citations, minCitations)) + 1)
        let normalized = (value - lowerValue) / (upperValue - lowerValue)
        return CGFloat(min(max(normalized, 0), 1))
    }

    private func shortCitationLabel(_ value: Int) -> String {
        if value >= 1_000 { return "\(value / 1_000)k" }
        return String(value)
    }

    private func isExternalNode(_ node: GraphNode?) -> Bool {
        node?.payload.objectValue?["is_external"] == .bool(true)
    }

    private func stringValue(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let value): return value.isEmpty ? nil : value
        case .number(let value): return value
        case .bool(let value): return value ? "Yes" : "No"
        case .null: return nil
        case .array, .object: return nil
        }
    }
}

private struct CitationSeed: Identifiable, Hashable {
    var id: String
    var title: String
    var localPaperID: Paper.ID?
    var graphNodeID: String?
    var inspireID: String?
    var doi: String?
    var arxiv: String?

    init(paper: Paper) {
        id = "local:\(paper.id)"
        title = paper.displayTitle
        localPaperID = paper.id
        graphNodeID = paper.resolvedGraphNodeID
        inspireID = PaperIdentityGenerator.normalizedInspire(paper.inspireID)
        doi = paper.doi
        arxiv = paper.arxiv
    }

    init?(node: GraphNode) {
        guard node.kind == .paper, let payload = node.payload.objectValue else { return nil }
        if let paperID = payload["paper_id"]?.stringValue {
            id = "local:\(paperID)"
            localPaperID = paperID
            if node.id.hasPrefix("paper:") {
                graphNodeID = String(node.id.dropFirst("paper:".count))
            }
        } else if let inspireID = payload["inspire_id"]?.stringValue, !inspireID.isEmpty {
            let normalized = PaperIdentityGenerator.normalizedInspire(inspireID) ?? inspireID
            id = "inspire:\(normalized)"
            self.inspireID = normalized
            localPaperID = nil
        } else {
            return nil
        }

        title = payload["title"]?.stringValue ?? node.displayName
        if inspireID == nil {
            inspireID = payload["inspire_id"]?.stringValue.flatMap(PaperIdentityGenerator.normalizedInspire)
        }
        doi = payload["doi"]?.stringValue
        arxiv = payload["arxiv"]?.stringValue
    }

    var nodeID: String {
        if let graphNodeID {
            return "paper:\(graphNodeID)"
        }
        if let inspireID, localPaperID == nil {
            return "paper:external:inspire:\(inspireID)"
        }
        if let localPaperID {
            return "paper:\(localPaperID)"
        }
        return id.replacingOccurrences(of: "local:", with: "paper:")
    }

    var shortTitle: String {
        title.count > 70 ? String(title.prefix(67)) + "..." : title
    }
}

private struct CitationSeedResult {
    var seedNode: GraphNode
    var nodes: [String: GraphNode]
    var outgoing: [GraphEdge]
    var incoming: [GraphEdge]
}

private struct CitationPlotItem: Identifiable {
    var id: String { "\(direction.rawValue):\(nodeID)" }
    var direction: CitationDirection
    var edge: GraphEdge
    var nodeID: String
    var node: GraphNode
}

private struct CitationPlotMetrics {
    var minYear: Int
    var maxYear: Int
    var minCitations: Int
    var maxCitations: Int

    var midYear: Int { (minYear + maxYear) / 2 }

    var yearTicks: [Int] { unique([minYear, midYear, maxYear]) }
    var citationTicks: [Int] {
        guard maxCitations > minCitations else { return [minCitations] }

        let lowerValue = log(Double(max(minCitations, 0)) + 1)
        let upperValue = log(Double(maxCitations) + 1)
        let tickCount = 4
        var ticks: [Int] = []

        for index in 0..<tickCount {
            let ratio = Double(index) / Double(tickCount - 1)
            let value = exp(lowerValue + (upperValue - lowerValue) * ratio) - 1
            ticks.append(Int(value.rounded()))
        }

        return unique([minCitations] + ticks + [maxCitations])
    }

    private func unique(_ values: [Int]) -> [Int] {
        var seen: Set<Int> = []
        var result: [Int] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

private enum CitationGraphSource {
    case inspire
    case local

    var title: String {
        switch self {
        case .inspire: return "INSPIRE"
        case .local: return "Local"
        }
    }

    var systemImage: String {
        switch self {
        case .inspire: return "network"
        case .local: return "externaldrive"
        }
    }

    var color: Color {
        switch self {
        case .inspire: return .purple
        case .local: return .secondary
        }
    }
}

private enum CitationDirection: String {
    case reference
    case citedBy = "cited_by"
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}