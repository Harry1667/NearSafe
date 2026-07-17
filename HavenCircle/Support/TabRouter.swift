import Foundation
import Observation

/// 跨分頁導航：讓任何畫面能切換主分頁、推入安心頁的二級頁、或打開設定 sheet。
/// 分頁減編（合成案 C2）後只剩三個一級分頁：安心・安全地圖・家人；
/// 提醒中心與回顧變成安心頁 push 的二級頁，設定變成全域 sheet。
@Observable
@MainActor
final class TabRouter {
    nonisolated static let homeTab = 0
    nonisolated static let mapTab = 2      // 保留原 tag 值：widget/通知的 map deep link 不受影響
    nonisolated static let familyTab = 3

    /// 安心頁的二級頁（提醒中心／回顧由此 push）
    enum HomeDestination: Hashable {
        case events
        case history
    }

    var selection: Int
    /// 安心頁的導航堆疊：deep link「alerts」把 .events 推上來
    var homePath: [HomeDestination] = []
    /// 設定改為全域 sheet（掛在 AppTabs 層，任何頁面都能打開）
    var showSettings = false

    init(selection: Int = TabRouter.homeTab) {
        self.selection = selection
    }

    /// 跳到安心頁並推入指定二級頁（deep link 與看守摘要行共用）
    func openHome(_ destination: HomeDestination) {
        selection = Self.homeTab
        if homePath.last != destination {
            homePath.append(destination)
        }
    }
}
