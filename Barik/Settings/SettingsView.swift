import AppKit
import SwiftUI
import OSLog

private struct SettingsSectionLabel: View {
    let section: SettingsSection

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            if section.iconIsAsset {
                Image(section.iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
            } else {
                Image(systemName: section.iconName)
            }
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $router.selectedSection) {
                ForEach(SettingsSectionCategory.allCases) { category in
                    Section(category.title) {
                        ForEach(
                            SettingsSection.allCases.filter {
                                $0.category == category && $0 != .widgetExport
                            }
                        ) { section in
                            SettingsSectionLabel(section: section)
                                .tag(section)
                        }
                    }
                }

                if AppRuntimeFlags.isWidgetExportEnabled {
                    Section("Widget Export") {
                        SettingsSectionLabel(section: .widgetExport)
                            .tag(SettingsSection.widgetExport)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .scrollContentBackground(.hidden)
            .background(Color.black)
        } detail: {
            SettingsDetailView(section: router.selectedSection)
                .background(Color.black)
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(SettingsWindowConfigurator())
        .preferredColorScheme(.dark)
    }
}

private struct SettingsDetailView: View {
    let section: SettingsSection

    var body: some View {
        // `.displays` manages its own internal per-column scrolling and
        // needs the full available height to lay out its adaptive
        // wide/compact columns — nesting it in this page-level ScrollView
        // would let it collapse to content size instead of filling the
        // window, since a ScrollView proposes unbounded height to children.
        if section == .displays {
            WidgetConfiguratorView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                switch section {
                case .general:
                    GeneralSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .displays:
                    EmptyView()
                case .spaces:
                    SpacesSettingsView()
                case .time:
                    TimeSettingsView()
                case .gotify:
                    GotifySettingsView()
                case .weather:
                    WeatherSettingsView()
                case .network:
                    NetworkSettingsView()
                case .nowPlaying:
                    NowPlayingSettingsView()
                case .cliProxyUsage:
                    CLIProxyUsageSettingsView()
                case .qwenProxyUsage:
                    QwenProxyUsageSettingsView()
                case .claudeUsage:
                    ClaudeUsageSettingsView()
                case .codexUsage:
                    CodexUsageSettingsView()
                case .pomodoro:
                    PomodoroSettingsView()
                case .ticktick:
                    TickTickSettingsView()
                case .shortcuts:
                    ShortcutsSettingsView()
                case .systemMonitor:
                    SystemMonitorSettingsView()
                case .widgetExport:
                    WidgetExportView()
                case .other:
                    OtherSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared

    @State private var yabaiPath = ""
    @State private var aerospacePath = ""
    @State private var isApplyingConfigSnapshot = false

    @State private var yabaiPathTask: Task<Void, Never>?
    @State private var aerospacePathTask: Task<Void, Never>?

    private let detectedYabaiPath = YabaiConfig().path
    private let detectedAerospacePath = AerospaceConfig().path
    private let configPath = "\(NSHomeDirectory())/.barik-config.toml"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.general.header.title"),
                description: settingsLocalized("settings.general.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.general.card.window_managers"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWindowManagerPaths
            ) {
                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.general.field.yabai_path.title"),
                    description: String(
                        format: settingsLocalized("settings.general.field.yabai_path.description"),
                        locale: .autoupdatingCurrent,
                        detectedYabaiPath
                    ),
                    text: $yabaiPath
                )
                .onChange(of: yabaiPath) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    schedulePathWrite(
                        task: &yabaiPathTask,
                        key: "yabai.path",
                        value: newValue
                    )
                }

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.general.field.aerospace_path.title"),
                    description: String(
                        format: settingsLocalized("settings.general.field.aerospace_path.description"),
                        locale: .autoupdatingCurrent,
                        detectedAerospacePath
                    ),
                    text: $aerospacePath
                )
                .onChange(of: aerospacePath) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    schedulePathWrite(
                        task: &aerospacePathTask,
                        key: "aerospace.path",
                        value: newValue
                    )
                }
            }

            SettingsCardView(settingsLocalized("settings.general.card.config_file")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(settingsLocalized("settings.general.config_path.title"))
                        .font(.headline)

                    Text(configPath)
                        .font(.subheadline.monospaced())
                        .textSelection(.enabled)

                    Text(settingsLocalized("settings.general.config_path.description"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { _ in
            loadFromConfig()
        }
        .onDisappear {
            yabaiPathTask?.cancel()
            aerospacePathTask?.cancel()
        }
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true
        yabaiPath = configManager.config.rootToml.yabai?.path ?? ""
        aerospacePath = configManager.config.rootToml.aerospace?.path ?? ""
        isApplyingConfigSnapshot = false
    }

    private func schedulePathWrite(task: inout Task<Void, Never>?, key: String, value: String) {
        task?.cancel()
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            if trimmedValue.isEmpty {
                ConfigManager.shared.removeConfigValue(tablePath: nil, key: key)
            } else {
                ConfigManager.shared.updateConfigValue(key: key, newValue: trimmedValue)
            }
        }
    }

    private func resetWindowManagerPaths() {
        yabaiPathTask?.cancel()
        aerospacePathTask?.cancel()

        isApplyingConfigSnapshot = true
        yabaiPath = ""
        aerospacePath = ""
        isApplyingConfigSnapshot = false

        ConfigManager.shared.removeConfigValue(tablePath: nil, key: "yabai.path")
        ConfigManager.shared.removeConfigValue(tablePath: nil, key: "aerospace.path")
    }
}

private struct OtherSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared

    @State private var batteryShowPercentage = true
    @State private var batteryWarningLevel = 30.0
    @State private var batteryCriticalLevel = 10.0
    @State private var keyboardLayoutShowText = true
    @State private var keyboardLayoutShowOutline = true
    @State private var screenRecordingShowLabel = true
    @State private var homebrewDisplayMode = HomebrewDisplayMode.label
    @State private var focusTintWithFocusColor = true
    @State private var isApplyingConfigSnapshot = false

    private let batteryTable = "widgets.default.battery"
    private let keyboardLayoutTable = "widgets.default.keyboard-layout"
    private let screenRecordingTable = "widgets.default.screen-recording-stop"
    private let homebrewTable = "widgets.default.homebrew"
    private let focusTable = "widgets.default.focus"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.other.header.title"),
                description: settingsLocalized("settings.other.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.other.card.battery"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetBatteryDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.field.show_percentage.title"),
                    description: settingsLocalized("settings.other.battery.show_percentage.description"),
                    isOn: $batteryShowPercentage
                )
                .onChange(of: batteryShowPercentage) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: batteryTable,
                        key: "show-percentage",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.field.warning_threshold.title"),
                    description: settingsLocalized("settings.other.battery.warning_threshold.description"),
                    value: $batteryWarningLevel,
                    range: 0...100,
                    step: 1,
                    valueFormat: { "\(Int($0))%" }
                )
                .onChange(of: batteryWarningLevel) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: batteryTable,
                        key: "warning-level",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.field.critical_threshold.title"),
                    description: settingsLocalized("settings.other.battery.critical_threshold.description"),
                    value: $batteryCriticalLevel,
                    range: 0...100,
                    step: 1,
                    valueFormat: { "\(Int($0))%" }
                )
                .onChange(of: batteryCriticalLevel) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: batteryTable,
                        key: "critical-level",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.other.card.keyboard_layout"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetKeyboardLayoutDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.other.keyboard_layout.show_text.title"),
                    description: settingsLocalized("settings.other.keyboard_layout.show_text.description"),
                    isOn: $keyboardLayoutShowText
                )
                .onChange(of: keyboardLayoutShowText) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: keyboardLayoutTable,
                        key: "show-text",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }

                ToggleRow(
                    title: settingsLocalized("settings.field.show_outline.title"),
                    description: settingsLocalized("settings.other.keyboard_layout.show_outline.description"),
                    isOn: $keyboardLayoutShowOutline
                )
                .onChange(of: keyboardLayoutShowOutline) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: keyboardLayoutTable,
                        key: "show-outline",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.other.card.screen_recording_stop"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetScreenRecordingDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.field.show_label.title"),
                    description: settingsLocalized("settings.other.screen_recording.show_label.description"),
                    isOn: $screenRecordingShowLabel
                )
                .onChange(of: screenRecordingShowLabel) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: screenRecordingTable,
                        key: "show-label",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.other.card.homebrew"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetHomebrewDefaults
            ) {
                SegmentedPickerRow(
                    title: settingsLocalized("settings.field.display_mode.title"),
                    description: settingsLocalized("settings.other.homebrew.display_mode.description"),
                    selection: $homebrewDisplayMode,
                    options: HomebrewDisplayMode.allCases,
                    titleForOption: { $0.title }
                )
                .onChange(of: homebrewDisplayMode) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: homebrewTable,
                        key: "display-mode",
                        newValueLiteral: "\"\(newValue.rawValue)\""
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.other.card.focus"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetFocusDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.other.focus.tint_with_focus_color.title"),
                    description: settingsLocalized("settings.other.focus.tint_with_focus_color.description"),
                    isOn: $focusTintWithFocusColor
                )
                .onChange(of: focusTintWithFocusColor) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: focusTable,
                        key: "tint-with-focus-color",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { _ in
            loadFromConfig()
        }
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true
        let batteryConfig = configManager.globalWidgetConfig(for: "default.battery")
        batteryShowPercentage = batteryConfig["show-percentage"]?.boolValue ?? true
        batteryWarningLevel = Double(batteryConfig["warning-level"]?.intValue ?? 30)
        batteryCriticalLevel = Double(batteryConfig["critical-level"]?.intValue ?? 10)

        let keyboardLayoutConfig = configManager.globalWidgetConfig(for: "default.keyboard-layout")
        keyboardLayoutShowText = keyboardLayoutConfig["show-text"]?.boolValue ?? true
        keyboardLayoutShowOutline = keyboardLayoutConfig["show-outline"]?.boolValue ?? true

        let screenRecordingConfig = configManager.globalWidgetConfig(for: "default.screen-recording-stop")
        screenRecordingShowLabel = screenRecordingConfig["show-label"]?.boolValue ?? true

        let homebrewConfig = configManager.globalWidgetConfig(for: "default.homebrew")
        homebrewDisplayMode = HomebrewDisplayMode(
            rawValue: homebrewConfig["display-mode"]?.stringValue ?? HomebrewDisplayMode.label.rawValue
        ) ?? .label

        let focusConfig = configManager.globalWidgetConfig(for: "default.focus")
        focusTintWithFocusColor = focusConfig["tint-with-focus-color"]?.boolValue ?? true
        isApplyingConfigSnapshot = false
    }

    private func resetBatteryDefaults() {
        isApplyingConfigSnapshot = true
        batteryShowPercentage = true
        batteryWarningLevel = 30
        batteryCriticalLevel = 10
        isApplyingConfigSnapshot = false

        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: batteryTable,
            key: "show-percentage",
            newValueLiteral: "true"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: batteryTable,
            key: "warning-level",
            newValueLiteral: "30"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: batteryTable,
            key: "critical-level",
            newValueLiteral: "10"
        )
    }

    private func resetKeyboardLayoutDefaults() {
        isApplyingConfigSnapshot = true
        keyboardLayoutShowText = true
        keyboardLayoutShowOutline = true
        isApplyingConfigSnapshot = false

        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: keyboardLayoutTable,
            key: "show-text",
            newValueLiteral: "true"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: keyboardLayoutTable,
            key: "show-outline",
            newValueLiteral: "true"
        )
    }

    private func resetScreenRecordingDefaults() {
        isApplyingConfigSnapshot = true
        screenRecordingShowLabel = true
        isApplyingConfigSnapshot = false

        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: screenRecordingTable,
            key: "show-label",
            newValueLiteral: "true"
        )
    }

    private func resetHomebrewDefaults() {
        isApplyingConfigSnapshot = true
        homebrewDisplayMode = .label
        isApplyingConfigSnapshot = false

        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: homebrewTable,
            key: "display-mode",
            newValueLiteral: "\"label\""
        )
    }

    private func resetFocusDefaults() {
        isApplyingConfigSnapshot = true
        focusTintWithFocusColor = true
        isApplyingConfigSnapshot = false

        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: focusTable,
            key: "tint-with-focus-color",
            newValueLiteral: "true"
        )
    }

}

private struct SettingsPlaceholderView: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.largeTitle.bold())

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}

/// Floating card that follows the cursor while a widget is being dragged,
/// giving explicit "something is being lifted" feedback beyond the source
/// card's dimming and the target's insertion gap.
private struct WidgetConfiguratorDragPreview: View {
    let title: String
    let icon: String
    let iconIsAsset: Bool

    var body: some View {
        HStack(spacing: 6) {
            if iconIsAsset {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.9))
        )
        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .scaleEffect(1.05)
        .rotationEffect(.degrees(-3))
    }
}

private struct WidgetConfiguratorView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @StateObject private var dragState = WidgetConfiguratorDragState()
    @State private var drafts: [String: [String]] = [:]
    @State private var catalogContext: DisplayCatalogContext?
    @State private var currentInsertion: (monitorID: String, index: Int)?
    @State private var rowFrames: [WidgetRowFrameKey.Entry] = []
    @State private var columnFrames: [String: CGRect] = [:]

    private var monitors: [MonitorDescriptor] { NSScreen.screens.map(\.monitorDescriptor) }

    var body: some View {
        GeometryReader { geometry in
            let requiredWideWidth = 188 + 12 + CGFloat(monitors.count) * (260 + 12)
            let isWide = geometry.size.width >= requiredWideWidth

            HStack(alignment: .top, spacing: 12) {
                AvailableWidgetsPanel(
                    isWidgetFullyPlaced: { widgetID in
                        let visibleMonitors = isWide ? monitors : monitors.filter { $0.id == selectedMonitorID }
                        return visibleMonitors.allSatisfy { !canAdd(widgetID, to: $0) }
                    },
                    dragState: dragState,
                    onDragChanged: { location in
                        currentInsertion = computeInsertion(at: location)
                    },
                    onDragEnded: { definition in
                        defer { currentInsertion = nil }
                        guard let insertion = currentInsertion,
                              let monitor = monitorDescriptor(for: insertion.monitorID) else {
                            return
                        }
                        appendWidget(definition.id, to: monitor, at: insertion.index)
                    }
                )

                if isWide {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(monitors) { monitor in
                                monitorColumn(for: monitor)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        if monitors.count > 1 {
                            Picker("", selection: selectedMonitorIDBinding) {
                                ForEach(monitors) { monitor in
                                    Text(monitor.name).tag(monitor.id)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        if let monitor = monitors.first(where: { $0.id == selectedMonitorID }) ?? monitors.first {
                            monitorColumn(for: monitor)
                        }
                    }
                }
            }
            .onPreferenceChange(WidgetRowFrameKey.self) { rowFrames = $0 }
            .onPreferenceChange(MonitorColumnFrameKey.self) { columnFrames = $0 }
            .overlay(alignment: .topLeading) {
                if let draggedID = dragState.draggedWidgetID {
                    let dragged = definition(for: draggedID)
                    WidgetConfiguratorDragPreview(title: dragged.title, icon: dragged.icon, iconIsAsset: dragged.iconIsAsset)
                        .position(dragState.dragLocation)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: dragState.draggedWidgetID)
        }
        .frame(minHeight: 520)
        .padding(24)
        .coordinateSpace(name: "widgetConfigurator")
        .onAppear {
            syncDraftsFromConfig(using: configManager.config)
            if selectedMonitorID == nil {
                selectedMonitorID = monitors.first?.id
            }
        }
        .onReceive(configManager.$config) { config in
            syncDraftsFromConfig(using: config)
        }
        .sheet(item: $catalogContext) { context in
            DisplayCatalogSheet(
                monitorName: context.monitorName,
                definitions: displayWidgetDefinitions,
                canAdd: { widgetID in
                    canAdd(widgetID, toMonitorID: context.monitorID)
                },
                addWidget: { widgetID in
                    appendWidget(widgetID, toMonitorID: context.monitorID)
                }
            )
        }
    }

    @State private var selectedMonitorID: String?
    private var selectedMonitorIDBinding: Binding<String> {
        Binding(
            get: { selectedMonitorID ?? monitors.first?.id ?? "" },
            set: { selectedMonitorID = $0 }
        )
    }

    @ViewBuilder
    private func monitorColumn(for monitor: MonitorDescriptor) -> some View {
        let layout = currentLayout(for: monitor)
        MonitorActiveColumn(
            monitor: monitor,
            items: layout.enumerated().map { index, widgetID in
                .init(index: index, widgetID: widgetID, title: definition(for: widgetID).title, icon: definition(for: widgetID).icon, iconIsAsset: definition(for: widgetID).iconIsAsset)
            },
            widgetCount: layout.count,
            statusText: displayStatus(for: monitor),
            hasOverride: configManager.hasDisplayOverride(for: monitor.id),
            insertionIndex: currentInsertion?.monitorID == monitor.id ? currentInsertion?.index : nil,
            dragState: dragState,
            onOpenCatalog: {
                catalogContext = .init(monitorID: monitor.id, monitorName: monitor.name)
            },
            onUseGlobalLayout: {
                resetOverride(for: monitor)
            },
            onRemove: { index in
                removeWidget(at: index, for: monitor)
            },
            onDragChanged: { location in
                currentInsertion = computeInsertion(at: location)
            },
            onDragEnded: {
                defer { currentInsertion = nil }
                guard let insertion = currentInsertion,
                      let origin = dragState.origin,
                      case .active(let sourceMonitorID, let sourceIndex) = origin,
                      let sourceMonitor = monitorDescriptor(for: sourceMonitorID),
                      let widgetID = dragState.draggedWidgetID else {
                    return
                }

                if sourceMonitorID == insertion.monitorID {
                    let adjustedDestination = sourceIndex < insertion.index ? insertion.index - 1 : insertion.index
                    moveWidget(for: sourceMonitor, from: sourceIndex, to: adjustedDestination)
                } else if let destMonitor = monitorDescriptor(for: insertion.monitorID) {
                    removeWidget(at: sourceIndex, for: sourceMonitor)
                    let adjustedIndex = insertion.index
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        appendWidget(widgetID, to: destMonitor, at: adjustedIndex)
                    }
                }
            }
        )
    }

    // MARK: - Persistence (ported unchanged from the former DisplaysSettingsView)

    private func effectiveWidgetIDs(for monitor: MonitorDescriptor) -> [String] {
        configManager
            .displayedWidgets(for: monitor.id)
            .map(\.id)
    }

    private func effectiveWidgetIDs(for monitor: MonitorDescriptor, in config: Config) -> [String] {
        if let displayConfig = config.rootToml.widgets.displays[monitor.id] {
            return displayConfig.displayed.map(\.id)
        }
        return config.rootToml.widgets.displayed.map(\.id)
    }

    private func currentLayout(for monitor: MonitorDescriptor) -> [String] {
        if let draft = drafts[monitor.id] {
            return draft
        }

        let fallback = effectiveWidgetIDs(for: monitor)
        drafts[monitor.id] = fallback
        return fallback
    }

    private func appendWidget(_ widgetID: String, to monitor: MonitorDescriptor) {
        var layout = currentLayout(for: monitor)
        guard definition(for: widgetID).allowsMultiple || !layout.contains(widgetID) else {
            return
        }
        layout.append(widgetID)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            persistLayout(layout, for: monitor)
        }
    }

    private func appendWidget(_ widgetID: String, toMonitorID monitorID: String) {
        guard let monitor = monitorDescriptor(for: monitorID) else { return }
        appendWidget(widgetID, to: monitor)
    }

    private func appendWidget(_ widgetID: String, to monitor: MonitorDescriptor, at index: Int) {
        var layout = currentLayout(for: monitor)
        guard definition(for: widgetID).allowsMultiple || !layout.contains(widgetID) else {
            return
        }
        let boundedIndex = max(0, min(index, layout.count))
        layout.insert(widgetID, at: boundedIndex)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            persistLayout(layout, for: monitor)
        }
    }

    private func removeWidget(at index: Int, for monitor: MonitorDescriptor) {
        var layout = currentLayout(for: monitor)
        guard layout.indices.contains(index) else { return }
        layout.remove(at: index)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            persistLayout(layout, for: monitor)
        }
    }

    private func moveWidget(for monitor: MonitorDescriptor, from source: Int, to destination: Int) {
        var layout = currentLayout(for: monitor)
        guard layout.indices.contains(source) else { return }

        let item = layout.remove(at: source)
        let boundedDestination = max(0, min(destination, layout.count))
        layout.insert(item, at: boundedDestination)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            persistLayout(layout, for: monitor)
        }
    }

    private func persistLayout(_ widgetIDs: [String], for monitor: MonitorDescriptor) {
        let normalized = widgetIDs.filter { !$0.isEmpty }
        let globalLayout = configManager.config.rootToml.widgets.displayed.map(\.id)

        drafts[monitor.id] = normalized

        guard !normalized.isEmpty else {
            resetOverride(for: monitor)
            return
        }

        if normalized == globalLayout {
            configManager.removeTable("widgets.displays.\"\(monitor.id)\"")
            return
        }

        configManager.updateConfigStringArrayValue(
            tablePath: "widgets.displays.\"\(monitor.id)\"",
            key: "displayed",
            newValue: normalized
        )
    }

    private func resetOverride(for monitor: MonitorDescriptor) {
        configManager.removeTable("widgets.displays.\"\(monitor.id)\"")
        drafts[monitor.id] = configManager
            .config
            .rootToml
            .widgets
            .displayed
            .map(\.id)
    }

    private func displayStatus(for monitor: MonitorDescriptor) -> String {
        if configManager.hasDisplayOverride(for: monitor.id) {
            return settingsLocalized("settings.displays.status.custom_override")
        }

        return settingsLocalized("settings.displays.status.global_layout")
    }

    private func syncDraftsFromConfig(using config: Config) {
        for monitor in monitors {
            drafts[monitor.id] = effectiveWidgetIDs(for: monitor, in: config)
        }
    }

    private func canAdd(_ widgetID: String, to monitor: MonitorDescriptor) -> Bool {
        let itemDefinition = definition(for: widgetID)
        return itemDefinition.allowsMultiple || !currentLayout(for: monitor).contains(widgetID)
    }

    private func canAdd(_ widgetID: String, toMonitorID monitorID: String) -> Bool {
        guard let monitor = monitorDescriptor(for: monitorID) else { return false }
        return canAdd(widgetID, to: monitor)
    }

    private func computeInsertion(at location: CGPoint) -> (monitorID: String, index: Int)? {
        guard let match = columnFrames.first(where: { $0.value.contains(location) }) else {
            return nil
        }
        let monitorID = match.key
        let rowsInColumn = rowFrames
            .filter { $0.monitorID == monitorID }
            .sorted { $0.index < $1.index }

        for row in rowsInColumn where location.y < row.midY {
            return (monitorID, row.index)
        }
        return (monitorID, rowsInColumn.count)
    }

    private func definition(for widgetID: String) -> DisplayWidgetDefinition {
        displayWidgetDefinitions.first(where: { $0.id == widgetID })
            ?? DisplayWidgetDefinition(
                id: widgetID,
                title: widgetID,
                description: settingsLocalized("settings.displays.catalog.custom_widget_description"),
                icon: "square.dashed",
                allowsMultiple: false
            )
    }

    private func monitorDescriptor(for monitorID: String) -> MonitorDescriptor? {
        monitors.first(where: { $0.id == monitorID })
    }
}

private enum AppearanceStyle: String, CaseIterable, Identifiable {
    case `default`
    case tui

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default:
            return "Default"
        case .tui:
            return "TUI"
        }
    }
}

private enum AppearanceChipMaterial: String, CaseIterable, Identifiable {
    case glass
    case flat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass:
            return "Glass"
        case .flat:
            return "Flat"
        }
    }
}

private struct AppearanceSettingsView: View {
    private enum AppearanceDefaults {
        static let foregroundHeightMode: AppearanceHeightMode = .defaultHeight
        static let foregroundCustomHeight: Double = 55
        static let applyFontToPopups = false
        static let horizontalPadding: Double = 6
        static let notchPadding: Double = 6
        static let widgetSpacing: Double = 7
        static let widgetBackgroundsShown = false
        static let widgetBlur: AppearanceBlur = .regular
        static let backgroundShown = false
        static let backgroundHeightMode: AppearanceHeightMode = .defaultHeight
        static let backgroundCustomHeight: Double = 55
        static let backgroundBlur: AppearanceBackgroundBlur = .ultraThin
    }

    @ObservedObject private var configManager = ConfigManager.shared

    @State private var theme = AppearanceTheme.system
    @State private var style = AppearanceStyle.default
    @State private var tuiTopPadding: Double = 0
    @State private var tuiAccentHex = "#7dd3fc"
    @State private var tuiChipMaterial = AppearanceChipMaterial.glass
    @State private var tuiChipOpacity: Double = 0.06
    @State private var foregroundHeightMode = AppearanceDefaults.foregroundHeightMode
    @State private var foregroundCustomHeight = AppearanceDefaults.foregroundCustomHeight
    @State private var selectedFontFamily = AppearanceFontFamilyOption.systemDefault
    @State private var applyFontToPopups = AppearanceDefaults.applyFontToPopups
    @State private var fontSearchText = ""
    @State private var horizontalPadding = AppearanceDefaults.horizontalPadding
    @State private var notchPadding = AppearanceDefaults.notchPadding
    @State private var widgetSpacing = AppearanceDefaults.widgetSpacing
    @State private var widgetBackgroundsShown = AppearanceDefaults.widgetBackgroundsShown
    @State private var widgetBlur = AppearanceDefaults.widgetBlur
    @State private var backgroundShown = AppearanceDefaults.backgroundShown
    @State private var backgroundHeightMode = AppearanceDefaults.backgroundHeightMode
    @State private var backgroundCustomHeight = AppearanceDefaults.backgroundCustomHeight
    @State private var backgroundBlur = AppearanceDefaults.backgroundBlur
    @State private var isApplyingConfigSnapshot = false

    private let foregroundTable = "experimental.foreground"
    private let widgetBackgroundTable = "experimental.foreground.widgets-background"
    private let backgroundTable = "experimental.background"
    private let fontBookURL = URL(fileURLWithPath: "/System/Applications/Font Book.app")

