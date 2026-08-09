import AppKit
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
        accent = Self.accentColor(hex: tui.accent, theme: config.rootToml.theme)
        dimOpacity = tui.dim
        separator = tui.separator
        chipEnabled = tui.chip
        chipOpacity = tui.chipOpacity
        chipGlass = tui.chipMaterial.lowercased() != "flat"
        tuiTopPadding = CGFloat(max(tui.topPadding, 0))
    }

    /// Resolves `tui.accent` to a `Color`, darkening it when the effective
    /// theme is light and the accent is too pale to read against a light
    /// glass background. Dark theme accents are returned unchanged.
    private static func accentColor(hex: String, theme: String?) -> Color {
        guard let base = Color(hex: hex) else { return .accentColor }
        guard resolvedColorScheme(theme: theme) == .light else { return base }

        let nsColor = NSColor(base).usingColorSpace(.deviceRGB) ?? NSColor(base)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        guard luminance > 0.5 else { return base }

        let t = min((luminance - 0.5) / 0.5, 1.0)
        let darkenFactor = t * 0.55

        var h: CGFloat = 0, s: CGFloat = 0, brightness: CGFloat = 0, a2: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &brightness, alpha: &a2)
        let adjusted = NSColor(
            hue: h, saturation: s, brightness: brightness * (1 - darkenFactor), alpha: a2
        )
        return Color(adjusted)
    }

    /// Same resolution rule as `WidgetExporter.resolvedColorScheme()`:
    /// explicit `[root] theme` config wins, otherwise follow the system
    /// appearance.
    private static func resolvedColorScheme(theme: String?) -> ColorScheme {
        switch theme {
        case "dark":
            return .dark
        case "light":
            return .light
        default:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? .dark : .light
        }
    }

    static var current: BarikStyle {
        BarikStyle(config: ConfigManager.shared.config)
    }

    /// Monospaced everywhere in TUI; a custom `font-family` still overrides this
    /// (handled in BarikFontModifier).
    var fontDesign: Font.Design { isTUI ? .monospaced : .default }

    var foreground: Color { Color("TUI Foreground") }
    var dim: Color { foreground.opacity(dimOpacity) }
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
