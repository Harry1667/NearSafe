import SwiftUI
import SwiftData

struct AppTabs: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var events: [LocalSafetyEvent]
    @Query private var members: [LocalFamilyMember]

    var body: some View {
        TabView {
            SafetyMapView()
                .tabItem { Label("安全地圖", systemImage: "map.fill") }
            EventListView()
                .tabItem { Label("提醒中心", systemImage: "bell.badge.fill") }
            FamilyListView()
                .tabItem { Label("家人", systemImage: "person.2.fill") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "slider.horizontal.3") }
        }
        .tint(.indigo)
        // App 每次回到前景重算每日摘要內容（原型限制：沒有背景更新，用前景時機讓摘要盡量新鮮）
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            let summary = DigestComposer.summary(events: events, members: members)
            Task { await NotificationScheduler.refreshDailyDigest(summary: summary) }
        }
    }
}

#Preview {
    AppTabs()
        .modelContainer(PreviewSupport.container())
}
