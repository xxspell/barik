import Combine
import AppKit
import ApplicationServices
import Foundation
import OSLog

/*
 Concrete macOS 14.6+ observation direction for this feature:

 Primary signal target: the native screen recording menu bar extra exposed by
 SystemUIServer / Control Center. This build currently uses bounded
 accessibility polling against that native stop control as the concrete
 production observer until a reliable notification-driven source is wired.

 Fallback polling trigger criteria (opt-in only): activate bounded low-frequency
 polling mode only when the observer reports that the primary accessibility
 signal is unavailable at startup (for example: unsupported environment,
 unavailable AX notification source, or explicit observer unavailability). Keep
 this mode explicitly distinct and inspectable via `isUsingFallbackPolling`.
 Fallback does not activate while the primary signal is available.

 In Task 5, fallback is represented as an explicit observation mode seam only;
 concrete polling execution can be added later if required by production data.

 [native macOS screen recording starts/stops]
                 |
                 v
 [SystemUIServer / Control Center recording extra changes]
                 |
                 v
 [accessibility observer emits started/stopped event]
                 |
          +------+------+
          |             |
          v             v
 [isRecording=true] [isRecording=false]

 Task 2 keeps this as a documented seam only. The concrete production observer
 arrives later; for now the manager only owns lifecycle and state propagation.
 */

enum ScreenRecordingObservationEvent {
    case recordingStarted
    case recordingStopped
}

enum ScreenRecordingControlError: Error {
    case notTrusted
    case controlNotFound
    case actionFailed
}

enum ScreenRecordingManagerError: Equatable {
    case notTrusted
    case controlNotFound
    case actionFailed
}

protocol ScreenRecordingObserving: AnyObject {
    var initialState: Bool { get }
    var isPrimarySignalAvailable: Bool { get }
    func startObserving(_ handler: @escaping (ScreenRecordingObservationEvent) -> Void)
    func stopObserving()
}

private enum ScreenRecordingObservationMode {
    case primaryEventDriven
    case fallbackPolling(interval: TimeInterval)

    var isUsingFallbackPolling: Bool {
        switch self {
        case .primaryEventDriven:
            return false
        case .fallbackPolling:
            return true
        }
    }
}

private enum ScreenRecordingFallbackPolicy {
    static let interval: TimeInterval = 0.25
    static let backupInterval: TimeInterval = 1
    static let primaryUpgradeCheckInterval: TimeInterval = 1
    static let stopActionSuppressionInterval: TimeInterval = 6
}

protocol ScreenRecordingControlling {
    func stopActiveRecording() throws
}

@MainActor
final class ScreenRecordingManager: ObservableObject {
    static let shared = ScreenRecordingManager()

    static func shouldShowStopWidget(isRecording: Bool) -> Bool {
        isRecording
    }

    @Published private(set) var isRecording: Bool
    @Published private(set) var lastError: ScreenRecordingManagerError?
    @Published private(set) var isUsingFallbackPolling: Bool

