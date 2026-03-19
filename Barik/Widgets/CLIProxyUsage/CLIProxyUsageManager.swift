import Foundation
import OSLog
import SwiftUI

let cliProxyUsageSelectedProviderKey = "cliproxy-usage.selected-provider"
let cliProxyUsageSelectedRangeKey = "cliproxy-usage.selected-range"

enum CLIProxyProviderFilter: String, CaseIterable, Codable, Identifiable {
    case all
    case codex
    case qwen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return NSLocalizedString("All", comment: "")
        case .codex:
            return NSLocalizedString("Codex", comment: "")
        case .qwen:
            return NSLocalizedString("Qwen", comment: "")
        }
    }

    func matchesAuthProvider(_ provider: String) -> Bool {
        if self == .all { return true }
        return provider == rawValue
    }

    func matchesUsageProvider(_ provider: String) -> Bool {
        if self == .all { return true }

        switch self {
        case .all:
            return true
        case .codex:
            return provider == "codex"
        case .qwen:
            return provider == "qwen"
        }
    }
}

enum CLIProxyTimeRange: String, CaseIterable, Codable, Identifiable {
    case all
    case hours7
    case hours24
    case days7

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return NSLocalizedString("All", comment: "")
        case .hours7:
            return NSLocalizedString("7h", comment: "")
        case .hours24:
            return NSLocalizedString("24h", comment: "")
        case .days7:
            return NSLocalizedString("7d", comment: "")
        }
    }

    var cutoffDate: Date? {
        switch self {
        case .all:
            return nil
        case .hours7:
            return Date().addingTimeInterval(-(7 * 3600))
        case .hours24:
            return Date().addingTimeInterval(-(24 * 3600))
        case .days7:
            return Date().addingTimeInterval(-(7 * 24 * 3600))
        }
    }
}

struct CLIProxyUsageDetail: Codable, Identifiable {
    let timestamp: Date
    let provider: String
    let authIndex: String?
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let failed: Bool

    var id: String {
        "\(provider)-\(authIndex ?? "na")-\(timestamp.timeIntervalSince1970)-\(totalTokens)-\(failed)"
    }
}

struct CLIProxyCodexQuotaSnapshot: Codable {
    var allowed: Bool = false
    var limitReached: Bool = false
    var usedPercent: Double = 0
    var resetAt: Date?
    var lastCheckedAt = Date()

    var hasQuota: Bool {
        allowed && !limitReached
    }
}

struct CLIProxyAuthCredential: Codable, Identifiable {
    let id: String
    let provider: String
    let authIndex: String?
    let accountID: String?
    let status: String
    let disabled: Bool
    let unavailable: Bool
    let label: String
    var quotaSnapshot: CLIProxyCodexQuotaSnapshot?

    var supportsQuota: Bool {
        switch provider {
        case CLIProxyProviderFilter.qwen.rawValue,
             CLIProxyProviderFilter.codex.rawValue:
            return true
        default:
            return false
        }
    }

    var isReady: Bool {
        quotaFraction > 0
    }

    var quotaFraction: Double {
        guard !disabled && !unavailable else { return 0 }

        switch provider {
        case CLIProxyProviderFilter.qwen.rawValue:
            return status.lowercased() == "active" ? 1 : 0
        case CLIProxyProviderFilter.codex.rawValue:
            guard let quotaSnapshot, quotaSnapshot.hasQuota else { return 0 }
            let remaining = 1 - (quotaSnapshot.usedPercent / 100)
            return max(0, min(1, remaining))
        default:
            return 0
        }
    }
}

struct CLIProxyQuotaSummary {
    let ready: Int
    let total: Int
    let supported: Bool
    let remainingQuota: Double

    var percentage: Double {
        guard total > 0 else { return 0 }
        return remainingQuota / Double(total)
    }
}

struct CLIProxyTokenSummary {
    let requests: Int
    let failures: Int
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
}

