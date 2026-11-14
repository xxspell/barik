import SwiftUI

struct AgentsWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = AgentsManager.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var widgetFrame: CGRect = .zero
    @State private var reduceMotion = false

    private var style: BarikStyle { BarikStyle.current }

    private var agentsConfig: AgentsConfig { AgentsConfig(config: configProvider.config) }

    private var isDisconnected: Bool {
        if case .disconnected = manager.connection { return true }
        return false
    }

    private var amber: Color { AgentsPalette.amber(tui: style.isTUI, light: colorScheme == .light) }
    private var green: Color { AgentsPalette.green(tui: style.isTUI, light: colorScheme == .light) }
    private var textColor: Color { style.isTUI ? style.foreground : .foregroundOutside }
    private var dimColor: Color { style.isTUI ? style.dim : Color.foregroundOutside.opacity(0.5) }

    var body: some View {
        content
            .trackingReduceMotion($reduceMotion)
            .onAppear { startManager() }
            .onChange(of: agentsConfig) { _, _ in startManager() }
    }

    private func startManager() {
        manager.start(config: agentsConfig)
    }

    @ViewBuilder
    private var content: some View {
        let showIdle = manager.config.showWhenIdle
        if isDisconnected {
            if showIdle {
                chip(blocked: false) { disconnectedIcon }
                    .help(String(localized: "agents.widget.not_running"))
            }
        } else {
            switch manager.summary.chipState {
            case .idle:
                if showIdle { chip(blocked: false) { idleIcon } }
            case let .needsYou(primary, extra, working, done):
                chip(blocked: true) { needsYouRow(primary, extra, working, done) }
            case let .active(working, done, since):
                chip(blocked: false) { activeRow(working, done, since) }
            }
        }
    }

    // MARK: Rows

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

    private func needsYouRow(_ primary: AgentSession, _ extra: Int, _ working: Int, _ done: Int) -> some View {
        HStack(spacing: 5) {
            AgentStatusIcon(status: .blocked, size: 13)
            AgentKindIcon(kind: primary.kind, size: 12)
            Text(primary.projectName)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 110, alignment: .leading)
                .foregroundStyle(amber)
            if extra > 0 {
                Text("+\(extra)").foregroundStyle(amber.opacity(0.85))
            }
            if working > 0 || done > 0 {
                divider
                counters(working: working, done: done)
            }
        }
        .barikFont(size: 12, weight: .medium, design: style.fontDesign)
    }

    @ViewBuilder
    private var divider: some View {
        if style.isTUI {
            Text("│").foregroundStyle(dimColor)
        } else {
            Color.clear.frame(width: 4, height: 1)
        }
    }

    private func counters(working: Int, done: Int) -> some View {
        HStack(spacing: 6) {
            if working > 0 {
                HStack(spacing: 3) {
                    AgentStatusIcon(status: .working, size: 13)
                    Text("\(working)").foregroundStyle(textColor)
                }
            }
            if done > 0 {
                HStack(spacing: 3) {
                    AgentStatusIcon(status: .done, size: 13)
                    Text("\(done)").foregroundStyle(green)
                }
            }
        }
    }

    private func activeRow(_ working: Int, _ done: Int, _ since: Date?) -> some View {
        HStack(spacing: 6) {
            if working > 0 {
                HStack(spacing: 3) {
                    AgentStatusIcon(status: .working, size: 13)
                    Text("\(working)").foregroundStyle(textColor)
                    if manager.config.showElapsed, let since {
                        // Ticks every 30 s; the label is minute-granular beyond the first minute.
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("· \(AgentTimeFormat.short(context.date.timeIntervalSince(since)))")
                                .foregroundStyle(dimColor)
                        }
                    }
                }
            }
            if done > 0 {
                HStack(spacing: 3) {
                    AgentStatusIcon(status: .done, size: 13)
                    Text("\(done)").foregroundStyle(green)
                }
            }
        }
        .barikFont(size: 12, weight: .medium, design: style.fontDesign)
    }

    // MARK: Chip

    private func chip<Inner: View>(blocked: Bool, @ViewBuilder _ inner: () -> Inner) -> some View {
        inner()
            .fixedSize()
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.summary.chipState)
            .experimentalConfiguration(cornerRadius: 15)
            .overlay { if blocked { glow } }
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.001))
            .captureScreenRect(into: $widgetFrame)
            .contentShape(Rectangle())
            .onChange(of: widgetFrame) { _, rect in AgentsChipRegistry.shared.update(rect: rect) }
            .onAppear { AgentsChipRegistry.shared.update(rect: widgetFrame) }
            .onDisappear { AgentsChipRegistry.shared.remove(rect: widgetFrame) }
            .onTapGesture {
                MenuBarPopup.show(rect: widgetFrame, id: "agents") {
                    // Placeholder until the agents popup lands.
                    Text(String(localized: "agents.widget.title"))
                        .barikFont(size: 13, weight: .semibold, design: BarikStyle.current.fontDesign)
                        .foregroundStyle(BarikStyle.current.isTUI ? BarikStyle.current.foreground : Color.foregroundOutside)
                        .padding(16)
                }
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
