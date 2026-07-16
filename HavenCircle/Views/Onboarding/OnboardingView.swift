import SwiftUI
import SwiftData
import MapKit
import os

/// 首次設定：五步分頁精靈（歡迎 → 名稱 → 生活圈 → 通知 → 完成）。
/// 設計原則：一步只問一件事、先講理由再要權限、家人邀請可略過（軟門檻）。
struct OnboardingView: View {
    /// 重播模式（從設定頁「重看新手教學」進入）：只導覽，不建立任何資料
    var isReplay = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.profileDisplayName) private var profileName = ""
    @AppStorage(SettingsKeys.onboardingCompleted) private var onboardingCompleted = false

    @State private var step: Step = .welcome
    @State private var name = ""
    @State private var placeName = "住家"
    @State private var address = "台北市南港區"
    @State private var radius = 1000
    @State private var found: MKMapItem?
    @State private var searchFailed = false
    @State private var showFallbackConfirmation = false
    @State private var notificationGranted: Bool?

    enum Step: Int, CaseIterable {
        case welcome, signIn, name, circle, notification, done
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                TabView(selection: $step) {
                    welcomePage.tag(Step.welcome)
                    signInPage.tag(Step.signIn)
                    namePage.tag(Step.name)
                    circlePage.tag(Step.circle)
                    notificationPage.tag(Step.notification)
                    donePage.tag(Step.done)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // 只允許用按鈕前進：滑動跳步會略過必要輸入
                .animation(.easeInOut, value: step)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .welcome && step != .done {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("返回", systemImage: "chevron.left") {
                            withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                        }
                    }
                }
                // 登入步驟右上角提供「跳過」（軟門檻：不登入也能用完整警報功能）
                if step == .signIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("跳過") { withAnimation { step = .name } }
                    }
                }
                if isReplay {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("關閉") { dismiss() }
                    }
                }
            }
            .confirmationDialog("尚未確認生活圈位置", isPresented: $showFallbackConfirmation) {
                Button("使用台北市南港區預設位置") { advanceFromCircle() }
                Button("返回確認地址", role: .cancel) {}
            } message: {
                Text("建議先用 Apple Maps 搜尋並確認位置，避免提醒範圍設在錯誤地點。")
            }
        }
    }

    // MARK: - 進度條

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? HCColor.brand : Color.secondary.opacity(0.2))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .accessibilityLabel("設定進度：第 \(step.rawValue + 1) 步，共 \(Step.allCases.count) 步")
    }

    // MARK: - 第 1 步：歡迎

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()
            // 品牌漸層圓底座＋白色盾牌：歡迎頁的第一眼要像產品 logo，不是浮著的系統圖示
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [HCColor.brand.opacity(0.8), HCColor.brand],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 108, height: 108)
                    .shadow(color: HCColor.brand.opacity(0.3), radius: 16, y: 8)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            Text("安心圈")
                .font(.system(.largeTitle, design: .rounded).bold())
            Text("替家人留意住家與生活範圍的安全動態")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // 三張價值卡統一品牌色：歡迎頁只留一個主色，靠圖示與文字區分——
            // 綠橘藍各自搶焦會讓第一印象像「通用範例」而不是有品牌的產品
            VStack(spacing: 12) {
                valueCard("checkmark.seal.fill", HCColor.brand,
                          "官方示警來源", "災害警報來自 NCDR 民生示警等政府公開資料")
                valueCard("mappin.and.ellipse", HCColor.brand,
                          "只提醒重要的", "事件落在家人生活圈內且可信度足夠，才會通知你")
                valueCard("person.2.fill", HCColor.brand,
                          "家人互報平安", "一鍵回報「我平安」，家人立刻知道")
            }
            .padding(.horizontal, 24)

            Spacer()
            Text("所有生活圈與事件資料只儲存在這支手機；不會追蹤任何人的即時位置。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            primaryButton("開始設定") { withAnimation { step = .signIn } }
        }
        .padding(.bottom, 24)
    }

    // MARK: - 第 2 步：Apple 登入（右上角可跳過）

    private var signInPage: some View {
        AppleSignInPage(onSignedIn: {
            // 登入成功：帶入的名稱直接預填下一步，少打一次字
            if name.isEmpty { name = profileName }
            withAnimation { step = .name }
        })
    }

    private func valueCard(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 第 2 步：名稱

    private var namePage: some View {
        VStack(spacing: 16) {
            Spacer()
            stepHeader("怎麼稱呼你？", "這個名稱會顯示在家人的安否回報裡，例如「媽媽 回報了平安」。")
            TextField("你的名稱", text: $name)
                .font(.title2)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 48)
            Spacer()
            primaryButton("下一步", disabled: !isReplay && name.trimmingCharacters(in: .whitespaces).isEmpty) {
                withAnimation { step = .circle }
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - 第 3 步：第一個生活圈

    private var circlePage: some View {
        VStack(spacing: 0) {
            stepHeader("設定第一個生活圈", "生活圈是你想守護的範圍，例如住家或長輩家。只有圈內的事件才會提醒。")
                .padding(.bottom, 8)
            Form {
                Section {
                    TextField("地點名稱（例如：住家）", text: $placeName)
                    TextField("城市或地址", text: $address)
                    Button("使用 Apple Maps 搜尋位置", systemImage: "magnifyingglass") {
                        Task { await search() }
                    }
                    if let found {
                        Label("找到：\(found.name ?? address)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(HCColor.safe)
                    } else if searchFailed {
                        Text("找不到這個地點，會先用台北市南港區的預設位置，之後可在「家人」頁修改。")
                            .font(.caption)
                            .foregroundStyle(HCColor.attention)
                    }
                    Stepper("提醒半徑：\(radius) 公尺", value: $radius, in: 300...3000, step: 100)
                } footer: {
                    // 服務範圍誠實告知（行政區已擴至全國 375 鄉鎮市區，文案同步更新）
                    Text("颱風、豪雨等區域型警報依行政區自動比對，已支援全國鄉鎮市區；地址判斷不到行政區時，可稍後在生活圈編輯裡手動指定。")
                }
            }
            .scrollContentBackground(.hidden)
            primaryButton("下一步") {
                if found == nil && !isReplay {
                    showFallbackConfirmation = true
                } else {
                    advanceFromCircle()
                }
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - 第 4 步：通知權限

    private var notificationPage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(HCColor.brand)
            stepHeader("打開通知，關鍵時刻才收得到",
                       "只有「落在生活圈內、且可信度足夠」的事件才會推播；確認中的線索只在 App 內顯示，不會吵你。")
            if notificationGranted == true {
                Label("通知已允許", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(HCColor.safe)
            } else if notificationGranted == false {
                Text("你選擇了不允許。之後可以在設定 App 裡隨時打開。")
                    .font(.caption)
                    .foregroundStyle(HCColor.attention)
            }
            Spacer()
            if notificationGranted == nil {
                primaryButton("允許通知") {
                    Task {
                        notificationGranted = await NotificationScheduler.requestPermission()
                        withAnimation { step = .done }
                    }
                }
                Button("稍後再說") { withAnimation { step = .done } }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                primaryButton("下一步") { withAnimation { step = .done } }
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - 第 5 步：完成

    private var donePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(HCColor.safe)
            stepHeader("設定完成！", "地圖上已經可以看到你的生活圈與最新的安全動態。")
            valueCard("person.crop.circle.badge.plus", HCColor.brand,
                      "下一步：邀請家人（可略過）",
                      "到「家人」分頁邀請家人加入，支援 QR code 或 8 位邀請碼；需要登入 iCloud。")
                .padding(.horizontal, 24)
            Spacer()
            primaryButton(isReplay ? "完成" : "開始使用") { finishSetup() }
        }
        .padding(.bottom, 24)
    }

    // MARK: - 共用元件與邏輯

    private func stepHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private func primaryButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled)
        .padding(.horizontal, 24)
    }

    private func advanceFromCircle() {
        withAnimation { step = .notification }
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        do {
            found = try await MKLocalSearch(request: request).start().mapItems.first
            searchFailed = (found == nil)
        } catch {
            AppLog.data.error("首次設定地點搜尋失敗：\(error.localizedDescription)")
            found = nil
            searchFailed = true
        }
    }

    private func finishSetup() {
        let displayName = name.trimmingCharacters(in: .whitespaces)
        // 重播模式只是導覽：不建立資料、不動旗標，關掉就好
        if isReplay {
            dismiss()
            return
        }
        let me = LocalFamilyMember(name: displayName.isEmpty ? "我" : displayName, relationship: "擁有者")
        context.insert(me)
        // 有搜尋結果用實際座標；沒有就退回南港區預設位置
        let coordinate = found?.location.coordinate ?? .init(latitude: 25.0525, longitude: 121.6072)
        let circle = LocalLifeCircle(
            name: placeName.isEmpty ? "住家" : placeName,
            encryptedAddress: found?.name ?? address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: radius,
            alertTypes: EventCategory.defaultSelection,
            member: me
        )
        circle.district = Self.guessDistrict(from: "\(found?.name ?? "") \(address)")
        context.insert(circle)
        context.saveReporting()
        // 名稱同步進個人資訊（安否回報署名用），使用者不必到設定頁再填一次
        if !displayName.isEmpty { profileName = displayName }
        // 完成旗標與家人資料脫鉤：之後就算刪光家人資料也不會被打回新手流程
        onboardingCompleted = true
        // 種下守護圈開場動效旗標：首次進地圖時演「鏡頭飛向生活圈」的確認儀式
        UserDefaults.standard.set(true, forKey: SettingsKeys.guardianIntroPending)
    }

    /// 從地址文字比對全國鄉鎮市區（供區域型警報使用）；找不到就標「未指定」
    static func guessDistrict(from text: String) -> String {
        Districts.all.dropFirst().first { text.contains($0) } ?? Districts.unspecified
    }
}

#Preview {
    OnboardingView()
        .modelContainer(PreviewSupport.container())
}
