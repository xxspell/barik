import SwiftUI
import OSLog

/// Main Bambuddy widget for the menu bar
struct BambuddyWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = BambuddyManager.shared
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "BambuddyWidget"
    )
    
    @State private var widgetFrame: CGRect = .zero
    
    // Configuration from config
    private var showIcon: Bool { configProvider.config["show-icon"]?.boolValue ?? true }
    private var showProgress: Bool { configProvider.config["show-progress"]?.boolValue ?? true }
    private var showPrinterCount: Bool { configProvider.config["show-printer-count"]?.boolValue ?? false }
    private var showTimeRemaining: Bool { configProvider.config["show-time-remaining"]?.boolValue ?? true }
    private var displayMode: BambuddyDisplayMode {
        guard let raw = configProvider.config["display-mode"]?.stringValue,
              let mode = BambuddyDisplayMode(rawValue: raw) else {
            return .auto
        }
        return mode
    }
    
    var body: some View {
        BarikStyle.current.isTUI ? AnyView(tuiBody) : AnyView(defaultBody)
    }
    
    private var defaultBody: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if showIcon {
                statusIcon
            }
            
            if displayMode == .progressOnly || displayMode == .auto {
                if let summary = progressSummary {
                    Text(summary)
                        .barikFont(size: 12, weight: .medium, design: .monospaced)
                        .foregroundStyle(summaryColor)
                        .lineLimit(1)
                }
            }

            if displayMode == .countOnly || (displayMode == .auto && showPrinterCount) {
                Text("\(manager.onlinePrinters.count)")
                    .barikFont(size: 12, weight: .medium, design: .monospaced)
                    .foregroundStyle(countColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .captureScreenRect(into: $widgetFrame)
        .contentShape(Rectangle())
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onTapGesture {
            if manager.printers.isEmpty && !manager.isConfigured {
                // Open settings if not configured
                SettingsRouter.shared.select(.bambuddy)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                MenuBarPopup.show(rect: widgetFrame, id: "bambuddy") {
                    BambuddyPopup()
                        .environmentObject(configProvider)
                }
            }
        }
        .debugPopupTrigger(id: "bambuddy", rect: widgetFrame) { _ in
            MenuBarPopup.show(rect: widgetFrame, id: "bambuddy") {
                BambuddyPopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            configureManager()
            manager.startUpdating()
        }
        .onReceive(ConfigManager.shared.$config) { _ in
            configureManager()
        }
        .onDisappear {
            manager.stopUpdating()
        }
    }
    
    private var tuiBody: some View {
        let style = BarikStyle.current
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            if showIcon {
                Image(systemName: tuiIconName)
                    .foregroundStyle(tuiIconColor(style: style))
            }
            
            if displayMode == .progressOnly || displayMode == .auto {
                if let summary = progressSummary {
                    Text(summary)
                        .foregroundStyle(summaryColor)
                }
            }

            if displayMode == .countOnly || (displayMode == .auto && showPrinterCount) {
                Text("\(manager.onlinePrinters.count)")
                    .foregroundStyle(countColor)
            }
        }
        .barikFont(size: 12, weight: .regular, design: .monospaced)
        .captureScreenRect(into: $widgetFrame)
        .contentShape(Rectangle())
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onTapGesture {
            if manager.printers.isEmpty && !manager.isConfigured {
                SettingsRouter.shared.select(.bambuddy)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                MenuBarPopup.show(rect: widgetFrame, id: "bambuddy") {
                    BambuddyPopup()
                        .environmentObject(configProvider)
                }
            }
        }
        .debugPopupTrigger(id: "bambuddy", rect: widgetFrame) { _ in
            MenuBarPopup.show(rect: widgetFrame, id: "bambuddy") {
                BambuddyPopup()
                    .environmentObject(configProvider)
            }
        }
        .onAppear {
            configureManager()
            manager.startUpdating()
        }
        .onReceive(ConfigManager.shared.$config) { _ in
            configureManager()
        }
        .onDisappear {
            manager.stopUpdating()
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusIcon: some View {
        // One glyph, colored by state — no icon swapping on every refresh cycle.
        // green = printing, orange = preparing/slicing, red = error, primary = idle/offline.
        // Sized/aligned like every other widget chip's icon (e.g. GitHubWidget): 11pt,
        // no forced frame, so it sits on the text's baseline instead of its geometric center.
        Image(systemName: "cube.fill")
            .font(.system(size: 11))
            .foregroundStyle(
                manager.printers.isEmpty && !manager.isConfigured
                    ? Color.secondary
                    : manager.overallStatusColor
            )
    }
    
    private var tuiIconName: String {
        "cube.fill"
    }

    private func tuiIconColor(style: BarikStyle) -> Color {
        if manager.printers.isEmpty && !manager.isConfigured {
            return style.dim
        }
        let color = manager.overallStatusColor
        // `.primary` doesn't read well against the TUI bar's own theming — fall back to its dim color.
        return color == .primary ? style.dim : color
    }
    
    private var progressSummary: String? {
        guard let firstActive = manager.activePrinters.first else { return nil }

        var parts: [String] = []
        if showProgress, let progress = firstActive.progress {
            parts.append("\(progress)%")
        }
        if showTimeRemaining, let remaining = firstActive.remainingTime {
            parts.append(formatCompactTime(remaining))
        }

        guard !parts.isEmpty else {
            // Neither toggle is on — fall back to just the active printer count.
            return "\(manager.activePrinters.count) \(String(localized: "bambuddy.printing"))"
        }
        return parts.joined(separator: " · ")
    }

    /// `remainingTime` is reported by the printer's own firmware in minutes, not seconds.
    private func formatCompactTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h\(mins)m" : "\(mins)m"
    }
    
    private var summaryColor: Color {
        if manager.anyPrinterHasCriticalErrors { return .red }
        if manager.anyPrinterHasErrors { return .orange }
        if !manager.activePrinters.isEmpty { return .green }
        if !manager.onlinePrinters.isEmpty { return .blue }
        return .secondary
    }
    
    private var countColor: Color {
        if manager.onlinePrinters.count == manager.printers.count && !manager.printers.isEmpty {
            return .green
        } else if manager.onlinePrinters.isEmpty {
            return .gray
        } else {
            return .orange
        }
    }
    
    // MARK: - Configuration
    
    private func configureManager() {
        let config = ConfigManager.shared.globalWidgetConfig(for: "default.bambuddy")
        
        let baseURL = config["base-url"]?.stringValue
        let apiKey = config["api-key"]?.stringValue
        let refreshInterval = config["refresh-interval"]?.intValue.map(Double.init)
        
        manager.updateConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            refreshInterval: refreshInterval
        )
    }
}

// MARK: - Display Mode

private enum BambuddyDisplayMode: String, CaseIterable {
    case auto = "auto"
    case progressOnly = "progress"
    case countOnly = "count"
    case iconOnly = "icon"
    
    var title: String {
        switch self {
        case .auto: return String(localized: "bambuddy.display_mode.auto")
        case .progressOnly: return String(localized: "bambuddy.display_mode.progress")
        case .countOnly: return String(localized: "bambuddy.display_mode.count")
        case .iconOnly: return String(localized: "bambuddy.display_mode.icon")
        }
    }
}

struct BambuddyWidget_Previews: PreviewProvider {
    static var previews: some View {
        BambuddyWidget()
            .frame(width: 100, height: 50)
            .background(Color.black)
    }
}