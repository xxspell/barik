import Foundation
import SwiftUI

private let codexUsageAccountFingerprintKey = "codex-usage-account-fingerprint"
private let codexUsageAcceptedRefreshKey = "codex-usage-accepted-auth-refresh"

struct CodexUsageData {
    var primaryPercentage: Double = 0
    var primaryResetDate: Date?
    var primaryWindowMinutes: Int = 0

    var plan: String = "ChatGPT"
    var lastUpdated: Date = Date()
    var lastActivityDate: Date?
    var isAvailable: Bool = false
}

private struct CodexSessionEvent: Decodable {
    let timestamp: String
    let type: String
    let payload: Payload

    struct Payload: Decodable {
        let type: String
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }
    }

    struct RateLimits: Decodable {
        let primary: Bucket?
        let planType: String?

        enum CodingKeys: String, CodingKey {
            case primary
            case planType = "plan_type"
        }
    }

    struct Bucket: Decodable {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: TimeInterval

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }
    }
}

private enum CodexUsageLoadState {
    case disconnected
    case connectedWithoutSnapshot(data: CodexUsageData)
    case connected(data: CodexUsageData)
    case failed
}

private struct CodexSessionScanResult {
    var latestSnapshot: (bucket: CodexSessionEvent.Bucket, plan: String?, timestamp: Date)?
    var latestActivity: Date?
}

private struct CodexAuthState {
    let plan: String
    let accountID: String?
    let userID: String?
    let lastRefreshDate: Date?
    let subscriptionActiveStart: Date?

    var fingerprint: String? {
        let parts = [accountID, userID]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "|")
    }

    var switchCutoffDate: Date? {
        [lastRefreshDate, subscriptionActiveStart]
            .compactMap { $0 }
            .max()
    }
}

@MainActor
final class CodexUsageManager: ObservableObject {
    static let shared = CodexUsageManager()

    @Published private(set) var usageData = CodexUsageData()
    @Published private(set) var isConnected = false
    @Published private(set) var fetchFailed = false

    private var refreshTimer: Timer?
    private var currentConfig: ConfigData = [:]

    private static let refreshInterval: TimeInterval = 30
    private static let sessionEventDecoder = JSONDecoder()
    private static let tokenCountMarker = Data(#""type":"token_count""#.utf8)
    private static let rateLimitsMarker = Data(#""rate_limits":"#.utf8)
    private static let timestampParseQueue = DispatchQueue(
        label: "barik.codex-usage.timestamp-parse"
    )
    private static let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plainTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

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
        connectAndFetch()
    }

    func reconnectIfNeeded() {
        connectAndFetch()
    }

    func stopUpdating() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        fetchFailed = false
        connectAndFetch()
    }

    private func handleWake() {
        refreshTimer?.invalidate()
        Task {
            try? await Task.sleep(for: .seconds(2))
            connectAndFetch()
        }
    }

