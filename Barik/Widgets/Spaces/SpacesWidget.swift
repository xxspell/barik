import AppKit
import SwiftUI

private extension NSScreen {
    static func spacesHoverTarget(for rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)

        if let containing = screens.first(where: { $0.frame.contains(center) }) {
            return containing
        }

        return screens.min { lhs, rhs in
            lhs.spacesHoverDistance(to: center) < rhs.spacesHoverDistance(to: center)
        }
    }

    func spacesHoverDistance(to point: CGPoint) -> CGFloat {
        let dx: CGFloat
        if point.x < frame.minX {
            dx = frame.minX - point.x
        } else if point.x > frame.maxX {
            dx = point.x - frame.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < frame.minY {
            dy = frame.minY - point.y
        } else if point.y > frame.maxY {
            dy = point.y - frame.maxY
        } else {
            dy = 0
        }

        return hypot(dx, dy)
    }
}

struct SpacesWidget: View {
    @ObservedObject var viewModel = SpacesViewModel.shared

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {
        HStack(spacing: foregroundHeight < 30 ? 0 : 8) {
            ForEach(viewModel.spaces) { space in
                SpaceView(space: space)
            }
        }
        .experimentalConfiguration(horizontalPadding: 5, cornerRadius: 10)
        .animation(.smooth(duration: 0.3), value: viewModel.spaces)
        .foregroundStyle(Color.foreground)
        .environmentObject(viewModel)
    }
}

/// This view shows a space with its windows.
private struct SpaceView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @EnvironmentObject var viewModel: SpacesViewModel

    var config: ConfigData { configProvider.config }
    var spaceConfig: ConfigData { config["space"]?.dictionaryValue ?? [:] }

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var showKey: Bool { spaceConfig["show-key"]?.boolValue ?? true }

    let space: AnySpace

    @State var isHovered = false

    var body: some View {
        let isFocused = space.windows.contains { $0.isFocused } || space.isFocused
        HStack(spacing: 0) {
            Spacer().frame(width: 10)
            if showKey {
                Text(space.id)
                    .font(.headline)
                    .frame(minWidth: 15)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer().frame(width: 5)
            }
            HStack(spacing: 2) {
                ForEach(space.windows) { window in
                    WindowView(window: window, space: space)
                }
            }
            Spacer().frame(width: 10)
        }
        .frame(height: 30)
        .background(
            foregroundHeight < 30 ?
            (isFocused
             ? Color.noActive
             : Color.clear) :
                (isFocused
                 ? Color.active
                 : isHovered ? Color.noActive : Color.noActive)
        )
        .clipShape(RoundedRectangle(cornerRadius: foregroundHeight < 30 ? 0 : 8, style: .continuous))
        .shadow(color: .shadow, radius: foregroundHeight < 30 ? 0 : 2)
        .transition(.blurReplace)
        .onTapGesture {
            viewModel.switchToSpace(space, needWindowFocus: true)
        }
        .animation(.smooth, value: isHovered)
        .onHover { value in
            isHovered = value
        }
    }
}

/// This view shows a window and its icon.
private struct WindowView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @EnvironmentObject var viewModel: SpacesViewModel

    var config: ConfigData { configProvider.config }
    var windowConfig: ConfigData { config["window"]?.dictionaryValue ?? [:] }
    var titleConfig: ConfigData {
        windowConfig["title"]?.dictionaryValue ?? [:]
    }

    var showTitle: Bool { windowConfig["show-title"]?.boolValue ?? true }
    var showHiddenWindows: Bool { windowConfig["show-hidden"]?.boolValue ?? false }
    var showHoverTooltip: Bool { windowConfig["show-hover-tooltip"]?.boolValue ?? false }
    var hoverTooltipTemplate: String {
        windowConfig["hover-tooltip"]?.stringValue ?? "{app} ({pid})"
    }
    var iconDesaturationPercent: Double {
        let rawValue = windowConfig["icon-desaturation"]?.intValue ?? 0
        return Double(min(max(rawValue, 0), 100))
    }
    var maxLength: Int { titleConfig["max-length"]?.intValue ?? 50 }
    var alwaysDisplayAppTitleFor: [String] { titleConfig["always-display-app-name-for"]?.arrayValue?.filter({ $0.stringValue != nil }).map { $0.stringValue! } ?? [] }

    let window: AnyWindow
    let space: AnySpace

    @State var isHovered = false
    @State private var iconFrame: CGRect = .zero

    var body: some View {
        let titleMaxLength = maxLength
        let size: CGFloat = 21
        let sameAppCount = space.windows.filter { $0.appName == window.appName }
            .count
        let title = sameAppCount > 1 && !alwaysDisplayAppTitleFor.contains { $0 == window.appName } ? window.title : (window.appName ?? "")
        let spaceIsFocused = space.windows.contains { $0.isFocused }
        HStack {
            ZStack {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: size, height: size)
                        .shadow(
                            color: .iconShadow,
                            radius: 2
                        )
                } else {
                    Image(systemName: "questionmark.circle")
                        .resizable()
                        .frame(width: size, height: size)
                }
            }
            .background(ScreenRectReader(screenRect: $iconFrame))
            .overlay(alignment: .topTrailing) {
                if showHiddenWindows && window.isHidden {
                    HiddenWindowBadge()
                        .offset(x: 2, y: -2)
                }
            }
            .saturation(iconSaturation)
            .opacity(iconOpacity(spaceIsFocused: spaceIsFocused))
            .transition(.blurReplace)

            if window.isFocused, !title.isEmpty, showTitle {
                HStack {
                    Text(
                        title.count > titleMaxLength
                            ? String(title.prefix(titleMaxLength)) + "..."
                            : title
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .shadow(color: .foregroundShadow, radius: 3)
                    .fontWeight(.semibold)
                    Spacer().frame(width: 5)
                }
                .transition(.blurReplace)
            }
        }
        .padding(.all, 2)
        .background(isHovered || (!showTitle && window.isFocused) ? .selected : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.smooth, value: isHovered)
        .frame(height: 30)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.switchToSpace(space)
            usleep(100_000)
            viewModel.switchToWindow(window)
        }
        .onHover { value in
            isHovered = value
            if value {
                HoverCardPanelController.shared.show(
                    anchorRect: iconFrame,
                    text: hoverTooltipText
                )
            } else {
                HoverCardPanelController.shared.hide()
            }
        }
    }
}

