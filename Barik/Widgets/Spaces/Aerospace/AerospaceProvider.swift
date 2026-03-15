import Foundation
import OSLog

class AerospaceSpacesProvider: SpacesProvider, SwitchableSpacesProvider {
    typealias SpaceType = AeroSpace
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "barik",
        category: "AerospaceSpacesProvider"
    )
    let executablePath = ConfigManager.shared.config.aerospace.path

    func getSpacesWithWindows() -> [AeroSpace]? {
        guard var spaces = fetchSpaces(), let windows = fetchWindows() else {
            return nil
        }
        if let focusedSpace = fetchFocusedSpace() {
            for i in 0..<spaces.count {
                spaces[i].isFocused = (spaces[i].id == focusedSpace.id)
            }
        }
        let focusedWindow = fetchFocusedWindow()
        var spaceDict = Dictionary(
            uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        for window in windows {
            var mutableWindow = window
            if let focused = focusedWindow, window.id == focused.id {
                mutableWindow.isFocused = true
            }
            if let ws = mutableWindow.workspace, !ws.isEmpty {
                if var space = spaceDict[ws] {
                    space.windows.append(mutableWindow)
                    spaceDict[ws] = space
                }
            } else if let focusedSpace = fetchFocusedSpace() {
                if var space = spaceDict[focusedSpace.id] {
                    space.windows.append(mutableWindow)
                    spaceDict[focusedSpace.id] = space
                }
            }
        }
        var resultSpaces = Array(spaceDict.values)
        for i in 0..<resultSpaces.count {
            resultSpaces[i].windows.sort { $0.id < $1.id }
        }
        return resultSpaces.filter { !$0.windows.isEmpty }
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        _ = runAerospaceCommand(arguments: ["workspace", spaceId])
    }

    func focusWindow(windowId: String) {
        _ = runAerospaceCommand(arguments: ["focus", "--window-id", windowId])
    }

    private func runAerospaceCommand(arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            logger.error("Aerospace error: \(error.localizedDescription)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    private func fetchSpaces() -> [AeroSpace]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-workspaces", "--all", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroSpace].self, from: data)
        } catch {
            logger.error("Decode spaces error: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchWindows() -> [AeroWindow]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--all", "--json", "--format",
                "%{window-id} %{app-name} %{window-title} %{workspace}",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroWindow].self, from: data)
        } catch {
            logger.error("Decode windows error: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchFocusedSpace() -> AeroSpace? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-workspaces", "--focused", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroSpace].self, from: data).first
        } catch {
            logger.error("Decode focused space error: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchFocusedWindow() -> AeroWindow? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--focused", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroWindow].self, from: data).first
        } catch {
            logger.error("Decode focused window error: \(error.localizedDescription)")
            return nil
        }
    }
}
