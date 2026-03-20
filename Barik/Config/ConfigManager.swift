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
                initError = "Error creating default config: \(error.localizedDescription)"
                logger.error("Error creating default config: \(error.localizedDescription)")
                return
            }
        }

        if let path = chosenPath {
            configFilePath = path
            parseConfigFile(at: path)
            startWatchingFile(at: path)
        }
    }

    private func parseConfigFile(at path: String) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let decoder = TOMLDecoder()
            let rootToml = try decoder.decode(RootToml.self, from: content)
            DispatchQueue.main.async {
                self.config = Config(rootToml: rootToml)
            }
        } catch {
            initError = "Error parsing TOML file: \(error.localizedDescription)"
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

            [widgets.default.spaces]
            space.show-key = true        # show space number (or character, if you use AeroSpace)
            window.show-title = true
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

            [widgets.default.battery]
            show-percentage = true
            warning-level = 30
            critical-level = 10

            [widgets.default.keyboard-layout]
            show-text = true
            show-outline = true

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
        fileDescriptor = open(path, O_EVTONLY)
        if fileDescriptor == -1 { return }
        fileWatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor, eventMask: .write,
            queue: DispatchQueue.global())
        fileWatchSource?.setEventHandler { [weak self] in
            guard let self = self, let path = self.configFilePath else {
                return
            }
            self.parseConfigFile(at: path)
        }
        fileWatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
            }
        }
        fileWatchSource?.resume()
    }

    func updateConfigValue(key: String, newValue: String) {
        guard let path = configFilePath else {
            logger.error("Config file path is not set")
            return
        }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            let updatedText = updatedTOMLString(
                original: currentText, key: key, newValue: newValue)
            try updatedText.write(
                toFile: path, atomically: false, encoding: .utf8)
            DispatchQueue.main.async {
                self.parseConfigFile(at: path)
            }
        } catch {
            logger.error("Error updating config: \(error.localizedDescription)")
        }
    }

    private func updatedTOMLString(
        original: String, key: String, newValue: String
    ) -> String {
        if key.contains(".") {
            let components = key.split(separator: ".").map(String.init)
            guard components.count >= 2 else {
                return original
            }

            let tablePath = components.dropLast().joined(separator: ".")
            let actualKey = components.last!

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
                        newLines.append("\(actualKey) = \"\(newValue)\"")
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
                            "^\(NSRegularExpression.escapedPattern(for: actualKey))\\s*="
                        if line.range(of: pattern, options: .regularExpression)
                            != nil
                        {
                            newLines.append("\(actualKey) = \"\(newValue)\"")
                            updatedKey = true
                            continue
                        }
                    }
                    newLines.append(line)
                }
            }

            if foundTable && insideTargetTable && !updatedKey {
                newLines.append("\(actualKey) = \"\(newValue)\"")
            }

            if !foundTable {
                newLines.append("")
                newLines.append("[\(tablePath)]")
                newLines.append("\(actualKey) = \"\(newValue)\"")
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
                        newLines.append("\(key) = \"\(newValue)\"")
                        updatedAtLeastOnce = true
                        continue
                    }
                }
                newLines.append(line)
            }
            if !updatedAtLeastOnce {
                newLines.append("\(key) = \"\(newValue)\"")
            }
            return newLines.joined(separator: "\n")
        }
    }

    func globalWidgetConfig(for widgetId: String) -> ConfigData {
        config.rootToml.widgets.config(for: widgetId) ?? [:]
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
