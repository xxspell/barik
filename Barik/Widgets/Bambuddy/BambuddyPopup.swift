import SwiftUI
import OSLog

/// Detailed popup for Bambuddy widget showing printer status and controls
struct BambuddyPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = BambuddyManager.shared
    @ObservedObject private var configManager = ConfigManager.shared
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "BambuddyPopup"
    )

    @State private var controlsHovered = false
    @State private var refreshAnimation = false

    // Same rhythm as the other Barik popups (Claude/Codex usage): flat sections
    // separated by hairline dividers, 20 pt side padding.
    private let popupWidth: CGFloat = 380
    private let sectionHorizontalPadding: CGFloat = 20
    private let sectionVerticalPadding: CGFloat = 14

    private var showPercentage: Bool { configProvider.config["show-progress"]?.boolValue ?? true }
    private var showTimeRemaining: Bool { configProvider.config["show-time-remaining"]?.boolValue ?? true }
    private var showLayerProgress: Bool { configProvider.config["show-layer-progress"]?.boolValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .background(Color.white.opacity(0.1))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if manager.printers.isEmpty && !manager.isConfigured {
                        notConfiguredView
                            .padding(.horizontal, sectionHorizontalPadding)
                    } else if manager.printers.isEmpty {
                        noPrintersView
                            .padding(.horizontal, sectionHorizontalPadding)
                    } else {
                        printerSections
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.1))

            footer
        }
        .frame(width: popupWidth)
        .background(Color.black)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsHovered = hovering
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "cube.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(manager.overallStatusColor)

            Text(String(localized: "bambuddy.title"))
                .barikPopupFont(size: 14, weight: .semibold)
                .foregroundStyle(.white)

            RoutedSettingsLink(section: .bambuddy) {
                Image(systemName: "gearshape.fill")
                    .barikPopupFont(size: 11, weight: .semibold)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer(minLength: 8)

            // Keep badges in place at all times — swapping them out for a spinner while
            // loading changed the header's width/height and made the whole popup jump on
            // every refresh. The refresh button's own rotation already signals loading.
            HStack(spacing: 6) {
                if !manager.onlinePrinters.isEmpty {
                    statusBadge(
                        count: manager.onlinePrinters.count,
                        label: String(localized: "bambuddy.online"),
                        color: .green
                    )
                }

                if !manager.activePrinters.isEmpty {
                    statusBadge(
                        count: manager.activePrinters.count,
                        label: String(localized: "bambuddy.printing"),
                        color: .blue
                    )
                }

                if manager.anyPrinterHasCriticalErrors {
                    statusBadge(
                        count: manager.printers.filter { $0.hasCriticalErrors }.count,
                        label: String(localized: "bambuddy.errors"),
                        color: .red
                    )
                } else if manager.anyPrinterHasErrors {
                    statusBadge(
                        count: manager.printers.filter { $0.hasErrors }.count,
                        label: String(localized: "bambuddy.warnings"),
                        color: .orange
                    )
                }
            }

            refreshButton
        }
        .padding(.horizontal, sectionHorizontalPadding)
        .padding(.vertical, sectionVerticalPadding)
    }

    private func statusBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text("\(count)")
                .barikPopupFont(size: 10, weight: .bold, design: .rounded)
                .foregroundStyle(.white)

            Text(label)
                .barikPopupFont(size: 10, weight: .medium)
                .foregroundStyle(.white.opacity(0.7))
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Printer Cards

    private var printerSections: some View {
        ForEach(Array(manager.printers.enumerated()), id: \.element.id) { index, printerWithStatus in
            if index > 0 {
                Divider()
                    .background(Color.white.opacity(0.1))
            }
            printerSection(for: printerWithStatus)
        }
    }

    private func printerSection(for printer: BambuddyPrinterWithStatus) -> some View {
        let isOnline = printer.isOnline
        let state = printer.displayState

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isOnline ? state.color.opacity(0.15) : Color.white.opacity(0.05))

                    Image(systemName: "cube.fill").font(.system(size: 14, weight: .medium)).foregroundStyle(isOnline ? state.color : .white.opacity(0.4))
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(printer.printer.name)
                            .barikPopupFont(size: 12, weight: .semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if !isOnline {
                            Text(String(localized: "bambuddy.offline"))
                                .barikPopupFont(size: 9, weight: .bold, design: .rounded)
                                .foregroundStyle(.gray)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(Capsule())
                        } else {
                            stateBadge(for: state)
                        }
                    }

                    HStack(spacing: 10) {
                        let model = printer.printer.model
                        if !model.isEmpty {
                            Label(model, systemImage: "cpu")
                                .barikPopupFont(size: 10, weight: .medium)
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                                .fixedSize()
                        }

                        if let location = printer.printer.location, !location.isEmpty {
                            Label(location, systemImage: "location.fill")
                                .barikPopupFont(size: 10, weight: .medium)
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }

                Spacer(minLength: 8)

                if isOnline, let progress = printer.progress, state.isActive {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if showPercentage {
                                Text("\(progress)%")
                                    .barikPopupFont(size: 18, weight: .bold, design: .rounded)
                                    .foregroundStyle(state.color)
                            }

                            if showTimeRemaining, let remaining = printer.remainingTime {
                                Text(formatTime(remaining))
                                    .barikPopupFont(size: 18, weight: .bold, design: .rounded)
                                    .foregroundStyle(showPercentage ? .white.opacity(0.85) : state.color)
                            }
                        }

                        if showLayerProgress, let layer = printer.status?.layerNum, let total = printer.status?.totalLayers, total > 0 {
                            Text(String(format: String(localized: "bambuddy.layer"), layer, total))
                                .barikPopupFont(size: 10, weight: .medium, design: .monospaced)
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
            }

            if isOnline, let currentPrint = printer.currentPrint, !currentPrint.isEmpty {
                HStack(spacing: 9) {
                    if state.isActive, let coverPath = printer.status?.coverURL {
                        BambuddyCoverImage(
                            path: coverPath,
                            jobKey: printer.status?.gcodeFile ?? printer.currentPrint ?? ""
                        )
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    } else {
                        Image(systemName: "doc.text.fill")
                            .barikPopupFont(size: 10)
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Text(currentPrint)
                        .barikPopupFont(size: 11, weight: .medium)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }
            }

            if isOnline, let temps = printer.temperatures {
                temperatureRow(temps)
            }

            if isOnline, let progress = printer.progress, state.isActive {
                progressBar(progress: Double(progress), color: state.color)
            }

            if !printer.hmsErrors.isEmpty {
                errorsSection(printer.hmsErrors)
            }

            if isOnline, printer.status?.awaitingPlateClear == true {
                plateClearNotice
            }
        }
        .padding(.horizontal, sectionHorizontalPadding)
        .padding(.vertical, sectionVerticalPadding)
    }

    /// The printer is done and waits for the build plate to be cleared. Shown as
    /// status, not a button: Barik has no Bambuddy control API wired up yet.
    private var plateClearNotice: some View {
        Label(String(localized: "bambuddy.plate_needs_clearing"), systemImage: "hand.raised.fill")
            .barikPopupFont(size: 11, weight: .semibold)
            .foregroundStyle(.orange)
    }

    private func stateBadge(for state: BambuddyPrinterState) -> some View {
        Text(state.displayName)
            .barikPopupFont(size: 9, weight: .bold, design: .rounded)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(state.color.opacity(0.2))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(state.color.opacity(0.5), lineWidth: 0.5)
            )
    }

    private func temperatureRow(_ temps: BambuddyTemperatures) -> some View {
        HStack(spacing: 14) {
            if let nozzle = temps.nozzle {
                tempItem(
                    label: String(localized: "bambuddy.nozzle"),
                    value: "\(Int(nozzle.rounded()))°",
                    target: heatingTarget(temps.nozzleTarget),
                    color: .orange
                )
            }

            if let bed = temps.bed {
                tempItem(
                    label: String(localized: "bambuddy.bed"),
                    value: "\(Int(bed.rounded()))°",
                    target: heatingTarget(temps.bedTarget),
                    color: .blue
                )
            }

            if let chamber = temps.chamber {
                tempItem(
                    label: String(localized: "bambuddy.chamber"),
                    value: "\(Int(chamber.rounded()))°",
                    target: nil,
                    color: .red
                )
            }

            Spacer(minLength: 0)
        }
    }

    private func tempItem(label: String, value: String, target: String?, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text(label)
                .barikPopupFont(size: 10, weight: .medium)
                .foregroundStyle(.white.opacity(0.45))

            Text(value)
                .barikPopupFont(size: 11, weight: .semibold, design: .monospaced)
                .foregroundStyle(.white)

            if let target = target {
                Text(verbatim: "→ \(target)")
                    .barikPopupFont(size: 10, weight: .medium, design: .monospaced)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// Target temperature only while heating; an idle printer reports 0.
    private func heatingTarget(_ target: Double?) -> String? {
        guard let target, target > 0 else { return nil }
        return "\(Int(target.rounded()))°"
    }

    private func progressBar(progress: Double, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress / 100)
                    .animation(.easeInOut(duration: 0.5), value: progress)
            }
        }
        .frame(height: 5)
    }

    private func errorsSection(_ errors: [BambuddyHMSError]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .barikPopupFont(size: 10, weight: .bold)
                    .foregroundStyle(.orange)

                Text(String(localized: "bambuddy.hms_errors"))
                    .barikPopupFont(size: 10, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer(minLength: 0)
            }

            ForEach(errors.prefix(3)) { error in
                HStack(spacing: 8) {
                    Circle()
                        .fill(severityColor(error.severity))
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        if let description = error.description, !description.isEmpty {
                            Text(description)
                                .barikPopupFont(size: 10, weight: .medium)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        } else {
                            Text(error.fullCode ?? error.code)
                                .barikPopupFont(size: 10, weight: .medium, design: .monospaced)
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        if let code = error.fullCode ?? error.code as String? {
                            Text(code)
                                .barikPopupFont(size: 9, design: .monospaced)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            if errors.count > 3 {
                Text(String(format: String(localized: "bambuddy.and_more_errors"), errors.count - 3))
                    .barikPopupFont(size: 10, weight: .medium)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.leading, 14)
            }
        }
    }

    private func severityColor(_ severity: Int?) -> Color {
        switch severity {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .gray
        }
    }

    // MARK: - Empty States

    private var notConfiguredView: some View {
        VStack(spacing: 14) {
            Image(systemName: "cube.fill").font(.system(size: 32)).foregroundStyle(.white.opacity(0.3))

            VStack(spacing: 6) {
                Text(String(localized: "bambuddy.not_configured_title"))
                    .barikPopupFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)

                Text(String(localized: "bambuddy.not_configured_description"))
                    .barikPopupFont(size: 11)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RoutedSettingsLink(section: .bambuddy) {
                Label(String(localized: "bambuddy.open_settings"), systemImage: "gearshape.fill")
                    .barikPopupFont(size: 11, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.bambuddyAccent.opacity(0.2))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.bambuddyAccent.opacity(0.5), lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var noPrintersView: some View {
        VStack(spacing: 14) {
            Image(systemName: "printer.slash")
                .barikPopupFont(size: 32)
                .foregroundStyle(.white.opacity(0.4))

            VStack(spacing: 6) {
                Text(String(localized: "bambuddy.no_printers_title"))
                    .barikPopupFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)

                Text(String(localized: "bambuddy.no_printers_description"))
                    .barikPopupFont(size: 11)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let lastError = manager.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .barikPopupFont(size: 10)
                        .foregroundStyle(.red)

                    Text(lastError)
                        .barikPopupFont(size: 10, weight: .medium)
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.1))
                .clipShape(Capsule())
            } else {
                Text(String(localized: "bambuddy.title"))
                    .barikPopupFont(size: 10, weight: .medium)
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer(minLength: 0)

            if let lastRefresh = manager.lastRefresh {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(updatedText(lastRefresh, now: context.date))
                        .barikPopupFont(size: 10)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, sectionHorizontalPadding)
        .padding(.vertical, 10)
    }

    // MARK: - Refresh Button

    private var refreshButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                refreshAnimation = true
            }
            Task {
                await manager.refresh()
                try? await Task.sleep(for: .milliseconds(500))
                refreshAnimation = false
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .barikPopupFont(size: 11, weight: .semibold)
                .foregroundStyle(.white.opacity(controlsHovered || manager.isLoading ? 0.8 : 0.4))
                .rotationEffect(.degrees(refreshAnimation || manager.isLoading ? 360 : 0))
                .animation(
                    manager.isLoading
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .spring(response: 0.4, dampingFraction: 0.6),
                    value: refreshAnimation
                )
        }
        .buttonStyle(.plain)
        .disabled(manager.isLoading)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help(String(localized: "bambuddy.refresh_tooltip"))
    }

    // MARK: - Helpers

    /// "Updated just now" under a minute, then "Updated 3 min. ago".
    private func updatedText(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 {
            return String(localized: "bambuddy.updated_just_now")
        }
        let relative = date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return String(format: String(localized: "bambuddy.updated_ago"), relative)
    }

    /// `remainingTime` is reported by the printer's own firmware in **minutes**, not seconds.
    private func formatTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, mins)
        } else {
            return String(format: "%dm", mins)
        }
    }
}

struct BambuddyPopup_Previews: PreviewProvider {
    static var previews: some View {
        BambuddyPopup()
            .background(Color.black)
    }
}