    private let observer: ScreenRecordingObserving
    private let observationMode: ScreenRecordingObservationMode
    private let controller: ScreenRecordingControlling
    private let now: () -> Date
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "ScreenRecordingManager"
    )
    private var suppressRecordingUntil: Date?

    init(
        observer: ScreenRecordingObserving = ProductionScreenRecordingObserver(),
        controller: ScreenRecordingControlling = SystemUIHelperScreenRecordingController(),
        now: @escaping () -> Date = Date.init
    ) {
        self.observer = observer
        self.controller = controller
        self.now = now
        self.isRecording = observer.initialState
        self.lastError = nil

        let observationMode: ScreenRecordingObservationMode
        if observer.isPrimarySignalAvailable {
            observationMode = .primaryEventDriven
        } else {
            observationMode = .fallbackPolling(interval: ScreenRecordingFallbackPolicy.interval)
        }

        self.observationMode = observationMode
        self.isUsingFallbackPolling = observationMode.isUsingFallbackPolling

        if case let .fallbackPolling(interval) = observationMode {
            logger.info("Primary screen recording signal unavailable. Entering fallback polling mode at \(interval, privacy: .public)s interval.")
        }

        observer.startObserving { [weak self] event in
            guard let self else { return }

            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.handleObservationEvent(event)
                }
            } else {
                Task { @MainActor in
                    self.handleObservationEvent(event)
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        logger.info("Stop recording tapped while widget is visible.")

        do {
            try controller.stopActiveRecording()
            lastError = nil
            suppressRecordingUntil = now().addingTimeInterval(
                ScreenRecordingFallbackPolicy.stopActionSuppressionInterval
            )
            isRecording = false
            logger.info("Stop recording succeeded. Hiding widget immediately and suppressing stale started events until \(String(describing: self.suppressRecordingUntil), privacy: .public).")
        } catch let error as ScreenRecordingControlError {
            let mappedError: ScreenRecordingManagerError
            switch error {
            case .notTrusted:
                mappedError = .notTrusted
            case .controlNotFound:
                mappedError = .controlNotFound
            case .actionFailed:
                mappedError = .actionFailed
            }

            lastError = mappedError
            logger.error("Failed to stop screen recording: \(String(describing: error), privacy: .public)")
        } catch {
            lastError = .actionFailed
            logger.error("Failed to stop screen recording with unexpected error: \(error.localizedDescription, privacy: .public)")
        }
    }

    func requestAccessibilityPermissionIfNeeded() {
        SystemUIHelper.requestAccessibilityPermissionIfNeeded()
    }

    private func handleObservationEvent(_ event: ScreenRecordingObservationEvent) {
        switch event {
        case .recordingStarted:
            if let suppressRecordingUntil, now() < suppressRecordingUntil {
                logger.info("Ignoring recordingStarted event because suppression window is still active until \(String(describing: suppressRecordingUntil), privacy: .public).")
                return
            }

            suppressRecordingUntil = nil
            isRecording = true
            logger.info("Recording state changed to active. Showing stop widget.")
        case .recordingStopped:
            suppressRecordingUntil = nil
            isRecording = false
            logger.info("Recording state changed to inactive. Hiding stop widget.")
        }
    }
}

private final class ProductionScreenRecordingObserver: ScreenRecordingObserving {
    private let primaryObserver: AccessibilityScreenRecordingObserver
    private let fallbackObserver: AccessibilityPollingScreenRecordingObserver
    private let backupObserver: AccessibilityPollingScreenRecordingObserver
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "ScreenRecordingProductionObserver"
    )
    private var handler: ((ScreenRecordingObservationEvent) -> Void)?
    private var trustUpgradeTimer: DispatchSourceTimer?
    private var activeMode: ActiveMode?

    private enum ActiveMode {
        case primary
        case fallback
    }

    init(
        detectIsRecording: @escaping () -> Bool = { SystemUIHelper.isActiveScreenRecordingDetected() }
    ) {
        self.primaryObserver = AccessibilityScreenRecordingObserver(detectIsRecording: detectIsRecording)
        self.fallbackObserver = AccessibilityPollingScreenRecordingObserver(
            pollInterval: ScreenRecordingFallbackPolicy.interval,
            detectIsRecording: detectIsRecording
        )
        self.backupObserver = AccessibilityPollingScreenRecordingObserver(
            pollInterval: ScreenRecordingFallbackPolicy.backupInterval,
            detectIsRecording: detectIsRecording
        )
    }

    var initialState: Bool {
        if primaryObserver.isPrimarySignalAvailable {
            return primaryObserver.initialState
        }

        return fallbackObserver.initialState
    }

    var isPrimarySignalAvailable: Bool {
        primaryObserver.isPrimarySignalAvailable
    }

    func startObserving(_ handler: @escaping (ScreenRecordingObservationEvent) -> Void) {
        self.handler = handler

        if primaryObserver.isPrimarySignalAvailable {
            startPrimaryObservationIfNeeded()
        } else {
            startFallbackObservationIfNeeded()
            startPrimaryUpgradeMonitoring()
        }
    }

    func stopObserving() {
        trustUpgradeTimer?.cancel()
        trustUpgradeTimer = nil
        primaryObserver.stopObserving()
        fallbackObserver.stopObserving()
        backupObserver.stopObserving()
        activeMode = nil
    }

    private func startPrimaryObservationIfNeeded() {
        guard activeMode != .primary, let handler else { return }

        fallbackObserver.stopObserving()
        primaryObserver.startObserving(handler)
        backupObserver.startObserving(handler)
        activeMode = .primary
        trustUpgradeTimer?.cancel()
        trustUpgradeTimer = nil
        logger.info("Using AXObserver primary mode for screen recording detection with 1s backup polling.")
    }

    private func startFallbackObservationIfNeeded() {
        guard activeMode != .fallback, let handler else { return }

        primaryObserver.stopObserving()
        backupObserver.stopObserving()
        fallbackObserver.startObserving(handler)
        activeMode = .fallback
        logger.info("Using polling fallback mode for screen recording detection.")
    }

    private func startPrimaryUpgradeMonitoring() {
        guard trustUpgradeTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(
            deadline: .now() + ScreenRecordingFallbackPolicy.primaryUpgradeCheckInterval,
            repeating: ScreenRecordingFallbackPolicy.primaryUpgradeCheckInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.primaryObserver.isPrimarySignalAvailable else { return }

            self.logger.info("Accessibility trust became available. Switching from polling fallback to AXObserver primary mode.")
            self.startPrimaryObservationIfNeeded()
        }

        trustUpgradeTimer = timer
        timer.resume()
    }
}

