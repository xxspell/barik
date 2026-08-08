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

extension MonitorDescriptor {
    /// Converts a point local to this monitor's bar row (SwiftUI coordinate
    /// space: origin top-left, y increasing downward) into AppKit screen
    /// coordinates (origin at the primary screen's bottom-left, y increasing
    /// upward) — needed because each monitor's bar renders in its own
    /// `NSPanel`/SwiftUI view tree, so there is no shared SwiftUI coordinate
    /// space to drag across panel boundaries.
    func screenPoint(fromRowLocal local: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + local.x, y: frame.minY + frame.height - local.y)
    }

    /// The inverse of `screenPoint(fromRowLocal:)`.
    func rowLocalPoint(fromScreen screenPoint: CGPoint) -> CGPoint {
        CGPoint(x: screenPoint.x - frame.minX, y: frame.height - (screenPoint.y - frame.minY))
    }
}
