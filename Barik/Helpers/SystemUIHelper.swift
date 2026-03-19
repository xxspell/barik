import AppKit
import ApplicationServices
import Darwin
import Foundation
import OSLog

final class SystemUIHelper {
    private static let activeRecordingTempDirectoryPaths: [String] = [
        "~/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings",
        "~/Library/ScreenRecordings"
    ].map { NSString(string: $0).expandingTildeInPath }

    private static let screenRecordingCandidateBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.screenshot",
        "com.apple.screencaptureui"
    ]

    private static let screenRecordingCandidateProcessFragments = [
        "controlcenter",
        "systemuiserver",
        "screencaptureui",
        "screenshot"
    ]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "ScreenRecordingHelper"
    )
    private static var lastDetectionSnapshot = ""

    private static let stopKeywords = [
        "stop",
        "stopped",
        "остан",
        "стоп"
    ]

    private static let recordingKeywords = [
        "record",
        "recording",
        "screenrecord",
        "screen record",
        "capture",
        "screen capture",
        "screencapture",
        "запис",
        "экрана",
        "экран"
    ]

    static func openWeatherApp() {
        guard let weatherURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.weather"
        ) else {
            if let fallback = URL(
                string: "x-apple.systempreferences:com.apple.preference.datetime"
            ) {
                NSWorkspace.shared.open(fallback)
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: weatherURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    static func stopActiveScreenRecording() throws {
        logger.info("Stop screen recording requested.")
        let lookupStartedAt = Date()

        guard AXIsProcessTrusted() else {
            requestAccessibilityPermissionIfNeeded()
            logger.error("Stop screen recording aborted because Accessibility permission is missing.")
            throw ScreenRecordingControlError.notTrusted
        }

        guard let stopControlDetails = findStopRecordingControl() else {
            logger.error("Stop screen recording failed because no native stop control was found.")
            throw ScreenRecordingControlError.controlNotFound
        }

        let lookupDuration = Date().timeIntervalSince(lookupStartedAt)
        logger.info("Native stop control lookup finished in \(lookupDuration, privacy: .public)s.")

        logger.info("Attempting to press native stop control owned by \(stopControlDetails.owner, privacy: .public). Details: \(describe(element: stopControlDetails.element), privacy: .public)")

        let actionResult = AXUIElementPerformAction(stopControlDetails.element, kAXPressAction as CFString)
        guard actionResult == .success else {
            logger.error("Pressing native stop control failed with AX error code \(actionResult.rawValue, privacy: .public).")
            throw ScreenRecordingControlError.actionFailed
        }

        logger.info("Native stop control press completed successfully.")
    }

    static func isActiveScreenRecordingDetected() -> Bool {
        let activeRecordingFiles = activeScreencaptureRecordingFiles()
        let fileSignal = !activeRecordingFiles.isEmpty
        let accessibilityTrusted = AXIsProcessTrusted()
        let axSignal = accessibilityTrusted && findStopRecordingControl() != nil
        let isRecording = fileSignal || axSignal

        logDetectionSnapshot(
            isRecording: isRecording,
            fileSignal: fileSignal,
            accessibilityTrusted: accessibilityTrusted,
            axSignal: axSignal,
            activeRecordingFiles: activeRecordingFiles
        )

        if fileSignal {
            return true
        }

        guard accessibilityTrusted else {
            return false
        }

        return axSignal
    }

    static func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else {
            return
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func findStopRecordingControl() -> (element: AXUIElement, owner: String)? {
        let candidates = NSWorkspace.shared.runningApplications
            .filter(isScreenRecordingCandidateApp)

        for app in candidates {
            guard app.processIdentifier > 0 else { continue }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            if let control = findStopRecordingControl(in: appElement) {
                let owner = app.bundleIdentifier ?? app.localizedName ?? "unknown-app"
                return (control, owner)
            }
        }

        return nil
    }

    private static func isScreenRecordingCandidateApp(_ app: NSRunningApplication) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier?.lowercased(),
           screenRecordingCandidateBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        if let localizedName = app.localizedName?.lowercased(),
           screenRecordingCandidateProcessFragments.contains(where: localizedName.contains) {
            return true
        }

        if let executableURL = app.executableURL?.path.lowercased(),
           screenRecordingCandidateProcessFragments.contains(where: executableURL.contains) {
            return true
        }

        return false
    }

    private static func activeScreencaptureRecordingFiles() -> [String] {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        let now = Date()
        let freshnessThreshold: TimeInterval = 60 * 60
        var matches: [String] = []

        for directoryPath in activeRecordingTempDirectoryPaths {
            let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
            guard let fileURLs = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "mov" {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys),
                      resourceValues.isRegularFile == true
                else {
                    continue
                }

                if let modificationDate = resourceValues.contentModificationDate,
                   now.timeIntervalSince(modificationDate) <= freshnessThreshold {
                    matches.append(fileURL.path)
                }
            }
        }

        guard isScreencaptureProcessRunning() else {
            return []
        }

        return matches
    }

    private static func isScreencaptureProcessRunning() -> Bool {
        let maxProcessCount = 4096
        var pids = [pid_t](repeating: 0, count: maxProcessCount)
        let bytesWritten = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        guard bytesWritten > 0 else {
            return false
        }

        let processCount = min(Int(bytesWritten), pids.count)

        for pid in pids.prefix(processCount) where pid > 0 {
            var processName = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let nameLength = proc_name(pid, &processName, UInt32(processName.count))
            guard nameLength > 0 else { continue }

            let name = String(cString: processName).lowercased()
            if name == "screencapture" || name == "screencap" {
                return true
            }
        }

        return false
    }

    private static func logDetectionSnapshot(
        isRecording: Bool,
        fileSignal: Bool,
        accessibilityTrusted: Bool,
        axSignal: Bool,
        activeRecordingFiles: [String]
    ) {
        let snapshot = "recording=\(isRecording) fileSignal=\(fileSignal) axTrusted=\(accessibilityTrusted) axSignal=\(axSignal) files=\(activeRecordingFiles.joined(separator: ","))"
        guard snapshot != lastDetectionSnapshot else { return }
        lastDetectionSnapshot = snapshot

        logger.info("Detection snapshot changed: \(snapshot, privacy: .public)")
    }

    private static func describe(element: AXUIElement) -> String {
        let attributes = [
            "role": attributeValue(kAXRoleAttribute as String, from: element) as? String,
            "subrole": attributeValue(kAXSubroleAttribute as String, from: element) as? String,
            "title": attributeValue(kAXTitleAttribute as String, from: element) as? String,
            "description": attributeValue(kAXDescriptionAttribute as String, from: element) as? String,
            "value": attributeValue(kAXValueAttribute as String, from: element) as? String,
            "identifier": attributeValue(kAXIdentifierAttribute as String, from: element) as? String,
            "help": attributeValue(kAXHelpAttribute as String, from: element) as? String,
            "roleDescription": attributeValue(kAXRoleDescriptionAttribute as String, from: element) as? String,
        ]

        return attributes
            .compactMap { key, value in
                guard let value, !value.isEmpty else { return nil }
                return "\(key)=\(value)"
            }
            .joined(separator: " | ")
    }

    private static func findStopRecordingControl(in rootElement: AXUIElement) -> AXUIElement? {
        var stack = prioritizedSearchRoots(for: rootElement)
        var visitedElementIDs = Set<String>()
        var visitedCount = 0
        let maxVisitedElements = 400

        while let current = stack.popLast(), visitedCount < maxVisitedElements {
            let currentID = elementIdentity(current)
            if let currentID, visitedElementIDs.contains(currentID) {
                continue
            }

            if let currentID {
                visitedElementIDs.insert(currentID)
            }

            visitedCount += 1

            if isStopRecordingControl(current) {
                return current
            }

            stack.append(contentsOf: prioritizedChildElements(of: current).reversed())
        }

        return nil
    }

    private static func prioritizedSearchRoots(for rootElement: AXUIElement) -> [AXUIElement] {
        var roots: [AXUIElement] = [rootElement]

        let prioritizedAttributes = [
            kAXMenuBarAttribute as String,
            kAXWindowsAttribute as String,
            kAXChildrenAttribute as String
        ]

        for attribute in prioritizedAttributes {
            roots.append(contentsOf: elementArrayValue(attribute, from: rootElement))
        }

        return roots
    }

    private static func isStopRecordingControl(_ element: AXUIElement) -> Bool {
        guard isPressableControl(element) else {
            return false
        }

        let searchableText = searchableText(for: element)
        let normalized = searchableText.lowercased()
        let matchesStopKeyword = stopKeywords.contains { normalized.contains($0) }
        let matchesRecordingKeyword = recordingKeywords.contains { normalized.contains($0) }

        return matchesStopKeyword && matchesRecordingKeyword
    }

    private static func isPressableControl(_ element: AXUIElement) -> Bool {
        guard let role = attributeValue(kAXRoleAttribute as String, from: element) as? String else {
            return false
        }

        let pressableRoles = [
            kAXButtonRole as String,
            kAXMenuItemRole as String,
            "AXMenuBarItem"
        ]

        if pressableRoles.contains(role) {
            return true
        }

        guard let actionNames = actionNames(of: element) else {
            return false
        }

        return actionNames.contains(kAXPressAction as String)
    }

    private static func searchableText(for element: AXUIElement) -> String {
        [
            attributeValue(kAXTitleAttribute as String, from: element) as? String,
            attributeValue(kAXDescriptionAttribute as String, from: element) as? String,
            attributeValue(kAXValueAttribute as String, from: element) as? String,
            attributeValue(kAXIdentifierAttribute as String, from: element) as? String,
            attributeValue(kAXHelpAttribute as String, from: element) as? String,
            attributeValue(kAXRoleDescriptionAttribute as String, from: element) as? String,
            attributeValue(kAXSubroleAttribute as String, from: element) as? String,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
    }

    private static func prioritizedChildElements(of element: AXUIElement) -> [AXUIElement] {
        let prioritizedAttributes = [
            kAXChildrenAttribute as String,
            kAXVisibleChildrenAttribute as String,
            kAXContentsAttribute as String,
            kAXMenuBarAttribute as String,
            kAXWindowsAttribute as String,
            kAXExtrasMenuBarAttribute as String,
            kAXExtrasMenuBarAttribute as String
        ]

        var children: [AXUIElement] = []
        for attribute in prioritizedAttributes {
            children.append(contentsOf: elementArrayValue(attribute, from: element))
        }

        return children
    }

    private static func elementArrayValue(_ attribute: String, from element: AXUIElement) -> [AXUIElement] {
        guard let value = attributeValue(attribute, from: element) else {
            return []
        }

        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [unsafeBitCast(value, to: AXUIElement.self)]
        }

        guard CFGetTypeID(value) == CFArrayGetTypeID(),
              let childArray = value as? [AnyObject]
        else {
            return []
        }

        return childArray.compactMap { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else {
                return nil
            }

            return unsafeBitCast(item, to: AXUIElement.self)
        }
    }

    private static func elementIdentity(_ element: AXUIElement) -> String? {
        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &pid)
        guard pidResult == .success else {
            return nil
        }

        let title = (attributeValue(kAXTitleAttribute as String, from: element) as? String) ?? ""
        let description = (attributeValue(kAXDescriptionAttribute as String, from: element) as? String) ?? ""
        let role = (attributeValue(kAXRoleAttribute as String, from: element) as? String) ?? ""
        let identifier = (attributeValue(kAXIdentifierAttribute as String, from: element) as? String) ?? ""
        return "\(pid)|\(role)|\(identifier)|\(title)|\(description)"
    }

    private static func actionNames(of element: AXUIElement) -> [String]? {
        var actionNamesCF: CFArray?
        let result = AXUIElementCopyActionNames(element, &actionNamesCF)
        guard result == .success,
              let actionNames = actionNamesCF as? [String]
        else {
            return nil
        }

        return actionNames
    }

    private static func attributeValue(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }

        return value
    }
}
