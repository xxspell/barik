import Foundation

/// Reads TickTick's own local Pomodoro state directly from its preferences domain
/// (~/Library/Preferences/com.TickTick.task.mac.plist), the same file TickTick itself writes
/// on every focus/pause/resume transition. This needs no permission at all — it's a normal
/// macOS preferences read (`CFPreferencesCopyValue`), not Accessibility or the network API.
///
/// Format confirmed empirically against a real TickTick install (undocumented, may change in
/// future TickTick versions): `focus__pomodoro_state` is `"idle"` when nothing is running, or
/// `"pomodoroing.<n>.true"` / `"pomodoroPaused.<n>"` while a session is active. While active,
/// `focus__pomodoro_timeline` holds every start/pause/resume segment of the *current* session
/// only — it resets to session-less metadata entries the moment state goes back to `"idle"`.
enum TickTickLocalPomodoroState {
    /// A point-in-time read of TickTick's own session. Callers should re-poll this every tick
    /// while mirroring a session — TickTick can pause/resume/cancel it independently of Barik.
    struct Snapshot {
        let isPaused: Bool
        let remaining: TimeInterval
        let totalDuration: TimeInterval
        let start: Date
    }

    private static let bundleIdentifier = "com.TickTick.task.mac" as CFString

    private static let stateKey = "focus__pomodoro_state" as CFString
    private static let timelineKey = "focus__pomodoro_timeline" as CFString
    /// Fallback only — this top-level preference reflects TickTick's *current* default focus
    /// duration setting, not necessarily what an already-running session was actually planned
    /// for (confirmed empirically: they can diverge if the user changes the default mid-session).
    /// The authoritative value for an active session is the `pomodoroDuration` entry appended to
    /// its own `focus__pomodoro_timeline`, read below.
    private static let fallbackDurationKey = "focus__pomodoro_pomodoroDuration" as CFString

    /// Returns TickTick's current Pomodoro session (running or paused), or nil if there isn't
    /// one (state is `"idle"`, or the data doesn't parse the way this was reverse-engineered).
    static func currentSnapshot() -> Snapshot? {
        // CFPreferencesCopyValue reads from this process's own preferences cache, which doesn't
        // always pick up TickTick's writes immediately — observed as the mirrored countdown
        // occasionally freezing for a beat and then jumping once the cache catches up. Force a
        // fresh read from cfprefsd on every poll instead of trusting the cache.
        CFPreferencesSynchronize(bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        guard let state = value(for: stateKey) as? String else { return nil }
        let isRunning = state.hasPrefix("pomodoroing")
        let isPaused = state.hasPrefix("pomodoroPaused")
        guard isRunning || isPaused else { return nil }

        guard let timeline = value(for: timelineKey) as? [[String: Any]] else {
            return nil
        }

        let sessionDuration = timeline.lazy.compactMap { $0["pomodoroDuration"] as? Double }.first
        guard let duration = sessionDuration ?? (value(for: fallbackDurationKey) as? Double), duration > 0 else {
            return nil
        }

        let segments: [(start: Date, end: Date, state: String)] = timeline.compactMap { entry in
            guard let start = entry["startDate"] as? Date,
                  let end = entry["endDate"] as? Date,
                  let segmentState = entry["state"] as? String
            else {
                return nil
            }
            return (start, end, segmentState)
        }

        guard let current = segments.last else { return nil }

        var elapsed: TimeInterval = 0
        for segment in segments.dropLast() where segment.state.hasPrefix("pomodoroing") {
            elapsed += segment.end.timeIntervalSince(segment.start)
        }
        if isRunning {
            elapsed += Date().timeIntervalSince(current.start)
        }

        let remaining = max(duration - elapsed, 0)
        guard remaining > 0 || isPaused else {
            // Not paused and no time left: TickTick hasn't rolled the state over to "idle" yet
            // in this snapshot, but there's nothing meaningful left to mirror.
            return nil
        }

        let sessionStart = segments.first?.start ?? current.start
        return Snapshot(isPaused: isPaused, remaining: remaining, totalDuration: duration, start: sessionStart)
    }

    private static func value(for key: CFString) -> Any? {
        CFPreferencesCopyValue(key, bundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
