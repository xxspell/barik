import SwiftUI

/// Window-related settings that the TUI spaces views read from the
/// `[widgets.default.spaces]` table — the same keys the default style uses.
struct TUISpacesWindowSettings {
    var showTitle = true
    var titleMaxLength = 50
    var alwaysAppNameFor: [String] = []
    var showHidden = false
    var showTooltip = false
    var tooltipTemplate = "{app} ({pid})"

    init(config: ConfigData) {
        let window = config["window"]?.dictionaryValue ?? [:]
        let title = window["title"]?.dictionaryValue ?? [:]
        showTitle = window["show-title"]?.boolValue ?? true
        titleMaxLength = max(title["max-length"]?.intValue ?? 50, 2)
        alwaysAppNameFor = title["always-display-app-name-for"]?.arrayValue?.compactMap(\.stringValue) ?? []
        showHidden = window["show-hidden"]?.boolValue ?? false
        showTooltip = window["show-hover-tooltip"]?.boolValue ?? false
        tooltipTemplate = window["hover-tooltip"]?.stringValue ?? "{app} ({pid})"
    }
}

/// Text-only rendition of the spaces widget for `style = "tui"`.
/// Mirrors the default style's settings: display mode, visual style,
/// outline, space key, delete button and the window options.
struct TUISpacesView: View {
    @EnvironmentObject var configProvider: ConfigProvider

    let spaces: [AnySpace]
    let focusedSpace: AnySpace?
    let displayMode: SpacesDisplayMode
    let visualStyle: SpacesVisualStyle
    let showOutline: Bool

    private var spaceConfig: ConfigData { configProvider.config["space"]?.dictionaryValue ?? [:] }
    private var showKey: Bool { spaceConfig["show-key"]?.boolValue ?? true }
    private var showDeleteButton: Bool { spaceConfig["show-delete-button"]?.boolValue ?? true }

    var body: some View {
        let windowSettings = TUISpacesWindowSettings(config: configProvider.config)
        let shape = TUISpacesShape(visualStyle: visualStyle)

        switch displayMode {
        case .classic:
            HStack(spacing: 4) {
                ForEach(spaces) { space in
                    TUISpaceGroup(
                        space: space,
                        showKey: showKey,
                        showDeleteButton: showDeleteButton,
                        showOutline: showOutline,
                        shape: shape,
                        windowSettings: windowSettings
                    )
                }
            }
        case .focusedStrip:
            HStack(spacing: 6) {
                TUISpaceNumberStrip(
                    spaces: spaces,
                    focusedSpaceID: focusedSpace?.id,
                    showDeleteButton: showDeleteButton,
                    showOutline: showOutline,
                    shape: shape
                )

                if let focusedSpace, !focusedSpace.windows.isEmpty {
                    Text("│")
                        .barikFont(size: 12)
                        .foregroundStyle(BarikStyle.current.dim)

                    HStack(spacing: 8) {
                        ForEach(focusedSpace.windows) { window in
                            TUIWindowLabel(window: window, space: focusedSpace, settings: windowSettings)
                        }
                    }
                }
            }
        }
    }
}

/// Shape used for the active highlight and the outline:
/// `standard` → small rounded rect, `rounded` → capsule.
struct TUISpacesShape: Shape {
    let visualStyle: SpacesVisualStyle

    func path(in rect: CGRect) -> Path {
        switch visualStyle {
        case .rounded:
            return Capsule().path(in: rect)
        case .standard:
            return RoundedRectangle(cornerRadius: 4, style: .continuous).path(in: rect)
        }
    }
}

private enum TUISpacesMetrics {
    static let itemHeight: CGFloat = 18
    static let itemHPadding: CGFloat = 5
    static let highlightOpacity: Double = 0.18
    static let outlineOpacity: Double = 0.25
    static let inactiveWindowOpacity: Double = 0.6
    static let hiddenWindowOpacity: Double = 0.35
    static let inactiveWindowMaxLength = 12
}

private extension View {
    /// Active-highlight fill and optional outline shared by space groups and numbers.
    func tuiSpaceChrome(isActive: Bool, showOutline: Bool, shape: TUISpacesShape) -> some View {
        let style = BarikStyle.current
        return self
            .padding(.horizontal, TUISpacesMetrics.itemHPadding)
            .frame(height: TUISpacesMetrics.itemHeight)
            .background(
                shape.fill(isActive ? style.accent.opacity(TUISpacesMetrics.highlightOpacity) : .clear)
            )
            .overlay {
                if showOutline {
                    shape.stroke(style.foreground.opacity(TUISpacesMetrics.outlineOpacity), lineWidth: 1)
                }
            }
            .contentShape(shape)
    }
}

/// Classic mode: one space = optional number + its window labels.
private struct TUISpaceGroup: View {
    @EnvironmentObject var viewModel: SpacesViewModel

    let space: AnySpace
    let showKey: Bool
    let showDeleteButton: Bool
    let showOutline: Bool
    let shape: TUISpacesShape
    let windowSettings: TUISpacesWindowSettings

    @State private var isHovered = false