private final class AccessibilityScreenRecordingObserver: ScreenRecordingObserving {
    private static let subscribedNotifications: [CFString] = [
        "AXChildrenChanged" as CFString,
        kAXCreatedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
        kAXWindowCreatedNotification as CFString
    ]

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "ScreenRecordingAXObserver"
    )
    private let detectIsRecording: () -> Bool
    private var handler: ((ScreenRecordingObservationEvent) -> Void)?
    private var observationRecords: [ObservationRecord] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var hasStarted = false
    private var lastKnownRecordingState: Bool

    init(
        detectIsRecording: @escaping () -> Bool = { SystemUIHelper.isActiveScreenRecordingDetected() }
    ) {
        self.detectIsRecording = detectIsRecording
        self.lastKnownRecordingState = detectIsRecording()
    }

    deinit {
        stopWorkspaceObservation()
    }

    var initialState: Bool {
        lastKnownRecordingState
    }

    var isPrimarySignalAvailable: Bool {
        AXIsProcessTrusted()
    }

    func startObserving(_ handler: @escaping (ScreenRecordingObservationEvent) -> Void) {
        guard !hasStarted else { return }
        hasStarted = true
        self.handler = handler

        guard isPrimarySignalAvailable else {
            logger.info("AX observer unavailable because Accessibility permission is not granted.")
            return
        }

        rebuildObservers()
        startWorkspaceObservation()
        emitIfStateChanged(trigger: "startup")
    }

    func stopObserving() {
        guard hasStarted else { return }

        for record in observationRecords {
            let source = AXObserverGetRunLoopSource(record.observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        observationRecords.removeAll()
        stopWorkspaceObservation()
        handler = nil
        hasStarted = false
    }

    private func rebuildObservers() {
        observationRecords.removeAll()

        for app in candidateApplications() {
            guard app.processIdentifier > 0 else { continue }

            var observerRef: AXObserver?
            let observerResult = AXObserverCreate(app.processIdentifier, axCallback, &observerRef)
            guard observerResult == .success, let observerRef else {
                logger.info("Failed to create AXObserver for pid \(app.processIdentifier, privacy: .public) with code \(observerResult.rawValue, privacy: .public).")
                continue
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let source = AXObserverGetRunLoopSource(observerRef)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            var registeredNotifications: [String] = []
            for notification in Self.subscribedNotifications {
                let addResult = AXObserverAddNotification(observerRef, appElement, notification, context)
                if addResult == .success || addResult == .notificationAlreadyRegistered {
                    registeredNotifications.append(notification as String)
                }
            }

            observationRecords.append(
                ObservationRecord(
                    observer: observerRef,
                    applicationElement: appElement,
                    pid: app.processIdentifier,
                    appName: app.bundleIdentifier ?? app.localizedName ?? "unknown-app",
                    notifications: registeredNotifications
                )
            )
        }

        logger.info("AX observer attached to \(self.observationRecords.count, privacy: .public) candidate apps.")
    }

    private func startWorkspaceObservation() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let launchObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWorkspaceAppChange(reason: "launch")
        }

        let terminateObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWorkspaceAppChange(reason: "terminate")
        }

        workspaceObservers = [launchObserver, terminateObserver]
    }

    private func stopWorkspaceObservation() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func handleWorkspaceAppChange(reason: String) {
        logger.info("Workspace app change detected (\(reason, privacy: .public)). Rebuilding AX observers.")
        rebuildObservers()
        emitIfStateChanged(trigger: "workspace-\(reason)")
    }

    fileprivate func handleAccessibilityEvent(notification: String) {
        logger.info("Received AX notification \(notification, privacy: .public).")
        emitIfStateChanged(trigger: notification)
    }

    private func emitIfStateChanged(trigger: String) {
        let isRecording = detectIsRecording()
        guard isRecording != lastKnownRecordingState else { return }

        lastKnownRecordingState = isRecording
        logger.info("AX observer state changed to \(isRecording, privacy: .public) via \(trigger, privacy: .public).")
        handler?(isRecording ? .recordingStarted : .recordingStopped)
    }

    private func candidateApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier > 0 else { return false }

            let bundleIdentifier = app.bundleIdentifier?.lowercased() ?? ""
            let localizedName = app.localizedName?.lowercased() ?? ""
            let executablePath = app.executableURL?.path.lowercased() ?? ""

            return bundleIdentifier == "com.apple.screencaptureui"
                || bundleIdentifier == "com.apple.controlcenter"
                || bundleIdentifier == "com.apple.systemuiserver"
                || localizedName.contains("screencaptureui")
                || localizedName.contains("controlcenter")
                || localizedName.contains("systemuiserver")
                || executablePath.contains("screencaptureui")
                || executablePath.contains("controlcenter")
                || executablePath.contains("systemuiserver")
        }
    }
}

