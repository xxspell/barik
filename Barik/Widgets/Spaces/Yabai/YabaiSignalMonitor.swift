import Darwin
import Foundation
import OSLog

struct YabaiSignalEvent {
    let name: String
    let windowId: Int?
    let spaceId: Int?
}

final class YabaiSignalMonitor {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "YabaiSignalMonitor"
    )

    private let executablePath: String
    private let queue = DispatchQueue(label: "barik.yabai.signal-monitor", qos: .utility)
    private let callbackQueue = DispatchQueue.main
    private let socketPath = "/tmp/barik-yabai-events.sock"
    private let labelPrefix = "barik-signal"
    private let debounceInterval: TimeInterval = 0.08
    private let events = [
        "application_hidden",
        "application_launched",
        "application_terminated",
        "application_visible",
        "display_added",
        "display_changed",
        "display_moved",
        "display_removed",
        "display_resized",
        "dock_did_restart",
        "space_changed",
        "space_created",
        "space_destroyed",
        "system_woke",
        "window_created",
        "window_deminimized",
        "window_destroyed",
        "window_focused",
        "window_minimized",
        "window_moved",
        "window_resized",
        "window_title_changed",
    ]

    private var listenFileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var debounceWorkItem: DispatchWorkItem?
    private let onEvent: (YabaiSignalEvent?) -> Void
    private var isRunning = false

    init(executablePath: String, onEvent: @escaping (YabaiSignalEvent?) -> Void) {
        self.executablePath = executablePath
        self.onEvent = onEvent
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }

            do {
                try self.startSocketServer()
                self.registerSignals()
                self.isRunning = true
            } catch {
                self.logger.error("Unable to start yabai signal monitor: \(error.localizedDescription)")
                self.stopLocked()
            }
        }
    }

    func stop() {
        queue.sync {
            stopLocked()
        }
    }

    private func stopLocked() {
        guard isRunning || listenFileDescriptor != -1 || readSource != nil else { return }

        unregisterSignals()
        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        readSource?.cancel()
        readSource = nil

        if listenFileDescriptor != -1 {
            close(listenFileDescriptor)
            listenFileDescriptor = -1
        }

        unlink(socketPath)
        isRunning = false
    }

    private func startSocketServer() throws {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.EIO)
        }

        var value = fcntl(fd, F_GETFL, 0)
        guard value != -1, fcntl(fd, F_SETFL, value | O_NONBLOCK) != -1 else {
            close(fd)
            throw POSIXError(.EIO)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < maxPathLength else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }

        withUnsafeMutablePointer(to: &address.sun_path) { pathPointer in
            socketPath.withCString { socketCString in
                strncpy(UnsafeMutableRawPointer(pathPointer).assumingMemoryBound(to: CChar.self), socketCString, maxPathLength - 1)
            }
        }

        let length = socklen_t(MemoryLayout<sa_family_t>.size + socketPath.utf8.count + 1)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, length)
            }
        }

        guard bindResult == 0, listen(fd, 8) == 0 else {
            close(fd)
            unlink(socketPath)
            throw POSIXError(.EIO)
        }

        listenFileDescriptor = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.listenFileDescriptor != -1 {
                close(self.listenFileDescriptor)
                self.listenFileDescriptor = -1
            }
        }
        readSource = source
        source.resume()
    }

    private func acceptPendingConnections() {
        while true {
            let clientFD = accept(listenFileDescriptor, nil, nil)
            if clientFD == -1 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                }
                logger.error("accept() failed for yabai signal socket")
                break
            }

            var buffer = [UInt8](repeating: 0, count: 128)
            let bytesRead = read(clientFD, &buffer, buffer.count)
            close(clientFD)

            let event = bytesRead > 0
                ? parseEvent(from: Data(buffer.prefix(Int(bytesRead))))
                : nil

            if let event {
                logger.debug(
                    "Received yabai event: \(event.name, privacy: .public) windowId=\(String(event.windowId ?? -1), privacy: .public) spaceId=\(String(event.spaceId ?? -1), privacy: .public)"
                )
            }

            scheduleRefresh(event: event)
        }
    }

    private func scheduleRefresh(event: YabaiSignalEvent?) {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.callbackQueue.async {
                self.onEvent(event)
            }
        }

        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func registerSignals() {
        for event in events {
            let label = signalLabel(for: event)
            _ = runYabaiCommand(arguments: ["-m", "signal", "--remove", label])

            let action =
                "/usr/bin/printf '%s\\t%s\\t%s\\n' '\(event)' \"$YABAI_WINDOW_ID\" \"$YABAI_SPACE_ID\" | /usr/bin/nc -U \(socketPath)"
            _ = runYabaiCommand(arguments: [
                "-m", "signal", "--add",
                "event=\(event)",
                "label=\(label)",
                "action=\(action)",
            ])
        }
    }

    private func unregisterSignals() {
        for event in events {
            _ = runYabaiCommand(arguments: ["-m", "signal", "--remove", signalLabel(for: event)])
        }
    }

    private func signalLabel(for event: String) -> String {
        "\(labelPrefix)-\(event)"
    }

    private func parseEvent(from data: Data) -> YabaiSignalEvent? {
        guard
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }

        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false)
        guard let name = parts.first.map(String.init), !name.isEmpty else {
            return nil
        }

        let windowId = parts.count > 1 ? Int(parts[1]) : nil
        let spaceId = parts.count > 2 ? Int(parts[2]) : nil
        return YabaiSignalEvent(name: name, windowId: windowId, spaceId: spaceId)
    }

    @discardableResult
    private func runYabaiCommand(arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            logger.error("Unable to run yabai command: \(error.localizedDescription)")
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}
