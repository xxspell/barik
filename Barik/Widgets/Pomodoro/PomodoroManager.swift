import AppKit
import Foundation
import OSLog
import SwiftUI

enum PomodoroIntegrationMode: String, CaseIterable, Codable {
    case local
    case ticktick
    case auto

    var title: String {
        switch self {
        case .local:
            return String(localized: "pomodoro.integration.local")
        case .ticktick:
            return "TickTick"
        case .auto:
            return String(localized: "pomodoro.integration.auto")
        }
    }
}

enum PomodoroPhase: String, Codable {
    case idle
    case focus
    case focusPaused
    case waitingForBreak
    case breakTime
    case breakPaused

    var isActiveCountdown: Bool {
        self == .focus || self == .breakTime
    }

    var isPaused: Bool {
        self == .focusPaused || self == .breakPaused
    }

    var isFocusRelated: Bool {
        self == .focus || self == .focusPaused || self == .waitingForBreak
    }

    var isBreakRelated: Bool {
        self == .breakTime || self == .breakPaused
    }

    var title: String {
        switch self {
        case .idle:
            return String(localized: "pomodoro.phase.idle")
        case .focus:
            return String(localized: "pomodoro.phase.focus")
        case .focusPaused:
            return String(localized: "pomodoro.phase.focus_paused")
        case .waitingForBreak:
            return String(localized: "pomodoro.phase.waiting_for_break")
        case .breakTime:
            return String(localized: "pomodoro.phase.break")
        case .breakPaused:
            return String(localized: "pomodoro.phase.break_paused")
        }
    }
}

enum PomodoroHistorySource: String, Codable {
    case local
    case ticktick
}

struct PomodoroHistoryEntry: Identifiable, Codable, Equatable {
    let id: String
    let startAt: Date
    let endAt: Date
    let effectiveDurationSeconds: Int
    let pauseDurationSeconds: Int
    let note: String
    let taskTitle: String?
    let source: PomodoroHistorySource

    var displayDurationMinutes: Int {
        max(Int(round(Double(effectiveDurationSeconds) / 60.0)), 1)
    }
}

struct PomodoroDisplayStatistics: Equatable {
    let todayCount: Int
    let totalCount: Int
    let todayMinutes: Int
    let totalMinutes: Int

    static let zero = PomodoroDisplayStatistics(
        todayCount: 0,
        totalCount: 0,
        todayMinutes: 0,
        totalMinutes: 0
    )
}

private struct PomodoroCachePayload: Codable {
    let phase: PomodoroPhase
    let remainingTime: TimeInterval
    let plannedDuration: TimeInterval
    let focusDurationMinutes: Int
    let shortBreakDurationMinutes: Int
    let longBreakDurationMinutes: Int
    let longBreakInterval: Int
    let completedFocusesInCycle: Int
    let currentSessionStart: Date?
    let currentSessionEnd: Date?
    let pausedAt: Date?
    let waitingForBreakStartedAt: Date?
    let accumulatedPauseDuration: Int
    let noteDraft: String
    let taskSearchQuery: String
    let selectedTaskTitle: String
    let selectedTaskID: String?
    let preferredMode: PomodoroIntegrationMode
    let localHistory: [PomodoroHistoryEntry]
    let pendingAdjustment: PendingPomodoroAdjustment?
}

