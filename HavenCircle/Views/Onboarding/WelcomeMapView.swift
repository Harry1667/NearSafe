import SwiftUI
import MapKit

/// 新手著陸頁：打開 App 先看到一片乾淨的地圖，鏡頭定位在台北車站。
///
/// 設計原則（呼應「會告知、不偷偷」）：**不在啟動時偷偷要定位**，
/// 而是等使用者點一下畫面、明白「為什麼要位置」之後才索取權限。
/// 使用者若拒絕，退回台北車站繼續（不卡死），並用溫和說明引導到「設定」開啟。
///
/// 這是重做新手流程的第一步；`onContinue` 交由上層（ContentView）決定下一步去哪。
struct WelcomeMapView: View {
    /// 著陸步驟處理完（定位已授權，或使用者選擇先略過）後呼叫，帶往下一步。
    var onContinue: () -> Void = {}

    /// 台北車站座標（新手預設鏡頭中心；專案原本沒有這組座標，需自訂）。
    private static let taipeiStation = CLLocationCoordinate2D(latitude: 25.0478, longitude: 121.5170)

    private static var stationRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: taipeiStation,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
    }

    @State private var cameraPosition: MapCameraPosition = .region(WelcomeMapView.stationRegion)
    /// 使用者是否已點畫面觸發過定位請求（避免重複彈窗、也用來切換文案階段）。
    @State private var didAskLocation = false
    /// 漏斗事件只記一次（onAppear 可能因視圖重掛重複觸發）
    @State private var didTrackShown = false
    /// 授權後的自動前進只排程一次（onAppear 與 onChange 都會呼叫 focusOnUser）
    @State private var didScheduleContinue = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 著陸頁目前所處的引導階段，決定底部卡片與提示的內容。
    private enum Stage {
        case intro        // 尚未點畫面：邀請使用者點一下
        case granted      // 已授權定位：鏡頭移到使用者、可開始使用
        case denied       // 使用者拒絕定位：溫和說明並引導去設定
    }

    private var stage: Stage {
        guard didAskLocation else { return .intro }
        switch LocationService.shared.authorization {
        case .authorizedWhenInUse, .authorizedAlways:
            return .granted
        case .denied, .restricted:
            return .denied
        default:
            return .intro // 對話框顯示中（.notDetermined）仍停在邀請階段
        }
    }

    var body: some View {
        ZStack {
            cleanMap
            // 卡片置中（與帶領卡一致）；iPad 上限制卡片寬度，ZStack 預設 .center 對齊會自動置中
            bottomCard
                .frame(maxWidth: 440)
                .padding(.horizontal, 20)
        }
        .ignoresSafeArea(edges: .top)
        // 進頁時若系統早已授權（例如重置流程的老使用者），直接把鏡頭帶到使用者位置
        .onAppear {
            // 漏斗事件：著陸卡出現（onAppear 可能重複觸發，只記第一次）
            if !didTrackShown {
                didTrackShown = true
                Analytics.track("onboarding_landing_shown")
            }
            if LocationService.shared.isAuthorized {
                didAskLocation = true
                focusOnUser()
            }
        }
        // 授權狀態一改變就反應：允許→移鏡頭；拒絕→由 stage 切換到說明卡。
        // 漏斗事件：只在「從未決定→有結果」的轉變記錄（老用戶重進不會誤記）
        .onChange(of: LocationService.shared.authorization) { oldValue, newValue in
            if oldValue == .notDetermined {
                switch newValue {
                case .authorizedWhenInUse, .authorizedAlways:
                    Analytics.track("onboarding_location_granted")
                case .denied, .restricted:
                    Analytics.track("onboarding_location_denied")
                default: break
                }
            }
            if LocationService.shared.isAuthorized { focusOnUser() }
        }
    }

    // MARK: - 乾淨地圖

    private var cleanMap: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            // 授權後才顯示使用者藍點；未授權時保持純淨、不透露任何位置
            if LocationService.shared.isAuthorized {
                UserAnnotation()
            }
        }
        // 降噪：關掉 POI、交通、立體感，讓畫面乾淨直白
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .ignoresSafeArea()
        // 點畫面任何一處＝索要定位（僅在還沒問過時觸發）
        .contentShape(Rectangle())
        .onTapGesture { askLocationOnce() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("點一下地圖開始")
    }

    // MARK: - 底部卡片（隨階段換內容）

    @ViewBuilder
    private var bottomCard: some View {
        switch stage {
        case .intro:   introCard
        case .granted: grantedCard
        case .denied:  deniedCard
        }
    }

    /// 邀請階段：一句話＋一行副標（2026-07-23 模擬走查：刪光開場白判定「剛好」，
    /// 唯一代價是少數人不知 App 幹嘛——一行副標封頂，不回退成兩段文字）
    private var introCard: some View {
        VStack(spacing: 12) {
            tapHint
            Text("點一下地圖，找到你家")
                .font(.title3.weight(.bold))
            Text("災害靠近時，全家都知道")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        // 讓整張卡也能點（等同點地圖）
        .contentShape(Rectangle())
        .onTapGesture { askLocationOnce() }
    }

    /// 已授權：只給「✓ 找到你了」的輕確認，**不再要求按「開始使用」**——
    /// 鏡頭飛到你家本身就是回饋，多一次點擊是純拖延（模擬走查修正：省一步）。
    /// 鏡頭動畫走完後自動進下一步（見 focusOnUser 的排程）。
    private var grantedCard: some View {
        Label("找到你了", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(HCColor.brand)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            .transition(.opacity)
    }

    /// 拒絕定位：溫和說明＋引導去設定；同時保留「先略過」的出路
    private var deniedCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("沒有定位也沒關係")
                    .font(.title3.weight(.bold))
                Text("安心圈需要你的位置，才能在災害發生時\n讓家人找到你。你可以隨時到「設定」開啟。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                openSystemSettings()
            } label: {
                Text("前往設定開啟定位")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(HCColor.brand)

            Button("先看看，稍後再開", action: onContinue)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: HCRadius.card, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }

    /// 邀請階段的點擊提示：一個輕輕呼吸的手勢圖示（尊重減少動態設定）。
    private var tapHint: some View {
        Image(systemName: "hand.tap.fill")
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(HCColor.brand)
            .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
            .accessibilityHidden(true)
    }

    // MARK: - 行為

    /// 點畫面索要定位——只在還沒問過時觸發，避免重複彈窗。
    private func askLocationOnce() {
        guard !didAskLocation else { return }
        didAskLocation = true
        Analytics.track("onboarding_landing_tapped")
        LocationService.shared.requestPermissionIfNeeded()
    }

    /// 把鏡頭平滑移到使用者的實際位置（拿不到時退回台北車站），
    /// 並在鏡頭動畫走完後**自動**進下一步——授權後不再要求按「開始使用」，
    /// 「地圖飛到你家」就是確認本身（2026-07-23 模擬走查：省一次點擊）。
    private func focusOnUser() {
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .userLocation(fallback: .region(WelcomeMapView.stationRegion))
        }
        guard !didScheduleContinue else { return }
        didScheduleContinue = true
        // 1.6 秒＝鏡頭飛行 0.8s＋讓「✓ 找到你了」被看見的短暫停留
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            onContinue()
        }
    }

    /// 開啟本 App 的系統設定頁（拒絕後唯一能重新授權的入口）。
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#if DEBUG
#Preview {
    WelcomeMapView()
}
#endif
