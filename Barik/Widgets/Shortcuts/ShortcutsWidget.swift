import SwiftUI

struct ShortcutsWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = ShortcutsManager.shared

    @State private var widgetFrame: CGRect = .zero

    private var isTUI: Bool { BarikStyle.current.isTUI }
    /// Slightly smaller icon in TUI so it matches the weight of monospaced text.
    private var iconSize: CGFloat { isTUI ? 12 : 15 }
    /// The filled stack glyph sits below its optical center; nudge it up in TUI.
    private var iconVerticalOffset: CGFloat { isTUI ? -1 : 0 }

    var body: some View {
        ZStack {
            if manager.isRunningShortcut {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .barikFont(size: iconSize, weight: .semibold)
                    .foregroundStyle(.foregroundOutside)
                    .rotationEffect(.degrees(manager.isRunningShortcut ? 360 : 0))
                    .animation(
                        .linear(duration: 0.9).repeatForever(autoreverses: false),
                        value: manager.isRunningShortcut
                    )
            } else {
                Image(systemName: "square.stack.3d.up.fill")
                    .barikFont(size: iconSize, weight: .semibold)
                    .foregroundStyle(.foregroundOutside)
            }
        }
        .offset(y: iconVerticalOffset)
        .frame(width: 18, height: 18)
        .padding(.horizontal, 1)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .captureScreenRect(into: $widgetFrame)
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "shortcuts") {
                ShortcutsPopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            manager.startUpdating(config: configProvider.config)
        }
        .onReceive(configProvider.$config) { config in
            manager.updateConfiguration(config: config)
        }
    }
}

struct ShortcutsWidget_Previews: PreviewProvider {
    static var previews: some View {
        ShortcutsWidget()
            .environmentObject(ConfigProvider(config: [:]))
            .frame(width: 120, height: 60)
            .background(.black)
    }
}
