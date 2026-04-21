import AppKit
import CryptoKit
import Foundation
import OSLog

@MainActor
final class TickTickWallpaperManager: ObservableObject {
    static let shared = TickTickWallpaperManager()

    private struct StoredWallpaperState: Codable {
        var urlsByScreenID: [String: String]
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "TickTickWallpaperManager"
    )
    private let defaults = UserDefaults.standard
    private let storedWallpapersKey = "barik.ticktick.wallpaper.previous"

    private var refreshTimer: Timer?
    private var isEnabled = false
    private var baseURLString = ""
    private var profile = "default"
    private var style = "glow"
    private var authToken = ""
    private var intervalSeconds: TimeInterval = 300
    private var applyToAllScreens = true
    private var activeTask: Task<Void, Never>?
    private var storedWallpaperURLsByScreenID: [String: URL] = [:]

    @Published private(set) var canRestorePreviousWallpapers = false
    @Published private(set) var lastAppliedAt: Date?
    @Published private(set) var lastErrorMessage: String?

    private var cacheDirectoryURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("barik", isDirectory: true)
            .appendingPathComponent("wallpapers", isDirectory: true)
    }

    private init() {
        loadStoredWallpaperState()
    }

    func startUpdating(config: ConfigData) {
        let wallpaperConfig = config["wallpaper"]?.dictionaryValue ?? [:]
        let enabled = wallpaperConfig["enabled"]?.boolValue ?? false
        let baseURL = wallpaperConfig["base-url"]?.stringValue
            ?? wallpaperConfig["base_url"]?.stringValue
            ?? ""
        let resolvedProfile = wallpaperConfig["profile"]?.stringValue ?? "default"
        let resolvedStyle = wallpaperConfig["style"]?.stringValue ?? "glow"
        let resolvedAuthToken = wallpaperConfig["token"]?.stringValue ?? ""
        let resolvedInterval = max(
            TimeInterval(wallpaperConfig["interval-seconds"]?.intValue ?? 300),
            60
        )
        let resolvedApplyToAllScreens = wallpaperConfig["apply-to-all-screens"]?.boolValue ?? true

        let configurationChanged =
            enabled != isEnabled ||
            baseURL != baseURLString ||
            resolvedProfile != profile ||
            resolvedStyle != style ||
            resolvedAuthToken != authToken ||
            resolvedInterval != intervalSeconds ||
            resolvedApplyToAllScreens != applyToAllScreens

        isEnabled = enabled
        baseURLString = baseURL
        profile = resolvedProfile
        style = resolvedStyle
        authToken = resolvedAuthToken
        intervalSeconds = resolvedInterval
        applyToAllScreens = resolvedApplyToAllScreens

        if !enabled || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.debug("startUpdating() — wallpaper integration disabled")
            stopUpdating()
            return
        }

        restartTimer()

        guard configurationChanged else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.refreshNow(reason: "config")
        }
    }

    func stopUpdating() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        activeTask?.cancel()
        activeTask = nil
    }

    func refreshNow() {
        guard isEnabled else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.refreshNow(reason: "manual")
        }
    }

    func restorePreviousWallpapers() {
        stopUpdating()

        guard !storedWallpaperURLsByScreenID.isEmpty else { return }

        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            let screenID = screen.monitorDescriptor.id
            guard let url = storedWallpaperURLsByScreenID[screenID] else { continue }
            do {
                let options = workspace.desktopImageOptions(for: screen) ?? [:]
                try workspace.setDesktopImageURL(url, for: screen, options: options)
            } catch {
                logger.error("restorePreviousWallpapers() — \(error.localizedDescription, privacy: .public)")
                lastErrorMessage = error.localizedDescription
            }
        }

        lastAppliedAt = nil
        clearStoredWallpaperState()
        logger.info("restorePreviousWallpapers() — restored previous wallpapers")
    }

    func screenConfigurationDidChange() {
        guard isEnabled else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.refreshNow(reason: "screens")
        }
    }

    private func restartTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.activeTask?.cancel()
            self.activeTask = Task { [weak self] in
                await self?.refreshNow(reason: "timer")
            }
        }
    }

    private func refreshNow(reason: String) async {
        guard isEnabled else { return }
        guard let request = wallpaperRequest() else {
            logger.error("refreshNow() — failed to build wallpaper URL")
            lastErrorMessage = "Failed to build wallpaper URL."
            return
        }

        logger.info("refreshNow() — reason=\(reason, privacy: .public) url=\(request.url?.absoluteString ?? "", privacy: .public)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("refreshNow() — missing HTTP response")
                return
            }
            guard httpResponse.statusCode == 200 else {
                logger.error("refreshNow() — HTTP \(httpResponse.statusCode, privacy: .public)")
                return
            }

            let hash = wallpaperContentHash(for: data)
            let fileURL = try cachedWallpaperFileURL(hash: hash)
            let targetScreens = targetScreens()

            if areWallpapersAlreadyApplied(fileURL, on: targetScreens) {
                logger.info("refreshNow() — skipped apply, wallpaper hash unchanged and already active")
                lastErrorMessage = nil
                return
            }

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL, options: .atomic)
                logger.info("refreshNow() — wrote new wallpaper asset hash=\(hash, privacy: .public)")
            } else {
                logger.info("refreshNow() — reusing cached wallpaper asset hash=\(hash, privacy: .public)")
            }

            captureCurrentWallpapersIfNeeded(for: targetScreens)
            try applyWallpaper(fileURL, to: targetScreens)
            lastAppliedAt = Date()
            lastErrorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("refreshNow() — \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
    }

    private func cachedWallpaperFileURL(hash: String) throws -> URL {
        guard let directory = cacheDirectoryURL else {
            throw NSError(domain: "TickTickWallpaperManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to resolve wallpaper cache directory."
            ])
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let sanitizedProfile = profile.replacingOccurrences(of: "/", with: "-")
        let sanitizedStyle = style.replacingOccurrences(of: "/", with: "-")
        let shortHash = String(hash.prefix(16))
        return directory.appendingPathComponent(
            "ticktick-habits-\(sanitizedProfile)-\(sanitizedStyle)-\(shortHash).png"
        )
    }

    private func wallpaperRequest() -> URLRequest? {
        guard var components = URLComponents(string: baseURLString) else { return nil }
        let path = components.path.hasSuffix("/")
            ? "\(components.path.dropLast())/v1/wallpaper.png"
            : "\(components.path)/v1/wallpaper.png"
        components.path = path

        let screens = NSScreen.screens
        let metrics = screens.map(screenMetrics(for:))
        let maxWidth = metrics.map(\.width).max() ?? 3024
        let maxHeight = metrics.map(\.height).max() ?? 1964
        let screensValue = metrics.map { "\($0.width)x\($0.height)" }.joined(separator: ",")

        components.queryItems = [
            URLQueryItem(name: "profile", value: profile),
            URLQueryItem(name: "device", value: "macos"),
            URLQueryItem(name: "style", value: style),
            URLQueryItem(name: "width", value: String(maxWidth)),
            URLQueryItem(name: "height", value: String(maxHeight)),
            URLQueryItem(name: "screens", value: screensValue)
        ]

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        if !authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(authToken, forHTTPHeaderField: "X-Wallpaper-Token")
        }
        return request
    }

    private func screenMetrics(for screen: NSScreen) -> (width: Int, height: Int) {
        let scale = screen.backingScaleFactor
        let width = Int((screen.frame.width * scale).rounded())
        let height = Int((screen.frame.height * scale).rounded())
        return (width: width, height: height)
    }

    private func applyWallpaper(_ imageURL: URL, to screens: [NSScreen]) throws {
        let workspace = NSWorkspace.shared

        for screen in screens {
            let existingOptions = workspace.desktopImageOptions(for: screen) ?? [:]
            try workspace.setDesktopImageURL(imageURL, for: screen, options: existingOptions)
        }

        logger.info("applyWallpaper() — applied to \(screens.count, privacy: .public) screen(s)")
    }

    private func captureCurrentWallpapersIfNeeded(for targetScreens: [NSScreen]) {
        let workspace = NSWorkspace.shared

        for screen in targetScreens {
            let screenID = screen.monitorDescriptor.id
            guard storedWallpaperURLsByScreenID[screenID] == nil else { continue }
            guard let currentURL = workspace.desktopImageURL(for: screen) else { continue }
            storedWallpaperURLsByScreenID[screenID] = currentURL
        }

        persistStoredWallpaperState()
    }

    private func persistStoredWallpaperState() {
        let state = StoredWallpaperState(
            urlsByScreenID: storedWallpaperURLsByScreenID.mapValues(\.absoluteString)
        )
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: storedWallpapersKey)
        } catch {
            logger.error("persistStoredWallpaperState() — \(error.localizedDescription, privacy: .public)")
        }
        canRestorePreviousWallpapers = !storedWallpaperURLsByScreenID.isEmpty
    }

    private func loadStoredWallpaperState() {
        guard let data = defaults.data(forKey: storedWallpapersKey) else {
            canRestorePreviousWallpapers = false
            return
        }
        do {
            let state = try JSONDecoder().decode(StoredWallpaperState.self, from: data)
            storedWallpaperURLsByScreenID = state.urlsByScreenID.reduce(into: [:]) { partialResult, entry in
                partialResult[entry.key] = URL(string: entry.value)
            }
        } catch {
            logger.error("loadStoredWallpaperState() — \(error.localizedDescription, privacy: .public)")
            storedWallpaperURLsByScreenID = [:]
        }
        canRestorePreviousWallpapers = !storedWallpaperURLsByScreenID.isEmpty
    }

    private func clearStoredWallpaperState() {
        storedWallpaperURLsByScreenID = [:]
        defaults.removeObject(forKey: storedWallpapersKey)
        canRestorePreviousWallpapers = false
    }

    private func targetScreens() -> [NSScreen] {
        applyToAllScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
    }

    private func wallpaperContentHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func areWallpapersAlreadyApplied(_ imageURL: URL, on screens: [NSScreen]) -> Bool {
        let workspace = NSWorkspace.shared
        guard !screens.isEmpty else { return false }
        return screens.allSatisfy { screen in
            workspace.desktopImageURL(for: screen)?.standardizedFileURL == imageURL.standardizedFileURL
        }
    }
}
