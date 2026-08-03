import SwiftUI

struct ClaudeUsageWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var usageManager = ClaudeUsageManager.shared

    @State private var widgetFrame: CGRect = .zero

    private var percentage: Double {
        normalizedProgress(usageManager.usageData.fiveHourPercentage)
    }

    private var weeklyRemaining: Double {
        normalizedProgress(1 - usageManager.usageData.weeklyPercentage)
    }

    private var ringColor: Color {
        let style = BarikStyle.current
        if style.isTUI {
            return percentage >= 0.6 ? style.accent : style.foreground
        }
        if percentage >= 0.8 { return .red }
        if percentage >= 0.6 { return .orange }
        return .white
    }

    var body: some View {
        BarikStyle.current.isTUI ? AnyView(tuiBody) : AnyView(defaultBody)
    }

    private var tuiBody: some View {
        HStack(spacing: 4) {
            Image("ClaudeIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 13, height: 13)
            tuiUsageView
                .barikFont(size: 12, weight: .medium, design: .monospaced)
        }
        .foregroundStyle(.foregroundOutside)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .captureScreenRect(into: $widgetFrame)
        .contentShape(Rectangle())
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "claude-usage") {
                ClaudeUsagePopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            usageManager.startUpdating(config: configProvider.config)
        }
    }

    @ViewBuilder
    private var tuiUsageView: some View {
        let style = BarikStyle.current
        if usageManager.usageData.isAvailable {
            let session = Int((usageManager.usageData.fiveHourPercentage * 100).rounded())
            let weekly = Int((usageManager.usageData.weeklyPercentage * 100).rounded())
            HStack(spacing: 0) {
                Text("\(session)%").foregroundStyle(style.foreground)
                Text("/").foregroundStyle(style.dim)
                Text("\(weekly)%").foregroundStyle(style.foreground)
            }
        } else {
            Text("--").foregroundStyle(style.dim)
        }
    }

    private var defaultBody: some View {
        ZStack {
            if usageManager.usageData.isAvailable {
                ringShape
            }

            drainableIcon
        }
        .frame(width: BarikStyle.current.isTUI ? 16 : 28, height: BarikStyle.current.isTUI ? 16 : 28)
        .foregroundStyle(.foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: BarikStyle.current.isTUI ? 0 : 3)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .captureScreenRect(into: $widgetFrame)
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "claude-usage") {
                ClaudeUsagePopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            usageManager.startUpdating(config: configProvider.config)
        }
    }

    private var drainableIcon: some View {
        let style = BarikStyle.current
        let iconSize: CGFloat = style.isTUI ? 14 : 16
        let baseColor: Color = style.isTUI ? style.foreground.opacity(0.3) : .white.opacity(0.3)
        let fillColor: Color = style.isTUI ? style.foreground : .white

        return ZStack {
            Image("ClaudeIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(baseColor)
                .frame(width: iconSize, height: iconSize)

            if weeklyRemaining >= 1 {
                Image("ClaudeIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(fillColor)
                    .frame(width: iconSize, height: iconSize)
            } else if weeklyRemaining > 0 {
                Rectangle()
                    .fill(fillColor)
                    .frame(width: iconSize, height: iconSize * weeklyRemaining)
                    .frame(width: iconSize, height: iconSize, alignment: .bottom)
                    .mask(
                        Image("ClaudeIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize, height: iconSize)
                    )
            }
        }
        .animation(.easeOut(duration: 0.8), value: weeklyRemaining)
    }

    @ViewBuilder
    private var ringShape: some View {
        if percentage >= 1 {
            Circle()
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
        } else {
            Circle()
                .trim(
                    from: 0.5 - percentage / 2,
                    to: 0.5 + percentage / 2
                )
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
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
