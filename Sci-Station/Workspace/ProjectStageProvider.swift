import Foundation

public nonisolated enum ProjectStage: String, Codable, CaseIterable, Sendable {
    case exploration
    case planning
    case drafting
    case reviewing
    case onHold = "on_hold"

    public var label: String {
        switch self {
        case .exploration:
            return "Exploration"
        case .planning:
            return "Planning"
        case .drafting:
            return "Drafting"
        case .reviewing:
            return "Reviewing"
        case .onHold:
            return "On Hold"
        }
    }
}

public nonisolated struct ProjectStageSignal: Codable, Hashable, Sendable {
    public var projectID: String
    public var papersCount: Int
    public var wikiPageCount: Int
    public var openGapsCount: Int
    public var artifactKinds: [String]
    public var unsupportedClaimCount: Int
    public var lastActivityAt: Date?

    public init(
        projectID: String,
        papersCount: Int = 0,
        wikiPageCount: Int = 0,
        openGapsCount: Int = 0,
        artifactKinds: [String] = [],
        unsupportedClaimCount: Int = 0,
        lastActivityAt: Date? = nil
    ) {
        self.projectID = projectID
        self.papersCount = papersCount
        self.wikiPageCount = wikiPageCount
        self.openGapsCount = openGapsCount
        self.artifactKinds = artifactKinds
        self.unsupportedClaimCount = unsupportedClaimCount
        self.lastActivityAt = lastActivityAt
    }
}

public nonisolated struct ProjectStageDecision: Codable, Hashable, Sendable {
    public var stage: ProjectStage
    public var rule: String

    public init(stage: ProjectStage, rule: String) {
        self.stage = stage
        self.rule = rule
    }
}

public nonisolated struct ProjectStageProvider: Sendable {
    public static let onHoldInterval: TimeInterval = 21 * 86_400

    public init() {}

    public func stage(for signal: ProjectStageSignal, today: Date = Date()) -> ProjectStageDecision {
        let normalizedKinds = Set(signal.artifactKinds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        if let lastActivityAt = signal.lastActivityAt,
           today.timeIntervalSince(lastActivityAt) > Self.onHoldInterval {
            return ProjectStageDecision(stage: .onHold, rule: "no activity in the last 21 days")
        }

        if signal.unsupportedClaimCount > 0 || normalizedKinds.contains("reviewer_response") {
            return ProjectStageDecision(stage: .reviewing, rule: "unsupported claims or reviewer response detected")
        }

        if normalizedKinds.contains("writing_revision") || normalizedKinds.contains("related_work") {
            return ProjectStageDecision(stage: .drafting, rule: "recent writing artifact detected")
        }

        if signal.papersCount >= 5,
           signal.openGapsCount > 0,
           normalizedKinds.contains("research_plan") {
            return ProjectStageDecision(stage: .planning, rule: "research plan with papers and open gaps")
        }

        if signal.papersCount < 5,
           signal.wikiPageCount < 3,
           normalizedKinds.isEmpty {
            return ProjectStageDecision(stage: .exploration, rule: "fewer than five papers and sparse project notes")
        }

        return ProjectStageDecision(stage: .planning, rule: "default project planning state")
    }
}