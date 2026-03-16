import AppKit
import Foundation

final class SystemUIHelper {
    static func openWeatherApp() {
        guard let weatherURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.weather"
        ) else {
            if let fallback = URL(
                string: "x-apple.systempreferences:com.apple.preference.datetime"
            ) {
                NSWorkspace.shared.open(fallback)
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: weatherURL,
            configuration: configuration,
            completionHandler: nil
        )
    }
}