import Foundation
import OSLog

@MainActor
final class HomebrewManager: ObservableObject {
    static let shared = HomebrewManager()

    @Published private(set) var outdatedPackages: [HomebrewPackage] = []
    @Published private(set) var installedCount: Int = 0
    @Published private(set) var brewVersion: String = "—"
    @Published private(set) var lastUpdateDate: Date? = nil
    @Published private(set) var isUpdating: Bool = false
    @Published private(set) var isRunningUpdate: Bool = false
    @Published private(set) var updateProgress: String = ""
    @Published private(set) var updateError: String? = nil
    @Published private(set) var sudoRequiredPackages: Set<String> = []

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "HomebrewManager"
    )

    private var refreshTimer: Timer?
    private var updateProcess: Process?
    let brewPath: String

    // How often to actually hit brew (1 hour)
    private let refreshInterval: TimeInterval = 60 * 60
    private var lastRefreshDate: Date? = nil

    var outdatedCount: Int { outdatedPackages.count }

    // Cache file in ~/Library/Caches/barik/homebrew-cache.json
    private var cacheURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("barik", isDirectory: true)
            .appendingPathComponent("homebrew-cache.json")
    }

    private init() {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            brewPath = "/opt/homebrew/bin/brew"
        } else {
            brewPath = "/usr/local/bin/brew"
        }
        logger.debug("HomebrewManager init, brewPath=\(self.brewPath)")
        loadCache()
        startMonitoring()
    }

    deinit {
        refreshTimer?.invalidate()
        updateProcess?.terminate()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        // Refresh on launch only if cache is stale
        Task { await refreshIfNeeded() }

        // Check every 5 minutes whether an hour has passed
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshIfNeeded() }
        }
    }

    func refreshIfNeeded() async {
        if let last = lastRefreshDate, Date().timeIntervalSince(last) < refreshInterval {
            logger.debug("refreshIfNeeded() skipped — last refresh \(Int(Date().timeIntervalSince(last)))s ago")
            return
        }
        await refresh()
    }

    func refresh() async {
        guard !isRunningUpdate else {
            logger.debug("refresh() skipped — update in progress")
            return
        }
        logger.debug("refresh() started")
        isUpdating = true
        updateError = nil

        async let version    = fetchBrewVersion()
        async let outdated   = fetchOutdatedPackages()
        async let installed  = fetchInstalledCount()
        async let lastUpdate = fetchLastUpdateDate()

        let (v, o, i, u) = await (version, outdated, installed, lastUpdate)

        brewVersion      = v ?? "—"
        outdatedPackages = o
        installedCount   = i
        lastUpdateDate   = u
        isUpdating       = false
        lastRefreshDate  = Date()
        logger.debug("refresh() done — version=\(self.brewVersion) outdated=\(o.count) installed=\(i)")
        saveCache()
    }

    // MARK: - Cache

    private struct CachePayload: Codable {
        let outdatedPackages: [CachedPackage]
        let installedCount: Int
        let brewVersion: String
        let lastUpdateTimestamp: Double?
        let cachedAt: Double

        struct CachedPackage: Codable {
            let name: String
            let versionInfo: String
            let isCask: Bool
        }
    }

    private func saveCache() {
        guard let url = cacheURL else { return }
        let payload = CachePayload(
            outdatedPackages: outdatedPackages.map {
                .init(name: $0.name, versionInfo: $0.versionInfo, isCask: $0.isCask)
            },
            installedCount: installedCount,
            brewVersion: brewVersion,
            lastUpdateTimestamp: lastUpdateDate.map { $0.timeIntervalSince1970 },
            cachedAt: Date().timeIntervalSince1970
        )
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url)
            logger.debug("Cache saved to \(url.path)")
        } catch {
            logger.error("Failed to save cache: \(error.localizedDescription)")
        }
    }

    private func loadCache() {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data)
        else {
            logger.debug("No cache found or failed to load")
            return
        }

        let age = Date().timeIntervalSince1970 - payload.cachedAt
        logger.debug("Cache loaded, age=\(Int(age))s")

        outdatedPackages = payload.outdatedPackages.map {
            HomebrewPackage(name: $0.name, versionInfo: $0.versionInfo, isCask: $0.isCask)
        }
        installedCount = payload.installedCount
        brewVersion    = payload.brewVersion
        lastUpdateDate = payload.lastUpdateTimestamp.map { Date(timeIntervalSince1970: $0) }

        // Mark when we last refreshed from brew (so we don't hit brew immediately)
        if age < refreshInterval {
            lastRefreshDate = Date(timeIntervalSince1970: payload.cachedAt)
        }
    }

    // MARK: - brew update + upgrade with live streaming progress

    func runUpdate() async {
        guard !isRunningUpdate else {
            logger.warning("runUpdate() called while already running")
            return
        }

        isRunningUpdate      = true
        isUpdating           = true
        updateError          = nil
        sudoRequiredPackages = []

        // Phase 1: brew update (refresh formula index)
        logger.info("runUpdate() phase 1: brew update")
        updateProgress = HomebrewProgressPhase.updating
        let updateStatus = await runBrewStreaming(arguments: ["update"], label: "update")

        if updateStatus != 0 {
            logger.error("brew update failed, status=\(updateStatus)")
            updateError     = "brew update exited with status \(updateStatus)"
            isRunningUpdate = false
            updateProgress  = ""
            await refresh()
            return
        }

        // Phase 2: brew upgrade --formula
        logger.info("runUpdate() phase 2: brew upgrade --formula")
        updateProgress = HomebrewProgressPhase.upgradeFormulae
        let formulaStatus = await runBrewStreaming(arguments: ["upgrade", "--formula"], label: "upgrade-formula")
        if formulaStatus != 0 {
            logger.error("brew upgrade --formula failed, status=\(formulaStatus)")
        }

        // Phase 3: brew upgrade --cask (may require sudo for some casks)
        logger.info("runUpdate() phase 3: brew upgrade --cask")
        updateProgress = HomebrewProgressPhase.upgradeCasks
        let (caskStatus, sudoPkgs) = await runBrewStreamingWithSudoDetection(
            arguments: ["upgrade", "--cask"], label: "upgrade-cask"
        )
        if !sudoPkgs.isEmpty {
            logger.warning("runUpdate() sudo required for casks: \(sudoPkgs.joined(separator: ", "))")
            sudoRequiredPackages = Set(sudoPkgs)
        }
        if caskStatus != 0 && sudoPkgs.isEmpty {
            logger.error("brew upgrade --cask failed, status=\(caskStatus)")
            updateError = "brew upgrade --cask exited with status \(caskStatus)"
        }

        isRunningUpdate = false
        updateProgress  = ""
        logger.debug("runUpdate() done, refreshing stats")
        // Force real refresh after upgrade (bypass cache)
        lastRefreshDate = nil
        await refresh()
    }

    // MARK: - Streaming helpers

    private func runBrewStreaming(arguments: [String], label: String) async -> Int32 {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments     = arguments
            process.environment   = brewEnvironment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            var stdoutBuffer = Data()
            var stderrBuffer = Data()

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                self?.logger.debug("[brew \(label) stdout chunk] \(chunk.count) bytes")
                stdoutBuffer.append(chunk)
                for line in brewDrainLines(from: &stdoutBuffer) {
                    self?.logger.debug("[brew \(label) stdout] \(line)")
                    Task { @MainActor [weak self] in self?.updateProgress = line }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                self?.logger.debug("[brew \(label) stderr chunk] \(chunk.count) bytes")
                stderrBuffer.append(chunk)
                for line in brewDrainLines(from: &stderrBuffer) {
                    self?.logger.debug("[brew \(label) stderr] \(line)")
                    Task { @MainActor [weak self] in self?.updateProgress = line }
                }
            }

            process.terminationHandler = { [weak self] proc in
                guard let self else { continuation.resume(returning: proc.terminationStatus); return }
                for line in brewFlushRemaining(&stdoutBuffer) {
                    self.logger.debug("[brew \(label) stdout flush] \(line)")
                    Task { @MainActor [self] in self.updateProgress = line }
                }
                for line in brewFlushRemaining(&stderrBuffer) {
                    self.logger.debug("[brew \(label) stderr flush] \(line)")
                    Task { @MainActor [self] in self.updateProgress = line }
                }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let status = proc.terminationStatus
                self.logger.info("brew \(label) terminated, status=\(status)")
                continuation.resume(returning: status)
            }

            do {
                try process.run()
                logger.info("brew \(label) launched, pid=\(process.processIdentifier)")
                updateProcess = process
            } catch {
                logger.error("Failed to launch brew \(label): \(error.localizedDescription)")
                Task { @MainActor [self] in self.updateError = error.localizedDescription }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }

    private func runBrewStreamingWithSudoDetection(
        arguments: [String], label: String
    ) async -> (status: Int32, sudoPackages: [String]) {
        var detectedSudoPackages: [String] = []
        var lastPackageName: String? = nil

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments     = arguments
            process.environment   = brewEnvironment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            var stdoutBuffer = Data()
            var stderrBuffer = Data()

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stdoutBuffer.append(chunk)
                for line in brewDrainLines(from: &stdoutBuffer) {
                    self?.logger.debug("[brew \(label) stdout] \(line)")
                    if line.hasPrefix("==> Upgrading ") {
                        lastPackageName = line
                            .replacingOccurrences(of: "==> Upgrading ", with: "")
                            .components(separatedBy: " ").first?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    Task { @MainActor [weak self] in self?.updateProgress = line }
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stderrBuffer.append(chunk)
                for line in brewDrainLines(from: &stderrBuffer) {
                    self?.logger.debug("[brew \(label) stderr] \(line)")
                    let isSudoError = line.contains("sudo") &&
                        (line.contains("password is required") || line.contains("terminal is required"))
                    if isSudoError {
                        if line.hasPrefix("Error:"),
                           let colonRange = line.range(of: ": "),
                           let nextColon = line[colonRange.upperBound...].range(of: ":") {
                            let name = String(line[colonRange.upperBound..<nextColon.lowerBound])
                                .trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty && !name.contains(" ") {
                                detectedSudoPackages.append(name)
                                self?.logger.warning("[brew \(label)] sudo required for: \(name)")
                            }
                        } else if let pkg = lastPackageName {
                            if !detectedSudoPackages.contains(pkg) {
                                detectedSudoPackages.append(pkg)
                                self?.logger.warning("[brew \(label)] sudo required for: \(pkg)")
                            }
                        }
                    }
                    Task { @MainActor [weak self] in self?.updateProgress = line }
                }
            }

            process.terminationHandler = { [weak self] proc in
                guard let self else { continuation.resume(returning: proc.terminationStatus); return }
                for line in brewFlushRemaining(&stdoutBuffer) {
                    self.logger.debug("[brew \(label) stdout flush] \(line)")
                    Task { @MainActor [self] in self.updateProgress = line }
                }
                for line in brewFlushRemaining(&stderrBuffer) {
                    self.logger.debug("[brew \(label) stderr flush] \(line)")
                    Task { @MainActor [self] in self.updateProgress = line }
                }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                self.logger.info("brew \(label) terminated, status=\(proc.terminationStatus)")
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                try process.run()
                logger.info("brew \(label) launched, pid=\(process.processIdentifier)")
                updateProcess = process
            } catch {
                logger.error("Failed to launch brew \(label): \(error.localizedDescription)")
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: -1)
            }
        }

        return (status, detectedSudoPackages)
    }

    // MARK: - Data fetchers

    private var brewEnvironment: [String: String] {
        [
            "PATH":                    "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME":                    FileManager.default.homeDirectoryForCurrentUser.path,
            "HOMEBREW_COLOR":          "0",
            "HOMEBREW_NO_ENV_HINTS":   "1",
            "HOMEBREW_NO_AUTO_UPDATE": "1"
        ]
    }

    private func fetchBrewVersion() async -> String? {
        logger.debug("fetchBrewVersion()")
        let output = await runBrewCommand(["--version"])
        return output?.components(separatedBy: "\n").first?
            .replacingOccurrences(of: "Homebrew ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func fetchOutdatedPackages() async -> [HomebrewPackage] {
        logger.debug("fetchOutdatedPackages()")
        async let formulaOut = runBrewCommand(["outdated", "--formula", "--verbose"])
        async let caskOut    = runBrewCommand(["outdated", "--cask", "--verbose"])
        let (fo, co) = await (formulaOut, caskOut)

        var packages: [HomebrewPackage] = []
        if let out = fo {
            for line in out.components(separatedBy: "\n").filter({ !$0.isEmpty }) {
                let parts = line.components(separatedBy: " ")
                packages.append(HomebrewPackage(name: parts.first ?? line,
                                                versionInfo: parts.dropFirst().joined(separator: " "),
                                                isCask: false))
            }
        }
        if let out = co {
            for line in out.components(separatedBy: "\n").filter({ !$0.isEmpty }) {
                let parts = line.components(separatedBy: " ")
                packages.append(HomebrewPackage(name: parts.first ?? line,
                                                versionInfo: parts.dropFirst().joined(separator: " "),
                                                isCask: true))
            }
        }
        logger.debug("fetchOutdatedPackages() found \(packages.count) outdated (\(packages.filter{$0.isCask}.count) casks)")
        return packages
    }

    private func fetchInstalledCount() async -> Int {
        logger.debug("fetchInstalledCount()")
        guard let output = await runBrewCommand(["list", "--formula"]) else { return 0 }
        let count = output.components(separatedBy: "\n").filter { !$0.isEmpty }.count
        logger.debug("fetchInstalledCount() = \(count)")
        return count
    }

    private func fetchLastUpdateDate() async -> Date? {
        logger.debug("fetchLastUpdateDate()")
        let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew")
            ? "/opt/homebrew" : "/usr/local/Homebrew"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments     = ["-C", brewPrefix, "log", "-1", "--format=%ct"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let ts = Double(str) {
                let date = Date(timeIntervalSince1970: ts)
                logger.debug("fetchLastUpdateDate() = \(date)")
                return date
            }
        } catch {
            logger.error("fetchLastUpdateDate git error: \(error.localizedDescription)")
        }
        return nil
    }

    @discardableResult
    private func runBrewCommand(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { continuation.resume(returning: nil); return }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.brewPath)
                process.arguments     = arguments
                process.environment   = [
                    "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
                    "HOME": FileManager.default.homeDirectoryForCurrentUser.path
                ]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError  = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data   = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)
                    self.logger.debug("runBrewCommand(\(arguments.joined(separator: " "))) status=\(process.terminationStatus)")
                    continuation.resume(returning: output)
                } catch {
                    self.logger.error("runBrewCommand(\(arguments.joined(separator: " "))) error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// Internal progress phase markers (used by popup to detect current phase)
enum HomebrewProgressPhase {
    static let updating        = "Updating Homebrew…"
    static let upgradeFormulae = "Upgrading formulae…"
    static let upgradeCasks    = "Upgrading casks…"
}

struct HomebrewPackage: Identifiable {
    let id         = UUID()
    let name: String
    let versionInfo: String
    let isCask: Bool
}

// MARK: - Free helpers (no actor isolation — safe on any thread)

private func brewDrainLines(from buffer: inout Data) -> [String] {
    var lines: [String] = []
    while let newlineIdx = buffer.firstIndex(of: UInt8(ascii: "\n")) {
        let lineData = buffer[buffer.startIndex...newlineIdx]
        buffer.removeSubrange(buffer.startIndex...newlineIdx)
        if let raw = String(data: lineData, encoding: .utf8) {
            let line = brewStripAnsi(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { lines.append(line) }
        }
    }
    return lines
}

private func brewFlushRemaining(_ buffer: inout Data) -> [String] {
    guard !buffer.isEmpty,
          let raw = String(data: buffer, encoding: .utf8) else { return [] }
    buffer.removeAll()
    let line = brewStripAnsi(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    return line.isEmpty ? [] : [line]
}

private func brewStripAnsi(_ input: String) -> String {
    var result = ""
    var i = input.startIndex
    while i < input.endIndex {
        if input[i] == "\u{1B}" {
            let next = input.index(after: i)
            if next < input.endIndex && input[next] == "[" {
                i = input.index(after: next)
                while i < input.endIndex && !input[i].isLetter { i = input.index(after: i) }
                if i < input.endIndex { i = input.index(after: i) }
                continue
            }
        }
        result.append(input[i])
        i = input.index(after: i)
    }
    return result
}
