import CryptoKit
import Foundation

public nonisolated enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .number(String(intValue))
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .number(Self.normalizedNumber(doubleValue))
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: JSONValue].self) {
            self = .object(objectValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            if let intValue = Int(value) {
                try container.encode(intValue)
            } else if let doubleValue = Double(value), doubleValue.isFinite {
                try container.encode(doubleValue)
            } else {
                try container.encode(value)
            }
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public nonisolated static func parse(_ rawJSON: String) throws -> JSONValue {
        let trimmed = rawJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw AgentError.invalidArguments("tool arguments must be UTF-8 JSON")
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try fromJSONObject(object)
    }

    public nonisolated static func fromJSONObject(_ object: Any) throws -> JSONValue {
        if object is NSNull {
            return .null
        }
        if let dictionary = object as? [String: Any] {
            var values: [String: JSONValue] = [:]
            for key in dictionary.keys.sorted() {
                values[key] = try fromJSONObject(dictionary[key] as Any)
            }
            return .object(values)
        }
        if let array = object as? [Any] {
            return .array(try array.map(fromJSONObject))
        }
        if let string = object as? String {
            return .string(string.precomposedStringWithCanonicalMapping)
        }
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(normalizedNumber(number.doubleValue))
        }
        throw AgentError.invalidArguments("Unsupported JSON value in tool arguments.")
    }

    public nonisolated var canonicalJSON: String {
        switch self {
        case let .object(value):
            let fields = value.keys.sorted().map { key in
                Self.encodedJSONString(key) + ":" + (value[key]?.canonicalJSON ?? "null")
            }
            return "{" + fields.joined(separator: ",") + "}"
        case let .array(value):
            return "[" + value.map(\.canonicalJSON).joined(separator: ",") + "]"
        case let .string(value):
            return Self.encodedJSONString(value.precomposedStringWithCanonicalMapping)
        case let .number(value):
            return value
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }

    public nonisolated var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    public nonisolated var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    private nonisolated static func encodedJSONString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let encodedArray = String(data: data, encoding: .utf8),
              encodedArray.count >= 2 else {
            return "\"\(value)\""
        }
        return String(encodedArray.dropFirst().dropLast())
    }

    private nonisolated static func normalizedNumber(_ value: Double) -> String {
        guard value.isFinite else {
            return "0"
        }
        if value.rounded(.towardZero) == value,
           value <= Double(Int64.max),
           value >= Double(Int64.min) {
            return String(Int64(value))
        }
        return String(format: "%.15g", value)
    }
}

public nonisolated struct AgentToolArguments: Codable, Hashable, Sendable {
    public var rawJSON: String
    public var canonicalJSON: String
    public var value: JSONValue

    public nonisolated init(rawJSON: String) throws {
        let value = try JSONValue.parse(rawJSON)
        guard value.objectValue != nil else {
            throw AgentError.invalidArguments("tool arguments must be a JSON object")
        }
        self.rawJSON = rawJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        self.canonicalJSON = value.canonicalJSON
        self.value = value
    }

    public nonisolated init(value: JSONValue) throws {
        guard value.objectValue != nil else {
            throw AgentError.invalidArguments("tool arguments must be a JSON object")
        }
        self.rawJSON = value.canonicalJSON
        self.canonicalJSON = value.canonicalJSON
        self.value = value
    }

    public nonisolated static var emptyObject: AgentToolArguments {
        try! AgentToolArguments(rawJSON: "{}")
    }

    private enum CodingKeys: String, CodingKey {
        case rawJSON = "raw_json"
        case canonicalJSON = "canonical_json"
        case value
    }
}

public nonisolated struct AgentRollbackHint: Codable, Hashable, Sendable {
    public var summary: String
    public var targetPaths: [String]

    public nonisolated init(summary: String, targetPaths: [String] = []) {
        self.summary = summary
        self.targetPaths = targetPaths
    }

    private enum CodingKeys: String, CodingKey {
        case summary
        case targetPaths = "target_paths"
    }
}

