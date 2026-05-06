import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog

struct KeyboardInputSource: Identifiable, Equatable {
    let id: String
    let localizedName: String
    let shortLabel: String
    let languages: [String]
    let isSelected: Bool
}

@MainActor
final class KeyboardLayoutManager: ObservableObject {
    static let shared = KeyboardLayoutManager()

    @Published private(set) var currentSource: KeyboardInputSource?
    @Published private(set) var availableSources: [KeyboardInputSource] = []

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "KeyboardLayoutManager"
    )
    private var sourceChangeObserver: NSObjectProtocol?
    private var pendingRefreshWorkItems: [DispatchWorkItem] = []
    private let notificationRefreshDelays: [DispatchTimeInterval] = [
        .milliseconds(0),
        .milliseconds(45),
        .milliseconds(140),
        .milliseconds(280),
    ]

    private init() {
        logger.debug("KeyboardLayoutManager init")
        refresh()
        observeInputSourceChanges()
    }

    deinit {
        MainActor.assumeIsolated {
            cancelPendingRefreshes()
        }
        if let sourceChangeObserver {
            DistributedNotificationCenter.default().removeObserver(
                sourceChangeObserver)
        }
    }

    func refresh() {
        let currentSource = Self.currentSelectedSource()
        let sources = Self.fetchSelectableSources(selectedID: currentSource?.id)
        let resolvedCurrentSource =
            currentSource
            ?? sources.first(where: { $0.isSelected })
            ?? sources.first

        let sourcesChanged = availableSources != sources
        let currentChanged = self.currentSource != resolvedCurrentSource

        if sourcesChanged {
            availableSources = sources
        }
        if currentChanged {
            self.currentSource = resolvedCurrentSource
        }

        if sourcesChanged || currentChanged {
            logger.debug(
                "refresh() — sources=\(sources.count, privacy: .public) current=\(resolvedCurrentSource?.localizedName ?? "nil", privacy: .public)"
            )
        }
    }

    func selectInputSource(id: String) {
        guard let source = Self.findInputSource(withID: id) else {
            logger.error(
                "selectInputSource() — source not found for id=\(id, privacy: .public)"
            )
            return
        }

        let status = TISSelectInputSource(source)
        guard status == noErr else {
            logger.error(
                "selectInputSource() — failed for id=\(id, privacy: .public), status=\(status, privacy: .public)"
            )
            return
        }

        let selectedModel = Self.inputSourceModel(for: source, isSelected: true)
        if let selectedModel {
            applyOptimisticSelection(selectedModel)
        }

        logger.info("selectInputSource() — switched to id=\(id, privacy: .public)")
        scheduleRefreshAfterNotification()
    }

    private func observeInputSourceChanges() {
        let notificationName = Notification.Name(
            rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String)

        sourceChangeObserver = DistributedNotificationCenter.default()
            .addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.logger.debug("Input source change notification received")
                self?.scheduleRefreshAfterNotification()
            }

        logger.debug(
            "observeInputSourceChanges() — subscribed to \(notificationName.rawValue, privacy: .public)"
        )
    }

    private func scheduleRefreshAfterNotification() {
        cancelPendingRefreshes()

        for delay in notificationRefreshDelays {
            let workItem = DispatchWorkItem { [weak self] in
                self?.logger.debug("Processing keyboard input source refresh")
                self?.refresh()
            }

            pendingRefreshWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay,
                execute: workItem
            )
        }
    }

    private func cancelPendingRefreshes() {
        pendingRefreshWorkItems.forEach { $0.cancel() }
        pendingRefreshWorkItems.removeAll()
    }

    private func applyOptimisticSelection(_ selectedModel: KeyboardInputSource) {
        currentSource = selectedModel
        availableSources = availableSources.map { source in
            KeyboardInputSource(
                id: source.id,
                localizedName: source.localizedName,
                shortLabel: source.shortLabel,
                languages: source.languages,
                isSelected: source.id == selectedModel.id
            )
        }
    }

    private static func fetchSelectableSources(selectedID: String?) -> [KeyboardInputSource] {
        let properties = [
            kTISPropertyInputSourceCategory as String:
                kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String:
                kCFBooleanTrue as Any
        ] as CFDictionary

        let sources = TISCreateInputSourceList(properties, false)
            .takeRetainedValue() as NSArray

        return sources.compactMap { item in
            let inputSource = item as! TISInputSource

            guard let id = stringProperty(
                    for: inputSource, key: kTISPropertyInputSourceID),
                let localizedName = stringProperty(
                    for: inputSource, key: kTISPropertyLocalizedName)
            else {
                return nil
            }

            let languages = stringArrayProperty(
                for: inputSource,
                key: kTISPropertyInputSourceLanguages)

            return KeyboardInputSource(
                id: id,
                localizedName: localizedName,
                shortLabel: shortLabel(
                    localizedName: localizedName,
                    languages: languages),
                languages: languages,
                isSelected: id == selectedID
            )
        }
        .sorted {
            if $0.isSelected != $1.isSelected {
                return $0.isSelected && !$1.isSelected
            }

            return $0.localizedName.localizedCaseInsensitiveCompare(
                $1.localizedName) == .orderedAscending
        }
    }

    private static func findInputSource(withID id: String) -> TISInputSource? {
        let properties = [
            kTISPropertyInputSourceID as String: id
        ] as CFDictionary

        let sources = TISCreateInputSourceList(properties, false)
            .takeRetainedValue() as NSArray

        guard let source = sources.firstObject else { return nil }
        return source as! TISInputSource
    }

    private static func currentSelectedSource() -> KeyboardInputSource? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return inputSourceModel(for: source, isSelected: true)
    }

    private static func shortLabel(
        localizedName: String,
        languages: [String]
    ) -> String {
        let compactName = localizedName.replacingOccurrences(of: " ", with: "")

        if compactName.count <= 4 {
            return compactName.uppercased()
        }

        if let languageCode = languages.first?
            .split(separator: "_")
            .first?
            .prefix(3),
            !languageCode.isEmpty
        {
            return languageCode.uppercased()
        }

        return String(localizedName.prefix(3)).uppercased()
    }

    private static func stringProperty(
        for source: TISInputSource,
        key: CFString
    ) -> String? {
        guard let value = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue()
            as String
    }

    private static func stringArrayProperty(
        for source: TISInputSource,
        key: CFString
    ) -> [String] {
        guard let value = TISGetInputSourceProperty(source, key) else {
            return []
        }

        let array = Unmanaged<CFArray>.fromOpaque(value).takeUnretainedValue()
            as NSArray

        return array.compactMap { $0 as? String }
    }

    private static func inputSourceModel(
        for source: TISInputSource,
        isSelected: Bool
    ) -> KeyboardInputSource? {
        guard let id = stringProperty(for: source, key: kTISPropertyInputSourceID),
            let localizedName = stringProperty(
                for: source,
                key: kTISPropertyLocalizedName)
        else {
            return nil
        }

        let languages = stringArrayProperty(
            for: source,
            key: kTISPropertyInputSourceLanguages)

        return KeyboardInputSource(
            id: id,
            localizedName: localizedName,
            shortLabel: shortLabel(
                localizedName: localizedName,
                languages: languages),
            languages: languages,
            isSelected: isSelected
        )
    }
}
