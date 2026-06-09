import Foundation

/// Quick date suggestions shown next to the date button in the task composer,
/// mirroring Apple Reminders' "今天 / 明天 / 本周末 / 下周 / 自定义" list.
public enum TodoDatePreset: String, CaseIterable, Identifiable, Sendable {
    case today
    case tomorrow
    case thisWeekend
    case nextWeek

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today:
            return "今天"
        case .tomorrow:
            return "明天"
        case .thisWeekend:
            return "本周末"
        case .nextWeek:
            return "下周"
        }
    }

    public var englishLabel: String {
        switch self {
        case .today:
            return "Today"
        case .tomorrow:
            return "Tomorrow"
        case .thisWeekend:
            return "This Weekend"
        case .nextWeek:
            return "Next Week"
        }
    }

    public var systemImage: String {
        switch self {
        case .today:
            return "sun.max"
        case .tomorrow:
            return "sunrise"
        case .thisWeekend:
            return "beach.umbrella"
        case .nextWeek:
            return "calendar.badge.clock"
        }
    }

    /// Resolves the concrete calendar day for this preset relative to `base`.
    ///
    /// - today: start of `base`.
    /// - tomorrow: the next day.
    /// - thisWeekend: the coming Saturday (or today if `base` is already Saturday).
    /// - nextWeek: the next Monday (always strictly after `base`).
    public func date(from base: Date = Date(), calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: base)
        switch self {
        case .today:
            return startOfToday
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        case .thisWeekend:
            return Self.nextOrSame(weekday: 7, from: startOfToday, calendar: calendar)
        case .nextWeek:
            return Self.next(weekday: 2, strictlyAfter: startOfToday, calendar: calendar)
        }
    }

    /// Returns `start` if it already matches `weekday`, otherwise the next match.
    private static func nextOrSame(weekday: Int, from start: Date, calendar: Calendar) -> Date {
        if calendar.component(.weekday, from: start) == weekday {
            return start
        }
        return next(weekday: weekday, strictlyAfter: start, calendar: calendar)
    }

    private static func next(weekday: Int, strictlyAfter start: Date, calendar: Calendar) -> Date {
        let components = DateComponents(weekday: weekday)
        let next = calendar.nextDate(
            after: start,
            matching: components,
            matchingPolicy: .nextTime
        )
        return next.map { calendar.startOfDay(for: $0) } ?? start
    }
}
