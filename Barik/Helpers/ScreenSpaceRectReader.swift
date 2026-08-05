import AppKit
import SwiftUI

struct ScreenSpaceRectReader: NSViewRepresentable {
    @Binding var screenRect: CGRect

    func makeNSView(context: Context) -> ScreenSpaceTrackingView {
        let view = ScreenSpaceTrackingView()
        view.onScreenRectChange = { rect in
            if screenRect != rect {
                screenRect = rect
            }
        }
        return view
    }

    func updateNSView(_ nsView: ScreenSpaceTrackingView, context: Context) {
        nsView.onScreenRectChange = { rect in
            if screenRect != rect {
                screenRect = rect
            }
        }
        nsView.reportRectIfPossible()
    }
}

final class ScreenSpaceTrackingView: NSView {
    var onScreenRectChange: ((CGRect) -> Void)?
    private var lastReportedRect: CGRect = .null

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
        guard shouldReport(screenRect) else { return }
        lastReportedRect = screenRect
        onScreenRectChange?(screenRect)
    }

    private func shouldReport(_ rect: CGRect) -> Bool {
        guard !lastReportedRect.isNull else { return true }

        return abs(lastReportedRect.minX - rect.minX) > 0.5
            || abs(lastReportedRect.minY - rect.minY) > 0.5
            || abs(lastReportedRect.width - rect.width) > 0.5
            || abs(lastReportedRect.height - rect.height) > 0.5
    }
}

private struct CaptureScreenRectModifier: ViewModifier {
    @Binding var screenRect: CGRect
    @Environment(\.isBarikExporting) private var isExporting

    func body(content: Content) -> some View {
        if isExporting {
            // `ScreenSpaceRectReader` is an `NSViewRepresentable`, which
            // needs a live `NSWindow` to report its on-screen frame.
            // `ImageRenderer` renders offscreen with no such window, so
            // SwiftUI can't flatten this layer at all: it fails the whole
            // render pass and substitutes a system "unable to render"
            // placeholder (a circle-slash glyph over a flat olive
            // background) for the entire widget. Popups aren't reachable
            // from a static export anyway, so just skip tracking the rect.
            content
        } else {
            content.background(ScreenSpaceRectReader(screenRect: $screenRect))
        }
    }
}

extension View {
    func captureScreenRect(into rect: Binding<CGRect>) -> some View {
        modifier(CaptureScreenRectModifier(screenRect: rect))
    }
}
