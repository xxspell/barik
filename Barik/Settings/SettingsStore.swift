import Foundation
import OSLog

struct SettingsFieldKey: Hashable {
    let tablePath: String
    let key: String
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var config: Config

    private let configManager = ConfigManager.shared
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "SettingsStore"
    )

    private init() {
        self.config = configManager.config
    }

    func refresh() {
        config = configManager.config
        logger.debug("refresh() — config snapshot updated")
    }

    func refresh(with config: Config) {
        self.config = config
        logger.debug("refresh(with:) — config snapshot updated from publisher payload")
    }

    func stringValue(
        _ field: SettingsFieldKey,
        fallback: String = ""
    ) -> String {
        configValue(for: field)?.stringValue ?? fallback
    }

    func boolValue(
        _ field: SettingsFieldKey,
        fallback: Bool = false
    ) -> Bool {
        configValue(for: field)?.boolValue ?? fallback
    }

    func intValue(
        _ field: SettingsFieldKey,
        fallback: Int = 0
    ) -> Int {
        configValue(for: field)?.intValue ?? fallback
    }

    func configValueArray(
        _ field: SettingsFieldKey,
        fallback: [String] = []
    ) -> [String] {
        configValue(for: field)?.stringArrayValue ?? fallback
    }

    func setString(_ value: String, for field: SettingsFieldKey) {
        logger.info(
            "setString() — tablePath=\(field.tablePath, privacy: .public) key=\(field.key, privacy: .public)"
        )
        configManager.updateConfigLiteralValue(
            tablePath: field.tablePath,
            key: field.key,
            newValueLiteral: "\"\(escapedTOMLString(value))\""
        )
    }

    func setBool(_ value: Bool, for field: SettingsFieldKey) {
        logger.info(
            "setBool() — tablePath=\(field.tablePath, privacy: .public) key=\(field.key, privacy: .public) value=\(value, privacy: .public)"
        )
        configManager.updateConfigLiteralValue(
            tablePath: field.tablePath,
            key: field.key,
            newValueLiteral: value ? "true" : "false"
        )
    }

    func setInt(_ value: Int, for field: SettingsFieldKey) {
        logger.info(
            "setInt() — tablePath=\(field.tablePath, privacy: .public) key=\(field.key, privacy: .public) value=\(value, privacy: .public)"
        )
        configManager.updateConfigLiteralValue(
            tablePath: field.tablePath,
            key: field.key,
            newValueLiteral: String(value)
        )
    }

    private func configValue(for field: SettingsFieldKey) -> TOMLValue? {
        if field.tablePath.hasPrefix("widgets.") {
            let widgetID = String(field.tablePath.dropFirst("widgets.".count))
            var current: TOMLValue = .dictionary(
                configManager.globalWidgetConfig(for: widgetID)
            )

            for component in field.key.split(separator: ".").map(String.init) {
                guard let dictionary = current.dictionaryValue,
                      let nextValue = dictionary[component] else {
                    return nil
                }
                current = nextValue
            }

            return current
        }

        let components = field.tablePath.split(separator: ".").map(String.init)
        var current: TOMLValue = .dictionary(config.rootToml.widgets.others.mapValues { .dictionary($0) })

        for component in components {
            guard let dictionary = current.dictionaryValue,
                  let nextValue = dictionary[component] else {
                return nil
            }
            current = nextValue
        }

        for component in field.key.split(separator: ".").map(String.init) {
            guard let dictionary = current.dictionaryValue,
                  let nextValue = dictionary[component] else {
                return nil
            }
            current = nextValue
        }

        return current
    }

    private func escapedTOMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
