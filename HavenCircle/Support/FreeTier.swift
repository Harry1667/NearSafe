import Foundation

/// 免費 vs Guardian+ 額度的單一設定檔。
///
/// 為什麼要集中在這裡：變現分層三方辯論已裁決定案（見 MONETIZATION_PLAN.md）。
/// 這裡是全 App 唯一真相來源，要調整額度只改這裡的數字即可全 App 生效，不必到處翻找散落在
/// 各畫面裡的魔術數字。
///
/// 鐵律：保命警報推播永遠免費，不受這裡任何數字影響——閘門只擋成員數、地點數、歷史回顧天數。
/// 實際的閘門判斷共用邏輯見 [EntitlementStore.canAddPlace] / [EntitlementStore.canAddFamilyMember]。
enum FreeTier {
    /// 免費方案「關心的據點」（老家／學校等）上限。額度值由變現分層決策控制，改這裡即全 App 生效。
    static let maxPlaces = 2

    /// 免費方案家庭成員上限。額度值由變現分層決策控制，改這裡即全 App 生效。
    static let maxFamilyMembers = 6

    /// 免費方案歷史回顧可查天數。額度值由變現分層決策控制，改這裡即全 App 生效。
    static let historyDays = 30

    /// Guardian+ 訂閱後的歷史回顧可查天數。額度值由變現分層決策控制，改這裡即全 App 生效。
    static let plusHistoryDays = 365
}
