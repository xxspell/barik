import AppKit
import OSLog
import SwiftUI

/// Renders currently-configured widgets to standalone, transparent PNGs
/// using the same views the live bar uses (via `WidgetViewFactory`), for
/// changelog/marketing screenshots. Only reachable from the dev-only
/// "Widget Export" settings section (see `AppRuntimeFlags`).
enum WidgetExporter {
    struct ExportResult {
        let succeeded: [String]
        let skipped: [String]
        let folder: URL
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "WidgetExporter"
    )

    /// Renders every item in `items` to its own PNG inside a fresh
    /// timestamped subfolder of `~/Desktop/Barik Widget Export/`.
    @MainActor
    static func exportAll(items: [TomlWidgetItem]) -> ExportResult {
        let folder = makeOutputFolder()
        var succeeded: [String] = []
        var skipped: [String] = []

        for item in items {
            if export(item: item, to: folder) {
                succeeded.append(item.id)
            } else {
                skipped.append(item.id)
            }
        }

        return ExportResult(succeeded: succeeded, skipped: skipped, folder: folder)
    }

    @MainActor
    private static func export(item: TomlWidgetItem, to folder: URL) -> Bool {
        guard let monitor = NSScreen.main?.monitorDescriptor else {
            logger.error(
                "export() — no NSScreen.main available, skipping \(item.id, privacy: .public)"
            )
            return false
        }

        let view = WidgetViewFactory.build(
            for: item,
            configManager: ConfigManager.shared,
            monitor: monitor,
            screenRecordingManager: ScreenRecordingManager.shared
        )
        .environment(\.isBarikExporting, true)
        .environment(\.colorScheme, Self.resolvedColorScheme())
        .foregroundStyle(Color.foregroundOutside)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3.0
        renderer.isOpaque = false

        guard let cgImage = renderer.cgImage else {
            logger.error(
                "export() — ImageRenderer produced no image for \(item.id, privacy: .public)"
            )
            return false
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            logger.error("export() — PNG encoding failed for \(item.id, privacy: .public)")
            return false
        }

        let fileURL = folder.appendingPathComponent(filename(for: item.id))
        do {
            try pngData.write(to: fileURL)
            return true
        } catch {
            logger.error(
                "export() — write failed for \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private static func makeOutputFolder() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let folder = desktop
            .appendingPathComponent("Barik Widget Export")
            .appendingPathComponent(timestamp)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func filename(for id: String) -> String {
        let stripped = id.hasPrefix("default.") ? String(id.dropFirst("default.".count)) : id
        return "\(stripped).png"
    }

    /// `MenuBarView.body` resolves an unset/"system" theme to `nil` and lets
    /// the hosting window inherit the OS appearance. `ImageRenderer` has no
    /// such window, so `nil` there silently means "light" — resolve
    /// "system" against the actual current appearance instead.
    private static func resolvedColorScheme() -> ColorScheme {
        switch ConfigManager.shared.config.rootToml.theme {
        case "dark":
            return .dark
        case "light":
            return .light
        default:
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? .dark : .light
        }
    }
}
