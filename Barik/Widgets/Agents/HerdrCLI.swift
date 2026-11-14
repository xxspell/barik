import Foundation

enum HerdrCLIError: Error, Equatable {
    case notFound
    case timeout
    case failed(status: Int32, stderr: String)
}

/// Fallback when the herdr socket protocol is unavailable: runs the `herdr` CLI.
enum HerdrCLI {
    static let defaultSearchDirs: [String] = {
        let home = NSHomeDirectory()
        var dirs = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for d in path.split(separator: ":").map(String.init) where !d.isEmpty && !dirs.contains(d) {
            dirs.append(d)
        }
        return dirs
    }()

    static func resolveExecutable(_ configured: String, extraDirs: [String] = defaultSearchDirs) -> String? {
        let fm = FileManager.default
        if configured.contains("/") {
            let p = (configured as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: p) ? p : nil
        }
        guard !configured.isEmpty else { return nil }
        for dir in extraDirs {
            let p = (dir as NSString).expandingTildeInPath + "/" + configured
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue, fm.isExecutableFile(atPath: p) {
                return p
            }
        }
        return nil
    }

    static func agentList(executable: String, timeout: TimeInterval = 5) async throws -> [AgentSession] {
        let out = try await run(executable, ["agent", "list"], timeout: timeout)
        return try HerdrParser.parseAgentList(out)
    }

    static func version(executable: String) async -> String? {
        guard let out = try? await run(executable, ["--version"], timeout: 5),
              let s = String(data: out, encoding: .utf8) else { return nil }
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let parts = line.split(separator: " ").map(String.init)
        if parts.count >= 2, parts[0] == "herdr" { return parts[1] }
        return nil
    }

    // MARK: - Process runner

    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()
        private var finished = false
        func appendOut(_ d: Data) { lock.lock(); out.append(d); lock.unlock() }
        func appendErr(_ d: Data) { lock.lock(); err.append(d); lock.unlock() }
        func snapshot() -> (Data, Data) { lock.lock(); defer { lock.unlock() }; return (out, err) }
        /// Returns true exactly once.
        func finish() -> Bool { lock.lock(); defer { lock.unlock() }; if finished { return false }; finished = true; return true }
    }

    private static func run(_ executable: String, _ args: [String], timeout: TimeInterval) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw HerdrCLIError.notFound }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = args
            let outPipe = Pipe(), errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            proc.standardInput = FileHandle.nullDevice
            let state = RunState()
            let readers = DispatchGroup()

            func drain(_ pipe: Pipe, _ sink: @escaping (Data) -> Void) {
                readers.enter()
                DispatchQueue.global().async {
                    let h = pipe.fileHandleForReading
                    while true {
                        let d = h.availableData
                        if d.isEmpty { break }
                        sink(d)
                    }
                    readers.leave()
                }
            }

            proc.terminationHandler = { p in
                let status = p.terminationStatus
                // Wait for EOF on both pipes, but not forever (grandchildren may hold them open).
                DispatchQueue.global().async {
                    _ = readers.wait(timeout: .now() + 1)
                    guard state.finish() else { return }
                    let (o, e) = state.snapshot()
                    if status == 0 {
                        cont.resume(returning: o)
                    } else {
                        let msg = String(data: e, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        cont.resume(throwing: HerdrCLIError.failed(status: status, stderr: msg))
                    }
                }
            }

            do { try proc.run() } catch {
                if state.finish() { cont.resume(throwing: HerdrCLIError.notFound) }
                return
            }
            // Parent's copy of the write ends must be closed so readers see EOF.
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()
            drain(outPipe, state.appendOut)
            drain(errPipe, state.appendErr)

            let pid = proc.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard state.finish() else { return }
                proc.terminate()
                cont.resume(throwing: HerdrCLIError.timeout)
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if proc.isRunning { kill(pid, SIGKILL) }
                }
            }
        }
    }
}
