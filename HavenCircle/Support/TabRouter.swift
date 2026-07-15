import Foundation
import Observation

/// 跨分頁導航：讓任何畫面能切換主分頁（例如家人頁的「邀請家人」跳到安否分頁）
@Observable
@MainActor
final class TabRouter {
    static let mapTab = 0
    static let eventsTab = 1
    static let safetyTab = 2
    static let familyTab = 3
    static let settingsTab = 4

    var selection: Int

    init(selection: Int = 0) {
        self.selection = selection
    }
}
