import SwiftUI

struct GitHubPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = GitHubManager.shared

    @State private var showCopiedNotification = false

    var body: some View {
        VStack(spacing: 0) {
            switch manager.authState {
            case .signedOut:
                signInView
            case .deviceFlowPending(let userCode, let verificationURI):
                deviceFlowView(userCode: userCode, verificationURI: verificationURI)
            case .signedIn(let login):
                statsView(login: login)
            }
        }
        .frame(width: 300)
        .background(Color.black)
    }

    // MARK: - Sign-In Screen

    private var signInView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "mark.github")
                    .barikPopupFont(size: 32)
                    .foregroundStyle(.white)

                Text("GitHub")
                    .barikPopupFont(size: 18, weight: .semibold)

                Text("Connect your GitHub account to see your contribution stats")
                    .barikPopupFont(size: 12)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            if let errorMessage = manager.errorMessage {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)

                        Text(errorMessage)
                            .barikPopupFont(size: 12)
                            .foregroundStyle(.red)
                    }
                }
                .padding(10)
                .background(Color.red.opacity(0.15))
                .cornerRadius(6)
            }

            Button(action: {
                manager.startSignIn()
            }) {
                HStack(spacing: 6) {
                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))

                    Text("Sign in with GitHub")
                        .barikPopupFont(size: 13, weight: .medium)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(Color.green.opacity(0.2))
                .cornerRadius(6)
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(minHeight: 220)
    }

    // MARK: - Device Flow Screen

    private func deviceFlowView(userCode: String, verificationURI: String) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "phone.circle.fill")
                    .barikPopupFont(size: 32)
                    .foregroundStyle(.cyan)

                Text("Verification Code")
                    .barikPopupFont(size: 16, weight: .semibold)

                Text("Visit the link below and enter this code:")
                    .barikPopupFont(size: 12)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            VStack(spacing: 12) {
                HStack {
                    Text("Code:")
                        .barikPopupFont(size: 12)
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer()

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(userCode, forType: .string)
                        showCopiedNotification = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showCopiedNotification = false
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(userCode)
                                .font(.system(.body, design: .monospaced))
                                .barikPopupFont(size: 13, weight: .semibold)
                                .foregroundStyle(.white)

                            Image(systemName: showCopiedNotification ? "checkmark" : "doc.on.doc")
                                .barikPopupFont(size: 11)
                                .foregroundStyle(showCopiedNotification ? .green : .white.opacity(0.5))
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }

                Button(action: {
                    NSWorkspace.shared.open(URL(string: verificationURI)!)
                }) {
                    HStack(spacing: 6) {
                        Text(verificationURI)
                            .barikPopupFont(size: 12)
                            .foregroundStyle(.cyan)

                        Image(systemName: "arrow.up.right.square")
                            .barikPopupFont(size: 11)
                            .foregroundStyle(.cyan)

                        Spacer()
                    }
                    .padding(10)
                    .background(Color.cyan.opacity(0.1))
                    .cornerRadius(4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.horizontal, 14)

            VStack(spacing: 6) {
                Text("Waiting for authorization...")
                    .barikPopupFont(size: 11)
                    .foregroundStyle(.white.opacity(0.6))

                ProgressView()
                    .scaleEffect(0.8, anchor: .center)
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(minHeight: 280)
    }

    // MARK: - Stats View

    private func statsView(login: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(login)
                        .barikPopupFont(size: 14, weight: .semibold)

                    Text("Contribution stats")
                        .barikPopupFont(size: 11)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                if manager.fetchFailed, let errorMessage = manager.errorMessage {
                    Text(errorMessage)
                        .barikPopupFont(size: 10)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(spacing: 16) {
                    contributionHeatmap
                    metricsGrid
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            Divider().background(Color.white.opacity(0.1))

            HStack {
                Text("Updated \(formattedTimeSince(manager.data.lastUpdated))")
                    .barikPopupFont(size: 11)
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()

                Button(action: {
                    manager.refresh()
                }) {
                    if manager.isFetching {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .barikPopupFont(size: 12)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                .disabled(manager.isFetching)
                .onHover { hovering in
                    if hovering && !manager.isFetching {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                RoutedSettingsLink(section: .github) {
                    Image(systemName: "gearshape.fill")
                        .barikPopupFont(size: 12)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                Button(action: {
                    manager.signOut()
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .barikPopupFont(size: 12)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(minHeight: 400)
    }

    // MARK: - Contribution Heatmap

    private var contributionHeatmap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Contribution Heatmap")
                .barikPopupFont(size: 12, weight: .semibold)

            if manager.data.contributionDays.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)

                    Text("Loading contribution data...")
                        .barikPopupFont(size: 11)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                let recentDays = manager.data.contributionDays
                    .sorted { $0.date < $1.date }
                    .suffix(84)
                let weeks = groupContributionsIntoWeeks(Array(recentDays))
                let maxContributions = recentDays.map { $0.count }.max() ?? 1

                HStack {
                    Spacer(minLength: 0)

                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            HStack(spacing: 3) {
                                ForEach(0..<weeks.count, id: \.self) { weekIndex in
                                    let week = weeks[weekIndex]
                                    if dayIndex < week.count {
                                        let day = week[dayIndex]
                                        Rectangle()
                                            .fill(contributionColor(count: day.count, max: maxContributions))
                                            .frame(width: 12, height: 12)
                                            .cornerRadius(3)
                                    } else {
                                        Rectangle()
                                            .fill(Color.clear)
                                            .frame(width: 12, height: 12)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    Spacer()

                    Text("Less")
                        .barikPopupFont(size: 9)
                        .foregroundStyle(.white.opacity(0.5))

                    ForEach([0.0, 0.33, 0.66, 1.0], id: \.self) { intensity in
                        Rectangle()
                            .fill(contributionColor(intensity: intensity))
                            .frame(width: 6, height: 6)
                            .cornerRadius(1)
                    }

                    Text("More")
                        .barikPopupFont(size: 9)
                        .foregroundStyle(.white.opacity(0.5))

                    Spacer()
                }
            }
        }
    }

    private func groupContributionsIntoWeeks(_ days: [GitHubContributionDay]) -> [[GitHubContributionDay]] {
        let sorted = days.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        var calendar = Calendar.current
        calendar.firstWeekday = 1 // Sunday

        var weeks: [[GitHubContributionDay]] = []
        var currentWeek: [GitHubContributionDay] = []

        var lastWeekNumber = calendar.component(.weekOfYear, from: sorted[0].date)
        var lastYear = calendar.component(.yearForWeekOfYear, from: sorted[0].date)

        for day in sorted {
            let weekNumber = calendar.component(.weekOfYear, from: day.date)
            let year = calendar.component(.yearForWeekOfYear, from: day.date)

            if weekNumber != lastWeekNumber || year != lastYear {
                if !currentWeek.isEmpty {
                    weeks.append(currentWeek)
                }
                currentWeek = []
                lastWeekNumber = weekNumber
                lastYear = year
            }

            currentWeek.append(day)
        }

        if !currentWeek.isEmpty {
            weeks.append(currentWeek)
        }

        return weeks
    }

    private func contributionColor(count: Int, max: Int) -> Color {
        let intensity = max > 0 ? Double(count) / Double(max) : 0
        return contributionColor(intensity: intensity)
    }

    private func contributionColor(intensity: Double) -> Color {
        switch intensity {
        case 0:
            return Color.white.opacity(0.08)
        case 0.01...0.33:
            return Color.green.opacity(0.2)
        case 0.33...0.66:
            return Color.green.opacity(0.4)
        case 0.66...1.0:
            return Color.green.opacity(0.7)
        default:
            return Color.white.opacity(0.08)
        }
    }

    private func formattedTimeSince(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case 0..<60:
            return "just now"
        case 60..<3600:
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        case 3600..<86400:
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        default:
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    // MARK: - Streak Risk

    private var streakWarningHour: Int {
        configProvider.config["streak-warning-hour"]?.intValue ?? 18
    }

    private var isPastWarningHour: Bool {
        Calendar.current.component(.hour, from: Date()) >= streakWarningHour
    }

    private var streakColor: Color {
        if manager.data.streakDays == 0 { return .red }
        if manager.data.commitsToday == 0 && isPastWarningHour { return .orange }
        return .green
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        VStack(spacing: 12) {
            Text("Quick Stats")
                .barikPopupFont(size: 12, weight: .semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                metricRow(icon: "flame.fill", label: "Streak", value: "\(manager.data.streakDays) days", color: streakColor)
                metricRow(icon: "checkmark.circle", label: "Today", value: "\(manager.data.commitsToday) commits", color: .green)
                metricRow(icon: "smallcircle.filled.circle", label: "Issues", value: "\(manager.data.openIssues)", color: .yellow)
                metricRow(icon: "arrow.triangle.branch", label: "PRs", value: "\(manager.data.openPRs)", color: .blue)
                metricRow(icon: "bell", label: "Notifications", value: "\(manager.data.unreadNotifications)", color: .cyan)
                metricRow(icon: "star.fill", label: "Stars", value: "\(manager.data.totalStars)", color: .yellow)
            }
        }
    }

    private func metricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .barikPopupFont(size: 12)
                .foregroundStyle(color)
                .frame(width: 16)

            Text(label)
                .barikPopupFont(size: 12)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Text(value)
                .barikPopupFont(size: 12, weight: .medium)
                .foregroundStyle(.white)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(4)
    }
}

