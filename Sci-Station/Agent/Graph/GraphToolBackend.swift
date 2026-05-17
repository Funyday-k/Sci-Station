import Foundation

public nonisolated enum GraphAgentTools {
    public static let findMissingCorePapers = "find_missing_core_papers"
    public static let generateReadingPath = "generate_reading_path"
    public static let detectStaleCitations = "detect_stale_citations"
    public static let findUnsupportedArtifactClaims = "find_unsupported_artifact_claims"
    public static let findStaleSavedArtifacts = "find_stale_saved_artifacts"
    public static let findMethodLineage = "find_method_lineage"
    public static let findBridgePapers = "find_bridge_papers"

    public static let allNames: Set<String> = [
        findMissingCorePapers,
        generateReadingPath,
        detectStaleCitations,
        findUnsupportedArtifactClaims,
        findStaleSavedArtifacts,
        findMethodLineage,
        findBridgePapers
    ]

    public static func makeDefaultTools(
        paperRepository: PaperRepository,
        debugEventLogger: AppDebugEventLogger? = nil
    ) -> [any AgentTool] {
        let backend = GraphToolBackend(
            repository: GraphRepository(debug: debugEventLogger),
            paperRepository: paperRepository,
            debugEventLogger: debugEventLogger
        )
        return [
            FindMissingCorePapersAgentTool(backend: backend),
            GenerateReadingPathAgentTool(backend: backend),
            DetectStaleCitationsAgentTool(backend: backend),
            FindUnsupportedArtifactClaimsAgentTool(backend: backend),
            FindStaleSavedArtifactsAgentTool(backend: backend),
            FindMethodLineageAgentTool(backend: backend),
            FindBridgePapersAgentTool(backend: backend)
        ]
    }
}