    private var tuiAccentColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: tuiAccentHex) ?? Color(red: 0.49, green: 0.83, blue: 0.99) },
            set: { newValue in
                let hex = newValue.toHexString() ?? "#7dd3fc"
                tuiAccentHex = hex
                ConfigManager.shared.updateConfigLiteralValue(
                    tablePath: "tui",
                    key: "accent",
                    newValueLiteral: "\"\(hex)\""
                )
            }
        )
    }

    private var availableFontFamilyOptions: [AppearanceFontFamilyOption] {
        let filteredFamilies = BarikFontCatalog.availableFamilies().filter { family in
            fontSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || family.localizedCaseInsensitiveContains(fontSearchText)
        }

        var options: [AppearanceFontFamilyOption] = [.systemDefault]
        options.append(contentsOf: filteredFamilies.map(AppearanceFontFamilyOption.custom))

        if case let .custom(currentFamily) = selectedFontFamily,
           !currentFamily.isEmpty,
           !options.contains(.custom(currentFamily)) {
            options.append(.custom(currentFamily))
        }

        return options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.appearance.header.title"),
                description: settingsLocalized("settings.appearance.header.description")
            )

            SettingsCardView(settingsLocalized("settings.appearance.card.theme")) {
                SegmentedPickerRow(
                    title: settingsLocalized("settings.appearance.field.color_scheme.title"),
                    description: settingsLocalized("settings.appearance.field.color_scheme.description"),
                    selection: $theme,
                    options: AppearanceTheme.allCases,
                    titleForOption: \.title
                )
                .onChange(of: theme) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        key: "theme",
                        newValueLiteral: "\"\(newValue.rawValue)\""
                    )
                }

                SegmentedPickerRow(
                    title: "Style",
                    description: "Narrow monochrome “almost-TUI” look. Overrides widget capsules and spacing.",
                    selection: $style,
                    options: AppearanceStyle.allCases,
                    titleForOption: \.title
                )
                .onChange(of: style) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        key: "style",
                        newValueLiteral: "\"\(newValue.rawValue)\""
                    )
                }

                if style == .tui {
                    SliderSettingRow(
                        title: "Top offset",
                        description: "Push the TUI bar down from the top edge of the screen.",
                        value: $tuiTopPadding,
                        range: 0...20,
                        step: 1,
                        valueFormat: { "\(Int($0)) pt" }
                    )
                    .onChange(of: tuiTopPadding) { _, newValue in
                        guard !isApplyingConfigSnapshot else { return }
                        ConfigManager.shared.updateConfigLiteralValue(
                            tablePath: "tui",
                            key: "top-padding",
                            newValueLiteral: String(Int(newValue.rounded()))
                        )
                    }

                    ColorSettingRow(
                        title: "Accent color",
                        description: "Color for the active / important element in TUI.",
                        color: tuiAccentColorBinding,
                        hexText: Binding(
                            get: { tuiAccentHex },
                            set: { newValue in
                                tuiAccentHex = newValue
                                ConfigManager.shared.updateConfigLiteralValue(
                                    tablePath: "tui",
                                    key: "accent",
                                    newValueLiteral: "\"\(newValue)\""
                                )
                            }
                        )
                    )

                    SegmentedPickerRow(
                        title: "Chip material",
                        description: "Frosted glass or a flat translucent fill behind widgets.",
                        selection: $tuiChipMaterial,
                        options: AppearanceChipMaterial.allCases,
                        titleForOption: \.title
                    )
                    .onChange(of: tuiChipMaterial) { _, newValue in
                        guard !isApplyingConfigSnapshot else { return }
                        ConfigManager.shared.updateConfigLiteralValue(
                            tablePath: "tui",
                            key: "chip-material",
                            newValueLiteral: "\"\(newValue.rawValue)\""
                        )
                    }

                    SliderSettingRow(
                        title: "Chip opacity",
                        description: "Visibility of the flat chip fill (ignored for glass).",
                        value: $tuiChipOpacity,
                        range: 0...0.3,
                        step: 0.01,
                        valueFormat: { String(format: "%.0f%%", $0 * 100) }
                    )
                    .disabled(tuiChipMaterial == .glass)
                    .onChange(of: tuiChipOpacity) { _, newValue in
                        guard !isApplyingConfigSnapshot else { return }
                        ConfigManager.shared.updateConfigLiteralValue(
                            tablePath: "tui",
                            key: "chip-opacity",
                            newValueLiteral: String(format: "%.2f", newValue)
                        )
                    }
                }
            }

            SettingsCardView(
                settingsLocalized("settings.appearance.card.font"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetFontDefaults
            ) {
                FontFamilySettingRow(
                    title: settingsLocalized("settings.appearance.field.font_family.title"),
                    description: settingsLocalized("settings.appearance.field.font_family.description"),
                    searchPlaceholder: settingsLocalized("settings.appearance.field.font_family.search_placeholder"),
                    installHint: settingsLocalized("settings.appearance.field.font_family.install_hint"),
                    openFontBookTitle: settingsLocalized("settings.appearance.field.font_family.open_font_book"),
                    selection: $selectedFontFamily,
                    searchText: $fontSearchText,
                    options: availableFontFamilyOptions,
                    openFontBook: openFontBook
                )
                .onChange(of: selectedFontFamily) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    applyFontFamilySelection(newValue)
                }

                ToggleRow(
                    title: settingsLocalized("settings.appearance.field.font_family.apply_to_popups.title"),
                    description: settingsLocalized("settings.appearance.field.font_family.apply_to_popups.description"),
                    isOn: $applyFontToPopups
                )
                .disabled(selectedFontFamily == .systemDefault)
                .onChange(of: applyFontToPopups) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: foregroundTable,
                        key: "font-apply-to-popups",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.appearance.card.foreground_bar"),
                badgeTitle: "Beta",
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetForegroundDefaults
            ) {
                SegmentedPickerRow(
                    title: settingsLocalized("settings.appearance.field.bar_height.title"),
                    description: settingsLocalized("settings.appearance.field.bar_height.description"),
                    selection: $foregroundHeightMode,
                    options: AppearanceHeightMode.allCases,
                    titleForOption: \.title
                )
                .onChange(of: foregroundHeightMode) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    applyForegroundHeight(mode: newValue)
                }

                if foregroundHeightMode == .custom {
                    SliderSettingRow(
                        title: settingsLocalized("settings.appearance.field.custom_foreground_height.title"),
                        description: settingsLocalized("settings.appearance.field.custom_foreground_height.description"),
                        value: $foregroundCustomHeight,
                        range: 20...100,
                        step: 1,
                        valueFormat: { "\(Int($0)) pt" }
                    )
                    .onChange(of: foregroundCustomHeight) { _, newValue in
                        guard !isApplyingConfigSnapshot else { return }
                        guard foregroundHeightMode == .custom else { return }
                        ConfigManager.shared.updateConfigLiteralValue(
                            tablePath: foregroundTable,
                            key: "height",
                            newValueLiteral: String(Int(newValue.rounded()))
                        )
                    }
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.appearance.field.horizontal_padding.title"),
                    description: settingsLocalized("settings.appearance.field.horizontal_padding.description"),
                    value: $horizontalPadding,
                    range: 0...60,
                    step: 1,
                    valueFormat: { "\(Int($0)) pt" }
                )
                .onChange(of: horizontalPadding) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: foregroundTable,
                        key: "horizontal-padding",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.appearance.field.notch_padding.title"),
                    description: settingsLocalized("settings.appearance.field.notch_padding.description"),
                    value: $notchPadding,
                    range: 0...40,
                    step: 1,
                    valueFormat: { "\(Int($0)) pt" }
                )
                .onChange(of: notchPadding) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: foregroundTable,
                        key: "notch-horizontal-padding",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.appearance.field.widget_spacing.title"),
                    description: settingsLocalized("settings.appearance.field.widget_spacing.description"),
                    value: $widgetSpacing,
                    range: 0...40,
                    step: 1,
                    valueFormat: { "\(Int($0)) pt" }
                )
                .disabled(style == .tui)
                .onChange(of: widgetSpacing) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: foregroundTable,
                        key: "spacing",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.appearance.card.widget_capsules"),
                badgeTitle: "Beta",
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWidgetCapsuleDefaults
            ) {
                if style == .tui {
                    Text("Widget capsules are replaced by the TUI style’s own chips and aren’t used here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ToggleRow(
                    title: settingsLocalized("settings.appearance.field.show_widget_backgrounds.title"),
                    description: settingsLocalized("settings.appearance.field.show_widget_backgrounds.description"),
                    isOn: $widgetBackgroundsShown
                )
                .disabled(style == .tui)
                .onChange(of: widgetBackgroundsShown) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: widgetBackgroundTable,
                        key: "displayed",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }

                PickerSettingRow(
                    title: settingsLocalized("settings.appearance.field.widget_blur.title"),
                    description: settingsLocalized("settings.appearance.field.widget_blur.description"),
                    selection: $widgetBlur,
                    options: AppearanceBlur.allCases,
                    titleForOption: \.title
                )
                .disabled(!widgetBackgroundsShown || style == .tui)
                .onChange(of: widgetBlur) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: widgetBackgroundTable,
                        key: "blur",
                        newValueLiteral: String(newValue.rawValue)
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.appearance.card.background_bar"),
                badgeTitle: "Beta",
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetBackgroundDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.appearance.field.show_background_bar.title"),
                    description: settingsLocalized("settings.appearance.field.show_background_bar.description"),
                    isOn: $backgroundShown
                )
                .onChange(of: backgroundShown) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: backgroundTable,
                        key: "displayed",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }

                SegmentedPickerRow(
                    title: settingsLocalized("settings.appearance.field.background_height.title"),
                    description: settingsLocalized("settings.appearance.field.background_height.description"),
                    selection: $backgroundHeightMode,
                    options: AppearanceHeightMode.allCases,
                    titleForOption: \.title
                )
                .disabled(!backgroundShown)
                .onChange(of: backgroundHeightMode) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    applyBackgroundHeight(mode: newValue)
                }

                if backgroundHeightMode == .custom {
                    SliderSettingRow(
                        title: settingsLocalized("settings.appearance.field.custom_background_height.title"),
                        description: settingsLocalized("settings.appearance.field.custom_background_height.description"),
                        value: $backgroundCustomHeight,
                        range: 20...100,
                        step: 1,
                        valueFormat: { "\(Int($0)) pt" }
                    )
                    .disabled(!backgroundShown)
                    .onChange(of: backgroundCustomHeight) { _, newValue in
                        guard !isApplyingConfigSnapshot else { return }
                        guard backgroundHeightMode == .custom else { return }
                        ConfigManager.shared.updateConfigLiteralValue(
                            tablePath: backgroundTable,
                            key: "height",
                            newValueLiteral: String(Int(newValue.rounded()))
                        )
                    }
                }

                PickerSettingRow(
                    title: settingsLocalized("settings.appearance.field.background_material.title"),
                    description: settingsLocalized("settings.appearance.field.background_material.description"),
                    selection: $backgroundBlur,
                    options: AppearanceBackgroundBlur.allCases,
                    titleForOption: \.title
                )
                .disabled(!backgroundShown)
                .onChange(of: backgroundBlur) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: backgroundTable,
                        key: "blur",
                        newValueLiteral: String(newValue.rawValue)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { _ in
            loadFromConfig()
        }
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let config = configManager.config
        let foreground = config.experimental.foreground
        let background = config.experimental.background

        theme = AppearanceTheme(rawValue: config.rootToml.theme ?? "system") ?? .system
        style = AppearanceStyle(rawValue: config.style) ?? .default
        tuiTopPadding = config.tui.topPadding
        tuiAccentHex = config.tui.accent
        tuiChipMaterial = AppearanceChipMaterial(rawValue: config.tui.chipMaterial.lowercased()) ?? .glass
        tuiChipOpacity = config.tui.chipOpacity
        foregroundHeightMode = AppearanceHeightMode(height: foreground.height)
        foregroundCustomHeight = AppearanceSettingsView.customHeightValue(from: foreground.height)
        selectedFontFamily = foreground.fontFamily.map(AppearanceFontFamilyOption.custom) ?? .systemDefault
        applyFontToPopups = foreground.fontFamily == nil ? false : foreground.applyFontToPopups
        horizontalPadding = foreground.horizontalPadding
        notchPadding = foreground.notchHorizontalPadding
        widgetSpacing = foreground.spacing
        widgetBackgroundsShown = foreground.widgetsBackground.displayed
        widgetBlur = AppearanceBlur(material: foreground.widgetsBackground.blur) ?? .regular
        backgroundShown = background.displayed
        backgroundHeightMode = AppearanceHeightMode(height: background.height)
        backgroundCustomHeight = AppearanceSettingsView.customHeightValue(from: background.height)
        backgroundBlur = AppearanceBackgroundBlur(
            material: background.blur,
            isBlack: background.black
        ) ?? .ultraThin

        isApplyingConfigSnapshot = false
    }

    private func applyForegroundHeight(mode: AppearanceHeightMode) {
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: foregroundTable,
            key: "height",
            newValueLiteral: heightLiteral(for: mode, customValue: foregroundCustomHeight)
        )
    }

    private func applyBackgroundHeight(mode: AppearanceHeightMode) {
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: backgroundTable,
            key: "height",
            newValueLiteral: heightLiteral(for: mode, customValue: backgroundCustomHeight)
        )
    }

    private func heightLiteral(for mode: AppearanceHeightMode, customValue: Double) -> String {
        switch mode {
        case .defaultHeight:
            return "\"default\""
        case .menuBar:
            return "\"menu-bar\""
        case .custom:
            return String(Int(customValue.rounded()))
        }
    }

    private static func customHeightValue(from height: BackgroundForegroundHeight) -> Double {
        switch height {
        case .float(let value):
            return Double(value)
        case .barikDefault:
            return AppearanceDefaults.foregroundCustomHeight
        case .menuBar:
            return 28
        }
    }

    private func applyFontFamilySelection(_ selection: AppearanceFontFamilyOption) {
        switch selection {
        case .systemDefault:
            ConfigManager.shared.removeConfigValue(tablePath: foregroundTable, key: "font-family")
            applyFontToPopups = false
            ConfigManager.shared.removeConfigValue(tablePath: foregroundTable, key: "font-apply-to-popups")
        case let .custom(family):
            ConfigManager.shared.updateConfigLiteralValue(
                tablePath: foregroundTable,
                key: "font-family",
                newValueLiteral: "\"\(family.replacingOccurrences(of: "\"", with: "\\\""))\""
            )
        }
    }

    private func resetForegroundDefaults() {
        isApplyingConfigSnapshot = true
        foregroundHeightMode = AppearanceDefaults.foregroundHeightMode
        foregroundCustomHeight = AppearanceDefaults.foregroundCustomHeight
        horizontalPadding = AppearanceDefaults.horizontalPadding
        notchPadding = AppearanceDefaults.notchPadding
        widgetSpacing = AppearanceDefaults.widgetSpacing
        isApplyingConfigSnapshot = false

        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: foregroundTable,
            key: "height",
            newValueLiteral: "\"default\""
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: foregroundTable,
            key: "horizontal-padding",
            newValueLiteral: String(Int(AppearanceDefaults.horizontalPadding))
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: foregroundTable,
            key: "notch-horizontal-padding",
            newValueLiteral: String(Int(AppearanceDefaults.notchPadding))
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: foregroundTable,
            key: "spacing",
            newValueLiteral: String(Int(AppearanceDefaults.widgetSpacing))
        )
    }

    private func resetFontDefaults() {
        isApplyingConfigSnapshot = true
        selectedFontFamily = .systemDefault
        applyFontToPopups = AppearanceDefaults.applyFontToPopups
        fontSearchText = ""
        isApplyingConfigSnapshot = false

        ConfigManager.shared.removeConfigValue(tablePath: foregroundTable, key: "font-family")
        ConfigManager.shared.removeConfigValue(tablePath: foregroundTable, key: "font-apply-to-popups")
    }

    private func resetWidgetCapsuleDefaults() {
        isApplyingConfigSnapshot = true
        widgetBackgroundsShown = AppearanceDefaults.widgetBackgroundsShown
        widgetBlur = AppearanceDefaults.widgetBlur
        isApplyingConfigSnapshot = false

        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: widgetBackgroundTable,
            key: "displayed",
            newValueLiteral: AppearanceDefaults.widgetBackgroundsShown ? "true" : "false"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: widgetBackgroundTable,
            key: "blur",
            newValueLiteral: String(AppearanceDefaults.widgetBlur.rawValue)
        )
    }

    private func resetBackgroundDefaults() {
        isApplyingConfigSnapshot = true
        backgroundShown = AppearanceDefaults.backgroundShown
        backgroundHeightMode = AppearanceDefaults.backgroundHeightMode
        backgroundCustomHeight = AppearanceDefaults.backgroundCustomHeight
        backgroundBlur = AppearanceDefaults.backgroundBlur
        isApplyingConfigSnapshot = false

        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: backgroundTable,
            key: "displayed",
            newValueLiteral: AppearanceDefaults.backgroundShown ? "true" : "false"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: backgroundTable,
            key: "height",
            newValueLiteral: "\"default\""
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: backgroundTable,
            key: "blur",
            newValueLiteral: String(AppearanceDefaults.backgroundBlur.rawValue)
        )
    }

    private func openFontBook() {
        if FileManager.default.fileExists(atPath: fontBookURL.path) {
            NSWorkspace.shared.open(fontBookURL)
        }
    }
}

private struct DisplayCatalogContext: Identifiable {
    let monitorID: String
    let monitorName: String
    var id: String { monitorID }
}

private struct DisplayWidgetDefinition: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    /// When true, `icon` names an asset-catalog image (the widget's real
    /// brand mark, e.g. "ClaudeIcon") to load via `Image(_:)` instead of
    /// `Image(systemName:)`.
    let iconIsAsset: Bool
    let allowsMultiple: Bool

    init(id: String, title: String, description: String, icon: String, iconIsAsset: Bool = false, allowsMultiple: Bool) {
        self.id = id
        self.title = title
        self.description = description
        self.icon = icon
        self.iconIsAsset = iconIsAsset
        self.allowsMultiple = allowsMultiple
    }
}

// Icons mirror what each widget actually renders on the bar (see each
// Widget.swift's own Image(systemName:)/Image(_:) calls) rather than
// generic stand-ins, so the catalog/tiles are recognizable at a glance.
private let displayWidgetDefinitions: [DisplayWidgetDefinition] = [
    .init(id: "default.spaces", title: settingsLocalized("settings.section.spaces"), description: settingsLocalized("settings.displays.catalog.widget.spaces.description"), icon: "square.3.layers.3d", allowsMultiple: false),
    .init(id: "default.claude-usage", title: settingsLocalized("settings.section.claude_usage"), description: settingsLocalized("settings.displays.catalog.widget.claude_usage.description"), icon: "ClaudeIcon", iconIsAsset: true, allowsMultiple: false),
    .init(id: "default.codex-usage", title: settingsLocalized("settings.section.codex_usage"), description: settingsLocalized("settings.displays.catalog.widget.codex_usage.description"), icon: "CodexIcon", iconIsAsset: true, allowsMultiple: false),
    .init(id: "default.system-monitor", title: settingsLocalized("settings.section.system_monitor"), description: settingsLocalized("settings.displays.catalog.widget.system_monitor.description"), icon: "cpu", allowsMultiple: false),
    .init(id: "default.network", title: settingsLocalized("settings.section.network"), description: settingsLocalized("settings.displays.catalog.widget.network.description"), icon: "wifi", allowsMultiple: false),
    .init(id: "default.focus", title: settingsLocalized("settings.displays.catalog.widget.focus.title"), description: settingsLocalized("settings.displays.catalog.widget.focus.description"), icon: "moon.circle", allowsMultiple: false),
    .init(id: "default.pomodoro", title: settingsLocalized("settings.section.pomodoro"), description: settingsLocalized("settings.displays.catalog.widget.pomodoro.description"), icon: "PomodoroIcon", iconIsAsset: true, allowsMultiple: false),
    .init(id: "default.shortcuts", title: settingsLocalized("settings.section.shortcuts"), description: settingsLocalized("settings.displays.catalog.widget.shortcuts.description"), icon: "square.stack.3d.up.fill", allowsMultiple: false),
    .init(id: "default.keyboard-layout", title: settingsLocalized("settings.displays.catalog.widget.keyboard_layout.title"), description: settingsLocalized("settings.displays.catalog.widget.keyboard_layout.description"), icon: "globe", allowsMultiple: false),
    .init(id: "default.battery", title: settingsLocalized("settings.displays.catalog.widget.battery.title"), description: settingsLocalized("settings.displays.catalog.widget.battery.description"), icon: "battery.100", allowsMultiple: false),
    .init(id: "default.time", title: settingsLocalized("settings.section.time"), description: settingsLocalized("settings.displays.catalog.widget.time.description"), icon: "clock", allowsMultiple: false),
    .init(id: "default.weather", title: settingsLocalized("settings.section.weather"), description: settingsLocalized("settings.displays.catalog.widget.weather.description"), icon: "cloud.sun", allowsMultiple: false),
    .init(id: "default.screen-recording-stop", title: settingsLocalized("settings.displays.catalog.widget.screen_recording_stop.title"), description: settingsLocalized("settings.displays.catalog.widget.screen_recording_stop.description"), icon: "stop.fill", allowsMultiple: false),
    .init(id: "default.qwen-proxy-usage", title: settingsLocalized("settings.section.qwen_proxy_usage"), description: settingsLocalized("settings.displays.catalog.widget.qwen_proxy_usage.description"), icon: "QwenIcon", iconIsAsset: true, allowsMultiple: false),
    .init(id: "default.cliproxy-usage", title: settingsLocalized("settings.section.cli_proxy_usage"), description: settingsLocalized("settings.displays.catalog.widget.cli_proxy_usage.description"), icon: "server.rack", allowsMultiple: false),
    .init(id: "default.nowplaying", title: settingsLocalized("settings.section.now_playing"), description: settingsLocalized("settings.displays.catalog.widget.now_playing.description"), icon: "music.note", allowsMultiple: false),
    .init(id: "default.homebrew", title: settingsLocalized("settings.displays.catalog.widget.homebrew.title"), description: settingsLocalized("settings.displays.catalog.widget.homebrew.description"), icon: "shippingbox.fill", allowsMultiple: false),
    .init(id: "default.ticktick", title: settingsLocalized("settings.section.ticktick"), description: settingsLocalized("settings.displays.catalog.widget.ticktick.description"), icon: "TickTickIcon", iconIsAsset: true, allowsMultiple: false),
    .init(id: "spacer", title: settingsLocalized("settings.displays.catalog.widget.spacer.title"), description: settingsLocalized("settings.displays.catalog.widget.spacer.description"), icon: "arrow.left.and.right", allowsMultiple: true),
    .init(id: "divider", title: settingsLocalized("settings.displays.catalog.widget.divider.title"), description: settingsLocalized("settings.displays.catalog.widget.divider.description"), icon: "line.diagonal", allowsMultiple: true)
]

@ViewBuilder
private func displayWidgetIconView(_ definition: DisplayWidgetDefinition, size: CGFloat) -> some View {
    if definition.iconIsAsset {
        Image(definition.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size * 0.55, height: size * 0.55)
            .frame(width: size, height: size)
    } else {
        Image(systemName: definition.icon)
            .font(.system(size: size * 0.7, weight: .medium))
            .frame(width: size, height: size)
    }
}

private final class WidgetConfiguratorDragState: ObservableObject {
    enum Origin: Equatable {
        case available
        case active(monitorID: String, index: Int)
    }

    @Published var draggedWidgetID: String?
    @Published var origin: Origin?
    @Published var dragLocation: CGPoint = .zero

    var isDragging: Bool { draggedWidgetID != nil }

    func reset() {
        draggedWidgetID = nil
        origin = nil
    }
}

private struct WidgetRowFrameKey: PreferenceKey {
    struct Entry: Equatable {
        let monitorID: String
        let index: Int
        let midY: CGFloat
    }

    static var defaultValue: [Entry] = []

    static func reduce(value: inout [Entry], nextValue: () -> [Entry]) {
        value.append(contentsOf: nextValue())
    }
}

private struct MonitorColumnFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct AvailableWidgetTile: View {
    let definition: DisplayWidgetDefinition
    let isFullyPlaced: Bool
    @ObservedObject var dragState: WidgetConfiguratorDragState
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void

    private var isBeingDragged: Bool {
        dragState.draggedWidgetID == definition.id && dragState.origin == .available
    }

    var body: some View {
        VStack(spacing: 6) {
            displayWidgetIconView(definition, size: 32)

            Text(definition.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 72, height: 72)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(isFullyPlaced ? 0.02 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .opacity(isFullyPlaced ? 0.35 : (isBeingDragged ? 0.4 : 1))
        .scaleEffect(isBeingDragged ? 0.92 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isBeingDragged)
        .help("\(definition.description)\n\(definition.id)")
        .gesture(
            isFullyPlaced ? nil : DragGesture(minimumDistance: 2, coordinateSpace: .named("widgetConfigurator"))
                .onChanged { value in
                    if dragState.draggedWidgetID == nil {
                        dragState.draggedWidgetID = definition.id
                        dragState.origin = .available
                    }
                    dragState.dragLocation = value.location
                    onDragChanged(value.location)
                }
                .onEnded { _ in
                    onDragEnded()
                    dragState.reset()
                }
        )
    }
}

private struct AvailableWidgetsPanel: View {
    let isWidgetFullyPlaced: (String) -> Bool
    @ObservedObject var dragState: WidgetConfiguratorDragState
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (DisplayWidgetDefinition) -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settingsLocalized("settings.displays.catalog.title"))
                .font(.headline)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(displayWidgetDefinitions) { definition in
                        AvailableWidgetTile(
                            definition: definition,
                            isFullyPlaced: isWidgetFullyPlaced(definition.id),
                            dragState: dragState,
                            onDragChanged: onDragChanged,
                            onDragEnded: { onDragEnded(definition) }
                        )
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 188)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(14)
        .background(SettingsCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MonitorActiveColumnItem: Identifiable, Equatable {
    let index: Int
    let widgetID: String
    let title: String
    let icon: String
    let iconIsAsset: Bool
    var id: String { "\(index)-\(widgetID)" }
}

private struct MonitorActiveColumnRow: View {
    let item: MonitorActiveColumnItem
    let monitorID: String
    @ObservedObject var dragState: WidgetConfiguratorDragState
    let onRemove: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void

    private var isBeingDragged: Bool {
        dragState.draggedWidgetID == item.widgetID
            && dragState.origin == .active(monitorID: monitorID, index: item.index)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            if item.iconIsAsset {
                Image(item.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                    .frame(width: 18)
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.widgetID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .opacity(isBeingDragged ? 0.35 : 1)
        .scaleEffect(isBeingDragged ? 0.96 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isBeingDragged)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: WidgetRowFrameKey.self,
                    value: [.init(monitorID: monitorID, index: item.index, midY: geo.frame(in: .named("widgetConfigurator")).midY)]
                )
            }
        )
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named("widgetConfigurator"))
                .onChanged { value in
                    if dragState.draggedWidgetID == nil {
                        dragState.draggedWidgetID = item.widgetID
                        dragState.origin = .active(monitorID: monitorID, index: item.index)
                    }
                    dragState.dragLocation = value.location
                    onDragChanged(value.location)
                }
                .onEnded { _ in
                    onDragEnded()
                    dragState.reset()
                }
        )
    }
}

private struct WidgetConfiguratorInsertionGap: View {
    let isTargeted: Bool

    var body: some View {
        Color.clear
            .frame(height: isTargeted ? 40 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.88), value: isTargeted)
    }
}

private struct MonitorActiveColumn: View {
    let monitor: MonitorDescriptor
    let items: [MonitorActiveColumnItem]
    let widgetCount: Int
    let statusText: String
    let hasOverride: Bool
    let insertionIndex: Int?
    @ObservedObject var dragState: WidgetConfiguratorDragState
    let onOpenCatalog: () -> Void
    let onUseGlobalLayout: () -> Void
    let onRemove: (Int) -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.name)
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(hasOverride ? .primary : .secondary)
                }

                Spacer(minLength: 8)

                Text("\(widgetCount) \(settingsLocalized("settings.displays.widget_count_suffix"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(settingsLocalized("settings.displays.action.open_catalog"), action: onOpenCatalog)
                    .font(.caption.weight(.semibold))
                if hasOverride {
                    Button(settingsLocalized("settings.displays.action.use_global_layout"), action: onUseGlobalLayout)
                        .font(.caption.weight(.semibold))
                }
            }

            ScrollView {
                VStack(spacing: 6) {
                    WidgetConfiguratorInsertionGap(isTargeted: insertionIndex == 0)
                    ForEach(items) { item in
                        MonitorActiveColumnRow(
                            item: item,
                            monitorID: monitor.id,
                            dragState: dragState,
                            onRemove: { onRemove(item.index) },
                            onDragChanged: onDragChanged,
                            onDragEnded: onDragEnded
                        )
                        WidgetConfiguratorInsertionGap(isTargeted: insertionIndex == item.index + 1)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 260, maxHeight: .infinity, alignment: .top)
        .padding(14)
        .background(SettingsCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: MonitorColumnFrameKey.self,
                    value: [monitor.id: geo.frame(in: .named("widgetConfigurator"))]
                )
            }
        )
    }
}

private struct DisplayLayoutRow<Accessory: View>: View {
    let definition: DisplayWidgetDefinition
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(definition.title)
                    .font(.headline)

