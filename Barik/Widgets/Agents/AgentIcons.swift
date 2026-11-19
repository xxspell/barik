import AppKit
import SwiftUI

// MARK: - Motion

/// Tracks the system "Reduce motion" setting so animated icons can fall back to static ones.
private struct ReduceMotionReader: ViewModifier {
    @Binding var reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
            .onReceive(
                NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            ) { _ in
                reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
    }
}

extension View {
    func trackingReduceMotion(_ value: Binding<Bool>) -> some View {
        modifier(ReduceMotionReader(reduceMotion: value))
    }

    /// Freezes the animated agent icons below this view (e.g. while their popup is hidden).
    func agentAnimationsPaused(_ paused: Bool) -> some View {
        environment(\.agentAnimationsPaused, paused)
    }
}

private struct AgentAnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True renders the spinner and the blocked pulse as static frames: no TimelineView ticks.
    var agentAnimationsPaused: Bool {
        get { self[AgentAnimationsPausedKey.self] }
        set { self[AgentAnimationsPausedKey.self] = newValue }
    }
}

/// Palette shared by the chip and (later) the popup/toast.
enum AgentsPalette {
    static func amber(tui: Bool, light: Bool) -> Color {
        if !tui { return .orange }
        return Color(hex: light ? "#C77700" : "#FFB454") ?? .orange
    }

    static func green(tui: Bool, light: Bool) -> Color {
        if !tui { return .green }
        return Color(hex: light ? "#2A9455" : "#7EE0A0") ?? .green
    }

    static func working(tui: Bool) -> Color {
        tui ? BarikStyle.current.accent : Color.foregroundOutside
    }
}

// MARK: - Ring spinner

/// 270 degree arc over a 22% opacity track, one turn per 0.9 s.
///
/// The rotation runs as a Core Animation layer animation on the render server.
/// A TimelineView here re-ran SwiftUI layout of the whole bar ~30×/s (≈20% of
/// the main thread while an agent was working), which also starved popup
/// open animations.
struct RingSpinner: View {
    var size: CGFloat = 12
    var lineWidth: CGFloat = 1.6
    var color: Color

    @State private var reduceMotion = false
    @Environment(\.agentAnimationsPaused) private var paused

    var body: some View {
        Group {
            if reduceMotion || paused {
                ZStack {
                    Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
                .frame(width: size, height: size)
                .padding(lineWidth / 2)
            } else {
                SpinnerLayerRepresentable(color: NSColor(color), lineWidth: lineWidth)
                    .frame(width: size + lineWidth, height: size + lineWidth)
            }
        }
        .trackingReduceMotion($reduceMotion)
    }
}

// MARK: - Core Animation icons

/// Base for icons animated by Core Animation: owns a plain (non view-backed)
/// layer centred in the view, so its anchor point and transform are ours.
/// Ignores hits so taps reach the SwiftUI gestures around it.
private class LayerIconView: NSView {
    let iconLayer = CALayer()

    var color: NSColor = .labelColor {
        didSet { if color != oldValue { applyAppearance() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(iconLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        iconLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layoutIcon()
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyAppearance()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        applyAppearance()
        if iconLayer.animation(forKey: Self.animationKey) == nil {
            iconLayer.add(makeAnimation(), forKey: Self.animationKey)
        }
    }

    var contentsScale: CGFloat { window?.backingScaleFactor ?? 2 }

    /// Resolves `color` for the current appearance and redraws static content.
    final func applyAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.applyColors()
        }
        CATransaction.commit()
    }

    static let animationKey = "barik.icon.animation"

    func layoutIcon() {}
    func applyColors() {}
    func makeAnimation() -> CAAnimation { CAAnimation() }
}

private final class SpinnerLayerView: LayerIconView {
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()

