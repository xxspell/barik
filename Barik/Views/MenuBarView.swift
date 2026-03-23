import SwiftUI

struct MenuBarView: View {
    let monitor: MonitorDescriptor

    @ObservedObject var configManager = ConfigManager.shared
    @StateObject private var screenRecordingManager = ScreenRecordingManager.shared
    private var horizontalPadding: CGFloat {
        configManager.config.experimental.foreground.horizontalPadding
    }
    private var notchZonePadding: CGFloat {
        configManager.config.experimental.foreground.notchHorizontalPadding
    }

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

        let items = configManager.displayedWidgets(for: monitor.id)

        Group {
            if usesNotchAwareLayout {
                notchAwareLayout(items: items)
            } else {
                standardLayout(items: items)
            }
        }
        .foregroundStyle(Color.foregroundOutside)
        .frame(height: max(configManager.config.experimental.foreground.resolveHeight(), 1.0))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, usesNotchAwareLayout ? 0 : horizontalPadding)
        .background(.black.opacity(0.001))
        .preferredColorScheme(theme)
        .onAppear {
            requestScreenRecordingAccessibilityPermissionIfNeeded(for: items)
        }
        .onChange(of: items.map(\.id)) { _, newItemIDs in
            requestScreenRecordingAccessibilityPermissionIfNeeded(for: newItemIDs)
        }
    }

    private var usesNotchAwareLayout: Bool {
        monitor.hasTopInsetCutout && itemsContainSpacerForSplit
    }

    private var itemsContainSpacerForSplit: Bool {
        configManager
            .displayedWidgets(for: monitor.id)
            .contains(where: { $0.id == "spacer" })
    }

    @ViewBuilder
    private func standardLayout(items: [TomlWidgetItem]) -> some View {
        HStack(spacing: 0) {
            widgetRow(items)
                .padding(.horizontal, horizontalPadding)

            if !items.contains(where: { $0.id == "system-banner" }) {
                SystemBannerWidget(withLeftPadding: true)
                    .padding(.trailing, horizontalPadding)
            }
        }
    }

    @ViewBuilder
    private func notchAwareLayout(items: [TomlWidgetItem]) -> some View {
        let split = splitItemsForNotch(items)
        let rightItems = split.rightItems + trailingSystemBannerItems(from: items)

        HStack(spacing: 0) {
            widgetRow(split.leftItems)
                .padding(.leading, notchZonePadding)
                .frame(
                    width: max(monitor.auxiliaryTopLeftArea.width, 0),
                    alignment: .leading
                )

            Spacer(minLength: max(monitor.notchGapWidth, 0))
                .frame(maxWidth: max(monitor.notchGapWidth, 0))

            widgetRow(rightItems, alignment: .trailing)
                .padding(.trailing, notchZonePadding)
                .frame(
                    width: max(monitor.auxiliaryTopRightArea.width, 0),
                    alignment: .trailing
                )
        }
    }

    @ViewBuilder
    private func widgetRow(
        _ items: [TomlWidgetItem],
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        HStack(spacing: configManager.config.experimental.foreground.spacing) {
            ForEach(0..<items.count, id: \.self) { index in
                let item = items[index]
                buildView(for: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func splitItemsForNotch(_ items: [TomlWidgetItem]) -> (leftItems: [TomlWidgetItem], rightItems: [TomlWidgetItem]) {
        guard let spacerIndex = items.firstIndex(where: { $0.id == "spacer" }) else {
            return (items, [])
        }

        let leftItems = Array(items[..<spacerIndex])
        let rightStart = items.index(after: spacerIndex)
        let rightItems = rightStart < items.endIndex
            ? Array(items[rightStart...])
            : []

        return (leftItems, rightItems)
    }

    private func trailingSystemBannerItems(from items: [TomlWidgetItem]) -> [TomlWidgetItem] {
        guard !items.contains(where: { $0.id == "system-banner" }) else {
            return []
        }

        return [TomlWidgetItem(id: "system-banner", inlineParams: [:])]
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

        case "default.keyboard-layout":
            KeyboardLayoutWidget()
                .environmentObject(config)

        case "default.focus":
            FocusWidget()
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

    private func requestScreenRecordingAccessibilityPermissionIfNeeded(for items: [TomlWidgetItem]) {
        requestScreenRecordingAccessibilityPermissionIfNeeded(for: items.map(\.id))
    }

    private func requestScreenRecordingAccessibilityPermissionIfNeeded(for itemIDs: [String]) {
        guard itemIDs.contains("default.screen-recording-stop") else { return }
        screenRecordingManager.requestAccessibilityPermissionIfNeeded()
    }
}
