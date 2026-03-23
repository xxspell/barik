import AppKit
import CoreGraphics

struct MonitorDescriptor: Identifiable {
    let id: String
    let name: String
    let frame: CGRect
    let safeAreaInsets: NSEdgeInsets
    let auxiliaryTopLeftArea: CGRect
    let auxiliaryTopRightArea: CGRect

    var hasTopInsetCutout: Bool {
        !auxiliaryTopLeftArea.isEmpty && !auxiliaryTopRightArea.isEmpty
    }

    var notchGapWidth: CGFloat {
        max(0, frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width)
    }
}

extension NSScreen {
    var monitorDescriptor: MonitorDescriptor {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let screenNumber =
            (deviceDescription[screenNumberKey] as? NSNumber)?.stringValue
            ?? "unknown"

        return MonitorDescriptor(
            id: screenNumber,
            name: localizedName,
            frame: frame,
            safeAreaInsets: safeAreaInsets,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRightArea: auxiliaryTopRightArea ?? .zero
        )
    }
}
