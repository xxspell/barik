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
            return 1 - healthyFraction
        }
        return healthyFraction
    }

    private var warnThreshold: Double {
        if let value = intConfig(named: ["ring-warning-level", "ring_warning_level"]) {
            return Double(value) / 100.0
        }
        return ringLogic == "healthy" ? 0.8 : 0.2
    }

    private var criticalThreshold: Double {
        if let value = intConfig(named: ["ring-critical-level", "ring_critical_level"]) {
            return Double(value) / 100.0
        }
        return ringLogic == "healthy" ? 0.6 : 0.4
    }

    private var ringColor: Color {
        if ringLogic == "healthy" {
            if ringFraction < criticalThreshold { return .red }
            if ringFraction < warnThreshold { return .orange }
            return .white
        }

        if ringFraction >= criticalThreshold { return .red }
        if ringFraction >= warnThreshold { return .orange }
        return .white
    }

    private var showArc: Bool {
        guard showRing, usageManager.usageData.isAvailable else { return false }
        if ringLogic == "healthy" { return true }
        return ringFraction > 0
    }

    var body: some View {
        ZStack {
            if showArc {
                Circle()
                    .trim(
                        from: 0.5 - min(ringFraction, 1.0) / 2,
                        to: 0.5 + min(ringFraction, 1.0) / 2
                    )
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .animation(.easeOut(duration: 0.3), value: ringFraction)
            }

            widgetContent
        }
        .frame(width: showRing ? 30 : nil, height: showRing ? 28 : nil)
        .foregroundStyle(.foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { widgetFrame = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, frame in
                        widgetFrame = frame
                    }
            }
        )
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
    }

    @ViewBuilder
    private var widgetContent: some View {
        let iconSize: CGFloat = 15

        if showRing {
            ZStack(alignment: .bottomTrailing) {
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
            }
        } else {
            HStack(spacing: 4) {
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
            }
        }
    }

    private func proxyIcon(size: CGFloat) -> some View {
        let fraction = usageManager.usageData.isAvailable
            ? max(0, min(1, quotaSummary.percentage))
            : 1.0

        return ZStack {
            Image(systemName: "server.rack")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))

            Image(systemName: "server.rack")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .mask(
                    Rectangle()
                        .frame(width: size * 1.6, height: size * fraction)
                        .frame(width: size * 1.6, height: size * 1.6, alignment: .bottom)
                )
                .animation(.easeOut(duration: 0.8), value: fraction)
        }
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
