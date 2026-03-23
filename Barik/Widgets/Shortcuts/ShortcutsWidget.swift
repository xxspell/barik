import SwiftUI

struct ShortcutsWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = ShortcutsManager.shared

    @State private var widgetFrame: CGRect = .zero

    var body: some View {
        ZStack {
            if manager.isRunningShortcut {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.foregroundOutside)
                    .rotationEffect(.degrees(manager.isRunningShortcut ? 360 : 0))
                    .animation(
                        .linear(duration: 0.9).repeatForever(autoreverses: false),
                        value: manager.isRunningShortcut
                    )
            } else {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.foregroundOutside)
            }
        }
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
