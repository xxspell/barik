import AppKit
import Foundation
import OSLog
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case displays
    case spaces
    case time
    case weather
    case network
    case nowPlaying
    case cliProxyUsage
    case qwenProxyUsage
    case claudeUsage
    case codexUsage
    case pomodoro
    case ticktick
    case shortcuts
    case systemMonitor
    case other
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return String(localized: "settings.section.general")
        case .appearance:
            return String(localized: "settings.section.appearance")
        case .displays:
            return String(localized: "settings.section.displays")
        case .spaces:
            return String(localized: "settings.section.spaces")
        case .time:
            return String(localized: "settings.section.time")
        case .weather:
            return String(localized: "settings.section.weather")
        case .network:
            return String(localized: "settings.section.network")
        case .nowPlaying:
            return String(localized: "settings.section.now_playing")
        case .cliProxyUsage:
            return String(localized: "settings.section.cli_proxy_usage")
        case .qwenProxyUsage:
            return String(localized: "settings.section.qwen_proxy_usage")
        case .claudeUsage:
            return String(localized: "settings.section.claude_usage")
        case .codexUsage:
            return String(localized: "settings.section.codex_usage")
        case .pomodoro:
            return String(localized: "settings.section.pomodoro")
        case .ticktick:
            return String(localized: "settings.section.ticktick")
        case .shortcuts:
            return String(localized: "settings.section.shortcuts")
        case .systemMonitor:
            return String(localized: "settings.section.system_monitor")
        case .other:
            return String(localized: "settings.section.other")
        case .about:
            return String(localized: "settings.section.about")
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
        case .spaces:
            return "square.3.layers.3d"
        case .time:
            return "clock"
        case .weather:
            return "cloud.sun"
        case .network:
            return "wifi"
        case .nowPlaying:
            return "music.note"
        case .cliProxyUsage:
            return "server.rack"
        case .qwenProxyUsage:
            return "q.circle"
        case .claudeUsage:
            return "c.circle"
        case .codexUsage:
            return "chevron.left.forwardslash.chevron.right"
        case .pomodoro:
            return "timer"
        case .ticktick:
            return "checklist"
        case .shortcuts:
            return "square.stack.3d.up"
        case .systemMonitor:
            return "menubar.dock.rectangle"
        case .other:
            return "square.grid.2x2"
        case .about:
            return "info.circle"
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
