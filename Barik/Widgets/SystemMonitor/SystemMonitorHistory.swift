import Foundation

/// A single tick of dashboard-relevant metrics, sampled at the base interval.
struct SystemMonitorSample: Equatable {
    var cpuLoad: Double = 0
    var userLoad: Double = 0
    var systemLoad: Double = 0
    var gpuDevice: Double = 0
    var gpuRenderer: Double = 0
    var gpuTiler: Double = 0
    var fps: Double = 0
    var ramUsage: Double = 0
    var appRAM: Double = 0
    var wiredRAM: Double = 0
    var compressedRAM: Double = 0
    var cachedRAM: Double = 0
    var diskReadBps: Double = 0
    var diskWriteBps: Double = 0
    var downloadBps: Double = 0
    var uploadBps: Double = 0
}

/// Fixed-capacity ring buffer of system monitor samples, oldest→newest.
/// Appends are O(1); `series` returns a left-padded window so charts can be
/// laid out against a fixed time span from the first open of the popup.
struct SystemMonitorHistory {
    private struct Slot {
        var sample: SystemMonitorSample
        var date: Date
    }

    let capacity: Int
    private var slots: [Slot] = []
    private var head = 0
    private(set) var count = 0

    init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
        slots.reserveCapacity(self.capacity)
    }

    mutating func append(_ sample: SystemMonitorSample, at date: Date) {
        if count < capacity {
            slots.append(Slot(sample: sample, date: date))
            count += 1
        } else {
            slots[head] = Slot(sample: sample, date: date)
            head = (head + 1) % capacity
        }
    }

    /// Oldest→newest values for one metric, left-padded with zeros to `capacity`.
    func series(_ keyPath: KeyPath<SystemMonitorSample, Double>) -> [Double] {
        var values = Array(repeating: 0.0, count: capacity)
        let offset = capacity - count
        for index in 0..<count {
            let slot = slots[(head + index) % slots.count]
            values[offset + index] = slot.sample[keyPath: keyPath]
        }
        return values
    }

    /// Only the timestamps that carry data, oldest→newest.
    func timestamps() -> [Date] {
        (0..<count).map { slots[(head + $0) % slots.count].date }
    }

    var latestSample: SystemMonitorSample? {
        guard count > 0 else { return nil }
        return slots[(head + count - 1) % slots.count].sample
    }

    /// A copy with a new capacity that keeps the newest samples (oldest are
    /// dropped when shrinking), so changing the history length never blanks charts.
    func resized(to newCapacity: Int) -> SystemMonitorHistory {
        var copy = SystemMonitorHistory(capacity: newCapacity)
        let keep = min(count, copy.capacity)
        for index in (count - keep)..<count {
            let slot = slots[(head + index) % slots.count]
            copy.append(slot.sample, at: slot.date)
        }
        return copy
    }
}
