import AppKit

protocol SpaceModel: Identifiable, Equatable, Codable {
    associatedtype WindowType: WindowModel
    var isFocused: Bool { get set }
    var windows: [WindowType] { get set }
}

protocol WindowModel: Identifiable, Equatable, Codable {
    var id: Int { get }
    var title: String { get }
    var appName: String? { get }
    var pid: Int? { get }
    var isFocused: Bool { get }
    var isHidden: Bool { get }
    var appIcon: NSImage? { get set }
}

protocol SpacesProvider {
    associatedtype SpaceType: SpaceModel
    func getSpacesWithWindows() -> [SpaceType]?
}

protocol SwitchableSpacesProvider: SpacesProvider {
    func focusSpace(spaceId: String, needWindowFocus: Bool)
    func focusWindow(windowId: String)
}

protocol DeletableSpacesProvider: SpacesProvider {
    func deleteSpace(spaceId: String)
    func canDeleteSpace(spaceId: String) -> Bool
}

struct AnyWindow: Identifiable, Equatable {
    let id: Int
    let title: String
    let appName: String?
    let pid: Int?
    let isFocused: Bool
    let isHidden: Bool
    let appIcon: NSImage?

    init<W: WindowModel>(_ window: W) {
        self.id = window.id
        self.title = window.title
        self.appName = window.appName
        self.pid = window.pid
        self.isFocused = window.isFocused
        self.isHidden = window.isHidden
        self.appIcon = window.appIcon
    }

    static func == (lhs: AnyWindow, rhs: AnyWindow) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title
            && lhs.appName == rhs.appName && lhs.pid == rhs.pid
            && lhs.isFocused == rhs.isFocused
            && lhs.isHidden == rhs.isHidden
    }
}

struct AnySpace: Identifiable, Equatable {
    let id: String
    let label: String
    let sortOrder: Int
    let displayFrame: CGRect?
    let isFocused: Bool
    let windows: [AnyWindow]
    let supportsDeletion: Bool

    init<S: SpaceModel>(_ space: S) {
        if let aero = space as? AeroSpace {
            self.id = aero.workspace
            self.label = aero.workspace
            self.sortOrder = Int(aero.workspace) ?? Int.max
            self.displayFrame = nil
            self.supportsDeletion = false
        } else if let yabai = space as? YabaiSpace {
            self.id = String(yabai.id)
            self.label = String(yabai.id)
            self.sortOrder = yabai.id
            self.displayFrame = nil
            self.supportsDeletion = true
        } else if let rift = space as? RiftWorkspace {
            self.id = rift.sourceId
            self.label = String(rift.index + 1)
            self.sortOrder = rift.index
            self.displayFrame = rift.displayFrame
            self.supportsDeletion = false
        } else {
            self.id = "0"
            self.label = "0"
            self.sortOrder = Int.max
            self.displayFrame = nil
            self.supportsDeletion = false
        }
        self.isFocused = space.isFocused
        self.windows = space.windows.map { AnyWindow($0) }
    }

    static func == (lhs: AnySpace, rhs: AnySpace) -> Bool {
        return lhs.id == rhs.id
            && lhs.label == rhs.label
            && lhs.sortOrder == rhs.sortOrder
            && lhs.displayFrame == rhs.displayFrame
            && lhs.isFocused == rhs.isFocused
            && lhs.windows == rhs.windows
    }
}

class AnySpacesProvider {
    private let _getSpacesWithWindows: () -> [AnySpace]?
    private let _focusSpace: ((String, Bool) -> Void)?
    private let _focusWindow: ((String) -> Void)?
    private let _deleteSpace: ((String) -> Void)?
    private let _canDeleteSpace: ((String) -> Bool)?

    init<P: SpacesProvider>(_ provider: P) {
        _getSpacesWithWindows = {
            provider.getSpacesWithWindows()?.map { AnySpace($0) }
        }
        if let switchable = provider as? any SwitchableSpacesProvider {
            _focusSpace = { spaceId, needWindowFocus in
                switchable.focusSpace(
                    spaceId: spaceId, needWindowFocus: needWindowFocus)
            }
            _focusWindow = { windowId in
                switchable.focusWindow(windowId: windowId)
            }
        } else {
            _focusSpace = nil
            _focusWindow = nil
        }

        if let deletable = provider as? any DeletableSpacesProvider {
            _deleteSpace = { spaceId in
                deletable.deleteSpace(spaceId: spaceId)
            }
            _canDeleteSpace = { spaceId in
                deletable.canDeleteSpace(spaceId: spaceId)
            }
        } else {
            _deleteSpace = nil
            _canDeleteSpace = nil
        }
    }

    func getSpacesWithWindows() -> [AnySpace]? {
        _getSpacesWithWindows()
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        _focusSpace?(spaceId, needWindowFocus)
    }

    func focusWindow(windowId: String) {
        _focusWindow?(windowId)
    }

    func deleteSpace(spaceId: String) {
        _deleteSpace?(spaceId)
    }

    func canDeleteSpace(spaceId: String) -> Bool {
        _canDeleteSpace?(spaceId) ?? false
    }
}
