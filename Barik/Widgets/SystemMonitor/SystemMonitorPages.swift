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
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared

    var body: some View {
        SMPageScroll {
            HStack(spacing: 10) {
                tile(title: "CPU", color: .orange, fraction: systemMonitor.cpuLoad / 100,
                     center: String(format: "%.0f%%", systemMonitor.cpuLoad),
                     caption: SMFormat.load(systemMonitor.loadAverage) + " load",
                     series: systemMonitor.series(\.cpuLoad), maxHeight: 100)
                tile(title: "GPU", color: .purple, fraction: (systemMonitor.gpuLoad ?? 0) / 100,
                     center: systemMonitor.gpuLoad.map { String(format: "%.0f%%", $0) } ?? "--",
                     caption: systemMonitor.fps.map { String(format: "%.0f FPS", $0) } ?? "no fps",
                     series: systemMonitor.series(\.gpuDevice), maxHeight: 100)
                tile(title: "RAM", color: .blue, fraction: systemMonitor.ramUsage / 100,
                     center: String(format: "%.0f%%", systemMonitor.ramUsage),
                     caption: String(format: "%.1f/%.0f GB", systemMonitor.usedRAM, systemMonitor.totalRAM),
                     series: systemMonitor.series(\.ramUsage), maxHeight: 100)
                tile(title: "Disk", color: .indigo, fraction: systemMonitor.diskUsage / 100,
                     center: String(format: "%.0f%%", systemMonitor.diskUsage),
                     caption: String(format: "%.0f GB free", systemMonitor.freeDisk),
                     series: systemMonitor.series(\.diskWriteBps), maxHeight: nil)
            }
            .frame(height: 148)

            HStack(alignment: .top, spacing: 10) {
                SMCard("Network") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 18) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down").barikPopupFont(size: 10, weight: .bold).foregroundStyle(.green)
                                Text(SMFormat.bytesPerSecond(systemMonitor.downloadSpeed * 1_048_576))
                                    .barikPopupFont(size: 12, weight: .semibold, design: .monospaced)
                                    .contentTransition(.numericText())
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up").barikPopupFont(size: 10, weight: .bold).foregroundStyle(.blue)
                                Text(SMFormat.bytesPerSecond(systemMonitor.uploadSpeed * 1_048_576))
                                    .barikPopupFont(size: 12, weight: .semibold, design: .monospaced)
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                        }
                        SMHistoryChart(
                            series: [
                                SMChartSeries(values: systemMonitor.series(\.downloadBps), color: .green),
                                SMChartSeries(values: systemMonitor.series(\.uploadBps), color: .blue)
                            ],
                            filledCount: max(systemMonitor.historyFilledCount, 2)
                        )
                        .frame(height: 54)
                    }
                }
                .frame(maxWidth: .infinity)

                SMCard("Temperatures") {
                    VStack(alignment: .leading, spacing: 6) {
                        SMStatRow(label: "CPU",
                                  value: systemMonitor.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "--",
                                  valueColor: tempColor(systemMonitor.cpuTemperature))
                        SMStatRow(label: "GPU",
                                  value: systemMonitor.gpuTemperature.map { String(format: "%.0f°C", $0) } ?? "--",
                                  valueColor: tempColor(systemMonitor.gpuTemperature))
                    }
                }
                .frame(width: 200)
            }
        }
    }

    private func tile(title: String, color: Color, fraction: Double, center: String,
                      caption: String, series: [Double], maxHeight: Double?) -> some View {
        SMCard(title) {
            HStack(spacing: 10) {
                SMRingGauge(fraction: fraction, color: color, centerText: center, caption: caption)
                    .frame(width: 64, height: 64)
                VStack(alignment: .trailing, spacing: 4) {
                    Spacer(minLength: 0)
                    SMHistoryChart(
                        series: [SMChartSeries(values: series, color: color)],
                        maxHeight: maxHeight,
                        filledCount: max(systemMonitor.historyFilledCount, 2)
                    )
                    .frame(height: 40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func tempColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 90 { return .red }
        if value >= 80 { return .orange }
        return .primary
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
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared

    var body: some View {
        SMPageScroll {
            HStack(alignment: .top, spacing: 10) {
                SMCard("Memory Usage") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            SMHeroMetric(
                                value: String(format: "%.1f", systemMonitor.usedRAM),
                                unit: "GB used",
                                color: .blue
                            )
                            Spacer()
                            Text(String(format: "of %.0f GB", systemMonitor.totalRAM))
                                .barikPopupFont(size: 11, weight: .medium, design: .rounded)
                                .foregroundStyle(.secondary)
                        }
                        SMStackedBar(segments: [
                            SMSegment(fraction: fraction(systemMonitor.appRAM), color: .blue,
                                      label: "App: \(String(format: "%.1f", systemMonitor.appRAM)) GB"),
                            SMSegment(fraction: fraction(systemMonitor.wiredRAM), color: .red.opacity(0.8),
                                      label: "Wired: \(String(format: "%.1f", systemMonitor.wiredRAM)) GB"),
                            SMSegment(fraction: fraction(systemMonitor.compressedRAM), color: .purple.opacity(0.8),
                                      label: "Compressed: \(String(format: "%.1f", systemMonitor.compressedRAM)) GB"),
                            SMSegment(fraction: fraction(systemMonitor.cachedRAM), color: .green.opacity(0.7),
                                      label: "Cached: \(String(format: "%.1f", systemMonitor.cachedRAM)) GB")
                        ], height: 12)
                        SMChartLegend(entries: [
                            .init(label: "App", color: .blue, value: gb(systemMonitor.appRAM)),
                            .init(label: "Wired", color: .red.opacity(0.8), value: gb(systemMonitor.wiredRAM)),
                            .init(label: "Compressed", color: .purple.opacity(0.8), value: gb(systemMonitor.compressedRAM)),
                            .init(label: "Cached", color: .green.opacity(0.7), value: gb(systemMonitor.cachedRAM))
                        ])
                        SMHistoryChart(
                            series: [SMChartSeries(values: systemMonitor.series(\.ramUsage), color: .blue)],
                            maxHeight: 100,
                            filledCount: max(systemMonitor.historyFilledCount, 2),
                            gridDivisions: 4
                        )
                        .frame(height: 64)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    SMCard("Pressure") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(pressureColor)
                                    .frame(width: 8, height: 8)
                                Text(systemMonitor.memoryPressure)
                                    .barikPopupFont(size: 13, weight: .semibold, design: .rounded)
                            }
                            SMStatRow(label: "Swap used", value: gb(systemMonitor.swapUsedRAM),
                                      valueColor: systemMonitor.swapUsedRAM > 1 ? .orange : .primary)
                            SMStatRow(label: "Free", value: gb(systemMonitor.freeRAM))
                        }
                    }
                    SMCard("Breakdown") {
                        VStack(alignment: .leading, spacing: 6) {
                            SMStatRow(label: "Active", value: gb(systemMonitor.activeRAM))
                            SMStatRow(label: "Inactive", value: gb(systemMonitor.inactiveRAM))
                            SMStatRow(label: "Total", value: gb(systemMonitor.totalRAM))
                        }
                    }
                }
                .frame(width: 200)
            }

            SMCard("Top Processes") {
                SMProcessList(
                    processes: systemMonitor.topMemoryProcesses,
                    emptyText: "Collecting…",
                    valueText: { process in
                        let cpu = process.secondary.map { String(format: " · %.1f%% CPU", $0) } ?? ""
                        return SMFormat.bytes(process.primary) + cpu
                    },
                    tint: .blue
                )
            }
        }
    }

    private func fraction(_ gbValue: Double) -> Double {
        systemMonitor.totalRAM > 0 ? min(max(gbValue / systemMonitor.totalRAM, 0), 1) : 0
    }

    private func gb(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }

    private var pressureColor: Color {
        switch systemMonitor.memoryPressure {
        case "Critical": .red
        case "Warning": .orange
        default: .green
        }
    }
}

