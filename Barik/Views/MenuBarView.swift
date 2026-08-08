import SwiftUI

struct MenuBarView: View {
    let monitor: MonitorDescriptor

    @ObservedObject var configManager = ConfigManager.shared
    @ObservedObject private var editModeState = BarEditModeState.shared
    @StateObject private var screenRecordingManager = ScreenRecordingManager.shared
    private var horizontalPadding: CGFloat {
        configManager.config.experimental.foreground.horizontalPadding
    }
    private var notchZonePadding: CGFloat {
        configManager.config.experimental.foreground.notchHorizontalPadding
    }

    /// Widgets with a dedicated TUI branch that manage their own palette.
    /// They opt out of the monochrome net so the accent survives.
    private static let tuiHandTunedWidgetIDs: Set<String> = [
        "default.spaces",
        "default.network",
        "default.battery",
        "default.time",
        "default.nowplaying",
        "default.system-monitor",
        "default.cpuram",
        "default.screen-recording-stop",
    ]

    private var widgetSpacing: CGFloat {
        BarikStyle.current.isTUI ? 8 : configManager.config.experimental.foreground.spacing
    }

    var body: some View {
        let theme: ColorScheme? =
            switch configManager.config.rootToml.theme {
            case "dark":
                .dark
            case "light":
                .light
            default:
                .none
            }

        let items = configManager.displayedWidgets(for: monitor.id)

        Group {
            if usesNotchAwareLayout {
                notchAwareLayout(items: items)
            } else {
                standardLayout(items: items)
            }
        }
        .foregroundStyle(Color.foregroundOutside)
        .frame(height: max(configManager.config.experimental.foreground.resolveHeight(), 1.0))
        .frame(maxWidth: .infinity)
        .padding(.top, BarikStyle.current.isTUI ? BarikStyle.current.tuiTopPadding : 0)
        .padding(.horizontal, usesNotchAwareLayout ? 0 : horizontalPadding)
        .background(.black.opacity(0.001))
        .preferredColorScheme(theme)
        .onAppear {
            requestScreenRecordingAccessibilityPermissionIfNeeded(for: items)
        }
        .onChange(of: items.map(\.id)) { _, newItemIDs in
            requestScreenRecordingAccessibilityPermissionIfNeeded(for: newItemIDs)
        }
    }

    private var usesNotchAwareLayout: Bool {
        monitor.hasTopInsetCutout && itemsContainSpacerForSplit
    }

    private var itemsContainSpacerForSplit: Bool {
        configManager
            .displayedWidgets(for: monitor.id)
            .contains(where: { $0.id == "spacer" })
    }

    @ViewBuilder
    private func standardLayout(items: [TomlWidgetItem]) -> some View {
        HStack(spacing: 0) {
            widgetRow(items)
                .padding(.horizontal, horizontalPadding)

            if !items.contains(where: { $0.id == "system-banner" }) {
                SystemBannerWidget(withLeftPadding: true)
                    .padding(.trailing, horizontalPadding)
            }
        }
    }

    @ViewBuilder
    private func notchAwareLayout(items: [TomlWidgetItem]) -> some View {
        let split = splitItemsForNotch(items)
        let rightItems = split.rightItems + trailingSystemBannerItems(from: items)

        HStack(spacing: 0) {
            widgetRow(split.leftItems)
                .padding(.leading, notchZonePadding)
                .frame(
                    width: max(monitor.auxiliaryTopLeftArea.width, 0),
                    alignment: .leading
                )

            Spacer(minLength: max(monitor.notchGapWidth, 0))
                .frame(maxWidth: max(monitor.notchGapWidth, 0))

            widgetRow(
                rightItems,
                baseIndex: split.leftItems.count + 1,
                editableCount: split.rightItems.count,
                alignment: .trailing
            )
                .padding(.trailing, notchZonePadding)
                .frame(
                    width: max(monitor.auxiliaryTopRightArea.width, 0),
                    alignment: .trailing
                )
        }
    }

    @ViewBuilder
    private func widgetRow(
        _ items: [TomlWidgetItem],
        baseIndex: Int = 0,
        editableCount: Int? = nil,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        let editableUpperBound = editableCount ?? items.count
        HStack(spacing: widgetSpacing) {
            ForEach(0..<items.count, id: \.self) { offset in
                let item = items[offset]
                let content = buildView(for: item)
                    .modifier(TUIMonochromeNet(
                        handTuned: MenuBarView.tuiHandTunedWidgetIDs.contains(item.id)
                    ))

                if editModeState.isActive && offset < editableUpperBound {
                    EditableWidgetSlot(
                        monitor: monitor,
                        index: baseIndex + offset,
                        widgetID: item.id
                    ) {
                        content
                    }
                } else {
                    content
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func splitItemsForNotch(_ items: [TomlWidgetItem]) -> (leftItems: [TomlWidgetItem], rightItems: [TomlWidgetItem]) {
        guard let spacerIndex = items.firstIndex(where: { $0.id == "spacer" }) else {
            return (items, [])
        }

        let leftItems = Array(items[..<spacerIndex])
        let rightStart = items.index(after: spacerIndex)
        let rightItems = rightStart < items.endIndex
            ? Array(items[rightStart...])
            : []

        return (leftItems, rightItems)
    }

    private func trailingSystemBannerItems(from items: [TomlWidgetItem]) -> [TomlWidgetItem] {
        guard !items.contains(where: { $0.id == "system-banner" }) else {
            return []
        }

        return [TomlWidgetItem(id: "system-banner", inlineParams: [:])]
    }

    @ViewBuilder
    private func buildView(for item: TomlWidgetItem) -> some View {
        WidgetViewFactory.build(
            for: item,
            configManager: configManager,
            monitor: monitor,
            screenRecordingManager: screenRecordingManager
        )
    }

    private func requestScreenRecordingAccessibilityPermissionIfNeeded(for items: [TomlWidgetItem]) {
        requestScreenRecordingAccessibilityPermissionIfNeeded(for: items.map(\.id))
    }

    private func requestScreenRecordingAccessibilityPermissionIfNeeded(for itemIDs: [String]) {
        guard itemIDs.contains("default.screen-recording-stop") else { return }
        screenRecordingManager.requestAccessibilityPermissionIfNeeded()
    }
}

private struct EditableWidgetSlot<Content: View>: View {
    let monitor: MonitorDescriptor
    let index: Int
    let widgetID: String
    let content: () -> Content

    @State private var isHovering = false

    init(
        monitor: MonitorDescriptor,
        index: Int,
        widgetID: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.monitor = monitor
        self.index = index
        self.widgetID = widgetID
        self.content = content
    }

    var body: some View {
        content()
            .allowsHitTesting(false)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.foregroundOutside.opacity(isHovering ? 0.85 : 0.5),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.foregroundOutside.opacity(isHovering ? 0.12 : 0))
            )
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button {
                        BarWidgetLayoutStore.removeWidget(at: index, for: monitor)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

/// Retired: `.saturation(0)` rasterizes the subtree and breaks the frosted-glass
/// chip Material. Widgets are now made monochrome per-widget (on their content,
/// not their chip), so this is a no-op kept only to avoid touching call sites.
private struct TUIMonochromeNet: ViewModifier {
    let handTuned: Bool

    func body(content: Content) -> some View {
        content
    }
}
