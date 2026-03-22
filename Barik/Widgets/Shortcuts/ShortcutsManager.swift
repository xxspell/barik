import Foundation
import OSLog

struct ShortcutItem: Identifiable, Equatable, Hashable {
    let name: String
    let folderName: String?

    var id: String {
        if let folderName {
            return "\(folderName)::\(name)"
        }
        return "none::\(name)"
    }
}

struct ShortcutFolderSection: Identifiable, Equatable {
    static let allID = "__all__"
    static let uncategorizedID = "__none__"

    let id: String
    let title: String
    let shortcuts: [ShortcutItem]
    let isUncategorized: Bool
}

private struct ShortcutsCommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

@MainActor
final class ShortcutsManager: ObservableObject {
    static let shared = ShortcutsManager()

    @Published private(set) var sections: [ShortcutFolderSection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRunningShortcut = false
    @Published private(set) var runningShortcutID: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefreshDate: Date?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "ShortcutsManager"
    )

    private let shortcutsExecutablePath = "/usr/bin/shortcuts"

    private var hasStarted = false
    private var folderAllowList: Set<String> = []
    private var folderDenyList: Set<String> = []
    private var shortcutDenyList: Set<String> = []

    private init() {}

    func startUpdating(config: ConfigData) {
        updateConfiguration(config: config)

        guard !hasStarted else { return }
        hasStarted = true
        logger.debug("startUpdating() — initial refresh scheduled")

        Task {
            await refresh()
        }
    }

    func updateConfiguration(config: ConfigData) {
        folderAllowList = normalizedSet(
            primary: config["include-folders"],
            fallback: config["folder-allow-list"]
        )
        folderDenyList = normalizedSet(
            primary: config["exclude-folders"],
            fallback: config["folder-deny-list"]
        )
        shortcutDenyList = normalizedSet(
            primary: config["exclude-shortcuts"],
            fallback: config["shortcut-deny-list"]
        )

        logger.debug(
            "updateConfiguration() — folderAllowList=\(self.folderAllowList.count) folderDenyList=\(self.folderDenyList.count) shortcutDenyList=\(self.shortcutDenyList.count)"
        )
    }

    func refresh() async {
        guard !isLoading else {
            logger.debug("refresh() skipped — already loading")
            return
        }

        guard FileManager.default.isExecutableFile(atPath: shortcutsExecutablePath) else {
            errorMessage = String(localized: "shortcuts.error.cli_unavailable")
            logger.error("refresh() failed — shortcuts executable missing at \(self.shortcutsExecutablePath)")
            return
        }

        isLoading = true
        errorMessage = nil
        logger.debug("refresh() — started")

        do {
            let fetchedSections = try await fetchSections()
            sections = fetchedSections
            lastRefreshDate = Date()
            logger.debug("refresh() — loaded \(fetchedSections.count) sections")
        } catch {
            errorMessage = error.localizedDescription
            logger.error("refresh() failed — \(error.localizedDescription)")
        }

        isLoading = false
    }

    func run(shortcut: ShortcutItem) async {
        guard !isRunningShortcut else {
            logger.debug("run(shortcut:) skipped — another shortcut is running")
            return
        }

        isRunningShortcut = true
        runningShortcutID = shortcut.id
        errorMessage = nil
        logger.info("run(shortcut:) — starting \(shortcut.name, privacy: .public)")

        do {
            let result = try await runShortcutsCommand(arguments: ["run", shortcut.name])
            guard result.status == 0 else {
                throw ShortcutsManagerError.commandFailed(
                    result.stderr.isEmpty ? result.stdout : result.stderr
                )
            }
            logger.info("run(shortcut:) — finished \(shortcut.name, privacy: .public)")
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("run(shortcut:) failed — \(shortcut.name, privacy: .public) — \(error.localizedDescription)")
        }

        isRunningShortcut = false
        runningShortcutID = nil
    }

    func isShortcutRunning(_ shortcut: ShortcutItem) -> Bool {
        runningShortcutID == shortcut.id
    }