    private func connectAndFetch() {
        let planOverride = currentConfig["plan"]?.stringValue

        Task {
            let loadState = await Task.detached(priority: .utility) {
                Self.loadUsage(planOverride: planOverride)
            }.value

            switch loadState {
            case .disconnected:
                isConnected = false
                fetchFailed = false
                usageData = CodexUsageData()
                stopUpdating()

            case .connectedWithoutSnapshot(let data):
                isConnected = true
                fetchFailed = false
                usageData = data
                scheduleRefreshTimer()

            case .connected(let data):
                isConnected = true
                fetchFailed = false
                usageData = data
                scheduleRefreshTimer()

            case .failed:
                isConnected = true
                fetchFailed = true
                scheduleRefreshTimer()
            }
        }
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.connectAndFetch()
            }
        }
    }

    nonisolated private static func loadUsage(planOverride: String?) -> CodexUsageLoadState {
        let codexHome = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let authURL = codexHome.appendingPathComponent("auth.json")
        let sessionsURL = codexHome.appendingPathComponent("sessions", isDirectory: true)

        guard let auth = readAuthState(from: authURL) else {
            return .disconnected
        }

        let plan = formatPlan(planOverride ?? auth.plan)
        let cutoffDate = accountSwitchCutoffDate(for: auth)
        let sessionFiles = recentSessionFiles(in: sessionsURL)
        let scanResult = scanRecentSessionFiles(sessionFiles, after: cutoffDate)

        guard let snapshot = scanResult.latestSnapshot else {
            var data = CodexUsageData(plan: plan)
            data.lastActivityDate = scanResult.latestActivity
            return .connectedWithoutSnapshot(data: data)
        }

        persistAccountFingerprintIfNeeded(auth)

        let primaryPercentage = max(0, min(snapshot.bucket.usedPercent / 100, 1))
        let data = CodexUsageData(
            primaryPercentage: primaryPercentage,
            primaryResetDate: Date(timeIntervalSince1970: snapshot.bucket.resetsAt),
            primaryWindowMinutes: snapshot.bucket.windowMinutes,
            plan: formatPlan(planOverride ?? snapshot.plan ?? auth.plan),
            lastUpdated: snapshot.timestamp,
            lastActivityDate: scanResult.latestActivity,
            isAvailable: true
        )
        return .connected(data: data)
    }

    nonisolated private static func readAuthState(from authURL: URL) -> CodexAuthState? {
        guard let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let authMode = json["auth_mode"] as? String
        if authMode == "apikey" || authMode == "api_key" {
            return CodexAuthState(
                plan: "API Key",
                accountID: nil,
                userID: nil,
                lastRefreshDate: parseTimestamp(json["last_refresh"] as? String ?? ""),
                subscriptionActiveStart: nil
            )
        }

        guard let tokens = json["tokens"] as? [String: Any] else {
            return nil
        }

        let accountID = tokens["account_id"] as? String
        let lastRefreshDate = parseTimestamp(json["last_refresh"] as? String ?? "")
        let candidateTokens = [
            tokens["id_token"] as? String,
            tokens["access_token"] as? String,
        ]

        for token in candidateTokens {
            guard let token,
                  let payload = decodeJWTPayload(token),
                  let auth = payload["https://api.openai.com/auth"] as? [String: Any],
                  let plan = auth["chatgpt_plan_type"] as? String,
                  !plan.isEmpty else {
                continue
            }

            return CodexAuthState(
                plan: plan,
                accountID: auth["chatgpt_account_id"] as? String ?? accountID,
                userID: auth["chatgpt_user_id"] as? String ?? auth["user_id"] as? String,
                lastRefreshDate: lastRefreshDate,
                subscriptionActiveStart: parseTimestamp(
                    auth["chatgpt_subscription_active_start"] as? String ?? ""
                )
            )
        }

        return nil
    }

    nonisolated private static func scanRecentSessionFiles(
        _ files: [URL],
        after cutoffDate: Date?
    ) -> CodexSessionScanResult {
        var result = CodexSessionScanResult()

        for fileURL in files {
            guard let content = try? Data(contentsOf: fileURL) else {
                continue
            }

            enumerateLinesBackwards(in: content) { line in
                let containsTokenCount = line.range(of: tokenCountMarker) != nil
                guard containsTokenCount else {
                    return true
                }

                if result.latestActivity == nil,
                   let event = decodeEvent(from: line),
                   event.type == "event_msg",
                   event.payload.type == "token_count",
                   let timestamp = parseTimestamp(event.timestamp) {
                    result.latestActivity = timestamp
                }

                guard result.latestSnapshot == nil || line.range(of: rateLimitsMarker) != nil else {
                    return result.latestActivity == nil
                }

                guard let event = decodeEvent(from: line),
                      event.type == "event_msg",
                      event.payload.type == "token_count",
                      let rateLimits = event.payload.rateLimits,
                      let bucket = rateLimits.primary,
                      let timestamp = parseTimestamp(event.timestamp) else {
                    return result.latestActivity == nil || result.latestSnapshot == nil
                }

                if let cutoffDate, timestamp < cutoffDate {
                    return result.latestActivity == nil || result.latestSnapshot == nil
                }

                if let latestSnapshot = result.latestSnapshot,
                   latestSnapshot.timestamp >= timestamp {
                    return result.latestActivity == nil || result.latestSnapshot == nil
                }

                result.latestSnapshot = (
                    bucket: bucket,
                    plan: rateLimits.planType,
                    timestamp: timestamp
                )

                return result.latestActivity == nil || result.latestSnapshot == nil
            }

            if result.latestActivity != nil, result.latestSnapshot != nil {
                break
            }
        }

        return result
    }

    nonisolated private static func enumerateLinesBackwards(
        in data: Data,
        _ body: (Data) -> Bool
    ) {
        guard !data.isEmpty else { return }

        var end = data.endIndex

        while end > data.startIndex {
            var lineEnd = end
            if lineEnd > data.startIndex,
               data[data.index(before: lineEnd)] == 0x0A {
                lineEnd = data.index(before: lineEnd)
            }

            var lineStart = lineEnd
            while lineStart > data.startIndex,
                  data[data.index(before: lineStart)] != 0x0A {
                lineStart = data.index(before: lineStart)
            }

            if lineStart < lineEnd {
                var line = data.subdata(in: lineStart..<lineEnd)
                if line.last == 0x0D {
                    line.removeLast()
                }

                if !line.isEmpty, body(line) == false {
                    return
                }
            }

            end = lineStart
            if end > data.startIndex,
               data[data.index(before: end)] == 0x0A {
                end = data.index(before: end)
            }
        }
    }

    nonisolated private static func accountSwitchCutoffDate(for auth: CodexAuthState) -> Date? {
        guard let fingerprint = auth.fingerprint else {
            return nil
        }

        let defaults = UserDefaults.standard
        guard let previousFingerprint = defaults.string(forKey: codexUsageAccountFingerprintKey) else {
            return auth.switchCutoffDate
        }

        guard previousFingerprint == fingerprint else {
            return auth.switchCutoffDate
        }

        guard defaults.object(forKey: codexUsageAcceptedRefreshKey) != nil else {
            return auth.switchCutoffDate
        }

        return nil
    }

    nonisolated private static func persistAccountFingerprintIfNeeded(_ auth: CodexAuthState) {
        guard let fingerprint = auth.fingerprint else {
            return
        }

        UserDefaults.standard.set(fingerprint, forKey: codexUsageAccountFingerprintKey)
        if let refreshDate = auth.switchCutoffDate {
            UserDefaults.standard.set(refreshDate.timeIntervalSince1970, forKey: codexUsageAcceptedRefreshKey)
        }
    }

    nonisolated private static func recentSessionFiles(in sessionsURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if lhsDate == rhsDate {
                    return lhs.path > rhs.path
                }
                return lhsDate > rhsDate
            }
            .prefix(100)
            .map { $0 }
    }

    nonisolated private static func decodeEvent(from line: Data) -> CodexSessionEvent? {
        try? sessionEventDecoder.decode(CodexSessionEvent.self, from: line)
    }

    nonisolated private static func parseTimestamp(_ rawValue: String) -> Date? {
        timestampParseQueue.sync {
            if let date = fractionalTimestampFormatter.date(from: rawValue) {
                return date
            }

            return plainTimestampFormatter.date(from: rawValue)
        }
    }

    nonisolated private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = 4 - (payload.count % 4)
        if padding < 4 {
            payload += String(repeating: "=", count: padding)
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }

    nonisolated private static func formatPlan(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "free":
            "Free"
        case "plus":
            "Plus"
        case "pro":
            "Pro"
        case "team":
            "Team"
        case "business":
            "Business"
        case "enterprise":
            "Enterprise"
        case "api key":
            "API Key"
        default:
            rawValue
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}