                Text(definition.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(definition.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            accessory()
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

private struct DisplayCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss

    let monitorName: String
    let definitions: [DisplayWidgetDefinition]
    let canAdd: (String) -> Bool
    let addWidget: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(settingsLocalized("settings.displays.catalog.title"))
                        .font(.title2.bold())

                    Text(
                        String(
                            format: settingsLocalized("settings.displays.catalog.description"),
                            locale: .autoupdatingCurrent,
                            monitorName
                        )
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button(settingsLocalized("settings.action.done")) {
                    dismiss()
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(definitions) { definition in
                        DisplayLayoutRow(definition: definition) {
                            Button {
                                addWidget(definition.id)
                            } label: {
                                Text(
                                    canAdd(definition.id)
                                    ? settingsLocalized("settings.action.add")
                                    : settingsLocalized("settings.status.added")
                                )
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.primary.opacity(canAdd(definition.id) ? 0.10 : 0.05))
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canAdd(definition.id))
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 480)
    }
}

private struct TimeSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var settingsStore = SettingsStore.shared

    @State private var format = ""
    @State private var timeZone = ""
    @State private var calendarFormat = ""
    @State private var stacked = false
    @State private var stackedTimeFormat = ""
    @State private var stackedDateFormat = ""
    @State private var showEvents = true
    @State private var popupVariant: MenuBarPopupVariant = .box
    @State private var isApplyingConfigSnapshot = false
    @State private var pendingStringWrites: [String: String] = [:]
    @State private var pendingBoolWrites: [String: Bool] = [:]

    @State private var formatTask: Task<Void, Never>?
    @State private var timeZoneTask: Task<Void, Never>?
    @State private var calendarFormatTask: Task<Void, Never>?
    @State private var stackedTimeFormatTask: Task<Void, Never>?
    @State private var stackedDateFormatTask: Task<Void, Never>?

    private let popupVariants: [MenuBarPopupVariant] = [.box, .vertical, .horizontal]
    private let timeTable = "widgets.default.time"
    private let popupTable = "widgets.default.time.popup"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.time.header.title"),
                description: settingsLocalized("settings.time.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.time.card.clock"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetClockDefaults
            ) {
                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.time.field.primary_format.title"),
                    description: settingsLocalized("settings.time.field.primary_format.description"),
                    text: $format
                )
                .onChange(of: format) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(
                        task: &formatTask,
                        key: "widgets.default.time.format",
                        value: newValue
                    )
                }

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.time.field.time_zone.title"),
                    description: settingsLocalized("settings.time.field.time_zone.description"),
                    text: $timeZone
                )
                .onChange(of: timeZone) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(
                        task: &timeZoneTask,
                        key: "widgets.default.time.time-zone",
                        value: newValue
                    )
                }

                ToggleRow(
                    title: settingsLocalized("settings.time.field.stacked_layout.title"),
                    description: settingsLocalized("settings.time.field.stacked_layout.description"),
                    isOn: Binding(
                        get: { stacked },
                        set: { newValue in
                            stacked = newValue
                            markPendingBoolWrite(
                                newValue,
                                for: .init(tablePath: timeTable, key: "stacked")
                            )
                            Task { @MainActor in
                                settingsStore.setBool(
                                    newValue,
                                    for: .init(tablePath: timeTable, key: "stacked")
                                )
                            }
                        }
                    )
                )

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.time.field.stacked_time_format.title"),
                    description: settingsLocalized("settings.time.field.stacked_time_format.description"),
                    text: $stackedTimeFormat
                )
                .disabled(!stacked)
                .onChange(of: stackedTimeFormat) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(
                        task: &stackedTimeFormatTask,
                        key: "widgets.default.time.stacked-time-format",
                        value: newValue
                    )
                }

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.time.field.stacked_date_format.title"),
                    description: settingsLocalized("settings.time.field.stacked_date_format.description"),
                    text: $stackedDateFormat
                )
                .disabled(!stacked)
                .onChange(of: stackedDateFormat) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(
                        task: &stackedDateFormatTask,
                        key: "widgets.default.time.stacked-date-format",
                        value: newValue
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.time.card.calendar"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetCalendarDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.time.field.show_upcoming_event.title"),
                    description: settingsLocalized("settings.time.field.show_upcoming_event.description"),
                    isOn: Binding(
                        get: { showEvents },
                        set: { newValue in
                            showEvents = newValue
                            markPendingBoolWrite(
                                newValue,
                                for: .init(tablePath: timeTable, key: "calendar.show-events")
                            )
                            Task { @MainActor in
                                settingsStore.setBool(
                                    newValue,
                                    for: .init(tablePath: timeTable, key: "calendar.show-events")
                                )
                            }
                        }
                    )
                )

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.time.field.event_time_format.title"),
                    description: settingsLocalized("settings.time.field.event_time_format.description"),
                    text: $calendarFormat
                )
                .onChange(of: calendarFormat) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(
                        task: &calendarFormatTask,
                        key: "widgets.default.time.calendar.format",
                        value: newValue
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.card.popup"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetPopupDefaults
            ) {
                Picker(settingsLocalized("settings.field.popup_layout.title"), selection: Binding(
                    get: { popupVariant },
                    set: { newValue in
                        popupVariant = newValue
                        markPendingStringWrite(
                            newValue.rawValue,
                            for: .init(tablePath: popupTable, key: "view-variant")
                        )
                        Task { @MainActor in
                            settingsStore.setString(
                                newValue.rawValue,
                                for: .init(tablePath: popupTable, key: "view-variant")
                            )
                        }
                    }
                )) {
                    ForEach(popupVariants, id: \.rawValue) { variant in
                        Text(variantTitle(for: variant)).tag(variant)
                    }
                }
                .pickerStyle(.segmented)
            }

            SettingsCardView(settingsLocalized("settings.card.preview")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(previewDateString())
                        .font(stacked ? .title3.weight(.semibold) : .headline.weight(.semibold))
                    if stacked {
                        Text(previewStackedDateString())
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else if showEvents {
                        Text(
                            String(
                                format: settingsLocalized("settings.time.preview.upcoming_event"),
                                locale: .autoupdatingCurrent,
                                previewEventTimeString()
                            )
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { config in
            settingsStore.refresh(with: config)
            loadFromConfig()
        }
        .onDisappear {
            cancelPendingTasks()
        }
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let formatField = SettingsFieldKey(tablePath: timeTable, key: "format")
        let timeZoneField = SettingsFieldKey(tablePath: timeTable, key: "time-zone")
        let calendarFormatField = SettingsFieldKey(tablePath: timeTable, key: "calendar.format")
        let showEventsField = SettingsFieldKey(tablePath: timeTable, key: "calendar.show-events")
        let stackedField = SettingsFieldKey(tablePath: timeTable, key: "stacked")
        let stackedTimeField = SettingsFieldKey(tablePath: timeTable, key: "stacked-time-format")
        let stackedDateField = SettingsFieldKey(tablePath: timeTable, key: "stacked-date-format")
        let popupVariantField = SettingsFieldKey(tablePath: popupTable, key: "view-variant")

        format = resolvedStringValue(
            for: formatField,
            incoming: settingsStore.stringValue(formatField, fallback: "E d, J:mm"),
            current: format
        )
        timeZone = resolvedStringValue(
            for: timeZoneField,
            incoming: settingsStore.stringValue(timeZoneField),
            current: timeZone
        )
        calendarFormat = resolvedStringValue(
            for: calendarFormatField,
            incoming: settingsStore.stringValue(calendarFormatField, fallback: "J:mm"),
            current: calendarFormat
        )
        showEvents = resolvedBoolValue(
            for: showEventsField,
            incoming: settingsStore.boolValue(showEventsField, fallback: true),
            current: showEvents
        )
        stacked = resolvedBoolValue(
            for: stackedField,
            incoming: settingsStore.boolValue(stackedField, fallback: false),
            current: stacked
        )
        stackedTimeFormat = resolvedStringValue(
            for: stackedTimeField,
            incoming: settingsStore.stringValue(stackedTimeField, fallback: "J:mm"),
            current: stackedTimeFormat
        )
        stackedDateFormat = resolvedStringValue(
            for: stackedDateField,
            incoming: settingsStore.stringValue(stackedDateField, fallback: "E d MMM"),
            current: stackedDateFormat
        )

        let rawVariant = resolvedStringValue(
            for: popupVariantField,
            incoming: settingsStore.stringValue(popupVariantField, fallback: "box"),
            current: popupVariant.rawValue
        )
        popupVariant = MenuBarPopupVariant(rawValue: rawVariant) ?? .box

        isApplyingConfigSnapshot = false
    }

    private func scheduleStringWrite(task: inout Task<Void, Never>?, key: String, value: String) {
        let field = timeField(for: key)
        let currentValue = settingsStore.stringValue(field)
        guard value != currentValue else {
            task?.cancel()
            return
        }

        task?.cancel()
        markPendingStringWrite(value, for: field)
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            settingsStore.setString(value, for: field)
        }
    }

    private func timeField(for key: String) -> SettingsFieldKey {
        switch key {
        case "widgets.default.time.format":
            return .init(tablePath: timeTable, key: "format")
        case "widgets.default.time.time-zone":
            return .init(tablePath: timeTable, key: "time-zone")
        case "widgets.default.time.calendar.format":
            return .init(tablePath: timeTable, key: "calendar.format")
        case "widgets.default.time.stacked-time-format":
            return .init(tablePath: timeTable, key: "stacked-time-format")
        case "widgets.default.time.stacked-date-format":
            return .init(tablePath: timeTable, key: "stacked-date-format")
        default:
            return .init(tablePath: timeTable, key: key)
        }
    }

    private func cancelPendingTasks() {
        formatTask?.cancel()
        timeZoneTask?.cancel()
        calendarFormatTask?.cancel()
        stackedTimeFormatTask?.cancel()
        stackedDateFormatTask?.cancel()
    }

    private func resetClockDefaults() {
        cancelPendingTasks()

        isApplyingConfigSnapshot = true
        format = "E d, J:mm"
        timeZone = ""
        stacked = false
        stackedTimeFormat = "J:mm"
        stackedDateFormat = "E d MMM"
        isApplyingConfigSnapshot = false

        pendingStringWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: timeTable, key: "format")))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: timeTable, key: "time-zone")))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: timeTable, key: "stacked-time-format")))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: timeTable, key: "stacked-date-format")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: timeTable, key: "stacked")))

        settingsStore.setString("E d, J:mm", for: .init(tablePath: timeTable, key: "format"))
        ConfigManager.shared.removeConfigValue(tablePath: timeTable, key: "time-zone")
        settingsStore.setBool(false, for: .init(tablePath: timeTable, key: "stacked"))
        settingsStore.setString("J:mm", for: .init(tablePath: timeTable, key: "stacked-time-format"))
        settingsStore.setString("E d MMM", for: .init(tablePath: timeTable, key: "stacked-date-format"))
    }

    private func resetCalendarDefaults() {
        calendarFormatTask?.cancel()

        isApplyingConfigSnapshot = true
        showEvents = true
        calendarFormat = "J:mm"
        isApplyingConfigSnapshot = false

        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: timeTable, key: "calendar.show-events")))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: timeTable, key: "calendar.format")))

        settingsStore.setBool(true, for: .init(tablePath: timeTable, key: "calendar.show-events"))
        settingsStore.setString("J:mm", for: .init(tablePath: timeTable, key: "calendar.format"))
    }

    private func resetPopupDefaults() {
        isApplyingConfigSnapshot = true
        popupVariant = .box
        isApplyingConfigSnapshot = false

        pendingStringWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: popupTable, key: "view-variant")))
        settingsStore.setString("box", for: .init(tablePath: popupTable, key: "view-variant"))
    }

    private func resolvedStringValue(
        for field: SettingsFieldKey,
        incoming: String,
        current: String
    ) -> String {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingStringWrites[fieldID] {
            if incoming == pendingValue {
                pendingStringWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedBoolValue(
        for field: SettingsFieldKey,
        incoming: Bool,
        current: Bool
    ) -> Bool {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingBoolWrites[fieldID] {
            if incoming == pendingValue {
                pendingBoolWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func markPendingStringWrite(_ value: String, for field: SettingsFieldKey) {
        pendingStringWrites[fieldIdentifier(field)] = value
    }

    private func markPendingBoolWrite(_ value: Bool, for field: SettingsFieldKey) {
        pendingBoolWrites[fieldIdentifier(field)] = value
    }

    private func fieldIdentifier(_ field: SettingsFieldKey) -> String {
        "\(field.tablePath).\(field.key)"
    }

    private func previewDateString() -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(stacked ? stackedTimeFormat : format)
        if let zone = TimeZone(identifier: timeZone), !timeZone.isEmpty {
            formatter.timeZone = zone
        }
        return formatter.string(from: Date())
    }

    private func previewStackedDateString() -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(stackedDateFormat)
        if let zone = TimeZone(identifier: timeZone), !timeZone.isEmpty {
            formatter.timeZone = zone
        }
        return formatter.string(from: Date())
    }

    private func previewEventTimeString() -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(calendarFormat)
        if let zone = TimeZone(identifier: timeZone), !timeZone.isEmpty {
            formatter.timeZone = zone
        }
        return formatter.string(from: Date().addingTimeInterval(60 * 45))
    }

    private func variantTitle(for variant: MenuBarPopupVariant) -> String {
        switch variant {
        case .box:
            return settingsLocalized("settings.option.box")
        case .vertical:
            return settingsLocalized("settings.option.vertical")
        case .horizontal:
            return settingsLocalized("settings.option.horizontal")
        case .settings:
            return settingsLocalized("settings.option.settings")
        }
    }
}

private struct GotifySettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var gotifyManager = GotifyManager.shared

    @State private var gotifyEnabled = false
    @State private var showInCalendarPopup = true
    @State private var gotifyBaseURL = ""
    @State private var gotifyHistoryLimit = 20
    @State private var username = ""
    @State private var password = ""
    @State private var isApplyingConfigSnapshot = false
    @State private var pendingStringWrites: [String: String] = [:]
    @State private var pendingBoolWrites: [String: Bool] = [:]
    @State private var gotifyBaseURLTask: Task<Void, Never>?

    private let gotifyTable = "widgets.default.gotify"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: "Gotify",
                description: "Configure the Gotify integration, sign in securely, and choose where notifications should appear inside Barik."
            )

            SettingsCardView(
                "Connection",
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetGotifyDefaults
            ) {
                ToggleRow(
                    title: "Enable Gotify integration",
                    description: "Keep a client session, fetch recent notifications, and listen for live updates over the Gotify websocket stream.",
                    isOn: Binding(
                        get: { gotifyEnabled },
                        set: { newValue in
                            gotifyEnabled = newValue
                            markPendingBoolWrite(
                                newValue,
                                for: .init(tablePath: gotifyTable, key: "enabled")
                            )
                            Task { @MainActor in
                                settingsStore.setBool(
                                    newValue,
                                    for: .init(tablePath: gotifyTable, key: "enabled")
                                )
                            }
                        }
                    )
                )

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.field.base_url.title"),
                    description: "The Gotify server URL, for example http://192.168.1.110:9229.",
                    text: $gotifyBaseURL
                )
                .onChange(of: gotifyBaseURL) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleGotifyBaseURLWrite(newValue)
                }

                SliderSettingRow(
                    title: "History limit",
                    description: "How many recent notifications to keep in Barik after each refresh.",
                    value: Binding(
                        get: { Double(gotifyHistoryLimit) },
                        set: { newValue in
                            gotifyHistoryLimit = Int(newValue.rounded())
                            Task { @MainActor in
                                settingsStore.setInt(
                                    gotifyHistoryLimit,
                                    for: .init(tablePath: gotifyTable, key: "history-limit")
                                )
                            }
                        }
                    ),
                    range: 5...100,
                    step: 1,
                    valueFormat: { "\(Int($0.rounded()))" }
                )
            }

            SettingsCardView(
                "Placement",
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetGotifyPlacementDefaults
            ) {
                ToggleRow(
                    title: "Show in calendar popup",
                    description: "Add a Gotify tab to the calendar popup. You can keep the integration enabled even if you hide this tab for now.",
                    isOn: Binding(
                        get: { showInCalendarPopup },
                        set: { newValue in
                            showInCalendarPopup = newValue
                            markPendingBoolWrite(
                                newValue,
                                for: .init(tablePath: gotifyTable, key: "show-in-calendar-popup")
                            )
                            Task { @MainActor in
                                settingsStore.setBool(
                                    newValue,
                                    for: .init(tablePath: gotifyTable, key: "show-in-calendar-popup")
                                )
                            }
                        }
                    )
                )
            }

            SettingsCardView("Account") {
                VStack(alignment: .leading, spacing: 10) {
                    if !gotifyEnabled {
                        Text("Enable the Gotify integration first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if !gotifyManager.isAuthenticated {
                        TextField("Username", text: $username)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { submitGotifyLogin() }

                        HStack(spacing: 10) {
                            Button(action: submitGotifyLogin) {
                                if gotifyManager.isLoading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Connecting…")
                                    }
                                } else {
                                    Text("Connect")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                gotifyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || password.isEmpty
                                    || gotifyManager.isLoading
                            )
                        }

                        Text("Credentials are stored in Keychain. Barik refreshes the client token automatically.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(gotifyManager.currentUser?.name ?? "Gotify")
                                        .font(.headline)
                                    Text(gotifyManager.isConnected ? "Live stream connected" : "Using fallback refresh")
                                        .font(.subheadline)
                                        .foregroundStyle(gotifyManager.isConnected ? .green : .secondary)
                                }
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Button("Open Web UI", action: gotifyManager.openWebUI)
                                    .buttonStyle(.bordered)
                                Button("Refresh") {
                                    Task { await gotifyManager.refreshNow() }
                                }
                                .buttonStyle(.bordered)
                                Button("Sign Out", role: .destructive, action: gotifyManager.signOut)
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            SettingsCardView(settingsLocalized("settings.card.status")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(gotifyStatusTitle)
                        .font(.headline)
                    Text(gotifyStatusDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { config in
            settingsStore.refresh(with: config)
            loadFromConfig()
        }
        .onDisappear {
            gotifyBaseURLTask?.cancel()
        }
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let gotifyEnabledField = SettingsFieldKey(tablePath: gotifyTable, key: "enabled")
        let gotifyBaseURLField = SettingsFieldKey(tablePath: gotifyTable, key: "base-url")
        let gotifyHistoryField = SettingsFieldKey(tablePath: gotifyTable, key: "history-limit")
        let calendarPopupField = SettingsFieldKey(tablePath: gotifyTable, key: "show-in-calendar-popup")

        gotifyEnabled = resolvedBoolValue(
            for: gotifyEnabledField,
            incoming: settingsStore.boolValue(gotifyEnabledField, fallback: false),
            current: gotifyEnabled
        )
        gotifyBaseURL = resolvedStringValue(
            for: gotifyBaseURLField,
            incoming: settingsStore.stringValue(gotifyBaseURLField),
            current: gotifyBaseURL
        )
        gotifyHistoryLimit = settingsStore.intValue(gotifyHistoryField, fallback: 20)
        showInCalendarPopup = resolvedBoolValue(
            for: calendarPopupField,
            incoming: settingsStore.boolValue(calendarPopupField, fallback: true),
            current: showInCalendarPopup
        )

        isApplyingConfigSnapshot = false
    }

    private func scheduleGotifyBaseURLWrite(_ value: String) {
        gotifyBaseURLTask?.cancel()
        let field = SettingsFieldKey(tablePath: gotifyTable, key: "base-url")
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        markPendingStringWrite(trimmedValue, for: field)

        gotifyBaseURLTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            if trimmedValue.isEmpty {
                ConfigManager.shared.removeConfigValue(tablePath: gotifyTable, key: "base-url")
            } else {
                settingsStore.setString(trimmedValue, for: field)
            }
        }
    }

    private func resetGotifyDefaults() {
        gotifyBaseURLTask?.cancel()

        isApplyingConfigSnapshot = true
        gotifyEnabled = false
        gotifyBaseURL = ""
        gotifyHistoryLimit = 20
        showInCalendarPopup = true
        isApplyingConfigSnapshot = false

        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: gotifyTable, key: "enabled")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: gotifyTable, key: "show-in-calendar-popup")))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: gotifyTable, key: "base-url")))

        settingsStore.setBool(false, for: .init(tablePath: gotifyTable, key: "enabled"))
        settingsStore.setBool(true, for: .init(tablePath: gotifyTable, key: "show-in-calendar-popup"))
        ConfigManager.shared.removeConfigValue(tablePath: gotifyTable, key: "base-url")
        settingsStore.setInt(20, for: .init(tablePath: gotifyTable, key: "history-limit"))
    }

    private func resetGotifyPlacementDefaults() {
        isApplyingConfigSnapshot = true
        showInCalendarPopup = true
        isApplyingConfigSnapshot = false

        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: gotifyTable, key: "show-in-calendar-popup")))
        settingsStore.setBool(true, for: .init(tablePath: gotifyTable, key: "show-in-calendar-popup"))
    }

    private func resolvedStringValue(
        for field: SettingsFieldKey,
        incoming: String,
        current: String
    ) -> String {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingStringWrites[fieldID] {
            if incoming == pendingValue {
                pendingStringWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedBoolValue(
        for field: SettingsFieldKey,
        incoming: Bool,
        current: Bool
    ) -> Bool {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingBoolWrites[fieldID] {
            if incoming == pendingValue {
                pendingBoolWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func markPendingStringWrite(_ value: String, for field: SettingsFieldKey) {
        pendingStringWrites[fieldIdentifier(field)] = value
    }

    private func markPendingBoolWrite(_ value: Bool, for field: SettingsFieldKey) {
        pendingBoolWrites[fieldIdentifier(field)] = value
    }

    private func fieldIdentifier(_ field: SettingsFieldKey) -> String {
        "\(field.tablePath).\(field.key)"
    }

    private func submitGotifyLogin() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else { return }
        Task {
            await gotifyManager.signIn(username: trimmedUsername, password: password)
            if gotifyManager.isAuthenticated {
                password = ""
            }
        }
    }

    private var gotifyStatusTitle: String {
        if !gotifyEnabled {
            return "Gotify is disabled"
        }
        if gotifyManager.isAuthenticated {
            return gotifyManager.isConnected ? "Gotify live stream connected" : "Gotify connected"
        }
        if gotifyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Gotify needs a base URL"
        }
        return "Gotify is ready for sign in"
    }

    private var gotifyStatusDescription: String {
        if !gotifyEnabled {
            return "Turn the integration on here when you want Barik to connect to Gotify."
        }
        if let error = gotifyManager.errorMessage, !error.isEmpty {
            return error
        }
        if gotifyManager.isAuthenticated {
            if showInCalendarPopup {
                return "Open the calendar popup and switch to the Gotify tab to inspect recent notifications."
            }
            return "Gotify is connected. The calendar popup tab is currently hidden in Placement settings."
        }
        return "Set the base URL here, then sign in from this section. Credentials stay in Keychain."
    }
}

private struct SpacesSettingsView: View {
    private enum SpacesDisplayModeOption: String, CaseIterable {
        case classic
        case focusedStrip = "focused-strip"

        var title: String {
            switch self {
            case .classic:
                settingsLocalized("settings.spaces.field.display_mode.option.classic")
            case .focusedStrip:
                settingsLocalized("settings.spaces.field.display_mode.option.focused_strip")
            }
        }
    }

    private enum SpacesVisualStyleOption: String, CaseIterable {
        case standard
        case rounded

        var title: String {
            switch self {
            case .standard:
                settingsLocalized("settings.spaces.field.visual_style.option.standard")
            case .rounded:
                settingsLocalized("settings.spaces.field.visual_style.option.rounded")
            }
        }
    }

    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var spacesViewModel = SpacesViewModel.shared

    @State private var showSpaceKey = true
    @State private var displayMode = SpacesDisplayModeOption.classic
    @State private var visualStyle = SpacesVisualStyleOption.standard
    @State private var showOutline = false
    @State private var showOnlyCurrentDisplaySpaces = false
    @State private var showInactiveSpaces = true
    @State private var showEmptySpaces = true
    @State private var showDeleteButton = true
    @State private var showWindowTitle = true
    @State private var showHiddenWindows = false
    @State private var showHoverTooltip = false
    @State private var hoverTooltipTemplate = "{app} ({pid})"
    @State private var iconDesaturation = 0.0
    @State private var titleMaxLength = 50.0
    @State private var alwaysDisplayAppNames = ""
    @State private var isApplyingConfigSnapshot = false
    @State private var pendingStringWrites: [String: String] = [:]
    @State private var pendingBoolWrites: [String: Bool] = [:]
    @State private var pendingIntWrites: [String: Int] = [:]
    @State private var pendingArrayWrites: [String: [String]] = [:]

    @State private var hoverTooltipTask: Task<Void, Never>?
    @State private var alwaysDisplayAppNamesTask: Task<Void, Never>?

    private let spacesTable = "widgets.default.spaces"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.spaces.header.title"),
                description: settingsLocalized("settings.spaces.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.spaces.card.spaces"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetSpaceDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.spaces.field.show_space_key.title"),
                    description: settingsLocalized("settings.spaces.field.show_space_key.description"),
                    isOn: bindingForBool(
                        $showSpaceKey,
                        field: .init(tablePath: spacesTable, key: "space.show-key")
                    )
                )

                SegmentedPickerRow(
                    title: settingsLocalized("settings.spaces.field.display_mode.title"),
                    description: settingsLocalized("settings.spaces.field.display_mode.description"),
                    selection: Binding(
                        get: { displayMode },
                        set: { newValue in
                            displayMode = newValue
                            markPendingStringWrite(newValue.rawValue, for: .init(tablePath: spacesTable, key: "space.display-mode"))
                            Task { @MainActor in
                                settingsStore.setString(newValue.rawValue, for: .init(tablePath: spacesTable, key: "space.display-mode"))
                            }
                        }
                    ),
                    options: SpacesDisplayModeOption.allCases,
                    titleForOption: { $0.title }
                )

                SegmentedPickerRow(
                    title: settingsLocalized("settings.spaces.field.visual_style.title"),
                    description: settingsLocalized("settings.spaces.field.visual_style.description"),
                    selection: Binding(
                        get: { visualStyle },
                        set: { newValue in
                            visualStyle = newValue
                            markPendingStringWrite(newValue.rawValue, for: .init(tablePath: spacesTable, key: "space.visual-style"))
                            Task { @MainActor in
                                settingsStore.setString(newValue.rawValue, for: .init(tablePath: spacesTable, key: "space.visual-style"))
                            }
                        }
                    ),
                    options: SpacesVisualStyleOption.allCases,
                    titleForOption: { $0.title }
                )

                ToggleRow(
                    title: settingsLocalized("settings.spaces.field.show_outline.title"),
                    description: settingsLocalized("settings.spaces.field.show_outline.description"),
                    isOn: bindingForBool(
                        $showOutline,
                        field: .init(tablePath: spacesTable, key: "space.show-outline")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.spaces.field.show_only_current_display_spaces.title"),
                    description: settingsLocalized("settings.spaces.field.show_only_current_display_spaces.description"),
                    isOn: bindingForBool(
                        $showOnlyCurrentDisplaySpaces,
                        field: .init(tablePath: spacesTable, key: "space.show-only-current-display-spaces")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.spaces.field.show_inactive_spaces.title"),
                    description: settingsLocalized("settings.spaces.field.show_inactive_spaces.description"),
                    isOn: bindingForBool(
                        $showInactiveSpaces,
                        field: .init(tablePath: spacesTable, key: "space.show-inactive")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.spaces.field.show_empty_spaces.title"),
                    description: settingsLocalized("settings.spaces.field.show_empty_spaces.description"),
                    isOn: bindingForBool(
                        $showEmptySpaces,
                        field: .init(tablePath: spacesTable, key: "space.show-empty")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.spaces.field.show_delete_button.title"),
                    description: settingsLocalized("settings.spaces.field.show_delete_button.description"),
                    isOn: bindingForBool(
                        $showDeleteButton,
                        field: .init(tablePath: spacesTable, key: "space.show-delete-button")
                    )
                )
            }

            SettingsCardView(
                settingsLocalized("settings.spaces.card.windows"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWindowDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.spaces.field.show_window_title.title"),
                    description: settingsLocalized("settings.spaces.field.show_window_title.description"),
                    isOn: bindingForBool(
                        $showWindowTitle,
                        field: .init(tablePath: spacesTable, key: "window.show-title")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.spaces.field.show_hidden_windows.title"),
                    description: settingsLocalized("settings.spaces.field.show_hidden_windows.description"),
                    isOn: bindingForBool(
                        $showHiddenWindows,
                        field: .init(tablePath: spacesTable, key: "window.show-hidden")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.spaces.field.show_hover_tooltip.title"),
                    description: settingsLocalized("settings.spaces.field.show_hover_tooltip.description"),
                    isOn: bindingForBool(
                        $showHoverTooltip,
                        field: .init(tablePath: spacesTable, key: "window.show-hover-tooltip")
                    )
                )

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.spaces.field.hover_tooltip_template.title"),
                    description: settingsLocalized("settings.spaces.field.hover_tooltip_template.description"),
                    text: $hoverTooltipTemplate
                )
                .disabled(!showHoverTooltip)
                .onChange(of: hoverTooltipTemplate) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(
                        task: &hoverTooltipTask,
                        field: .init(tablePath: spacesTable, key: "window.hover-tooltip"),
                        value: newValue
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.spaces.field.icon_desaturation.title"),
                    description: settingsLocalized("settings.spaces.field.icon_desaturation.description"),
                    value: $iconDesaturation,
                    range: 0...100,
                    step: 1,
                    valueFormat: { "\(Int($0))%" }
                )
                .onChange(of: iconDesaturation) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(
                        Int(newValue.rounded()),
                        for: .init(tablePath: spacesTable, key: "window.icon-desaturation")
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.spaces.field.focused_title_max_length.title"),
                    description: settingsLocalized("settings.spaces.field.focused_title_max_length.description"),
                    value: $titleMaxLength,
                    range: 10...100,
                    step: 1,
                    valueFormat: { "\(Int($0)) chars" }
                )
                .onChange(of: titleMaxLength) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(
                        Int(newValue.rounded()),
                        for: .init(tablePath: spacesTable, key: "window.title.max-length")
                    )
                }

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.spaces.field.always_show_app_name_for.title"),
                    description: settingsLocalized("settings.spaces.field.always_show_app_name_for.description"),
                    text: $alwaysDisplayAppNames
                )
                .onChange(of: alwaysDisplayAppNames) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleArrayWrite(
                        task: &alwaysDisplayAppNamesTask,
                        field: .init(tablePath: spacesTable, key: "window.title.always-display-app-name-for"),
                        value: newValue
                    )
                }
            }

            SettingsCardView(settingsLocalized("settings.card.status")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        String(
                            format: settingsLocalized("settings.spaces.status.loaded"),
                            locale: .autoupdatingCurrent,
                            spacesViewModel.spaces.count
                        )
                    )
                        .font(.headline)

                    Text(spacesViewModel.spaces.first(where: \.isFocused)?.id ?? settingsLocalized("settings.spaces.status.no_focused_space"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { config in
            settingsStore.refresh(with: config)
            loadFromConfig()
        }
        .onDisappear {
            hoverTooltipTask?.cancel()
            alwaysDisplayAppNamesTask?.cancel()
        }
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let showSpaceKeyField = SettingsFieldKey(tablePath: spacesTable, key: "space.show-key")
        let displayModeField = SettingsFieldKey(tablePath: spacesTable, key: "space.display-mode")
        let visualStyleField = SettingsFieldKey(tablePath: spacesTable, key: "space.visual-style")
        let showOutlineField = SettingsFieldKey(tablePath: spacesTable, key: "space.show-outline")
        let showOnlyCurrentDisplaySpacesField = SettingsFieldKey(tablePath: spacesTable, key: "space.show-only-current-display-spaces")
        let showInactiveSpacesField = SettingsFieldKey(tablePath: spacesTable, key: "space.show-inactive")
        let showEmptySpacesField = SettingsFieldKey(tablePath: spacesTable, key: "space.show-empty")
        let showDeleteButtonField = SettingsFieldKey(tablePath: spacesTable, key: "space.show-delete-button")
        let showWindowTitleField = SettingsFieldKey(tablePath: spacesTable, key: "window.show-title")
        let showHiddenWindowsField = SettingsFieldKey(tablePath: spacesTable, key: "window.show-hidden")
        let showHoverTooltipField = SettingsFieldKey(tablePath: spacesTable, key: "window.show-hover-tooltip")
        let hoverTooltipField = SettingsFieldKey(tablePath: spacesTable, key: "window.hover-tooltip")
        let iconDesaturationField = SettingsFieldKey(tablePath: spacesTable, key: "window.icon-desaturation")
        let titleMaxLengthField = SettingsFieldKey(tablePath: spacesTable, key: "window.title.max-length")
        let alwaysDisplayAppNamesField = SettingsFieldKey(tablePath: spacesTable, key: "window.title.always-display-app-name-for")

        showSpaceKey = resolvedBoolValue(for: showSpaceKeyField, incoming: settingsStore.boolValue(showSpaceKeyField, fallback: true), current: showSpaceKey)
        displayMode = SpacesDisplayModeOption(
            rawValue: resolvedStringValue(
                for: displayModeField,
                incoming: settingsStore.stringValue(displayModeField, fallback: SpacesDisplayModeOption.classic.rawValue),
                current: displayMode.rawValue
            )
        ) ?? .classic
        visualStyle = SpacesVisualStyleOption(
            rawValue: resolvedStringValue(
                for: visualStyleField,
                incoming: settingsStore.stringValue(visualStyleField, fallback: SpacesVisualStyleOption.standard.rawValue),
                current: visualStyle.rawValue
            )
        ) ?? .standard
        showOutline = resolvedBoolValue(
            for: showOutlineField,
            incoming: settingsStore.boolValue(showOutlineField, fallback: false),
            current: showOutline
        )
        showOnlyCurrentDisplaySpaces = resolvedBoolValue(
            for: showOnlyCurrentDisplaySpacesField,
            incoming: settingsStore.boolValue(showOnlyCurrentDisplaySpacesField, fallback: false),
            current: showOnlyCurrentDisplaySpaces
        )
        showInactiveSpaces = resolvedBoolValue(for: showInactiveSpacesField, incoming: settingsStore.boolValue(showInactiveSpacesField, fallback: true), current: showInactiveSpaces)
        showEmptySpaces = resolvedBoolValue(for: showEmptySpacesField, incoming: settingsStore.boolValue(showEmptySpacesField, fallback: true), current: showEmptySpaces)
        showDeleteButton = resolvedBoolValue(for: showDeleteButtonField, incoming: settingsStore.boolValue(showDeleteButtonField, fallback: true), current: showDeleteButton)
        showWindowTitle = resolvedBoolValue(for: showWindowTitleField, incoming: settingsStore.boolValue(showWindowTitleField, fallback: true), current: showWindowTitle)
        showHiddenWindows = resolvedBoolValue(for: showHiddenWindowsField, incoming: settingsStore.boolValue(showHiddenWindowsField, fallback: false), current: showHiddenWindows)
        showHoverTooltip = resolvedBoolValue(for: showHoverTooltipField, incoming: settingsStore.boolValue(showHoverTooltipField, fallback: false), current: showHoverTooltip)
        hoverTooltipTemplate = resolvedStringValue(for: hoverTooltipField, incoming: settingsStore.stringValue(hoverTooltipField, fallback: "{app} ({pid})"), current: hoverTooltipTemplate)
        iconDesaturation = Double(resolvedIntValue(for: iconDesaturationField, incoming: settingsStore.intValue(iconDesaturationField, fallback: 0), current: Int(iconDesaturation.rounded())))
        titleMaxLength = Double(resolvedIntValue(for: titleMaxLengthField, incoming: settingsStore.intValue(titleMaxLengthField, fallback: 50), current: Int(titleMaxLength.rounded())))
        alwaysDisplayAppNames = resolvedArrayValue(
            for: alwaysDisplayAppNamesField,
            incoming: settingsStore.configValueArray(alwaysDisplayAppNamesField),
            current: commaSeparatedAppNames(from: alwaysDisplayAppNames)
        ).joined(separator: ", ")

        isApplyingConfigSnapshot = false
    }

    private func bindingForBool(
        _ state: Binding<Bool>,
        field: SettingsFieldKey
    ) -> Binding<Bool> {
        Binding(
            get: { state.wrappedValue },
            set: { newValue in
                state.wrappedValue = newValue
                setBoolValue(newValue, for: field)
            }
        )
    }

    private func scheduleStringWrite(
        task: inout Task<Void, Never>?,
        field: SettingsFieldKey,
        value: String
    ) {
        task?.cancel()
        markPendingStringWrite(value, for: field)
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            settingsStore.setString(value, for: field)
        }
    }

    private func scheduleArrayWrite(
        task: inout Task<Void, Never>?,
        field: SettingsFieldKey,
        value: String
    ) {
        task?.cancel()
        let values = commaSeparatedAppNames(from: value)
        markPendingArrayWrite(values, for: field)
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            ConfigManager.shared.updateConfigStringArrayValue(
                tablePath: field.tablePath,
                key: field.key,
                newValue: values
            )
        }
    }

    private func commaSeparatedAppNames(from rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func setBoolValue(_ value: Bool, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingBoolWrites[fieldIdentifier(field)] = value
        Task { @MainActor in
            settingsStore.setBool(value, for: field)
        }
    }

    private func setIntValue(_ value: Int, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingIntWrites[fieldIdentifier(field)] = value
        Task { @MainActor in
            settingsStore.setInt(value, for: field)
        }
    }

    private func resolvedStringValue(for field: SettingsFieldKey, incoming: String, current: String) -> String {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingStringWrites[fieldID] {
            if incoming == pendingValue {
                pendingStringWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedBoolValue(for field: SettingsFieldKey, incoming: Bool, current: Bool) -> Bool {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingBoolWrites[fieldID] {
            if incoming == pendingValue {
                pendingBoolWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedIntValue(for field: SettingsFieldKey, incoming: Int, current: Int) -> Int {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingIntWrites[fieldID] {
            if incoming == pendingValue {
                pendingIntWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedArrayValue(for field: SettingsFieldKey, incoming: [String], current: [String]) -> [String] {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingArrayWrites[fieldID] {
            if incoming == pendingValue {
                pendingArrayWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func markPendingStringWrite(_ value: String, for field: SettingsFieldKey) {
        pendingStringWrites[fieldIdentifier(field)] = value
    }

    private func markPendingArrayWrite(_ value: [String], for field: SettingsFieldKey) {
        pendingArrayWrites[fieldIdentifier(field)] = value
    }

    private func fieldIdentifier(_ field: SettingsFieldKey) -> String {
        "\(field.tablePath).\(field.key)"
    }

    private func resetSpaceDefaults() {
        isApplyingConfigSnapshot = true
        showSpaceKey = true
        displayMode = .classic
        visualStyle = .standard
        showOutline = false
        showOnlyCurrentDisplaySpaces = false
        showInactiveSpaces = true
        showEmptySpaces = true
        showDeleteButton = true
        isApplyingConfigSnapshot = false

        settingsStore.setBool(true, for: .init(tablePath: spacesTable, key: "space.show-key"))
        settingsStore.setString("classic", for: .init(tablePath: spacesTable, key: "space.display-mode"))
        settingsStore.setString("standard", for: .init(tablePath: spacesTable, key: "space.visual-style"))
        settingsStore.setBool(false, for: .init(tablePath: spacesTable, key: "space.show-outline"))
        settingsStore.setBool(false, for: .init(tablePath: spacesTable, key: "space.show-only-current-display-spaces"))
        settingsStore.setBool(true, for: .init(tablePath: spacesTable, key: "space.show-inactive"))
        settingsStore.setBool(true, for: .init(tablePath: spacesTable, key: "space.show-empty"))
        settingsStore.setBool(true, for: .init(tablePath: spacesTable, key: "space.show-delete-button"))
    }

    private func resetWindowDefaults() {
        hoverTooltipTask?.cancel()
        alwaysDisplayAppNamesTask?.cancel()

        isApplyingConfigSnapshot = true
        showWindowTitle = true
        showHiddenWindows = false
        showHoverTooltip = false
        hoverTooltipTemplate = "{app} ({pid})"
        iconDesaturation = 0
        titleMaxLength = 50
        alwaysDisplayAppNames = ""
        isApplyingConfigSnapshot = false

        settingsStore.setBool(true, for: .init(tablePath: spacesTable, key: "window.show-title"))
        settingsStore.setBool(false, for: .init(tablePath: spacesTable, key: "window.show-hidden"))
        settingsStore.setBool(false, for: .init(tablePath: spacesTable, key: "window.show-hover-tooltip"))
        settingsStore.setString("{app} ({pid})", for: .init(tablePath: spacesTable, key: "window.hover-tooltip"))
        settingsStore.setInt(0, for: .init(tablePath: spacesTable, key: "window.icon-desaturation"))
        settingsStore.setInt(50, for: .init(tablePath: spacesTable, key: "window.title.max-length"))
        ConfigManager.shared.updateConfigStringArrayValue(
            tablePath: spacesTable,
            key: "window.title.always-display-app-name-for",
            newValue: []
        )
    }
}

private struct NetworkSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var networkStatus = NetworkStatusViewModel.shared

    @State private var showWiFi = true
    @State private var showEthernet = true
    @State private var showSignalStrength = true
    @State private var showRSSI = true
    @State private var showNoise = true
    @State private var showChannel = true
    @State private var showEthernetSection = true
    @State private var isApplyingConfigSnapshot = false
    @State private var pendingBoolWrites: [String: Bool] = [:]

    private let networkTable = "widgets.default.network"
    private let networkPopupTable = "widgets.default.network.popup"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.network.header.title"),
                description: settingsLocalized("settings.network.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.card.widget"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWidgetDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.network.field.show_wifi.title"),
                    description: settingsLocalized("settings.network.field.show_wifi.description"),
                    isOn: Binding(
                        get: { showWiFi },
                        set: { newValue in
                            updateRequiredPair(
                                state: &showWiFi,
                                otherState: showEthernet,
                                field: .init(tablePath: networkTable, key: "show-wifi"),
                                newValue: newValue
                            )
                        }
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.network.field.show_ethernet.title"),
                    description: settingsLocalized("settings.network.field.show_ethernet.description"),
                    isOn: Binding(
                        get: { showEthernet },
                        set: { newValue in
                            updateRequiredPair(
                                state: &showEthernet,
                                otherState: showWiFi,
                                field: .init(tablePath: networkTable, key: "show-ethernet"),
                                newValue: newValue
                            )
                        }
                    )
                )
            }

            SettingsCardView(
                settingsLocalized("settings.card.popup"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetPopupDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.network.field.show_signal_strength.title"),
                    description: settingsLocalized("settings.network.field.show_signal_strength.description"),
                    isOn: bindingForBool(
                        $showSignalStrength,
                        field: .init(tablePath: networkPopupTable, key: "show-signal-strength")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.network.field.show_rssi.title"),
                    description: settingsLocalized("settings.network.field.show_rssi.description"),
                    isOn: bindingForBool(
                        $showRSSI,
                        field: .init(tablePath: networkPopupTable, key: "show-rssi")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.network.field.show_noise.title"),
                    description: settingsLocalized("settings.network.field.show_noise.description"),
                    isOn: bindingForBool(
                        $showNoise,
                        field: .init(tablePath: networkPopupTable, key: "show-noise")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.network.field.show_channel.title"),
                    description: settingsLocalized("settings.network.field.show_channel.description"),
                    isOn: bindingForBool(
                        $showChannel,
                        field: .init(tablePath: networkPopupTable, key: "show-channel")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.network.field.show_ethernet_section.title"),
                    description: settingsLocalized("settings.network.field.show_ethernet_section.description"),
                    isOn: bindingForBool(
                        $showEthernetSection,
                        field: .init(tablePath: networkPopupTable, key: "show-ethernet-section")
                    )
                )
            }

            SettingsCardView(settingsLocalized("settings.card.status")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        String(
                            format: settingsLocalized("settings.network.status.summary"),
                            locale: .autoupdatingCurrent,
                            networkStatus.wifiState.rawValue,
                            networkStatus.ethernetState.rawValue
                        )
                    )
                        .font(.headline)

                    Text(networkStatus.ssid == "Not connected" || networkStatus.ssid == "No interface"
                         ? settingsLocalized("settings.network.status.no_active_wifi")
                         : String(
                            format: settingsLocalized("settings.network.status.connected_wifi"),
                            locale: .autoupdatingCurrent,
                            networkStatus.ssid
                         ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { config in
            settingsStore.refresh(with: config)
            loadFromConfig()
        }
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let showWiFiField = SettingsFieldKey(tablePath: networkTable, key: "show-wifi")
        let showEthernetField = SettingsFieldKey(tablePath: networkTable, key: "show-ethernet")
        let showSignalStrengthField = SettingsFieldKey(tablePath: networkPopupTable, key: "show-signal-strength")
        let showRSSIField = SettingsFieldKey(tablePath: networkPopupTable, key: "show-rssi")
        let showNoiseField = SettingsFieldKey(tablePath: networkPopupTable, key: "show-noise")
        let showChannelField = SettingsFieldKey(tablePath: networkPopupTable, key: "show-channel")
        let showEthernetSectionField = SettingsFieldKey(tablePath: networkPopupTable, key: "show-ethernet-section")

        showWiFi = resolvedBoolValue(for: showWiFiField, incoming: settingsStore.boolValue(showWiFiField, fallback: true), current: showWiFi)
        showEthernet = resolvedBoolValue(for: showEthernetField, incoming: settingsStore.boolValue(showEthernetField, fallback: true), current: showEthernet)
        showSignalStrength = resolvedBoolValue(for: showSignalStrengthField, incoming: settingsStore.boolValue(showSignalStrengthField, fallback: true), current: showSignalStrength)
        showRSSI = resolvedBoolValue(for: showRSSIField, incoming: settingsStore.boolValue(showRSSIField, fallback: true), current: showRSSI)
        showNoise = resolvedBoolValue(for: showNoiseField, incoming: settingsStore.boolValue(showNoiseField, fallback: true), current: showNoise)
        showChannel = resolvedBoolValue(for: showChannelField, incoming: settingsStore.boolValue(showChannelField, fallback: true), current: showChannel)
        showEthernetSection = resolvedBoolValue(for: showEthernetSectionField, incoming: settingsStore.boolValue(showEthernetSectionField, fallback: true), current: showEthernetSection)

        isApplyingConfigSnapshot = false
    }

    private func bindingForBool(
        _ state: Binding<Bool>,
        field: SettingsFieldKey
    ) -> Binding<Bool> {
        Binding(
            get: { state.wrappedValue },
            set: { newValue in
                state.wrappedValue = newValue
                setBoolValue(newValue, for: field)
            }
        )
    }

    private func updateRequiredPair(
        state: inout Bool,
        otherState: Bool,
        field: SettingsFieldKey,
        newValue: Bool
    ) {
        guard newValue || otherState else { return }
        state = newValue
        setBoolValue(newValue, for: field)
    }

    private func setBoolValue(_ value: Bool, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingBoolWrites[fieldIdentifier(field)] = value
        Task { @MainActor in
            settingsStore.setBool(value, for: field)
        }
    }

    private func resolvedBoolValue(
        for field: SettingsFieldKey,
        incoming: Bool,
        current: Bool
    ) -> Bool {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingBoolWrites[fieldID] {
            if incoming == pendingValue {
                pendingBoolWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func fieldIdentifier(_ field: SettingsFieldKey) -> String {
        "\(field.tablePath).\(field.key)"
    }

    private func resetWidgetDefaults() {
        isApplyingConfigSnapshot = true
        showWiFi = true
        showEthernet = true
        isApplyingConfigSnapshot = false

        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: networkTable, key: "show-wifi")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: networkTable, key: "show-ethernet")))

        settingsStore.setBool(true, for: .init(tablePath: networkTable, key: "show-wifi"))
        settingsStore.setBool(true, for: .init(tablePath: networkTable, key: "show-ethernet"))
    }

    private func resetPopupDefaults() {
        isApplyingConfigSnapshot = true
        showSignalStrength = true
        showRSSI = true
        showNoise = true
        showChannel = true
        showEthernetSection = true
        isApplyingConfigSnapshot = false

        let fields = [
            SettingsFieldKey(tablePath: networkPopupTable, key: "show-signal-strength"),
            SettingsFieldKey(tablePath: networkPopupTable, key: "show-rssi"),
            SettingsFieldKey(tablePath: networkPopupTable, key: "show-noise"),
            SettingsFieldKey(tablePath: networkPopupTable, key: "show-channel"),
            SettingsFieldKey(tablePath: networkPopupTable, key: "show-ethernet-section")
        ]

        for field in fields {
            pendingBoolWrites.removeValue(forKey: fieldIdentifier(field))
            settingsStore.setBool(true, for: field)
        }
    }
}

private struct NowPlayingSettingsView: View {
    private enum NowPlayingBackgroundFillSource: String, CaseIterable {
        case accent
        case custom

        var title: String {
            switch self {
            case .accent:
                settingsLocalized("settings.now_playing.field.background_fill_source.option.accent")
            case .custom:
                settingsLocalized("settings.now_playing.field.background_fill_source.option.custom")
            }
        }
    }

    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var nowPlayingManager = NowPlayingManager.shared

    @State private var showAlbumArt = true
    @State private var showArtist = true
    @State private var showPauseIndicator = true
    @State private var backgroundFillEnabled = false
    @State private var backgroundFillSource = NowPlayingBackgroundFillSource.accent
    @State private var backgroundFillColorHex = "#4A90E2"
    @State private var hideAfterPausedMinutes = 10.0
    @State private var maxCharactersPerLine = 25.0
    @State private var scrollLongText = false
    @State private var popupLayout = NowPlayingPopupLayout.horizontal
    @State private var showPlaybackProgress = true
    @State private var showTransportControls = true
    @State private var isApplyingConfigSnapshot = false
    @State private var pendingBoolWrites: [String: Bool] = [:]
    @State private var pendingStringWrites: [String: String] = [:]
    @State private var pendingIntWrites: [String: Int] = [:]

    private let nowPlayingTable = "widgets.default.nowplaying"
    private let nowPlayingPopupTable = "widgets.default.nowplaying.popup"
    private var backgroundFillColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: backgroundFillColorHex) ?? Color(red: 74 / 255, green: 144 / 255, blue: 226 / 255) },
            set: { newValue in
                let hex = newValue.toHexString() ?? "#4A90E2"
                backgroundFillColorHex = hex
                setStringValue(hex, for: .init(tablePath: nowPlayingTable, key: "background-fill-color"))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.now_playing.header.title"),
                description: settingsLocalized("settings.now_playing.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.card.widget"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWidgetDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.now_playing.field.show_album_art.title"),
                    description: settingsLocalized("settings.now_playing.field.show_album_art.description"),
                    isOn: bindingForBool(
                        $showAlbumArt,
                        field: .init(tablePath: nowPlayingTable, key: "show-album-art")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.now_playing.field.show_artist.title"),
                    description: settingsLocalized("settings.now_playing.field.show_artist.description"),
                    isOn: bindingForBool(
                        $showArtist,
                        field: .init(tablePath: nowPlayingTable, key: "show-artist")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.now_playing.field.show_pause_indicator.title"),
                    description: settingsLocalized("settings.now_playing.field.show_pause_indicator.description"),
                    isOn: bindingForBool(
                        $showPauseIndicator,
                        field: .init(tablePath: nowPlayingTable, key: "show-pause-indicator")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.now_playing.field.background_fill_enabled.title"),
                    description: settingsLocalized("settings.now_playing.field.background_fill_enabled.description"),
                    isOn: bindingForBool(
                        $backgroundFillEnabled,
                        field: .init(tablePath: nowPlayingTable, key: "background-fill-enabled")
                    )
                )

                if backgroundFillEnabled {
                    SegmentedPickerRow(
                        title: settingsLocalized("settings.now_playing.field.background_fill_source.title"),
                        description: settingsLocalized("settings.now_playing.field.background_fill_source.description"),
                        selection: Binding(
                            get: { backgroundFillSource },
                            set: { newValue in
                                backgroundFillSource = newValue
                                setStringValue(newValue.rawValue, for: .init(tablePath: nowPlayingTable, key: "background-fill-source"))
                            }
                        ),
                        options: NowPlayingBackgroundFillSource.allCases,
                        titleForOption: { $0.title }
                    )

                    if backgroundFillSource == .custom {
                        ColorSettingRow(
                            title: settingsLocalized("settings.now_playing.field.background_fill_color.title"),
                            description: settingsLocalized("settings.now_playing.field.background_fill_color.description"),
                            color: backgroundFillColorBinding,
                            hexText: Binding(
                                get: { backgroundFillColorHex },
                                set: { newValue in
                                    backgroundFillColorHex = newValue
                                    setStringValue(newValue, for: .init(tablePath: nowPlayingTable, key: "background-fill-color"))
                                }
                            )
                        )
                    }
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.now_playing.field.hide_after_paused_minutes.title"),
                    description: settingsLocalized("settings.now_playing.field.hide_after_paused_minutes.description"),
                    value: $hideAfterPausedMinutes,
                    range: 1...120,
                    step: 1,
                    valueFormat: { "\($0.formatted(.number.precision(.fractionLength(0)))) min" }
                )
                .onChange(of: hideAfterPausedMinutes) { _, newValue in
                    setIntValue(Int(newValue.rounded()), for: .init(tablePath: nowPlayingTable, key: "hide-after-paused-minutes"))
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.now_playing.field.max_characters_per_line.title"),
                    description: settingsLocalized("settings.now_playing.field.max_characters_per_line.description"),
                    value: $maxCharactersPerLine,
                    range: 8...60,
                    step: 1,
                    valueFormat: { "\($0.formatted(.number.precision(.fractionLength(0))))" }
                )
                .onChange(of: maxCharactersPerLine) { _, newValue in
                    setIntValue(Int(newValue.rounded()), for: .init(tablePath: nowPlayingTable, key: "max-characters-per-line"))
                }

                ToggleRow(
                    title: settingsLocalized("settings.now_playing.field.scroll_long_text.title"),
                    description: settingsLocalized("settings.now_playing.field.scroll_long_text.description"),
                    isOn: bindingForBool(
                        $scrollLongText,
                        field: .init(tablePath: nowPlayingTable, key: "scroll-long-text")
                    )
                )
            }

            SettingsCardView(
                settingsLocalized("settings.card.popup"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetPopupDefaults
            ) {
                SegmentedPickerRow(
                    title: settingsLocalized("settings.field.popup_layout.title"),
                    description: settingsLocalized("settings.now_playing.field.popup_layout.description"),
                    selection: Binding(
                        get: { popupLayout },
                        set: { newValue in
                            popupLayout = newValue
                            setStringValue(newValue.rawValue, for: .init(tablePath: nowPlayingPopupTable, key: "view-variant"))
                        }
                    ),
                    options: NowPlayingPopupLayout.allCases,
                    titleForOption: { $0.title }
                )

                ToggleRow(
                    title: settingsLocalized("settings.now_playing.field.show_playback_progress.title"),
                    description: settingsLocalized("settings.now_playing.field.show_playback_progress.description"),
                    isOn: bindingForBool(
                        $showPlaybackProgress,
                        field: .init(tablePath: nowPlayingPopupTable, key: "show-playback-progress")
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.now_playing.field.show_transport_controls.title"),
                    description: settingsLocalized("settings.now_playing.field.show_transport_controls.description"),
                    isOn: bindingForBool(
                        $showTransportControls,
                        field: .init(tablePath: nowPlayingPopupTable, key: "show-transport-controls")
                    )
                )
            }

            SettingsCardView(settingsLocalized("settings.card.status")) {
                VStack(alignment: .leading, spacing: 8) {
                    if let song = nowPlayingManager.nowPlaying {
                        Text(song.title)
                            .font(.headline)

                        Text(song.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(settingsLocalized("settings.now_playing.status.no_session"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { config in
            settingsStore.refresh(with: config)
            loadFromConfig()
        }
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let showAlbumArtField = SettingsFieldKey(tablePath: nowPlayingTable, key: "show-album-art")
        let showArtistField = SettingsFieldKey(tablePath: nowPlayingTable, key: "show-artist")
        let showPauseIndicatorField = SettingsFieldKey(tablePath: nowPlayingTable, key: "show-pause-indicator")
        let backgroundFillEnabledField = SettingsFieldKey(tablePath: nowPlayingTable, key: "background-fill-enabled")
        let backgroundFillSourceField = SettingsFieldKey(tablePath: nowPlayingTable, key: "background-fill-source")
        let backgroundFillColorField = SettingsFieldKey(tablePath: nowPlayingTable, key: "background-fill-color")
        let hideAfterPausedMinutesField = SettingsFieldKey(tablePath: nowPlayingTable, key: "hide-after-paused-minutes")
        let maxCharactersPerLineField = SettingsFieldKey(tablePath: nowPlayingTable, key: "max-characters-per-line")
        let scrollLongTextField = SettingsFieldKey(tablePath: nowPlayingTable, key: "scroll-long-text")
        let popupLayoutField = SettingsFieldKey(tablePath: nowPlayingPopupTable, key: "view-variant")
        let showPlaybackProgressField = SettingsFieldKey(tablePath: nowPlayingPopupTable, key: "show-playback-progress")
        let showTransportControlsField = SettingsFieldKey(tablePath: nowPlayingPopupTable, key: "show-transport-controls")

        showAlbumArt = resolvedBoolValue(for: showAlbumArtField, incoming: settingsStore.boolValue(showAlbumArtField, fallback: true), current: showAlbumArt)
        showArtist = resolvedBoolValue(for: showArtistField, incoming: settingsStore.boolValue(showArtistField, fallback: true), current: showArtist)
        showPauseIndicator = resolvedBoolValue(for: showPauseIndicatorField, incoming: settingsStore.boolValue(showPauseIndicatorField, fallback: true), current: showPauseIndicator)
        backgroundFillEnabled = resolvedBoolValue(for: backgroundFillEnabledField, incoming: settingsStore.boolValue(backgroundFillEnabledField, fallback: false), current: backgroundFillEnabled)
        backgroundFillSource = NowPlayingBackgroundFillSource(
            rawValue: resolvedStringValue(
                for: backgroundFillSourceField,
                incoming: settingsStore.stringValue(backgroundFillSourceField, fallback: NowPlayingBackgroundFillSource.accent.rawValue),
                current: backgroundFillSource.rawValue
            )
        ) ?? .accent
        backgroundFillColorHex = resolvedStringValue(
            for: backgroundFillColorField,
            incoming: settingsStore.stringValue(backgroundFillColorField, fallback: "#4A90E2"),
            current: backgroundFillColorHex
        )
        hideAfterPausedMinutes = Double(resolvedIntValue(for: hideAfterPausedMinutesField, incoming: settingsStore.intValue(hideAfterPausedMinutesField, fallback: 10), current: Int(hideAfterPausedMinutes.rounded())))
        maxCharactersPerLine = Double(resolvedIntValue(for: maxCharactersPerLineField, incoming: settingsStore.intValue(maxCharactersPerLineField, fallback: 25), current: Int(maxCharactersPerLine.rounded())))
        scrollLongText = resolvedBoolValue(for: scrollLongTextField, incoming: settingsStore.boolValue(scrollLongTextField, fallback: false), current: scrollLongText)
        popupLayout = NowPlayingPopupLayout(
            rawValue: resolvedStringValue(
                for: popupLayoutField,
                incoming: settingsStore.stringValue(popupLayoutField, fallback: NowPlayingPopupLayout.horizontal.rawValue),
                current: popupLayout.rawValue
            )
        ) ?? .horizontal
        showPlaybackProgress = resolvedBoolValue(for: showPlaybackProgressField, incoming: settingsStore.boolValue(showPlaybackProgressField, fallback: true), current: showPlaybackProgress)
        showTransportControls = resolvedBoolValue(for: showTransportControlsField, incoming: settingsStore.boolValue(showTransportControlsField, fallback: true), current: showTransportControls)

        isApplyingConfigSnapshot = false
    }

    private func bindingForBool(
        _ state: Binding<Bool>,
        field: SettingsFieldKey
    ) -> Binding<Bool> {
        Binding(
            get: { state.wrappedValue },
            set: { newValue in
                state.wrappedValue = newValue
                setBoolValue(newValue, for: field)
            }
        )
    }

    private func setBoolValue(_ value: Bool, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingBoolWrites[fieldIdentifier(field)] = value
        Task { @MainActor in
            settingsStore.setBool(value, for: field)
        }
    }

    private func setStringValue(_ value: String, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingStringWrites[fieldIdentifier(field)] = value
        Task { @MainActor in
            settingsStore.setString(value, for: field)
        }
    }

    private func setIntValue(_ value: Int, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingIntWrites[fieldIdentifier(field)] = value
        Task { @MainActor in
            settingsStore.setInt(value, for: field)
        }
    }

    private func resolvedBoolValue(for field: SettingsFieldKey, incoming: Bool, current: Bool) -> Bool {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingBoolWrites[fieldID] {
            if incoming == pendingValue {
                pendingBoolWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedStringValue(for field: SettingsFieldKey, incoming: String, current: String) -> String {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingStringWrites[fieldID] {
            if incoming == pendingValue {
                pendingStringWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedIntValue(for field: SettingsFieldKey, incoming: Int, current: Int) -> Int {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingIntWrites[fieldID] {
            if incoming == pendingValue {
                pendingIntWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func fieldIdentifier(_ field: SettingsFieldKey) -> String {
        "\(field.tablePath).\(field.key)"
    }

    private func resetWidgetDefaults() {
        isApplyingConfigSnapshot = true
        showAlbumArt = true
        showArtist = true
        showPauseIndicator = true
        backgroundFillEnabled = false
        backgroundFillSource = .accent
        backgroundFillColorHex = "#4A90E2"
        hideAfterPausedMinutes = 10
        maxCharactersPerLine = 25
        scrollLongText = false
        isApplyingConfigSnapshot = false

        settingsStore.setBool(true, for: .init(tablePath: nowPlayingTable, key: "show-album-art"))
        settingsStore.setBool(true, for: .init(tablePath: nowPlayingTable, key: "show-artist"))
        settingsStore.setBool(true, for: .init(tablePath: nowPlayingTable, key: "show-pause-indicator"))
        settingsStore.setBool(false, for: .init(tablePath: nowPlayingTable, key: "background-fill-enabled"))
        settingsStore.setString("accent", for: .init(tablePath: nowPlayingTable, key: "background-fill-source"))
        settingsStore.setString("#4A90E2", for: .init(tablePath: nowPlayingTable, key: "background-fill-color"))
        settingsStore.setInt(10, for: .init(tablePath: nowPlayingTable, key: "hide-after-paused-minutes"))
        settingsStore.setInt(25, for: .init(tablePath: nowPlayingTable, key: "max-characters-per-line"))
        settingsStore.setBool(false, for: .init(tablePath: nowPlayingTable, key: "scroll-long-text"))
    }

    private func resetPopupDefaults() {
        isApplyingConfigSnapshot = true
        popupLayout = .horizontal
        showPlaybackProgress = true
        showTransportControls = true
        isApplyingConfigSnapshot = false

        settingsStore.setString("horizontal", for: .init(tablePath: nowPlayingPopupTable, key: "view-variant"))
        settingsStore.setBool(true, for: .init(tablePath: nowPlayingPopupTable, key: "show-playback-progress"))
        settingsStore.setBool(true, for: .init(tablePath: nowPlayingPopupTable, key: "show-transport-controls"))
    }
}

private struct CLIProxyUsageSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var usageManager = CLIProxyUsageManager.shared

    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var refreshInterval = 300.0
    @State private var showRing = false
    @State private var showLabel = true
    @State private var ringLogic = UsageRingLogic.healthy
    @State private var warningLevel = 90.0
    @State private var criticalLevel = 80.0
    @State private var isApplyingConfigSnapshot = false

    @State private var baseURLTask: Task<Void, Never>?
    @State private var apiKeyTask: Task<Void, Never>?

    private let widgetID = "default.cliproxy-usage"
    private let tablePath = "widgets.default.cliproxy-usage"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.cli_proxy.header.title"),
                description: settingsLocalized("settings.cli_proxy.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.card.connection"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetConnectionDefaults
            ) {
                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.field.base_url.title"),
                    description: settingsLocalized("settings.cli_proxy.field.base_url.description"),
                    text: $baseURL
                )
                .onChange(of: baseURL) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(
                        task: &baseURLTask,
                        key: "base-url",
                        value: newValue
                    )
                }

                SecureTextSettingRow(
                    title: settingsLocalized("settings.field.api_key.title"),
                    description: settingsLocalized("settings.cli_proxy.field.api_key.description"),
                    text: $apiKey
                )
                .onChange(of: apiKey) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(
                        task: &apiKeyTask,
                        key: "api-key",
                        value: newValue
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.field.refresh_interval.title"),
                    description: settingsLocalized("settings.cli_proxy.field.refresh_interval.description"),
                    value: $refreshInterval,
                    range: 15...1800,
                    step: 15,
                    valueFormat: { formatDuration(seconds: Int($0.rounded())) }
                )
                .onChange(of: refreshInterval) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "refresh-interval",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.card.widget_appearance"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWidgetDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.field.show_ring.title"),
                    description: settingsLocalized("settings.cli_proxy.field.show_ring.description"),
                    isOn: $showRing
                )
                .onChange(of: showRing) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "show-ring",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }

                ToggleRow(
                    title: settingsLocalized("settings.field.show_label.title"),
                    description: settingsLocalized("settings.cli_proxy.field.show_label.description"),
                    isOn: $showLabel
                )
                .onChange(of: showLabel) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "show-label",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }

                SegmentedPickerRow(
                    title: settingsLocalized("settings.field.ring_logic.title"),
                    description: settingsLocalized("settings.cli_proxy.field.ring_logic.description"),
                    selection: $ringLogic,
                    options: UsageRingLogic.allCases,
                    titleForOption: \.title
                )
                .onChange(of: ringLogic) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "ring-logic",
                        newValueLiteral: "\"\(newValue.rawValue)\""
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.field.warning_level.title"),
                    description: settingsLocalized("settings.cli_proxy.field.warning_level.description"),
                    value: $warningLevel,
                    range: 0...100,
                    step: 1,
                    valueFormat: { "\(Int($0.rounded()))%" }
                )
                .onChange(of: warningLevel) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "warning-level",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.field.critical_level.title"),
                    description: settingsLocalized("settings.cli_proxy.field.critical_level.description"),
                    value: $criticalLevel,
                    range: 0...100,
                    step: 1,
                    valueFormat: { "\(Int($0.rounded()))%" }
                )
                .onChange(of: criticalLevel) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "critical-level",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }
            }

            SettingsCardView(settingsLocalized("settings.card.status")) {
                ProxyUsageStatusView(
                    title: usageManager.usageData.isAvailable
                        ? String(
                            format: settingsLocalized("settings.cli_proxy.status.title.available"),
                            locale: .autoupdatingCurrent,
                            Int((usageManager.usageData.quotaSummary(for: .all).percentage * 100).rounded())
                        )
                        : settingsLocalized("settings.status.waiting_for_data"),
                    description: statusText,
                    isHealthy: usageManager.usageData.isAvailable && !usageManager.fetchFailed,
                    refreshAction: refreshManager
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onAppear(perform: refreshManager)
        .onReceive(configManager.$config) { _ in
            loadFromConfig()
            refreshManager()
        }
        .onDisappear {
            baseURLTask?.cancel()
            apiKeyTask?.cancel()
        }
    }

    private var statusText: String {
        if usageManager.fetchFailed {
            return usageManager.errorMessage ?? settingsLocalized("settings.cli_proxy.status.request_failed")
        }
        if usageManager.usageData.isAvailable {
            return settingsLocalized("settings.cli_proxy.status.live")
        }
        if usageManager.hasConfiguration(in: configManager.globalWidgetConfig(for: widgetID)) {
            return settingsLocalized("settings.cli_proxy.status.config_saved")
        }
        return settingsLocalized("settings.cli_proxy.status.needs_connection")
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let config = configManager.globalWidgetConfig(for: widgetID)
        baseURL = stringValue(in: config, keys: ["base-url", "base_url"]) ?? ""
        apiKey = stringValue(in: config, keys: ["api-key", "api_key"]) ?? ""
        refreshInterval = Double(
            intValue(in: config, keys: ["refresh-interval", "refresh_interval"]) ?? 300
        )
        showRing = boolValue(in: config, keys: ["show-ring", "show_ring"]) ?? false
        showLabel = boolValue(in: config, keys: ["show-label", "show_label"]) ?? !showRing
        ringLogic = UsageRingLogic(
            rawValue: stringValue(in: config, keys: ["ring-logic", "ring_logic"]) ?? UsageRingLogic.healthy.rawValue
        ) ?? .healthy
        warningLevel = Double(
            intValue(in: config, keys: ["warning-level", "warning_level", "ring-warning-level", "ring_warning_level"]) ?? 90
        )
        criticalLevel = Double(
            intValue(in: config, keys: ["critical-level", "critical_level", "ring-critical-level", "ring_critical_level"]) ?? 80
        )

        isApplyingConfigSnapshot = false
    }

    private func scheduleStringWrite(
        task: inout Task<Void, Never>?,
        key: String,
        value: String
    ) {
        task?.cancel()
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            if trimmedValue.isEmpty {
                ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: key)
            } else {
                ConfigManager.shared.updateConfigValue(
                    tablePath: tablePath,
                    key: key,
                    newValue: trimmedValue
                )
            }
        }
    }

    private func resetConnectionDefaults() {
        baseURLTask?.cancel()
        apiKeyTask?.cancel()

        isApplyingConfigSnapshot = true
        baseURL = ""
        apiKey = ""
        refreshInterval = 300
        isApplyingConfigSnapshot = false

        ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "base-url")
        ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "api-key")
        ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "base_url")
        ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "api_key")
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "refresh-interval",
            newValueLiteral: "300"
        )
    }

    private func resetWidgetDefaults() {
        isApplyingConfigSnapshot = true
        showRing = false
        showLabel = true
        ringLogic = .healthy
        warningLevel = 90
        criticalLevel = 80
        isApplyingConfigSnapshot = false

        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "show-ring",
            newValueLiteral: "false"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "show-label",
            newValueLiteral: "true"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "ring-logic",
            newValueLiteral: "\"healthy\""
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "warning-level",
            newValueLiteral: "90"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "critical-level",
            newValueLiteral: "80"
        )
    }

    private func refreshManager() {
        usageManager.startUpdating(config: configManager.globalWidgetConfig(for: widgetID))
    }
}

private struct QwenProxyUsageSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var usageManager = QwenProxyUsageManager.shared

    @State private var baseURL = ""
    @State private var token = ""
    @State private var showRing = false
    @State private var showLabel = true
    @State private var ringLogic = UsageRingLogic.failed
    @State private var warningLevel = 30.0
    @State private var criticalLevel = 50.0
    @State private var isApplyingConfigSnapshot = false

    @State private var baseURLTask: Task<Void, Never>?
    @State private var tokenTask: Task<Void, Never>?

    private let widgetID = "default.qwen-proxy-usage"
    private let tablePath = "widgets.default.qwen-proxy-usage"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.qwen_proxy.header.title"),
                description: settingsLocalized("settings.qwen_proxy.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.card.connection"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetConnectionDefaults
            ) {
                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.field.base_url.title"),
                    description: settingsLocalized("settings.qwen_proxy.field.base_url.description"),
                    text: $baseURL
                )
                .onChange(of: baseURL) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(
                        task: &baseURLTask,
                        key: "base-url",
                        value: newValue
                    )
                }

                SecureTextSettingRow(
                    title: settingsLocalized("settings.field.token.title"),
                    description: settingsLocalized("settings.qwen_proxy.field.token.description"),
                    text: $token
                )
                .onChange(of: token) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(
                        task: &tokenTask,
                        key: "token",
                        value: newValue
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.card.widget_appearance"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWidgetDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.field.show_ring.title"),
                    description: settingsLocalized("settings.qwen_proxy.field.show_ring.description"),
                    isOn: $showRing
                )
                .onChange(of: showRing) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "show-ring",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }

                ToggleRow(
                    title: settingsLocalized("settings.field.show_label.title"),
                    description: settingsLocalized("settings.qwen_proxy.field.show_label.description"),
                    isOn: $showLabel
                )
                .onChange(of: showLabel) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "show-label",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }

                SegmentedPickerRow(
                    title: settingsLocalized("settings.field.ring_logic.title"),
                    description: settingsLocalized("settings.qwen_proxy.field.ring_logic.description"),
                    selection: $ringLogic,
                    options: UsageRingLogic.allCases,
                    titleForOption: \.title
                )
                .onChange(of: ringLogic) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "ring-logic",
                        newValueLiteral: "\"\(newValue.rawValue)\""
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.field.warning_level.title"),
                    description: settingsLocalized("settings.qwen_proxy.field.warning_level.description"),
                    value: $warningLevel,
                    range: 0...100,
                    step: 1,
                    valueFormat: { "\(Int($0.rounded()))%" }
                )
                .onChange(of: warningLevel) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "ring-warning-level",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.field.critical_level.title"),
                    description: settingsLocalized("settings.qwen_proxy.field.critical_level.description"),
                    value: $criticalLevel,
                    range: 0...100,
                    step: 1,
                    valueFormat: { "\(Int($0.rounded()))%" }
                )
                .onChange(of: criticalLevel) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: tablePath,
                        key: "ring-critical-level",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }
            }

            SettingsCardView(settingsLocalized("settings.card.status")) {
                ProxyUsageStatusView(
                    title: usageManager.usageData.isAvailable
                        ? String(
                            format: settingsLocalized("settings.qwen_proxy.status.title.healthy"),
                            locale: .autoupdatingCurrent,
                            usageManager.usageData.summary.healthy,
                            usageManager.usageData.summary.total
                        )
                        : settingsLocalized("settings.status.waiting_for_data"),
                    description: statusText,
                    isHealthy: usageManager.usageData.isAvailable && !usageManager.fetchFailed,
                    refreshAction: refreshManager
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onAppear(perform: refreshManager)
        .onReceive(configManager.$config) { _ in
            loadFromConfig()
            refreshManager()
        }
        .onDisappear {
            baseURLTask?.cancel()
            tokenTask?.cancel()
        }
    }

    private var statusText: String {
        if usageManager.fetchFailed {
            return usageManager.errorMessage ?? settingsLocalized("settings.qwen_proxy.status.failed")
        }
        if usageManager.usageData.isAvailable {
            return settingsLocalized("settings.qwen_proxy.status.live")
        }
        if !(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            return settingsLocalized("settings.qwen_proxy.status.config_saved")
        }
        return settingsLocalized("settings.qwen_proxy.status.needs_connection")
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let config = configManager.globalWidgetConfig(for: widgetID)
        baseURL = stringValue(in: config, keys: ["base-url", "base_url"]) ?? ""
        token = stringValue(in: config, keys: ["token"]) ?? ""
        showRing = boolValue(in: config, keys: ["show-ring", "show_ring"]) ?? false
        showLabel = boolValue(in: config, keys: ["show-label", "show_label"]) ?? !showRing
        ringLogic = UsageRingLogic(
            rawValue: stringValue(in: config, keys: ["ring-logic", "ring_logic"]) ?? UsageRingLogic.failed.rawValue
        ) ?? .failed
        warningLevel = Double(
            intValue(in: config, keys: ["ring-warning-level", "ring_warning_level"]) ?? (ringLogic == .healthy ? 60 : 30)
        )
        criticalLevel = Double(
            intValue(in: config, keys: ["ring-critical-level", "ring_critical_level"]) ?? (ringLogic == .healthy ? 30 : 50)
        )

        isApplyingConfigSnapshot = false
    }

    private func scheduleStringWrite(
        task: inout Task<Void, Never>?,
        key: String,
        value: String
    ) {
        task?.cancel()
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            if trimmedValue.isEmpty {
                ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: key)
            } else {
                ConfigManager.shared.updateConfigValue(
                    tablePath: tablePath,
                    key: key,
                    newValue: trimmedValue
                )
            }
        }
    }

    private func resetConnectionDefaults() {
        baseURLTask?.cancel()
        tokenTask?.cancel()

        isApplyingConfigSnapshot = true
        baseURL = ""
        token = ""
        isApplyingConfigSnapshot = false

        ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "base-url")
        ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "base_url")
        ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "token")
    }

    private func resetWidgetDefaults() {
        isApplyingConfigSnapshot = true
        showRing = false
        showLabel = true
        ringLogic = .failed
        warningLevel = 30
        criticalLevel = 50
        isApplyingConfigSnapshot = false

        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "show-ring",
            newValueLiteral: "false"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "show-label",
            newValueLiteral: "true"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "ring-logic",
            newValueLiteral: "\"failed\""
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "ring-warning-level",
            newValueLiteral: "30"
        )
        ConfigManager.shared.updateConfigLiteralValue(
            tablePath: tablePath,
            key: "ring-critical-level",
            newValueLiteral: "50"
        )
    }

    private func refreshManager() {
        usageManager.startUpdating(config: configManager.globalWidgetConfig(for: widgetID))
    }
}

private struct ClaudeUsageSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var usageManager = ClaudeUsageManager.shared

    @State private var planOverride = ""
    @State private var isApplyingConfigSnapshot = false
    @State private var planTask: Task<Void, Never>?

    private let widgetID = "default.claude-usage"
    private let tablePath = "widgets.default.claude-usage"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.claude.header.title"),
                description: settingsLocalized("settings.claude.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.card.display"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetDefaults
            ) {
                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.field.plan_override.title"),
                    description: settingsLocalized("settings.claude.field.plan_override.description"),
                    text: $planOverride
                )
                .onChange(of: planOverride) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    schedulePlanWrite(newValue)
                }
            }

            SettingsCardView(settingsLocalized("settings.card.connection")) {
                ProxyUsageStatusView(
                    title: usageManager.isConnected ? settingsLocalized("settings.status.connected") : settingsLocalized("settings.status.not_connected"),
                    description: claudeStatusText,
                    isHealthy: usageManager.isConnected && !usageManager.fetchFailed,
                    refreshAction: usageManager.refresh
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onAppear(perform: refreshManager)
        .onReceive(configManager.$config) { _ in
            loadFromConfig()
            refreshManager()
        }
        .onDisappear {
            planTask?.cancel()
        }
    }

    private var claudeStatusText: String {
        if usageManager.fetchFailed {
            return usageManager.errorMessage ?? settingsLocalized("settings.claude.status.failed")
        }
        if usageManager.usageData.isAvailable {
            return settingsLocalized("settings.claude.status.live")
        }
        if usageManager.isConnected {
            return settingsLocalized("settings.claude.status.connected")
        }
        return settingsLocalized("settings.claude.status.no_credentials")
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true
        let config = configManager.globalWidgetConfig(for: widgetID)
        planOverride = stringValue(in: config, keys: ["plan"]) ?? ""
        isApplyingConfigSnapshot = false
    }

    private func schedulePlanWrite(_ value: String) {
        planTask?.cancel()
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        planTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            if trimmedValue.isEmpty {
                ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "plan")
            } else {
                ConfigManager.shared.updateConfigValue(
                    tablePath: tablePath,
                    key: "plan",
                    newValue: trimmedValue
                )
            }
        }
    }

    private func resetDefaults() {
        planTask?.cancel()
        isApplyingConfigSnapshot = true
        planOverride = ""
        isApplyingConfigSnapshot = false
        ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "plan")
    }

    private func refreshManager() {
        usageManager.startUpdating(config: configManager.globalWidgetConfig(for: widgetID))
    }
}

