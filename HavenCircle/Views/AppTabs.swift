import SwiftUI
import SwiftData

struct AppTabs: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    // 功能導覽：黑幕聚光燈跨分頁介紹主要功能（nil＝未進行）
    @AppStorage(SettingsKeys.homeTourPending) private var homeTourPending = false
    @State private var tourStep: Int?
    /// Onboarding 完成後先讓地圖的守護圈確認儀式播完，再開始功能導覽。
    @State private var shouldConfirmCircleOnMap = UserDefaults.standard.bool(forKey: SettingsKeys.guardianIntroPending)
    /// 守護圈確認動效播放中（等待期間顯示「跳過」；設回 false 即中止等待）
    @State private var isPlayingGuardianIntro = false

    private static func initialTab() -> Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let flagIndex = args.firstIndex(of: "--start-tab"),
           flagIndex + 1 < args.count,
           let tab = Int(args[flagIndex + 1]) {
            return min(max(tab, 0), 3)
        }
        #endif
        if UserDefaults.standard.bool(forKey: SettingsKeys.guardianIntroPending) {
            return TabRouter.mapTab
        }
        return TabRouter.homeTab  // 打開就是安心頁：3 秒讀完「家人都平安嗎」
    }

    var body: some View {
        ZStack {
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
            // Coach marks 顯示時，VoiceOver 只應讀到導覽卡，不可穿透到背景按鈕。
            .accessibilityHidden(tourStep != nil)
            .allowsHitTesting(tourStep == nil)

            // 守護圈確認動效期間給「跳過」：儀式感只該演給想看的人
            if isPlayingGuardianIntro {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button("跳過") { isPlayingGuardianIntro = false }
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .accessibilityLabel("跳過地圖確認動畫")
                    }
                    .padding(.trailing, HCSpacing.x4)
                    .padding(.bottom, 64) // 避開分頁列
                }
            }
        }
        // 功能導覽遮罩：主要內容使用實際 anchor，只有 TabView 私有結構才做安全區域降級推算
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if tourStep != nil {
                FeatureTourView(
                    anchors: anchors,
                    stepIndex: $tourStep,
                    selectedTab: Bindable(router).selection
                )
            }
        }
        // 旗標一變 true 就從安心頁開始跨分頁導覽（首次進入或設定頁重看都走這裡）
        .task(id: homeTourPending) {
            // DEBUG：--tour 強制啟動導覽，供自動化截圖與 Demo 排練
            var forceTour = false
            #if DEBUG
            forceTour = ProcessInfo.processInfo.arguments.contains("--tour")
            #endif
            guard homeTourPending || forceTour else { return }
            if shouldConfirmCircleOnMap {
                router.selection = TabRouter.mapTab
                // 等地圖框住剛建立的圈並顯示名稱／半徑；Reduce Motion 時只需短暫停留。
                // 分段睡：使用者按「跳過」（isPlayingGuardianIntro 設回 false）就提前結束等待。
                isPlayingGuardianIntro = true
                let totalMilliseconds = reduceMotion ? 900 : 3_100
                var elapsed = 0
                while elapsed < totalMilliseconds && isPlayingGuardianIntro {
                    try? await Task.sleep(for: .milliseconds(100))
                    elapsed += 100
                }
                isPlayingGuardianIntro = false
                shouldConfirmCircleOnMap = false
            } else {
                try? await Task.sleep(for: .milliseconds(900))
            }
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

    /// havencircle://alerts[?event=<eventKey>]｜map｜family｜refresh
    /// 分頁減編後 alerts/refresh 改為「安心頁＋push 提醒中心」，widget 與通知不用改 URL；
    /// 通知另帶 event 參數時，提醒中心會直接打開那一則的詳情
    private func route(_ url: URL) {
        guard url.scheme == "havencircle" else { return }
        switch url.host {
        case "alerts":
            router.pendingEventKey = eventKey(from: url)
            router.openHome(.events)
        case "map": router.selection = TabRouter.mapTab
        case "family": router.selection = TabRouter.familyTab
        case "refresh":
            router.openHome(.events)
            Task { await EventPipeline.refresh(context: context) }
        default: break
        }
    }

    private func eventKey(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "event" }?
            .value
    }
}

#if DEBUG
#Preview {
    AppTabs()
        .modelContainer(PreviewSupport.container())
        .environment(FamilySyncService())
}
#endif
