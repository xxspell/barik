import SwiftUI

struct TickTickWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = TickTickManager.shared

    @State private var widgetFrame: CGRect = .zero

    private enum DisplayMode: String {
        case badge
        case rotatingItem = "rotating-item"
    }

    private var displayMode: DisplayMode {
        DisplayMode(rawValue: configProvider.config["display-mode"]?.stringValue?.lowercased() ?? "badge") ?? .badge
    }

    private var outsideTextColor: Color {
        BarikStyle.current.isTUI ? BarikStyle.current.foreground : .foregroundOutside
    }

    private var rotatingItemTextColor: Color {
        guard let item = manager.rotatingBarItem else { return outsideTextColor }
        let accent = accentColor(for: item)
        return shouldTintRotatingItemText ? accent.opacity(0.92) : outsideTextColor
    }

    private var shouldTintRotatingItemText: Bool {
        configProvider.config["tint-rotating-item-text"]?.boolValue ?? false
    }

    private var shouldShowRotatingItem: Bool {
        displayMode == .rotatingItem && manager.rotatingBarItem != nil
    }

    private var rotatingItemMaxWidth: CGFloat {
        CGFloat(max(configProvider.config["rotating-item-max-width"]?.intValue ?? 148, 60))
    }

    private var iconSlotWidth: CGFloat {
        shouldShowRotatingItem ? 19 : (BarikStyle.current.isTUI ? 22 : 28)
    }

    var body: some View {
        Group {
            if shouldShowRotatingItem, let item = manager.rotatingBarItem {
                rotatingItemBar(for: item)
            } else {
                defaultBadgeBar
            }
        }
        .padding(.horizontal, shouldShowRotatingItem ? 0 : 1)
        .foregroundStyle(outsideTextColor)
        .shadow(color: .foregroundShadowOutside, radius: BarikStyle.current.isTUI ? 0 : 3)
        .experimentalConfiguration(
            horizontalPadding: shouldShowRotatingItem ? 6 : 15,
            cornerRadius: 15
        )
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .captureScreenRect(into: $widgetFrame)
        .animation(.smooth(duration: 0.22), value: shouldShowRotatingItem)
        .animation(.smooth(duration: 0.22), value: manager.rotatingBarItem?.transitionID ?? 0)
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "ticktick") {
                TickTickPopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            manager.startUpdating(config: configProvider.config)
        }
        .onReceive(configProvider.$config) { config in
            manager.updateWidgetConfiguration(config: config)
        }
    }

    private var defaultBadgeBar: some View {
        HStack(spacing: 0) {
            iconWithBadge
        }
    }

    private func rotatingItemBar(for item: TickTickRotatingBarItem) -> some View {
        HStack(spacing: 4) {
            iconWithBadge

            RotatingTickTickText(
                item: item,
                color: rotatingItemTextColor,
                maxWidth: rotatingItemMaxWidth
            )
                .layoutPriority(1)
                .transition(.tickTickRevealFromIcon)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            manager.preparePopupFocus(for: item)
            MenuBarPopup.show(rect: widgetFrame, id: "ticktick") {
                TickTickPopup()
                    .environmentObject(configProvider)
            }
        }
    }

    private var iconWithBadge: some View {
        let tui = BarikStyle.current.isTUI
        return HStack(spacing: tui ? 4 : 0) {
            ZStack(alignment: .topTrailing) {
                Image("TickTickIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: tui ? 14 : 16, height: tui ? 14 : 16)
                    .foregroundStyle(outsideTextColor)
                    .opacity(manager.isAuthenticated ? 1.0 : 0.6)
                    .offset(x: shouldShowRotatingItem ? -2 : 0)

                if !tui && manager.isAuthenticated && manager.totalPendingCount > 0 {
                    Text("\(min(manager.totalPendingCount, 99))")
                        .barikFont(size: 8, weight: .bold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .offset(x: shouldShowRotatingItem ? 2 : 6, y: -5)
                }
            }
            .frame(width: tui ? 16 : iconSlotWidth, height: 20, alignment: .leading)

            if tui && manager.isAuthenticated && manager.totalPendingCount > 0 {
                Text("\(min(manager.totalPendingCount, 99))")
                    .barikFont(size: 12, weight: .semibold)
                    .foregroundStyle(outsideTextColor)
            }
        }
    }

    private func accentColor(for item: TickTickRotatingBarItem) -> Color {
        switch item.kind {
        case .task(let priority, let overdue):
            if overdue {
                return Color(red: 0.97, green: 0.42, blue: 0.39)
            }
            if priority == .none {
                return outsideTextColor
            }
            return Color(hex: priority.color) ?? outsideTextColor
        case .habit:
            return outsideTextColor
        }
    }
}

private extension AnyTransition {
    static var tickTickRevealFromIcon: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: TickTickRevealModifier(progress: 0),
                identity: TickTickRevealModifier(progress: 1)
            ),
            removal: .modifier(
                active: TickTickRevealModifier(progress: 0),
                identity: TickTickRevealModifier(progress: 1)
            )
        )
    }
}

private struct TickTickRevealModifier: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: max(progress, 0.001), y: 1, anchor: .leading)
            .opacity(progress)
            .clipped()
    }
}

private struct RotatingTickTickText: View {
    let item: TickTickRotatingBarItem
    let color: Color
    let maxWidth: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: item.sourceIconName)
                .barikFont(size: 9, weight: .semibold)
                .foregroundStyle(color.opacity(0.9))

            Text(item.title)
                .barikFont(size: 11, weight: .medium)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
        .id(item.transitionID)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, 1)
    }
}
