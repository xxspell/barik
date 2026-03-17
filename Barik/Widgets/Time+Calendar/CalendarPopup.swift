import EventKit
import SwiftUI

// MARK: - CalendarPopup

struct CalendarPopup: View {
    let calendarManager: CalendarManager

    @ObservedObject var configProvider: ConfigProvider
    @State private var selectedVariant: MenuBarPopupVariant = .box

    var body: some View {
        MenuBarPopupVariantView(
            selectedVariant: selectedVariant,
            onVariantSelected: { variant in
                selectedVariant = variant
                ConfigManager.shared.updateConfigValue(
                    key: "widgets.default.time.popup.view-variant",
                    newValue: variant.rawValue
                )
            },
            box: { CalendarBoxPopup() },
            vertical: { CalendarVerticalPopup(calendarManager) },
            horizontal: { CalendarHorizontalPopup(calendarManager) }
        )
        .onAppear {
            if let variantString = configProvider.config["popup"]?
                .dictionaryValue?["view-variant"]?.stringValue,
                let variant = MenuBarPopupVariant(rawValue: variantString)
            {
                selectedVariant = variant
            } else {
                selectedVariant = .box
            }
        }
        .onReceive(configProvider.$config) { newConfig in
            if let variantString = newConfig["popup"]?.dictionaryValue?[
                "view-variant"]?.stringValue,
                let variant = MenuBarPopupVariant(rawValue: variantString)
            {
                selectedVariant = variant
            }
        }
    }
}

struct CalendarBoxPopup: View {
    var body: some View {
        VStack(spacing: 0) {
            Text(currentMonthYear)
                .font(.title2)
                .padding(.bottom, 25)
            WeekdayHeaderView()
            CalendarDaysView(
                weeks: weeks,
                currentYear: currentYear,
                currentMonth: currentMonth,
                selectedDay: .constant(nil)
            )
        }
        .padding(30)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
    }
}

struct CalendarVerticalPopup: View {
    let calendarManager: CalendarManager
    @ObservedObject private var tickTick = TickTickManager.shared
    @State private var selectedDay: Int? = Calendar.current.component(.day, from: Date())

    init(_ calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    private var taskDaysForCurrentMonth: [Int: (hasDeadline: Bool, priority: TickTickPriority)] {
        let cal = Calendar.current
        var result: [Int: (hasDeadline: Bool, priority: TickTickPriority)] = [:]

        if tickTick.isAuthenticated {
            for task in tickTick.tasksByProject.values.flatMap({ $0 }).filter({ !$0.isCompleted }) {
                guard let due = task.dueDate else { continue }
                let comps = cal.dateComponents([.year, .month, .day], from: due)
                guard comps.year == currentYear, comps.month == currentMonth, let day = comps.day else { continue }
                if result[day] == nil || task.priority.rawValue > (result[day]?.priority.rawValue ?? 0) {
                    result[day] = (hasDeadline: true, priority: task.priority)
                }
            }
        }

        for (comps, events) in calendarManager.monthlyEventsByDay {
            guard comps.year == currentYear, comps.month == currentMonth, let day = comps.day else { continue }
            if !events.isEmpty && result[day] == nil {
                result[day] = (hasDeadline: true, priority: .low)
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(currentMonthYear)
                .font(.title2)
                .padding(.bottom, 25)
            WeekdayHeaderView()
            CalendarDaysView(
                weeks: weeks,
                currentYear: currentYear,
                currentMonth: currentMonth,
                taskDays: taskDaysForCurrentMonth,
                selectedDay: $selectedDay
            )

            Group {
                CombinedDayAgendaView(
                    calendarManager: calendarManager,
                    selectedDay: selectedDay,
                    currentYear: currentYear,
                    currentMonth: currentMonth
                )
            }
            .frame(width: 255)
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 30)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        
    }
}

struct CalendarHorizontalPopup: View {
    let calendarManager: CalendarManager
    @ObservedObject private var tickTick = TickTickManager.shared

    init(_ calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    private var taskDaysForCurrentMonth: [Int: (hasDeadline: Bool, priority: TickTickPriority)] {
        let cal = Calendar.current
        var result: [Int: (hasDeadline: Bool, priority: TickTickPriority)] = [:]

        if tickTick.isAuthenticated {
            for task in tickTick.tasksByProject.values.flatMap({ $0 }).filter({ !$0.isCompleted }) {
                guard let due = task.dueDate else { continue }
                let comps = cal.dateComponents([.year, .month, .day], from: due)
                guard comps.year == currentYear, comps.month == currentMonth, let day = comps.day else { continue }
                if result[day] == nil || task.priority.rawValue > (result[day]?.priority.rawValue ?? 0) {
                    result[day] = (hasDeadline: true, priority: task.priority)
                }
            }
        }

        for (comps, events) in calendarManager.monthlyEventsByDay {
            guard comps.year == currentYear, comps.month == currentMonth, let day = comps.day else { continue }
            if !events.isEmpty && result[day] == nil {
                result[day] = (hasDeadline: true, priority: .low)
            }
        }

        return result
    }

    @State private var selectedDay: Int? = Calendar.current.component(.day, from: Date())

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(currentMonthYear)
                    .font(.title2)
                    .padding(.bottom, 25)
                    .fixedSize(horizontal: true, vertical: false)
                WeekdayHeaderView()
                CalendarDaysView(
                    weeks: weeks,
                    currentYear: currentYear,
                    currentMonth: currentMonth,
                    taskDays: taskDaysForCurrentMonth,
                    selectedDay: $selectedDay
                )
            }

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    CombinedDayAgendaView(
                        calendarManager: calendarManager,
                        selectedDay: selectedDay,
                        currentYear: currentYear,
                        currentMonth: currentMonth
                    )
                }
            }
            .frame(width: 255)
            .padding(.leading, 30)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 30)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
    }
}