struct CLIProxyAPIKeyUsageSummary: Codable, Identifiable {
    let key: String
    let requests: Int
    let totalTokens: Int

    var id: String { key }

    var displayName: String {
        if key.hasPrefix("sk-") {
            return String(key.dropFirst(3))
        }
        return key
    }
}

struct CLIProxyQuotaSettings: Codable {
    var switchProject: Bool = false
    var switchPreviewModel: Bool = false
}

struct CLIProxyUsageData: Codable {
    var totalRequests: Int = 0
    var successCount: Int = 0
    var failureCount: Int = 0
    var totalTokens: Int = 0
    var details: [CLIProxyUsageDetail] = []
    var apiKeyUsage: [CLIProxyAPIKeyUsageSummary] = []
    var authCredentials: [CLIProxyAuthCredential] = []
    var quotaSettings = CLIProxyQuotaSettings()
    var lastUpdated = Date()
    var isAvailable = false

    var successRatio: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(successCount) / Double(totalRequests)
    }

    func quotaSummary(for provider: CLIProxyProviderFilter) -> CLIProxyQuotaSummary {
        let credentials = authCredentials.filter {
            provider.matchesAuthProvider($0.provider) && $0.supportsQuota
        }
        let ready = credentials.filter(\.isReady).count
        let remainingQuota = credentials.reduce(0) { $0 + $1.quotaFraction }
        return CLIProxyQuotaSummary(
            ready: ready,
            total: credentials.count,
            supported: !credentials.isEmpty,
            remainingQuota: remainingQuota
        )
    }

    func tokenSummary(
        for provider: CLIProxyProviderFilter,
        range: CLIProxyTimeRange
    ) -> CLIProxyTokenSummary {
        let cutoff = range.cutoffDate
        let filtered = details.filter { detail in
            provider.matchesUsageProvider(detail.provider)
                && (cutoff == nil || detail.timestamp >= cutoff!)
        }

        return CLIProxyTokenSummary(
            requests: filtered.count,
            failures: filtered.filter(\.failed).count,
            inputTokens: filtered.reduce(0) { $0 + $1.inputTokens },
            outputTokens: filtered.reduce(0) { $0 + $1.outputTokens },
            totalTokens: filtered.reduce(0) { $0 + $1.totalTokens }
        )
    }

    func groupedQuotaProviders() -> [(filter: CLIProxyProviderFilter, summary: CLIProxyQuotaSummary)] {
        CLIProxyProviderFilter.allCases
            .filter { $0 != .all }
            .map { provider in
                (provider, quotaSummary(for: provider))
            }
            .filter { $0.summary.total > 0 }
    }

    var topAPIKeys: [CLIProxyAPIKeyUsageSummary] {
        Array(apiKeyUsage.sorted {
            if $0.totalTokens == $1.totalTokens {
                return $0.requests > $1.requests
            }
            return $0.totalTokens > $1.totalTokens
        }.prefix(10))
    }
}

private struct CLIProxyUsageEnvelope: Decodable {
    let usage: Usage

    struct Usage: Decodable {
        let totalRequests: Int
        let successCount: Int
        let failureCount: Int
        let totalTokens: Int
        let apis: [String: APIStats]

        enum CodingKeys: String, CodingKey {
            case totalRequests = "total_requests"
            case successCount = "success_count"
            case failureCount = "failure_count"
            case totalTokens = "total_tokens"
            case apis
        }
    }

    struct APIStats: Decodable {
        let models: [String: ModelStats]
    }

    struct ModelStats: Decodable {
        let details: [Detail]
    }

    struct Detail: Decodable {
        let timestamp: String?
        let source: String?
        let authIndex: String?
        let failed: Bool?
        let tokens: Tokens?

        enum CodingKeys: String, CodingKey {
            case timestamp
            case source
            case authIndex = "auth_index"
            case failed
            case tokens
        }
    }

