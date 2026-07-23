import SwiftUI
import SwiftData

/// App 根畫面：新手設定未完成走首次設定精靈，否則進入主分頁。
/// 完成與否看獨立旗標；既有使用者（升級前已建過家人資料）自動視為已完成。
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKeys.onboardingCompleted) private var onboardingCompleted = false
    @Query private var members: [LocalFamilyMember]

    var body: some View {
        content
        #if DEBUG
            // 驗證用：--demo-firstrun 直接進入「剛完成第一次著陸」的狀態（建預設圈＋落在地圖帶領），
            // 讓自動化截圖能繞過無法用指令點地圖完成第一次的限制。
            .task {
                guard ProcessInfo.processInfo.arguments.contains("--demo-firstrun") else { return }
                FirstRunSetup.ensureDefaultCircle(context: modelContext)
                UserDefaults.standard.set(true, forKey: SettingsKeys.firstRunCoachingPending)
                UserDefaults.standard.set(true, forKey: SettingsKeys.roleSelectionPending)
                onboardingCompleted = true
            }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--force-onboarding") {
            WelcomeFlowView()
        } else if onboardingCompleted || !members.isEmpty {
            appTabsWithLegacyMigration
        } else {
            WelcomeFlowView()
        }
        #else
        if onboardingCompleted || !members.isEmpty {
            appTabsWithLegacyMigration
        } else {
            WelcomeFlowView()
        }
        #endif
    }

    private var appTabsWithLegacyMigration: some View {
        AppTabs()
            .task {
                // 舊版使用者的一次性遷移：補寫旗標
                if !onboardingCompleted { onboardingCompleted = true }
            }
    }
}

#if DEBUG
#Preview {
    ContentView()
        .modelContainer(PreviewSupport.container())
}
#endif