private struct CodexUsageSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var usageManager = CodexUsageManager.shared

    @State private var planOverride = ""
    @State private var isApplyingConfigSnapshot = false
    @State private var planTask: Task<Void, Never>?

    private let widgetID = "default.codex-usage"
    private let tablePath = "widgets.default.codex-usage"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.codex.header.title"),
                description: settingsLocalized("settings.codex.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.card.display"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetDefaults
            ) {
                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.field.plan_override.title"),
                    description: settingsLocalized("settings.codex.field.plan_override.description"),
                    text: $planOverride
                )
                .onChange(of: planOverride) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    schedulePlanWrite(newValue)
                }
            }

            SettingsCardView(settingsLocalized("settings.card.connection")) {
                ProxyUsageStatusView(
                    title: usageManager.isConnected ? settingsLocalized("settings.status.connected") : settingsLocalized("settings.status.not_connected"),
                    description: codexStatusText,
                    isHealthy: usageManager.isConnected && !usageManager.fetchFailed,
                    refreshAction: usageManager.refresh
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onAppear(perform: refreshManager)
        .onReceive(configManager.$config) { _ in
            loadFromConfig()
            refreshManager()
        }
        .onDisappear {
            planTask?.cancel()
        }
    }

    private var codexStatusText: String {
        if usageManager.fetchFailed {
            return settingsLocalized("settings.codex.status.failed")
        }
        if usageManager.usageData.isAvailable {
            return settingsLocalized("settings.codex.status.live")
        }
        if usageManager.isConnected {
            return settingsLocalized("settings.codex.status.connected")
        }
        return settingsLocalized("settings.codex.status.no_credentials")
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true
        let config = configManager.globalWidgetConfig(for: widgetID)
        planOverride = stringValue(in: config, keys: ["plan"]) ?? ""
        isApplyingConfigSnapshot = false
    }

    private func schedulePlanWrite(_ value: String) {
        planTask?.cancel()
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        planTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            if trimmedValue.isEmpty {
                ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "plan")
            } else {
                ConfigManager.shared.updateConfigValue(
                    tablePath: tablePath,
                    key: "plan",
                    newValue: trimmedValue
                )
            }
        }
    }

    private func resetDefaults() {
        planTask?.cancel()
        isApplyingConfigSnapshot = true
        planOverride = ""
        isApplyingConfigSnapshot = false
        ConfigManager.shared.removeConfigValue(tablePath: tablePath, key: "plan")
    }

    private func refreshManager() {
        usageManager.startUpdating(config: configManager.globalWidgetConfig(for: widgetID))
    }
}

