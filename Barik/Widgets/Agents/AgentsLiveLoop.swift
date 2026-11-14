import Foundation

enum AgentsConnectionState: Equatable {
    case connecting
    case live
    case fallbackPolling(reason: String)
    case disconnected(reason: String)
}

/// Drives the live herdr socket connection: snapshot → event stream → debounced refreshes,
/// re-subscribing on topology changes and reconnecting with backoff.
/// Single use: `start()` after `stop()` is a no-op. Outputs may arrive on any thread;
/// once `stop()` returns, no further outputs are delivered.
final class AgentsLiveLoop: @unchecked Sendable {
    enum Output {
        case snapshot([AgentSession], isInitial: Bool)
        case status(paneID: String, status: AgentStatus)
        case state(AgentsConnectionState)
    }

    private let client: HerdrClient
    private let output: (Output) -> Void
    private let backoff: [TimeInterval]
    private let statusRefreshDebounce: TimeInterval
    private let topologyDebounce: TimeInterval

    /// Recursive so `stop()` may be called from inside the output callback.
    private let lock = NSRecursiveLock()
    private var started = false
    private var stopped = false
    private var task: Task<Void, Never>?
    private var lastState: AgentsConnectionState?

    convenience init(client: HerdrClient, output: @escaping (Output) -> Void) {
        self.init(client: client, backoff: [2, 4, 8, 16, 30],
                  statusRefreshDebounce: 0.3, topologyDebounce: 0.5, output: output)
    }

