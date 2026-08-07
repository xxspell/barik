import AppKit
import SwiftUI

/// Reaches the Settings window's `NSWindow` once it's attached to the view
/// hierarchy and configures its chrome to match the rest of Barik's dark UI
/// (see `MenuBarPopupView`, which uses a plain black card + white text).
/// SwiftUI's `Settings` scene gives no direct handle to the `NSWindow`, so
/// this walks up from a mounted `NSView` instead.
struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        // Belt-and-suspenders: `.windowResizability(.contentMinSize)` on the
        // `Settings` scene (BarikApp.swift) should already make this window
        // resizable, but that's an implicit SwiftUI-level guarantee. Since
        // we already have a direct NSWindow handle here, enforce it
        // explicitly at the AppKit level too.
        window.styleMask.insert(.resizable)
    }
}
