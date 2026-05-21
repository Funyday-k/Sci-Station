import Foundation

public nonisolated enum ReadingPlanScope: Hashable, Sendable, Codable {
    case workspace
    case project(String)

    public var identifier: String {
        switch self {
        case .workspace:
            return "workspace"
        case .project(let projectID):
            return "project:\(projectID)"
        }
    }

    public var projectID: String? {
        if case .project(let id) = self {
            return id
        }
        return nil
    }

    public init?(identifier: String) {
        if identifier == "workspace" {
            self = .workspace
            return
        }
        if identifier.hasPrefix("project:") {
            let projectID = String(identifier.dropFirst("project:".count))
            guard !projectID.isEmpty else { return nil }
            self = .project(projectID)
            return
        }
        return nil
    }

    public init(queueScope: QueueScope) {
        switch queueScope {
        case .workspace:
            self = .workspace
        case .project(let projectID):
            self = .project(projectID)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let scope = ReadingPlanScope(identifier: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown reading plan scope: \(raw)")
        }
        self = scope
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
}

public nonisolated enum ReadingPlanStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case draft
    case active
    case archived
}

public nonisolated enum ReadingPlanSlotStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case planned
    case reading
    case finished
    case skipped
    case carriedOver = "carried_over"
}

public nonisolated struct ReadingPlanSlot: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var queueEntryID: String?
    public var paperID: String?
    public var externalKey: String?
    public var displayTitle: String
    public var status: ReadingPlanSlotStatus
    public var plannedDay: String?
    public var estimatedMinutes: Int
    public var actualMinutes: Int?
    public var order: Int
    public var sourceRefs: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        queueEntryID: String? = nil,
        paperID: String? = nil,
        externalKey: String? = nil,
        displayTitle: String,
        status: ReadingPlanSlotStatus = .planned,
        plannedDay: String? = nil,
        estimatedMinutes: Int,
        actualMinutes: Int? = nil,
        order: Int,
        sourceRefs: [String] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.queueEntryID = queueEntryID
        self.paperID = paperID
        self.externalKey = externalKey
        self.displayTitle = displayTitle
        self.status = status
        self.plannedDay = plannedDay
        self.estimatedMinutes = estimatedMinutes
        self.actualMinutes = actualMinutes
        self.order = order
        self.sourceRefs = sourceRefs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case queueEntryID = "queue_entry_id"
        case paperID = "paper_id"
        case externalKey = "external_key"
        case displayTitle = "display_title"
        case status
        case plannedDay = "planned_day"
        case estimatedMinutes = "estimated_minutes"
        case actualMinutes = "actual_minutes"
        case order
        case sourceRefs = "source_refs"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public nonisolated struct ReadingPlan: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var scope: ReadingPlanScope
    public var weekStart: Date
    public var status: ReadingPlanStatus
    public var slots: [ReadingPlanSlot]
    public var sourceRefs: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var activatedAt: Date?
    public var archivedAt: Date?

    public init(
        id: String,
        scope: ReadingPlanScope,
        weekStart: Date,
        status: ReadingPlanStatus,
        slots: [ReadingPlanSlot],
        sourceRefs: [String] = [],
        createdAt: Date,
        updatedAt: Date,
        activatedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.scope = scope
        self.weekStart = weekStart
        self.status = status
        self.slots = slots
        self.sourceRefs = sourceRefs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.activatedAt = activatedAt
        self.archivedAt = archivedAt
    }

    public var completedSlotCount: Int {
        slots.filter { $0.status == .finished }.count
    }

    public var openSlotCount: Int {
        slots.filter { $0.status == .planned || $0.status == .reading || $0.status == .carriedOver }.count
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case scope
        case weekStart = "week_start"
        case status
        case slots
        case sourceRefs = "source_refs"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case activatedAt = "activated_at"
        case archivedAt = "archived_at"
    }
}

