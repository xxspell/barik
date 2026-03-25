import SwiftUI

struct ClaudeUsagePopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var usageManager = ClaudeUsageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !usageManager.isConnected {
                connectView
            } else if usageManager.usageData.isAvailable {
                titleBar
                Divider().background(Color.white.opacity(0.2))
                rateLimitSection(
                    icon: "clock",
                    title: localized("5-Hour Window"),
                    percentage: usageManager.usageData.fiveHourPercentage,
                    resetDate: usageManager.usageData.fiveHourResetDate,
                    resetPrefix: localized("Resets in %@")
                )
                Divider().background(Color.white.opacity(0.2))
                rateLimitSection(
                    icon: "calendar",
                    title: localized("Weekly"),
                    percentage: usageManager.usageData.weeklyPercentage,
                    resetDate: usageManager.usageData.weeklyResetDate,
                    resetPrefix: localized("Resets %@")
                )
                Divider().background(Color.white.opacity(0.2))
                footerSection
            } else if usageManager.fetchFailed {
                errorView
            } else {
                loadingView
            }
        }
        .frame(width: 280)
        .background(Color.black)
        .onAppear {
            usageManager.reconnectIfNeeded()
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image("ClaudeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text(localized("Claude Usage"))
                .font(.system(size: 14, weight: .semibold))
            RoutedSettingsLink(section: .claudeUsage) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            Spacer()
            Text(usageManager.usageData.plan)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(planBadgeColor.opacity(0.3))
                .foregroundColor(planBadgeColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var planBadgeColor: Color {
        switch usageManager.usageData.plan.lowercased() {
        case "pro":
            .orange
        case "max":
            .purple
        case "team":
            .blue
        case "free":
            .gray
        default:
            .orange
        }
    }

    private func rateLimitSection(
        icon: String,
        title: String,
        percentage: Double,
        resetDate: Date?,
        resetPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .opacity(0.6)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(min(percentage, 1.0) * 100))%")
                    .font(.system(size: 24, weight: .semibold))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressColor(for: percentage))
                        .frame(
                            width: geometry.size.width * min(percentage, 1.0),
                            height: 6
                        )
                        .animation(.easeOut(duration: 0.3), value: percentage)
                }
            }
            .frame(height: 6)

            if let resetDate {
                Text(String(format: resetPrefix, locale: .autoupdatingCurrent, resetTimeString(resetDate)))
                    .font(.system(size: 11))
                    .opacity(0.5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func progressColor(for percentage: Double) -> Color {
        if percentage >= 0.8 { return .red }
        if percentage >= 0.6 { return .orange }
        return .white
    }

    private func resetTimeString(_ date: Date) -> String {
        let interval = date.timeIntervalSince(Date())
        if interval <= 0 { return localized("Soon") }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 24 {
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.timeZone = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("Ejm")
            return formatter.string(from: date)
        } else if hours > 0 {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = minutes > 0 ? [.hour, .minute] : [.hour]
            formatter.maximumUnitCount = 2
            formatter.zeroFormattingBehavior = .dropLeading
            formatter.calendar?.locale = .autoupdatingCurrent
            return formatter.string(from: interval) ?? localized("Soon")
        } else {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = [.minute]
            formatter.maximumUnitCount = 1
            return formatter.string(from: interval) ?? localized("Soon")
        }
    }

    private var footerSection: some View {
        HStack {
            Text(
                String(
                    format: localized("Updated %@"),
                    locale: .autoupdatingCurrent,
                    timeAgoString(usageManager.usageData.lastUpdated)
                )
            )
                .font(.system(size: 11))
                .opacity(0.4)

            Spacer()

            Button(action: {
                usageManager.refresh()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .opacity(0.6)
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

    private func timeAgoString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var connectView: some View {
        VStack(spacing: 14) {
            Image("ClaudeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)

            Text(localized("Claude Usage"))
                .font(.system(size: 14, weight: .semibold))

            Text(localized("View your Claude rate limit usage directly in the menu bar."))
                .font(.system(size: 11))
                .opacity(0.5)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                usageManager.requestAccess()
            }) {
                Text(localized("Allow Access"))
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.89, green: 0.45, blue: 0.29))
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }

            Text(localized("Reads credentials from your Claude Code keychain entry."))
                .font(.system(size: 10))
                .opacity(0.3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 30)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text(localized("Loading usage data..."))
                .font(.system(size: 11))
                .opacity(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .opacity(0.5)

            Text(localized("Unable to load usage data"))
                .font(.system(size: 12, weight: .medium))

            Text(usageManager.errorMessage ?? "The request failed. Your token may have expired.")
                .font(.system(size: 11))
                .opacity(0.5)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                usageManager.refresh()
            }) {
                Text(localized("Retry"))
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.89, green: 0.45, blue: 0.29))
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 30)
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
