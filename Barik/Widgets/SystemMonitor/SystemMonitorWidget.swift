import SwiftUI

private enum SystemMonitorLayoutMode: String {
    case rows
    case stacked
}

private enum SystemMonitorDividerMode: String {
    case none
    case horizontal
    case vertical
    case both

    var showsHorizontalDividers: Bool {
        self == .horizontal || self == .both
    }

    var showsVerticalDividers: Bool {
        self == .vertical || self == .both
    }
}

struct SystemMonitorWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    private var config: ConfigData { configProvider.config }

    private var showIcon: Bool { config["show-icon"]?.boolValue ?? false }
    private var useMetricIcons: Bool { config["use-metric-icons"]?.boolValue ?? false }
    private var showUsageBars: Bool { config["show-usage-bars"]?.boolValue ?? true }
    private var networkDisplayMode: String { config["network-display-mode"]?.stringValue ?? "single" }
    private var usesSplitNetworkRows: Bool { networkDisplayMode == "dual-line" }
    private var metricsPerColumn: Int {
        max(1, min(4, config["metrics-per-column"]?.intValue ?? 2))
    }
    private var layoutMode: SystemMonitorLayoutMode {
        guard let rawValue = config["layout"]?.stringValue,
              let mode = SystemMonitorLayoutMode(rawValue: rawValue) else {
            return .rows
        }
        return mode
    }
    private var dividerMode: SystemMonitorDividerMode {
        guard let rawValue = config["dividers"]?.stringValue,
              let mode = SystemMonitorDividerMode(rawValue: rawValue) else {
            return .none
        }
        return mode
    }
    private var usesSingleMetricColumns: Bool { metricsPerColumn == 1 }
    private var usesExpandedRowsLayout: Bool {
        layoutMode == .rows && usesSingleMetricColumns
    }
    private var columnSpacing: CGFloat {
        usesExpandedRowsLayout ? 12 : (usesSingleMetricColumns ? 10 : 8)
    }
    private var columnRowSpacing: CGFloat {
        usesExpandedRowsLayout ? 5 : (usesSingleMetricColumns ? 4 : 2)
    }
    private var rowSpacing: CGFloat {
        if usesExpandedRowsLayout { return showUsageBars ? 5 : 3 }
        return showUsageBars ? 4 : 2
    }
    private var labelWidth: CGFloat {
        if layoutMode == .stacked {
            return usesSingleMetricColumns ? 34 : 28
        }
        return usesExpandedRowsLayout ? 28 : 24
    }
    private var valueWidth: CGFloat {
        usesExpandedRowsLayout ? 34 : 28
    }
    private var barWidth: CGFloat {
        usesExpandedRowsLayout ? 38 : 30
    }
    private var barHeight: CGFloat {
        usesExpandedRowsLayout ? 4 : 3
    }
    private var horizontalDividerWidth: CGFloat {
        if layoutMode == .stacked {
            return max(labelWidth, valueWidth) + 6
        }

        let baseWidth = labelWidth + valueWidth + rowSpacing
        let fullWidth = showUsageBars ? baseWidth + barWidth + rowSpacing : baseWidth
        return fullWidth - (usesExpandedRowsLayout ? 8 : 6)
    }
    private var metricRowHeight: CGFloat {
        if layoutMode == .stacked {
            if usesSplitNetworkRows && metrics.contains(.network) {
                return usesSingleMetricColumns ? 36 : 31
            }
            return usesSingleMetricColumns ? 26 : 23
        }
        return usesExpandedRowsLayout ? 16 : 13
    }
    private var metrics: [SystemMonitorMetric] {
        let rawMetrics = config["metrics"]?.stringArrayValue ?? ["cpu", "ram"]
        let resolved = rawMetrics.compactMap(SystemMonitorMetric.init(rawValue:))
        return resolved.isEmpty ? [.cpu, .ram] : resolved
    }
    private var metricColumns: [[SystemMonitorMetric]] {
        stride(from: 0, to: metrics.count, by: metricsPerColumn).map { startIndex in
            Array(metrics[startIndex..<min(startIndex + metricsPerColumn, metrics.count)])
        }
    }
    private var cpuWarningLevel: Int { config["cpu-warning-level"]?.intValue ?? 70 }
    private var cpuCriticalLevel: Int { config["cpu-critical-level"]?.intValue ?? 90 }
    private var ramWarningLevel: Int { config["ram-warning-level"]?.intValue ?? 70 }
    private var ramCriticalLevel: Int { config["ram-critical-level"]?.intValue ?? 90 }
    private var diskWarningLevel: Int { config["disk-warning-level"]?.intValue ?? 80 }
    private var diskCriticalLevel: Int { config["disk-critical-level"]?.intValue ?? 90 }
    private var gpuWarningLevel: Int { config["gpu-warning-level"]?.intValue ?? 70 }
    private var gpuCriticalLevel: Int { config["gpu-critical-level"]?.intValue ?? 90 }
    private var temperatureWarningLevel: Int { config["temperature-warning-level"]?.intValue ?? 80 }
    private var temperatureCriticalLevel: Int { config["temperature-critical-level"]?.intValue ?? 95 }

    @ObservedObject private var systemMonitor = SystemMonitorManager.shared
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 6) {
            if showIcon {
                Image(systemName: "cpu")
                    .font(.system(size: usesExpandedRowsLayout ? 15 : (usesSingleMetricColumns ? 13 : 12), weight: .medium))
                    .foregroundStyle(.foregroundOutside)
            }

            HStack(alignment: .top, spacing: columnSpacing) {
                ForEach(Array(metricColumns.enumerated()), id: \.offset) { columnIndex, column in
                    HStack(alignment: .top, spacing: columnSpacing) {
                        VStack(alignment: .leading, spacing: columnRowSpacing) {
                            ForEach(Array(column.enumerated()), id: \.element.rawValue) { metricIndex, metric in
                                VStack(alignment: .leading, spacing: columnRowSpacing) {
                                    metricRow(for: metric)

                                    if dividerMode.showsHorizontalDividers && metricIndex < column.count - 1 {
                                        metricDivider()
                                    }
                                }
                            }
                        }

                        if dividerMode.showsVerticalDividers && columnIndex < metricColumns.count - 1 {
                            metricDivider(vertical: true, metricCount: column.count)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, usesExpandedRowsLayout ? 10 : 8)
        .padding(.vertical, usesExpandedRowsLayout ? 6 : (usesSingleMetricColumns ? 5 : 4))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        rect = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, newValue in
                        rect = newValue
                    }
            }
        )
        .contentShape(Rectangle())
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "system-monitor") {
                SystemMonitorPopup()
                    .environmentObject(configProvider)
            }
        }
    }

    private func metricDivider(vertical: Bool = false, metricCount: Int = 1) -> some View {
        let verticalHeight = CGFloat(metricCount) * metricRowHeight
            + CGFloat(max(0, metricCount - 1)) * columnRowSpacing
            + CGFloat(max(0, metricCount - 1)) * (dividerMode.showsHorizontalDividers ? columnRowSpacing : 0)

        return Rectangle()
            .fill(.foregroundOutside.opacity(0.18))
            .frame(
                width: vertical ? 1 : horizontalDividerWidth,
                height: vertical ? verticalHeight : 1
            )
    }

    @ViewBuilder
    private func metricRow(for metric: SystemMonitorMetric) -> some View {
        switch metric {
        case .cpu:
            metricValueRow(
                metric: metric,
                valueText: "\(Int(systemMonitor.cpuLoad))%",
                color: cpuColor,
                percentValue: systemMonitor.cpuLoad
            )
        case .temperature:
            if let temperature = systemMonitor.cpuTemperature {
                metricValueRow(
                    metric: metric,
                    valueText: shortTemperatureString(temperature),
                    color: temperatureColor,
                    percentValue: temperatureProgress(temperature)
                )
            } else {
                unavailableMetricRow(metric: metric)
            }
        case .ram:
            metricValueRow(
                metric: metric,
                valueText: "\(Int(systemMonitor.ramUsage))%",
                color: ramColor,
                percentValue: systemMonitor.ramUsage
            )
        case .disk:
            metricValueRow(
                metric: metric,
                valueText: "\(Int(systemMonitor.diskUsage))%",
                color: diskColor,
                percentValue: systemMonitor.diskUsage
            )
        case .gpu:
            if let gpuLoad = systemMonitor.gpuLoad {
                metricValueRow(
                    metric: metric,
                    valueText: "\(Int(gpuLoad))%",
                    color: gpuColor,
                    percentValue: gpuLoad
                )
            } else {
                unavailableMetricRow(metric: metric)
            }
        case .network:
            networkMetricRow()
        }
    }

    @ViewBuilder
    private func metricLabel(for metric: SystemMonitorMetric) -> some View {
        if useMetricIcons {
            Image(systemName: metric.systemImageName)
                .font(.system(size: usesExpandedRowsLayout ? 11 : (usesSingleMetricColumns ? 10 : 9), weight: .semibold))
                .foregroundStyle(.foregroundOutside.opacity(0.8))
                .frame(width: labelWidth, alignment: .leading)
        } else {
            Text(metric.title)
                .font(.system(size: usesExpandedRowsLayout ? 11 : (usesSingleMetricColumns ? 10 : 9), weight: .semibold))
                .foregroundStyle(.foregroundOutside.opacity(0.8))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: labelWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private func metricValueRow(
        metric: SystemMonitorMetric,
        valueText: String?,
        color: Color,
        percentValue: Double? = nil
    ) -> some View {
        if layoutMode == .stacked {
            stackedMetricRow(metric: metric, valueText: valueText, color: color)
        } else {
            percentMetricRow(metric: metric, valueText: valueText, percentValue: percentValue, color: color)
        }
    }

    @ViewBuilder
    private func percentMetricRow(
        metric: SystemMonitorMetric,
        valueText: String?,
        percentValue: Double? = nil,
        color: Color
    ) -> some View {
        HStack(spacing: rowSpacing) {
            metricLabel(for: metric)

            if showUsageBars {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.foregroundOutside.opacity(0.2))
                        .frame(width: barWidth, height: barHeight)

                    if let percentValue {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(
                                width: max(usesExpandedRowsLayout ? 3 : 2, barWidth * percentValue / 100),
                                height: barHeight
                            )
                            .animation(.easeInOut(duration: 0.3), value: percentValue)
                    }
                }
            }

            Text(valueText ?? "--")
                .font(.system(size: usesExpandedRowsLayout ? 11 : (usesSingleMetricColumns ? 10 : 9), weight: .medium, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: valueWidth, alignment: .trailing)
        }
    }

    private func stackedMetricRow(metric: SystemMonitorMetric, valueText: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            metricLabel(for: metric)

            Text(valueText ?? "--")
                .font(.system(size: usesSingleMetricColumns ? 11 : 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .frame(minWidth: labelWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private func unavailableMetricRow(metric: SystemMonitorMetric) -> some View {
        if layoutMode == .stacked {
            stackedMetricRow(metric: metric, valueText: "--", color: .foregroundOutside.opacity(0.6))
        } else {
            HStack(spacing: rowSpacing) {
                metricLabel(for: metric)

                if showUsageBars {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.foregroundOutside.opacity(0.12))
                        .frame(width: barWidth, height: barHeight)
                }

                Text("--")
                    .font(.system(size: usesExpandedRowsLayout ? 11 : (usesSingleMetricColumns ? 10 : 9), weight: .medium, design: .monospaced))
                    .foregroundStyle(.foregroundOutside.opacity(0.6))
                    .frame(width: valueWidth, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func networkMetricRow() -> some View {
        let uploadText = formatSpeed(systemMonitor.uploadSpeed)
        let downloadText = formatSpeed(systemMonitor.downloadSpeed)
        let dominantDownload = systemMonitor.downloadSpeed >= systemMonitor.uploadSpeed
        let directionIcon = dominantDownload ? "arrow.down" : "arrow.up"
        let speedColor: Color = dominantDownload ? .blue : .green
        let valueText = formatSpeed(max(systemMonitor.uploadSpeed, systemMonitor.downloadSpeed))

        if layoutMode == .stacked && usesSplitNetworkRows {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: usesSingleMetricColumns ? 9 : 8, weight: .bold))
                        .foregroundStyle(.green)
                    Text(uploadText)
                        .font(.system(size: usesSingleMetricColumns ? 11 : 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.foregroundOutside)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: usesSingleMetricColumns ? 9 : 8, weight: .bold))
                        .foregroundStyle(.blue)
                    Text(downloadText)
                        .font(.system(size: usesSingleMetricColumns ? 11 : 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.foregroundOutside)
                }
            }
        } else if layoutMode == .stacked {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    metricLabel(for: .network)

                    Image(systemName: directionIcon)
                        .font(.system(size: usesSingleMetricColumns ? 9 : 8, weight: .bold))
                        .foregroundStyle(speedColor)
                }

                Text(valueText)
                    .font(.system(size: usesSingleMetricColumns ? 11 : 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.foregroundOutside)
                    .frame(minWidth: 32, alignment: .leading)
            }
        } else {
            HStack(spacing: showUsageBars ? rowSpacing : 1) {
                metricLabel(for: .network)

                Image(systemName: directionIcon)
                    .font(.system(size: usesExpandedRowsLayout ? 9 : 8, weight: .bold))
                    .foregroundStyle(speedColor)
                    .frame(width: usesExpandedRowsLayout ? 10 : 8)

                Text(valueText)
                    .font(.system(size: usesExpandedRowsLayout ? 11 : (usesSingleMetricColumns ? 10 : 9), weight: .medium, design: .monospaced))
                    .foregroundStyle(.foregroundOutside)
                    .frame(width: usesExpandedRowsLayout ? 56 : 50, alignment: .trailing)
            }
        }
    }

    private func formatSpeed(_ speed: Double) -> String {
        if speed >= 1.0 {
            return String(format: "%.1fM", speed)
        } else if speed >= 0.001 {
            return String(format: "%.0fK", speed * 1024)
        } else {
            return "0B"
        }
    }

    private var cpuColor: Color {
        let cpu = Int(systemMonitor.cpuLoad)
        if cpu >= cpuCriticalLevel { return .red }
        if cpu >= cpuWarningLevel { return .yellow }
        return .foregroundOutside
    }

    private var ramColor: Color {
        let ram = Int(systemMonitor.ramUsage)
        if ram >= ramCriticalLevel { return .red }
        if ram >= ramWarningLevel { return .yellow }
        return .foregroundOutside
    }

    private var diskColor: Color {
        let disk = Int(systemMonitor.diskUsage)
        if disk >= diskCriticalLevel { return .red }
        if disk >= diskWarningLevel { return .yellow }
        return .foregroundOutside
    }

    private var gpuColor: Color {
        let gpu = Int(systemMonitor.gpuLoad ?? 0)
        if gpu >= gpuCriticalLevel { return .red }
        if gpu >= gpuWarningLevel { return .yellow }
        return .foregroundOutside
    }

    private var temperatureColor: Color {
        let temperature = Int(systemMonitor.cpuTemperature ?? 0)
        if temperature >= temperatureCriticalLevel { return .red }
        if temperature >= temperatureWarningLevel { return .yellow }
        return .foregroundOutside
    }

    private func temperatureProgress(_ value: Double) -> Double {
        let critical = max(Double(temperatureCriticalLevel), 1)
        return min(100, max(0, (value / critical) * 100))
    }

    private func shortTemperatureString(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}
