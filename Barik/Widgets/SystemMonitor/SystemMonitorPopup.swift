import OSLog
import SwiftUI

private enum SystemMonitorCPUDetail: String, CaseIterable {
    case usage
    case user
    case system
    case idle
    case temperature
    case cores
    case loadAverage = "load-average"

    var title: String {
        switch self {
        case .usage: String(localized: "Usage")
        case .user: String(localized: "User")
        case .system: String(localized: "System")
        case .idle: String(localized: "Idle")
        case .temperature: String(localized: "Temperature")
        case .cores: String(localized: "Cores")
        case .loadAverage: String(localized: "Load Avg")
        }
    }
}

private enum SystemMonitorTemperatureDetail: String, CaseIterable {
    case cpu
    case gpu

    var title: String {
        rawValue.uppercased()
    }
}

private enum SystemMonitorRAMDetail: String, CaseIterable {
    case used
    case app
    case active
    case inactive
    case wired
    case compressed
    case cache
    case free
    case swap
    case pressure
    case total

    var title: String {
        switch self {
        case .used: String(localized: "Used")
        case .app: String(localized: "App")
        case .active: String(localized: "Active")
        case .inactive: String(localized: "Inactive")
        case .wired: String(localized: "Wired")
        case .compressed: String(localized: "Compressed")
        case .cache: String(localized: "Cache")
        case .free: String(localized: "Free")
        case .swap: String(localized: "Swap")
        case .pressure: String(localized: "Pressure")
        case .total: String(localized: "Total")
        }
    }
}

private enum SystemMonitorDiskDetail: String, CaseIterable {
    case volume
    case used
    case free
    case total

    var title: String {
        switch self {
        case .volume: String(localized: "Volume")
        case .used: String(localized: "Used")
        case .free: String(localized: "Free")
        case .total: String(localized: "Total")
        }
    }
}

private enum SystemMonitorGPUDetail: String, CaseIterable {
    case utilization
    case temperature

    var title: String {
        switch self {
        case .utilization: String(localized: "Utilization")
        case .temperature: String(localized: "Temperature")
        }
    }
}

private enum SystemMonitorNetworkDetail: String, CaseIterable {
    case interfaceName = "interface"
    case status
    case download
    case upload
    case totalDownloaded = "total-downloaded"
    case totalUploaded = "total-uploaded"

    var title: String {
        switch self {
        case .interfaceName: String(localized: "Interface")
        case .status: String(localized: "Status")
        case .download: String(localized: "Download")
        case .upload: String(localized: "Upload")
        case .totalDownloaded: String(localized: "Downloaded")
        case .totalUploaded: String(localized: "Uploaded")
        }
    }
}

private struct SystemMonitorDetailItem: Identifiable {
    let title: String
    let value: String

    var id: String { "\(title):\(value)" }
}

struct SystemMonitorPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider

    var body: some View {
        MenuBarPopupVariantView(
            selectedVariant: .vertical,
            settingsLinkSection: .systemMonitor,
            vertical: {
                SystemMonitorDetailsPopup()
                    .environmentObject(configProvider)
            }
        )
    }
}

