import AppKit

struct YabaiWindow: WindowModel {
    let id: Int
    let title: String
    let appName: String?
    let isFocused: Bool
    let stackIndex: Int
    var appIcon: NSImage?
    let rawIsHidden: Bool
    let isMinimized: Bool
    let isFloating: Bool
    let isSticky: Bool
    let spaceId: Int

    var isHidden: Bool { rawIsHidden || isMinimized }

    enum CodingKeys: String, CodingKey {
        case id
        case spaceId = "space"
        case title
        case appName = "app"
        case isFocused = "has-focus"
        case stackIndex = "stack-index"
        case rawIsHidden = "is-hidden"
        case isMinimized = "is-minimized"
        case isFloating = "is-floating"
        case isSticky = "is-sticky"
    }

    init(
        id: Int,
        title: String,
        appName: String?,
        isFocused: Bool,
        stackIndex: Int,
        appIcon: NSImage?,
        rawIsHidden: Bool,
        isMinimized: Bool,
        isFloating: Bool,
        isSticky: Bool,
        spaceId: Int
    ) {
        self.id = id
        self.title = title
        self.appName = appName
        self.isFocused = isFocused
        self.stackIndex = stackIndex
        self.appIcon = appIcon
        self.rawIsHidden = rawIsHidden
        self.isMinimized = isMinimized
        self.isFloating = isFloating
        self.isSticky = isSticky
        self.spaceId = spaceId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        spaceId = try container.decode(Int.self, forKey: .spaceId)
        title =
            try container.decodeIfPresent(String.self, forKey: .title)
            ?? "Unnamed"
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        isFocused = try container.decode(Bool.self, forKey: .isFocused)
        stackIndex =
            try container.decodeIfPresent(Int.self, forKey: .stackIndex) ?? 0
        rawIsHidden = try container.decode(Bool.self, forKey: .rawIsHidden)
        isMinimized = try container.decodeIfPresent(Bool.self, forKey: .isMinimized) ?? false
        isFloating = try container.decode(Bool.self, forKey: .isFloating)
        isSticky = try container.decode(Bool.self, forKey: .isSticky)
        if let name = appName {
            appIcon = IconCache.shared.icon(for: name)
        }
    }
}

struct YabaiSpace: SpaceModel {
    typealias WindowType = YabaiWindow
    let id: Int
    var isFocused: Bool
    var windows: [YabaiWindow] = []

    enum CodingKeys: String, CodingKey {
        case id = "index"
        case isFocused = "has-focus"
    }
}
