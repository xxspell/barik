import SwiftUI

// Page implementations are fleshed out page by page; each fills the content
// area next to the sidebar and scrolls vertically.

private struct SMPageScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
        }
    }
}

struct SMOverviewPage: View {
    var body: some View {
        SMPageScroll {
            Text("Overview")
        }
    }
}

struct SMCPUPage: View {
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared

    private var loadSeries: [Double] { systemMonitor.series(\.cpuLoad) }

    var body: some View {
        SMPageScroll {
            HStack(alignment: .top, spacing: 10) {
                SMCard("Usage") {
                    VStack(alignment: .leading, spacing: 10) {
                        SMHeroMetric(value: String(format: "%.0f", systemMonitor.cpuLoad), unit: "%")
                        SMLinearGauge(fraction: systemMonitor.cpuLoad / 100, color: .orange, height: 7)
                        SMChartLegend(entries: [
                            .init(label: "User", color: .orange,
                                  value: SMFormat.percent(systemMonitor.userLoad, digits: 1)),
                            .init(label: "System", color: .red.opacity(0.75),
                                  value: SMFormat.percent(systemMonitor.systemLoad, digits: 1)),
                            .init(label: "Idle", color: .secondary.opacity(0.5),
                                  value: SMFormat.percent(systemMonitor.idleLoad, digits: 1))
                        ])
                        SMHistoryChart(
                            series: [
                                SMChartSeries(values: loadSeries, color: .orange),
                                SMChartSeries(values: systemMonitor.series(\.systemLoad),
                                              color: .red.opacity(0.75), filled: false)
                            ],
                            maxHeight: 100,
                            filledCount: max(systemMonitor.historyFilledCount, 2),
                            gridDivisions: 4
                        )
                        .frame(height: 74)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    SMCard("Load Average") {
                        VStack(alignment: .leading, spacing: 6) {
                            SMStatRow(label: "1 min", value: SMFormat.load(systemMonitor.loadAverage),
                                      valueColor: loadColor(systemMonitor.loadAverage))
                            SMStatRow(label: "5 min", value: SMFormat.load(systemMonitor.loadAverage5m),
                                      valueColor: loadColor(systemMonitor.loadAverage5m))
                            SMStatRow(label: "15 min", value: SMFormat.load(systemMonitor.loadAverage15m),
                                      valueColor: loadColor(systemMonitor.loadAverage15m))
                        }
                    }
                    SMCard("Processor") {
                        VStack(alignment: .leading, spacing: 6) {
                            SMStatRow(label: "Cores", value: "\(systemMonitor.cpuCoreCount)")
                            SMStatRow(label: "Temp",
                                      value: systemMonitor.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "--",
                                      valueColor: (systemMonitor.cpuTemperature ?? 0) >= 85 ? .red : .primary)
                        }
                    }
                }
                .frame(width: 200)
            }

            SMCard("Top Processes") {
                SMProcessList(
                    processes: systemMonitor.topCPUProcesses,
                    emptyText: "Collecting…",
                    valueText: { process in
                        let rss = process.secondary.map { " · " + SMFormat.bytes($0) } ?? ""
                        return String(format: "%.1f%%", process.primary) + rss
                    },
                    tint: .orange
                )
            }
        }
    }

    private func loadColor(_ value: Double) -> Color {
        let perCore = systemMonitor.cpuCoreCount > 0
            ? value / Double(systemMonitor.cpuCoreCount) : value
        if perCore > 0.9 { return .red }
        if perCore > 0.5 { return .orange }
        return .primary
    }
}

struct SMGPUPage: View {
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared

    var body: some View {
        SMPageScroll {
            HStack(alignment: .top, spacing: 10) {
                SMCard("Utilization") {
                    VStack(alignment: .leading, spacing: 10) {
                        SMHeroMetric(
                            value: systemMonitor.gpuLoad.map { String(format: "%.0f", $0) } ?? "--",
                            unit: "%", color: .purple
                        )
                        SMLinearGauge(fraction: (systemMonitor.gpuLoad ?? 0) / 100, color: .purple, height: 7)
                        SMHistoryChart(
                            series: [
                                SMChartSeries(values: systemMonitor.series(\.gpuDevice), color: .purple),
                                SMChartSeries(values: systemMonitor.series(\.gpuRenderer),
                                              color: .cyan, filled: false),
                                SMChartSeries(values: systemMonitor.series(\.gpuTiler),
                                              color: .yellow, filled: false)
                            ],
                            maxHeight: 100,
                            filledCount: max(systemMonitor.historyFilledCount, 2),
                            gridDivisions: 4
                        )
                        .frame(height: 74)
                        SMChartLegend(entries: [
                            .init(label: "Device", color: .purple,
                                  value: systemMonitor.gpuLoad.map { SMFormat.percent($0) }),
                            .init(label: "Renderer", color: .cyan,
                                  value: systemMonitor.gpuRendererLoad.map { SMFormat.percent($0) }),
                            .init(label: "Tiler", color: .yellow,
                                  value: systemMonitor.gpuTilerLoad.map { SMFormat.percent($0) })
                        ])
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    if let fps = systemMonitor.fps {
                        SMCard("Display") {
                            VStack(alignment: .leading, spacing: 10) {
                                SMHeroMetric(value: String(format: "%.0f", fps), unit: "FPS")
                                SMHistoryChart(
                                    series: [SMChartSeries(values: systemMonitor.series(\.fps),
                                                           color: .green)],
                                    filledCount: max(systemMonitor.historyFilledCount, 2)
                                )
                                .frame(height: 40)
                            }
                        }
                    }
                    SMCard("Memory") {
                        VStack(alignment: .leading, spacing: 6) {
                            SMStatRow(label: "In use",
                                      value: systemMonitor.gpuInUseMemoryBytes.map(SMFormat.bytes) ?? "--")
                            SMStatRow(label: "Temp",
                                      value: systemMonitor.gpuTemperature.map { String(format: "%.0f°C", $0) } ?? "--")
                        }
                    }
                }
                .frame(width: 200)
            }

            SMCard("GPU Processes") {
                SMProcessList(
                    processes: systemMonitor.topGPUProcesses,
                    emptyText: "No GPU activity",
                    valueText: { String(format: "%.1f%%", $0.primary) },
                    tint: .purple
                )
            }
        }
    }
}

struct SMRAMPage: View {
    var body: some View {
        SMPageScroll {
            Text("RAM")
        }
    }
}

struct SMDiskPage: View {
    var body: some View {
        SMPageScroll {
            Text("Disk")
        }
    }
}

struct SMNetworkPage: View {
    var body: some View {
        SMPageScroll {
            Text("Network")
        }
    }
}