private var currentMonthYear: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "LLLL yyyy"
    return formatter.string(from: Date()).capitalized
}

private var currentMonth: Int {
    Calendar.current.component(.month, from: Date())
}

private var currentYear: Int {
    Calendar.current.component(.year, from: Date())
}

private var calendarDays: [Int?] {
    let calendar = Calendar.current
    let date = Date()
    guard
        let range = calendar.range(of: .day, in: .month, for: date),
        let firstOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        )
    else {
        return []
    }
    let startOfMonthWeekday = calendar.component(.weekday, from: firstOfMonth)
    let blanks = (startOfMonthWeekday - calendar.firstWeekday + 7) % 7
    var days: [Int?] = Array(repeating: nil, count: blanks)
    days.append(contentsOf: range.map { $0 })
    return days
}

private var weeks: [[Int?]] {
    var days = calendarDays
    let remainder = days.count % 7
    if remainder != 0 {
        days.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
    }
    return stride(from: 0, to: days.count, by: 7).map {
        Array(days[$0..<min($0 + 7, days.count)])
    }
}

private struct WeekdayHeaderView: View {
    var body: some View {
        let calendar = Calendar.current
        let weekdaySymbols = calendar.shortWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1
        let reordered = Array(
            weekdaySymbols[firstWeekdayIndex...]
                + weekdaySymbols[..<firstWeekdayIndex]
        )
        let referenceDate = DateComponents(
            calendar: calendar, year: 2020, month: 12, day: 13
        ).date!
        let referenceDays = (0..<7).map { i in
            calendar.date(byAdding: .day, value: i, to: referenceDate)!
        }

        HStack {
            ForEach(reordered.indices, id: \.self) { i in
                let originalIndex = (i + firstWeekdayIndex) % 7
                let isWeekend = calendar.isDateInWeekend(
                    referenceDays[originalIndex]
                )
                let color = isWeekend ? Color.gray : Color.white

                Text(reordered[i])
                    .frame(width: 30)
                    .foregroundColor(color)
            }
        }
        .padding(.bottom, 10)
    }
}

private struct CalendarDaysView: View {
    let weeks: [[Int?]]
    let currentYear: Int
    let currentMonth: Int
    var taskDays: [Int: (hasDeadline: Bool, priority: TickTickPriority)] = [:]
    @Binding var selectedDay: Int?