public nonisolated struct AgentEvidenceRef: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var sourceType: String?
    public var sourceID: String?
    public var relativePath: String?
    public var lines: [Int]
    public var sourceHash: String?
    public var chunkID: String?
    public var retrievedAt: Date?
    public var heading: String?
    public var quote: String?
    public var confidence: Double?

    public nonisolated init(
        id: String = "evidence-\(UUID().uuidString.lowercased())",
        sourceType: String? = nil,
        sourceID: String? = nil,
        relativePath: String? = nil,
        lines: [Int] = [],
        sourceHash: String? = nil,
        chunkID: String? = nil,
        retrievedAt: Date? = nil,
        heading: String? = nil,
        quote: String? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.relativePath = relativePath
        self.lines = lines
        self.sourceHash = sourceHash
        self.chunkID = chunkID
        self.retrievedAt = retrievedAt
        self.heading = heading
        self.quote = quote
        self.confidence = confidence
    }

    public nonisolated init(
        sourceType: String,
        sourceID: String? = nil,
        relativePath: String,
        startLine: Int,
        endLine: Int,
        sourceHash: String,
        chunkID: String? = nil,
        retrievedAt: Date? = Date(),
        heading: String? = nil,
        quote: String? = nil,
        confidence: Double? = nil
    ) {
        self.init(
            id: Self.stableID(
                sourceType: sourceType,
                sourceID: sourceID,
                relativePath: relativePath,
                startLine: startLine,
                endLine: endLine,
                sourceHash: sourceHash
            ),
            sourceType: sourceType,
            sourceID: sourceID,
            relativePath: relativePath,
            lines: [startLine, endLine],
            sourceHash: sourceHash,
            chunkID: chunkID,
            retrievedAt: retrievedAt,
            heading: heading,
            quote: quote,
            confidence: confidence
        )
    }

    public nonisolated static func stableID(
        sourceType: String,
        sourceID: String? = nil,
        relativePath: String,
        startLine: Int,
        endLine: Int,
        sourceHash: String
    ) -> String {
        AgentToolCallFingerprint.stableHash([
            sourceType,
            sourceID ?? "",
            relativePath,
            String(startLine),
            String(endLine),
            sourceHash
        ].joined(separator: "\u{1f}"))
    }

    public nonisolated func isStale(currentSourceHash: String?) -> Bool {
        guard let sourceHash, let currentSourceHash else {
            return false
        }
        return sourceHash != currentSourceHash
    }

    public nonisolated func sourceJump(in root: ResearchRoot, currentSourceHash: String? = nil) -> AgentEvidenceSourceJump {
        guard let relativePath, !relativePath.isEmpty else {
            return AgentEvidenceSourceJump(
                evidenceID: id,
                sourceType: sourceType,
                sourceID: sourceID,
                relativePath: nil,
                sourceURL: nil,
                startLine: lines.first,
                endLine: lines.dropFirst().first,
                status: .missingSource,
                warning: "Evidence has no relative source path."
            )
        }

        let url = root.fileURL(for: relativePath)
        let exists = FileManager.default.fileExists(atPath: url.path)
        let status: AgentEvidenceSourceStatus
        let warning: String?
        if !exists {
            status = .missingSource
            warning = "Missing source: \(relativePath)"
        } else if isStale(currentSourceHash: currentSourceHash) {
            status = .stale
            warning = "Source changed since this evidence was retrieved."
        } else {
            status = .available
            warning = nil
        }
        let pdfTarget = Self.pdfPageTarget(for: relativePath, startLine: lines.first, in: root)

        return AgentEvidenceSourceJump(
            evidenceID: id,
            sourceType: sourceType,
            sourceID: sourceID,
            relativePath: relativePath,
            sourceURL: exists ? url : nil,
            startLine: lines.first,
            endLine: lines.dropFirst().first,
            status: status,
            warning: warning,
            pdfRelativePath: pdfTarget?.relativePath,
            pdfURL: pdfTarget?.url,
            pdfPage: pdfTarget?.page
        )
    }

    private nonisolated static func pdfPageTarget(for relativePath: String, startLine: Int?, in root: ResearchRoot) -> (relativePath: String, url: URL, page: Int)? {
        guard let startLine, relativePath.hasSuffix("/paper.md") || relativePath.hasSuffix("/annotations.md") else {
            return nil
        }
        let directoryPath = relativePath.split(separator: "/").dropLast().joined(separator: "/")
        let mappingNames = ["paper_page_map.json", "page_mapping.json", "markdown_page_map.json"]
        for mappingName in mappingNames {
            let mappingRelativePath = directoryPath + "/" + mappingName
            let mappingURL = root.fileURL(for: mappingRelativePath)
            guard let data = try? Data(contentsOf: mappingURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let target = targetFromMappingObject(object, startLine: startLine, directoryPath: directoryPath, root: root) {
                return target
            }
        }
        return nil
    }

    private nonisolated static func targetFromMappingObject(_ object: [String: Any], startLine: Int, directoryPath: String, root: ResearchRoot) -> (relativePath: String, url: URL, page: Int)? {
        if let linePages = object["line_pages"] as? [String: Any] {
            let page = (linePages[String(startLine)] as? NSNumber)?.intValue
                ?? (linePages[String(startLine)] as? String).flatMap(Int.init)
            if let page {
                return pdfTarget(relativePath: object["pdf_relative_path"] as? String, directoryPath: directoryPath, page: page, root: root)
            }
        }
        let candidates = (object["mappings"] as? [[String: Any]]) ?? (object["pages"] as? [[String: Any]]) ?? []
        for candidate in candidates {
            let start = intValue(candidate["start_line"]) ?? intValue(candidate["startLine"]) ?? intValue(candidate["line"]) ?? 1
            let end = intValue(candidate["end_line"]) ?? intValue(candidate["endLine"]) ?? start
            guard startLine >= start && startLine <= end, let page = intValue(candidate["page"]) else {
                continue
            }
            return pdfTarget(relativePath: candidate["pdf_relative_path"] as? String, directoryPath: directoryPath, page: page, root: root)
        }
        return nil
    }

    private nonisolated static func pdfTarget(relativePath: String?, directoryPath: String, page: Int, root: ResearchRoot) -> (relativePath: String, url: URL, page: Int)? {
        let resolvedRelativePath = relativePath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? directoryPath + "/paper.pdf"
        let url = root.fileURL(for: resolvedRelativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return (resolvedRelativePath, url, max(page, 1))
    }

    private nonisolated static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceType = "source_type"
        case sourceID = "source_id"
        case relativePath = "relative_path"
        case lines
        case sourceHash = "source_hash"
        case chunkID = "chunk_id"
        case retrievedAt = "retrieved_at"
        case heading
        case quote
        case confidence
    }
}

