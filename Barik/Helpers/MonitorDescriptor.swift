import AppKit
import CoreGraphics

struct MonitorDescriptor: Identifiable {
    let id: String
    let displayUUID: String?
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
        let screenIDNumber = deviceDescription[screenNumberKey] as? NSNumber
        let screenNumber = screenIDNumber?.stringValue ?? "unknown"
        let displayUUID: String?
        if let screenIDNumber,
           let resolvedUUID = CGDisplayCreateUUIDFromDisplayID(
                CGDirectDisplayID(screenIDNumber.uint32Value)
           )?.takeRetainedValue() {
            displayUUID = CFUUIDCreateString(nil, resolvedUUID) as String
        } else {
            displayUUID = nil
        }

        return MonitorDescriptor(
            id: screenNumber,
            displayUUID: displayUUID,
            name: localizedName,
            frame: frame,
            safeAreaInsets: safeAreaInsets,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRightArea: auxiliaryTopRightArea ?? .zero
        )
    }
}
