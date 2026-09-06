import Foundation
import SwiftUI
import Security
import AppKit
import OSLog

// MARK: - Auth State

enum GitHubAuthState: Equatable {
    case signedOut
    case deviceFlowPending(userCode: String, verificationURI: String)
    case signedIn(login: String)
}

// MARK: - Data Models

struct GitHubContributionDay: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

struct GitHubData {
    var login: String = ""
    var streakDays: Int = 0
    var commitsToday: Int = 0
    var contributionDays: [GitHubContributionDay] = []
    var openIssues: Int = 0
    var openPRs: Int = 0
    var unreadNotifications: Int = 0
    var totalStars: Int = 0
    var lastUpdated: Date = Date()
    var isAvailable: Bool = false
}

// MARK: - Metrics

/// The set of metrics the bar widget/settings can show, in their default order.
enum GitHubMetric: String, CaseIterable {
    case streak
    case issues
    case prs
    case notifications
    case stars
    case commitsToday = "commits-today"

    var title: String {
        switch self {
        case .streak: return "Streak"
        case .issues: return "Issues"
        case .prs: return "Pull Requests"
        case .notifications: return "Notifications"
        case .stars: return "Stars"
        case .commitsToday: return "Commits Today"
        }
    }

    var systemImageName: String {
        switch self {
        case .streak: return "flame.fill"
        case .issues: return "smallcircle.filled.circle"
        case .prs: return "arrow.triangle.branch"
        case .notifications: return "bell"
        case .stars: return "star.fill"
        case .commitsToday: return "checkmark.circle"
        }
    }
}

extension GitHubMetric: Identifiable {
    var id: String { rawValue }
}

// MARK: - Streak Calculator

enum GitHubStreakCalculator {
    /// Computes the current commit streak from a list of per-day contribution counts.
    /// The most recent day ("today") is never treated as a break by itself — it may
    /// simply not be over yet. If today already has commits, it counts toward the streak.
    static func calculate(days: [GitHubContributionDay]) -> (streakDays: Int, commitsToday: Int) {
        let sorted = days.sorted { $0.date < $1.date }
        guard let today = sorted.last else { return (0, 0) }

        let commitsToday = today.count
        var streak = 0
        var index = sorted.count - 1

        if sorted[index].count == 0 {
            index -= 1
        }

        while index >= 0, sorted[index].count > 0 {
            streak += 1
            index -= 1
        }

        return (streak, commitsToday)
    }
}

// MARK: - GraphQL Response

private struct GitHubGraphQLResponse: Decodable {
    struct Viewer: Decodable {
        let login: String
        let contributionsCollection: ContributionsCollection
        let repositories: Repositories

        struct ContributionsCollection: Decodable {
            let contributionCalendar: ContributionCalendar
        }
        struct ContributionCalendar: Decodable {
            let weeks: [Week]
        }
        struct Week: Decodable {
            let contributionDays: [ContributionDay]
        }
        struct ContributionDay: Decodable {
            let date: String
            let contributionCount: Int
        }
        struct Repositories: Decodable {
            let nodes: [RepoNode]
        }
        struct RepoNode: Decodable {
            let stargazerCount: Int
        }
    }
    struct DataField: Decodable { let viewer: Viewer }
    let data: DataField
}

private struct GitHubSearchResponse: Decodable {
    let totalCount: Int
    enum CodingKeys: String, CodingKey { case totalCount = "total_count" }
}

private enum GitHubAPIError: Error {
    case unauthorized
    case rateLimited(resetAt: Date)
    case http(Int)
}

// MARK: - Manager

