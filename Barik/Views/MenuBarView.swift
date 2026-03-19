import SwiftUI

struct MenuBarView: View {
    @ObservedObject var configManager = ConfigManager.shared
    @StateObject private var screenRecordingManager = ScreenRecordingManager.shared

    var body: some View {
        let theme: ColorScheme? =
            switch configManager.config.rootToml.theme {
            case "dark":
                .dark
            case "light":
                .light
            default:
                .none
            }

        let items = configManager.config.rootToml.widgets.displayed

        HStack(spacing: 0) {
            HStack(spacing: configManager.config.experimental.foreground.spacing) {
                ForEach(0..<items.count, id: \.self) { index in
                    let item = items[index]
                    buildView(for: item)
                }
            }

            if !items.contains(where: { $0.id == "system-banner" }) {
                SystemBannerWidget(withLeftPadding: true)
            }
        }
        .foregroundStyle(Color.foregroundOutside)
        .frame(height: max(configManager.config.experimental.foreground.resolveHeight(), 1.0))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, configManager.config.experimental.foreground.horizontalPadding)
        .background(.black.opacity(0.001))
        .preferredColorScheme(theme)
        .onAppear {
            requestScreenRecordingAccessibilityPermissionIfNeeded(for: items)
        }
        .onChange(of: items.map(\.id)) { _, newItemIDs in
            requestScreenRecordingAccessibilityPermissionIfNeeded(for: newItemIDs)
        }
    }

    @ViewBuilder
    private func buildView(for item: TomlWidgetItem) -> some View {
        let config = ConfigProvider(
            config: configManager.resolvedWidgetConfig(for: item))

        switch item.id {
        case "default.spaces":
            SpacesWidget().environmentObject(config)

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

        case "spacer":
            Spacer().frame(minWidth: 50, maxWidth: .infinity)

        case "divider":
            Rectangle()
                .fill(Color.active)
                .frame(width: 2, height: 15)
                .clipShape(Capsule())
            
        case "default.ticktick":
            TickTickWidget()
                .environmentObject(config)

        case "system-banner":
            SystemBannerWidget()

        default:
            Text("?\(item.id)?").foregroundColor(.red)
        }
    }

    private func requestScreenRecordingAccessibilityPermissionIfNeeded(for items: [TomlWidgetItem]) {
        requestScreenRecordingAccessibilityPermissionIfNeeded(for: items.map(\.id))
    }

    private func requestScreenRecordingAccessibilityPermissionIfNeeded(for itemIDs: [String]) {
        guard itemIDs.contains("default.screen-recording-stop") else { return }
        screenRecordingManager.requestAccessibilityPermissionIfNeeded()
    }
}
