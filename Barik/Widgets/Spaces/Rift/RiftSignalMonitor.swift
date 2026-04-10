import Darwin
import Foundation
import OSLog

final class RiftSignalMonitor {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "RiftSignalMonitor"
    )

    private let executablePath: String
    private let queue = DispatchQueue(label: "barik.rift.signal-monitor", qos: .utility)
    private let queueSpecificKey = DispatchSpecificKey<Void>()
    private let callbackQueue = DispatchQueue.main
    private let debounceInterval: TimeInterval = 0.08

    private var subscriptionProcess: Process?
    private var outputPipe: Pipe?
    private var readSource: DispatchSourceRead?
    private var debounceWorkItem: DispatchWorkItem?
    private var reconnectWorkItem: DispatchWorkItem?
    private var bufferedOutput = Data()
    private var reconnectAttempt = 0
    private var isRunning = false

    private let onEvent: () -> Void

    init(executablePath: String, onEvent: @escaping () -> Void) {
        self.executablePath = executablePath
        self.onEvent = onEvent
        queue.setSpecific(key: queueSpecificKey, value: ())
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.reconnectAttempt = 0
            self.startSubscriptionLocked()
        }
    }

    func stop() {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            stopLocked()
            return
        }

        queue.sync {
            stopLocked()
        }
    }

    private func stopLocked() {
        guard isRunning || subscriptionProcess != nil || readSource != nil else {
            return
        }

        isRunning = false
        reconnectAttempt = 0
        bufferedOutput.removeAll(keepingCapacity: false)

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        debounceWorkItem?.cancel()
        debounceWorkItem = nil

        stopSubscriptionLocked(terminateProcess: true)
    }

    private func startSubscriptionLocked() {
        guard isRunning else { return }

        stopSubscriptionLocked(terminateProcess: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["subscribe", "mach", "*"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.queue.async {
                self.handleProcessTermination(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            logger.error("Unable to start Rift mach subscription: \(error.localizedDescription)")
            scheduleReconnectLocked()
            return
        }

        subscriptionProcess = process
        outputPipe = pipe
        bufferedOutput.removeAll(keepingCapacity: true)
        attachReadSourceLocked(to: pipe.fileHandleForReading.fileDescriptor)

        logger.debug("Started Rift mach subscription")
    }

    private func stopSubscriptionLocked(terminateProcess: Bool) {
        readSource?.cancel()
        readSource = nil

        if let process = subscriptionProcess, terminateProcess, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }

        subscriptionProcess = nil

        if let outputPipe {
            outputPipe.fileHandleForReading.closeFile()
        }
        self.outputPipe = nil
    }

    private func attachReadSourceLocked(to fileDescriptor: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)

        source.setEventHandler { [weak self] in
            guard let self, let outputPipe = self.outputPipe else { return }
            let data = outputPipe.fileHandleForReading.availableData
            if data.isEmpty {
                self.readSource?.cancel()
                self.readSource = nil
                return
            }
            self.handleIncomingChunk(data)
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            self.readSource = nil
        }

        readSource = source
        source.resume()
    }

    private func handleIncomingChunk(_ data: Data) {
        bufferedOutput.append(data)
        scheduleRefreshLocked()

        while let newlineRange = bufferedOutput.firstRange(of: Data([0x0A])) {
            let lineData = bufferedOutput.subdata(in: bufferedOutput.startIndex..<newlineRange.lowerBound)
            bufferedOutput.removeSubrange(bufferedOutput.startIndex...newlineRange.lowerBound)

            guard
                let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty
            else {
                continue
            }

            logger.debug("Rift mach event: \(line, privacy: .public)")
            scheduleRefreshLocked()
        }
    }

    private func scheduleRefreshLocked() {
        debounceWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.callbackQueue.async {
                self.onEvent()
            }
        }

        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    private func handleProcessTermination(status: Int32) {
        if isRunning {
            logger.error("Rift mach subscription terminated with status=\(status)")
        }

        stopSubscriptionLocked(terminateProcess: false)

        guard isRunning else { return }
        scheduleReconnectLocked()
    }

    private func scheduleReconnectLocked() {
        guard isRunning else { return }

        reconnectWorkItem?.cancel()

        let delay = nextBackoffDelay()
        let workItem = DispatchWorkItem { [weak self] in
            self?.startSubscriptionLocked()
        }

        reconnectWorkItem = workItem
        logger.debug("Scheduling Rift mach reconnect in \(delay, privacy: .public)s")
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func nextBackoffDelay() -> TimeInterval {
        let power = min(reconnectAttempt, 5)
        let base = pow(2.0, Double(power)) * 0.5
        reconnectAttempt = min(reconnectAttempt + 1, 5)
        return min(base, 10.0)
    }
}
