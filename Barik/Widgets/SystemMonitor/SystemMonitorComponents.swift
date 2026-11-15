import SwiftUI

// MARK: - Formatting

enum SMFormat {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func bytes(_ value: Double) -> String {
        byteFormatter.string(fromByteCount: Int64(max(0, value)))
    }

    static func bytes(_ value: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(value))
    }

    static func bytesPerSecond(_ value: Double) -> String {
        let formatted = byteFormatter.string(fromByteCount: Int64(max(0, value)))
        return formatted + "/s"
    }

    static func percent(_ value: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", max(0, value))
    }

    /// Load average with adaptive precision.
    static func load(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    static func hz(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f Hz", value) : String(format: "%.1f Hz", value)
    }
}

// MARK: - Section card

struct SMCard<Content: View>: View {
    let title: String?
    let accessory: AnyView?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, accessory: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack {
                    Text(LocalizedStringKey(title))
                        .barikPopupFont(size: 11, weight: .semibold, design: .rounded)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    accessory
                }
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.tertiaryLabelColor).opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - History chart

/// Canvas-based multi-series chart. Values are oldest→newest with trailing
/// alignment, so a partly filled window renders pinned to the right edge.
struct SMChartSeries: Identifiable {
    let id = UUID()
    let values: [Double]
    let color: Color
    /// When true the area under the line is filled.
    var filled: Bool = true
    /// Draw as vertical bars (throughput style) instead of a line.
    var bar: Bool = false
}

struct SMHistoryChart: View {
    let series: [SMChartSeries]
    var maxHeight: Double? = nil
    /// How many trailing samples the x-axis spans; earlier slots are blank.
    var filledCount: Int
    /// Horizontal grid lines at fixed fractions when set (e.g. 100 for %).
    var gridDivisions: Int = 0
    var cornerRadius: CGFloat = 6

    @Environment(\.smShowCharts) private var showCharts

