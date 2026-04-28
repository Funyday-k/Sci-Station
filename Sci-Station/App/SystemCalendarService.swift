import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(EventKit)
@preconcurrency import EventKit
#endif

enum SystemCalendarAccessState: Equatable {
    case unavailable
    case notDetermined
    case authorized
    case denied
    case restricted

    var canReadSchedule: Bool {
        self == .authorized
    }

    var label: String {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .notDetermined:
            return "Connect"
        case .authorized:
            return "Connected"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }
}

struct SystemScheduleItem: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case event
        case reminder

        var label: String {
            switch self {
            case .event:
                return "Calendar"
            case .reminder:
                return "Reminder"
            }
        }

        var systemImage: String {
            switch self {
            case .event:
                return "calendar"
            case .reminder:
                return "bell"
            }
        }
    }

    var id: String
    var title: String
    var kind: Kind
    var startDate: Date
    var endDate: Date?
    var calendarTitle: String?
    var calendarColorHex: String?
    var notes: String?
    var isCompleted: Bool
    var isHoliday: Bool

    var displayDate: Date {
        startDate
    }

    var categoryName: String {
        if isHoliday {
            return "Holiday"
        }

        let trimmedCalendarTitle = calendarTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmedCalendarTitle?.isEmpty == false ? trimmedCalendarTitle : nil) ?? kind.label
    }
}

enum SystemCalendarServiceError: LocalizedError {
    case accessDenied
    case reminderCalendarUnavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar or Reminders access has not been granted."
        case .reminderCalendarUnavailable:
            return "No default Apple Reminders list is available."
        }
    }
}

@MainActor
final class SystemCalendarService {
#if canImport(EventKit)
    private let eventStore = EKEventStore()
#endif

    var accessState: SystemCalendarAccessState {
#if canImport(EventKit)
        combinedAccessState()
#else
        .unavailable
#endif
    }

    var canCreateReminders: Bool {
#if canImport(EventKit)
        Self.isGranted(EKEventStore.authorizationStatus(for: .reminder))
#else
        false
#endif
    }

    func requestAccess() async throws -> SystemCalendarAccessState {
#if canImport(EventKit)
        _ = try await requestAccess(to: .event)
        _ = try await requestAccess(to: .reminder)
        return combinedAccessState()
#else
        return .unavailable
#endif
    }

    func loadItems(from startDate: Date, to endDate: Date) async throws -> [SystemScheduleItem] {
#if canImport(EventKit)
        guard accessState.canReadSchedule else {
            return []
        }

        var items: [SystemScheduleItem] = []

        if Self.isGranted(EKEventStore.authorizationStatus(for: .event)) {
            let predicate = eventStore.predicateForEvents(
                withStart: startDate,
                end: endDate,
                calendars: eventStore.calendars(for: .event)
            )
            items += eventStore.events(matching: predicate).map { event in
                SystemScheduleItem(
                    id: "event-\(event.eventIdentifier ?? event.calendarItemIdentifier)",
                    title: event.title ?? "Untitled Event",
                    kind: .event,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    calendarTitle: event.calendar?.title,
                    calendarColorHex: Self.colorHex(from: event.calendar?.cgColor),
                    notes: event.notes,
                    isCompleted: false,
                    isHoliday: Self.isHoliday(title: event.title, calendarTitle: event.calendar?.title)
                )
            }
        }

        if Self.isGranted(EKEventStore.authorizationStatus(for: .reminder)) {
            let predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: startDate,
                ending: endDate,
                calendars: nil
            )
            let reminders = try await fetchReminders(matching: predicate)
            items += reminders.compactMap { reminder in
                guard let dueDate = reminder.dueDateComponents?.date else {
                    return nil
                }

                return SystemScheduleItem(
                    id: "reminder-\(reminder.calendarItemIdentifier)",
                    title: reminder.title,
                    kind: .reminder,
                    startDate: dueDate,
                    endDate: nil,
                    calendarTitle: reminder.calendar?.title,
                    calendarColorHex: Self.colorHex(from: reminder.calendar?.cgColor),
                    notes: reminder.notes,
                    isCompleted: reminder.isCompleted,
                    isHoliday: false
                )
            }
        }

        return items.sorted { first, second in
            if first.startDate == second.startDate {
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            }
            return first.startDate < second.startDate
        }
#else
        return []
#endif
    }

    func createReminder(title: String, dueDate: Date?, notes: String?) async throws -> SystemScheduleItem? {
#if canImport(EventKit)
        guard canCreateReminders else {
            throw SystemCalendarServiceError.accessDenied
        }
        guard let defaultCalendar = eventStore.defaultCalendarForNewReminders() else {
            throw SystemCalendarServiceError.reminderCalendarUnavailable
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = defaultCalendar

        if let dueDate {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
            components.calendar = Calendar.current
            reminder.dueDateComponents = components
        }

        try eventStore.save(reminder, commit: true)

        return SystemScheduleItem(
            id: "reminder-\(reminder.calendarItemIdentifier)",
            title: reminder.title,
            kind: .reminder,
            startDate: dueDate ?? Date(),
            endDate: nil,
            calendarTitle: defaultCalendar.title,
            calendarColorHex: Self.colorHex(from: defaultCalendar.cgColor),
            notes: reminder.notes,
            isCompleted: false,
            isHoliday: false
        )
#else
        return nil
#endif
    }

    private nonisolated static func isHoliday(title: String?, calendarTitle: String?) -> Bool {
        let candidates = [title, calendarTitle]
            .compactMap { $0?.lowercased() }
        return candidates.contains { value in
            value.contains("holiday") || value.contains("holidays") || value.contains("节假日") || value.contains("假日")
        }
    }

    private nonisolated static func colorHex(from color: CGColor?) -> String? {
        guard let color else {
            return nil
        }

#if canImport(AppKit)
        guard let nsColor = NSColor(cgColor: color)?.usingColorSpace(.sRGB) else {
            return nil
        }

        let red = Int(round(nsColor.redComponent * 255))
        let green = Int(round(nsColor.greenComponent * 255))
        let blue = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
#else
        return nil
#endif
    }

#if canImport(EventKit)
    private func requestAccess(to entityType: EKEntityType) async throws -> Bool {
        switch entityType {
        case .event:
            return try await eventStore.requestFullAccessToEvents()
        case .reminder:
            return try await eventStore.requestFullAccessToReminders()
        @unknown default:
            return false
        }
    }

    private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func combinedAccessState() -> SystemCalendarAccessState {
        let eventStatus = EKEventStore.authorizationStatus(for: .event)
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)

        if Self.isGranted(eventStatus) || Self.isGranted(reminderStatus) {
            return .authorized
        }
        if eventStatus == .notDetermined || reminderStatus == .notDetermined {
            return .notDetermined
        }
        if eventStatus == .restricted || reminderStatus == .restricted {
            return .restricted
        }
        return .denied
    }

    private static func isGranted(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .authorized:
            return true
        case .fullAccess:
            return true
        default:
            return false
        }
    }
#endif
}
