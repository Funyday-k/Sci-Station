import Foundation

/// Bridges P49 (Recommendation Engine) and P48.10 (paper status auto-flips)
/// into `ResearchQueueStore`. The ingestor never subscribes to any artifact
/// approval stream (none exists today — see `docs/development/Proposal48.md` §0.5).
/// Instead the calling layer (`AppViewModel`) forwards two deterministic
/// inputs after each `@Published` change:
///
///   1. `ingest(runs:)` — scans the agent run history for already-approved
///      `recommendation_note` tool results and appends their `queue_candidates`
///      to the store. Deduped by `(runID, callID)`; the cursor is persisted to
///      `.sci-station/queue/ingest_cursor.json` so reopens never double-ingest.
///   2. `ingest(papers:previous:)` — diffs `Paper.status` against the supplied
///      previous snapshot and asks the store to apply the transition rules in
///      §4.10. The ingestor itself never reads or writes paper data.
public actor ResearchQueueIngestor {
    public static let cursorRelativePath = ".sci-station/queue/ingest_cursor.json"
    public static let cursorSchemaVersion: Int = 1

    private struct CursorState: Codable, Sendable {
        var schemaVersion: Int
        var scannedToolCalls: [String]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case scannedToolCalls = "scanned_tool_calls"
        }
    }

    private let store: ResearchQueueStore
    private let workspace: ResearchWorkspace
    private let researchRoot: ResearchRoot
    private let fileManager: FileManager
    private let debugLogger: AppDebugEventLogger?

    private var scannedToolCalls: Set<String> = []
    private var isStarted = false

    public init(
        store: ResearchQueueStore,
        workspace: ResearchWorkspace,
        researchRoot: ResearchRoot? = nil,
        fileManager: FileManager = .default,
        debugLogger: AppDebugEventLogger? = nil
    ) {
        self.store = store
        self.workspace = workspace
        self.researchRoot = researchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
        self.fileManager = fileManager
        self.debugLogger = debugLogger
    }

    /// Load the dedupe cursor from disk. Safe to call repeatedly — only the
    /// first invocation does the IO; later calls are no-ops.
    public func start() async {
        guard !isStarted else {
            return
        }
        scannedToolCalls = loadCursor()
        isStarted = true
    }

    /// Reset the in-memory cursor and remove the persisted file. Intended for
    /// tests; production code should not call this.
    public func resetCursorForTesting() {
        scannedToolCalls.removeAll()
        let cursorURL = workspace.fileURL(for: Self.cursorRelativePath)
        try? fileManager.removeItem(at: cursorURL)
    }

    // MARK: - Layer B: AgentRun.toolResults scan

    /// Scan the supplied agent runs for newly-saved `recommendation_note`
    /// tool results. `runs` is expected to be the union of in-flight and
    /// historical runs from `AppViewModel`. Idempotent.
    public func ingest(runs: [AgentRun]) async {
        await start()

        var runsScanned = 0
        var hitCount = 0

        for run in runs {
            for result in run.toolResults {
                let key = "\(run.id):\(result.callID)"
                if scannedToolCalls.contains(key) {
                    continue
                }
                guard isCandidate(result) else {
                    // Mark as scanned regardless so we don't re-evaluate it on
                    // every refresh. Pending-approval rows that later become
                    // approved will appear as a new toolResult (different call
                    // id) — `requiresConfirmation` is monotonic per call id
                    // because the approval flow re-runs the tool and replaces
                    // the result in place.
                    if result.requiresConfirmation == false {
                        scannedToolCalls.insert(key)
                    }
                    continue
                }

                scannedToolCalls.insert(key)
                runsScanned += 1

                guard let payload = result.payload,
                      let candidates = payload.objectValue?["queue_candidates"]?.arrayValue,
                      !candidates.isEmpty else {
                    continue
                }

                let scope = resolveScope(payload: payload, run: run)
                let mapped = mapCandidatesToEntries(
                    candidates: candidates,
                    scope: scope,
                    runID: run.id,
                    callID: result.callID
                )
                guard !mapped.isEmpty else {
                    continue
                }

                do {
                    try await store.appendBatch(mapped, scope: scope)
                    hitCount += mapped.count
                    await emitDebug(event: "queue.ingest_from_recommendation", payload: .object([
                        "run_id": .string(run.id),
                        "tool_call_id": .string(result.callID),
                        "scope": .string(scope.identifier),
                        "added": .number(String(mapped.count))
                    ]))
                } catch {
                    await emitDebug(event: "queue.ingest_error", payload: .object([
                        "run_id": .string(run.id),
                        "tool_call_id": .string(result.callID),
                        "reason": .string("append_failed")
                    ]))
                }
            }
        }

        persistCursor()

        await emitDebug(event: "queue.ingest_scanned", payload: .object([
            "run_count": .number(String(runs.count)),
            "matched_results": .number(String(runsScanned)),
            "hit_count": .number(String(hitCount))
        ]))
    }

    // MARK: - P48.10: Paper status diff

    /// Forward `Paper.status` changes to the store using the deterministic
    /// transition table in §4.10. `previous` is the prior `[paperID: Paper]`
    /// snapshot; pass `[:]` on first call to avoid any flip.
    public func ingest(papers: [Paper], previous: [String: Paper]) async {
        await start()

        for paper in papers {
            let before = previous[paper.id]?.status
            let after = paper.status
            guard before != after else {
                continue
            }
            await store.applyPaperStatusTransition(
                paperID: paper.id,
                from: before,
                to: after,
                at: paper.lastReadAt ?? paper.updatedAt
            )
        }
    }

    // MARK: - Internals

    private func isCandidate(_ result: AgentToolResult) -> Bool {
        guard result.succeeded, !result.requiresConfirmation else {
            return false
        }
        guard let payload = result.payload else {
            return false
        }
        // Match `kind: "recommendation_note"`. We accept `artifact_kind` as a
        // secondary spelling so P49 producers can match either contract.
        let kind = payload.objectValue?["kind"]?.stringValue
            ?? payload.objectValue?["artifact_kind"]?.stringValue
        return kind == "recommendation_note"
    }

    private func resolveScope(payload: JSONValue, run: AgentRun) -> QueueScope {
        if let scopeValue = payload.objectValue?["queue_scope"]?.stringValue,
           let scope = QueueScope(identifier: scopeValue) {
            return scope
        }
        if let projectID = (run.projectID ?? run.currentProjectID)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectID.isEmpty {
            return .project(projectID)
        }
        return .workspace
    }

    private func mapCandidatesToEntries(
        candidates: [JSONValue],
        scope: QueueScope,
        runID: String,
        callID: String
    ) -> [ResearchQueueEntry] {
        let now = Date()
        var rows: [ResearchQueueEntry] = []
        var seenWithinBatch: Set<String> = []
        for (offset, candidate) in candidates.enumerated() {
            guard let object = candidate.objectValue else {
                continue
            }
            let paperID = object["paper_id"]?.stringValue?.nilIfBlank
            let externalKey = object["external_key"]?.stringValue?.nilIfBlank
            guard let identifier = paperID ?? externalKey else {
                continue
            }
            let entryID = "queue:\(scope.identifier):\(identifier)"
            guard !seenWithinBatch.contains(entryID) else {
                continue
            }
            seenWithinBatch.insert(entryID)
            let displayTitle = object["display_title"]?.stringValue?.nilIfBlank
                ?? object["title"]?.stringValue?.nilIfBlank
                ?? identifier
            let noteSummary = object["reason"]?.stringValue?.nilIfBlank
                ?? object["note_summary"]?.stringValue?.nilIfBlank
            rows.append(
                ResearchQueueEntry(
                    id: entryID,
                    paperID: paperID,
                    externalKey: externalKey,
                    displayTitle: displayTitle,
                    scope: scope,
                    status: .queued,
                    source: .recommendation,
                    order: offset + 1,
                    addedAt: now,
                    startedAt: nil,
                    finishedAt: nil,
                    lastTouchedAt: now,
                    noteSummary: noteSummary,
                    sourceRefs: ["run:\(runID)", "tool_call:\(callID)"]
                )
            )
        }
        return rows
    }

    private func loadCursor() -> Set<String> {
        let cursorURL = workspace.fileURL(for: Self.cursorRelativePath)
        guard fileManager.fileExists(atPath: cursorURL.path) else {
            return []
        }
        guard let data = try? Data(contentsOf: cursorURL),
              let state = try? JSONDecoder().decode(CursorState.self, from: data) else {
            return []
        }
        return Set(state.scannedToolCalls)
    }

    private func persistCursor() {
        let cursorURL = workspace.fileURL(for: Self.cursorRelativePath)
        do {
            try fileManager.createDirectory(at: cursorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let state = CursorState(
                schemaVersion: Self.cursorSchemaVersion,
                scannedToolCalls: scannedToolCalls.sorted()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(state)
            try data.write(to: cursorURL, options: .atomic)
        } catch {
            // Cursor persistence failures are not fatal — the next ingest pass
            // will simply re-attempt. The debug event flags it for ops.
            Task { @Sendable [debugLogger, researchRoot] in
                guard let debugLogger else { return }
                let event = AppDebugEvent(event: "queue.ingest_error", payload: .object([
                    "reason": .string("cursor_write_failed")
                ]))
                try? await debugLogger.append(event, in: researchRoot)
            }
        }
    }

    private func emitDebug(event: String, payload: JSONValue) async {
        guard let debugLogger else {
            return
        }
        let evt = AppDebugEvent(
            event: event,
            workspaceID: workspace.rootURL.path,
            payload: payload
        )
        try? await debugLogger.append(evt, in: researchRoot)
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