    var body: some View {
        let calendar = Calendar.current
        VStack(spacing: 10) {
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 8) {
                    ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                        if let day = weeks[weekIndex][dayIndex] {
                            let date = calendar.date(
                                from: DateComponents(year: currentYear, month: currentMonth, day: day)
                            )!
                            let isWeekend = calendar.isDateInWeekend(date)
                            let todayDay = isToday(day: day)
                            let isSelected = selectedDay == day && !todayDay
                            let taskInfo = taskDays[day]
                            let textColor: Color = todayDay ? .black
                                : isSelected ? .black
                                : (isWeekend ? .gray : .white)

                            ZStack(alignment: .bottom) {
                                // today circle (white)
                                if todayDay {
                                    Circle().fill(Color.white).frame(width: 30, height: 30)
                                }
                                // selected circle (subtle)
                                if isSelected {
                                    Circle().fill(Color.white.opacity(0.25)).frame(width: 30, height: 30)
                                }
                                // task highlight ring
                                if let info = taskInfo, !todayDay, !isSelected {
                                    Circle()
                                        .stroke(taskHighlightColor(info.priority), lineWidth: 1.5)
                                        .frame(width: 28, height: 28)
                                }
                                Text("\(day)")
                                    .foregroundColor(textColor)
                                    .frame(width: 30, height: 30)
                                // dot indicator
                                if let info = taskInfo {
                                    Circle()
                                        .fill((todayDay || isSelected) ? Color.black.opacity(0.4) : taskHighlightColor(info.priority))
                                        .frame(width: 4, height: 4)
                                        .offset(y: -2)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedDay = (selectedDay == day) ? nil : day
                                }
                            }
                            .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
                        } else {
                            Color.clear.frame(width: 30, height: 30)
                        }
                    }
                }
            }
        }.compositingGroup()
    }

    private func taskHighlightColor(_ priority: TickTickPriority) -> Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .none:   return Color(red: 0.3, green: 0.7, blue: 1.0)
        }
    }

    func isToday(day: Int) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        if let dateFromDay = calendar.date(
            from: DateComponents(year: components.year, month: components.month, day: day)
        ) {
            return calendar.isDateInToday(dateFromDay)
        }
        return false
    }
}

private struct EventListView: View {
    let todaysEvents: [EKEvent]
    let tomorrowsEvents: [EKEvent]

    var body: some View {
        if !todaysEvents.isEmpty || !tomorrowsEvents.isEmpty {
            VStack(spacing: 10) {
                eventSection(
                    title: NSLocalizedString("TODAY", comment: "").uppercased(),
                    events: todaysEvents)
                eventSection(
                    title: NSLocalizedString("TOMORROW", comment: "")
                        .uppercased(), events: tomorrowsEvents)
            }
        }
    }

    @ViewBuilder
    func eventSection(title: String, events: [EKEvent]) -> some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                ForEach(events, id: \.eventIdentifier) { event in
                    EventRow(event: event)
                }
            }
        }
    }
}

// MARK: - Combined Day Agenda

private struct CombinedDayAgendaView: View {
    let calendarManager: CalendarManager
    let selectedDay: Int?
    let currentYear: Int
    let currentMonth: Int
    @ObservedObject private var tickTick = TickTickManager.shared
    @State private var filter: AgendaFilter = .all

    private var displayDate: Date {
        if let day = selectedDay,
           let date = Calendar.current.date(from: DateComponents(year: currentYear, month: currentMonth, day: day)) {
            return date
        }
        return Date()
    }

