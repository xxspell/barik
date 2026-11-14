import AppKit
import Foundation

/// One row in a top-process list. Which metric `primary`/`secondary` carry
/// depends on the sampler: CPU rows (%CPU, RSS bytes), memory rows (RSS, %CPU),
/// network rows (bytes/s down, bytes/s up), GPU rows (GPU time %, -).
struct TopProcess: Identifiable, Equatable {
    let pid: Int
    var id: Int { pid }
    let name: String
    let icon: NSImage?
    let primary: Double
    let secondary: Double?

    static func == (lhs: TopProcess, rhs: TopProcess) -> Bool {
        lhs.pid == rhs.pid && lhs.name == rhs.name
            && lhs.primary == rhs.primary && lhs.secondary == rhs.secondary
    }
}

/// Cumulative nettop counters keyed by pid, kept between sampler calls so each
/// call yields bytes/sec instead of bytes-since-launch.
struct NettopState {
    var previous: [Int: (download: UInt64, upload: UInt64, at: Date)] = [:]
}

enum ProcessSampler {
    private static let iconCache = NSCache<NSString, NSImage>()

    // MARK: - ps

    static func cpuProcesses(limit: Int) -> [TopProcess] {
        psProcesses(arguments: ["-Aceo", "pid,pcpu,rss,comm", "-r"], limit: limit,
                    parse: { pid, tokens in
                        guard let pcpu = double(tokens[1]), let rssKB = double(tokens[2]) else { return nil }
                        return TopProcess(pid: pid, name: "", icon: nil,
                                          primary: pcpu, secondary: rssKB * 1024)
                    })
    }

    static func memoryProcesses(limit: Int) -> [TopProcess] {
        psProcesses(arguments: ["-Aceo", "pid,rss,pcpu,comm", "-m"], limit: limit,
                    parse: { pid, tokens in
                        guard let rssKB = double(tokens[1]), let pcpu = double(tokens[2]) else { return nil }
                        return TopProcess(pid: pid, name: "", icon: nil,
                                          primary: rssKB * 1024, secondary: pcpu)
                    })
    }