public nonisolated enum AgentEvidenceSourceStatus: String, Codable, Hashable, Sendable {
    case available
    case stale
    case missingSource = "missing_source"
}

public nonisolated struct AgentEvidenceSourceJump: Codable, Hashable, Sendable {
    public var evidenceID: String
    public var sourceType: String?
    public var sourceID: String?
    public var relativePath: String?
    public var sourceURL: URL?
    public var startLine: Int?
    public var endLine: Int?
    public var status: AgentEvidenceSourceStatus
    public var warning: String?
    public var pdfRelativePath: String?
    public var pdfURL: URL?
    public var pdfPage: Int?

    public nonisolated init(
        evidenceID: String,
        sourceType: String? = nil,
        sourceID: String? = nil,
        relativePath: String?,
        sourceURL: URL?,
        startLine: Int?,
        endLine: Int?,
        status: AgentEvidenceSourceStatus,
        warning: String? = nil,
        pdfRelativePath: String? = nil,
        pdfURL: URL? = nil,
        pdfPage: Int? = nil
    ) {
        self.evidenceID = evidenceID
        self.sourceType = sourceType
        self.sourceID = sourceID
        self.relativePath = relativePath
        self.sourceURL = sourceURL
        self.startLine = startLine
        self.endLine = endLine
        self.status = status
        self.warning = warning
        self.pdfRelativePath = pdfRelativePath
        self.pdfURL = pdfURL
        self.pdfPage = pdfPage
    }

    public nonisolated var lineTargetDescription: String {
        guard let relativePath else {
            return warning ?? "Source path is unavailable."
        }
        if let startLine, let endLine {
            return "\(relativePath) lines \(startLine)-\(endLine)"
        }
        if let startLine {
            return "\(relativePath) line \(startLine)"
        }
        return relativePath
    }
}

