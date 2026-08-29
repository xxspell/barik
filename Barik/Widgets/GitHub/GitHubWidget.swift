import SwiftUI

struct GitHubWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = GitHubManager.shared

    @State private var widgetFrame: CGRect = .zero

    private var metrics: [String] {
        configProvider.config["metrics"]?.stringArrayValue ?? ["streak", "issues", "prs", "notifications"]
    }

    private var streakWarningHour: Int {
        configProvider.config["streak-warning-hour"]?.intValue ?? 18
    }

    private var isPastWarningHour: Bool {
        Calendar.current.component(.hour, from: Date()) >= streakWarningHour
    }

    private var streakColor: Color {
        let style = BarikStyle.current
        if style.isTUI { return style.foreground }
        if manager.data.streakDays == 0 { return .red }
        if manager.data.commitsToday == 0 && isPastWarningHour { return .orange }
        return .foregroundOutside
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(metrics, id: \.self) { metric in
                metricView(for: metric)
            }
        }
        .barikTextStyle(.headline)
        .foregroundStyle(BarikStyle.current.isTUI ? BarikStyle.current.foreground : .foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: BarikStyle.current.isTUI ? 0 : 3)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .captureScreenRect(into: $widgetFrame)
        .onTapGesture {
            MenuBarPopup.show(rect: widgetFrame, id: "github") {
                GitHubPopup().environmentObject(configProvider)
            }
        }
        .onAppear {
            manager.startUpdating(config: configProvider.config)
        }
        .onChange(of: configProvider.config["refresh-interval"]?.intValue) { _, _ in
            manager.startUpdating(config: configProvider.config)
        }
    }

    @ViewBuilder
    private func metricView(for metric: String) -> some View {
        switch metric {
        case "streak":
            HStack(spacing: 2) {
                Image(systemName: "flame.fill").foregroundStyle(streakColor)
                Text("\(manager.data.streakDays)").barikFont(size: 12, weight: .medium)
            }
        case "issues":
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.circle")
                Text("\(manager.data.openIssues)").barikFont(size: 12, weight: .medium)
            }
        case "prs":
            HStack(spacing: 2) {
                Image(systemName: "arrow.triangle.pull")
                Text("\(manager.data.openPRs)").barikFont(size: 12, weight: .medium)
            }
        case "notifications":
            HStack(spacing: 2) {
                Image(systemName: manager.data.unreadNotifications > 0 ? "bell.badge.fill" : "bell")
                Text("\(manager.data.unreadNotifications)").barikFont(size: 12, weight: .medium)
            }
        case "stars":
            HStack(spacing: 2) {
                Image(systemName: "star.fill")
                Text("\(manager.data.totalStars)").barikFont(size: 12, weight: .medium)
            }
        case "commits-today":
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle")
                Text("\(manager.data.commitsToday)").barikFont(size: 12, weight: .medium)
            }
        default:
            EmptyView()
        }
    }
}
