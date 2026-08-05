import SwiftUI

/// Set to `true` only on the view tree handed to `ImageRenderer` by
/// `WidgetExporter`. Lets widget chrome swap real `Material` (which
/// `ImageRenderer` cannot composite without a live window behind it —
/// it falls back to a flat, opaque, near-white rectangle) for a solid
/// approximation, so exported PNGs look like the live bar instead of a
/// washed-out placeholder.
private struct IsBarikExportingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isBarikExporting: Bool {
        get { self[IsBarikExportingKey.self] }
        set { self[IsBarikExportingKey.self] = newValue }
    }
}
