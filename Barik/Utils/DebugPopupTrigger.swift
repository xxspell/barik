import AppKit
import SwiftUI

#if DEBUG
/// Debug-only hook for media capture (`.dev/media`): posting the distributed
/// notification `dev.barik.debug.openPopup` with `object` = a widget id opens
/// that widget's popup on the primary display, exactly like clicking it.
/// Synthetic mouse clicks don't reach the bar's tap gestures, and the popup
/// closes as soon as another app (the terminal) takes focus, so screenshots
/// for README/CHANGELOG need a click-free way in. Not compiled into Release.
private struct DebugPopupTrigger: ViewModifier {
    static let name = Notification.Name("dev.barik.debug.openPopup")

    let id: String
    let rect: CGRect
    let action: ([AnyHashable: Any]) -> Void

    func body(content: Content) -> some View {
        content.onReceive(DistributedNotificationCenter.default().publisher(for: Self.name)) { note in
            guard (note.object as? String) == id,
                  let primary = NSScreen.screens.first,
                  primary.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) else { return }
            action(note.userInfo ?? [:])
        }
    }
}
#endif

extension View {
    /// Debug builds: run `action` when `dev.barik.debug.openPopup` arrives for
    /// `id` and this widget sits on the primary display. Release: no-op.
    @ViewBuilder
    func debugPopupTrigger(
        id: String,
        rect: CGRect,
        action: @escaping ([AnyHashable: Any]) -> Void
    ) -> some View {
        #if DEBUG
        modifier(DebugPopupTrigger(id: id, rect: rect, action: action))
        #else
        self
        #endif
    }
}
