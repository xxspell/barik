import SwiftUI
import OSLog
import UniformTypeIdentifiers

struct SettingsRootView: View {
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $router.selectedSection) { section in
                Label(section.title, systemImage: section.iconName)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            SettingsDetailView(section: router.selectedSection)
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}

private struct SettingsDetailView: View {
    let section: SettingsSection

    var body: some View {
        ScrollView {
            switch section {
            case .general:
                SettingsPlaceholderView(
                    title: "General",
                    description: "The shared settings platform is now in place. General app options can land here next."
                )
            case .appearance:
                AppearanceSettingsView()
            case .displays:
                DisplaysSettingsView()
            case .time:
                TimeSettingsView()
            case .weather:
                WeatherSettingsView()
            }
        }
        .scrollContentBackground(.hidden)
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

private struct DisplaysSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @State private var drafts: [String: [String]] = [:]
    @State private var catalogContext: DisplayCatalogContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeaderView(
                title: "Displays",
                description: "Each display can override the global widget layout. Open the catalog to add widgets, then reorder or remove them directly from the active layout."
            )

            ForEach(NSScreen.screens.map(\.monitorDescriptor)) { monitor in
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(monitor.name)
                                .font(.headline)
                            Text("Monitor ID: \(monitor.id)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(displayStatus(for: monitor))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(
                                    configManager.hasDisplayOverride(for: monitor.id)
                                        ? .primary
                                        : .secondary
                                )
                        }

                        Spacer(minLength: 12)

                        HStack(spacing: 8) {
                            Button("Open Catalog") {
                                catalogContext = .init(
                                    monitorID: monitor.id,
                                    monitorName: monitor.name
                                )
                            }

                            if configManager.hasDisplayOverride(for: monitor.id) {
                                Button("Use Global Layout") {
                                    resetOverride(for: monitor)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active Layout")
                            .font(.headline)

                        Text("This list is the exact widget order for this display. Drag by the handle to reorder, or remove rows with the delete button.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        let layout = currentLayout(for: monitor)
                        if layout.isEmpty {
                            Text("No widgets in this display override yet. Open the catalog to add the first one.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                )
                        } else {
                            DisplayLayoutListEditor(
                                monitorID: monitor.id,
                                items: layout.enumerated().map { index, widgetID in
                                    .init(
                                        index: index,
                                        widgetID: widgetID,
                                        title: definition(for: widgetID).title
                                    )
                                },
                                onMove: { from, to in
                                    moveWidget(for: monitor, from: from, to: to)
                                },
                                onRemove: { index in
                                    removeWidget(at: index, for: monitor)
                                }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(SettingsCardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .onAppear(perform: syncDraftsFromConfig)
        .onReceive(configManager.$config) { _ in
            syncDraftsFromConfig()
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

    private func effectiveWidgetIDs(for monitor: MonitorDescriptor) -> [String] {
        configManager
            .displayedWidgets(for: monitor.id)
            .map(\.id)
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
            return "Custom display override is active for this monitor."
        }

        return "Using the global widget layout."
    }

    private func syncDraftsFromConfig() {
        let monitors = NSScreen.screens.map(\.monitorDescriptor)
        for monitor in monitors {
            drafts[monitor.id] = effectiveWidgetIDs(for: monitor)
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

    private func definition(for widgetID: String) -> DisplayWidgetDefinition {
        displayWidgetDefinitions.first(where: { $0.id == widgetID })
            ?? DisplayWidgetDefinition(
                id: widgetID,
                title: widgetID,
                description: "Custom widget ID from the current config.",
                allowsMultiple: false
            )
    }

    private func monitorDescriptor(for monitorID: String) -> MonitorDescriptor? {
        NSScreen.screens
            .map(\.monitorDescriptor)
            .first(where: { $0.id == monitorID })
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared

    @State private var theme = AppearanceTheme.system
    @State private var horizontalPadding: Double = 24
    @State private var notchPadding: Double = 12
    @State private var widgetSpacing: Double = 15
    @State private var widgetBackgroundsShown = false
    @State private var widgetBlur = AppearanceBlur.regular
    @State private var backgroundShown = true
    @State private var backgroundBlur = AppearanceBackgroundBlur.ultraThin
    @State private var isApplyingConfigSnapshot = false

    private let foregroundTable = "experimental.foreground"
    private let widgetBackgroundTable = "experimental.foreground.widgets-background"
    private let backgroundTable = "experimental.background"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHeaderView(
                title: "Appearance",
                description: "Tune the global bar look and spacing. Stable settings and experimental bar controls live together here."
            )

            SettingsCardView("Theme") {
                SegmentedPickerRow(
                    title: "Color Scheme",
                    description: "Pick a fixed appearance or let Barik follow the current macOS setting.",
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
            }

            SettingsCardView("Foreground Bar", badgeTitle: "Beta") {
                SliderSettingRow(
                    title: "Horizontal Padding",
                    description: "Outer left and right padding for displays without a notch.",
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
                    title: "Notch Padding",
                    description: "Inner padding around the notch gap on displays that split the layout.",
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
                    title: "Widget Spacing",
                    description: "Gap between widgets in the menu bar row.",
                    value: $widgetSpacing,
                    range: 0...40,
                    step: 1,
                    valueFormat: { "\(Int($0)) pt" }
                )
                .onChange(of: widgetSpacing) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: foregroundTable,
                        key: "spacing",
                        newValueLiteral: String(Int(newValue.rounded()))
                    )
                }
            }

            SettingsCardView("Widget Capsules", badgeTitle: "Beta") {
                ToggleRow(
                    title: "Show Widget Backgrounds",
                    description: "Wrap compatible widgets in a shared blurred capsule background.",
                    isOn: $widgetBackgroundsShown
                )
                .onChange(of: widgetBackgroundsShown) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: widgetBackgroundTable,
                        key: "displayed",
                        newValueLiteral: newValue ? "true" : "false"
                    )
                }

                PickerSettingRow(
                    title: "Widget Blur",
                    description: "Choose the blur material used for widget capsule backgrounds.",
                    selection: $widgetBlur,
                    options: AppearanceBlur.allCases,
                    titleForOption: \.title
                )
                .disabled(!widgetBackgroundsShown)
                .onChange(of: widgetBlur) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    ConfigManager.shared.updateConfigLiteralValue(
                        tablePath: widgetBackgroundTable,
                        key: "blur",
                        newValueLiteral: String(newValue.rawValue)
                    )
                }
            }

            SettingsCardView("Background Bar", badgeTitle: "Beta") {
                ToggleRow(
                    title: "Show Background Bar",
                    description: "Render the full-width bar backdrop behind the widgets.",
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

                PickerSettingRow(
                    title: "Background Material",
                    description: "Switch between blur materials or a solid black backdrop.",
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
        horizontalPadding = foreground.horizontalPadding
        notchPadding = foreground.notchHorizontalPadding
        widgetSpacing = foreground.spacing
        widgetBackgroundsShown = foreground.widgetsBackground.displayed
        widgetBlur = AppearanceBlur(material: foreground.widgetsBackground.blur) ?? .regular
        backgroundShown = background.displayed
        backgroundBlur = AppearanceBackgroundBlur(
            material: background.blur,
            isBlack: background.black
        ) ?? .ultraThin

        isApplyingConfigSnapshot = false
    }
}

private struct DisplayCatalogContext: Identifiable {
    let monitorID: String
    let monitorName: String
    var id: String { monitorID }
}

private struct DisplayLayoutDragItem: Equatable {
    let monitorID: String
    let widgetID: String
    let index: Int
}

private struct DisplayLayoutDropTarget: Equatable {
    let monitorID: String
    let destinationIndex: Int
}

private struct DisplayListContainerDropDelegate: DropDelegate {
    let monitorID: String
    let destinationIndex: Int
    @Binding var draggedLayoutItem: DisplayLayoutDragItem?
    @Binding var dropTarget: DisplayLayoutDropTarget?
    let moveWidget: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard let currentDrag = draggedLayoutItem, currentDrag.monitorID == monitorID else {
            return
        }
        withAnimation(.easeInOut(duration: 0.14)) {
            dropTarget = .init(
                monitorID: monitorID,
                destinationIndex: currentDrag.index == destinationIndex
                    ? currentDrag.index
                    : destinationIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        withAnimation(.easeInOut(duration: 0.14)) {
            dropTarget = .init(monitorID: monitorID, destinationIndex: destinationIndex)
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.14)) {
            if dropTarget?.monitorID == monitorID
                && dropTarget?.destinationIndex == destinationIndex {
                dropTarget = nil
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            withAnimation(.easeInOut(duration: 0.14)) {
                draggedLayoutItem = nil
                dropTarget = nil
            }
        }
        guard let draggedLayoutItem, draggedLayoutItem.monitorID == monitorID else {
            return false
        }

        let adjustedDestination = adjustedDestinationIndex(
            sourceIndex: draggedLayoutItem.index,
            destinationIndex: destinationIndex
        )
        guard adjustedDestination != draggedLayoutItem.index else {
            return true
        }

        moveWidget(draggedLayoutItem.index, adjustedDestination)
        return true
    }

    private func adjustedDestinationIndex(sourceIndex: Int, destinationIndex: Int) -> Int {
        if destinationIndex > sourceIndex {
            return max(0, destinationIndex - 1)
        }
        return destinationIndex
    }
}

private struct DisplayWidgetDefinition: Identifiable {
    let id: String
    let title: String
    let description: String
    let allowsMultiple: Bool
}

private let displayWidgetDefinitions: [DisplayWidgetDefinition] = [
    .init(id: "default.spaces", title: "Spaces", description: "Virtual desktops and focused window state.", allowsMultiple: false),
    .init(id: "default.claude-usage", title: "Claude Usage", description: "Claude quota and account usage status.", allowsMultiple: false),
    .init(id: "default.codex-usage", title: "Codex Usage", description: "Codex quota usage and remaining allowance.", allowsMultiple: false),
    .init(id: "default.system-monitor", title: "System Monitor", description: "CPU, RAM, GPU, temperature, disk, and network metrics.", allowsMultiple: false),
    .init(id: "default.network", title: "Network", description: "Current connectivity and transfer speeds.", allowsMultiple: false),
    .init(id: "default.focus", title: "Focus", description: "Current macOS Focus mode and status tinting.", allowsMultiple: false),
    .init(id: "default.pomodoro", title: "Pomodoro", description: "Active pomodoro timer and daily progress.", allowsMultiple: false),
    .init(id: "default.shortcuts", title: "Shortcuts", description: "Apple Shortcuts launcher in the menu bar.", allowsMultiple: false),
    .init(id: "default.keyboard-layout", title: "Keyboard Layout", description: "Current input source and layout capsule.", allowsMultiple: false),
    .init(id: "default.battery", title: "Battery", description: "Battery level, charging state, and thresholds.", allowsMultiple: false),
    .init(id: "default.time", title: "Time", description: "Clock and upcoming calendar event.", allowsMultiple: false),
    .init(id: "default.weather", title: "Weather", description: "Current weather, forecast, and precipitation.", allowsMultiple: false),
    .init(id: "default.screen-recording-stop", title: "Screen Recording Stop", description: "Quick stop control for active recordings.", allowsMultiple: false),
    .init(id: "default.qwen-proxy-usage", title: "Qwen Proxy Usage", description: "Health and quota overview for the Qwen proxy.", allowsMultiple: false),
    .init(id: "default.cliproxy-usage", title: "CLIProxy Usage", description: "CLIProxy account health and quota usage.", allowsMultiple: false),
    .init(id: "default.nowplaying", title: "Now Playing", description: "Current track info and album artwork.", allowsMultiple: false),
    .init(id: "default.homebrew", title: "Homebrew", description: "Available formula and cask updates.", allowsMultiple: false),
    .init(id: "default.ticktick", title: "TickTick", description: "Tasks or habits from your TickTick account.", allowsMultiple: false),
    .init(id: "spacer", title: "Spacer", description: "Flexible empty space used to split left and right groups.", allowsMultiple: true),
    .init(id: "divider", title: "Divider", description: "Thin visual separator between widget groups.", allowsMultiple: true)
]

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

private struct DisplayLayoutListItem: Identifiable, Equatable {
    let index: Int
    let widgetID: String
    let title: String
    var id: String { "\(index)-\(widgetID)" }
}

private struct DisplayLayoutListEditor: View {
    let monitorID: String
    let items: [DisplayLayoutListItem]
    let onMove: (Int, Int) -> Void
    let onRemove: (Int) -> Void
    @State private var draggedLayoutItem: DisplayLayoutDragItem?
    @State private var dropTarget: DisplayLayoutDropTarget?

    var body: some View {
        VStack(spacing: 8) {
            DisplayLayoutInsertionZone(
                isTargeted: dropTarget == .init(
                    monitorID: monitorID,
                    destinationIndex: 0
                )
            )
            .onDrop(
                of: [UTType.plainText],
                delegate: DisplayListContainerDropDelegate(
                    monitorID: monitorID,
                    destinationIndex: 0,
                    draggedLayoutItem: $draggedLayoutItem,
                    dropTarget: $dropTarget,
                    moveWidget: onMove
                )
            )

            ForEach(items) { item in
                DisplayLayoutListRow(
                    title: item.title,
                    widgetID: item.widgetID,
                    isDragging: draggedLayoutItem?.monitorID == monitorID
                        && draggedLayoutItem?.index == item.index,
                    onRemove: {
                        onRemove(item.index)
                    },
                    dragProvider: {
                        draggedLayoutItem = .init(
                            monitorID: monitorID,
                            widgetID: item.widgetID,
                            index: item.index
                        )
                        return NSItemProvider(object: "\(item.index)" as NSString)
                    }
                )

                DisplayLayoutInsertionZone(
                    isTargeted: dropTarget == .init(
                        monitorID: monitorID,
                        destinationIndex: item.index + 1
                    )
                )
                .onDrop(
                    of: [UTType.plainText],
                    delegate: DisplayListContainerDropDelegate(
                        monitorID: monitorID,
                        destinationIndex: item.index + 1,
                        draggedLayoutItem: $draggedLayoutItem,
                        dropTarget: $dropTarget,
                        moveWidget: onMove
                    )
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: items)
    }
}

private struct DisplayLayoutListRow: View {
    let title: String
    let widgetID: String
    let isDragging: Bool
    let onRemove: () -> Void
    let dragProvider: () -> NSItemProvider

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(widgetID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isDragging ? 0.07 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
        .scaleEffect(isDragging ? 0.985 : 1)
        .opacity(isDragging ? 0.72 : 1)
        .onDrag(dragProvider)
    }
}

private struct DisplayLayoutInsertionZone: View {
    let isTargeted: Bool

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: isTargeted ? 18 : 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isTargeted ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        isTargeted ? Color.accentColor.opacity(0.55) : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .animation(.spring(response: 0.18, dampingFraction: 0.9), value: isTargeted)
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
                    Text("Widget Catalog")
                        .font(.title2.bold())

                    Text("Add widgets to \(monitorName). Descriptions stay here in the catalog, while the active layout stays compact.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button("Done") {
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
                                Text(canAdd(definition.id) ? "Add" : "Added")
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
                title: "Time Widget",
                description: "This is the first GUI-backed settings section. It edits the same TOML config the widgets already use, so changes apply immediately."
            )

            SettingsCardView("Clock") {
                DebouncedTextSettingRow(
                    title: "Primary Format",
                    description: "Unicode date template used in the default single-line mode.",
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
                    title: "Time Zone",
                    description: "Optional IANA time zone like Europe/Berlin or America/Los_Angeles.",
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
                    title: "Stacked Layout",
                    description: "Show time and date on two separate lines.",
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
                    title: "Stacked Time Format",
                    description: "Format used for the larger top line in stacked mode.",
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
                    title: "Stacked Date Format",
                    description: "Format used for the smaller bottom line in stacked mode.",
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

            SettingsCardView("Calendar") {
                ToggleRow(
                    title: "Show Upcoming Event",
                    description: "Display the next calendar event under the clock in single-line mode.",
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
                    title: "Event Time Format",
                    description: "Format used when showing an event start time.",
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

            SettingsCardView("Popup") {
                Picker("Popup Layout", selection: Binding(
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

            SettingsCardView("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(previewDateString())
                        .font(stacked ? .title3.weight(.semibold) : .headline.weight(.semibold))
                    if stacked {
                        Text(previewStackedDateString())
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else if showEvents {
                        Text("Upcoming event example (\(previewEventTimeString()))")
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
            return "Box"
        case .vertical:
            return "Vertical"
        case .horizontal:
            return "Horizontal"
        case .settings:
            return "Settings"
        }
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
                title: "Weather Widget",
                description: "This section uses the same live config pipeline as the clock. You can switch temperature units and either use the current location or pin custom coordinates."
            )

            SettingsCardView("Location") {
                SegmentedPickerRow(
                    title: "Temperature Unit",
                    description: "Select how the widget formats current temperature and forecast values.",
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
                    title: "Latitude",
                    description: "Leave empty to use the Mac's current location. Custom coordinates must be paired with longitude.",
                    text: $latitude
                )
                .onChange(of: latitude) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(task: &latitudeTask, field: .init(tablePath: weatherTable, key: "latitude"), value: newValue)
                }

                DebouncedTextSettingRow(
                    title: "Longitude",
                    description: "Leave empty to use the Mac's current location. For example: 37.6173",
                    text: $longitude
                )
                .onChange(of: longitude) { _, newValue in
                    guard !isApplyingConfigSnapshot else { return }
                    scheduleStringWrite(task: &longitudeTask, field: .init(tablePath: weatherTable, key: "longitude"), value: newValue)
                }
            }

            SettingsCardView("Status") {
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
                            Text("Refreshing weather data…")
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
            return weatherManager.locationName ?? "Current Location"
        }

        if latitude.isEmpty || longitude.isEmpty {
            return "Custom coordinates incomplete"
        }

        return "Pinned coordinates"
    }

    private var statusDescription: String {
        if usesCurrentLocation {
            return "Weather updates follow the Mac's current location."
        }

        if latitude.isEmpty || longitude.isEmpty {
            return "Enter both latitude and longitude to lock the widget to a custom place."
        }

        return "Weather updates now use latitude \(latitude) and longitude \(longitude)."
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
            return "Celsius"
        case .fahrenheit:
            return "Fahrenheit"
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
    @ViewBuilder let content: () -> Content

    init(
        _ title: String,
        badgeTitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.badgeTitle = badgeTitle
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
