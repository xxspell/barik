import Foundation
import OSLog
import SwiftUI
import TOMLDecoder

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "ConfigManager"
    )

    @Published private(set) var config = Config()
    @Published private(set) var initError: String?
    
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var configFilePath: String?
    private var isPerformingInternalWrite = false
    private let parseRevisionQueue = DispatchQueue(label: "Pansy.Barik.ConfigManager.ParseRevision")
    private var latestScheduledParseRevision: Int = 0

    private init() {
        loadOrCreateConfigIfNeeded()
    }

    private func loadOrCreateConfigIfNeeded() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let path1 = "\(homePath)/.barik-config.toml"
        let path2 = "\(homePath)/.config/barik/config.toml"
        var chosenPath: String?

        if FileManager.default.fileExists(atPath: path1) {
            chosenPath = path1
        } else if FileManager.default.fileExists(atPath: path2) {
            chosenPath = path2
        } else {
            do {
                try createDefaultConfig(at: path1)
                chosenPath = path1
            } catch {
                publishInitError(
                    "Error creating default config: \(error.localizedDescription)"
                )
                logger.error("Error creating default config: \(error.localizedDescription)")
                return
            }
        }

        if let path = chosenPath {
            configFilePath = path
            logger.info("Using config path: \(path, privacy: .public)")
            parseConfigFile(at: path)
            startWatchingFile(at: path)
        }
    }

    private func parseConfigFile(at path: String) {
        let revision = nextParseRevision()
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            logger.debug(
                "Parsing config file revision=\(revision, privacy: .public) at \(path, privacy: .public), size=\(content.count, privacy: .public)"
            )
            let decoder = TOMLDecoder()
            let rootToml = try decoder.decode(RootToml.self, from: content)
            let overrideMonitorIDs = rootToml.widgets.displays.keys
                .sorted()
                .joined(separator: ", ")
            logger.debug(
                "Loaded config revision=\(revision, privacy: .public) with monitor widget overrides: \(overrideMonitorIDs, privacy: .public)"
            )
            guard shouldPublishParseRevision(revision) else {
                logger.debug(
                    "Discarding stale config parse revision=\(revision, privacy: .public) latestScheduled=\(self.currentScheduledParseRevision(), privacy: .public)"
                )
                return
            }
            publishOnMain {
                self.initError = nil
                self.config = Config(rootToml: rootToml)
            }
        } catch {
            publishInitError("Error parsing TOML file: \(error.localizedDescription)")
            logger.error("Error when parsing TOML file: \(error.localizedDescription)")
        }
    }

    private func createDefaultConfig(at path: String) throws {
        let defaultTOML = """
            # If you installed yabai or aerospace without using Homebrew,
            # manually set the path to the binary. For example:
            #
            # yabai.path = "/run/current-system/sw/bin/yabai"
            # aerospace.path = ...
            
            theme = "system" # system, light, dark

            [widgets]
            displayed = [ # widgets on menu bar
                "default.spaces",
                "spacer",
                "default.claude-usage",
                "default.codex-usage",
                "default.system-monitor",
                "default.network",
                # "default.focus",
                # "default.pomodoro",
                # "default.shortcuts",
                "default.keyboard-layout",
                "default.battery",
                "divider",
                # { "default.time" = { time-zone = "America/Los_Angeles", format = "E d, hh:mm" } },
                "default.time"
                # Uncomment the line below to add the weather widget
                # "default.weather"
                # Uncomment the line below to add the screen recording stop widget
                # "default.screen-recording-stop"
            ]

            # Optional per-monitor overrides. Use the monitor id from the debug logs.
            # If a monitor override exists, it fully replaces the global list above.
            # [widgets.displays."69732928"]
            # displayed = [
            #     "default.system-monitor",
            #     "default.time"
            # ]

            [experimental.foreground]
            # Optional tighter edge padding for displays with a notch.
            # Falls back to min(horizontal-padding, 12) when omitted.
            # notch-horizontal-padding = 12

            [widgets.default.spaces]
            space.show-key = true        # show space number (or character, if you use AeroSpace)
            space.show-inactive = true
            space.show-empty = true
            space.show-delete-button = true
            window.show-title = true
            window.show-hidden = false
            window.icon-desaturation = 0
            window.show-hover-tooltip = false
            window.hover-tooltip = "{app} ({pid})"
            window.title.max-length = 50

            [widgets.default.claude-usage]

            [widgets.default.codex-usage]

            # Qwen Proxy Usage widget — monitors your self-hosted Qwen proxy
            # Uncomment and configure to enable:
            # [widgets.default.qwen-proxy-usage]
            # base_url = "http://192.168.1.110:9927"
            # token = "sk-yourtoken"
            # show_ring = false       # ring arc around the icon
            # ring_logic = "failed"   # "failed" = arc grows on problems (Codex style)
            #                         # "healthy" = arc shrinks on problems (Claude style)
            # ring-warning-level = 60      # %
            # ring-critical-level = 90  # %
            # show_label = true       # healthy account count label
            # All settings also available via popup gear icon

            # CLIProxy Usage widget — reads stats from the Management API
            # Uncomment and configure to enable:
            # [widgets.default.cliproxy-usage]
            # base-url = "http://localhost:8317"
            # api-key = "your-management-key"
            # show-ring = false          # arc around the icon
            # ring-logic = "failed"      # "failed" = arc grows on errors
            #                            # "healthy" = arc shrinks on errors
            # warning-level = 90         # remaining quota % before warning color
            # critical-level = 80        # remaining quota % before critical color
            # show-label = true          # show quota percentage near the icon
            # refresh-interval = 300     # seconds between automatic refreshes (min 15)

            [widgets.default.system-monitor]
            show-icon = false
            use-metric-icons = false
            show-usage-bars = true
            # network-display-mode = "dual-line" # "single" (default) or "dual-line" for stacked upload/download
            metrics-per-column = 2
            layout = "rows"
            dividers = "none"
            metrics = ["cpu", "temperature", "ram", "disk", "gpu", "network"]
            cpu-warning-level = 70   # CPU warning threshold (%)
            cpu-critical-level = 90  # CPU critical threshold (%)
            temperature-warning-level = 80   # Temperature warning threshold (°C)
            temperature-critical-level = 95  # Temperature critical threshold (°C)
            ram-warning-level = 70   # RAM warning threshold (%)
            ram-critical-level = 90  # RAM critical threshold (%)
            disk-warning-level = 80  # Disk warning threshold (%)
            disk-critical-level = 90 # Disk critical threshold (%)
            gpu-warning-level = 70   # GPU warning threshold (%)
            gpu-critical-level = 90  # GPU critical threshold (%)
            # Optional popup customization:
            # [widgets.default.system-monitor.popup]
            # view-variant = "vertical" # vertical, settings
            # metrics = ["cpu", "temperature", "ram", "disk", "gpu", "network"]
            # cpu-details = ["usage", "temperature", "cores", "load-average"]
            # temperature-details = ["cpu", "gpu"]
            # ram-details = ["used", "app", "free", "pressure"]
            # disk-details = ["used", "free", "total"]
            # gpu-details = ["utilization", "temperature"]
            # network-details = ["status", "download", "upload", "interface"]

            [widgets.default.battery]
            show-percentage = true
            warning-level = 30
            critical-level = 10

            [widgets.default.keyboard-layout]
            show-text = true
            show-outline = true

            [widgets.default.focus]
            show-name = false
            tint-with-focus-color = true

            [widgets.default.pomodoro]
            mode = "local" # local, ticktick, auto
            display-mode = "timer" # timer, today-pomodoros
            focus-duration = 25
            short-break-duration = 5
            long-break-duration = 15
            long-break-interval = 4
            show-seconds = false
            play-sound-on-focus-end = true
            play-sound-on-break-end = true
            focus-finished-sound = "pomo-v1.mp3"
            break-finished-sound = "pomo-v2.wav"
            repeat-break-finished-sound-until-popup-opened = false
            break-finished-sound-repeat-interval-seconds = 12
            history-window-days = 180

            [widgets.default.shortcuts]
            # include-folders = ["Work", "Personal"] # show only these folders; use "none" for uncategorized shortcuts
            # exclude-folders = ["Archive"] # ignored when include-folders is set
            # exclude-shortcuts = ["Debug Shortcut", "Temporary Shortcut"]

            [widgets.default.ticktick]
            display-mode = "badge" # badge, rotating-item
            rotating-item-change-interval = 900 # seconds, minimum 5, default 15 minutes
            rotating-item-max-width = 148 # px, minimum 60
            rotating-item-sources = ["tasks", "habits"] # tasks, habits, all
            tint-rotating-item-text = false
            [widgets.default.ticktick.rotating-tasks]
            overdue = true
            today = true
            important = true
            tomorrow = true
            normal = true
            priorities = ["medium", "high"] # low, medium, high

            [widgets.default.time]
            format = "E d, J:mm"
            calendar.format = "J:mm"

            calendar.show-events = true
            # calendar.allow-list = ["Home", "Personal"] # show only these calendars
            # calendar.deny-list = ["Work", "Boss"] # show all calendars except these

            stacked = false
            # Time on top in a larger font, date below in a smaller font.
            # Overrides the default single-line `format` layout.
            # Default: false

            stacked-time-format = "J:mm"
            # Time format used in stacked mode (top line, larger text).
            # Uses Unicode date format patterns.
            # Default: "J:mm"

            stacked-date-format = "E d MMM"
            # Date format used in stacked mode (bottom line, smaller text).
            # Uses Unicode date format patterns.
            # Default: "E d MMM"

            [widgets.default.screen-recording-stop]
            show-label = true

            [popup.default.time]
            view-variant = "box"

            [widgets.default.weather]
            unit = "celsius"  # Options: "celsius" or "fahrenheit" (default: "celsius")
            # latitude = "51.773333"   # Custom latitude (if not provided, uses geolocation)
            # longitude = "52.140278"  # Custom longitude (if not provided, uses geolocation)

            [background]
            enabled = true
            """
        try defaultTOML.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func startWatchingFile(at path: String) {
        stopWatchingFile()
        fileDescriptor = open(path, O_EVTONLY)
        if fileDescriptor == -1 { return }
        logger.debug("Starting config watcher for \(path, privacy: .public)")
        fileWatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor, eventMask: .write,
            queue: DispatchQueue.global())
        fileWatchSource?.setEventHandler { [weak self] in
            guard let self = self, let path = self.configFilePath else {
                return
            }
            guard !self.isPerformingInternalWrite else {
                self.logger.debug("Ignoring watcher event during internal config write")
                return
            }
            self.logger.debug("Watcher noticed config file change")
            self.parseConfigFile(at: path)
        }
        fileWatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
            }
        }
        fileWatchSource?.resume()
    }

    private func stopWatchingFile() {
        if fileWatchSource != nil {
            logger.debug("Stopping config watcher")
        }
        fileWatchSource?.cancel()
        fileWatchSource = nil
        fileDescriptor = -1
    }

    func updateConfigValue(key: String, newValue: String) {
        updateConfigLiteralValue(key: key, newValueLiteral: "\"\(escapedTOMLString(newValue))\"")
    }

    func updateConfigBoolValue(key: String, newValue: Bool) {
        updateConfigLiteralValue(
            key: key,
            newValueLiteral: newValue ? "true" : "false"
        )
    }

    func updateConfigIntValue(key: String, newValue: Int) {
        updateConfigLiteralValue(key: key, newValueLiteral: String(newValue))
    }

    func updateConfigStringArrayValue(key: String, newValue: [String]) {
        let escapedValues = newValue.map { "\"\(escapedTOMLString($0))\"" }
        let literal = "[\(escapedValues.joined(separator: ", "))]"
        updateConfigLiteralValue(key: key, newValueLiteral: literal)
    }

    func updateConfigLiteralValue(key: String, newValueLiteral: String) {
        updateConfigLiteralValue(
            tablePath: nil,
            key: key,
            newValueLiteral: newValueLiteral
        )
    }

    func updateConfigLiteralValue(
        tablePath: String?,
        key: String,
        newValueLiteral: String
    ) {
        guard let path = configFilePath else {
            logger.error("Config file path is not set")
            return
        }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            logger.info(
                "Updating config tablePath=\(tablePath ?? "<root>", privacy: .public) key=\(key, privacy: .public)"
            )
            let updatedText = updatedTOMLString(
                original: currentText,
                tablePath: tablePath,
                key: key,
                newValueLiteral: newValueLiteral
            )

            isPerformingInternalWrite = true
            stopWatchingFile()
            try updatedText.write(
                toFile: path,
                atomically: true,
                encoding: .utf8
            )
            parseConfigFile(at: path)
            startWatchingFile(at: path)
            isPerformingInternalWrite = false
            logger.info("Config update finished for key=\(key, privacy: .public)")
        } catch {
            isPerformingInternalWrite = false
            if let path = configFilePath {
                startWatchingFile(at: path)
            }
            logger.error("Error updating config: \(error.localizedDescription)")
        }
    }

    private func updatedTOMLString(
        original: String,
        tablePath: String?,
        key: String,
        newValueLiteral: String
    ) -> String {
        if let tablePath {
            let tableHeader = "[\(tablePath)]"
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var insideTargetTable = false
            var updatedKey = false
            var foundTable = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    if insideTargetTable && !updatedKey {
                        newLines.append("\(key) = \(newValueLiteral)")
                        updatedKey = true
                    }
                    if trimmed == tableHeader {
                        foundTable = true
                        insideTargetTable = true
                    } else {
                        insideTargetTable = false
                    }
                    newLines.append(line)
                } else {
                    if insideTargetTable && !updatedKey {
                        let pattern =
                            "^\(NSRegularExpression.escapedPattern(for: key))\\s*="
                        if line.range(of: pattern, options: .regularExpression)
                            != nil
                        {
                            newLines.append("\(key) = \(newValueLiteral)")
                            updatedKey = true
                            continue
                        }
                    }
                    newLines.append(line)
                }
            }

            if foundTable && insideTargetTable && !updatedKey {
                newLines.append("\(key) = \(newValueLiteral)")
            }

            if !foundTable {
                newLines.append("")
                newLines.append("[\(tablePath)]")
                newLines.append("\(key) = \(newValueLiteral)")
            }
            return newLines.joined(separator: "\n")
        } else {
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var updatedAtLeastOnce = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("#") {
                    let pattern =
                        "^\(NSRegularExpression.escapedPattern(for: key))\\s*="
                    if line.range(of: pattern, options: .regularExpression)
                        != nil
                    {
                        newLines.append("\(key) = \(newValueLiteral)")
                        updatedAtLeastOnce = true
                        continue
                    }
                }
                newLines.append(line)
            }
            if !updatedAtLeastOnce {
                newLines.append("\(key) = \(newValueLiteral)")
            }
            return newLines.joined(separator: "\n")
        }
    }

    private func publishInitError(_ message: String) {
        publishOnMain {
            self.initError = message
        }
        logger.error("Published initError: \(message, privacy: .public)")
    }

    private func publishOnMain(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.sync {
                update()
            }
        }
    }

    private func nextParseRevision() -> Int {
        parseRevisionQueue.sync {
            latestScheduledParseRevision += 1
            return latestScheduledParseRevision
        }
    }

    private func shouldPublishParseRevision(_ revision: Int) -> Bool {
        parseRevisionQueue.sync {
            revision == latestScheduledParseRevision
        }
    }

    private func currentScheduledParseRevision() -> Int {
        parseRevisionQueue.sync {
            latestScheduledParseRevision
        }
    }

    private func escapedTOMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func globalWidgetConfig(for widgetId: String) -> ConfigData {
        config.rootToml.widgets.config(for: widgetId) ?? [:]
    }

    func displayedWidgets(for monitorID: String) -> [TomlWidgetItem] {
        if let displayConfig = config.rootToml.widgets.displays[monitorID] {
            return displayConfig.displayed
        }

        return config.rootToml.widgets.displayed
    }

    func resolvedWidgetConfig(for item: TomlWidgetItem) -> ConfigData {
        let global = globalWidgetConfig(for: item.id)
        if item.inlineParams.isEmpty {
            return global
        }
        var merged = global
        for (key, value) in item.inlineParams {
            merged[key] = value
        }
        return merged
    }
}
