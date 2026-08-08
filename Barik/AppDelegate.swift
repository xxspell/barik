import SwiftUI
import AppKit
import OSLog
import Combine
import UserNotifications

final class MenuBarEditablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var backgroundPanels: [NSPanel] = []
    private var menuBarPanels: [NSPanel] = []
    private var configCancellable: AnyCancellable?
    private var editModeCancellable: AnyCancellable?
    private var escapeKeyMonitor: Any?
    private let tickTickWallpaperManager = TickTickWallpaperManager.shared
    private let gotifyManager = GotifyManager.shared
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "AppDelegate"
    )

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
        UNUserNotificationCenter.current().delegate = self
        setupPanels()
        tickTickWallpaperManager.startUpdating(
            config: ConfigManager.shared.globalWidgetConfig(for: "default.ticktick")
        )
        gotifyManager.startUpdating(
            config: ConfigManager.shared.globalWidgetConfig(for: "default.gotify")
        )
        configCancellable = ConfigManager.shared.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] config in
                let widgetConfig = config.rootToml.widgets.config(for: "default.ticktick") ?? [:]
                self?.tickTickWallpaperManager.startUpdating(config: widgetConfig)
                let gotifyConfig = config.rootToml.widgets.config(for: "default.gotify") ?? [:]
                self?.gotifyManager.startUpdating(config: gotifyConfig)
            }

        editModeCancellable = BarEditModeState.shared.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] isActive in
                self?.handleEditModeChange(isActive)
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        setupPanels()
        tickTickWallpaperManager.screenConfigurationDidChange()
    }

    private func handleEditModeChange(_ isActive: Bool) {
        if isActive {
            menuBarPanels.first?.makeKey()
            installEscapeMonitorIfNeeded()
        } else {
            removeEscapeMonitorIfNeeded()
            BarEditDragState.shared.reset()
        }
    }

    private func installEscapeMonitorIfNeeded() {
        guard escapeKeyMonitor == nil else { return }
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            BarEditModeState.shared.isActive = false
            return nil
        }
    }

    private func removeEscapeMonitorIfNeeded() {
        guard let monitor = escapeKeyMonitor else { return }
        NSEvent.removeMonitor(monitor)
        escapeKeyMonitor = nil
    }

    private func edgeInsetsDescription(_ insets: NSEdgeInsets) -> String {
        "{top=\(insets.top), left=\(insets.left), bottom=\(insets.bottom), right=\(insets.right)}"
    }

    /// Configures and displays the background and menu bar panels.
    private func setupPanels() {
        // Clean up existing panels
        cleanupPanels()

        // Create panels for each screen
        let screens = NSScreen.screens
        for screen in screens {
            let monitor = screen.monitorDescriptor
            logger.debug(
                """
                Creating panels for monitor id=\(monitor.id, privacy: .public) \
                name=\(monitor.name, privacy: .public) \
                frame=\(NSStringFromRect(monitor.frame), privacy: .public) \
                safeInsets=\(self.edgeInsetsDescription(monitor.safeAreaInsets), privacy: .public) \
                leftArea=\(NSStringFromRect(monitor.auxiliaryTopLeftArea), privacy: .public) \
                rightArea=\(NSStringFromRect(monitor.auxiliaryTopRightArea), privacy: .public)
                """
            )

            // Create background panel for this screen
            let backgroundPanel = createPanel(
                frame: monitor.frame,
                level: Int(CGWindowLevelForKey(.desktopWindow)),
                hostingRootView: AnyView(BackgroundView()))
            backgroundPanels.append(backgroundPanel)

            // Create menu bar panel for this screen
            let menuBarPanel = createPanel(
                frame: monitor.frame,
                level: Int(CGWindowLevelForKey(.backstopMenu)),
                hostingRootView: AnyView(MenuBarView(monitor: monitor)),
                isKeyCapable: true)
            menuBarPanels.append(menuBarPanel)
        }
    }

    /// Creates an NSPanel with the provided parameters.
    private func createPanel(
        frame: CGRect, level: Int,
        hostingRootView: AnyView,
        isKeyCapable: Bool = false
    ) -> NSPanel {
        let newPanel: NSPanel =
            isKeyCapable
            ? MenuBarEditablePanel(
                contentRect: frame,
                styleMask: [.nonactivatingPanel],
                backing: .buffered,
                defer: false)
            : NSPanel(
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
