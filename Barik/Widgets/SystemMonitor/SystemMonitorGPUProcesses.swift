import Foundation
import IOKit

/// Per-client GPU time from IORegistry (`IOAccelerator` children expose an
/// `AppUsage` array with `accumulatedGPUTime` per queue). Same approach as
/// exelban/Stats: percentage = GPU-time delta / wall-time delta * 100.
struct GPUClientState {
    var clients: [UInt64: (pid: Int, name: String, gpuTime: UInt64)] = [:]
    var timestamp: UInt64 = 0
}

enum GPUProcessSampler {
    /// Cumulative GPU time per user client, keyed by registry entry id.
    /// Returns nil when IORegistry is unreachable (state must stay untouched).
    private static func readClients() -> [UInt64: (pid: Int, name: String, gpuTime: UInt64)]? {
        var iterator: io_iterator_t = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var clients: [UInt64: (pid: Int, name: String, gpuTime: UInt64)] = [:]
        while case let accelerator = IOIteratorNext(iterator), accelerator != 0 {
            defer { IOObjectRelease(accelerator) }
            var children: io_iterator_t = io_iterator_t()
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }

            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                var entryID: UInt64 = 0
                var properties: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryGetRegistryEntryID(child, &entryID) == KERN_SUCCESS,
                      IORegistryEntryCreateCFProperties(child, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let properties = properties?.takeRetainedValue() as? [String: Any],
                      let client = parseClient(properties) else { continue }
                if let existing = clients[entryID] {
                    clients[entryID] = (existing.pid, existing.name, existing.gpuTime + client.gpuTime)
                } else {
                    clients[entryID] = client
                }
            }
        }
        return clients
    }

    /// `IOUserClientCreator` looks like "pid 123, Google Chrome"; `AppUsage`
    /// carries one dict per command queue with `accumulatedGPUTime` in ns.
    private static func parseClient(_ properties: [String: Any]) -> (pid: Int, name: String, gpuTime: UInt64)? {
        guard let creator = properties["IOUserClientCreator"] as? String, creator.hasPrefix("pid "),
              let queues = properties["AppUsage"] as? [[String: Any]] else { return nil }
        let parts = creator.dropFirst(4).split(separator: ",", maxSplits: 1)
        guard let first = parts.first,
              let pid = Int(first.trimmingCharacters(in: .whitespaces)), pid > 0 else { return nil }
        let times = queues.compactMap { ($0["accumulatedGPUTime"] as? NSNumber)?.uint64Value }
        guard !times.isEmpty else { return nil }
        let name = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "\(pid)"
        return (pid, name, times.reduce(0, &+))
    }

    /// Rates against `previous` state; first call (nil state) seeds and returns [].
    /// Clients that appeared/disappeared or whose queue count changed are
    /// skipped, matching Stats' guard against context reuse.
    static func gpuProcesses(limit: Int, previous: inout GPUClientState?) -> [TopProcess] {
        guard limit > 0, let current = readClients() else { return [] }
        let now = DispatchTime.now().uptimeNanoseconds

        var result: [TopProcess] = []
        if let state = previous, state.timestamp > 0, now > state.timestamp {
            let elapsed = Double(now - state.timestamp)
            var byPID: [Int: Double] = [:]
            var names: [Int: String] = [:]
            for (id, client) in current {
                guard let old = state.clients[id],
                      old.pid == client.pid,
                      client.gpuTime >= old.gpuTime else { continue }
                let delta = Double(client.gpuTime - old.gpuTime)
                guard delta > 0 else { continue }
                byPID[client.pid, default: 0] += delta / elapsed * 100
                names[client.pid] = client.name
            }
            result = byPID.compactMap { pid, usage in
                guard usage >= 0.05 else { return nil }
                let resolved = ProcessSampler.displayName(pid: pid, command: names[pid] ?? "\(pid)")
                return TopProcess(pid: pid, name: resolved.name, icon: resolved.icon,
                                  primary: usage, secondary: nil)
            }
            .sorted { $0.primary > $1.primary }
            .prefix(limit).map { $0 }
        }

        var state = GPUClientState()
        state.clients = current
        state.timestamp = now
        previous = state
        return result
    }
}

#if DEBUG
func systemMonitorGPUProcessesSelfTest() {
    var state: GPUClientState?
    precondition(GPUProcessSampler.gpuProcesses(limit: 10, previous: &state).isEmpty, "first read must seed")
    precondition(state != nil && !state!.clients.isEmpty, "no GPU clients found in IORegistry")
    Thread.sleep(forTimeInterval: 2)
    let rows = GPUProcessSampler.gpuProcesses(limit: 10, previous: &state)
    for row in rows {
        precondition(row.primary > 0 && row.primary < 1000, "gpu % out of range: \(row.primary)")
        precondition(!row.name.isEmpty)
    }
    NSLog("gpuProcessesSelfTest OK clients=\(rows.map { "\($0.name):\($0.primary)" })")
}
#endif
