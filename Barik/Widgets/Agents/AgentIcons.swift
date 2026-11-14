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
struct RingSpinner: View {
    var size: CGFloat = 12
    var lineWidth: CGFloat = 1.6

    @State private var reduceMotion = false

    var body: some View {
        ZStack {
            Circle().stroke(.tint.opacity(0.22), lineWidth: lineWidth)
            if reduceMotion {
                arc
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    arc.rotationEffect(.degrees((t.truncatingRemainder(dividingBy: 0.9) / 0.9) * 360))
                }
            }
        }
        .frame(width: size, height: size)
        .padding(lineWidth / 2)
        .trackingReduceMotion($reduceMotion)
    }

    private var arc: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}

// MARK: - Status icon

struct AgentStatusIcon: View {
    let status: AgentStatus
    var size: CGFloat = 13

    @Environment(\.colorScheme) private var colorScheme
    @State private var reduceMotion = false

    var body: some View {
        let tui = BarikStyle.current.isTUI
        let light = colorScheme == .light
        switch status {
        case .blocked:
            let amber = AgentsPalette.amber(tui: tui, light: light)
            Group {
                if reduceMotion {
                    symbol("exclamationmark.bubble.fill", amber)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let phase = (sin(t * 2 * .pi / 1.6) + 1) / 2
                        symbol("exclamationmark.bubble.fill", amber)
                            .opacity(0.7 + 0.3 * phase)
                            .scaleEffect(1 + 0.06 * phase)
                    }
                }
            }
            .trackingReduceMotion($reduceMotion)
        case .working:
            RingSpinner(size: size - 2, lineWidth: 1.6)
                .tint(AgentsPalette.working(tui: tui))
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
