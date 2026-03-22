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

    private var rotatingItemTextColor: Color {
        guard let item = manager.rotatingBarItem else { return .foregroundOutside }
        let accent = accentColor(for: item)
        return shouldTintRotatingItemText ? accent.opacity(0.92) : .foregroundOutside
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
        shouldShowRotatingItem ? 19 : 28
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
        .foregroundStyle(.foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .experimentalConfiguration(
            horizontalPadding: shouldShowRotatingItem ? 6 : 15,
            cornerRadius: 15
        )
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { widgetFrame = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        widgetFrame = newFrame
                    }
            }
        )
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
        ZStack(alignment: .topTrailing) {
            Image("TickTickIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.foregroundOutside)
                .opacity(manager.isAuthenticated ? 1.0 : 0.6)
                .offset(x: shouldShowRotatingItem ? -2 : 0)

            if manager.isAuthenticated && manager.totalPendingCount > 0 {
                Text("\(min(manager.totalPendingCount, 99))")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .offset(x: shouldShowRotatingItem ? 2 : 6, y: -5)
            }
        }
        .frame(width: iconSlotWidth, height: 20, alignment: .leading)
    }

    private func accentColor(for item: TickTickRotatingBarItem) -> Color {
        switch item.kind {
        case .task(let priority, let overdue):
            if overdue {
                return Color(red: 0.97, green: 0.42, blue: 0.39)
            }
            if priority == .none {
                return .foregroundOutside
            }
            return Color(hex: priority.color) ?? .foregroundOutside
        case .habit:
            return .foregroundOutside
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
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color.opacity(0.9))

            Text(item.title)
                .font(.system(size: 11, weight: .medium))
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