struct SMDiskPage: View {
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared

    var body: some View {
        SMPageScroll {
            HStack(alignment: .top, spacing: 10) {
                SMCard("Activity") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Read")
                                    .barikPopupFont(size: 10, weight: .medium, design: .rounded)
                                    .foregroundStyle(.secondary)
                                Text(SMFormat.bytesPerSecond(systemMonitor.diskReadBps))
                                    .barikPopupFont(size: 16, weight: .bold, design: .monospaced)
                                    .foregroundStyle(.cyan)
                                    .contentTransition(.numericText())
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Write")
                                    .barikPopupFont(size: 10, weight: .medium, design: .rounded)
                                    .foregroundStyle(.secondary)
                                Text(SMFormat.bytesPerSecond(systemMonitor.diskWriteBps))
                                    .barikPopupFont(size: 16, weight: .bold, design: .monospaced)
                                    .foregroundStyle(.orange)
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                        }
                        SMHistoryChart(
                            series: [
                                SMChartSeries(values: systemMonitor.series(\.diskWriteBps), color: .orange, bar: true),
                                SMChartSeries(values: systemMonitor.series(\.diskReadBps), color: .cyan, bar: true)
                            ],
                            filledCount: max(systemMonitor.historyFilledCount, 2)
                        )
                        .frame(height: 90)
                    }
                }
                .frame(maxWidth: .infinity)