private struct PomodoroSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var pomodoroManager = PomodoroManager.shared

    @State private var integrationMode = PomodoroIntegrationMode.local
    @State private var displayMode = PomodoroDisplayModeSelection.timer
    @State private var showSeconds = false
    @State private var nativeMirrorEnabled = false
    @State private var focusDuration = 25.0
    @State private var shortBreakDuration = 5.0
    @State private var longBreakDuration = 15.0
    @State private var longBreakInterval = 4.0
    @State private var playSoundOnFocusEnd = true
    @State private var playSoundOnBreakEnd = true
    @State private var repeatBreakFinishedSoundUntilPopupOpened = false
    @State private var breakFinishedSoundRepeatInterval = 12.0
    @State private var isApplyingConfigSnapshot = false
    @State private var pendingStringWrites: [String: String] = [:]
    @State private var pendingBoolWrites: [String: Bool] = [:]
    @State private var pendingIntWrites: [String: Int] = [:]

    private let pomodoroTable = "widgets.default.pomodoro"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.pomodoro.header.title"),
                description: settingsLocalized("settings.pomodoro.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.card.display"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetDisplayDefaults
            ) {
                SegmentedPickerRow(
                    title: settingsLocalized("settings.pomodoro.field.integration_mode.title"),
                    description: settingsLocalized("settings.pomodoro.field.integration_mode.description"),
                    selection: Binding(
                        get: { integrationMode },
                        set: { newValue in
                            integrationMode = newValue
                            setStringValue(
                                newValue.rawValue,
                                for: .init(tablePath: pomodoroTable, key: "mode")
                            )
                        }
                    ),
                    options: PomodoroIntegrationMode.allCases,
                    titleForOption: { $0.title }
                )

                SegmentedPickerRow(
                    title: settingsLocalized("settings.pomodoro.field.widget_layout.title"),
                    description: settingsLocalized("settings.pomodoro.field.widget_layout.description"),
                    selection: Binding(
                        get: { displayMode },
                        set: { newValue in
                            displayMode = newValue
                            setStringValue(
                                newValue.rawValue,
                                for: .init(tablePath: pomodoroTable, key: "display-mode")
                            )
                        }
                    ),
                    options: PomodoroDisplayModeSelection.allCases,
                    titleForOption: { $0.title }
                )

                ToggleRow(
                    title: settingsLocalized("settings.pomodoro.field.show_seconds.title"),
                    description: settingsLocalized("settings.pomodoro.field.show_seconds.description"),
                    isOn: Binding(
                        get: { showSeconds },
                        set: { newValue in
                            showSeconds = newValue
                            setBoolValue(
                                newValue,
                                for: .init(tablePath: pomodoroTable, key: "show-seconds")
                            )
                        }
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.pomodoro.field.native_mirror.title"),
                    description: settingsLocalized("settings.pomodoro.field.native_mirror.description"),
                    isOn: Binding(
                        get: { nativeMirrorEnabled },
                        set: { newValue in
                            nativeMirrorEnabled = newValue
                            setBoolValue(
                                newValue,
                                for: .init(tablePath: pomodoroTable, key: "native-mirror")
                            )
                        }
                    )
                )
            }

            SettingsCardView(
                settingsLocalized("settings.pomodoro.card.durations"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetDurationDefaults
            ) {
                SliderSettingRow(
                    title: settingsLocalized("settings.pomodoro.field.focus_duration.title"),
                    description: settingsLocalized("settings.pomodoro.field.focus_duration.description"),
                    value: $focusDuration,
                    range: 5...90,
                    step: 1,
                    valueFormat: { "\(Int($0)) min" }
                )
                .onChange(of: focusDuration) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(
                        Int(newValue.rounded()),
                        for: .init(tablePath: pomodoroTable, key: "focus-duration")
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.pomodoro.field.short_break.title"),
                    description: settingsLocalized("settings.pomodoro.field.short_break.description"),
                    value: $shortBreakDuration,
                    range: 1...30,
                    step: 1,
                    valueFormat: { "\(Int($0)) min" }
                )
                .onChange(of: shortBreakDuration) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(
                        Int(newValue.rounded()),
                        for: .init(tablePath: pomodoroTable, key: "short-break-duration")
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.pomodoro.field.long_break.title"),
                    description: settingsLocalized("settings.pomodoro.field.long_break.description"),
                    value: $longBreakDuration,
                    range: 5...45,
                    step: 1,
                    valueFormat: { "\(Int($0)) min" }
                )
                .onChange(of: longBreakDuration) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(
                        Int(newValue.rounded()),
                        for: .init(tablePath: pomodoroTable, key: "long-break-duration")
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.pomodoro.field.long_break_every.title"),
                    description: settingsLocalized("settings.pomodoro.field.long_break_every.description"),
                    value: $longBreakInterval,
                    range: 2...8,
                    step: 1,
                    valueFormat: { "\(Int($0)) sessions" }
                )
                .onChange(of: longBreakInterval) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(
                        Int(newValue.rounded()),
                        for: .init(tablePath: pomodoroTable, key: "long-break-interval")
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.pomodoro.card.sounds"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetSoundDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.pomodoro.field.play_focus_end_sound.title"),
                    description: settingsLocalized("settings.pomodoro.field.play_focus_end_sound.description"),
                    isOn: Binding(
                        get: { playSoundOnFocusEnd },
                        set: { newValue in
                            playSoundOnFocusEnd = newValue
                            setBoolValue(
                                newValue,
                                for: .init(tablePath: pomodoroTable, key: "play-sound-on-focus-end")
                            )
                        }
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.pomodoro.field.play_break_end_sound.title"),
                    description: settingsLocalized("settings.pomodoro.field.play_break_end_sound.description"),
                    isOn: Binding(
                        get: { playSoundOnBreakEnd },
                        set: { newValue in
                            playSoundOnBreakEnd = newValue
                            setBoolValue(
                                newValue,
                                for: .init(tablePath: pomodoroTable, key: "play-sound-on-break-end")
                            )
                        }
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.pomodoro.field.repeat_break_sound_until_popup_opens.title"),
                    description: settingsLocalized("settings.pomodoro.field.repeat_break_sound_until_popup_opens.description"),
                    isOn: Binding(
                        get: { repeatBreakFinishedSoundUntilPopupOpened },
                        set: { newValue in
                            repeatBreakFinishedSoundUntilPopupOpened = newValue
                            setBoolValue(
                                newValue,
                                for: .init(tablePath: pomodoroTable, key: "repeat-break-finished-sound-until-popup-opened")
                            )
                        }
                    )
                )

                SliderSettingRow(
                    title: settingsLocalized("settings.pomodoro.field.repeat_interval.title"),
                    description: settingsLocalized("settings.pomodoro.field.repeat_interval.description"),
                    value: $breakFinishedSoundRepeatInterval,
                    range: 3...60,
                    step: 1,
                    valueFormat: { "\(Int($0)) sec" }
                )
                .disabled(!repeatBreakFinishedSoundUntilPopupOpened)
                .onChange(of: breakFinishedSoundRepeatInterval) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(
                        Int(newValue.rounded()),
                        for: .init(tablePath: pomodoroTable, key: "break-finished-sound-repeat-interval-seconds")
                    )
                }
            }

            SettingsCardView(settingsLocalized("settings.card.status")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pomodoroManager.phase.title)
                        .font(.headline)

                    Text(statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { config in
            settingsStore.refresh(with: config)
            loadFromConfig()
        }
    }

    private var statusDescription: String {
        String(
            format: settingsLocalized("settings.pomodoro.status.description"),
            locale: .autoupdatingCurrent,
            pomodoroManager.effectiveIntegrationMode.title,
            Int(focusDuration),
            Int(shortBreakDuration),
            Int(longBreakDuration)
        )
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let modeField = SettingsFieldKey(tablePath: pomodoroTable, key: "mode")
        let displayModeField = SettingsFieldKey(tablePath: pomodoroTable, key: "display-mode")
        let showSecondsField = SettingsFieldKey(tablePath: pomodoroTable, key: "show-seconds")
        let nativeMirrorField = SettingsFieldKey(tablePath: pomodoroTable, key: "native-mirror")
        let focusDurationField = SettingsFieldKey(tablePath: pomodoroTable, key: "focus-duration")
        let shortBreakField = SettingsFieldKey(tablePath: pomodoroTable, key: "short-break-duration")
        let longBreakField = SettingsFieldKey(tablePath: pomodoroTable, key: "long-break-duration")
        let longBreakIntervalField = SettingsFieldKey(tablePath: pomodoroTable, key: "long-break-interval")
        let playFocusSoundField = SettingsFieldKey(tablePath: pomodoroTable, key: "play-sound-on-focus-end")
        let playBreakSoundField = SettingsFieldKey(tablePath: pomodoroTable, key: "play-sound-on-break-end")
        let repeatBreakSoundField = SettingsFieldKey(tablePath: pomodoroTable, key: "repeat-break-finished-sound-until-popup-opened")
        let repeatIntervalField = SettingsFieldKey(tablePath: pomodoroTable, key: "break-finished-sound-repeat-interval-seconds")

        integrationMode = PomodoroIntegrationMode(
            rawValue: resolvedStringValue(
                for: modeField,
                incoming: settingsStore.stringValue(modeField, fallback: PomodoroIntegrationMode.local.rawValue),
                current: integrationMode.rawValue
            )
        ) ?? .local

        displayMode = PomodoroDisplayModeSelection(
            rawValue: resolvedStringValue(
                for: displayModeField,
                incoming: settingsStore.stringValue(displayModeField, fallback: PomodoroDisplayModeSelection.timer.rawValue),
                current: displayMode.rawValue
            )
        ) ?? .timer

        showSeconds = resolvedBoolValue(
            for: showSecondsField,
            incoming: settingsStore.boolValue(showSecondsField, fallback: false),
            current: showSeconds
        )
        nativeMirrorEnabled = resolvedBoolValue(
            for: nativeMirrorField,
            incoming: settingsStore.boolValue(nativeMirrorField, fallback: false),
            current: nativeMirrorEnabled
        )
        focusDuration = Double(
            resolvedIntValue(
                for: focusDurationField,
                incoming: settingsStore.intValue(focusDurationField, fallback: 25),
                current: Int(focusDuration.rounded())
            )
        )
        shortBreakDuration = Double(
            resolvedIntValue(
                for: shortBreakField,
                incoming: settingsStore.intValue(shortBreakField, fallback: 5),
                current: Int(shortBreakDuration.rounded())
            )
        )
        longBreakDuration = Double(
            resolvedIntValue(
                for: longBreakField,
                incoming: settingsStore.intValue(longBreakField, fallback: 15),
                current: Int(longBreakDuration.rounded())
            )
        )
        longBreakInterval = Double(
            resolvedIntValue(
                for: longBreakIntervalField,
                incoming: settingsStore.intValue(longBreakIntervalField, fallback: 4),
                current: Int(longBreakInterval.rounded())
            )
        )
        playSoundOnFocusEnd = resolvedBoolValue(
            for: playFocusSoundField,
            incoming: settingsStore.boolValue(playFocusSoundField, fallback: true),
            current: playSoundOnFocusEnd
        )
        playSoundOnBreakEnd = resolvedBoolValue(
            for: playBreakSoundField,
            incoming: settingsStore.boolValue(playBreakSoundField, fallback: true),
            current: playSoundOnBreakEnd
        )
        repeatBreakFinishedSoundUntilPopupOpened = resolvedBoolValue(
            for: repeatBreakSoundField,
            incoming: settingsStore.boolValue(repeatBreakSoundField, fallback: false),
            current: repeatBreakFinishedSoundUntilPopupOpened
        )
        breakFinishedSoundRepeatInterval = Double(
            resolvedIntValue(
                for: repeatIntervalField,
                incoming: settingsStore.intValue(repeatIntervalField, fallback: 12),
                current: Int(breakFinishedSoundRepeatInterval.rounded())
            )
        )

        isApplyingConfigSnapshot = false
    }

    private func resetDisplayDefaults() {
        isApplyingConfigSnapshot = true
        integrationMode = .local
        displayMode = .timer
        showSeconds = false
        nativeMirrorEnabled = false
        isApplyingConfigSnapshot = false

        pendingStringWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "mode")))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "display-mode")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "show-seconds")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "native-mirror")))

        settingsStore.setString("local", for: .init(tablePath: pomodoroTable, key: "mode"))
        settingsStore.setString("timer", for: .init(tablePath: pomodoroTable, key: "display-mode"))
        settingsStore.setBool(false, for: .init(tablePath: pomodoroTable, key: "show-seconds"))
        settingsStore.setBool(false, for: .init(tablePath: pomodoroTable, key: "native-mirror"))
    }

    private func resetDurationDefaults() {
        isApplyingConfigSnapshot = true
        focusDuration = 25
        shortBreakDuration = 5
        longBreakDuration = 15
        longBreakInterval = 4
        isApplyingConfigSnapshot = false

        pendingIntWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "focus-duration")))
        pendingIntWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "short-break-duration")))
        pendingIntWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "long-break-duration")))
        pendingIntWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "long-break-interval")))

        settingsStore.setInt(25, for: .init(tablePath: pomodoroTable, key: "focus-duration"))
        settingsStore.setInt(5, for: .init(tablePath: pomodoroTable, key: "short-break-duration"))
        settingsStore.setInt(15, for: .init(tablePath: pomodoroTable, key: "long-break-duration"))
        settingsStore.setInt(4, for: .init(tablePath: pomodoroTable, key: "long-break-interval"))
    }

    private func resetSoundDefaults() {
        isApplyingConfigSnapshot = true
        playSoundOnFocusEnd = true
        playSoundOnBreakEnd = true
        repeatBreakFinishedSoundUntilPopupOpened = false
        breakFinishedSoundRepeatInterval = 12
        isApplyingConfigSnapshot = false

        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "play-sound-on-focus-end")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "play-sound-on-break-end")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "repeat-break-finished-sound-until-popup-opened")))
        pendingIntWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: pomodoroTable, key: "break-finished-sound-repeat-interval-seconds")))

        settingsStore.setBool(true, for: .init(tablePath: pomodoroTable, key: "play-sound-on-focus-end"))
        settingsStore.setBool(true, for: .init(tablePath: pomodoroTable, key: "play-sound-on-break-end"))
        settingsStore.setBool(false, for: .init(tablePath: pomodoroTable, key: "repeat-break-finished-sound-until-popup-opened"))
        settingsStore.setInt(12, for: .init(tablePath: pomodoroTable, key: "break-finished-sound-repeat-interval-seconds"))
    }

    private func setStringValue(_ value: String, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingStringWrites[fieldIdentifier(field)] = value
        settingsStore.setString(value, for: field)
    }

    private func setBoolValue(_ value: Bool, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingBoolWrites[fieldIdentifier(field)] = value
        settingsStore.setBool(value, for: field)
    }

    private func setIntValue(_ value: Int, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingIntWrites[fieldIdentifier(field)] = value
        settingsStore.setInt(value, for: field)
    }

    private func resolvedStringValue(
        for field: SettingsFieldKey,
        incoming: String,
        current: String
    ) -> String {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingStringWrites[fieldID] {
            if incoming == pendingValue {
                pendingStringWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedBoolValue(
        for field: SettingsFieldKey,
        incoming: Bool,
        current: Bool
    ) -> Bool {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingBoolWrites[fieldID] {
            if incoming == pendingValue {
                pendingBoolWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedIntValue(
        for field: SettingsFieldKey,
        incoming: Int,
        current: Int
    ) -> Int {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingIntWrites[fieldID] {
            if incoming == pendingValue {
                pendingIntWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func fieldIdentifier(_ field: SettingsFieldKey) -> String {
        "\(field.tablePath).\(field.key)"
    }
}

private struct TickTickSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var tickTickManager = TickTickManager.shared
    @ObservedObject private var wallpaperManager = TickTickWallpaperManager.shared

    @State private var displayMode = TickTickDisplayMode.badge
    @State private var tintRotatingItemText = false
    @State private var rotatingItemChangeInterval = 900.0
    @State private var rotatingItemMaxWidth = 148.0
    @State private var includeTaskSource = true
    @State private var includeHabitSource = true
    @State private var includeOverdue = true
    @State private var includeToday = true
    @State private var includeImportant = true
    @State private var includeTomorrow = true
    @State private var includeNormal = true
    @State private var includeLowPriority = false
    @State private var includeMediumPriority = true
    @State private var includeHighPriority = true
    @State private var wallpaperEnabled = false
    @State private var wallpaperBaseURL = ""
    @State private var wallpaperProfile = "default"
    @State private var wallpaperStyle = TickTickWallpaperStyle.glow
    @State private var wallpaperToken = ""
    @State private var wallpaperIntervalSeconds = 300.0
    @State private var wallpaperApplyToAllScreens = true
    @State private var isApplyingConfigSnapshot = false
    @State private var pendingStringWrites: [String: String] = [:]
    @State private var pendingBoolWrites: [String: Bool] = [:]
    @State private var pendingIntWrites: [String: Int] = [:]
    @State private var pendingArrayWrites: [String: [String]] = [:]
    @State private var wallpaperBaseURLTask: Task<Void, Never>?
    @State private var wallpaperProfileTask: Task<Void, Never>?
    @State private var wallpaperTokenTask: Task<Void, Never>?

    private let tickTickTable = "widgets.default.ticktick"
    private let rotatingTasksTable = "widgets.default.ticktick.rotating-tasks"
    private let wallpaperTable = "widgets.default.ticktick.wallpaper"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.ticktick.header.title"),
                description: settingsLocalized("settings.ticktick.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.card.widget"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWidgetDefaults
            ) {
                SegmentedPickerRow(
                    title: settingsLocalized("settings.ticktick.field.display_mode.title"),
                    description: settingsLocalized("settings.ticktick.field.display_mode.description"),
                    selection: Binding(
                        get: { displayMode },
                        set: { newValue in
                            displayMode = newValue
                            setStringValue(
                                newValue.rawValue,
                                for: .init(tablePath: tickTickTable, key: "display-mode")
                            )
                        }
                    ),
                    options: TickTickDisplayMode.allCases,
                    titleForOption: { $0.title }
                )

                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.tint_rotating_text.title"),
                    description: settingsLocalized("settings.ticktick.field.tint_rotating_text.description"),
                    isOn: Binding(
                        get: { tintRotatingItemText },
                        set: { newValue in
                            tintRotatingItemText = newValue
                            setBoolValue(
                                newValue,
                                for: .init(tablePath: tickTickTable, key: "tint-rotating-item-text")
                            )
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)

                SliderSettingRow(
                    title: settingsLocalized("settings.ticktick.field.rotation_interval.title"),
                    description: settingsLocalized("settings.ticktick.field.rotation_interval.description"),
                    value: $rotatingItemChangeInterval,
                    range: 5...3600,
                    step: 5,
                    valueFormat: formatTickTickInterval
                )
                .disabled(displayMode != .rotatingItem)
                .onChange(of: rotatingItemChangeInterval) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(
                        Int(newValue.rounded()),
                        for: .init(tablePath: tickTickTable, key: "rotating-item-change-interval")
                    )
                }

                SliderSettingRow(
                    title: settingsLocalized("settings.ticktick.field.max_text_width.title"),
                    description: settingsLocalized("settings.ticktick.field.max_text_width.description"),
                    value: $rotatingItemMaxWidth,
                    range: 60...280,
                    step: 1,
                    valueFormat: { "\(Int($0)) px" }
                )
                .disabled(displayMode != .rotatingItem)
                .onChange(of: rotatingItemMaxWidth) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(
                        Int(newValue.rounded()),
                        for: .init(tablePath: tickTickTable, key: "rotating-item-max-width")
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.ticktick.card.rotation_sources"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetRotationSourceDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.show_tasks.title"),
                    description: settingsLocalized("settings.ticktick.field.show_tasks.description"),
                    isOn: Binding(
                        get: { includeTaskSource },
                        set: { newValue in
                            includeTaskSource = newValue
                            persistRotationSources()
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)

                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.show_habits.title"),
                    description: settingsLocalized("settings.ticktick.field.show_habits.description"),
                    isOn: Binding(
                        get: { includeHabitSource },
                        set: { newValue in
                            includeHabitSource = newValue
                            persistRotationSources()
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)
            }

            SettingsCardView(
                settingsLocalized("settings.ticktick.card.rotating_tasks"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetRotatingTaskDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.overdue.title"),
                    description: settingsLocalized("settings.ticktick.field.overdue.description"),
                    isOn: Binding(
                        get: { includeOverdue },
                        set: { newValue in
                            includeOverdue = newValue
                            persistRotatingTaskFilters()
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)

                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.today.title"),
                    description: settingsLocalized("settings.ticktick.field.today.description"),
                    isOn: Binding(
                        get: { includeToday },
                        set: { newValue in
                            includeToday = newValue
                            persistRotatingTaskFilters()
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)

                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.important.title"),
                    description: settingsLocalized("settings.ticktick.field.important.description"),
                    isOn: Binding(
                        get: { includeImportant },
                        set: { newValue in
                            includeImportant = newValue
                            persistRotatingTaskFilters()
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)

                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.tomorrow.title"),
                    description: settingsLocalized("settings.ticktick.field.tomorrow.description"),
                    isOn: Binding(
                        get: { includeTomorrow },
                        set: { newValue in
                            includeTomorrow = newValue
                            persistRotatingTaskFilters()
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)

                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.normal.title"),
                    description: settingsLocalized("settings.ticktick.field.normal.description"),
                    isOn: Binding(
                        get: { includeNormal },
                        set: { newValue in
                            includeNormal = newValue
                            persistRotatingTaskFilters()
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)

                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.low_priority.title"),
                    description: settingsLocalized("settings.ticktick.field.low_priority.description"),
                    isOn: Binding(
                        get: { includeLowPriority },
                        set: { newValue in
                            includeLowPriority = newValue
                            persistPriorityFilters()
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)

                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.medium_priority.title"),
                    description: settingsLocalized("settings.ticktick.field.medium_priority.description"),
                    isOn: Binding(
                        get: { includeMediumPriority },
                        set: { newValue in
                            includeMediumPriority = newValue
                            persistPriorityFilters()
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)

                ToggleRow(
                    title: settingsLocalized("settings.ticktick.field.high_priority.title"),
                    description: settingsLocalized("settings.ticktick.field.high_priority.description"),
                    isOn: Binding(
                        get: { includeHighPriority },
                        set: { newValue in
                            includeHighPriority = newValue
                            persistPriorityFilters()
                        }
                    )
                )
                .disabled(displayMode != .rotatingItem)
            }

            SettingsCardView(
                settingsLocalized("settings.card.connection"),
                badgeTitle: settingsLocalized("settings.badge.live")
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tickTickManager.isAuthenticated ? settingsLocalized("settings.status.connected") : settingsLocalized("settings.status.not_connected"))
                        .font(.headline)

                    Text(connectionDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCardView(
                "Habit Wallpaper",
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWallpaperDefaults
            ) {
                ToggleRow(
                    title: "Enable wallpaper sync",
                    description: "Off by default. When enabled, Barik asks your local wallpaper service for a fresh TickTick habits wallpaper.",
                    isOn: Binding(
                        get: { wallpaperEnabled },
                        set: { newValue in
                            wallpaperEnabled = newValue
                            setBoolValue(
                                newValue,
                                for: .init(tablePath: wallpaperTable, key: "enabled")
                            )
                        }
                    )
                )

                DebouncedTextSettingRow(
                    title: "Wallpaper service URL",
                    description: "Example: http://127.0.0.1:8765",
                    text: $wallpaperBaseURL
                )
                .disabled(!wallpaperEnabled)
                .onChange(of: wallpaperBaseURL) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleWallpaperStringWrite(
                        task: &wallpaperBaseURLTask,
                        field: .init(tablePath: wallpaperTable, key: "base-url"),
                        value: newValue
                    )
                }

                DebouncedTextSettingRow(
                    title: "Profile",
                    description: "Profile name from the wallpaper service config, for example default.",
                    text: $wallpaperProfile
                )
                .disabled(!wallpaperEnabled)
                .onChange(of: wallpaperProfile) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleWallpaperStringWrite(
                        task: &wallpaperProfileTask,
                        field: .init(tablePath: wallpaperTable, key: "profile"),
                        value: newValue
                    )
                }

                SegmentedPickerRow(
                    title: "Wallpaper style",
                    description: "Glow keeps the current soft wallpaper look. Terminal switches to a monochrome TUI-inspired monospace style.",
                    selection: Binding(
                        get: { wallpaperStyle },
                        set: { newValue in
                            wallpaperStyle = newValue
                            setStringValue(
                                newValue.rawValue,
                                for: .init(tablePath: wallpaperTable, key: "style")
                            )
                        }
                    ),
                    options: TickTickWallpaperStyle.allCases,
                    titleForOption: { $0.title }
                )
                .disabled(!wallpaperEnabled)

                DebouncedTextSettingRow(
                    title: "Access token",
                    description: "Optional shared secret for the wallpaper service. Barik sends it in the request header.",
                    text: $wallpaperToken
                )
                .disabled(!wallpaperEnabled)
                .onChange(of: wallpaperToken) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleWallpaperStringWrite(
                        task: &wallpaperTokenTask,
                        field: .init(tablePath: wallpaperTable, key: "token"),
                        value: newValue
                    )
                }

                SliderSettingRow(
                    title: "Refresh interval",
                    description: "How often Barik fetches and applies a new wallpaper.",
                    value: $wallpaperIntervalSeconds,
                    range: 60...3600,
                    step: 60,
                    valueFormat: formatTickTickInterval
                )
                .disabled(!wallpaperEnabled)
                .onChange(of: wallpaperIntervalSeconds) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(
                        Int(newValue.rounded()),
                        for: .init(tablePath: wallpaperTable, key: "interval-seconds")
                    )
                }

                ToggleRow(
                    title: "Apply to all screens",
                    description: "When enabled, the same generated wallpaper is applied to every connected display.",
                    isOn: Binding(
                        get: { wallpaperApplyToAllScreens },
                        set: { newValue in
                            wallpaperApplyToAllScreens = newValue
                            setBoolValue(
                                newValue,
                                for: .init(tablePath: wallpaperTable, key: "apply-to-all-screens")
                            )
                        }
                    )
                )

                HStack(spacing: 12) {
                    Button("Apply Now") {
                        wallpaperManager.refreshNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!wallpaperEnabled)

                    Button("Restore Previous Wallpapers") {
                        wallpaperEnabled = false
                        setBoolValue(false, for: .init(tablePath: wallpaperTable, key: "enabled"))
                        wallpaperManager.restorePreviousWallpapers()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!wallpaperManager.canRestorePreviousWallpapers)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(wallpaperManager.canRestorePreviousWallpapers ? "Previous wallpapers are saved and can be restored." : "No saved previous wallpapers yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let lastAppliedAt = wallpaperManager.lastAppliedAt {
                        Text("Last applied: \(lastAppliedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage = wallpaperManager.lastErrorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { config in
            settingsStore.refresh(with: config)
            loadFromConfig()
        }
        .onDisappear {
            wallpaperBaseURLTask?.cancel()
            wallpaperProfileTask?.cancel()
            wallpaperTokenTask?.cancel()
        }
    }

    private var connectionDescription: String {
        if tickTickManager.isAuthenticated {
            return settingsLocalized("settings.ticktick.status.connected")
        }

        return settingsLocalized("settings.ticktick.status.not_connected")
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let displayModeField = SettingsFieldKey(tablePath: tickTickTable, key: "display-mode")
        let tintField = SettingsFieldKey(tablePath: tickTickTable, key: "tint-rotating-item-text")
        let intervalField = SettingsFieldKey(tablePath: tickTickTable, key: "rotating-item-change-interval")
        let maxWidthField = SettingsFieldKey(tablePath: tickTickTable, key: "rotating-item-max-width")
        let sourcesField = SettingsFieldKey(tablePath: tickTickTable, key: "rotating-item-sources")
        let overdueField = SettingsFieldKey(tablePath: rotatingTasksTable, key: "overdue")
        let todayField = SettingsFieldKey(tablePath: rotatingTasksTable, key: "today")
        let importantField = SettingsFieldKey(tablePath: rotatingTasksTable, key: "important")
        let tomorrowField = SettingsFieldKey(tablePath: rotatingTasksTable, key: "tomorrow")
        let normalField = SettingsFieldKey(tablePath: rotatingTasksTable, key: "normal")
        let prioritiesField = SettingsFieldKey(tablePath: rotatingTasksTable, key: "priorities")
        let wallpaperEnabledField = SettingsFieldKey(tablePath: wallpaperTable, key: "enabled")
        let wallpaperBaseURLField = SettingsFieldKey(tablePath: wallpaperTable, key: "base-url")
        let wallpaperProfileField = SettingsFieldKey(tablePath: wallpaperTable, key: "profile")
        let wallpaperStyleField = SettingsFieldKey(tablePath: wallpaperTable, key: "style")
        let wallpaperTokenField = SettingsFieldKey(tablePath: wallpaperTable, key: "token")
        let wallpaperIntervalField = SettingsFieldKey(tablePath: wallpaperTable, key: "interval-seconds")
        let wallpaperAllScreensField = SettingsFieldKey(tablePath: wallpaperTable, key: "apply-to-all-screens")

        displayMode = TickTickDisplayMode(
            rawValue: resolvedStringValue(
                for: displayModeField,
                incoming: settingsStore.stringValue(displayModeField, fallback: TickTickDisplayMode.badge.rawValue),
                current: displayMode.rawValue
            )
        ) ?? .badge
        tintRotatingItemText = resolvedBoolValue(
            for: tintField,
            incoming: settingsStore.boolValue(tintField, fallback: false),
            current: tintRotatingItemText
        )
        rotatingItemChangeInterval = Double(
            resolvedIntValue(
                for: intervalField,
                incoming: settingsStore.intValue(intervalField, fallback: 900),
                current: Int(rotatingItemChangeInterval.rounded())
            )
        )
        rotatingItemMaxWidth = Double(
            resolvedIntValue(
                for: maxWidthField,
                incoming: settingsStore.intValue(maxWidthField, fallback: 148),
                current: Int(rotatingItemMaxWidth.rounded())
            )
        )

        let sources = resolvedStringArrayValue(
            for: sourcesField,
            incoming: settingsStore.configValueArray(sourcesField, fallback: TickTickRotationSource.allCases.map(\.rawValue)),
            current: selectedRotationSources()
        )
        includeTaskSource = sources.contains(TickTickRotationSource.tasks.rawValue)
        includeHabitSource = sources.contains(TickTickRotationSource.habits.rawValue)

        includeOverdue = resolvedBoolValue(
            for: overdueField,
            incoming: settingsStore.boolValue(overdueField, fallback: true),
            current: includeOverdue
        )
        includeToday = resolvedBoolValue(
            for: todayField,
            incoming: settingsStore.boolValue(todayField, fallback: true),
            current: includeToday
        )
        includeImportant = resolvedBoolValue(
            for: importantField,
            incoming: settingsStore.boolValue(importantField, fallback: true),
            current: includeImportant
        )
        includeTomorrow = resolvedBoolValue(
            for: tomorrowField,
            incoming: settingsStore.boolValue(tomorrowField, fallback: true),
            current: includeTomorrow
        )
        includeNormal = resolvedBoolValue(
            for: normalField,
            incoming: settingsStore.boolValue(normalField, fallback: true),
            current: includeNormal
        )

        let priorities = Set(
            resolvedStringArrayValue(
                for: prioritiesField,
                incoming: settingsStore.configValueArray(prioritiesField, fallback: ["medium", "high"]),
                current: selectedPriorityValues()
            )
        )
        includeLowPriority = priorities.contains("low")
        includeMediumPriority = priorities.contains("medium")
        includeHighPriority = priorities.contains("high")

        wallpaperEnabled = resolvedBoolValue(
            for: wallpaperEnabledField,
            incoming: settingsStore.boolValue(wallpaperEnabledField, fallback: false),
            current: wallpaperEnabled
        )
        wallpaperBaseURL = resolvedStringValue(
            for: wallpaperBaseURLField,
            incoming: settingsStore.stringValue(wallpaperBaseURLField, fallback: ""),
            current: wallpaperBaseURL
        )
        wallpaperProfile = resolvedStringValue(
            for: wallpaperProfileField,
            incoming: settingsStore.stringValue(wallpaperProfileField, fallback: "default"),
            current: wallpaperProfile
        )
        wallpaperStyle = TickTickWallpaperStyle(
            rawValue: resolvedStringValue(
                for: wallpaperStyleField,
                incoming: settingsStore.stringValue(wallpaperStyleField, fallback: TickTickWallpaperStyle.glow.rawValue),
                current: wallpaperStyle.rawValue
            )
        ) ?? .glow
        wallpaperToken = resolvedStringValue(
            for: wallpaperTokenField,
            incoming: settingsStore.stringValue(wallpaperTokenField, fallback: ""),
            current: wallpaperToken
        )
        wallpaperIntervalSeconds = Double(
            resolvedIntValue(
                for: wallpaperIntervalField,
                incoming: settingsStore.intValue(wallpaperIntervalField, fallback: 300),
                current: Int(wallpaperIntervalSeconds.rounded())
            )
        )
        wallpaperApplyToAllScreens = resolvedBoolValue(
            for: wallpaperAllScreensField,
            incoming: settingsStore.boolValue(wallpaperAllScreensField, fallback: true),
            current: wallpaperApplyToAllScreens
        )

        isApplyingConfigSnapshot = false
    }

    private func resetWidgetDefaults() {
        isApplyingConfigSnapshot = true
        displayMode = .badge
        tintRotatingItemText = false
        rotatingItemChangeInterval = 900
        rotatingItemMaxWidth = 148
        isApplyingConfigSnapshot = false

        pendingStringWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: tickTickTable, key: "display-mode")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: tickTickTable, key: "tint-rotating-item-text")))
        pendingIntWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: tickTickTable, key: "rotating-item-change-interval")))
        pendingIntWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: tickTickTable, key: "rotating-item-max-width")))

        settingsStore.setString("badge", for: .init(tablePath: tickTickTable, key: "display-mode"))
        settingsStore.setBool(false, for: .init(tablePath: tickTickTable, key: "tint-rotating-item-text"))
        settingsStore.setInt(900, for: .init(tablePath: tickTickTable, key: "rotating-item-change-interval"))
        settingsStore.setInt(148, for: .init(tablePath: tickTickTable, key: "rotating-item-max-width"))
    }

    private func resetRotationSourceDefaults() {
        isApplyingConfigSnapshot = true
        includeTaskSource = true
        includeHabitSource = true
        isApplyingConfigSnapshot = false

        let field = SettingsFieldKey(tablePath: tickTickTable, key: "rotating-item-sources")
        pendingArrayWrites.removeValue(forKey: fieldIdentifier(field))
        ConfigManager.shared.updateConfigStringArrayValue(
            tablePath: tickTickTable,
            key: "rotating-item-sources",
            newValue: TickTickRotationSource.allCases.map(\.rawValue)
        )
    }

    private func resetRotatingTaskDefaults() {
        isApplyingConfigSnapshot = true
        includeOverdue = true
        includeToday = true
        includeImportant = true
        includeTomorrow = true
        includeNormal = true
        includeLowPriority = false
        includeMediumPriority = true
        includeHighPriority = true
        isApplyingConfigSnapshot = false

        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: rotatingTasksTable, key: "overdue")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: rotatingTasksTable, key: "today")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: rotatingTasksTable, key: "important")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: rotatingTasksTable, key: "tomorrow")))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: rotatingTasksTable, key: "normal")))
        pendingArrayWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: rotatingTasksTable, key: "priorities")))

        settingsStore.setBool(true, for: .init(tablePath: rotatingTasksTable, key: "overdue"))
        settingsStore.setBool(true, for: .init(tablePath: rotatingTasksTable, key: "today"))
        settingsStore.setBool(true, for: .init(tablePath: rotatingTasksTable, key: "important"))
        settingsStore.setBool(true, for: .init(tablePath: rotatingTasksTable, key: "tomorrow"))
        settingsStore.setBool(true, for: .init(tablePath: rotatingTasksTable, key: "normal"))
        ConfigManager.shared.updateConfigStringArrayValue(
            tablePath: rotatingTasksTable,
            key: "priorities",
            newValue: ["medium", "high"]
        )
    }

    private func resetWallpaperDefaults() {
        wallpaperBaseURLTask?.cancel()
        wallpaperProfileTask?.cancel()
        wallpaperTokenTask?.cancel()

        let enabledField = SettingsFieldKey(tablePath: wallpaperTable, key: "enabled")
        let baseURLField = SettingsFieldKey(tablePath: wallpaperTable, key: "base-url")
        let profileField = SettingsFieldKey(tablePath: wallpaperTable, key: "profile")
        let styleField = SettingsFieldKey(tablePath: wallpaperTable, key: "style")
        let tokenField = SettingsFieldKey(tablePath: wallpaperTable, key: "token")
        let intervalField = SettingsFieldKey(tablePath: wallpaperTable, key: "interval-seconds")
        let allScreensField = SettingsFieldKey(tablePath: wallpaperTable, key: "apply-to-all-screens")

        isApplyingConfigSnapshot = true
        wallpaperEnabled = false
        wallpaperBaseURL = ""
        wallpaperProfile = "default"
        wallpaperStyle = .glow
        wallpaperToken = ""
        wallpaperIntervalSeconds = 300
        wallpaperApplyToAllScreens = true
        isApplyingConfigSnapshot = false

        pendingBoolWrites.removeValue(forKey: fieldIdentifier(enabledField))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(baseURLField))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(profileField))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(styleField))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(tokenField))
        pendingIntWrites.removeValue(forKey: fieldIdentifier(intervalField))
        pendingBoolWrites.removeValue(forKey: fieldIdentifier(allScreensField))

        settingsStore.setBool(false, for: enabledField)
        ConfigManager.shared.removeConfigValue(tablePath: wallpaperTable, key: "base-url")
        ConfigManager.shared.removeConfigValue(tablePath: wallpaperTable, key: "profile")
        ConfigManager.shared.removeConfigValue(tablePath: wallpaperTable, key: "style")
        ConfigManager.shared.removeConfigValue(tablePath: wallpaperTable, key: "token")
        ConfigManager.shared.removeConfigValue(tablePath: wallpaperTable, key: "interval-seconds")
        ConfigManager.shared.removeConfigValue(tablePath: wallpaperTable, key: "apply-to-all-screens")
    }

    private func persistRotationSources() {
        guard !isApplyingConfigSnapshot else { return }
        let field = SettingsFieldKey(tablePath: tickTickTable, key: "rotating-item-sources")
        let newSources = selectedRotationSources()
        pendingArrayWrites[fieldIdentifier(field)] = newSources
        ConfigManager.shared.updateConfigStringArrayValue(
            tablePath: tickTickTable,
            key: "rotating-item-sources",
            newValue: newSources
        )
    }

    private func persistRotatingTaskFilters() {
        guard !isApplyingConfigSnapshot else { return }
        setBoolValue(includeOverdue, for: .init(tablePath: rotatingTasksTable, key: "overdue"))
        setBoolValue(includeToday, for: .init(tablePath: rotatingTasksTable, key: "today"))
        setBoolValue(includeImportant, for: .init(tablePath: rotatingTasksTable, key: "important"))
        setBoolValue(includeTomorrow, for: .init(tablePath: rotatingTasksTable, key: "tomorrow"))
        setBoolValue(includeNormal, for: .init(tablePath: rotatingTasksTable, key: "normal"))
    }

    private func persistPriorityFilters() {
        guard !isApplyingConfigSnapshot else { return }
        let field = SettingsFieldKey(tablePath: rotatingTasksTable, key: "priorities")
        let newPriorities = selectedPriorityValues()
        pendingArrayWrites[fieldIdentifier(field)] = newPriorities
        ConfigManager.shared.updateConfigStringArrayValue(
            tablePath: rotatingTasksTable,
            key: "priorities",
            newValue: newPriorities
        )
    }

    private func selectedRotationSources() -> [String] {
        var values: [String] = []
        if includeTaskSource { values.append(TickTickRotationSource.tasks.rawValue) }
        if includeHabitSource { values.append(TickTickRotationSource.habits.rawValue) }
        return values.isEmpty ? [TickTickRotationSource.tasks.rawValue] : values
    }

    private func selectedPriorityValues() -> [String] {
        var values: [String] = []
        if includeLowPriority { values.append("low") }
        if includeMediumPriority { values.append("medium") }
        if includeHighPriority { values.append("high") }
        return values.isEmpty ? ["medium", "high"] : values
    }

    private func formatTickTickInterval(_ value: Double) -> String {
        let seconds = Int(value.rounded())
        if seconds < 60 {
            return "\(seconds) sec"
        }

        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes) min" : "\(minutes)m \(remainder)s"
    }

    private func scheduleWallpaperStringWrite(
        task: inout Task<Void, Never>?,
        field: SettingsFieldKey,
        value: String
    ) {
        task?.cancel()
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            if trimmedValue.isEmpty {
                pendingStringWrites.removeValue(forKey: fieldIdentifier(field))
                ConfigManager.shared.removeConfigValue(tablePath: field.tablePath, key: field.key)
            } else {
                setStringValue(trimmedValue, for: field)
            }
        }
    }

    private func setStringValue(_ value: String, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingStringWrites[fieldIdentifier(field)] = value
        settingsStore.setString(value, for: field)
    }

    private func setBoolValue(_ value: Bool, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingBoolWrites[fieldIdentifier(field)] = value
        settingsStore.setBool(value, for: field)
    }

    private func setIntValue(_ value: Int, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingIntWrites[fieldIdentifier(field)] = value
        settingsStore.setInt(value, for: field)
    }

    private func resolvedStringValue(
        for field: SettingsFieldKey,
        incoming: String,
        current: String
    ) -> String {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingStringWrites[fieldID] {
            if incoming == pendingValue {
                pendingStringWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedBoolValue(
        for field: SettingsFieldKey,
        incoming: Bool,
        current: Bool
    ) -> Bool {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingBoolWrites[fieldID] {
            if incoming == pendingValue {
                pendingBoolWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedIntValue(
        for field: SettingsFieldKey,
        incoming: Int,
        current: Int
    ) -> Int {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingIntWrites[fieldID] {
            if incoming == pendingValue {
                pendingIntWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedStringArrayValue(
        for field: SettingsFieldKey,
        incoming: [String],
        current: [String]
    ) -> [String] {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingArrayWrites[fieldID] {
            if incoming == pendingValue {
                pendingArrayWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func fieldIdentifier(_ field: SettingsFieldKey) -> String {
        "\(field.tablePath).\(field.key)"
    }
}

private struct ShortcutsSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var shortcutsManager = ShortcutsManager.shared

    @State private var includeFoldersText = ""
    @State private var excludeFoldersText = ""
    @State private var excludeShortcutsText = ""
    @State private var isApplyingConfigSnapshot = false
    @State private var pendingArrayWrites: [String: [String]] = [:]

    @State private var includeFoldersTask: Task<Void, Never>?
    @State private var excludeFoldersTask: Task<Void, Never>?
    @State private var excludeShortcutsTask: Task<Void, Never>?

    private let shortcutsTable = "widgets.default.shortcuts"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.shortcuts.header.title"),
                description: settingsLocalized("settings.shortcuts.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.shortcuts.card.folders"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetFolderDefaults
            ) {
                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.shortcuts.field.include_folders.title"),
                    description: settingsLocalized("settings.shortcuts.field.include_folders.description"),
                    text: $includeFoldersText
                )
                .onChange(of: includeFoldersText) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleArrayWrite(
                        task: &includeFoldersTask,
                        field: .init(tablePath: shortcutsTable, key: "include-folders"),
                        rawValue: newValue
                    )
                }

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.shortcuts.field.exclude_folders.title"),
                    description: settingsLocalized("settings.shortcuts.field.exclude_folders.description"),
                    text: $excludeFoldersText
                )
                .onChange(of: excludeFoldersText) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleArrayWrite(
                        task: &excludeFoldersTask,
                        field: .init(tablePath: shortcutsTable, key: "exclude-folders"),
                        rawValue: newValue
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.shortcuts.card.shortcut_filters"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetShortcutDefaults
            ) {
                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.shortcuts.field.exclude_shortcuts.title"),
                    description: settingsLocalized("settings.shortcuts.field.exclude_shortcuts.description"),
                    text: $excludeShortcutsText
                )
                .onChange(of: excludeShortcutsText) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleArrayWrite(
                        task: &excludeShortcutsTask,
                        field: .init(tablePath: shortcutsTable, key: "exclude-shortcuts"),
                        rawValue: newValue
                    )
                }
            }

            SettingsCardView(settingsLocalized("settings.card.status")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        shortcutsManager.sections.isEmpty
                        ? settingsLocalized("settings.shortcuts.status.waiting")
                        : String(
                            format: settingsLocalized("settings.shortcuts.status.loaded_groups"),
                            locale: .autoupdatingCurrent,
                            shortcutsManager.sections.count
                        )
                    )
                        .font(.headline)

                    Text(statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { config in
            settingsStore.refresh(with: config)
            loadFromConfig()
        }
        .onDisappear {
            includeFoldersTask?.cancel()
            excludeFoldersTask?.cancel()
            excludeShortcutsTask?.cancel()
        }
    }

    private var statusDescription: String {
        if let errorMessage = shortcutsManager.errorMessage, shortcutsManager.sections.isEmpty {
            return errorMessage
        }

        return String(
            format: settingsLocalized("settings.shortcuts.status.description"),
            locale: .autoupdatingCurrent,
            shortcutsManager.sections.reduce(0) { $0 + $1.shortcuts.count }
        )
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let includeField = SettingsFieldKey(tablePath: shortcutsTable, key: "include-folders")
        let excludeFoldersField = SettingsFieldKey(tablePath: shortcutsTable, key: "exclude-folders")
        let excludeShortcutsField = SettingsFieldKey(tablePath: shortcutsTable, key: "exclude-shortcuts")

        includeFoldersText = resolvedArrayTextValue(
            for: includeField,
            incoming: settingsStore.configValueArray(includeField),
            current: includeFoldersText
        )
        excludeFoldersText = resolvedArrayTextValue(
            for: excludeFoldersField,
            incoming: settingsStore.configValueArray(excludeFoldersField),
            current: excludeFoldersText
        )
        excludeShortcutsText = resolvedArrayTextValue(
            for: excludeShortcutsField,
            incoming: settingsStore.configValueArray(excludeShortcutsField),
            current: excludeShortcutsText
        )

        isApplyingConfigSnapshot = false
    }

    private func resetFolderDefaults() {
        includeFoldersTask?.cancel()
        excludeFoldersTask?.cancel()

        isApplyingConfigSnapshot = true
        includeFoldersText = ""
        excludeFoldersText = ""
        isApplyingConfigSnapshot = false

        pendingArrayWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: shortcutsTable, key: "include-folders")))
        pendingArrayWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: shortcutsTable, key: "exclude-folders")))

        ConfigManager.shared.removeConfigValue(tablePath: shortcutsTable, key: "include-folders")
        ConfigManager.shared.removeConfigValue(tablePath: shortcutsTable, key: "exclude-folders")
    }

    private func resetShortcutDefaults() {
        excludeShortcutsTask?.cancel()

        isApplyingConfigSnapshot = true
        excludeShortcutsText = ""
        isApplyingConfigSnapshot = false

        pendingArrayWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: shortcutsTable, key: "exclude-shortcuts")))
        ConfigManager.shared.removeConfigValue(tablePath: shortcutsTable, key: "exclude-shortcuts")
    }

    private func scheduleArrayWrite(
        task: inout Task<Void, Never>?,
        field: SettingsFieldKey,
        rawValue: String
    ) {
        let parsedValues = parseCommaSeparatedList(rawValue)
        let currentValue = settingsStore.configValueArray(field)
        guard parsedValues != currentValue else {
            task?.cancel()
            return
        }

        task?.cancel()
        pendingArrayWrites[fieldIdentifier(field)] = parsedValues
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            if parsedValues.isEmpty {
                ConfigManager.shared.removeConfigValue(tablePath: field.tablePath, key: field.key)
            } else {
                ConfigManager.shared.updateConfigStringArrayValue(
                    tablePath: field.tablePath,
                    key: field.key,
                    newValue: parsedValues
                )
            }
        }
    }

    private func parseCommaSeparatedList(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func resolvedArrayTextValue(
        for field: SettingsFieldKey,
        incoming: [String],
        current: String
    ) -> String {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingArrayWrites[fieldID] {
            if incoming == pendingValue {
                pendingArrayWrites.removeValue(forKey: fieldID)
                return incoming.joined(separator: ", ")
            }
            return current
        }
        return incoming.joined(separator: ", ")
    }

    private func fieldIdentifier(_ field: SettingsFieldKey) -> String {
        "\(field.tablePath).\(field.key)"
    }
}

