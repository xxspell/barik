import AppKit
import Foundation
import OSLog
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case displays
    case time
    case weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .appearance:
            return "Appearance"
        case .displays:
            return "Displays"
        case .time:
            return "Time"
        case .weather:
            return "Weather"
        }
    }

    var iconName: String {
        switch self {
        case .general:
            return "gearshape"
        case .appearance:
            return "paintbrush"
        case .displays:
            return "display.2"
        case .time:
            return "clock"
        case .weather:
            return "cloud.sun"
        }
    }
}

@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "SettingsRouter"
    )

    @Published var selectedSection: SettingsSection = .time

    private init() {}

    func select(_ section: SettingsSection) {
        logger.info("select() — section=\(section.rawValue, privacy: .public)")
        selectedSection = section
    }
}

struct RoutedSettingsLink<Label: View>: View {
    let section: SettingsSection
    @ViewBuilder let label: () -> Label

    var body: some View {
        SettingsLink {
            label()
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                SettingsRouter.shared.select(section)
                NSApp.activate(ignoringOtherApps: true)
            }
        )
    }
}
