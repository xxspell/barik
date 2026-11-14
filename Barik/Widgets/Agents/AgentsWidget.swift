import SwiftUI

/// Render-only: AppDelegate starts/stops `AgentsManager` depending on whether the widget is displayed.
struct AgentsWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = AgentsManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var widgetFrame: CGRect = .zero
    @State private var reduceMotion = false

    private var style: BarikStyle { BarikStyle.current }

    private var isDisconnected: Bool {
        if case .disconnected = manager.connection { return true }
        return false
    }

    private var amber: Color { AgentsPalette.amber(tui: style.isTUI, light: colorScheme == .light) }
    private var green: Color { AgentsPalette.green(tui: style.isTUI, light: colorScheme == .light) }
    private var textColor: Color { style.isTUI ? style.foreground : .foregroundOutside }
    private var dimColor: Color { style.isTUI ? style.dim : Color.foregroundOutside.opacity(0.5) }

    /// Hidden renders nothing at all, so the bar's HStack adds no spacing for it.
    var body: some View {
        if isVisible {
            chip.trackingReduceMotion($reduceMotion)
        }
    }

    // MARK: State

    private enum Mode { case hidden, idle, disconnected, active }

    private var mode: Mode {
        guard manager.isStarted else { return .hidden }
        let showIdle = manager.config.showWhenIdle
        if isDisconnected { return showIdle ? .disconnected : .hidden }
        if case .idle = manager.summary.chipState { return showIdle ? .idle : .hidden }
        return .active
    }

    private var isVisible: Bool { mode != .hidden }

    private struct Parts {
        var primary: AgentSession?
        var extra = 0
        var working = 0
        var done = 0
        var since: Date?
    }

    private var parts: Parts {
        switch manager.summary.chipState {
        case .idle: return Parts()
        case let .needsYou(p, extra, w, d): return Parts(primary: p, extra: extra, working: w, done: d)
        case let .active(w, d, since): return Parts(working: w, done: d, since: since)
        }
    }

    // MARK: Chip

    /// One stable container for every state: only the inner conditional pieces come and go, so the
    /// chip's width and background interpolate instead of swapping views.
    private var chip: some View {
        let mode = self.mode
        let p = parts
        let blocked = p.primary != nil
        let anim: Animation? = reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)
        let pieceTransition: AnyTransition = reduceMotion
            ? .identity : .opacity.combined(with: .scale(scale: 0.8))

        return HStack(spacing: 5) {
            if mode == .idle { idleIcon.transition(pieceTransition) }
            if mode == .disconnected { disconnectedIcon.transition(pieceTransition) }
            if let primary = p.primary {
                HStack(spacing: 5) {
                    AgentStatusIcon(status: .blocked, size: 13)
                    AgentKindIcon(kind: primary.kind, size: 12)
                    Text(primary.projectName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 80, alignment: .leading)
                        .foregroundStyle(amber)
                    if p.extra > 0 {
                        Text("+\(p.extra)").foregroundStyle(amber.opacity(0.85))
                    }
                }
                .transition(pieceTransition)
                if p.working > 0 || p.done > 0 { divider.transition(pieceTransition) }
            }
            if p.working > 0 {
                HStack(spacing: 3) {
                    AgentStatusIcon(status: .working, size: 13)
                    Text("\(p.working)")
                        .contentTransition(.numericText())
                        .foregroundStyle(textColor)
                    if !blocked, manager.config.showElapsed, let since = p.since {
                        // Minute-granular only: seconds ("0s", "30s") are noise in the bar,
                        // so nothing is shown during the first minute.
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            let elapsed = context.date.timeIntervalSince(since)
                            if elapsed >= 60 {
                                Text(verbatim: "· \(AgentTimeFormat.short(elapsed))")
                                    .foregroundStyle(dimColor)
                            }
                        }
                    }
                }
                .transition(pieceTransition)
            }
            if p.done > 0 {
                HStack(spacing: 3) {
                    AgentStatusIcon(status: .done, size: 13)
                    Text("\(p.done)")
                        .contentTransition(.numericText())
                        .foregroundStyle(green)
                }
                .transition(pieceTransition)
            }
        }
        .barikFont(size: 12, weight: .medium, design: style.fontDesign)
        .experimentalConfiguration(cornerRadius: 15)
        .overlay { if blocked { glow } }
        .frame(maxHeight: .infinity)
        .animation(anim, value: manager.summary.chipState)
        .animation(anim, value: mode)
        .background(.black.opacity(0.001))
        .captureScreenRect(into: $widgetFrame)
        .contentShape(Rectangle())
        .help(mode == .disconnected ? String(localized: "agents.widget.not_running") : "")
        .onChange(of: widgetFrame) { _, rect in AgentsChipRegistry.shared.update(rect: rect) }
        .onAppear { AgentsChipRegistry.shared.update(rect: widgetFrame) }
        .onDisappear { AgentsChipRegistry.shared.remove(rect: widgetFrame) }
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "agents") {
                AgentsPopup()
                    .environmentObject(configProvider)
            }
        }
    }

    private var idleIcon: some View {
        Image(systemName: "apple.terminal")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(dimColor)
    }

    private var disconnectedIcon: some View {
        idleIcon
            .overlay {
                Rectangle()
                    .fill(dimColor)
                    .frame(width: 1.4, height: 17)
                    .rotationEffect(.degrees(45))
            }
    }

    @ViewBuilder
    private var divider: some View {
        if style.isTUI {
            Text("│").foregroundStyle(dimColor)
        } else {
            Color.clear.frame(width: 4, height: 1)
        }
    }

    /// Amber glow around the chip while an agent needs the user.
    @ViewBuilder
    private var glow: some View {
        let radius: CGFloat = style.isTUI ? style.chipCornerRadius : 15
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceMotion {
            shape.stroke(amber.opacity(0.5), lineWidth: 1)
                .shadow(color: amber.opacity(0.5), radius: 4)
                .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (sin(t * 2 * .pi / 1.8) + 1) / 2
                shape.stroke(amber.opacity(0.35 + 0.3 * phase), lineWidth: 1)
                    .shadow(color: amber.opacity(0.35 + 0.35 * phase), radius: 3 + 4 * phase)
            }
            .allowsHitTesting(false)
        }
    }
}