public actor GraphToolBackend {
    private let paperRepository: PaperRepository
    private let repository: GraphRepository?
    private let injectedReadModel: GraphReadModel?
    private let debugEventLogger: AppDebugEventLogger?
    private var openedRootURL: URL?

    public init(
        repository: GraphRepository = GraphRepository(),
        paperRepository: PaperRepository = PaperRepository(),
        debugEventLogger: AppDebugEventLogger? = nil
    ) {
        self.repository = repository
        self.injectedReadModel = nil
        self.paperRepository = paperRepository
        self.debugEventLogger = debugEventLogger
    }

    public init(
        readModel: GraphReadModel,
        paperRepository: PaperRepository = PaperRepository(),
        debugEventLogger: AppDebugEventLogger? = nil
    ) {
        self.repository = nil
        self.injectedReadModel = readModel
        self.paperRepository = paperRepository
        self.debugEventLogger = debugEventLogger
    }

    public func findMissingCorePapers(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let start = Date()
        let toolName = GraphAgentTools.findMissingCorePapers
        do {
            let arguments = try decodeGraphArguments(argumentsJSON)
            let environment = try await loadEnvironment(context: context)
            let projectID = stringArgument(arguments, keys: ["project_id", "projectID"]) ?? context.currentProjectID
            guard let projectID = projectID?.nilIfEmpty else {
                throw AgentError.invalidArguments("project_id is required when no project is selected")
            }
            let limit = clampedLimit(arguments, defaultValue: 10, maximum: 50)
            let minimumCitations = max(1, intArgument(arguments, keys: ["min_citations", "minCitations"], defaultValue: 1))
            let projectNodeID = normalizedProjectNodeID(projectID)
            let corePaperNodeIDs = environment.paperIndex.corePaperNodeIDs(projectID: projectID)
            var candidates: [String: MissingCorePaperCandidate] = [:]

            for edge in environment.snapshot.edges.values where edge.kind == .cites && corePaperNodeIDs.contains(edge.from) {
                guard let targetNode = environment.snapshot.nodes[edge.to], targetNode.kind == .paper else { continue }
                guard !belongsToProject(nodeID: edge.to, projectID: projectID, projectNodeID: projectNodeID, environment: environment) else { continue }
                var candidate = candidates[edge.to] ?? MissingCorePaperCandidate(nodeID: edge.to, citingCorePaperIDs: [])
                candidate.citingCorePaperIDs.insert(edge.from)
                candidates[edge.to] = candidate
            }

            let ranked = candidates.values
                .filter { $0.citingCorePaperIDs.count >= minimumCitations }
                .sorted { first, second in
                    if first.citingCorePaperIDs.count != second.citingCorePaperIDs.count {
                        return first.citingCorePaperIDs.count > second.citingCorePaperIDs.count
                    }
                    let firstName = environment.snapshot.nodes[first.nodeID]?.displayName ?? first.nodeID
                    let secondName = environment.snapshot.nodes[second.nodeID]?.displayName ?? second.nodeID
                    return firstName.localizedStandardCompare(secondName) == .orderedAscending
                }
            let selected = Array(ranked.prefix(limit))
            let wasTruncated = ranked.count > selected.count
            let rows = selected.map { candidate -> JSONValue in
                let node = environment.snapshot.nodes[candidate.nodeID]
                let citingPapers = candidate.citingCorePaperIDs.sorted().prefix(5).map { JSONValue.string($0) }
                return .object([
                    "paper_node_id": .string(candidate.nodeID),
                    "paper_id": .string(environment.paperIndex.paperID(forNodeID: candidate.nodeID) ?? candidate.nodeID),
                    "title": .string(node?.displayName ?? candidate.nodeID),
                    "year": node.flatMap(yearValue).map { .number(String($0)) } ?? .null,
                    "citing_core_count": .number(String(candidate.citingCorePaperIDs.count)),
                    "sample_citing_core_papers": .array(Array(citingPapers))
                ])
            }
            let draft = graphInsightDraft(
                title: "Missing core citations for \(projectID)",
                content: "The citation graph found \(ranked.count) candidate papers cited by core project papers but not linked to this project.",
                nodeIDs: selected.flatMap { [$0.nodeID] + Array($0.citingCorePaperIDs.prefix(3)) }
            )
            var payloadFields: [String: JSONValue] = [
                "schema_version": .number("1"),
                "kind": .string("graph_missing_core_papers"),
                "project_id": .string(projectID),
                "project_node_id": .string(projectNodeID),
                "core_paper_count": .number(String(corePaperNodeIDs.count)),
                "missing_core_papers": .array(rows),
                "total_count": .number(String(ranked.count)),
                "truncated": .bool(wasTruncated)
            ]
            try attachDraft(draft, to: &payloadFields, context: context, root: environment.root)
            let result = AgentToolResult(
                callID: "",
                toolName: toolName,
                succeeded: true,
                requiresConfirmation: draft != nil,
                message: "Found \(ranked.count) missing core paper candidate(s).",
                payload: .object(payloadFields)
            )
            await emitSuccess(toolName: toolName, result: result, resultCount: ranked.count, wasTruncated: wasTruncated, startedAt: start, context: context, root: environment.root)
            return result
        } catch {
            await emitFailure(toolName: toolName, error: error, context: context)
            throw error
        }
    }

    public func generateReadingPath(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let start = Date()
        let toolName = GraphAgentTools.generateReadingPath
        do {
            let arguments = try decodeGraphArguments(argumentsJSON)
            let environment = try await loadEnvironment(context: context)
            let centerInput = stringArgument(arguments, keys: ["center_paper_id", "centerPaperID", "paper_id", "paperID"]) ?? context.selectedPaperID
            guard let centerNodeID = normalizedPaperNodeID(centerInput, environment: environment) else {
                throw AgentError.invalidArguments("center_paper_id is required when no paper is selected")
            }
            let projectID = stringArgument(arguments, keys: ["project_id", "projectID"]) ?? context.currentProjectID
            let limit = clampedLimit(arguments, defaultValue: 12, maximum: 50)
            let depth = max(1, min(intArgument(arguments, keys: ["depth"], defaultValue: 3), 5))
            let subgraph = await environment.readModel.subgraph(centerNodeID: centerNodeID, depth: depth, kinds: [.cites, .extends, .uses, .belongsTo])
            let candidateIDs = subgraph.nodes
                .filter { $0.kind == .paper }
                .map(\.id)
            let scores = readingScores(
                candidateIDs: candidateIDs,
                centerNodeID: centerNodeID,
                projectID: projectID,
                environment: environment
            )
            let orderedNodeIDs = readingOrder(candidateIDs: candidateIDs, scores: scores, environment: environment)
            let selected = Array(orderedNodeIDs.prefix(limit))
            let rows = selected.map { nodeID -> JSONValue in
                let node = environment.snapshot.nodes[nodeID]
                let score = scores[nodeID] ?? 0
                return .object([
                    "paper_node_id": .string(nodeID),
                    "paper_id": .string(environment.paperIndex.paperID(forNodeID: nodeID) ?? nodeID),
                    "title": .string(node?.displayName ?? nodeID),
                    "year": node.flatMap(yearValue).map { .number(String($0)) } ?? .null,
                    "score": .number(String(format: "%.3f", score)),
                    "reason": .string(readingReason(nodeID: nodeID, centerNodeID: centerNodeID, projectID: projectID, environment: environment))
                ])
            }
            let payload: JSONValue = .object([
                "schema_version": .number("1"),
                "kind": .string("graph_reading_path"),
                "center_paper_node_id": .string(centerNodeID),
                "project_id": projectID.map { .string($0) } ?? .null,
                "depth": .number(String(depth)),
                "reading_path": .array(rows),
                "total_count": .number(String(candidateIDs.count)),
                "truncated": .bool(candidateIDs.count > selected.count)
            ])
            let result = AgentToolResult(
                callID: "",
                toolName: toolName,
                succeeded: true,
                message: "Generated a reading path with \(selected.count) paper(s).",
                payload: payload
            )
            await emitSuccess(toolName: toolName, result: result, resultCount: candidateIDs.count, wasTruncated: candidateIDs.count > selected.count, startedAt: start, context: context, root: environment.root)
            return result
        } catch {
            await emitFailure(toolName: toolName, error: error, context: context)
            throw error
        }
    }

    public func detectStaleCitations(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let start = Date()
        let toolName = GraphAgentTools.detectStaleCitations
        do {
            let arguments = try decodeGraphArguments(argumentsJSON)
            let environment = try await loadEnvironment(context: context)
            let projectID = stringArgument(arguments, keys: ["project_id", "projectID"]) ?? context.currentProjectID
            let thresholdDays = max(365, intArgument(arguments, keys: ["threshold_days", "thresholdDays"], defaultValue: 3650))
            let thresholdYears = max(1, Int(ceil(Double(thresholdDays) / 365.0)))
            let currentYear = Calendar.current.component(.year, from: Date())
            let sourceScope = projectID.map { scopedProjectPaperNodeIDs(projectID: $0, environment: environment) }
            var staleRows: [JSONValue] = []
            var staleCount = 0

            for edge in environment.snapshot.edges.values where edge.kind == .cites {
                if let sourceScope, !sourceScope.contains(edge.from) { continue }
                guard let targetNode = environment.snapshot.nodes[edge.to], targetNode.kind == .paper else { continue }
                guard let targetYear = yearValue(targetNode), currentYear - targetYear >= thresholdYears else { continue }
                let newerNodes = newerExtendingPapers(for: edge.to, targetYear: targetYear, environment: environment)
                guard !newerNodes.isEmpty else { continue }
                staleCount += 1
                if staleRows.count < 100 {
                    staleRows.append(.object([
                        "edge_id": .string(edge.id),
                        "from_paper_node_id": .string(edge.from),
                        "to_paper_node_id": .string(edge.to),
                        "to_title": .string(targetNode.displayName),
                        "to_year": .number(String(targetYear)),
                        "age_years": .number(String(currentYear - targetYear)),
                        "suggested_newer_papers": .array(newerNodes.prefix(5).map { node in
                            .object([
                                "paper_node_id": .string(node.id),
                                "title": .string(node.displayName),
                                "year": yearValue(node).map { .number(String($0)) } ?? .null
                            ])
                        })
                    ]))
                }
            }
            let draft = staleCount > 0 ? graphInsightDraft(
                title: "Stale citation candidates",
                content: "The citation graph found \(staleCount) citation edge(s) with newer extending papers available.",
                nodeIDs: staleRows.compactMap { row in row.objectValue?["to_paper_node_id"]?.stringValue }
            ) : nil
            var payloadFields: [String: JSONValue] = [
                "schema_version": .number("1"),
                "kind": .string("graph_stale_citations"),
                "project_id": projectID.map { .string($0) } ?? .null,
                "threshold_days": .number(String(thresholdDays)),
                "stale_edges": .array(staleRows),
                "total_count": .number(String(staleCount)),
                "truncated": .bool(staleCount > staleRows.count)
            ]
            try attachDraft(draft, to: &payloadFields, context: context, root: environment.root)
            let result = AgentToolResult(
                callID: "",
                toolName: toolName,
                succeeded: true,
                requiresConfirmation: draft != nil,
                message: "Detected \(staleCount) stale citation candidate(s).",
                payload: .object(payloadFields)
            )
            await emitSuccess(toolName: toolName, result: result, resultCount: staleCount, wasTruncated: staleCount > staleRows.count, startedAt: start, context: context, root: environment.root)
            return result
        } catch {
            await emitFailure(toolName: toolName, error: error, context: context)
            throw error
        }
    }

    public func findUnsupportedArtifactClaims(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let start = Date()
        let toolName = GraphAgentTools.findUnsupportedArtifactClaims
        do {
            let arguments = try decodeGraphArguments(argumentsJSON)
            let environment = try await loadEnvironment(context: context)
            let projectID = stringArgument(arguments, keys: ["project_id", "projectID"]) ?? context.currentProjectID
            let severity = stringArgument(arguments, keys: ["severity"])?.lowercased()
            let artifactNodes = scopedArtifactNodes(projectID: projectID, environment: environment)
            var rows: [JSONValue] = []

            for artifactNode in artifactNodes {
                let claimNodes = claims(forArtifactNodeID: artifactNode.id, environment: environment)
                let inspectedClaimNodes = claimNodes.isEmpty ? [artifactNode] : claimNodes
                for claimNode in inspectedClaimNodes {
                    let support = supportSummary(forNodeID: claimNode.id, environment: environment)
                    let problemSeverity = support.supportingEvidenceIDs.isEmpty ? "error" : (support.staleEvidenceIDs.isEmpty ? "ok" : "warning")
                    if problemSeverity == "ok" { continue }
                    if let severity, severity != problemSeverity { continue }
                    rows.append(.object([
                        "artifact_node_id": .string(artifactNode.id),
                        "artifact_title": .string(artifactNode.displayName),
                        "claim_node_id": .string(claimNode.id),
                        "claim_title": .string(claimNode.displayName),
                        "severity": .string(problemSeverity),
                        "missing_evidence": .bool(support.supportingEvidenceIDs.isEmpty),
                        "stale_evidence_ids": .array(support.staleEvidenceIDs.map { .string($0) }),
                        "supporting_evidence_ids": .array(support.supportingEvidenceIDs.map { .string($0) })
                    ]))
                }
            }
            let wasTruncated = rows.count > 100
            let selectedRows = Array(rows.prefix(100))
            let draft = !selectedRows.isEmpty ? graphInsightDraft(
                title: "Unsupported artifact claims",
                content: "The graph found \(rows.count) artifact claim(s) with missing or stale evidence.",
                nodeIDs: selectedRows.flatMap { row in
                    [
                        row.objectValue?["artifact_node_id"]?.stringValue,
                        row.objectValue?["claim_node_id"]?.stringValue
                    ].compactMap { $0 }
                }
            ) : nil
            var payloadFields: [String: JSONValue] = [
                "schema_version": .number("1"),
                "kind": .string("graph_unsupported_artifact_claims"),
                "project_id": projectID.map { .string($0) } ?? .null,
                "claims": .array(selectedRows),
                "total_count": .number(String(rows.count)),
                "truncated": .bool(wasTruncated)
            ]
            try attachDraft(draft, to: &payloadFields, context: context, root: environment.root)
            let result = AgentToolResult(
                callID: "",
                toolName: toolName,
                succeeded: true,
                requiresConfirmation: draft != nil,
                message: "Found \(rows.count) unsupported or stale artifact claim(s).",
                payload: .object(payloadFields)
            )
            await emitSuccess(toolName: toolName, result: result, resultCount: rows.count, wasTruncated: wasTruncated, startedAt: start, context: context, root: environment.root)
            return result
        } catch {
            await emitFailure(toolName: toolName, error: error, context: context)
            throw error
        }
    }

    public func findStaleSavedArtifacts(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let start = Date()
        let toolName = GraphAgentTools.findStaleSavedArtifacts
        do {
            let arguments = try decodeGraphArguments(argumentsJSON)
            let environment = try await loadEnvironment(context: context)
            let projectID = stringArgument(arguments, keys: ["project_id", "projectID"]) ?? context.currentProjectID
            let thresholdDays = max(1, intArgument(arguments, keys: ["threshold_days", "thresholdDays"], defaultValue: 90))
            let cutoff = Date().addingTimeInterval(-Double(thresholdDays) * 24 * 60 * 60)
            let artifactNodes = scopedArtifactNodes(projectID: projectID, environment: environment)
            var rows: [JSONValue] = []

            for artifactNode in artifactNodes where isSavedArtifact(artifactNode) {
                let support = supportSummary(forNodeID: artifactNode.id, environment: environment)
                let reasons = staleArtifactReasons(artifactNode: artifactNode, cutoff: cutoff, support: support, environment: environment)
                guard !reasons.isEmpty else { continue }
                rows.append(.object([
                    "artifact_node_id": .string(artifactNode.id),
                    "title": .string(artifactNode.displayName),
                    "last_indexed_at": .string(iso8601(artifactNode.lastIndexedAt)),
                    "reasons": .array(reasons.map { .string($0) }),
                    "stale_evidence_ids": .array(support.staleEvidenceIDs.map { .string($0) })
                ]))
            }
            let wasTruncated = rows.count > 100
            let selectedRows = Array(rows.prefix(100))
            let draft = !selectedRows.isEmpty ? graphInsightDraft(
                title: "Stale saved artifacts",
                content: "The graph found \(rows.count) saved artifact(s) whose source evidence or index state is stale.",
                nodeIDs: selectedRows.compactMap { $0.objectValue?["artifact_node_id"]?.stringValue }
            ) : nil
            var payloadFields: [String: JSONValue] = [
                "schema_version": .number("1"),
                "kind": .string("graph_stale_saved_artifacts"),
                "project_id": projectID.map { .string($0) } ?? .null,
                "threshold_days": .number(String(thresholdDays)),
                "artifacts": .array(selectedRows),
                "total_count": .number(String(rows.count)),
                "truncated": .bool(wasTruncated)
            ]
            try attachDraft(draft, to: &payloadFields, context: context, root: environment.root)
            let result = AgentToolResult(
                callID: "",
                toolName: toolName,
                succeeded: true,
                requiresConfirmation: draft != nil,
                message: "Found \(rows.count) stale saved artifact(s).",
                payload: .object(payloadFields)
            )
            await emitSuccess(toolName: toolName, result: result, resultCount: rows.count, wasTruncated: wasTruncated, startedAt: start, context: context, root: environment.root)
            return result
        } catch {
            await emitFailure(toolName: toolName, error: error, context: context)
            throw error
        }
    }

    public func findMethodLineage(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let start = Date()
        let toolName = GraphAgentTools.findMethodLineage
        do {
            let arguments = try decodeGraphArguments(argumentsJSON)
            let environment = try await loadEnvironment(context: context)
            guard let methodNodeID = stringArgument(arguments, keys: ["method_node_id", "methodNodeID", "node_id", "nodeID"])?.nilIfEmpty else {
                throw AgentError.invalidArguments("method_node_id is required")
            }
            guard environment.snapshot.nodes[methodNodeID]?.kind == .method else {
                throw AgentError.invalidArguments("method_node_id must refer to a method node")
            }
            let maxDepth = max(1, min(intArgument(arguments, keys: ["max_depth", "maxDepth", "depth"], defaultValue: 4), 8))
            let lineage = methodLineage(from: methodNodeID, maxDepth: maxDepth, environment: environment)
            let rows = lineage.map { item -> JSONValue in
                let node = environment.snapshot.nodes[item.nodeID]
                return .object([
                    "method_node_id": .string(item.nodeID),
                    "title": .string(node?.displayName ?? item.nodeID),
                    "depth": .number(String(item.depth)),
                    "via_edge_kind": item.viaEdgeKind.map { .string($0.rawValue) } ?? .null,
                    "direction": .string(item.direction)
                ])
            }
            let payload: JSONValue = .object([
                "schema_version": .number("1"),
                "kind": .string("graph_method_lineage"),
                "method_node_id": .string(methodNodeID),
                "max_depth": .number(String(maxDepth)),
                "lineage": .array(rows),
                "total_count": .number(String(lineage.count)),
                "truncated": .bool(false)
            ])
            let result = AgentToolResult(
                callID: "",
                toolName: toolName,
                succeeded: true,
                message: "Found \(lineage.count) method lineage node(s).",
                payload: payload
            )
            await emitSuccess(toolName: toolName, result: result, resultCount: lineage.count, wasTruncated: false, startedAt: start, context: context, root: environment.root)
            return result
        } catch {
            await emitFailure(toolName: toolName, error: error, context: context)
            throw error
        }
    }

    public func findBridgePapers(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        let start = Date()
        let toolName = GraphAgentTools.findBridgePapers
        do {
            let arguments = try decodeGraphArguments(argumentsJSON)
            let environment = try await loadEnvironment(context: context)
            let fromInput = stringArgument(arguments, keys: ["from_paper_id", "fromPaperID", "source_paper_id", "sourcePaperID"])
                ?? context.selectedPaperID
            let toInput = stringArgument(arguments, keys: ["to_paper_id", "toPaperID", "target_paper_id", "targetPaperID"])
            guard let fromNodeID = normalizedPaperNodeID(fromInput, environment: environment) else {
                throw AgentError.invalidArguments("from_paper_id is required when no paper is selected")
            }
            guard let toNodeID = normalizedPaperNodeID(toInput, environment: environment) else {
                throw AgentError.invalidArguments("to_paper_id is required")
            }
            let maxDepth = max(1, min(intArgument(arguments, keys: ["max_depth", "maxDepth", "depth"], defaultValue: 4), 8))
            let pathEdges = await environment.readModel.path(from: fromNodeID, to: toNodeID, maxDepth: maxDepth) ?? []
            let pathNodeIDs = orderedPathNodeIDs(from: fromNodeID, edges: pathEdges)
            let paperRows = pathNodeIDs.compactMap { environment.snapshot.nodes[$0] }.filter { $0.kind == .paper }.map { node -> JSONValue in
                .object([
                    "paper_node_id": .string(node.id),
                    "paper_id": .string(environment.paperIndex.paperID(forNodeID: node.id) ?? node.id),
                    "title": .string(node.displayName),
                    "year": yearValue(node).map { .number(String($0)) } ?? .null
                ])
            }
            let edgeRows = pathEdges.map { edge -> JSONValue in
                .object([
                    "edge_id": .string(edge.id),
                    "kind": .string(edge.kind.rawValue),
                    "from": .string(edge.from),
                    "to": .string(edge.to)
                ])
            }
            let payload: JSONValue = .object([
                "schema_version": .number("1"),
                "kind": .string("graph_bridge_papers"),
                "from_paper_node_id": .string(fromNodeID),
                "to_paper_node_id": .string(toNodeID),
                "max_depth": .number(String(maxDepth)),
                "path_found": .bool(fromNodeID == toNodeID || !pathEdges.isEmpty),
                "bridge_papers": .array(paperRows),
                "path_edges": .array(edgeRows),
                "total_count": .number(String(paperRows.count)),
                "truncated": .bool(false)
            ])
            let result = AgentToolResult(
                callID: "",
                toolName: toolName,
                succeeded: true,
                message: (fromNodeID == toNodeID || !pathEdges.isEmpty) ? "Found a bridge path with \(paperRows.count) paper node(s)." : "No bridge path found.",
                payload: payload
            )
            await emitSuccess(toolName: toolName, result: result, resultCount: paperRows.count, wasTruncated: false, startedAt: start, context: context, root: environment.root)
            return result
        } catch {
            await emitFailure(toolName: toolName, error: error, context: context)
            throw error
        }
    }

    private func loadEnvironment(context: AgentToolContext) async throws -> GraphToolEnvironment {
        let root = context.researchRoot ?? ResearchRoot(rootURL: context.workspace.rootURL)
        let readModel: GraphReadModel
        if let injectedReadModel {
            readModel = injectedReadModel
        } else if let repository {
            if openedRootURL != root.rootURL {
                try await repository.open(in: root)
                openedRootURL = root.rootURL
            }
            readModel = GraphReadModel(repository: repository)
        } else {
            throw AgentError.invalidArguments("Graph read model is unavailable")
        }
        let snapshot = await readModel.snapshot()
        let papers = try await paperRepository.loadPapers(in: context.workspace)
        return GraphToolEnvironment(
            readModel: readModel,
            snapshot: snapshot,
            paperIndex: PaperGraphIndex(papers: papers),
            root: root
        )
    }

    private func emitSuccess(
        toolName: String,
        result: AgentToolResult,
        resultCount: Int,
        wasTruncated: Bool,
        startedAt: Date,
        context: AgentToolContext,
        root: ResearchRoot
    ) async {
        let payloadSize = result.payload?.canonicalJSON.count ?? result.message.count
        let duration = Date().timeIntervalSince(startedAt) * 1000
        await emit(
            AppDebugEventName.agentToolGraphQuery.rawValue,
            payload: .object([
                "tool": .string(toolName),
                "project_id": context.currentProjectID.map { .string($0) } ?? .null,
                "result_count": .number(String(resultCount)),
                "duration_ms": .number(String(format: "%.1f", duration))
            ]),
            context: context,
            root: root
        )
        await emit(
            AppDebugEventName.agentToolGraphResultSize.rawValue,
            payload: .object([
                "tool": .string(toolName),
                "payload_characters": .number(String(payloadSize)),
                "result_count": .number(String(resultCount)),
                "truncated": .bool(wasTruncated)
            ]),
            context: context,
            root: root
        )
    }

    private func emitFailure(toolName: String, error: Error, context: AgentToolContext) async {
        let root = context.researchRoot ?? ResearchRoot(rootURL: context.workspace.rootURL)
        await emit(
            AppDebugEventName.agentToolGraphError.rawValue,
            payload: .object([
                "tool": .string(toolName),
                "error_type": .string(String(describing: type(of: error)))
            ]),
            context: context,
            root: root
        )
    }

    private func emit(_ event: String, payload: JSONValue, context: AgentToolContext, root: ResearchRoot) async {
        let logger = context.debugEventLogger ?? debugEventLogger
        guard let logger else { return }
        try? await logger.append(AppDebugEvent(event: event, payload: payload), in: root)
    }

    private func attachDraft(
        _ draft: AgentArtifactDraft?,
        to payloadFields: inout [String: JSONValue],
        context: AgentToolContext,
        root: ResearchRoot
    ) throws {
        guard let draft else { return }
        payloadFields["graph_insight_draft"] = try encodedJSONValue(draft)
        Task { [context, root, debugEventLogger] in
            let logger = context.debugEventLogger ?? debugEventLogger
            guard let logger else { return }
            try? await logger.append(AppDebugEvent(
                event: AppDebugEventName.agentToolGraphInsightDraft.rawValue,
                payload: .object([
                    "kind": .string(draft.kind),
                    "evidence_count": .number(String(draft.evidenceRefs.count))
                ])
            ), in: root)
        }
    }
}

