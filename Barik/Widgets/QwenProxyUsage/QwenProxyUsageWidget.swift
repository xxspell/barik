import SwiftUI

struct QwenProxyUsageWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var usageManager = QwenProxyUsageManager.shared

    @State private var widgetFrame: CGRect = .zero

    private var showRing: Bool {
        configProvider.config["show-ring"]?.boolValue ?? false
    }

    private var showLabel: Bool {
        if let explicit = configProvider.config["show-label"]?.boolValue { return explicit }
        return !showRing
    }

    // "failed" (default, like Codex): arc = dead accounts → arc grows on problems
    // "healthy" (like Claude):        arc = live accounts → arc shrinks on problems
    private var ringLogic: String {
        configProvider.config["ring-logic"]?.stringValue ?? "failed"
    }

    private var healthyCount: Int { usageManager.usageData.summary.healthy }
    private var totalCount: Int   { usageManager.usageData.summary.total }

    private var ringFraction: Double {
        guard totalCount > 0 else { return 0 }
        if ringLogic == "healthy" {
            // Like Claude: full arc when all alive, shrinks as accounts die
            return normalizedProgress(Double(healthyCount) / Double(totalCount))
        } else {
            // Like Codex: no arc when all alive, grows as accounts die
            let failed = totalCount - healthyCount
            return normalizedProgress(Double(failed) / Double(totalCount))
        }
    }

    // Thresholds in percent (0–100). Defaults: warn=30, critical=50 for "failed" logic.
    // For "healthy" logic the values are inverted (warn triggers below warn threshold).
    private var warnThreshold: Double {
        let v = configProvider.config["ring-warning-level"]?.intValue
            ?? configProvider.config["ring-warning-level"]?.intValue
        if let v { return Double(v) / 100.0 }
        return ringLogic == "healthy" ? 0.6 : 0.3
    }

    private var criticalThreshold: Double {
        let v = configProvider.config["ring-critical-level"]?.intValue
        if let v { return Double(v) / 100.0 }
        return ringLogic == "healthy" ? 0.3 : 0.5
    }

    private var ringColor: Color {
        if ringLogic == "healthy" {
            // fraction = healthy/total — low is bad
            if ringFraction < criticalThreshold { return .red }
            if ringFraction < warnThreshold     { return .orange }
            return .white
        } else {
            // fraction = failed/total — high is bad
            if ringFraction >= criticalThreshold { return .red }
            if ringFraction >= warnThreshold     { return .orange }
            return .white
        }
    }

    private var showArc: Bool {
        guard showRing, usageManager.usageData.isAvailable else { return false }
        if ringLogic == "healthy" { return true }          // always show (like Claude)
        return ringFraction > 0                            // hide when no failures (like Codex)
    }

    var body: some View {
        ZStack {
            if showArc {
                ringShape
            }

            widgetContent
        }
        .frame(width: showRing ? 28 : nil, height: showRing ? 28 : nil)
        .foregroundStyle(.foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .captureScreenRect(into: $widgetFrame)
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "qwen-proxy-usage") {
                QwenProxyUsagePopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            usageManager.startUpdating(config: configProvider.config)
        }
        .onChange(of: configProvider.config["base-url"]?.stringValue) { _, _ in
            usageManager.startUpdating(config: configProvider.config)
        }
    }

    @ViewBuilder
    private var widgetContent: some View {
        let iconSize: CGFloat = 16

        if showRing {
            ZStack(alignment: .bottomTrailing) {
                drainableIcon(size: iconSize)
                if showLabel, usageManager.usageData.isAvailable {
                    Text("\(healthyCount)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 2)
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .offset(x: 5, y: 4)
                }
            }
        } else {
            HStack(spacing: 4) {
                drainableIcon(size: iconSize)
                if showLabel {
                    if usageManager.usageData.isAvailable {
                        Text("\(healthyCount)")
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

    // Icon drains from top (like Codex): full = all healthy, empty = all dead
    private func drainableIcon(size: CGFloat) -> some View {
        let fraction = totalCount > 0
            ? max(0, min(1, Double(healthyCount) / Double(totalCount)))
            : 1.0

        return ZStack {
            Image("QwenIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.28))
                .frame(width: size, height: size)

            if fraction >= 1 {
                Image("QwenIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
            } else if fraction > 0 {
                Image("QwenIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .mask(
                        Rectangle()
                            .frame(width: size, height: size * fraction)
                            .frame(width: size, height: size, alignment: .bottom)
                    )
            }
        }
        .animation(.easeOut(duration: 0.8), value: fraction)
    }

    @ViewBuilder
    private var ringShape: some View {
        if ringFraction >= 1 {
            Circle()
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        } else {
            Circle()
                .trim(
                    from: 0.5 - ringFraction / 2,
                    to:   0.5 + ringFraction / 2
                )
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(90))
        }
    }

    private func normalizedProgress(_ value: Double) -> Double {
        let clamped = max(0, min(1, value))
        if clamped >= 0.999 { return 1 }
        if clamped <= 0.001 { return 0 }
        return clamped
    }
}
