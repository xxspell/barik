import Darwin
import Foundation
import IOKit

enum SystemMonitorMetric: String, CaseIterable {
    case cpu
    case ram
    case disk
    case gpu
    case network

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .ram: "RAM"
        case .disk: "Disk"
        case .gpu: "GPU"
        case .network: "Net"
        }
    }

    var systemImageName: String {
        switch self {
        case .cpu: "cpu"
        case .ram: "memorychip"
        case .disk: "internaldrive"
        case .gpu: "sparkles.tv"
        case .network: "network"
        }
    }
}

@MainActor
final class SystemMonitorManager: ObservableObject {
    static let shared = SystemMonitorManager()

    @Published private(set) var cpuLoad: Double = 0
    @Published private(set) var userLoad: Double = 0
    @Published private(set) var systemLoad: Double = 0
    @Published private(set) var idleLoad: Double = 100

    @Published private(set) var ramUsage: Double = 0
    @Published private(set) var totalRAM: Double = 0
    @Published private(set) var activeRAM: Double = 0
    @Published private(set) var wiredRAM: Double = 0
    @Published private(set) var compressedRAM: Double = 0

    @Published private(set) var diskUsage: Double = 0
    @Published private(set) var totalDisk: Double = 0
    @Published private(set) var usedDisk: Double = 0
    @Published private(set) var freeDisk: Double = 0

    @Published private(set) var gpuLoad: Double?

    @Published private(set) var uploadSpeed: Double = 0
    @Published private(set) var downloadSpeed: Double = 0

    private var timer: Timer?
    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousNetworkData: [String: (ibytes: UInt64, obytes: UInt64)] = [:]
    private var lastNetworkUpdate = Date()

