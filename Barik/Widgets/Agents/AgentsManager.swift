import AppKit
import Combine
import Foundation
import OSLog

// MARK: - Config parsing

extension AgentsConfig {
    /// Builds the config from `[widgets.default.agents]`; missing or mistyped keys keep defaults.
    init(config: ConfigData) {
        self = .default
        func string(_ key: String) -> String? { config[key]?.stringValue }
        func bool(_ key: String) -> Bool? { config[key]?.boolValue }
        func number(_ key: String) -> Double? {
            switch config[key] {
            case let .int(i)?: return Double(i)
            case let .double(d)?: return d
            default: return nil
            }
        }

        if let s = string("socket-path"), !s.isEmpty { socketPath = (s as NSString).expandingTildeInPath }
        if let s = string("herdr-cli"), !s.isEmpty { herdrCLI = s }
        if let a = config["herdr-bundle-ids"]?.stringArrayValue { herdrBundleIDs = a.filter { !$0.isEmpty } }
        if let s = string("terminal-bundle-id") { terminalBundleID = s }
        if let n = number("fallback-interval") { fallbackInterval = max(0.5, n) }
        if let b = bool("show-when-idle") { showWhenIdle = b }
        if let b = bool("show-elapsed") { showElapsed = b }
        if let a = config["agents"]?.stringArrayValue { agentKinds = Set(a.filter { !$0.isEmpty }) }
        if let s = string("group-by"), ["status", "project"].contains(s) { groupBy = s }
        if let n = config["preview-lines"]?.intValue { previewLines = min(max(0, n), 50) }
        if let b = bool("notifications") { notifications = b }
        if let a = config["notify-on"]?.stringArrayValue { notifyOn = Set(a.compactMap(AgentStatus.init(rawValue:))) }
        if let s = string("toast-style"), ToastStyle(rawValue: s) != nil { toastStyle = s }
        if let s = string("screen"), !s.isEmpty { screen = s }
        if let b = bool("quiet-when-herdr-active") { quietWhenHerdrActive = b }
        if let n = number("done-autohide") { doneAutohide = max(0, n) }
        if let s = string("sound"), !s.isEmpty { sound = s }
    }
}

// MARK: - Manager

/// Shared state of herdr-managed agents: live socket loop with CLI polling fallback.
@MainActor
final class AgentsManager: ObservableObject {
    static let shared = AgentsManager()

    @Published private(set) var agents: [AgentSession] = []
    @Published private(set) var summary = AgentsSummary(agents: [], kinds: [])
    @Published private(set) var connection: AgentsConnectionState = .connecting
    @Published private(set) var herdrVersion: String?
    @Published private(set) var herdrIsFrontmost = false
    private(set) var config: AgentsConfig = .default
    let transitions = PassthroughSubject<AgentTransition, Never>()

    private enum Mode { case stopped, live, fallback }

