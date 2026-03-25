import SwiftUI

struct QwenProxyUsagePopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var usageManager = QwenProxyUsageManager.shared

    @State private var selectedVariant: MenuBarPopupVariant = .box

    var body: some View {
        QwenProxyStatsView()
            .environmentObject(configProvider)
            .onAppear {
                usageManager.startUpdating(config: configProvider.config)
            }
    }
}

// MARK: - Stats View

struct QwenProxyStatsView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var usageManager = QwenProxyUsageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if usageManager.usageData.isAvailable {
                titleBar
                Divider().background(Color.white.opacity(0.2))
                accountsSection
                Divider().background(Color.white.opacity(0.2))
                requestsSection
                Divider().background(Color.white.opacity(0.2))
                serverSection
                Divider().background(Color.white.opacity(0.2))
                footerSection
            } else if usageManager.fetchFailed {
                errorView
            } else {
                loadingView
            }
        }
        .frame(width: 300)
        .background(Color.black)
    }

    // MARK: Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image("QwenIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 18, height: 18)
            Text("Qwen Proxy")
                .font(.system(size: 14, weight: .semibold))
            RoutedSettingsLink(section: .qwenProxyUsage) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var statusBadge: some View {
        let healthy = usageManager.usageData.summary.healthy
        let total = usageManager.usageData.summary.total
        let color: Color = healthy == total ? .green : (healthy > 0 ? .orange : .red)
        return Text(String(localized: "\(healthy)/\(total) alive"))
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.5)
                .textCase(.uppercase)

            let s = usageManager.usageData.summary
            HStack(spacing: 0) {
                accountStat(label: String(localized: "Total"),    value: "\(s.total)",        color: .white)
                Spacer()
                accountStat(label: String(localized: "Healthy"),  value: "\(s.healthy)",      color: .green)
                Spacer()
                accountStat(label: String(localized: "Errors"),   value: "\(s.failed)",       color: s.failed > 0 ? .red : .white.opacity(0.4))
                Spacer()
                accountStat(label: String(localized: "Expiring"), value: "\(s.expiringSoon)", color: s.expiringSoon > 0 ? .orange : .white.opacity(0.4))
                Spacer()
                accountStat(label: String(localized: "Expired"),  value: "\(s.expired)",      color: s.expired > 0 ? .red : .white.opacity(0.4))
        }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func accountStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .opacity(0.5)
        }
    }

    // MARK: Requests & Tokens

    private var requestsSection: some View {
        let usage = usageManager.usageData.tokenUsage
        let summary = usageManager.usageData.summary

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.5)
                    .textCase(.uppercase)
                Spacer()
                if !summary.lastReset.isEmpty {
                    Text("since \(summary.lastReset)")
                        .font(.system(size: 10))
                        .opacity(0.3)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Requests").font(.system(size: 10)).opacity(0.5)
                    Text("\(summary.totalRequestsToday)").font(.system(size: 15, weight: .semibold))
                }
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Input").font(.system(size: 10)).opacity(0.5)
                    Text(formatTokens(usage.inputTokensToday)).font(.system(size: 15, weight: .semibold))
                }
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output").font(.system(size: 10)).opacity(0.5)
                    Text(formatTokens(usage.outputTokensToday)).font(.system(size: 15, weight: .semibold))
                }
                Spacer()
            }

            GeometryReader { geometry in
                let inputFrac = usage.totalTokensToday > 0
                    ? CGFloat(usage.inputTokensToday) / CGFloat(usage.totalTokensToday) : 0
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.6))
                        .frame(width: geometry.size.width * inputFrac, height: 5)
                    RoundedRectangle(cornerRadius: 3).fill(Color.purple.opacity(0.6))
                        .frame(width: geometry.size.width * (1 - inputFrac), height: 5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 5)

            HStack {
                Circle().fill(Color.blue.opacity(0.6)).frame(width: 6, height: 6)
                Text("input").font(.system(size: 9)).opacity(0.4)
                Circle().fill(Color.purple.opacity(0.6)).frame(width: 6, height: 6)
                Text("output").font(.system(size: 9)).opacity(0.4)
                Spacer()
                Text("total: \(formatTokens(usage.totalTokensToday))").font(.system(size: 10)).opacity(0.4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Server

    private var serverSection: some View {
        let info = usageManager.usageData.serverInfo
        return VStack(alignment: .leading, spacing: 10) {
            Text("Server")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.5)
                .textCase(.uppercase)

            HStack(spacing: 16) {
                serverInfoRow(icon: "clock",      label: String(localized: "Uptime"), value: formatUptime(info.uptimeSeconds))
                Spacer()
                serverInfoRow(icon: "memorychip", label: String(localized: "RSS"),    value: formatBytes(info.memoryRss))
                Spacer()
                serverInfoRow(icon: "cpu",        label: String(localized: "Heap"),   value: "\(formatBytes(info.memoryHeapUsed)) / \(formatBytes(info.memoryHeapTotal))")
            }

            if !info.nodeVersion.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 9)).opacity(0.4)
                    Text("Node \(info.nodeVersion)  ·  \(info.platform)").font(.system(size: 10)).opacity(0.35)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func serverInfoRow(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9)).opacity(0.45)
                Text(label).font(.system(size: 9)).opacity(0.45)
            }
            Text(value).font(.system(size: 12, weight: .medium))
        }
    }

    // MARK: Footer

    private var footerSection: some View {
        HStack {
            Text("Updated \(timeAgoString(usageManager.usageData.lastUpdated))")
                .font(.system(size: 11))
                .opacity(0.4)
            Spacer()
            Button(action: { usageManager.refresh() }) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12)).opacity(0.6)
            }
            .buttonStyle(.plain)
            .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(0.8)
            Text("Connecting to proxy…").font(.system(size: 11)).opacity(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Image("QwenIcon")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text("Cannot reach Qwen Proxy").font(.system(size: 13, weight: .medium))
            Text(usageManager.errorMessage ?? "Check base-url and token in config.")
                .font(.system(size: 11)).opacity(0.5)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { usageManager.refresh() }) {
                Text("Retry").font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.38, green: 0.58, blue: 0.93))
            .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 30)
    }

    // MARK: Helpers

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    private func formatUptime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0    { return "\(days)d \(hours)h" }
        if hours > 0   { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func timeAgoString(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = .autoupdatingCurrent
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Settings View
//
//struct QwenProxySettingsView: View {
//    @EnvironmentObject var configProvider: ConfigProvider
//
//    // Local state mirrors current config — changes write back to TOML immediately
//    @State private var showRing: Bool = false
//    @State private var showLabel: Bool = true
//    @State private var ringLogic: String = "failed"   // "failed" or "healthy"
//    @State private var ringWarn: Int = 30             // percent
//    @State private var ringCritical: Int = 50         // percent
//
//    private let configKeyPrefix = "widgets.default.qwen-proxy-usage"
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 0) {
//            // Header
//            HStack(spacing: 8) {
//                Image("QwenIcon")
//                    .resizable()
//                    .renderingMode(.template)
//                    .scaledToFit()
//                    .frame(width: 18, height: 18)
//                Text("Widget Settings")
//                    .font(.system(size: 14, weight: .semibold))
//                Spacer()
//            }
//            .padding(.horizontal, 20)
//            .padding(.vertical, 14)
//
//            Divider().background(Color.white.opacity(0.2))
//
//            VStack(alignment: .leading, spacing: 20) {
//
//                // Ring toggle
//                settingsRow(
//                    icon: "circle.inset.filled",
//                    title: "Show ring",
//                    subtitle: "Circle arc around the icon"
//                ) {
//                    Toggle("", isOn: $showRing)
//                        .toggleStyle(.switch)
//                        .scaleEffect(0.8)
//                        .labelsHidden()
//                        .onChange(of: showRing) { _, val in
//                            save(key: "show_ring", value: val ? "true" : "false")
//                        }
//                }
//
//                // Ring logic — only shown when ring is on
//                if showRing {
//                    VStack(alignment: .leading, spacing: 8) {
//                        HStack(spacing: 8) {
//                            Image(systemName: "arrow.triangle.2.circlepath")
//                                .font(.system(size: 13))
//                                .opacity(0.6)
//                                .frame(width: 20)
//                            VStack(alignment: .leading, spacing: 2) {
//                                Text("Ring logic")
//                                    .font(.system(size: 13, weight: .medium))
//                                Text("What the arc size represents")
//                                    .font(.system(size: 11))
//                                    .opacity(0.45)
//                            }
//                        }
//
//                        VStack(spacing: 6) {
//                            ringLogicOption(
//                                value: "failed",
//                                title: "Failed accounts",
//                                subtitle: "Arc grows when accounts die (like Codex)"
//                            )
//                            ringLogicOption(
//                                value: "healthy",
//                                title: "Healthy accounts",
//                                subtitle: "Arc shrinks when accounts die (like Claude)"
//                            )
//                        }
//                        .padding(.leading, 28)
//                    }
//                }
//
//                // Thresholds — only shown when ring is on
//                if showRing {
//                    VStack(alignment: .leading, spacing: 10) {
//                        HStack(spacing: 8) {
//                            Image(systemName: "slider.horizontal.3")
//                                .font(.system(size: 13))
//                                .opacity(0.6)
//                                .frame(width: 20)
//                            Text("Color thresholds")
//                                .font(.system(size: 13, weight: .medium))
//                            Spacer()
//                        }
//
//                        VStack(spacing: 8) {
//                            thresholdRow(
//                                label: "Warn",
//                                color: .orange,
//                                value: $ringWarn,
//                                hint: ringLogic == "failed"
//                                    ? "Orange above \(ringWarn)% failed"
//                                    : "Orange below \(ringWarn)% healthy"
//                            ) { save(key: "ring_warn", value: "\(ringWarn)") }
//
//                            thresholdRow(
//                                label: "Critical",
//                                color: .red,
//                                value: $ringCritical,
//                                hint: ringLogic == "failed"
//                                    ? "Red above \(ringCritical)% failed"
//                                    : "Red below \(ringCritical)% healthy"
//                            ) { save(key: "ring_critical", value: "\(ringCritical)") }
//                        }
//                        .padding(.leading, 28)
//                    }
//                }
//
//                Divider().background(Color.white.opacity(0.1))
//
//                // Label toggle
//                settingsRow(
//                    icon: "number",
//                    title: "Show label",
//                    subtitle: "Number of healthy accounts"
//                ) {
//                    Toggle("", isOn: $showLabel)
//                        .toggleStyle(.switch)
//                        .scaleEffect(0.8)
//                        .labelsHidden()
//                        .onChange(of: showLabel) { _, val in
//                            save(key: "show_label", value: val ? "true" : "false")
//                        }
//                }
//
//            }
//            .padding(.horizontal, 20)
//            .padding(.vertical, 16)
//
//            Divider().background(Color.white.opacity(0.2))
//
//            // Config file note
//            HStack(spacing: 6) {
//                Image(systemName: "doc.text")
//                    .font(.system(size: 10))
//                    .opacity(0.35)
//                Text("Changes are saved to your config file")
//                    .font(.system(size: 10))
//                    .opacity(0.35)
//            }
//            .padding(.horizontal, 20)
//            .padding(.vertical, 10)
//        }
//        .frame(width: 300)
//        .background(Color.black)
//        .onAppear { syncFromConfig() }
//        .onReceive(configProvider.$config) { _ in syncFromConfig() }
//    }
//
//    // MARK: - Subviews
//
//    private func settingsRow<Control: View>(
//        icon: String,
//        title: String,
//        subtitle: String,
//        @ViewBuilder control: () -> Control
//    ) -> some View {
//        HStack(alignment: .center, spacing: 8) {
//            Image(systemName: icon)
//                .font(.system(size: 13))
//                .opacity(0.6)
//                .frame(width: 20)
//            VStack(alignment: .leading, spacing: 2) {
//                Text(title).font(.system(size: 13, weight: .medium))
//                Text(subtitle).font(.system(size: 11)).opacity(0.45)
//            }
//            Spacer()
//            control()
//        }
//    }
//
//    private func ringLogicOption(value: String, title: String, subtitle: String) -> some View {
//        let selected = ringLogic == value
//        return Button(action: {
//            ringLogic = value
//            save(key: "ring_logic", value: value)
//        }) {
//            HStack(spacing: 10) {
//                ZStack {
//                    Circle()
//                        .stroke(Color.white.opacity(selected ? 0.8 : 0.25), lineWidth: 1.5)
//                        .frame(width: 16, height: 16)
//                    if selected {
//                        Circle()
//                            .fill(Color.white.opacity(0.9))
//                            .frame(width: 8, height: 8)
//                    }
//                }
//                VStack(alignment: .leading, spacing: 2) {
//                    Text(title)
//                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
//                        .foregroundColor(.white.opacity(selected ? 1 : 0.6))
//                    Text(subtitle)
//                        .font(.system(size: 10))
//                        .foregroundColor(.white.opacity(0.35))
//                }
//                Spacer()
//            }
//            .padding(.horizontal, 12)
//            .padding(.vertical, 8)
//            .background(selected ? Color.white.opacity(0.08) : Color.clear)
//            .clipShape(RoundedRectangle(cornerRadius: 8))
//            .overlay(
//                RoundedRectangle(cornerRadius: 8)
//                    .stroke(Color.white.opacity(selected ? 0.15 : 0), lineWidth: 1)
//            )
//        }
//        .buttonStyle(.plain)
//        .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
//    }
//
//    private func thresholdRow(
//        label: String,
//        color: Color,
//        value: Binding<Int>,
//        hint: String,
//        onRelease: @escaping () -> Void
//    ) -> some View {
//        VStack(alignment: .leading, spacing: 4) {
//            HStack {
//                Circle()
//                    .fill(color.opacity(0.8))
//                    .frame(width: 8, height: 8)
//                Text(label)
//                    .font(.system(size: 11, weight: .medium))
//                    .foregroundColor(color.opacity(0.9))
//                Spacer()
//                Text("\(value.wrappedValue)%")
//                    .font(.system(size: 11, weight: .semibold))
//                    .monospacedDigit()
//                    .frame(width: 36, alignment: .trailing)
//            }
//            Slider(value: Binding(
//                get: { Double(value.wrappedValue) },
//                set: { value.wrappedValue = Int($0) }
//            ), in: 5...95, step: 5)
//            .accentColor(color)
//            .onAppear { }
//            .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in onRelease() })
//            Text(hint)
//                .font(.system(size: 10))
//                .opacity(0.4)
//        }
//    }
//
//    // MARK: - Config sync
//
//    private func syncFromConfig() {
//        let cfg = configProvider.config
//        showRing     = cfg["show-ring"]?.boolValue     ?? false
//        showLabel    = cfg["show-label"]?.boolValue    ?? !showRing
//        ringLogic    = cfg["ring-logic"]?.stringValue  ?? "failed"
//        ringWarn     = cfg["ring-warning-level"]?.intValue      ?? (ringLogic == "healthy" ? 60 : 30)
//        ringCritical = cfg["ring-critical-level"]?.intValue  ?? (ringLogic == "healthy" ? 30 : 50)
//    }
//
//    private func save(key: String, value: String) {
//        ConfigManager.shared.updateConfigValue(
//            key: "\(configKeyPrefix).\(key)",
//            newValue: value
//        )
//    }
//}
