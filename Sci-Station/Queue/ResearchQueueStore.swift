import Foundation

/// Errors surfaced by `ResearchQueueStore` write paths. Read paths never throw
/// — they fall back to an empty in-memory snapshot and emit a debug warning.
public nonisolated enum ResearchQueueStoreError: Error, Sendable, Equatable {
    case duplicateID(String)
    case unknownID(String)
    case storeNotOpen
    case scopeMismatch(expected: String, actual: String)
}

/// Snapshot value handed back from the actor for read APIs. Plain struct so
/// the calling site can hold it without leaking actor-isolation.
public nonisolated struct ResearchQueueSnapshot: Sendable, Hashable {
    public var entriesByScope: [String: [ResearchQueueEntry]]

    public init(entriesByScope: [String: [ResearchQueueEntry]] = [:]) {
        self.entriesByScope = entriesByScope
    }

    public var totalCount: Int {
        entriesByScope.values.reduce(0) { $0 + $1.count }
    }
}

/// Single source of truth for `library/queue.yaml` and
/// `projects/<id>/queue.yaml`. All mutations are atomic at the file level
/// (write to `.tmp` then rename) and emit `queue.*` debug events that strip
/// any user-facing text. See `DOC/Proposal48.md` §4.2 / §5.2 / §8.
public actor ResearchQueueStore {
    private let workspace: ResearchWorkspace
    private let researchRoot: ResearchRoot
    private let fileManager: FileManager
    private let debugLogger: AppDebugEventLogger?
    private let dateProvider: @Sendable () -> Date

    private var indices: [String: ScopeIndex] = [:]
    private var subscribers: [UUID: AsyncStream<QueueChange>.Continuation] = [:]
    private var isOpen = false

    private struct ScopeIndex: Sendable {
        var scope: QueueScope
        var entriesByID: [String: ResearchQueueEntry]
    }

    public init(
        workspace: ResearchWorkspace,
        researchRoot: ResearchRoot? = nil,
        fileManager: FileManager = .default,
        debugLogger: AppDebugEventLogger? = nil,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workspace = workspace
        self.researchRoot = researchRoot ?? ResearchRoot(rootURL: workspace.rootURL)
        self.fileManager = fileManager
        self.debugLogger = debugLogger
        self.dateProvider = dateProvider
    }

    // MARK: - Lifecycle

    public func open() async throws {
        guard !isOpen else {
            return
        }

        var loaded: [String: ScopeIndex] = [:]

        let workspaceScope = QueueScope.workspace
        let workspaceURL = url(for: workspaceScope)
        if fileManager.fileExists(atPath: workspaceURL.path) {
            let result = await loadScope(workspaceScope, from: workspaceURL)
            loaded[workspaceScope.identifier] = ScopeIndex(
                scope: workspaceScope,
                entriesByID: Dictionary(uniqueKeysWithValues: result.entries.map { ($0.id, $0) })
            )
        }

        for projectID in discoverProjectScopes() {
            let scope = QueueScope.project(projectID)
            let scopeURL = url(for: scope)
            guard fileManager.fileExists(atPath: scopeURL.path) else {
                continue
            }
            let result = await loadScope(scope, from: scopeURL)
            loaded[scope.identifier] = ScopeIndex(
                scope: scope,
                entriesByID: Dictionary(uniqueKeysWithValues: result.entries.map { ($0.id, $0) })
            )
        }

        indices = loaded
        isOpen = true

        await emitDebug(event: "queue.load", payload: .object([
            "scope_count": .number(String(indices.count)),
            "total_entries": .number(String(indices.values.reduce(0) { $0 + $1.entriesByID.count }))
        ]))
    }

    public func close() {
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
        indices.removeAll()
        isOpen = false
    }

    // MARK: - Read

    public func entries(in scope: QueueScope) -> [ResearchQueueEntry] {
        sortedEntries(in: scope)
    }

    public func entry(id: String) -> ResearchQueueEntry? {
        for index in indices.values {
            if let entry = index.entriesByID[id] {
                return entry
            }
        }
        return nil
    }

    public func snapshot() -> ResearchQueueSnapshot {
        var byScope: [String: [ResearchQueueEntry]] = [:]
        for (key, index) in indices {
            byScope[key] = sortedEntries(in: index.scope)
        }
        return ResearchQueueSnapshot(entriesByScope: byScope)
    }

    public func workspaceQueueTop(limit: Int) -> [ResearchQueueEntry] {
        topEntries(in: .workspace, limit: limit)
    }

    public func projectQueueTop(projectID: String, limit: Int) -> [ResearchQueueEntry] {
        topEntries(in: .project(projectID), limit: limit)
    }

    public func entries(byPaperID paperID: String) -> [ResearchQueueEntry] {
        var result: [ResearchQueueEntry] = []
        for index in indices.values {
            for entry in index.entriesByID.values where entry.paperID == paperID {
                result.append(entry)
            }
        }
        return result.sorted { $0.scope.identifier < $1.scope.identifier }
    }

    public func knownScopes() -> [QueueScope] {
        indices.values.map(\.scope).sorted { $0.identifier < $1.identifier }
    }

    // MARK: - Write

    public func append(_ entry: ResearchQueueEntry) async throws {
        try ensureOpen()
        try await appendBatchInternal([entry], scope: entry.scope, isBatch: false)
    }

    public func appendBatch(_ entries: [ResearchQueueEntry], scope: QueueScope) async throws {
        try ensureOpen()
        try await appendBatchInternal(entries, scope: scope, isBatch: true)
    }

    public func updateStatus(id: String, status: QueueStatus, at: Date? = nil) async throws {
        try ensureOpen()
        let timestamp = at ?? dateProvider()
        guard let (scopeKey, existing) = locate(id: id) else {
            throw ResearchQueueStoreError.unknownID(id)
        }
        try await applyStatusChange(
            scopeKey: scopeKey,
            entry: existing,
            newStatus: status,
            timestamp: timestamp,
            source: existing.source
        )
    }

    public func reorder(scope: QueueScope, orderedIDs: [String]) async throws {
        try ensureOpen()
        guard let index = indices[scope.identifier] else {
            return
        }

        var rebuilt: [ResearchQueueEntry] = []
        var consumed: Set<String> = []
        let timestamp = dateProvider()

        for (offset, id) in orderedIDs.enumerated() {
            guard var entry = index.entriesByID[id] else {
                continue
            }
            entry.order = offset + 1
            entry.lastTouchedAt = timestamp
            rebuilt.append(entry)
            consumed.insert(id)
        }

        let leftover = index.entriesByID.values
            .filter { !consumed.contains($0.id) }
            .sorted { $0.order < $1.order }
        for entry in leftover {
            var copy = entry
            copy.order = rebuilt.count + 1
            rebuilt.append(copy)
        }

        let entriesByID = Dictionary(uniqueKeysWithValues: rebuilt.map { ($0.id, $0) })
        let updatedIndex = ScopeIndex(scope: scope, entriesByID: entriesByID)
        indices[scope.identifier] = updatedIndex

        do {
            try await persist(scope: scope)
        } catch {
            throw error
        }

        await emitDebug(event: "queue.reorder", payload: .object([
            "scope": .string(scope.identifier),
            "count": .number(String(rebuilt.count))
        ]))
        publish(.reordered(scope: scope, count: rebuilt.count))
    }

    public func remove(id: String) async throws {
        try ensureOpen()
        guard let (scopeKey, _) = locate(id: id) else {
            throw ResearchQueueStoreError.unknownID(id)
        }
        guard var index = indices[scopeKey] else {
            throw ResearchQueueStoreError.unknownID(id)
        }
        index.entriesByID[id] = nil
        indices[scopeKey] = index

        try await persist(scope: index.scope)
        await emitDebug(event: "queue.remove", payload: .object([
            "entry_id": .string(redactedID(id)),
            "scope": .string(index.scope.identifier)
        ]))
        publish(.removed(id: id, scope: index.scope))
    }

    // MARK: - Paper status integration

    /// Apply a deterministic transition derived from a `Paper.status` change.
    /// Idempotent: returns silently when no entry matches or when the rule
    /// table maps to the entry's current status. See `DOC/Proposal48.md` §4.10.
    public func applyPaperStatusTransition(
        paperID: String,
        from previous: ReadingStatus?,
        to current: ReadingStatus,
        at timestamp: Date? = nil
    ) async {
        guard isOpen else {
            return
        }
        let touchedAt = timestamp ?? dateProvider()
        let candidates = entries(byPaperID: paperID)
        for entry in candidates {
            guard entry.status != .finished, entry.status != .dismissed else {
                continue
            }
            guard let target = mappedStatus(for: current, currentEntry: entry.status), target != entry.status else {
                continue
            }
            do {
                try await applyStatusChange(
                    scopeKey: entry.scope.identifier,
                    entry: entry,
                    newStatus: target,
                    timestamp: touchedAt,
                    source: .paperStatus,
                    transitionFromPaperStatus: previous,
                    transitionToPaperStatus: current
                )
            } catch {
                await emitDebug(event: "queue.save_error", payload: .object([
                    "scope": .string(entry.scope.identifier),
                    "reason": .string("write_failed")
                ]))
            }
        }
    }

    // MARK: - Subscribers

    public func subscribeChanges() -> AsyncStream<QueueChange> {
        AsyncStream { [weak self] continuation in
            let id = UUID()
            Task { [weak self] in
                await self?.attachSubscriber(id: id, continuation: continuation)
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { [weak self] in
                    await self?.detachSubscriber(id: id)
                }
            }
        }
    }

    private func attachSubscriber(id: UUID, continuation: AsyncStream<QueueChange>.Continuation) {
        subscribers[id] = continuation
    }

    private func detachSubscriber(id: UUID) {
        subscribers[id] = nil
    }

    // MARK: - Internals

    private func ensureOpen() throws {
        guard isOpen else {
            throw ResearchQueueStoreError.storeNotOpen
        }
    }

    private func appendBatchInternal(
        _ entries: [ResearchQueueEntry],
        scope: QueueScope,
        isBatch: Bool
    ) async throws {
        for entry in entries {
            guard entry.scope == scope else {
                throw ResearchQueueStoreError.scopeMismatch(expected: scope.identifier, actual: entry.scope.identifier)
            }
        }

        let scopeKey = scope.identifier
        var index = indices[scopeKey] ?? ScopeIndex(scope: scope, entriesByID: [:])

        for entry in entries {
            if index.entriesByID[entry.id] != nil {
                throw ResearchQueueStoreError.duplicateID(entry.id)
            }
        }

        let baseOrder = (index.entriesByID.values.map(\.order).max() ?? 0)
        let now = dateProvider()
        var insertedOrders: [Int] = []
        for (offset, entry) in entries.enumerated() {
            var copy = entry
            // Preserve caller-supplied non-zero order; otherwise auto-increment.
            if copy.order <= 0 {
                copy.order = baseOrder + offset + 1
            }
            copy.lastTouchedAt = max(entry.lastTouchedAt, now)
            insertedOrders.append(copy.order)
            index.entriesByID[copy.id] = copy
        }
        indices[scopeKey] = index

        try await persist(scope: scope)

        if isBatch {
            await emitDebug(event: "queue.append", payload: .object([
                "scope": .string(scope.identifier),
                "added": .number(String(entries.count)),
                "batch": .bool(true)
            ]))
            publish(.appendedBatch(scope: scope, count: entries.count))
        } else if let single = entries.first {
            await emitDebug(event: "queue.append", payload: .object([
                "scope": .string(scope.identifier),
                "entry_id": .string(redactedID(single.id)),
                "source": .string(single.source.rawValue),
                "has_paper_id": .bool(single.paperID != nil),
                "has_external_key": .bool(single.externalKey != nil)
            ]))
            publish(.appended(id: single.id, scope: scope))
        }
    }

    private func applyStatusChange(
        scopeKey: String,
        entry: ResearchQueueEntry,
        newStatus: QueueStatus,
        timestamp: Date,
        source: QueueSource,
        transitionFromPaperStatus: ReadingStatus? = nil,
        transitionToPaperStatus: ReadingStatus? = nil
    ) async throws {
        guard var index = indices[scopeKey] else {
            throw ResearchQueueStoreError.unknownID(entry.id)
        }
        guard var stored = index.entriesByID[entry.id] else {
            throw ResearchQueueStoreError.unknownID(entry.id)
        }

        let previous = stored.status
        guard previous != newStatus else {
            return
        }

        stored.status = newStatus
        stored.lastTouchedAt = timestamp
        if newStatus == .reading, stored.startedAt == nil {
            stored.startedAt = timestamp
        }
        if newStatus == .finished {
            stored.finishedAt = timestamp
            if stored.startedAt == nil {
                stored.startedAt = timestamp
            }
        }
        index.entriesByID[entry.id] = stored
        indices[scopeKey] = index

        try await persist(scope: index.scope)

        var payload: [String: JSONValue] = [
            "entry_id": .string(redactedID(stored.id)),
            "scope": .string(index.scope.identifier),
            "from": .string(previous.rawValue),
            "to": .string(newStatus.rawValue),
            "source": .string(source.rawValue)
        ]
        if let from = transitionFromPaperStatus {
            payload["paper_status_from"] = .string(from.rawValue)
        }
        if let to = transitionToPaperStatus {
            payload["paper_status_to"] = .string(to.rawValue)
        }
        await emitDebug(event: "queue.status_change", payload: .object(payload))
        publish(.statusChanged(id: stored.id, scope: index.scope, from: previous, to: newStatus))
    }

    private func mappedStatus(for paperStatus: ReadingStatus, currentEntry: QueueStatus) -> QueueStatus? {
        switch paperStatus {
        case .skimmed, .deepRead:
            return currentEntry == .queued ? .reading : nil
        case .summarized, .used:
            return (currentEntry == .queued || currentEntry == .reading) ? .finished : nil
        case .rejected:
            return .dismissed
        case .unread:
            return nil
        }
    }

    private func locate(id: String) -> (String, ResearchQueueEntry)? {
        for (key, index) in indices {
            if let entry = index.entriesByID[id] {
                return (key, entry)
            }
        }
        return nil
    }

    private func sortedEntries(in scope: QueueScope) -> [ResearchQueueEntry] {
        guard let index = indices[scope.identifier] else {
            return []
        }
        return index.entriesByID.values.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.id < rhs.id
        }
    }

    private func topEntries(in scope: QueueScope, limit: Int) -> [ResearchQueueEntry] {
        let activeStatuses: Set<QueueStatus> = [.queued, .reading]
        let cap = max(0, limit)
        let filtered = sortedEntries(in: scope).filter { activeStatuses.contains($0.status) }
        return Array(filtered.prefix(cap))
    }

    private func persist(scope: QueueScope) async throws {
        let index = indices[scope.identifier]
        let entries = index?.entriesByID.values.map { $0 } ?? []
        let yaml = ResearchQueueYAMLEncoder.encode(
            entries: entries,
            scope: scope,
            generatedAt: dateProvider()
        )
        let target = url(for: scope)
        let directory = target.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // `Data.write(options: .atomic)` writes to a temporary file and
            // moves it into place; that gives us the tmp+rename guarantee
            // without re-implementing it here.
            try Data(yaml.utf8).write(to: target, options: .atomic)
        } catch {
            await emitDebug(event: "queue.save_error", payload: .object([
                "scope": .string(scope.identifier),
                "reason": .string("write_failed")
            ]))
            throw error
        }
    }

    private func loadScope(_ scope: QueueScope, from url: URL) async -> ResearchQueueYAMLEncoder.DecodeResult {
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let result = ResearchQueueYAMLEncoder.decode(contents: contents)
            if result.skippedEntryCount > 0 || (result.fileSchemaVersion ?? 1) > ResearchQueueYAMLEncoder.schemaVersion {
                await emitDebug(event: "queue.load.error", payload: .object([
                    "scope": .string(scope.identifier),
                    "skipped": .number(String(result.skippedEntryCount)),
                    "file_schema_version": .number(String(result.fileSchemaVersion ?? 0)),
                    "reason": .string("yaml_parse_failure")
                ]))
            }
            return result
        } catch {
            await emitDebug(event: "queue.load.error", payload: .object([
                "scope": .string(scope.identifier),
                "skipped": .number("0"),
                "reason": .string("io_failure")
            ]))
            return ResearchQueueYAMLEncoder.DecodeResult(entries: [], skippedEntryCount: 0, fileSchemaVersion: nil)
        }
    }

    private func discoverProjectScopes() -> [String] {
        let projectsURL = workspace.rootURL.appendingPathComponent("projects", isDirectory: true)
        guard fileManager.fileExists(atPath: projectsURL.path) else {
            return []
        }
        let candidates = (try? fileManager.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var projectIDs: [String] = []
        for url in candidates {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            let queueURL = url.appendingPathComponent("queue.yaml", isDirectory: false)
            if fileManager.fileExists(atPath: queueURL.path) {
                projectIDs.append(url.lastPathComponent)
            }
        }
        return projectIDs.sorted()
    }

    private func url(for scope: QueueScope) -> URL {
        workspace.fileURL(for: scope.fileRelativePath)
    }

    private func publish(_ change: QueueChange) {
        for continuation in subscribers.values {
            continuation.yield(change)
        }
    }

    private func emitDebug(event: String, payload: JSONValue) async {
        guard let debugLogger else {
            return
        }
        let event = AppDebugEvent(
            event: event,
            workspaceID: workspace.rootURL.path,
            payload: payload
        )
        try? await debugLogger.append(event, in: researchRoot)
    }

    /// Truncate IDs in debug events: the local-part of `queue:<scope>:<paperID>`
    /// can include the user's own `paper_id`, which is expected and not
    /// sensitive, but we cap length to avoid leaking long external keys.
    private func redactedID(_ id: String) -> String {
        guard id.count > 80 else { return id }
        return String(id.prefix(80)) + "…"
    }
}