public nonisolated struct AgentLoopOptions: Codable, Hashable, Sendable {
    public var maxSteps: Int
    public var maxToolCalls: Int
    public var maxContextCharacters: Int
    public var maxToolResultCharactersPerCall: Int
    public var maxAccumulatedToolResultCharacters: Int
    public var autoApproveReadOnly: Bool
    public var allowProviderNativeTools: Bool

    public nonisolated init(
        maxSteps: Int = 8,
        maxToolCalls: Int = 16,
        maxContextCharacters: Int = 80_000,
        maxToolResultCharactersPerCall: Int = 12_000,
        maxAccumulatedToolResultCharacters: Int = 40_000,
        autoApproveReadOnly: Bool = true,
        allowProviderNativeTools: Bool = true
    ) {
        self.maxSteps = max(1, maxSteps)
        self.maxToolCalls = max(1, maxToolCalls)
        self.maxContextCharacters = max(1_000, maxContextCharacters)
        self.maxToolResultCharactersPerCall = max(1_000, maxToolResultCharactersPerCall)
        self.maxAccumulatedToolResultCharacters = max(1_000, maxAccumulatedToolResultCharacters)
        self.autoApproveReadOnly = autoApproveReadOnly
        self.allowProviderNativeTools = allowProviderNativeTools
    }

    private enum CodingKeys: String, CodingKey {
        case maxSteps = "max_steps"
        case maxToolCalls = "max_tool_calls"
        case maxContextCharacters = "max_context_characters"
        case maxToolResultCharactersPerCall = "max_tool_result_characters_per_call"
        case maxAccumulatedToolResultCharacters = "max_accumulated_tool_result_characters"
        case autoApproveReadOnly = "auto_approve_read_only"
        case allowProviderNativeTools = "allow_provider_native_tools"
    }
}