    private var agendaItems: [AgendaItem] {
        let baseEvents = calendarEventsForDisplayDate()
        let events: [AgendaItem] = baseEvents.map { event in
            AgendaItem(
                id: "event-\(event.eventIdentifier ?? UUID().uuidString)",
                sortDate: event.startDate,
                kind: .event(event)
            )
        }
        let tasks: [AgendaItem] = tickTickTasks()
        return (events + tasks).sorted { lhs, rhs in
            let lBucket = sortBucket(for: lhs.sortDate)
            let rBucket = sortBucket(for: rhs.sortDate)
            if lBucket != rBucket { return lBucket < rBucket }
            return lhs.sortDate < rhs.sortDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            filterTabs
            if filteredItems.isEmpty {
                Text(NSLocalizedString("EMPTY_EVENTS", comment: ""))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.callout)
                    .padding(.top, 3)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredItems) { item in
                            AgendaRow(item: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 270)
            }
        }
    }

    private func tickTickTasks() -> [AgendaItem] {
        guard tickTick.isAuthenticated else { return [] }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: displayDate)
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: displayDate) ?? displayDate

        let allTasks = tickTick.tasksByProject.values.flatMap { $0 }.filter { !$0.isCompleted }
        let dueTasks = allTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return cal.isDate(due, inSameDayAs: displayDate)
        }

        var items: [AgendaItem] = []

        if cal.isDateInToday(displayDate) {
            let overdue = allTasks.filter { task in
                guard let due = task.dueDate else { return false }
                return due < startOfDay
            }
            items += overdue.map { task in
                AgendaItem(
                    id: "task-\(task.id)-overdue",
                    sortDate: startOfDay,
                    kind: .task(task, label: NSLocalizedString("OVERDUE", comment: ""))
                )
            }

            let importantNoDue = allTasks.filter { task in
                task.dueDate == nil && (task.priority == .high || task.priority == .medium)
            }
            items += importantNoDue.map { task in
                AgendaItem(
                    id: "task-\(task.id)-important",
                    sortDate: endOfDay.addingTimeInterval(1),
                    kind: .task(task, label: NSLocalizedString("IMPORTANT · NO DUE", comment: ""))
                )
            }
        }

        items += dueTasks.map { task in
            AgendaItem(
                id: "task-\(task.id)-due",
                sortDate: task.dueDate ?? endOfDay,
                kind: .task(task, label: nil)
            )
        }
        return items
    }

    private func sortBucket(for date: Date) -> Int {
        Calendar.current.isDateInToday(date) ? 0 : 1
    }

    private var filteredItems: [AgendaItem] {
        switch filter {
        case .all:
            return agendaItems
        case .calendar:
            return agendaItems.filter { item in
                if case .event = item.kind { return true }
                return false
            }
        case .ticktick:
            return agendaItems.filter { item in
                if case .task = item.kind { return true }
                return false
            }
        }
    }

    private func calendarEventsForDisplayDate() -> [EKEvent] {
        let cal = Calendar.current
        let events = calendarManager.events(for: displayDate)
        if !events.isEmpty { return events }
        if cal.isDateInToday(displayDate) { return calendarManager.todaysEvents }
        if cal.isDateInTomorrow(displayDate) { return calendarManager.tomorrowsEvents }
        return events
    }

    private var filterTabs: some View {
        HStack(spacing: 6) {
            if tickTick.isAuthenticated {
                filterTab(title: localized("All"), isSelected: filter == .all) { filter = .all }
            }
            filterTab(title: localized("Calendar"), isSelected: filter == .calendar) { filter = .calendar }
            if tickTick.isAuthenticated {
                filterTab(title: localized("TickTick Filter"), isSelected: filter == .ticktick) { filter = .ticktick }
            }
            Spacer()
        }
        .padding(.bottom, 2)
    }

    private func filterTab(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.12)) { action() } }) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { h in h ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    private enum AgendaFilter {
        case all
        case calendar
        case ticktick
    }

    fileprivate struct AgendaItem: Identifiable {
        enum Kind {
            case event(EKEvent)
            case task(TickTickTask, label: String?)
        }

        let id: String
        let sortDate: Date
        let kind: Kind
    }
}

private struct AgendaRow: View {
    let item: CombinedDayAgendaView.AgendaItem

    var body: some View {
        switch item.kind {
        case .event(let event):
            CombinedEventRow(event: event)
        case .task(let task, let label):
            CombinedTaskRow(task: task, label: label)
        }
    }
}

private struct CombinedEventRow: View {
    let event: EKEvent

