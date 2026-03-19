import SwiftUI

struct CLIProxyUsagePopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var usageManager = CLIProxyUsageManager.shared

    @AppStorage(cliProxyUsageSelectedProviderKey)
    private var selectedProviderRawValue = CLIProxyProviderFilter.all.rawValue

    @AppStorage(cliProxyUsageSelectedRangeKey)
    private var selectedRangeRawValue = CLIProxyTimeRange.hours24.rawValue

    @State private var baseURLInput = ""
    @State private var apiKeyInput = ""
    @State private var hasSavedConfiguration = false
    @State private var isSavingConfiguration = false
    @State private var isRefreshQuotaHovered = false

    private var selectedProvider: CLIProxyProviderFilter {
        CLIProxyProviderFilter(rawValue: selectedProviderRawValue) ?? .all
    }

    private var selectedRange: CLIProxyTimeRange {
        CLIProxyTimeRange(rawValue: selectedRangeRawValue) ?? .hours24
    }

    private var quotaSummary: CLIProxyQuotaSummary {
        usageManager.usageData.quotaSummary(for: selectedProvider)
    }

    private var tokenSummary: CLIProxyTokenSummary {
        usageManager.usageData.tokenSummary(for: selectedProvider, range: selectedRange)
    }

    private var topAPIKeys: [CLIProxyAPIKeyUsageSummary] {
        usageManager.usageData.topAPIKeys
    }

    private var canSaveConfiguration: Bool {
        !baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowWelcome: Bool {
        let hasConfigFromPopup = hasSavedConfiguration && usageManager.hasConfiguration()
        return !usageManager.hasConfiguration(in: configProvider.config) && !hasConfigFromPopup
    }

    private var quotaIsSupportedForSelection: Bool {
        selectedProvider == .all || quotaSummary.supported
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if shouldShowWelcome {
                welcomeView
            } else if usageManager.usageData.isAvailable {
                titleBar
                Divider().background(Color.white.opacity(0.2))
                providerSection
                Divider().background(Color.white.opacity(0.2))
                quotaSection
                Divider().background(Color.white.opacity(0.2))
                tokenSection
                Divider().background(Color.white.opacity(0.2))
                topKeysSection
                Divider().background(Color.white.opacity(0.2))
                footerSection
            } else if usageManager.fetchFailed {
                errorView
            } else {
                loadingView
            }
        }
        .frame(width: 330)
        .background(Color.black)
        .onAppear {
            baseURLInput = currentStringValue(for: ["base-url", "base_url"])
            apiKeyInput = currentStringValue(for: ["api-key", "api_key"])
            hasSavedConfiguration = usageManager.hasConfiguration(in: configProvider.config)
            usageManager.startUpdating(config: configProvider.config)
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 16, weight: .semibold))
            Text(localized("CLIProxy"))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(
                String(
                    format: localized("%@ %lld%%"),
                    locale: .autoupdatingCurrent,
                    selectedProvider.title,
                    Int64((quotaSummary.percentage * 100).rounded())
                )
            )
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusBadgeColor.opacity(0.2))
                .foregroundColor(statusBadgeColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var statusBadgeColor: Color {
        let ratio = quotaSummary.percentage
        if ratio < 0.6 { return .red }
        if ratio < 0.85 { return .orange }
        return .green
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Provider")

            horizontalChipRow(items: CLIProxyProviderFilter.allCases, selectedID: selectedProvider.id) { provider in
                selectedProviderRawValue = provider.rawValue
            } label: { provider in
                provider.title
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Quota")

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int((quotaSummary.percentage * 100).rounded()))%")
                        .font(.system(size: 30, weight: .semibold))
                    Text(quotaStatusText)
                        .font(.system(size: 11))
                        .opacity(0.45)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(statusBadgeColor)
                            .frame(width: geometry.size.width * quotaSummary.percentage, height: 8)
                    }
                }
                .frame(height: 8)
            }

            HStack(spacing: 10) {
                quotaPill(title: "Auto-switch project", enabled: usageManager.usageData.quotaSettings.switchProject)
                quotaPill(title: "Auto-switch preview model", enabled: usageManager.usageData.quotaSettings.switchPreviewModel)
            }

            HStack(spacing: 8) {
                Button(action: { usageManager.refreshQuota() }) {
                    HStack(spacing: 7) {
                        if usageManager.quotaRefreshInProgress {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.72)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .bold))
                        }

                        Text(usageManager.quotaRefreshInProgress ? localized("Refreshing Codex quota…") : localized("Refresh"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(refreshQuotaForegroundColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(refreshQuotaBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(refreshQuotaBorderColor, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(usageManager.quotaRefreshInProgress)
                .opacity(usageManager.quotaRefreshInProgress ? 0.9 : 1)
                .onHover { hovering in
                    isRefreshQuotaHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }

                Text(usageManager.quotaRefreshInProgress ? localized("Checking Codex quota…") : localized("Checks Codex quota and refreshes cache"))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))

                Spacer(minLength: 0)
            }

            if !quotaIsSupportedForSelection {
                Text(
                    String(
                        format: localized("Quota is not available for %@ yet. Token usage still works for this provider."),
                        locale: .autoupdatingCurrent,
                        selectedProvider.title
                    )
                )
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if selectedProvider == .all {
                HStack(spacing: 0) {
                    ForEach(Array(usageManager.usageData.groupedQuotaProviders().enumerated()), id: \.element.filter.id) { index, item in
                        VStack(spacing: 3) {
                            Text("\(Int((item.summary.percentage * 100).rounded()))%")
                                .font(.system(size: 14, weight: .semibold))
                            Text(item.filter.title)
                                .font(.system(size: 10))
                                .opacity(0.5)
                        }

                        if index < usageManager.usageData.groupedQuotaProviders().count - 1 {
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var quotaStatusText: String {
        if quotaSummary.supported {
            return String(
                format: localized("%lld ready of %lld"),
                locale: .autoupdatingCurrent,
                Int64(quotaSummary.ready),
                Int64(quotaSummary.total)
            )
        }

        return localized("Quota unavailable")
    }

    private var refreshQuotaBackground: some ShapeStyle {
        if usageManager.quotaRefreshInProgress {
            return Color.orange.opacity(0.18)
        }
        if isRefreshQuotaHovered {
            return Color.orange.opacity(0.24)
        }
        return Color.orange.opacity(0.14)
    }

    private var refreshQuotaBorderColor: Color {
        if usageManager.quotaRefreshInProgress {
            return Color.orange.opacity(0.6)
        }
        if isRefreshQuotaHovered {
            return Color.orange.opacity(0.7)
        }
        return Color.orange.opacity(0.42)
    }

    private var refreshQuotaForegroundColor: Color {
        usageManager.quotaRefreshInProgress ? .orange : Color(red: 1.0, green: 0.78, blue: 0.32)
    }

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Tokens")
                Spacer()
                horizontalChipRow(items: CLIProxyTimeRange.allCases, selectedID: selectedRange.id) { range in
                    selectedRangeRawValue = range.rawValue
                } label: { range in
                    range.title
                }
            }

            HStack(spacing: 0) {
                tokenStat(title: "Requests", value: "\(tokenSummary.requests)", color: .white)
                Spacer()
                tokenStat(title: "Failed", value: "\(tokenSummary.failures)", color: tokenSummary.failures > 0 ? .orange : .white.opacity(0.4))
                Spacer()
                tokenStat(title: "Input", value: abbreviatedNumber(tokenSummary.inputTokens), color: .blue)
                Spacer()
                tokenStat(title: "Output", value: abbreviatedNumber(tokenSummary.outputTokens), color: .purple)
            }

            GeometryReader { geometry in
                let total = max(tokenSummary.totalTokens, 1)
                let inputFraction = CGFloat(tokenSummary.inputTokens) / CGFloat(total)

                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.opacity(0.7))
                        .frame(width: geometry.size.width * inputFraction, height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.purple.opacity(0.7))
                        .frame(width: geometry.size.width * (1 - inputFraction), height: 6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 6)

            HStack {
                Circle().fill(Color.blue.opacity(0.7)).frame(width: 6, height: 6)
                Text(localized("input"))
                    .font(.system(size: 9))
                    .opacity(0.4)
                Circle().fill(Color.purple.opacity(0.7)).frame(width: 6, height: 6)
                Text(localized("output"))
                    .font(.system(size: 9))
                    .opacity(0.4)
                Spacer()
                Text(
                    String(
                        format: localized("total %@"),
                        locale: .autoupdatingCurrent,
                        abbreviatedNumber(tokenSummary.totalTokens)
                    )
                )
                    .font(.system(size: 10))
                    .opacity(0.4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footerSection: some View {
        HStack {
            if usageManager.fetchFailed {
                Text(localized("Using cached data"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
            } else {
                Text(
                    String(
                        format: localized("Updated %@"),
                        locale: .autoupdatingCurrent,
                        timeAgoString(usageManager.usageData.lastUpdated)
                    )
                )
                    .font(.system(size: 11))
                    .opacity(0.4)
            }

            Spacer()

            Button(action: { usageManager.refresh() }) {
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

    private var topKeysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Top Keys")
                Spacer()
                Text("\(min(topAPIKeys.count, 10))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }

            if topAPIKeys.isEmpty {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            } else {
                let maxTokens = max(topAPIKeys.first?.totalTokens ?? 1, 1)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(topAPIKeys.enumerated()), id: \.element.id) { index, item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.35))
                                    .frame(width: 16, alignment: .leading)

                                Text(item.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.92))
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Text(abbreviatedNumber(item.totalTokens))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.88))
                            }

                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange.opacity(0.22))
                                    .frame(maxWidth: .infinity)
                                    .overlay(alignment: .leading) {
                                        GeometryReader { geometry in
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.orange.opacity(0.8))
                                                .frame(
                                                    width: max(
                                                        6,
                                                        geometry.size.width * CGFloat(item.totalTokens) / CGFloat(maxTokens)
                                                    ),
                                                    height: 5
                                                )
                                        }
                                    }
                                    .frame(height: 5)

                                Text("\(item.requests)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(0.8)
            Text(localized("Loading CLIProxy stats…"))
                .font(.system(size: 11))
                .opacity(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var errorView: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.system(size: 28, weight: .semibold))

            Text(localized("Cannot reach CLIProxy"))
                .font(.system(size: 13, weight: .medium))

            Text(usageManager.errorMessage ?? localized("Check base-url and management key in config."))
                .font(.system(size: 11))
                .opacity(0.5)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: { usageManager.refresh() }) {
                Text(localized("Retry"))
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.38, green: 0.58, blue: 0.93))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 30)
    }

    private var welcomeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 16, weight: .semibold))
                Text(localized("CLIProxy"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider().background(Color.white.opacity(0.2))

            VStack(alignment: .leading, spacing: 12) {
                Text(localized("Connect the widget to the CLIProxy Management API to see quota and token statistics."))
                    .font(.system(size: 11))
                    .opacity(0.6)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("Base URL"))
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.5)
                    TextField("http://localhost:8317", text: $baseURLInput)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("Management key"))
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.5)
                    SecureField(localized("Enter key"), text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                }

                Text(localized("You can paste either the server root URL or the full `/v0/management` path."))
                    .font(.system(size: 10))
                    .opacity(0.35)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: saveConfiguration) {
                    HStack(spacing: 8) {
                        if isSavingConfiguration {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSavingConfiguration ? localized("Connecting…") : localized("Save & Connect"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.38, green: 0.58, blue: 0.93))
                .disabled(!canSaveConfiguration || isSavingConfiguration)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func saveConfiguration() {
        let trimmedBaseURL = baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedBaseURL.isEmpty, !trimmedAPIKey.isEmpty else {
            return
        }

        isSavingConfiguration = true

        ConfigManager.shared.updateConfigValue(
            key: "widgets.default.cliproxy-usage.base-url",
            newValue: trimmedBaseURL
        )
        ConfigManager.shared.updateConfigValue(
            key: "widgets.default.cliproxy-usage.api-key",
            newValue: trimmedAPIKey
        )

        hasSavedConfiguration = true
        let updatedConfig: ConfigData = [
            "base-url": .string(trimmedBaseURL),
            "api-key": .string(trimmedAPIKey)
        ]
        usageManager.startUpdating(config: updatedConfig)
        usageManager.refresh()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            isSavingConfiguration = false
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(localized(title))
            .font(.system(size: 11, weight: .semibold))
            .opacity(0.5)
            .textCase(.uppercase)
    }

    private func tokenStat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(color)
            Text(localized(title))
                .font(.system(size: 10))
                .opacity(0.5)
        }
    }

    private func quotaPill(title: String, enabled: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(enabled ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(localized(title))
                .font(.system(size: 11, weight: .medium))
                .opacity(enabled ? 0.95 : 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func horizontalChipRow<Item: Identifiable>(
        items: [Item],
        selectedID: String,
        onSelect: @escaping (Item) -> Void,
        label: @escaping (Item) -> String
    ) -> some View where Item.ID == String {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let isSelected = item.id == selectedID
                    Button(action: { onSelect(item) }) {
                        Text(label(item))
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
                            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func currentStringValue(for keys: [String]) -> String {
        for key in keys {
            if let value = configProvider.config[key]?.stringValue {
                return value
            }
        }
        return ""
    }

    private func abbreviatedNumber(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func timeAgoString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
