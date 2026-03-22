import SwiftUI
import UniformTypeIdentifiers

// MARK: - View Mode

private enum ViewMode: String, CaseIterable {
    case tasks
    case matrix
    case habits

    var title: LocalizedStringKey {
        switch self {
        case .tasks:  return "tasks"
        case .matrix: return "matrix"
        case .habits: return "habits"
        }
    }

    var icon: String {
        switch self {
        case .tasks:  return "checklist"
        case .matrix: return "square.grid.2x2"
        case .habits: return "flame"
        }
    }
}

// MARK: - Main Popup

struct TickTickPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = TickTickManager.shared

    @State private var viewMode: ViewMode = .tasks
    @State private var selectedProjectId: String? = nil
    @State private var searchText: String = ""
    @State private var expandedTaskId: String? = nil
    @State private var showingAddTask = false
    @State private var newTaskTitle = ""
    @State private var highlightedTaskID: String?
    @State private var highlightedHabitID: String?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if !manager.isAuthenticated {
                    authView
                } else {
                    headerView
                    Divider().background(Color.white.opacity(0.1))

                    if manager.isLoading && manager.projects.isEmpty {
                        loadingView
                    } else {
                        // Mode tabs
                        modeTabsView
                        Divider().background(Color.white.opacity(0.1))

                        switch viewMode {
                        case .tasks:
                            projectTabsView
                            Divider().background(Color.white.opacity(0.08))
                            tasksContentView(scrollProxy: proxy)
                            if showingAddTask {
                                Divider().background(Color.white.opacity(0.08))
                                addTaskView
                            }
                        case .matrix:
                            matrixView
                        case .habits:
                            habitsView(scrollProxy: proxy)
                        }

                        if let toast = manager.taskCompletionToast {
                            Divider().background(Color.white.opacity(0.08))
                            taskCompletionToastView(toast)
                        }

                        Divider().background(Color.white.opacity(0.1))
                        footerView
                    }
                }
            }
            .onAppear {
                handlePopupFocusIfNeeded(using: proxy)
            }
            .onReceive(manager.$popupFocusTarget) { _ in
                handlePopupFocusIfNeeded(using: proxy)
            }
        }
        .frame(width: 480)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
    }

    // MARK: - Auth

    @State private var loginUsername: String = ""
    @State private var loginPassword: String = ""
    @State private var showPasswordLogin: Bool = true

    private var authView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image("TickTickIcon")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.white.opacity(0.7))
                Text("TickTick")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Sign in to access your tasks, habits and Eisenhower matrix.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28).padding(.horizontal, 32).padding(.bottom, 20)

            // Mode toggle
            HStack(spacing: 0) {
                authModeTab(title: "Email & Password", selected: showPasswordLogin) {
                    showPasswordLogin = true
                }
                authModeTab(title: "OAuth (API Key)", selected: !showPasswordLogin) {
                    showPasswordLogin = false
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 16)

            if let error = manager.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.bottom, 10)
            }

            if showPasswordLogin {
                passwordLoginView
            } else {
                oauthLoginView
            }
        }
        .padding(.bottom, 24)
    }

    private func authModeTab(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : .white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? Color.white.opacity(0.1) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var passwordLoginView: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                HStack {
                    Image(systemName: "envelope").font(.system(size: 12)).foregroundStyle(.white.opacity(0.3)).frame(width: 20)
                    TextField("Email", text: $loginUsername)
                        .font(.system(size: 12)).foregroundStyle(.white).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.white.opacity(0.07)).cornerRadius(8)

                HStack {
                    Image(systemName: "lock").font(.system(size: 12)).foregroundStyle(.white.opacity(0.3)).frame(width: 20)
                    SecureField("Password", text: $loginPassword)
                        .font(.system(size: 12)).foregroundStyle(.white).textFieldStyle(.plain)
                        .onSubmit { submitPasswordLogin() }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.white.opacity(0.07)).cornerRadius(8)
            }
            .padding(.horizontal, 24)

            Button(action: submitPasswordLogin) {
                Group {
                    if manager.isLoading {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7).tint(.white)
                            Text("Signing in…").font(.system(size: 13, weight: .medium))
                        }
                    } else {
                        Text("Sign In")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.18, green: 0.55, blue: 1.0))
            .disabled(loginUsername.isEmpty || loginPassword.isEmpty || manager.isLoading)
            .padding(.horizontal, 24)
            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

            Text("Full access: tasks, habits, matrix. Credentials stored in Keychain.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.2))
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
    }

    private var oauthLoginView: some View {
        VStack(spacing: 10) {
            Button(action: { manager.startOAuth() }) {
                Label("Authorize via Browser", systemImage: "safari")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.35, green: 0.65, blue: 0.35))
            .padding(.horizontal, 24)
            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

            Text("Requires client_id & client_secret in [widgets.default.ticktick].\nHabits are not available in this mode.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.2))
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
    }

    private func submitPasswordLogin() {
        guard !loginUsername.isEmpty, !loginPassword.isEmpty else { return }
        Task { await manager.signInPrivate(username: loginUsername, password: loginPassword) }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            Image("TickTickIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(.white.opacity(0.75))
            Text("TickTick")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            if manager.totalPendingCount > 0 {
                Text("\(manager.totalPendingCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white)
                    .clipShape(Capsule())
            }

            Spacer()

            // Search (only relevant for tasks mode)
            if viewMode == .tasks {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                    TextField("Search…", text: $searchText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .textFieldStyle(.plain)
                        .frame(width: 90)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.35))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.07))
                .cornerRadius(6)
            }

            // Refresh
            Button(action: {
                Task {
                    await manager.refresh()
                    await manager.refreshHabits()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .rotationEffect(manager.isLoading ? .degrees(360) : .degrees(0))
                    .animation(
                        manager.isLoading
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: manager.isLoading
                    )
            }
            .buttonStyle(.plain)
            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    // MARK: - Mode Tabs

    private var modeTabsView: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                let isSelected = viewMode == mode
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { viewMode = mode } }) {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11))
                        Text(mode.title)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }
    
    

    // MARK: - Project Tabs
    
    private func localizedProjectName(_ project: TickTickProject) -> String {
        let name = project.name.lowercased()

        switch name {
        case "inbox":
            return String(localized: "inbox")
        default:
            return project.name
        }
    }

    private var projectTabsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                projectTab(id: nil, name: String(localized: "all"), color: nil,
                           count: manager.tasksByProject.values.flatMap { $0 }.count)
                ForEach(manager.projects) { project in
                    projectTab(id: project.id, name: localizedProjectName(project), color: project.color,
                               count: manager.tasksByProject[project.id]?.count ?? 0)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
    }

    private func projectTab(id: String?, name: String, color: String?, count: Int) -> some View {
        let isSelected = selectedProjectId == id
        return Button(action: { selectedProjectId = id }) {
            HStack(spacing: 4) {
                if let hex = color {
                    Circle().fill(Color(hex: hex) ?? .white).frame(width: 6, height: 6)
                }
                Text(name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.35))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(isSelected ? Color.white : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.45))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isSelected ? Color.white.opacity(0.11) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    // MARK: - Tasks List

    private var visibleTasks: [TickTickTask] {
        var tasks: [TickTickTask] = selectedProjectId == nil
            ? manager.tasksByProject.values.flatMap { $0 }
            : manager.tasksByProject[selectedProjectId!] ?? []

        if !searchText.isEmpty {
            tasks = tasks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        return tasks.sorted {
            if $0.priority.rawValue != $1.priority.rawValue { return $0.priority.rawValue > $1.priority.rawValue }
            if let d0 = $0.dueDate, let d1 = $1.dueDate { return d0 < d1 }
            if $0.dueDate != nil { return true }
            if $1.dueDate != nil { return false }
            return false
        }
    }

    private func tasksContentView(scrollProxy: ScrollViewProxy) -> some View {
        Group {
            if visibleTasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.15))
                    Text(searchText.isEmpty ? "All done! 🎉" : "No results")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleTasks) { task in
                            TaskRow(
                                task: task,
                                isExpanded: expandedTaskId == task.id,
                                isHighlighted: highlightedTaskID == task.id,
                                projectName: selectedProjectId == nil ? projectName(for: task) : nil,
                                onTap: {
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                        expandedTaskId = expandedTaskId == task.id ? nil : task.id
                                    }
                                },
                                onComplete: { manager.scheduleTaskCompletion(task) },
                                onDelete:   { Task { await manager.deleteTask(task) } }
                            )
                            .id(taskScrollID(task.id))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 380)
            }
        }
    }

    private func projectName(for task: TickTickTask) -> String? {
        manager.projects.first(where: { $0.id == task.projectId }).map { localizedProjectName($0) }
    }

    // MARK: - Add Task

    private var addTaskView: some View {
        HStack(spacing: 8) {
            Image(systemName: "square").font(.system(size: 13)).foregroundStyle(.white.opacity(0.25))
            TextField("New task…", text: $newTaskTitle)
                .font(.system(size: 12)).foregroundStyle(.white)
                .textFieldStyle(.plain).onSubmit { submitNewTask() }
            if !newTaskTitle.isEmpty {
                Button(action: submitNewTask) {
                    Image(systemName: "return").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }.buttonStyle(.plain)
            }
            Button(action: { showingAddTask = false; newTaskTitle = "" }) {
                Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.white.opacity(0.25))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private func submitNewTask() {
        guard !newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let projectId = selectedProjectId ?? defaultProjectId()
        let title = newTaskTitle
        newTaskTitle = ""
        showingAddTask = false
        Task { await manager.createTask(title: title, projectId: projectId) }
    }

    private func defaultProjectId() -> String? {
        if let inbox = manager.projects.first(where: { $0.name.lowercased() == "inbox" }) {
            return inbox.id
        }
        return manager.projects.first?.id
    }

    // MARK: - Eisenhower Matrix

    private var matrixView: some View {
        let allTasks = manager.tasksByProject.values.flatMap { $0 }

        let q1 = sortMatrixTasks(allTasks.filter {  isUrgent($0) &&  isImportant($0) })
        let q2 = sortMatrixTasks(allTasks.filter { !isUrgent($0) &&  isImportant($0) })
        let q3 = sortMatrixTasks(allTasks.filter {  isUrgent($0) && !isImportant($0) })
        let q4 = sortMatrixTasks(allTasks.filter { !isUrgent($0) && !isImportant($0) })

        return VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 1) {
                Color.clear.frame(width: 70, height: 1) // placeholder for row labels
                matrixAxisLabel(localized("URGENT"))
                matrixAxisLabel(localized("NOT URGENT"))
            }
            .padding(.top, 10).padding(.bottom, 2).padding(.horizontal, 8)

            // Grid
            HStack(alignment: .top, spacing: 1) {
                // Row labels
                VStack(spacing: 1) {
                    matrixRowLabel(localized("IMPORTANT"), height: 200)
                    matrixRowLabel(localized("NOT IMPORTANT"), height: 200)
                }
                .frame(width: 18)

                // Quadrants
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        MatrixQuadrant(
                            title: localized("DO FIRST"),
                            subtitle: localized("Important & Urgent"),
                            accentColor: Color(red: 0.95, green: 0.35, blue: 0.35),
                            tasks: q1, expandedTaskId: $expandedTaskId,
                            onComplete: { t in manager.scheduleTaskCompletion(t) },
                            onMove: { id in Task { await manager.moveTaskInMatrix(taskId: id, urgent: true, important: true) } }
                        )
                        MatrixQuadrant(
                            title: localized("SCHEDULE"),
                            subtitle: localized("Important, Not Urgent"),
                            accentColor: Color(red: 0.95, green: 0.75, blue: 0.18),
                            tasks: q2, expandedTaskId: $expandedTaskId,
                            onComplete: { t in manager.scheduleTaskCompletion(t) },
                            onMove: { id in Task { await manager.moveTaskInMatrix(taskId: id, urgent: false, important: true) } }
                        )
                    }
                    HStack(spacing: 1) {
                        MatrixQuadrant(
                            title: localized("DELEGATE"),
                            subtitle: localized("Urgent, Not Important"),
                            accentColor: Color(red: 0.35, green: 0.65, blue: 1.0),
                            tasks: q3, expandedTaskId: $expandedTaskId,
                            onComplete: { t in manager.scheduleTaskCompletion(t) },
                            onMove: { id in Task { await manager.moveTaskInMatrix(taskId: id, urgent: true, important: false) } }
                        )
                        MatrixQuadrant(
                            title: localized("ELIMINATE"),
                            subtitle: localized("Not Important, Not Urgent"),
                            accentColor: Color(red: 0.33, green: 0.75, blue: 0.43),
                            tasks: q4, expandedTaskId: $expandedTaskId,
                            onComplete: { t in manager.scheduleTaskCompletion(t) },
                            onMove: { id in Task { await manager.moveTaskInMatrix(taskId: id, urgent: false, important: false) } }
                        )
                    }
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
    }

    private func matrixAxisLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.3))
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    // Rotated label using a fixed-size container — works reliably in SwiftUI
    private func matrixRowLabel(_ text: String, height: CGFloat) -> some View {
        ZStack {
            Text(text)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .fixedSize()
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: height)
        .clipped()
    }

    private func isUrgent(_ task: TickTickTask) -> Bool {
        // TickTick matrix urgency is not derived from due dates reliably.
        // Until we decode the actual quadrant/source field from the private API,
        // showing due-date-based urgency places tasks into the wrong quadrants.
        _ = task
        return false
    }

    private func isImportant(_ task: TickTickTask) -> Bool {
        task.priority == .high || task.priority == .medium
    }

    private func sortMatrixTasks(_ tasks: [TickTickTask]) -> [TickTickTask] {
        tasks.sorted { lhs, rhs in
            let lhsOverdue = lhs.dueDate.map { $0 < Date() } ?? false
            let rhsOverdue = rhs.dueDate.map { $0 < Date() } ?? false
            if lhsOverdue != rhsOverdue { return lhsOverdue }

            if lhs.priority.rawValue != rhs.priority.rawValue {
                return lhs.priority.rawValue > rhs.priority.rawValue
            }

            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?) where l != r:
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    // MARK: - Habits

    private func habitsView(scrollProxy: ScrollViewProxy) -> some View {
        Group {
            if manager.habits.isEmpty && !manager.isLoading {
                VStack(spacing: 10) {
                    Image(systemName: "flame").font(.system(size: 26)).foregroundStyle(.white.opacity(0.15))
                    Text("No habits found")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.3))
                    Text("Create habits in TickTick to track them here.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.2))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 36)
            } else if manager.isLoading && manager.habits.isEmpty {
                loadingView
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        habitsWeekSummaryView
                            .padding(.vertical, 6)
                        ForEach(manager.habits) { habit in
                            HabitRow(habit: habit, isHighlighted: highlightedHabitID == habit.id, onCheckin: {
                                Task { await manager.toggleHabitCheckin(habit) }
                            })
                            .id(habitScrollID(habit.id))
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .frame(maxHeight: 380)
            }
        }
    }

    private var habitsWeekSummaryView: some View {
        let days = last7Days()
        let total = max(manager.habits.count, 1)
        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { date in
                let done = manager.habits.filter { $0.completedDates.contains(dayString(date)) }.count
                let progress = Double(done) / Double(total)
                HabitWeekRing(
                    date: date,
                    progress: progress,
                    isToday: Calendar.current.isDateInToday(date)
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private func last7Days() -> [Date] {
        let cal = Calendar.current
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }
    }

    private func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 12) {
            if viewMode == .tasks {
                Button(action: { withAnimation { showingAddTask.toggle() } }) {
                    Label("Add Task", systemImage: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
            }

            Spacer()

            if let error = manager.errorMessage {
                Text(error)
                    .font(.system(size: 10)).foregroundStyle(.red.opacity(0.6))
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: 200)
            }

            Button(action: { openTickTick() }) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.2))
            }
            .buttonStyle(.plain)
            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

            Button(action: { Task { await manager.signOut() } }) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.2))
            }
            .buttonStyle(.plain)
            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
    }

    private func taskCompletionToastView(_ toast: TickTickTaskCompletionToast) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.green.opacity(0.85))

            Text("Task completed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            Text(toast.title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)

            Spacer()

            Button(action: { manager.undoScheduledTaskCompletion(taskId: toast.id) }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 22)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Shared

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView().scaleEffect(0.75)
            Text("Loading…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private func taskScrollID(_ id: String) -> String {
        "ticktick-task-\(id)"
    }

    private func habitScrollID(_ id: String) -> String {
        "ticktick-habit-\(id)"
    }

    private func handlePopupFocusIfNeeded(using proxy: ScrollViewProxy) {
        guard let target = manager.popupFocusTarget else { return }

        switch target.kind {
        case .task(let taskID):
            selectedProjectId = nil
            searchText = ""
            withAnimation(.easeInOut(duration: 0.18)) {
                viewMode = .tasks
                expandedTaskId = taskID
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(taskScrollID(taskID), anchor: .center)
                }
            }
            highlightTask(taskID, token: target.token)
        case .habit(let habitID):
            withAnimation(.easeInOut(duration: 0.18)) {
                viewMode = .habits
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(habitScrollID(habitID), anchor: .center)
                }
            }
            highlightHabit(habitID, token: target.token)
        }

        manager.clearPopupFocusTarget()
    }

    private func highlightTask(_ id: String, token: Int) {
        withAnimation(.easeInOut(duration: 0.28)) {
            highlightedTaskID = id
            highlightedHabitID = nil
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if highlightedTaskID == id {
                withAnimation(.easeInOut(duration: 0.45)) {
                    highlightedTaskID = nil
                }
            }
            _ = token
        }
    }

    private func highlightHabit(_ id: String, token: Int) {
        withAnimation(.easeInOut(duration: 0.28)) {
            highlightedHabitID = id
            highlightedTaskID = nil
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if highlightedHabitID == id {
                withAnimation(.easeInOut(duration: 0.45)) {
                    highlightedHabitID = nil
                }
            }
            _ = token
        }
    }

    private func openTickTick() {
        if let url = URL(string: "ticktick://"), NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else if let web = URL(string: "https://ticktick.com") {
            NSWorkspace.shared.open(web)
        }
    }
}

