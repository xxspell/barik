import AppKit
import Combine
import SwiftUI

// MARK: - Controller

/// Turns agent transitions into toasts: owns the queue, the per-screen panels, placement, timers and input.
@MainActor
final class AgentToastController {
    static let shared = AgentToastController()

    private static let testPaneID = "barik-demo"
    /// Lets the chip relayout (it may grow when an agent blocks) before the card anchors to it.
    private static let placementDelay: TimeInterval = 0.12
    private static let retireDelay: TimeInterval = 0.6
    /// A done toast expires on the 1 s tick at which this much (or less) of its time is left.
    private static let expireTolerance: TimeInterval = 0.3

    private struct StatusMark {
        let status: AgentStatus
        let since: Date?
    }

    private let manager = AgentsManager.shared
    private var started = false
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [NSObjectProtocol] = []

    private var queue = ToastQueue()
    private var testAgent: AgentSession?
    /// Island/chip: the item on display (nil = newest).
    private var shownID: String?
    private var previews: [String: [String]] = [:]          // by pane id
    private var doneIn: [String: TimeInterval] = [:]        // by item id
    private var history: [String: (current: StatusMark, previous: StatusMark?)] = [:]
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private var hovered: Set<String> = []
    private var pauseStart: [String: Date] = [:]
    private var pausedTotal: [String: TimeInterval] = [:]
    private var countdowns: [String: ToastCountdown] = [:]

    private var panels: [String: AgentToastPanel] = [:]     // by screen id
    private var retiring: [AgentToastPanel] = []
    private var placementWork: DispatchWorkItem?
    private var expireTimer: Timer?
    private var expireTimerStart = Date()
    private var previewTask: Task<Void, Never>?
    private var previewTargets: [String] = []
    private var mouseMonitors: [Any] = []
    private var keyMonitor: Any?

