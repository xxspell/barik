import Darwin
import CoreServices
import Foundation
import IOKit
import OSLog
import SystemConfiguration

private let systemMonitorLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "barik",
    category: "SystemMonitor"
)

private struct TemperatureCandidate {
    let key: String
    let value: Double
    let dataType: String
    let bytesHex: String
}

private struct TemperatureSelection {
    let value: Double
    let source: String
    let suspicious: Bool
    let candidates: [TemperatureCandidate]
}

enum SystemMonitorMetric: String, CaseIterable {
    case cpu
    case temperature
    case ram
    case disk
    case gpu
    case network

    var title: String {
        switch self {
        case .cpu: String(localized: "CPU")
        case .temperature: String(localized: "Temp")
        case .ram: String(localized: "RAM")
        case .disk: String(localized: "Disk")
        case .gpu: String(localized: "GPU")
        case .network: String(localized: "Net")
        }
    }

    var systemImageName: String {
        switch self {
        case .cpu: "cpu"
        case .temperature: "thermometer.medium"
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
    @Published private(set) var loadAverage: Double = 0
    @Published private(set) var cpuCoreCount: Int = 0

    @Published private(set) var ramUsage: Double = 0
    @Published private(set) var totalRAM: Double = 0
    @Published private(set) var usedRAM: Double = 0
    @Published private(set) var activeRAM: Double = 0
    @Published private(set) var inactiveRAM: Double = 0
    @Published private(set) var wiredRAM: Double = 0
    @Published private(set) var compressedRAM: Double = 0
    @Published private(set) var appRAM: Double = 0
    @Published private(set) var cachedRAM: Double = 0
    @Published private(set) var freeRAM: Double = 0
    @Published private(set) var swapUsedRAM: Double = 0
    @Published private(set) var memoryPressure: String = "Normal"

    @Published private(set) var diskUsage: Double = 0
    @Published private(set) var totalDisk: Double = 0
    @Published private(set) var usedDisk: Double = 0
    @Published private(set) var freeDisk: Double = 0
    @Published private(set) var diskVolumeName: String = "/"

    @Published private(set) var gpuLoad: Double?
    @Published private(set) var cpuTemperature: Double?
    @Published private(set) var gpuTemperature: Double?

    @Published private(set) var uploadSpeed: Double = 0
    @Published private(set) var downloadSpeed: Double = 0
    @Published private(set) var totalUploadedBytes: UInt64 = 0
    @Published private(set) var totalDownloadedBytes: UInt64 = 0
    @Published private(set) var activeNetworkInterface: String = ""
    @Published private(set) var networkLinkIsUp: Bool = false

    private var timer: Timer?
    private var previousCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var previousNetworkData: [String: (ibytes: UInt64, obytes: UInt64)] = [:]
    private var lastNetworkUpdate = Date()
    private var lastValidCPUTemperature: Double?

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
            let gpuSnapshot = Self.readGPUStats()
            let rawCPUTemperature = Self.readCPUTemperature()
            let loadAverage = Self.readLoadAverage()
            let cpuCoreCount = Self.readCPUCoreCount()
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
                self.loadAverage = loadAverage
                self.cpuCoreCount = cpuCoreCount

                if let ramSnapshot {
                    self.ramUsage = ramSnapshot.ramUsage
                    self.totalRAM = ramSnapshot.totalRAM
                    self.usedRAM = ramSnapshot.usedRAM
                    self.activeRAM = ramSnapshot.activeRAM
                    self.inactiveRAM = ramSnapshot.inactiveRAM
                    self.wiredRAM = ramSnapshot.wiredRAM
                    self.compressedRAM = ramSnapshot.compressedRAM
                    self.appRAM = ramSnapshot.appRAM
                    self.cachedRAM = ramSnapshot.cachedRAM
                    self.freeRAM = ramSnapshot.freeRAM
                    self.swapUsedRAM = ramSnapshot.swapUsedRAM
                    self.memoryPressure = ramSnapshot.memoryPressure
                }

                if let diskSnapshot {
                    self.diskUsage = diskSnapshot.diskUsage
                    self.totalDisk = diskSnapshot.totalDisk
                    self.usedDisk = diskSnapshot.usedDisk
                    self.freeDisk = diskSnapshot.freeDisk
                    self.diskVolumeName = diskSnapshot.diskVolumeName
                }

                self.gpuLoad = gpuSnapshot.load
                self.gpuTemperature = gpuSnapshot.temperature
                let resolvedCPUTemperature = Self.stabilizedCPUTemperature(
                    rawCPUTemperature,
                    previousValid: self.lastValidCPUTemperature
                )
                self.cpuTemperature = resolvedCPUTemperature
                if let resolvedCPUTemperature {
                    self.lastValidCPUTemperature = resolvedCPUTemperature
                }

                if let networkSnapshot {
                    self.previousNetworkData = networkSnapshot.currentNetworkData
                    self.lastNetworkUpdate = networkSnapshot.currentTime
                    self.uploadSpeed = networkSnapshot.uploadSpeed
                    self.downloadSpeed = networkSnapshot.downloadSpeed
                    self.totalUploadedBytes = networkSnapshot.totalUploadedBytes
                    self.totalDownloadedBytes = networkSnapshot.totalDownloadedBytes
                    self.activeNetworkInterface = networkSnapshot.activeInterface
                    self.networkLinkIsUp = networkSnapshot.linkIsUp
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
        usedRAM: Double,
        activeRAM: Double,
        inactiveRAM: Double,
        wiredRAM: Double,
        compressedRAM: Double,
        appRAM: Double,
        cachedRAM: Double,
        freeRAM: Double,
        swapUsedRAM: Double,
        memoryPressure: String
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
        let inactiveBytes = UInt64(vmStats.inactive_count) * pageSize
        let speculativeBytes = UInt64(vmStats.speculative_count) * pageSize
        let wiredBytes = UInt64(vmStats.wire_count) * pageSize
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
        let purgeableBytes = UInt64(vmStats.purgeable_count) * pageSize
        let externalBytes = UInt64(vmStats.external_page_count) * pageSize
        let usedBytes = activeBytes + inactiveBytes + speculativeBytes + wiredBytes + compressedBytes
            - min(purgeableBytes + externalBytes, activeBytes + inactiveBytes + speculativeBytes + wiredBytes + compressedBytes)
        let freeBytes = totalMemory > usedBytes ? totalMemory - usedBytes : 0
        let appBytes = usedBytes > (wiredBytes + compressedBytes) ? usedBytes - wiredBytes - compressedBytes : 0
        let cachedBytes = purgeableBytes + externalBytes

        var pressureLevel: Int32 = 0
        var pressureLevelSize = MemoryLayout<Int32>.size
        _ = sysctlbyname(
            "kern.memorystatus_vm_pressure_level",
            &pressureLevel,
            &pressureLevelSize,
            nil,
            0
        )

        var swapUsage = xsw_usage()
        var swapUsageSize = MemoryLayout<xsw_usage>.size
        _ = sysctlbyname("vm.swapusage", &swapUsage, &swapUsageSize, nil, 0)

        let totalGB = Double(totalMemory) / 1_073_741_824
        let activeGB = Double(activeBytes) / 1_073_741_824
        let inactiveGB = Double(inactiveBytes) / 1_073_741_824
        let wiredGB = Double(wiredBytes) / 1_073_741_824
        let compressedGB = Double(compressedBytes) / 1_073_741_824
        let appGB = Double(appBytes) / 1_073_741_824
        let cachedGB = Double(cachedBytes) / 1_073_741_824
        let freeGB = Double(freeBytes) / 1_073_741_824
        let swapUsedGB = Double(swapUsage.xsu_used) / 1_073_741_824
        let usedGB = Double(usedBytes) / 1_073_741_824
        let usagePercent = totalGB > 0 ? (usedGB / totalGB) * 100 : 0
        let pressure: String
        switch pressureLevel {
        case 4:
            pressure = "Critical"
        case 2:
            pressure = "Warning"
        default:
            pressure = "Normal"
        }

        return (
            ramUsage: min(100, max(0, usagePercent)),
            totalRAM: totalGB,
            usedRAM: usedGB,
            activeRAM: activeGB,
            inactiveRAM: inactiveGB,
            wiredRAM: wiredGB,
            compressedRAM: compressedGB,
            appRAM: appGB,
            cachedRAM: cachedGB,
            freeRAM: freeGB,
            swapUsedRAM: swapUsedGB,
            memoryPressure: pressure
        )
    }

    nonisolated private static func readDiskUsage() -> (
        diskUsage: Double,
        totalDisk: Double,
        usedDisk: Double,
        freeDisk: Double,
        diskVolumeName: String
    )? {
        let volumeURL = URL(fileURLWithPath: "/")

        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: volumeURL.path),
              let totalBytes = attributes[.systemSize] as? NSNumber,
              let systemFreeBytes = attributes[.systemFreeSize] as? NSNumber else {
            return nil
        }

        let resourceValues = try? volumeURL.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        let freeBytes = recoverableFreeDiskSpace(at: volumeURL)
            ?? resourceValues?.volumeAvailableCapacityForImportantUsage
            ?? Int64(systemFreeBytes.int64Value)

        let totalGB = totalBytes.doubleValue / 1_073_741_824
        let freeGB = Double(freeBytes) / 1_073_741_824
        let usedGB = totalGB - freeGB
        let usagePercent = totalGB > 0 ? (usedGB / totalGB) * 100 : 0

        return (
            diskUsage: min(100, max(0, usagePercent)),
            totalDisk: totalGB,
            usedDisk: usedGB,
            freeDisk: freeGB,
            diskVolumeName: resourceValues?.volumeName ?? "/"
        )
    }

    nonisolated private static func recoverableFreeDiskSpace(at volumeURL: URL) -> Int64? {
        var stats = statfs()
        guard statfs(volumeURL.path, &stats) == 0 else {
            return nil
        }

        let purgeable = Int64(CSDiskSpaceGetRecoveryEstimate(volumeURL as NSURL))
        return (Int64(stats.f_bfree) * Int64(stats.f_bsize)) + max(0, purgeable)
    }

    nonisolated private static func readGPUStats() -> (load: Double?, temperature: Double?) {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        )

        guard result == KERN_SUCCESS else {
            return (nil, fallbackGPUTemperature())
        }
        defer { IOObjectRelease(iterator) }

        var load: Double?
        var temperature: Double?

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }

