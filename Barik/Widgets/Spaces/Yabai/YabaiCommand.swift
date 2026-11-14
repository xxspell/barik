import Foundation

/// Runs a `yabai -m ...` client command with a hard timeout.
///
/// The yabai client blocks in `read()` on the server socket until the server
/// answers. If the server drops a request (seen right after yabai restarts),
/// the client never exits, and without a timeout every caller that waits on it
/// — and every later refresh queued behind it — freezes, so the spaces widget
/// goes blank until Barik is restarted.
enum YabaiCommand {
    static let defaultTimeout: TimeInterval = 3

    /// Returns the command's stdout (and stderr if `mergeStderr`), or nil when
    /// the process can't start or is killed by the timeout.
    static func run(
        executablePath: String,
        arguments: [String],
        mergeStderr: Bool = false,
        timeout: TimeInterval = defaultTimeout
    ) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        if mergeStderr {
            process.standardError = pipe
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let lock = NSLock()
        var timedOut = false
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            lock.lock()
            timedOut = true
            lock.unlock()
            process.terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Terminating the client closes its end of the pipe, so this returns.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        lock.lock()
        defer { lock.unlock() }
        return timedOut ? nil : data
    }
}
