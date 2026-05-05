import Foundation

public nonisolated struct AgentDeterministicSafetyPolicy: Sendable {
    public nonisolated init() {}

    public nonisolated func evaluatePrompt(_ prompt: String) -> AgentPermissionDecision? {
        if matchesSecretPattern(prompt) {
            return AgentPermissionDecision(
                action: .deny,
                ruleID: "deterministic-secret-prompt-block",
                message: "Prompt appears to contain an API key, token, JWT, or private key. Remove the secret before sending it to the model."
            )
        }
        return nil
    }

    public nonisolated func evaluateToolCall(_ call: AgentToolCall, definition: AgentToolDefinition?) -> AgentPermissionDecision? {
        let risk = definition?.risk ?? .externalSideEffect
        let inspection = AgentToolArgumentInspection(argumentsJSON: call.argumentsJSON)
        if risk != .readOnly, inspection.paths.contains(where: isCredentialPath) {
            return AgentPermissionDecision(
                action: .deny,
                ruleID: "deterministic-sensitive-path-block",
                message: "Tool call targets a credential or dotenv path and was blocked."
            )
        }
        if risk == .credentialAccess || risk == .destructive {
            return AgentPermissionDecision(
                action: .deny,
                ruleID: "deterministic-high-risk-block",
                message: "Credential access and destructive tool calls are blocked by the deterministic safety policy."
            )
        }
        return nil
    }

    public nonisolated func evaluateToolResult(_ result: AgentToolResult, workspace: ResearchWorkspace) -> AgentPermissionDecision? {
        let workspacePath = workspace.rootURL.standardizedFileURL.path
        if result.modifiedPaths.contains(where: { modifiedPath in
            let normalized = modifiedPath.hasPrefix("/") ? modifiedPath : workspace.fileURL(for: modifiedPath).standardizedFileURL.path
            return normalized != workspacePath && !normalized.hasPrefix(workspacePath + "/")
        }) {
            return AgentPermissionDecision(
                action: .ask,
                ruleID: "deterministic-outside-workspace-audit",
                message: "Tool result reports modifications outside the workspace."
            )
        }
        return nil
    }

    private nonisolated func matchesSecretPattern(_ text: String) -> Bool {
        let patterns = [
            #"sk-[A-Za-z0-9_-]{16,}"#,
            #"ghp_[A-Za-z0-9_]{20,}"#,
            #"AKIA[0-9A-Z]{16}"#,
            #"eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{8,}"#,
            #"-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----"#
        ]
        return patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private nonisolated func isCredentialPath(_ path: String) -> Bool {
        path.range(of: #"(^|/)(\.ssh|\.aws)(/|$)|(^|/)\.env(\.|$)|keychain|credential"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}