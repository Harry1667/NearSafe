import SwiftUI
import SwiftData

/// App 根畫面：新手設定未完成走首次設定精靈，否則進入主分頁。
/// 完成與否看獨立旗標；既有使用者（升級前已建過家人資料）自動視為已完成。
struct ContentView: View {
    @AppStorage(SettingsKeys.onboardingCompleted) private var onboardingCompleted = false
    @Query private var members: [LocalFamilyMember]

    var body: some View {
        if onboardingCompleted || !members.isEmpty {
            AppTabs()
                .task {
                    // 舊版使用者的一次性遷移：補寫旗標
                    if !onboardingCompleted { onboardingCompleted = true }
                }
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewSupport.container())
}