    var lineWidth: CGFloat = 1.6 {
        didSet { if lineWidth != oldValue { needsLayout = true } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for shape in [track, arc] {
            shape.fillColor = nil
            iconLayer.addSublayer(shape)
        }
        arc.strokeEnd = 0.75
        arc.lineCap = .round
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutIcon() {
        let inset = lineWidth / 2
        let path = CGPath(ellipseIn: iconLayer.bounds.insetBy(dx: inset, dy: inset), transform: nil)
        for shape in [track, arc] {
            shape.frame = iconLayer.bounds
            shape.path = path
            shape.lineWidth = lineWidth
            shape.contentsScale = contentsScale
        }
    }

    override func applyColors() {
        track.strokeColor = color.withAlphaComponent(color.alphaComponent * 0.22).cgColor
        arc.strokeColor = color.cgColor
    }

    override func makeAnimation() -> CAAnimation {
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi // clockwise in AppKit's y-up layer space
        spin.duration = 0.9
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        return spin
    }
}

private struct SpinnerLayerRepresentable: NSViewRepresentable {
    let color: NSColor
    let lineWidth: CGFloat

    func makeNSView(context: Context) -> SpinnerLayerView {
        let view = SpinnerLayerView()
        view.lineWidth = lineWidth
        view.color = color
        return view
    }

    func updateNSView(_ view: SpinnerLayerView, context: Context) {
        view.lineWidth = lineWidth
        view.color = color
    }
}

/// A monochrome SF Symbol pulsing in opacity (0.7…1) and scale (1…1.06) over
/// 1.6 s, rendered once into a layer and animated by Core Animation.
private final class PulsingSymbolLayerView: LayerIconView {
    var symbolName = "" {
        didSet { if symbolName != oldValue { applyAppearance() } }
    }
    var pointSize: CGFloat = 13 {
        didSet { if pointSize != oldValue { applyAppearance() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconLayer.contentsGravity = .center
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func applyColors() {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            iconLayer.contents = nil
            return
        }
        let tint = color
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let scale = contentsScale
        iconLayer.contentsScale = scale
        iconLayer.contents = tinted.layerContents(forContentsScale: scale)
    }

    override func makeAnimation() -> CAAnimation {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.7
        opacity.toValue = 1.0
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.06
        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = 0.8
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.isRemovedOnCompletion = false
        return group
    }
}

private struct PulsingSymbolRepresentable: NSViewRepresentable {
    let symbolName: String
    let pointSize: CGFloat
    let color: NSColor

    func makeNSView(context: Context) -> PulsingSymbolLayerView {
        let view = PulsingSymbolLayerView()
        update(view)
        return view
    }

    func updateNSView(_ view: PulsingSymbolLayerView, context: Context) {
        update(view)
    }

    private func update(_ view: PulsingSymbolLayerView) {
        view.symbolName = symbolName
        view.pointSize = pointSize
        view.color = color
    }
}

// MARK: - Status icon

struct AgentStatusIcon: View {
    let status: AgentStatus
    var size: CGFloat = 13

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.agentAnimationsPaused) private var paused
    @State private var reduceMotion = false

    var body: some View {
        let tui = BarikStyle.current.isTUI
        let light = colorScheme == .light
        switch status {
        case .blocked:
            let amber = AgentsPalette.amber(tui: tui, light: light)
            Group {
                if reduceMotion || paused {
                    symbol("exclamationmark.bubble.fill", amber)
                } else {
                    PulsingSymbolRepresentable(
                        symbolName: "exclamationmark.bubble.fill",
                        pointSize: size,
                        color: NSColor(amber)
                    )
                    .frame(width: size + 2, height: size + 2)
                }
            }
            .trackingReduceMotion($reduceMotion)
        case .working:
            RingSpinner(size: size - 2, lineWidth: 1.6, color: AgentsPalette.working(tui: tui))
        case .done:
            symbol("checkmark.circle.fill", AgentsPalette.green(tui: tui, light: light))
        case .idle:
            symbol("apple.terminal", dim(tui))
        case .unknown:
            symbol("questionmark.circle", dim(tui))
        }
    }

    private func dim(_ tui: Bool) -> Color {
        tui ? BarikStyle.current.dim : Color.foregroundOutside.opacity(0.5)
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size + 2, height: size + 2)
    }
}

// MARK: - Kind icon

struct AgentKindIcon: View {
    let kind: String
    var size: CGFloat = 12

    var body: some View {
        switch kind {
        case "claude":
            Image("ClaudeIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(Color(hex: "#E8875B") ?? .orange)
                .frame(width: size, height: size)
        default:
            let (name, tint) = Self.glyph(for: kind)
            Image(systemName: name)
                .font(.system(size: size - 1, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }

    private static func glyph(for kind: String) -> (String, Color) {
        func c(_ hex: String) -> Color { Color(hex: hex) ?? .gray }
        switch kind {
        case "opencode": return ("square.dashed.inset.filled", c("#9ECBFF"))
        case "jcode": return ("j.square", c("#C4A7FF"))
        case "omp": return ("circle.hexagongrid", c("#7EE0A0"))
        case "pi": return ("pi", c("#FFD479"))
        default: return ("terminal", .gray)
        }
    }
}

// MARK: - Chip registry

/// Screen-space rects of the agents chip per monitor, so toasts can anchor to the chip on their screen.
@MainActor
final class AgentsChipRegistry {
    static let shared = AgentsChipRegistry()
    private var byMonitor: [String: CGRect] = [:]

    private init() {}

    func update(rect: CGRect) {
        guard rect.width > 0, rect.height > 0, let id = Self.monitorID(containing: rect) else { return }
        byMonitor[id] = rect
    }

    func remove(rect: CGRect) {
        guard let id = Self.monitorID(containing: rect) else { return }
        if byMonitor[id] == rect { byMonitor[id] = nil }
    }

    private static func monitorID(containing rect: CGRect) -> String? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }?.monitorDescriptor.id
    }

    func rects() -> [String: CGRect] { byMonitor }
}
