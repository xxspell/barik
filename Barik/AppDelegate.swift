import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var backgroundPanels: [NSPanel] = []
    private var menuBarPanels: [NSPanel] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let error = ConfigManager.shared.initError {
            showFatalConfigError(message: error)
            return
        }
        
        // Show "What's New" banner if the app version is outdated
        if !VersionChecker.isLatestVersion() {
            VersionChecker.updateVersionFile()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(
                    name: Notification.Name("ShowWhatsNewBanner"), object: nil)
            }
        }
        
        MenuBarPopup.setup()
        setupPanels()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        setupPanels()
    }

    /// Configures and displays the background and menu bar panels.
    private func setupPanels() {
        // Clean up existing panels
        cleanupPanels()

        // Create panels for each screen
        let screens = NSScreen.screens
        for screen in screens {
            let screenFrame = screen.frame

            // Create background panel for this screen
            let backgroundPanel = createPanel(
                frame: screenFrame,
                level: Int(CGWindowLevelForKey(.desktopWindow)),
                hostingRootView: AnyView(BackgroundView()))
            backgroundPanels.append(backgroundPanel)

            // Create menu bar panel for this screen
            let menuBarPanel = createPanel(
                frame: screenFrame,
                level: Int(CGWindowLevelForKey(.backstopMenu)),
                hostingRootView: AnyView(MenuBarView()))
            menuBarPanels.append(menuBarPanel)
        }
    }

    /// Creates an NSPanel with the provided parameters.
    private func createPanel(
        frame: CGRect, level: Int,
        hostingRootView: AnyView
    ) -> NSPanel {
        let newPanel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false)
        newPanel.level = NSWindow.Level(rawValue: level)
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary] // Add fullScreenPrimary to allow on all screens
        newPanel.contentView = NSHostingView(rootView: hostingRootView)
        newPanel.orderFront(nil)
        return newPanel
    }

    /// Cleans up existing panels
    private func cleanupPanels() {
        for panel in backgroundPanels {
            panel.close()
        }
        backgroundPanels.removeAll()

        for panel in menuBarPanels {
            panel.close()
        }
        menuBarPanels.removeAll()
    }
    
    private func showFatalConfigError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Configuration Error"
        alert.informativeText = "\(message)\n\nPlease double check ~/.barik-config.toml and try again."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}
