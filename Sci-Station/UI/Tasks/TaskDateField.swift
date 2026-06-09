import SwiftUI

/// Calendar-icon date button (gray when unset, blue when a date/range is set).
/// Tapping opens a popover with quick presets (今天/明天/本周末/下周) and a
/// custom range calendar where repeated taps select a date span.
struct TaskDateField: View {
    @EnvironmentObject private var appModel: AppViewModel

    @Binding var startDate: Date?
    @Binding var dueDate: Date?

    @State private var isPresentingPopover = false

    private var hasDate: Bool { dueDate != nil }

    var body: some View {
        Button {
            isPresentingPopover = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                if hasDate {
                    Text(summaryText)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                } else {
                    Text(appModel.localized("添加日期", "Add Date"))
                        .font(.callout)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(hasDate ? Color.white : Color.secondary)
            .background(
                Capsule().fill(hasDate ? Color.accentColor : SciStationDesign.subtleSurface)
            )
            .overlay(
                Capsule().stroke(hasDate ? Color.clear : SciStationDesign.hairline, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresentingPopover, arrowEdge: .bottom) {
            TaskDatePopover(startDate: $startDate, dueDate: $dueDate)
                .environmentObject(appModel)
        }
    }

    private var summaryText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        guard let due = dueDate else { return "" }
        if let start = startDate, !Calendar.current.isDate(start, inSameDayAs: due), start < due {
            return "\(formatter.string(from: start)) – \(formatter.string(from: due))"
        }
        return formatter.string(from: due)
    }
}

private struct TaskDatePopover: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Binding var startDate: Date?
    @Binding var dueDate: Date?

    @State private var showsCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsCustom {
                customSection
            } else {
                presetSection
            }
        }
        .padding(14)
        .frame(width: 290)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appModel.localized("建议", "Suggestions"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(TodoDatePreset.allCases) { preset in
                presetRow(preset)
            }

            Divider().padding(.vertical, 4)

            Button {
                withAnimation(.snappy(duration: 0.15)) { showsCustom = true }
            } label: {
                presetLabel(
                    systemImage: "calendar.badge.plus",
                    title: appModel.localized("自定义…", "Custom…"),
                    subtitle: appModel.localized("用日历挑选日期段", "Pick a date or range")
                )
            }
            .buttonStyle(.plain)

            if dueDate != nil {
                Button(role: .destructive) {
                    startDate = nil
                    dueDate = nil
                } label: {
                    Label(appModel.localized("清除日期", "Clear Date"), systemImage: "xmark.circle")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private func presetRow(_ preset: TodoDatePreset) -> some View {
        let date = preset.date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d"
        return Button {
            startDate = nil
            dueDate = date
        } label: {
            presetLabel(
                systemImage: preset.systemImage,
                title: appModel.localized(preset.label, preset.englishLabel),
                subtitle: formatter.string(from: date)
            )
        }
        .buttonStyle(.plain)
    }

    private func presetLabel(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(SciStationDesign.subtleSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    withAnimation(.snappy(duration: 0.15)) { showsCustom = false }
                } label: {
                    Label(appModel.localized("建议", "Suggestions"), systemImage: "chevron.left")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(appModel.localized("可多次点击选择日期段", "Tap twice for a range"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            TaskRangeCalendar(startDate: $startDate, dueDate: $dueDate)
        }
    }
}

/// Month grid that supports single-day and range selection by repeated taps.
struct TaskRangeCalendar: View {
    @Binding var startDate: Date?
    @Binding var dueDate: Date?

    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(monthDays, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .onAppear {
            if let due = dueDate {
                displayedMonth = calendar.startOfDay(for: due)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            Spacer()
            Text(monthTitle)
                .font(.callout.weight(.semibold))
            Spacer()
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let isInRange = isWithinRange(day)
            let isEndpoint = isEndpoint(day)
            Button {
                select(day)
            } label: {
                Text("\(calendar.component(.day, from: day))")
                    .font(.caption)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .foregroundStyle(isEndpoint ? Color.white : (isInRange ? Color.accentColor : Color.primary))
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isEndpoint ? Color.accentColor : (isInRange ? Color.accentColor.opacity(0.18) : Color.clear))
                    )
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 28)
        }
    }

    private func select(_ day: Date) {
        let normalized = calendar.startOfDay(for: day)
        // No start, or a complete range exists -> begin a fresh selection.
        if startDate == nil || dueDate == nil || (startDate != nil && dueDate != nil && startDate != dueDate) {
            startDate = normalized
            dueDate = normalized
            return
        }
        // Exactly one anchor day set (startDate == dueDate): extend into a range.
        if let anchor = startDate {
            if normalized < anchor {
                startDate = normalized
                dueDate = anchor
            } else {
                dueDate = normalized
            }
        }
    }

    private func isEndpoint(_ day: Date) -> Bool {
        guard let start = startDate, let due = dueDate else { return false }
        return calendar.isDate(day, inSameDayAs: start) || calendar.isDate(day, inSameDayAs: due)
    }

    private func isWithinRange(_ day: Date) -> Bool {
        guard let start = startDate, let due = dueDate else { return false }
        let normalized = calendar.startOfDay(for: day)
        return normalized >= calendar.startOfDay(for: start) && normalized <= calendar.startOfDay(for: due)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var monthDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeekday = calendar.dateComponents([.weekday], from: monthInterval.start).weekday else {
            return []
        }
        let leadingBlanks = firstWeekday - 1
        let daysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<daysInMonth {
            cells.append(calendar.date(byAdding: .day, value: offset, to: monthInterval.start))
        }
        return cells
    }
}

#if DEBUG
#Preview("Task Date Field") {
    struct Harness: View {
        @State private var start: Date?
        @State private var due: Date?
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                TaskDateField(startDate: $start, dueDate: $due)
                TaskRangeCalendar(startDate: $start, dueDate: $due)
                    .frame(width: 280)
            }
            .padding(24)
            .environmentObject(AppViewModel())
        }
    }
    return Harness()
}
#endif
