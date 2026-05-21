import Foundation

public nonisolated enum ReadingPlanStoreError: Error, Sendable, Equatable {
    case unknownPlan(String)
    case unknownSlot(String)
    case storeNotOpen
}

public nonisolated struct ReadingPlanSnapshot: Sendable, Hashable {
    public var plansByScope: [String: [ReadingPlan]]

    public init(plansByScope: [String: [ReadingPlan]] = [:]) {
        self.plansByScope = plansByScope
    }

    public var totalCount: Int {
        plansByScope.values.reduce(0) { $0 + $1.count }
    }

    public func activePlan(for scope: ReadingPlanScope) -> ReadingPlan? {
        plansByScope[scope.identifier]?.first { $0.status == .active }
    }
}

public actor ReadingPlanStore {
    private let workspace: ResearchWorkspace
    private let researchRoot: ResearchRoot
    private let fileManager: FileManager
    private let debugLogger: AppDebugEventLogger?
    private let dateProvider: @Sendable () -> Date

    private struct ScopeIndex: Sendable {
        var scope: ReadingPlanScope
        var plansByID: [String: ReadingPlan]
    }

    private var indices: [String: ScopeIndex] = [:]
    private var subscribers: [UUID: AsyncStream<ReadingPlanChange>.Continuation] = [:]
    private var isOpen = false

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

    public func open(projectIDs: [String] = []) async throws {
        guard !isOpen else {
            return
        }

        var loaded: [String: ScopeIndex] = [:]
        var scopes = [ReadingPlanScope.workspace]
        scopes.append(contentsOf: projectIDs.sorted().map(ReadingPlanScope.project))
        for scope in scopes {
            let url = fileURL(for: scope)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            let result = await loadScope(scope, from: url)
            loaded[scope.identifier] = ScopeIndex(
                scope: scope,
                plansByID: Dictionary(uniqueKeysWithValues: result.plans.map { ($0.id, $0) })
            )
        }

        indices = loaded
        isOpen = true
        await emitDebug(event: "reading_plan.load", payload: .object([
            "scope_count": .number(String(indices.count)),
            "total_plans": .number(String(indices.values.reduce(0) { $0 + $1.plansByID.count }))
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

    public func plans(in scope: ReadingPlanScope) -> [ReadingPlan] {
        sortedPlans(in: scope)
    }

    public func activePlan(in scope: ReadingPlanScope) -> ReadingPlan? {
        sortedPlans(in: scope).first { $0.status == .active }
    }

    public func snapshot() -> ReadingPlanSnapshot {
        var byScope: [String: [ReadingPlan]] = [:]
        for (_, index) in indices {
            byScope[index.scope.identifier] = sortedPlans(in: index.scope)
        }
        return ReadingPlanSnapshot(plansByScope: byScope)
    }

    public func save(_ plan: ReadingPlan) async throws {
        try ensureOpen()
        var index = indices[plan.scope.identifier] ?? ScopeIndex(scope: plan.scope, plansByID: [:])
        index.plansByID[plan.id] = plan
        indices[plan.scope.identifier] = index
        try await persist(scope: plan.scope)
        await emitDebug(event: "reading_plan.save", payload: .object([
            "plan_id": .string(plan.id),
            "scope": .string(plan.scope.identifier),
            "status": .string(plan.status.rawValue),
            "slot_count": .number(String(plan.slots.count))
        ]))
        publish(.saved(id: plan.id, scope: plan.scope, status: plan.status))
    }

    public func activate(planID: String, in scope: ReadingPlanScope, at timestamp: Date? = nil) async throws {
        try ensureOpen()
        guard var index = indices[scope.identifier], var plan = index.plansByID[planID] else {
            throw ReadingPlanStoreError.unknownPlan(planID)
        }
        let now = timestamp ?? dateProvider()
        var archivedPrevious = false
        for (id, existing) in index.plansByID where existing.status == .active && id != planID {
            var archived = existing
            archived.status = .archived
            archived.archivedAt = now
            archived.updatedAt = now
            index.plansByID[id] = archived
            archivedPrevious = true
        }
        plan.status = .active
        plan.activatedAt = plan.activatedAt ?? now
        plan.archivedAt = nil
        plan.updatedAt = now
        index.plansByID[plan.id] = plan
        indices[scope.identifier] = index
        try await persist(scope: scope)
        await emitDebug(event: "reading_plan.activate", payload: .object([
            "plan_id": .string(plan.id),
            "scope": .string(scope.identifier),
            "archived_previous": .bool(archivedPrevious)
        ]))
        publish(.activated(id: plan.id, scope: scope))
    }

    public func archive(planID: String, in scope: ReadingPlanScope, at timestamp: Date? = nil) async throws {
        try ensureOpen()
        guard var index = indices[scope.identifier], var plan = index.plansByID[planID] else {
            throw ReadingPlanStoreError.unknownPlan(planID)
        }
        let now = timestamp ?? dateProvider()
        plan.status = .archived
        plan.archivedAt = now
        plan.updatedAt = now
        index.plansByID[plan.id] = plan
        indices[scope.identifier] = index
        try await persist(scope: scope)
        await emitDebug(event: "reading_plan.archive", payload: .object([
            "plan_id": .string(plan.id),
            "scope": .string(scope.identifier)
        ]))
        publish(.archived(id: plan.id, scope: scope))
    }

    public func updateSlotStatus(planID: String, slotID: String, status: ReadingPlanSlotStatus, actualMinutes: Int? = nil, at timestamp: Date? = nil) async throws {
        try ensureOpen()
        guard let (scopeKey, planScope, storedPlan) = locate(planID: planID) else {
            throw ReadingPlanStoreError.unknownPlan(planID)
        }
        guard var index = indices[scopeKey] else {
            throw ReadingPlanStoreError.unknownPlan(planID)
        }
        var plan = storedPlan
        guard let slotIndex = plan.slots.firstIndex(where: { $0.id == slotID }) else {
            throw ReadingPlanStoreError.unknownSlot(slotID)
        }
        let previous = plan.slots[slotIndex].status
        guard previous != status || plan.slots[slotIndex].actualMinutes != actualMinutes else {
            return
        }
        let now = timestamp ?? dateProvider()
        plan.slots[slotIndex].status = status
        plan.slots[slotIndex].actualMinutes = actualMinutes ?? plan.slots[slotIndex].actualMinutes
        plan.slots[slotIndex].updatedAt = now
        plan.updatedAt = now
        index.plansByID[plan.id] = plan
        indices[scopeKey] = index
        try await persist(scope: planScope)
        await emitDebug(event: "reading_plan.slot_status_change", payload: .object([
            "plan_id": .string(plan.id),
            "slot_id": .string(slotID),
            "from": .string(previous.rawValue),
            "to": .string(status.rawValue)
        ]))
        publish(.slotStatusChanged(planID: plan.id, slotID: slotID, from: previous, to: status))
    }

    public func reorderSlots(planID: String, orderedSlotIDs: [String], at timestamp: Date? = nil) async throws {
        try ensureOpen()
        guard let (scopeKey, planScope, storedPlan) = locate(planID: planID) else {
            throw ReadingPlanStoreError.unknownPlan(planID)
        }
        guard var index = indices[scopeKey] else {
            throw ReadingPlanStoreError.unknownPlan(planID)
        }
        let now = timestamp ?? dateProvider()
        var plan = storedPlan
        let slotsByID = Dictionary(uniqueKeysWithValues: plan.slots.map { ($0.id, $0) })
        var rebuilt: [ReadingPlanSlot] = []
        var consumed: Set<String> = []
        for id in orderedSlotIDs {
            guard var slot = slotsByID[id] else { continue }
            slot.order = rebuilt.count + 1
            slot.updatedAt = now
            rebuilt.append(slot)
            consumed.insert(id)
        }
        let leftovers = slotsByID.values.filter { !consumed.contains($0.id) }.sorted { $0.order < $1.order }
        for var slot in leftovers {
            slot.order = rebuilt.count + 1
            rebuilt.append(slot)
        }
        plan.slots = rebuilt
        plan.updatedAt = now
        index.plansByID[plan.id] = plan
        indices[scopeKey] = index
        try await persist(scope: planScope)
        await emitDebug(event: "reading_plan.reorder", payload: .object([
            "plan_id": .string(plan.id),
            "scope": .string(planScope.identifier),
            "slot_count": .number(String(rebuilt.count))
        ]))
        publish(.saved(id: plan.id, scope: planScope, status: plan.status))
    }

    public func subscribeChanges() -> AsyncStream<ReadingPlanChange> {
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

    private func attachSubscriber(id: UUID, continuation: AsyncStream<ReadingPlanChange>.Continuation) {
        subscribers[id] = continuation
    }

    private func detachSubscriber(id: UUID) {
        subscribers[id] = nil
    }

    private func ensureOpen() throws {
        guard isOpen else {
            throw ReadingPlanStoreError.storeNotOpen
        }
    }

    private func locate(planID: String) -> (String, ReadingPlanScope, ReadingPlan)? {
        for (key, index) in indices {
            if let plan = index.plansByID[planID] {
                return (key, index.scope, plan)
            }
        }
        return nil
    }

    private func sortedPlans(in scope: ReadingPlanScope) -> [ReadingPlan] {
        guard let index = indices[scope.identifier] else {
            return []
        }
        return index.plansByID.values.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return statusRank(lhs.status) < statusRank(rhs.status)
            }
            if lhs.weekStart != rhs.weekStart {
                return lhs.weekStart > rhs.weekStart
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private func statusRank(_ status: ReadingPlanStatus) -> Int {
        switch status {
        case .active: return 0
        case .draft: return 1
        case .archived: return 2
        }
    }

    private func persist(scope: ReadingPlanScope) async throws {
        let plans = indices[scope.identifier]?.plansByID.values.map { $0 } ?? []
        let yaml = ReadingPlanYAMLCodec.encode(plans: plans, scope: scope, generatedAt: dateProvider())
        let target = fileURL(for: scope)
        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(yaml.utf8).write(to: target, options: .atomic)
        } catch {
            await emitDebug(event: "reading_plan.save_error", payload: .object([
                "scope": .string(scope.identifier),
                "reason": .string("write_failed")
            ]))
            throw error
        }
    }

    private func loadScope(_ scope: ReadingPlanScope, from url: URL) async -> ReadingPlanYAMLCodec.DecodeResult {
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let result = ReadingPlanYAMLCodec.decode(contents: contents)
            if result.skippedPlanCount > 0 || (result.fileSchemaVersion ?? 1) > ReadingPlanYAMLCodec.schemaVersion {
                await emitDebug(event: "reading_plan.load.error", payload: .object([
                    "scope": .string(scope.identifier),
                    "skipped": .number(String(result.skippedPlanCount)),
                    "file_schema_version": .number(String(result.fileSchemaVersion ?? 0)),
                    "reason": .string("yaml_parse_failure")
                ]))
            }
            return result
        } catch {
            await emitDebug(event: "reading_plan.load.error", payload: .object([
                "scope": .string(scope.identifier),
                "skipped": .number("0"),
                "reason": .string("io_failure")
            ]))
            return ReadingPlanYAMLCodec.DecodeResult(plans: [], skippedPlanCount: 0, fileSchemaVersion: nil)
        }
    }

    private func fileURL(for scope: ReadingPlanScope) -> URL {
        switch scope {
        case .workspace:
            return workspace.fileURL(for: ".sci-station/reading-plans/workspace.yaml")
        case .project(let projectID):
            return workspace.fileURL(for: "projects/\(projectID)/reading-plans/plans.yaml")
        }
    }

    private func publish(_ change: ReadingPlanChange) {
        for continuation in subscribers.values {
            continuation.yield(change)
        }
    }

    private func emitDebug(event: String, payload: JSONValue) async {
        guard let debugLogger else {
            return
        }
        try? await debugLogger.append(AppDebugEvent(event: event, workspaceID: workspace.rootURL.path, payload: payload), in: researchRoot)
    }
}
