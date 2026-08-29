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
    let error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
    }
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
        request.httpBody = "client_id=\(clientId)&scope=\(scope)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubDeviceFlowError.invalidResponse
        }
        return try JSONDecoder().decode(GitHubDeviceCodeResponse.self, from: data)
    }

    /// Polls until the user approves the code, the code expires, or access is denied.
    func pollForToken(deviceCode: String, interval: Int, expiresIn: Int) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        var currentInterval = interval

        while Date() < deadline {
            try await Task.sleep(for: .seconds(currentInterval))
            try Task.checkCancellation()

            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "client_id=\(clientId)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code".data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw GitHubDeviceFlowError.invalidResponse
            }
            let decoded = try JSONDecoder().decode(GitHubAccessTokenResponse.self, from: data)

            if let token = decoded.accessToken {
                return token
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
}
