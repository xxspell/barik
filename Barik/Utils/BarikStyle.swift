import SwiftUI

/// Single source of truth for the active visual style (default "glass" vs "tui").
/// Read `BarikStyle.current` anywhere (views or plain code). It is cheap to
/// construct and always reflects the live `ConfigManager.shared.config`.
struct BarikStyle {
    static let tuiDefaultHeight: CGFloat = 34

    let isTUI: Bool
    let accent: Color
    let dimOpacity: Double
    let separator: String
    let chipEnabled: Bool
    let chipOpacity: Double

    init(config: Config) {
        isTUI = config.style == "tui"
        let tui = config.tui
        accent = Color(hex: tui.accent) ?? .accentColor
        dimOpacity = tui.dim
        separator = tui.separator
        chipEnabled = tui.chip
        chipOpacity = tui.chipOpacity
    }

    static var current: BarikStyle {
        BarikStyle(config: ConfigManager.shared.config)
    }

    /// Monospaced everywhere in TUI; a custom `font-family` still overrides this
    /// (handled in BarikFontModifier).
    var fontDesign: Font.Design { isTUI ? .monospaced : .default }

    var foreground: Color { Color.foregroundOutside }
    var dim: Color { Color.foregroundOutside.opacity(dimOpacity) }
    var chipCornerRadius: CGFloat { 8 }
}
