import Foundation

// MARK: - Model

enum AgentStatus: String, Equatable, CaseIterable {
    case idle, working, blocked, done, unknown
}

struct AgentSession: Identifiable, Equatable {
    let paneID: String
    let workspaceID: String
    let tabID: String
    var kind: String
    var status: AgentStatus
    var cwd: String
    var title: String
    /// nil = unknown age (came from a snapshot).
    var statusSince: Date?
    var focusedInHerdr: Bool

    var id: String { paneID }

    var projectName: String {
        if cwd == NSHomeDirectory() { return "~" }
        return (cwd as NSString).lastPathComponent
    }
}

// MARK: - Parsing

enum HerdrEvent: Equatable {
    case subscriptionStarted
    case statusChanged(paneID: String, status: AgentStatus)
    case topologyChanged
    case error(code: String, message: String)
}

enum HerdrParseError: Error, Equatable {
    case malformed
    case server(code: String, message: String)
}

enum HerdrParser {
    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func serverError(_ o: [String: Any]) -> HerdrParseError? {
        guard let e = o["error"] as? [String: Any] else { return nil }
        return .server(code: e["code"] as? String ?? "", message: e["message"] as? String ?? "")
    }

    static func parseAgentList(_ data: Data) throws -> [AgentSession] {
        guard let o = object(data) else { throw HerdrParseError.malformed }
        if let err = serverError(o) { throw err }
        guard let result = o["result"] as? [String: Any],
              let agents = result["agents"] as? [[String: Any]] else { throw HerdrParseError.malformed }
        return agents.compactMap { a in
            guard let pane = a["pane_id"] as? String else { return nil }
            let stripped = a["terminal_title_stripped"] as? String
            let title = stripped ?? (a["terminal_title"] as? String) ?? ""
            return AgentSession(
                paneID: pane,
                workspaceID: a["workspace_id"] as? String ?? "",
                tabID: a["tab_id"] as? String ?? "",
                kind: a["agent"] as? String ?? "",
                status: AgentStatus(rawValue: a["agent_status"] as? String ?? "") ?? .unknown,
                cwd: a["cwd"] as? String ?? "",
                title: title,
                statusSince: nil,
                focusedInHerdr: a["focused"] as? Bool ?? false)
        }
    }

    static func parseEvent(_ line: Data) -> HerdrEvent? {
        guard let o = object(line) else { return nil }
        if let err = serverError(o), case let .server(code, message) = err {
            return .error(code: code, message: message)
        }
        if let r = o["result"] as? [String: Any] {
            return r["type"] as? String == "subscription_started" ? .subscriptionStarted : nil
        }
        guard let event = o["event"] as? String else { return nil }
        switch event {
        case "pane.agent_status_changed":
            guard let d = o["data"] as? [String: Any], let pane = d["pane_id"] as? String else { return nil }
            let status = AgentStatus(rawValue: d["agent_status"] as? String ?? "") ?? .unknown
            return .statusChanged(paneID: pane, status: status)
        case "pane.created", "pane.closed", "pane.agent_detected":
            return .topologyChanged
        default:
            return nil
        }
    }

    static func parseReadText(_ data: Data) throws -> String {
        guard let o = object(data) else { throw HerdrParseError.malformed }
        if let err = serverError(o) { throw err }
        guard let result = o["result"] as? [String: Any],
              let read = result["read"] as? [String: Any],
              let text = read["text"] as? String else { throw HerdrParseError.malformed }
        return text
    }

    /// Last `max` meaningful lines: blank lines and pure box-drawing rules are dropped.
    static func previewLines(_ text: String, max: Int) -> [String] {
        let kept = text.components(separatedBy: "\n").filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return false }
            return !t.unicodeScalars.allSatisfy { (0x2500...0x257F).contains($0.value) }
        }
        return Array(kept.suffix(Swift.max(0, max)))
    }
}

// MARK: - Requests

enum HerdrRequest {
    private static func make(_ method: String, _ params: [String: Any]) -> Data {
        let body: [String: Any] = [
            "id": "barik-\(UUID().uuidString.prefix(8))",
            "method": method,
            "params": params,
        ]
        var d = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        d.append(0x0A)
        return d
    }

    static func agentList() -> Data { make("agent.list", [:]) }

    static func subscribe(paneIDs: [String]) -> Data {
        var subs: [[String: Any]] = ["pane.created", "pane.closed", "pane.agent_detected"].map { ["type": $0] }
        subs += paneIDs.map { ["type": "pane.agent_status_changed", "pane_id": $0] }
        return make("events.subscribe", ["subscriptions": subs])
    }

    static func read(paneID: String, lines: Int) -> Data {
        make("agent.read", ["target": paneID, "source": "visible", "lines": lines, "strip_ansi": true])
    }

    static func focus(paneID: String) -> Data { make("agent.focus", ["target": paneID]) }
}

// MARK: - Store

struct AgentTransition: Equatable {
    let agent: AgentSession
    let from: AgentStatus?
    let to: AgentStatus
}

