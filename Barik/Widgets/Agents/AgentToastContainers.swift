import SwiftUI

// MARK: - Metrics & palette

enum AgentToastMetrics {
    static let cardWidth: CGFloat = 300
    /// Transparent room around the card inside the panel for the shadow and spring overshoot.
    static let margin: CGFloat = 36
    static let gap: CGFloat = 8
    /// Upper bound for the preview box in a toast, whatever `preview-lines` says.
    static let maxPreviewLines = 12
    /// Preview cap in the stack, where up to three cards share the screen edge.
    static let stackPreviewLines = 4
    /// Panel height for island/chip: the tallest card plus the "+N" pill and shadow room.
    static let singleCanvasHeight: CGFloat = 500
    static let canvasSpace = "agentToastCanvas"
    static let pillKey = "+pill"
}

enum AgentToastPalette {
    static func radius(tui: Bool) -> CGFloat { tui ? 8 : 14 }

    static func fill(tui: Bool) -> Color {
        tui ? Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.95)
            : Color(red: 18 / 255, green: 16 / 255, blue: 22 / 255).opacity(0.86)
    }

    static func border(tui: Bool) -> Color {
        tui ? BarikStyle.current.accent.opacity(0.35) : Color.white.opacity(0.1)
    }
}

// MARK: - Layout

/// Where the card sits inside its panel and the shape it grows from. Built by the controller per placement.
struct ToastLayout: Equatable {
    var style: ToastStyle
    var canvas: CGSize
    /// Top-left of the card (stack: of the topmost card), canvas coordinates.
    var cardOrigin: CGPoint
    /// Start shape in card-local coordinates (island: notch or small capsule; chip: the chip).
    var start: CGRect = .zero
    var startTopRadius: CGFloat = 14
    var startBottomRadius: CGFloat = 14
    /// The start shape is black (notch / Dynamic Island capsule) and blends into the card colour.
    var blackStart = false
    /// Notched island: the card is pure black, flush with the top edge, square top corners.
    var notched = false
    /// Content clearance under the notch.
    var topInset: CGFloat = 0
}

/// Live state of one toast panel; the controller writes it inside animation transactions.
@MainActor
final class AgentToastPanelModel: ObservableObject {
    @Published var layout: ToastLayout
    /// Stack: the visible items, newest first. Island/chip: only the item on display.
    @Published var items: [ToastItem] = []
    /// Count shown in the "+N" pill (0 hides it).
    @Published var extra = 0
    @Published var previews: [String: [String]] = [:]
    @Published var countdowns: [String: ToastCountdown] = [:]
    @Published var doneIn: [String: TimeInterval] = [:]
    @Published var reduceMotion = false

    var onOpen: (ToastItem) -> Void = { _ in }
    var onLater: (ToastItem) -> Void = { _ in }
    var onCycle: () -> Void = {}
    /// Card / pill frames in canvas coordinates, keyed by item id (pill: `AgentToastMetrics.pillKey`).
    var onRects: ([String: CGRect]) -> Void = { _ in }

    init(layout: ToastLayout) {
        self.layout = layout
    }
}

// MARK: - Morph

private struct ToastMorphKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    /// 0 = start shape (notch / capsule / chip), 1 = full card. Values past 1 come from spring overshoot.
    var toastMorph: Double {
        get { self[ToastMorphKey.self] }
        set { self[ToastMorphKey.self] = newValue }
    }
}

/// Animatable carrier for the morph progress, used as the island/chip insertion/removal transition.
struct ToastMorphProgress: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.environment(\.toastMorph, progress)
    }
}

extension AnyTransition {
    static var toastMorph: AnyTransition {
        .modifier(active: ToastMorphProgress(progress: 0), identity: ToastMorphProgress(progress: 1))
    }

    static var toastSlide: AnyTransition {
        .offset(x: AgentToastMetrics.cardWidth + 40).combined(with: .opacity)
    }
}

/// Rounded rect interpolated between the start shape and the view bounds.
struct ToastMorphShape: Shape {
    var progress: Double
    var start: CGRect
    var startTop: CGFloat
    var startBottom: CGFloat
    var endTop: CGFloat
    var endBottom: CGFloat

    func path(in rect: CGRect) -> Path {
        let p = CGFloat(progress)
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        let r = CGRect(x: lerp(start.minX, rect.minX), y: lerp(start.minY, rect.minY),
                       width: max(0, lerp(start.width, rect.width)),
                       height: max(0, lerp(start.height, rect.height)))
        let limit = min(r.width, r.height) / 2
        let top = min(max(0, lerp(startTop, endTop)), limit)
        let bottom = min(max(0, lerp(startBottom, endBottom)), limit)
        return UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top),
            style: .continuous
        ).path(in: r)
    }
}

/// Card background, border, shadow and clip; follows `toastMorph` so the card can grow out of its start shape.
struct ToastChrome: ViewModifier {
    let layout: ToastLayout
    var tui: Bool = BarikStyle.current.isTUI

    @Environment(\.toastMorph) private var progress
    @Environment(\.isBarikExporting) private var isExporting

