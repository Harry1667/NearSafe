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
    /// 通知深連結指定的事件：提醒中心出現後直接打開這一則的詳情，
    /// 使用者不必在清單裡自己找剛剛通知講的是哪一件
    var pendingEventKey: String?
    /// B2：QR／havencircle://join 深連結帶進來的邀請碼，交給家人頁消耗（開加入流程並預填）；
    /// 用過就清空，避免重新進到家人頁時被舊值誤觸發。
    var pendingJoinCode: String?

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