public nonisolated enum AgentHumanDecisionAction: String, Codable, Sendable {
    case allowOnce
    case denyAndContinue
    case denyAndStop
    case reviseWithFeedback
    case editArguments

    public nonisolated init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "deny":
            self = .denyAndStop
        case "askAgentToRevise":
            self = .reviseWithFeedback
        default:
            guard let action = AgentHumanDecisionAction(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unsupported human decision action: \(rawValue)"
                )
            }
            self = action
        }
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public nonisolated struct AgentApprovalRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var runID: String
    public var toolCallID: String
    public var tool: String
    public var permissionKey: String
    public var risk: AgentToolRisk
    public var arguments: AgentToolArguments
    public var targetPaths: [String]
    public var fingerprint: String
    public var diffPreview: String?
    public var summaryPreview: String?
    public var reason: String
    public var rollbackHint: AgentRollbackHint?
    public var expiresAt: Date?
    public var suggestedDecisions: [AgentHumanDecisionAction]
    public var createdAt: Date

    public nonisolated var toolName: String {
        get { tool }
        set { tool = newValue }
    }

    public nonisolated var argumentsJSON: String {
        get { arguments.rawJSON }
        set {
            if let parsed = try? AgentToolArguments(rawJSON: newValue) {
                arguments = parsed
                fingerprint = Self.fingerprint(
                    tool: tool,
                    risk: risk,
                    permissionKey: permissionKey,
                    canonicalArgumentsJSON: parsed.canonicalJSON,
                    targetPaths: targetPaths
                )
            }
        }
    }

    public nonisolated init(
        id: String = "approval-\(UUID().uuidString.lowercased())",
        runID: String = "",
        toolCallID: String = "",
        tool: String? = nil,
        toolName: String,
        permissionKey: String,
        risk: AgentToolRisk,
        argumentsJSON: String,
        targetPaths: [String] = [],
        fingerprint: String? = nil,
        diffPreview: String? = nil,
        summaryPreview: String? = nil,
        reason: String? = nil,
        rollbackHint: AgentRollbackHint? = nil,
        expiresAt: Date? = nil,
        suggestedDecisions: [AgentHumanDecisionAction] = [.allowOnce, .denyAndStop, .reviseWithFeedback, .editArguments],
        createdAt: Date = Date()
    ) {
        let parsedArguments = (try? AgentToolArguments(rawJSON: argumentsJSON)) ?? .emptyObject
        let resolvedTool = tool ?? toolName
        self.id = id
        self.runID = runID
        self.toolCallID = toolCallID
        self.tool = resolvedTool
        self.permissionKey = permissionKey
        self.risk = risk
        self.arguments = parsedArguments
        self.targetPaths = targetPaths
        self.fingerprint = fingerprint ?? Self.fingerprint(
            tool: resolvedTool,
            risk: risk,
            permissionKey: permissionKey,
            canonicalArgumentsJSON: parsedArguments.canonicalJSON,
            targetPaths: targetPaths
        )
        self.diffPreview = diffPreview
        self.summaryPreview = summaryPreview
        self.reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Tool call requires approval."
        self.rollbackHint = rollbackHint
        self.expiresAt = expiresAt
        self.suggestedDecisions = suggestedDecisions
        self.createdAt = createdAt
    }

    public nonisolated init(
        id: String = "approval-\(UUID().uuidString.lowercased())",
        runID: String,
        toolCallID: String,
        tool: String,
        risk: AgentToolRisk,
        permissionKey: String,
        arguments: AgentToolArguments,
        targetPaths: [String],
        fingerprint: String? = nil,
        diffPreview: String? = nil,
        summaryPreview: String? = nil,
        reason: String,
        rollbackHint: AgentRollbackHint? = nil,
        expiresAt: Date? = nil,
        suggestedDecisions: [AgentHumanDecisionAction] = [.allowOnce, .denyAndContinue, .denyAndStop, .reviseWithFeedback, .editArguments],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.runID = runID
        self.toolCallID = toolCallID
        self.tool = tool
        self.risk = risk
        self.permissionKey = permissionKey
        self.arguments = arguments
        self.targetPaths = targetPaths
        self.fingerprint = fingerprint ?? Self.fingerprint(
            tool: tool,
            risk: risk,
            permissionKey: permissionKey,
            canonicalArgumentsJSON: arguments.canonicalJSON,
            targetPaths: targetPaths
        )
        self.diffPreview = diffPreview
        self.summaryPreview = summaryPreview
        self.reason = reason
        self.rollbackHint = rollbackHint
        self.expiresAt = expiresAt
        self.suggestedDecisions = suggestedDecisions
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case runID = "run_id"
        case toolCallID = "tool_call_id"
        case tool
        case toolName = "tool_name"
        case permissionKey = "permission_key"
        case risk
        case arguments
        case argumentsJSON = "arguments_json"
        case targetPaths = "target_paths"
        case fingerprint
        case diffPreview = "diff_preview"
        case summaryPreview = "summary_preview"
        case reason
        case rollbackHint = "rollback_hint"
        case expiresAt = "expires_at"
        case suggestedDecisions = "suggested_decisions"
        case createdAt = "created_at"
    }

    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id) ?? "approval-\(UUID().uuidString.lowercased())"
        let tool = try container.decodeIfPresent(String.self, forKey: .tool)
            ?? container.decodeIfPresent(String.self, forKey: .toolName)
            ?? "unknown_tool"
        let permissionKey = try container.decodeIfPresent(String.self, forKey: .permissionKey) ?? "tool.external_side_effect"
        let risk = try container.decodeIfPresent(AgentToolRisk.self, forKey: .risk) ?? .externalSideEffect
        let runID = try container.decodeIfPresent(String.self, forKey: .runID) ?? ""
        let toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID) ?? ""
        let arguments = try container.decodeIfPresent(AgentToolArguments.self, forKey: .arguments)
            ?? AgentToolArguments(rawJSON: container.decodeIfPresent(String.self, forKey: .argumentsJSON) ?? "{}")
        let targetPaths = try container.decodeIfPresent([String].self, forKey: .targetPaths) ?? []
        self.id = id
        self.runID = runID
        self.toolCallID = toolCallID
        self.tool = tool
        self.permissionKey = permissionKey
        self.risk = risk
        self.arguments = arguments
        self.targetPaths = targetPaths
        self.fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint) ?? Self.fingerprint(
            tool: tool,
            risk: risk,
            permissionKey: permissionKey,
            canonicalArgumentsJSON: arguments.canonicalJSON,
            targetPaths: targetPaths
        )
        self.diffPreview = try container.decodeIfPresent(String.self, forKey: .diffPreview)
        self.summaryPreview = try container.decodeIfPresent(String.self, forKey: .summaryPreview)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "Tool call requires approval."
        self.rollbackHint = try container.decodeIfPresent(AgentRollbackHint.self, forKey: .rollbackHint)
        self.expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        self.suggestedDecisions = try container.decodeIfPresent([AgentHumanDecisionAction].self, forKey: .suggestedDecisions) ?? [.allowOnce, .denyAndStop, .reviseWithFeedback, .editArguments]
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(runID, forKey: .runID)
        try container.encode(toolCallID, forKey: .toolCallID)
        try container.encode(tool, forKey: .tool)
        try container.encode(permissionKey, forKey: .permissionKey)
        try container.encode(risk, forKey: .risk)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(arguments.rawJSON, forKey: .argumentsJSON)
        try container.encode(targetPaths, forKey: .targetPaths)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encodeIfPresent(diffPreview, forKey: .diffPreview)
        try container.encodeIfPresent(summaryPreview, forKey: .summaryPreview)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(rollbackHint, forKey: .rollbackHint)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encode(suggestedDecisions, forKey: .suggestedDecisions)
        try container.encode(createdAt, forKey: .createdAt)
    }

    public nonisolated static func fingerprint(
        tool: String,
        risk: AgentToolRisk,
        permissionKey: String,
        canonicalArgumentsJSON: String,
        targetPaths: [String]
    ) -> String {
        let normalizedPaths = targetPaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\n")
        return AgentToolCallFingerprint.stableHash([
            tool,
            risk.rawValue,
            permissionKey,
            canonicalArgumentsJSON,
            normalizedPaths
        ].joined(separator: "\u{1f}"))
    }
}

