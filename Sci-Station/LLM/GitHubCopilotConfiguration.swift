import Foundation

public struct GitHubCopilotConfiguration: Codable, Hashable, Sendable {
    public nonisolated static let defaultCallbackURLString = "sci-station://github-copilot/callback"
    public nonisolated static let defaultScopeString = "read:user read:org"

    public var isEnabled: Bool
    public var clientID: String
    public var callbackURLString: String
    public var tokenExchangeURLString: String
    public var requiredOrganization: String?
    public var model: String
    public var scopeString: String

    public nonisolated init(
        isEnabled: Bool = false,
        clientID: String = "",
        callbackURLString: String = Self.defaultCallbackURLString,
        tokenExchangeURLString: String = "",
        requiredOrganization: String? = nil,
        model: String = "gpt-4.1",
        scopeString: String = Self.defaultScopeString
    ) {
        self.isEnabled = isEnabled
        self.clientID = clientID
        self.callbackURLString = callbackURLString
        self.tokenExchangeURLString = tokenExchangeURLString
        self.requiredOrganization = requiredOrganization
        self.model = model
        self.scopeString = scopeString
    }

    public nonisolated var isConnectable: Bool {
        isEnabled
            && !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && URL(string: callbackURLString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    public nonisolated var hasTokenExchangeRelay: Bool {
        URL(string: tokenExchangeURLString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }
}

public enum GitHubCopilotOAuthError: LocalizedError, Sendable {
    case missingClientID
    case invalidCallbackURL(String)
    case invalidAuthorizeURL
    case callbackDoesNotMatch(URL)
    case missingCode
    case stateMismatch
    case authorizationDenied(String)
    case missingTokenExchangeRelay
    case invalidTokenExchangeRelay(String)
    case tokenExchangeHTTPError(statusCode: Int, message: String)
    case malformedTokenExchangeResponse

    public var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Add a GitHub OAuth Client ID before connecting."
        case let .invalidCallbackURL(value):
            return "Invalid GitHub OAuth callback URL: \(value)."
        case .invalidAuthorizeURL:
            return "Could not build the GitHub authorization URL."
        case let .callbackDoesNotMatch(url):
            return "The callback URL is not a Sci-Station GitHub Copilot callback: \(url.absoluteString)"
        case .missingCode:
            return "GitHub did not return an OAuth code."
        case .stateMismatch:
            return "GitHub OAuth state did not match this session. Try connecting again."
        case let .authorizationDenied(message):
            return "GitHub authorization failed: \(message)"
        case .missingTokenExchangeRelay:
            return "GitHub returned an OAuth code. Add a token exchange relay URL so Sci-Station can complete login without storing a client secret."
        case let .invalidTokenExchangeRelay(value):
            return "Invalid token exchange relay URL: \(value)."
        case let .tokenExchangeHTTPError(statusCode, message):
            return "Token exchange relay failed with HTTP \(statusCode): \(message)"
        case .malformedTokenExchangeResponse:
            return "Token exchange relay returned a malformed response."
        }
    }
}

public struct GitHubCopilotOAuthCallback: Hashable, Sendable {
    public let code: String?
    public let state: String?
    public let error: String?
    public let errorDescription: String?

    public nonisolated init(url: URL) throws {
        guard url.scheme == "sci-station",
              url.host == "github-copilot",
              url.path == "/callback" else {
            throw GitHubCopilotOAuthError.callbackDoesNotMatch(url)
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        self.code = items.first(where: { $0.name == "code" })?.value
        self.state = items.first(where: { $0.name == "state" })?.value
        self.error = items.first(where: { $0.name == "error" })?.value
        self.errorDescription = items.first(where: { $0.name == "error_description" })?.value
    }
}

public struct GitHubCopilotOAuthRequestBuilder: Sendable {
    public nonisolated init() {}

    public nonisolated func authorizationURL(configuration: GitHubCopilotConfiguration, state: String) throws -> URL {
        let clientID = configuration.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            throw GitHubCopilotOAuthError.missingClientID
        }
        guard URL(string: configuration.callbackURLString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil else {
            throw GitHubCopilotOAuthError.invalidCallbackURL(configuration.callbackURLString)
        }

        var components = URLComponents(string: "https://github.com/login/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.callbackURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "scope", value: configuration.scopeString.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components?.url else {
            throw GitHubCopilotOAuthError.invalidAuthorizeURL
        }
        return url
    }
}

public actor GitHubCopilotOAuthTokenExchanger {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public nonisolated func buildRequest(
        code: String,
        state: String,
        configuration: GitHubCopilotConfiguration
    ) throws -> URLRequest {
        let relayURLString = configuration.tokenExchangeURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relayURLString.isEmpty else {
            throw GitHubCopilotOAuthError.missingTokenExchangeRelay
        }
        guard let relayURL = URL(string: relayURLString) else {
            throw GitHubCopilotOAuthError.invalidTokenExchangeRelay(configuration.tokenExchangeURLString)
        }

        var request = URLRequest(url: relayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": configuration.clientID,
            "code": code,
            "redirect_uri": configuration.callbackURLString,
            "state": state
        ])
        return request
    }

    public func exchange(
        code: String,
        state: String,
        configuration: GitHubCopilotConfiguration
    ) async throws -> String {
        let request = try buildRequest(code: code, state: state, configuration: configuration)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubCopilotOAuthError.malformedTokenExchangeResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubCopilotOAuthError.tokenExchangeHTTPError(
                statusCode: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8) ?? "Unknown relay error"
            )
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = root["access_token"] as? String,
              !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubCopilotOAuthError.malformedTokenExchangeResponse
        }
        return accessToken
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

