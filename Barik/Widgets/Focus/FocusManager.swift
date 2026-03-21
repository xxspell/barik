import AppKit
import Foundation
import OSLog
import SwiftUI

struct FocusMode: Identifiable, Equatable {
    let id: String
    let name: String
    let symbolName: String
    let tintColorName: String?
    let isActive: Bool

    var tintColor: Color? {
        guard let tintColorName else { return nil }
        return Color(nsColorName: tintColorName)
    }

    var resolvedSymbolName: String {
        FocusSymbolResolver.resolve(symbolName, modeID: id)
    }
}

@MainActor
final class FocusManager: ObservableObject {
    static let shared = FocusManager()

    @Published private(set) var modes: [FocusMode] = []
    @Published private(set) var activeMode: FocusMode?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "FocusManager"
    )
    private let fileManager = FileManager.default
    private let dbDirectoryURL = URL(
        fileURLWithPath: NSString(string: "~/Library/DoNotDisturb/DB").expandingTildeInPath,
        isDirectory: true
    )
    private let modeConfigurationsURL: URL
    private let assertionsURL: URL

    private var directoryWatchSource: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: CInt = -1
    private var refreshTimer: Timer?
    private var pendingRefreshWorkItem: DispatchWorkItem?

    private init() {
        modeConfigurationsURL = dbDirectoryURL.appendingPathComponent("ModeConfigurations.json")
        assertionsURL = dbDirectoryURL.appendingPathComponent("Assertions.json")

        refresh()
        startWatchingFiles()
        startPolling()
    }

    deinit {
        pendingRefreshWorkItem?.cancel()
        refreshTimer?.invalidate()
        directoryWatchSource?.cancel()
        if directoryFileDescriptor != -1 {
            close(directoryFileDescriptor)
        }
    }

    func refresh() {
        logger.debug("refresh() started")
        let modeSnapshots = loadAvailableModes()
        let activeModeID = loadActiveModeIdentifier()

        let resolvedModes = modeSnapshots
            .map { snapshot in
                FocusMode(
                    id: snapshot.id,
                    name: snapshot.name,
                    symbolName: snapshot.symbolName,
                    tintColorName: snapshot.tintColorName,
                    isActive: snapshot.id == activeModeID
                )
            }
            .sorted { lhs, rhs in
                if lhs.id == activeModeID, rhs.id != activeModeID {
                    return true
                }

                if rhs.id == activeModeID, lhs.id != activeModeID {
                    return false
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        modes = resolvedModes
        activeMode = resolvedModes.first(where: \.isActive)
        logger.debug(
            "refresh() done — modes=\(resolvedModes.count) activeModeID=\(activeModeID ?? "none", privacy: .public)"
        )
    }

    private func startWatchingFiles() {
        guard directoryWatchSource == nil else { return }

        directoryFileDescriptor = open(dbDirectoryURL.path, O_EVTONLY)
        guard directoryFileDescriptor != -1 else {
            logger.error("Unable to watch Focus DB directory: \(self.dbDirectoryURL.path, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.scheduleRefresh()
        }

        source.setCancelHandler { [weak self] in
            guard let self, self.directoryFileDescriptor != -1 else { return }
            close(self.directoryFileDescriptor)
            self.directoryFileDescriptor = -1
        }

        directoryWatchSource = source
        source.resume()
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func scheduleRefresh() {
        pendingRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }

        pendingRefreshWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + .milliseconds(180),
            execute: workItem
        )
    }

    private func loadAvailableModes() -> [FocusModeSnapshot] {
        guard fileManager.fileExists(atPath: modeConfigurationsURL.path) else {
            logger.error("ModeConfigurations.json not found at \(self.modeConfigurationsURL.path, privacy: .public)")
            return []
        }

        do {
            let data = try Data(contentsOf: modeConfigurationsURL)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payloads = root["data"] as? [[String: Any]]
            else {
                logger.error("Unable to decode Focus modes JSON payload.")
                return []
            }

            var seen = Set<String>()
            var result: [FocusModeSnapshot] = []

            for payload in payloads {
                guard let configurations = payload["modeConfigurations"] as? [String: Any] else {
                    continue
                }

                for (fallbackID, rawConfiguration) in configurations {
                    guard let configuration = rawConfiguration as? [String: Any],
                          let mode = configuration["mode"] as? [String: Any]
                    else {
                        continue
                    }

                    let id = (mode["modeIdentifier"] as? String) ?? fallbackID
                    guard !id.isEmpty, !seen.contains(id) else { continue }

                    let name = (mode["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let symbolName = (mode["symbolImageName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let tintColorName = mode["tintColorName"] as? String

                    guard let name, !name.isEmpty else { continue }

                    result.append(
                        FocusModeSnapshot(
                            id: id,
                            name: name,
                            symbolName: (symbolName?.isEmpty == false ? symbolName! : "moon.fill"),
                            tintColorName: tintColorName
                        )
                    )
                    seen.insert(id)
                }
            }

            return result.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        } catch {
            logger.error("Failed to read Focus modes: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func loadActiveModeIdentifier() -> String? {
        guard fileManager.fileExists(atPath: assertionsURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: assertionsURL)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payloads = root["data"] as? [[String: Any]]
            else {
                return nil
            }

            var latestActiveAssertion: (modeID: String, startedAt: Double)?

            for payload in payloads {
                guard let records = payload["storeAssertionRecords"] as? [[String: Any]] else {
                    continue
                }

                for record in records {
                    let assertion =
                        (record["assertion"] as? [String: Any])
                        ?? (record["storeAssertion"] as? [String: Any])
                        ?? record

                    guard let details = assertion["assertionDetails"] as? [String: Any],
                          let modeID = details["assertionDetailsModeIdentifier"] as? String
                    else {
                        continue
                    }

                    let startedAt = assertion["assertionStartDateTimestamp"] as? Double ?? 0
                    if latestActiveAssertion == nil || startedAt > latestActiveAssertion!.startedAt {
                        latestActiveAssertion = (modeID, startedAt)
                    }
                }
            }

            return latestActiveAssertion?.modeID
        } catch {
            logger.error("Failed to read Focus assertions: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

private struct FocusModeSnapshot {
    let id: String
    let name: String
    let symbolName: String
    let tintColorName: String?
}

private enum FocusSymbolResolver {
    private static let explicitFallbacks: [String: String] = [
        "moon.slash.fill": "moon.fill",
        "person.lanyardcard.fill": "briefcase.fill"
    ]

    private static let semanticFallbacks: [(fragment: String, replacement: String)] = [
        ("sleep", "bed.double.fill"),
        ("work", "briefcase.fill"),
        ("reading", "book.fill"),
        ("personal", "person.fill"),
        ("fitness", "figure.run"),
        ("driving", "car.fill")
    ]

    static func resolve(_ rawSymbolName: String, modeID: String) -> String {
        let preferred = explicitFallbacks[rawSymbolName] ?? rawSymbolName
        if isAvailable(preferred) {
            return preferred
        }

        for (fragment, replacement) in semanticFallbacks where modeID.localizedCaseInsensitiveContains(fragment) {
            if isAvailable(replacement) {
                return replacement
            }
        }

        return isAvailable("moon.fill") ? "moon.fill" : "circle.fill"
    }

    private static func isAvailable(_ symbolName: String) -> Bool {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil
    }
}

extension Color {
    init?(nsColorName: String) {
        guard let nsColor = NSColor.focusTint(named: nsColorName) else { return nil }
        self.init(nsColor: nsColor)
    }

    func lightened(by amount: CGFloat) -> Color {
        let nsColor = NSColor(self)
        return Color(nsColor: nsColor.lightened(by: amount))
    }
}

extension NSColor {
    static func focusTint(named name: String) -> NSColor? {
        switch name {
        case "systemBlueColor":
            .systemBlue
        case "systemBrownColor":
            .systemBrown
        case "systemCyanColor":
            .systemCyan
        case "systemGrayColor":
            .systemGray
        case "systemGreenColor":
            .systemGreen
        case "systemIndigoColor":
            .systemIndigo
        case "systemMintColor":
            .systemMint
        case "systemOrangeColor":
            .systemOrange
        case "systemPinkColor":
            .systemPink
        case "systemPurpleColor":
            .systemPurple
        case "systemRedColor":
            .systemRed
        case "systemTealColor":
            .systemTeal
        case "systemYellowColor":
            .systemYellow
        default:
            nil
        }
    }

    func lightened(by amount: CGFloat) -> NSColor {
        let clamped = max(0, min(amount, 1))
        let rgb = usingColorSpace(.deviceRGB) ?? self
        let blended = rgb.blended(withFraction: clamped, of: .white) ?? rgb
        return blended
    }
}
