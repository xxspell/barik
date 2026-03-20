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
    @State private var selectedVariant: MenuBarPopupVariant = .vertical

    var body: some View {
        MenuBarPopupVariantView(
            selectedVariant: selectedVariant,
            onVariantSelected: { variant in
                selectedVariant = variant
                ConfigManager.shared.updateConfigValue(
                    key: "widgets.default.system-monitor.popup.view-variant",
                    newValue: variant.rawValue
                )
            },
            vertical: {
                SystemMonitorDetailsPopup()
                    .environmentObject(configProvider)
            },
            settings: {
                SystemMonitorSettingsPopup()
                    .environmentObject(configProvider)
            }
        )
        .onAppear(perform: loadVariant)
        .onReceive(configProvider.$config, perform: updateVariant)
    }

    private func loadVariant() {
        if let variantString = configProvider.config["popup"]?
            .dictionaryValue?["view-variant"]?.stringValue,
           let variant = MenuBarPopupVariant(rawValue: variantString) {
            selectedVariant = variant
        } else {
            selectedVariant = .vertical
        }
    }

    private func updateVariant(newConfig: ConfigData) {
        if let variantString = newConfig["popup"]?.dictionaryValue?["view-variant"]?.stringValue,
           let variant = MenuBarPopupVariant(rawValue: variantString) {
            selectedVariant = variant
        }
    }
}