private extension WindowView {
    func iconOpacity(spaceIsFocused: Bool) -> Double {
        var opacity = spaceIsFocused && !window.isFocused ? 0.5 : 1
        if window.isHidden {
            opacity *= 0.72
        }
        return opacity
    }

    var iconSaturation: Double {
        let normalizedDesaturation = iconDesaturationPercent / 100.0
        return max(0, 1.0 - pow(normalizedDesaturation, 2))
    }

    var hoverTooltipText: String {
        guard showHoverTooltip else { return "" }

        let replacements: [String: String] = [
            "{app}": window.appName ?? "",
            "{title}": window.title,
            "{pid}": window.pid.map(String.init) ?? "",
            "{id}": String(window.id),
            "{state}": window.isHidden ? "hidden" : "visible",
        ]

        let text = replacements.reduce(into: hoverTooltipTemplate) { partial, entry in
            partial = partial.replacingOccurrences(of: entry.key, with: entry.value)
        }

        return text
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: "()", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct HiddenWindowBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 10, height: 10)

            Image(systemName: "minus")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
        }
        .shadow(color: .black.opacity(0.18), radius: 1)
    }
}

private struct ScreenRectReader: NSViewRepresentable {
    @Binding var screenRect: CGRect

    func makeNSView(context: Context) -> TrackingRectView {
        let view = TrackingRectView()
        view.onScreenRectChange = { rect in
            if screenRect != rect {
                screenRect = rect
            }
        }
        return view
    }

    func updateNSView(_ nsView: TrackingRectView, context: Context) {
        nsView.onScreenRectChange = { rect in
            if screenRect != rect {
                screenRect = rect
            }
        }
        nsView.reportRectIfPossible()
    }
}

private final class TrackingRectView: NSView {
    var onScreenRectChange: ((CGRect) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportRectIfPossible()
    }

    override func layout() {
        super.layout()
        reportRectIfPossible()
    }

    func reportRectIfPossible() {
        guard let window else { return }
        let localRect = convert(bounds, to: nil)
        let screenRect = window.convertToScreen(localRect)
        onScreenRectChange?(screenRect)
    }
}

private struct HoverTooltipBubble: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(text.components(separatedBy: "\n"), id: \.self) { line in
                Text(line)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.22, green: 0.23, blue: 0.25).opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        .fixedSize(horizontal: true, vertical: true)
        .allowsHitTesting(false)
    }
}

private final class HoverCardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class HoverCardPanelController {
    static let shared = HoverCardPanelController()

    private let panel: HoverCardPanel
    private var hideWorkItem: DispatchWorkItem?
    private let horizontalPadding: CGFloat = 12
    private let verticalOffset: CGFloat = 8

    private init() {
        panel = HoverCardPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
    }

    func show(anchorRect: CGRect, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let screen = NSScreen.spacesHoverTarget(for: anchorRect) else {
            hide()
            return
        }

        hideWorkItem?.cancel()

        let rootView = HoverTooltipBubble(text: trimmed)
        let hostingView = NSHostingView(rootView: rootView)
        let size = hostingView.fittingSize

        let screenFrame = screen.frame
        let anchorMidX = anchorRect.midX
        let desiredX = anchorMidX - size.width / 2
        let minX = screenFrame.minX + horizontalPadding
        let maxX = screenFrame.maxX - size.width - horizontalPadding
        let x = min(max(desiredX, minX), maxX)
        let y = max(screenFrame.minY + horizontalPadding, anchorRect.minY - size.height - verticalOffset)

        panel.setContentSize(size)
        panel.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: true)
        panel.contentView = hostingView
        panel.orderFrontRegardless()
    }

    func hide(after delay: TimeInterval = 0.04) {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