// MARK: - Matrix Quadrant

private struct MatrixQuadrant: View {
    private let contentHeight: CGFloat = 160

    let title: String
    let subtitle: String
    let accentColor: Color
    let tasks: [TickTickTask]
    @Binding var expandedTaskId: String?
    let onComplete: (TickTickTask) -> Void
    let onMove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView

            Divider().background(accentColor.opacity(0.15))

            contentView
            .frame(height: contentHeight)
        }
        .frame(maxWidth: .infinity)
        .background(accentColor.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(accentColor.opacity(0.12), lineWidth: 1)
        )
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let item = providers.first else { return false }
            _ = item.loadObject(ofClass: String.self) { id, _ in
                guard let id else { return }
                DispatchQueue.main.async {
                    onMove(id)
                }
            }
            return true
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentColor)
                Spacer()
                if !tasks.isEmpty {
                    Text("\(tasks.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accentColor.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var contentView: some View {
        if tasks.isEmpty {
            Text("No tasks")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(tasks.prefix(20))) { task in
                        MatrixTaskRow(
                            task: task,
                            accentColor: accentColor,
                            isExpanded: expandedTaskId == task.id,
                            onTap: {
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                    expandedTaskId = expandedTaskId == task.id ? nil : task.id
                                }
                            },
                            onComplete: { onComplete(task) }
                        )
                    }
                }
            }
            .frame(maxHeight: contentHeight)
        }
    }
}

