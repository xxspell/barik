import AppKit
import Combine
import Foundation
import OSLog
import Security
import SwiftUI
import UserNotifications

struct GotifyUser: Decodable, Equatable {
    let id: Int
    let name: String
    let admin: Bool?
}

struct GotifyApplication: Decodable, Equatable, Identifiable {
    let id: Int
    let token: String?
    let name: String
    let description: String?
    let internalApp: Bool?
    let image: String?
    let defaultPriority: Int?
    let lastUsed: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case token
        case name
        case description
        case internalApp = "internal"
        case image
        case defaultPriority
        case lastUsed
    }
}

struct GotifyMessage: Decodable, Equatable, Identifiable {
    let id: Int
    let appid: Int
    let message: String
    let title: String
    let priority: Int
    let date: Date
}

private struct GotifyPagedMessagesResponse: Decodable {
    let messages: [GotifyMessage]
}

private struct GotifyClientSession: Codable {
    let baseURL: String
    let clientID: Int
    let token: String
    let name: String
}

private struct GotifyClientResponse: Decodable {
    let id: Int
    let token: String
    let name: String
}

private enum GotifyWebSocketStrategy: String {
    case originHeader
    case plainURL
}

enum GotifyLiveState: Equatable {
    case disabled
    case idle
    case connecting
    case connected
    case reconnecting
    case failed(String)
}

