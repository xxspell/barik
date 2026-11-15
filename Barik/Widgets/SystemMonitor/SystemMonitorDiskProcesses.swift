import Darwin
import Foundation

/// Cumulative per-process disk counters kept between sampler calls so each
/// call yields bytes/sec instead of bytes-since-launch.
struct DiskProcessState {
    var previous: [Int: (read: UInt64, written: UInt64)] = [:]
    var at = Date()
}

/// Per-process disk read/write rates from `proc_pid_rusage` (no child process).
/// Rows: `primary` = read bytes/s, `secondary` = write bytes/s.
enum DiskProcessSampler {
    /// First call (nil state) seeds the counters and returns [].
    static func diskProcesses(limit: Int, previous: inout DiskProcessState?) -> [TopProcess] {
        guard limit > 0 else { return [] }
        let now = Date()
        var current: [Int: (read: UInt64, written: UInt64)] = [:]

        for pid in allPIDs() where pid > 0 {
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard result == 0 else { continue } // other users' processes are not readable
            current[Int(pid)] = (info.ri_diskio_bytesread, info.ri_diskio_byteswritten)
        }

        defer { previous = DiskProcessState(previous: current, at: now) }
        guard let state = previous else { return [] }
        let interval = now.timeIntervalSince(state.at)
        guard interval >= 0.5 else { return [] }

        return current.compactMap { pid, counters -> TopProcess? in
            guard let old = state.previous[pid],
                  counters.read >= old.read, counters.written >= old.written else { return nil }
            let read = Double(counters.read - old.read) / interval
            let written = Double(counters.written - old.written) / interval
            guard read + written > 0 else { return nil }
            let resolved = ProcessSampler.displayName(pid: pid, command: processName(pid: pid_t(pid)))
            return TopProcess(pid: pid, name: resolved.name, icon: resolved.icon, primary: read, secondary: written)
        }
        .sorted { ($0.primary + ($0.secondary ?? 0)) > ($1.primary + ($1.secondary ?? 0)) }
        .prefix(limit)
        .map { $0 }
    }

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    private static func processName(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "pid \(pid)" }
        return String(cString: buffer)
    }
}
