import Foundation

struct GitHubDeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct GitHubAccessTokenResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let refreshTokenExpiresIn: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case error
    }
}

/// A GitHub App with "Expire user authorization tokens" enabled returns a
/// short-lived access token alongside a long-lived refresh token. Classic
/// OAuth Apps (and GitHub Apps without expiration enabled) omit `refresh_token`
/// and `expires_in` entirely — the access token is then non-expiring.
struct GitHubTokenResult {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
}

enum GitHubDeviceFlowError: Error {
    case expired
    case accessDenied
    case invalidResponse
}

/// GitHub OAuth Device Flow — no client secret or local callback server required.
/// See https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
final class GitHubDeviceFlow {
    private let clientId: String
    private let scope: String

    init(clientId: String, scope: String) {
        self.clientId = clientId
        self.scope = scope
    }

    func requestCode() async throws -> GitHubDeviceCodeResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encodedClientId = clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientId
        let encodedScope = scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scope
        request.httpBody = "client_id=\(encodedClientId)&scope=\(encodedScope)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubDeviceFlowError.invalidResponse
        }
        return try JSONDecoder().decode(GitHubDeviceCodeResponse.self, from: data)
    }

    /// Polls until the user approves the code, the code expires, or access is denied.
    func pollForToken(deviceCode: String, interval: Int, expiresIn: Int) async throws -> GitHubTokenResult {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        var currentInterval = interval

        while Date() < deadline {
            try await Task.sleep(for: .seconds(currentInterval))
            try Task.checkCancellation()

            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let encodedClientId = clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientId
            let encodedDeviceCode = deviceCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceCode
            request.httpBody = "client_id=\(encodedClientId)&device_code=\(encodedDeviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code".data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw GitHubDeviceFlowError.invalidResponse
            }
            let decoded = try JSONDecoder().decode(GitHubAccessTokenResponse.self, from: data)

            if let token = decoded.accessToken {
                return GitHubTokenResult(
                    accessToken: token, refreshToken: decoded.refreshToken, expiresIn: decoded.expiresIn
                )
            }

            switch decoded.error {
            case "authorization_pending", "slow_down":
                if decoded.error == "slow_down" { currentInterval += 5 }
                continue
            case "expired_token":
                throw GitHubDeviceFlowError.expired
            case "access_denied":
                throw GitHubDeviceFlowError.accessDenied
            default:
                continue
            }
        }

        throw GitHubDeviceFlowError.expired
    }

    /// Exchanges a refresh token for a new access token. Only meaningful for GitHub
    /// Apps with "Expire user authorization tokens" enabled — see `GitHubTokenResult`.
    func refreshAccessToken(refreshToken: String) async throws -> GitHubTokenResult {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encodedClientId = clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientId
        let encodedRefreshToken = refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken
        request.httpBody = "client_id=\(encodedClientId)&refresh_token=\(encodedRefreshToken)&grant_type=refresh_token".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubDeviceFlowError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(GitHubAccessTokenResponse.self, from: data)
        guard let token = decoded.accessToken else {
            throw GitHubDeviceFlowError.invalidResponse
        }
        return GitHubTokenResult(accessToken: token, refreshToken: decoded.refreshToken, expiresIn: decoded.expiresIn)
    }
}