    var body: some View {
        let style = BarikStyle.current
        HStack(spacing: 6) {
            if showKey {
                TUISpaceNumber(space: space)
            }

            ForEach(space.windows) { window in
                TUIWindowLabel(window: window, space: space, settings: windowSettings)
            }

            // Keep a keyless empty space visible and clickable.
            if !showKey && space.windows.isEmpty {
                Text("·")
                    .barikFont(size: 12, weight: .bold)
                    .foregroundStyle(space.isFocused ? style.accent : style.dim)
            }

            if showsDelete {
                TUIDeleteButton(space: space)
            }
        }
        .tuiSpaceChrome(isActive: space.isFocused, showOutline: showOutline, shape: shape)
        .onTapGesture {
            viewModel.switchToSpace(space, needWindowFocus: true)
        }
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.2), value: isHovered)
    }

    private var showsDelete: Bool {
        isHovered && showDeleteButton && space.windows.isEmpty
            && space.supportsDeletion && viewModel.canDeleteSpace(space)
    }
}

/// Focused-strip mode: the row of space numbers, wrapped in one outline.
private struct TUISpaceNumberStrip: View {
    let spaces: [AnySpace]
    let focusedSpaceID: String?
    let showDeleteButton: Bool
    let showOutline: Bool
    let shape: TUISpacesShape

    var body: some View {
        HStack(spacing: 1) {
            ForEach(spaces) { space in
                TUIStripItem(
                    space: space,
                    isActive: space.id == focusedSpaceID,
                    showDeleteButton: showDeleteButton,
                    shape: shape
                )
            }
        }
        .padding(.horizontal, 1)
        .frame(height: TUISpacesMetrics.itemHeight + 2)
        .overlay {
            if showOutline {
                shape.stroke(BarikStyle.current.foreground.opacity(TUISpacesMetrics.outlineOpacity), lineWidth: 1)
            }
        }
    }
}

private struct TUIStripItem: View {
    @EnvironmentObject var viewModel: SpacesViewModel

    let space: AnySpace
    let isActive: Bool
    let showDeleteButton: Bool
    let shape: TUISpacesShape

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 3) {
            TUISpaceNumber(space: space, isActive: isActive)
            if showsDelete {
                TUIDeleteButton(space: space)
            }
        }
        .tuiSpaceChrome(isActive: isActive, showOutline: false, shape: shape)
        .onTapGesture {
            viewModel.switchToSpace(space, needWindowFocus: true)
        }
        .onHover { isHovered = $0 }
        .animation(.smooth(duration: 0.2), value: isHovered)
    }

    private var showsDelete: Bool {
        isHovered && showDeleteButton && space.windows.isEmpty
            && space.supportsDeletion && viewModel.canDeleteSpace(space)
    }
}

private struct TUISpaceNumber: View {
    let space: AnySpace
    var isActive: Bool?

    var body: some View {
        let style = BarikStyle.current
        let active = isActive ?? space.isFocused
        Text(space.id)
            .barikFont(size: 12, weight: active ? .bold : .regular)
            .foregroundStyle(active ? style.accent : style.dim)
            .fixedSize()
    }
}

private struct TUIDeleteButton: View {
    @EnvironmentObject var viewModel: SpacesViewModel
    let space: AnySpace

    var body: some View {
        Button {
            viewModel.deleteSpace(space)
        } label: {
            Text("×")
                .barikFont(size: 12, weight: .bold)
                .foregroundStyle(BarikStyle.current.foreground)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }
}

/// One window as text. The focused window is accented and shows its title
/// (when `show-title` is on); others show a short app name.
private struct TUIWindowLabel: View {
    @EnvironmentObject var viewModel: SpacesViewModel

    let window: AnyWindow
    let space: AnySpace
    let settings: TUISpacesWindowSettings

    @State private var frame: CGRect = .zero

    var body: some View {
        let style = BarikStyle.current
        let isHiddenMarked = settings.showHidden && window.isHidden
        Text(label)
            .italic(isHiddenMarked)
            .barikFont(size: 12, weight: window.isFocused ? .semibold : .regular)
            .foregroundStyle(window.isFocused ? style.accent : style.foreground)
            .opacity(opacity(isHiddenMarked: isHiddenMarked))
            .lineLimit(1)
            .fixedSize()
            .background {
                if settings.showTooltip {
                    Color.clear.captureScreenRect(into: $frame)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.switchToSpace(space)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    viewModel.switchToWindow(window)
                }
            }
            .onHover { hovering in
                guard settings.showTooltip else { return }
                if hovering {
                    HoverCardPanelController.shared.show(
                        anchorRect: frame,
                        text: spacesTooltipText(for: window, template: settings.tooltipTemplate)
                    )
                } else {
                    HoverCardPanelController.shared.hide()
                }
            }
    }

    private var label: String {
        let appName = window.appName?.isEmpty == false ? window.appName! : window.title
        // TUI always shows the app name (there are no icons), so `show-title`
        // swaps the focused window's label for its real window title, unless
        // the app is listed in `always-display-app-name-for`.
        if window.isFocused && settings.showTitle && !window.title.isEmpty
            && !settings.alwaysAppNameFor.contains(where: { $0 == window.appName }) {
            return truncate(window.title, to: settings.titleMaxLength)
        }
        let maxLength = window.isFocused ? settings.titleMaxLength : TUISpacesMetrics.inactiveWindowMaxLength
        return truncate(appName, to: maxLength)
    }

    private func opacity(isHiddenMarked: Bool) -> Double {
        if isHiddenMarked { return TUISpacesMetrics.hiddenWindowOpacity }
        return window.isFocused ? 1 : TUISpacesMetrics.inactiveWindowOpacity
    }

    private func truncate(_ text: String, to maxLength: Int) -> String {
        text.count > maxLength ? String(text.prefix(maxLength - 1)) + "…" : text
    }
}
