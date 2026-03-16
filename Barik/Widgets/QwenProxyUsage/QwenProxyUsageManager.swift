import Foundation
import SwiftUI

struct QwenProxyAccount: Identifiable {
    let id: String
    let status: String
    let expiresIn: String
    let requestCount: Int
    let webSearchCount: Int
    let authErrorCount: Int
}

struct QwenProxySummary {
    var total: Int = 0
    var healthy: Int = 0
    var failed: Int = 0
    var expiringSoon: Int = 0
    var expired: Int = 0
    var totalRequestsToday: Int = 0
    var lastReset: String = ""
}

struct QwenProxyTokenUsage {
    var inputTokensToday: Int = 0
    var outputTokensToday: Int = 0
    var totalTokensToday: Int = 0
}

struct QwenProxyServerInfo {
    var uptimeSeconds: Double = 0
    var memoryRss: Int = 0
    var memoryHeapUsed: Int = 0
    var memoryHeapTotal: Int = 0
    var nodeVersion: String = ""
    var platform: String = ""
}

struct QwenProxyUsageData {
    var summary = QwenProxySummary()
    var tokenUsage = QwenProxyTokenUsage()
    var serverInfo = QwenProxyServerInfo()
    var accounts: [QwenProxyAccount] = []
    var lastUpdated: Date = Date()
    var isAvailable: Bool = false
}

private struct QwenHealthResponse: Decodable {
    let status: String
    let summary: Summary
    let tokenUsage: TokenUsage
    let accounts: [Account]
    let serverInfo: ServerInfo

    enum CodingKeys: String, CodingKey {
        case status
        case summary
        case tokenUsage = "token_usage"
        case accounts
        case serverInfo = "server_info"
    }

    struct Summary: Decodable {
        let total: Int
        let healthy: Int
        let failed: Int
        let expiringSoon: Int
        let expired: Int
        let totalRequestsToday: Int
        let lastReset: String

        enum CodingKeys: String, CodingKey {
            case total, healthy, failed, expired
            case expiringSoon = "expiring_soon"
            case totalRequestsToday = "total_requests_today"
            case lastReset = "lastReset"
        }
    }

    struct TokenUsage: Decodable {
        let inputTokensToday: Int
        let outputTokensToday: Int
        let totalTokensToday: Int

        enum CodingKeys: String, CodingKey {
            case inputTokensToday = "input_tokens_today"
            case outputTokensToday = "output_tokens_today"
            case totalTokensToday = "total_tokens_today"
        }
    }

    struct Account: Decodable {
        let id: String
        let status: String
        let expiresIn: String
        let requestCount: Int
        let webSearchCount: Int
        let authErrorCount: Int

        enum CodingKeys: String, CodingKey {
            case id, status
            case expiresIn = "expiresIn"
            case requestCount, webSearchCount, authErrorCount
        }
    }

    struct Memory: Decodable {
        let rss: Int
        let heapTotal: Int
        let heapUsed: Int
    }

    struct ServerInfo: Decodable {
        let uptime: Double
        let memory: Memory
        let nodeVersion: String
        let platform: String

        enum CodingKeys: String, CodingKey {
            case uptime, memory, platform
            case nodeVersion = "node_version"
        }
    }
}

@MainActor
final class QwenProxyUsageManager: ObservableObject {
    static let shared = QwenProxyUsageManager()

    @Published private(set) var usageData = QwenProxyUsageData()
    @Published private(set) var fetchFailed = false
    @Published private(set) var errorMessage: String?

    private var refreshTimer: Timer?
    private var currentConfig: ConfigData = [:]

    private static let refreshInterval: TimeInterval = 3600 // 1 hour

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
        let configChanged = currentConfig["base_url"]?.stringValue != config["base_url"]?.stringValue
            || currentConfig["token"]?.stringValue != config["token"]?.stringValue

        currentConfig = config

        if configChanged || !usageData.isAvailable {
            fetchData()
        }

        scheduleTimer()
    }

    func refresh() {
        fetchFailed = false
        errorMessage = nil
        fetchData()
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
        let baseURL = currentConfig["base-url"]?.stringValue ?? ""
        let token = currentConfig["token"]?.stringValue ?? ""

        guard !baseURL.isEmpty else {
            fetchFailed = true
            errorMessage = "base-url not configured"
            return
        }

        Task {
            let healthURL = baseURL.hasSuffix("/") ? "\(baseURL)health" : "\(baseURL)/health"

            guard let url = URL(string: healthURL) else {
                fetchFailed = true
                errorMessage = "Invalid URL: \(healthURL)"
                return
            }

            var request = URLRequest(url: url)
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = 10

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    fetchFailed = true
                    errorMessage = "Invalid response"
                    return
                }

                guard http.statusCode == 200 else {
                    fetchFailed = true
                    errorMessage = "HTTP \(http.statusCode)"
                    return
                }

                guard let decoded = try? JSONDecoder().decode(QwenHealthResponse.self, from: data) else {
                    fetchFailed = true
                    errorMessage = "Failed to parse response"
                    return
                }

                var newData = QwenProxyUsageData()
                newData.summary = QwenProxySummary(
                    total: decoded.summary.total,
                    healthy: decoded.summary.healthy,
                    failed: decoded.summary.failed,
                    expiringSoon: decoded.summary.expiringSoon,
                    expired: decoded.summary.expired,
                    totalRequestsToday: decoded.summary.totalRequestsToday,
                    lastReset: decoded.summary.lastReset
                )
                newData.tokenUsage = QwenProxyTokenUsage(
                    inputTokensToday: decoded.tokenUsage.inputTokensToday,
                    outputTokensToday: decoded.tokenUsage.outputTokensToday,
                    totalTokensToday: decoded.tokenUsage.totalTokensToday
                )
                newData.serverInfo = QwenProxyServerInfo(
                    uptimeSeconds: decoded.serverInfo.uptime,
                    memoryRss: decoded.serverInfo.memory.rss,
                    memoryHeapUsed: decoded.serverInfo.memory.heapUsed,
                    memoryHeapTotal: decoded.serverInfo.memory.heapTotal,
                    nodeVersion: decoded.serverInfo.nodeVersion,
                    platform: decoded.serverInfo.platform
                )
                newData.accounts = decoded.accounts.map { acc in
                    QwenProxyAccount(
                        id: acc.id,
                        status: acc.status,
                        expiresIn: acc.expiresIn,
                        requestCount: acc.requestCount,
                        webSearchCount: acc.webSearchCount,
                        authErrorCount: acc.authErrorCount
                    )
                }
                newData.lastUpdated = Date()
                newData.isAvailable = true

                fetchFailed = false
                errorMessage = nil
                usageData = newData

            } catch {
                fetchFailed = true
                errorMessage = error.localizedDescription
            }
        }
    }
}