@MainActor
final class GotifyManager: NSObject, ObservableObject {
    static let shared = GotifyManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var isConfigured = false
    @Published private(set) var isLoading = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isConnected = false
    @Published private(set) var showInCalendarPopup = true
    @Published private(set) var notificationsAuthorized = false
    @Published private(set) var liveState: GotifyLiveState = .idle
    @Published private(set) var currentUser: GotifyUser?
    @Published private(set) var messages: [GotifyMessage] = []
    @Published private(set) var errorMessage: String?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "GotifyManager"
    )
    private let credentialsKey = "barik-gotify-credentials"
    private let clientSessionKey = "barik-gotify-client-session"
    private let refreshInterval: TimeInterval = 120

    private var baseURL: URL?
    private var historyLimit = 20
    private var applicationsByID: [Int: GotifyApplication] = [:]
    private var websocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var lastSeenMessageID = 0
    private var hasStarted = false
    private var currentSessionToken: String?
    private var webSocketStrategy: GotifyWebSocketStrategy = .originHeader

    private override init() {
        super.init()
    }

    var showsTab: Bool {
        showInCalendarPopup && (isEnabled || isAuthenticated || isConfigured)
    }

    var webURLString: String? {
        baseURL?.absoluteString
    }

    var liveStatusText: String {
        switch liveState {
        case .disabled:
            return "Live stream disabled"
        case .idle:
            return "Live stream idle"
        case .connecting:
            return "Live stream connecting"
        case .connected:
            return "Live stream connected"
        case .reconnecting:
            return "Live stream reconnecting"
        case .failed(let reason):
            return "Live stream failed: \(reason)"
        }
    }

    var notificationStatusText: String {
        notificationsAuthorized ? "Notifications allowed" : "Notifications not allowed"
    }

    var liveStatusColor: Color {
        switch liveState {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .failed:
            return .red
        case .idle, .disabled:
            return .gray
        }
    }

    func startUpdating(config: ConfigData) {
        updateConfiguration(config: config)
        guard !hasStarted else { return }
        hasStarted = true
        applyConfiguration()
    }

    func updateConfiguration(config: ConfigData) {
        let oldBaseURL = baseURL?.absoluteString
        let newBaseURL = normalizedBaseURL(from: config["base-url"]?.stringValue)
        let newEnabled = config["enabled"]?.boolValue ?? false
        let newHistoryLimit = max(config["history-limit"]?.intValue ?? 20, 5)
        let newShowInCalendarPopup = config["show-in-calendar-popup"]?.boolValue ?? true

        baseURL = newBaseURL
        isConfigured = newBaseURL != nil
        historyLimit = newHistoryLimit
        showInCalendarPopup = newShowInCalendarPopup

        let baseURLChanged = oldBaseURL != newBaseURL?.absoluteString
        let enabledChanged = isEnabled != newEnabled
        isEnabled = newEnabled

        if !newEnabled {
            liveState = .disabled
        } else if case .disabled = liveState {
            liveState = .idle
        }

        if hasStarted, (baseURLChanged || enabledChanged) {
            applyConfiguration()
        } else if hasStarted {
            trimMessagesToLimit()
        }
    }

    func signIn(username: String, password: String) async {
        guard let baseURL else {
            errorMessage = "Set the Gotify base URL first."
            return
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        cancelBackgroundWork()

        let credentials = ["username": trimmedUsername, "password": trimmedPassword]
        if let data = try? JSONSerialization.data(withJSONObject: credentials),
           let encoded = String(data: data, encoding: .utf8) {
            saveKey(encoded, key: credentialsKey)
        }
        deleteKey(clientSessionKey)

        do {
            let session = try await createClientSession(
                baseURL: baseURL,
                username: trimmedUsername,
                password: trimmedPassword
            )
            saveClientSession(session)
            currentSessionToken = session.token
            try await refreshAll(using: session.token, updateWatermark: true)
            isAuthenticated = true
            errorMessage = nil
            startRefreshTimer()
            requestNotificationAuthorizationIfNeeded()
            connectWebSocket(using: session.token)
        } catch {
            guard !isCancellation(error) else {
                isLoading = false
                return
            }
            logger.error("signIn() failed: \(error.localizedDescription, privacy: .public)")
            isAuthenticated = false
            isConnected = false
            currentSessionToken = nil
            errorMessage = userFacingError(error)
        }

        isLoading = false
    }

    func signOut() {
        logger.info("signOut()")
        disconnect()
        deleteKey(credentialsKey)
        deleteKey(clientSessionKey)
        currentUser = nil
        applicationsByID = [:]
        messages = []
        errorMessage = nil
        lastSeenMessageID = 0
        isAuthenticated = false
    }

    func refreshNow() async {
        guard isEnabled, let token = currentSessionToken else { return }
        do {
            try await refreshAll(using: token, updateWatermark: false)
        } catch {
            guard !isCancellation(error) else { return }
            logger.error("refreshNow() failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = userFacingError(error)
        }
    }

    func openWebUI() {
        guard let baseURL else { return }
        NSWorkspace.shared.open(baseURL)
    }

    func appName(for appID: Int) -> String {
        applicationsByID[appID]?.name ?? "Gotify"
    }

    func ensureLiveConnection() {
        guard isEnabled, isAuthenticated, let token = currentSessionToken else { return }
        if websocketTask != nil || reconnectTask != nil || restoreTask != nil {
            return
        }
        logger.info("ensureLiveConnection() restoring idle websocket")
        connectWebSocket(using: token)
    }

    private func applyConfiguration() {
        reconnectTask?.cancel()
        restoreTask?.cancel()

        guard isEnabled, let _ = baseURL else {
            disconnect()
            errorMessage = nil
            liveState = .disabled
            return
        }

        liveState = .connecting
        restoreTask = Task { [weak self] in
            await self?.restoreSessionIfPossible()
        }
    }

    private func restoreSessionIfPossible() async {
        guard isEnabled, let baseURL else { return }
        disconnectTransientState()
        isLoading = true
        defer { isLoading = false }

        if let session = loadClientSession(),
           session.baseURL == baseURL.absoluteString {
            currentSessionToken = session.token
            do {
                try await refreshAll(using: session.token, updateWatermark: true)
                guard !Task.isCancelled else { return }
                isAuthenticated = true
                errorMessage = nil
                startRefreshTimer()
                requestNotificationAuthorizationIfNeeded()
                connectWebSocket(using: session.token)
                return
            } catch {
                guard !isCancellation(error) else { return }
                logger.warning("restoreSessionIfPossible() token refresh failed, recreating client")
                deleteKey(clientSessionKey)
                currentSessionToken = nil
            }
        }

        guard let credentials = loadCredentials() else {
            isAuthenticated = false
            errorMessage = "Open the Gotify tab and sign in."
            return
        }

        do {
            let session = try await createClientSession(
                baseURL: baseURL,
                username: credentials.username,
                password: credentials.password
            )
            saveClientSession(session)
            currentSessionToken = session.token
            try await refreshAll(using: session.token, updateWatermark: true)
            guard !Task.isCancelled else { return }
            isAuthenticated = true
            errorMessage = nil
            startRefreshTimer()
            requestNotificationAuthorizationIfNeeded()
            connectWebSocket(using: session.token)
        } catch {
            guard !isCancellation(error) else { return }
            logger.error("restoreSessionIfPossible() failed: \(error.localizedDescription, privacy: .public)")
            isAuthenticated = false
            currentSessionToken = nil
            errorMessage = userFacingError(error)
        }
    }

    private func createClientSession(
        baseURL: URL,
        username: String,
        password: String
    ) async throws -> GotifyClientSession {
        let url = baseURL.appendingPathComponent("client")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgentValue, forHTTPHeaderField: "User-Agent")
        request.setValue(basicAuthorizationValue(username: username, password: password), forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(["name": clientName])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        let client = try JSONDecoder().decode(GotifyClientResponse.self, from: data)
        logger.info("createClientSession() created client id=\(client.id)")
        return GotifyClientSession(
            baseURL: baseURL.absoluteString,
            clientID: client.id,
            token: client.token,
            name: client.name
        )
    }

    private func refreshAll(using token: String, updateWatermark: Bool) async throws {
        guard let baseURL else { return }

        async let user = fetchCurrentUser(baseURL: baseURL, token: token)
        async let applications = fetchApplications(baseURL: baseURL, token: token)
        async let messages = fetchMessages(baseURL: baseURL, token: token)

        let fetchedUser = try await user
        let fetchedApplications = try await applications
        let fetchedMessages = try await messages

        currentUser = fetchedUser
        applicationsByID = Dictionary(uniqueKeysWithValues: fetchedApplications.map { ($0.id, $0) })

        let sortedMessages = fetchedMessages.sorted { lhs, rhs in
            if lhs.id != rhs.id { return lhs.id > rhs.id }
            return lhs.date > rhs.date
        }
        let previousWatermark = lastSeenMessageID
        self.messages = Array(sortedMessages.prefix(historyLimit))
        if updateWatermark {
            if let latestID = sortedMessages.first?.id {
                lastSeenMessageID = max(lastSeenMessageID, latestID)
            }
        } else {
            let freshMessages = sortedMessages
                .filter { $0.id > previousWatermark }
                .sorted { lhs, rhs in lhs.id < rhs.id }
            for message in freshMessages {
                notifyUser(for: message)
            }
            if let latestID = sortedMessages.first?.id {
                lastSeenMessageID = max(lastSeenMessageID, latestID)
            }
        }
    }

    private func fetchCurrentUser(baseURL: URL, token: String) async throws -> GotifyUser {
        let url = baseURL.appendingPathComponent("current/user")
        var request = authorizedRequest(url: url, token: token)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)
        return try JSONDecoder().decode(GotifyUser.self, from: data)
    }

    private func fetchApplications(baseURL: URL, token: String) async throws -> [GotifyApplication] {
        let url = baseURL.appendingPathComponent("application")
        var request = authorizedRequest(url: url, token: token)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)
        return try JSONDecoder().decode([GotifyApplication].self, from: data)
    }

    private func fetchMessages(baseURL: URL, token: String) async throws -> [GotifyMessage] {
        var components = URLComponents(url: baseURL.appendingPathComponent("message"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "since", value: "0"),
            URLQueryItem(name: "limit", value: String(historyLimit))
        ]
        guard let url = components?.url else { throw GotifyError.invalidURL }
        var request = authorizedRequest(url: url, token: token)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)
        return try gotifyDecoder.decode(GotifyPagedMessagesResponse.self, from: data).messages
    }

    private func connectWebSocket(using token: String) {
        guard let websocketURL = websocketURL(for: token) else { return }

        websocketTask?.cancel(with: .goingAway, reason: nil)
        receiveTask?.cancel()

        let task: URLSessionWebSocketTask
        switch webSocketStrategy {
        case .originHeader:
            var request = URLRequest(url: websocketURL)
            request.setValue(userAgentValue, forHTTPHeaderField: "User-Agent")
            if let origin = websocketOriginValue {
                request.setValue(origin, forHTTPHeaderField: "Origin")
            }
            logger.info(
                "connectWebSocket() opening url=\(websocketURL.absoluteString, privacy: .public) strategy=\(self.webSocketStrategy.rawValue, privacy: .public) origin=\(request.value(forHTTPHeaderField: "Origin") ?? "<nil>", privacy: .public)"
            )
            task = URLSession.shared.webSocketTask(with: request)
        case .plainURL:
            logger.info(
                "connectWebSocket() opening url=\(websocketURL.absoluteString, privacy: .public) strategy=\(self.webSocketStrategy.rawValue, privacy: .public)"
            )
            task = URLSession.shared.webSocketTask(with: websocketURL)
        }
        websocketTask = task
        liveState = .connecting
        task.resume()

        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveWebSocketMessages()
        }

        Task { [weak self, weak task] in
            guard let self, let task else { return }
            await self.confirmWebSocketConnection(task)
        }
    }

    private func receiveWebSocketMessages() async {
        guard let websocketTask else { return }
        logger.info("receiveWebSocketMessages() started")

        while !Task.isCancelled {
            do {
                let message = try await websocketTask.receive()
                if !isConnected {
                    isConnected = true
                    liveState = .connected
                }
                switch message {
                case .string(let text):
                    handleIncomingWebSocketText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleIncomingWebSocketText(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled else { return }
                if isSocketCancellation(error) {
                    logger.info("receiveWebSocketMessages() cancelled")
                    return
                }
                logger.warning("receiveWebSocketMessages() failed: \(error.localizedDescription, privacy: .public)")
                if retryWebSocketHandshakeIfNeeded(after: error) {
                    return
                }
                isConnected = false
                liveState = .failed(shortErrorMessage(error))
                scheduleReconnect()
                return
            }
        }
    }

    private func handleIncomingWebSocketText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let message = try gotifyDecoder.decode(GotifyMessage.self, from: data)
            let wasNew = insertOrUpdate(message)
            if wasNew {
                notifyUser(for: message)
            }
        } catch {
            logger.debug("handleIncomingWebSocketText() ignored payload")
        }
    }

    @discardableResult
    private func insertOrUpdate(_ message: GotifyMessage) -> Bool {
        if messages.contains(where: { $0.id == message.id }) {
            messages = messages.map { $0.id == message.id ? message : $0 }
            messages.sort { lhs, rhs in lhs.id > rhs.id }
            trimMessagesToLimit()
            return false
        }

        messages.insert(message, at: 0)
        messages.sort { lhs, rhs in lhs.id > rhs.id }
        trimMessagesToLimit()

        let isNew = message.id > lastSeenMessageID
        lastSeenMessageID = max(lastSeenMessageID, message.id)
        return isNew
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        guard isEnabled else { return }

        liveState = .reconnecting
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await self?.restoreSessionIfPossible()
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshNow() }
        }
    }

    private func disconnect() {
        restoreTask?.cancel()
        restoreTask = nil
        disconnectTransientState()
        messages = []
        currentUser = nil
        applicationsByID = [:]
        currentSessionToken = nil
        isAuthenticated = false
    }

    private func disconnectTransientState() {
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        websocketTask?.cancel(with: .goingAway, reason: nil)
        websocketTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        isConnected = false
        webSocketStrategy = .originHeader
        if isEnabled {
            liveState = .idle
        }
    }

    private func cancelBackgroundWork() {
        reconnectTask?.cancel()
        reconnectTask = nil
        restoreTask?.cancel()
        restoreTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        websocketTask?.cancel(with: .goingAway, reason: nil)
        websocketTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        isConnected = false
        webSocketStrategy = .originHeader
        if isEnabled {
            liveState = .idle
        }
    }

    private func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.notificationsAuthorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            }
        }
        center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            if let error {
                self?.logger.warning("requestNotificationAuthorizationIfNeeded() failed: \(error.localizedDescription, privacy: .public)")
            } else {
                self?.logger.info("Gotify notifications authorization granted=\(granted)")
            }
            Task { @MainActor in
                self?.notificationsAuthorized = granted
            }
        }
    }

    private func notifyUser(for message: GotifyMessage) {
        let content = UNMutableNotificationContent()
        let appName = appName(for: message.appid)
        let trimmedBody = message.message.trimmingCharacters(in: .whitespacesAndNewlines)
        content.title = message.title.isEmpty ? appName : message.title
        if !message.title.isEmpty {
            content.subtitle = appName
        }
        content.body = trimmedBody.isEmpty ? "New notification" : trimmedBody
        content.sound = .default
        content.threadIdentifier = "gotify"
        content.userInfo = [
            "source": "gotify",
            "message_id": message.id,
            "app_id": message.appid
        ]

        let request = UNNotificationRequest(
            identifier: "gotify.\(message.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.warning("notifyUser() failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func authorizedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Gotify-Key")
        request.setValue(userAgentValue, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GotifyError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw GotifyError.unauthorized
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GotifyError.api(statusCode: http.statusCode, body: body)
        }
    }

    private func loadCredentials() -> (username: String, password: String)? {
        guard let raw = loadKey(credentialsKey),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let username = object["username"],
              let password = object["password"]
        else {
            return nil
        }
        return (username, password)
    }

    private func saveClientSession(_ session: GotifyClientSession) {
        guard let data = try? JSONEncoder().encode(session),
              let encoded = String(data: data, encoding: .utf8) else { return }
        saveKey(encoded, key: clientSessionKey)
    }

    private func loadClientSession() -> GotifyClientSession? {
        guard let raw = loadKey(clientSessionKey),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GotifyClientSession.self, from: data)
    }

    private func websocketURL(for token: String) -> URL? {
        guard let baseURL else { return nil }
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("stream"),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        let currentScheme = components.scheme
        components.scheme = currentScheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private func normalizedBaseURL(from raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        var normalized = url
        if !normalized.absoluteString.hasSuffix("/") {
            normalized.appendPathComponent("")
        }
        return normalized
    }

    private var clientName: String {
        "Barik \(appVersionString)"
    }

    private var userAgentValue: String {
        "Barik/\(appVersionString)"
    }

    private var websocketOriginValue: String? {
        guard let baseURL else { return nil }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private var appVersionString: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let build, !build.isEmpty {
            return "\(shortVersion) (\(build))"
        }
        return shortVersion
    }

    private func basicAuthorizationValue(username: String, password: String) -> String {
        let raw = "\(username):\(password)"
        let token = Data(raw.utf8).base64EncodedString()
        return "Basic \(token)"
    }

    private func trimMessagesToLimit() {
        if messages.count > historyLimit {
            messages = Array(messages.prefix(historyLimit))
        }
    }

    private func userFacingError(_ error: Error) -> String {
        switch error {
        case is CancellationError:
            return ""
        case GotifyError.unauthorized:
            return "Gotify rejected the credentials or client token."
        case GotifyError.invalidURL:
            return "The Gotify base URL is invalid."
        case GotifyError.invalidResponse:
            return "Gotify returned an invalid response."
        case GotifyError.api(let statusCode, _):
            return "Gotify request failed with HTTP \(statusCode)."
        default:
            return error.localizedDescription
        }
    }

    private func shortErrorMessage(_ error: Error) -> String {
        let text = userFacingError(error).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
        return error.localizedDescription
    }

    private func confirmWebSocketConnection(_ task: URLSessionWebSocketTask) async {
        do {
            try await sendPing(task)
            guard websocketTask === task else { return }
            logger.info("confirmWebSocketConnection() ping succeeded")
            isConnected = true
            liveState = .connected
        } catch {
            guard websocketTask === task else { return }
            guard !isSocketCancellation(error) else { return }
            logger.warning("confirmWebSocketConnection() failed: \(error.localizedDescription, privacy: .public)")
            if isConnected {
                logger.info("confirmWebSocketConnection() keeping established stream alive despite ping failure")
                return
            }
            if retryWebSocketHandshakeIfNeeded(after: error) {
                return
            }
            isConnected = false
            liveState = .failed(shortErrorMessage(error))
            scheduleReconnect()
        }
    }

    private func retryWebSocketHandshakeIfNeeded(after error: Error) -> Bool {
        guard !isConnected, isBadServerResponse(error), let token = currentSessionToken else {
            return false
        }
        switch webSocketStrategy {
        case .originHeader:
            logger.warning("retryWebSocketHandshakeIfNeeded() retrying with plain URL websocket task")
            webSocketStrategy = .plainURL
            connectWebSocket(using: token)
            return true
        case .plainURL:
            return false
        }
    }

    private func sendPing(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func isSocketCancellation(_ error: Error) -> Bool {
        if isCancellation(error) {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }

    private func isBadServerResponse(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .badServerResponse {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorBadServerResponse
    }

    private var gotifyDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: value)
                ?? ISO8601DateFormatter.standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(value)"
            )
        }
        return decoder
    }

    private func saveKey(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadKey(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKey(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum GotifyError: Error {
    case invalidURL
    case invalidResponse
    case unauthorized
    case api(statusCode: Int, body: String)
}

private extension ISO8601DateFormatter {
    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