private struct MatrixTaskRow: View {
    let task: TickTickTask
    let accentColor: Color
    let isExpanded: Bool
    let onTap: () -> Void
    let onComplete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onComplete) {
                    Image(systemName: "circle")
                        .font(.system(size: 12))
                        .foregroundStyle(accentColor.opacity(0.5))
                }
                .buttonStyle(.plain)
                .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

                Text(task.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(isExpanded ? nil : 1)

                Spacer()

                if let due = task.dueDate {
                    Text(matrixDue(due))
                        .font(.system(size: 9))
                        .foregroundStyle(isOverdue(due) ? .red.opacity(0.7) : .white.opacity(0.2))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)

            if isExpanded && !task.subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(task.subtasks.prefix(5))) { sub in
                        HStack(spacing: 4) {
                            Circle().fill(.white.opacity(0.2)).frame(width: 3, height: 3)
                            Text(sub.title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 24).padding(.bottom, 5)
            }
        }
        .background(isHovered ? accentColor.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeInOut(duration: 0.1)) { isHovered = h } }
        .onTapGesture { onTap() }
        .onDrag { NSItemProvider(object: task.id as NSString) }
    }

    private func isOverdue(_ date: Date) -> Bool { date < Date() }

    private func matrixDue(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)    { return NSLocalizedString("Today", comment: "") }
        if cal.isDateInTomorrow(date) { return NSLocalizedString("Tomorrow", comment: "") }
        if isOverdue(date)            { return NSLocalizedString("Overdue", comment: "") }
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }
}