private protocol SystemMonitorPopupDetailOption: CaseIterable, Hashable, RawRepresentable where RawValue == String {
    var title: String { get }
}

private enum SystemMonitorPopupCPUDetailOption: String, CaseIterable, SystemMonitorPopupDetailOption {
    case usage
    case user
    case system
    case idle
    case temperature
    case cores
    case loadAverage = "load-average"

    var title: String {
        switch self {
        case .usage: settingsLocalized("settings.system_monitor.option.usage")
        case .user: settingsLocalized("settings.system_monitor.option.user")
        case .system: settingsLocalized("settings.system_monitor.option.system")
        case .idle: settingsLocalized("settings.system_monitor.option.idle")
        case .temperature: settingsLocalized("settings.system_monitor.option.temperature")
        case .cores: settingsLocalized("settings.system_monitor.option.cores")
        case .loadAverage: settingsLocalized("settings.system_monitor.option.load_avg")
        }
    }
}

private enum SystemMonitorPopupTemperatureDetailOption: String, CaseIterable, SystemMonitorPopupDetailOption {
    case cpu
    case gpu

    var title: String { rawValue.uppercased() }
}

private enum SystemMonitorPopupRAMDetailOption: String, CaseIterable, SystemMonitorPopupDetailOption {
    case used
    case app
    case active
    case inactive
    case wired
    case compressed
    case cache
    case free
    case swap
    case pressure
    case total

