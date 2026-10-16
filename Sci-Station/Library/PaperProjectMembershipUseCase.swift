import Foundation

public protocol PaperProjectMetadataMirroring: Sendable {
    func updateProjectMetadataMirror(
        forPaperID paperID: Paper.ID,
        links: [ProjectPaperLink],
        in workspace: ResearchWorkspace
    ) async throws
}

extension PaperRepository: PaperProjectMetadataMirroring {}

public nonisolated enum PaperProjectMutation: Sendable {
    case membership(Bool)
    case toggleMembership
    case core(Bool)
    case toggleCore
    case pinned(Bool)
    case useFor([String])
    case folderPath(String?)
}

public nonisolated struct PaperProjectMembershipError: Error, LocalizedError, Sendable {
    public enum Phase: Sendable {
        case linkWrite
        case metadataMirror
        case compensation
        case synchronization
    }

    public let phase: Phase
    public let paperID: Paper.ID
    public let reason: String

    public var errorDescription: String? {
        switch phase {
        case .linkWrite:
            return "The project association could not be saved. \(reason)"
        case .metadataMirror:
            return "The paper metadata could not be updated; the previous project association was restored. Repair the metadata or file access, then retry the action. \(reason)"
        case .compensation:
            return "The paper metadata could not be updated and the project association could not be restored safely. Its current state was preserved. Repair file access, then retry metadata synchronization from the current project links. \(reason)"
        case .synchronization:
            return "The paper metadata mirror could not be synchronized. Repair the metadata or file access, then retry synchronization. \(reason)"
        }
    }
}

/// Write links first, then patch the metadata mirror. A mirror failure restores
/// only the affected link when its committed value is still current. Conflicting
/// newer changes are preserved and can be synchronized explicitly. The task
/// chain serializes both stages and compensation across actor suspension points.
public actor PaperProjectMembershipUseCase {
    private let links: ProjectPaperLinkRepository
    private let papers: any PaperProjectMetadataMirroring
    private var pending: Task<Void, Error>?

    public init(links: ProjectPaperLinkRepository, papers: any PaperProjectMetadataMirroring) {
        self.links = links
        self.papers = papers
    }

    public func apply(
        _ mutation: PaperProjectMutation,
        paperID: Paper.ID,
        projectID: ResearchProject.ID,
        in workspace: ResearchWorkspace
    ) async throws {
        let previous = pending
        let task = Task { [links, papers] in
            _ = try? await previous?.value
            // Cancellation before commit leaves both files untouched. Once links
            // commit, always attempt the mirror even if the caller is cancelled.
            try Task.checkCancellation()
            let receipt: ProjectPaperLinkMutationReceipt
            do {
                receipt = try await links.apply(mutation, projectID: projectID, paperID: paperID, in: workspace)
            } catch {
                throw PaperProjectMembershipError(phase: .linkWrite, paperID: paperID, reason: error.localizedDescription)
            }
            do {
                try await Self.synchronize(paperID: paperID, in: workspace, links: links, papers: papers)
            } catch {
                let mirrorReason = error.localizedDescription
                do {
                    try await links.compensate(receipt, in: workspace)
                } catch {
                    throw PaperProjectMembershipError(
                        phase: .compensation, paperID: paperID,
                        reason: "\(mirrorReason) \(error.localizedDescription)"
                    )
                }
                throw PaperProjectMembershipError(phase: .metadataMirror, paperID: paperID, reason: mirrorReason)
            }
        }
        pending = task
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Idempotent recovery, including after restarting the app. No UI draft or
    /// remembered previous link value is needed, and toggles are not replayed.
    public func synchronizeMetadataMirror(forPaperID paperID: Paper.ID, in workspace: ResearchWorkspace) async throws {
        let previous = pending
        let task = Task { [links, papers] in
            _ = try? await previous?.value
            try Task.checkCancellation()
            do {
                try await Self.synchronize(paperID: paperID, in: workspace, links: links, papers: papers)
            } catch {
                throw PaperProjectMembershipError(phase: .synchronization, paperID: paperID, reason: error.localizedDescription)
            }
        }
        pending = task
        try await task.value
    }

    private static func synchronize(
        paperID: Paper.ID,
        in workspace: ResearchWorkspace,
        links: ProjectPaperLinkRepository,
        papers: any PaperProjectMetadataMirroring
    ) async throws {
        let currentLinks = try await links.links(forPaperID: paperID, in: workspace)
        try await papers.updateProjectMetadataMirror(forPaperID: paperID, links: currentLinks, in: workspace)
    }
}

/// Preserve unsaved fields while updating association fields the user has not
/// edited. A clean draft follows the persisted paper completely.
nonisolated enum PaperProjectDraftMerge {
    static func merge(draft: Paper, original: Paper?, updated: Paper) -> Paper {
        guard draft != original else { return updated }
        var result = draft
        if draft.projectIDs == original?.projectIDs { result.projectIDs = updated.projectIDs }
        if draft.coreProjectIDs == original?.coreProjectIDs { result.coreProjectIDs = updated.coreProjectIDs }
        if draft.useFor == original?.useFor { result.useFor = updated.useFor }
        if draft.folderPath == original?.folderPath { result.folderPath = updated.folderPath }
        return result
    }
}