public nonisolated struct ReadingPlanSlotSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var queueEntryID: String?
    public var paperID: String?
    public var externalKey: String?
    public var displayTitle: String
    public var status: ReadingPlanSlotStatus
    public var plannedDay: String?
    public var estimatedMinutes: Int
    public var order: Int

    public init(
        id: String,
        queueEntryID: String? = nil,
        paperID: String? = nil,
        externalKey: String? = nil,
        displayTitle: String,
        status: ReadingPlanSlotStatus,
        plannedDay: String? = nil,
        estimatedMinutes: Int,
        order: Int
    ) {
        self.id = id
        self.queueEntryID = queueEntryID
        self.paperID = paperID
        self.externalKey = externalKey
        self.displayTitle = displayTitle
        self.status = status
        self.plannedDay = plannedDay
        self.estimatedMinutes = estimatedMinutes
        self.order = order
    }

    public init(slot: ReadingPlanSlot) {
        self.init(
            id: slot.id,
            queueEntryID: slot.queueEntryID,
            paperID: slot.paperID,
            externalKey: slot.externalKey,
            displayTitle: slot.displayTitle,
            status: slot.status,
            plannedDay: slot.plannedDay,
            estimatedMinutes: slot.estimatedMinutes,
            order: slot.order
        )
    }
}

public nonisolated struct ReadingPlanSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var scopeIdentifier: String
    public var projectID: String?
    public var weekStart: Date
    public var status: ReadingPlanStatus
    public var completedSlotCount: Int
    public var totalSlotCount: Int
    public var estimatedMinutes: Int
    public var slots: [ReadingPlanSlotSummary]
    public var updatedAt: Date

    public init(
        id: String,
        scopeIdentifier: String,
        projectID: String? = nil,
        weekStart: Date,
        status: ReadingPlanStatus,
        completedSlotCount: Int,
        totalSlotCount: Int,
        estimatedMinutes: Int,
        slots: [ReadingPlanSlotSummary],
        updatedAt: Date
    ) {
        self.id = id
        self.scopeIdentifier = scopeIdentifier
        self.projectID = projectID
        self.weekStart = weekStart
        self.status = status
        self.completedSlotCount = completedSlotCount
        self.totalSlotCount = totalSlotCount
        self.estimatedMinutes = estimatedMinutes
        self.slots = slots
        self.updatedAt = updatedAt
    }

    public init(plan: ReadingPlan, slotLimit: Int = 5) {
        let sortedSlots = plan.slots.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.createdAt < rhs.createdAt
        }
        self.init(
            id: plan.id,
            scopeIdentifier: plan.scope.identifier,
            projectID: plan.scope.projectID,
            weekStart: plan.weekStart,
            status: plan.status,
            completedSlotCount: plan.completedSlotCount,
            totalSlotCount: plan.slots.count,
            estimatedMinutes: plan.slots.reduce(0) { $0 + max(0, $1.estimatedMinutes) },
            slots: sortedSlots.prefix(slotLimit).map(ReadingPlanSlotSummary.init(slot:)),
            updatedAt: plan.updatedAt
        )
    }
}

public nonisolated struct ReadingPlanSettings: Codable, Hashable, Sendable {
    public var weeklyCapacityMinutes: Int
    public var defaultSlotMinutes: Int
    public var maxPapersPerWeek: Int
    public var preferredReadingDays: [String]
    public var autoCarryOver: Bool
    public var createTodosByDefault: Bool

    public init(
        weeklyCapacityMinutes: Int = 240,
        defaultSlotMinutes: Int = 60,
        maxPapersPerWeek: Int = 4,
        preferredReadingDays: [String] = ["Mon", "Wed", "Fri"],
        autoCarryOver: Bool = true,
        createTodosByDefault: Bool = false
    ) {
        self.weeklyCapacityMinutes = weeklyCapacityMinutes
        self.defaultSlotMinutes = defaultSlotMinutes
        self.maxPapersPerWeek = maxPapersPerWeek
        self.preferredReadingDays = preferredReadingDays
        self.autoCarryOver = autoCarryOver
        self.createTodosByDefault = createTodosByDefault
    }
}

public nonisolated enum ReadingPlanChange: Hashable, Sendable {
    case reloaded(scope: ReadingPlanScope, count: Int)
    case saved(id: String, scope: ReadingPlanScope, status: ReadingPlanStatus)
    case activated(id: String, scope: ReadingPlanScope)
    case slotStatusChanged(planID: String, slotID: String, from: ReadingPlanSlotStatus, to: ReadingPlanSlotStatus)
    case archived(id: String, scope: ReadingPlanScope)
}
