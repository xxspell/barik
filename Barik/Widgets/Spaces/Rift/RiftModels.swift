import AppKit
import CoreGraphics

struct RiftWindowIdentity: Codable, Equatable {
    let pid: Int?
    let idx: Int?
}

struct RiftPoint: Codable, Equatable {
    let x: CGFloat
    let y: CGFloat
}

struct RiftSize: Codable, Equatable {
    let width: CGFloat
    let height: CGFloat
}

struct RiftFrame: Codable, Equatable {
    let origin: RiftPoint
    let size: RiftSize

    var cgRect: CGRect {
        CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
}

struct RiftWindow: WindowModel {
    let id: Int
    let title: String
    let appName: String?
    let pid: Int?
    let isFocused: Bool
    let isHidden: Bool
    var appIcon: NSImage?
    let workspaceId: String?

    private let identity: RiftWindowIdentity?

    enum CodingKeys: String, CodingKey {
        case identity = "id"
        case id = "window_server_id"
        case appName = "app_name"
        case title
        case isFocused = "is_focused"
        case workspaceId = "workspace_id"
    }

    enum ExtraCodingKeys: String, CodingKey {
        case workspace
        case workspaceName = "workspace_name"
        case hidden = "is_hidden"
        case minimized = "is_minimized"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let extraContainer = try decoder.container(keyedBy: ExtraCodingKeys.self)

        identity = try container.decodeIfPresent(RiftWindowIdentity.self, forKey: .identity)

        if let windowServerId = try container.decodeIfPresent(Int.self, forKey: .id) {
            id = windowServerId
        } else if let fallbackIdx = identity?.idx {
            id = fallbackIdx
        } else {
            id = -1
        }

        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Unnamed"
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        pid = identity?.pid
        isFocused = try container.decodeIfPresent(Bool.self, forKey: .isFocused) ?? false

        let isHiddenValue = try extraContainer.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        let isMinimizedValue = try extraContainer.decodeIfPresent(Bool.self, forKey: .minimized) ?? false
        isHidden = isHiddenValue || isMinimizedValue

        let workspaceFromId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
        let workspaceFromLegacy = try extraContainer.decodeIfPresent(String.self, forKey: .workspace)
        let workspaceFromName = try extraContainer.decodeIfPresent(String.self, forKey: .workspaceName)
        workspaceId = workspaceFromId ?? workspaceFromLegacy ?? workspaceFromName

        if let appName {
            appIcon = IconCache.shared.icon(for: appName)
        } else {
            appIcon = nil
        }
    }
}

struct RiftDisplay: Codable, Equatable {
    let screenId: Int
    let name: String
    let frame: RiftFrame
    let activeSpaceId: Int
    let inactiveSpaceIds: [Int]

    var allSpaceIds: [Int] {
        var ids = [activeSpaceId]
        ids.append(contentsOf: inactiveSpaceIds)
        return Array(Set(ids)).sorted()
    }

    enum CodingKeys: String, CodingKey {
        case screenId = "screen_id"
        case name
        case frame
        case activeSpaceId = "space"
        case inactiveSpaceIds = "inactive_space_ids"
    }
}

struct RiftWorkspace: SpaceModel {
    typealias WindowType = RiftWindow

    let sourceId: String
    let index: Int
    let workspace: String
    var id: String { sourceId }
    var isFocused: Bool
    var windows: [RiftWindow]
    var displayFrame: CGRect?

    enum CodingKeys: String, CodingKey {
        case sourceId = "id"
        case index
        case workspace = "name"
        case isFocused = "is_active"
        case windows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceId = try container.decode(String.self, forKey: .sourceId)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
        workspace = try container.decodeIfPresent(String.self, forKey: .workspace) ?? "Workspace"
        isFocused = try container.decodeIfPresent(Bool.self, forKey: .isFocused) ?? false
        windows = try container.decodeIfPresent([RiftWindow].self, forKey: .windows) ?? [RiftWindow]()
        displayFrame = nil
    }
}