    private init() {
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    private func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            let cpuSnapshot = Self.readCPUUsage(previous: await self.previousCPUTicks)
            let ramSnapshot = Self.readRAMUsage()
            let diskSnapshot = Self.readDiskUsage()
            let gpuLoad = Self.readGPULoad()
            let networkSnapshot = Self.readNetworkActivity(
                previous: await self.previousNetworkData,
                lastUpdate: await self.lastNetworkUpdate
            )

            await MainActor.run {
                if let cpuSnapshot {
                    self.previousCPUTicks = cpuSnapshot.currentTicks
                    self.cpuLoad = cpuSnapshot.cpuLoad
                    self.userLoad = cpuSnapshot.userLoad
                    self.systemLoad = cpuSnapshot.systemLoad
                    self.idleLoad = cpuSnapshot.idleLoad
                }

                if let ramSnapshot {
                    self.ramUsage = ramSnapshot.ramUsage
                    self.totalRAM = ramSnapshot.totalRAM
                    self.activeRAM = ramSnapshot.activeRAM
                    self.wiredRAM = ramSnapshot.wiredRAM
                    self.compressedRAM = ramSnapshot.compressedRAM
                }

                if let diskSnapshot {
                    self.diskUsage = diskSnapshot.diskUsage
                    self.totalDisk = diskSnapshot.totalDisk
                    self.usedDisk = diskSnapshot.usedDisk
                    self.freeDisk = diskSnapshot.freeDisk
                }

                self.gpuLoad = gpuLoad

                if let networkSnapshot {
                    self.previousNetworkData = networkSnapshot.currentNetworkData
                    self.lastNetworkUpdate = networkSnapshot.currentTime
                    self.uploadSpeed = networkSnapshot.uploadSpeed
                    self.downloadSpeed = networkSnapshot.downloadSpeed
                }
            }
        }
    }

    nonisolated private static func readCPUUsage(
        previous: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    ) -> (
        cpuLoad: Double,
        userLoad: Double,
        systemLoad: Double,
        idleLoad: Double,
        currentTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)
    )? {
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        let currentTicks = (
            user: cpuInfo.cpu_ticks.0,
            system: cpuInfo.cpu_ticks.1,
            idle: cpuInfo.cpu_ticks.2,
            nice: cpuInfo.cpu_ticks.3
        )

        guard let previous else {
            return (
                cpuLoad: 0,
                userLoad: 0,
                systemLoad: 0,
                idleLoad: 100,
                currentTicks: currentTicks
            )
        }

        let userDelta = currentTicks.user >= previous.user ? currentTicks.user - previous.user : 0
        let systemDelta = currentTicks.system >= previous.system ? currentTicks.system - previous.system : 0
        let idleDelta = currentTicks.idle >= previous.idle ? currentTicks.idle - previous.idle : 0
        let niceDelta = currentTicks.nice >= previous.nice ? currentTicks.nice - previous.nice : 0
        let totalDelta = userDelta + systemDelta + idleDelta + niceDelta

        guard totalDelta > 0 else {
            return (
                cpuLoad: 0,
                userLoad: 0,
                systemLoad: 0,
                idleLoad: 100,
                currentTicks: currentTicks
            )
        }

        let userPercent = Double(userDelta + niceDelta) / Double(totalDelta) * 100
        let systemPercent = Double(systemDelta) / Double(totalDelta) * 100
        let idlePercent = Double(idleDelta) / Double(totalDelta) * 100

        return (
            cpuLoad: min(100, max(0, userPercent + systemPercent)),
            userLoad: min(100, max(0, userPercent)),
            systemLoad: min(100, max(0, systemPercent)),
            idleLoad: min(100, max(0, idlePercent)),
            currentTicks: currentTicks
        )
    }

    nonisolated private static func readRAMUsage() -> (
        ramUsage: Double,
        totalRAM: Double,
        activeRAM: Double,
        wiredRAM: Double,
        compressedRAM: Double
    )? {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        var totalMemory: UInt64 = 0
        var totalMemorySize = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &totalMemory, &totalMemorySize, nil, 0) == 0 else {
            return nil
        }

        let pageSize = UInt64(vm_page_size)
        let activeBytes = UInt64(vmStats.active_count) * pageSize
        let wiredBytes = UInt64(vmStats.wire_count) * pageSize
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
        let usedBytes = activeBytes + wiredBytes + compressedBytes

        let totalGB = Double(totalMemory) / 1_073_741_824
        let activeGB = Double(activeBytes) / 1_073_741_824
        let wiredGB = Double(wiredBytes) / 1_073_741_824
        let compressedGB = Double(compressedBytes) / 1_073_741_824
        let usedGB = Double(usedBytes) / 1_073_741_824
        let usagePercent = totalGB > 0 ? (usedGB / totalGB) * 100 : 0

        return (
            ramUsage: min(100, max(0, usagePercent)),
            totalRAM: totalGB,
            activeRAM: activeGB,
            wiredRAM: wiredGB,
            compressedRAM: compressedGB
        )
    }

    nonisolated private static func readDiskUsage() -> (
        diskUsage: Double,
        totalDisk: Double,
        usedDisk: Double,
        freeDisk: Double
    )? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let totalBytes = attributes[.systemSize] as? NSNumber,
              let freeBytes = attributes[.systemFreeSize] as? NSNumber else {
            return nil
        }

        let totalGB = totalBytes.doubleValue / 1_073_741_824
        let freeGB = freeBytes.doubleValue / 1_073_741_824
        let usedGB = totalGB - freeGB
        let usagePercent = totalGB > 0 ? (usedGB / totalGB) * 100 : 0

        return (
            diskUsage: min(100, max(0, usagePercent)),
            totalDisk: totalGB,
            usedDisk: usedGB,
            freeDisk: freeGB
        )
    }

    nonisolated private static func readGPULoad() -> Double? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        )

        guard result == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }

            if let stats = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any],
               let usage = stats["Device Utilization %"] as? NSNumber {
                IOObjectRelease(service)
                return min(100, max(0, usage.doubleValue))
            }

            IOObjectRelease(service)
        }

        return nil
    }

    nonisolated private static func readNetworkActivity(
        previous: [String: (ibytes: UInt64, obytes: UInt64)],
        lastUpdate: Date
    ) -> (
        uploadSpeed: Double,
        downloadSpeed: Double,
        currentNetworkData: [String: (ibytes: UInt64, obytes: UInt64)],
        currentTime: Date
    )? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
            return nil
        }

        defer { freeifaddrs(ifaddrPointer) }

        var currentNetworkData: [String: (ibytes: UInt64, obytes: UInt64)] = [:]
        var ptr = firstAddr

        while true {
            let name = String(cString: ptr.pointee.ifa_name)
            if (name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("pdp_ip")),
               let data = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                currentNetworkData[name] = (
                    ibytes: UInt64(data.pointee.ifi_ibytes),
                    obytes: UInt64(data.pointee.ifi_obytes)
                )
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        let currentTime = Date()
        let timeDelta = currentTime.timeIntervalSince(lastUpdate)
        guard timeDelta > 0 else {
            return (
                uploadSpeed: 0,
                downloadSpeed: 0,
                currentNetworkData: currentNetworkData,
                currentTime: currentTime
            )
        }

        var totalUploadDelta: UInt64 = 0
        var totalDownloadDelta: UInt64 = 0

        for (interface, currentValue) in currentNetworkData {
            guard let previousValue = previous[interface] else { continue }
            if currentValue.obytes >= previousValue.obytes {
                totalUploadDelta += currentValue.obytes - previousValue.obytes
            }
            if currentValue.ibytes >= previousValue.ibytes {
                totalDownloadDelta += currentValue.ibytes - previousValue.ibytes
            }
        }

        return (
            uploadSpeed: Double(totalUploadDelta) / timeDelta / 1_048_576,
            downloadSpeed: Double(totalDownloadDelta) / timeDelta / 1_048_576,
            currentNetworkData: currentNetworkData,
            currentTime: currentTime
        )
    }
}
