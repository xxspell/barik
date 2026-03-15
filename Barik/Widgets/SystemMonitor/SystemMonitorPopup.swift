import SwiftUI

struct SystemMonitorPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared

    private var config: ConfigData { configProvider.config }
    private var metrics: [SystemMonitorMetric] {
        let rawMetrics = config["metrics"]?.stringArrayValue ?? ["cpu", "ram"]
        let resolved = rawMetrics.compactMap(SystemMonitorMetric.init(rawValue:))
        return resolved.isEmpty ? [.cpu, .ram] : resolved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "cpu")
                    .font(.system(size: 18, weight: .semibold))
                Text("System Monitor")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }

            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                section(for: metric)
                if index < metrics.count - 1 {
                    Divider().background(Color.white.opacity(0.2))
                }
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(Color.black)
    }

    @ViewBuilder
    private func section(for metric: SystemMonitorMetric) -> some View {
        switch metric {
        case .cpu:
            monitorSection(title: "CPU Usage", percentage: systemMonitor.cpuLoad, color: cpuColor) {
                detailRow(title: "User", value: "\(Int(systemMonitor.userLoad))%")
                detailRow(title: "System", value: "\(Int(systemMonitor.systemLoad))%")
                detailRow(title: "Idle", value: "\(Int(systemMonitor.idleLoad))%")
            }
        case .ram:
            monitorSection(title: "Memory Usage", percentage: systemMonitor.ramUsage, color: ramColor) {
                detailRow(title: "Used", value: "\(usedRAMString) / \(totalRAMString)")
                detailRow(title: "Active", value: gbString(systemMonitor.activeRAM))
                detailRow(title: "Wired", value: gbString(systemMonitor.wiredRAM))
                detailRow(title: "Compressed", value: gbString(systemMonitor.compressedRAM))
            }
        case .disk:
            monitorSection(title: "Disk Usage", percentage: systemMonitor.diskUsage, color: diskColor) {
                detailRow(title: "Used", value: "\(gbString(systemMonitor.usedDisk)) / \(gbString(systemMonitor.totalDisk))")
                detailRow(title: "Free", value: gbString(systemMonitor.freeDisk))
            }
        case .gpu:
            if let gpuLoad = systemMonitor.gpuLoad {
                monitorSection(title: "GPU Usage", percentage: gpuLoad, color: gpuColor) {
                    detailRow(title: "Utilization", value: "\(Int(gpuLoad))%")
                }
            } else {
                unavailableSection(title: "GPU Usage", description: "Unavailable on this system")
            }
        case .network:
            networkSection
        }
    }

    private func monitorSection<Details: View>(
        title: String,
        percentage: Double,
        color: Color,
        @ViewBuilder details: () -> Details
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * min(percentage, 100) / 100)
                }
            }
            .frame(height: 8)

            details()
        }
    }

    private func unavailableSection(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("--")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Text(description)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Network Activity")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }

            detailRow(title: "Download", value: speedString(systemMonitor.downloadSpeed))
            detailRow(title: "Upload", value: speedString(systemMonitor.uploadSpeed))
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
        .font(.system(size: 12, weight: .medium))
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

    private var usedRAM: Double {
        systemMonitor.activeRAM + systemMonitor.wiredRAM + systemMonitor.compressedRAM
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
}
