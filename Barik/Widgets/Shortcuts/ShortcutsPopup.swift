import SwiftUI

struct ShortcutsPopup: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var manager = ShortcutsManager.shared

    @State private var selectedFolderID = ShortcutFolderSection.allID
    @State private var searchText = ""

    private var visibleSections: [ShortcutFolderSection] {
        if selectedFolderID == ShortcutFolderSection.allID {
            return manager.sections
        }

        return manager.sections.filter { $0.id == selectedFolderID }
    }

    private var filteredSections: [ShortcutFolderSection] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return visibleSections
        }

        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return visibleSections.compactMap { section in
            let shortcuts = section.shortcuts.filter {
                $0.name.lowercased().contains(normalizedQuery)
            }

            guard !shortcuts.isEmpty else { return nil }

            return ShortcutFolderSection(
                id: section.id,
                title: section.title,
                shortcuts: shortcuts,
                isUncategorized: section.isUncategorized
            )
        }
    }

    private var shortcutCount: Int {
        filteredSections.reduce(0) { $0 + $1.shortcuts.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider().background(Color.white.opacity(0.08))

            if manager.isLoading && manager.sections.isEmpty {
                loadingView
            } else if let errorMessage = manager.errorMessage, manager.sections.isEmpty {
                errorView(message: errorMessage)
            } else {
                contentView
            }
        }
        .frame(width: 520, height: 420)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
        .onAppear {
            manager.startUpdating(config: configProvider.config)
            reconcileSelectedFolder()

            Task {
                await manager.refresh()
                reconcileSelectedFolder()
            }
        }
        .onChange(of: manager.sections) { _, _ in
            reconcileSelectedFolder()
        }
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            ZStack {
                if manager.isRunningShortcut {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .rotationEffect(.degrees(manager.isRunningShortcut ? 360 : 0))
                        .animation(
                            .linear(duration: 0.9).repeatForever(autoreverses: false),
                            value: manager.isRunningShortcut
                        )
                } else {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "shortcuts.title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitleText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            searchField

            Button {
                Task {
                    await manager.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .rotationEffect(manager.isLoading ? .degrees(360) : .degrees(0))
                    .animation(
                        manager.isLoading
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: manager.isLoading
                    )
            }
            .buttonStyle(.plain)

            RoutedSettingsLink(section: .shortcuts) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var contentView: some View {
        HStack(spacing: 0) {
            folderSidebar
            Divider().background(Color.white.opacity(0.08))
            shortcutList
        }
    }

    private var folderSidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                folderButton(
                    title: String(localized: "shortcuts.folder.all"),
                    id: ShortcutFolderSection.allID,
                    count: manager.sections.reduce(0) { $0 + $1.shortcuts.count }
                )

                ForEach(manager.sections) { section in
                    folderButton(
                        title: section.title,
                        id: section.id,
                        count: section.shortcuts.count
                    )
                }
            }
            .padding(12)
        }
        .frame(width: 150)
        .background(Color.white.opacity(0.02))
    }

    private func folderButton(title: String, id: String, count: Int) -> some View {
        let isSelected = selectedFolderID == id

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedFolderID = id
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white : Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.14 : 0.06), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var shortcutList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let errorMessage = manager.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange.opacity(0.95))
                        .padding(.horizontal, 18)
                        .padding(.top, 2)
                }

                if filteredSections.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredSections) { section in
                        sectionView(section)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private func sectionView(_ section: ShortcutFolderSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectedFolderID == ShortcutFolderSection.allID {
                HStack(spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                }
            }

            ForEach(section.shortcuts) { shortcut in
                shortcutRow(shortcut, section: section)
            }
        }
    }

    private func shortcutRow(_ shortcut: ShortcutItem, section: ShortcutFolderSection) -> some View {
        let isRunning = manager.isShortcutRunning(shortcut)
        let isAnotherShortcutRunning = manager.isRunningShortcut && !isRunning

        return Button {
            Task {
                await manager.run(shortcut: shortcut)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isRunning ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                        .frame(width: 34, height: 34)

                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .offset(x: 1)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(shortcut.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(isAnotherShortcutRunning ? 0.5 : 1.0))
                        .lineLimit(1)

                    if selectedFolderID == ShortcutFolderSection.allID {
                        Text(section.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                if isRunning {
                    Text(String(localized: "shortcuts.state.running"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.26))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isRunning ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isRunning ? 0.16 : 0.06), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAnotherShortcutRunning)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))

            TextField(String(localized: "shortcuts.search.placeholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 140)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(.white)
            Text(String(localized: "shortcuts.loading"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.orange)

            Text(String(localized: "shortcuts.error.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button(String(localized: "shortcuts.action.try_again")) {
                Task {
                    await manager.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.18))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.24))

            Text(String(localized: "shortcuts.empty.title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text(emptyStateSubtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
    }

    private var subtitleText: String {
        if manager.isRunningShortcut {
            return String(localized: "shortcuts.subtitle.running")
        }

        if let lastRefreshDate = manager.lastRefreshDate {
            return String(
                format: String(localized: "shortcuts.subtitle.updated"),
                locale: Locale.current,
                shortcutCount,
                relativeTimeString(from: lastRefreshDate)
            )
        }

        return String(
            format: String(localized: "shortcuts.subtitle.available"),
            locale: Locale.current,
            shortcutCount
        )
    }

    private var emptyStateSubtitle: String {
        if !searchText.isEmpty {
            return String(localized: "shortcuts.empty.search")
        }

        return String(localized: "shortcuts.empty.filters")
    }

    private func reconcileSelectedFolder() {
        guard selectedFolderID != ShortcutFolderSection.allID else { return }
        guard manager.sections.contains(where: { $0.id == selectedFolderID }) else {
            selectedFolderID = ShortcutFolderSection.allID
            return
        }
    }

    private func relativeTimeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ShortcutsPopup_Previews: PreviewProvider {
    static var previews: some View {
        ShortcutsPopup()
            .environmentObject(ConfigProvider(config: [:]))
            .background(.black)
            .previewLayout(.sizeThatFits)
    }
}
