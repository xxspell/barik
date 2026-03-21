import SwiftUI

struct PomodoroWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = PomodoroManager.shared
    @ObservedObject private var configManager = ConfigManager.shared

    @State private var widgetFrame: CGRect = .zero

    private enum WidgetDisplayMode: String {
        case timer
        case todayPomodoros = "today-pomodoros"
    }

    private var displayMode: WidgetDisplayMode {
        WidgetDisplayMode(
            rawValue: liveConfig["display-mode"]?.stringValue?.lowercased() ?? "timer"
        ) ?? .timer
    }

    private var iconColor: Color {
        switch manager.phase {
        case .focus, .focusPaused, .waitingForBreak:
            return Color(red: 1.0, green: 0.42, blue: 0.33)
        case .breakTime, .breakPaused:
            return Color(red: 0.43, green: 0.87, blue: 0.63)
        case .idle:
            return .foregroundOutside
        }
    }

    private let timerIconSize: CGFloat = 21
    private let tomatoIconSize: CGFloat = 21
    private let tomatoSpacing: CGFloat = 8
    private let timerLabelWidth: CGFloat = 40

    private var liveConfig: ConfigData {
        configManager.globalWidgetConfig(for: "default.pomodoro")
    }

    var body: some View {
        HStack(spacing: 6) {
            switch displayMode {
            case .timer:
                timerDisplay
            case .todayPomodoros:
                todayPomodorosDisplay
            }
        }
        .padding(.horizontal, horizontalPadding)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: manager.widgetLabel == nil)
        .background(.black.opacity(0.001))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { widgetFrame = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        widgetFrame = newFrame
                    }
            }
        )
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "pomodoro") {
                PomodoroPopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            manager.startUpdating(config: liveConfig)
        }
        .onReceive(ConfigManager.shared.$config) { _ in
            manager.updateConfiguration(config: liveConfig)
        }
    }

    private var horizontalPadding: CGFloat {
        switch displayMode {
        case .timer:
            return 2
        case .todayPomodoros:
            return 2
        }
    }

    private var timerDisplay: some View {
        HStack(spacing: 6) {
            Image("PomodoroIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: timerIconSize, height: timerIconSize)
                .foregroundStyle(iconColor)

            Text(manager.widgetLabel ?? "00:00")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.foregroundOutside)
                .opacity(manager.widgetLabel == nil ? 0 : 1)
                .frame(width: manager.widgetLabel == nil ? 0 : timerLabelWidth, alignment: .center)
                .clipped()
                .lineLimit(1)
        }
        .frame(width: manager.widgetLabel == nil ? timerIconSize : timerIconSize + 6 + timerLabelWidth, alignment: .leading)
    }

    private var todayPomodorosDisplay: some View {
        HStack(spacing: tomatoSpacing) {
            if manager.statistics.todayCount == 0 {
                Image("PomodoroIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: timerIconSize, height: timerIconSize)
                    .foregroundStyle(.foregroundOutside.opacity(0.45))
            } else {
                ForEach(0..<min(manager.statistics.todayCount, 8), id: \.self) { _ in
                    Image("PomodoroIcon")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: tomatoIconSize, height: tomatoIconSize)
                        .foregroundStyle(iconColor)
                }

                if manager.statistics.todayCount > 8 {
                    Text("+\(manager.statistics.todayCount - 8)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.foregroundOutside.opacity(0.8))
                        .padding(.leading, 1)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