public nonisolated struct AgentPendingToolCall: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var runID: String
    public var stepIndex: Int
    public var toolCall: AgentToolCall
    public var approvalRequest: AgentApprovalRequest
    public var messagesBeforePause: [LLMChatMessage]
    public var createdAt: Date
    public var expiresAt: Date?

    public nonisolated init(
        id: String = "pending-tool-\(UUID().uuidString.lowercased())",
        runID: String,
        stepIndex: Int,
        toolCall: AgentToolCall,
        approvalRequest: AgentApprovalRequest,
        messagesBeforePause: [LLMChatMessage],
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.runID = runID
        self.stepIndex = stepIndex
        self.toolCall = toolCall
        self.approvalRequest = approvalRequest
        self.messagesBeforePause = messagesBeforePause
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public nonisolated func replacing(
        toolCall: AgentToolCall,
        approvalRequest: AgentApprovalRequest
    ) -> AgentPendingToolCall {
        AgentPendingToolCall(
            id: id,
            runID: runID,
            stepIndex: stepIndex,
            toolCall: toolCall,
            approvalRequest: approvalRequest,
            messagesBeforePause: messagesBeforePause,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case runID = "run_id"
        case stepIndex = "step_index"
        case toolCall = "tool_call"
        case approvalRequest = "approval_request"
        case messagesBeforePause = "messages_before_pause"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(String.self, forKey: .id) ?? "pending-tool-\(UUID().uuidString.lowercased())"
        let toolCall = try container.decode(AgentToolCall.self, forKey: .toolCall)
        var approval = try container.decodeIfPresent(AgentApprovalRequest.self, forKey: .approvalRequest) ?? AgentApprovalRequest(
            toolName: toolCall.toolName,
            permissionKey: AgentToolRisk.externalSideEffect.defaultPermissionKey,
            risk: .externalSideEffect,
            argumentsJSON: toolCall.argumentsJSON
        )
        let runID = try container.decodeIfPresent(String.self, forKey: .runID)
            ?? approval.runID.nilIfEmpty
            ?? "agent-run-legacy-\(AgentToolCallFingerprint.stableHash(id + toolCall.id).replacingOccurrences(of: "sha256:", with: "").prefix(12))"
        let stepIndex = try container.decodeIfPresent(Int.self, forKey: .stepIndex) ?? 1
        approval.runID = approval.runID.nilIfEmpty ?? runID
        approval.toolCallID = approval.toolCallID.nilIfEmpty ?? toolCall.id
        if approval.targetPaths.isEmpty {
            approval.targetPaths = AgentToolArgumentInspection(argumentsJSON: toolCall.argumentsJSON).paths
        }
        if approval.summaryPreview == nil {
            approval.summaryPreview = "\(toolCall.toolName) requires approval."
        }
        approval.fingerprint = AgentApprovalRequest.fingerprint(
            tool: approval.tool,
            risk: approval.risk,
            permissionKey: approval.permissionKey,
            canonicalArgumentsJSON: approval.arguments.canonicalJSON,
            targetPaths: approval.targetPaths
        )

        self.id = id
        self.runID = runID
        self.stepIndex = stepIndex
        self.toolCall = toolCall
        self.approvalRequest = approval
        self.messagesBeforePause = try container.decodeIfPresent([LLMChatMessage].self, forKey: .messagesBeforePause) ?? []
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}

public nonisolated struct AgentToolCallFingerprint: Codable, Hashable, Sendable {
    public var toolName: String
    public var normalizedArgumentsHash: String
    public var targetPathsHash: String?

    public nonisolated init(toolName: String, normalizedArgumentsHash: String, targetPathsHash: String? = nil) {
        self.toolName = toolName
        self.normalizedArgumentsHash = normalizedArgumentsHash
        self.targetPathsHash = targetPathsHash
    }

    public nonisolated init(call: AgentToolCall, targetPaths: [String] = []) {
        let normalizedArguments = Self.normalizedJSON(call.argumentsJSON)
        let normalizedPaths = targetPaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\n")
        self.init(
            toolName: call.toolName,
            normalizedArgumentsHash: Self.stableHash(normalizedArguments),
            targetPathsHash: normalizedPaths.isEmpty ? nil : Self.stableHash(normalizedPaths)
        )
    }

    public nonisolated var idempotencyFingerprint: String {
        [toolName, normalizedArgumentsHash, targetPathsHash ?? ""].joined(separator: ":")
    }

    private enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case normalizedArgumentsHash = "normalized_arguments_hash"
        case targetPathsHash = "target_paths_hash"
    }

    public nonisolated static func normalizedJSON(_ json: String) -> String {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let normalizedData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let normalized = String(data: normalizedData, encoding: .utf8) else {
            return trimmed
        }
        return normalized
    }

    public nonisolated static func stableHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

public nonisolated struct AgentToolArgumentInspection: Hashable, Sendable {
    public var paths: [String]
    public var command: String?

    public nonisolated init(argumentsJSON: String) {
        guard let data = argumentsJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            self.paths = []
            self.command = nil
            return
        }

        var pathValues: [String] = []
        var commandValue: String?
        Self.collect(from: root, keyPath: [], paths: &pathValues, command: &commandValue)
        self.paths = uniqueOrdered(pathValues).prefix(8).map { $0 }
        self.command = commandValue
    }

    private nonisolated static func collect(from value: Any, keyPath: [String], paths: inout [String], command: inout String?) {
        if let dictionary = value as? [String: Any] {
            for key in dictionary.keys.sorted() {
                collect(from: dictionary[key] as Any, keyPath: keyPath + [key], paths: &paths, command: &command)
            }
            return
        }

        if let array = value as? [Any] {
            for item in array {
                collect(from: item, keyPath: keyPath, paths: &paths, command: &command)
            }
            return
        }

        guard let string = value as? String, !string.isEmpty else {
            return
        }

        let joinedKey = keyPath.joined(separator: ".").lowercased()
        if command == nil, joinedKey.contains("command") || joinedKey == "cmd" || joinedKey.contains("shell") {
            command = string
        }
        if joinedKey.contains("path") || joinedKey.contains("file") || joinedKey.contains("folder") || joinedKey.contains("directory") {
            paths.append(string)
        }
    }
}

public nonisolated enum AgentLoopPauseKind: String, Codable, Sendable {
    case approvalRequired = "approval_required"
    case contextLimitExceeded = "context_limit_exceeded"
    case maxStepsExceeded = "max_steps_exceeded"
    case maxToolCallsExceeded = "max_tool_calls_exceeded"
    case safetyPolicyBlocked = "safety_policy_blocked"
    case deniedAndStopped = "denied_and_stopped"
    case providerUnavailable = "provider_unavailable"
}

public nonisolated struct AgentLoopPauseReason: Codable, Hashable, Sendable {
    public var kind: AgentLoopPauseKind
    public var message: String
    public var toolCallID: String?
    public var approvalRequest: AgentApprovalRequest?

    public nonisolated init(
        kind: AgentLoopPauseKind,
        message: String,
        toolCallID: String? = nil,
        approvalRequest: AgentApprovalRequest? = nil
    ) {
        self.kind = kind
        self.message = message
        self.toolCallID = toolCallID
        self.approvalRequest = approvalRequest
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
        case toolCallID = "tool_call_id"
        case approvalRequest = "approval_request"
    }
}

public nonisolated struct AgentLoopStep: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var stepIndex: Int
    public var assistantMessage: LLMChatMessage?
    public var toolCalls: [AgentToolCall]
    public var toolResults: [AgentToolResult]
    public var cachedToolCallIDs: [String]
    public var pauseReason: AgentLoopPauseReason?

    public nonisolated init(
        id: String = "loop-step-\(UUID().uuidString.lowercased())",
        stepIndex: Int,
        assistantMessage: LLMChatMessage? = nil,
        toolCalls: [AgentToolCall] = [],
        toolResults: [AgentToolResult] = [],
        cachedToolCallIDs: [String] = [],
        pauseReason: AgentLoopPauseReason? = nil
    ) {
        self.id = id
        self.stepIndex = stepIndex
        self.assistantMessage = assistantMessage
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.cachedToolCallIDs = cachedToolCallIDs
        self.pauseReason = pauseReason
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case stepIndex = "step_index"
        case assistantMessage = "assistant_message"
        case toolCalls = "tool_calls"
        case toolResults = "tool_results"
        case cachedToolCallIDs = "cached_tool_call_ids"
        case pauseReason = "pause_reason"
    }
}