    struct Tokens: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

private struct CLIProxyConfigResponse: Decodable {
    let quotaExceeded: QuotaExceeded?

    enum CodingKeys: String, CodingKey {
        case quotaExceeded = "quota-exceeded"
    }

    struct QuotaExceeded: Decodable {
        let switchProject: Bool?
        let switchPreviewModel: Bool?

        enum CodingKeys: String, CodingKey {
            case switchProject = "switch-project"
            case switchPreviewModel = "switch-preview-model"
        }
    }
}

private struct CLIProxyAuthFilesResponse: Decodable {
    let files: [File]

    struct File: Decodable {
        let id: String
        let provider: String?
        let authIndex: String?
        let idToken: IDToken?
        let label: String?
        let status: String?
        let disabled: Bool?
        let unavailable: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case provider
            case authIndex = "auth_index"
            case idToken = "id_token"
            case label
            case status
            case disabled
            case unavailable
        }
    }

    struct IDToken: Decodable {
        let chatgptAccountID: String?

        enum CodingKeys: String, CodingKey {
            case chatgptAccountID = "chatgpt_account_id"
        }
    }
}

private struct CLIProxyManagementAPICallRequest: Encodable {
    let authIndex: String
    let method: String
    let url: String
    let header: [String: String]
}

private struct CLIProxyManagementAPICallResponse: Decodable {
    let statusCode: Int
    let body: String?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case body
    }
}

private struct CLIProxyCodexQuotaResponse: Decodable {
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }

    struct RateLimit: Decodable {
        let allowed: Bool
        let limitReached: Bool
        let primaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case allowed
            case limitReached = "limit_reached"
            case primaryWindow = "primary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let resetAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
        }
    }
}

private struct CLIProxyUsageCachePayload: Codable {
    let baseURL: String
    let usageData: CLIProxyUsageData
    let cachedAt: Date
}

@MainActor
final class CLIProxyUsageManager: ObservableObject {
    static let shared = CLIProxyUsageManager()

