import SwiftUI

private struct ExperimentalConfigurationModifier: ViewModifier {
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    
    let horizontalPadding: CGFloat
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        let style = BarikStyle.current

        if style.isTUI {
            return AnyView(tuiBody(content: content, style: style))
        }

        return AnyView(defaultBody(content: content))
    }

    @ViewBuilder
    private func tuiBody(content: Content, style: BarikStyle) -> some View {
        if style.chipEnabled {
            content
                .frame(height: BarikStyle.tuiChipHeight)
                .padding(.horizontal, BarikStyle.tuiChipHPadding)
                .background(
                    RoundedRectangle(cornerRadius: style.chipCornerRadius, style: .continuous)
                        .fill(style.chipGlass
                            ? AnyShapeStyle(.ultraThinMaterial)
                            : AnyShapeStyle(style.foreground.opacity(style.chipOpacity)))
                )
        } else {
            content
                .frame(height: BarikStyle.tuiChipHeight)
        }
    }

    @ViewBuilder
    private func defaultBody(content: Content) -> some View {
        Group {
            if !configManager.config.experimental.foreground.widgetsBackground.displayed {
                content
            } else {
                content
                    .frame(height: foregroundHeight < 45 ? 30 : 38)
                    .padding(.horizontal, foregroundHeight < 45 && horizontalPadding != 15 ? 0 :
                                foregroundHeight < 30 ? 0 : horizontalPadding
                    )
                    .background(configManager.config.experimental.foreground.widgetsBackground.blur)
                    .cornerRadius(foregroundHeight < 30 ? 0 : cornerRadius)
                    .overlay(
                        foregroundHeight < 30 ? nil :
                            Capsule().stroke(Color.noActive, lineWidth: 1)
                    )
            }
        }.scaleEffect(foregroundHeight < 25 ? 0.9 : 1, anchor: .leading)
    }
}

extension View {
    func experimentalConfiguration(
        horizontalPadding: CGFloat = 15,
        cornerRadius: CGFloat
    ) -> some View {
        self.modifier(ExperimentalConfigurationModifier(
            horizontalPadding: horizontalPadding,
            cornerRadius: cornerRadius
        ))
    }
}
