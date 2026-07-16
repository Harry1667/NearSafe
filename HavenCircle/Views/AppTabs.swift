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
    // 功能導覽：黑幕聚光燈逐步介紹安心頁（nil＝未進行）
    @AppStorage(SettingsKeys.homeTourPending) private var homeTourPending = false
    @State private var tourStep: Int?

    private static func initialTab() -> Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let flagIndex = args.firstIndex(of: "--start-tab"),
           flagIndex + 1 < args.count,
           let tab = Int(args[flagIndex + 1]) {
            return min(max(tab, 0), 3)
        }
        #endif
        return TabRouter.homeTab  // 打開就是安心頁：3 秒讀完「家人都平安嗎」
    }

    var body: some View {
        TabView(selection: Bindable(router).selection) {
            HomeStatusView(myName: myName)
                .tabItem { Label("安心", systemImage: "checkmark.shield.fill") }
                .tag(TabRouter.homeTab)
            SafetyMapView()
                .tabItem { Label("安全地圖", systemImage: "map.fill") }
                .tag(TabRouter.mapTab)
            FamilyHubView(myName: myName)
                .tabItem { Label("家人", systemImage: "person.2.fill") }
                .tag(TabRouter.familyTab)
        }
        .tint(HCColor.brand)
        .environment(router)
        // 設定改為全域 sheet：任何頁面（含家人頁的「查看 Apple 帳號狀態」）都能打開
        .sheet(isPresented: Bindable(router).showSettings) { SettingsView() }
        // 功能導覽遮罩：anchor 由安心頁各元件向上匯報，遮罩蓋整個畫面（含分頁列）
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if tourStep != nil {
                FeatureTourView(anchors: anchors, stepIndex: $tourStep)
            }
        }
        // 旗標一變 true 就開始導覽（首次進入或設定頁重看都走這裡）
        .task(id: homeTourPending) {
            // DEBUG：--tour 強制啟動導覽，供自動化截圖與 Demo 排練
            var forceTour = false
            #if DEBUG
            forceTour = ProcessInfo.processInfo.arguments.contains("--tour")
            #endif
            guard homeTourPending || forceTour else { return }
            try? await Task.sleep(for: .milliseconds(900)) // 等安心頁站穩再上黑幕
            router.selection = TabRouter.homeTab
            tourStep = 0
            homeTourPending = false
        }
        // App 每次回到前景重跑資料管線（含每日摘要重算）。
        // 原型限制：沒有背景更新，用前景時機讓資料與摘要盡量新鮮。
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await EventPipeline.refresh(context: context) }
        }
        // Widget deep link 路由（經 scene delegate 轉交，.onOpenURL 在自訂 delegate 下收不到）
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveDeepLink)) { note in
            if let url = note.object as? URL { route(url) }
        }
        .onAppear {
            // 冷啟動由 URL 拉起的情況
            if let url = DeepLinkStore.pending {
                DeepLinkStore.pending = nil
                route(url)
            }
        }
    }

    /// havencircle://alerts｜map｜family｜refresh
    /// 分頁減編後 alerts/refresh 改為「安心頁＋push 提醒中心」，widget 與通知不用改 URL
    private func route(_ url: URL) {
        guard url.scheme == "havencircle" else { return }
        switch url.host {
        case "alerts": router.openHome(.events)
        case "map": router.selection = TabRouter.mapTab
        case "family": router.selection = TabRouter.familyTab
        case "refresh":
            router.openHome(.events)
            Task { await EventPipeline.refresh(context: context) }
        default: break
        }
    }
}

#Preview {
    AppTabs()
        .modelContainer(PreviewSupport.container())
        .environment(FamilySyncService())
}