    private func fetchSections() async throws -> [ShortcutFolderSection] {
        let allFolderNames = try await fetchFolderNames()
        let folderNames = filteredFolderNames(from: allFolderNames)
        let shouldIncludeUncategorized = shouldIncludeUncategorizedSection(allFolderNames: allFolderNames)

        var sections: [ShortcutFolderSection] = []

        for folderName in folderNames {
            let shortcuts = try await fetchShortcuts(inFolderNamed: folderName)
            guard !shortcuts.isEmpty else { continue }
            sections.append(
                ShortcutFolderSection(
                    id: folderName,
                    title: folderName,
                    shortcuts: shortcuts,
                    isUncategorized: false
                )
            )
        }

        if shouldIncludeUncategorized {
            let shortcuts = try await fetchShortcuts(inFolderNamed: nil)
            if !shortcuts.isEmpty {
                sections.append(
                    ShortcutFolderSection(
                        id: ShortcutFolderSection.uncategorizedID,
                        title: String(localized: "shortcuts.folder.none"),
                        shortcuts: shortcuts,
                        isUncategorized: true
                    )
                )
            }
        }

        return sections
    }

    private func fetchFolderNames() async throws -> [String] {
        let result = try await runShortcutsCommand(arguments: ["list", "--folders"])
        guard result.status == 0 else {
            throw ShortcutsManagerError.commandFailed(
                result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }

        let folders = parseOutputLines(result.stdout)
        logger.debug("fetchFolderNames() — loaded \(folders.count) folders")
        return folders
    }

    private func fetchShortcuts(inFolderNamed folderName: String?) async throws -> [ShortcutItem] {
        var arguments = ["list"]
        if let folderName {
            arguments.append(contentsOf: ["--folder-name", folderName])
        } else {
            arguments.append(contentsOf: ["--folder-name", "none"])
        }

        let result = try await runShortcutsCommand(arguments: arguments)
        guard result.status == 0 else {
            throw ShortcutsManagerError.commandFailed(
                result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }

        let shortcuts = parseOutputLines(result.stdout)
            .filter { !isShortcutDenied($0) }
            .map { ShortcutItem(name: $0, folderName: folderName) }

        logger.debug(
            "fetchShortcuts(inFolderNamed:) — folder=\(folderName ?? "none", privacy: .public) count=\(shortcuts.count)"
        )

        return shortcuts
    }

    private func filteredFolderNames(from folderNames: [String]) -> [String] {
        if !folderAllowList.isEmpty {
            return folderNames.filter { folderAllowList.contains(normalizedName($0)) }
        }

        if folderDenyList.isEmpty {
            return folderNames
        }

        return folderNames.filter { !folderDenyList.contains(normalizedName($0)) }
    }

    private func shouldIncludeUncategorizedSection(allFolderNames: [String]) -> Bool {
        if !folderAllowList.isEmpty {
            return folderAllowList.contains(ShortcutFolderSection.uncategorizedID)
                || folderAllowList.contains("none")
        }

        return !folderDenyList.contains(ShortcutFolderSection.uncategorizedID)
            && !folderDenyList.contains("none")
    }

    private func isShortcutDenied(_ name: String) -> Bool {
        shortcutDenyList.contains(normalizedName(name))
    }

    private func normalizedSet(primary: TOMLValue?, fallback: TOMLValue?) -> Set<String> {
        let value = primary ?? fallback

        return Set(
            (value?.arrayValue ?? [])
                .compactMap(\.stringValue)
                .map(normalizedName(_:))
        )
    }

    private func normalizedName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func parseOutputLines(_ output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func runShortcutsCommand(arguments: [String]) async throws -> ShortcutsCommandResult {
        logger.debug("runShortcutsCommand() — arguments=\(arguments.joined(separator: " "), privacy: .public)")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shortcutsExecutablePath)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(decoding: stdoutData, as: UTF8.self)
                let stderr = String(decoding: stderrData, as: UTF8.self)

                continuation.resume(
                    returning: ShortcutsCommandResult(
                        status: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private enum ShortcutsManagerError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "shortcuts.error.command_failed") : trimmed
        }
    }
}
