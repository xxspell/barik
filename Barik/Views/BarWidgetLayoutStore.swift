import Foundation

enum BarWidgetLayoutStore {
    static func currentLayout(for monitor: MonitorDescriptor) -> [String] {
        ConfigManager.shared.displayedWidgets(for: monitor.id).map(\.id)
    }

    static func removeWidget(at index: Int, for monitor: MonitorDescriptor) {
        var layout = currentLayout(for: monitor)
        guard layout.indices.contains(index) else { return }
        layout.remove(at: index)
        persist(layout, for: monitor)
    }

    static func moveWidget(
        withID widgetID: String,
        fromMonitor sourceMonitor: MonitorDescriptor,
        sourceIndex: Int,
        toMonitor destinationMonitor: MonitorDescriptor,
        destinationIndex: Int
    ) {
        if sourceMonitor.id == destinationMonitor.id {
            var layout = currentLayout(for: sourceMonitor)
            guard layout.indices.contains(sourceIndex) else { return }
            let item = layout.remove(at: sourceIndex)
            let boundedDestination = max(0, min(destinationIndex, layout.count))
            layout.insert(item, at: boundedDestination)
            persist(layout, for: sourceMonitor)
            return
        }

        removeWidget(at: sourceIndex, for: sourceMonitor)
        var destinationLayout = currentLayout(for: destinationMonitor)
        let boundedDestination = max(0, min(destinationIndex, destinationLayout.count))
        destinationLayout.insert(widgetID, at: boundedDestination)
        persist(destinationLayout, for: destinationMonitor)
    }

    private static func persist(_ widgetIDs: [String], for monitor: MonitorDescriptor) {
        let normalized = widgetIDs.filter { !$0.isEmpty }
        let globalLayout = ConfigManager.shared.config.rootToml.widgets.displayed.map(\.id)

        guard !normalized.isEmpty else {
            ConfigManager.shared.removeTable("widgets.displays.\"\(monitor.id)\"")
            return
        }

        if normalized == globalLayout {
            ConfigManager.shared.removeTable("widgets.displays.\"\(monitor.id)\"")
            return
        }

        ConfigManager.shared.updateConfigStringArrayValue(
            tablePath: "widgets.displays.\"\(monitor.id)\"",
            key: "displayed",
            newValue: normalized
        )
    }
}
