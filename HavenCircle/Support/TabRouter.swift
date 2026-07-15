import Foundation
import Observation

/// 跨分頁導航：讓任何畫面能切換主分頁（例如家人頁的「邀請家人」跳到安否分頁）
@Observable
@MainActor
final class TabRouter {
    /// 分頁順序：地圖置中，開 App 直接看到完整地圖
    static let eventsTab = 0
    static let historyTab = 1
    static let mapTab = 2
    static let familyTab = 3
    static let settingsTab = 4

    var selection: Int

    init(selection: Int = TabRouter.mapTab) {
        self.selection = selection
    }
}
