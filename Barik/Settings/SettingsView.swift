import SwiftUI
import OSLog

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
                SettingsPlaceholderView(
                    title: "Appearance",
                    description: "Appearance controls are a good next step after the first widget settings flow is stable."
                )
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
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeaderView(
                title: "Displays",
                description: "Per-display widget layout is already supported by the config model. This section is the right place for the upcoming drag-and-drop layout editor."
            )

            ForEach(NSScreen.screens.map(\.monitorDescriptor)) { monitor in
                VStack(alignment: .leading, spacing: 6) {
                    Text(monitor.name)
                        .font(.headline)
                    Text("Monitor ID: \(monitor.id)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(SettingsCardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
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
            settingsStore.setString(value, for: field)
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
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))

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
