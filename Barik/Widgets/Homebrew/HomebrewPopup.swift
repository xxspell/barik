import SwiftUI

struct HomebrewPopup: View {
    @ObservedObject var manager: HomebrewManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.3).padding(.horizontal, 12)

            outdatedSection

            Divider().opacity(0.3).padding(.horizontal, 12)

            statsSection

            updateSection
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text("Homebrew")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if manager.isRunningUpdate {
                    Text("homebrew.updating")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                } else if manager.outdatedCount == 0 {
                    Text("homebrew.all_up_to_date")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text(manager.outdatedCount == 1 ? String(localized: "homebrew.one_package_needs_update") : String(format: String(localized: "homebrew.n_packages_need_update"), manager.outdatedCount))
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if manager.isUpdating {
                SpinnerView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Outdated packages

    @ViewBuilder
    private var outdatedSection: some View {
        if manager.outdatedPackages.isEmpty {
            HStack {
                Spacer()
                Label("homebrew.nothing_to_update", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Spacer()
            }
            .padding(.vertical, 10)
        } else {
            let rowHeight: CGFloat = 32
            let maxRows: CGFloat = 15
            let count = CGFloat(manager.outdatedCount)
            ScrollView(count > maxRows ? .vertical : [], showsIndicators: count > maxRows) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(manager.outdatedPackages) { pkg in
                        packageRow(pkg)
                        if pkg.id != manager.outdatedPackages.last?.id {
                            Divider().opacity(0.15).padding(.leading, 14)
                        }
                    }
                }
            }
            .frame(height: min(count, maxRows) * rowHeight)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            // Suppress layout animation on first render
            .transaction { $0.animation = nil }
        }
    }

    private func packageRow(_ pkg: HomebrewPackage) -> some View {
        let needsSudo = manager.sudoRequiredPackages.contains(pkg.name)

        return HStack(spacing: 7) {
            // formula vs cask icon
            Image(systemName: pkg.isCask ? "app.gift" : "cube")
                .font(.system(size: 10))
                .foregroundStyle(needsSudo ? Color.red.opacity(0.8) : Color.orange.opacity(0.7))
                .frame(width: 14)

            Text(pkg.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            if pkg.isCask {
                Text("homebrew.cask")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Spacer()

            // sudo warning badge
            if needsSudo {
                Label("sudo", systemImage: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Text(pkg.versionInfo)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(spacing: 0) {
            statRow(icon: "tray.full",  label: "homebrew.installed",   value: String(format: String(localized: "homebrew.packages_count"), manager.installedCount))
            Divider().opacity(0.15).padding(.leading, 14)
            statRow(icon: "tag",        label: "homebrew.version",     value: manager.brewVersion)
            Divider().opacity(0.15).padding(.leading, 14)
            statRow(icon: "clock",      label: "homebrew.last_update", value: relativeUpdateTime)
        }
        .padding(.vertical, 4)
    }

    private func statRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .frame(height: 28)
    }

    private var relativeUpdateTime: String {
        guard let date = manager.lastUpdateDate else { return "Unknown" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60    { return "\(Int(diff))s ago" }
        if diff < 3600  { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }

    // MARK: - Update section

    @ViewBuilder
    private var updateSection: some View {
        // Sudo warning banner
        if !manager.sudoRequiredPackages.isEmpty && !manager.isRunningUpdate {
            sudoBanner
            Divider().opacity(0.3).padding(.horizontal, 12)
        }

        if manager.isRunningUpdate {
            progressBlock
        } else {
            updateButton
        }
    }

    private var sudoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("homebrew.sudo_required_title")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(manager.sudoRequiredPackages.sorted().joined(separator: ", "))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("homebrew.sudo_required_hint")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // Live progress block
    private var progressBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            SpinnerView().padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(manager.updateProgress.hasPrefix(HomebrewProgressPhase.upgradeCasks)
                     ? String(localized: "homebrew.running_upgrade_cask")
                     : manager.updateProgress.hasPrefix(HomebrewProgressPhase.upgradeFormulae)
                     ? String(localized: "homebrew.running_upgrade_formula")
                     : String(localized: "homebrew.running_update"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                if !manager.updateProgress.isEmpty
                    && !manager.updateProgress.hasPrefix("Upgrading")
                    && !manager.updateProgress.hasPrefix("Updating") {
                    Text(manager.updateProgress)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .animation(.easeInOut(duration: 0.2), value: manager.updateProgress)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(minHeight: 52)
    }

    // Normal button — flush to bottom, corners match popup's cornerRadius
    private var updateButton: some View {
        Button(action: {
            Task { await manager.runUpdate() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("homebrew.update_and_upgrade")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 40,
                    bottomTrailingRadius: 40,
                    topTrailingRadius: 0
                )
                .fill(Color.orange)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable spinner

private struct SpinnerView: View {
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.orange)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}

struct HomebrewPopup_Previews: PreviewProvider {
    static var previews: some View {
        HomebrewPopup(manager: HomebrewManager.shared)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