    @Published private(set) var usageData = CLIProxyUsageData()
    @Published private(set) var fetchFailed = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var quotaRefreshInProgress = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "CLIProxyUsageManager"
    )

    private var refreshTimer: Timer?
    private var currentConfig: ConfigData = [:]
    private var dataRefreshTask: Task<Void, Never>?

    private static let refreshInterval: TimeInterval = 300
    private static let cacheFileName = "barik/cliproxy-usage-cache.json"
    private static let quotaRefreshInterval: TimeInterval = 1800
    private static let recentCodexQuotaWindow: TimeInterval = 24 * 3600
    private static let maxCodexQuotaChecksPerRefresh = 8
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
        let previousBaseURL = configString(named: ["base-url", "base_url"], in: currentConfig)
        let newBaseURL = configString(named: ["base-url", "base_url"], in: config)
        let previousAPIKey = configString(named: ["api-key", "api_key"], in: currentConfig)
        let newAPIKey = configString(named: ["api-key", "api_key"], in: config)
        let configChanged = previousBaseURL != newBaseURL || previousAPIKey != newAPIKey

        currentConfig = config

        if configChanged {
            logger.debug("startUpdating() config changed, loading cache if available")
            loadCacheIfAvailable(for: newBaseURL)
        }

        if configChanged || !usageData.isAvailable {
            fetchData()
        }

        scheduleTimer()
    }

    func refresh() {
        logger.debug("refresh() requested")
        fetchFailed = false
        errorMessage = nil
        fetchData()
    }

    func refreshQuota() {
        guard hasConfiguration() else { return }
        let rawBaseURL = configString(named: ["base-url", "base_url"], in: currentConfig)
        let apiKey = configString(named: ["api-key", "api_key"], in: currentConfig)

        guard let managementBaseURL = normalizedManagementBaseURL(from: rawBaseURL),
              !apiKey.isEmpty else {
            return
        }

        refreshQuotaIfNeeded(
            using: managementBaseURL,
            apiKey: apiKey,
            forceAllRecent: true
        )
    }

    func hasConfiguration(in config: ConfigData? = nil) -> Bool {
        let targetConfig = config ?? currentConfig
        let baseURL = configString(named: ["base-url", "base_url"], in: targetConfig)
        let apiKey = configString(named: ["api-key", "api_key"], in: targetConfig)
        return !baseURL.isEmpty && !apiKey.isEmpty
    }

    private func handleWake() {
        refreshTimer?.invalidate()
        Task {
            try? await Task.sleep(for: .seconds(2))
            fetchData()
        }
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchData()
            }
        }
    }

    private func fetchData() {
        guard dataRefreshTask == nil else {
            logger.debug("fetchData() skipped, request already in flight")
            return
        }

        let rawBaseURL = configString(named: ["base-url", "base_url"], in: currentConfig)
        let apiKey = configString(named: ["api-key", "api_key"], in: currentConfig)

        guard !rawBaseURL.isEmpty else {
            logger.debug("fetchData() skipped: base-url missing")
            fetchFailed = false
            errorMessage = nil
            usageData = CLIProxyUsageData()
            return
        }

        guard !apiKey.isEmpty else {
            logger.debug("fetchData() skipped: api-key missing")
            fetchFailed = false
            errorMessage = nil
            usageData = CLIProxyUsageData()
            return
        }

        guard let managementBaseURL = normalizedManagementBaseURL(from: rawBaseURL) else {
            logger.error("fetchData() invalid base URL: \(rawBaseURL, privacy: .public)")
            fetchFailed = true
            errorMessage = NSLocalizedString("Invalid base URL", comment: "")
            return
        }

        logger.debug("fetchData() start for \(managementBaseURL.absoluteString, privacy: .public)")

        dataRefreshTask = Task {
            defer { dataRefreshTask = nil }

            do {
                async let usageEnvelope: CLIProxyUsageEnvelope = performRequest(
                    url: managementBaseURL.appendingPathComponent("usage"),
                    apiKey: apiKey
                )
                async let configResponse: CLIProxyConfigResponse = performRequest(
                    url: managementBaseURL.appendingPathComponent("config"),
                    apiKey: apiKey
                )
                async let authFilesResponse: CLIProxyAuthFilesResponse = performRequest(
                    url: managementBaseURL.appendingPathComponent("auth-files"),
                    apiKey: apiKey
                )

                let (usage, config, authFiles) = try await (usageEnvelope, configResponse, authFilesResponse)

                var newData = CLIProxyUsageData()
                newData.totalRequests = usage.usage.totalRequests
                newData.successCount = usage.usage.successCount
                newData.failureCount = usage.usage.failureCount
                newData.totalTokens = usage.usage.totalTokens
                newData.apiKeyUsage = buildAPIKeyUsage(from: usage.usage)
                let previousCredentials = usageData.authCredentials
                newData.authCredentials = buildAuthCredentials(
                    from: authFiles.files,
                    previousCredentials: previousCredentials
                )
                newData.details = buildUsageDetails(
                    from: usage.usage,
                    authCredentials: newData.authCredentials
                )
                newData.quotaSettings = CLIProxyQuotaSettings(
                    switchProject: config.quotaExceeded?.switchProject ?? false,
                    switchPreviewModel: config.quotaExceeded?.switchPreviewModel ?? false
                )
                newData.lastUpdated = Date()
                newData.isAvailable = true

                usageData = newData
                fetchFailed = false
                errorMessage = nil
                refreshQuotaIfNeeded(using: managementBaseURL, apiKey: apiKey, forceAllRecent: false)
                saveCache(newData, for: rawBaseURL)

                let allQuota = newData.quotaSummary(for: .all)
                logger.debug(
                    "fetchData() success requests=\(newData.totalRequests) details=\(newData.details.count) auth=\(newData.authCredentials.count) quotaReady=\(allQuota.ready)/\(allQuota.total)"
                )
            } catch {
                fetchFailed = true
                errorMessage = friendlyMessage(for: error)
                logger.error("fetchData() failed: \(error.localizedDescription, privacy: .public)")

                if usageData.isAvailable {
                    logger.debug("fetchData() keeping cached/in-memory data after failure")
                } else {
                    loadCacheIfAvailable(for: rawBaseURL)
                }
            }
        }
    }

    private func buildUsageDetails(
        from usage: CLIProxyUsageEnvelope.Usage,
        authCredentials: [CLIProxyAuthCredential]
    ) -> [CLIProxyUsageDetail] {
        var details: [CLIProxyUsageDetail] = []
        let authIndexPairs: [(String, String)] = authCredentials.compactMap { credential in
            guard let authIndex = credential.authIndex else { return nil }
            return (authIndex, credential.provider)
        }
        let providerByAuthIndex = Dictionary(uniqueKeysWithValues: authIndexPairs)

        for apiStats in usage.apis.values {
            for modelStats in apiStats.models.values {
                for detail in modelStats.details {
                    guard let timestampString = detail.timestamp,
                          let timestamp = Self.parseISODate(timestampString) else {
                        continue
                    }

                    let provider = detail.authIndex.flatMap { providerByAuthIndex[$0] }
                        ?? normalizedUsageProvider(detail.source)
                    let inputTokens = detail.tokens?.inputTokens ?? 0
                    let outputTokens = detail.tokens?.outputTokens ?? 0
                    let totalTokens = detail.tokens?.totalTokens ?? (inputTokens + outputTokens)

                    details.append(
                        CLIProxyUsageDetail(
                            timestamp: timestamp,
                            provider: provider,
                            authIndex: detail.authIndex,
                            inputTokens: inputTokens,
                            outputTokens: outputTokens,
                            totalTokens: totalTokens,
                            failed: detail.failed ?? false
                        )
                    )
                }
            }
        }

        return details.sorted { $0.timestamp > $1.timestamp }
    }

    private func buildAPIKeyUsage(from usage: CLIProxyUsageEnvelope.Usage) -> [CLIProxyAPIKeyUsageSummary] {
        usage.apis.map { key, stats in
            let requests = stats.models.values.reduce(0) { partialResult, modelStats in
                partialResult + modelStats.details.count
            }
            let totalTokens = stats.models.values.reduce(0) { partialResult, modelStats in
                partialResult + modelStats.details.reduce(0) { $0 + ($1.tokens?.totalTokens ?? 0) }
            }

            return CLIProxyAPIKeyUsageSummary(
                key: key,
                requests: requests,
                totalTokens: totalTokens
            )
        }
        .sorted {
            if $0.totalTokens == $1.totalTokens {
                return $0.requests > $1.requests
            }
            return $0.totalTokens > $1.totalTokens
        }
    }

    private func buildAuthCredentials(
        from files: [CLIProxyAuthFilesResponse.File],
        previousCredentials: [CLIProxyAuthCredential]
    ) -> [CLIProxyAuthCredential] {
        let supportedProviders = Set(CLIProxyProviderFilter.allCases.filter { $0 != .all }.map(\.rawValue))
        let previousQuotaByID = Dictionary(
            uniqueKeysWithValues: previousCredentials.map { ($0.id, $0.quotaSnapshot) }
        )

        let credentials = files.compactMap { file -> CLIProxyAuthCredential? in
            guard let provider = normalizedAuthProvider(file.provider),
                  supportedProviders.contains(provider) else {
                return nil
            }

            return CLIProxyAuthCredential(
                id: file.id,
                provider: provider,
                authIndex: file.authIndex,
                accountID: file.idToken?.chatgptAccountID,
                status: file.status ?? "unknown",
                disabled: file.disabled ?? false,
                unavailable: file.unavailable ?? false,
                label: file.label ?? file.id,
                quotaSnapshot: previousQuotaByID[file.id] ?? nil
            )
        }

        let counts = Dictionary(grouping: credentials, by: \.provider)
            .mapValues(\.count)
        logger.debug("buildAuthCredentials() providers=\(String(describing: counts), privacy: .public)")

        return credentials.sorted { lhs, rhs in
            if lhs.provider == rhs.provider {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.provider < rhs.provider
        }
    }

    private func refreshQuotaIfNeeded(
        using managementBaseURL: URL,
        apiKey: String,
        forceAllRecent: Bool
    ) {
        let codexCredentials = usageData.authCredentials.filter {
            $0.provider == CLIProxyProviderFilter.codex.rawValue
        }
        guard !codexCredentials.isEmpty else { return }

        let now = Date()
        let needsRefresh = codexCredentials.contains { credential in
            guard let snapshot = credential.quotaSnapshot else { return true }
            return now.timeIntervalSince(snapshot.lastCheckedAt) > Self.quotaRefreshInterval
        }

        guard forceAllRecent || needsRefresh else {
            logger.debug("refreshQuotaIfNeeded() skipped, quota cache is fresh")
            return
        }

        let recentlyUsedAuthIndexes = recentCodexAuthIndexes()
        let latestUsageByAuthIndex = latestCodexUsageByAuthIndex()
        let uncachedCredentials = codexCredentials.filter { $0.quotaSnapshot == nil }
        let usedSinceLastCheckCredentials = codexCredentials.filter { credential in
            guard let authIndex = credential.authIndex,
                  let lastUsageAt = latestUsageByAuthIndex[authIndex],
                  let snapshot = credential.quotaSnapshot else {
                return false
            }
            return lastUsageAt > snapshot.lastCheckedAt
        }
        let staleCachedCredentials = codexCredentials.filter { credential in
            guard credential.quotaSnapshot != nil else { return false }
            guard let authIndex = credential.authIndex else { return false }
            return recentlyUsedAuthIndexes.contains(authIndex)
        }
        let eligibleCredentials: [CLIProxyAuthCredential]

        if !uncachedCredentials.isEmpty {
            eligibleCredentials = uncachedCredentials
        } else if !usedSinceLastCheckCredentials.isEmpty {
            eligibleCredentials = usedSinceLastCheckCredentials
        } else if forceAllRecent {
            if !staleCachedCredentials.isEmpty {
                eligibleCredentials = staleCachedCredentials
            } else if recentlyUsedAuthIndexes.isEmpty {
                eligibleCredentials = codexCredentials
            } else {
                eligibleCredentials = codexCredentials.filter { credential in
                    guard let authIndex = credential.authIndex else { return false }
                    return recentlyUsedAuthIndexes.contains(authIndex)
                }
            }
        } else {
            guard !recentlyUsedAuthIndexes.isEmpty else {
                logger.debug("refreshQuotaIfNeeded() skipped, no recent Codex auth indexes")
                return
            }

            eligibleCredentials = staleCachedCredentials
        }

        let credentialsToRefresh: [CLIProxyAuthCredential]
        if !uncachedCredentials.isEmpty || !usedSinceLastCheckCredentials.isEmpty {
            credentialsToRefresh = eligibleCredentials
        } else {
            credentialsToRefresh = Array(eligibleCredentials.prefix(Self.maxCodexQuotaChecksPerRefresh))
        }

        guard !credentialsToRefresh.isEmpty else {
            logger.debug("refreshQuotaIfNeeded() skipped, no credentials matched recent indexes")
            return
        }

        quotaRefreshInProgress = true
        logger.debug(
            "refreshQuotaIfNeeded() start force=\(forceAllRecent) recent=\(recentlyUsedAuthIndexes.count) uncached=\(uncachedCredentials.count) changed=\(usedSinceLastCheckCredentials.count) checks=\(credentialsToRefresh.count)"
        )

        Task {
            defer { quotaRefreshInProgress = false }

            var updatedCredentials = usageData.authCredentials
            var refreshedCount = 0

            for credential in credentialsToRefresh {
                guard let authIndex = credential.authIndex,
                      let accountID = credential.accountID else {
                    continue
                }

                if let snapshot = await fetchCodexQuota(
                    managementBaseURL: managementBaseURL,
                    apiKey: apiKey,
                    authIndex: authIndex,
                    accountID: accountID
                ) {
                    if let index = updatedCredentials.firstIndex(where: { $0.id == credential.id }) {
                        updatedCredentials[index].quotaSnapshot = snapshot
                        refreshedCount += 1
                    }
                }
            }

            if refreshedCount > 0 {
                usageData.authCredentials = updatedCredentials
                usageData.lastUpdated = Date()
                saveCache(usageData, for: configString(named: ["base-url", "base_url"], in: currentConfig))
            }

            let codexQuota = usageData.quotaSummary(for: .codex)
            logger.debug(
                "refreshQuotaIfNeeded() refreshed=\(refreshedCount) codexQuota=\(codexQuota.ready)/\(codexQuota.total)"
            )
        }
    }

    private func recentCodexAuthIndexes() -> Set<String> {
        let cutoff = Date().addingTimeInterval(-Self.recentCodexQuotaWindow)
        let indexes = usageData.details
            .filter { $0.provider == CLIProxyProviderFilter.codex.rawValue && $0.timestamp >= cutoff }
            .compactMap(\.authIndex)
        return Set(indexes)
    }

    private func latestCodexUsageByAuthIndex() -> [String: Date] {
        var latestByAuthIndex: [String: Date] = [:]

        for detail in usageData.details where detail.provider == CLIProxyProviderFilter.codex.rawValue {
            guard let authIndex = detail.authIndex else { continue }
            let currentLatest = latestByAuthIndex[authIndex] ?? .distantPast
            if detail.timestamp > currentLatest {
                latestByAuthIndex[authIndex] = detail.timestamp
            }
        }

        return latestByAuthIndex
    }

    private func fetchCodexQuota(
        managementBaseURL: URL,
        apiKey: String,
        authIndex: String,
        accountID: String
    ) async -> CLIProxyCodexQuotaSnapshot? {
        let payload = CLIProxyManagementAPICallRequest(
            authIndex: authIndex,
            method: "GET",
            url: "https://chatgpt.com/backend-api/wham/usage",
            header: [
                "Authorization": "Bearer $TOKEN$",
                "Content-Type": "application/json",
                "User-Agent": "codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal",
                "Chatgpt-Account-Id": accountID
            ]
        )

        guard let response: CLIProxyManagementAPICallResponse = try? await performRequest(
            url: managementBaseURL.appendingPathComponent("api-call"),
            apiKey: apiKey,
            method: "POST",
            body: payload
        ) else {
            logger.error("fetchCodexQuota() api-call failed for authIndex=\(authIndex, privacy: .public)")
            return nil
        }

        guard response.statusCode == 200,
              let body = response.body,
              let data = body.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CLIProxyCodexQuotaResponse.self, from: data) else {
            logger.error("fetchCodexQuota() decode failed for authIndex=\(authIndex, privacy: .public)")
            return nil
        }

        let snapshot = CLIProxyCodexQuotaSnapshot(
            allowed: decoded.rateLimit?.allowed ?? false,
            limitReached: decoded.rateLimit?.limitReached ?? false,
            usedPercent: decoded.rateLimit?.primaryWindow?.usedPercent ?? 0,
            resetAt: decoded.rateLimit?.primaryWindow?.resetAt.map { Date(timeIntervalSince1970: $0) } ,
            lastCheckedAt: Date()
        )

        logger.debug(
            "fetchCodexQuota() authIndex=\(authIndex, privacy: .public) allowed=\(snapshot.allowed) reached=\(snapshot.limitReached) used=\(snapshot.usedPercent)"
        )
        return snapshot
    }

    private func performRequest<T: Decodable>(
        url: URL,
        apiKey: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIProxyError.invalidResponse
        }

        logger.debug("performRequest() \(url.lastPathComponent, privacy: .public) HTTP \(http.statusCode)")

        guard (200..<300).contains(http.statusCode) else {
            throw CLIProxyError.httpStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("performRequest() decode failed for \(url.absoluteString, privacy: .public)")
            throw CLIProxyError.decoding
        }
    }

    private func normalizedManagementBaseURL(from raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        guard let url = URL(string: value),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("usage") || path.hasSuffix("config") || path.hasSuffix("auth-files") {
            path = path.split(separator: "/").dropLast().joined(separator: "/")
        }
        if !path.hasSuffix("v0/management") {
            path = path.isEmpty ? "v0/management" : "\(path)/v0/management"
        }
        components.path = "/" + path
        return components.url
    }

    private func configString(named keys: [String], in config: ConfigData) -> String {
        for key in keys {
            if let value = config[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func normalizedUsageProvider(_ source: String?) -> String {
        let normalized = source?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "openai", "codex":
            return CLIProxyProviderFilter.codex.rawValue
        case "qwen":
            return CLIProxyProviderFilter.qwen.rawValue
        default:
            return normalized ?? "other"
        }
    }

    private func normalizedAuthProvider(_ provider: String?) -> String? {
        let normalized = provider?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "codex":
            return CLIProxyProviderFilter.codex.rawValue
        case "qwen":
            return CLIProxyProviderFilter.qwen.rawValue
        default:
            return nil
        }
    }

    private func cacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Self.cacheFileName)
    }

    private func saveCache(_ data: CLIProxyUsageData, for baseURL: String) {
        guard let url = cacheURL() else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = CLIProxyUsageCachePayload(
                baseURL: baseURL,
                usageData: data,
                cachedAt: Date()
            )
            let encoded = try JSONEncoder().encode(payload)
            try encoded.write(to: url, options: .atomic)
            logger.debug("saveCache() saved to \(url.path, privacy: .public)")
        } catch {
            logger.error("saveCache() failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadCacheIfAvailable(for baseURL: String) {
        guard !baseURL.isEmpty,
              let url = cacheURL(),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CLIProxyUsageCachePayload.self, from: data),
              payload.baseURL == baseURL else {
            logger.debug("loadCacheIfAvailable() no matching cache")
            return
        }

        usageData = payload.usageData
        logger.debug(
            "loadCacheIfAvailable() loaded cache age=\(Int(Date().timeIntervalSince(payload.cachedAt)))s"
        )
    }

    private func friendlyMessage(for error: Error) -> String {
        switch error {
        case CLIProxyError.httpStatus(401):
            return NSLocalizedString("Management key is invalid", comment: "")
        case CLIProxyError.httpStatus(403):
            return NSLocalizedString("Remote management is disabled", comment: "")
        case CLIProxyError.httpStatus(404):
            return NSLocalizedString("Management API is unavailable", comment: "")
        case CLIProxyError.httpStatus(let code):
            return String(
                format: NSLocalizedString("HTTP %d", comment: ""),
                locale: .autoupdatingCurrent,
                code
            )
        case CLIProxyError.decoding:
            return NSLocalizedString("Failed to parse management response", comment: "")
        case CLIProxyError.invalidResponse:
            return NSLocalizedString("Invalid response", comment: "")
        default:
            return error.localizedDescription
        }
    }

    nonisolated private static func parseISODate(_ rawValue: String) -> Date? {
        if let date = fractionalTimestampFormatter.date(from: rawValue) {
            return date
        }
        return plainTimestampFormatter.date(from: rawValue)
    }
}

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encodeImpl = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}

private enum CLIProxyError: Error {
    case httpStatus(Int)
    case invalidResponse
    case decoding
}
