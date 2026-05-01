import AppKit
import SwiftUI

enum BarikFontCatalog {
    static func availableFamilies() -> [String] {
        let managerFamilies = NSFontManager.shared.availableFontFamilies
        return Array(Set(managerFamilies))
            .sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
    }
}

enum BarikSemanticFontStyle {
    case body
    case headline
    case subheadline
    case caption
    case caption2
    case title2
    case callout

    var size: CGFloat {
        switch self {
        case .body:
            return 13
        case .headline:
            return 13
        case .subheadline:
            return 12
        case .caption:
            return 11
        case .caption2:
            return 10
        case .title2:
            return 22
        case .callout:
            return 16
        }
    }

    var defaultWeight: Font.Weight {
        switch self {
        case .body:
            return .regular
        case .headline:
            return .semibold
        case .subheadline:
            return .regular
        case .caption:
            return .regular
        case .caption2:
            return .regular
        case .title2:
            return .regular
        case .callout:
            return .regular
        }
    }
}

enum BarikFontScope {
    case menuBar
    case popup
}

private struct BarikFontModifier: ViewModifier {
    @ObservedObject private var configManager = ConfigManager.shared

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let scope: BarikFontScope

    func body(content: Content) -> some View {
        content.font(resolvedFont)
    }

    private var resolvedFont: Font {
        guard shouldUseCustomFont else {
            return .system(size: size, weight: weight, design: design)
        }

        return .custom(resolvedFamily, size: size).weight(weight)
    }

    private var shouldUseCustomFont: Bool {
        switch scope {
        case .menuBar:
            return !resolvedFamily.isEmpty
        case .popup:
            return !resolvedFamily.isEmpty && configManager.config.experimental.foreground.applyFontToPopups
        }
    }

    private var resolvedFamily: String {
        guard
            let family = configManager.config.experimental.foreground.fontFamily?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !family.isEmpty
        else {
            return ""
        }

        return family
    }
}

extension View {
    func barikFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        scope: BarikFontScope = .menuBar
    ) -> some View {
        modifier(BarikFontModifier(size: size, weight: weight, design: design, scope: scope))
    }

    func barikTextStyle(
        _ style: BarikSemanticFontStyle,
        weightOverride: Font.Weight? = nil,
        design: Font.Design = .default,
        scope: BarikFontScope = .menuBar
    ) -> some View {
        modifier(
            BarikFontModifier(
                size: style.size,
                weight: weightOverride ?? style.defaultWeight,
                design: design,
                scope: scope
            )
        )
    }

    func barikPopupFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        barikFont(size: size, weight: weight, design: design, scope: .popup)
    }

    func barikPopupTextStyle(
        _ style: BarikSemanticFontStyle,
        weightOverride: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> some View {
        barikTextStyle(style, weightOverride: weightOverride, design: design, scope: .popup)
    }
}