private struct SystemMonitorDetailsPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared
    private let popupWidth: CGFloat = 416
    private let popupHeight: CGFloat = 404
    private let popupHorizontalPadding: CGFloat = 12
    private let compactRowSpacing: CGFloat = 8

    private var config: ConfigData { configProvider.config }
    private var popupConfig: ConfigData { config["popup"]?.dictionaryValue ?? [:] }
    private var widgetMetrics: [SystemMonitorMetric] {
        let rawMetrics = config["metrics"]?.stringArrayValue ?? ["cpu", "ram"]
        let resolved = rawMetrics.compactMap(SystemMonitorMetric.init(rawValue:))
        return resolved.isEmpty ? [.cpu, .ram] : resolved
    }
    private var popupMetrics: [SystemMonitorMetric] {
        let rawMetrics = popupConfig["metrics"]?.stringArrayValue
        let resolved = rawMetrics?.compactMap(SystemMonitorMetric.init(rawValue:))
        let metrics = resolved ?? widgetMetrics
        return metrics.isEmpty ? widgetMetrics : metrics
    }
    private var contentWidth: CGFloat { popupWidth - popupHorizontalPadding * 2 }
    private var compactMetricWidth: CGFloat {
        floor((contentWidth - compactRowSpacing) / 2)
    }

    private var temperatureWarningLevel: Int { config["temperature-warning-level"]?.intValue ?? 80 }
    private var temperatureCriticalLevel: Int { config["temperature-critical-level"]?.intValue ?? 95 }

    private var cpuDetails: [SystemMonitorCPUDetail] {
        detailSelection(key: "cpu-details", defaults: [.usage, .temperature, .loadAverage, .cores])
    }
    private var temperatureDetails: [SystemMonitorTemperatureDetail] {
        detailSelection(key: "temperature-details", defaults: [.cpu, .gpu])
    }
    private var ramDetails: [SystemMonitorRAMDetail] {
        detailSelection(key: "ram-details", defaults: [.used, .app, .free, .pressure])
    }
    private var diskDetails: [SystemMonitorDiskDetail] {
        detailSelection(key: "disk-details", defaults: [.used, .free, .total])
    }
    private var gpuDetails: [SystemMonitorGPUDetail] {
        detailSelection(key: "gpu-details", defaults: [.utilization, .temperature])
    }
    private var networkDetails: [SystemMonitorNetworkDetail] {
        detailSelection(key: "network-details", defaults: [.status, .download, .upload, .interfaceName])
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

    private func detailSelection<Detail: RawRepresentable>(
        key: String,
        defaults: [Detail]
    ) -> [Detail] where Detail.RawValue == String {
        let rawValues = popupConfig[key]?.stringArrayValue ?? defaults.map(\.rawValue)
        let resolved = rawValues.compactMap(Detail.init(rawValue:))
        return resolved.isEmpty ? defaults : resolved
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

private struct SystemMonitorSettingsPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    private let popupWidth: CGFloat = 416
    private let popupHeight: CGFloat = 404

    private var config: ConfigData { configProvider.config }
    private var popupConfig: ConfigData { config["popup"]?.dictionaryValue ?? [:] }
    private var widgetMetrics: [SystemMonitorMetric] {
        let rawMetrics = config["metrics"]?.stringArrayValue ?? ["cpu", "ram"]
        let resolved = rawMetrics.compactMap(SystemMonitorMetric.init(rawValue:))
        return resolved.isEmpty ? [.cpu, .ram] : resolved
    }
    private var popupMetrics: [SystemMonitorMetric] {
        let rawMetrics = popupConfig["metrics"]?.stringArrayValue
        let resolved = rawMetrics?.compactMap(SystemMonitorMetric.init(rawValue:))
        return (resolved?.isEmpty == false ? resolved! : widgetMetrics)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Popup Settings")
                    .font(.system(size: 16, weight: .semibold))

                settingsSection(title: "Visible Sections") {
                    flowLayout(items: SystemMonitorMetric.allCases, id: \.rawValue) { metric in
                        toggleChip(
                            title: metric.title,
                            isSelected: popupMetrics.contains(metric)
                        ) {
                            toggleMetric(metric)
                        }
                    }
                }

                detailSection(title: "CPU Fields", items: SystemMonitorCPUDetail.allCases, selected: selectedDetails(key: "cpu-details", defaults: [.usage, .temperature, .loadAverage, .cores]), update: updateCPUDetails)
                detailSection(title: "Temperature Fields", items: SystemMonitorTemperatureDetail.allCases, selected: selectedDetails(key: "temperature-details", defaults: [.cpu, .gpu]), update: updateTemperatureDetails)
                detailSection(title: "Memory Fields", items: SystemMonitorRAMDetail.allCases, selected: selectedDetails(key: "ram-details", defaults: [.used, .app, .free, .pressure]), update: updateRAMDetails)
                detailSection(title: "Disk Fields", items: SystemMonitorDiskDetail.allCases, selected: selectedDetails(key: "disk-details", defaults: [.used, .free, .total]), update: updateDiskDetails)
                detailSection(title: "GPU Fields", items: SystemMonitorGPUDetail.allCases, selected: selectedDetails(key: "gpu-details", defaults: [.utilization, .temperature]), update: updateGPUDetails)
                detailSection(title: "Network Fields", items: SystemMonitorNetworkDetail.allCases, selected: selectedDetails(key: "network-details", defaults: [.status, .download, .upload, .interfaceName]), update: updateNetworkDetails)

                Button("Reset Popup Defaults", action: resetToDefaults)
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.8))
            }
            .padding(20)
        }
        .frame(width: popupWidth, height: popupHeight)
        .background(Color.black)
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.5)
                .textCase(.uppercase)
            content()
        }
    }

    private func detailSection<Detail: CaseIterable & RawRepresentable>(
        title: String,
        items: Detail.AllCases,
        selected: [Detail],
        update: @escaping ([Detail]) -> Void
    ) -> some View where Detail: Hashable, Detail.RawValue == String {
        settingsSection(title: title) {
            flowLayout(items: Array(items), id: \.rawValue) { item in
                toggleChip(
                    title: detailTitle(item),
                    isSelected: selected.contains(item)
                ) {
                    var next = selected
                    if let index = next.firstIndex(of: item) {
                        guard next.count > 1 else { return }
                        next.remove(at: index)
                    } else {
                        next.append(item)
                    }
                    update(next)
                }
            }
        }
    }

    private func flowLayout<Item: Hashable, Content: View>(
        items: [Item],
        id: KeyPath<Item, String>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let columns = [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(items, id: id) { item in
                    content(item)
                }
            }
        }
    }

    private func toggleChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func toggleMetric(_ metric: SystemMonitorMetric) {
        var next = popupMetrics
        if let index = next.firstIndex(of: metric) {
            guard next.count > 1 else { return }
            next.remove(at: index)
        } else {
            next.append(metric)
        }
        updateMetricSelection(next)
    }

    private func updateMetricSelection(_ metrics: [SystemMonitorMetric]) {
        ConfigManager.shared.updateConfigLiteralValue(
            key: "widgets.default.system-monitor.popup.metrics",
            newValueLiteral: tomlStringArray(metrics.map(\.rawValue))
        )
    }

    private func updateCPUDetails(_ details: [SystemMonitorCPUDetail]) {
        updateDetails(key: "cpu-details", values: details.map(\.rawValue))
    }

    private func updateTemperatureDetails(_ details: [SystemMonitorTemperatureDetail]) {
        updateDetails(key: "temperature-details", values: details.map(\.rawValue))
    }

    private func updateRAMDetails(_ details: [SystemMonitorRAMDetail]) {
        updateDetails(key: "ram-details", values: details.map(\.rawValue))
    }

    private func updateDiskDetails(_ details: [SystemMonitorDiskDetail]) {
        updateDetails(key: "disk-details", values: details.map(\.rawValue))
    }

    private func updateGPUDetails(_ details: [SystemMonitorGPUDetail]) {
        updateDetails(key: "gpu-details", values: details.map(\.rawValue))
    }

    private func updateNetworkDetails(_ details: [SystemMonitorNetworkDetail]) {
        updateDetails(key: "network-details", values: details.map(\.rawValue))
    }

    private func updateDetails(key: String, values: [String]) {
        ConfigManager.shared.updateConfigLiteralValue(
            key: "widgets.default.system-monitor.popup.\(key)",
            newValueLiteral: tomlStringArray(values)
        )
    }

    private func resetToDefaults() {
        updateMetricSelection(widgetMetrics)
        updateCPUDetails([.usage, .temperature, .loadAverage, .cores])
        updateTemperatureDetails([.cpu, .gpu])
        updateRAMDetails([.used, .app, .free, .pressure])
        updateDiskDetails([.used, .free, .total])
        updateGPUDetails([.utilization, .temperature])
        updateNetworkDetails([.status, .download, .upload, .interfaceName])
    }

    private func selectedDetails<Detail: RawRepresentable>(
        key: String,
        defaults: [Detail]
    ) -> [Detail] where Detail.RawValue == String {
        let rawValues = popupConfig[key]?.stringArrayValue ?? defaults.map(\.rawValue)
        let resolved = rawValues.compactMap(Detail.init(rawValue:))
        return resolved.isEmpty ? defaults : resolved
    }

    private func tomlStringArray(_ values: [String]) -> String {
        "[" + values.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
    }

    private func detailTitle<Detail: RawRepresentable>(_ detail: Detail) -> String
    where Detail.RawValue == String {
        switch detail {
        case let detail as SystemMonitorCPUDetail:
            return detail.title
        case let detail as SystemMonitorTemperatureDetail:
            return detail.title
        case let detail as SystemMonitorRAMDetail:
            return detail.title
        case let detail as SystemMonitorDiskDetail:
            return detail.title
        case let detail as SystemMonitorGPUDetail:
            return detail.title
        case let detail as SystemMonitorNetworkDetail:
            return detail.title
        default:
            return detail.rawValue
        }
    }
}
