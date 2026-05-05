import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    static let shared = SpacesViewModel()

    @Published var spaces: [AnySpace] = []
    private var refreshTimer: Timer?
    private var provider: AnySpacesProvider?
    private var yabaiProvider: YabaiSpacesProvider?
    private var yabaiSignalMonitor: YabaiSignalMonitor?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenParametersObserver: NSObjectProtocol?
    private let loadQueue = DispatchQueue(
        label: "barik.spaces.load",
        qos: .utility
    )
    private var isLoading = false
    private var pendingReload = false

    init() {
        let runningApps = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        if runningApps.contains("yabai") {
            let yabaiProvider = YabaiSpacesProvider()
            self.yabaiProvider = yabaiProvider
            provider = AnySpacesProvider(yabaiProvider)
            yabaiSignalMonitor = YabaiSignalMonitor(
                executablePath: yabaiProvider.executablePath
            ) { [weak self] event in
                self?.yabaiProvider?.handleSignal(event)
                self?.loadSpaces()
            }
        } else if runningApps.contains("aerospace") {
            provider = AnySpacesProvider(AerospaceSpacesProvider())
        } else {
            provider = nil
        }
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        guard provider != nil else { return }

        registerEventObservers()

        if yabaiSignalMonitor != nil {
            scheduleFallbackTimer(interval: 5.0)
            yabaiSignalMonitor?.start()
        } else {
            // AeroSpace has no equally reliable signal stream here, so keep a
            // conservative fallback poll and rely on workspace/screen events
            // for perceived responsiveness.
            scheduleFallbackTimer(interval: 1.0)
        }
        loadSpaces()
    }

    private func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        yabaiSignalMonitor?.stop()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
    }

    private func scheduleFallbackTimer(interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.loadSpaces()
        }
    }

    private func registerEventObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNames: [NSNotification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]

        workspaceObservers = workspaceNames.map { name in
            workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.loadSpaces()
            }
        }

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadSpaces()
        }
    }

    private func loadSpaces() {
        loadQueue.async { [weak self] in
            guard let self else { return }

            if self.isLoading {
                self.pendingReload = true
                return
            }

            self.isLoading = true

            let nextSpaces: [AnySpace]
            if let provider = self.provider,
               let spaces = provider.getSpacesWithWindows() {
                nextSpaces = spaces.sorted { $0.id < $1.id }
            } else {
                nextSpaces = []
            }

            DispatchQueue.main.async {
                if self.spaces != nextSpaces {
                    self.spaces = nextSpaces
                }
            }

            self.isLoading = false
            if self.pendingReload {
                self.pendingReload = false
                self.loadSpaces()
            }
        }
    }

    func refresh() {
        loadSpaces()
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusSpace(
                spaceId: space.id, needWindowFocus: needWindowFocus)
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusWindow(windowId: String(window.id))
        }
    }

    func canDeleteSpace(_ space: AnySpace) -> Bool {
        provider?.canDeleteSpace(spaceId: space.id) ?? false
    }

    func deleteSpace(_ space: AnySpace) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.deleteSpace(spaceId: space.id)
            self.loadSpaces()
        }
    }
}

class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {}
    func icon(for appName: String) -> NSImage? {
        if let cached = cache.object(forKey: appName as NSString) {
            return cached
        }
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: {
            $0.localizedName == appName
        }),
            let bundleURL = app.bundleURL
        {
            let icon = workspace.icon(forFile: bundleURL.path)
            cache.setObject(icon, forKey: appName as NSString)
            return icon
        }
        return nil
    }
}
