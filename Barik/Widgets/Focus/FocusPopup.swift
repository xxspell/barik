import SwiftUI

struct FocusPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @StateObject private var focusManager = FocusManager.shared

    private var config: ConfigData { configProvider.config }
    private var tintWithFocusColor: Bool {
        config["tint-with-focus-color"]?.boolValue ?? true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            noticeBanner

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(focusManager.modes) { mode in
                        FocusModeRow(
                            mode: mode,
                            tintWithFocusColor: tintWithFocusColor
                        )
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 300)
        .padding(18)
        .onAppear {
            focusManager.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Focus")
                    .font(.system(size: 16, weight: .semibold))

                if let activeMode = focusManager.activeMode {
                    HStack(spacing: 6) {
                        Image(systemName: activeMode.resolvedSymbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                tintWithFocusColor
                                    ? ((activeMode.tintColor ?? .white).lightened(by: 0.2))
                                    : .white
                            )

                        Text(activeMode.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                } else {
                    Text("No active Focus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            Button {
                focusManager.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var noticeBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus modes are read-only for now.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            Text("Barik currently shows which Focus modes exist and which one is active, but it does not switch them yet.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct FocusModeRow: View {
    let mode: FocusMode
    let tintWithFocusColor: Bool

    private var tintColor: Color {
        guard tintWithFocusColor else { return .white }
        return (mode.tintColor ?? .white).lightened(by: 0.2)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mode.resolvedSymbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tintColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(mode.id)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)
            }

            Spacer()

            if mode.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(mode.isActive ? 0.12 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color.white.opacity(mode.isActive ? 0.18 : 0.06),
                    lineWidth: 1
                )
        }
    }
}

struct FocusPopup_Previews: PreviewProvider {
    static var previews: some View {
        FocusPopup()
            .environmentObject(
                ConfigProvider(config: [
                    "show-name": .bool(true),
                    "tint-with-focus-color": .bool(true)
                ])
            )
            .background(.black)
            .previewLayout(.sizeThatFits)
    }
}