    /// `ps` rows are `pid value1 value2 command-with-possible-spaces`.
    private static func psProcesses(
        arguments: [String],
        limit: Int,
        parse: (Int, [String]) -> TopProcess?
    ) -> [TopProcess] {
        guard limit > 0, let output = run("/bin/ps", arguments: arguments) else { return [] }
        var processes: [TopProcess] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count >= 4, let pid = Int(tokens[0]), pid > 0, pid != 0 else { continue } // skips " PID  %CPU..." header
            guard var process = parse(pid, tokens.map(String.init)) else { continue }
            let command = tokens[3...].joined(separator: " ")
            let resolved = displayName(pid: pid, command: command)
            process = TopProcess(pid: pid, name: resolved.name, icon: resolved.icon,
                                 primary: process.primary, secondary: process.secondary)
            processes.append(process)
            if processes.count >= limit { break }
        }
        return processes
    }

    // MARK: - nettop

    /// Rates per second computed against `previous`. First call (nil state)
    /// seeds the cumulative counters and returns [].
    static func networkProcesses(limit: Int, previous: inout NettopState?) -> [TopProcess] {
        guard limit > 0,
              let output = run("/usr/bin/nettop",
                               arguments: ["-P", "-L", "1", "-x", "-c", "1"]) else { return [] }
        let now = Date()
        var current: [Int: (download: UInt64, upload: UInt64)] = [:]
        var names: [Int: String] = [:]

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            // Data rows: time, name.pid, interface, state, bytes_in, bytes_out, ...
            guard fields.count > 5, !fields[1].isEmpty, !fields[1].contains("interface") else { continue }
            guard let pid = pid(fromNettopName: fields[1]),
                  let download = UInt64(fields[4]),
                  let upload = UInt64(fields[5]) else { continue }
            current[pid] = (download, upload)
            names[pid] = fields[1]
        }

        let result: [TopProcess]
        if let state = previous {
            result = current.compactMap { pid, counters in
                guard let old = state.previous[pid],
                      counters.download >= old.download,
                      counters.upload >= old.upload else { return nil }
                let interval = now.timeIntervalSince(old.at)
                guard interval >= 0.5 else { return nil }
                let down = Double(counters.download - old.download) / interval
                let up = Double(counters.upload - old.upload) / interval
                guard down + up > 0 else { return nil }
                let resolved = displayName(pid: pid, command: stripPIDSuffix(names[pid] ?? ""))
                return TopProcess(pid: pid, name: resolved.name, icon: resolved.icon,
                                  primary: down, secondary: up)
            }
            .sorted { ($0.primary + ($0.secondary ?? 0)) > ($1.primary + ($1.secondary ?? 0)) }
            .prefix(limit).map { $0 }
        } else {
            result = []
        }

        var state = NettopState()
        state.previous = current.mapValues { (download: $0.download, upload: $0.upload, at: now) }
        previous = state
        return result
    }

    /// "Google Chrome H.1233" → 1233 (last ".digits" segment).
    private static func pid(fromNettopName name: String) -> Int? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let suffix = name[name.index(after: dot)...]
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(suffix)
    }

    private static func stripPIDSuffix(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return name }
        let suffix = name[name.index(after: dot)...]
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber }) else { return name }
        return String(name[..<dot])
    }

    // MARK: - names & icons

    static func displayName(pid: Int, command: String) -> (name: String, icon: NSImage?) {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            let name = app.localizedName ?? command
            if let icon = cachedIcon(for: app) {
                return (name, icon)
            }
            return (name, app.icon)
        }
        return (command, nil)
    }

    private static func cachedIcon(for app: NSRunningApplication) -> NSImage? {
        guard let bundlePath = app.bundleURL?.path else { return nil }
        let key = bundlePath as NSString
        if let cached = iconCache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        icon.size = NSSize(width: 32, height: 32)
        iconCache.setObject(icon, forKey: key, cost: 1)
        return icon
    }

    // MARK: - process running

    private static func double(_ token: String) -> Double? {
        Double(token.replacingOccurrences(of: ",", with: "."))
    }

    /// Runs `path` synchronously, killing it after 5 s. nil on any failure.
    private static func run(_ path: String, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        do {
            try task.run()
        } catch {
            return nil
        }

        let watchdog = DispatchWorkItem {
            if task.isRunning { task.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: watchdog)

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        stderr.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        watchdog.cancel()
        guard task.terminationStatus == 0, !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

#if DEBUG
func systemMonitorProcessesSelfTest() {
    let cpu = ProcessSampler.cpuProcesses(limit: 5)
    precondition(!cpu.isEmpty, "cpu list empty")
    precondition(cpu[0].primary >= 0 && cpu[0].primary < 500)
    precondition(cpu[0].secondary != nil && cpu[0].secondary! > 0, "rss missing")
    precondition(!cpu[0].name.isEmpty && !cpu[0].name.contains(".1"), "name not resolved: \(cpu[0].name)")

    let mem = ProcessSampler.memoryProcesses(limit: 5)
    precondition(!mem.isEmpty, "mem list empty")
    precondition(mem[0].primary > 1_000_000, "rss not bytes: \(mem[0].primary)")

    var state: NettopState?
    precondition(ProcessSampler.networkProcesses(limit: 5, previous: &state).isEmpty, "first nettop must seed")
    Thread.sleep(forTimeInterval: 2)
    let net = ProcessSampler.networkProcesses(limit: 5, previous: &state)
    for p in net {
        precondition(p.primary >= 0 && (p.secondary ?? 0) >= 0)
        precondition(!p.name.isEmpty)
    }
    NSLog("processesSelfTest OK cpu=\(cpu.map(\.name)) net=\(net.map { "\($0.name):\($0.primary)" })")
}
#endif