                SMCard("Volume") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "internaldrive.fill")
                                .foregroundStyle(.secondary)
                            Text(systemMonitor.diskVolumeName)
                                .barikPopupFont(size: 12, weight: .semibold, design: .rounded)
                                .lineLimit(1)
                        }
                        SMStackedBar(segments: [
                            SMSegment(fraction: systemMonitor.diskUsage / 100, color: .indigo,
                                      label: "Used: \(String(format: "%.0f", systemMonitor.usedDisk)) GB")
                        ], height: 12)
                        VStack(alignment: .leading, spacing: 6) {
                            SMStatRow(label: "Used", value: gb(systemMonitor.usedDisk))
                            SMStatRow(label: "Free", value: gb(systemMonitor.freeDisk))
                            SMStatRow(label: "Total", value: gb(systemMonitor.totalDisk))
                        }
                    }
                }
                .frame(width: 200)
            }
        }
    }

    private func gb(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }
}

struct SMNetworkPage: View {
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared

    var body: some View {
        SMPageScroll {
            HStack(alignment: .top, spacing: 10) {
                SMCard("Throughput") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 28) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .barikPopupFont(size: 11)
                                        .foregroundStyle(.green)
                                    Text("Download")
                                        .barikPopupFont(size: 10, weight: .medium, design: .rounded)
                                        .foregroundStyle(.secondary)
                                }
                                Text(SMFormat.bytesPerSecond(systemMonitor.downloadSpeed * 1_048_576))
                                    .barikPopupFont(size: 17, weight: .bold, design: .monospaced)
                                    .foregroundStyle(.green)
                                    .contentTransition(.numericText())
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .barikPopupFont(size: 11)
                                        .foregroundStyle(.blue)
                                    Text("Upload")
                                        .barikPopupFont(size: 10, weight: .medium, design: .rounded)
                                        .foregroundStyle(.secondary)
                                }
                                Text(SMFormat.bytesPerSecond(systemMonitor.uploadSpeed * 1_048_576))
                                    .barikPopupFont(size: 17, weight: .bold, design: .monospaced)
                                    .foregroundStyle(.blue)
                                    .contentTransition(.numericText())
                            }
                            Spacer()
                        }
                        SMHistoryChart(
                            series: [
                                SMChartSeries(values: systemMonitor.series(\.downloadBps), color: .green),
                                SMChartSeries(values: systemMonitor.series(\.uploadBps), color: .blue)
                            ],
                            filledCount: max(systemMonitor.historyFilledCount, 2)
                        )
                        .frame(height: 96)
                    }
                }
                .frame(maxWidth: .infinity)

                SMCard("Interface") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(systemMonitor.networkLinkIsUp ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(systemMonitor.networkLinkIsUp ? "Connected" : "Offline")
                                .barikPopupFont(size: 13, weight: .semibold, design: .rounded)
                        }
                        SMStatRow(label: "Interface",
                                  value: systemMonitor.activeNetworkInterface.isEmpty
                                      ? "--" : systemMonitor.activeNetworkInterface,
                                  monospaced: false)
                        SMStatRow(label: "Downloaded", value: SMFormat.bytes(systemMonitor.totalDownloadedBytes))
                        SMStatRow(label: "Uploaded", value: SMFormat.bytes(systemMonitor.totalUploadedBytes))
                    }
                }
                .frame(width: 200)
            }

            SMCard("Top Processes") {
                SMProcessList(
                    processes: systemMonitor.topNetworkProcesses,
                    emptyText: "Idle",
                    valueText: { process in
                        let up = process.secondary.map { " ↑ " + SMFormat.bytesPerSecond($0) } ?? ""
                        return "↓ " + SMFormat.bytesPerSecond(process.primary) + up
                    },
                    tint: .green
                )
            }
        }
    }
}
