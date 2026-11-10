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

    /// Extra weekly limits scoped to a model or surface (e.g. "Fable").
    var scopedLimits: [ScopedLimit] = []
    /// Share of this week's usage per surface (Claude Code, Chats, ...).
    var surfaceBreakdown: [SurfaceShare] = []
    var extraUsage: ExtraUsage? = nil

    struct ScopedLimit: Identifiable {
        let id: Int
        let name: String
        let percentage: Double
        let resetDate: Date?
    }

    struct SurfaceShare: Identifiable {
        let id: String
        let name: String
        let percentage: Double
    }

    struct ExtraUsage {
        let isEnabled: Bool
        /// 0...1, nil when the API does not report it.
        let utilization: Double?
    }
}

private struct ClaudeUsageResponse: Decodable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let cedarEmber: CedarEmberBlock?
    let limits: [LimitEntry]?
    let sevenDayBreakdown: BreakdownBlock?
    let extraUsage: ExtraUsageBlock?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case cedarEmber = "cedar_ember"
        case limits
        case sevenDayBreakdown = "seven_day_breakdown"
        case extraUsage = "extra_usage"
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
        // Same isolation for the other undocumented blocks: if their shape
        // changes, the matching popup section just disappears.
        limits = (try? container.decodeIfPresent([LimitEntry].self, forKey: .limits)) ?? nil
        sevenDayBreakdown = (try? container.decodeIfPresent(BreakdownBlock.self, forKey: .sevenDayBreakdown)) ?? nil
        extraUsage = (try? container.decodeIfPresent(ExtraUsageBlock.self, forKey: .extraUsage)) ?? nil
    }

    struct LimitEntry: Decodable {
        let kind: String?
        let percent: Double?
        let resetsAt: String?
        let scopeName: String?

        enum CodingKeys: String, CodingKey {
            case kind, percent, scope
            case resetsAt = "resets_at"
        }

        enum ScopeKeys: String, CodingKey {
            case model, surface
        }

        struct Named: Decodable {
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try? container.decodeIfPresent(String.self, forKey: .kind)
            percent = try? container.decodeIfPresent(Double.self, forKey: .percent)
            resetsAt = try? container.decodeIfPresent(String.self, forKey: .resetsAt)

            // `scope` is null for unscoped limits; `surface` has only been
            // observed as null, so its shape is a guess.
            let scope = try? container.nestedContainer(keyedBy: ScopeKeys.self, forKey: .scope)
            let model = (try? scope?.decodeIfPresent(Named.self, forKey: .model)) ?? nil
            let surface = (try? scope?.decodeIfPresent(Named.self, forKey: .surface)) ?? nil
            scopeName = model?.displayName ?? surface?.displayName
        }
    }

    struct BreakdownBlock: Decodable {
        let rows: [Row]?

        struct Row: Decodable {
            let key: String?
            let displayName: String?
            let percent: Double?

            enum CodingKeys: String, CodingKey {
                case key, percent
                case displayName = "display_name"
            }
        }
    }

    struct ExtraUsageBlock: Decodable {
        let isEnabled: Bool?
        let utilization: Double?

        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case utilization
        }
    }

    struct UsageBucket: Codable {
        let utilization: Double
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    struct CedarEmberBlock: Decodable {
        let eligible: Bool?
        let grants: [Grant]?

        struct Grant: Decodable {
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

            // Field-by-field tolerance: one field changing type must not
            // drop the whole grant (and with it the reset banner).
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                resetsLeft = try? container.decodeIfPresent(Int.self, forKey: .resetsLeft)
                endsAt = try? container.decodeIfPresent(String.self, forKey: .endsAt)
                usableNow = try? container.decodeIfPresent(Bool.self, forKey: .usableNow)

                // `blocking` used to be a Bool and is now a list of the
                // limits blocking the grant; an empty list means "not blocked".
                if let flag = try? container.decode(Bool.self, forKey: .blocking) {
                    blocking = flag
                } else if let list = try? container.nestedUnkeyedContainer(forKey: .blocking) {
                    blocking = !list.isAtEnd
                } else {
                    blocking = nil
                }
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

                data.scopedLimits = Self.scopedLimits(from: response.limits)
                data.surfaceBreakdown = Self.surfaceBreakdown(from: response.sevenDayBreakdown)
                data.extraUsage = response.extraUsage.flatMap { block in
                    block.isEnabled.map {
                        ClaudeUsageData.ExtraUsage(
                            isEnabled: $0,
                            utilization: block.utilization.map { $0 / 100 }
                        )
                    }
                }

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
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1") else {
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

    nonisolated private static func scopedLimits(
        from limits: [ClaudeUsageResponse.LimitEntry]?
    ) -> [ClaudeUsageData.ScopedLimit] {
        guard let limits else { return [] }
        return limits.enumerated().compactMap { index, entry in
            guard entry.kind == "weekly_scoped",
                  let name = entry.scopeName, !name.isEmpty,
                  let percent = entry.percent else {
                return nil
            }
            return ClaudeUsageData.ScopedLimit(
                id: index,
                name: name,
                percentage: percent / 100,
                resetDate: entry.resetsAt.flatMap(Self.parseISODate)
            )
        }
    }

    nonisolated private static func surfaceBreakdown(
        from block: ClaudeUsageResponse.BreakdownBlock?
    ) -> [ClaudeUsageData.SurfaceShare] {
        guard let rows = block?.rows else { return [] }
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let name = row.displayName ?? row.key,
                  let percent = row.percent, percent > 0,
                  seen.insert(row.key ?? name).inserted else {
                return nil
            }
            return ClaudeUsageData.SurfaceShare(
                id: row.key ?? name,
                name: name,
                percentage: percent / 100
            )
        }
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
