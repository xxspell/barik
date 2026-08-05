import SwiftUI

/// Single source of truth for the active visual style (default "glass" vs "tui").
/// Read `BarikStyle.current` anywhere (views or plain code). It is cheap to
/// construct and always reflects the live `ConfigManager.shared.config`.
struct BarikStyle {
    static let tuiDefaultHeight: CGFloat = 34
    /// Uniform content height of every widget chip in TUI, so all chips match.
    static let tuiChipHeight: CGFloat = 22
    /// Horizontal padding inside every widget chip in TUI.
    static let tuiChipHPadding: CGFloat = 6

    let isTUI: Bool
    let accent: Color
    let dimOpacity: Double
    let separator: String
    let chipEnabled: Bool
    let chipOpacity: Double
    /// When true, chips use a frosted-glass Material; otherwise a flat translucent fill.
    let chipGlass: Bool
    /// Extra space above the bar content in TUI (points), to push it down from the top edge.
    let tuiTopPadding: CGFloat

    init(config: Config) {
        isTUI = config.style == "tui"
        let tui = config.tui
        accent = Color(hex: tui.accent) ?? .accentColor
        dimOpacity = tui.dim
        separator = tui.separator
        chipEnabled = tui.chip
        chipOpacity = tui.chipOpacity
        chipGlass = tui.chipMaterial.lowercased() != "flat"
        tuiTopPadding = CGFloat(max(tui.topPadding, 0))
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

    /// Fill for a TUI chip's glass/flat background. `isExporting` swaps
    /// `.ultraThinMaterial` for a solid approximation — see
    /// `BarikExportEnvironment.swift` for why.
    func chipFillStyle(isExporting: Bool) -> AnyShapeStyle {
        guard chipGlass else {
            return AnyShapeStyle(foreground.opacity(chipOpacity))
        }
        if isExporting {
            return AnyShapeStyle(Color.black.opacity(0.55))
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }
}
