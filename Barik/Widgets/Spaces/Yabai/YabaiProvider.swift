import Foundation
import OSLog

class YabaiSpacesProvider: SpacesProvider, SwitchableSpacesProvider, DeletableSpacesProvider {
    typealias SpaceType = YabaiSpace
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "YabaiSpacesProvider"
    )
    let executablePath = ConfigManager.shared.config.yabai.path
    private let stateLock = NSLock()
    private var lastKnownWindowsById: [Int: YabaiWindow] = [:]
    private var minimizedWindowsById: [Int: YabaiWindow] = [:]

    private var shouldShowHiddenWindows: Bool {
        ConfigManager.shared.config.rootToml.widgets
            .config(for: "default.spaces")?["window"]?
            .dictionaryValue?["show-hidden"]?.boolValue ?? false
    }

    private var shouldShowEmptySpaces: Bool {
        ConfigManager.shared.config.rootToml.widgets
            .config(for: "default.spaces")?["space"]?
            .dictionaryValue?["show-empty"]?.boolValue ?? true
    }

    private func runYabaiCommand(arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            logger.error("Yabai error: \(error.localizedDescription)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    private func fetchSpaces() -> [YabaiSpace]? {
        guard
            let data = runYabaiCommand(arguments: ["-m", "query", "--spaces"])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            let spaces = try decoder.decode([YabaiSpace].self, from: data)
            return spaces
        } catch {
            logger.error("Decode yabai spaces error: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchWindows() -> [YabaiWindow]? {
        guard
            let data = runYabaiCommand(arguments: ["-m", "query", "--windows"])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            let windows = try decoder.decode([YabaiWindow].self, from: data)
            logger.debug("fetchWindows() — decoded \(windows.count) windows")
            return windows
        } catch {
            logger.error("Decode yabai windows error: \(error.localizedDescription)")
            return nil
        }
    }

    func handleSignal(_ event: YabaiSignalEvent?) {
        guard let event else { return }

        switch event.name {
        case "window_minimized":
            guard let windowId = event.windowId else { return }
            stateLock.lock()
            let knownWindow = lastKnownWindowsById[windowId]
            if let knownWindow {
                minimizedWindowsById[windowId] = YabaiWindow(
                    id: knownWindow.id,
                    title: knownWindow.title,
                    appName: knownWindow.appName,
                    pid: knownWindow.pid,
                    isFocused: false,
                    stackIndex: max(knownWindow.stackIndex, 10_000),
                    appIcon: knownWindow.appIcon,
                    isVisible: false,
                    rawIsHidden: knownWindow.rawIsHidden,
                    isMinimized: true,
                    isFloating: knownWindow.isFloating,
                    isSticky: knownWindow.isSticky,
                    spaceId: event.spaceId ?? knownWindow.spaceId
                )
                logger.debug(
                    "handleSignal() — cached minimized window id=\(windowId) space=\(String(event.spaceId ?? knownWindow.spaceId), privacy: .public)"
                )
            } else {
                logger.debug(
                    "handleSignal() — missing last known window for minimized id=\(windowId)"
                )
            }
            stateLock.unlock()

        case "window_deminimized", "window_destroyed":
            guard let windowId = event.windowId else { return }
            stateLock.lock()
            minimizedWindowsById.removeValue(forKey: windowId)
            stateLock.unlock()
            logger.debug("handleSignal() — removed cached minimized window id=\(windowId)")

        default:
            break
        }
    }

    func getSpacesWithWindows() -> [YabaiSpace]? {
        guard let spaces = fetchSpaces(), let windows = fetchWindows() else {
            return nil
        }

        updateWindowCaches(with: windows)
        let mergedWindows = mergeWindows(liveWindows: windows)

        logger.debug("getSpacesWithWindows() — showHidden=\(self.shouldShowHiddenWindows, privacy: .public) spaces=\(spaces.count) liveWindows=\(windows.count) mergedWindows=\(mergedWindows.count)")

        let hiddenLikeWindows = mergedWindows.filter(\.isHidden)
        if !hiddenLikeWindows.isEmpty {
            for window in hiddenLikeWindows {
                logger.debug(
                    """
                    hidden-like window — id=\(window.id) app=\(window.appName ?? "nil", privacy: .public) title=\(window.title, privacy: .public) space=\(window.spaceId) focused=\(window.isFocused, privacy: .public) stackIndex=\(window.stackIndex) hidden=\(window.rawIsHidden, privacy: .public) minimized=\(window.isMinimized, privacy: .public) effectiveHidden=\(window.isHidden, privacy: .public) floating=\(window.isFloating, privacy: .public) sticky=\(window.isSticky, privacy: .public)
                    """
                )
            }
        } else {
            logger.debug("getSpacesWithWindows() — no hidden or minimized windows")
        }

        let filteredWindows = mergedWindows.filter {
            !($0.isFloating || $0.isSticky)
                && $0.spaceId > 0
                && (shouldShowHiddenWindows || !$0.isHidden)
        }
        logger.debug("getSpacesWithWindows() — filteredWindows=\(filteredWindows.count)")
        var spaceDict = Dictionary(
            uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        for window in filteredWindows {
            if var space = spaceDict[window.spaceId] {
                space.windows.append(window)
                spaceDict[window.spaceId] = space
            }
        }
        var resultSpaces = Array(spaceDict.values)
        for i in 0..<resultSpaces.count {
            resultSpaces[i].windows.sort {
                if $0.isHidden != $1.isHidden {
                    return !$0.isHidden && $1.isHidden
                }
                return $0.stackIndex < $1.stackIndex
            }
        }
        if shouldShowEmptySpaces {
            return resultSpaces
        }

        return resultSpaces.filter { !$0.windows.isEmpty }
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        _ = runYabaiCommand(arguments: ["-m", "space", "--focus", spaceId])
        if !needWindowFocus { return }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 0.1
        ) {
            if let spaces = self.getSpacesWithWindows() {
                if let space = spaces.first(where: { $0.id == Int(spaceId) }) {
                    let hasFocused = space.windows.contains { $0.isFocused }
                    if !hasFocused, let firstWindow = space.windows.first {
                        _ = self.runYabaiCommand(arguments: [
                            "-m", "window", "--focus", String(firstWindow.id),
                        ])
                    }
                }
            }
        }
    }

    func focusWindow(windowId: String) {
        _ = runYabaiCommand(arguments: ["-m", "window", "--focus", windowId])
    }

    func deleteSpace(spaceId: String) {
        logger.info("deleteSpace() — destroying yabai space id=\(spaceId, privacy: .public)")
        _ = runYabaiCommand(arguments: ["-m", "space", spaceId, "--destroy"])
    }

    func canDeleteSpace(spaceId: String) -> Bool {
        Int(spaceId) != nil
    }

    private func updateWindowCaches(with liveWindows: [YabaiWindow]) {
        stateLock.lock()
        defer { stateLock.unlock() }

        for window in liveWindows {
            lastKnownWindowsById[window.id] = window

            if !window.isHidden {
                minimizedWindowsById.removeValue(forKey: window.id)
            }
        }
    }

    private func mergeWindows(liveWindows: [YabaiWindow]) -> [YabaiWindow] {
        stateLock.lock()
        defer { stateLock.unlock() }

        var mergedWindows = liveWindows
        let liveWindowIds = Set(liveWindows.map(\.id))

        for (windowId, window) in minimizedWindowsById where !liveWindowIds.contains(windowId) {
            mergedWindows.append(window)
        }

        return mergedWindows
    }
}
