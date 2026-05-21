import Foundation

public nonisolated enum ReadingPlanYAMLCodec {
    public static let schemaVersion = 1

    public struct DecodeResult: Sendable {
        public var plans: [ReadingPlan]
        public var skippedPlanCount: Int
        public var fileSchemaVersion: Int?

        public init(plans: [ReadingPlan], skippedPlanCount: Int, fileSchemaVersion: Int?) {
            self.plans = plans
            self.skippedPlanCount = skippedPlanCount
            self.fileSchemaVersion = fileSchemaVersion
        }
    }

    public static func encode(plans: [ReadingPlan], scope: ReadingPlanScope, generatedAt: Date) -> String {
        let formatter = isoFormatter()
        var lines: [String] = []
        lines.append("schema_version: \(schemaVersion)")
        lines.append("scope: \(quoted(scope.identifier))")
        lines.append("generated_at: \(quoted(formatter.string(from: generatedAt)))")
        if plans.isEmpty {
            lines.append("plans: []")
            return lines.joined(separator: "\n") + "\n"
        }
        lines.append("plans:")
        for plan in plans.sorted(by: planSort) {
            lines.append(contentsOf: encodePlan(plan, formatter: formatter))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func decode(contents: String) -> DecodeResult {
        let lines = contents.components(separatedBy: .newlines)
        var fileSchemaVersion: Int?
        var plans: [ReadingPlan] = []
        var skipped = 0
        var cursor = 0
        var insidePlans = false

        while cursor < lines.count {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !insidePlans {
                if trimmed.hasPrefix("schema_version:") {
                    let value = trimmed.replacingOccurrences(of: "schema_version:", with: "").trimmingCharacters(in: .whitespaces)
                    fileSchemaVersion = Int(value)
                } else if trimmed == "plans: []" {
                    return DecodeResult(plans: [], skippedPlanCount: 0, fileSchemaVersion: fileSchemaVersion)
                } else if trimmed == "plans:" {
                    insidePlans = true
                }
                cursor += 1
                continue
            }

            if !trimmed.hasPrefix("- id:") {
                cursor += 1
                continue
            }

            let start = cursor
            let end = endOfBlock(lines: lines, start: start + 1, marker: "- id:", topLevelEnds: true)
            let block = Array(lines[start..<end])
            if let plan = decodePlan(block: block) {
                plans.append(plan)
            } else {
                skipped += 1
            }
            cursor = end
        }

        return DecodeResult(plans: plans, skippedPlanCount: skipped, fileSchemaVersion: fileSchemaVersion)
    }

    private static func encodePlan(_ plan: ReadingPlan, formatter: ISO8601DateFormatter) -> [String] {
        var lines: [String] = []
        lines.append("  - id: \(quoted(plan.id))")
        lines.append("    scope: \(quoted(plan.scope.identifier))")
        lines.append("    week_start: \(quoted(dayFormatter().string(from: plan.weekStart)))")
        lines.append("    status: \(plan.status.rawValue)")
        lines.append("    created_at: \(quoted(formatter.string(from: plan.createdAt)))")
        lines.append("    updated_at: \(quoted(formatter.string(from: plan.updatedAt)))")
        lines.append("    activated_at: \(timestampOrNull(plan.activatedAt, formatter: formatter))")
        lines.append("    archived_at: \(timestampOrNull(plan.archivedAt, formatter: formatter))")
        if plan.sourceRefs.isEmpty {
            lines.append("    source_refs: []")
        } else {
            lines.append("    source_refs:")
            for ref in plan.sourceRefs {
                lines.append("      - \(quoted(ref))")
            }
        }
        if plan.slots.isEmpty {
            lines.append("    slots: []")
        } else {
            lines.append("    slots:")
            for slot in plan.slots.sorted(by: slotSort) {
                lines.append(contentsOf: encodeSlot(slot, formatter: formatter))
            }
        }
        return lines
    }

    private static func encodeSlot(_ slot: ReadingPlanSlot, formatter: ISO8601DateFormatter) -> [String] {
        var lines: [String] = []
        lines.append("      - id: \(quoted(slot.id))")
        lines.append("        queue_entry_id: \(quotedOrNull(slot.queueEntryID))")
        lines.append("        paper_id: \(quotedOrNull(slot.paperID))")
        lines.append("        external_key: \(quotedOrNull(slot.externalKey))")
        lines.append("        display_title: \(quoted(slot.displayTitle))")
        lines.append("        status: \(slot.status.rawValue)")
        lines.append("        planned_day: \(quotedOrNull(slot.plannedDay))")
        lines.append("        estimated_minutes: \(slot.estimatedMinutes)")
        lines.append("        actual_minutes: \(slot.actualMinutes.map(String.init) ?? "")")
        lines.append("        order: \(slot.order)")
        lines.append("        created_at: \(quoted(formatter.string(from: slot.createdAt)))")
        lines.append("        updated_at: \(quoted(formatter.string(from: slot.updatedAt)))")
        if slot.sourceRefs.isEmpty {
            lines.append("        source_refs: []")
        } else {
            lines.append("        source_refs:")
            for ref in slot.sourceRefs {
                lines.append("          - \(quoted(ref))")
            }
        }
        return lines
    }

    private static func decodePlan(block: [String]) -> ReadingPlan? {
        guard let firstLine = block.first else { return nil }
        let trimmedFirst = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmedFirst.hasPrefix("- id:") else { return nil }

        var fields: [String: String] = [:]
        var sourceRefs: [String] = []
        var slots: [ReadingPlanSlot] = []
        fields["id"] = unquoted(trimmedFirst.replacingOccurrences(of: "- id:", with: "").trimmingCharacters(in: .whitespaces))

        var cursor = 1
        while cursor < block.count {
            let line = block[cursor]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                cursor += 1
                continue
            }
            if trimmed == "source_refs:" {
                let parsed = parseIndentedArray(lines: block, start: cursor + 1)
                sourceRefs = parsed.values
                cursor = parsed.nextIndex
                continue
            }
            if trimmed == "source_refs: []" {
                sourceRefs = []
                cursor += 1
                continue
            }
            if trimmed == "slots:" {
                let parsed = decodeSlots(lines: block, start: cursor + 1)
                slots = parsed.slots
                cursor = parsed.nextIndex
                continue
            }
            if trimmed == "slots: []" {
                slots = []
                cursor += 1
                continue
            }
            if let separatorIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
                fields[key] = value
            }
            cursor += 1
        }

        guard
            let id = fields["id"], !id.isEmpty,
            let scopeRaw = fields["scope"].map(unquoted), let scope = ReadingPlanScope(identifier: scopeRaw),
            let weekStartRaw = fields["week_start"].map(unquoted), let weekStart = dayFormatter().date(from: weekStartRaw),
            let statusRaw = fields["status"], let status = ReadingPlanStatus(rawValue: statusRaw),
            let createdAtRaw = fields["created_at"], let createdAt = parseTimestamp(createdAtRaw),
            let updatedAtRaw = fields["updated_at"], let updatedAt = parseTimestamp(updatedAtRaw)
        else {
            return nil
        }

        return ReadingPlan(
            id: id,
            scope: scope,
            weekStart: weekStart,
            status: status,
            slots: slots,
            sourceRefs: sourceRefs,
            createdAt: createdAt,
            updatedAt: updatedAt,
            activatedAt: fields["activated_at"].flatMap(parseOptionalTimestamp),
            archivedAt: fields["archived_at"].flatMap(parseOptionalTimestamp)
        )
    }

    private static func decodeSlots(lines: [String], start: Int) -> (slots: [ReadingPlanSlot], nextIndex: Int) {
        var slots: [ReadingPlanSlot] = []
        var cursor = start
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                cursor += 1
                continue
            }
            if !trimmed.hasPrefix("- id:") {
                break
            }
            let slotStart = cursor
            let slotEnd = endOfBlock(lines: lines, start: slotStart + 1, marker: "- id:", topLevelEnds: false)
            let block = Array(lines[slotStart..<slotEnd])
            if let slot = decodeSlot(block: block) {
                slots.append(slot)
            }
            cursor = slotEnd
        }
        return (slots, cursor)
    }

    private static func decodeSlot(block: [String]) -> ReadingPlanSlot? {
        guard let firstLine = block.first else { return nil }
        let trimmedFirst = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmedFirst.hasPrefix("- id:") else { return nil }
        var fields: [String: String] = [:]
        var sourceRefs: [String] = []
        fields["id"] = unquoted(trimmedFirst.replacingOccurrences(of: "- id:", with: "").trimmingCharacters(in: .whitespaces))

        var cursor = 1
        while cursor < block.count {
            let trimmed = block[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                cursor += 1
                continue
            }
            if trimmed == "source_refs:" {
                let parsed = parseIndentedArray(lines: block, start: cursor + 1)
                sourceRefs = parsed.values
                cursor = parsed.nextIndex
                continue
            }
            if trimmed == "source_refs: []" {
                sourceRefs = []
                cursor += 1
                continue
            }
            if let separatorIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
                fields[key] = value
            }
            cursor += 1
        }

        guard
            let id = fields["id"], !id.isEmpty,
            let displayTitle = fields["display_title"].map(unquoted), !displayTitle.isEmpty,
            let statusRaw = fields["status"], let status = ReadingPlanSlotStatus(rawValue: statusRaw),
            let estimatedMinutesRaw = fields["estimated_minutes"], let estimatedMinutes = Int(estimatedMinutesRaw),
            let orderRaw = fields["order"], let order = Int(orderRaw),
            let createdAtRaw = fields["created_at"], let createdAt = parseTimestamp(createdAtRaw),
            let updatedAtRaw = fields["updated_at"], let updatedAt = parseTimestamp(updatedAtRaw)
        else {
            return nil
        }

        return ReadingPlanSlot(
            id: id,
            queueEntryID: fields["queue_entry_id"].flatMap(parseOptionalScalar),
            paperID: fields["paper_id"].flatMap(parseOptionalScalar),
            externalKey: fields["external_key"].flatMap(parseOptionalScalar),
            displayTitle: displayTitle,
            status: status,
            plannedDay: fields["planned_day"].flatMap(parseOptionalScalar),
            estimatedMinutes: estimatedMinutes,
            actualMinutes: fields["actual_minutes"].flatMap { Int($0) },
            order: order,
            sourceRefs: sourceRefs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func endOfBlock(lines: [String], start: Int, marker: String, topLevelEnds: Bool) -> Int {
        var cursor = start
        while cursor < lines.count {
            let raw = lines[cursor]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if topLevelEnds {
                if raw.hasPrefix("  \(marker)") {
                    return cursor
                }
            } else if trimmed.hasPrefix(marker) {
                return cursor
            }
            if topLevelEnds, !trimmed.isEmpty, raw.prefix(while: { $0 == " " }).count == 0 {
                return cursor
            }
            cursor += 1
        }
        return cursor
    }

    private static func parseIndentedArray(lines: [String], start: Int) -> (values: [String], nextIndex: Int) {
        var values: [String] = []
        var cursor = start
        while cursor < lines.count {
            let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                cursor += 1
                continue
            }
            if !trimmed.hasPrefix("-") {
                break
            }
            let literal = trimmed.replacingOccurrences(of: "-", with: "", options: [], range: trimmed.startIndex..<trimmed.index(after: trimmed.startIndex)).trimmingCharacters(in: .whitespaces)
            values.append(unquoted(literal))
            cursor += 1
        }
        return (values, cursor)
    }

    private static func planSort(_ lhs: ReadingPlan, _ rhs: ReadingPlan) -> Bool {
        if lhs.weekStart != rhs.weekStart {
            return lhs.weekStart > rhs.weekStart
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func slotSort(_ lhs: ReadingPlanSlot, _ rhs: ReadingPlanSlot) -> Bool {
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.createdAt < rhs.createdAt
    }

    private static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        parseOptionalTimestamp(value)
    }

    private static func parseOptionalTimestamp(_ value: String) -> Date? {
        let parsed = parseOptionalScalar(value)
        return parsed.flatMap { isoFormatter().date(from: $0) }
    }

    private static func timestampOrNull(_ date: Date?, formatter: ISO8601DateFormatter) -> String {
        guard let date else { return "" }
        return quoted(formatter.string(from: date))
    }

    private static func quotedOrNull(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        return quoted(value)
    }

    private static func parseOptionalScalar(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "null" else { return nil }
        return unquoted(trimmed)
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }
        let start = value.index(after: value.startIndex)
        let end = value.index(before: value.endIndex)
        return value[start..<end]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