    var body: some View {
        if showCharts {
            chartBody
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        Canvas { context, size in
            let allValues = series.flatMap(\.values)
            let dataMax = max(allValues.max() ?? 0, 0.0001)
            let ceiling = maxHeight ?? dataMax * 1.15
            guard ceiling > 0 else { return }

            let count = series.first?.values.count ?? 0
            guard count > 0 else { return }
            let visible = max(2, min(count, max(filledCount, 2)))
            let stepX = size.width / CGFloat(visible - 1)

            if gridDivisions > 1 {
                for division in 1..<gridDivisions {
                    let y = size.height * CGFloat(division) / CGFloat(gridDivisions)
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(Color(NSColor.separatorColor).opacity(0.35)), lineWidth: 0.5)
                }
            }

            for lineSeries in series where !lineSeries.bar {
                let offset = count - visible
                var path = Path()
                var area = Path()
                var lastPoint = CGPoint(x: 0, y: size.height)
                for index in 0..<visible {
                    let value = lineSeries.values[offset + index]
                    let x = CGFloat(index) * stepX
                    let y = size.height * (1 - min(max(value / ceiling, 0), 1))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                        area.move(to: CGPoint(x: x, y: size.height))
                        area.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                        area.addLine(to: CGPoint(x: x, y: y))
                    }
                    lastPoint = CGPoint(x: x, y: y)
                }
                area.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
                area.closeSubpath()

                if lineSeries.filled {
                    context.fill(area, with: .linearGradient(
                        Gradient(colors: [lineSeries.color.opacity(0.45), lineSeries.color.opacity(0.05)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    ))
                }
                context.stroke(path, with: .color(lineSeries.color), lineWidth: 1.4)
            }

            for barSeries in series where barSeries.bar {
                let offset = count - visible
                let barWidth = max(1, size.width / CGFloat(visible) - 1)
                for index in 0..<visible {
                    let value = barSeries.values[offset + index]
                    guard value > 0 else { continue }
                    let height = size.height * min(max(value / ceiling, 0), 1)
                    let x = (CGFloat(index) / CGFloat(visible)) * size.width
                    let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(barSeries.color))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Legend & labels

struct SMChartLegend: View {
    struct Entry: Identifiable {
        let id = UUID()
        let label: String
        let color: Color
        let value: String?
    }

    let entries: [Entry]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(entries) { entry in
                HStack(spacing: 4) {
                    Circle().fill(entry.color).frame(width: 6, height: 6)
                    Text(LocalizedStringKey(entry.label))
                        .barikPopupFont(size: 10, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                    if let value = entry.value {
                        Text(value)
                            .barikPopupFont(size: 10, weight: .semibold, design: .monospaced)
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
    }
}

/// Big rounded number with unit suffix, used as page hero.
struct SMHeroMetric: View {
    let value: String
    let unit: String
    var color: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .barikPopupFont(size: 30, weight: .bold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(LocalizedStringKey(unit))
                .barikPopupFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Stat rows

struct SMStatRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var monospaced: Bool = true

    var body: some View {
        HStack {
            Text(LocalizedStringKey(label))
                .barikPopupFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .barikPopupFont(size: 11, weight: .semibold, design: monospaced ? .monospaced : .rounded)
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
                .textSelection(.enabled)
        }
    }
}

// MARK: - Stacked / segmented bar

struct SMSegment: Identifiable {
    let id = UUID()
    let fraction: Double
    let color: Color
    let label: String
}

/// Horizontal 100% bar with segments (memory breakdown, disk usage).
struct SMStackedBar: View {
    let segments: [SMSegment]
    var height: CGFloat = 10
    var trackColor: Color = Color(NSColor.quaternaryLabelColor)

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(segment.color)
                        .frame(width: max(2, proxy.size.width * segment.fraction - 1.5))
                        .help(segment.label)
                }
                Color.clear
            }
            .frame(height: height)
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(trackColor.opacity(0.6))
        )
    }
}

/// Thin linear gauge for a single percentage.
struct SMLinearGauge: View {
    let fraction: Double
    var color: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(NSColor.quaternaryLabelColor))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Ring gauge (overview tiles)

struct SMRingGauge: View {
    let fraction: Double
    let color: Color
    let centerText: String
    var caption: String?

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            VStack(spacing: 0) {
                Text(centerText)
                    .barikPopupFont(size: 15, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let caption {
                    Text(LocalizedStringKey(caption))
                        .barikPopupFont(size: 8, weight: .medium, design: .rounded)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Process list

struct SMProcessRow: View {
    let process: TopProcess
    let valueText: (TopProcess) -> String
    let valueFraction: (TopProcess) -> Double
    var tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = process.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "terminal")
                        .barikPopupFont(size: 12)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
            }
            Text(process.name)
                .barikPopupFont(size: 11, weight: .medium, design: .rounded)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(valueText(process))
                .barikPopupFont(size: 10, weight: .semibold, design: .monospaced)
                .foregroundStyle(tint)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: proxy.size.width * min(max(valueFraction(process), 0), 1))
            }
        }
    }
}

struct SMProcessList: View {
    let processes: [TopProcess]
    let emptyText: String
    let valueText: (TopProcess) -> String
    let tint: Color

    var body: some View {
        if processes.isEmpty {
            Text(LocalizedStringKey(emptyText))
                .barikPopupFont(size: 11, weight: .medium, design: .rounded)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            let maxPrimary = processes.map(\.primary).max() ?? 1
            VStack(spacing: 2) {
                ForEach(processes) { process in
                    SMProcessRow(
                        process: process,
                        valueText: valueText,
                        valueFraction: { $0.primary / max(maxPrimary, 0.0001) },
                        tint: tint
                    )
                }
            }
        }
    }
}

/// `popup.show-charts`: when false every history chart in the dashboard is hidden.
private struct SMShowChartsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var smShowCharts: Bool {
        get { self[SMShowChartsKey.self] }
        set { self[SMShowChartsKey.self] = newValue }
    }
}
