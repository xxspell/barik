import SwiftUI

/// Builds the concrete SwiftUI view for a widget id. Shared by the live
/// bar (`MenuBarView`) and the dev-only widget exporter (`WidgetExporter`)
/// so both render identical widgets.
enum WidgetViewFactory {
    @ViewBuilder
    static func build(
        for item: TomlWidgetItem,
        configManager: ConfigManager,
        monitor: MonitorDescriptor,
        screenRecordingManager: ScreenRecordingManager
    ) -> some View {
        let config = ConfigProvider(
            config: configManager.resolvedWidgetConfig(for: item))

        switch item.id {
        case "default.spaces":
            SpacesWidget(monitorID: monitor.id).environmentObject(config)

        case "default.network":
            NetworkWidget().environmentObject(config)

        case "default.battery":
            BatteryWidget().environmentObject(config)

        case "default.time":
            TimeWidget(calendarManager: CalendarManager(configProvider: config))
                .environmentObject(config)

        case "default.qwen-proxy-usage":
            QwenProxyUsageWidget()
                .environmentObject(config)

        case "default.github":
            GitHubWidget()
                .environmentObject(config)

        case "default.cliproxy-usage":
            CLIProxyUsageWidget()
                .environmentObject(config)

        case "default.nowplaying":
            NowPlayingWidget()
                .environmentObject(config)

        case "default.homebrew":
            HomebrewWidget()
                .environmentObject(config)

        case "default.claude-usage":
            ClaudeUsageWidget()
                .environmentObject(config)

        case "default.codex-usage":
            CodexUsageWidget()
                .environmentObject(config)

        case "default.system-monitor", "default.cpuram":
            SystemMonitorWidget()
                .environmentObject(config)

        case "default.weather":
            WeatherWidget()
                .environmentObject(config)

        case "default.screen-recording-stop":
            ScreenRecordingWidget(manager: screenRecordingManager)
                .environmentObject(config)

        case "default.keyboard-layout":
            KeyboardLayoutWidget()
                .environmentObject(config)

        case "default.focus":
            FocusWidget()
                .environmentObject(config)

        case "spacer":
            Spacer()

        case "divider":
            let style = BarikStyle.current
            Rectangle()
                .fill(style.isTUI ? style.dim : Color.active)
                .frame(width: style.isTUI ? 1 : 2, height: style.isTUI ? 12 : 15)
                .clipShape(Capsule())

        case "default.ticktick":
            TickTickWidget()
                .environmentObject(config)

        case "default.pomodoro":
            PomodoroWidget()
                .environmentObject(config)

        case "default.shortcuts":
            ShortcutsWidget()
                .environmentObject(config)

        case "system-banner":
            SystemBannerWidget()

        default:
            Text("?\(item.id)?").foregroundColor(.red)
        }
    }
}
