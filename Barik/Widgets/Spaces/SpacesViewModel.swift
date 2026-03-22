import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    static let shared = SpacesViewModel()

    @Published var spaces: [AnySpace] = []
    private var timer: Timer?
    private var provider: AnySpacesProvider?
    private var yabaiProvider: YabaiSpacesProvider?
    private var yabaiSignalMonitor: YabaiSignalMonitor?
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
        if yabaiSignalMonitor != nil {
            timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
                [weak self] _ in
                self?.loadSpaces()
            }
            yabaiSignalMonitor?.start()
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
                [weak self] _ in
                self?.loadSpaces()
            }
        }
        loadSpaces()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        yabaiSignalMonitor?.stop()
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
