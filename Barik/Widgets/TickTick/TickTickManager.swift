import Foundation
import Security
import AppKit
import OSLog
import Network

// MARK: - Auth Mode

enum TickTickAuthMode {
    case openAPI    // OAuth2 — /open/v1/* — tasks only
    case privateAPI // Login/password — /api/v2+v3/* — full access
}

// MARK: - Models

struct TickTickTask: Identifiable, Equatable {
    let id: String
    let projectId: String
    let parentId: String?
    var title: String
    var content: String?
    var priority: TickTickPriority
    var dueDate: Date?
    var status: Int
    var items: [TickTickChecklistItem]
    var subtasks: [TickTickTask]

    var isSubtask: Bool { parentId != nil }
    var isCompleted: Bool { status == 2 }

    static func == (lhs: TickTickTask, rhs: TickTickTask) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.title == rhs.title
    }
}

struct TickTickChecklistItem: Identifiable, Equatable {
    let id: String
    var title: String
    var status: Int
    var isCompleted: Bool { status == 1 }
}

struct TickTickProject: Identifiable, Equatable {
    let id: String
    var name: String
    var color: String?
}

enum TickTickPriority: Int {
    case none = 0, low = 1, medium = 3, high = 5
    var label: String {
        switch self {
        case .none: return "—"; case .low: return "Low"
        case .medium: return "Medium"; case .high: return "High"
        }
    }
    var color: String {
        switch self {
        case .none: return "#888888"; case .low: return "#4FC3F7"
        case .medium: return "#FFB74D"; case .high: return "#EF5350"
        }
    }
}

struct TickTickHabit: Identifiable {
    let id: String
    var name: String
    var color: String?
    var streak: Int
    var repeatRule: String
    var totalCheckIns: Int
    var completedDates: Set<String>
    var checkedInToday: Bool
}

struct TickTickHabitCheckin: Identifiable, Codable {
    let id: String
    let habitId: String
    let stamp: Int
    let status: Int
    let checkinTime: String?
    let opTime: String?
    let value: Double?
    let goal: Double?
    var localArchived: Bool
}

// MARK: - Private API raw models

private struct BatchCheckResponse: Decodable {
    let syncTaskBean: SyncTaskBean?
    let projectProfiles: [RawProject]?
    let inboxId: String?
    let checkPoint: Int64?

    struct SyncTaskBean: Decodable {
        let update: [RawTask]?
        let add: [RawTask]?
    }
}

private struct RawTask: Decodable {
    let id: String
    let projectId: String?
    let parentId: String?
    let childIds: [String]?
    let title: String
    let content: String?
    let priority: Int?
    let dueDate: String?
    let startDate: String?
    let status: Int?
    let items: [RawChecklistItem]?
    let kind: String?
    let tags: [String]?
}

private struct RawChecklistItem: Decodable {
    let id: String; let title: String; let status: Int?
}

private struct RawProject: Decodable {
    let id: String; let name: String; let color: String?
    let closed: Bool?; let kind: String?
}

// OpenAPI models
private struct OpenAPIProjectData: Decodable {
    let project: RawProject; let tasks: [RawTask]?
}

private struct OpenAPIToken: Codable {
    let accessToken: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
}

private struct PrivateSignonResponse: Decodable {
    let token: String?; let userId: String?
    let username: String?; let inboxId: String?
}

struct APIHabit: Decodable {
    let id: String
    let name: String
    let iconRes: String?
    let color: String?
    let sortOrder: Int64?
    let status: Int?
    let encouragement: String?
    let totalCheckIns: Int?
    let createdTime: String?
    let modifiedTime: String?
    let archivedTime: String?
    let type: String?
    let goal: Double?
    let step: Double?
    let unit: String?
    let etag: String?
    let repeatRule: String?
    let reminders: [String]?
    let recordEnable: Bool?
    let sectionId: String?
    let targetDays: Int?
    let targetStartDate: Int?
    let completedCycles: Int?
    let exDates: [String]?
    let style: Int?
    let currentStreak: Int?
}

struct APIHabitCheckins: Decodable {
    let checkins: [String: [Record]]
    struct Record: Decodable {
        let id: String?
        let stampDate: Int?
        let checkinStamp: Int?
        let checkinTime: String?
        let opTime: String?
        let value: Double?
        let goal: Double?
        let status: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case stampDate
            case checkinStamp
            case checkinTime
            case opTime
            case value
            case goal
            case status
        }
    }
}

// MARK: - Localhost OAuth Server

final class TickTickOAuthServer {
    private let port: UInt16
    private var listener: NWListener?
    private let onCode: (String) -> Void
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "barik", category: "TickTickOAuthServer")

    init(port: UInt16 = 7777, onCode: @escaping (String) -> Void) {
        self.port = port; self.onCode = onCode
    }

    func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        listener = try? NWListener(using: .tcp, on: nwPort)
        listener?.newConnectionHandler = { [weak self] in self?.handle($0) }
        listener?.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.logger.info("OAuth server ready on :\(self?.port ?? 0)") }
            if case .failed(let e) = state { self?.logger.error("OAuth server failed: \(e)") }
        }
        listener?.start(queue: .global(qos: .utility))
    }

    func stop() { listener?.cancel(); listener = nil }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8) else {
                connection.cancel(); return
            }
            var code: String? = nil
            if let line = text.components(separatedBy: "\r\n").first {
                let parts = line.components(separatedBy: " ")
                if parts.count >= 2, let url = URL(string: "http://localhost" + parts[1]) {
                    code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value
                }
            }
            let body = code != nil
                ? "<!DOCTYPE html><html><head><meta charset='utf-8'><style>body{font-family:-apple-system,sans-serif;background:#0d0d10;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}.c{text-align:center}</style></head><body><div class='c'><div style='font-size:52px'>✅</div><h2>Signed in to TickTick</h2><p style='opacity:.4'>You can close this tab.</p></div></body></html>"
                : "<html><body>Error: no authorization code received.</body></html>"
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
            if let code { self.stop(); self.onCode(code) }
        }
    }
}

