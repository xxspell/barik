import SwiftUI

struct KeyboardLayoutPopup: View {
    @StateObject private var layoutManager = KeyboardLayoutManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keyboard Layout")
                        .font(.system(size: 16, weight: .semibold))
                    Text(layoutManager.currentSource?.localizedName ?? "Unknown")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }

                Spacer()

                Button {
                    layoutManager.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.8))
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(layoutManager.availableSources) { source in
                        Button {
                            layoutManager.selectInputSource(id: source.id)
                            MenuBarPopup.hide()
                        } label: {
                            KeyboardLayoutRow(source: source)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .frame(width: 260)
        .padding(18)
        .onAppear {
            layoutManager.refresh()
        }
    }
}

private struct KeyboardLayoutRow: View {
    let source: KeyboardInputSource

    var body: some View {
        HStack(spacing: 10) {
            Text(source.shortLabel)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 34, height: 24)
                .background(Color.white.opacity(source.isSelected ? 0.18 : 0.08))
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(source.localizedName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                if let language = source.languages.first {
                    Text(language)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer()

            if source.isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(source.isSelected ? 0.12 : 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    Color.white.opacity(source.isSelected ? 0.18 : 0.06),
                    lineWidth: 1
                )
        }
    }
}

struct KeyboardLayoutPopup_Previews: PreviewProvider {
    static var previews: some View {
        KeyboardLayoutPopup()
            .background(.black)
            .previewLayout(.sizeThatFits)
    }
}
