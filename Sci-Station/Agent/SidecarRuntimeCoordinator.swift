import Foundation

public nonisolated struct SidecarRuntimeDecision: Hashable, Sendable {
    public var selection: AgentRuntimeSelection
    public var effectiveRuntime: AgentRuntimeSelection
    public var shouldAttemptSidecar: Bool
    public var health: SidecarHealth
    public var fallbackReason: String?
    public var provenance: AgentRunProvenance

    public nonisolated init(
        selection: AgentRuntimeSelection,
        effectiveRuntime: AgentRuntimeSelection,
        shouldAttemptSidecar: Bool,
        health: SidecarHealth,
        fallbackReason: String? = nil,
        provenance: AgentRunProvenance? = nil
    ) {
        self.selection = selection
        self.effectiveRuntime = effectiveRuntime
        self.shouldAttemptSidecar = shouldAttemptSidecar
        self.health = health
        self.fallbackReason = fallbackReason
        self.provenance = provenance ?? AgentRunProvenance(
            requestedRuntime: selection.rawValue,
            effectiveRuntime: effectiveRuntime.rawValue,
            runtime: effectiveRuntime.rawValue,
            fallbackReason: fallbackReason,
            metadata: health.provenanceMetadata
        )
    }
}

public actor SidecarRuntimeCoordinator {
    private let supervisor: SidecarProcessSupervisor
    private var cachedHealth = SidecarHealth(status: "unavailable")
    private var lastCrash: String?
    private var fallbackReason: String?

    public init(supervisor: SidecarProcessSupervisor = SidecarProcessSupervisor()) {
        self.supervisor = supervisor
    }

    public func langGraphRuntime(fallbackRuntime: (any ExternalAgentRuntime)? = LegacySwiftAgentRuntime()) -> LangGraphAgentRuntime {
        LangGraphAgentRuntime(supervisor: supervisor, fallbackRuntime: fallbackRuntime, healthCoordinator: self)
    }

    public func resolve(
        selection: AgentRuntimeSelection,
        sidecarDisabled: Bool,
        root: ResearchRoot
    ) async -> SidecarRuntimeDecision {
        if sidecarDisabled {
            let health = healthWithSessionState(SidecarHealth(status: "disabled", fallbackReason: "Sidecar disabled for this workspace."))
            return SidecarRuntimeDecision(
                selection: selection,
                effectiveRuntime: .swiftLoop,
                shouldAttemptSidecar: false,
                health: health,
                fallbackReason: health.fallbackReason
            )
        }

        if selection == .swiftLoop {
            let health = await refreshHealth()
            return SidecarRuntimeDecision(
                selection: selection,
                effectiveRuntime: .swiftLoop,
                shouldAttemptSidecar: false,
                health: health,
                fallbackReason: nil
            )
        }

        let health = await ensureReady(for: root)
        let sidecarAvailable = health.status == "ready"
        let effective = selection.effectiveRuntime(sidecarAvailable: sidecarAvailable)
        let reason = selection.fallbackReason(sidecarAvailable: sidecarAvailable) ?? health.fallbackReason
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fallbackReason = reason
        }
        return SidecarRuntimeDecision(
            selection: selection,
            effectiveRuntime: effective,
            shouldAttemptSidecar: effective == .langGraphSidecar,
            health: healthWithSessionState(health),
            fallbackReason: reason ?? fallbackReason
        )
    }

    public func refreshHealth() async -> SidecarHealth {
        let health = await supervisor.health()
        cachedHealth = healthWithSessionState(health)
        return cachedHealth
    }

    public func restart(for root: ResearchRoot) async -> SidecarHealth {
        do {
            _ = try await supervisor.restart(initialization: initialization(for: root))
            let health = await supervisor.health()
            fallbackReason = nil
            cachedHealth = healthWithSessionState(health)
            return cachedHealth
        } catch {
            fallbackReason = "Sidecar restart failed: \(error.localizedDescription)"
            cachedHealth = healthWithSessionState(SidecarHealth(status: "unavailable"))
            return cachedHealth
        }
    }

    public func stop() async {
        try? await supervisor.stop()
        cachedHealth = healthWithSessionState(SidecarHealth(status: "unavailable"))
    }

    public func recordCrash(_ message: String) {
        lastCrash = message
        cachedHealth = healthWithSessionState(SidecarHealth(status: "unavailable"))
    }

    public func recordFallback(_ message: String) {
        fallbackReason = message
        cachedHealth = healthWithSessionState(cachedHealth)
    }

    private func ensureReady(for root: ResearchRoot) async -> SidecarHealth {
        let current = await supervisor.health()
        if current.status == "ready" {
            cachedHealth = healthWithSessionState(current)
            return cachedHealth
        }

        do {
            _ = try await supervisor.start(initialization: initialization(for: root))
            let health = await supervisor.health()
            cachedHealth = healthWithSessionState(health)
            return cachedHealth
        } catch {
            fallbackReason = "Sidecar unavailable: \(error.localizedDescription)"
            cachedHealth = healthWithSessionState(SidecarHealth(status: "unavailable"))
            return cachedHealth
        }
    }

    private nonisolated func initialization(for root: ResearchRoot) -> SidecarInitializationRequest {
        SidecarInitializationRequest(
            workspaceRoot: root.rootURL.path,
            allowedRoots: AgentAuthorizedResourceProvider.defaultAllowedRoots
        )
    }

    private func healthWithSessionState(_ health: SidecarHealth) -> SidecarHealth {
        var updated = health
        if updated.lastCrash == nil {
            updated.lastCrash = lastCrash
        }
        if updated.fallbackReason == nil {
            updated.fallbackReason = fallbackReason
        }
        return updated
    }
}

private extension SidecarHealth {
    nonisolated var provenanceMetadata: [String: String] {
        [
            "sidecar_status": status,
            "sidecar_version": sidecarVersion ?? "",
            "protocol_version": protocolVersion ?? "",
            "schema_version": schemaVersion.map(String.init) ?? "",
            "python_version": pythonVersion ?? "",
            "protocol_schema_version": protocolSchemaVersion ?? "",
            "last_crash": lastCrash ?? "",
            "fallback_reason": fallbackReason ?? ""
        ].filter { !$0.value.isEmpty }
    }
}
