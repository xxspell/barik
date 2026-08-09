import SwiftUI

struct KeyboardLayoutWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @StateObject private var layoutManager = KeyboardLayoutManager.shared

    private var config: ConfigData { configProvider.config }
    private var showText: Bool { config["show-text"]?.boolValue ?? true }
    private var showOutline: Bool { config["show-outline"]?.boolValue ?? true }

    @State private var rect: CGRect = .zero

    private var textColor: Color {
        BarikStyle.current.isTUI ? BarikStyle.current.foreground : .foregroundOutside
    }

    var body: some View {
        Group {
            if showText {
                labelView
            } else {
                Image(systemName: "globe")
                    .barikFont(size: 14, weight: .semibold)
                    .foregroundStyle(textColor)
            }
        }
        .padding(.horizontal, BarikStyle.current.isTUI ? 0 : (showOutline ? (showText ? 8 : 2) : 0))
        .padding(.vertical, showText && !BarikStyle.current.isTUI ? 3 : 0)
        .background(
            Group {
                if showOutline && !BarikStyle.current.isTUI {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                }
            }
        )
        .overlay(
            Group {
                if showOutline && !BarikStyle.current.isTUI {
                    Capsule()
                        .stroke(Color.noActive, lineWidth: 1)
                }
            }
        )
        .captureScreenRect(into: $rect)
        .contentShape(Rectangle())
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "keyboard-layout") {
                KeyboardLayoutPopup()
            }
        }
    }

    private var labelView: some View {
        Text(layoutManager.currentSource?.shortLabel ?? "--")
            .barikFont(size: 12, weight: .semibold, design: .rounded)
            .foregroundStyle(textColor)
            .monospaced()
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct KeyboardLayoutWidget_Previews: PreviewProvider {
    static var previews: some View {
        KeyboardLayoutWidget()
            .environmentObject(ConfigProvider(config: [:]))
            .frame(width: 200, height: 100)
            .background(.black)
    }
}
