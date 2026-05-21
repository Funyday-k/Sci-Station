import Foundation

public nonisolated struct ReadingPlanGenerationInput: Sendable, Hashable {
    public var scope: ReadingPlanScope
    public var weekStart: Date
    public var queueEntries: [ResearchQueueEntry]
    public var existingPlans: [ReadingPlan]
    public var settings: ReadingPlanSettings
    public var now: Date

    public init(
        scope: ReadingPlanScope,
        weekStart: Date,
        queueEntries: [ResearchQueueEntry],
        existingPlans: [ReadingPlan] = [],
        settings: ReadingPlanSettings = ReadingPlanSettings(),
        now: Date = Date()
    ) {
        self.scope = scope
        self.weekStart = weekStart
        self.queueEntries = queueEntries
        self.existingPlans = existingPlans
        self.settings = settings
        self.now = now
    }
}

public nonisolated struct ReadingPlanGenerator: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = ReadingPlanGenerator.defaultCalendar()) {
        self.calendar = calendar
    }

    public nonisolated static func defaultCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    public func generate(input: ReadingPlanGenerationInput) -> ReadingPlan {
        let weekStart = normalizedWeekStart(input.weekStart)
        let selectedEntries = selectEntries(input: input)
        let slotMinutes = max(15, input.settings.defaultSlotMinutes)
        let days = input.settings.preferredReadingDays.isEmpty ? ["Mon", "Wed", "Fri"] : input.settings.preferredReadingDays
        let slots = selectedEntries.enumerated().map { offset, entry in
            ReadingPlanSlot(
                id: "slot-\(stableSlug(entry.id))-\(offset + 1)",
                queueEntryID: entry.id,
                paperID: entry.paperID,
                externalKey: entry.externalKey,
                displayTitle: entry.displayTitle,
                status: .planned,
                plannedDay: days[offset % days.count],
                estimatedMinutes: slotMinutes,
                order: offset + 1,
                sourceRefs: ["queue:\(entry.id)"] + entry.sourceRefs,
                createdAt: input.now,
                updatedAt: input.now
            )
        }
        let id = planID(scope: input.scope, weekStart: weekStart)
        return ReadingPlan(
            id: id,
            scope: input.scope,
            weekStart: weekStart,
            status: .draft,
            slots: slots,
            sourceRefs: slots.compactMap(\.queueEntryID).map { "queue:\($0)" },
            createdAt: input.now,
            updatedAt: input.now
        )
    }

    public func normalizedWeekStart(_ date: Date) -> Date {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
            return calendar.startOfDay(for: interval.start)
        }
        return calendar.startOfDay(for: date)
    }

    private func selectEntries(input: ReadingPlanGenerationInput) -> [ResearchQueueEntry] {
        let slotMinutes = max(15, input.settings.defaultSlotMinutes)
        let capacityLimit = max(1, input.settings.weeklyCapacityMinutes / slotMinutes)
        let countLimit = max(1, min(input.settings.maxPapersPerWeek, capacityLimit))
        let existingActiveIDs = Set(input.existingPlans
            .filter { $0.status == .active || $0.status == .draft }
            .flatMap { $0.slots.compactMap(\.queueEntryID) })
        let carriedOverIDs = input.settings.autoCarryOver
            ? input.existingPlans.flatMap { $0.slots.filter { $0.status == .skipped || $0.status == .carriedOver }.compactMap(\.queueEntryID) }
            : []
        let carriedOverSet = Set(carriedOverIDs)
        return input.queueEntries
            .filter { entry in
                guard entry.status == .reading || entry.status == .queued else {
                    return false
                }
                return !existingActiveIDs.contains(entry.id) || carriedOverSet.contains(entry.id)
            }
            .sorted { lhs, rhs in
                let lhsRank = rank(entry: lhs, carriedOverSet: carriedOverSet)
                let rhsRank = rank(entry: rhs, carriedOverSet: carriedOverSet)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                if lhs.lastTouchedAt != rhs.lastTouchedAt {
                    return lhs.lastTouchedAt > rhs.lastTouchedAt
                }
                return lhs.id < rhs.id
            }
            .prefix(countLimit)
            .map { $0 }
    }

    private func rank(entry: ResearchQueueEntry, carriedOverSet: Set<String>) -> Int {
        if carriedOverSet.contains(entry.id) {
            return 0
        }
        switch entry.status {
        case .reading:
            return 1
        case .queued:
            return 2
        case .deferred:
            return 3
        case .finished, .dismissed:
            return 4
        }
    }

    private func planID(scope: ReadingPlanScope, weekStart: Date) -> String {
        let day = dayFormatter().string(from: weekStart)
        return "reading-plan-\(stableSlug(scope.identifier))-\(day)"
    }

    private func stableSlug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var result = ""
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("-")
            }
        }
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
