import SwiftUI

struct CLIProxyUsageWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var usageManager = CLIProxyUsageManager.shared

    @AppStorage(cliProxyUsageSelectedProviderKey)
    private var selectedProviderRawValue = CLIProxyProviderFilter.all.rawValue

    @State private var widgetFrame: CGRect = .zero

    private var selectedProvider: CLIProxyProviderFilter {
        CLIProxyProviderFilter(rawValue: selectedProviderRawValue) ?? .all
    }

    private var quotaSummary: CLIProxyQuotaSummary {
        usageManager.usageData.quotaSummary(for: selectedProvider)
    }

    private var quotaPercentageText: String {
        "\(Int((quotaSummary.percentage * 100).rounded()))%"
    }

    private var showRing: Bool {
        boolConfig(named: ["show-ring", "show_ring"], default: false)
    }

    private var showLabel: Bool {
        if let explicit = optionalBoolConfig(named: ["show-label", "show_label"]) {
            return explicit
        }
        return !showRing
    }

    private var ringLogic: String {
        stringConfig(named: ["ring-logic", "ring_logic"], default: "healthy")
    }

    private var ringFraction: Double {
        let healthyFraction = quotaSummary.percentage
        if ringLogic == "failed" {
            return normalizedProgress(1 - healthyFraction)
        }
        return normalizedProgress(healthyFraction)
    }

    private var warnThreshold: Double {
        if let value = intConfig(named: ["warning-level", "warning_level"]) {
            return Double(value) / 100.0
        }
        if let value = intConfig(named: ["ring-warning-level", "ring_warning_level"]) {
            return normalizedProgress(Double(value) / 100.0)
        }
        return 0.15
    }

    private var criticalThreshold: Double {
        if let value = intConfig(named: ["critical-level", "critical_level"]) {
            return Double(value) / 100.0
        }
        if let value = intConfig(named: ["ring-critical-level", "ring_critical_level"]) {
            return normalizedProgress(Double(value) / 100.0)
        }
        return 0.3
    }

    private var ringColor: Color {
        let remainingFraction = normalizedProgress(quotaSummary.percentage)
        if remainingFraction <= criticalThreshold { return .red }
        if remainingFraction <= warnThreshold { return .orange }
        return .white
    }

    private var showArc: Bool {
        guard showRing, usageManager.usageData.isAvailable else { return false }
        if ringLogic == "healthy" { return true }
        return ringFraction > 0
    }

    var body: some View {
        widgetBody
    }

    private var widgetBody: AnyView {
        let ring = ringLayerView()
        let content = widgetContentView()
        let stack = AnyView(ZStack {
            ring
            content
        })
        let sized = AnyView(stack.frame(width: showRing ? 30 : nil, height: showRing ? 28 : nil))
        let styled = AnyView(
            sized
                .foregroundStyle(.foregroundOutside)
                .shadow(color: .foregroundShadowOutside, radius: 3)
                .experimentalConfiguration(cornerRadius: 15)
                .frame(maxHeight: .infinity)
                .background(.black.opacity(0.001))
                .background(widgetFrameReader)
        )
        let interactive = AnyView(
            styled
                .onTapGesture {
                    MenuBarPopup.show(rect: widgetFrame, id: "cliproxy-usage") {
                        CLIProxyUsagePopup()
                            .environmentObject(configProvider)
                    }
                }
                .onAppear {
                    usageManager.startUpdating(config: configProvider.config)
                }
                .onChange(of: configProvider.config["base-url"]?.stringValue) { _, _ in
                    usageManager.startUpdating(config: configProvider.config)
                }
                .onChange(of: configProvider.config["base_url"]?.stringValue) { _, _ in
                    usageManager.startUpdating(config: configProvider.config)
                }
                .onChange(of: configProvider.config["api-key"]?.stringValue) { _, _ in
                    usageManager.startUpdating(config: configProvider.config)
                }
                .onChange(of: configProvider.config["api_key"]?.stringValue) { _, _ in
                    usageManager.startUpdating(config: configProvider.config)
                }
                .onChange(of: configProvider.config["refresh-interval"]?.intValue) { _, _ in
                    usageManager.startUpdating(config: configProvider.config)
                }
                .onChange(of: configProvider.config["refresh_interval"]?.intValue) { _, _ in
                    usageManager.startUpdating(config: configProvider.config)
                }
                .onChange(of: configProvider.config["refresh-interval"]?.stringValue) { _, _ in
                    usageManager.startUpdating(config: configProvider.config)
                }
                .onChange(of: configProvider.config["refresh_interval"]?.stringValue) { _, _ in
                    usageManager.startUpdating(config: configProvider.config)
                }
        )

        return interactive
    }

    private func ringLayerView() -> AnyView {
        if showArc {
            return ringShapeView()
        }
        return AnyView(EmptyView())
    }

    private var widgetFrameReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { widgetFrame = geometry.frame(in: .global) }
                .onChange(of: geometry.frame(in: .global)) { _, frame in
                    widgetFrame = frame
                }
        }
    }

    private func widgetContentView() -> AnyView {
        let iconSize: CGFloat = 15

        if showRing {
            return AnyView(ZStack(alignment: .bottomTrailing) {
                proxyIcon(size: iconSize)

                if showLabel, usageManager.usageData.isAvailable {
                    Text(String(quotaPercentageText.dropLast()))
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 2)
                        .background(Color.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .offset(x: 6, y: 4)
                }
            })
        } else {
            return AnyView(HStack(spacing: 4) {
                proxyIcon(size: iconSize)

                if showLabel {
                    if usageManager.usageData.isAvailable {
                        Text(quotaPercentageText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.foregroundOutside)
                    } else if usageManager.fetchFailed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }
                }
            })
        }
    }

    private func proxyIcon(size: CGFloat) -> some View {
        let fraction = usageManager.usageData.isAvailable
            ? normalizedProgress(quotaSummary.percentage)
            : 1.0
        let icon = Image(systemName: "server.rack")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)

        return ZStack {
            icon
                .foregroundStyle(.white.opacity(0.28))

            if fraction >= 1 {
                icon
                    .foregroundStyle(.white)
            } else if fraction > 0 {
                icon
                    .foregroundStyle(.white)
                    .mask(
                        Rectangle()
                            .frame(width: size, height: size * fraction)
                            .frame(width: size, height: size, alignment: .bottom)
                    )
            }
        }
        .animation(.easeOut(duration: 0.8), value: fraction)
    }

    private func ringShapeView() -> AnyView {
        if ringFraction >= 1 {
            return AnyView(
                Circle()
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            )
        } else {
            return AnyView(
                Circle()
                    .trim(
                        from: 0.5 - ringFraction / 2,
                        to: 0.5 + ringFraction / 2
                    )
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(90))
            )
        }
    }

    private func normalizedProgress(_ value: Double) -> Double {
        let clamped = max(0, min(1, value))
        if clamped >= 0.999 { return 1 }
        if clamped <= 0.001 { return 0 }
        return clamped
    }

    private func stringConfig(named keys: [String], default defaultValue: String) -> String {
        for key in keys {
            if let value = configProvider.config[key]?.stringValue {
                return value
            }
        }
        return defaultValue
    }

    private func intConfig(named keys: [String]) -> Int? {
        for key in keys {
            if let value = configProvider.config[key]?.intValue {
                return value
            }
        }
        return nil
    }

    private func optionalBoolConfig(named keys: [String]) -> Bool? {
        for key in keys {
            if let value = configProvider.config[key]?.boolValue {
                return value
            }
        }
        return nil
    }

    private func boolConfig(named keys: [String], default defaultValue: Bool) -> Bool {
        optionalBoolConfig(named: keys) ?? defaultValue
    }
}