private struct ObservationRecord {
    let observer: AXObserver
    let applicationElement: AXUIElement
    let pid: pid_t
    let appName: String
    let notifications: [String]
}

private let axCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    let observer = Unmanaged<AccessibilityScreenRecordingObserver>.fromOpaque(refcon).takeUnretainedValue()
    observer.handleAccessibilityEvent(notification: notification as String)
}

private final class AccessibilityPollingScreenRecordingObserver: ScreenRecordingObserving {
    let isPrimarySignalAvailable = false

    private let pollInterval: TimeInterval
    private let detectIsRecording: () -> Bool
    private let queue = DispatchQueue(label: "barik.screen-recording-observer")
    private var timer: DispatchSourceTimer?
    private var hasStarted = false
    private var lastKnownRecordingState: Bool

    init(
        pollInterval: TimeInterval = ScreenRecordingFallbackPolicy.interval,
        detectIsRecording: @escaping () -> Bool = { SystemUIHelper.isActiveScreenRecordingDetected() }
    ) {
        self.pollInterval = pollInterval
        self.detectIsRecording = detectIsRecording
        self.lastKnownRecordingState = detectIsRecording()
    }

    var initialState: Bool {
        lastKnownRecordingState
    }

    func startObserving(_ handler: @escaping (ScreenRecordingObservationEvent) -> Void) {
        guard !hasStarted else { return }
        hasStarted = true

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }

            let isRecording = self.detectIsRecording()
            guard isRecording != self.lastKnownRecordingState else { return }

            self.lastKnownRecordingState = isRecording
            handler(isRecording ? .recordingStarted : .recordingStopped)
        }

        self.timer = timer
        timer.resume()
    }

    func stopObserving() {
        timer?.cancel()
        timer = nil
        hasStarted = false
    }
}

struct SystemUIHelperScreenRecordingController: ScreenRecordingControlling {
    private let stopHandler: () throws -> Void

    init(stopHandler: @escaping () throws -> Void = { try SystemUIHelper.stopActiveScreenRecording() }) {
        self.stopHandler = stopHandler
    }

    func stopActiveRecording() throws {
        try stopHandler()
    }
}