@MainActor
final class GitHubManager: ObservableObject {
    static let shared = GitHubManager()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "barik", category: "GitHubManager")

    @Published private(set) var data = GitHubData()
    @Published private(set) var authState: GitHubAuthState = .signedOut
    @Published private(set) var fetchFailed = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var rateLimitedUntil: Date?
    @Published private(set) var isFetching = false

    private var refreshTimer: Timer?
    private var currentConfig: ConfigData = [:]
    private var pollTask: Task<Void, Never>?
    private var fetchGeneration = 0

    private static let tokenKey = "barik-github-token"
    private static let refreshTokenKey = "barik-github-refresh-token"
    private static let tokenExpiryKey = "barik-github-token-expiry"
    private static let loginKey = "barik-github-login"

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }

        if let login = Self.loadKey(Self.loginKey), Self.loadKey(Self.tokenKey) != nil {
            authState = .signedIn(login: login)
        }
    }

    // MARK: Lifecycle

    func startUpdating(config: ConfigData) {
        currentConfig = config
        scheduleTimer()
        if case .signedIn = authState {
            fetchData()
        }
    }

    func refresh() {
        if let rateLimitedUntil {
            if Date() < rateLimitedUntil {
                // Still rate-limited: keep the rate-limit message visible instead of
                // letting a plain "Updated Xm ago" footer silently replace it with no
                // fetch having actually happened.
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                errorMessage = "Rate limited, retry at \(formatter.string(from: rateLimitedUntil))"
                fetchFailed = true
                return
            }
            // Window elapsed: clear the stale gate so it doesn't linger.
            self.rateLimitedUntil = nil
        }

        fetchFailed = false
        errorMessage = nil
        fetchData()
    }

    private func handleWake() {
        refreshTimer?.invalidate()
        Task {
            try? await Task.sleep(for: .seconds(2))
            fetchData()
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(currentConfig["refresh-interval"]?.intValue ?? 1800)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetchData() }
        }
    }

    private var includePrivate: Bool {
        currentConfig["include-private"]?.boolValue ?? true
    }

    private var scopes: String {
        includePrivate ? "repo read:user notifications" : "public_repo read:user notifications"
    }

    // MARK: Auth

    func startSignIn() {
        guard let clientId = currentConfig["client-id"]?.stringValue, !clientId.isEmpty else {
            errorMessage = "client-id not configured"
            return
        }

        let flow = GitHubDeviceFlow(clientId: clientId, scope: scopes)
        pollTask?.cancel()

        pollTask = Task { @MainActor in
            do {
                let code = try await flow.requestCode()
                authState = .deviceFlowPending(userCode: code.userCode, verificationURI: code.verificationUri)
                let result = try await flow.pollForToken(
                    deviceCode: code.deviceCode, interval: code.interval, expiresIn: code.expiresIn
                )
                Self.saveTokenResult(result)
                try await fetchLogin(token: result.accessToken)
            } catch GitHubDeviceFlowError.expired {
                logger.debug("GitHub device flow code expired")
                errorMessage = "Code expired, try again"
                authState = .signedOut
            } catch GitHubDeviceFlowError.accessDenied {
                logger.debug("GitHub device flow authorization denied by user")
                errorMessage = "Authorization denied"
                authState = .signedOut
            } catch {
                logger.error("GitHub sign-in failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
                authState = .signedOut
            }
        }
    }

    func signOut() {
        pollTask?.cancel()
        Self.deleteKey(Self.tokenKey)
        Self.deleteKey(Self.refreshTokenKey)
        Self.deleteKey(Self.tokenExpiryKey)
        Self.deleteKey(Self.loginKey)
        authState = .signedOut
        data = GitHubData()
    }

    /// Persists a token exchange result. `refreshToken`/`expiresIn` are only present
    /// for GitHub Apps with token expiration enabled — absent for classic OAuth Apps.
    private static func saveTokenResult(_ result: GitHubTokenResult) {
        saveKey(result.accessToken, key: tokenKey)
        if let refreshToken = result.refreshToken {
            saveKey(refreshToken, key: refreshTokenKey)
        } else {
            deleteKey(refreshTokenKey)
        }
        if let expiresIn = result.expiresIn {
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            saveKey(String(expiry.timeIntervalSince1970), key: tokenExpiryKey)
        } else {
            deleteKey(tokenExpiryKey)
        }
    }

    /// Returns a token usable for a request, refreshing it first if it's expired or
    /// about to expire. Returns nil (after signing out) if no usable token remains —
    /// e.g. the refresh token itself expired or was revoked.
    private func validAccessToken() async -> String? {
        guard let token = Self.loadKey(Self.tokenKey) else { return nil }
        guard let refreshToken = Self.loadKey(Self.refreshTokenKey),
              let expiryInterval = Self.loadKey(Self.tokenExpiryKey).flatMap(Double.init)
        else {
            // No expiry metadata: a classic OAuth App token, which doesn't expire.
            return token
        }

        let expiry = Date(timeIntervalSince1970: expiryInterval)
        guard Date() > expiry.addingTimeInterval(-60) else { return token }

        guard let clientId = currentConfig["client-id"]?.stringValue, !clientId.isEmpty else { return token }

        do {
            let flow = GitHubDeviceFlow(clientId: clientId, scope: scopes)
            let result = try await flow.refreshAccessToken(refreshToken: refreshToken)
            Self.saveTokenResult(result)
            return result.accessToken
        } catch {
            logger.error("GitHub token refresh failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetchLogin(token: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response)

        struct UserResponse: Decodable { let login: String }
        let user = try JSONDecoder().decode(UserResponse.self, from: responseData)

        Self.saveKey(user.login, key: Self.loginKey)
        authState = .signedIn(login: user.login)
        fetchData()
    }

    // MARK: Fetch

    private func fetchData() {
        guard case .signedIn(let login) = authState else { return }
        if let rateLimitedUntil, Date() < rateLimitedUntil { return }

        // Multiple triggers (timer, manual refresh, wake, widget re-appear)
        // can call fetchData() while a previous call is still in flight.
        // Without this guard, an older/slower call finishing after a newer
        // one would silently overwrite fresher data with stale results.
        fetchGeneration += 1
        let generation = fetchGeneration
        isFetching = true

        Task {
            defer {
                // Only the latest generation clears the spinner — an older
                // call finishing after a newer one started must not hide
                // the fact that the newer fetch is still in flight.
                if generation == fetchGeneration {
                    isFetching = false
                }
            }

            // Refreshes an about-to-expire token before use so routine 8-hour
            // GitHub App token expiry doesn't surface as a sign-in error.
            guard let token = await validAccessToken() else {
                guard generation == fetchGeneration else { return }
                signOut()
                fetchFailed = true
                errorMessage = "Sign-in expired, please reconnect"
                return
            }
            guard generation == fetchGeneration else { return }

            var newData = data
            var anySucceeded = false
            var lastError: String?
            var rateLimitError: String?

            // Launch all four requests concurrently up front. Awaiting each
            // `async let` binding below only blocks on that specific result —
            // the underlying network calls are already in flight together.
            // GitHub's search API only supports OR between values of the SAME
            // qualifier — "author:x OR review-requested:x" (with or without
            // parens) is rejected with a 422. Query the two qualifiers
            // separately and sum them instead.
            async let graphQLResult = fetchGraphQL(token: token)
            async let issuesResult = fetchSearchCount(token: token, query: "is:issue is:open user:\(login)")
            async let authoredPRsResult = fetchSearchCount(token: token, query: "is:pr is:open author:\(login)")
            async let reviewRequestedPRsResult = fetchSearchCount(token: token, query: "is:pr is:open review-requested:\(login)")
            async let notificationsResult = fetchNotificationCount(token: token)

            do {
                let (days, stars) = try await graphQLResult
                let (streak, commitsToday) = GitHubStreakCalculator.calculate(days: days)
                newData.contributionDays = days
                newData.totalStars = stars
                newData.streakDays = streak
                newData.commitsToday = commitsToday
                newData.login = login
                anySucceeded = true
            } catch {
                let message = handleFetchError(error)
                if case GitHubAPIError.rateLimited = error { rateLimitError = message } else { lastError = message }
            }

            do {
                newData.openIssues = try await issuesResult
                anySucceeded = true
            } catch {
                let message = handleFetchError(error)
                if case GitHubAPIError.rateLimited = error { rateLimitError = message } else { lastError = message }
            }

            var prTotal = 0
            var prSucceeded = false
            do {
                prTotal += try await authoredPRsResult
                prSucceeded = true
            } catch {
                let message = handleFetchError(error)
                if case GitHubAPIError.rateLimited = error { rateLimitError = message } else { lastError = message }
            }
            do {
                prTotal += try await reviewRequestedPRsResult
                prSucceeded = true
            } catch {
                let message = handleFetchError(error)
                if case GitHubAPIError.rateLimited = error { rateLimitError = message } else { lastError = message }
            }
            if prSucceeded {
                newData.openPRs = prTotal
                anySucceeded = true
            }

            do {
                newData.unreadNotifications = try await notificationsResult
                anySucceeded = true
            } catch {
                let message = handleFetchError(error)
                if case GitHubAPIError.rateLimited = error { rateLimitError = message } else { lastError = message }
            }

            // A rate-limit signal is more actionable than a generic failure
            // from another concurrent call in the same pass, so it takes
            // priority when both occurred.
            let finalErrorMessage = rateLimitError ?? lastError

            // A newer fetchData() call superseded this one while it was in
            // flight — discard this pass entirely rather than let a slow,
            // stale response clobber the newer result (or its error state).
            guard generation == fetchGeneration else { return }

            // If any of the four calls 401'd, `handleFetchError` already
            // signed out and reset `authState`/`data`. The other calls were
            // already in flight with the stale token/login and may still
            // have "succeeded" — discard their results instead of writing
            // stale data back right after a sign-out.
            guard case .signedIn = authState else {
                fetchFailed = true
                errorMessage = finalErrorMessage
                return
            }

            if anySucceeded {
                newData.isAvailable = true
                newData.lastUpdated = Date()
                data = newData
            }

            fetchFailed = !anySucceeded
            errorMessage = finalErrorMessage
        }
    }

    private func fetchGraphQL(token: String) async throws -> (days: [GitHubContributionDay], stars: Int) {
        let query = """
        query {
          viewer {
            login
            contributionsCollection {
              contributionCalendar {
                weeks { contributionDays { date contributionCount } }
              }
            }
            # Only sums stars from the first 100 owned repos (GraphQL page size) —
            # an intentional budget cap, not a bug.
            repositories(first: 100, ownerAffiliations: OWNER, isFork: false) {
              nodes { stargazerCount }
            }
          }
        }
        """

        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response)

        let decoded = try JSONDecoder().decode(GitHubGraphQLResponse.self, from: responseData)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let days: [GitHubContributionDay] = decoded.data.viewer.contributionsCollection.contributionCalendar.weeks
            .flatMap { $0.contributionDays }
            .compactMap { day in
                guard let date = dateFormatter.date(from: day.date) else { return nil }
                return GitHubContributionDay(date: date, count: day.contributionCount)
            }

        let stars = decoded.data.viewer.repositories.nodes.reduce(0) { $0 + $1.stargazerCount }
        return (days, stars)
    }

    private func fetchSearchCount(token: String, query: String) async throws -> Int {
        var components = URLComponents(string: "https://api.github.com/search/issues")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "1"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response)
        return try JSONDecoder().decode(GitHubSearchResponse.self, from: responseData).totalCount
    }

    // Capped at 50 for a menu-bar glance — not paginated; a user with more unread
    // notifications will see a flat 50.
    private func fetchNotificationCount(token: String) async throws -> Int {
        var request = URLRequest(url: URL(string: "https://api.github.com/notifications?participating=false&per_page=50")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (responseData, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response)
        let array = try JSONSerialization.jsonObject(with: responseData) as? [Any]
        return array?.count ?? 0
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw GitHubAPIError.http(-1) }
        if http.statusCode == 401 { throw GitHubAPIError.unauthorized }
        if http.statusCode == 403, http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
            let resetEpoch = Double(http.value(forHTTPHeaderField: "X-RateLimit-Reset") ?? "")
                ?? Date().timeIntervalSince1970 + 3600
            throw GitHubAPIError.rateLimited(resetAt: Date(timeIntervalSince1970: resetEpoch))
        }
        guard (200...299).contains(http.statusCode) else { throw GitHubAPIError.http(http.statusCode) }
    }

    private func handleFetchError(_ error: Error) -> String {
        switch error {
        case GitHubAPIError.unauthorized:
            logger.error("GitHub fetch unauthorized (401) — signing out")
            signOut()
            return "Sign-in expired, please reconnect"
        case GitHubAPIError.rateLimited(let resetAt):
            logger.debug("GitHub fetch rate limited until \(resetAt, privacy: .public)")
            rateLimitedUntil = resetAt
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Rate limited, retry at \(formatter.string(from: resetAt))"
        case GitHubAPIError.http(let code):
            logger.debug("GitHub fetch failed with HTTP \(code, privacy: .public)")
            return "HTTP \(code)"
        default:
            logger.error("GitHub fetch failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    // MARK: Keychain

    private static func saveKey(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadKey(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKey(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: key]
        SecItemDelete(query as CFDictionary)
    }
}
