import SwiftUI

/// Remaining auto-hide time of a done toast. `fraction` is the share left now; the line shrinks to zero
/// over `remaining` seconds unless `paused` (hovered).
struct ToastCountdown: Equatable {
    var fraction: Double
    var remaining: TimeInterval
    var paused: Bool
}

/// Content of one toast (chrome comes from `ToastChrome`): "needs you" with preview and buttons, or "done".
struct AgentToastCard: View {
    let item: ToastItem
    let style: ToastStyle
    let preview: [String]
    let onOpen: () -> Void
    let onLater: () -> Void
    /// Length of the working stint that ended in "done", when known.
    var doneIn: TimeInterval? = nil
    var countdown: ToastCountdown? = nil
    /// Clearance under the notch (notched island only).
    var topInset: CGFloat = 0
    /// Pure black card (notched island): the preview box lightens instead of darkening.
    var onBlack = false

    private var barik: BarikStyle { BarikStyle.current }
    private var tui: Bool { barik.isTUI }
    private var design: Font.Design { barik.fontDesign }
    private var fg: Color { tui ? barik.foreground : Color.white.opacity(0.93) }
    private var dim: Color { tui ? barik.dim : Color.white.opacity(0.45) }
    private var amber: Color { AgentsPalette.amber(tui: tui, light: false) }
    private var green: Color { AgentsPalette.green(tui: tui, light: false) }
    private var blocked: Bool { item.kind == .blocked }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !item.agent.title.isEmpty {
                Text(item.agent.title)
                    .barikPopupFont(size: 11, design: design)
                    .foregroundStyle(fg.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 3)
            }
            if blocked {
                if !shownPreview.isEmpty {
                    previewBox.padding(.top, 8)
                }
                buttons.padding(.top, 9)
            } else if let countdown {
                ToastCountdownLine(countdown: countdown, color: green)
                    .padding(.top, 9)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10 + topInset)
        .padding(.bottom, blocked ? 10 : 9)
        .frame(width: AgentToastMetrics.cardWidth, alignment: .leading)
        .foregroundStyle(fg)
        .contentShape(Rectangle())
        .onTapGesture { if !blocked { onOpen() } }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            AgentStatusIcon(status: blocked ? .blocked : .done, size: 13)
            AgentKindIcon(kind: item.agent.kind, size: 12)
            Text(item.agent.projectName)
                .barikPopupFont(size: 12.5, weight: .semibold, design: design)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if blocked {
                let since = item.agent.statusSince ?? item.createdAt
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    meta(String(format: String(localized: "agents.toast.waiting"),
                                AgentTimeFormat.clock(context.date.timeIntervalSince(since))))
                }
            } else if let doneIn {
                meta(String(format: String(localized: "agents.toast.done_in"), AgentTimeFormat.short(doneIn)))
            }
            Spacer(minLength: 0)
        }
    }

    private func meta(_ text: String) -> some View {
        Text("· \(text)")
            .barikPopupFont(size: 11.5, design: design)
            .monospacedDigit()
            .foregroundStyle(dim)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: Preview

    private var shownPreview: [String] {
        let cap = style == .stack ? AgentToastMetrics.stackPreviewLines : AgentToastMetrics.maxPreviewLines
        return Array(preview.suffix(cap))
    }

    private var previewBox: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(shownPreview.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(line.hasPrefix("❯") ? barik.accent : fg.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(onBlack ? Color.white.opacity(0.07) : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: tui ? 4 : 8, style: .continuous))
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 6) {
            ToastButton(title: String(localized: "agents.toast.open"), key: "⏎", primary: true, action: onOpen)
            ToastButton(title: String(localized: "agents.toast.later"), key: "esc", primary: false, action: onLater)
        }
    }
}

// MARK: - Button

private struct ToastButton: View {
    let title: String
    let key: String
    let primary: Bool
    let action: () -> Void

    var body: some View {
        let style = BarikStyle.current
        let ink = primary ? Color(red: 27 / 255, green: 27 / 255, blue: 34 / 255)
            : (style.isTUI ? style.foreground : Color.white.opacity(0.9))
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).barikPopupFont(size: 11.5, weight: .semibold, design: style.fontDesign)
                Text(key).barikPopupFont(size: 10.5, design: style.fontDesign).opacity(0.5)
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                primary ? AnyShapeStyle(style.accent) : AnyShapeStyle(Color.white.opacity(0.1)),
                in: RoundedRectangle(cornerRadius: style.isTUI ? 4 : 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(ToastPressStyle())
    }
}

private struct ToastPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Auto-hide line

/// Thin line that drains over the remaining auto-hide time; frozen (and dimmed) while hovered.
private struct ToastCountdownLine: View {
    let countdown: ToastCountdown
    let color: Color

    @State private var value: Double

    init(countdown: ToastCountdown, color: Color) {
        self.countdown = countdown
        self.color = color
        _value = State(initialValue: countdown.fraction)
    }

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.12))
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(countdown.paused ? 0.55 : 1))
                    .frame(height: 2)
                    .scaleEffect(x: max(0, min(1, value)), y: 1, anchor: .leading)
            }
            .onAppear(perform: run)
            .onChange(of: countdown) { _, _ in run() }
    }

    private func run() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { value = countdown.fraction }
        guard !countdown.paused, countdown.remaining > 0 else { return }
        let remaining = countdown.remaining
        DispatchQueue.main.async {
            withAnimation(.linear(duration: remaining)) { value = 0 }
        }
    }
}