public nonisolated struct FindMissingCorePapersAgentTool: AgentTool {
    private let backend: GraphToolBackend

    public nonisolated init(backend: GraphToolBackend) {
        self.backend = backend
    }

    public nonisolated var definition: AgentToolDefinition {
        graphToolDefinition(
            name: GraphAgentTools.findMissingCorePapers,
            summary: "Find papers cited by project core papers but not linked to the project.",
            inputSchema: "{\"project_id\":\"project id optional when a project is selected\",\"k\":10,\"min_citations\":1}",
            examples: ["{\"project_id\":\"proj-dark-matter\",\"k\":8}"]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        try await backend.findMissingCorePapers(argumentsJSON: argumentsJSON, context: context)
    }
}

public nonisolated struct GenerateReadingPathAgentTool: AgentTool {
    private let backend: GraphToolBackend

    public nonisolated init(backend: GraphToolBackend) {
        self.backend = backend
    }

    public nonisolated var definition: AgentToolDefinition {
        graphToolDefinition(
            name: GraphAgentTools.generateReadingPath,
            summary: "Generate a deterministic graph-based reading path around a paper.",
            inputSchema: "{\"center_paper_id\":\"paper id optional when selected\",\"project_id\":\"project id optional\",\"depth\":3,\"k\":12}",
            examples: ["{\"center_paper_id\":\"paper-123\",\"depth\":3,\"k\":12}"]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        try await backend.generateReadingPath(argumentsJSON: argumentsJSON, context: context)
    }
}

public nonisolated struct DetectStaleCitationsAgentTool: AgentTool {
    private let backend: GraphToolBackend

    public nonisolated init(backend: GraphToolBackend) {
        self.backend = backend
    }

    public nonisolated var definition: AgentToolDefinition {
        graphToolDefinition(
            name: GraphAgentTools.detectStaleCitations,
            summary: "Detect citations with newer extending papers available.",
            inputSchema: "{\"project_id\":\"project id optional\",\"threshold_days\":3650}",
            examples: ["{\"project_id\":\"proj-dark-matter\",\"threshold_days\":3650}"]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        try await backend.detectStaleCitations(argumentsJSON: argumentsJSON, context: context)
    }
}

public nonisolated struct FindUnsupportedArtifactClaimsAgentTool: AgentTool {
    private let backend: GraphToolBackend

    public nonisolated init(backend: GraphToolBackend) {
        self.backend = backend
    }

    public nonisolated var definition: AgentToolDefinition {
        graphToolDefinition(
            name: GraphAgentTools.findUnsupportedArtifactClaims,
            summary: "Find artifact claim nodes missing fresh supporting evidence.",
            inputSchema: "{\"project_id\":\"project id optional\",\"severity\":\"warning|error optional\"}",
            examples: ["{\"project_id\":\"proj-dark-matter\",\"severity\":\"error\"}"]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        try await backend.findUnsupportedArtifactClaims(argumentsJSON: argumentsJSON, context: context)
    }
}

public nonisolated struct FindStaleSavedArtifactsAgentTool: AgentTool {
    private let backend: GraphToolBackend

    public nonisolated init(backend: GraphToolBackend) {
        self.backend = backend
    }

    public nonisolated var definition: AgentToolDefinition {
        graphToolDefinition(
            name: GraphAgentTools.findStaleSavedArtifacts,
            summary: "Find saved graph-backed artifacts whose evidence or index state is stale.",
            inputSchema: "{\"project_id\":\"project id optional\",\"threshold_days\":90}",
            examples: ["{\"project_id\":\"proj-dark-matter\",\"threshold_days\":90}"]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        try await backend.findStaleSavedArtifacts(argumentsJSON: argumentsJSON, context: context)
    }
}

public nonisolated struct FindMethodLineageAgentTool: AgentTool {
    private let backend: GraphToolBackend

    public nonisolated init(backend: GraphToolBackend) {
        self.backend = backend
    }

    public nonisolated var definition: AgentToolDefinition {
        graphToolDefinition(
            name: GraphAgentTools.findMethodLineage,
            summary: "Trace method lineage through extends and uses graph edges.",
            inputSchema: "{\"method_node_id\":\"method:<id>\",\"max_depth\":4}",
            examples: ["{\"method_node_id\":\"method:simulation-based-inference\",\"max_depth\":4}"]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        try await backend.findMethodLineage(argumentsJSON: argumentsJSON, context: context)
    }
}

public nonisolated struct FindBridgePapersAgentTool: AgentTool {
    private let backend: GraphToolBackend

    public nonisolated init(backend: GraphToolBackend) {
        self.backend = backend
    }

    public nonisolated var definition: AgentToolDefinition {
        graphToolDefinition(
            name: GraphAgentTools.findBridgePapers,
            summary: "Find the shortest graph path of papers between two papers.",
            inputSchema: "{\"from_paper_id\":\"paper id optional when selected\",\"to_paper_id\":\"paper id\",\"max_depth\":4}",
            examples: ["{\"from_paper_id\":\"paper-a\",\"to_paper_id\":\"paper-b\",\"max_depth\":4}"]
        )
    }

    public func invoke(argumentsJSON: String, context: AgentToolContext) async throws -> AgentToolResult {
        try await backend.findBridgePapers(argumentsJSON: argumentsJSON, context: context)
    }
}

private nonisolated struct GraphToolEnvironment: Sendable {
    var readModel: GraphReadModel
    var snapshot: GraphSnapshot
    var paperIndex: PaperGraphIndex
    var root: ResearchRoot
}

private nonisolated struct PaperGraphIndex: Sendable {
    private let papersByID: [String: Paper]
    private let papersByGraphNodeID: [String: Paper]
    private let papersByCitekey: [String: Paper]

    init(papers: [Paper]) {
        papersByID = Dictionary(uniqueKeysWithValues: papers.map { ($0.id, $0) })
        papersByGraphNodeID = Dictionary(uniqueKeysWithValues: papers.map { ("paper:\($0.resolvedGraphNodeID)", $0) })
        papersByCitekey = Dictionary(uniqueKeysWithValues: papers.map { ($0.citekey.lowercased(), $0) })
    }

    func paperID(forNodeID nodeID: String) -> String? {
        papersByGraphNodeID[nodeID]?.id
    }

    func graphNodeID(for input: String?) -> String? {
        guard let value = input?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        if value.hasPrefix("paper:") {
            return value
        }
        if let paper = papersByID[value] {
            return "paper:\(paper.resolvedGraphNodeID)"
        }
        if let paper = papersByCitekey[value.lowercased()] {
            return "paper:\(paper.resolvedGraphNodeID)"
        }
        let graphNodeID = "paper:\(value)"
        if papersByGraphNodeID[graphNodeID] != nil {
            return graphNodeID
        }
        return graphNodeID
    }

    func corePaperNodeIDs(projectID: String) -> Set<String> {
        Set(papersByID.values.filter { $0.coreProjectIDs.contains(projectID) }.map { "paper:\($0.resolvedGraphNodeID)" })
    }

    func projectPaperNodeIDs(projectID: String) -> Set<String> {
        Set(papersByID.values.filter { $0.projectIDs.contains(projectID) || $0.coreProjectIDs.contains(projectID) }.map { "paper:\($0.resolvedGraphNodeID)" })
    }

    func belongsToProject(nodeID: String, projectID: String) -> Bool {
        guard let paper = papersByGraphNodeID[nodeID] else { return false }
        return paper.projectIDs.contains(projectID) || paper.coreProjectIDs.contains(projectID)
    }
}

private nonisolated struct MissingCorePaperCandidate: Sendable {
    var nodeID: String
    var citingCorePaperIDs: Set<String>
}

private nonisolated struct SupportSummary: Sendable {
    var supportingEvidenceIDs: [String]
    var staleEvidenceIDs: [String]
}

private nonisolated struct MethodLineageItem: Sendable {
    var nodeID: String
    var depth: Int
    var viaEdgeKind: GraphEdgeKind?
    var direction: String
}

private nonisolated func graphToolDefinition(
    name: String,
    summary: String,
    inputSchema: String,
    examples: [String]
) -> AgentToolDefinition {
    AgentToolDefinition(
        name: name,
        displayName: name.replacingOccurrences(of: "_", with: " ").capitalized,
        summary: summary,
        inputSchema: inputSchema,
        risk: .readOnly,
        requiresConfirmation: false,
        permissionKey: "graph.read",
        outputPolicy: AgentToolOutputPolicy(maxCharacters: 16000),
        examples: examples
    )
}

private nonisolated func decodeGraphArguments(_ rawJSON: String) throws -> [String: JSONValue] {
    let trimmed = rawJSON.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [:] }
    let value = try JSONValue.parse(trimmed)
    guard let object = value.objectValue else {
        throw AgentError.invalidArguments("graph tool arguments must be a JSON object")
    }
    return object
}

private nonisolated func stringArgument(_ arguments: [String: JSONValue], keys: [String]) -> String? {
    for key in keys {
        if let value = arguments[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            return value
        }
    }
    return nil
}

private nonisolated func intArgument(_ arguments: [String: JSONValue], keys: [String], defaultValue: Int) -> Int {
    for key in keys {
        guard let value = arguments[key] else { continue }
        if let stringValue = value.stringValue, let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intValue
        }
        if case let .number(rawValue) = value, let intValue = Int(rawValue) {
            return intValue
        }
    }
    return defaultValue
}

private nonisolated func clampedLimit(_ arguments: [String: JSONValue], defaultValue: Int, maximum: Int) -> Int {
    min(max(intArgument(arguments, keys: ["k", "limit", "top_k", "topK"], defaultValue: defaultValue), 1), maximum)
}

private nonisolated func normalizedProjectNodeID(_ projectID: String) -> String {
    projectID.hasPrefix("project:") ? projectID : "project:\(projectID)"
}

private nonisolated func normalizedPaperNodeID(_ input: String?, environment: GraphToolEnvironment) -> String? {
    guard let nodeID = environment.paperIndex.graphNodeID(for: input) else {
        return nil
    }
    if environment.snapshot.nodes[nodeID]?.kind == .paper || nodeID.hasPrefix("paper:") {
        return nodeID
    }
    return nil
}

private nonisolated func scopedProjectPaperNodeIDs(projectID: String, environment: GraphToolEnvironment) -> Set<String> {
    let projectNodeID = normalizedProjectNodeID(projectID)
    var nodeIDs = environment.paperIndex.projectPaperNodeIDs(projectID: projectID)
    for edge in environment.snapshot.edges.values where edge.kind == .belongsTo && edge.to == projectNodeID {
        if environment.snapshot.nodes[edge.from]?.kind == .paper {
            nodeIDs.insert(edge.from)
        }
    }
    return nodeIDs
}

private nonisolated func belongsToProject(
    nodeID: String,
    projectID: String,
    projectNodeID: String,
    environment: GraphToolEnvironment
) -> Bool {
    if environment.paperIndex.belongsToProject(nodeID: nodeID, projectID: projectID) {
        return true
    }
    return environment.snapshot.edges.values.contains { edge in
        edge.kind == .belongsTo && edge.from == nodeID && edge.to == projectNodeID
    }
}

private nonisolated func yearValue(_ node: GraphNode) -> Int? {
    guard let object = node.payload.objectValue else { return nil }
    if let raw = object["year"]?.stringValue, let year = Int(raw) {
        return year
    }
    if case let .number(raw)? = object["year"], let year = Int(raw) {
        return year
    }
    return nil
}

private nonisolated func boolPayload(_ node: GraphNode, keys: [String]) -> Bool {
    guard let object = node.payload.objectValue else { return false }
    for key in keys {
        if case let .bool(value)? = object[key] {
            return value
        }
        if let raw = object[key]?.stringValue?.lowercased(), ["true", "yes", "stale"].contains(raw) {
            return true
        }
    }
    return false
}

private nonisolated func stringPayload(_ node: GraphNode, keys: [String]) -> String? {
    guard let object = node.payload.objectValue else { return nil }
    for key in keys {
        if let value = object[key]?.stringValue?.nilIfEmpty {
            return value
        }
    }
    return nil
}

private nonisolated func readingScores(
    candidateIDs: [String],
    centerNodeID: String,
    projectID: String?,
    environment: GraphToolEnvironment
) -> [String: Double] {
    let currentYear = Calendar.current.component(.year, from: Date())
    var scores: [String: Double] = [:]
    let projectScope = projectID.map { scopedProjectPaperNodeIDs(projectID: $0, environment: environment) } ?? []
    for nodeID in candidateIDs {
        let incidentCitations = environment.snapshot.edges.values.filter { edge in
            edge.kind == .cites && (edge.from == nodeID || edge.to == nodeID)
        }.count
        let yearScore: Double
        if let node = environment.snapshot.nodes[nodeID], let year = yearValue(node) {
            yearScore = 1.0 / Double(max(currentYear - year + 1, 1))
        } else {
            yearScore = 0
        }
        let projectBoost = projectScope.contains(nodeID) ? 1.5 : 0
        let centerBoost = nodeID == centerNodeID ? 2.0 : 0
        let freshnessBoost: Double
        if let node = environment.snapshot.nodes[nodeID], boolPayload(node, keys: ["evidence_fresh", "fresh"]) {
            freshnessBoost = 0.75
        } else {
            freshnessBoost = 0
        }
        scores[nodeID] = Double(incidentCitations) + yearScore + projectBoost + centerBoost + freshnessBoost
    }
    return scores
}

private nonisolated func readingOrder(
    candidateIDs: [String],
    scores: [String: Double],
    environment: GraphToolEnvironment
) -> [String] {
    let candidateSet = Set(candidateIDs)
    var outgoing: [String: Set<String>] = [:]
    var incomingCount: [String: Int] = Dictionary(uniqueKeysWithValues: candidateIDs.map { ($0, 0) })
    for edge in environment.snapshot.edges.values where edge.kind == .cites && candidateSet.contains(edge.from) && candidateSet.contains(edge.to) {
        outgoing[edge.to, default: []].insert(edge.from)
        incomingCount[edge.from, default: 0] += 1
    }
    var ready = incomingCount.filter { $0.value == 0 }.map(\.key)
    var result: [String] = []
    while !ready.isEmpty {
        ready.sort { first, second in
            let firstScore = scores[first] ?? 0
            let secondScore = scores[second] ?? 0
            if firstScore != secondScore { return firstScore > secondScore }
            return first.localizedStandardCompare(second) == .orderedAscending
        }
        let nodeID = ready.removeFirst()
        result.append(nodeID)
        for next in outgoing[nodeID, default: []] {
            incomingCount[next, default: 0] -= 1
            if incomingCount[next] == 0 {
                ready.append(next)
            }
        }
    }
    let remaining = candidateIDs.filter { !result.contains($0) }.sorted { first, second in
        let firstScore = scores[first] ?? 0
        let secondScore = scores[second] ?? 0
        if firstScore != secondScore { return firstScore > secondScore }
        return first.localizedStandardCompare(second) == .orderedAscending
    }
    return result + remaining
}

private nonisolated func readingReason(
    nodeID: String,
    centerNodeID: String,
    projectID: String?,
    environment: GraphToolEnvironment
) -> String {
    if nodeID == centerNodeID { return "selected center paper" }
    if let projectID, scopedProjectPaperNodeIDs(projectID: projectID, environment: environment).contains(nodeID) {
        return "linked to the current project"
    }
    let citedByCenter = environment.snapshot.edges.values.contains { $0.kind == .cites && $0.from == centerNodeID && $0.to == nodeID }
    if citedByCenter { return "cited by the center paper" }
    let citesCenter = environment.snapshot.edges.values.contains { $0.kind == .cites && $0.from == nodeID && $0.to == centerNodeID }
    if citesCenter { return "cites the center paper" }
    return "nearby in the citation graph"
}

private nonisolated func newerExtendingPapers(for nodeID: String, targetYear: Int, environment: GraphToolEnvironment) -> [GraphNode] {
    var nodes: [GraphNode] = []
    for edge in environment.snapshot.edges.values where edge.kind == .extends && (edge.from == nodeID || edge.to == nodeID) {
        let candidateID = edge.from == nodeID ? edge.to : edge.from
        guard let node = environment.snapshot.nodes[candidateID], node.kind == .paper else { continue }
        guard let year = yearValue(node), year > targetYear else { continue }
        nodes.append(node)
    }
    return nodes.sorted { first, second in
        let firstYear = yearValue(first) ?? 0
        let secondYear = yearValue(second) ?? 0
        if firstYear != secondYear { return firstYear > secondYear }
        return first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
    }
}

private nonisolated func scopedArtifactNodes(projectID: String?, environment: GraphToolEnvironment) -> [GraphNode] {
    let artifacts = environment.snapshot.nodes.values.filter { $0.kind == .artifact }
    guard let projectID else {
        return artifacts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    let projectNodeID = normalizedProjectNodeID(projectID)
    return artifacts.filter { artifact in
        environment.snapshot.edges.values.contains { edge in
            edge.kind == .belongsTo && edge.from == artifact.id && edge.to == projectNodeID
        }
    }
    .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
}

private nonisolated func claims(forArtifactNodeID artifactNodeID: String, environment: GraphToolEnvironment) -> [GraphNode] {
    var claimIDs: Set<String> = []
    for edge in environment.snapshot.edges.values where edge.from == artifactNodeID || edge.to == artifactNodeID {
        let otherID = edge.from == artifactNodeID ? edge.to : edge.from
        if environment.snapshot.nodes[otherID]?.kind == .claim {
            claimIDs.insert(otherID)
        }
    }
    for (nodeID, node) in environment.snapshot.nodes where node.kind == .claim && nodeID.hasPrefix("claim:\(artifactNodeID):") {
        claimIDs.insert(nodeID)
    }
    return claimIDs.compactMap { environment.snapshot.nodes[$0] }.sorted { first, second in
        first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
    }
}

private nonisolated func supportSummary(forNodeID nodeID: String, environment: GraphToolEnvironment) -> SupportSummary {
    var supportingEvidenceIDs: Set<String> = []
    var staleEvidenceIDs: Set<String> = []
    for edge in environment.snapshot.edges.values where edge.kind == .supports && (edge.from == nodeID || edge.to == nodeID) {
        let otherID = edge.from == nodeID ? edge.to : edge.from
        if let node = environment.snapshot.nodes[otherID], node.kind == .evidence {
            supportingEvidenceIDs.insert(otherID)
            if isStaleEvidence(node) {
                staleEvidenceIDs.insert(otherID)
            }
        }
    }
    return SupportSummary(
        supportingEvidenceIDs: supportingEvidenceIDs.sorted(),
        staleEvidenceIDs: staleEvidenceIDs.sorted()
    )
}

private nonisolated func isStaleEvidence(_ node: GraphNode) -> Bool {
    boolPayload(node, keys: ["stale", "is_stale", "needs_refresh"])
        || stringPayload(node, keys: ["status", "freshness"])?.lowercased() == "stale"
}

private nonisolated func isSavedArtifact(_ node: GraphNode) -> Bool {
    let status = stringPayload(node, keys: ["status", "lifecycle_state"])
    return status == nil || status?.lowercased() == "saved"
}

private nonisolated func staleArtifactReasons(
    artifactNode: GraphNode,
    cutoff: Date,
    support: SupportSummary,
    environment: GraphToolEnvironment
) -> [String] {
    var reasons: [String] = []
    if artifactNode.lastIndexedAt < cutoff {
        reasons.append("artifact_index_older_than_threshold")
    }
    if !support.staleEvidenceIDs.isEmpty {
        reasons.append("supporting_evidence_stale")
    }
    if boolPayload(artifactNode, keys: ["stale", "needs_refresh"]) {
        reasons.append("artifact_marked_stale")
    }
    if support.supportingEvidenceIDs.isEmpty {
        let claims = claims(forArtifactNodeID: artifactNode.id, environment: environment)
        if claims.isEmpty {
            reasons.append("no_supporting_evidence")
        }
    }
    return Array(Set(reasons)).sorted()
}

private nonisolated func methodLineage(from methodNodeID: String, maxDepth: Int, environment: GraphToolEnvironment) -> [MethodLineageItem] {
    var visited: Set<String> = [methodNodeID]
    var queue: [MethodLineageItem] = [MethodLineageItem(nodeID: methodNodeID, depth: 0, viaEdgeKind: nil, direction: "self")]
    var result: [MethodLineageItem] = []
    while !queue.isEmpty {
        let item = queue.removeFirst()
        result.append(item)
        guard item.depth < maxDepth else { continue }
        for edge in environment.snapshot.edges.values where [.extends, .uses].contains(edge.kind) && (edge.from == item.nodeID || edge.to == item.nodeID) {
            let nextNodeID = edge.from == item.nodeID ? edge.to : edge.from
            guard !visited.contains(nextNodeID), environment.snapshot.nodes[nextNodeID]?.kind == .method else { continue }
            visited.insert(nextNodeID)
            queue.append(MethodLineageItem(
                nodeID: nextNodeID,
                depth: item.depth + 1,
                viaEdgeKind: edge.kind,
                direction: edge.from == item.nodeID ? "outgoing" : "incoming"
            ))
        }
    }
    return result
}

private nonisolated func orderedPathNodeIDs(from sourceNodeID: String, edges: [GraphEdge]) -> [String] {
    var nodeIDs = [sourceNodeID]
    var currentNodeID = sourceNodeID
    for edge in edges {
        let nextNodeID: String
        if edge.from == currentNodeID {
            nextNodeID = edge.to
        } else if edge.to == currentNodeID {
            nextNodeID = edge.from
        } else {
            nextNodeID = edge.from
        }
        nodeIDs.append(nextNodeID)
        currentNodeID = nextNodeID
    }
    return nodeIDs
}

private nonisolated func graphInsightDraft(title: String, content: String, nodeIDs: [String]) -> AgentArtifactDraft? {
    let uniqueNodeIDs = Array(Set(nodeIDs.filter { !$0.isEmpty })).sorted()
    guard !uniqueNodeIDs.isEmpty else { return nil }
    return AgentArtifactDraft(
        runID: "graph-insight",
        kind: "graph_insight",
        title: title,
        content: content,
        evidenceRefs: uniqueNodeIDs.prefix(20).map { nodeID in
            AgentEvidenceRef(
                sourceType: "graph",
                sourceID: nodeID,
                retrievedAt: Date(),
                heading: nodeID,
                confidence: 1.0
            )
        },
        risk: .readOnly
    )
}

private nonisolated func encodedJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try AgentRunDirectoryStore.encoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    return try JSONValue.fromJSONObject(object)
}

private nonisolated func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private extension Optional where Wrapped == String {
    nonisolated var nilIfEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}