    var body: some View {
        let eventTime = getEventTime(event)
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color(event.calendar.cgColor))
                .frame(width: 3, height: 28)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(eventTime)
                        .font(.caption)
                        .fontWeight(.regular)
                        .lineLimit(1)
                    Text(NSLocalizedString("Calendar", comment: ""))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer()
        }
        .padding(5)
        .padding(.trailing, 5)
        .foregroundStyle(Color(event.calendar.cgColor))
        .background(Color(event.calendar.cgColor).opacity(0.2))
        .cornerRadius(6)
        .frame(maxWidth: .infinity)
    }

    private func getEventTime(_ event: EKEvent) -> String {
        if !event.isAllDay {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("j:mm")
            let start = formatter.string(from: event.startDate).replacingOccurrences(of: ":00", with: "")
            let end = formatter.string(from: event.endDate).replacingOccurrences(of: ":00", with: "")
            return "\(start) — \(end)"
        } else {
            return NSLocalizedString("ALL_DAY", comment: "")
        }
    }
}

private struct CombinedTaskRow: View {
    let task: TickTickTask
    let label: String?

    var body: some View {
        let color = priorityColor(task.priority)
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 3, height: 28)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let lbl = label {
                        Text(lbl)
                            .font(.caption)
                            .fontWeight(.regular)
                            .foregroundStyle(color.opacity(0.8))
                    } else if let due = task.dueDate {
                        Text(taskTime(due))
                            .font(.caption)
                            .fontWeight(.regular)
                            .foregroundStyle(color.opacity(0.7))
                    }
                    Text(NSLocalizedString("TickTick", comment: ""))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            Spacer()
            if task.priority != .none && label == nil {
                Circle().fill(color).frame(width: 5, height: 5)
            }
        }
        .padding(5)
        .padding(.trailing, 5)
        .foregroundStyle(color)
        .background(color.opacity(0.15))
        .cornerRadius(6)
        .frame(maxWidth: .infinity)
    }

    private func priorityColor(_ priority: TickTickPriority) -> Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .none:   return .white.opacity(0.6)
        }
    }

    private func taskTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f.string(from: date)
    }
}

private struct EventRow: View {
    let event: EKEvent

    var body: some View {
        let eventTime = getEventTime(event)
        HStack(spacing: 4) {
            Rectangle()
                .fill(Color(event.calendar.cgColor))
                .frame(width: 3, height: 30)
                .clipShape(Capsule())
            VStack(alignment: .leading) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(eventTime)
                    .font(.caption)
                    .fontWeight(.regular)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(5)
        .padding(.trailing, 5)
        .foregroundStyle(Color(event.calendar.cgColor))
        .background(Color(event.calendar.cgColor).opacity(0.2))
        .cornerRadius(6)
        .frame(maxWidth: .infinity)
    }

    func getEventTime(_ event: EKEvent) -> String {
        var text = ""
        if !event.isAllDay {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("j:mm")
            text += formatter.string(from: event.startDate).replacing(":00", with: "")
            text += " — "
            text += formatter.string(from: event.endDate).replacing(":00", with: "")
        } else {
            return NSLocalizedString("ALL_DAY", comment: "")
        }
        return text
    }
}

// MARK: - TickTick Day Tasks View

/// Displays tasks for the selected day (or today by default).
/// Tasks due today + important tasks without a due date.
struct TickTickDayTasksView: View {
    let selectedDay: Int?
    let currentYear: Int
    let currentMonth: Int
    @ObservedObject private var manager = TickTickManager.shared

    private var selectedDate: Date? {
        guard let day = selectedDay else { return nil }
        return Calendar.current.date(from: DateComponents(year: currentYear, month: currentMonth, day: day))
    }

    private var displayDate: Date { selectedDate ?? Date() }

