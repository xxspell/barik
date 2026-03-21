import SwiftUI

private enum FocusWidgetLayout {
    static let badgeSize: CGFloat = 28
    static let iconSize: CGFloat = 14
}

struct FocusWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @StateObject private var focusManager = FocusManager.shared
    @ObservedObject private var configManager = ConfigManager.shared

    @State private var widgetFrame: CGRect = .zero

    private var config: ConfigData { configProvider.config }
    private var tintWithFocusColor: Bool {
        config["tint-with-focus-color"]?.boolValue ?? true
    }

    private var activeMode: FocusMode? { focusManager.activeMode }
    private var foregroundColor: Color {
        guard tintWithFocusColor, let tintColor = activeMode?.tintColor else {
            return .foregroundOutside
        }
        return tintColor.lightened(by: 0.2)
    }

    var body: some View {
        Group {
            if let activeMode {
                Image(systemName: activeMode.resolvedSymbolName)
                    .font(.system(size: FocusWidgetLayout.iconSize, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .frame(
                        width: FocusWidgetLayout.badgeSize,
                        height: FocusWidgetLayout.badgeSize
                    )
                .background(
                    Circle()
                        .fill(configManager.config.experimental.foreground.widgetsBackground.blur)
                )
                .overlay(
                    Circle()
                        .stroke(Color.noActive, lineWidth: 1)
                )
                .shadow(color: .foregroundShadowOutside, radius: 3)
                .background(widgetFrameReader)
                .contentShape(Rectangle())
                .experimentalConfiguration(cornerRadius: 15)
                .frame(maxHeight: .infinity)
                .background(.black.opacity(0.001))
                .onTapGesture {
                    MenuBarPopup.show(rect: widgetFrame, id: "focus") {
                        FocusPopup()
                            .environmentObject(configProvider)
                    }
                }
            }
        }
    }

    private var widgetFrameReader: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { widgetFrame = geometry.frame(in: .global) }
                .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                    widgetFrame = newFrame
                }
        }
    }
}

struct FocusWidget_Previews: PreviewProvider {
    static var previews: some View {
        FocusWidget()
            .environmentObject(
                ConfigProvider(config: [
                    "show-name": .bool(true),
                    "tint-with-focus-color": .bool(true)
                ])
            )
            .frame(width: 240, height: 100)
            .background(.black)
    }
}
