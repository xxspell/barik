import SwiftUI

private enum PomodoroPopupTab: String, CaseIterable {
    case timer
    case history
    case stats

    var title: String {
        switch self {
        case .timer:
            return String(localized: "pomodoro.tab.timer")
        case .history:
            return String(localized: "pomodoro.tab.history")
        case .stats:
            return String(localized: "pomodoro.tab.stats")
        }
    }

    var icon: String {
        switch self {
        case .timer:
            return "timer"
        case .history:
            return "list.bullet.rectangle.portrait"
        case .stats:
            return "chart.bar.xaxis"
        }
    }
}

private struct HistoryIconAnchor: Equatable {
    let index: Int
    let bounds: Anchor<CGRect>
}

private struct HistoryIconAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [HistoryIconAnchor] = []

    static func reduce(value: inout [HistoryIconAnchor], nextValue: () -> [HistoryIconAnchor]) {
        value.append(contentsOf: nextValue())
    }
}

struct PomodoroPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = PomodoroManager.shared
    @ObservedObject private var tickTickManager = TickTickManager.shared

    @State private var selectedTab: PomodoroPopupTab = .timer
    @State private var loginUsername: String = ""
    @State private var loginPassword: String = ""
    @State private var isTaskPickerExpanded = false

    private var accentColor: Color {
        switch manager.phase {
        case .focus, .focusPaused, .waitingForBreak:
            return Color(red: 1.0, green: 0.42, blue: 0.33)
        case .breakTime, .breakPaused:
            return Color(red: 0.43, green: 0.87, blue: 0.63)
        case .idle:
            return Color(red: 1.0, green: 0.42, blue: 0.33)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))
            tabs
            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    syncBanner

                    switch selectedTab {
                    case .timer:
                        timerContent
                    case .history:
                        historyContent
                    case .stats:
                        statsContent
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 440)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
        .onAppear {
            manager.popupPresented()
            manager.startUpdating(config: configProvider.config)
            manager.refreshManually()
        }
        .onDisappear {
            manager.popupDismissed()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 38, height: 38)

                Image("PomodoroIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "pomodoro.title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)

                Text(manager.phase.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(manager.effectiveIntegrationMode == .ticktick ? String(localized: "pomodoro.sync.ticktick") : String(localized: "pomodoro.sync.local_timer"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text(manager.effectiveIntegrationMode == .ticktick ? String(localized: "pomodoro.sync.private_api") : String(localized: "pomodoro.sync.works_offline"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Button {
                manager.refreshManually()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            RoutedSettingsLink(section: .pomodoro) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            ForEach(PomodoroPopupTab.allCases, id: \.rawValue) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.45))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var syncBanner: some View {
        if manager.needsTickTickSignIn {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "pomodoro.signin.private_required"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                Text(String(localized: "pomodoro.signin.public_api_not_supported"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage = tickTickManager.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                }

                HStack(spacing: 8) {
                    TextField(String(localized: "pomodoro.signin.email"), text: $loginUsername)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    SecureField(String(localized: "pomodoro.signin.password"), text: $loginPassword)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    Task {
                        await tickTickManager.signInPrivate(username: loginUsername, password: loginPassword)
                        await manager.refreshRemoteData(reason: "pomodoro-login")
                    }
                } label: {
                    HStack(spacing: 8) {
                        if tickTickManager.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }

                        Text(tickTickManager.isLoading ? String(localized: "pomodoro.signin.signing_in") : String(localized: "pomodoro.signin.sign_in"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(accentColor.opacity(0.92))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(loginUsername.isEmpty || loginPassword.isEmpty || tickTickManager.isLoading)
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        } else if let syncError = manager.syncError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)

                Text(syncError)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(12)
            .background(Color.yellow.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var timerContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            timerHero
            durationControls
            taskBindingCard
            noteCard
            actionsCard
        }
    }

    private var timerHero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: max(manager.progress, 0.02))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [accentColor.opacity(0.35), accentColor]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 6) {
                    Text(manager.remainingLabel)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(manager.phase.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: 170, height: 170)

            HStack(spacing: 10) {
                statusPill(title: manager.effectiveIntegrationMode == .ticktick ? "TickTick" : String(localized: "pomodoro.integration.local"), color: manager.effectiveIntegrationMode == .ticktick ? .blue : .white)
                statusPill(title: manager.phase.isBreakRelated ? String(localized: "pomodoro.phase.break_short") : String(localized: "pomodoro.phase.focus_short"), color: manager.phase.isBreakRelated ? .green : accentColor)
                if manager.isPaused {
                    statusPill(title: String(localized: "pomodoro.state.paused"), color: .yellow)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            LinearGradient(
                colors: [accentColor.opacity(0.14), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var durationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "pomodoro.durations.title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            HStack(spacing: 10) {
                durationControl(
                    title: String(localized: "pomodoro.phase.focus_short"),
                    value: manager.focusDurationMinutes,
                    range: 5...180,
                    decrement: { manager.setFocusDuration(minutes: manager.focusDurationMinutes - 5) },
                    increment: { manager.setFocusDuration(minutes: manager.focusDurationMinutes + 5) }
                )

                durationControl(
                    title: String(localized: "pomodoro.phase.break_short"),
                    value: manager.shortBreakDurationMinutes,
                    range: 1...60,
                    decrement: { manager.setShortBreakDuration(minutes: manager.shortBreakDurationMinutes - 1) },
                    increment: { manager.setShortBreakDuration(minutes: manager.shortBreakDurationMinutes + 1) }
                )
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var taskBindingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "pomodoro.task_context.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                Spacer()

                if !manager.selectedTaskTitle.isEmpty {
                    Button {
                        manager.clearTaskBinding()
                        isTaskPickerExpanded = false
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark.circle.fill")
                            Text(String(localized: "pomodoro.action.clear"))
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !manager.selectedTaskTitle.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11, weight: .semibold))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(manager.selectedTaskTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(manager.selectedTaskID == nil ? String(localized: "pomodoro.task_context.text_context") : String(localized: "pomodoro.task_context.bound_to_ticktick"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                Button {
                    isTaskPickerExpanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "checklist")
                        Text(isTaskPickerExpanded ? String(localized: "pomodoro.task_picker.hide") : String(localized: "pomodoro.task_picker.show"))
                        Spacer()
                        Image(systemName: isTaskPickerExpanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

            }

            if isTaskPickerExpanded {
                VStack(spacing: 8) {
                    TextField(
                        String(localized: "pomodoro.task_picker.search_placeholder"),
                        text: Binding(
                            get: { manager.taskSearchQuery },
                            set: { manager.updateTaskSearchQuery($0) }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if taskSuggestions.isEmpty {
                        Text(String(localized: "pomodoro.task_picker.empty"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(taskSuggestions.prefix(8), id: \.id) { task in
                                Button {
                                    manager.selectTickTickTask(task)
                                    isTaskPickerExpanded = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(task.title)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)

                                            Text(projectName(for: task))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.45))
                                                .lineLimit(1)
                                        }
                                        Spacer()

                                        if manager.selectedTaskID == task.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(taskBackground(for: task))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "pomodoro.note.title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            ZStack(alignment: .topLeading) {
                if manager.noteDraft.isEmpty {
                    Text(String(localized: "pomodoro.note.placeholder"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }

                TextEditor(text: $manager.noteDraft)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .frame(height: 84)
            }
            .padding(6)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "pomodoro.actions.title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))

            switch manager.phase {
            case .idle:
                actionButton(title: String(localized: "pomodoro.action.start_focus"), icon: "play.fill", fill: accentColor) {
                    manager.startFocusSession()
                }

            case .focus, .focusPaused:
                HStack(spacing: 10) {
                    actionButton(
                        title: manager.isPaused ? String(localized: "pomodoro.action.resume") : String(localized: "pomodoro.action.pause"),
                        icon: manager.isPaused ? "play.fill" : "pause.fill",
                        fill: manager.isPaused ? .green : .yellow
                    ) {
                        manager.togglePause()
                    }

                    actionButton(title: String(localized: "pomodoro.action.stop"), icon: "stop.fill", fill: .white.opacity(0.12), foreground: .white) {
                        manager.cancelCurrentTimer()
                    }
                }

            case .breakTime, .breakPaused:
                HStack(spacing: 10) {
                    actionButton(
                        title: manager.isPaused ? String(localized: "pomodoro.action.resume") : String(localized: "pomodoro.action.pause"),
                        icon: manager.isPaused ? "play.fill" : "pause.fill",
                        fill: manager.isPaused ? .green : .yellow
                    ) {
                        manager.togglePause()
                    }

                    actionButton(title: String(localized: "pomodoro.action.skip_break"), icon: "forward.fill", fill: accentColor) {
                        manager.skipBreakAndStartNextFocus()
                    }
                }

            case .waitingForBreak:
                VStack(alignment: .leading, spacing: 10) {
                    if let overtimeLabel = manager.suggestedOvertimeLabel {
                        Text(String(format: String(localized: "pomodoro.overtime.description"), overtimeLabel))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(String(localized: "pomodoro.overtime.waiting_description"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let overtimeLabel = manager.suggestedOvertimeLabel {
                        actionButton(
                            title: String(format: String(localized: "pomodoro.action.add_more"), overtimeLabel),
                            icon: "plus.circle.fill",
                            fill: accentColor
                        ) {
                            manager.applyOvertimeWorked()
                        }
                    }

                    HStack(spacing: 10) {
                        actionButton(
                            title: String(format: String(localized: "pomodoro.action.take_break"), manager.nextBreakDurationLabel),
                            icon: "leaf.fill",
                            fill: .green
                        ) {
                            manager.startBreakSession()
                        }

                        actionButton(title: String(localized: "pomodoro.action.skip_break"), icon: "forward.fill", fill: accentColor) {
                            manager.skipBreakAndStartNextFocus()
                        }

                        actionButton(title: String(localized: "pomodoro.action.finish_cycle"), icon: "checkmark", fill: .white.opacity(0.12), foreground: .white) {
                            manager.finishCycle()
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if manager.history.isEmpty {
                emptyState(title: String(localized: "pomodoro.history.empty_title"), subtitle: String(localized: "pomodoro.history.empty_subtitle"))
            } else {
                ForEach(groupedHistory, id: \.dateKey) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))

                        VStack(spacing: 10) {
                            ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                                historyRow(entry, index: index)
                            }
                        }
                        .overlayPreferenceValue(HistoryIconAnchorPreferenceKey.self) { anchors in
                            GeometryReader { proxy in
                                let sortedAnchors = anchors.sorted { $0.index < $1.index }

                                ForEach(Array(zip(sortedAnchors, sortedAnchors.dropFirst())), id: \.0.index) { current, next in
                                    let currentRect = proxy[current.bounds]
                                    let nextRect = proxy[next.bounds]
                                    let connectorGap: CGFloat = 12

                                    Rectangle()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 2, height: max(nextRect.midY - currentRect.midY - (connectorGap * 2), 0))
                                        .offset(
                                            x: currentRect.midX - 1,
                                            y: currentRect.midY + connectorGap
                                        )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var statsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statsCard(title: String(localized: "pomodoro.stats.today_count"), value: "\(manager.statistics.todayCount)")
                statsCard(title: String(localized: "pomodoro.stats.today_focus"), value: manager.statistics.todayMinutes.formattedDuration)
                statsCard(title: String(localized: "pomodoro.stats.total_count"), value: "\(manager.statistics.totalCount)")
                statsCard(title: String(localized: "pomodoro.stats.total_focus"), value: manager.statistics.totalMinutes.formattedDuration)
            }
        }
    }

    private func historyRow(_ entry: PomodoroHistoryEntry, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image("PomodoroIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(entry.source == .ticktick ? accentColor.opacity(0.92) : Color.white.opacity(0.8))
                .anchorPreference(
                    key: HistoryIconAnchorPreferenceKey.self,
                    value: .bounds
                ) { [HistoryIconAnchor(index: index, bounds: $0)] }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(String(format: String(localized: "pomodoro.history.time_range"), entry.startAt.pomodoroTimeLabel, entry.endAt.pomodoroTimeLabel))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(String(format: String(localized: "pomodoro.duration.minutes_short"), entry.displayDurationMinutes))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }

                if let taskTitle = entry.taskTitle, !taskTitle.isEmpty {
                    Text(taskTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.74))
                }

                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func durationControl(
        title: String,
        value: Int,
        range: ClosedRange<Int>,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))

            HStack(spacing: 8) {
                smallIconButton(systemName: "minus", action: decrement)
                    .disabled(value <= range.lowerBound)

                Text("\(value)m")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                smallIconButton(systemName: "plus", action: increment)
                    .disabled(value >= range.upperBound)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func smallIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func actionButton(
        title: String,
        icon: String,
        fill: Color,
        foreground: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func statsCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var groupedHistory: [PomodoroHistorySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: manager.history) { entry in
            calendar.startOfDay(for: entry.startAt)
        }

        return grouped
            .map { date, entries in
                PomodoroHistorySection(dateKey: date, entries: entries.sorted { $0.startAt > $1.startAt })
            }
            .sorted { $0.dateKey > $1.dateKey }
    }

    private var taskSuggestions: [TickTickTask] {
        let allTasks = tickTickManager.tasksByProject.values
            .flatMap { $0 }
            .filter { !$0.isCompleted && ($0.deleted ?? 0) == 0 }

        let query = manager.taskSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? allTasks
            : allTasks.filter { $0.title.localizedCaseInsensitiveContains(query) }

        return filtered.sorted(by: compareTasks)
    }

    private func projectName(for task: TickTickTask) -> String {
        let projectLabel: String
        if let dueDate = task.dueDate, Calendar.current.isDateInToday(dueDate) {
            if task.projectId == "inbox" || task.projectId.hasPrefix("inbox") {
                projectLabel = String(localized: "inbox")
            } else {
                projectLabel = tickTickManager.projects.first(where: { $0.id == task.projectId })?.name ?? String(localized: "pomodoro.project.none")
            }
            return String(format: String(localized: "pomodoro.project.today_format"), projectLabel)
        }
        if task.projectId == "inbox" || task.projectId.hasPrefix("inbox") {
            return String(localized: "inbox")
        }
        return tickTickManager.projects.first(where: { $0.id == task.projectId })?.name ?? String(localized: "pomodoro.project.none")
    }

    private func compareTasks(_ lhs: TickTickTask, _ rhs: TickTickTask) -> Bool {
        let lhsToday = lhs.dueDate.map { Calendar.current.isDateInToday($0) } ?? false
        let rhsToday = rhs.dueDate.map { Calendar.current.isDateInToday($0) } ?? false
        if lhsToday != rhsToday {
            return lhsToday && !rhsToday
        }

        if lhs.priority.rawValue != rhs.priority.rawValue {
            return lhs.priority.rawValue > rhs.priority.rawValue
        }

        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    @ViewBuilder
    private func taskBackground(for task: TickTickTask) -> some View {
        let baseColor = Color(hex: task.priority.color) ?? Color.white
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        baseColor.opacity(task.priority == .none ? 0.06 : 0.18),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

private struct PomodoroHistorySection {
    let dateKey: Date
    let entries: [PomodoroHistoryEntry]

    var title: String {
        dateKey.pomodoroDateLabel
    }
}

private extension Date {
    var pomodoroDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .long
        return formatter.string(from: self)
    }

    var pomodoroTimeLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }
}

private extension Int {
    var formattedDuration: String {
        if self >= 60 {
            let hours = self / 60
            let minutes = self % 60
            if minutes == 0 {
                return "\(hours)ч"
            }
            return "\(hours)ч \(minutes)м"
        }
        return "\(self)м"
    }
}
