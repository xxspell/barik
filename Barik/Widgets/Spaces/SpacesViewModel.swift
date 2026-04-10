import AppKit
import Combine
import Foundation

private extension CGRect {
    func equalToWithTolerance(_ other: CGRect, tolerance: CGFloat = 1.0) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

class SpacesViewModel: ObservableObject {
    static let shared = SpacesViewModel()

    @Published var spaces: [AnySpace] = []
    private var timer: Timer?
    private var provider: AnySpacesProvider?
    private var yabaiProvider: YabaiSpacesProvider?
    private var yabaiSignalMonitor: YabaiSignalMonitor?
    private var riftSignalMonitor: RiftSignalMonitor?
    private var isRiftProvider = false
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
        } else if runningApps.contains("rift") {
            let riftProvider = RiftSpacesProvider()
            provider = AnySpacesProvider(riftProvider)
            isRiftProvider = true
            riftSignalMonitor = RiftSignalMonitor(
                executablePath: riftProvider.executablePath
            ) { [weak self] in
                self?.loadSpaces()
            }
        } else {
            provider = nil
        }
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        if isRiftProvider {
            riftSignalMonitor?.start()
            loadSpaces()
            return
        }

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
        riftSignalMonitor?.stop()
    }

    private func loadSpaces() {
        loadQueue.async { [weak self] in
            guard let self else { return }

            if self.isLoading {
                self.pendingReload = true
                return
            }

            self.isLoading = true

            guard let provider = self.provider else {
                DispatchQueue.main.async {
                    if !self.spaces.isEmpty {
                        self.spaces = []
                    }
                }
                self.isLoading = false
                if self.pendingReload {
                    self.pendingReload = false
                    self.loadSpaces()
                }
                return
            }

            guard let spaces = provider.getSpacesWithWindows() else {
                self.isLoading = false
                if self.pendingReload {
                    self.pendingReload = false
                    self.loadSpaces()
                }
                return
            }

            let nextSpaces = spaces.sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.label < rhs.label
                }
                return lhs.sortOrder < rhs.sortOrder
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
            return
        }
    }

    func spacesForDisplay(_ screenFrame: CGRect) -> [AnySpace] {
        guard !screenFrame.isEmpty else {
            return spaces
        }

        let spacesWithDisplay = spaces.filter { $0.displayFrame != nil }
        guard !spacesWithDisplay.isEmpty else {
            return spaces
        }

        let matched = spaces.filter { space in
            guard let frame = space.displayFrame else { return false }
            return frame.equalToWithTolerance(screenFrame)
        }

        return matched.isEmpty ? spaces : matched
    }

    func refresh() {
        loadSpaces()
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusSpace(
                spaceId: space.id, needWindowFocus: needWindowFocus)
            self.loadSpaces()
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusWindow(windowId: String(window.id))
            self.loadSpaces()
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
