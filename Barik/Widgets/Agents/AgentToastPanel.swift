import AppKit
import SwiftUI

// MARK: - Panel

/// Borderless, non-activating, transparent panel hosting one toast canvas. It never takes focus on
/// appear; it becomes key only when the user clicks a card, so ⏎ / esc reach it.
final class AgentToastPanel: NSPanel {
    let screenID: String
    let model: AgentToastPanelModel
    /// Card and pill frames in canvas coordinates (top-left origin); the rest of the canvas lets clicks through.
    var canvasRects: [String: CGRect] = [:]

    /// `canvasRects` in screen coordinates for the current frame.
    var hitRects: [String: CGRect] {
        let f = frame
        return canvasRects.mapValues { r in
            CGRect(x: f.minX + r.minX, y: f.maxY - r.maxY, width: r.width, height: r.height)
        }
    }
    /// Set one beat after ordering in, so the first items get an insertion transition.
    var ready = false
    /// Called when a click made the panel key.
    var onBecomeKey: (() -> Void)?
    /// Called when the panel stops being key.
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    init(screenID: String, frame: CGRect, model: AgentToastPanelModel) {
        self.screenID = screenID
        self.model = model
        super.init(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        animationBehavior = .none

        let host = AgentToastHostingView(rootView: AgentToastCanvas(model: model))
        host.sizingOptions = []
        host.safeAreaRegions = []
        contentView = host
        setFrame(frame, display: false)
    }
}

/// Lets the first click on a card act (buttons, tap to open) even though the panel is not key yet.
private final class AgentToastHostingView: NSHostingView<AgentToastCanvas> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Geometry

/// Where a toast panel goes on its screen and how its card is laid out inside it.
@MainActor
enum AgentToastGeometry {
    /// Panel frame (screen coordinates) and card layout for a placement.
    static func frame(for placement: ToastPlacement, on screen: NSScreen) -> (CGRect, ToastLayout) {
        let d = screen.monitorDescriptor
        let f = d.frame
        let w = AgentToastMetrics.cardWidth
        let m = AgentToastMetrics.margin
        let height = min(AgentToastMetrics.singleCanvasHeight, f.height)
        let barik = BarikStyle.current
        let barHeight = ConfigManager.shared.config.experimental.foreground.resolveHeight()
            + (barik.isTUI ? barik.tuiTopPadding : 0)
        // Bottom of the bar (or of a visible system menu bar, whichever is lower).
        let contentTop = min(f.maxY - barHeight, screen.visibleFrame.maxY)

        switch placement.style {
        case .island where d.hasTopInsetCutout && d.notchGapWidth > 0:
            // Grows out of the notch: flush with the top edge, start shape = the notch itself.
            let notchH = max(d.safeAreaInsets.top, 24)
            let nw = min(d.notchGapWidth, w)
            let canvasW = w + 2 * m
            let frame = CGRect(x: f.midX - canvasW / 2, y: f.maxY - height, width: canvasW, height: height)
            return (frame, ToastLayout(
                style: .island, canvas: frame.size, cardOrigin: CGPoint(x: m, y: 0),
                start: CGRect(x: (w - nw) / 2, y: 0, width: nw, height: notchH),
                startTopRadius: 0, startBottomRadius: min(10, notchH / 3),
                blackStart: true, notched: true, topInset: notchH))

        case .island,
             .chip where placement.anchor == nil: // chip without an anchor falls back to the island
            let cardTop = contentTop - 8
            let top = min(cardTop + 16, f.maxY)
            let canvasW = w + 2 * m
            let frame = CGRect(x: f.midX - canvasW / 2, y: top - height, width: canvasW, height: height)
            return (frame, ToastLayout(
                style: .island, canvas: frame.size, cardOrigin: CGPoint(x: m, y: top - cardTop),
                start: CGRect(x: (w - 120) / 2, y: 0, width: 120, height: 28),
                startTopRadius: 14, startBottomRadius: 14, blackStart: true))

        case .chip:
            // Grows down out of the chip, clamped to the screen edges.
            let a = placement.anchor ?? .zero
            let cardTop = a.minY - 6
            let cardX = min(max(a.midX - w / 2, f.minX + 8), f.maxX - 8 - w)
            let chipH = min(a.height, 28)
            let chip = CGRect(x: a.minX, y: a.midY - chipH / 2, width: a.width, height: chipH)
            let minX = min(cardX, chip.minX) - m
            let maxX = max(cardX + w, chip.maxX) + m
            let top = min(max(chip.maxY, cardTop) + 12, f.maxY)
            let frame = CGRect(x: minX, y: top - height, width: maxX - minX, height: height)
            return (frame, ToastLayout(
                style: .chip, canvas: frame.size, cardOrigin: CGPoint(x: cardX - minX, y: top - cardTop),
                start: CGRect(x: chip.minX - cardX, y: cardTop - chip.maxY, width: chip.width, height: chipH),
                startTopRadius: chipH / 2, startBottomRadius: chipH / 2))

        case .stack:
            // Right edge, 10 pt below the bar; the canvas runs to the bottom of the screen.
            let cardTop = contentTop - 10
            let cardX = f.maxX - 10 - w
            let top = min(cardTop + 16, f.maxY)
            let bottom = max(f.minY, screen.visibleFrame.minY)
            let frame = CGRect(x: cardX - m, y: bottom, width: f.maxX - (cardX - m), height: top - bottom)
            return (frame, ToastLayout(
                style: .stack, canvas: frame.size, cardOrigin: CGPoint(x: m, y: top - cardTop)))
        }
    }
}
