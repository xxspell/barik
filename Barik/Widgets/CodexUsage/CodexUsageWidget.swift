import SwiftUI

struct CodexUsageWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var usageManager = CodexUsageManager.shared

    @State private var widgetFrame: CGRect = .zero

    private var percentage: Double {
        normalizedProgress(usageManager.usageData.primaryPercentage)
    }

    private var remainingPercentage: Double {
        normalizedProgress(1 - percentage)
    }

    private var ringColor: Color {
        if percentage >= 0.8 { return .red }
        if percentage >= 0.6 { return .orange }
        return .white
    }

    var body: some View {
        ZStack {
            if usageManager.usageData.isAvailable {
                ringShape
            }

            drainableIcon
        }
        .frame(width: 28, height: 28)
        .foregroundStyle(.foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        widgetFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        widgetFrame = newFrame
                    }
            }
        )
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "codex-usage") {
                CodexUsagePopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            usageManager.startUpdating(config: configProvider.config)
        }
    }

    private var drainableIcon: some View {
        let iconSize: CGFloat = 16

        return ZStack {
            Image("CodexIcon")
                .resizable()
                .scaledToFit()
                .opacity(0.28)
                .frame(width: iconSize, height: iconSize)

            if remainingPercentage >= 1 {
                Image("CodexIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            } else if remainingPercentage > 0 {
                Image("CodexIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .mask(
                        Rectangle()
                            .frame(width: iconSize, height: iconSize * remainingPercentage)
                            .frame(width: iconSize, height: iconSize, alignment: .bottom)
                    )
            }
        }
        .animation(.easeOut(duration: 0.8), value: remainingPercentage)
    }

    @ViewBuilder
    private var ringShape: some View {
        if percentage >= 1 {
            Circle()
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
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