private struct SystemMonitorDetailsPopup: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "SystemMonitorPopup"
    )

    private let popupWidth: CGFloat = 416
    private let popupHeight: CGFloat = 404
    private let popupHorizontalPadding: CGFloat = 12
    private let compactRowSpacing: CGFloat = 8

    @State private var popupMetrics: [SystemMonitorMetric] = [.cpu, .temperature, .ram, .disk, .gpu, .network]
    @State private var cpuDetails: [SystemMonitorCPUDetail] = [.usage, .temperature, .loadAverage, .cores]
    @State private var temperatureDetails: [SystemMonitorTemperatureDetail] = [.cpu, .gpu]
    @State private var ramDetails: [SystemMonitorRAMDetail] = [.used, .app, .free, .pressure]
    @State private var diskDetails: [SystemMonitorDiskDetail] = [.used, .free, .total]
    @State private var gpuDetails: [SystemMonitorGPUDetail] = [.utilization, .temperature]
    @State private var networkDetails: [SystemMonitorNetworkDetail] = [.status, .download, .upload, .interfaceName]
    @State private var temperatureWarningLevel = 80
    @State private var temperatureCriticalLevel = 95

    private var contentWidth: CGFloat { popupWidth - popupHorizontalPadding * 2 }
    private var compactMetricWidth: CGFloat {
        floor((contentWidth - compactRowSpacing) / 2)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 9) {
                header

                ForEach(Array(metricRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: compactRowSpacing) {
                        ForEach(row, id: \.rawValue) { metric in
                            metricCard(for: metric)
                                .frame(width: row.count == 1 ? nil : compactMetricWidth, alignment: .topLeading)
                                .frame(maxWidth: row.count == 1 ? .infinity : compactMetricWidth, alignment: .topLeading)
                        }
                        if row.count == 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(.horizontal, popupHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .frame(width: popupWidth, height: popupHeight)
        .background(Color.black)
        .onAppear(perform: reloadFromConfig)
        .onReceive(configManager.$config) { _ in
            reloadFromConfig()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.07))

                Image(systemName: "menubar.dock.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "System Monitor"))
                    .font(.system(size: 15, weight: .semibold))
            }

            Spacer(minLength: 10)

            HStack(spacing: 6) {
                if !systemMonitor.activeNetworkInterface.isEmpty {
                    headerBadge(title: systemMonitor.activeNetworkInterface)
                }
                if let temperature = systemMonitor.cpuTemperature {
                    headerBadge(title: temperatureString(temperature))
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private func headerBadge(title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
    }

    private var metricRows: [[SystemMonitorMetric]] {
        var rows: [[SystemMonitorMetric]] = []
        var index = 0

        while index < popupMetrics.count {
            let metric = popupMetrics[index]
            if isCompact(metric),
               index + 1 < popupMetrics.count,
               isCompact(popupMetrics[index + 1]) {
                rows.append([metric, popupMetrics[index + 1]])
                index += 2
            } else {
                rows.append([metric])
                index += 1
            }
        }

        return rows
    }

    private func isCompact(_ metric: SystemMonitorMetric) -> Bool {
        switch metric {
        case .temperature, .network:
            true
        case .cpu, .ram, .disk, .gpu:
            false
        }
    }

    @ViewBuilder
    private func metricCard(for metric: SystemMonitorMetric) -> some View {
        switch metric {
        case .cpu:
            metricSection(
                title: String(localized: "CPU Usage"),
                systemImage: "cpu.fill",
                headline: "\(Int(systemMonitor.cpuLoad))%",
                accent: cpuColor,
                progressValue: systemMonitor.cpuLoad,
                subtitle: "\(String(localized: "User")) \(Int(systemMonitor.userLoad))% • \(String(localized: "System")) \(Int(systemMonitor.systemLoad))%"
            ) {
                detailGrid(detailItems(cpuDetails.compactMap { detail in
                    cpuDetailValue(for: detail).map { SystemMonitorDetailItem(title: detail.title, value: $0) }
                }))
            }
        case .temperature:
            if let cpuTemperature = systemMonitor.cpuTemperature {
                metricSection(
                    title: String(localized: "Temperature"),
                    systemImage: "thermometer.medium",
                    headline: temperatureString(cpuTemperature),
                    accent: temperatureColor,
                    progressValue: temperatureProgress(cpuTemperature),
                    subtitle: String(localized: "CPU thermal sensors")
                ) {
                    detailGrid(detailItems(temperatureDetails.compactMap { detail in
                        temperatureDetailValue(for: detail).map { SystemMonitorDetailItem(title: detail.title, value: $0) }
                    }))
                }
            } else {
                unavailableCard(
                    title: String(localized: "Temperature"),
                    systemImage: "thermometer.medium",
                    description: String(localized: "Unavailable on this system")
                )
            }
        case .ram:
            metricSection(
                title: String(localized: "Memory Usage"),
                systemImage: "memorychip.fill",
                headline: "\(Int(systemMonitor.ramUsage))%",
                accent: ramColor,
                progressValue: systemMonitor.ramUsage,
                subtitle: "\(usedRAMString) / \(totalRAMString)"
            ) {
                detailGrid(detailItems(ramDetails.compactMap { detail in
                    ramDetailValue(for: detail).map { SystemMonitorDetailItem(title: detail.title, value: $0) }
                }))
            }
        case .disk:
            metricSection(
                title: String(localized: "Disk Usage"),
                systemImage: "internaldrive.fill",
                headline: "\(Int(systemMonitor.diskUsage))%",
                accent: diskColor,
                progressValue: systemMonitor.diskUsage,
                subtitle: systemMonitor.diskVolumeName
            ) {
                detailGrid(detailItems(diskDetails.compactMap { detail in
                    diskDetailValue(for: detail).map { SystemMonitorDetailItem(title: detail.title, value: $0) }
                }))
            }
        case .gpu:
            if let gpuLoad = systemMonitor.gpuLoad {
                metricSection(
                    title: String(localized: "GPU Usage"),
                    systemImage: "sparkles.tv.fill",
                    headline: "\(Int(gpuLoad))%",
                    accent: gpuColor,
                    progressValue: gpuLoad,
                    subtitle: systemMonitor.gpuTemperature.map(temperatureString) ?? String(localized: "Graphics load")
                ) {
                    detailGrid(detailItems(gpuDetails.compactMap { detail in
                        gpuDetailValue(for: detail).map { SystemMonitorDetailItem(title: detail.title, value: $0) }
                    }))
                }
            } else {
                unavailableCard(
                    title: String(localized: "GPU Usage"),
                    systemImage: "sparkles.tv.fill",
                    description: String(localized: "Unavailable on this system")
                )
            }
        case .network:
            networkMetricSection {
                detailGrid(detailItems(networkDetails.compactMap { detail in
                    networkDetailValue(for: detail).map { SystemMonitorDetailItem(title: detail.title, value: $0) }
                }))
            }
        }
    }

    private func metricSection<Content: View>(
        title: String,
        systemImage: String,
        headline: String,
        accent: Color,
        progressValue: Double?,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: title,
                systemImage: systemImage,
                headline: headline,
                accent: accent
            )

            if let progressValue {
                progressBar(progressValue, accent: accent)
            }

            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.055), lineWidth: 1)
                )
        )
    }

    private func networkMetricSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 14, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Network Activity"))
                        .font(.system(size: 12, weight: .semibold))

                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        networkSpeedBlock(
                            icon: "arrow.down",
                            value: speedString(systemMonitor.downloadSpeed),
                            color: .cyan
                        )
                        networkSpeedBlock(
                            icon: "arrow.up",
                            value: speedString(systemMonitor.uploadSpeed),
                            color: .green
                        )
                    }
                }

                Spacer(minLength: 6)
            }

            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.055), lineWidth: 1)
                )
        )
    }

    private func networkSpeedBlock(icon: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(
        title: String,
        systemImage: String,
        headline: String,
        accent: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 14, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(headline)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 6)
        }
    }

    private func progressBar(_ progressValue: Double, accent: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.72), accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * min(progressValue, 100) / 100)
            }
        }
        .frame(height: 6)
    }

    private func unavailableCard(title: String, systemImage: String, description: String) -> some View {
        metricSection(
            title: title,
            systemImage: systemImage,
            headline: "--",
            accent: .white.opacity(0.7),
            progressValue: nil,
            subtitle: description
        ) {
            Text(description)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private func detailGrid(_ items: [SystemMonitorDetailItem]) -> some View {
        let columns = [
            GridItem(.flexible(minimum: 112), spacing: 10),
            GridItem(.flexible(minimum: 112), spacing: 10)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                detailRow(item)
            }
        }
    }

    private func detailRow(_ item: SystemMonitorDetailItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .layoutPriority(1)
        }
        .padding(.vertical, 2)
    }

    private func detailItems(_ items: [SystemMonitorDetailItem]) -> [SystemMonitorDetailItem] {
        items
    }

    private func cpuDetailValue(for detail: SystemMonitorCPUDetail) -> String? {
        switch detail {
        case .usage:
            "\(Int(systemMonitor.cpuLoad))%"
        case .user:
            "\(Int(systemMonitor.userLoad))%"
        case .system:
            "\(Int(systemMonitor.systemLoad))%"
        case .idle:
            "\(Int(systemMonitor.idleLoad))%"
        case .temperature:
            systemMonitor.cpuTemperature.map(temperatureString)
        case .cores:
            systemMonitor.cpuCoreCount > 0 ? "\(systemMonitor.cpuCoreCount)" : nil
        case .loadAverage:
            String(format: "%.2f", systemMonitor.loadAverage)
        }
    }

    private func temperatureDetailValue(for detail: SystemMonitorTemperatureDetail) -> String? {
        switch detail {
        case .cpu:
            systemMonitor.cpuTemperature.map(temperatureString)
        case .gpu:
            systemMonitor.gpuTemperature.map(temperatureString)
        }
    }

    private func ramDetailValue(for detail: SystemMonitorRAMDetail) -> String? {
        switch detail {
        case .used:
            "\(usedRAMString) / \(totalRAMString)"
        case .app:
            gbString(systemMonitor.appRAM)
        case .active:
            gbString(systemMonitor.activeRAM)
        case .inactive:
            gbString(systemMonitor.inactiveRAM)
        case .wired:
            gbString(systemMonitor.wiredRAM)
        case .compressed:
            gbString(systemMonitor.compressedRAM)
        case .cache:
            gbString(systemMonitor.cachedRAM)
        case .free:
            gbString(systemMonitor.freeRAM)
        case .swap:
            gbString(systemMonitor.swapUsedRAM)
        case .pressure:
            systemMonitor.memoryPressure
        case .total:
            totalRAMString
        }
    }

    private func diskDetailValue(for detail: SystemMonitorDiskDetail) -> String? {
        switch detail {
        case .volume:
            systemMonitor.diskVolumeName
        case .used:
            gbString(systemMonitor.usedDisk)
        case .free:
            gbString(systemMonitor.freeDisk)
        case .total:
            gbString(systemMonitor.totalDisk)
        }
    }

    private func gpuDetailValue(for detail: SystemMonitorGPUDetail) -> String? {
        switch detail {
        case .utilization:
            systemMonitor.gpuLoad.map { "\(Int($0))%" }
        case .temperature:
            systemMonitor.gpuTemperature.map(temperatureString)
        }
    }

    private func networkDetailValue(for detail: SystemMonitorNetworkDetail) -> String? {
        switch detail {
        case .interfaceName:
            systemMonitor.activeNetworkInterface.isEmpty ? nil : systemMonitor.activeNetworkInterface
        case .status:
            systemMonitor.activeNetworkInterface.isEmpty ? "Disconnected" : (systemMonitor.networkLinkIsUp ? "Connected" : "Idle")
        case .download:
            speedString(systemMonitor.downloadSpeed)
        case .upload:
            speedString(systemMonitor.uploadSpeed)
        case .totalDownloaded:
            byteCountString(systemMonitor.totalDownloadedBytes)
        case .totalUploaded:
            byteCountString(systemMonitor.totalUploadedBytes)
        }
    }

    private var networkHeadline: String {
        "↓\(speedString(systemMonitor.downloadSpeed))"
    }

    private var networkSubtitle: String {
        if systemMonitor.activeNetworkInterface.isEmpty {
            return String(localized: "Primary or aggregate traffic")
        }
        return "↑\(speedString(systemMonitor.uploadSpeed))"
    }

    private func reloadFromConfig() {
        let config = configManager.globalWidgetConfig(for: "default.system-monitor")
        let popupConfig = config["popup"]?.dictionaryValue ?? [:]

        let widgetMetrics = resolveMetrics(
            from: config["metrics"]?.stringArrayValue,
            fallback: [.cpu, .temperature, .ram, .disk, .gpu, .network]
        )
        popupMetrics = resolveMetrics(
            from: popupConfig["metrics"]?.stringArrayValue,
            fallback: widgetMetrics
        )

        cpuDetails = resolveDetails(
            from: popupConfig["cpu-details"]?.stringArrayValue,
            fallback: [.usage, .temperature, .loadAverage, .cores]
        )
        temperatureDetails = resolveDetails(
            from: popupConfig["temperature-details"]?.stringArrayValue,
            fallback: [.cpu, .gpu]
        )
        ramDetails = resolveDetails(
            from: popupConfig["ram-details"]?.stringArrayValue,
            fallback: [.used, .app, .free, .pressure]
        )
        diskDetails = resolveDetails(
            from: popupConfig["disk-details"]?.stringArrayValue,
            fallback: [.used, .free, .total]
        )
        gpuDetails = resolveDetails(
            from: popupConfig["gpu-details"]?.stringArrayValue,
            fallback: [.utilization, .temperature]
        )
        networkDetails = resolveDetails(
            from: popupConfig["network-details"]?.stringArrayValue,
            fallback: [.status, .download, .upload, .interfaceName]
        )

        temperatureWarningLevel = config["temperature-warning-level"]?.intValue ?? 80
        temperatureCriticalLevel = config["temperature-critical-level"]?.intValue ?? 95

        let metricsLog = popupMetrics.map(\.rawValue).joined(separator: ",")
        let cpuLog = cpuDetails.map(\.rawValue).joined(separator: ",")
        let temperatureLog = temperatureDetails.map(\.rawValue).joined(separator: ",")
        let ramLog = ramDetails.map(\.rawValue).joined(separator: ",")
        let diskLog = diskDetails.map(\.rawValue).joined(separator: ",")
        let gpuLog = gpuDetails.map(\.rawValue).joined(separator: ",")
        let networkLog = networkDetails.map(\.rawValue).joined(separator: ",")

        logger.debug(
            "reloadFromConfig() metrics=\(metricsLog, privacy: .public) cpu=\(cpuLog, privacy: .public) temp=\(temperatureLog, privacy: .public) ram=\(ramLog, privacy: .public) disk=\(diskLog, privacy: .public) gpu=\(gpuLog, privacy: .public) network=\(networkLog, privacy: .public)"
        )
    }

    private func resolveMetrics(
        from rawValues: [String]?,
        fallback: [SystemMonitorMetric]
    ) -> [SystemMonitorMetric] {
        let resolved = rawValues?.compactMap(SystemMonitorMetric.init(rawValue:))
        let metrics = resolved ?? fallback
        return metrics.isEmpty ? fallback : metrics
    }

    private func resolveDetails<Detail: RawRepresentable>(
        from rawValues: [String]?,
        fallback: [Detail]
    ) -> [Detail] where Detail.RawValue == String {
        let resolved = rawValues?.compactMap(Detail.init(rawValue:))
        let details = resolved ?? fallback
        return details.isEmpty ? fallback : details
    }

    private var cpuColor: Color {
        if systemMonitor.cpuLoad >= 90 { return .red }
        if systemMonitor.cpuLoad >= 70 { return .yellow }
        return .green
    }

    private var ramColor: Color {
        if systemMonitor.ramUsage >= 90 { return .red }
        if systemMonitor.ramUsage >= 70 { return .yellow }
        return .green
    }

    private var diskColor: Color {
        if systemMonitor.diskUsage >= 90 { return .red }
        if systemMonitor.diskUsage >= 80 { return .yellow }
        return .green
    }

    private var gpuColor: Color {
        let gpuLoad = systemMonitor.gpuLoad ?? 0
        if gpuLoad >= 90 { return .red }
        if gpuLoad >= 70 { return .yellow }
        return .green
    }

    private var temperatureColor: Color {
        let temperature = Int(systemMonitor.cpuTemperature ?? 0)
        if temperature >= temperatureCriticalLevel { return .red }
        if temperature >= temperatureWarningLevel { return .yellow }
        return .green
    }

    private var usedRAM: Double {
        systemMonitor.usedRAM
    }

    private var usedRAMString: String {
        gbString(usedRAM)
    }

    private var totalRAMString: String {
        gbString(systemMonitor.totalRAM)
    }

    private func gbString(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }

    private func speedString(_ value: Double) -> String {
        if value >= 1.0 {
            return String(format: "%.2f MB/s", value)
        } else if value >= 0.001 {
            return String(format: "%.0f KB/s", value * 1024)
        } else {
            return "0 B/s"
        }
    }

    private func byteCountString(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }

    private func temperatureProgress(_ value: Double) -> Double {
        let critical = max(Double(temperatureCriticalLevel), 1)
        return min(100, max(0, (value / critical) * 100))
    }

    private func temperatureString(_ value: Double) -> String {
        "\(Int(value.rounded()))°C"
    }
}