    private static let liveRetryInterval: TimeInterval = 300
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "barik", category: "Agents")

    private var started = false
    private var mode: Mode = .stopped
    private var store = AgentStore()
    private var client: HerdrClient?

    private var loop: AgentsLiveLoop?
    /// Generation of the current loop; outputs from older loops are dropped.
    private var loopToken = 0
    /// The current loop is a socket probe made while in fallback mode.
    private var probing = false

    private var fallbackReason = ""
    private var pollTask: Task<Void, Never>?
    private var liveRetryTask: Task<Void, Never>?
    private var versionTask: Task<Void, Never>?
    /// A fallback poll has fed the store since entering fallback.
    private var hasPolled = false

    private var observers: [NSObjectProtocol] = []

    private init() {}

    // MARK: Public API

    func start(config newConfig: AgentsConfig) {
        if started && newConfig == config { return }
        if started { stopAll() }
        started = true
        config = newConfig
        client = HerdrClient(socketPath: newConfig.socketPath)
        installObserversOnce()
        updateFrontmost(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        publish()
        logger.info("Agents: starting (socket \(newConfig.socketPath, privacy: .public))")
        startLive()
        fetchVersion()
    }

    func focus(_ agent: AgentSession) {
        let request = HerdrRequest.focus(paneID: agent.paneID)
        let client = self.client
        Task { [weak self] in
            _ = try? await client?.send(request)
            guard let self else { return }
            let launched = self.activateHerdr()
            if launched {
                // The GUI may host the server: re-send focus once it had a moment to come up.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                _ = try? await client?.send(request)
            }
        }
    }

    func openHerdr() {
        _ = activateHerdr()
    }

    func preview(paneID: String) async -> [String] {
        guard let client else { return [] }
        let lines = config.previewLines
        do {
            let data = try await client.send(HerdrRequest.read(paneID: paneID, lines: max(lines * 3, 20)))
            return HerdrParser.previewLines(try HerdrParser.parseReadText(data), max: lines)
        } catch {
            return []
        }
    }

    // MARK: Lifecycle

    private func stopAll() {
        stopLoop()
        stopFallback()
        versionTask?.cancel()
        versionTask = nil
        mode = .stopped
    }

    private func stopLoop() {
        loop?.stop()
        loop = nil
        probing = false
        loopToken += 1
    }

    private func stopFallback() {
        pollTask?.cancel()
        pollTask = nil
        liveRetryTask?.cancel()
        liveRetryTask = nil
    }

    private func startLive() {
        stopFallback()
        mode = .live
        makeLoop(probing: false)
    }

    private func makeLoop(probing: Bool) {
        stopLoop()
        guard let client else { return }
        self.probing = probing
        let token = loopToken
        let loop = AgentsLiveLoop(client: client) { [weak self] output in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(output, token: token) }
            }
        }
        self.loop = loop
        loop.start()
    }

    private func handle(_ output: AgentsLiveLoop.Output, token: Int) {
        guard token == loopToken, loop != nil else { return }
        switch output {
        case let .snapshot(list, isInitial):
            if probing {
                // The socket answered again: leave fallback polling.
                logger.info("Agents: herdr socket recovered, leaving fallback polling")
                let storeIsFresh = hasPolled
                probing = false
                stopFallback()
                mode = .live
                apply(list, emit: isInitial ? storeIsFresh : true)
            } else {
                apply(list, emit: !isInitial)
            }
        case let .status(paneID, status):
            if let t = store.applyStatus(paneID: paneID, status: status, now: Date()) {
                publish()
                transitions.send(t)
            }
        case let .state(state):
            if probing {
                switch state {
                case .disconnected, .fallbackPolling:
                    stopLoop() // probe failed; keep polling until the next retry
                case .connecting, .live:
                    break
                }
                return
            }
            if case let .fallbackPolling(reason) = state {
                enterFallback(reason: reason)
            } else {
                setConnection(state)
            }
        }
    }

    // MARK: Fallback polling

    private func enterFallback(reason: String) {
        stopLoop()
        stopFallback()
        mode = .fallback
        fallbackReason = reason
        hasPolled = false
        logger.info("Agents: socket protocol failure (\(reason, privacy: .public)), falling back to CLI")
        scheduleLiveRetry()

        guard let exe = HerdrCLI.resolveExecutable(config.herdrCLI) else {
            setConnection(.disconnected(reason: "herdr CLI not found"))
            return
        }
        setConnection(.fallbackPolling(reason: reason))
        let interval = config.fallbackInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let list = try await HerdrCLI.agentList(executable: exe)
                    guard !Task.isCancelled, let self else { return }
                    self.apply(list, emit: self.hasPolled)
                    self.hasPolled = true
                    self.setConnection(.fallbackPolling(reason: self.fallbackReason))
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    self.setConnection(.disconnected(reason: "herdr CLI failed"))
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func scheduleLiveRetry() {
        liveRetryTask?.cancel()
        liveRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.liveRetryInterval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.probeSocket()
            }
        }
    }

    private func probeSocket() {
        guard mode == .fallback else { return }
        makeLoop(probing: true)
    }

    /// Wake / herdr launch: reconnect right away instead of waiting for backoff.
    private func retryNow() {
        switch mode {
        case .stopped: break
        case .live: makeLoop(probing: false)
        case .fallback: probeSocket()
        }
    }

    // MARK: State

    private func apply(_ list: [AgentSession], emit: Bool) {
        let ts = store.applySnapshot(list, now: Date(), emit: emit)
        publish()
        ts.forEach(transitions.send)
    }

    private func publish() {
        if agents != store.agents { agents = store.agents }
        let s = AgentsSummary(agents: store.agents, kinds: config.agentKinds)
        if s != summary { summary = s }
    }

    private func setConnection(_ state: AgentsConnectionState) {
        guard state != connection else { return }
        connection = state
        logger.info("Agents: connection \(String(describing: state), privacy: .public)")
    }

    private func fetchVersion() {
        versionTask?.cancel()
        guard let exe = HerdrCLI.resolveExecutable(config.herdrCLI) else {
            herdrVersion = nil
            return
        }
        versionTask = Task { [weak self] in
            let v = await HerdrCLI.version(executable: exe)
            guard !Task.isCancelled, let self else { return }
            self.herdrVersion = v
        }
    }

    // MARK: Activation

    /// Raises herdr per the spec's "Terminal TUI client" rule. Returns true if the GUI had to be launched.
    @discardableResult
    private func activateHerdr() -> Bool {
        let running = NSWorkspace.shared.runningApplications
        if let gui = running.first(where: { config.herdrBundleIDs.contains($0.bundleIdentifier ?? "") }) {
            activate(gui)
            return false
        }
        let terminal = config.terminalBundleID
        if !terminal.isEmpty, let app = running.first(where: { $0.bundleIdentifier == terminal }) {
            activate(app)
            return false
        }
        for id in config.herdrBundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            let logger = self.logger
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
                if let error {
                    logger.error("Agents: failed to launch herdr: \(error.localizedDescription, privacy: .public)")
                }
            }
            return true
        }
        logger.info("Agents: no herdr app found to activate")
        return false
    }

    private func activate(_ app: NSRunningApplication) {
        NSApp.yieldActivation(to: app)
        app.activate()
    }

    // MARK: Workspace observers

    private func installObserversOnce() {
        guard observers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter

        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.updateFrontmost(id) }
        })

        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mode != .stopped else { return }
                self.logger.info("Agents: wake, reconnecting")
                self.retryNow()
            }
        })

        observers.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let id, self.config.herdrBundleIDs.contains(id) else { return }
                let disconnected: Bool
                switch self.connection {
                case .disconnected, .fallbackPolling: disconnected = true
                case .connecting, .live: disconnected = false
                }
                guard disconnected else { return }
                self.logger.info("Agents: herdr launched, reconnecting")
                self.retryNow()
            }
        })
    }

    private func updateFrontmost(_ bundleID: String?) {
        let front = bundleID.map { config.herdrBundleIDs.contains($0) } ?? false
        if front != herdrIsFrontmost { herdrIsFrontmost = front }
    }
}