    private init() {}

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.75)
    }

    // MARK: Public API

    func start() {
        guard !started else { return }
        started = true

        manager.$agents
            .sink { [weak self] agents in MainActor.assumeIsolated { self?.agentsChanged(agents) } }
            .store(in: &cancellables)
        manager.transitions
            .sink { [weak self] t in MainActor.assumeIsolated { self?.handle(t) } }
            .store(in: &cancellables)

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self.updateModels()
            }
        })
    }

    /// Fake "barik-demo" toast in the current style and screen, for Settings. Works without herdr,
    /// bypasses suppression; Open only dismisses it.
    func showTest(kind: ToastKind) {
        start()
        let status: AgentStatus = kind == .blocked ? .blocked : .done
        let now = Date()
        let agent = AgentSession(
            paneID: Self.testPaneID, workspaceID: "", tabID: "", kind: "claude", status: status,
            cwd: Self.testPaneID, title: String(localized: "agents.toast.test.title"),
            statusSince: now, focusedInHerdr: false)
        testAgent = agent
        guard queue.push(AgentTransition(agent: agent, from: .working, to: status), notifyOn: [status], now: now),
              let item = queue.visible.first else { return }
        resetPause(item.id)
        previews[Self.testPaneID] = String(localized: "agents.toast.test.preview").components(separatedBy: "\n")
        if kind == .done { doneIn[item.id] = 12 * 60 + 7 }
        shownID = item.id
        if kind == .blocked { playSound() }
        placementWork?.cancel()
        placementWork = nil
        placePanels()
        sync()
    }

    // MARK: Inputs

    private func agentsChanged(_ agents: [AgentSession]) {
        var live = Set<String>()
        for a in agents {
            live.insert(a.paneID)
            let mark = StatusMark(status: a.status, since: a.statusSince)
            if let h = history[a.paneID], h.current.status == a.status {
                history[a.paneID] = (mark, h.previous)
            } else {
                history[a.paneID] = (mark, history[a.paneID]?.current)
            }
        }
        history = history.filter { live.contains($0.key) }
        live.insert(Self.testPaneID)
        doneIn = doneIn.filter { live.contains(Self.pane(ofItemID: $0.key)) }

        let before = queue.visible.map(\.id)
        queue.reconcile(with: agents + (testAgent.map { [$0] } ?? []))
        if before.isEmpty && queue.visible.isEmpty && panels.isEmpty { return }
        sync()
    }

    private func handle(_ t: AgentTransition) {
        let cfg = manager.config
        guard cfg.notifications else { return }
        guard cfg.agentKinds.isEmpty || cfg.agentKinds.contains(t.agent.kind) else { return }
        // Suppressed toasts are simply not queued: the chip still glows.
        guard !ToastPlacementResolver.shouldSuppress(
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            herdrBundleIDs: cfg.herdrBundleIDs, quiet: cfg.quietWhenHerdrActive) else { return }
        guard queue.push(t, notifyOn: cfg.notifyOn, now: Date()), let item = queue.visible.first else { return }

        resetPause(item.id)
        doneIn[item.id] = nil
        if item.kind == .done, let prev = history[t.agent.paneID]?.previous,
           prev.status == .working, let since = prev.since {
            doneIn[item.id] = (t.agent.statusSince ?? Date()).timeIntervalSince(since)
        }
        shownID = item.id
        if item.kind == .blocked { playSound() }
        schedulePlacement()
        sync()
    }

    private func screensChanged() {
        guard !panels.isEmpty else { return }
        let infos = Self.screenInfos()
        let ids = Set(infos.map(\.id))
        var targets = panels.keys.filter(ids.contains)
        if targets.count < panels.count {
            // A toast's screen vanished: it moves to the screen the user is on.
            let active = ToastPlacementResolver.resolve(
                screens: infos, mainScreenID: infos.first?.id, mouse: NSEvent.mouseLocation,
                mode: "active", style: .island, chipRects: [:]).first?.screenID
            if let active, !targets.contains(active) { targets.append(active) }
        }
        let style = ToastStyle(rawValue: manager.config.toastStyle) ?? .island
        let rects = AgentsChipRegistry.shared.rects()
        let placements = targets.flatMap { id in
            ToastPlacementResolver.resolve(screens: infos, mainScreenID: infos.first?.id,
                                           mouse: NSEvent.mouseLocation, mode: id, style: style, chipRects: rects)
        }
        apply(placements)
        sync()
    }

    // MARK: Actions

    private func open(_ item: ToastItem) {
        if item.agent.paneID != Self.testPaneID { manager.focus(item.agent) }
        dismiss(item)
    }

    private func dismiss(_ item: ToastItem) {
        queue.dismiss(id: item.id)
        doneIn[item.id] = nil
        if shownID == item.id { shownID = nil }
        sync()
    }

    private func cycle() {
        let ids = queue.visible.map(\.id)
        guard ids.count > 1 else { return }
        let current = shownID.flatMap(ids.firstIndex(of:)) ?? 0
        shownID = ids[(current + 1) % ids.count]
        sync()
    }

    private func playSound() {
        let sound = manager.config.sound
        guard !sound.isEmpty, sound.lowercased() != "off" else { return }
        NSSound(named: NSSound.Name(sound))?.play()
    }

    // MARK: Sync

    /// Brings timers, preview polling and panel contents in line with the queue.
    private func sync() {
        prune()
        updateExpireTimer()
        updatePreviewTask()
        if queue.visible.isEmpty {
            placementWork?.cancel()
            placementWork = nil
            for panel in panels.values { retire(panel) }
            updateMonitors()
            return
        }
        if panels.isEmpty && placementWork == nil { placePanels() }
        updateModels()
    }

    private func prune() {
        let visible = queue.visible
        let ids = Set(visible.map(\.id))
        let panes = Set(visible.map(\.agent.paneID))
        hovered.formIntersection(ids)
        pauseStart = pauseStart.filter { ids.contains($0.key) }
        pausedTotal = pausedTotal.filter { ids.contains($0.key) }
        countdowns = countdowns.filter { ids.contains($0.key) }
        previews = previews.filter { panes.contains($0.key) }
        if !panes.contains(Self.testPaneID) { testAgent = nil }
        if let s = shownID, !ids.contains(s) { shownID = nil }
    }

    private var shownItem: ToastItem? {
        let visible = queue.visible
        return visible.first { $0.id == shownID } ?? visible.first
    }

    private func updateModels() {
        let visible = queue.visible
        let now = Date()
        for item in visible where item.kind == .done && countdowns[item.id] == nil {
            countdowns[item.id] = countdown(for: item, now: now)
        }
        let visibleDoneIn = doneIn.filter { id, _ in visible.contains { $0.id == id } }
        for panel in panels.values {
            let m = panel.model
            if m.reduceMotion != reduceMotion { m.reduceMotion = reduceMotion }
            if m.doneIn != visibleDoneIn { m.doneIn = visibleDoneIn }
            if m.countdowns != countdowns { m.countdowns = countdowns }
            if m.previews != previews {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { m.previews = previews }
            }
            guard panel.ready else { continue }
            let items: [ToastItem]
            let extra: Int
            if m.layout.style == .stack {
                items = visible
                extra = queue.overflow
            } else {
                items = shownItem.map { [$0] } ?? []
                extra = max(0, visible.count - 1) + queue.overflow
            }
            if m.items != items || m.extra != extra {
                withAnimation(animation) {
                    m.items = items
                    m.extra = extra
                }
            }
        }
    }

    // MARK: Done auto-hide

    private func effectiveElapsed(_ item: ToastItem, now: Date) -> TimeInterval {
        let paused = (pausedTotal[item.id] ?? 0) + (pauseStart[item.id].map { now.timeIntervalSince($0) } ?? 0)
        return now.timeIntervalSince(item.createdAt) - paused
    }

    private func countdown(for item: ToastItem, now: Date) -> ToastCountdown {
        let autohide = manager.config.doneAutohide
        let left = max(0, autohide - effectiveElapsed(item, now: now))
        // The card leaves on a 1 s tick: let the line run out on that tick rather than before it.
        let due = now.addingTimeInterval(left - Self.expireTolerance)
        let ticks = max(0, (due.timeIntervalSince(expireTimerStart)).rounded(.up))
        let lineEnd = expireTimerStart.addingTimeInterval(ticks)
        return ToastCountdown(
            fraction: autohide > 0 ? left / autohide : 0,
            remaining: max(0, lineEnd.timeIntervalSince(now)),
            paused: hovered.contains(item.id))
    }

    private func updateExpireTimer() {
        let needed = queue.visible.contains { $0.kind == .done } || queue.overflow > 0
        if needed, expireTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 0.05
            RunLoop.main.add(timer, forMode: .common)
            expireTimer = timer
            expireTimerStart = Date()
        } else if !needed, let timer = expireTimer {
            timer.invalidate()
            expireTimer = nil
        }
    }

    private func tick() {
        let now = Date()
        let autohide = manager.config.doneAutohide
        let keep = queue.visible.filter {
            $0.kind == .done
                && (hovered.contains($0.id) || effectiveElapsed($0, now: now) < autohide - Self.expireTolerance)
        }
        let before = queue.visible.count + queue.overflow
        queue.expireDone(now: now, autohide: autohide, pausedIDs: Set(keep.map(\.id)))
        if queue.visible.count + queue.overflow != before { sync() }
    }

    private func resetPause(_ id: String) {
        pauseStart[id] = nil
        pausedTotal[id] = nil
        countdowns[id] = nil
        hovered.remove(id)
    }

    // MARK: Preview polling

    /// Blocked cards on display (island/chip: only the shown one). Test toasts use a fixed sample.
    private func currentPreviewTargets() -> [String] {
        guard manager.config.previewLines > 0 else { return [] }
        let stack = panels.isEmpty
            ? manager.config.toastStyle == ToastStyle.stack.rawValue
            : panels.values.contains { $0.model.layout.style == .stack }
        let shown = stack ? queue.visible : (shownItem.map { [$0] } ?? [])
        return shown.filter { $0.kind == .blocked && $0.agent.paneID != Self.testPaneID }.map(\.agent.paneID)
    }

    private func updatePreviewTask() {
        let targets = currentPreviewTargets()
        if targets == previewTargets && (previewTask != nil || targets.isEmpty) { return }
        previewTask?.cancel()
        previewTask = nil
        previewTargets = targets
        guard !targets.isEmpty else { return }
        previewTask = Task { [weak self] in
            while !Task.isCancelled {
                for pane in targets {
                    guard let self else { return }
                    let lines = await self.manager.preview(paneID: pane)
                    if Task.isCancelled { return }
                    self.setPreview(lines, pane: pane)
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func setPreview(_ lines: [String], pane: String) {
        // A failed read keeps the last good preview.
        guard !lines.isEmpty || previews[pane] == nil, previews[pane] != lines else { return }
        guard queue.visible.contains(where: { $0.agent.paneID == pane }) else { return }
        previews[pane] = lines
        updateModels()
    }

    // MARK: Placement

    private static func screenInfos() -> [ScreenInfo] {
        NSScreen.screens.map { s in
            let d = s.monitorDescriptor
            return ScreenInfo(id: d.id, frame: d.frame, hasNotch: d.hasTopInsetCutout, notchWidth: d.notchGapWidth)
        }
    }

    private static func pane(ofItemID id: String) -> String {
        id.split(separator: "#", maxSplits: 1).first.map(String.init) ?? id
    }

    private func schedulePlacement() {
        placementWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.placementWork = nil
                guard !self.queue.visible.isEmpty else { return }
                self.placePanels()
                self.sync()
            }
        }
        placementWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.placementDelay, execute: work)
    }

    /// Resolves where toasts go right now (screen under the mouse by default) and moves panels there.
    private func placePanels() {
        let infos = Self.screenInfos()
        guard !infos.isEmpty else { return }
        let cfg = manager.config
        let placements = ToastPlacementResolver.resolve(
            screens: infos, mainScreenID: infos.first?.id, mouse: NSEvent.mouseLocation,
            mode: cfg.screen, style: ToastStyle(rawValue: cfg.toastStyle) ?? .island,
            chipRects: AgentsChipRegistry.shared.rects())
        apply(placements)
    }

    private func apply(_ placements: [ToastPlacement]) {
        let screens = NSScreen.screens
        var keep = Set<String>()
        for placement in placements {
            guard !keep.contains(placement.screenID),
                  let screen = screens.first(where: { $0.monitorDescriptor.id == placement.screenID }) else { continue }
            keep.insert(placement.screenID)
            let (frame, layout) = AgentToastGeometry.frame(for: placement, on: screen)
            if let panel = panels[placement.screenID] {
                if panel.model.layout.style == layout.style {
                    if panel.frame != frame { panel.setFrame(frame, display: true) }
                    if panel.model.layout != layout { panel.model.layout = layout }
                    continue
                }
                retire(panel)
            }
            makePanel(screenID: placement.screenID, frame: frame, layout: layout)
        }
        for (id, panel) in panels where !keep.contains(id) { retire(panel) }
        updateMonitors()
    }

    private func makePanel(screenID: String, frame: CGRect, layout: ToastLayout) {
        let model = AgentToastPanelModel(layout: layout)
        model.reduceMotion = reduceMotion
        let panel = AgentToastPanel(screenID: screenID, frame: frame, model: model)
        model.onOpen = { [weak self] item in self?.open(item) }
        model.onLater = { [weak self] item in self?.dismiss(item) }
        model.onCycle = { [weak self] in self?.cycle() }
        model.onRects = { [weak self, weak panel] rects in
            DispatchQueue.main.async {
                guard let self, let panel, self.panels[panel.screenID] === panel else { return }
                panel.canvasRects = rects
                self.updateMouse()
            }
        }
        panels[screenID] = panel
        panel.orderFrontRegardless()
        // Render the empty canvas first so the cards get their insertion transition.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 30) { [weak self, weak panel] in
            guard let self, let panel, self.panels[panel.screenID] === panel else { return }
            panel.ready = true
            self.updateModels()
        }
    }

    private func retire(_ panel: AgentToastPanel) {
        if panels[panel.screenID] === panel { panels[panel.screenID] = nil }
        panel.canvasRects = [:]
        panel.ignoresMouseEvents = true
        withAnimation(animation) {
            panel.model.items = []
            panel.model.extra = 0
        }
        retiring.append(panel)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retireDelay) { [weak self, weak panel] in
            guard let panel else { return }
            panel.orderOut(nil)
            panel.close()
            self?.retiring.removeAll { $0 === panel }
        }
    }

    // MARK: Mouse & keyboard

    private func updateMonitors() {
        let active = !panels.isEmpty
        if active, mouseMonitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMouse() }
            }) {
                mouseMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
                MainActor.assumeIsolated { self?.updateMouse() }
                return event
            }) {
                mouseMonitors.append(local)
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let code = event.keyCode
                let window = event.windowNumber
                let consumed = MainActor.assumeIsolated { self?.handleKey(code, window: window) ?? false }
                return consumed ? nil : event
            }
        } else if !active, !mouseMonitors.isEmpty {
            mouseMonitors.forEach(NSEvent.removeMonitor)
            mouseMonitors.removeAll()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            if !hovered.isEmpty { setHovered([]) }
        }
    }

    /// Only the cards (and the pill) take clicks; hovering a card pauses its auto-hide.
    private func updateMouse() {
        let p = NSEvent.mouseLocation
        var now = Set<String>()
        for panel in panels.values {
            let rects = panel.hitRects
            let inside = rects.values.contains { $0.insetBy(dx: -1, dy: -1).contains(p) }
            if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
            for (id, r) in rects where id != AgentToastMetrics.pillKey && r.contains(p) {
                now.insert(id)
            }
        }
        if now != hovered { setHovered(now) }
    }

    private func setHovered(_ now: Set<String>) {
        let t = Date()
        for id in now.subtracting(hovered) { pauseStart[id] = t }
        for id in hovered.subtracting(now) {
            if let s = pauseStart.removeValue(forKey: id) { pausedTotal[id, default: 0] += t.timeIntervalSince(s) }
        }
        let changed = now.symmetricDifference(hovered)
        hovered = now
        let visible = queue.visible
        for item in visible where item.kind == .done && changed.contains(item.id) {
            countdowns[item.id] = countdown(for: item, now: t)
        }
        updateModels()
    }

    /// ⏎ opens, esc dismisses the hovered (or first) card of the key toast panel. Returns true if consumed.
    /// Matched by window number: `NSApp.keyWindow` can be nil while Barik itself is not the active app.
    private func handleKey(_ code: UInt16, window: Int) -> Bool {
        guard let panel = panels.values.first(where: { $0.windowNumber == window && $0.isKeyWindow }),
              let item = panel.model.items.first(where: { hovered.contains($0.id) }) ?? panel.model.items.first
        else { return false }
        switch code {
        case 36, 76: // return, keypad enter
            open(item)
            return true
        case 53: // escape
            dismiss(item)
            return true
        default:
            return false
        }
    }
}
