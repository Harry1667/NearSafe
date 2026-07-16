import SwiftUI
import SwiftData

struct AppTabs: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var members: [LocalFamilyMember]
    @AppStorage(SettingsKeys.profileDisplayName) private var profileDisplayName = ""

    /// 擁有者名稱作為安否回報的發送者署名
    private var myName: String {
        if !profileDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return profileDisplayName
        }
        return members.first { $0.relationship == "擁有者" }?.name ?? members.first?.name ?? "我"
    }

    // DEBUG：--start-tab <n> 讓 App 直接開在指定分頁，方便自動化截圖驗證
    @State private var router = TabRouter(selection: Self.initialTab())

    private static func initialTab() -> Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let flagIndex = args.firstIndex(of: "--start-tab"),
           flagIndex + 1 < args.count,
           let tab = Int(args[flagIndex + 1]) {
            return min(max(tab, 0), 4)
        }
        #endif
        return TabRouter.mapTab  // 打開就是完整地圖
    }

    var body: some View {
        TabView(selection: Bindable(router).selection) {
            EventListView()
                .tabItem { Label("提醒中心", systemImage: "bell.badge.fill") }
                .tag(TabRouter.eventsTab)
            NavigationStack { HistoryView() }
                .tabItem { Label("回顧", systemImage: "clock.arrow.circlepath") }
                .tag(TabRouter.historyTab)
            SafetyMapView()
                .tabItem { Label("安全地圖", systemImage: "map.fill") }
                .tag(TabRouter.mapTab)
            FamilyHubView(myName: myName)
                .tabItem { Label("家人", systemImage: "person.2.fill") }
                .tag(TabRouter.familyTab)
            SettingsView()
                .tabItem { Label("設定", systemImage: "slider.horizontal.3") }
                .tag(TabRouter.settingsTab)
        }
        .tint(.indigo)
        .environment(router)
        // App 每次回到前景重跑資料管線（含每日摘要重算）。
        // 原型限制：沒有背景更新，用前景時機讓資料與摘要盡量新鮮。
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await EventPipeline.refresh(context: context) }
        }
    }
}

#Preview {
    AppTabs()
        .modelContainer(PreviewSupport.container())
        .environment(FamilySyncService())
}
