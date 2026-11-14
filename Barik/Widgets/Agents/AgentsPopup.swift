import AppKit
import SwiftUI

// MARK: - Live wrapper

/// Popup opened from the agents chip: lists herdr agents grouped by status or project.
struct AgentsPopup: View {
    @ObservedObject private var manager = AgentsManager.shared
    @State private var previews: [String: [String]] = [:]
    /// The panel is only ordered out on close (the hosting view stays alive), so visibility comes from
    /// the popup's show/hide notifications rather than onAppear/onDisappear.
    @State private var visible = true

    var body: some View {
        AgentsPopupContent(
            summary: manager.summary,
            connection: manager.connection,
            herdrVersion: manager.herdrVersion,
            herdrAppAvailable: manager.herdrAppAvailable,
            groupBy: manager.config.groupBy,
            previewLines: manager.config.previewLines,
            previews: previews,
            active: visible,
            onFocus: { agent in
                manager.focus(agent)
                MenuBarPopup.hide()
            },
            onOpenHerdr: { manager.openHerdr() }
        )
        // Hidden, the tree stays mounted but static: no spinner/pulse TimelineViews keep ticking.
        .agentAnimationsPaused(!visible)
        .onAppear {
            visible = true
            manager.refreshHerdrAppAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: .willShowWindow)) { _ in
            visible = true
            manager.refreshHerdrAppAvailability()
        }
        .onReceive(NotificationCenter.default.publisher(for: .willHideWindow)) { _ in visible = false }
        // Re-keyed on visibility: the loop is cancelled as soon as the popup hides, so nothing polls in the background.
        .task(id: visible) {
            guard visible else { return }
            await refreshPreviewsWhileVisible()
        }
    }

    private func refreshPreviewsWhileVisible() async {
        guard manager.config.previewLines > 0 else { return }
        while !Task.isCancelled {
            let blocked = manager.summary.blocked
            var fresh: [String: [String]] = [:]
            for agent in blocked {
                let lines = await manager.preview(paneID: agent.paneID)
                if Task.isCancelled { return }
                fresh[agent.paneID] = lines
            }
            previews = fresh
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}

// MARK: - Content

struct AgentsPopupContent: View {
    let summary: AgentsSummary
    let connection: AgentsConnectionState
    let herdrVersion: String?
    var herdrAppAvailable = true
    let groupBy: String
    let previewLines: Int
    let previews: [String: [String]]
    /// False while the popup is hidden: timers stop ticking.
    var active = true
    var onFocus: (AgentSession) -> Void = { _ in }
    var onOpenHerdr: () -> Void = {}
    var startExpandedIdle = false

    @State private var idleExpanded = false

    private var style: BarikStyle { BarikStyle.current }
    private var tui: Bool { style.isTUI }
    private var design: Font.Design { style.fontDesign }
    private var amber: Color { AgentsPalette.amber(tui: tui, light: false) }
    private var green: Color { AgentsPalette.green(tui: tui, light: false) }
    private var fg: Color { tui ? style.foreground : .white }
    private var dim: Color { tui ? style.dim : Color.white.opacity(0.5) }
    private var accent: Color { tui ? style.accent : .white }
    private let divider = Color.white.opacity(0.2)

    private var isDisconnected: Bool {
        if case .disconnected = connection { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(divider)
            if case let .fallbackPolling(reason) = connection {
                fallbackBanner(reason)
                Divider().background(divider)
            }
            if isDisconnected {
                disconnectedState
            } else if summary.total == 0 {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if groupBy == "project" { projectGroups } else { statusSections }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: 400)
                .fixedSize(horizontal: false, vertical: true)
            }
            Divider().background(divider)
            footer
        }
        .frame(width: 320)
        .frame(maxHeight: 520)
        .background(Color.black)
        .foregroundStyle(fg)
        // Always black: status icons must use their dark-theme palette.
        .environment(\.colorScheme, .dark)
        .onAppear { if startExpandedIdle { idleExpanded = true } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(String(localized: "agents.widget.title"))
                .barikPopupFont(size: 14, weight: .semibold, design: design)
            RoutedSettingsLink(section: .agents) {
                Image(systemName: "gearshape.fill")
                    .barikPopupFont(size: 11, weight: .semibold)
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            Spacer()
            if !isDisconnected {
                if !summary.blocked.isEmpty { pill(.blocked, summary.blocked.count, amber) }
                if !summary.working.isEmpty { pill(.working, summary.working.count, accent) }
                if !summary.done.isEmpty { pill(.done, summary.done.count, green) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func pill(_ status: AgentStatus, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            AgentStatusIcon(status: status, size: 10)
                .frame(width: 12, height: 12)
            Text("\(count)")
        }
        .barikPopupFont(size: 10.5, weight: .medium, design: design)
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Banners and empty states

    private func fallbackBanner(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
            Text(String(format: String(localized: "agents.popup.fallback"), reason))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .barikPopupFont(size: 11, design: design)
        .foregroundStyle(amber)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(amber.opacity(0.10))
    }

    private var disconnectedState: some View {
        VStack(spacing: 10) {
            ZStack {
                Image(systemName: "apple.terminal")
                    .font(.system(size: 26, weight: .semibold))
                Rectangle().frame(width: 2, height: 36).rotationEffect(.degrees(45))
            }
            .foregroundStyle(dim)
            Text(String(localized: "agents.widget.not_running"))
                .barikPopupFont(size: 12, design: design)
                .foregroundStyle(dim)
            if herdrAppAvailable {
                Button(action: onOpenHerdr) {
                    Text(String(localized: "agents.popup.open_herdr"))
                        .barikPopupFont(size: 11.5, weight: .medium, design: design)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            } else {
                Text(String(localized: "agents.popup.install_herdr"))
                    .barikPopupFont(size: 11, design: design)
                    .foregroundStyle(dim)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var emptyState: some View {
        Text(String(localized: isConnecting ? "agents.popup.connecting" : "agents.popup.empty"))
            .barikPopupFont(size: 12, design: design)
            .foregroundStyle(dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    private var isConnecting: Bool {
        if case .connecting = connection { return true }
        return false
    }

    // MARK: Status grouping

    @ViewBuilder
    private var statusSections: some View {
        if !summary.blocked.isEmpty {
            sectionTitle(String(localized: "agents.popup.section.needs_you"))
            ForEach(summary.blocked) { statusRow($0) }
        }
        if !summary.working.isEmpty {
            sectionTitle(String(localized: "agents.popup.section.working"))
            ForEach(summary.working) { statusRow($0) }
        }
        if !summary.done.isEmpty {
            sectionTitle(String(localized: "agents.popup.section.done"))
            ForEach(summary.done) { statusRow($0) }
        }
        if !summary.idle.isEmpty {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { idleExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(idleExpanded ? 90 : 0))
                    Text(String(format: String(localized: "agents.popup.section.idle"), summary.idle.count))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .barikPopupFont(size: 10, weight: .semibold, design: design)
            .textCase(.uppercase)
            .foregroundStyle(fg.opacity(0.45))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            if idleExpanded {
                ForEach(summary.idle) { statusRow($0) }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .barikPopupFont(size: 10, weight: .semibold, design: design)
            .textCase(.uppercase)
            .foregroundStyle(fg.opacity(0.45))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func statusRow(_ agent: AgentSession) -> some View {
        let blocked = agent.status == .blocked
        return Button { onFocus(agent) } label: {
            HStack(alignment: .top, spacing: 8) {
                AgentStatusIcon(status: agent.status, size: 13)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        AgentKindIcon(kind: agent.kind, size: 11)
                        Text(agent.projectName)
                            .barikPopupFont(size: 12, weight: .semibold, design: design)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if !agent.title.isEmpty {
                        Text(agent.title)
                            .barikPopupFont(size: 11.5, design: design)
                            .foregroundStyle(fg.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if blocked, let lines = previews[agent.paneID], !lines.isEmpty {
                        previewBox(lines)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                timeLabel(agent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(blocked ? amber.opacity(0.08) : Color.clear)
            .overlay(alignment: .leading) {
                if blocked { Rectangle().fill(amber).frame(width: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AgentRowButtonStyle())
        .contextMenu { contextMenu(agent) }
    }

    private func previewBox(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.prefix(max(previewLines, 1)).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(fg.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            .padding(.top, 3)
    }

    // MARK: Time

    @ViewBuilder
    private func timeLabel(_ agent: AgentSession) -> some View {
        if let since = agent.statusSince {
            switch agent.status {
            case .blocked:
                ticking(1) { now in
                    timeText(AgentTimeFormat.clock(now.timeIntervalSince(since)), color: amber)
                }
                .help(String(localized: "agents.popup.waiting"))
            case .working:
                ticking(30) { now in
                    timeText(AgentTimeFormat.short(now.timeIntervalSince(since)), color: nil)
                }
            case .done:
                ticking(30) { now in
                    let t = AgentTimeFormat.short(now.timeIntervalSince(since))
                    timeText(String(format: String(localized: "agents.popup.ago"), t), color: nil)
                }
            case .idle, .unknown:
                EmptyView()
            }
        }
    }

    /// Ticks only while the popup is visible; hidden, it renders once and stops.
    @ViewBuilder
    private func ticking<C: View>(_ interval: TimeInterval, @ViewBuilder _ content: @escaping (Date) -> C) -> some View {
        if active {
            TimelineView(.periodic(from: .now, by: interval)) { ctx in content(ctx.date) }
        } else {
            content(Date())
        }
    }

    private func timeText(_ text: String, color: Color?) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(color ?? fg.opacity(0.55))
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: Project grouping

    private struct ProjectGroup: Identifiable {
        let name: String
        let agents: [AgentSession]
        var id: String { name }
    }

    private static func rank(_ s: AgentStatus) -> Int {
        switch s {
        case .blocked: return 0
        case .working: return 1
        case .done: return 2
        case .idle: return 3
        case .unknown: return 4
        }
    }

    private var projectGroupList: [ProjectGroup] {
        let all = summary.blocked + summary.working + summary.done + summary.idle
        var order: [String] = []
        var buckets: [String: [AgentSession]] = [:]
        for a in all {
            if buckets[a.projectName] == nil { order.append(a.projectName) }
            buckets[a.projectName, default: []].append(a)
        }
        let groups = order.map { name -> ProjectGroup in
            // `all` is already ordered by status, so each bucket is sorted by urgency.
            ProjectGroup(name: name, agents: buckets[name] ?? [])
        }
        return groups.enumerated().sorted { l, r in
            let a = l.element.agents.map { Self.rank($0.status) }.min() ?? 9
            let b = r.element.agents.map { Self.rank($0.status) }.min() ?? 9
            return a != b ? a < b : l.offset < r.offset
        }.map(\.element)
    }

    @ViewBuilder
    private var projectGroups: some View {
        ForEach(projectGroupList) { group in
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 10.5))
                    .foregroundStyle(fg.opacity(0.5))
                Text(group.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(group.agents.count)")
                    .foregroundStyle(fg.opacity(0.45))
                Spacer(minLength: 0)
            }
            .barikPopupFont(size: 12.5, weight: .semibold, design: design)
            .padding(.horizontal, 16)
            .padding(.top, 9)
            .padding(.bottom, 2)
            ForEach(group.agents) { projectRow($0) }
        }
    }

    private func projectRow(_ agent: AgentSession) -> some View {
        let blocked = agent.status == .blocked
        return Button { onFocus(agent) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    AgentStatusIcon(status: agent.status, size: 12)
                        .frame(width: 16, height: 16)
                    AgentKindIcon(kind: agent.kind, size: 11)
                    Text(agent.title.isEmpty ? agent.kind : agent.title)
                        .barikPopupFont(size: 11.5, design: design)
                        .foregroundStyle(fg.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    timeLabel(agent)
                }
                if blocked, let lines = previews[agent.paneID], !lines.isEmpty {
                    previewBox(lines).padding(.leading, 38)
                }
            }
            .padding(.leading, 34)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .background(blocked ? amber.opacity(0.08) : Color.clear)
            .overlay(alignment: .leading) {
                if blocked { Rectangle().fill(amber).frame(width: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AgentRowButtonStyle())
        .contextMenu { contextMenu(agent) }
    }

    // MARK: Context menu

    @ViewBuilder
    private func contextMenu(_ agent: AgentSession) -> some View {
        Button(String(localized: "agents.popup.copy_path")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(agent.cwd, forType: .string)
        }
        Button(String(localized: "agents.popup.show_in_finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: agent.cwd)])
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 6, height: 6)
            Text(footerText)
                .lineLimit(1)
            Spacer()
            if herdrAppAvailable {
                Button(action: onOpenHerdr) {
                    Text(String(localized: "agents.popup.open_herdr_arrow"))
                }
                .buttonStyle(.plain)
            }
        }
        .barikPopupFont(size: 11, design: design)
        .foregroundStyle(fg.opacity(0.6))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var dotColor: Color {
        switch connection {
        case .live: return green
        case .fallbackPolling: return amber
        case .connecting, .disconnected: return Color.gray
        }
    }

    /// "herdr 0.9.5 · 13 agents" (or "herdr · 13 agents" without a version).
    private var footerText: String {
        if isDisconnected { return "herdr" }
        let n = summary.total
        let count = n == 1
            ? String(format: String(localized: "agents.popup.count.one"), n)
            : String(format: String(localized: "agents.popup.count.other"), n)
        if let v = herdrVersion, !v.isEmpty { return "herdr \(v) · \(count)" }
        return "herdr · \(count)"
    }
}

private struct AgentRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear)
    }
}