public nonisolated struct AgentLoopResult: Codable, Hashable, Sendable {
    public var runID: String
    public var sessionID: String
    public var finalResponseMarkdown: String?
    public var messages: [LLMChatMessage]
    public var toolResults: [AgentToolResult]
    public var pauseReason: AgentLoopPauseReason?
    public var pendingToolCall: AgentPendingToolCall?
    public var steps: [AgentLoopStep]

    public nonisolated init(
        runID: String,
        sessionID: String? = nil,
        finalResponseMarkdown: String? = nil,
        messages: [LLMChatMessage],
        toolResults: [AgentToolResult] = [],
        pauseReason: AgentLoopPauseReason? = nil,
        pendingToolCall: AgentPendingToolCall? = nil,
        steps: [AgentLoopStep] = []
    ) {
        self.runID = runID
        self.sessionID = sessionID ?? runID
        self.finalResponseMarkdown = finalResponseMarkdown
        self.messages = messages
        self.toolResults = toolResults
        self.pauseReason = pauseReason
        self.pendingToolCall = pendingToolCall
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case sessionID = "session_id"
        case finalResponseMarkdown = "final_response_markdown"
        case messages
        case toolResults = "tool_results"
        case pauseReason = "pause_reason"
        case pendingToolCall = "pending_tool_call"
        case steps
    }
}