            if let stats = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] {
                if let usage = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
                    load = min(100, max(0, usage))
                } else if let usage = (stats["GPU Activity(%)"] as? NSNumber)?.doubleValue {
                    load = min(100, max(0, usage))
                }

                if let value = (stats["Temperature(C)"] as? NSNumber)?.doubleValue,
                   isPlausibleTemperature(value) {
                    temperature = value
                }
            }

            IOObjectRelease(service)
        }

        return (load, temperature ?? fallbackGPUTemperature())
    }

    nonisolated private static func fallbackGPUTemperature() -> Double? {
        if let value = SMCReader.shared.readValue(for: "TGDD"), isPlausibleTemperature(value) {
            return value
        }
        if let value = SMCReader.shared.readValue(for: "TCGC"), isPlausibleTemperature(value) {
            return value
        }
        return nil
    }

    nonisolated private static func readCPUTemperature() -> Double? {
        let isAppleSilicon = looksLikeAppleSilicon()
        let directCandidates = readTemperatureCandidates(keys: ["TC0D", "TC0E", "TC0F", "TC0P", "TC0H"])
        let appleCandidates = readTemperatureCandidates(keys: appleSiliconCPUTemperatureKeys())

        let selection: TemperatureSelection?
        if isAppleSilicon {
            selection = selectAppleSiliconCPUTemperature(
                appleCandidates: appleCandidates,
                directCandidates: directCandidates
            )
        } else if let directValue = directCandidates.first?.value {
            selection = TemperatureSelection(
                value: directValue,
                source: "direct-first",
                suspicious: false,
                candidates: directCandidates
            )
        } else if let fallbackValue = robustTemperatureAverage(appleCandidates) {
            selection = TemperatureSelection(
                value: fallbackValue,
                source: "apple-fallback",
                suspicious: false,
                candidates: appleCandidates
            )
        } else {
            selection = nil
        }

        logCPUTemperatureSelection(
            isAppleSilicon: isAppleSilicon,
            selection: selection,
            appleCandidates: appleCandidates,
            directCandidates: directCandidates
        )

        return selection?.value
    }

    nonisolated private static func appleSiliconCPUTemperatureKeys() -> [String] {
        let chipName = systemChipName()

        if chipName.contains("M4") {
            return ["Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        }
        if chipName.contains("M3") {
            return ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        }
        if chipName.contains("M2") {
            return ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        }
        if chipName.contains("M1") {
            return ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        }

        return [
            "TC0D", "TC0E", "TC0F", "TC0P", "TC0H",
            "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
            "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",
            "Te05", "Te09", "Te0H", "Te0L", "Te0P", "Te0S", "Tp0V", "Tp0Y", "Tp0e",
            "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"
        ]
    }

    nonisolated private static func systemChipName() -> String {
        sysctlString("machdep.cpu.brand_string")
            ?? sysctlString("hw.model")
            ?? ""
    }

    nonisolated private static func looksLikeAppleSilicon() -> Bool {
        let chipName = systemChipName().uppercased()
        return chipName.contains("APPLE") || chipName.contains("M1") || chipName.contains("M2")
            || chipName.contains("M3") || chipName.contains("M4")
    }

    nonisolated private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    nonisolated private static func isPlausibleTemperature(_ value: Double) -> Bool {
        value >= 0 && value < 120
    }

    nonisolated private static func readTemperatureCandidates(keys: [String]) -> [TemperatureCandidate] {
        keys.compactMap { key in
            guard let sample = SMCReader.shared.readSample(for: key),
                  let value = sample.decodedValue,
                  isPlausibleTemperature(value) else {
                return nil
            }

            return TemperatureCandidate(
                key: key,
                value: value,
                dataType: sample.dataType,
                bytesHex: sample.bytesHex
            )
        }
    }

    nonisolated private static func selectAppleSiliconCPUTemperature(
        appleCandidates: [TemperatureCandidate],
        directCandidates: [TemperatureCandidate]
    ) -> TemperatureSelection? {
        let filteredAppleCandidates = filteredAppleSiliconCPUCandidates(appleCandidates)

        if let appleValue = robustTemperatureAverage(filteredAppleCandidates) {
            let directMax = directCandidates.map(\.value).max()
            let suspicious = appleValue < 30 && (directMax.map { $0 - appleValue > 15 } ?? false)

            if suspicious, let directMax {
                return TemperatureSelection(
                    value: directMax,
                    source: "direct-max-fallback",
                    suspicious: true,
                    candidates: directCandidates
                )
            }

            return TemperatureSelection(
                value: appleValue,
                source: "apple-robust-average",
                suspicious: false,
                candidates: filteredAppleCandidates
            )
        }

        if let directMax = directCandidates.map(\.value).max() {
            return TemperatureSelection(
                value: directMax,
                source: "direct-max",
                suspicious: false,
                candidates: directCandidates
            )
        }

        return nil
    }

    nonisolated private static func robustTemperatureAverage(_ candidates: [TemperatureCandidate]) -> Double? {
        guard !candidates.isEmpty else { return nil }

        let sorted = candidates.map(\.value).sorted()
        let median = sorted[sorted.count / 2]
        let filtered = candidates.map(\.value).filter { abs($0 - median) <= 15 }
        let values = filtered.isEmpty ? sorted : filtered

        return values.reduce(0, +) / Double(values.count)
    }

    nonisolated private static func filteredAppleSiliconCPUCandidates(
        _ candidates: [TemperatureCandidate]
    ) -> [TemperatureCandidate] {
        guard !candidates.isEmpty else { return [] }

        let hasWarmCandidate = candidates.contains(where: { $0.value >= 20 })
        guard hasWarmCandidate else { return candidates }

        let filtered = candidates.filter { $0.value >= 10 }
        if filtered.count != candidates.count {
            systemMonitorLogger.debug(
                "CPU temp dropping low Apple Silicon candidates: [\(formatTemperatureCandidates(candidates), privacy: .public)] -> [\(formatTemperatureCandidates(filtered), privacy: .public)]"
            )
        }

        return filtered.isEmpty ? candidates : filtered
    }

    nonisolated private static func stabilizedCPUTemperature(
        _ value: Double?,
        previousValid: Double?
    ) -> Double? {
        guard let value else { return previousValid }

        if value < 10, let previousValid {
            systemMonitorLogger.debug(
                "CPU temp rejected implausible reading=\(value, privacy: .public); keeping previous=\(previousValid, privacy: .public)"
            )
            return previousValid
        }

        return value
    }

    nonisolated private static func logCPUTemperatureSelection(
        isAppleSilicon: Bool,
        selection: TemperatureSelection?,
        appleCandidates: [TemperatureCandidate],
        directCandidates: [TemperatureCandidate]
    ) {
        if let selection, selection.suspicious {
            systemMonitorLogger.debug(
                """
                CPU temp suspicious. selected=\(selection.value, privacy: .public) source=\(selection.source, privacy: .public) \
                chip=\(systemChipName(), privacy: .public) \
                apple=[\(formatTemperatureCandidates(appleCandidates), privacy: .public)] \
                direct=[\(formatTemperatureCandidates(directCandidates), privacy: .public)]
                """
            )
            return
        }

        let chosenValue = selection?.value ?? -1
        if chosenValue < 25 || selection == nil {
            systemMonitorLogger.debug(
                """
                CPU temp debug. selected=\(chosenValue, privacy: .public) source=\(selection?.source ?? "none", privacy: .public) \
                appleSilicon=\(isAppleSilicon, privacy: .public) chip=\(systemChipName(), privacy: .public) \
                apple=[\(formatTemperatureCandidates(appleCandidates), privacy: .public)] \
                direct=[\(formatTemperatureCandidates(directCandidates), privacy: .public)]
                """
            )
        }
    }

    nonisolated private static func formatTemperatureCandidates(_ candidates: [TemperatureCandidate]) -> String {
        candidates
            .map { candidate in
                "\(candidate.key)=\(String(format: "%.1f", candidate.value))(\(candidate.dataType) \(candidate.bytesHex))"
            }
            .joined(separator: ", ")
    }

    nonisolated private static func readLoadAverage() -> Double {
        var loadAverages = [Double](repeating: 0, count: 3)
        guard getloadavg(&loadAverages, 3) > 0 else { return 0 }
        return loadAverages[0]
    }

    nonisolated private static func readCPUCoreCount() -> Int {
        var coreCount: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        guard sysctlbyname("hw.logicalcpu", &coreCount, &size, nil, 0) == 0 else {
            return 0
        }
        return Int(coreCount)
    }

    nonisolated private static func readNetworkActivity(
        previous: [String: (ibytes: UInt64, obytes: UInt64)],
        lastUpdate: Date
    ) -> (
        uploadSpeed: Double,
        downloadSpeed: Double,
        totalUploadedBytes: UInt64,
        totalDownloadedBytes: UInt64,
        activeInterface: String,
        linkIsUp: Bool,
        currentNetworkData: [String: (ibytes: UInt64, obytes: UInt64)],
        currentTime: Date
    )? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
            return nil
        }

        defer { freeifaddrs(ifaddrPointer) }

        var currentNetworkData: [String: (ibytes: UInt64, obytes: UInt64)] = [:]
        let preferredInterface = primaryNetworkInterface()
        var fallbackInterface: String?
        var activeInterface = preferredInterface
        var linkIsUp = false
        var ptr = firstAddr

        while true {
            let name = String(cString: ptr.pointee.ifa_name)
            if (name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("pdp_ip")),
               let data = ptr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                fallbackInterface = fallbackInterface ?? name
                currentNetworkData[name] = (
                    ibytes: UInt64(data.pointee.ifi_ibytes),
                    obytes: UInt64(data.pointee.ifi_obytes)
                )

                if preferredInterface.isEmpty, activeInterface.isEmpty {
                    activeInterface = name
                }
                if name == activeInterface {
                    linkIsUp = (ptr.pointee.ifa_flags & UInt32(IFF_UP)) != 0
                }
            }

            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        if activeInterface.isEmpty, let fallbackInterface {
            activeInterface = fallbackInterface
        }

        let currentTime = Date()
        let timeDelta = currentTime.timeIntervalSince(lastUpdate)
        let selectedData = activeInterface.isEmpty ? nil : currentNetworkData[activeInterface]
        let previousSelectedData = activeInterface.isEmpty ? nil : previous[activeInterface]

        let aggregateUploadedBytes = currentNetworkData.values.reduce(0) { $0 + $1.obytes }
        let aggregateDownloadedBytes = currentNetworkData.values.reduce(0) { $0 + $1.ibytes }
        let totalUploadedBytes = selectedData?.obytes ?? aggregateUploadedBytes
        let totalDownloadedBytes = selectedData?.ibytes ?? aggregateDownloadedBytes
        guard timeDelta > 0 else {
            return (
                uploadSpeed: 0,
                downloadSpeed: 0,
                totalUploadedBytes: totalUploadedBytes,
                totalDownloadedBytes: totalDownloadedBytes,
                activeInterface: activeInterface,
                linkIsUp: linkIsUp,
                currentNetworkData: currentNetworkData,
                currentTime: currentTime
            )
        }

        var totalUploadDelta: UInt64 = 0
        var totalDownloadDelta: UInt64 = 0

        if let selectedData, let previousSelectedData {
            if selectedData.obytes >= previousSelectedData.obytes {
                totalUploadDelta = selectedData.obytes - previousSelectedData.obytes
            }
            if selectedData.ibytes >= previousSelectedData.ibytes {
                totalDownloadDelta = selectedData.ibytes - previousSelectedData.ibytes
            }
        }

        if totalUploadDelta == 0 && totalDownloadDelta == 0 {
            for (interface, currentValue) in currentNetworkData {
                guard let previousValue = previous[interface] else { continue }
                if currentValue.obytes >= previousValue.obytes {
                    totalUploadDelta += currentValue.obytes - previousValue.obytes
                }
                if currentValue.ibytes >= previousValue.ibytes {
                    totalDownloadDelta += currentValue.ibytes - previousValue.ibytes
                }
            }

            if activeInterface.isEmpty && !currentNetworkData.isEmpty {
                systemMonitorLogger.debug("Network primary interface missing. Falling back to aggregate counters.")
            }
        }

        return (
            uploadSpeed: Double(totalUploadDelta) / timeDelta / 1_048_576,
            downloadSpeed: Double(totalDownloadDelta) / timeDelta / 1_048_576,
            totalUploadedBytes: totalUploadedBytes,
            totalDownloadedBytes: totalDownloadedBytes,
            activeInterface: activeInterface,
            linkIsUp: linkIsUp,
            currentNetworkData: currentNetworkData,
            currentTime: currentTime
        )
    }

    nonisolated private static func primaryNetworkInterface() -> String {
        guard let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString)
            as? [String: Any],
            let interface = global["PrimaryInterface"] as? String else {
            return ""
        }
        return interface
    }
}