struct AgentStore {
    private(set) var agents: [AgentSession] = []
    var debounce: TimeInterval = 3
    /// When each pane last entered each status (for debouncing flapping).
    private var entered: [String: [AgentStatus: Date]] = [:]

    private func isDebounced(_ pane: String, into status: AgentStatus, now: Date) -> Bool {
        guard let t = entered[pane]?[status] else { return false }
        return now.timeIntervalSince(t) < debounce
    }

    mutating func applySnapshot(_ list: [AgentSession], now: Date, emit: Bool) -> [AgentTransition] {
        let old = Dictionary(agents.map { ($0.paneID, $0) }, uniquingKeysWith: { a, _ in a })
        var transitions: [AgentTransition] = []
        var next: [AgentSession] = []
        for var a in list {
            let prev = old[a.paneID]
            if let prev, prev.status == a.status {
                a.statusSince = prev.statusSince
            } else {
                let suppressed = isDebounced(a.paneID, into: a.status, now: now)
                a.statusSince = emit ? now : nil
                entered[a.paneID, default: [:]][a.status] = now
                if emit && !suppressed {
                    transitions.append(AgentTransition(agent: a, from: prev?.status, to: a.status))
                }
            }
            next.append(a)
        }
        let live = Set(next.map(\.paneID))
        entered = entered.filter { live.contains($0.key) }
        agents = next
        return transitions
    }

    mutating func applyStatus(paneID: String, status: AgentStatus, now: Date) -> AgentTransition? {
        guard let i = agents.firstIndex(where: { $0.paneID == paneID }),
              agents[i].status != status else { return nil }
        let from = agents[i].status
        let suppressed = isDebounced(paneID, into: status, now: now)
        agents[i].status = status
        agents[i].statusSince = now
        entered[paneID, default: [:]][status] = now
        return suppressed ? nil : AgentTransition(agent: agents[i], from: from, to: status)
    }
}

// MARK: - Summary

enum ChipState: Equatable {
    case needsYou(primary: AgentSession, extraBlocked: Int, working: Int, done: Int)
    case active(working: Int, done: Int, longestWorkingSince: Date?)
    case idle
}

struct AgentsSummary: Equatable {
    let blocked: [AgentSession]
    let working: [AgentSession]
    let done: [AgentSession]
    let idle: [AgentSession]   // includes unknown

    init(agents: [AgentSession], kinds: Set<String>) {
        let f = kinds.isEmpty ? agents : agents.filter { kinds.contains($0.kind) }
        blocked = f.filter { $0.status == .blocked }
        working = f.filter { $0.status == .working }
        done = f.filter { $0.status == .done }
        idle = f.filter { $0.status == .idle || $0.status == .unknown }
    }

    var total: Int { blocked.count + working.count + done.count + idle.count }

    var chipState: ChipState {
        if !blocked.isEmpty {
            // Unknown age (nil) sorts first; ties keep herdr list order.
            let primary = blocked.enumerated().min { l, r in
                switch (l.element.statusSince, r.element.statusSince) {
                case let (a?, b?): return a != b ? a < b : l.offset < r.offset
                case (nil, nil): return l.offset < r.offset
                case (nil, _): return true
                case (_, nil): return false
                }
            }!.element
            return .needsYou(primary: primary, extraBlocked: blocked.count - 1, working: working.count, done: done.count)
        }
        if !working.isEmpty || !done.isEmpty {
            return .active(working: working.count, done: done.count,
                           longestWorkingSince: working.compactMap(\.statusSince).min())
        }
        return .idle
    }
}

// MARK: - Time formatting

enum AgentTimeFormat {
    static func short(_ t: TimeInterval) -> String {
        let s = Int(Swift.max(0, t))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 {
            let h = s / 3600, m = (s % 3600) / 60
            return m == 0 ? "\(h)h" : "\(h)h\(m)m"
        }
        return "\(s / 86400)d"
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(Swift.max(0, t))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Config

struct AgentsConfig: Equatable {
    var socketPath: String
    var herdrCLI: String
    var herdrBundleIDs: [String]
    var terminalBundleID: String
    var fallbackInterval: TimeInterval
    var showWhenIdle: Bool
    var showElapsed: Bool
    var agentKinds: Set<String>
    var groupBy: String
    var previewLines: Int
    var notifications: Bool
    var notifyOn: Set<AgentStatus>
    var toastStyle: String
    var screen: String
    var quietWhenHerdrActive: Bool
    var doneAutohide: TimeInterval
    var sound: String

    static let `default` = AgentsConfig(
        socketPath: ("~/.config/herdr/herdr.sock" as NSString).expandingTildeInPath,
        herdrCLI: "herdr",
        herdrBundleIDs: ["so.pen.herdr-gpui"],
        terminalBundleID: "",
        fallbackInterval: 2,
        showWhenIdle: true,
        showElapsed: true,
        agentKinds: [],
        groupBy: "status",
        previewLines: 6,
        notifications: true,
        notifyOn: [.blocked, .done],
        toastStyle: "island",
        screen: "active",
        quietWhenHerdrActive: true,
        doneAutohide: 6,
        sound: "off")
}