    init(client: HerdrClient, backoff: [TimeInterval], statusRefreshDebounce: TimeInterval,
         topologyDebounce: TimeInterval, output: @escaping (Output) -> Void) {
        self.client = client
        self.backoff = backoff.isEmpty ? [2] : backoff
        self.statusRefreshDebounce = statusRefreshDebounce
        self.topologyDebounce = topologyDebounce
        self.output = output
    }

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard !started, !stopped else { return }
        started = true
        task = Task.detached(priority: .utility) { [self] in await runLoop() }
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        task?.cancel()
        task = nil
    }

    // MARK: Output gating

    private func emit(_ o: Output) {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return }
        if case let .state(s) = o {
            if s == lastState { return }
            lastState = s
        }
        output(o)
    }

    // MARK: Run loop

    private enum SessionEnd {
        case cancelled
        case fallback(String)
        case disconnected(String, hadSnapshot: Bool)
    }

    private func runLoop() async {
        emit(.state(.connecting))
        var failures = 0
        while !Task.isCancelled {
            switch await runSession() {
            case .cancelled:
                return
            case let .fallback(reason):
                emit(.state(.fallbackPolling(reason: reason)))
                return
            case let .disconnected(reason, hadSnapshot):
                if hadSnapshot { failures = 0 }
                emit(.state(.disconnected(reason: reason)))
                let delay = backoff[min(failures, backoff.count - 1)]
                failures += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func fetchList() async throws -> [AgentSession] {
        try HerdrParser.parseAgentList(try await client.send(HerdrRequest.agentList()))
    }

    private func classify(_ error: Error, hadSnapshot: Bool) -> SessionEnd {
        if Task.isCancelled || error is CancellationError { return .cancelled }
        switch error {
        case HerdrParseError.malformed:
            return .fallback("unparseable herdr response")
        case let HerdrParseError.server(code, message) where code == "invalid_request":
            return .fallback("herdr rejected request: \(message)")
        case let HerdrParseError.server(code, _):
            return .disconnected("herdr error: \(code)", hadSnapshot: hadSnapshot)
        case HerdrClientError.socketMissing:
            return .disconnected("herdr not running", hadSnapshot: hadSnapshot)
        case HerdrClientError.timeout:
            return .disconnected("herdr not responding", hadSnapshot: hadSnapshot)
        default:
            return .disconnected("herdr connection failed", hadSnapshot: hadSnapshot)
        }
    }

    private enum Command {
        case line(gen: Int, Data)
        case streamEnded(gen: Int)
        case refreshTitles
        case topology
    }

    /// One connected session: initial snapshot, then serially process stream lines and
    /// debounced refresh commands until the stream ends, a protocol error occurs, or cancellation.
    private func runSession() async -> SessionEnd {
        let initial: [AgentSession]
        do { initial = try await fetchList() } catch { return classify(error, hadSnapshot: false) }
        if Task.isCancelled { return .cancelled }
        emit(.snapshot(initial, isInitial: true))
        emit(.state(.live))

        let (commands, sink) = AsyncStream<Command>.makeStream()
        var gen = 0
        var streamTask: Task<Void, Never>?
        var titleTask: Task<Void, Never>?
        var topologyTask: Task<Void, Never>?
        var gapFillPending = false
        defer {
            streamTask?.cancel(); titleTask?.cancel(); topologyTask?.cancel()
            sink.finish()
        }

        let client = self.client
        func openStream(_ paneIDs: [String]) {
            streamTask?.cancel()
            gen += 1
            let g = gen
            let request = HerdrRequest.subscribe(paneIDs: paneIDs)
            streamTask = Task.detached(priority: .utility) {
                do {
                    for try await line in client.subscribe(request) { sink.yield(.line(gen: g, line)) }
                } catch {}
                sink.yield(.streamEnded(gen: g))
            }
        }
        func later(_ delay: TimeInterval, _ cmd: Command) -> Task<Void, Never> {
            Task.detached(priority: .utility) {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if !Task.isCancelled { sink.yield(cmd) }
            }
        }

        openStream(initial.map(\.paneID))

        // AsyncStream iteration ends (returns nil) when this task is cancelled.
        for await command in commands {
            if Task.isCancelled { return .cancelled }
            switch command {
            case let .line(g, data):
                guard g == gen, let event = HerdrParser.parseEvent(data) else { continue }
                switch event {
                case .subscriptionStarted:
                    // A fresh subscription after a topology change: take a list to cover the gap.
                    if gapFillPending {
                        gapFillPending = false
                        do { emit(.snapshot(try await fetchList(), isInitial: false)) }
                        catch { return classify(error, hadSnapshot: true) }
                    }
                case let .statusChanged(paneID, status):
                    emit(.status(paneID: paneID, status: status))
                    titleTask?.cancel()
                    titleTask = later(statusRefreshDebounce, .refreshTitles)
                case .topologyChanged:
                    topologyTask?.cancel()
                    topologyTask = later(topologyDebounce, .topology)
                case let .error(code, message):
                    return .fallback("herdr stream error \(code): \(message)")
                }
            case let .streamEnded(g):
                guard g == gen else { continue }
                return Task.isCancelled ? .cancelled : .disconnected("herdr not running", hadSnapshot: true)
            case .refreshTitles:
                do { emit(.snapshot(try await fetchList(), isInitial: false)) }
                catch { return classify(error, hadSnapshot: true) }
            case .topology:
                do {
                    let list = try await fetchList()
                    if Task.isCancelled { return .cancelled }
                    emit(.snapshot(list, isInitial: false))
                    gapFillPending = true
                    openStream(list.map(\.paneID))
                } catch { return classify(error, hadSnapshot: true) }
            }
        }
        return .cancelled
    }
}

/// Decides whether a successful snapshot may emit transitions (toasts).
/// The first snapshot after any period without a fresh baseline (start, outage, wake) is silent.
struct SnapshotBaseline: Equatable {
    private(set) var isFresh = false

    /// Call when the store may have gone stale: a failed poll, an outage, wake from sleep.
    mutating func invalidate() { isFresh = false }

    /// Call for each successful snapshot; returns whether it should emit transitions.
    mutating func admit() -> Bool {
        defer { isFresh = true }
        return isFresh
    }
}
