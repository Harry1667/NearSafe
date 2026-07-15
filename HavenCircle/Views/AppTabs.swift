import SwiftUI
import SwiftData

struct AppTabs: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var members: [LocalFamilyMember]

    /// 擁有者名稱作為安否回報的發送者署名
    private var myName: String {
        members.first { $0.relationship == "擁有者" }?.name ?? members.first?.name ?? "我"
    }

    // DEBUG：--start-tab-safety 讓 App 直接開在安否分頁，方便自動化截圖驗證
    @State private var selection: Int = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--start-tab-safety") ? 2 : 0
        #else
        0
        #endif
    }()

    var body: some View {
        TabView(selection: $selection) {
            SafetyMapView()
                .tabItem { Label("安全地圖", systemImage: "map.fill") }
                .tag(0)
            EventListView()
                .tabItem { Label("提醒中心", systemImage: "bell.badge.fill") }
                .tag(1)
            SafetyCheckInView(myName: myName)
                .tabItem { Label("安否", systemImage: "hand.raised.fingers.spread.fill") }
                .tag(2)
            FamilyListView()
                .tabItem { Label("家人", systemImage: "person.2.fill") }
                .tag(3)
            SettingsView()
                .tabItem { Label("設定", systemImage: "slider.horizontal.3") }
                .tag(4)
        }
        .tint(.indigo)
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