private struct PendingPomodoroAdjustment: Codable, Equatable {
    let historyEntryID: String
    let startAt: Date
    let originalEndAt: Date
    var currentRecordedEndAt: Date
    let pauseDurationSeconds: Int
    let remotePomodoroID: String?
    var remotePomodoroEtag: String?
    let taskID: String?
    let taskTitle: String?
}

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var remainingTime: TimeInterval = 25 * 60
    @Published private(set) var plannedDuration: TimeInterval = 25 * 60
    @Published private(set) var effectiveIntegrationMode: PomodoroIntegrationMode = .local
    @Published private(set) var isSyncing = false
    @Published private(set) var syncError: String?
    @Published private(set) var history: [PomodoroHistoryEntry] = []
    @Published private(set) var statistics: PomodoroDisplayStatistics = .zero
    @Published private(set) var tickTickPreferences: TickTickPomodoroPreferences?

    @Published var focusDurationMinutes: Int = 25
    @Published var shortBreakDurationMinutes: Int = 5
    @Published var longBreakDurationMinutes: Int = 15
    @Published var longBreakInterval: Int = 4
    @Published var noteDraft: String = ""
    @Published var taskSearchQuery: String = ""
    @Published var selectedTaskTitle: String = ""
    @Published private(set) var selectedTaskID: String?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "PomodoroManager"
    )
    private let tickTickManager = TickTickManager.shared

    private var refreshTimer: Timer?
    private var hasStarted = false
    private var showSeconds = false
    private var preferredMode: PomodoroIntegrationMode = .local
    private var playSoundOnFocusEnd = true
    private var playSoundOnBreakEnd = true
    private var focusFinishedSoundName: String?
    private var breakFinishedSoundName: String?
    private var repeatBreakFinishedSoundUntilPopupOpened = false
    private var breakFinishedSoundRepeatInterval: TimeInterval = 12
    private var historyWindowDays = 180
    private var currentSessionStart: Date?
    private var currentSessionEnd: Date?
    private var pausedAt: Date?
    private var waitingForBreakStartedAt: Date?
    private var accumulatedPauseDuration = 0
    private var completedFocusesInCycle = 0
    private var localHistory: [PomodoroHistoryEntry] = []
    private var remoteHistory: [PomodoroHistoryEntry] = []
    private var pendingAdjustment: PendingPomodoroAdjustment?
    private var breakFinishedRepeatTimer: Timer?
    private var isPopupVisible = false

    private var cacheURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("barik", isDirectory: true)
            .appendingPathComponent("pomodoro-cache.json")
    }

    private init() {}

    deinit {
        refreshTimer?.invalidate()
        breakFinishedRepeatTimer?.invalidate()
    }

    var isRunning: Bool {
        phase.isActiveCountdown
    }

    var isPaused: Bool {
        phase.isPaused
    }

    var progress: Double {
        guard plannedDuration > 0 else { return 0 }
        let elapsed = max(plannedDuration - remainingTime, 0)
        return min(max(elapsed / plannedDuration, 0), 1)
    }

    var remainingLabel: String {
        if phase == .waitingForBreak {
            let overtime = overtimeSeconds
            return overtime > 0 ? "+\(Self.minutesLabel(from: overtime))" : String(localized: "pomodoro.phase.idle")
        }
        let totalSeconds = max(Int(remainingTime.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if showSeconds || totalSeconds < 60 {
            return String(format: "%02d:%02d", minutes, seconds)
        }
        return "\(minutes)m"
    }

    var widgetLabel: String? {
        guard phase != .idle else { return nil }
        if phase == .waitingForBreak {
            return overtimeSeconds > 0 ? "+\(Self.minutesLabel(from: overtimeSeconds))" : String(localized: "pomodoro.phase.idle")
        }
        return remainingLabel
    }

    var overtimeSeconds: Int {
        guard phase == .waitingForBreak, let waitingForBreakStartedAt else { return 0 }
        return max(Int(Date().timeIntervalSince(waitingForBreakStartedAt)), 0)
    }

    var canApplyOvertime: Bool {
        overtimeSeconds > 0 && pendingAdjustment != nil
    }

    var suggestedOvertimeLabel: String? {
        guard canApplyOvertime else { return nil }
        return Self.minutesLabel(from: overtimeSeconds)
    }

    var nextBreakDurationLabel: String {
        "\(nextBreakDurationMinutes())m"
    }

    var needsTickTickSignIn: Bool {
        preferredMode != .local && !tickTickManager.hasPrivatePomodoroAccess
    }

    func startUpdating(config: ConfigData) {
        logger.debug("startUpdating() called")
        if !hasStarted {
            hasStarted = true
            loadCache()
            mergeHistory()
            refreshClock()
            startRefreshTimer()
        }
        updateConfiguration(config: config)

        Task { [weak self] in
            await self?.refreshRemoteData(reason: "start")
        }
    }

    func updateConfiguration(config: ConfigData) {
        preferredMode = PomodoroIntegrationMode(
            rawValue: config["mode"]?.stringValue?.lowercased() ?? "local"
        ) ?? .local
        focusDurationMinutes = clampDuration(config["focus-duration"]?.intValue ?? focusDurationMinutes)
        shortBreakDurationMinutes = max(config["short-break-duration"]?.intValue ?? shortBreakDurationMinutes, 1)
        longBreakDurationMinutes = max(config["long-break-duration"]?.intValue ?? longBreakDurationMinutes, 1)
        longBreakInterval = max(config["long-break-interval"]?.intValue ?? longBreakInterval, 1)
        showSeconds = config["show-seconds"]?.boolValue ?? false
        playSoundOnFocusEnd = config["play-sound-on-focus-end"]?.boolValue ?? true
        playSoundOnBreakEnd = config["play-sound-on-break-end"]?.boolValue ?? true
        focusFinishedSoundName = config["focus-finished-sound"]?.stringValue
        breakFinishedSoundName = config["break-finished-sound"]?.stringValue
        repeatBreakFinishedSoundUntilPopupOpened = config["repeat-break-finished-sound-until-popup-opened"]?.boolValue ?? false
        breakFinishedSoundRepeatInterval = max(Double(config["break-finished-sound-repeat-interval-seconds"]?.intValue ?? 12), 3)
        historyWindowDays = max(config["history-window-days"]?.intValue ?? 180, 7)

        logger.debug(
            "updateConfiguration() mode=\(self.preferredMode.rawValue, privacy: .public) focus=\(self.focusDurationMinutes) shortBreak=\(self.shortBreakDurationMinutes) longBreak=\(self.longBreakDurationMinutes)"
        )

        reconcileEffectiveIntegrationMode()
        if phase == .idle {
            plannedDuration = TimeInterval(focusDurationMinutes * 60)
            remainingTime = plannedDuration
        }

        saveCache()
    }

    func refreshRemoteData(reason: String) async {
        reconcileEffectiveIntegrationMode()
        logger.info("refreshRemoteData() reason=\(reason, privacy: .public) mode=\(self.effectiveIntegrationMode.rawValue, privacy: .public)")

        guard effectiveIntegrationMode == .ticktick else {
            syncError = needsTickTickSignIn ? String(localized: "pomodoro.sync.private_sign_in_required") : nil
            remoteHistory = []
            recalculateStatistics()
            mergeHistory()
            return
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let preferences = try await tickTickManager.fetchPomodoroPreferences()
            tickTickPreferences = preferences
            logger.debug("refreshRemoteData() preferences loaded")
            applyTickTickPreferencesIfNeeded(preferences)
        } catch {
            logger.error("refreshRemoteData() preferences failed: \(error.localizedDescription, privacy: .public)")
            syncError = String(localized: "pomodoro.sync.preferences_load_failed")
        }

        do {
            let tickTickStats = try await tickTickManager.fetchPomodoroStatistics()
            statistics = PomodoroDisplayStatistics(
                todayCount: tickTickStats.todayPomoCount,
                totalCount: tickTickStats.totalPomoCount,
                todayMinutes: tickTickStats.todayPomoDuration,
                totalMinutes: tickTickStats.totalPomoDuration
            )
            logger.debug("refreshRemoteData() statistics loaded")
        } catch {
            logger.error("refreshRemoteData() statistics failed: \(error.localizedDescription, privacy: .public)")
            syncError = String(localized: "pomodoro.sync.statistics_load_failed")
            recalculateStatistics()
        }

        do {
            let to = Date()
            let from = Calendar.current.date(byAdding: .day, value: -historyWindowDays, to: to) ?? to
            let records = try await tickTickManager.fetchPomodoroRecords(from: from, to: to)
            if records.isEmpty {
                logger.debug("refreshRemoteData() records empty, trying timeline fallback")
                let timeline = try await tickTickManager.fetchPomodoroTimeline()
                remoteHistory = timeline.compactMap(Self.makeHistoryEntry(from:))
            } else {
                remoteHistory = records.compactMap(Self.makeHistoryEntry(from:))
            }
            logger.debug("refreshRemoteData() remote history entries=\(self.remoteHistory.count)")
            mergeHistory()
        } catch {
            logger.error("refreshRemoteData() history failed: \(error.localizedDescription, privacy: .public)")
            syncError = String(localized: "pomodoro.sync.history_load_failed")
            mergeHistory()
        }

        do {
            let currentTimers = try await tickTickManager.fetchPomodoroCurrentTimer()
            logger.debug("refreshRemoteData() remote current timers=\(currentTimers.count)")
            if phase == .idle, let remote = currentTimers.first {
                adoptRemoteTimerIfPossible(remote)
            }
        } catch {
            logger.error("refreshRemoteData() current timer failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startFocusSession() {
        logger.info("startFocusSession() phase=\(self.phase.rawValue, privacy: .public)")

        if phase == .focusPaused || phase == .breakPaused {
            resume()
            return
        }

        guard phase == .idle || phase == .waitingForBreak else { return }

        if phase == .waitingForBreak {
            resetToIdle(keepSelection: true)
        }

        let duration = TimeInterval(clampDuration(focusDurationMinutes) * 60)
        beginSession(phase: .focus, duration: duration)
    }

    func startBreakSession() {
        logger.info("startBreakSession() phase=\(self.phase.rawValue, privacy: .public)")
        guard phase == .waitingForBreak || phase == .idle else { return }
        let duration = TimeInterval(nextBreakDurationMinutes() * 60)
        noteDraft = ""
        beginSession(phase: .breakTime, duration: duration)
    }

    func skipBreakAndStartNextFocus() {
        logger.info("skipBreakAndStartNextFocus() phase=\(self.phase.rawValue, privacy: .public)")
        guard phase == .waitingForBreak || phase == .breakTime || phase == .breakPaused else { return }
        resetToIdle(keepSelection: true)
        let duration = TimeInterval(clampDuration(focusDurationMinutes) * 60)
        beginSession(phase: .focus, duration: duration)
    }

    func togglePause() {
        logger.info("togglePause() phase=\(self.phase.rawValue, privacy: .public)")
        switch phase {
        case .focus, .breakTime:
            pause()
        case .focusPaused, .breakPaused:
            resume()
        default:
            break
        }
    }

    func finishCycle() {
        logger.info("finishCycle() phase=\(self.phase.rawValue, privacy: .public)")
        resetToIdle(keepSelection: true)
    }

    func cancelCurrentTimer() {
        logger.info("cancelCurrentTimer() phase=\(self.phase.rawValue, privacy: .public)")
        resetToIdle(keepSelection: true)
    }

    func refreshManually() {
        Task { [weak self] in
            await self?.refreshRemoteData(reason: "manual")
        }
    }

    func popupPresented() {
        isPopupVisible = true
        stopBreakFinishedRepeat()
    }

    func popupDismissed() {
        isPopupVisible = false
    }

    func setFocusDuration(minutes: Int) {
        let clamped = clampDuration(minutes)
        logger.info("setFocusDuration() \(clamped)")
        focusDurationMinutes = clamped
        if phase == .idle {
            plannedDuration = TimeInterval(clamped * 60)
            remainingTime = plannedDuration
        }
        persistPreferencesToTickTickIfNeeded()
        saveCache()
    }

    func setShortBreakDuration(minutes: Int) {
        shortBreakDurationMinutes = max(minutes, 1)
        logger.info("setShortBreakDuration() \(self.shortBreakDurationMinutes)")
        persistPreferencesToTickTickIfNeeded()
        saveCache()
    }

    func updateTaskSearchQuery(_ value: String) {
        taskSearchQuery = value
        saveCache()
    }

    func updateTaskContext(_ value: String) {
        selectedTaskTitle = value
        if selectedTaskID != nil {
            selectedTaskID = nil
        }
        logger.info("updateTaskContext() textOnly=\(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, privacy: .public)")
        saveCache()
    }

    func selectTickTickTask(_ task: TickTickTask) {
        taskSearchQuery = task.title
        selectedTaskTitle = task.title
        selectedTaskID = task.id
        logger.info("selectTickTickTask() taskId=\(task.id, privacy: .public) title=\(task.title, privacy: .public)")
        saveCache()
    }

    func clearTaskBinding() {
        taskSearchQuery = ""
        selectedTaskTitle = ""
        selectedTaskID = nil
        logger.info("clearTaskBinding()")
        saveCache()
    }

    func applyOvertimeWorked() {
        guard phase == .waitingForBreak else { return }
        let extraSeconds = overtimeSeconds
        guard extraSeconds > 0, let pendingAdjustment else { return }

        logger.info("applyOvertimeWorked() extraSeconds=\(extraSeconds)")
        var updatedAdjustment = pendingAdjustment
        updatedAdjustment.currentRecordedEndAt = pendingAdjustment.currentRecordedEndAt.addingTimeInterval(TimeInterval(extraSeconds))

        if let index = localHistory.firstIndex(where: { $0.id == pendingAdjustment.historyEntryID }) {
            let existing = localHistory[index]
            localHistory[index] = PomodoroHistoryEntry(
                id: existing.id,
                startAt: existing.startAt,
                endAt: existing.endAt.addingTimeInterval(TimeInterval(extraSeconds)),
                effectiveDurationSeconds: existing.effectiveDurationSeconds + extraSeconds,
                pauseDurationSeconds: existing.pauseDurationSeconds,
                note: existing.note,
                taskTitle: existing.taskTitle,
                source: existing.source
            )
        }

        self.pendingAdjustment = updatedAdjustment
        waitingForBreakStartedAt = Date()
        mergeHistory()
        recalculateStatistics()
        saveCache()

        Task { [weak self] in
            await self?.syncPendingAdjustmentIfPossible(reason: "manual-overtime")
        }
    }

    private func beginSession(phase: PomodoroPhase, duration: TimeInterval) {
        refreshTimer?.invalidate()
        currentSessionStart = Date()
        currentSessionEnd = Date().addingTimeInterval(duration)
        pausedAt = nil
        accumulatedPauseDuration = 0
        plannedDuration = duration
        remainingTime = duration
        self.phase = phase
        logger.info("beginSession() phase=\(phase.rawValue, privacy: .public) duration=\(Int(duration))")
        startRefreshTimer()
        saveCache()
    }

    private func pause() {
        guard pausedAt == nil else { return }
        pausedAt = Date()
        phase = phase == .focus ? .focusPaused : .breakPaused
        logger.info("pause() pausedAt=\(String(describing: self.pausedAt), privacy: .public)")
        refreshTimer?.invalidate()
        saveCache()
    }

    private func resume() {
        guard let pausedAt else { return }
        let pauseSeconds = max(Int(Date().timeIntervalSince(pausedAt)), 0)
        accumulatedPauseDuration += pauseSeconds
        currentSessionEnd = currentSessionEnd?.addingTimeInterval(TimeInterval(pauseSeconds))
        self.pausedAt = nil
        phase = phase == .focusPaused ? .focus : .breakTime
        logger.info("resume() pauseSeconds=\(pauseSeconds)")
        refreshClock()
        startRefreshTimer()
        saveCache()
    }

    private func handleTimerFinished() {
        logger.info("handleTimerFinished() phase=\(self.phase.rawValue, privacy: .public)")
        refreshTimer?.invalidate()

        switch phase {
        case .focus, .focusPaused:
            completeFocusSession()
        case .breakTime, .breakPaused:
            completeBreakSession()
        default:
            break
        }
    }

    private func completeFocusSession() {
        let startAt = currentSessionStart ?? Date().addingTimeInterval(-plannedDuration)
        let endAt = Date()
        let effectiveDuration = max(Int(endAt.timeIntervalSince(startAt)) - accumulatedPauseDuration, 0)
        let entry = PomodoroHistoryEntry(
            id: UUID().uuidString,
            startAt: startAt,
            endAt: endAt,
            effectiveDurationSeconds: effectiveDuration,
            pauseDurationSeconds: accumulatedPauseDuration,
            note: noteDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            taskTitle: selectedTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            source: effectiveIntegrationMode == .ticktick ? .ticktick : .local
        )

        completedFocusesInCycle += 1
        localHistory.insert(entry, at: 0)
        pendingAdjustment = PendingPomodoroAdjustment(
            historyEntryID: entry.id,
            startAt: startAt,
            originalEndAt: endAt,
            currentRecordedEndAt: endAt,
            pauseDurationSeconds: accumulatedPauseDuration,
            remotePomodoroID: nil,
            remotePomodoroEtag: nil,
            taskID: selectedTaskID,
            taskTitle: selectedTaskTitle.nilIfEmpty
        )
        logger.info(
            "completeFocusSession() durationSeconds=\(effectiveDuration) pause=\(self.accumulatedPauseDuration) localHistory=\(self.localHistory.count)"
        )

        if playSoundOnFocusEnd {
            playSound(named: resolvedFocusFinishedSoundName)
        }

        if effectiveIntegrationMode == .ticktick {
            let draft = TickTickPomodoroSessionDraft(
                startTime: startAt,
                endTime: endAt,
                pauseDuration: accumulatedPauseDuration,
                note: noteDraft,
                taskTitle: selectedTaskTitle.nilIfEmpty,
                taskId: selectedTaskID
            )

            Task { [weak self] in
                guard let self else { return }
                do {
                    let saved = try await self.tickTickManager.savePomodoroSession(draft)
                    if var pendingAdjustment = self.pendingAdjustment,
                       pendingAdjustment.historyEntryID == entry.id {
                        pendingAdjustment = PendingPomodoroAdjustment(
                            historyEntryID: pendingAdjustment.historyEntryID,
                            startAt: pendingAdjustment.startAt,
                            originalEndAt: pendingAdjustment.originalEndAt,
                            currentRecordedEndAt: pendingAdjustment.currentRecordedEndAt,
                            pauseDurationSeconds: pendingAdjustment.pauseDurationSeconds,
                            remotePomodoroID: saved.pomodoroId,
                            remotePomodoroEtag: saved.etag,
                            taskID: pendingAdjustment.taskID,
                            taskTitle: pendingAdjustment.taskTitle
                        )
                        self.pendingAdjustment = pendingAdjustment
                    }
                    self.logger.info("completeFocusSession() synced to TickTick")
                    await self.syncPendingAdjustmentIfPossible(reason: "initial-save")
                    await self.refreshRemoteData(reason: "focus-complete")
                } catch {
                    self.logger.error("completeFocusSession() sync failed: \(error.localizedDescription, privacy: .public)")
                    self.syncError = String(localized: "pomodoro.sync.session_save_failed")
                    self.mergeHistory()
                    self.recalculateStatistics()
                }
            }
        } else {
            mergeHistory()
            recalculateStatistics()
        }

        noteDraft = ""
        phase = .waitingForBreak
        waitingForBreakStartedAt = Date()
        let nextBreakDuration = TimeInterval(nextBreakDurationMinutes() * 60)
        plannedDuration = nextBreakDuration
        remainingTime = plannedDuration
        currentSessionStart = nil
        currentSessionEnd = nil
        pausedAt = nil
        accumulatedPauseDuration = 0
        saveCache()
    }

    private func completeBreakSession() {
        logger.info("completeBreakSession()")
        if playSoundOnBreakEnd {
            playSound(named: resolvedBreakFinishedSoundName)
            scheduleBreakFinishedRepeatIfNeeded()
        }
        resetToIdle(keepSelection: true)
    }

    private func resetToIdle(keepSelection: Bool) {
        refreshTimer?.invalidate()
        phase = .idle
        plannedDuration = TimeInterval(focusDurationMinutes * 60)
        remainingTime = plannedDuration
        currentSessionStart = nil
        currentSessionEnd = nil
        pausedAt = nil
        waitingForBreakStartedAt = nil
        accumulatedPauseDuration = 0
        pendingAdjustment = nil
        stopBreakFinishedRepeat()
        noteDraft = ""
        taskSearchQuery = keepSelection ? selectedTaskTitle : ""
        if !keepSelection {
            selectedTaskTitle = ""
            selectedTaskID = nil
        }
        logger.info("resetToIdle()")
        mergeHistory()
        recalculateStatistics()
        saveCache()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshClock()
            }
        }
    }

    private func refreshClock() {
        if phase == .waitingForBreak {
            objectWillChange.send()
            return
        }
        guard let currentSessionEnd else { return }
        guard !phase.isPaused else { return }

        let newRemaining = max(currentSessionEnd.timeIntervalSinceNow, 0)
        remainingTime = newRemaining
        if newRemaining <= 0 {
            handleTimerFinished()
        }
    }

    private func reconcileEffectiveIntegrationMode() {
        let newMode: PomodoroIntegrationMode
        switch preferredMode {
        case .local:
            newMode = .local
        case .ticktick:
            newMode = tickTickManager.hasPrivatePomodoroAccess ? .ticktick : .local
        case .auto:
            newMode = tickTickManager.hasPrivatePomodoroAccess ? .ticktick : .local
        }

        if effectiveIntegrationMode != newMode {
            logger.info("reconcileEffectiveIntegrationMode() \(self.effectiveIntegrationMode.rawValue, privacy: .public) -> \(newMode.rawValue, privacy: .public)")
            effectiveIntegrationMode = newMode
        }
    }

    private func applyTickTickPreferencesIfNeeded(_ preferences: TickTickPomodoroPreferences) {
        let clampedDuration = clampDuration(preferences.pomoDuration)
        let shortBreak = max(preferences.shortBreakDuration, 1)
        let longBreak = max(preferences.longBreakDuration, 1)
        let interval = max(preferences.longBreakInterval, 1)

        if phase == .idle {
            focusDurationMinutes = clampedDuration
            shortBreakDurationMinutes = shortBreak
            longBreakDurationMinutes = longBreak
            longBreakInterval = interval
            plannedDuration = TimeInterval(clampedDuration * 60)
            remainingTime = plannedDuration
            logger.debug("applyTickTickPreferencesIfNeeded() applied idle preferences")
            saveCache()
        }
    }

    private func persistPreferencesToTickTickIfNeeded() {
        guard effectiveIntegrationMode == .ticktick else { return }
        let existing = tickTickPreferences ?? .default
        let updated = TickTickPomodoroPreferences(
            id: existing.id,
            shortBreakDuration: shortBreakDurationMinutes,
            longBreakDuration: longBreakDurationMinutes,
            longBreakInterval: longBreakInterval,
            pomoGoal: existing.pomoGoal,
            focusDuration: existing.focusDuration,
            mindfulnessEnabled: existing.mindfulnessEnabled,
            autoPomo: existing.autoPomo,
            autoBreak: existing.autoBreak,
            lightsOn: existing.lightsOn,
            focused: existing.focused,
            soundsOn: existing.soundsOn,
            pomoDuration: focusDurationMinutes
        )

        tickTickPreferences = updated
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.tickTickManager.updatePomodoroPreferences(updated)
                self.logger.info("persistPreferencesToTickTickIfNeeded() synced")
            } catch {
                self.logger.error("persistPreferencesToTickTickIfNeeded() failed: \(error.localizedDescription, privacy: .public)")
                self.syncError = String(localized: "pomodoro.sync.preferences_update_failed")
            }
        }
    }

    private func adoptRemoteTimerIfPossible(_ record: TickTickPomodoroRecord) {
        guard let startAt = Self.parseTickTickDate(record.startTime),
              let endAt = Self.parseTickTickDate(record.endTime),
              endAt > Date()
        else {
            logger.debug("adoptRemoteTimerIfPossible() skipped")
            return
        }

        currentSessionStart = startAt
        currentSessionEnd = endAt
        accumulatedPauseDuration = record.pauseDuration ?? 0
        plannedDuration = max(endAt.timeIntervalSince(startAt) - Double(accumulatedPauseDuration), 1)
        remainingTime = max(endAt.timeIntervalSinceNow, 0)
        phase = .focus
        logger.info("adoptRemoteTimerIfPossible() adopted remote timer endAt=\(String(describing: self.currentSessionEnd), privacy: .public)")
        startRefreshTimer()
        saveCache()
    }

    private func recalculateStatistics() {
        guard effectiveIntegrationMode == .local else {
            if statistics == .zero {
                let localStats = Self.buildLocalStatistics(from: localHistory)
                statistics = localStats
            }
            return
        }

        statistics = Self.buildLocalStatistics(from: localHistory)
    }

    private func mergeHistory() {
        var merged: [PomodoroHistoryEntry] = remoteHistory

        for localEntry in localHistory {
            let duplicate = merged.contains { remoteEntry in
                abs(remoteEntry.startAt.timeIntervalSince(localEntry.startAt)) < 2
                    && abs(remoteEntry.endAt.timeIntervalSince(localEntry.endAt)) < 2
                    && remoteEntry.note == localEntry.note
                    && remoteEntry.taskTitle == localEntry.taskTitle
            }
            if !duplicate {
                merged.append(localEntry)
            }
        }

        history = merged.sorted { $0.startAt > $1.startAt }
        logger.debug("mergeHistory() history=\(self.history.count) local=\(self.localHistory.count) remote=\(self.remoteHistory.count)")
    }

    private func nextBreakDurationMinutes() -> Int {
        let useLongBreak = completedFocusesInCycle > 0 && completedFocusesInCycle % longBreakInterval == 0
        return useLongBreak ? longBreakDurationMinutes : shortBreakDurationMinutes
    }

    private var resolvedFocusFinishedSoundName: String? {
        let configured = focusFinishedSoundName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return configured?.isEmpty == false ? configured : "pomo-v1.mp3"
    }

    private var resolvedBreakFinishedSoundName: String? {
        let configured = breakFinishedSoundName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return configured?.isEmpty == false ? configured : "pomo-v2.wav"
    }

    private func playSound(named soundName: String?) {
        guard let soundName, !soundName.isEmpty else {
            logger.debug("playSound() fallback beep")
            NSSound.beep()
            return
        }

        if let bundleURL = Bundle.main.url(forResource: soundName, withExtension: nil),
           let sound = NSSound(contentsOf: bundleURL, byReference: true) {
            logger.debug("playSound() bundle resource=\(soundName, privacy: .public)")
            sound.play()
            return
        }

        let resourceName = (soundName as NSString).deletingPathExtension
        let resourceExtension = (soundName as NSString).pathExtension
        if !resourceName.isEmpty,
           let bundleURL = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension.isEmpty ? nil : resourceExtension),
           let sound = NSSound(contentsOf: bundleURL, byReference: true) {
            logger.debug("playSound() bundle split resource=\(soundName, privacy: .public)")
            sound.play()
            return
        }

        if let sound = NSSound(named: NSSound.Name(soundName)) {
            logger.debug("playSound() named=\(soundName, privacy: .public)")
            sound.play()
            return
        }

        logger.debug("playSound() fallback beep for \(soundName, privacy: .public)")
        NSSound.beep()
    }

    private func scheduleBreakFinishedRepeatIfNeeded() {
        stopBreakFinishedRepeat()
        guard repeatBreakFinishedSoundUntilPopupOpened, !isPopupVisible else { return }

        breakFinishedRepeatTimer = Timer.scheduledTimer(withTimeInterval: breakFinishedSoundRepeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.isPopupVisible else {
                    self.stopBreakFinishedRepeat()
                    return
                }
                self.playSound(named: self.resolvedBreakFinishedSoundName)
            }
        }
        logger.info("scheduleBreakFinishedRepeatIfNeeded() interval=\(self.breakFinishedSoundRepeatInterval)")
    }

    private func stopBreakFinishedRepeat() {
        breakFinishedRepeatTimer?.invalidate()
        breakFinishedRepeatTimer = nil
    }

    private func loadCache() {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(PomodoroCachePayload.self, from: data)
        else {
            logger.debug("loadCache() no cache")
            return
        }

        phase = payload.phase
        remainingTime = payload.remainingTime
        plannedDuration = payload.plannedDuration
        focusDurationMinutes = payload.focusDurationMinutes
        shortBreakDurationMinutes = payload.shortBreakDurationMinutes
        longBreakDurationMinutes = payload.longBreakDurationMinutes
        longBreakInterval = payload.longBreakInterval
        completedFocusesInCycle = payload.completedFocusesInCycle
        currentSessionStart = payload.currentSessionStart
        currentSessionEnd = payload.currentSessionEnd
        pausedAt = payload.pausedAt
        waitingForBreakStartedAt = payload.waitingForBreakStartedAt
        accumulatedPauseDuration = payload.accumulatedPauseDuration
        noteDraft = payload.noteDraft
        taskSearchQuery = payload.taskSearchQuery
        selectedTaskTitle = payload.selectedTaskTitle
        selectedTaskID = payload.selectedTaskID
        preferredMode = payload.preferredMode
        localHistory = payload.localHistory
        pendingAdjustment = payload.pendingAdjustment
        logger.debug("loadCache() phase=\(self.phase.rawValue, privacy: .public) localHistory=\(self.localHistory.count)")
    }

    private func saveCache() {
        guard let url = cacheURL else { return }
        let payload = PomodoroCachePayload(
            phase: phase,
            remainingTime: remainingTime,
            plannedDuration: plannedDuration,
            focusDurationMinutes: focusDurationMinutes,
            shortBreakDurationMinutes: shortBreakDurationMinutes,
            longBreakDurationMinutes: longBreakDurationMinutes,
            longBreakInterval: longBreakInterval,
            completedFocusesInCycle: completedFocusesInCycle,
            currentSessionStart: currentSessionStart,
            currentSessionEnd: currentSessionEnd,
            pausedAt: pausedAt,
            waitingForBreakStartedAt: waitingForBreakStartedAt,
            accumulatedPauseDuration: accumulatedPauseDuration,
            noteDraft: noteDraft,
            taskSearchQuery: taskSearchQuery,
            selectedTaskTitle: selectedTaskTitle,
            selectedTaskID: selectedTaskID,
            preferredMode: preferredMode,
            localHistory: localHistory,
            pendingAdjustment: pendingAdjustment
        )

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url)
            logger.debug("saveCache() saved to \(url.path, privacy: .public)")
        } catch {
            logger.error("saveCache() failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func buildLocalStatistics(from history: [PomodoroHistoryEntry]) -> PomodoroDisplayStatistics {
        let calendar = Calendar.current
        let todayEntries = history.filter { calendar.isDateInToday($0.startAt) }
        return PomodoroDisplayStatistics(
            todayCount: todayEntries.count,
            totalCount: history.count,
            todayMinutes: todayEntries.reduce(0) { $0 + $1.displayDurationMinutes },
            totalMinutes: history.reduce(0) { $0 + $1.displayDurationMinutes }
        )
    }

    private static func makeHistoryEntry(from record: TickTickPomodoroRecord) -> PomodoroHistoryEntry? {
        guard let startAt = parseTickTickDate(record.startTime),
              let rawEndAt = parseTickTickDate(record.endTime)
        else {
            return nil
        }

        let pauseDuration = record.pauseDuration ?? 0
        let adjustedDurationSeconds = max((record.adjustTime ?? 0) / 1000, 0)
        let effectiveDuration = adjustedDurationSeconds > 0
            ? adjustedDurationSeconds
            : max(Int(rawEndAt.timeIntervalSince(startAt)) - pauseDuration, 0)
        let endAt = adjustedDurationSeconds > 0
            ? startAt.addingTimeInterval(TimeInterval(effectiveDuration + pauseDuration))
            : rawEndAt
        let taskTitle = record.title ?? record.tasks?.first?.title

        return PomodoroHistoryEntry(
            id: record.id,
            startAt: startAt,
            endAt: endAt,
            effectiveDurationSeconds: effectiveDuration,
            pauseDurationSeconds: pauseDuration,
            note: record.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            taskTitle: taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            source: .ticktick
        )
    }

    private static func parseTickTickDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private func clampDuration(_ minutes: Int) -> Int {
        min(max(minutes, 5), 180)
    }

    private func syncPendingAdjustmentIfPossible(reason: String) async {
        guard effectiveIntegrationMode == .ticktick else { return }
        guard let pendingAdjustment, let remotePomodoroID = pendingAdjustment.remotePomodoroID else {
            logger.debug("syncPendingAdjustmentIfPossible() skipped reason=\(reason, privacy: .public) remote session not ready")
            return
        }

        let adjustedDurationSeconds = max(
            Int(pendingAdjustment.currentRecordedEndAt.timeIntervalSince(pendingAdjustment.startAt)) - pendingAdjustment.pauseDurationSeconds,
            0
        )
        let baseDurationSeconds = max(
            Int(pendingAdjustment.originalEndAt.timeIntervalSince(pendingAdjustment.startAt)) - pendingAdjustment.pauseDurationSeconds,
            0
        )

        guard adjustedDurationSeconds > baseDurationSeconds else { return }

        do {
            let saved = try await tickTickManager.adjustPomodoroSession(
                pomodoroId: remotePomodoroID,
                pomodoroEtag: pendingAdjustment.remotePomodoroEtag,
                startTime: pendingAdjustment.startAt,
                endTime: pendingAdjustment.originalEndAt,
                pauseDuration: pendingAdjustment.pauseDurationSeconds,
                adjustedDurationSeconds: adjustedDurationSeconds,
                taskId: pendingAdjustment.taskID,
                taskTitle: pendingAdjustment.taskTitle
            )

            if var refreshedAdjustment = self.pendingAdjustment,
               refreshedAdjustment.historyEntryID == pendingAdjustment.historyEntryID {
                refreshedAdjustment.remotePomodoroEtag = saved.etag
                self.pendingAdjustment = refreshedAdjustment
                saveCache()
            }
            logger.info("syncPendingAdjustmentIfPossible() synced reason=\(reason, privacy: .public) adjustedDurationSeconds=\(adjustedDurationSeconds)")
        } catch {
            logger.error("syncPendingAdjustmentIfPossible() failed: \(error.localizedDescription, privacy: .public)")
            syncError = String(localized: "pomodoro.sync.adjustment_update_failed")
        }
    }

    private static func minutesLabel(from seconds: Int) -> String {
        let roundedMinutes = max(Int(ceil(Double(seconds) / 60.0)), 1)
        return "\(roundedMinutes)m"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