// MARK: - Manager

@MainActor
final class TickTickManager: ObservableObject {
    static let shared = TickTickManager()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var authMode: TickTickAuthMode = .privateAPI
    @Published private(set) var projects: [TickTickProject] = []
    @Published private(set) var tasksByProject: [String: [TickTickTask]] = [:]
    @Published private(set) var habits: [TickTickHabit] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var totalPendingCount: Int = 0

    // Config
    var clientId:     String = "rW76D80NVRiKqPun0a"
    var clientSecret: String = "tx9QG4UMzasK95f7QG3Tofhp7CPYUm5C"
    var redirectURI:  String = "http://localhost:7777/callback"

    // Private
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "barik", category: "TickTickManager")

    private let openAPIKey   = "barik-ticktick-openapi-token"
    private let privTokenKey = "barik-ticktick-priv-token"
    private let privUserIdKey = "barik-ticktick-priv-userid"
    private let credsKey     = "barik-ticktick-credentials"

    private let openAPIBase = "https://api.ticktick.com/open/v1"
    private let privBase    = "https://api.ticktick.com/api/v2"
    private let privBase3   = "https://api.ticktick.com/api/v3"
    private let xDevice     = #"{"device":"MacBook","os":"macOS 15.0","channel":"website","id":"barik0000000000000000000000000000","platform":"macOS","version":"8020","name":"mercury"}"#

    private var refreshTimer: Timer?
    private var oauthServer: TickTickOAuthServer?
    private static let refreshInterval: TimeInterval = 120

    private var hasStarted     = false
    private var isRefreshing   = false
    private var isRefreshingHabits = false
    private var reAuthAttempts = 0
    private let maxReAuth      = 2
    private var privateUserId: String?
    private var habitRawById: [String: APIHabit] = [:]
    private var todayCheckinIdByHabit: [String: String] = [:]
    private var habitCheckinsByHabit: [String: [TickTickHabitCheckin]] = [:]

    // Cache
    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("barik/ticktick-cache.json")
    }

    private init() {
        if let _ = loadKey(privTokenKey) {
            isAuthenticated = true; authMode = .privateAPI
            logger.debug("init — private token found")
            privateUserId = loadKey(privUserIdKey)
        } else if let _ = loadKey(openAPIKey) {
            isAuthenticated = true; authMode = .openAPI
            logger.debug("init — OpenAPI token found")
        }
        if isAuthenticated { loadCache() }
    }

    // MARK: - startUpdating

    func startUpdating(config: ConfigData) {
        if let id  = config["client-id"]?.stringValue     { clientId     = id }
        if let sec = config["client-secret"]?.stringValue { clientSecret = sec }
        if let uri = config["redirect-uri"]?.stringValue  { redirectURI  = uri }

        guard !hasStarted else {
            logger.debug("startUpdating() — duplicate, skipping")
            return
        }
        hasStarted = true
        logger.debug("startUpdating() — started")

        if isAuthenticated {
            Task { await refresh() }
            if authMode == .privateAPI { Task { await refreshHabits() } }
            startTimer()
        }
    }

    func stopUpdating() { stopTimer() }

    // MARK: - Private API Login

    func signInPrivate(username: String, password: String) async {
        logger.info("signInPrivate() — username=\(username)")
        errorMessage = nil

        guard let url = URL(string: "\(privBase)/user/signon?wc=true&remember=true") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(xDevice, forHTTPHeaderField: "X-Device")
        req.setValue("TickTick/M-8020", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["username": username, "password": password])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { return }
            logger.debug("signInPrivate() — HTTP \(http.statusCode)")
            logger.debug("signInPrivate() — response (first 200): \(String((String(data: data, encoding: .utf8) ?? "").prefix(200)))")

            guard http.statusCode == 200 else {
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = obj["errorMessage"] as? String {
                    errorMessage = msg
                } else {
                    errorMessage = "Login failed (\(http.statusCode))"
                }
                return
            }

            let resp = try JSONDecoder().decode(PrivateSignonResponse.self, from: data)
            guard let token = resp.token else { errorMessage = "No token in response"; return }

            saveKey(token, key: privTokenKey)
            if let uid = resp.userId {
                privateUserId = uid
                saveKey(uid, key: privUserIdKey)
            }
            let creds = try? JSONSerialization.data(withJSONObject: ["username": username, "password": password])
            if let c = creds, let s = String(data: c, encoding: .utf8) { saveKey(s, key: credsKey) }

            authMode = .privateAPI
            isAuthenticated = true
            errorMessage = nil
            reAuthAttempts = 0
            logger.info("signInPrivate() — success! userId=\(resp.userId ?? "?")")

            if refreshTimer == nil { startTimer() }
            await refresh()
            await refreshHabits()

        } catch {
            logger.error("signInPrivate() — \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - OpenAPI OAuth

    func startOAuth() {
        logger.info("startOAuth()")
        oauthServer?.stop()
        oauthServer = TickTickOAuthServer(port: 7777) { [weak self] code in
            Task { @MainActor [weak self] in await self?.exchangeCode(code) }
        }
        oauthServer?.start()

        var c = URLComponents(string: "https://ticktick.com/oauth/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id",     value: clientId),
            URLQueryItem(name: "scope",         value: "tasks:read tasks:write"),
            URLQueryItem(name: "state",         value: UUID().uuidString),
            URLQueryItem(name: "redirect_uri",  value: redirectURI),
            URLQueryItem(name: "response_type", value: "code")
        ]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    private func exchangeCode(_ code: String) async {
        guard let url = URL(string: "https://ticktick.com/oauth/token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let d = "\(clientId):\(clientSecret)".data(using: .utf8) {
            req.setValue("Basic \(d.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        var params = URLComponents()
        params.queryItems = [
            URLQueryItem(name: "code",         value: code),
            URLQueryItem(name: "grant_type",   value: "authorization_code"),
            URLQueryItem(name: "scope",        value: "tasks:read tasks:write"),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        req.httpBody = params.query?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "OAuth token exchange failed"; return
            }
            let token = try JSONDecoder().decode(OpenAPIToken.self, from: data)
            saveKey(token.accessToken, key: openAPIKey)
            authMode = .openAPI
            isAuthenticated = true
            errorMessage = nil
            reAuthAttempts = 0
            if refreshTimer == nil { startTimer() }
            await refresh()
        } catch {
            errorMessage = "OAuth error: \(error.localizedDescription)"
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        logger.info("signOut()")
        if authMode == .privateAPI, let token = loadKey(privTokenKey),
           let url = URL(string: "\(privBase)/user/signout") {
            var req = URLRequest(url: url)
            req.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(xDevice, forHTTPHeaderField: "X-Device")
            req.setValue("TickTick/M-8020", forHTTPHeaderField: "User-Agent")
            _ = try? await URLSession.shared.data(for: req)
        }
        deleteKey(openAPIKey); deleteKey(privTokenKey); deleteKey(credsKey)
        deleteKey(privUserIdKey); privateUserId = nil
        isAuthenticated = false; authMode = .openAPI; hasStarted = false
        projects = []; tasksByProject = [:]; habits = []; totalPendingCount = 0
        habitCheckinsByHabit = [:]; habitRawById = [:]; todayCheckinIdByHabit = [:]
        stopTimer(); clearCache()
    }

    // MARK: - Refresh

    func refresh() async {
        guard isAuthenticated else { return }
        guard !isRefreshing else { logger.debug("refresh() — in progress, skip"); return }
        isRefreshing = true
        logger.debug("refresh() — started")
        isLoading = true; errorMessage = nil

        do {
            let (projs, tasks) = authMode == .privateAPI
                ? try await fetchPrivateBatch()
                : try await fetchOpenAPI()

            let hierarchy = buildHierarchy(tasks)
            var byProject: [String: [TickTickTask]] = [:]
            for task in hierarchy { byProject[task.projectId, default: []].append(task) }

            var finalProjects = projs
            let knownIds = Set(projs.map { $0.id })
            for pid in Set(byProject.keys).subtracting(knownIds) {
                finalProjects.insert(TickTickProject(id: pid, name: "Inbox", color: nil), at: 0)
            }

            projects = finalProjects
            tasksByProject = byProject
            recalc()
            saveCache()
            reAuthAttempts = 0
            logger.info("refresh() — done, pending=\(self.totalPendingCount)")

        } catch TickTickError.unauthorized {
            logger.error("refresh() — 401")
            isRefreshing = false; isLoading = false
            await handleUnauth()
            return
        } catch {
            logger.error("refresh() — \(error.localizedDescription)")
            errorMessage = "Failed to load tasks"
        }
        isRefreshing = false; isLoading = false
    }

    private func handleUnauth() async {
        guard reAuthAttempts < maxReAuth else {
            logger.error("handleUnauth() — max retries reached")
            reAuthAttempts = 0; isAuthenticated = false
            deleteKey(privTokenKey); deleteKey(openAPIKey)
            errorMessage = "Session expired. Please sign in again."
            return
        }
        reAuthAttempts += 1
        logger.info("handleUnauth() — attempt \(self.reAuthAttempts)/\(self.maxReAuth)")

        if authMode == .privateAPI,
           let credsStr = loadKey(credsKey),
           let credsData = credsStr.data(using: .utf8),
           let creds = try? JSONSerialization.jsonObject(with: credsData) as? [String: String],
           let u = creds["username"], let p = creds["password"] {
            await signInPrivate(username: u, password: p)
        } else {
            isAuthenticated = false
            deleteKey(privTokenKey); deleteKey(openAPIKey)
            errorMessage = "Session expired. Please sign in again."
        }
    }

    // MARK: - Private API data fetch (batch/check)

    private func fetchPrivateBatch() async throws -> ([TickTickProject], [TickTickTask]) {
        guard let token = loadKey(privTokenKey) else { throw TickTickError.noToken }
        // checkpoint=0 → returns all data
        guard let url = URL(string: "\(privBase3)/batch/check/0") else { throw TickTickError.noToken }

        var req = URLRequest(url: url)
        req.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(xDevice, forHTTPHeaderField: "X-Device")
        req.setValue("TickTick/M-8020", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw TickTickError.apiError(-1) }
        logger.debug("fetchPrivateBatch() — HTTP \(http.statusCode), \(data.count) bytes")
        try checkStatus(http.statusCode)

        let batch = try JSONDecoder().decode(BatchCheckResponse.self, from: data)

        let rawProjects = (batch.projectProfiles ?? [])
            .filter { !($0.closed ?? false) && ($0.kind ?? "TASK") == "TASK" }
        let projects = rawProjects.map { TickTickProject(id: $0.id, name: $0.name, color: $0.color) }
        logger.info("fetchPrivateBatch() — \(projects.count) projects")

        let allRawTasks = (batch.syncTaskBean?.update ?? []) + (batch.syncTaskBean?.add ?? [])
        let pendingRaw = allRawTasks.filter { ($0.status ?? 0) == 0 }
        logger.info("fetchPrivateBatch() — \(allRawTasks.count) total tasks, \(pendingRaw.count) pending")

        let tasks = pendingRaw.compactMap { mapTask($0) }
        return (projects, tasks)
    }

    // MARK: - OpenAPI data fetch

    private func fetchOpenAPI() async throws -> ([TickTickProject], [TickTickTask]) {
        guard let token = loadKey(openAPIKey) else { throw TickTickError.noToken }

        // Fetch projects
        guard let projURL = URL(string: "\(openAPIBase)/project") else { throw TickTickError.noToken }
        var projReq = URLRequest(url: projURL)
        projReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        projReq.timeoutInterval = 10

        let (projData, projResp) = try await URLSession.shared.data(for: projReq)
        guard let http1 = projResp as? HTTPURLResponse else { throw TickTickError.apiError(-1) }
        logger.debug("fetchOpenAPI() projects — HTTP \(http1.statusCode)")
        try checkStatus(http1.statusCode)

        let rawProjects = try JSONDecoder().decode([RawProject].self, from: projData)
        let projects = rawProjects.filter { !($0.closed ?? false) && ($0.kind ?? "TASK") == "TASK" }
            .map { TickTickProject(id: $0.id, name: $0.name, color: $0.color) }

        // Fetch all pending tasks via filter
        guard let filterURL = URL(string: "\(openAPIBase)/task/filter") else { throw TickTickError.noToken }
        var filterReq = URLRequest(url: filterURL)
        filterReq.httpMethod = "POST"
        filterReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        filterReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        filterReq.timeoutInterval = 10
        filterReq.httpBody = try? JSONSerialization.data(withJSONObject: ["status": [0]])

        let (filterData, filterResp) = try await URLSession.shared.data(for: filterReq)
        guard let http2 = filterResp as? HTTPURLResponse else { throw TickTickError.apiError(-1) }
        logger.debug("fetchOpenAPI() tasks — HTTP \(http2.statusCode), \(filterData.count) bytes")
        try checkStatus(http2.statusCode)

        let rawTasks = try JSONDecoder().decode([RawTask].self, from: filterData)
        logger.info("fetchOpenAPI() — \(projects.count) projects, \(rawTasks.count) tasks")
        let tasks = rawTasks.compactMap { mapTask($0) }
        return (projects, tasks)
    }

    // MARK: - Task Actions

    func completeTask(_ task: TickTickTask) async {
        logger.info("completeTask() — '\(task.title)'")
        removeLocally(task)
        guard let req = taskActionRequest(task: task, action: "complete", method: "POST") else { return }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { await refresh() }
        } catch { await refresh() }
    }

    func deleteTask(_ task: TickTickTask) async {
        logger.info("deleteTask() — '\(task.title)'")
        removeLocally(task)
        guard let req = taskActionRequest(task: task, action: "delete", method: authMode == .privateAPI ? "POST" : "DELETE") else { return }
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { await refresh() }
        } catch { await refresh() }
    }

    func createTask(title: String, projectId: String?) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logger.info("createTask() — '\(trimmed)'")
        if authMode == .privateAPI {
            await createTaskPrivate(title: trimmed, projectId: projectId)
        } else {
            await createTaskOpenAPI(title: trimmed, projectId: projectId)
        }
    }

    func updateTask(_ task: TickTickTask, priority: TickTickPriority, dueDate: Date?) async {
        guard authMode == .privateAPI, let token = loadKey(privTokenKey) else { return }
        guard let url = URL(string: "\(privBase)/batch/task") else { return }

        let now = Date()
        let taskId = task.id
        let bodyTask = buildTaskPayload(
            id: taskId,
            projectId: task.projectId,
            title: task.title,
            content: task.content ?? "",
            priority: priority,
            dueDate: dueDate,
            createdTime: now,
            modifiedTime: now
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(xDevice, forHTTPHeaderField: "X-Device")
        req.setValue("TickTick/M-8020", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "update": [bodyTask]
        ])

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { await refresh() }
        } catch { await refresh() }
    }

    func moveTaskInMatrix(taskId: String, urgent: Bool, important: Bool) async {
        guard var task = taskById(taskId) else { return }
        let newPriority: TickTickPriority
        if important {
            newPriority = (task.priority == .none || task.priority == .low) ? .medium : task.priority
        } else {
            newPriority = .low
        }
        let newDueDate: Date?
        if urgent {
            let cal = Calendar.current
            newDueDate = cal.date(bySettingHour: 23, minute: 59, second: 0, of: Date())
        } else {
            newDueDate = nil
        }

        task.priority = newPriority
        task.dueDate = newDueDate
        updateLocalTask(task)
        await updateTask(task, priority: newPriority, dueDate: newDueDate)
    }

    private func taskActionRequest(task: TickTickTask, action: String, method: String) -> URLRequest? {
        let urlStr: String
        if authMode == .privateAPI {
            guard let token = loadKey(privTokenKey) else { return nil }
            urlStr = "\(privBase)/task/\(task.id)/\(action)"
            guard let url = URL(string: urlStr) else { return nil }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(xDevice, forHTTPHeaderField: "X-Device")
            req.setValue("TickTick/M-8020", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 10
            return req
        } else {
            guard let token = loadKey(openAPIKey) else { return nil }
            let endpointAction = action == "delete" ? "" : "/complete"
            urlStr = "\(openAPIBase)/project/\(task.projectId)/task/\(task.id)\(endpointAction)"
            guard let url = URL(string: urlStr) else { return nil }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 10
            return req
        }
    }

    private func createTaskPrivate(title: String, projectId: String?) async {
        guard let token = loadKey(privTokenKey) else { return }
        guard let url = URL(string: "\(privBase)/batch/task") else { return }

        let now = Date()
        let taskId = uuidNoDash()
        let bodyTask = buildTaskPayload(
            id: taskId,
            projectId: projectId ?? "inbox",
            title: title,
            content: "",
            priority: .none,
            dueDate: nil,
            createdTime: now,
            modifiedTime: now
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(xDevice, forHTTPHeaderField: "X-Device")
        req.setValue("TickTick/M-8020", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "add": [bodyTask],
            "update": [bodyTask]
        ])

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { await refresh() }
            await refresh()
        } catch { await refresh() }
    }

    private func createTaskOpenAPI(title: String, projectId: String?) async {
        guard let token = loadKey(openAPIKey),
              let url = URL(string: "\(openAPIBase)/task") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "title": title,
            "projectId": projectId ?? ""
        ])
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { await refresh() }
            await refresh()
        } catch { await refresh() }
    }

    // MARK: - Habits (private API only)

    func refreshHabits() async {
        guard isAuthenticated, authMode == .privateAPI else {
            logger.debug("refreshHabits() — skipped (not private API mode)")
            return
        }
        guard !isRefreshingHabits else { logger.debug("refreshHabits() — in progress"); return }
        isRefreshingHabits = true
        defer { isRefreshingHabits = false }
        logger.debug("refreshHabits() — started")

        guard let token = loadKey(privTokenKey),
              let habitsURL = URL(string: "\(privBase)/habits") else { return }

        var habReq = URLRequest(url: habitsURL)
        habReq.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        habReq.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        habReq.setValue(xDevice, forHTTPHeaderField: "X-Device")
        habReq.setValue("TickTick/M-8020", forHTTPHeaderField: "User-Agent")
        habReq.timeoutInterval = 10

        do {
            let (habData, habResp) = try await URLSession.shared.data(for: habReq)
            guard let http = habResp as? HTTPURLResponse, http.statusCode == 200 else {
                logger.warning("refreshHabits() — habits HTTP \((habResp as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            logger.debug("refreshHabits() — habits bytes=\(habData.count)")
            logger.debug("refreshHabits() — habits raw: \(String(data: habData, encoding: .utf8) ?? "")")
            let apiHabits = try JSONDecoder().decode([APIHabit].self, from: habData)
            let active = apiHabits.filter { ($0.status ?? 0) == 0 }
            logger.info("refreshHabits() — \(active.count) active habits")
            guard !active.isEmpty else { habits = []; return }
            habitRawById = Dictionary(uniqueKeysWithValues: active.map { ($0.id, $0) })

            // Fetch checkins
            guard let cURL = URL(string: "\(privBase)/habitCheckins/query") else { return }
            var cReq = URLRequest(url: cURL)
            cReq.httpMethod = "POST"
            cReq.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
            cReq.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
            cReq.setValue(xDevice, forHTTPHeaderField: "X-Device")
            cReq.setValue("TickTick/M-8020", forHTTPHeaderField: "User-Agent")
            cReq.timeoutInterval = 10
            cReq.httpBody = try? JSONSerialization.data(withJSONObject: [
                "afterStamp": afterStampInt(daysAgo: 30),
                "habitIds": active.map { $0.id }
            ])

            let (cData, cResp) = try await URLSession.shared.data(for: cReq)
            logger.debug("refreshHabits() — checkins HTTP \((cResp as? HTTPURLResponse)?.statusCode ?? -1)")
            logger.debug("refreshHabits() — checkins bytes=\(cData.count)")
            logger.debug("refreshHabits() — checkins raw: \(String(data: cData, encoding: .utf8) ?? "")")

            var checkinsByHabit: [String: Set<String>] = [:]
            var todayIds: [String: String] = [:]
            var serverCheckins: [String: [TickTickHabitCheckin]] = [:]
            if let ci = try? JSONDecoder().decode(APIHabitCheckins.self, from: cData) {
                for (hid, records) in ci.checkins {
                    let mapped: [TickTickHabitCheckin] = records.compactMap { r in
                        guard let id = r.id, let stamp = rStamp(r) else { return nil }
                        return TickTickHabitCheckin(
                            id: id,
                            habitId: hid,
                            stamp: stamp,
                            status: r.status ?? 0,
                            checkinTime: r.checkinTime,
                            opTime: r.opTime,
                            value: r.value,
                            goal: r.goal,
                            localArchived: false
                        )
                    }
                    serverCheckins[hid] = mapped
                }
            }
            let merged = mergeHabitCheckins(server: serverCheckins, cached: habitCheckinsByHabit)
            logger.debug("refreshHabits() — merged checkins: \(merged.values.flatMap { $0 }.count)")
            habitCheckinsByHabit = merged

            for (hid, records) in merged {
                let dates = Set(records.filter { $0.status == 2 && !$0.localArchived }.compactMap { r -> String? in
                    let s = String(r.stamp)
                    guard s.count == 8 else { return nil }
                    return "\(s.prefix(4))-\(s.dropFirst(4).prefix(2))-\(s.suffix(2))"
                })
                checkinsByHabit[hid] = dates
                if let todayRec = records.first(where: { !$0.localArchived && $0.stamp == todayInt() }) {
                    todayIds[hid] = todayRec.id
                }
            }
            todayCheckinIdByHabit = todayIds

            let today = todayStr()
            habits = active.map { h in
                let dates = checkinsByHabit[h.id] ?? []
                let streak = calcStreak(dates)
                logger.debug("  '\(h.name)' streak=\(streak) today=\(dates.contains(today))")
                return TickTickHabit(id: h.id, name: h.name, color: h.color,
                                     streak: streak, repeatRule: fmtRule(h.repeatRule ?? ""),
                                     totalCheckIns: h.totalCheckIns ?? dates.count,
                                     completedDates: dates, checkedInToday: dates.contains(today))
            }
            saveCache()
        } catch {
            logger.error("refreshHabits() — \(error.localizedDescription)")
        }
    }

    func toggleHabitCheckin(_ habit: TickTickHabit) async {
        guard authMode == .privateAPI, let token = loadKey(privTokenKey) else { return }
        let today = todayStr()
        let stamp = Int(today.replacingOccurrences(of: "-", with: "")) ?? 0
        let now = Date()

        let isUndo = habit.checkedInToday
        logger.info("toggleHabitCheckin() — '\(habit.name)' undo=\(isUndo) stamp=\(stamp)")
        var newTotal = habit.totalCheckIns
        var newStreak = habit.streak
        if let i = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[i].checkedInToday = !isUndo
            if isUndo {
                habits[i].completedDates.remove(today)
                habits[i].totalCheckIns = max(0, habits[i].totalCheckIns - 1)
            } else {
                habits[i].completedDates.insert(today)
                habits[i].totalCheckIns += 1
            }
            habits[i].streak = calcStreak(habits[i].completedDates)
            newTotal = habits[i].totalCheckIns
            newStreak = habits[i].streak
        }

        guard let url = URL(string: "\(privBase)/habitCheckins/batch") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(xDevice, forHTTPHeaderField: "X-Device")
        req.setValue("TickTick/M-8020", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10

        if let existingId = todayCheckinIdByHabit[habit.id],
           let existing = habitCheckinsByHabit[habit.id]?.first(where: { $0.id == existingId })
        {
            await updateHabitForCheckin(habit: habit, totalCheckIns: newTotal, currentStreak: newStreak)

            let update = [
                "checkinStamp": stamp,
                "opTime": tickTickDateWithMillisZero(now),
                "goal": Int(existing.goal ?? 1.0),
                "habitId": habit.id,
                "id": existingId,
                "status": isUndo ? 0 : 2,
                "value": isUndo ? 0 : 1
            ] as [String: Any]
            logger.debug("toggleHabitCheckin() — update payload: \(update)")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "add": [],
                "update": [update],
                "delete": []
            ])
        } else {
            await updateHabitForCheckin(habit: habit, totalCheckIns: newTotal, currentStreak: newStreak)
            let checkin = [
                "checkinStamp": stamp,
                "checkinTime": tickTickDateWithMillis(now),
                "opTime": tickTickDateWithMillis(now),
                "goal": 1,
                "status": isUndo ? 0 : 2,
                "habitId": habit.id,
                "id": objectId(),
                "value": isUndo ? 0 : 1
            ] as [String: Any]
            logger.debug("toggleHabitCheckin() — add payload: \(checkin)")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "add": [checkin],
                "update": [],
                "delete": []
            ])
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                logger.debug("toggleHabitCheckin() — HTTP \(http.statusCode)")
                logger.debug("toggleHabitCheckin() — raw: \(String(data: data, encoding: .utf8) ?? "")")
                if http.statusCode >= 400 { await refreshHabits() }
            }
        } catch { await refreshHabits() }
        await refreshHabits()
    }

    private func updateHabitForCheckin(habit: TickTickHabit, totalCheckIns: Int, currentStreak: Int) async {
        guard let token = loadKey(privTokenKey),
              let raw = habitRawById[habit.id],
              let url = URL(string: "\(privBase)/habits/batch") else { return }

        let payload = buildHabitUpdatePayload(raw: raw, totalCheckIns: totalCheckIns, currentStreak: currentStreak)
        logger.info("updateHabitForCheckin() — habitId=\(habit.id) total=\(totalCheckIns) streak=\(currentStreak)")
        logger.debug("updateHabitForCheckin() — update payload: \(String(describing: payload))")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(xDevice, forHTTPHeaderField: "X-Device")
        req.setValue("TickTick/M-8020", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "add": [],
            "update": [payload],
            "delete": []
        ])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                logger.debug("updateHabitForCheckin() — HTTP \(http.statusCode)")
                logger.debug("updateHabitForCheckin() — raw: \(String(data: data, encoding: .utf8) ?? "")")
                if http.statusCode >= 400 { await refreshHabits() }
            }
        } catch { await refreshHabits() }
    }

    // MARK: - Helpers

    private func mapTask(_ t: RawTask) -> TickTickTask? {
        guard !t.title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return TickTickTask(
            id: t.id, projectId: t.projectId ?? "inbox",
            parentId: t.parentId, title: t.title, content: t.content,
            priority: TickTickPriority(rawValue: t.priority ?? 0) ?? .none,
            dueDate: (t.dueDate ?? t.startDate).flatMap { parseISO($0) },
            status: t.status ?? 0,
            items: (t.items ?? []).map { TickTickChecklistItem(id: $0.id, title: $0.title, status: $0.status ?? 0) },
            subtasks: []
        )
    }

    private func buildHierarchy(_ flat: [TickTickTask]) -> [TickTickTask] {
        var result: [TickTickTask] = []
        for var task in flat {
            guard task.parentId == nil else { continue }
            task.subtasks = flat.filter { $0.parentId == task.id && !$0.title.isEmpty }
            result.append(task)
        }
        logger.debug("buildHierarchy() — \(flat.count) flat → \(result.count) top-level")
        return result
    }

    private func removeLocally(_ task: TickTickTask) {
        if var arr = tasksByProject[task.projectId] {
            arr.removeAll { $0.id == task.id }
            tasksByProject[task.projectId] = arr
        }
        recalc()
    }

    private func updateLocalTask(_ task: TickTickTask) {
        if var arr = tasksByProject[task.projectId],
           let idx = arr.firstIndex(where: { $0.id == task.id }) {
            arr[idx] = task
            tasksByProject[task.projectId] = arr
            recalc()
        }
    }

    private func taskById(_ id: String) -> TickTickTask? {
        for arr in tasksByProject.values {
            if let task = arr.first(where: { $0.id == id }) { return task }
        }
        return nil
    }

    private func recalc() {
        totalPendingCount = tasksByProject.values.flatMap { $0 }.filter { !$0.isCompleted }.count
    }

    private func checkStatus(_ code: Int) throws {
        if code == 401 { throw TickTickError.unauthorized }
        if code >= 400 { throw TickTickError.apiError(code) }
    }

    private func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private func todayStr() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    private func afterStampInt(daysAgo: Int) -> Int {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return Int(f.string(from: d)) ?? 0
    }

    private func calcStreak(_ dates: Set<String>) -> Int {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        var streak = 0; var check = Date()
        if !dates.contains(f.string(from: check)) {
            check = cal.date(byAdding: .day, value: -1, to: check) ?? check
        }
        while dates.contains(f.string(from: check)) {
            streak += 1
            check = cal.date(byAdding: .day, value: -1, to: check) ?? check
            if streak > 365 { break }
        }
        return streak
    }

    private func fmtRule(_ rule: String) -> String {
        if rule.contains("FREQ=DAILY") { return "Daily" }
        if rule.contains("FREQ=WEEKLY") {
            if let r = rule.range(of: "BYDAY=") {
                let days = String(rule[r.upperBound...]).components(separatedBy: ";").first ?? ""
                let m = ["MO":"Mon","TU":"Tue","WE":"Wed","TH":"Thu","FR":"Fri","SA":"Sat","SU":"Sun"]
                return days.components(separatedBy: ",").compactMap { m[$0] }.joined(separator: ", ")
            }
            return "Weekly"
        }
        if rule.contains("FREQ=MONTHLY") { return "Monthly" }
        return ""
    }

    private func todayInt() -> Int {
        Int(todayStr().replacingOccurrences(of: "-", with: "")) ?? 0
    }

    private func rStamp(_ r: APIHabitCheckins.Record) -> Int? {
        r.checkinStamp ?? r.stampDate
    }

    private func mergeHabitCheckins(
        server: [String: [TickTickHabitCheckin]],
        cached: [String: [TickTickHabitCheckin]]
    ) -> [String: [TickTickHabitCheckin]] {
        var merged: [String: [TickTickHabitCheckin]] = server
        for (hid, cachedItems) in cached {
            var byId = Dictionary(uniqueKeysWithValues: (merged[hid] ?? []).map { ($0.id, $0) })
            for item in cachedItems {
                if byId[item.id] == nil {
                    var archived = item
                    archived.localArchived = true
                    byId[item.id] = archived
                }
            }
            merged[hid] = Array(byId.values)
        }
        return merged
    }

    private func buildTaskPayload(
        id: String,
        projectId: String,
        title: String,
        content: String,
        priority: TickTickPriority,
        dueDate: Date?,
        createdTime: Date,
        modifiedTime: Date
    ) -> [String: Any] {
        let tz = TimeZone.current.identifier
        let creator = privateUserId.flatMap { Int($0) }
        let creatorValue: Any = creator ?? NSNull()
        return [
            "creator": creatorValue,
            "id": id,
            "imgMode": 0,
            "createdTime": tickTickDate(createdTime),
            "exDate": [],
            "sortOrder": Int64(Date().timeIntervalSince1970 * -100000),
            "repeatTaskId": NSNull(),
            "focusSummaries": [],
            "completedTime": "",
            "commentCount": 0,
            "isAllDay": false,
            "timeZone": tz,
            "modifiedTime": tickTickDate(modifiedTime),
            "progress": 0,
            "priority": priority.rawValue,
            "pinnedTime": "-1",
            "dueDate": dueDate.map(tickTickDate) ?? "",
            "attachments": [],
            "completedUserId": 0,
            "assignee": -1,
            "childIds": [],
            "attendId": NSNull(),
            "reminders": [],
            "isFloating": false,
            "status": 0,
            "notionBlock": NSNull(),
            "repeatFlag": NSNull(),
            "tags": [],
            "content": content,
            "kind": "TEXT",
            "remindTime": "",
            "desc": "",
            "projectId": projectId,
            "parentId": NSNull(),
            "title": title,
            "items": [],
            "startDate": "",
            "repeatFrom": NSNull(),
            "columnId": NSNull()
        ]
    }

    private func tickTickDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    private func tickTickDateWithMillis(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }

    private func tickTickDateWithMillisZero(_ date: Date) -> String {
        let cal = Calendar.current
        let floored = cal.date(bySettingHour: cal.component(.hour, from: date),
                               minute: cal.component(.minute, from: date),
                               second: cal.component(.second, from: date),
                               of: date) ?? date
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: floored)
    }

    private func uuidNoDash() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func objectId() -> String {
        let seconds = Int(Date().timeIntervalSince1970)
        let hexTime = String(format: "%08x", seconds)
        let random = (0..<16).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined()
        return hexTime + random
    }

    private func buildHabitUpdatePayload(raw: APIHabit, totalCheckIns: Int, currentStreak: Int) -> [String: Any] {
        let now = tickTickDateWithMillis(Date())
        return [
            "color": raw.color ?? NSNull(),
            "iconRes": raw.iconRes ?? NSNull(),
            "createdTime": raw.createdTime ?? NSNull(),
            "encouragement": raw.encouragement ?? NSNull(),
            "etag": raw.etag ?? NSNull(),
            "goal": raw.goal ?? 1,
            "id": raw.id,
            "modifiedTime": now,
            "name": raw.name,
            "recordEnable": raw.recordEnable ?? false,
            "reminders": raw.reminders ?? [],
            "repeatRule": raw.repeatRule ?? "",
            "sortOrder": raw.sortOrder ?? 0,
            "status": raw.status ?? 0,
            "step": raw.step ?? 1,
            "totalCheckIns": totalCheckIns,
            "type": raw.type ?? "Boolean",
            "unit": raw.unit ?? "Count",
            "sectionId": raw.sectionId ?? "-1",
            "targetDays": raw.targetDays ?? 0,
            "targetStartDate": raw.targetStartDate ?? 0,
            "completedCycles": raw.completedCycles ?? 0,
            "exDates": raw.exDates ?? NSNull(),
            "currentStreak": currentStreak,
            "style": raw.style ?? NSNull()
        ]
    }

    // MARK: - Timer

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
                if self?.authMode == .privateAPI { await self?.refreshHabits() }
            }
        }
        logger.debug("startTimer() — interval=\(Self.refreshInterval)s")
    }

    private func stopTimer() { refreshTimer?.invalidate(); refreshTimer = nil }

    // MARK: - Cache

    private struct Cache: Codable {
        let projects: [CP]
        let tasks: [String: [CT]]
        let habits: [CH]
        let habitCheckins: [String: [CC]]
        let ts: Double
        struct CP: Codable { let id: String; let name: String; let color: String? }
        struct CT: Codable {
            let id, projectId: String; let parentId: String?
            let title: String; let content: String?; let pri: Int
            let due: Double?; let status: Int
            let items: [String]; let subs: [String]
        }
        struct CH: Codable {
            let id: String
            let name: String
            let color: String?
            let streak: Int
            let repeatRule: String
            let totalCheckIns: Int
            let completedDates: [String]
            let checkedInToday: Bool
        }
        struct CC: Codable {
            let id: String
            let habitId: String
            let stamp: Int
            let status: Int
            let checkinTime: String?
            let opTime: String?
            let value: Double?
            let goal: Double?
            let localArchived: Bool
        }
    }

    private func saveCache() {
        guard let url = cacheURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let cps = projects.map { Cache.CP(id: $0.id, name: $0.name, color: $0.color) }
            var cts: [String: [Cache.CT]] = [:]
            for (pid, arr) in tasksByProject {
                cts[pid] = arr.map { t in
                    Cache.CT(id: t.id, projectId: t.projectId, parentId: t.parentId,
                             title: t.title, content: t.content, pri: t.priority.rawValue,
                             due: t.dueDate?.timeIntervalSince1970, status: t.status,
                             items: t.items.map { $0.title },
                             subs: t.subtasks.map { $0.title })
                }
            }
            let ch = habits.map { h in
                Cache.CH(
                    id: h.id,
                    name: h.name,
                    color: h.color,
                    streak: h.streak,
                    repeatRule: h.repeatRule,
                    totalCheckIns: h.totalCheckIns,
                    completedDates: Array(h.completedDates),
                    checkedInToday: h.checkedInToday
                )
            }
            var ccs: [String: [Cache.CC]] = [:]
            for (hid, arr) in habitCheckinsByHabit {
                ccs[hid] = arr.map { c in
                    Cache.CC(
                        id: c.id,
                        habitId: c.habitId,
                        stamp: c.stamp,
                        status: c.status,
                        checkinTime: c.checkinTime,
                        opTime: c.opTime,
                        value: c.value,
                        goal: c.goal,
                        localArchived: c.localArchived
                    )
                }
            }
            try JSONEncoder().encode(
                Cache(
                    projects: cps,
                    tasks: cts,
                    habits: ch,
                    habitCheckins: ccs,
                    ts: Date().timeIntervalSince1970
                )
            ).write(to: url)
            logger.debug("saveCache() — saved")
        } catch { logger.error("saveCache() — \(error.localizedDescription)") }
    }

    private func loadCache() {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(Cache.self, from: data) else {
            logger.debug("loadCache() — no cache"); return
        }
        logger.debug("loadCache() — age=\(Int(Date().timeIntervalSince1970 - c.ts))s")
        projects = c.projects.map { TickTickProject(id: $0.id, name: $0.name, color: $0.color) }
        var byP: [String: [TickTickTask]] = [:]
        for (pid, arr) in c.tasks {
            byP[pid] = arr.map { t in
                TickTickTask(id: t.id, projectId: t.projectId, parentId: t.parentId,
                             title: t.title, content: t.content,
                             priority: TickTickPriority(rawValue: t.pri) ?? .none,
                             dueDate: t.due.map { Date(timeIntervalSince1970: $0) },
                             status: t.status,
                             items: t.items.enumerated().map { TickTickChecklistItem(id: "c\($0.offset)", title: $0.element, status: 0) },
                             subtasks: t.subs.enumerated().map { TickTickTask(
                                id: "s\($0.offset)", projectId: t.projectId, parentId: t.id,
                                title: $0.element, content: nil, priority: .none,
                                dueDate: nil, status: 0, items: [], subtasks: [])
                             })
            }
        }
        tasksByProject = byP; recalc()

        habitCheckinsByHabit = c.habitCheckins.mapValues { arr in
            arr.map {
                TickTickHabitCheckin(
                    id: $0.id,
                    habitId: $0.habitId,
                    stamp: $0.stamp,
                    status: $0.status,
                    checkinTime: $0.checkinTime,
                    opTime: $0.opTime,
                    value: $0.value,
                    goal: $0.goal,
                    localArchived: $0.localArchived
                )
            }
        }
        habits = c.habits.map { h in
            TickTickHabit(
                id: h.id,
                name: h.name,
                color: h.color,
                streak: h.streak,
                repeatRule: h.repeatRule,
                totalCheckIns: h.totalCheckIns,
                completedDates: Set(h.completedDates),
                checkedInToday: h.checkedInToday
            )
        }
        logger.debug("loadCache() — \(self.totalPendingCount) pending tasks")
    }

    private func clearCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Keychain

    private func saveKey(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: key, kSecValueData as String: data]
        SecItemDelete(q as CFDictionary)
        let s = SecItemAdd(q as CFDictionary, nil)
        logger.debug("saveKeychain('\(key)') — status=\(s)")
    }

    private func loadKey(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: key, kSecReturnData as String: true]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess,
              let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func deleteKey(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Errors

enum TickTickError: Error {
    case noToken, unauthorized, apiError(Int)
}
