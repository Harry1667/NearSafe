import SwiftUI
import SwiftData

/// 重做後的新手流程：**第一次開 App 只走一步**——乾淨地圖著陸＋點畫面索要定位。
///
/// 選家庭身分刻意不放在這裡：改由 `AppTabs` 在「第二次開 App，或第一次點家人分頁」時才跳出
/// （見 SettingsKeys.roleSelectionPending 的消耗式旗標）。這樣第一次打開最乾淨、阻力最小，
/// 符合「介面越簡單、點擊越少」的方向。
struct WelcomeFlowView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.onboardingCompleted) private var onboardingCompleted = false
    @AppStorage(SettingsKeys.roleSelectionPending) private var roleSelectionPending = false
    @AppStorage(SettingsKeys.firstRunCoachingPending) private var firstRunCoachingPending = false

    var body: some View {
        WelcomeMapView(onContinue: completeLanding)
    }

    /// 著陸步驟完成（定位已處理或使用者略過）：建立本人＋預設 1 公里圈、
    /// 標記新手完成、留下「還沒選身分」與「地圖帶領待播」兩個待辦，交給主畫面接手。
    private func completeLanding() {
        FirstRunSetup.ensureDefaultCircle(context: context)
        roleSelectionPending = true
        firstRunCoachingPending = true
        // 漏斗事件：新手著陸完成（沿用舊精靈的事件名，前後版本漏斗可直接對比）
        Analytics.track("onboarding_completed")
        onboardingCompleted = true   // ContentView 監看此旗標，會自動換成主分頁
    }
}