    var title: String {
        switch self {
        case .used: settingsLocalized("settings.system_monitor.option.used")
        case .app: settingsLocalized("settings.system_monitor.option.app")
        case .active: settingsLocalized("settings.system_monitor.option.active")
        case .inactive: settingsLocalized("settings.system_monitor.option.inactive")
        case .wired: settingsLocalized("settings.system_monitor.option.wired")
        case .compressed: settingsLocalized("settings.system_monitor.option.compressed")
        case .cache: settingsLocalized("settings.system_monitor.option.cache")
        case .free: settingsLocalized("settings.system_monitor.option.free")
        case .swap: settingsLocalized("settings.system_monitor.option.swap")
        case .pressure: settingsLocalized("settings.system_monitor.option.pressure")
        case .total: settingsLocalized("settings.system_monitor.option.total")
        }
    }
}

private enum SystemMonitorPopupDiskDetailOption: String, CaseIterable, SystemMonitorPopupDetailOption {
    case volume
    case used
    case free
    case total

    var title: String {
        switch self {
        case .volume: settingsLocalized("settings.system_monitor.option.volume")
        case .used: settingsLocalized("settings.system_monitor.option.used")
        case .free: settingsLocalized("settings.system_monitor.option.free")
        case .total: settingsLocalized("settings.system_monitor.option.total")
        }
    }
}

private enum SystemMonitorPopupGPUDetailOption: String, CaseIterable, SystemMonitorPopupDetailOption {
    case utilization
    case temperature

    var title: String {
        switch self {
        case .utilization: settingsLocalized("settings.system_monitor.option.utilization")
        case .temperature: settingsLocalized("settings.system_monitor.option.temperature")
        }
    }
}

private enum SystemMonitorPopupNetworkDetailOption: String, CaseIterable, SystemMonitorPopupDetailOption {
    case interfaceName = "interface"
    case status
    case download
    case upload
    case totalDownloaded = "total-downloaded"
    case totalUploaded = "total-uploaded"

    var title: String {
        switch self {
        case .interfaceName: settingsLocalized("settings.system_monitor.option.interface")
        case .status: settingsLocalized("settings.card.status")
        case .download: settingsLocalized("settings.system_monitor.option.download")
        case .upload: settingsLocalized("settings.system_monitor.option.upload")
        case .totalDownloaded: settingsLocalized("settings.system_monitor.option.downloaded")
        case .totalUploaded: settingsLocalized("settings.system_monitor.option.uploaded")
        }
    }
}

private struct SystemMonitorMetricRow: View {
    let metric: SystemMonitorMetric
    let description: String
    let isEnabled: Bool
    let isDragging: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.title)
                    .font(.subheadline.weight(.semibold))

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Toggle(
                "",
                isOn: Binding(get: { isEnabled }, set: onToggle)
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isDragging ? 0.07 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(isDragging ? 0.985 : 1)
        .opacity(isDragging ? 0.72 : (isEnabled ? 1 : 0.5))
    }
}

private struct SystemMonitorSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared

    @State private var showIcon = false
    @State private var useMetricIcons = false
    @State private var showUsageBars = true
    @State private var networkDisplayMode = SystemMonitorNetworkDisplayMode.single
    @State private var metricsPerColumn = 2.0
    @State private var layout = SystemMonitorLayoutSelection.rows
    @State private var dividers = SystemMonitorDividerSelection.none
    @State private var cpuWarningLevel = 70.0
    @State private var cpuCriticalLevel = 90.0
    @State private var temperatureWarningLevel = 80.0
    @State private var temperatureCriticalLevel = 95.0
    @State private var ramWarningLevel = 70.0
    @State private var ramCriticalLevel = 90.0
    @State private var diskWarningLevel = 80.0
    @State private var diskCriticalLevel = 90.0
    @State private var gpuWarningLevel = 70.0
    @State private var gpuCriticalLevel = 90.0
    @State private var metricSelections: [String: Bool] = [:]
    @State private var metricsOrder: [String] = []
    @State private var popupMetricSelections: [String: Bool] = [:]
    @State private var popupCPUDetailSelections: [String: Bool] = [:]
    @State private var popupTemperatureDetailSelections: [String: Bool] = [:]
    @State private var popupRAMDetailSelections: [String: Bool] = [:]
    @State private var popupDiskDetailSelections: [String: Bool] = [:]
    @State private var popupGPUDetailSelections: [String: Bool] = [:]
    @State private var popupNetworkDetailSelections: [String: Bool] = [:]
    @State private var isApplyingConfigSnapshot = false
    @State private var pendingStringWrites: [String: String] = [:]
    @State private var pendingBoolWrites: [String: Bool] = [:]
    @State private var pendingIntWrites: [String: Int] = [:]
    @State private var pendingArrayWrites: [String: [String]] = [:]

    private let systemMonitorTable = "widgets.default.system-monitor"
    private let systemMonitorPopupTable = "widgets.default.system-monitor.popup"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.system_monitor.header.title"),
                description: settingsLocalized("settings.system_monitor.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.card.widget"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWidgetDefaults
            ) {
                ToggleRow(
                    title: settingsLocalized("settings.system_monitor.field.show_leading_icon.title"),
                    description: settingsLocalized("settings.system_monitor.field.show_leading_icon.description"),
                    isOn: Binding(
                        get: { showIcon },
                        set: { newValue in
                            showIcon = newValue
                            setBoolValue(newValue, for: .init(tablePath: systemMonitorTable, key: "show-icon"))
                        }
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.system_monitor.field.use_metric_icons.title"),
                    description: settingsLocalized("settings.system_monitor.field.use_metric_icons.description"),
                    isOn: Binding(
                        get: { useMetricIcons },
                        set: { newValue in
                            useMetricIcons = newValue
                            setBoolValue(newValue, for: .init(tablePath: systemMonitorTable, key: "use-metric-icons"))
                        }
                    )
                )

                ToggleRow(
                    title: settingsLocalized("settings.system_monitor.field.show_usage_bars.title"),
                    description: settingsLocalized("settings.system_monitor.field.show_usage_bars.description"),
                    isOn: Binding(
                        get: { showUsageBars },
                        set: { newValue in
                            showUsageBars = newValue
                            setBoolValue(newValue, for: .init(tablePath: systemMonitorTable, key: "show-usage-bars"))
                        }
                    )
                )

                SegmentedPickerRow(
                    title: settingsLocalized("settings.system_monitor.field.layout.title"),
                    description: settingsLocalized("settings.system_monitor.field.layout.description"),
                    selection: Binding(
                        get: { layout },
                        set: { newValue in
                            layout = newValue
                            setStringValue(newValue.rawValue, for: .init(tablePath: systemMonitorTable, key: "layout"))
                        }
                    ),
                    options: SystemMonitorLayoutSelection.allCases,
                    titleForOption: { $0.title }
                )

                SegmentedPickerRow(
                    title: settingsLocalized("settings.system_monitor.field.dividers.title"),
                    description: settingsLocalized("settings.system_monitor.field.dividers.description"),
                    selection: Binding(
                        get: { dividers },
                        set: { newValue in
                            dividers = newValue
                            setStringValue(newValue.rawValue, for: .init(tablePath: systemMonitorTable, key: "dividers"))
                        }
                    ),
                    options: SystemMonitorDividerSelection.allCases,
                    titleForOption: { $0.title }
                )

                SegmentedPickerRow(
                    title: settingsLocalized("settings.system_monitor.field.network_rows.title"),
                    description: settingsLocalized("settings.system_monitor.field.network_rows.description"),
                    selection: Binding(
                        get: { networkDisplayMode },
                        set: { newValue in
                            networkDisplayMode = newValue
                            setStringValue(newValue.rawValue, for: .init(tablePath: systemMonitorTable, key: "network-display-mode"))
                        }
                    ),
                    options: SystemMonitorNetworkDisplayMode.allCases,
                    titleForOption: { $0.title }
                )

                SliderSettingRow(
                    title: settingsLocalized("settings.system_monitor.field.metrics_per_column.title"),
                    description: settingsLocalized("settings.system_monitor.field.metrics_per_column.description"),
                    value: $metricsPerColumn,
                    range: 1...4,
                    step: 1,
                    valueFormat: { "\(Int($0))" }
                )
                .onChange(of: metricsPerColumn) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    setIntValue(Int(newValue.rounded()), for: .init(tablePath: systemMonitorTable, key: "metrics-per-column"))
                }
            }

            SettingsCardView(
                settingsLocalized("settings.system_monitor.card.visible_metrics"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetMetricDefaults
            ) {
                ReorderableListEditor(
                    groupID: "system-monitor-metrics",
                    items: metricsOrder.compactMap(SystemMonitorMetric.init(rawValue:)),
                    onMove: moveMetric
                ) { metric, _, isDragging in
                    SystemMonitorMetricRow(
                        metric: metric,
                        description: systemMonitorMetricDescription(for: metric),
                        isEnabled: metricSelections[metric.rawValue] ?? true,
                        isDragging: isDragging,
                        onToggle: { newValue in
                            metricSelections[metric.rawValue] = newValue
                            persistMetricSelection()
                        }
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.system_monitor.card.thresholds"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetThresholdDefaults
            ) {
                thresholdRow(title: settingsLocalized("settings.system_monitor.threshold.cpu_warning"), value: $cpuWarningLevel, key: "cpu-warning-level")
                thresholdRow(title: settingsLocalized("settings.system_monitor.threshold.cpu_critical"), value: $cpuCriticalLevel, key: "cpu-critical-level")
                thresholdRow(title: settingsLocalized("settings.system_monitor.threshold.temperature_warning"), value: $temperatureWarningLevel, key: "temperature-warning-level", suffix: "°C", range: 40...110)
                thresholdRow(title: settingsLocalized("settings.system_monitor.threshold.temperature_critical"), value: $temperatureCriticalLevel, key: "temperature-critical-level", suffix: "°C", range: 50...120)
                thresholdRow(title: settingsLocalized("settings.system_monitor.threshold.ram_warning"), value: $ramWarningLevel, key: "ram-warning-level")
                thresholdRow(title: settingsLocalized("settings.system_monitor.threshold.ram_critical"), value: $ramCriticalLevel, key: "ram-critical-level")
                thresholdRow(title: settingsLocalized("settings.system_monitor.threshold.disk_warning"), value: $diskWarningLevel, key: "disk-warning-level")
                thresholdRow(title: settingsLocalized("settings.system_monitor.threshold.disk_critical"), value: $diskCriticalLevel, key: "disk-critical-level")
                thresholdRow(title: settingsLocalized("settings.system_monitor.threshold.gpu_warning"), value: $gpuWarningLevel, key: "gpu-warning-level")
                thresholdRow(title: settingsLocalized("settings.system_monitor.threshold.gpu_critical"), value: $gpuCriticalLevel, key: "gpu-critical-level")
            }

            SettingsCardView(
                settingsLocalized("settings.system_monitor.card.popup_content"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetPopupDefaults
            ) {
                ForEach(SystemMonitorMetric.allCases, id: \.rawValue) { metric in
                    ToggleRow(
                        title: metric.title,
                        description: String(
                            format: settingsLocalized("settings.system_monitor.popup_content.metric_description"),
                            locale: .autoupdatingCurrent,
                            metric.title.lowercased()
                        ),
                        isOn: Binding(
                            get: { popupMetricSelections[metric.rawValue] ?? true },
                            set: { newValue in
                                updatePopupSelection(
                                    dictionary: &popupMetricSelections,
                                    key: metric.rawValue,
                                    newValue: newValue,
                                    minimumSelectedCount: 1
                                ) {
                                    persistPopupMetricSelection()
                                }
                            }
                        )
                    )
                }
            }

            SettingsCardView(
                settingsLocalized("settings.system_monitor.card.popup_details"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetPopupDefaults
            ) {
                popupDetailSection(
                    title: settingsLocalized("settings.system_monitor.popup_details.cpu_fields.title"),
                    description: settingsLocalized("settings.system_monitor.popup_details.cpu_fields.description"),
                    options: SystemMonitorPopupCPUDetailOption.allCases,
                    selections: $popupCPUDetailSelections,
                    fieldKey: "cpu-details",
                    defaults: [.usage, .temperature, .loadAverage, .cores]
                )

                popupDetailSection(
                    title: settingsLocalized("settings.system_monitor.popup_details.temperature_fields.title"),
                    description: settingsLocalized("settings.system_monitor.popup_details.temperature_fields.description"),
                    options: SystemMonitorPopupTemperatureDetailOption.allCases,
                    selections: $popupTemperatureDetailSelections,
                    fieldKey: "temperature-details",
                    defaults: [.cpu, .gpu]
                )

                popupDetailSection(
                    title: settingsLocalized("settings.system_monitor.popup_details.memory_fields.title"),
                    description: settingsLocalized("settings.system_monitor.popup_details.memory_fields.description"),
                    options: SystemMonitorPopupRAMDetailOption.allCases,
                    selections: $popupRAMDetailSelections,
                    fieldKey: "ram-details",
                    defaults: [.used, .app, .free, .pressure]
                )

                popupDetailSection(
                    title: settingsLocalized("settings.system_monitor.popup_details.disk_fields.title"),
                    description: settingsLocalized("settings.system_monitor.popup_details.disk_fields.description"),
                    options: SystemMonitorPopupDiskDetailOption.allCases,
                    selections: $popupDiskDetailSelections,
                    fieldKey: "disk-details",
                    defaults: [.used, .free, .total]
                )

                popupDetailSection(
                    title: settingsLocalized("settings.system_monitor.popup_details.gpu_fields.title"),
                    description: settingsLocalized("settings.system_monitor.popup_details.gpu_fields.description"),
                    options: SystemMonitorPopupGPUDetailOption.allCases,
                    selections: $popupGPUDetailSelections,
                    fieldKey: "gpu-details",
                    defaults: [.utilization, .temperature]
                )

                popupDetailSection(
                    title: settingsLocalized("settings.system_monitor.popup_details.network_fields.title"),
                    description: settingsLocalized("settings.system_monitor.popup_details.network_fields.description"),
                    options: SystemMonitorPopupNetworkDetailOption.allCases,
                    selections: $popupNetworkDetailSelections,
                    fieldKey: "network-details",
                    defaults: [.status, .download, .upload, .interfaceName]
                )
            }

            SettingsCardView(settingsLocalized("settings.card.status")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        String(
                            format: settingsLocalized("settings.system_monitor.status.summary"),
                            locale: .autoupdatingCurrent,
                            Int(systemMonitor.cpuLoad),
                            Int(systemMonitor.ramUsage),
                            Int(systemMonitor.diskUsage)
                        )
                    )
                        .font(.headline)

                    Text(
                        systemMonitor.activeNetworkInterface.isEmpty
                        ? settingsLocalized("settings.system_monitor.status.monitoring")
                        : String(
                            format: settingsLocalized("settings.system_monitor.status.active_interface"),
                            locale: .autoupdatingCurrent,
                            systemMonitor.activeNetworkInterface
                        )
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { config in
            settingsStore.refresh(with: config)
            loadFromConfig()
        }
    }

    @ViewBuilder
    private func thresholdRow(
        title: String,
        value: Binding<Double>,
        key: String,
        suffix: String = "%",
        range: ClosedRange<Double> = 0...100
    ) -> some View {
        SliderSettingRow(
            title: title,
            description: settingsLocalized("settings.system_monitor.threshold.description"),
            value: value,
            range: range,
            step: 1,
            valueFormat: { "\(Int($0))\(suffix)" }
        )
        .onChange(of: value.wrappedValue) { _, newValue in
            guard !isApplyingConfigSnapshot else { return }
            setIntValue(Int(newValue.rounded()), for: .init(tablePath: systemMonitorTable, key: key))
        }
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let config = configManager.globalWidgetConfig(for: "default.system-monitor")
        showIcon = resolvedBoolValue(for: .init(tablePath: systemMonitorTable, key: "show-icon"), incoming: config["show-icon"]?.boolValue ?? false, current: showIcon)
        useMetricIcons = resolvedBoolValue(for: .init(tablePath: systemMonitorTable, key: "use-metric-icons"), incoming: config["use-metric-icons"]?.boolValue ?? false, current: useMetricIcons)
        showUsageBars = resolvedBoolValue(for: .init(tablePath: systemMonitorTable, key: "show-usage-bars"), incoming: config["show-usage-bars"]?.boolValue ?? true, current: showUsageBars)
        networkDisplayMode = SystemMonitorNetworkDisplayMode(
            rawValue: resolvedStringValue(for: .init(tablePath: systemMonitorTable, key: "network-display-mode"), incoming: config["network-display-mode"]?.stringValue ?? SystemMonitorNetworkDisplayMode.single.rawValue, current: networkDisplayMode.rawValue)
        ) ?? .single
        metricsPerColumn = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "metrics-per-column"), incoming: config["metrics-per-column"]?.intValue ?? 2, current: Int(metricsPerColumn.rounded())))
        layout = SystemMonitorLayoutSelection(
            rawValue: resolvedStringValue(for: .init(tablePath: systemMonitorTable, key: "layout"), incoming: config["layout"]?.stringValue ?? SystemMonitorLayoutSelection.rows.rawValue, current: layout.rawValue)
        ) ?? .rows
        dividers = SystemMonitorDividerSelection(
            rawValue: resolvedStringValue(for: .init(tablePath: systemMonitorTable, key: "dividers"), incoming: config["dividers"]?.stringValue ?? SystemMonitorDividerSelection.none.rawValue, current: dividers.rawValue)
        ) ?? .none

        let popupConfig = config["popup"]?.dictionaryValue ?? [:]

        cpuWarningLevel = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "cpu-warning-level"), incoming: config["cpu-warning-level"]?.intValue ?? 70, current: Int(cpuWarningLevel.rounded())))
        cpuCriticalLevel = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "cpu-critical-level"), incoming: config["cpu-critical-level"]?.intValue ?? 90, current: Int(cpuCriticalLevel.rounded())))
        temperatureWarningLevel = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "temperature-warning-level"), incoming: config["temperature-warning-level"]?.intValue ?? 80, current: Int(temperatureWarningLevel.rounded())))
        temperatureCriticalLevel = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "temperature-critical-level"), incoming: config["temperature-critical-level"]?.intValue ?? 95, current: Int(temperatureCriticalLevel.rounded())))
        ramWarningLevel = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "ram-warning-level"), incoming: config["ram-warning-level"]?.intValue ?? 70, current: Int(ramWarningLevel.rounded())))
        ramCriticalLevel = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "ram-critical-level"), incoming: config["ram-critical-level"]?.intValue ?? 90, current: Int(ramCriticalLevel.rounded())))
        diskWarningLevel = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "disk-warning-level"), incoming: config["disk-warning-level"]?.intValue ?? 80, current: Int(diskWarningLevel.rounded())))
        diskCriticalLevel = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "disk-critical-level"), incoming: config["disk-critical-level"]?.intValue ?? 90, current: Int(diskCriticalLevel.rounded())))
        gpuWarningLevel = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "gpu-warning-level"), incoming: config["gpu-warning-level"]?.intValue ?? 70, current: Int(gpuWarningLevel.rounded())))
        gpuCriticalLevel = Double(resolvedIntValue(for: .init(tablePath: systemMonitorTable, key: "gpu-critical-level"), incoming: config["gpu-critical-level"]?.intValue ?? 90, current: Int(gpuCriticalLevel.rounded())))

        let metricsField = SettingsFieldKey(tablePath: systemMonitorTable, key: "metrics")
        let resolvedMetrics = resolvedStringArrayValue(
            for: metricsField,
            incoming: config["metrics"]?.stringArrayValue ?? SystemMonitorMetric.allCases.map(\.rawValue),
            current: selectedSystemMonitorMetrics()
        )
        metricsOrder = mergedMetricsOrder(fromVisible: resolvedMetrics)
        metricSelections = Dictionary(uniqueKeysWithValues: SystemMonitorMetric.allCases.map { metric in
            (metric.rawValue, resolvedMetrics.contains(metric.rawValue))
        })

        let popupMetricsField = SettingsFieldKey(tablePath: systemMonitorPopupTable, key: "metrics")
        let resolvedPopupMetrics = resolvedStringArrayValue(
            for: popupMetricsField,
            incoming: popupConfig["metrics"]?.stringArrayValue ?? resolvedMetrics,
            current: selectedPopupMetrics(defaults: resolvedMetrics)
        )
        popupMetricSelections = Dictionary(uniqueKeysWithValues: SystemMonitorMetric.allCases.map { metric in
            (metric.rawValue, resolvedPopupMetrics.contains(metric.rawValue))
        })

        popupCPUDetailSelections = detailSelectionDictionary(
            for: .init(tablePath: systemMonitorPopupTable, key: "cpu-details"),
            incoming: popupConfig["cpu-details"]?.stringArrayValue,
            defaults: SystemMonitorPopupCPUDetailOption.defaultSelection
        )
        popupTemperatureDetailSelections = detailSelectionDictionary(
            for: .init(tablePath: systemMonitorPopupTable, key: "temperature-details"),
            incoming: popupConfig["temperature-details"]?.stringArrayValue,
            defaults: SystemMonitorPopupTemperatureDetailOption.defaultSelection
        )
        popupRAMDetailSelections = detailSelectionDictionary(
            for: .init(tablePath: systemMonitorPopupTable, key: "ram-details"),
            incoming: popupConfig["ram-details"]?.stringArrayValue,
            defaults: SystemMonitorPopupRAMDetailOption.defaultSelection
        )
        popupDiskDetailSelections = detailSelectionDictionary(
            for: .init(tablePath: systemMonitorPopupTable, key: "disk-details"),
            incoming: popupConfig["disk-details"]?.stringArrayValue,
            defaults: SystemMonitorPopupDiskDetailOption.defaultSelection
        )
        popupGPUDetailSelections = detailSelectionDictionary(
            for: .init(tablePath: systemMonitorPopupTable, key: "gpu-details"),
            incoming: popupConfig["gpu-details"]?.stringArrayValue,
            defaults: SystemMonitorPopupGPUDetailOption.defaultSelection
        )
        popupNetworkDetailSelections = detailSelectionDictionary(
            for: .init(tablePath: systemMonitorPopupTable, key: "network-details"),
            incoming: popupConfig["network-details"]?.stringArrayValue,
            defaults: SystemMonitorPopupNetworkDetailOption.defaultSelection
        )

        isApplyingConfigSnapshot = false
    }

    private func resetWidgetDefaults() {
        isApplyingConfigSnapshot = true
        showIcon = false
        useMetricIcons = false
        showUsageBars = true
        networkDisplayMode = .single
        metricsPerColumn = 2
        layout = .rows
        dividers = .none
        isApplyingConfigSnapshot = false

        settingsStore.setBool(false, for: .init(tablePath: systemMonitorTable, key: "show-icon"))
        settingsStore.setBool(false, for: .init(tablePath: systemMonitorTable, key: "use-metric-icons"))
        settingsStore.setBool(true, for: .init(tablePath: systemMonitorTable, key: "show-usage-bars"))
        settingsStore.setString("single", for: .init(tablePath: systemMonitorTable, key: "network-display-mode"))
        settingsStore.setInt(2, for: .init(tablePath: systemMonitorTable, key: "metrics-per-column"))
        settingsStore.setString("rows", for: .init(tablePath: systemMonitorTable, key: "layout"))
        settingsStore.setString("none", for: .init(tablePath: systemMonitorTable, key: "dividers"))
    }

    private func resetMetricDefaults() {
        let defaults = SystemMonitorMetric.allCases.map(\.rawValue)
        metricsOrder = defaults
        metricSelections = Dictionary(uniqueKeysWithValues: SystemMonitorMetric.allCases.map { ($0.rawValue, true) })
        pendingArrayWrites.removeValue(forKey: fieldIdentifier(.init(tablePath: systemMonitorTable, key: "metrics")))
        ConfigManager.shared.updateConfigStringArrayValue(tablePath: systemMonitorTable, key: "metrics", newValue: defaults)
    }

    private func resetThresholdDefaults() {
        cpuWarningLevel = 70
        cpuCriticalLevel = 90
        temperatureWarningLevel = 80
        temperatureCriticalLevel = 95
        ramWarningLevel = 70
        ramCriticalLevel = 90
        diskWarningLevel = 80
        diskCriticalLevel = 90
        gpuWarningLevel = 70
        gpuCriticalLevel = 90

        settingsStore.setInt(70, for: .init(tablePath: systemMonitorTable, key: "cpu-warning-level"))
        settingsStore.setInt(90, for: .init(tablePath: systemMonitorTable, key: "cpu-critical-level"))
        settingsStore.setInt(80, for: .init(tablePath: systemMonitorTable, key: "temperature-warning-level"))
        settingsStore.setInt(95, for: .init(tablePath: systemMonitorTable, key: "temperature-critical-level"))
        settingsStore.setInt(70, for: .init(tablePath: systemMonitorTable, key: "ram-warning-level"))
        settingsStore.setInt(90, for: .init(tablePath: systemMonitorTable, key: "ram-critical-level"))
        settingsStore.setInt(80, for: .init(tablePath: systemMonitorTable, key: "disk-warning-level"))
        settingsStore.setInt(90, for: .init(tablePath: systemMonitorTable, key: "disk-critical-level"))
        settingsStore.setInt(70, for: .init(tablePath: systemMonitorTable, key: "gpu-warning-level"))
        settingsStore.setInt(90, for: .init(tablePath: systemMonitorTable, key: "gpu-critical-level"))
    }

    private func resetPopupDefaults() {
        let widgetDefaults = selectedSystemMonitorMetrics()
        popupMetricSelections = Dictionary(uniqueKeysWithValues: SystemMonitorMetric.allCases.map { metric in
            (metric.rawValue, widgetDefaults.contains(metric.rawValue))
        })
        popupCPUDetailSelections = selectionDictionary(
            for: SystemMonitorPopupCPUDetailOption.allCases,
            selected: SystemMonitorPopupCPUDetailOption.defaultSelection
        )
        popupTemperatureDetailSelections = selectionDictionary(
            for: SystemMonitorPopupTemperatureDetailOption.allCases,
            selected: SystemMonitorPopupTemperatureDetailOption.defaultSelection
        )
        popupRAMDetailSelections = selectionDictionary(
            for: SystemMonitorPopupRAMDetailOption.allCases,
            selected: SystemMonitorPopupRAMDetailOption.defaultSelection
        )
        popupDiskDetailSelections = selectionDictionary(
            for: SystemMonitorPopupDiskDetailOption.allCases,
            selected: SystemMonitorPopupDiskDetailOption.defaultSelection
        )
        popupGPUDetailSelections = selectionDictionary(
            for: SystemMonitorPopupGPUDetailOption.allCases,
            selected: SystemMonitorPopupGPUDetailOption.defaultSelection
        )
        popupNetworkDetailSelections = selectionDictionary(
            for: SystemMonitorPopupNetworkDetailOption.allCases,
            selected: SystemMonitorPopupNetworkDetailOption.defaultSelection
        )

        setStringArrayValue(widgetDefaults, for: .init(tablePath: systemMonitorPopupTable, key: "metrics"))
        setStringArrayValue(SystemMonitorPopupCPUDetailOption.defaultSelection.map(\.rawValue), for: .init(tablePath: systemMonitorPopupTable, key: "cpu-details"))
        setStringArrayValue(SystemMonitorPopupTemperatureDetailOption.defaultSelection.map(\.rawValue), for: .init(tablePath: systemMonitorPopupTable, key: "temperature-details"))
        setStringArrayValue(SystemMonitorPopupRAMDetailOption.defaultSelection.map(\.rawValue), for: .init(tablePath: systemMonitorPopupTable, key: "ram-details"))
        setStringArrayValue(SystemMonitorPopupDiskDetailOption.defaultSelection.map(\.rawValue), for: .init(tablePath: systemMonitorPopupTable, key: "disk-details"))
        setStringArrayValue(SystemMonitorPopupGPUDetailOption.defaultSelection.map(\.rawValue), for: .init(tablePath: systemMonitorPopupTable, key: "gpu-details"))
        setStringArrayValue(SystemMonitorPopupNetworkDetailOption.defaultSelection.map(\.rawValue), for: .init(tablePath: systemMonitorPopupTable, key: "network-details"))
    }

    private func persistMetricSelection() {
        guard !isApplyingConfigSnapshot else { return }
        let values = selectedSystemMonitorMetrics()
        setStringArrayValue(values, for: .init(tablePath: systemMonitorTable, key: "metrics"))
    }

    private func moveMetric(from source: Int, to destination: Int) {
        guard metricsOrder.indices.contains(source) else { return }
        var order = metricsOrder
        let item = order.remove(at: source)
        let boundedDestination = max(0, min(destination, order.count))
        order.insert(item, at: boundedDestination)
        metricsOrder = order
        persistMetricSelection()
    }

    /// Reconstructs the full metric order (visible + hidden) from the newly
    /// resolved visible-metrics array. Walks the previous full order and
    /// replaces each previously-visible slot with the next id from
    /// `visibleOrder`, in sequence, while leaving previously-hidden slots
    /// untouched — so a hidden metric keeps its position and a drag/toggle
    /// only reshuffles the currently-visible slots.
    private func mergedMetricsOrder(fromVisible visibleOrder: [String]) -> [String] {
        let previousOrder = metricsOrder.isEmpty
            ? SystemMonitorMetric.allCases.map(\.rawValue)
            : metricsOrder
        var remainingVisible = visibleOrder
        var result: [String] = []
        for id in previousOrder {
            if visibleOrder.contains(id) {
                guard !remainingVisible.isEmpty else { continue }
                result.append(remainingVisible.removeFirst())
            } else {
                result.append(id)
            }
        }
        result.append(contentsOf: remainingVisible)
        return result
    }

    private func selectedSystemMonitorMetrics() -> [String] {
        let orderedIDs = metricsOrder.isEmpty
            ? SystemMonitorMetric.allCases.map(\.rawValue)
            : metricsOrder
        let selected = orderedIDs.filter { metricSelections[$0] ?? true }
        return selected.isEmpty ? ["cpu", "temperature", "ram", "disk", "gpu", "network"] : selected
    }

    private func systemMonitorMetricDescription(for metric: SystemMonitorMetric) -> String {
        switch metric {
        case .cpu:
            return "CPU load, temperature, and related processor status."
        case .temperature:
            return "Dedicated thermal summary card for CPU and GPU temperatures."
        case .ram:
            return "Memory usage and pressure readings."
        case .disk:
            return "Disk space usage and free capacity."
        case .gpu:
            return "GPU utilization and graphics temperature when available."
        case .network:
            return "Network throughput and interface status."
        }
    }

    @ViewBuilder
    private func popupDetailSection<Option: SystemMonitorPopupDetailOption>(
        title: String,
        description: String,
        options: [Option],
        selections: Binding<[String: Bool]>,
        fieldKey: String,
        defaults: [Option]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(options, id: \.rawValue) { option in
                ToggleRow(
                    title: option.title,
                    description: String(
                        format: settingsLocalized("settings.system_monitor.popup_details.option_description"),
                        locale: .autoupdatingCurrent,
                        option.title.lowercased(),
                        title.lowercased()
                    ),
                    isOn: Binding(
                        get: { selections.wrappedValue[option.rawValue] ?? defaults.map(\.rawValue).contains(option.rawValue) },
                        set: { newValue in
                            updatePopupSelection(
                                dictionary: &selections.wrappedValue,
                                key: option.rawValue,
                                newValue: newValue,
                                minimumSelectedCount: 1
                            ) {
                                persistPopupDetailSelection(
                                    fieldKey: fieldKey,
                                    values: selectedValues(
                                        from: selections.wrappedValue,
                                        orderedKeys: options.map(\.rawValue),
                                        fallback: defaults.map(\.rawValue)
                                    )
                                )
                            }
                        }
                    )
                )
            }
        }
    }

    private func persistPopupMetricSelection() {
        guard !isApplyingConfigSnapshot else { return }
        setStringArrayValue(
            selectedPopupMetrics(defaults: selectedSystemMonitorMetrics()),
            for: .init(tablePath: systemMonitorPopupTable, key: "metrics")
        )
    }

    private func persistPopupDetailSelection(fieldKey: String, values: [String]) {
        guard !isApplyingConfigSnapshot else { return }
        setStringArrayValue(values, for: .init(tablePath: systemMonitorPopupTable, key: fieldKey))
    }

    private func selectedPopupMetrics(defaults: [String]) -> [String] {
        selectedValues(
            from: popupMetricSelections,
            orderedKeys: SystemMonitorMetric.allCases.map(\.rawValue),
            fallback: defaults
        )
    }

    private func detailSelectionDictionary<Option: SystemMonitorPopupDetailOption>(
        for field: SettingsFieldKey,
        incoming: [String]?,
        defaults: [Option]
    ) -> [String: Bool] {
        let resolved = resolvedStringArrayValue(
            for: field,
            incoming: incoming ?? defaults.map(\.rawValue),
            current: selectedValues(
                from: selectionDictionary(for: Array(Option.allCases), selected: defaults),
                orderedKeys: Array(Option.allCases).map(\.rawValue),
                fallback: defaults.map(\.rawValue)
            )
        )
        return Dictionary(uniqueKeysWithValues: Array(Option.allCases).map { option in
            (option.rawValue, resolved.contains(option.rawValue))
        })
    }

    private func updatePopupSelection(
        dictionary: inout [String: Bool],
        key: String,
        newValue: Bool,
        minimumSelectedCount: Int,
        onPersist: () -> Void
    ) {
        let currentSelectedCount = dictionary.values.filter { $0 }.count
        if dictionary[key] ?? false, !newValue, currentSelectedCount <= minimumSelectedCount {
            return
        }

        dictionary[key] = newValue
        onPersist()
    }

    private func selectionDictionary<Option: SystemMonitorPopupDetailOption>(
        for options: [Option],
        selected: [Option]
    ) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: options.map { option in
            (option.rawValue, selected.map(\.rawValue).contains(option.rawValue))
        })
    }

    private func selectedValues(
        from dictionary: [String: Bool],
        orderedKeys: [String],
        fallback: [String]
    ) -> [String] {
        let selected = orderedKeys.filter { dictionary[$0] ?? false }
        return selected.isEmpty ? fallback : selected
    }

    private func setStringValue(_ value: String, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingStringWrites[fieldIdentifier(field)] = value
        settingsStore.setString(value, for: field)
    }

    private func setBoolValue(_ value: Bool, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingBoolWrites[fieldIdentifier(field)] = value
        settingsStore.setBool(value, for: field)
    }

    private func setIntValue(_ value: Int, for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingIntWrites[fieldIdentifier(field)] = value
        settingsStore.setInt(value, for: field)
    }

    private func setStringArrayValue(_ value: [String], for field: SettingsFieldKey) {
        guard !isApplyingConfigSnapshot else { return }
        pendingArrayWrites[fieldIdentifier(field)] = value
        ConfigManager.shared.updateConfigStringArrayValue(
            tablePath: field.tablePath,
            key: field.key,
            newValue: value
        )
    }

    private func resolvedStringValue(for field: SettingsFieldKey, incoming: String, current: String) -> String {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingStringWrites[fieldID] {
            if incoming == pendingValue {
                pendingStringWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedBoolValue(for field: SettingsFieldKey, incoming: Bool, current: Bool) -> Bool {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingBoolWrites[fieldID] {
            if incoming == pendingValue {
                pendingBoolWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedIntValue(for field: SettingsFieldKey, incoming: Int, current: Int) -> Int {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingIntWrites[fieldID] {
            if incoming == pendingValue {
                pendingIntWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func resolvedStringArrayValue(for field: SettingsFieldKey, incoming: [String], current: [String]) -> [String] {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingArrayWrites[fieldID] {
            if incoming == pendingValue {
                pendingArrayWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func fieldIdentifier(_ field: SettingsFieldKey) -> String {
        "\(field.tablePath).\(field.key)"
    }
}

private extension SystemMonitorPopupCPUDetailOption {
    static let defaultSelection: [Self] = [.usage, .temperature, .loadAverage, .cores]
}

private extension SystemMonitorPopupTemperatureDetailOption {
    static let defaultSelection: [Self] = [.cpu, .gpu]
}

private extension SystemMonitorPopupRAMDetailOption {
    static let defaultSelection: [Self] = [.used, .app, .free, .pressure]
}

private extension SystemMonitorPopupDiskDetailOption {
    static let defaultSelection: [Self] = [.used, .free, .total]
}

private extension SystemMonitorPopupGPUDetailOption {
    static let defaultSelection: [Self] = [.utilization, .temperature]
}

private extension SystemMonitorPopupNetworkDetailOption {
    static let defaultSelection: [Self] = [.status, .download, .upload, .interfaceName]
}

private struct AboutSettingsView: View {
    @State private var showingChangelog = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.about.header.title"),
                description: settingsLocalized("settings.about.header.description")
            )

            SettingsCardView(settingsLocalized("settings.about.card.application")) {
                HStack(spacing: 16) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(settingsLocalized("settings.about.app_name"))
                            .font(.title2.weight(.semibold))

                        Text(
                            String(
                                format: settingsLocalized("settings.about.version"),
                                locale: .autoupdatingCurrent,
                                appVersion,
                                buildNumber
                            )
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(settingsLocalized("settings.about.description"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsCardView(settingsLocalized("settings.about.card.project")) {
                HStack(spacing: 10) {
                    Button(settingsLocalized("settings.about.action.view_changelog")) {
                        showingChangelog = true
                    }
                    .buttonStyle(.bordered)

                    Button(settingsLocalized("settings.about.action.open_repository")) {
                        openURL("https://github.com/xxspell/barik")
                    }
                    .buttonStyle(.bordered)

                    Button(settingsLocalized("settings.about.action.open_releases")) {
                        openURL("https://github.com/xxspell/barik/releases")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .sheet(isPresented: $showingChangelog) {
            ChangelogPopup()
                .background(Color.black)
                .frame(minWidth: 760, minHeight: 720)
        }
    }

    private func openURL(_ rawValue: String) {
        guard let url = URL(string: rawValue) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct WeatherSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var settingsStore = SettingsStore.shared
    @ObservedObject private var weatherManager = WeatherManager.shared
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "WeatherSettings"
    )

    @State private var unit = WeatherUnit.celsius
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var isApplyingConfigSnapshot = false
    @State private var pendingStringWrites: [String: String] = [:]

    @State private var latitudeTask: Task<Void, Never>?
    @State private var longitudeTask: Task<Void, Never>?

    private let weatherTable = "widgets.default.weather"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: settingsLocalized("settings.weather.header.title"),
                description: settingsLocalized("settings.weather.header.description")
            )

            SettingsCardView(
                settingsLocalized("settings.weather.card.location"),
                actionTitle: settingsLocalized("settings.action.reset"),
                action: resetWeatherDefaults
            ) {
                SegmentedPickerRow(
                    title: settingsLocalized("settings.weather.field.temperature_unit.title"),
                    description: settingsLocalized("settings.weather.field.temperature_unit.description"),
                    selection: Binding(
                        get: { unit },
                        set: { newValue in
                            guard unit != newValue else { return }
                            logger.info(
                                "pickerSelection() oldUnit=\(unit.rawValue, privacy: .public) newUnit=\(newValue.rawValue, privacy: .public) latitudeField=\(latitude, privacy: .public) longitudeField=\(longitude, privacy: .public)"
                            )
                            unit = newValue
                            pendingStringWrites[fieldIdentifier(.init(tablePath: weatherTable, key: "unit"))] = newValue.rawValue
                            let intendedUnit = newValue.rawValue
                            let intendedLatitude = normalizedCoordinateValue(latitude)
                            let intendedLongitude = normalizedCoordinateValue(longitude)
                            Task { @MainActor in
                                settingsStore.setString(
                                    intendedUnit,
                                    for: .init(tablePath: weatherTable, key: "unit")
                                )
                                applyWeatherConfiguration(
                                    unit: intendedUnit,
                                    latitude: intendedLatitude,
                                    longitude: intendedLongitude
                                )
                            }
                        }
                    ),
                    options: WeatherUnit.allCases,
                    titleForOption: { $0.title }
                )

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.weather.field.latitude.title"),
                    description: settingsLocalized("settings.weather.field.latitude.description"),
                    text: $latitude
                )
                .onChange(of: latitude) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(task: &latitudeTask, field: .init(tablePath: weatherTable, key: "latitude"), value: newValue)
                }

                DebouncedTextSettingRow(
                    title: settingsLocalized("settings.weather.field.longitude.title"),
                    description: settingsLocalized("settings.weather.field.longitude.description"),
                    text: $longitude
                )
                .onChange(of: longitude) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(task: &longitudeTask, field: .init(tablePath: weatherTable, key: "longitude"), value: newValue)
                }
            }

            SettingsCardView(settingsLocalized("settings.card.status")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(statusTitle)
                        .font(.headline)

                    Text(statusDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let currentWeather = weatherManager.currentWeather {
                        HStack(spacing: 8) {
                            Image(systemName: currentWeather.symbolName)
                                .symbolRenderingMode(.multicolor)
                            HStack(spacing: 4) {
                                Text(currentWeather.temperature)
                                Text("•")
                                Text(LocalizedStringKey(currentWeather.condition))
                            }
                            .font(.subheadline.weight(.medium))
                        }
                    } else if weatherManager.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(settingsLocalized("settings.weather.status.refreshing"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: loadFromConfig)
        .onReceive(configManager.$config) { config in
            settingsStore.refresh(with: config)
            loadFromConfig()
        }
        .onDisappear {
            latitudeTask?.cancel()
            longitudeTask?.cancel()
        }
    }

    private var statusTitle: String {
        if usesCurrentLocation {
            return weatherManager.locationName ?? settingsLocalized("settings.weather.status.current_location")
        }

        if latitude.isEmpty || longitude.isEmpty {
            return settingsLocalized("settings.weather.status.custom_coordinates_incomplete")
        }

        return settingsLocalized("settings.weather.status.pinned_coordinates")
    }

    private var statusDescription: String {
        if usesCurrentLocation {
            return settingsLocalized("settings.weather.status.using_current_location")
        }

        if latitude.isEmpty || longitude.isEmpty {
            return settingsLocalized("settings.weather.status.enter_both_coordinates")
        }

        return String(
            format: settingsLocalized("settings.weather.status.using_coordinates"),
            locale: .autoupdatingCurrent,
            latitude,
            longitude
        )
    }

    private var usesCurrentLocation: Bool {
        latitude.isEmpty && longitude.isEmpty
    }

    private func loadFromConfig() {
        isApplyingConfigSnapshot = true

        let unitField = SettingsFieldKey(tablePath: weatherTable, key: "unit")
        let latitudeField = SettingsFieldKey(tablePath: weatherTable, key: "latitude")
        let longitudeField = SettingsFieldKey(tablePath: weatherTable, key: "longitude")

        let resolvedUnit = resolvedStringValue(
            for: unitField,
            incoming: settingsStore.stringValue(unitField, fallback: WeatherUnit.celsius.rawValue),
            current: unit.rawValue
        )
        unit = WeatherUnit(rawValue: resolvedUnit) ?? .celsius
        latitude = resolvedStringValue(
            for: latitudeField,
            incoming: settingsStore.stringValue(latitudeField),
            current: latitude
        )
        longitude = resolvedStringValue(
            for: longitudeField,
            incoming: settingsStore.stringValue(longitudeField),
            current: longitude
        )

        logger.debug(
            "loadFromConfig() resolvedUnit=\(unit.rawValue, privacy: .public) latitude=\(latitude, privacy: .public) longitude=\(longitude, privacy: .public)"
        )

        isApplyingConfigSnapshot = false
    }

    private func scheduleStringWrite(
        task: inout Task<Void, Never>?,
        field: SettingsFieldKey,
        value: String
    ) {
        let currentValue = settingsStore.stringValue(field)
        guard value != currentValue else {
            task?.cancel()
            logger.debug(
                "scheduleStringWrite() skipped unchanged field=\(fieldIdentifier(field), privacy: .public) value=\(value, privacy: .public)"
            )
            return
        }

        task?.cancel()
        pendingStringWrites[fieldIdentifier(field)] = value
        let intendedUnit = unit.rawValue
        let intendedLatitude = field.key == "latitude"
            ? normalizedCoordinateValue(value)
            : normalizedCoordinateValue(latitude)
        let intendedLongitude = field.key == "longitude"
            ? normalizedCoordinateValue(value)
            : normalizedCoordinateValue(longitude)
        logger.info(
            "scheduleStringWrite() field=\(fieldIdentifier(field), privacy: .public) value=\(value, privacy: .public) intendedUnit=\(intendedUnit, privacy: .public) intendedLatitude=\(intendedLatitude ?? "<nil>", privacy: .public) intendedLongitude=\(intendedLongitude ?? "<nil>", privacy: .public)"
        )
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            if normalizedCoordinateValue(value) == nil {
                ConfigManager.shared.removeConfigValue(
                    tablePath: field.tablePath,
                    key: field.key
                )
            } else {
                settingsStore.setString(value, for: field)
            }
            applyWeatherConfiguration(
                unit: intendedUnit,
                latitude: intendedLatitude,
                longitude: intendedLongitude
            )
        }
    }

    private func resolvedStringValue(
        for field: SettingsFieldKey,
        incoming: String,
        current: String
    ) -> String {
        let fieldID = fieldIdentifier(field)
        if let pendingValue = pendingStringWrites[fieldID] {
            if incoming == pendingValue {
                pendingStringWrites.removeValue(forKey: fieldID)
                return incoming
            }
            return current
        }
        return incoming
    }

    private func fieldIdentifier(_ field: SettingsFieldKey) -> String {
        "\(field.tablePath).\(field.key)"
    }

    private func resetWeatherDefaults() {
        latitudeTask?.cancel()
        longitudeTask?.cancel()

        let unitField = SettingsFieldKey(tablePath: weatherTable, key: "unit")
        let latitudeField = SettingsFieldKey(tablePath: weatherTable, key: "latitude")
        let longitudeField = SettingsFieldKey(tablePath: weatherTable, key: "longitude")

        isApplyingConfigSnapshot = true
        unit = .celsius
        latitude = ""
        longitude = ""
        isApplyingConfigSnapshot = false

        pendingStringWrites.removeValue(forKey: fieldIdentifier(unitField))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(latitudeField))
        pendingStringWrites.removeValue(forKey: fieldIdentifier(longitudeField))

        settingsStore.setString(WeatherUnit.celsius.rawValue, for: unitField)
        ConfigManager.shared.removeConfigValue(tablePath: weatherTable, key: "latitude")
        ConfigManager.shared.removeConfigValue(tablePath: weatherTable, key: "longitude")
        applyWeatherConfiguration(
            unit: WeatherUnit.celsius.rawValue,
            latitude: nil,
            longitude: nil
        )
    }

    private func applyWeatherConfiguration(
        unit: String,
        latitude: String?,
        longitude: String?
    ) {
        logger.info(
            "applyWeatherConfiguration() unit=\(unit, privacy: .public) latitude=\(latitude ?? "<nil>", privacy: .public) longitude=\(longitude ?? "<nil>", privacy: .public)"
        )
        weatherManager.updateConfiguration(
            unit: unit,
            latitude: latitude,
            longitude: longitude
        )
    }

    private func normalizedCoordinateValue(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

private enum WeatherUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .celsius:
            return settingsLocalized("settings.weather.unit.celsius")
        case .fahrenheit:
            return settingsLocalized("settings.weather.unit.fahrenheit")
        }
    }
}

private enum PomodoroDisplayModeSelection: String, CaseIterable, Identifiable {
    case timer
    case todayPomodoros = "today-pomodoros"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timer:
            return settingsLocalized("settings.pomodoro.option.timer")
        case .todayPomodoros:
            return settingsLocalized("settings.pomodoro.option.today")
        }
    }
}

private enum TickTickDisplayMode: String, CaseIterable, Identifiable {
    case badge
    case rotatingItem = "rotating-item"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .badge:
            return settingsLocalized("settings.ticktick.option.badge")
        case .rotatingItem:
            return settingsLocalized("settings.ticktick.option.rotating")
        }
    }
}

private enum TickTickRotationSource: String, CaseIterable, Identifiable {
    case tasks
    case habits

    var id: String { rawValue }
}

private enum TickTickWallpaperStyle: String, CaseIterable, Identifiable {
    case glow
    case panel
    case terminal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glow:
            return "Glow"
        case .panel:
            return "Panel"
        case .terminal:
            return "Terminal"
        }
    }
}

private enum HomebrewDisplayMode: String, CaseIterable, Identifiable {
    case label
    case icon
    case badge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .label:
            return "Label"
        case .icon:
            return "Icon"
        case .badge:
            return "Badge"
        }
    }
}

private enum NowPlayingPopupLayout: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vertical:
            return settingsLocalized("settings.option.vertical")
        case .horizontal:
            return settingsLocalized("settings.option.horizontal")
        }
    }
}

