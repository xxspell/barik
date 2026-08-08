import Foundation
import Combine

final class BarEditModeState: ObservableObject {
    static let shared = BarEditModeState()

    @Published var isActive: Bool = false

    private init() {}
}
