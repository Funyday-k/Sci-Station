import Foundation

public struct GitHubCopilotConfiguration: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var clientID: String
    public var callbackURLString: String
    public var requiredOrganization: String?
    public var model: String

    public nonisolated init(
        isEnabled: Bool = false,
        clientID: String = "",
        callbackURLString: String = "",
        requiredOrganization: String? = nil,
        model: String = "gpt-4.1"
    ) {
        self.isEnabled = isEnabled
        self.clientID = clientID
        self.callbackURLString = callbackURLString
        self.requiredOrganization = requiredOrganization
        self.model = model
    }

    public nonisolated var isConnectable: Bool {
        isEnabled
            && !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: callbackURLString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }
}

public enum GitHubCopilotTokenKind: String, Codable, Sendable {
    case oauthUser = "oauth-user"
    case githubAppUser = "github-app-user"
    case fineGrainedPAT = "fine-grained-pat"
    case classicPAT = "classic-pat"
    case unsupported = "unsupported"

    public nonisolated var label: String {
        switch self {
        case .oauthUser:
            return "OAuth user token"
        case .githubAppUser:
            return "GitHub App user token"
        case .fineGrainedPAT:
            return "Fine-grained personal access token"
        case .classicPAT:
            return "Classic personal access token"
        case .unsupported:
            return "Unsupported token"
        }
    }

    public nonisolated var isRecommended: Bool {
        switch self {
        case .oauthUser, .githubAppUser, .fineGrainedPAT:
            return true
        case .classicPAT, .unsupported:
            return false
        }
    }
}

public struct GitHubCopilotTokenClassifier: Sendable {
    public nonisolated init() {}

    public nonisolated func classify(_ token: String) -> GitHubCopilotTokenKind {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedToken.hasPrefix("gho_") {
            return .oauthUser
        }
        if trimmedToken.hasPrefix("ghu_") {
            return .githubAppUser
        }
        if trimmedToken.hasPrefix("github_pat_") {
            return .fineGrainedPAT
        }
        if trimmedToken.hasPrefix("ghp_") {
            return .classicPAT
        }
        return .unsupported
    }
}

public protocol CopilotSDKProvider: Sendable {
    func complete(prompt: String, configuration: GitHubCopilotConfiguration, userToken: String) async throws -> String
}

public enum GitHubCopilotProviderError: LocalizedError, Sendable {
    case notConnected
    case unsupportedToken(GitHubCopilotTokenKind)
    case sdkUnavailable

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Connect GitHub Copilot before using the Copilot SDK provider."
        case let .unsupportedToken(kind):
            return "\(kind.label) is not recommended for Copilot SDK access."
        case .sdkUnavailable:
            return "GitHub Copilot SDK execution is not bundled yet. Use Copilot Bridge export or finish the SDK integration."
        }
    }
}

public actor GitHubCopilotSDKAdapter: CopilotSDKProvider {
    private let tokenClassifier: GitHubCopilotTokenClassifier

    public init(tokenClassifier: GitHubCopilotTokenClassifier = GitHubCopilotTokenClassifier()) {
        self.tokenClassifier = tokenClassifier
    }

    public func complete(prompt: String, configuration: GitHubCopilotConfiguration, userToken: String) async throws -> String {
        guard configuration.isConnectable, !userToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubCopilotProviderError.notConnected
        }

        let tokenKind = tokenClassifier.classify(userToken)
        guard tokenKind.isRecommended else {
            throw GitHubCopilotProviderError.unsupportedToken(tokenKind)
        }

        throw GitHubCopilotProviderError.sdkUnavailable
    }
}

