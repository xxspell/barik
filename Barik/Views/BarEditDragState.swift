import Foundation
import Combine
import CoreGraphics
import SwiftUI

final class BarEditDragState: ObservableObject {
    struct Origin: Equatable {
        let monitorID: String
        let index: Int
    }

    static let shared = BarEditDragState()

    @Published var draggedWidgetID: String?
    @Published var origin: Origin?
    @Published var dragScreenLocation: CGPoint = .zero
    @Published var currentInsertion: Origin?

    var isDragging: Bool { draggedWidgetID != nil }

    func reset() {
        draggedWidgetID = nil
        origin = nil
        currentInsertion = nil
    }

    private init() {}
}

struct BarEditRowFrameKey: PreferenceKey {
    struct Entry: Equatable {
        let index: Int
        let midX: CGFloat
    }

    static var defaultValue: [Entry] = []

    static func reduce(value: inout [Entry], nextValue: () -> [Entry]) {
        value.append(contentsOf: nextValue())
    }
}