    func body(content: Content) -> some View {
        let p = progress
        let radius = AgentToastPalette.radius(tui: tui)
        let shape = ToastMorphShape(
            progress: p, start: layout.start,
            startTop: layout.startTopRadius, startBottom: layout.startBottomRadius,
            endTop: layout.notched ? 0 : radius, endBottom: layout.notched ? 18 : radius)
        let reveal = min(max((p - 0.4) / 0.6, 0), 1)
        content
            .opacity(reveal)
            .scaleEffect(0.94 + 0.06 * reveal, anchor: .top)
            .clipShape(shape)
            .background {
                ZStack {
                    if layout.notched {
                        shape.fill(Color.black)
                    } else {
                        if !tui && !isExporting {
                            shape.fill(.ultraThinMaterial)
                        }
                        shape.fill(isExporting ? AgentToastPalette.fill(tui: tui).opacity(1) : AgentToastPalette.fill(tui: tui))
                        if layout.blackStart {
                            shape.fill(Color.black).opacity(max(0, 1 - p))
                        }
                    }
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.45 * min(max(p, 0), 1)), radius: 18, y: 10)
            }
            .overlay {
                if !layout.notched {
                    shape.stroke(AgentToastPalette.border(tui: tui).opacity(min(max(p, 0), 1)), lineWidth: 1)
                }
            }
            // The notched start is black over the black notch: no fade needed, it emerges from it.
            .opacity(layout.notched ? 1 : min(max(p / 0.15, 0), 1))
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Rect reporting

private struct ToastRectsKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func reportToastRect(_ key: String) -> some View {
        background {
            GeometryReader { g in
                Color.clear.preference(
                    key: ToastRectsKey.self,
                    value: [key: g.frame(in: .named(AgentToastMetrics.canvasSpace))])
            }
        }
    }
}

// MARK: - Canvas

/// Root view of a toast panel: a transparent canvas holding the island/chip card or the stack.
struct AgentToastCanvas: View {
    @ObservedObject var model: AgentToastPanelModel

    var body: some View {
        let layout = model.layout
        ZStack(alignment: .topLeading) {
            Color.clear
            Group {
                if layout.style == .stack { stack } else { single }
            }
            .padding(.leading, layout.cardOrigin.x)
            .padding(.top, layout.cardOrigin.y)
        }
        .frame(width: layout.canvas.width, height: layout.canvas.height, alignment: .topLeading)
        .coordinateSpace(name: AgentToastMetrics.canvasSpace)
        .onPreferenceChange(ToastRectsKey.self) { rects in
            model.onRects(rects)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    private func card(_ item: ToastItem) -> some View {
        AgentToastCard(
            item: item,
            style: model.layout.style,
            preview: model.previews[item.agent.paneID] ?? [],
            onOpen: { model.onOpen(item) },
            onLater: { model.onLater(item) },
            doneIn: model.doneIn[item.id],
            countdown: model.countdowns[item.id],
            topInset: model.layout.topInset,
            onBlack: model.layout.notched)
    }

    /// Island / chip: one card that grows out of its start shape; cycling crossfades the content.
    private var single: some View {
        let first = model.items.first
        return VStack(spacing: AgentToastMetrics.gap) {
            if let item = first {
                ZStack(alignment: .top) {
                    card(item)
                        .id(item.id)
                        .transition(.opacity)
                }
                .modifier(ToastChrome(layout: model.layout))
                .reportToastRect(item.id)
                .transition(model.reduceMotion ? .opacity : .toastMorph)
            }
            if first != nil, model.extra > 0 {
                ToastMorePill(count: model.extra, action: { model.onCycle() })
                    .reportToastRect(AgentToastMetrics.pillKey)
                    .transition(model.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
            }
        }
        .frame(width: AgentToastMetrics.cardWidth, alignment: .top)
    }

    /// Stack: newest on top, sliding in from the right edge.
    private var stack: some View {
        VStack(alignment: .trailing, spacing: AgentToastMetrics.gap) {
            ForEach(model.items) { item in
                card(item)
                    .modifier(ToastChrome(layout: model.layout))
                    .reportToastRect(item.id)
                    .transition(model.reduceMotion ? .opacity : .toastSlide)
            }
            if !model.items.isEmpty, model.extra > 0 {
                ToastMorePill(count: model.extra, action: nil)
                    .transition(.opacity)
            }
        }
        .frame(width: AgentToastMetrics.cardWidth, alignment: .trailing)
    }
}

// MARK: - "+N" pill

struct ToastMorePill: View {
    let count: Int
    /// nil: a plain label (stack); otherwise clicking cycles to the next toast.
    let action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .help(String(localized: "agents.toast.next"))
        } else {
            label
        }
    }

    private var label: some View {
        let style = BarikStyle.current
        return HStack(spacing: 4) {
            Text(String(format: String(localized: "agents.toast.more"), count))
            if action != nil {
                Image(systemName: "chevron.right").font(.system(size: 8.5, weight: .bold))
            }
        }
        .barikPopupFont(size: 11, weight: .semibold, design: style.fontDesign)
        .foregroundStyle(style.isTUI ? style.foreground : Color.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(AgentToastPalette.fill(tui: style.isTUI), in: Capsule())
        .overlay(Capsule().stroke(AgentToastPalette.border(tui: style.isTUI), lineWidth: 1))
        .contentShape(Capsule())
    }
}