public nonisolated struct AgentToolResultWireFormat: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var toolName: String
    public var toolCallID: String
    public var succeeded: Bool
    public var content: String
    public var summary: String
    public var modifiedPaths: [String]
    public var evidence: [AgentEvidenceRef]
    public var error: String?

    public nonisolated init(
        schemaVersion: Int = 1,
        toolName: String,
        toolCallID: String,
        succeeded: Bool,
        content: String,
        summary: String,
        modifiedPaths: [String] = [],
        evidence: [AgentEvidenceRef] = [],
        error: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.succeeded = succeeded
        self.content = content
        self.summary = summary
        self.modifiedPaths = modifiedPaths
        self.evidence = evidence
        self.error = error
    }

    public nonisolated init(result: AgentToolResult, toolCallID: String, summary: String? = nil, evidence: [AgentEvidenceRef] = []) {
        self.init(
            toolName: result.toolName,
            toolCallID: toolCallID,
            succeeded: result.succeeded,
            content: result.message,
            summary: summary ?? Self.summary(for: result.message),
            modifiedPaths: result.modifiedPaths,
            evidence: evidence,
            error: result.errorMessage
        )
    }

    public nonisolated func agentToolResult() -> AgentToolResult {
        AgentToolResult(
            callID: toolCallID,
            toolName: toolName,
            succeeded: succeeded,
            message: content,
            modifiedPaths: modifiedPaths,
            errorMessage: error
        )
    }

    public nonisolated func stableJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public nonisolated static func summary(for text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 240 else {
            return trimmed
        }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 240)
        return String(trimmed[..<endIndex])
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case toolName = "tool_name"
        case toolCallID = "tool_call_id"
        case succeeded
        case content
        case summary
        case modifiedPaths = "modified_paths"
        case evidence
        case error
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}