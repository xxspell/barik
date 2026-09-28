import Foundation
import Security
import SwiftUI

struct ClaudeUsageData {
    var fiveHourPercentage: Double = 0
    var fiveHourResetDate: Date?

    var weeklyPercentage: Double = 0
    var weeklyResetDate: Date?

    var plan: String = "Pro"
    var lastUpdated: Date = Date()
    var isAvailable: Bool = false

    var resetAvailable: Bool = false
    var resetExpiresAt: Date? = nil
}

private struct ClaudeUsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let cedarEmber: CedarEmberBlock?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case cedarEmber = "cedar_ember"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // five_hour / seven_day are documented API fields; keep strict
        // decoding so genuine malformation still throws as before.
        fiveHour = try container.decodeIfPresent(UsageBucket.self, forKey: .fiveHour)
        sevenDay = try container.decodeIfPresent(UsageBucket.self, forKey: .sevenDay)
        // cedar_ember is a reverse-engineered, undocumented block whose
        // shape may change without warning. A decode error anywhere in
        // this sub-tree must not affect fiveHour/sevenDay above, so it is
        // isolated behind try? and simply resolves to nil.
        cedarEmber = (try? container.decodeIfPresent(CedarEmberBlock.self, forKey: .cedarEmber)) ?? nil
    }

    struct UsageBucket: Codable {
        let utilization: Double
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    struct CedarEmberBlock: Codable {
        let eligible: Bool?
        let grants: [Grant]?

        struct Grant: Codable {
            let resetsLeft: Int?
            let endsAt: String?
            let usableNow: Bool?
            let blocking: Bool?

            enum CodingKeys: String, CodingKey {
                case resetsLeft = "resets_left"
                case endsAt = "ends_at"
                case usableNow = "usable_now"
                case blocking
            }
        }
    }
}

@MainActor
final class ClaudeUsageManager: ObservableObject {
    static let shared = ClaudeUsageManager()

    @Published private(set) var usageData = ClaudeUsageData()
    @Published private(set) var isConnected = false
    @Published private(set) var fetchFailed = false
    @Published private(set) var errorMessage: String?

    private var refreshTimer: Timer?
    private var cachedCredentials: (accessToken: String, plan: String)?
    private var currentConfig: ConfigData = [:]

    private static let connectedKey = "claude-usage-connected"
    private static let refreshInterval: TimeInterval = 120

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }
    }

    func startUpdating(config: ConfigData) {
        currentConfig = config
        reconnectIfNeeded()
    }

    func reconnectIfNeeded() {
        if !isConnected && UserDefaults.standard.bool(forKey: Self.connectedKey) {
            connectAndFetch()
        }
    }

    func stopUpdating() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        fetchFailed = false
        errorMessage = nil
        connectAndFetch()
    }

    func requestAccess() {
        connectAndFetch()
    }

    private func handleWake() {
        guard isConnected else { return }

        refreshTimer?.invalidate()
        Task {
            try? await Task.sleep(for: .seconds(2))
            connectAndFetch()
        }
    }

    private func connectAndFetch() {
        guard let creds = readKeychainCredentials() else {
            isConnected = false
            cachedCredentials = nil
            errorMessage = nil
            UserDefaults.standard.set(false, forKey: Self.connectedKey)
            return
        }

        cachedCredentials = creds
        isConnected = true
        UserDefaults.standard.set(true, forKey: Self.connectedKey)
        fetchData()

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchData()
            }
        }
    }

    private func fetchData() {
        guard let creds = cachedCredentials else { return }

        let plan = currentConfig["plan"]?.stringValue ?? creds.plan

        Task {
            let result = await fetchUsageWithRetry(token: creds.accessToken)

            switch result {
            case .success(let response):
                var data = ClaudeUsageData()
                data.fiveHourPercentage = (response.fiveHour?.utilization ?? 0) / 100
                data.fiveHourResetDate = response.fiveHour.flatMap { bucket in
                    bucket.resetsAt.flatMap(Self.parseISODate)
                }
                data.weeklyPercentage = (response.sevenDay?.utilization ?? 0) / 100
                data.weeklyResetDate = response.sevenDay.flatMap { bucket in
                    bucket.resetsAt.flatMap(Self.parseISODate)
                }
                data.plan = plan.capitalized
                data.lastUpdated = Date()
                data.isAvailable = true

                let resetInfo = Self.resetInfo(from: response.cedarEmber)
                data.resetAvailable = resetInfo.available
                data.resetExpiresAt = resetInfo.expiresAt

                fetchFailed = false
                errorMessage = nil
                usageData = data

            case .rateLimited:
                fetchFailed = true
                errorMessage = "Claude is rate limiting usage checks right now. Try again later."

            case .failed:
                fetchFailed = true
                errorMessage = "The request failed. Your token may have expired."
            }
        }
    }

    private func fetchUsageWithRetry(token: String) async -> FetchResult {
        for attempt in 0..<2 {
            let result = await fetchUsageFromAPI(token: token)
            switch result {
            case .success:
                return result
            case .rateLimited(let retryAfter):
                guard attempt == 0, retryAfter > 0, retryAfter <= 180 else {
                    return .rateLimited(retryAfter: retryAfter)
                }
                try? await Task.sleep(for: .seconds(retryAfter))
            case .failed:
                return .failed
            }
        }

        return .failed
    }

    private enum FetchResult {
        case success(ClaudeUsageResponse)
        case rateLimited(retryAfter: Int)
        case failed
    }

    private func fetchUsageFromAPI(token: String) async -> FetchResult {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1&skip_spend=1") else {
            return .failed
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-cli/2.1.280 (external, cli)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }

            if http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                    .flatMap(Int.init) ?? 0
                return .rateLimited(retryAfter: retryAfter)
            }

            guard http.statusCode == 200 else { return .failed }
            guard let decoded = try? JSONDecoder().decode(ClaudeUsageResponse.self, from: data) else {
                return .failed
            }

            return .success(decoded)
        } catch {
            return .failed
        }
    }

    private func readKeychainCredentials() -> (accessToken: String, plan: String)? {
        guard let data = Self.runSecurityFindGenericPassword(service: "Claude Code-credentials") else {
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }

        let plan = oauth["subscriptionType"] as? String ?? "pro"
        return (token, plan)
    }

    // Reads the item via the `security` CLI (the same tool Claude Code
    // itself uses to write it) instead of Security.framework directly,
    // so the read is attributed to that trusted system binary's identity
    // rather than Barik's own code signature. Sidesteps Keychain ACL
    // prompts tied to Barik's own (rebuild-unstable, ad-hoc-signed)
    // signature. See docs/superpowers/specs/2026-09-26-claude-keychain-security-cli-design.md.
    nonisolated private static func runSecurityFindGenericPassword(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !outputData.isEmpty else {
            return nil
        }

        var trimmed = outputData
        if trimmed.last == 0x0A {
            trimmed.removeLast()
        }
        return trimmed
    }

    nonisolated private static func parseISODate(_ rawValue: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: rawValue) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }

    nonisolated private static func resetInfo(
        from cedarEmber: ClaudeUsageResponse.CedarEmberBlock?
    ) -> (available: Bool, expiresAt: Date?) {
        guard let grants = cedarEmber?.grants else { return (false, nil) }
        let usable = grants.filter {
            ($0.usableNow ?? false) && !($0.blocking ?? false) && ($0.resetsLeft ?? 0) > 0
        }
        guard !usable.isEmpty else { return (false, nil) }
        let expiry = usable.compactMap { $0.endsAt.flatMap(Self.parseISODate) }.min()
        return (true, expiry)
    }
}