// MARK: - Habit Row

private struct HabitRow: View {
    let habit: TickTickHabit
    let isHighlighted: Bool
    let onCheckin: () -> Void

    @State private var isHovered = false

    private var todayDone: Bool { habit.checkedInToday }

    var body: some View {
        HStack(spacing: 12) {
            // Check-in button
            Button(action: onCheckin) {
                ZStack {
                    Circle()
                        .fill(todayDone ? habitColor.opacity(0.25) : Color.white.opacity(0.05))
                        .frame(width: 32, height: 32)
                    Image(systemName: todayDone ? "checkmark" : "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(todayDone ? habitColor : .white.opacity(0.35))
                }
            }
            .buttonStyle(.plain)
            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(todayDone ? 0.5 : 0.9))

                HStack(spacing: 8) {
                    // Repeat rule intentionally hidden per UI preference
                    Label("\(habit.totalCheckIns)", systemImage: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow.opacity(0.8))
                    if habit.streak > 0 {
                        Label("\(habit.streak)d", systemImage: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(habit.streak >= 7 ? .orange : .white.opacity(0.35))
                    }
                }
            }

            Spacer()

            // Last 7 days dots
            HStack(spacing: 4) {
                ForEach(last7Days(), id: \.self) { date in
                    let done = habit.completedDates.contains(dayString(date))
                    Circle()
                        .fill(done ? habitColor : Color.white.opacity(0.08))
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle().stroke(
                                Calendar.current.isDateInToday(date) ? habitColor.opacity(0.5) : Color.clear,
                                lineWidth: 1
                            )
                        )
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(isHighlighted ? habitColor.opacity(0.14) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? habitColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.28), value: isHighlighted)
        .onHover { h in withAnimation(.easeInOut(duration: 0.1)) { isHovered = h } }
    }

    private var habitColor: Color {
        guard let hex = habit.color else { return Color(red: 0.3, green: 0.65, blue: 1.0) }
        return Color(hex: hex) ?? Color(red: 0.3, green: 0.65, blue: 1.0)
    }

    private func last7Days() -> [Date] {
        let cal = Calendar.current
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: Date()) }
    }

    private func dayString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
}

