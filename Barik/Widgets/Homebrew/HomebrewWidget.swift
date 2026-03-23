import SwiftUI

struct HomebrewWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = HomebrewManager.shared
    @State private var rect: CGRect = .zero

    // display-mode: "label" (default) | "icon" | "badge"
    private var displayMode: String {
        configProvider.config["display-mode"]?.stringValue ?? "label"
    }

    var body: some View {
        ZStack {
            switch displayMode {
            case "badge":
                badgeContent
            case "icon":
                iconOnlyContent
            default:
                labelContent
            }
        }
        .captureScreenRect(into: $rect)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "homebrew") {
                HomebrewPopup(manager: manager)
            }
        }
    }

    // MARK: - Mode: label (icon + count side by side)

    private var labelContent: some View {
        HStack(spacing: 5) {
            brewIcon(size: 15)

            if manager.isUpdating {
                updatingSpinner(size: 11)
            } else {
                Text(manager.outdatedCount == 0 ? "✓" : "\(manager.outdatedCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(countColor)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: manager.outdatedCount)
            }
        }
    }

    // MARK: - Mode: icon (icon only)

    private var iconOnlyContent: some View {
        brewIcon(size: 15)
    }

    // MARK: - Mode: badge (icon with small pill badge at bottom-right)

    private var badgeContent: some View {
        ZStack(alignment: .bottomTrailing) {
            brewIcon(size: 16, badgeMode: true)

            if manager.isUpdating {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 2.5)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(x: 6, y: 4)
                    .rotationEffect(.degrees(manager.isUpdating ? 360 : 0))
                    .animation(
                        .linear(duration: 1).repeatForever(autoreverses: false),
                        value: manager.isUpdating
                    )
            } else if manager.outdatedCount > 0 {
                Text("\(manager.outdatedCount)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 2.5)
                    .padding(.vertical, 1)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(x: 6, y: 4)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.smooth, value: manager.outdatedCount)
            }
        }
        .padding(.trailing, manager.outdatedCount > 0 ? 4 : 0)
        .animation(.smooth, value: manager.outdatedCount > 0)
    }

    // MARK: - Shared subviews

    private func brewIcon(size: CGFloat, badgeMode: Bool = false) -> some View {
        Image(systemName: "shippingbox.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(badgeMode ? Color.foregroundOutside : iconColor)
    }

    private func updatingSpinner(size: CGFloat) -> some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.foregroundOutside)
            .rotationEffect(.degrees(manager.isUpdating ? 360 : 0))
            .animation(
                .linear(duration: 1).repeatForever(autoreverses: false),
                value: manager.isUpdating
            )
    }

    // MARK: - Colors

    private var iconColor: Color {
        manager.outdatedCount > 0 ? .orange : .foregroundOutside
    }

    private var countColor: Color {
        manager.outdatedCount > 0 ? .orange : .foregroundOutside
    }
}

struct HomebrewWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            HomebrewWidget()
        }.frame(width: 200, height: 100)
            .background(.yellow)
            .environmentObject(ConfigProvider(config: [:]))
    }
}
