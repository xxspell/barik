import Foundation
import OSLog

class RiftSpacesProvider: SpacesProvider, SwitchableSpacesProvider {
    typealias SpaceType = RiftWorkspace

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "RiftSpacesProvider"
    )

    let executablePath = ConfigManager.shared.config.rift.path

    func getSpacesWithWindows() -> [RiftWorkspace]? {
        guard var workspaces = fetchWorkspaces() else {
            return nil
        }

        let windows = fetchWindows() ?? []
        let displays = fetchDisplays() ?? []

        if !windows.isEmpty {
            var windowsByWorkspace = Dictionary(grouping: windows) { window in
                window.workspaceId ?? ""
            }

            for index in workspaces.indices {
                let workspaceId = workspaces[index].sourceId
                let workspaceName = workspaces[index].workspace

                if workspaces[index].windows.isEmpty {
                    let fromId = windowsByWorkspace.removeValue(forKey: workspaceId) ?? []
                    let fromName = windowsByWorkspace.removeValue(forKey: workspaceName) ?? []
                    workspaces[index].windows = mergeWindows(primary: fromId, secondary: fromName)
                }

                workspaces[index].windows.sort { $0.id < $1.id }
            }
        }

        if displays.isEmpty {
            return workspaces
        }

        let workspacesByIndex = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.index, $0) })
        var result: [RiftWorkspace] = []

        for display in displays {
            for spaceId in display.allSpaceIds {
                guard var workspace = workspacesByIndex[spaceId - 1] else {
                    continue
                }
                workspace.displayFrame = display.frame.cgRect
                result.append(workspace)
            }
        }

        if result.isEmpty {
            return workspaces
        }

        return result
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        if let workspaces = fetchWorkspaces(),
           let workspace = workspaces.first(where: { $0.workspace == spaceId }) {
            _ = runRiftCommand(arguments: ["execute", "workspace", "switch", workspace.sourceId])
            return
        }

        _ = runRiftCommand(arguments: ["execute", "workspace", "switch", spaceId])
    }

    func focusWindow(windowId: String) {
        guard let targetWindowId = Int(windowId) else {
            logger.error("Invalid Rift window id=\(windowId, privacy: .public)")
            return
        }

        guard let windows = fetchWindows(), !windows.isEmpty else {
            logger.error("Unable to focus Rift window: no windows snapshot")
            return
        }

        if windows.contains(where: { $0.id == targetWindowId && $0.isFocused }) {
            return
        }

        let maxSteps = windows.count
        for _ in 0..<maxSteps {
            _ = runRiftCommand(arguments: ["execute", "window", "next"])
            if let refreshed = fetchWindows(),
               refreshed.contains(where: { $0.id == targetWindowId && $0.isFocused }) {
                return
            }
        }

        logger.error(
            "Unable to focus Rift window by id via window next traversal. windowId=\(windowId, privacy: .public)"
        )
    }

    private func fetchWorkspaces() -> [RiftWorkspace]? {
        guard let data = runRiftCommand(arguments: ["query", "workspaces"]) else {
            return nil
        }

        do {
            return try JSONDecoder().decode([RiftWorkspace].self, from: data)
        } catch {
            logger.error("Decode Rift workspaces error: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchWindows() -> [RiftWindow]? {
        guard let data = runRiftCommand(arguments: ["query", "windows"]) else {
            return nil
        }

        do {
            return try JSONDecoder().decode([RiftWindow].self, from: data)
        } catch {
            logger.error("Decode Rift windows error: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchDisplays() -> [RiftDisplay]? {
        guard let data = runRiftCommand(arguments: ["query", "displays"]) else {
            return nil
        }

        do {
            return try JSONDecoder().decode([RiftDisplay].self, from: data)
        } catch {
            logger.error("Decode Rift displays error: \(error.localizedDescription)")
            return nil
        }
    }

    private func mergeWindows(primary: [RiftWindow], secondary: [RiftWindow]) -> [RiftWindow] {
        if primary.isEmpty {
            return secondary
        }
        if secondary.isEmpty {
            return primary
        }

        var merged = primary
        let existingIds = Set(primary.map(\.id))
        for window in secondary where !existingIds.contains(window.id) {
            merged.append(window)
        }
        return merged
    }

    @discardableResult
    private func runRiftCommand(arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            logger.error("rift-cli process error: \(error.localizedDescription)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(data: data, encoding: .utf8) ?? ""
            logger.error(
                "rift-cli command failed status=\(process.terminationStatus) args=\(arguments.joined(separator: " "), privacy: .public) output=\(stderr, privacy: .public)"
            )
            return nil
        }

        return data
    }
}