private struct HabitWeekRing: View {
    let date: Date
    let progress: Double
    let isToday: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(dayNumber(date))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(weekdayShort(date))
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.35))
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3)
                    .frame(width: 18, height: 18)
                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: min(progress, 1.0))
                        .stroke(progress >= 1.0 ? Color.green : Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 18, height: 18)
                }
                if isToday {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        .frame(width: 22, height: 22)
                }
            }
        }
    }

    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d")
        return f.string(from: date)
    }

    private func weekdayShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateFormat = "EE"
        return f.string(from: date)
    }
}

// MARK: - Task Row

private struct TaskRow: View {
    let task: TickTickTask
    let isExpanded: Bool
    let isHighlighted: Bool
    let projectName: String?
    let onTap: () -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var completeHovered = false
    @State private var deleteHovered = false

    private var isOverdue: Bool {
        guard let due = task.dueDate else { return false }
        return due < Date()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(alignment: .top, spacing: 10) {
                // Complete button
                Button(action: onComplete) {
                    Image(systemName: completeHovered ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(completeHovered ? .green : .white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .onHover { h in
                    completeHovered = h
                    h ? NSCursor.pointingHand.push() : NSCursor.pop()
                }
                .padding(.top, 1)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(task.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(isExpanded ? nil : 2)
                        if task.priority != .none {
                            priorityDot(task.priority)
                        }
                    }

                    // Meta row
                    HStack(spacing: 10) {
                        if let due = task.dueDate {
                            Label(formatDue(due), systemImage: "calendar")
                                .font(.system(size: 10))
                                .foregroundStyle(isOverdue ? .red.opacity(0.8) : .white.opacity(0.3))
                        }
                        if let proj = projectName {
                            Text(proj)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.2))
                        }
                        if !task.items.isEmpty {
                            let done = task.items.filter { $0.isCompleted }.count
                            Label("\(done)/\(task.items.count)", systemImage: "checklist")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        if !task.subtasks.isEmpty {
                            let done = task.subtasks.filter { $0.isCompleted }.count
                            Label("\(done)/\(task.subtasks.count)", systemImage: "list.bullet.indent")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }

                Spacer()

                // Actions on hover
                if isHovered {
                    HStack(spacing: 6) {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(deleteHovered ? .red : .white.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                        .onHover { h in
                            deleteHovered = h
                            h ? NSCursor.pointingHand.push() : NSCursor.pop()
                        }
                    }
                    .transition(.opacity)
                }

                // Expand chevron
                if !task.items.isEmpty || !task.subtasks.isEmpty || !(task.content ?? "").isEmpty {
                    Button(action: onTap) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                    .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .contentShape(Rectangle())
            .onHover { h in withAnimation(.easeInOut(duration: 0.12)) { isHovered = h } }

            // Expanded section
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Content/notes
                    if let content = task.content, !content.isEmpty {
                        Text(content)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(5)
                            .padding(.leading, 26)
                    }

                    // Checklist items (kind=CHECKLIST)
                    if !task.items.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(task.items) { item in
                                HStack(spacing: 7) {
                                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 11))
                                        .foregroundStyle(item.isCompleted ? .green.opacity(0.6) : .white.opacity(0.25))
                                    Text(item.title)
                                        .font(.system(size: 11))
                                        .foregroundStyle(item.isCompleted ? .white.opacity(0.25) : .white.opacity(0.65))
                                        .strikethrough(item.isCompleted)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.leading, 26)
                    }

                    // Subtasks (вложенные задачи)
                    if !task.subtasks.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(task.subtasks) { sub in
                                HStack(spacing: 7) {
                                    Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(sub.isCompleted ? .green.opacity(0.6) : .white.opacity(0.25))
                                    Text(sub.title)
                                        .font(.system(size: 11))
                                        .foregroundStyle(sub.isCompleted ? .white.opacity(0.25) : .white.opacity(0.7))
                                        .strikethrough(sub.isCompleted)
                                        .lineLimit(2)
                                    Spacer()
                                    if sub.priority != .none { priorityDot(sub.priority) }
                                    if let due = sub.dueDate {
                                        Text(formatDue(due))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.white.opacity(0.2))
                                    }
                                }
                            }
                        }
                        .padding(.leading, 26)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? highlightColor.opacity(0.14) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHighlighted ? highlightColor.opacity(0.45) : Color.clear, lineWidth: 1)
                )
                .padding(.horizontal, 8)
        )
        .animation(.easeInOut(duration: 0.28), value: isHighlighted)
    }

    private var highlightColor: Color {
        if isOverdue {
            return Color.red
        }
        if task.priority != .none {
            return Color(hex: task.priority.color) ?? .white
        }
        return .white
    }

    @ViewBuilder
    private func priorityDot(_ priority: TickTickPriority) -> some View {
        Circle()
            .fill(Color(hex: priority.color) ?? .orange)
            .frame(width: 5, height: 5)
    }

    private func formatDue(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return NSLocalizedString("Today", comment: "") }
        if cal.isDateInTomorrow(date)  { return NSLocalizedString("Tomorrow", comment: "") }
        if cal.isDateInYesterday(date) { return NSLocalizedString("Yesterday", comment: "") }
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }
}

// MARK: - Color from Hex

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >>  8) & 0xFF) / 255,
            blue:  Double( val        & 0xFF) / 255
        )
    }
}
