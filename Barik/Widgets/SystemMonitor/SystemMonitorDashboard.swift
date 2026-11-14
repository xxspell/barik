import SwiftUI

/// Dashboard popup: fixed-size card with a category sidebar. Replaces the old
/// single-scroll details popup; Settings is reachable from the sidebar footer,
/// so this view intentionally bypasses MenuBarPopupVariantView.
struct SystemMonitorDashboard: View {
    @ObservedObject private var systemMonitor = SystemMonitorManager.shared

    private let dashboardWidth: CGFloat = 760
    private let dashboardHeight: CGFloat = 520
    private let sidebarWidth: CGFloat = 150

    private let willHideWindow = NotificationCenter.default.publisher(for: .willHideWindow)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: dashboardWidth, height: dashboardHeight)
        .onAppear {
            systemMonitor.setPopupVisible(true)
        }
        .onDisappear {
            systemMonitor.setPopupVisible(false)
        }
        .onReceive(willHideWindow) { _ in
            systemMonitor.setPopupVisible(false)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SystemMonitorCategory.allCases) { category in
                sidebarItem(category)
            }
            Spacer()
            HStack(spacing: 6) {
                RoutedSettingsLink(section: .systemMonitor) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(hoverSettings ? Color.gray.opacity(0.3) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                Text("Settings")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 6)
        }
        .padding(10)
        .frame(width: sidebarWidth, alignment: .leading)
    }

    @State private var hoverSettings = false

    private func sidebarItem(_ category: SystemMonitorCategory) -> some View {
        let isSelected = systemMonitor.selectedCategory == category
        return Button {
            systemMonitor.selectedCategory = category
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.systemImageName)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(category.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var page: some View {
        switch systemMonitor.selectedCategory {
        case .overview:
            SMOverviewPage()
        case .cpu:
            SMCPUPage()
        case .gpu:
            SMGPUPage()
        case .ram:
            SMRAMPage()
        case .disk:
            SMDiskPage()
        case .network:
            SMNetworkPage()
        }
    }
}