private enum SystemMonitorLayoutSelection: String, CaseIterable, Identifiable {
    case rows
    case stacked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rows:
            return settingsLocalized("settings.system_monitor.option.rows")
        case .stacked:
            return settingsLocalized("settings.system_monitor.option.stacked")
        }
    }
}

private enum SystemMonitorDividerSelection: String, CaseIterable, Identifiable {
    case none
    case horizontal
    case vertical
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return settingsLocalized("settings.option.none")
        case .horizontal:
            return settingsLocalized("settings.option.horizontal")
        case .vertical:
            return settingsLocalized("settings.option.vertical")
        case .both:
            return settingsLocalized("settings.option.both")
        }
    }
}

private enum UsageRingLogic: String, CaseIterable, Identifiable {
    case healthy
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .healthy:
            return settingsLocalized("settings.ring_logic.healthy")
        case .failed:
            return settingsLocalized("settings.ring_logic.failed")
        }
    }
}

private enum SystemMonitorNetworkDisplayMode: String, CaseIterable, Identifiable {
    case single
    case dualLine = "dual-line"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            return settingsLocalized("settings.system_monitor.option.single")
        case .dualLine:
            return settingsLocalized("settings.system_monitor.option.dual")
        }
    }
}

private enum AppearanceTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

private enum AppearanceHeightMode: CaseIterable, Identifiable {
    case defaultHeight
    case menuBar
    case custom

    var id: String { title }

    var title: String {
        switch self {
        case .defaultHeight:
            return "Default"
        case .menuBar:
            return "Menu Bar"
        case .custom:
            return "Custom"
        }
    }

    init(height: BackgroundForegroundHeight) {
        switch height {
        case .barikDefault:
            self = .defaultHeight
        case .menuBar:
            self = .menuBar
        case .float:
            self = .custom
        }
    }
}

private enum AppearanceBlur: Int, CaseIterable, Identifiable {
    case ultraThin = 1
    case thin = 2
    case regular = 3
    case thick = 4
    case ultraThick = 5
    case bar = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .ultraThin:
            return "Ultra Thin"
        case .thin:
            return "Thin"
        case .regular:
            return "Regular"
        case .thick:
            return "Thick"
        case .ultraThick:
            return "Ultra Thick"
        case .bar:
            return "Bar"
        }
    }

    init?(material: Material) {
        switch String(describing: material) {
        case "ultraThin":
            self = .ultraThin
        case "thin":
            self = .thin
        case "regular":
            self = .regular
        case "thick":
            self = .thick
        case "ultraThick":
            self = .ultraThick
        case "bar":
            self = .bar
        default:
            return nil
        }
    }
}

private enum AppearanceBackgroundBlur: Int, CaseIterable, Identifiable {
    case ultraThin = 1
    case thin = 2
    case regular = 3
    case thick = 4
    case ultraThick = 5
    case bar = 6
    case solidBlack = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .ultraThin:
            return "Ultra Thin"
        case .thin:
            return "Thin"
        case .regular:
            return "Regular"
        case .thick:
            return "Thick"
        case .ultraThick:
            return "Ultra Thick"
        case .bar:
            return "Bar"
        case .solidBlack:
            return "Solid Black"
        }
    }

    init?(material: Material, isBlack: Bool) {
        if isBlack {
            self = .solidBlack
            return
        }

        switch String(describing: material) {
        case "ultraThin":
            self = .ultraThin
        case "thin":
            self = .thin
        case "regular":
            self = .regular
        case "thick":
            self = .thick
        case "ultraThick":
            self = .ultraThick
        case "bar":
            self = .bar
        default:
            return nil
        }
    }
}

private struct SettingsHeaderView: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())

            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsCardView<Content: View>: View {
    let title: String
    let badgeTitle: String?
    let actionTitle: String?
    let action: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        _ title: String,
        badgeTitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.badgeTitle = badgeTitle
        self.actionTitle = actionTitle
        self.action = action
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.title3.weight(.semibold))

                if let badgeTitle {
                    SettingsStatusBadge(
                        title: badgeTitle,
                        tint: .orange
                    )
                }

                Spacer(minLength: 8)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(SettingsCardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SettingsCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
    }
}

private struct SettingsStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .kerning(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }
}

private struct ProxyUsageStatusView: View {
    let title: String
    let description: String
    let isHealthy: Bool
    let refreshAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                SettingsStatusBadge(
                    title: isHealthy ? settingsLocalized("settings.badge.live") : settingsLocalized("settings.badge.check"),
                    tint: isHealthy ? .green : .orange
                )
            }

            Button(settingsLocalized("settings.action.refresh_now"), action: refreshAction)
                .buttonStyle(.bordered)
        }
    }
}

private struct DebouncedTextSettingRow: View {
    let title: String
    let description: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct ColorSettingRow: View {
    let title: String
    let description: String
    @Binding var color: Color
    @Binding var hexText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44, height: 28)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color)
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )

                TextField("#RRGGBB", text: $hexText)
                    .textFieldStyle(.roundedBorder)
                    .monospaced()
            }
        }
    }
}

private struct SecureTextSettingRow: View {
    let title: String
    let description: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct SegmentedPickerRow<Option: Hashable>: View {
    let title: String
    let description: String
    @Binding var selection: Option
    let options: [Option]
    let titleForOption: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(titleForOption(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private func stringValue(in config: ConfigData, keys: [String]) -> String? {
    for key in keys {
        if let value = config[key]?.stringValue {
            return value
        }
    }
    return nil
}

private func boolValue(in config: ConfigData, keys: [String]) -> Bool? {
    for key in keys {
        if let value = config[key]?.boolValue {
            return value
        }
    }
    return nil
}

private func intValue(in config: ConfigData, keys: [String]) -> Int? {
    for key in keys {
        if let value = config[key]?.intValue {
            return value
        }
    }
    return nil
}

private func formatDuration(seconds: Int) -> String {
    if seconds < 60 {
        return "\(seconds)s"
    }

    if seconds % 60 == 0 {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    let minutes = seconds / 60
    let remainingSeconds = seconds % 60
    return "\(minutes)m \(remainingSeconds)s"
}

private func settingsLocalized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private struct ToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }
}

private struct SliderSettingRow: View {
    let title: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueFormat: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)

                Spacer(minLength: 8)

                Text(valueFormat(value))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Slider(value: $value, in: range, step: step)
        }
    }
}

private extension Color {
    func toHexString() -> String? {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB)
        guard let nsColor else { return nil }

        let red = Int(round(nsColor.redComponent * 255))
        let green = Int(round(nsColor.greenComponent * 255))
        let blue = Int(round(nsColor.blueComponent * 255))

        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

private struct PickerSettingRow<Option: Hashable>: View {
    let title: String
    let description: String
    @Binding var selection: Option
    let options: [Option]
    let titleForOption: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(titleForOption(option)).tag(option)
                }
            }
            .labelsHidden()
        }
    }
}

private enum AppearanceFontFamilyOption: Hashable {
    case systemDefault
    case custom(String)

    var title: String {
        switch self {
        case .systemDefault:
            return settingsLocalized("settings.appearance.field.font_family.system_default")
        case let .custom(family):
            return family
        }
    }

    var previewFamilyName: String? {
        switch self {
        case .systemDefault:
            return nil
        case let .custom(family):
            return family
        }
    }
}

private struct FontFamilySettingRow: View {
    let title: String
    let description: String
    let searchPlaceholder: String
    let installHint: String
    let openFontBookTitle: String
    @Binding var selection: AppearanceFontFamilyOption
    @Binding var searchText: String
    let options: [AppearanceFontFamilyOption]
    let openFontBook: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()

            Text("Barik Aa 0123456789")
                .font(previewFont)
                .foregroundStyle(.primary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            HStack(alignment: .top, spacing: 12) {
                Text(installHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button(openFontBookTitle, action: openFontBook)
            }
        }
    }

    private var previewFont: Font {
        if let family = selection.previewFamilyName {
            return .custom(family, size: 13).weight(.medium)
        }
        return .system(size: 13, weight: .medium)
    }
}

/// Dev-only screen (see `AppRuntimeFlags.isWidgetExportEnabled`) that
/// renders every currently-configured widget to a transparent PNG via
/// `WidgetExporter`, for changelog/marketing screenshots.
private struct WidgetExportView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @State private var lastResultSummary: String?

    private static let nonExportableIDs: Set<String> = ["spacer", "divider", "system-banner"]

    /// Union of the global `widgets.displayed` list and every per-display
    /// `[widgets.displays."N"]` override, deduplicated by widget id. A
    /// widget enabled only on one monitor (not in the global fallback list)
    /// should still be exportable.
    private var exportableItems: [TomlWidgetItem] {
        let widgets = configManager.config.rootToml.widgets
        var seenIDs = Set<String>()
        var items: [TomlWidgetItem] = []

        for item in widgets.displayed + widgets.displays.values.flatMap(\.displayed) {
            guard !Self.nonExportableIDs.contains(item.id), !seenIDs.contains(item.id) else {
                continue
            }
            seenIDs.insert(item.id)
            items.append(item)
        }

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: "Widget Export",
                description: "Renders each widget in your current bar config to a transparent PNG at 3x scale using live data. Dev-only — visible because Barik was launched with --dev-export."
            )

            SettingsCardView(
                "Widgets",
                actionTitle: exportableItems.isEmpty ? nil : "Export All",
                action: exportableItems.isEmpty ? nil : exportAll
            ) {
                if exportableItems.isEmpty {
                    Text("No exportable widgets in the current configuration.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(exportableItems, id: \.id) { item in
                            HStack {
                                Text(displayName(for: item.id))

                                Spacer()

                                Button("Export") {
                                    exportOne(item)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let lastResultSummary {
                    Text(lastResultSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func displayName(for id: String) -> String {
        let stripped = id.hasPrefix("default.") ? String(id.dropFirst("default.".count)) : id
        return stripped
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func exportOne(_ item: TomlWidgetItem) {
        let result = WidgetExporter.exportAll(items: [item])
        reveal(result.folder)
        lastResultSummary = "Exported \(result.succeeded.count) of 1"
    }

    private func exportAll() {
        let result = WidgetExporter.exportAll(items: exportableItems)
        reveal(result.folder)
        let total = result.succeeded.count + result.skipped.count
        lastResultSummary = result.skipped.isEmpty
            ? "Exported \(result.succeeded.count) of \(total)"
            : "Exported \(result.succeeded.count) of \(total) — skipped: \(result.skipped.joined(separator: ", "))"
    }

    private func reveal(_ folder: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