    private var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(displayDate) { return NSLocalizedString("TODAY", comment: "") }
        if cal.isDateInTomorrow(displayDate) { return NSLocalizedString("TOMORROW", comment: "") }
        if cal.isDateInYesterday(displayDate) { return NSLocalizedString("YESTERDAY", comment: "") }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: displayDate)
    }

    /// Tasks with a deadline on the selected day
    private var deadlineTasks: [TickTickTask] {
        let cal = Calendar.current
        let target = displayDate
        return manager.tasksByProject.values.flatMap { $0 }
            .filter { task in
                guard !task.isCompleted, let due = task.dueDate else { return false }
                return cal.isDate(due, inSameDayAs: target)
            }
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
    }

    /// Overdue tasks (only if today's date is selected)
    private var overdueTasks: [TickTickTask] {
        guard Calendar.current.isDateInToday(displayDate) else { return [] }
        return manager.tasksByProject.values.flatMap { $0 }
            .filter { task in
                guard !task.isCompleted, let due = task.dueDate else { return false }
                return due < Calendar.current.startOfDay(for: Date())
            }
            .sorted { ($0.dueDate ?? Date()) < ($1.dueDate ?? Date()) }
    }

    /// Important tasks without a deadline (high/medium, only if “today” is selected)
    private var importantNoDueTasks: [TickTickTask] {
        guard Calendar.current.isDateInToday(displayDate) else { return [] }
        return manager.tasksByProject.values.flatMap { $0 }
            .filter { !$0.isCompleted && $0.dueDate == nil && ($0.priority == .high || $0.priority == .medium) }
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "checkmark.square.fill")
                    .font(.system(size: 10))
                    .opacity(0.6)
                Text(dayLabel.uppercased())
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                Spacer()
                if manager.totalPendingCount > 0 {
                    Text("\(manager.totalPendingCount) total")
                        .font(.caption)
                        .foregroundStyle(.gray.opacity(0.5))
                }
            }

            // Overdue (today only)
            if !overdueTasks.isEmpty {
                ForEach(overdueTasks.prefix(3)) { task in
                    taskRow(task, overrideColor: .red, label: NSLocalizedString("OVERDUE", comment: ""))
                }
            }

            // Tasks with deadline on this day
            if deadlineTasks.isEmpty && overdueTasks.isEmpty && importantNoDueTasks.isEmpty {
                Text(NSLocalizedString("No tasks for this day", comment: ""))
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                ForEach(deadlineTasks.prefix(5)) { task in
                    taskRow(task, overrideColor: nil, label: nil)
                }
            }

            // Important tasks without deadline (today only)
            if !importantNoDueTasks.isEmpty {
                Text(NSLocalizedString("IMPORTANT · NO DUE DATE", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.5))
                    .padding(.top, 2)
                ForEach(importantNoDueTasks.prefix(3)) { task in
                    taskRow(task, overrideColor: nil, label: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: TickTickTask, overrideColor: Color?, label: String?) -> some View {
        let color = overrideColor ?? priorityColor(task.priority)
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 3, height: 30)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)
                if let lbl = label {
                    Text(lbl)
                        .font(.caption)
                        .fontWeight(.regular)
                        .foregroundStyle(color.opacity(0.8))
                } else if let due = task.dueDate {
                    let f = DateFormatter()
                    let _ = { f.setLocalizedDateFormatFromTemplate("j:mm") }()
                    Text(f.string(from: due))
                        .font(.caption)
                        .fontWeight(.regular)
                        .foregroundStyle(color.opacity(0.7))
                }
            }
            Spacer()
            if task.priority != .none && overrideColor == nil {
                Circle().fill(color).frame(width: 5, height: 5)
            }
        }
        .padding(5).padding(.trailing, 5)
        .foregroundStyle(color)
        .background(color.opacity(0.15))
        .cornerRadius(6)
        .frame(maxWidth: .infinity)
    }

    private func priorityColor(_ priority: TickTickPriority) -> Color {
        switch priority {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return Color(red: 0.3, green: 0.7, blue: 1.0)
        case .none:   return .white.opacity(0.6)
        }
    }
}

struct CalendarPopup_Previews: PreviewProvider {
    var configProvider: ConfigProvider = ConfigProvider(config: ConfigData())
    var calendarManager: CalendarManager

    init() {
        self.calendarManager = CalendarManager(configProvider: configProvider)
    }

    static var previews: some View {
        let configProvider = ConfigProvider(config: ConfigData())
        let calendarManager = CalendarManager(configProvider: configProvider)

        CalendarBoxPopup()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Box")
        CalendarVerticalPopup(calendarManager)
            .background(Color.black)
            .frame(height: 600)
            .previewDisplayName("Vertical")
        CalendarHorizontalPopup(calendarManager)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Horizontal")
    }
}

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
